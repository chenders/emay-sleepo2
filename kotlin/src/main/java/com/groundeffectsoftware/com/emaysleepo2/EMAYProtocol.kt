package com.groundeffectsoftware.com.emaysleepo2

// ---- EMAY SleepO2 BLE Protocol ----

object EMAYProtocol {
    // BLE identifiers
    const val SERVICE_UUID = "0000ff12-0000-1000-8000-00805f9b34fb"
    const val WRITE_UUID = "0000ff01-0000-1000-8000-00805f9b34fb"
    const val NOTIFY_UUID = "0000ff02-0000-1000-8000-00805f9b34fb"
    const val NAME_PREFIX = "SleepO2"

    // Commands (payload + checksum)
    val HELLO: ByteArray = byteArrayOf(0x89.toByte(), 0x09.toByte())
    val DEVICE_STATE: ByteArray = byteArrayOf(0x8E.toByte(), 0x05.toByte(), 0x13.toByte())
    val START_REALTIME: ByteArray = byteArrayOf(0x9B.toByte(), 0x01.toByte(), 0x1C.toByte())
    val STOP_REALTIME: ByteArray = byteArrayOf(0x9B.toByte(), 0x7F.toByte(), 0x1A.toByte())
    val GET_BATTERY: ByteArray = byteArrayOf(0x86.toByte(), 0x06.toByte())
    val HEARTBEAT: ByteArray = byteArrayOf(0x9A.toByte(), 0x1A.toByte())

    val START_SEQUENCE = listOf(HELLO, DEVICE_STATE, START_REALTIME, GET_BATTERY)

    // Data frame constants
    private const val FRAME_LENGTH = 8
    private val FRAME_HEADER = byteArrayOf(0xEB.toByte(), 0x01.toByte(), 0x05.toByte())
    private val FRAME_TRAILER = byteArrayOf(0x7F.toByte(), 0x00.toByte())
    private val SENTINEL_VALUES = setOf(0x00.toByte(), 0xFF.toByte())

    // Plausibility bounds
    private const val PULSE_MIN = 30
    private const val PULSE_MAX = 220
    private const val SPO2_MIN = 0
    private const val SPO2_MAX = 100

    /** Compute EMAY checksum: sum(payload) & 0x7F */
    fun checksum(payload: ByteArray): Byte {
        val sum = payload.fold(0) { acc, b -> acc + (b.toInt() and 0xFF) }
        return (sum and 0x7F).toByte()
    }

    /** Build a full command frame. */
    fun command(payload: ByteArray): ByteArray = payload + checksum(payload)

    /**
     * Attempt to parse an 8-byte raw frame. Returns an EMAYReading on
     * success, null if any validation check fails.
     */
    fun parseReading(raw: ByteArray): EMAYReading? {
        if (raw.size != FRAME_LENGTH) return null
        if (raw[0] != FRAME_HEADER[0] || raw[1] != FRAME_HEADER[1] || raw[2] != FRAME_HEADER[2]) return null
        if (raw[5] != FRAME_TRAILER[0] || raw[6] != FRAME_TRAILER[1]) return null

        val cks = raw.take(7).fold(0) { acc, b -> acc + (b.toInt() and 0xFF) } and 0x7F
        if ((raw[7].toInt() and 0xFF) != cks) return null

        val rawPR = raw[3].toInt() and 0xFF
        val rawSpO2 = raw[4].toInt() and 0xFF

        val pulse: Int? = if (rawPR in SENTINEL_VALUES.map { it.toInt() and 0xFF }) null else rawPR
        val spo2: Int? = if (rawSpO2 in SENTINEL_VALUES.map { it.toInt() and 0xFF }) null else rawSpO2

        if (pulse != null && (pulse < PULSE_MIN || pulse > PULSE_MAX)) return null
        if (spo2 != null && (spo2 < SPO2_MIN || spo2 > SPO2_MAX)) return null

        return EMAYReading(spo2 = spo2, pulse = pulse, timestamp = System.currentTimeMillis())
    }
}
