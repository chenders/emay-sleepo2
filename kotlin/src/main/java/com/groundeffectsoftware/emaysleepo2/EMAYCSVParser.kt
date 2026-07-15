package com.groundeffectsoftware.emaysleepo2

import java.io.File
import java.text.SimpleDateFormat
import java.util.*

/**
 * DST fall-back fold corrector for EMAY CSV timestamps.
 */
class DSTFoldCorrector(private val timeZone: TimeZone = TimeZone.getDefault()) {
    private var offset: Long = 0
    private var previous: Long? = null

    fun corrected(parsed: Date): Date {
        val ms = parsed.time
        if (previous == null) { previous = ms; return parsed }

        if (offset > 0 && ms >= previous!!) { offset = 0 }

        var candidate = ms + offset
        val delta = candidate - previous!!

        if (delta < -5000 && delta >= -7200000 && clocksFellBack(Date(previous!!))) {
            offset += 3600000
            candidate = ms + offset
        }

        previous = candidate
        return Date(candidate)
    }

    private fun clocksFellBack(instant: Date): Boolean {
        return timeZone.inDaylightTime(instant) &&
            !timeZone.inDaylightTime(Date(instant.time - 3600000))
    }
}

/**
 * Parse EMAY CSV content.
 * Returns a CSVResult with readings and warnings. Throws if no data rows.
 */
fun parseCSV(content: String, timeZone: TimeZone = TimeZone.getDefault(),
             correctDST: Boolean = true): CSVResult {
    val lines = content.lines().map { it.trim() }.filter { it.isNotEmpty() }
    if (lines.size <= 1) throw IllegalArgumentException("CSV file contains no data rows")

    val readings = mutableListOf<EMAYReading>()
    val warnings = mutableListOf<String>()
    val formatter = SimpleDateFormat("M/d/yyyy h:mm:ss a", Locale.US)
    formatter.timeZone = timeZone
    val corrector = if (correctDST) DSTFoldCorrector(timeZone) else null

    for (i in 1 until lines.size) {
        val rowNum = i + 1
        val fields = lines[i].split(",").map { it.trim() }
        if (fields.size < 2) {
            warnings.add("Row $rowNum: skipping — expected at least date,time columns")
            continue
        }

        val dateStr = "${fields[0]} ${fields[1]}"
        val parsed = try {
            formatter.parse(dateStr)
        } catch (e: Exception) {
            warnings.add("Row $rowNum: skipping — invalid date/time '$dateStr'")
            continue
        }
        val timestamp = corrector?.corrected(parsed!!) ?: parsed!!

        val spo2 = if (fields.size > 2 && fields[2].isNotEmpty()) fields[2].toIntOrNull() else null
        val pulse = if (fields.size > 3 && fields[3].isNotEmpty()) fields[3].toIntOrNull() else null

        readings.add(EMAYReading(spo2 = spo2, pulse = pulse, timestamp = timestamp.time))
    }

    return CSVResult(readings, warnings)
}

/** Parse an EMAY CSV file from disk. */
fun parseCSVFile(path: String, timeZone: TimeZone = TimeZone.getDefault(),
                 correctDST: Boolean = true): CSVResult {
    val content = File(path).readText()
    return parseCSV(content, timeZone, correctDST)
}
