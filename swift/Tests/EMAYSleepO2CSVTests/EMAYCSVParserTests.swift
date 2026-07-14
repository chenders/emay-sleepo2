import Testing
import Foundation
@testable import EMAYSleepO2CSV

struct EMAYCSVParserTests {

    @Test("parses valid CSV with readings and sensor gaps")
    func validCSV() throws {
        let csv = """
Date,Time,SpO2(%),PR(bpm)
5/8/2026,4:46:58 PM,98,52
5/8/2026,4:47:00 PM,,58
5/8/2026,4:47:01 PM,97,55
"""
        EMAYCSVParser.correctDSTFold = false
        let result = try EMAYCSVParser.parse(content: csv)
        #expect(result.readings.count == 3)

        // First: both values present
        #expect(result.readings[0].spo2 == 98)
        #expect(result.readings[0].pulse == 52)

        // Second: blank SpO2 → nil
        #expect(result.readings[1].spo2 == nil)
        #expect(result.readings[1].pulse == 58)

        // Third: both present
        #expect(result.readings[2].spo2 == 97)
        #expect(result.readings[2].pulse == 55)
    }

    @Test("empty CSV throws")
    func emptyCSV() {
        #expect(throws: EMAYCSVParser.Error.self) {
            try EMAYCSVParser.parse(content: "Date,Time,SpO2(%),PR(bpm)")
        }
    }

    @Test("invalid date generates warning but doesn't fail parse")
    func invalidDate() throws {
        EMAYCSVParser.correctDSTFold = false
        let csv = """
Date,Time,SpO2(%),PR(bpm)
bad,data,99,50
5/8/2026,4:47:00 PM,98,52
"""
        let result = try EMAYCSVParser.parse(content: csv)
        #expect(result.warnings.count == 1)
        #expect(result.warnings[0].contains("invalid date"))
        #expect(result.readings.count == 1)
        #expect(result.readings[0].spo2 == 98)
    }

    @Test("missing columns generate warning")
    func missingColumns() throws {
        EMAYCSVParser.correctDSTFold = false
        let csv = """
Date,Time,SpO2(%),PR(bpm)
5/8/2026
"""
        let result = try EMAYCSVParser.parse(content: csv)
        #expect(result.warnings.count >= 1)
        #expect(result.readings.isEmpty)
    }

    @Test("DST fold corrector detects backward jump with transition")
    func dstFoldCorrection() {
        // Get a timezone that observes DST
        var tz = TimeZone(identifier: "America/New_York")!

        // Find the fall-back transition date
        // Nov 1, 2026 2:00 AM EDT → 1:00 AM EST
        var corrector = DSTFoldCorrector(timeZone: tz)

        // Simulate: 1:30 AM EDT (before transition) → 1:05 AM EST (after transition)
        // This would appear as a backward jump in naive wall-clock parsing

        // We need to find an actual DST transition.
        // For testing, test the behavior of the corrector with known fold dates
        // Fall back 2026: November 1, 2026 at 2:00 AM
        // Before: 1:55 AM EDT = UTC-4
        // After:  1:05 AM EST = UTC-5

        // These two times, parsed naively, would be 50 minutes apart FORWARD
        // in wall clock (1:55 → 1:05 = -50 min backward jump = fold)
        let before = dateInNY(month: 11, day: 1, hour: 1, minute: 55)
        let after = dateInNY(month: 11, day: 1, hour: 1, minute: 5)

        let c1 = corrector.corrected(before)
        let c2 = corrector.corrected(after)

        // c2 should be ~3600 seconds ahead of c1 (monotonic)
        // Without correction, after.timeIntervalSince(before) ≈ -3000
        let delta = c2.timeIntervalSince(c1)
        #expect(delta > 0, "DST fold should produce monotonic timestamps, got delta=\(delta)")
    }

    @Test("DST fold corrector ignores backward jumps outside fold window")
    func dstFoldIgnoresLargeJumps() {
        let tz = TimeZone(identifier: "America/New_York")!
        var corrector = DSTFoldCorrector(timeZone: tz)

        // 3 hour backward jump — too large for a fold
        let t1 = Date()
        let t2 = t1.addingTimeInterval(-3 * 3600)

        let c1 = corrector.corrected(t1)
        let c2 = corrector.corrected(t2)
        // Should NOT be fold-corrected → c2 < c1
        #expect(c2 < c1)
    }

    private func dateInNY(month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var tz = TimeZone(identifier: "America/New_York")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var comps = DateComponents()
        comps.year = 2026
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return cal.date(from: comps)!
    }
}
