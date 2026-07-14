/**
 * Tests for EMAY downsampler (Node.js).
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { LiveDownsampler } from "../src/downsampler.js";
import { Reading } from "../src/types.js";

function reading(
  spo2: number | null,
  pulse: number | null,
  minute = 10,
  second = 30,
): Reading {
  const ts = new Date(2026, 4, 8, 16, minute, second); // month 0-indexed
  return { spo2, pulse, timestamp: ts };
}

describe("LiveDownsampler", () => {
  it("below minimum produces nothing", () => {
    const ds = new LiveDownsampler();
    ds.minimumSamplesPerMinute = 2;
    const result = ds.add(reading(98, 60));
    assert.equal(result.length, 0);
  });

  it("two samples produce means", () => {
    const ds = new LiveDownsampler();
    ds.minimumSamplesPerMinute = 2;
    ds.add(reading(98, 60, 10, 30));
    ds.add(reading(96, 62, 10, 31));
    const result = ds.flush();
    const spo2Sample = result.find((r) => r.metricType === "SpO2")!;
    assert.ok(spo2Sample);
    assert.equal(spo2Sample.value, 0.97);
    const pulseSample = result.find((r) => r.metricType === "PulseRate")!;
    assert.equal(pulseSample.value, 61.0);
  });

  it("minute boundary flushes previous", () => {
    const ds = new LiveDownsampler();
    ds.minimumSamplesPerMinute = 1;
    ds.add(reading(98, null, 10, 30));
    const flushed = ds.add(reading(95, 60, 11, 1));
    assert.equal(flushed.length, 1);
    assert.equal(flushed[0].value, 0.98);
  });

  it("below min discarded at boundary", () => {
    const ds = new LiveDownsampler();
    ds.minimumSamplesPerMinute = 5;
    ds.add(reading(98, 60, 10, 30));
    const flushed = ds.add(reading(95, 62, 11, 1));
    assert.equal(flushed.length, 0);
  });

  it("nil metrics excluded", () => {
    const ds = new LiveDownsampler();
    ds.minimumSamplesPerMinute = 2;
    ds.add(reading(98, null, 10, 30));
    ds.add(reading(96, 60, 10, 31));
    const result = ds.flush();
    const pulseSamples = result.filter((r) => r.metricType === "PulseRate");
    assert.equal(pulseSamples.length, 0);
  });

  it("flush empties buffer", () => {
    const ds = new LiveDownsampler();
    ds.minimumSamplesPerMinute = 1;
    ds.add(reading(98, 60));
    assert.ok(ds.flush().length > 0);
    assert.equal(ds.flush().length, 0);
  });
});
