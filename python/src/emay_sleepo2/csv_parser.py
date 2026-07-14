"""CSV parser for EMAY SleepO2 export files.

The device's companion app exports sleep sessions as CSV with columns:
Date,Time,SpO2(%),PR(bpm). No BLE hardware is required.
"""

from __future__ import annotations

from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import List, Tuple, Optional

from .types import Reading


class DSTFoldCorrector:
    """Restores physical (monotonic) time across DST fall-back transitions.

    Without correction, the repeated 1–2 AM hour on clocks-back night
    produces duplicate wall-clock timestamps, silently erasing an hour
    of real data.
    """

    MIN_BACKWARD_JUMP: float = 5.0
    MAX_BACKWARD_JUMP: float = 7200.0  # 2 hours
    FOLD_DURATION: float = 3600.0  # 1 hour

    def __init__(self, tz: timezone | None = None):
        # Store seconds offset from UTC for DST transition detection.
        # We use isdst to detect whether the timezone is currently in DST.
        self._tz = tz
        self._offset: float = 0.0
        self._previous: Optional[datetime] = None

    def corrected(self, parsed: datetime) -> datetime:
        """Feed naively parsed timestamps in file order; returns
        the fold-corrected physical timestamp."""
        if self._previous is None:
            self._previous = parsed
            return parsed

        # Once naive parse catches up to corrected timeline, wall clock
        # has passed the ambiguous hour — stop compensating.
        if self._offset > 0 and parsed >= self._previous:
            self._offset = 0.0

        candidate = parsed + timedelta(seconds=self._offset)
        delta = (candidate - self._previous).total_seconds()

        if (
            delta < -self.MIN_BACKWARD_JUMP
            and delta >= -self.MAX_BACKWARD_JUMP
            and self._tz is not None
            and _clocks_fell_back(self._previous, self._tz)
        ):
            self._offset += self.FOLD_DURATION
            candidate = parsed + timedelta(seconds=self._offset)

        self._previous = candidate
        return candidate


def _clocks_fell_back(instant: datetime, tz: timezone) -> bool:
    """True only when the timezone transitioned clocks back near instant."""
    # Check if instant is in DST and 1 hour earlier is not —
    # this is a heuristic for fall-back transition proximity.
    before = instant - timedelta(hours=1)
    before_dst = before.astimezone(tz).dst() != timedelta(0)
    instant_dst = instant.astimezone(tz).dst() != timedelta(0)
    return before_dst and not instant_dst


def parse_csv(content: str, timezone: timezone | None = None,
              correct_dst_fold: bool = True) -> Tuple[List[Reading], List[str]]:
    """Parse EMAY CSV content.

    Returns (readings, warnings). Raises ValueError if the file has no
    data rows.
    """
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    if len(lines) <= 1:
        raise ValueError("CSV file contains no data rows")

    warnings: List[str] = []
    readings: List[Reading] = []
    corrector = DSTFoldCorrector(tz=timezone if correct_dst_fold else None)

    for i, line in enumerate(lines[1:], start=2):
        fields = [f.strip() for f in line.split(",")]
        if len(fields) < 2:
            warnings.append(f"Row {i}: skipping — expected at least date,time columns")
            continue

        date_str = f"{fields[0]} {fields[1]}"
        try:
            parsed = datetime.strptime(date_str, "%m/%d/%Y %I:%M:%S %p")
        except ValueError:
            warnings.append(f"Row {i}: skipping — invalid date/time '{date_str}'")
            continue

        # Attach local timezone info if provided
        if timezone is not None:
            parsed = parsed.replace(tzinfo=timezone)

        timestamp = corrector.corrected(parsed) if correct_dst_fold else parsed

        spo2_str = fields[2] if len(fields) > 2 else ""
        pr_str = fields[3] if len(fields) > 3 else ""

        spo2 = int(spo2_str) if spo2_str else None
        pulse = int(pr_str) if pr_str else None

        readings.append(Reading(spo2=spo2, pulse=pulse, timestamp=timestamp))

    return readings, warnings


def parse_csv_file(path: str | Path, timezone: timezone | None = None,
                   correct_dst_fold: bool = True) -> Tuple[List[Reading], List[str]]:
    """Parse an EMAY CSV file from disk."""
    content = Path(path).read_text(encoding="utf-8")
    return parse_csv(content, timezone=timezone, correct_dst_fold=correct_dst_fold)


__all__ = ["parse_csv", "parse_csv_file", "DSTFoldCorrector"]
