/// CSV parser for EMAY SleepO2 export files (feature-gated behind "csv").
use crate::types::Reading;

/// DST fall-back fold corrector.
pub struct DSTFoldCorrector {
    offset: f64,
    previous: Option<f64>,
    tz_is_dst_aware: bool,
}

impl DSTFoldCorrector {
    pub fn new() -> Self {
        Self {
            offset: 0.0,
            previous: None,
            tz_is_dst_aware: false,
        }
    }
}

impl Default for DSTFoldCorrector {
    fn default() -> Self {
        Self::new()
    }
}

impl DSTFoldCorrector {
    pub fn with_dst() -> Self {
        Self {
            offset: 0.0,
            previous: None,
            tz_is_dst_aware: true,
        }
    }

    pub fn corrected(&mut self, parsed_secs: f64) -> f64 {
        if let Some(prev) = self.previous {
            if self.offset > 0.0 && parsed_secs >= prev {
                self.offset = 0.0;
            }
            let mut candidate = parsed_secs + self.offset;
            let delta = candidate - prev;
            if (-7200.0..-5.0).contains(&delta) && self.tz_is_dst_aware {
                self.offset += 3600.0;
                candidate = parsed_secs + self.offset;
            }
            self.previous = Some(candidate);
            candidate
        } else {
            self.previous = Some(parsed_secs);
            parsed_secs
        }
    }
}

/// Parse EMAY CSV content. Returns (readings, warnings).
pub fn parse_csv(
    content: &str,
    correct_dst_fold: bool,
) -> Result<(Vec<Reading>, Vec<String>), String> {
    let lines: Vec<&str> = content
        .lines()
        .map(|l| l.trim())
        .filter(|l| !l.is_empty())
        .collect();

    if lines.len() <= 1 {
        return Err("CSV file contains no data rows".into());
    }

    let mut readings = Vec::new();
    let mut warnings = Vec::new();
    let mut corrector = if correct_dst_fold {
        Some(DSTFoldCorrector::with_dst())
    } else {
        None
    };

    for (i, line) in lines.iter().enumerate().skip(1) {
        let row_num = i + 1;
        let fields: Vec<&str> = line.split(',').map(|f| f.trim()).collect();
        if fields.len() < 2 {
            warnings.push(format!(
                "Row {row_num}: skipping — expected at least date,time columns"
            ));
            continue;
        }

        // Simple parse: M/D/YYYY H:MM:SS AM/PM
        let date_str = format!("{} {}", fields[0], fields[1]);
        let parsed_secs = parse_date_to_secs(&date_str);
        let Some(parsed_secs) = parsed_secs else {
            warnings.push(format!("Row {row_num}: invalid date/time '{date_str}'"));
            continue;
        };

        let timestamp_secs = if let Some(ref mut c) = corrector {
            c.corrected(parsed_secs)
        } else {
            parsed_secs
        };

        let spo2 = fields
            .get(2)
            .and_then(|s| if s.is_empty() { None } else { s.parse().ok() });
        let pulse = fields
            .get(3)
            .and_then(|s| if s.is_empty() { None } else { s.parse().ok() });

        readings.push(Reading {
            spo2,
            pulse,
            timestamp_secs,
        });
    }

    Ok((readings, warnings))
}

/// Parse an EMAY CSV file from disk.
pub fn parse_csv_file<P: AsRef<std::path::Path>>(
    path: P,
    correct_dst_fold: bool,
) -> Result<(Vec<Reading>, Vec<String>), String> {
    let content = std::fs::read_to_string(path).map_err(|e| format!("{e}"))?;
    parse_csv(&content, correct_dst_fold)
}

fn parse_date_to_secs(s: &str) -> Option<f64> {
    // Format: M/D/YYYY H:MM:SS AM|PM
    let parts: Vec<&str> = s.split_whitespace().collect();
    if parts.len() < 3 {
        return None;
    }

    let date_parts: Vec<&str> = parts[0].split('/').collect();
    let time_parts: Vec<&str> = parts[1].split(':').collect();
    if date_parts.len() < 3 || time_parts.len() < 3 {
        return None;
    }

    let month: u32 = date_parts[0].parse().ok()?;
    let day: u32 = date_parts[1].parse().ok()?;
    let year: i32 = date_parts[2].parse().ok()?;
    let mut hour: u32 = time_parts[0].parse().ok()?;
    let minute: u32 = time_parts[1].parse().ok()?;
    let second: u32 = time_parts[2].parse().ok()?;
    let ampm = parts[2];

    if ampm.eq_ignore_ascii_case("PM") && hour < 12 {
        hour += 12;
    }
    if ampm.eq_ignore_ascii_case("AM") && hour == 12 {
        hour = 0;
    }

    use std::time::{SystemTime, UNIX_EPOCH};
    // Use a simple days-from-epoch approach
    let days_before_month: [u32; 12] = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
    let is_leap = |y: i32| (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
    let leap_days = (1970..year).filter(|&y| is_leap(y)).count() as u32;
    let year_days = ((year - 1970) as u32) * 365 + leap_days;
    let month_days =
        days_before_month[(month - 1) as usize] + if month > 2 && is_leap(year) { 1 } else { 0 };
    let day_part = year_days + month_days + (day - 1);

    let total_secs =
        day_part as f64 * 86400.0 + hour as f64 * 3600.0 + minute as f64 * 60.0 + second as f64;

    // Adjust for local offset: approximate
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let now_utc = now.as_secs() as f64;
    let _local_now = now_utc; // UTC for simplicity
    Some(total_secs)
}
