package emay

import (
	"testing"
)

func frame(pr, spo2 byte) []byte {
	buf := []byte{0xEB, 0x01, 0x05, pr, spo2, 0x7F, 0x00, 0x00}
	var sum int
	for i := 0; i < 7; i++ { sum += int(buf[i]) }
	buf[7] = byte(sum & 0x7F)
	return buf
}

func TestParseReadingValid(t *testing.T) {
	r := parseReading(frame(62, 98))
	if r == nil { t.Fatal("expected non-nil") }
	if *r.Pulse != 62 { t.Errorf("pulse = %d, want 62", *r.Pulse) }
	if *r.SpO2 != 98 { t.Errorf("spo2 = %d, want 98", *r.SpO2) }
}

func TestParseReadingWrongLength(t *testing.T) {
	if r := parseReading([]byte{0xEB, 0x01}); r != nil {
		t.Error("expected nil for short frame")
	}
}

func TestParseReadingBadChecksum(t *testing.T) {
	raw := []byte{0xEB, 0x01, 0x05, 62, 98, 0x7F, 0x00, 0xFF}
	if r := parseReading(raw); r != nil { t.Error("expected nil") }
}

func TestParseReadingSentinelPR(t *testing.T) {
	r := parseReading(frame(0x00, 98))
	if r == nil { t.Fatal("expected non-nil") }
	if r.Pulse != nil { t.Error("pulse should be nil for 0x00 sentinel") }
	if r.SpO2 == nil || *r.SpO2 != 98 { t.Error("spo2 should be 98") }
}

func TestParseReadingSentinelSpO2(t *testing.T) {
	r := parseReading(frame(62, 0xFF))
	if r == nil { t.Fatal("expected non-nil") }
	if r.SpO2 != nil { t.Error("spo2 should be nil for 0xFF sentinel") }
}

func TestParseReadingBothSentinels(t *testing.T) {
	r := parseReading(frame(0xFF, 0xFF))
	if r == nil { t.Fatal("expected non-nil") }
	if r.Pulse != nil { t.Error("pulse should be nil") }
	if r.SpO2 != nil { t.Error("spo2 should be nil") }
}

func TestParseReadingPulseTooLow(t *testing.T) {
	r := parseReading(frame(29, 98))
	if r == nil || r.Pulse != nil { t.Error("pulse 29 should be nil") }
}

func TestParseReadingPulseTooHigh(t *testing.T) {
	r := parseReading(frame(221, 98))
	if r == nil || r.Pulse != nil { t.Error("pulse 221 should be nil") }
}

func TestParseReadingPulseBoundary(t *testing.T) {
	r := parseReading(frame(30, 98))
	if r == nil || *r.Pulse != 30 { t.Error("pulse 30 should be accepted") }
	r = parseReading(frame(220, 98))
	if r == nil || *r.Pulse != 220 { t.Error("pulse 220 should be accepted") }
}

func TestParseReadingSpO2TooHigh(t *testing.T) {
	r := parseReading(frame(62, 101))
	if r == nil || r.SpO2 != nil { t.Error("spo2 101 should be nil") }
}

func TestParseReadingSpO2Boundary(t *testing.T) {
	r := parseReading(frame(62, 0))
	// 0x00 is a sentinel — so spo2 should be nil
	if r == nil || r.SpO2 != nil { t.Error("spo2 0x00 should be sentinel") }
	r = parseReading(frame(62, 1))
	if r == nil || *r.SpO2 != 1 { t.Error("spo2 1 should be accepted") }
	r = parseReading(frame(62, 100))
	if r == nil || *r.SpO2 != 100 { t.Error("spo2 100 should be accepted") }
}
