"""Tests for EMAYClient status callbacks."""

import asyncio
import logging

import pytest

pytest.importorskip("bleak", reason="client tests need the ble extra")

from emay_sleepo2.client import EMAYClient  # noqa: E402
from emay_sleepo2.types import Status, FailureReason  # noqa: E402


def test_scan_failure_fires_failed_once(monkeypatch):
    async def no_device(*args, **kwargs):
        return None

    monkeypatch.setattr("emay_sleepo2.client.BleakScanner.find_device_by_filter", no_device)

    client = EMAYClient()
    statuses = []
    client.on_status_change = statuses.append

    asyncio.run(client.start())

    assert statuses == [Status.SCANNING, Status.FAILED]
    assert client.failure_reason == FailureReason.NOT_FOUND
    assert "connected to another app" in client.failure_reason.message


def test_connect_failure_fires_failed_once(monkeypatch):
    class FakeDevice:
        address = "AA:BB:CC:DD:EE:FF"
        name = "SleepO2 Test"

    async def found_device(*args, **kwargs):
        return FakeDevice()

    class FailingBleakClient:
        def __init__(self, device, disconnected_callback=None):
            pass

        async def connect(self):
            raise OSError("connect refused")

    monkeypatch.setattr("emay_sleepo2.client.BleakScanner.find_device_by_filter", found_device)
    monkeypatch.setattr("emay_sleepo2.client.BleakClient", FailingBleakClient)

    client = EMAYClient()
    statuses = []
    client.on_status_change = statuses.append

    asyncio.run(client.start())

    assert statuses == [Status.SCANNING, Status.CONNECTING, Status.FAILED]
    assert client.failure_reason == FailureReason.CONNECTION_FAILED


def test_failure_reason_defaults_none_and_resets(monkeypatch):
    """failure_reason is NONE initially and is cleared at the start of start()."""

    async def no_device(*args, **kwargs):
        return None

    monkeypatch.setattr("emay_sleepo2.client.BleakScanner.find_device_by_filter", no_device)

    client = EMAYClient()
    assert client.failure_reason == FailureReason.NONE  # default

    asyncio.run(client.start())
    assert client.failure_reason == FailureReason.NOT_FOUND  # set on failure

    # A fresh start() clears the stale reason before re-scanning.
    reasons_at_scanning = []

    def capture(status):
        if status == Status.SCANNING:
            reasons_at_scanning.append(client.failure_reason)

    client.on_status_change = capture
    asyncio.run(client.start())
    assert reasons_at_scanning == [FailureReason.NONE]


def test_stop_warns_when_link_stays_up(caplog):
    """A disconnect() that returns without dropping the link must not be silent.

    Mirrors the observed "device still shows connected after close" symptom:
    disconnect() completes cleanly yet is_connected stays True.
    """

    class LingeringClient:
        @property
        def is_connected(self):
            return True  # link never actually drops

        async def disconnect(self):
            pass  # returns cleanly, no exception, no effect

    client = EMAYClient()
    client._client = LingeringClient()

    with caplog.at_level(logging.WARNING, logger="emay_sleepo2.client"):
        asyncio.run(client.stop())

    assert any("still up" in r.message for r in caplog.records)
    assert client.status == Status.IDLE  # teardown still completes


def test_stop_logs_disconnect_exception(caplog):
    """An exception from disconnect() must be logged, not swallowed."""

    class RaisingClient:
        @property
        def is_connected(self):
            return True

        async def disconnect(self):
            raise OSError("peripheral busy")

    client = EMAYClient()
    client._client = RaisingClient()

    with caplog.at_level(logging.WARNING, logger="emay_sleepo2.client"):
        asyncio.run(client.stop())

    assert any("disconnect() raised" in r.message for r in caplog.records)
    assert client.status == Status.IDLE


def test_stop_completes_when_disconnect_hangs(caplog, monkeypatch):
    """The root symptom: a wedged disconnect() must not hang stop() forever.

    stop() must trip its timeout, log it, and still reach IDLE instead of
    blocking indefinitely (which held the BLE link open — the 'stayed
    connected' bug).
    """
    monkeypatch.setattr("emay_sleepo2.client.DISCONNECT_TIMEOUT", 0.1)

    class HangingClient:
        @property
        def is_connected(self):
            return True

        async def disconnect(self):
            await asyncio.sleep(3600)  # never returns

    client = EMAYClient()
    client._client = HangingClient()

    async def run():
        # Outer guard: if the fix regresses, fail fast instead of hanging CI.
        await asyncio.wait_for(client.stop(), timeout=2.0)

    with caplog.at_level(logging.WARNING, logger="emay_sleepo2.client"):
        asyncio.run(run())

    assert any("disconnect() timed out" in r.message for r in caplog.records)
    assert client.status == Status.IDLE


def test_stop_completes_when_stop_write_hangs(caplog, monkeypatch):
    """A wedged STOP_REALTIME write must time out and still let teardown finish.

    This is the exact call that hung on the real device; stop() must bound it,
    log the timeout, proceed to disconnect(), and reach IDLE.
    """
    monkeypatch.setattr("emay_sleepo2.client.STOP_WRITE_TIMEOUT", 0.1)

    class WedgedWriteClient:
        @property
        def is_connected(self):
            return True

        async def write_gatt_char(self, *args, **kwargs):
            await asyncio.sleep(3600)  # write-response never arrives

        async def disconnect(self):
            pass

    client = EMAYClient()
    client._client = WedgedWriteClient()
    client._write_char = object()  # truthy so the STOP_REALTIME path runs

    async def run():
        await asyncio.wait_for(client.stop(), timeout=2.0)

    with caplog.at_level(logging.WARNING, logger="emay_sleepo2.client"):
        asyncio.run(run())

    assert any("STOP_REALTIME write timed out" in r.message for r in caplog.records)
    assert client.status == Status.IDLE
