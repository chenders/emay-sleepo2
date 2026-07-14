"""Tests for EMAY downsampler."""
from datetime import datetime
from emay_sleepo2.downsampler import LiveDownsampler
from emay_sleepo2.types import Reading


def _reading(spo2, pulse, minute=10, second=30):
    ts = datetime(2026, 5, 8, 16, minute, second)
    return Reading(spo2=spo2, pulse=pulse, timestamp=ts)


def test_below_minimum():
    ds = LiveDownsampler(minimum_samples_per_minute=2)
    result = ds.add(_reading(98, 60))
    assert len(result) == 0


def test_two_samples():
    ds = LiveDownsampler(minimum_samples_per_minute=2)
    ds.add(_reading(98, 60, second=30))
    ds.add(_reading(96, 62, second=31))
    result = ds.flush()
    spo2 = [s for s in result if s.metric_type == "SpO2"][0]
    pulse = [s for s in result if s.metric_type == "PulseRate"][0]
    assert spo2.value == 0.97
    assert pulse.value == 61.0


def test_minute_boundary():
    ds = LiveDownsampler(minimum_samples_per_minute=1)
    ds.add(_reading(98, None, minute=10, second=30))
    flushed = ds.add(_reading(95, 60, minute=11, second=1))
    assert len(flushed) == 1
    assert flushed[0].metric_type == "SpO2"
    assert flushed[0].value == 0.98


def test_boundary_below_minimum():
    ds = LiveDownsampler(minimum_samples_per_minute=5)
    ds.add(_reading(98, 60, minute=10, second=30))
    flushed = ds.add(_reading(95, 62, minute=11, second=1))
    assert len(flushed) == 0


def test_nil_metrics_excluded():
    ds = LiveDownsampler(minimum_samples_per_minute=2)
    ds.add(_reading(98, None, second=30))
    ds.add(_reading(96, 60, second=31))
    result = ds.flush()
    pulse_samples = [s for s in result if s.metric_type == "PulseRate"]
    assert len(pulse_samples) == 0


def test_flush_empties():
    ds = LiveDownsampler(minimum_samples_per_minute=1)
    ds.add(_reading(98, 60))
    assert len(ds.flush()) > 0
    assert len(ds.flush()) == 0


def test_spo2_fraction():
    ds = LiveDownsampler(minimum_samples_per_minute=1)
    ds.add(_reading(50, 60))
    result = ds.flush()
    spo2 = [s for s in result if s.metric_type == "SpO2"][0]
    assert spo2.value == 0.50
    assert spo2.unit_string == "%"


def test_pulse_unit():
    ds = LiveDownsampler(minimum_samples_per_minute=1)
    ds.add(_reading(98, 75))
    result = ds.flush()
    pulse = [s for s in result if s.metric_type == "PulseRate"][0]
    assert pulse.value == 75.0
    assert pulse.unit_string == "count/min"
