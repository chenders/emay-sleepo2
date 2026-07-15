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
