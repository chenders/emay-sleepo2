"""Per-minute downsampler for the ~1 Hz EMAY stream."""

from __future__ import annotations

import threading
from datetime import datetime
from typing import List, Optional

from .types import MinuteSample, Reading


def _start_of_minute(dt: datetime) -> datetime:
    return dt.replace(second=0, microsecond=0)


class LiveDownsampler:
    """Buffers ~1 Hz EMAY readings into per-minute mean samples.

    Thread-safe. Use in a BLE callback to accumulate readings; finalized
    minutes are returned from add().
    """

    def __init__(self, minimum_samples_per_minute: int = 2):
        self.minimum_samples_per_minute = minimum_samples_per_minute
        self._lock = threading.Lock()
        self._spo2_values: List[float] = []
        self._pulse_values: List[float] = []
        self._current_minute: Optional[datetime] = None

    def add(self, reading: Reading) -> List[MinuteSample]:
        """Feed a new reading into the current minute bucket.

        Returns any finalized MinuteSamples (typically 0 or 2 per call).
        """
        with self._lock:
            minute = _start_of_minute(reading.timestamp)
            flushed: List[MinuteSample] = []

            if self._current_minute is not None and minute != self._current_minute:
                flushed = self._finalize_locked()

            self._current_minute = minute
            if reading.spo2 is not None:
                self._spo2_values.append(float(reading.spo2))
            if reading.pulse is not None:
                self._pulse_values.append(float(reading.pulse))
            return flushed

    def flush(self) -> List[MinuteSample]:
        """Finalize and return the current partial bucket."""
        with self._lock:
            return self._finalize_locked()

    def _finalize_locked(self) -> List[MinuteSample]:
        if self._current_minute is None:
            return []
        minute = self._current_minute
        spo2_vals = self._spo2_values
        pulse_vals = self._pulse_values
        self._spo2_values = []
        self._pulse_values = []
        self._current_minute = None

        samples: List[MinuteSample] = []
        if len(spo2_vals) >= self.minimum_samples_per_minute:
            mean = sum(spo2_vals) / len(spo2_vals)
            samples.append(MinuteSample(
                minute_start=minute,
                metric_type="SpO2",
                value=mean / 100.0,
                unit_string="%"
            ))
        if len(pulse_vals) >= self.minimum_samples_per_minute:
            mean = sum(pulse_vals) / len(pulse_vals)
            samples.append(MinuteSample(
                minute_start=minute,
                metric_type="PulseRate",
                value=mean,
                unit_string="count/min"
            ))
        return samples
