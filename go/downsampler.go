package emay

import "time"

func startOfMinute(t time.Time) time.Time {
	return t.Truncate(time.Minute)
}

// LiveDownsampler buckets ~1 Hz EMAY readings into per-minute means.
type LiveDownsampler struct {
	MinSamplesPerMinute int
	spo2Vals            []float64
	pulseVals           []float64
	currentMinute       *time.Time
}

func NewLiveDownsampler(minSamples int) *LiveDownsampler {
	return &LiveDownsampler{MinSamplesPerMinute: minSamples}
}

// Add feeds a new reading. Returns finalized MinuteSamples.
func (d *LiveDownsampler) Add(r Reading) []MinuteSample {
	minute := startOfMinute(r.Timestamp)
	var flushed []MinuteSample

	if d.currentMinute != nil && !minute.Equal(*d.currentMinute) {
		flushed = d.finalize()
	}

	d.currentMinute = &minute
	if r.SpO2 != nil {
		d.spo2Vals = append(d.spo2Vals, float64(*r.SpO2))
	}
	if r.Pulse != nil {
		d.pulseVals = append(d.pulseVals, float64(*r.Pulse))
	}
	return flushed
}

// Flush finalizes and returns the current partial bucket.
func (d *LiveDownsampler) Flush() []MinuteSample {
	samples := d.finalize()
	d.currentMinute = nil
	d.spo2Vals = nil
	d.pulseVals = nil
	return samples
}

func (d *LiveDownsampler) finalize() []MinuteSample {
	if d.currentMinute == nil {
		return nil
	}
	var samples []MinuteSample

	if len(d.spo2Vals) >= d.MinSamplesPerMinute {
		sum := 0.0
		for _, v := range d.spo2Vals {
			sum += v
		}
		samples = append(samples, MinuteSample{
			MinuteStart: *d.currentMinute,
			MetricType:  "SpO2",
			Value:       sum / float64(len(d.spo2Vals)) / 100.0,
			UnitString:  "%",
		})
	}

	if len(d.pulseVals) >= d.MinSamplesPerMinute {
		sum := 0.0
		for _, v := range d.pulseVals {
			sum += v
		}
		samples = append(samples, MinuteSample{
			MinuteStart: *d.currentMinute,
			MetricType:  "PulseRate",
			Value:       sum / float64(len(d.pulseVals)),
			UnitString:  "count/min",
		})
	}

	d.spo2Vals = nil
	d.pulseVals = nil
	return samples
}
