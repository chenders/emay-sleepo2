"""EMAY SleepO2 BLE SDK — Python."""

from .types import Reading, MinuteSample, Status, FailureReason
from .protocol import (
    parse_reading,
    checksum,
    command,
    HELLO,
    DEVICE_STATE,
    START_REALTIME,
    STOP_REALTIME,
    GET_BATTERY,
    HEARTBEAT,
    SERVICE_UUID,
    WRITE_UUID,
    NOTIFY_UUID,
)
from .downsampler import LiveDownsampler

# EMAYClient requires bleak (pip install bleak). Import it explicitly
# to avoid load failures when only the protocol layer is needed.
try:
    from .client import EMAYClient
except ImportError:
    EMAYClient = None  # type: ignore

__all__ = [
    "Reading",
    "MinuteSample",
    "Status",
    "FailureReason",
    "LiveDownsampler",
    "parse_reading",
    "checksum",
    "command",
    "HELLO",
    "DEVICE_STATE",
    "START_REALTIME",
    "STOP_REALTIME",
    "GET_BATTERY",
    "HEARTBEAT",
    "SERVICE_UUID",
    "WRITE_UUID",
    "NOTIFY_UUID",
]
if EMAYClient is not None:
    __all__.append("EMAYClient")
