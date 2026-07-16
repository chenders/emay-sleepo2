/**
 * Data types for the EMAY SleepO2 SDK.
 */

/** A single physiological reading from the EMAY SleepO2. */
export interface Reading {
  /** Oxygen saturation percent (0–100), or null when not acquired. */
  spo2: number | null;
  /** Pulse rate in bpm, or null when not acquired. */
  pulse: number | null;
  /** When this reading was captured. */
  timestamp: Date;
}

/** A finalized per-minute mean sample. */
export interface MinuteSample {
  minuteStart: Date;
  metricType: string; // "SpO2" | "PulseRate"
  value: number;
  unitString: string; // "%" | "count/min"
}

/** Observable connection/streaming state. */
export enum Status {
  Idle = "idle",
  Scanning = "scanning",
  Connecting = "connecting",
  Streaming = "streaming",
  BluetoothOff = "bluetoothOff",
  BluetoothUnauthorized = "bluetoothUnauthorized",
  BluetoothUnsupported = "bluetoothUnsupported",
  Failed = "failed",
}

/**
 * Best-effort reason the client entered {@link Status.Failed}.
 *
 * Only meaningful while `status === Status.Failed`; otherwise it is
 * {@link FailureReason.None}. Read it via `EMAYClient.failureReason`.
 *
 * Note on `NotFound`: the SleepO2 is single-connection and stops advertising
 * while connected to another central, so a device that is "connected to another
 * app" is radio-indistinguishable from one that is off or out of range. We
 * therefore cannot report a definitive "busy" — the message enumerates the
 * possibilities honestly.
 */
export enum FailureReason {
  None = "none",
  NotFound = "notFound",
  ConnectionFailed = "connectionFailed",
}

/** A human-readable explanation of a {@link FailureReason}, suitable for showing a user. */
export function failureReasonMessage(r: FailureReason): string {
  switch (r) {
    case FailureReason.NotFound:
      return "Device not found — it may be off, out of range, or connected to another app (the SleepO2 allows only one connection at a time).";
    case FailureReason.ConnectionFailed:
      return "Found the device but the connection failed — it may have moved out of range or been taken by another app mid-connect.";
    case FailureReason.None:
      return "";
  }
}
