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
