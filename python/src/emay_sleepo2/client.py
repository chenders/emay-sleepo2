"""Bleak-based client for the EMAY SleepO2 pulse oximeter."""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Callable, List, Optional

from bleak import BleakClient, BleakScanner
from bleak.backends.device import BLEDevice
from bleak.backends.characteristic import BleakGATTCharacteristic

from .protocol import (
    SERVICE_UUID,
    WRITE_UUID,
    NOTIFY_UUID,
    NAME_PREFIX,
    HEARTBEAT,
    START_SEQUENCE,
    STOP_REALTIME,
    parse_reading,
)
from .types import Reading, Status, MinuteSample, FailureReason
from .downsampler import LiveDownsampler

logger = logging.getLogger(__name__)

# Teardown safety timeouts (seconds). Even after awaiting the heartbeat, a
# wedged backend write or disconnect must never hang stop() forever. Normal
# write-response round trips are well under a second and disconnects are near
# instant; these ceilings only trip when something is genuinely stuck.
STOP_WRITE_TIMEOUT: float = 2.0
DISCONNECT_TIMEOUT: float = 5.0


class EMAYClient:
    """Async BLE client for the EMAY SleepO2.

    Example::

        emay = EMAYClient()
        emay.on_reading = lambda r: print(f"SpO2: {r.spo2}%  HR: {r.pulse}")
        await emay.start()
        await asyncio.sleep(30)
        await emay.stop()
    """

    def __init__(
        self,
        heartbeat_interval: float = 1.5,
        stale_timeout: float = 4.0,
        auto_reconnect: bool = True,
    ):
        self.heartbeat_interval = heartbeat_interval
        self.stale_timeout = stale_timeout
        self.auto_reconnect = auto_reconnect

        # Callbacks
        self.on_reading: Optional[Callable[[Reading], None]] = None
        self.on_status_change: Optional[Callable[[Status], None]] = None
        self.on_minute_samples: Optional[Callable[[List[MinuteSample]], None]] = None

        # State
        self._status: Status = Status.IDLE
        self._failure_reason: FailureReason = FailureReason.NONE
        self._latest_reading: Optional[Reading] = None
        self._last_reading_at: Optional[datetime] = None
        self._client: Optional[BleakClient] = None
        self._device: Optional[BLEDevice] = None
        self._notify_char: Optional[BleakGATTCharacteristic] = None
        self._write_char: Optional[BleakGATTCharacteristic] = None
        self._heartbeat_task: Optional[asyncio.Task] = None
        self._want_scan = False
        self._downsampler = LiveDownsampler()
        self._known_address: Optional[str] = None

    @property
    def status(self) -> Status:
        return self._status

    @status.setter
    def status(self, value: Status) -> None:
        if self._status != value:
            self._status = value
            if self.on_status_change:
                self.on_status_change(value)

    @property
    def latest_reading(self) -> Optional[Reading]:
        return self._latest_reading

    @property
    def failure_reason(self) -> FailureReason:
        """Why the last session failed. Meaningful only when status is FAILED.

        ``FailureReason.NOT_FOUND`` means the device was never discovered — off,
        out of range, or connected to another app (indistinguishable in-band).
        ``FailureReason.CONNECTION_FAILED`` means it was found but connecting or
        GATT setup failed. See ``FailureReason.message`` for user-facing text.
        """
        return self._failure_reason

    @property
    def is_streaming(self) -> bool:
        return self._status == Status.STREAMING

    async def start(self, address: Optional[str] = None) -> None:
        """Start monitoring for the oximeter."""
        if self._status.is_active:
            return
        self._failure_reason = FailureReason.NONE
        self._want_scan = True
        self._known_address = address or self._known_address
        self.status = Status.SCANNING
        await self._begin_monitoring()

    async def stop(self) -> None:
        """Stop streaming and disconnect.

        Ordering matters: the heartbeat task is cancelled *and awaited* before
        any teardown write. A heartbeat write left in-flight on the write
        characteristic otherwise races STOP_REALTIME and can orphan its
        write-response, wedging stop() and holding the BLE link open (the device
        "stays connected"). The teardown write and disconnect are additionally
        bounded by timeouts so a wedged backend can never hang stop() forever.
        """
        self._want_scan = False
        if self._heartbeat_task:
            self._heartbeat_task.cancel()
            try:
                await self._heartbeat_task
            except (asyncio.CancelledError, Exception):
                pass
            self._heartbeat_task = None
        # Keep a local handle: disconnect() fires _on_disconnect, which nulls
        # out self._client before we can inspect the result below.
        client = self._client
        if client is not None and client.is_connected and self._write_char:
            try:
                await asyncio.wait_for(
                    client.write_gatt_char(self._write_char, STOP_REALTIME, response=True),
                    timeout=STOP_WRITE_TIMEOUT,
                )
            except asyncio.TimeoutError:
                logger.warning("EMAY: STOP_REALTIME write timed out during stop(); tearing down anyway")
            except Exception as e:
                logger.warning("EMAY: STOP_REALTIME write failed during stop(): %r", e)
        if client is not None:
            try:
                await asyncio.wait_for(client.disconnect(), timeout=DISCONNECT_TIMEOUT)
            except asyncio.TimeoutError:
                logger.warning("EMAY: disconnect() timed out during stop(); resetting state anyway")
            except Exception as e:
                logger.warning("EMAY: disconnect() raised during stop(): %r", e)
            else:
                # A clean return does NOT guarantee the link dropped — on some
                # backends disconnect() is a no-op and the peripheral keeps
                # showing connected. Surface that case explicitly.
                if client.is_connected:
                    logger.warning(
                        "EMAY: disconnect() returned but the link is still up; the device may keep reporting connected"
                    )
                else:
                    logger.info("EMAY: disconnect() completed; link closed")
        self._reset_connection_state()
        self.status = Status.IDLE

    async def _begin_monitoring(self) -> None:
        if self._device:
            await self._connect_to(self._device)
            return
        if self._known_address:
            # Try to find the known device
            device = await BleakScanner.find_device_by_address(self._known_address)
            if device:
                await self._connect_to(device)
                return
        await self._scan()

    async def _scan(self) -> None:
        self.status = Status.SCANNING

        def _filter(device: BLEDevice, adv_data) -> bool:
            if SERVICE_UUID.lower() not in [s.lower() for s in adv_data.service_uuids or []]:
                return False
            name = adv_data.local_name or device.name or ""
            return not name or name.startswith(NAME_PREFIX)

        device = await BleakScanner.find_device_by_filter(_filter, timeout=10)
        if device is None:
            self._failure_reason = FailureReason.NOT_FOUND
            self.status = Status.FAILED
            return
        self._known_address = device.address
        await self._connect_to(device)

    async def _connect_to(self, device: BLEDevice) -> None:
        self._device = device
        self.status = Status.CONNECTING
        client = BleakClient(
            device,
            disconnected_callback=self._on_disconnect,
        )
        try:
            await client.connect()
        except Exception as e:
            self._failure_reason = FailureReason.CONNECTION_FAILED
            self.status = Status.FAILED
            logger.error(f"EMAY: connect failed: {e}")
            return
        self._client = client
        await self._start_streaming()

    async def _start_streaming(self) -> None:
        client = self._client
        assert client is not None
        # Discover and enable
        svc = client.services.get_service(SERVICE_UUID)
        if svc is None:
            self._failure_reason = FailureReason.CONNECTION_FAILED
            self.status = Status.FAILED
            logger.error("EMAY: service not found")
            return
        self._write_char = svc.get_characteristic(WRITE_UUID)
        self._notify_char = svc.get_characteristic(NOTIFY_UUID)
        if self._write_char is None or self._notify_char is None:
            self._failure_reason = FailureReason.CONNECTION_FAILED
            self.status = Status.FAILED
            logger.error("EMAY: characteristics not found")
            return

        await client.start_notify(self._notify_char, self._on_data)

        # Serialized start sequence
        for cmd in START_SEQUENCE:
            await client.write_gatt_char(self._write_char, cmd, response=True)
        self.status = Status.STREAMING
        self._start_heartbeat()

    def _on_data(self, char: BleakGATTCharacteristic, data: bytearray) -> None:
        reading = parse_reading(bytes(data))
        if reading is None:
            return
        self._latest_reading = reading
        self._last_reading_at = datetime.now(timezone.utc)
        if self.on_reading:
            self.on_reading(reading)

        minutes = self._downsampler.add(reading)
        if minutes and self.on_minute_samples:
            self.on_minute_samples(minutes)

    def _on_disconnect(self, client: BleakClient) -> None:
        was_failure = self._status == Status.FAILED
        is_transient = self._want_scan and not was_failure and self.auto_reconnect
        if not is_transient:
            _ = self._downsampler.flush()
        self._reset_connection_state()
        if is_transient:
            asyncio.ensure_future(self._begin_monitoring())
        elif not was_failure:
            self.status = Status.IDLE

    def _start_heartbeat(self) -> None:
        if self._heartbeat_task:
            self._heartbeat_task.cancel()
        self._heartbeat_task = asyncio.ensure_future(self._heartbeat_loop())

    async def _heartbeat_loop(self) -> None:
        while True:
            await asyncio.sleep(self.heartbeat_interval)
            if self._status != Status.STREAMING or self._client is None:
                return
            if self._write_char:
                try:
                    await self._client.write_gatt_char(self._write_char, HEARTBEAT, response=True)
                except Exception:
                    pass
            # Staleness watchdog
            if self._last_reading_at is not None:
                if (datetime.now(timezone.utc) - self._last_reading_at).total_seconds() > self.stale_timeout:
                    if self._latest_reading is not None:
                        self._latest_reading = None
                        self._downsampler.flush()

    def _reset_connection_state(self) -> None:
        if self._heartbeat_task:
            self._heartbeat_task.cancel()
            self._heartbeat_task = None
        self._client = None
        self._device = None
        self._write_char = None
        self._notify_char = None
        self._latest_reading = None
        self._last_reading_at = None


__all__ = ["EMAYClient"]
