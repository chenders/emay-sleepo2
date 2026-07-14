"""Data types for the EMAY SleepO2 SDK."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum, auto
from typing import Optional


@dataclass(frozen=True, slots=True)
class Reading:
    """A single physiological reading from the EMAY SleepO2.

    Both spo2 and pulse are optional — the device can report a valid
    pulse rate without SpO₂ (finger partially on) or vice versa. None
    means the sensor couldn't acquire that measurement, NOT zero
    saturation or asystole.
    """

    spo2: Optional[int]  # Oxygen saturation percent (0–100)
    pulse: Optional[int]  # Pulse rate in bpm
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    def __repr__(self) -> str:
        s = f"{self.spo2}%" if self.spo2 is not None else "—"
        p = f"{self.pulse}" if self.pulse is not None else "—"
        return f"Reading(spo2={s}, pulse={p})"


@dataclass(frozen=True, slots=True)
class MinuteSample:
    """A finalized per-minute mean sample."""

    minute_start: datetime
    metric_type: str  # "SpO2" or "PulseRate"
    value: float
    unit_string: str  # "%" or "count/min"


class Status(Enum):
    """Observable connection/streaming state."""

    IDLE = auto()
    SCANNING = auto()
    CONNECTING = auto()
    STREAMING = auto()
    BLUETOOTH_OFF = auto()
    BLUETOOTH_UNAUTHORIZED = auto()
    BLUETOOTH_UNSUPPORTED = auto()
    FAILED = auto()

    @property
    def is_active(self) -> bool:
        """Whether a session is actively in progress."""
        return self in (Status.SCANNING, Status.CONNECTING, Status.STREAMING)


@dataclass(frozen=True, slots=True)
class StatusEvent:
    """A status change event from the client."""

    status: Status
    message: str = ""
