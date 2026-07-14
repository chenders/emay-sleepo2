/**
 * Tests for EMAY CSV parser (Node.js).
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { parseCSV } from "../src/csv-parser.js";

describe("parseCSV", () => {
  it("parses valid CSV", () => {
    const csv = "Date,Time,SpO2(%),PR(bpm)\n5/8/2026,4:46:58 PM,98,52\n5/8/2026,4:47:00 PM,,58";
    const result = parseCSV(csv, undefined, false);
    assert.equal(result.readings.length, 2);
    assert.equal(result.readings[0].spo2, 98);
    assert.equal(result.readings[0].pulse, 52);
    assert.equal(result.readings[1].spo2, null);
    assert.equal(result.readings[1].pulse, 58);
  });

  it("empty CSV throws", () => {
    assert.throws(() => parseCSV("Date,Time,SpO2(%),PR(bpm)"));
  });

  it("invalid date warns", () => {
    const csv = "Date,Time,SpO2(%),PR(bpm)\nbad,data,99,50\n5/8/2026,4:47:00 PM,98,52";
    const result = parseCSV(csv, undefined, false);
    assert.ok(result.warnings.length >= 1);
    assert.equal(result.readings.length, 1);
    assert.equal(result.readings[0].spo2, 98);
  });
});
