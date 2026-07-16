package com.groundeffectsoftware.emaysleepo2

// ---- Types ----

/**
 * A single physiological reading from the EMAY SleepO2.
 * Both spo2 and pulse are nullable — the device can report one
 * without the other when a finger is partially on/off.
 */
data class EMAYReading(
    val spo2: Int?,       // Oxygen saturation percent (0–100)
    val pulse: Int?,      // Pulse rate in bpm
    val timestamp: Long   // System.currentTimeMillis()
)

/** A finalized per-minute mean sample. */
data class MinuteSample(
    val minuteStart: Long,
    val metricType: String, // "SpO2" or "PulseRate"
    val value: Double,
    val unitString: String  // "%" or "count/min"
)

/** Connection/streaming state. */
enum class EMAYStatus {
    Idle, Scanning, Connecting, Streaming,
    BluetoothOff, BluetoothUnauthorized, BluetoothUnsupported, Failed;

    val isActive: Boolean
        get() = this == Scanning || this == Connecting || this == Streaming
}

/**
 * Best-effort reason the client entered [EMAYStatus.Failed].
 *
 * Only meaningful while `status == EMAYStatus.Failed`; otherwise it is [None].
 * Read it via `EMAYClient.failureReason`.
 *
 * Note on [NotFound]: the SleepO2 is single-connection and stops advertising
 * while connected to another central, so a device that is "connected to another
 * app" is radio-indistinguishable from one that is off or out of range. We
 * therefore cannot report a definitive "busy" — the message enumerates the
 * possibilities honestly.
 */
enum class FailureReason(val message: String) {
    None(""),
    NotFound("Device not found — it may be off, out of range, or connected to another app (the SleepO2 allows only one connection at a time)."),
    ConnectionFailed("Found the device but the connection failed — it may have moved out of range or been taken by another app mid-connect.");
}
