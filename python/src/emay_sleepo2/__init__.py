"""EMAY SleepO2 BLE SDK — Python."""

from .types import Reading, MinuteSample, Status
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
from .csv_parser import parse_csv, parse_csv_file

# EMAYClient requires bleak (pip install bleak). Import it explicitly
# to avoid load failures when only CSV parsing is needed.
try:
    from .client import EMAYClient
except ImportError:
    EMAYClient = None  # type: ignore

__all__ = [
    "Reading",
    "MinuteSample",
    "Status",
    "LiveDownsampler",
    "parse_csv",
    "parse_csv_file",
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
