"""EMAY SleepO2 BLE SDK — Python."""

from .downsampler import LiveDownsampler
from .protocol import (
    DEVICE_STATE,
    GET_BATTERY,
    HEARTBEAT,
    HELLO,
    NOTIFY_UUID,
    SERVICE_UUID,
    START_REALTIME,
    STOP_REALTIME,
    WRITE_UUID,
    checksum,
    command,
    parse_reading,
)
from .types import FailureReason, MinuteSample, Reading, Status

# EMAYClient requires bleak (pip install bleak). Import it explicitly
# to avoid load failures when only the protocol layer is needed.
try:
    from .client import EMAYClient
except ImportError:
    EMAYClient = None  # type: ignore

__all__ = [
    "DEVICE_STATE",
    "GET_BATTERY",
    "HEARTBEAT",
    "HELLO",
    "NOTIFY_UUID",
    "SERVICE_UUID",
    "START_REALTIME",
    "STOP_REALTIME",
    "WRITE_UUID",
    "FailureReason",
    "LiveDownsampler",
    "MinuteSample",
    "Reading",
    "Status",
    "checksum",
    "command",
    "parse_reading",
]
if EMAYClient is not None:
    __all__.append("EMAYClient")
