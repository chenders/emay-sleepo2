package com.anxietywatch.emaysleepo2

import java.util.Calendar

/** Per-minute downsampler for the ~1 Hz EMAY stream. */
class EMAYLiveDownsampler(
    var minimumSamplesPerMinute: Int = 2
) {
    private val spo2Values = mutableListOf<Double>()
    private val pulseValues = mutableListOf<Double>()
    private var currentMinute: Long? = null
    private val calendar = Calendar.getInstance()

    private fun startOfMinute(ts: Long): Long {
        calendar.timeInMillis = ts
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        return calendar.timeInMillis
    }

    /** Feed a new reading. Returns finalized MinuteSamples. */
    fun add(reading: EMAYReading): List<MinuteSample> {
        val minute = startOfMinute(reading.timestamp)
        val flushed = mutableListOf<MinuteSample>()

        if (currentMinute != null && minute != currentMinute) {
            flushed.addAll(finalize())
        }

        currentMinute = minute
        reading.spo2?.let { spo2Values.add(it.toDouble()) }
        reading.pulse?.let { pulseValues.add(it.toDouble()) }
        return flushed
    }

    /** Finalize and return the current partial bucket. */
    fun flush(): List<MinuteSample> {
        val result = finalize()
        currentMinute = null
        return result
    }

    private fun finalize(): List<MinuteSample> {
        val minute = currentMinute ?: return emptyList()
        val samples = mutableListOf<MinuteSample>()

        if (spo2Values.size >= minimumSamplesPerMinute) {
            val mean = spo2Values.sum() / spo2Values.size
            samples.add(MinuteSample(minute, "SpO2", mean / 100.0, "%"))
        }

        if (pulseValues.size >= minimumSamplesPerMinute) {
            val mean = pulseValues.sum() / pulseValues.size
            samples.add(MinuteSample(minute, "PulseRate", mean, "count/min"))
        }

        spo2Values.clear()
        pulseValues.clear()
        return samples
    }
}
