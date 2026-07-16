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


class FailureReason(Enum):
    """Best-effort reason the client entered :attr:`Status.FAILED`.

    Only meaningful while ``status == Status.FAILED``; otherwise it is
    :attr:`NONE`. Read it via ``EMAYClient.failure_reason``.

    Note on ``NOT_FOUND``: the SleepO2 is single-connection and stops
    advertising while connected to another central, so a device that is
    "connected to another app" is radio-indistinguishable from one that is off
    or out of range. We therefore cannot report a definitive "busy" — the
    message enumerates the possibilities honestly.
    """

    NONE = auto()
    NOT_FOUND = auto()
    CONNECTION_FAILED = auto()

    @property
    def message(self) -> str:
        """A human-readable explanation suitable for showing a user."""
        return {
            FailureReason.NONE: "",
            FailureReason.NOT_FOUND: (
                "Device not found — it may be off, out of range, or connected "
                "to another app (the SleepO2 allows only one connection at a time)."
            ),
            FailureReason.CONNECTION_FAILED: (
                "Found the device but the connection failed — it may have moved "
                "out of range or been taken by another app mid-connect."
            ),
        }[self]


@dataclass(frozen=True, slots=True)
class StatusEvent:
    """A status change event from the client."""

    status: Status
    message: str = ""
