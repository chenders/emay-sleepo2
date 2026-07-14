/**
 * Per-minute downsampler for the ~1 Hz EMAY stream.
 */
import { Reading, MinuteSample } from "./types.js";

function startOfMinute(d: Date): Date {
  const m = new Date(d);
  m.setSeconds(0, 0);
  return m;
}

export class LiveDownsampler {
  minimumSamplesPerMinute: number = 2;

  private spo2Values: number[] = [];
  private pulseValues: number[] = [];
  private currentMinute: Date | null = null;

  /** Feed a new reading. Returns finalized MinuteSamples (0 or 2 per call). */
  add(reading: Reading): MinuteSample[] {
    const minute = startOfMinute(reading.timestamp);
    const flushed: MinuteSample[] = [];

    if (
      this.currentMinute !== null &&
      minute.getTime() !== this.currentMinute.getTime()
    ) {
      flushed.push(...this.finalize());
    }

    this.currentMinute = minute;
    if (reading.spo2 !== null) this.spo2Values.push(reading.spo2);
    if (reading.pulse !== null) this.pulseValues.push(reading.pulse);
    return flushed;
  }

  /** Finalize and return the current partial bucket. */
  flush(): MinuteSample[] {
    const result = this.finalize();
    this.currentMinute = null;
    this.spo2Values = [];
    this.pulseValues = [];
    return result;
  }

  private finalize(): MinuteSample[] {
    if (this.currentMinute === null) return [];
    const samples: MinuteSample[] = [];

    if (this.spo2Values.length >= this.minimumSamplesPerMinute) {
      const mean =
        this.spo2Values.reduce((a, b) => a + b, 0) / this.spo2Values.length;
      samples.push({
        minuteStart: this.currentMinute,
        metricType: "SpO2",
        value: mean / 100,
        unitString: "%",
      });
    }

    if (this.pulseValues.length >= this.minimumSamplesPerMinute) {
      const mean =
        this.pulseValues.reduce((a, b) => a + b, 0) / this.pulseValues.length;
      samples.push({
        minuteStart: this.currentMinute,
        metricType: "PulseRate",
        value: mean,
        unitString: "count/min",
      });
    }

    return samples;
  }
}
