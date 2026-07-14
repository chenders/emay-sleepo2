package emay

import (
	"testing"
	"time"
)

func reading(spo2, pulse *int, minute, second int) Reading {
	ts := time.Date(2026, 5, 8, 16, minute, second, 0, time.UTC)
	return Reading{SpO2: spo2, Pulse: pulse, Timestamp: ts}
}

func intPtr(v int) *int { return &v }

func TestDownsamplerBelowMinimum(t *testing.T) {
	ds := NewLiveDownsampler(2)
	result := ds.Add(reading(intPtr(98), intPtr(60), 10, 30))
	if len(result) != 0 { t.Errorf("expected 0, got %d", len(result)) }
}

func TestDownsamplerTwoSamples(t *testing.T) {
	ds := NewLiveDownsampler(2)
	ds.Add(reading(intPtr(98), intPtr(60), 10, 30))
	ds.Add(reading(intPtr(96), intPtr(62), 10, 31))
	result := ds.Flush()
	if len(result) != 2 { t.Errorf("expected 2 samples, got %d", len(result)) }
}

func TestDownsamplerMinuteBoundary(t *testing.T) {
	ds := NewLiveDownsampler(1)
	ds.Add(reading(intPtr(98), nil, 10, 30))
	flushed := ds.Add(reading(intPtr(95), intPtr(60), 11, 1))
	if len(flushed) != 1 { t.Errorf("expected 1, got %d", len(flushed)) }
	if flushed[0].Value != 0.98 { t.Errorf("expected 0.98, got %f", flushed[0].Value) }
}

func TestDownsamplerNilMetrics(t *testing.T) {
	ds := NewLiveDownsampler(2)
	ds.Add(reading(intPtr(98), nil, 10, 30))
	ds.Add(reading(intPtr(96), intPtr(60), 10, 31))
	result := ds.Flush()
	for _, s := range result {
		if s.MetricType == "PulseRate" {
			t.Error("expected no pulse sample with only 1 reading")
		}
	}
}

func TestDownsamplerFlushEmpties(t *testing.T) {
	ds := NewLiveDownsampler(1)
	ds.Add(reading(intPtr(98), intPtr(60), 10, 30))
	if len(ds.Flush()) == 0 { t.Error("first flush should have data") }
	if len(ds.Flush()) != 0 { t.Error("second flush should be empty") }
}
