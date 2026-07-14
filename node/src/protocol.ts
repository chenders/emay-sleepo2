/**
 * Pure-protocol layer for the EMAY SleepO2 BLE protocol.
 * No Bluetooth, no platform dependencies.
 */

import { Reading } from "./types.js";

// ---- BLE identifiers ----
export const SERVICE_UUID = "0000ff12-0000-1000-8000-00805f9b34fb";
export const WRITE_UUID = "0000ff01-0000-1000-8000-00805f9b34fb";
export const NOTIFY_UUID = "0000ff02-0000-1000-8000-00805f9b34fb";
export const NAME_PREFIX = "SleepO2";

// ---- Commands ----
export const HELLO = Buffer.from([0x89, 0x09]);
export const DEVICE_STATE = Buffer.from([0x8e, 0x05, 0x13]);
export const START_REALTIME = Buffer.from([0x9b, 0x01, 0x1c]);
export const STOP_REALTIME = Buffer.from([0x9b, 0x7f, 0x1a]);
export const GET_BATTERY = Buffer.from([0x86, 0x06]);
export const HEARTBEAT = Buffer.from([0x9a, 0x1a]);

export const START_SEQUENCE: Buffer[] = [
  HELLO,
  DEVICE_STATE,
  START_REALTIME,
  GET_BATTERY,
];

// ---- Data frame constants ----
const FRAME_LENGTH = 8;
const FRAME_HEADER = [0xeb, 0x01, 0x05];
const FRAME_TRAILER = [0x7f, 0x00];
const SENTINEL_VALUES = new Set([0x00, 0xff]);

// ---- Plausibility bounds ----
const PULSE_MIN_BPM = 30;
const PULSE_MAX_BPM = 220;
const SPO2_MAX_PERCENT = 100;
const SPO2_MIN_PERCENT = 0;

/**
 * Compute the EMAY checksum: sum(payload) & 0x7F.
 * The 0x7F mask (NOT 0xFF) is crucial.
 */
export function checksum(payload: Buffer | Uint8Array): number {
  let sum = 0;
  for (let i = 0; i < payload.length; i++) sum += payload[i];
  return sum & 0x7f;
}

/** Build a full command frame: payload + checksum. */
export function command(payload: number[]): Buffer {
  const buf = Buffer.from(payload);
  return Buffer.concat([buf, Buffer.from([checksum(buf)])]);
}

/**
 * Attempt to parse an 8-byte raw frame from the BLE notify characteristic.
 * Returns a Reading on success, null if any validation check fails.
 */
export function parseReading(raw: Buffer | Uint8Array): Reading | null {
  if (raw.length !== FRAME_LENGTH) return null;
  if (raw[0] !== FRAME_HEADER[0] || raw[1] !== FRAME_HEADER[1] || raw[2] !== FRAME_HEADER[2])
    return null;
  if (raw[5] !== FRAME_TRAILER[0] || raw[6] !== FRAME_TRAILER[1]) return null;

  let cks = 0;
  for (let i = 0; i < 7; i++) cks += raw[i];
  cks = cks & 0x7f;
  if (raw[7] !== cks) return null;

  const rawPR = raw[3];
  const rawSpO2 = raw[4];

  const pulse: number | null = SENTINEL_VALUES.has(rawPR) ? null : rawPR;
  const spo2: number | null = SENTINEL_VALUES.has(rawSpO2) ? null : rawSpO2;

  if (pulse !== null && (pulse < PULSE_MIN_BPM || pulse > PULSE_MAX_BPM)) return null;
  if (spo2 !== null && (spo2 < SPO2_MIN_PERCENT || spo2 > SPO2_MAX_PERCENT)) return null;

  return { spo2, pulse, timestamp: new Date() };
}
