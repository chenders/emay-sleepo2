/**
 * Tests for EMAY SleepO2 protocol (Node.js).
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  parseReading,
  checksum,
  command,
  HELLO,
  HEARTBEAT,
  START_REALTIME,
  DEVICE_STATE,
  STOP_REALTIME,
} from "../src/protocol.js";

function frame(pr: number, spo2: number): Buffer {
  const buf = Buffer.from([0xeb, 0x01, 0x05, pr, spo2, 0x7f, 0x00, 0x00]);
  let cks = 0;
  for (let i = 0; i < 7; i++) cks += buf[i];
  buf[7] = cks & 0x7f;
  return buf;
}

describe("checksum", () => {
  it("hello", () => assert.equal(checksum(Buffer.from([0x89])), 0x09));
  it("heartbeat", () => assert.equal(checksum(Buffer.from([0x9a])), 0x1a));
  it("startRealtime", () =>
    assert.equal(checksum(Buffer.from([0x9b, 0x01])), 0x1c));
  it("stopRealtime", () =>
    assert.equal(checksum(Buffer.from([0x9b, 0x7f])), 0x1a));
});

describe("parseReading", () => {
  it("valid frame", () => {
    const r = parseReading(frame(62, 98));
    assert.ok(r);
    assert.equal(r!.pulse, 62);
    assert.equal(r!.spo2, 98);
  });

  it("wrong length", () =>
    assert.equal(parseReading(Buffer.from([0xeb, 0x01])), null));
  it("bad checksum", () =>
    assert.equal(
      parseReading(Buffer.from([0xeb, 0x01, 0x05, 62, 98, 0x7f, 0x00, 0xff])),
      null,
    ));

  it("PR=0x00 → null pulse", () => {
    const r = parseReading(frame(0x00, 98));
    assert.ok(r);
    assert.equal(r!.pulse, null);
    assert.equal(r!.spo2, 98);
  });

  it("PR=0xFF → null pulse", () => {
    const r = parseReading(frame(0xff, 98));
    assert.equal(r!.pulse, null);
  });

  it("SpO2=0x00 → null spo2", () => {
    const r = parseReading(frame(62, 0x00));
    assert.equal(r!.spo2, null);
  });

  it("both sentinels", () => {
    const r = parseReading(frame(0xff, 0xff));
    assert.equal(r!.pulse, null);
    assert.equal(r!.spo2, null);
  });

  it("pulse < 30 rejected", () =>
    assert.equal(parseReading(frame(29, 98)), null));
  it("pulse > 220 rejected", () =>
    assert.equal(parseReading(frame(221, 98)), null));
  it("pulse 30 accepted", () => {
    const r = parseReading(frame(30, 98));
    assert.equal(r!.pulse, 30);
  });
  it("pulse 220 accepted", () => {
    const r = parseReading(frame(220, 98));
    assert.equal(r!.pulse, 220);
  });
  it("SpO2 > 100 rejected", () =>
    assert.equal(parseReading(frame(62, 101)), null));
});
