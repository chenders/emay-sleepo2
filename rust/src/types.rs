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

/// Best-effort reason the client failed to reach a streaming session.
///
/// Only meaningful once a session has failed; otherwise it is
/// [`FailureReason::None`]. Read it via [`crate::EMAYClient::failure_reason`].
///
/// Note on [`FailureReason::NotFound`]: the SleepO2 is single-connection and
/// stops advertising while connected to another central, so a device that is
/// "connected to another app" is radio-indistinguishable from one that is off
/// or out of range. We therefore cannot report a definitive "busy" — the
/// message enumerates the possibilities honestly.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FailureReason {
    None,
    NotFound,
    ConnectionFailed,
}

impl FailureReason {
    /// A human-readable explanation suitable for showing a user.
    pub fn message(&self) -> &'static str {
        match self {
            FailureReason::None => "",
            FailureReason::NotFound => {
                "Device not found — it may be off, out of range, or connected to another app (the SleepO2 allows only one connection at a time)."
            }
            FailureReason::ConnectionFailed => {
                "Found the device but the connection failed — it may have moved out of range or been taken by another app mid-connect."
            }
        }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_failure_reason_messages() {
        assert_eq!(FailureReason::None.message(), "");
        assert!(
            FailureReason::NotFound
                .message()
                .contains("connected to another app")
        );
        assert!(
            FailureReason::ConnectionFailed
                .message()
                .contains("connection failed")
        );
    }
}
