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

/// <summary>
/// Best-effort reason a session failed. Meaningful only for a failed session;
/// otherwise <see cref="None"/>. Read it via <c>EMAYBLEClient.FailureReason</c>
/// and see <see cref="FailureReasonExtensions.Message"/> for user-facing text.
///
/// Note on <see cref="NotFound"/>: the SleepO2 is single-connection and stops
/// advertising while connected to another central, so a device "connected to
/// another app" is radio-indistinguishable from one that is off or out of range.
/// We therefore cannot report a definitive "busy" — the message enumerates the
/// possibilities honestly.
/// </summary>
public enum FailureReason
{
    None,
    NotFound,
    ConnectionFailed,
}

/// <summary>Human-readable explanations for <see cref="FailureReason"/> values.</summary>
public static class FailureReasonExtensions
{
    /// <summary>A user-facing explanation of a <see cref="FailureReason"/>.</summary>
    public static string Message(this FailureReason reason) => reason switch
    {
        FailureReason.NotFound =>
            "Device not found — it may be off, out of range, or connected to another app (the SleepO2 allows only one connection at a time).",
        FailureReason.ConnectionFailed =>
            "Found the device but the connection failed — it may have moved out of range or been taken by another app mid-connect.",
        _ => "",
    };
}
