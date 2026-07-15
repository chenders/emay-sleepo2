/*
 * EMAY SleepO2 BLE Protocol — C# reference implementation
 * Copyright (c) 2026 Ground Effect Software, LLC
 * MIT License
 */

namespace GroundEffectSoftware.EMAYSleepO2;

/// <summary>EMAY SleepO2 BLE protocol: identifiers, commands, checksum, and frame parsing.</summary>
public static class EMAYProtocol
{
    // ---- BLE identifiers ----
    public const string ServiceUuid = "0000ff12-0000-1000-8000-00805f9b34fb";
    public const string WriteUuid   = "0000ff01-0000-1000-8000-00805f9b34fb";
    public const string NotifyUuid  = "0000ff02-0000-1000-8000-00805f9b34fb";
    public const string NamePrefix  = "SleepO2";

    // ---- Pre-built commands ----
    public static readonly byte[] Hello        = { 0x89, 0x09 };
    public static readonly byte[] DeviceState  = { 0x8E, 0x05, 0x13 };
    public static readonly byte[] StartRealtime = { 0x9B, 0x01, 0x1C };
    public static readonly byte[] StopRealtime  = { 0x9B, 0x7F, 0x1A };
    public static readonly byte[] GetBattery   = { 0x86, 0x06 };
    public static readonly byte[] Heartbeat    = { 0x9A, 0x1A };

    public static readonly byte[][] StartSequence = { Hello, DeviceState, StartRealtime, GetBattery };

    // ---- Data frame constants ----
    private const int FrameLength = 8;
    private static readonly byte[] FrameHeader  = { 0xEB, 0x01, 0x05 };
    private static readonly byte[] FrameTrailer = { 0x7F, 0x00 };
    private static readonly HashSet<byte> SentinelValues = new() { 0x00, 0xFF };

    // ---- Plausibility bounds ----
    private const int PulseMin = 30;
    private const int PulseMax = 220;
    private const int Spo2Min  = 0;
    private const int Spo2Max  = 100;

    /// <summary>Compute EMAY checksum: sum(payload) &amp; 0x7F.</summary>
    public static byte Checksum(byte[] payload)
    {
        int sum = 0;
        foreach (var b in payload) sum += b;
        return (byte)(sum & 0x7F);
    }

    /// <summary>Build a full command: payload + checksum.</summary>
    public static byte[] Command(byte[] payload)
    {
        var cmd = new byte[payload.Length + 1];
        Array.Copy(payload, cmd, payload.Length);
        cmd[payload.Length] = Checksum(payload);
        return cmd;
    }

    /// <summary>Attempt to parse an 8-byte raw frame. Returns null on failure.</summary>
    public static EMAYReading? ParseReading(byte[] raw)
    {
        if (raw == null || raw.Length != FrameLength) return null;
        if (raw[0] != FrameHeader[0] || raw[1] != FrameHeader[1] || raw[2] != FrameHeader[2]) return null;
        if (raw[5] != FrameTrailer[0] || raw[6] != FrameTrailer[1]) return null;

        int sum = 0;
        for (int i = 0; i < 7; i++) sum += raw[i];
        if (raw[7] != (byte)(sum & 0x7F)) return null;

        byte rawPR   = raw[3];
        byte rawSpO2 = raw[4];

        int? pulse = SentinelValues.Contains(rawPR)   ? null : rawPR;
        int? spo2  = SentinelValues.Contains(rawSpO2) ? null : rawSpO2;

        if (pulse.HasValue && (pulse < PulseMin || pulse > PulseMax)) return null;
        if (spo2.HasValue  && (spo2  < Spo2Min  || spo2  > Spo2Max))  return null;

        return new EMAYReading(spo2, pulse, DateTimeOffset.UtcNow.ToUnixTimeSeconds());
    }
}
