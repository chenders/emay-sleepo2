use std::time::{SystemTime, UNIX_EPOCH};

/// A single physiological reading from the EMAY SleepO2.
#[derive(Debug, Clone, PartialEq)]
pub struct Reading {
    /// Oxygen saturation percent (0–100), or None when not acquired.
    pub spo2: Option<u8>,
    /// Pulse rate in beats per minute, or None when not acquired.
    pub pulse: Option<u8>,
    /// When this reading was captured (seconds since UNIX epoch).
    pub timestamp_secs: f64,
}

impl Reading {
    pub fn new(spo2: Option<u8>, pulse: Option<u8>) -> Self {
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs_f64();
        Self {
            spo2,
            pulse,
            timestamp_secs: ts,
        }
    }
}

/// Observable connection/streaming state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Status {
    Idle,
    Scanning,
    Connecting,
    Streaming,
    BluetoothOff,
    BluetoothUnauthorized,
    BluetoothUnsupported,
    Failed(String),
}

impl Status {
    pub fn is_active(&self) -> bool {
        matches!(
            self,
            Status::Scanning | Status::Connecting | Status::Streaming
        )
    }
}

/// A finalized per-minute mean sample.
#[derive(Debug, Clone, PartialEq)]
pub struct MinuteSample {
    pub minute_start_secs: u64,
    pub metric_type: String,
    pub value: f64,
    pub unit_string: String,
}
