/*
 * EMAY SleepO2 BLE Protocol — C# reference implementation
 * Copyright (c) 2026 Ground Effect Software, LLC
 * MIT License
 */

namespace GroundEffectSoftware.EMAYSleepO2;

/// <summary>A single physiological reading from the EMAY SleepO2.</summary>
public record EMAYReading(int? Spo2, int? Pulse, double TimestampSecs);

/// <summary>A finalized per-minute mean sample.</summary>
public record MinuteSample(double MinuteStartSecs, string MetricType, double Value, string UnitString);
