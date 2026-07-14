/**
 * CSV parser for EMAY SleepO2 export files.
 */
import { Reading, CSVResult } from "./types";

/**
 * DST fall-back fold corrector.
 * Restores physical (monotonic) time across the repeated 1-2 AM hour.
 */
export class DSTFoldCorrector {
  private static MIN_BACKWARD_JUMP = 5;
  private static MAX_BACKWARD_JUMP = 7200;
  private static FOLD_DURATION = 3600;

  private offset: number = 0;
  private previous: Date | null = null;
  private tzOffset: number;

  constructor(timezoneOffsetMinutes?: number) {
    // Store the timezone's standard (non-DST) UTC offset
    this.tzOffset = timezoneOffsetMinutes ?? new Date().getTimezoneOffset();
  }

  /** Feed naively parsed timestamps in file order. */
  corrected(parsed: Date): Date {
    if (!this.previous) { this.previous = parsed; return parsed; }

    if (this.offset > 0 && parsed >= this.previous) {
      this.offset = 0;
    }

    let candidate = new Date(parsed.getTime() + this.offset * 1000);
    const delta = (candidate.getTime() - this.previous.getTime()) / 1000;

    if (
      delta < -DSTFoldCorrector.MIN_BACKWARD_JUMP &&
      delta >= -DSTFoldCorrector.MAX_BACKWARD_JUMP &&
      this.clocksFellBack(this.previous)
    ) {
      this.offset += DSTFoldCorrector.FOLD_DURATION;
      candidate = new Date(parsed.getTime() + this.offset * 1000);
    }

    this.previous = candidate;
    return candidate;
  }

  private clocksFellBack(instant: Date): boolean {
    // Heuristic: if instant is in DST, check if subtracting 1 hour
    // would land in standard time.
    const janOffset = new Date(instant.getFullYear(), 0, 1).getTimezoneOffset();
    const julOffset = new Date(instant.getFullYear(), 6, 1).getTimezoneOffset();
    const standardOffset = Math.max(janOffset, julOffset);
    const currentOffset = instant.getTimezoneOffset();
    // If current offset is smaller (less negative = DST), and standard
    // offset is larger, this is a DST→standard transition candidate.
    return currentOffset < standardOffset;
  }
}

/** Parse EMAY CSV content. */
export function parseCSV(content: string, timezoneOffset?: number,
                          correctDSTFold: boolean = true): CSVResult {
  const lines = content.split(/\r?\n/).map(s => s.trim()).filter(s => s);
  if (lines.length <= 1) throw new Error("CSV file contains no data rows");

  const readings: Reading[] = [];
  const warnings: string[] = [];
  const corrector = correctDSTFold ? new DSTFoldCorrector(timezoneOffset) : null;

  for (let i = 1; i < lines.length; i++) {
    const rowNum = i + 1;
    const fields = lines[i].split(",").map(s => s.trim());
    if (fields.length < 2) {
      warnings.push(`Row ${rowNum}: skipping — expected at least date,time columns`);
      continue;
    }

    const dateStr = `${fields[0]} ${fields[1]}`;
    const parsed = new Date(dateStr);
    if (isNaN(parsed.getTime())) {
      warnings.push(`Row ${rowNum}: skipping — invalid date/time '${dateStr}'`);
      continue;
    }

    const timestamp = corrector ? corrector.corrected(parsed) : parsed;
    const spo2 = fields.length > 2 && fields[2] ? parseInt(fields[2]) : null;
    const pulse = fields.length > 3 && fields[3] ? parseInt(fields[3]) : null;

    readings.push({ spo2: isNaN(spo2!) ? null : spo2, pulse: isNaN(pulse!) ? null : pulse, timestamp });
  }

  return { readings, warnings };
}

/** Parse an EMAY CSV file from disk (Node.js only). */
export function parseCSVFile(path: string, timezoneOffset?: number,
                              correctDSTFold: boolean = true): CSVResult {
  const fs = require("fs");
  const content = fs.readFileSync(path, "utf-8");
  return parseCSV(content, timezoneOffset, correctDSTFold);
}
