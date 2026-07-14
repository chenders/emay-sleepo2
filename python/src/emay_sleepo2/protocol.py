"""Pure-protocol layer for the EMAY SleepO2 BLE protocol.

Contains no Bluetooth calls, no async, no platform dependencies. Each
language binding reimplements these functions with that language's
byte-manipulation idioms.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import List, Optional

from .types import Reading

# ---- BLE identifiers ----
SERVICE_UUID = "0000ff12-0000-1000-8000-00805f9b34fb"
WRITE_UUID = "0000ff01-0000-1000-8000-00805f9b34fb"
NOTIFY_UUID = "0000ff02-0000-1000-8000-00805f9b34fb"
NAME_PREFIX = "SleepO2"

# ---- Commands ----
HELLO: bytes = bytes([0x89, 0x09])
DEVICE_STATE: bytes = bytes([0x8E, 0x05, 0x13])
START_REALTIME: bytes = bytes([0x9B, 0x01, 0x1C])
STOP_REALTIME: bytes = bytes([0x9B, 0x7F, 0x1A])
GET_BATTERY: bytes = bytes([0x86, 0x06])
HEARTBEAT: bytes = bytes([0x9A, 0x1A])

START_SEQUENCE: List[bytes] = [HELLO, DEVICE_STATE, START_REALTIME, GET_BATTERY]

# ---- Data frame constants ----
FRAME_LENGTH: int = 8
FRAME_HEADER: bytes = bytes([0xEB, 0x01, 0x05])
FRAME_TRAILER: bytes = bytes([0x7F, 0x00])

# ---- Plausibility bounds ----
PULSE_MIN_BPM: int = 30
PULSE_MAX_BPM: int = 220
SPO2_MAX_PERCENT: int = 100
SPO2_MIN_PERCENT: int = 0

# ---- Sentinel values ----
_SENTINEL_VALUES = {0x00, 0xFF}


def checksum(payload: bytes) -> int:
    """Compute the EMAY checksum: sum(payload) & 0x7F.

    The 0x7F mask (NOT 0xFF) is crucial — 0xFF produces invalid
    checksums that the device silently ignores.
    """
    return sum(payload) & 0x7F


def command(payload: bytes) -> bytes:
    """Build a full command frame: payload + checksum."""
    return payload + bytes([checksum(payload)])


def parse_reading(raw: bytes) -> Optional[Reading]:
    """Attempt to parse an 8-byte raw frame from the BLE notify characteristic.

    Returns a Reading on success, or None if the frame
    fails any validation check. Both spo2 and pulse can individually be
    None when the sensor reports "no finger detected" for that metric.
    """
    if len(raw) != FRAME_LENGTH:
        return None
    if raw[0] != FRAME_HEADER[0] or raw[1] != FRAME_HEADER[1] or raw[2] != FRAME_HEADER[2]:
        return None
    if raw[5] != FRAME_TRAILER[0] or raw[6] != FRAME_TRAILER[1]:
        return None

    cks = sum(raw[:7]) & 0x7F
    if raw[7] != cks:
        return None

    raw_pr = raw[3]
    raw_spo2 = raw[4]

    pr: Optional[int] = None if raw_pr in _SENTINEL_VALUES else raw_pr
    spo2: Optional[int] = None if raw_spo2 in _SENTINEL_VALUES else raw_spo2

    # Application-level plausibility bounds
    if pr is not None and (pr < PULSE_MIN_BPM or pr > PULSE_MAX_BPM):
        return None
    if spo2 is not None and (spo2 < SPO2_MIN_PERCENT or spo2 > SPO2_MAX_PERCENT):
        return None

    return Reading(spo2=spo2, pulse=pr, timestamp=datetime.now(timezone.utc))
