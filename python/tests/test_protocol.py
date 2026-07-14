"""Tests for EMAY SleepO2 protocol."""

from emay_sleepo2.protocol import parse_reading, checksum


def _frame(pr: int, spo2: int) -> bytes:
    """Build a valid frame with given PR and SpO2."""
    raw = bytearray([0xEB, 0x01, 0x05, pr, spo2, 0x7F, 0x00, 0x00])
    raw[7] = sum(raw[:7]) & 0x7F
    return bytes(raw)


class TestChecksum:
    def test_hello(self):
        assert checksum(bytes([0x89])) == 0x09

    def test_heartbeat(self):
        assert checksum(bytes([0x9A])) == 0x1A

    def test_start_realtime(self):
        assert checksum(bytes([0x9B, 0x01])) == 0x1C

    def test_device_state(self):
        assert checksum(bytes([0x8E, 0x05])) == 0x13

    def test_stop_realtime(self):
        assert checksum(bytes([0x9B, 0x7F])) == 0x1A


class TestParseReading:
    def test_valid(self):
        r = parse_reading(_frame(62, 98))
        assert r.pulse == 62
        assert r.spo2 == 98

    def test_wrong_length(self):
        assert parse_reading(b"\xeb\x01\x05\x3e\x62\x7f") is None

    def test_bad_header(self):
        raw = bytearray([0x00, 0x01, 0x05, 62, 98, 0x7F, 0x00, 0x00])
        raw[7] = sum(raw[:7]) & 0x7F
        assert parse_reading(bytes(raw)) is None

    def test_bad_trailer(self):
        raw = bytearray([0xEB, 0x01, 0x05, 62, 98, 0x00, 0x00, 0x00])
        raw[7] = sum(raw[:7]) & 0x7F
        assert parse_reading(bytes(raw)) is None

    def test_bad_checksum(self):
        assert parse_reading(bytes([0xEB, 0x01, 0x05, 62, 98, 0x7F, 0x00, 0xFF])) is None

    def test_sentinel_pr_0(self):
        r = parse_reading(_frame(0x00, 98))
        assert r.pulse is None
        assert r.spo2 == 98

    def test_sentinel_pr_ff(self):
        r = parse_reading(_frame(0xFF, 98))
        assert r.pulse is None

    def test_sentinel_spo2_0(self):
        r = parse_reading(_frame(62, 0x00))
        assert r.spo2 is None
        assert r.pulse == 62

    def test_sentinel_spo2_ff(self):
        r = parse_reading(_frame(62, 0xFF))
        assert r.spo2 is None

    def test_both_sentinels(self):
        r = parse_reading(_frame(0xFF, 0xFF))
        assert r.spo2 is None
        assert r.pulse is None

    def test_pulse_too_low(self):
        assert parse_reading(_frame(29, 98)) is None

    def test_pulse_too_high(self):
        assert parse_reading(_frame(221, 98)) is None

    def test_pulse_boundary_min(self):
        r = parse_reading(_frame(30, 98))
        assert r.pulse == 30

    def test_pulse_boundary_max(self):
        r = parse_reading(_frame(220, 98))
        assert r.pulse == 220

    def test_spo2_too_high(self):
        assert parse_reading(_frame(62, 101)) is None

    def test_spo2_boundary_min(self):
        r = parse_reading(_frame(62, 1))
        assert r.spo2 == 1

    def test_spo2_boundary_max(self):
        r = parse_reading(_frame(62, 100))
        assert r.spo2 == 100
