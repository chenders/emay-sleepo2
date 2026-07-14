/// Per-minute downsampler for the ~1 Hz EMAY stream.
use crate::types::{MinuteSample, Reading};

fn start_of_minute(secs: f64) -> u64 {
    (secs as u64) / 60 * 60
}

#[derive(Default)]
pub struct LiveDownsampler {
    pub minimum_samples_per_minute: usize,
    spo2_values: Vec<f64>,
    pulse_values: Vec<f64>,
    current_minute: Option<u64>,
}

impl LiveDownsampler {
    pub fn new() -> Self {
        Self {
            minimum_samples_per_minute: 2,
            ..Default::default()
        }
    }

    /// Feed a new reading. Returns finalized MinuteSamples.
    pub fn add(&mut self, reading: &Reading) -> Vec<MinuteSample> {
        let minute = start_of_minute(reading.timestamp_secs);
        let mut flushed = Vec::new();

        if let Some(cur) = self.current_minute && minute != cur {
                flushed = self.finalize_locked();
            }

        self.current_minute = Some(minute);
        if let Some(s) = reading.spo2 { self.spo2_values.push(s as f64); }
        if let Some(p) = reading.pulse { self.pulse_values.push(p as f64); }
        flushed
    }

    /// Finalize and return the current partial bucket.
    pub fn flush(&mut self) -> Vec<MinuteSample> {
        let result = self.finalize_locked();
        self.current_minute = None;
        self.spo2_values.clear();
        self.pulse_values.clear();
        result
    }

    fn finalize_locked(&mut self) -> Vec<MinuteSample> {
        let Some(minute) = self.current_minute else { return vec![] };
        let mut samples = Vec::new();

        let spo2_count = self.spo2_values.len();
        if spo2_count >= self.minimum_samples_per_minute {
            let mean = self.spo2_values.iter().sum::<f64>() / spo2_count as f64;
            samples.push(MinuteSample {
                minute_start_secs: minute,
                metric_type: "SpO2".into(),
                value: mean / 100.0,
                unit_string: "%".into(),
            });
        }

        let pulse_count = self.pulse_values.len();
        if pulse_count >= self.minimum_samples_per_minute {
            let mean = self.pulse_values.iter().sum::<f64>() / pulse_count as f64;
            samples.push(MinuteSample {
                minute_start_secs: minute,
                metric_type: "PulseRate".into(),
                value: mean,
                unit_string: "count/min".into(),
            });
        }

        self.spo2_values.clear();
        self.pulse_values.clear();
        samples
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reading(spo2: Option<u8>, pulse: Option<u8>, minute: u64, second: u64) -> Reading {
        let ts = (minute * 60 + second) as f64;
        Reading { spo2, pulse, timestamp_secs: ts }
    }

    #[test]
    fn test_below_minimum() {
        let mut ds = LiveDownsampler::new();
        ds.minimum_samples_per_minute = 2;
        assert!(ds.add(&reading(Some(98), Some(60), 10, 30)).is_empty());
    }

    #[test]
    fn test_two_samples() {
        let mut ds = LiveDownsampler::new();
        ds.minimum_samples_per_minute = 2;
        ds.add(&reading(Some(98), Some(60), 10, 30));
        ds.add(&reading(Some(96), Some(62), 10, 31));
        let result = ds.flush();
        assert_eq!(result.len(), 2);
    }

    #[test]
    fn test_minute_boundary() {
        let mut ds = LiveDownsampler::new();
        ds.minimum_samples_per_minute = 1;
        ds.add(&reading(Some(98), None, 10, 30));
        let flushed = ds.add(&reading(Some(95), Some(60), 11, 1));
        assert_eq!(flushed.len(), 1);
    }

    #[test]
    fn test_nil_excluded() {
        let mut ds = LiveDownsampler::new();
        ds.minimum_samples_per_minute = 2;
        ds.add(&reading(Some(98), None, 10, 30));
        ds.add(&reading(Some(96), Some(60), 10, 31));
        let result = ds.flush();
        assert!(!result.iter().any(|s| s.metric_type == "PulseRate"));
    }

    #[test]
    fn test_flush_empties() {
        let mut ds = LiveDownsampler::new();
        ds.minimum_samples_per_minute = 1;
        ds.add(&reading(Some(98), Some(60), 10, 30));
        assert!(!ds.flush().is_empty());
        assert!(ds.flush().is_empty());
    }
}
