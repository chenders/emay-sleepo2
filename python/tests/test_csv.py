"""Tests for EMAY CSV parser."""
import pytest
from emay_sleepo2.csv_parser import parse_csv, DSTFoldCorrector
from datetime import datetime, timezone


def test_parse_valid():
    csv = "Date,Time,SpO2(%),PR(bpm)\n5/8/2026,4:46:58 PM,98,52\n5/8/2026,4:47:00 PM,,58"
    readings, warnings = parse_csv(csv, correct_dst_fold=False)
    assert len(readings) == 2
    assert readings[0].spo2 == 98
    assert readings[0].pulse == 52
    assert readings[1].spo2 is None
    assert readings[1].pulse == 58


def test_empty_throws():
    with pytest.raises(ValueError):
        parse_csv("Date,Time,SpO2(%),PR(bpm)")


def test_invalid_date_warns():
    csv = "Date,Time,SpO2(%),PR(bpm)\nbad,data,99,50\n5/8/2026,4:47:00 PM,98,52"
    readings, warnings = parse_csv(csv, correct_dst_fold=False)
    assert len(warnings) >= 1
    assert len(readings) == 1
    assert readings[0].spo2 == 98


def test_dst_fold_no_correction_without_transition():
    """Without a real DST transition, backward jumps are left alone."""
    # Fixed-offset timezone has no DST transitions
    utc = timezone.utc
    corrector = DSTFoldCorrector(tz=utc)
    t1 = datetime(2026, 11, 1, 1, 55, tzinfo=utc)
    t2 = datetime(2026, 11, 1, 1, 5, tzinfo=utc)
    c1 = corrector.corrected(t1)
    c2 = corrector.corrected(t2)
    # UTC has no DST → backward jump stays
    assert c2 < c1, "Without DST transition, backward jump should NOT be corrected"
