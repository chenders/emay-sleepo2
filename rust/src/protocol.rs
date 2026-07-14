/// Pure-protocol layer for the EMAY SleepO2 BLE protocol.
/// no_std compatible with alloc.
use crate::types::Reading;

// ---- BLE identifiers ----
pub const SERVICE_UUID: &str = "0000ff12-0000-1000-8000-00805f9b34fb";
pub const WRITE_UUID: &str = "0000ff01-0000-1000-8000-00805f9b34fb";
pub const NOTIFY_UUID: &str = "0000ff02-0000-1000-8000-00805f9b34fb";
pub const NAME_PREFIX: &str = "SleepO2";

// ---- Command bytes ----
pub const HELLO: [u8; 2] = [0x89, 0x09];
pub const DEVICE_STATE: [u8; 3] = [0x8E, 0x05, 0x13];
pub const START_REALTIME: [u8; 3] = [0x9B, 0x01, 0x1C];
pub const STOP_REALTIME: [u8; 3] = [0x9B, 0x7F, 0x1A];
pub const GET_BATTERY: [u8; 2] = [0x86, 0x06];
pub const HEARTBEAT: [u8; 2] = [0x9A, 0x1A];

pub const START_SEQUENCE: &[&[u8]] = &[&HELLO, &DEVICE_STATE, &START_REALTIME, &GET_BATTERY];

// ---- Data frame constants ----
const FRAME_LENGTH: usize = 8;
const FRAME_HEADER: [u8; 3] = [0xEB, 0x01, 0x05];
const FRAME_TRAILER: [u8; 2] = [0x7F, 0x00];

// ---- Plausibility bounds ----
const PULSE_MIN_BPM: u8 = 30;
const PULSE_MAX_BPM: u8 = 220;
const SPO2_MIN_PCT: u8 = 0;
const SPO2_MAX_PCT: u8 = 100;
const SENTINEL_VALUES: [u8; 2] = [0x00, 0xFF];

/// Compute the EMAY checksum: sum(payload) & 0x7F.
pub fn checksum(payload: &[u8]) -> u8 {
    (payload.iter().map(|&b| b as u16).sum::<u16>() & 0x7F) as u8
}

/// Build a full command frame: payload + checksum.
pub fn command(payload: &[u8]) -> Vec<u8> {
    let mut v = payload.to_vec();
    v.push(checksum(payload));
    v
}

/// Attempt to parse an 8-byte raw frame. Returns Some(Reading) on
/// success, None if any validation fails.
pub fn parse_reading(raw: &[u8]) -> Option<Reading> {
    if raw.len() != FRAME_LENGTH { return None; }
    if raw[0] != FRAME_HEADER[0] || raw[1] != FRAME_HEADER[1] || raw[2] != FRAME_HEADER[2] {
        return None;
    }
    if raw[5] != FRAME_TRAILER[0] || raw[6] != FRAME_TRAILER[1] {
        return None;
    }
    let cks = (raw[..7].iter().map(|&b| b as u16).sum::<u16>() & 0x7F) as u8;
    if raw[7] != cks { return None; }

    let raw_pr = raw[3];
    let raw_spo2 = raw[4];

    let is_sentinel = |b: u8| SENTINEL_VALUES.contains(&b);

    let pulse = if is_sentinel(raw_pr) { None } else { Some(raw_pr) };
    let spo2 = if is_sentinel(raw_spo2) { None } else { Some(raw_spo2) };

    if let Some(p) = pulse { if p < PULSE_MIN_BPM || p > PULSE_MAX_BPM { return None; } }
    if let Some(s) = spo2 { if s < SPO2_MIN_PCT || s > SPO2_MAX_PCT { return None; } }

    Some(Reading::new(spo2, pulse))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(pr: u8, spo2: u8) -> Vec<u8> {
        let mut buf = vec![0xEB, 0x01, 0x05, pr, spo2, 0x7F, 0x00, 0x00];
        let ck: u8 = (buf[..7].iter().map(|&b| b as u16).sum::<u16>() & 0x7F) as u8;
        buf[7] = ck;
        buf
    }

    #[test]
    fn test_checksums() {
        assert_eq!(checksum(&[0x89]), 0x09);
        assert_eq!(checksum(&[0x9A]), 0x1A);
        assert_eq!(checksum(&[0x9B, 0x01]), 0x1C);
        assert_eq!(checksum(&[0x8E, 0x05]), 0x13);
        assert_eq!(checksum(&[0x9B, 0x7F]), 0x1A);
    }

    #[test]
    fn test_valid_frame() {
        let r = parse_reading(&frame(62, 98)).unwrap();
        assert_eq!(r.pulse, Some(62));
        assert_eq!(r.spo2, Some(98));
    }

    #[test]
    fn test_wrong_length() {
        assert!(parse_reading(&[0xEB, 0x01]).is_none());
    }

    #[test]
    fn test_bad_checksum() {
        let bad = vec![0xEB, 0x01, 0x05, 62, 98, 0x7F, 0x00, 0xFF];
        assert!(parse_reading(&bad).is_none());
    }

    #[test]
    fn test_sentinel_pr_0() {
        let r = parse_reading(&frame(0x00, 98)).unwrap();
        assert_eq!(r.pulse, None);
        assert_eq!(r.spo2, Some(98));
    }

    #[test]
    fn test_sentinel_spo2_ff() {
        let r = parse_reading(&frame(62, 0xFF)).unwrap();
        assert_eq!(r.spo2, None);
    }

    #[test]
    fn test_both_sentinels() {
        let r = parse_reading(&frame(0xFF, 0xFF)).unwrap();
        assert_eq!(r.pulse, None);
        assert_eq!(r.spo2, None);
    }

    #[test]
    fn test_pulse_too_low() {
        assert!(parse_reading(&frame(29, 98)).is_none());
    }

    #[test]
    fn test_pulse_too_high() {
        assert!(parse_reading(&frame(221, 98)).is_none());
    }

    #[test]
    fn test_pulse_boundary() {
        assert_eq!(parse_reading(&frame(30, 98)).unwrap().pulse, Some(30));
        assert_eq!(parse_reading(&frame(220, 98)).unwrap().pulse, Some(220));
    }

    #[test]
    fn test_spo2_too_high() {
        assert!(parse_reading(&frame(62, 101)).is_none());
    }

    #[test]
    fn test_spo2_boundary() {
        assert_eq!(parse_reading(&frame(62, 0)).unwrap().spo2, None);
        assert_eq!(parse_reading(&frame(62, 1)).unwrap().spo2, Some(1));
        assert_eq!(parse_reading(&frame(62, 100)).unwrap().spo2, Some(100));
    }
}
