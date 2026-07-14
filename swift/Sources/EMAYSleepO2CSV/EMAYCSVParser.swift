import Foundation

// MARK: - CSV Parser

/// Parses EMAY SleepO2 CSV export files.
///
/// The device's companion app exports sleep session data as CSV with columns:
/// `Date,Time,SpO2(%),PR(bpm)`. No BLE hardware is required — this is a file
/// parser only.
///
/// ## Example
///
/// ```swift
/// let result = try EMAYCSVParser.parse(content: csvString)
/// print("Parsed \(result.readings.count) readings")
/// for warning in result.warnings { print("Warning: \(warning)") }
/// ```
public enum EMAYCSVParser {

    public struct Result: Sendable {
        public let readings: [EMAYReading]
        public let warnings: [String]
    }

    /// Error thrown when the entire parse fails.
    public enum Error: Swift.Error, LocalizedError {
        case noData
        case invalidFormat(String)

        public var errorDescription: String? {
            switch self {
            case .noData:
                return "CSV file contains no data rows"
            case .invalidFormat(let detail):
                return "Invalid CSV format: \(detail)"
            }
        }
    }

    // MARK: - Configuration

    /// Timezone for interpreting wall-clock timestamps. Default: system local.
    public nonisolated(unsafe) static var timezone: TimeZone = .current

    /// Whether to correct timestamps across DST fall-back folds.
    /// When true, the repeated hour during clocks-back is detected and
    /// corrected so samples arrive in physical (monotonic) order.
    /// Default: true.
    public nonisolated(unsafe) static var correctDSTFold: Bool = true

    // MARK: - Public entry points

    /// Parse EMAY CSV content from a pre-read string.
    public static func parse(content: String) throws -> Result {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard lines.count > 1 else { throw Error.noData }
        return try parseDataLines(Array(lines.dropFirst()))
    }

    /// Parse EMAY CSV from a file URL. Handles security-scoped resources.
    public static func parseFile(at url: URL) throws -> Result {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer { if isSecurityScoped { url.stopAccessingSecurityScopedResource() } }
        let content = try String(contentsOf: url, encoding: .utf8)
        return try parse(content: content)
    }

    // MARK: - Internal parsing

    private static func parseDataLines(_ lines: [String]) throws -> Result {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy h:mm:ss a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone

        var readings: [EMAYReading] = []
        var warnings: [String] = []
        var foldCorrector = DSTFoldCorrector(timeZone: timezone)

        for (index, line) in lines.enumerated() {
            let rowNumber = index + 2  // 1-indexed, header is row 1
            let fields = line.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }

            guard fields.count >= 2 else {
                warnings.append("Row \(rowNumber): skipping — expected at least date,time columns")
                continue
            }

            let dateTimeStr = "\(fields[0]) \(fields[1])"
            guard let parsed = formatter.date(from: dateTimeStr) else {
                warnings.append("Row \(rowNumber): skipping — invalid date/time '\(dateTimeStr)'")
                continue
            }

            let timestamp = correctDSTFold
                ? foldCorrector.corrected(parsed)
                : parsed

            let spo2Str = fields.count > 2 ? fields[2] : ""
            let prStr = fields.count > 3 ? fields[3] : ""

            let spo2: Int? = spo2Str.isEmpty ? nil : Int(spo2Str)
            let pulse: Int? = prStr.isEmpty ? nil : Int(prStr)

            readings.append(EMAYReading(spo2: spo2, pulse: pulse, timestamp: timestamp))
        }

        return Result(readings: readings, warnings: warnings)
    }
}

// MARK: - DST Fold Corrector

/// Restores physical (monotonic) time across DST fall-back ("fall back")
/// transitions in EMAY CSV files.
///
/// Without correction, the repeated 1:00–2:00 AM hour produces duplicate
/// wall-clock timestamps that collide in deduplication — silently erasing
/// an hour of real data.
///
/// **Algorithm**: When a backward jump of 5–7200 seconds is detected between
/// consecutive timestamps, cross-check whether the parse timezone actually
/// transitioned clocks back within ±2 hours of the jump. If yes, add 3600
/// seconds of correction (accumulating across multiple folds if needed).
/// A backward jump with NO nearby DST transition (device-clock resync or
/// manual time change) is left untouched — falsifying monotonicity would
/// shift the entire night's timestamps, which is worse than reporting the
/// discontinuity honestly.
public struct DSTFoldCorrector: Sendable {
    /// Backward jumps at or below this are noise or duplicate rows, not a fold.
    public static let minimumBackwardJump: TimeInterval = 5
    /// Backward jumps beyond this can't be a DST fold (folds are at most 1h).
    public static let maximumBackwardJump: TimeInterval = 2 * 3600
    /// Every real-world DST fold repeats exactly one hour.
    public static let foldDuration: TimeInterval = 3600

    private var offset: TimeInterval = 0
    private var previousCorrected: Date?
    private let timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    /// Feed naively parsed timestamps in file order; returns the
    /// fold-corrected physical timestamp.
    public mutating func corrected(_ parsed: Date) -> Date {
        guard let previous = previousCorrected else {
            previousCorrected = parsed
            return parsed
        }

        // Once the naive parse catches back up to the corrected timeline,
        // wall clock has passed the ambiguous hour — stop compensating.
        if offset > 0 && parsed >= previous {
            offset = 0
        }

        var candidate = parsed.addingTimeInterval(offset)
        let delta = candidate.timeIntervalSince(previous)

        if delta < -Self.minimumBackwardJump,
           delta >= -Self.maximumBackwardJump,
           clocksFellBackNear(previous) {
            offset += Self.foldDuration
            candidate = parsed.addingTimeInterval(offset)
        }

        previousCorrected = candidate
        return candidate
    }

    /// True only when the parse timezone actually sets clocks BACK within
    /// ±2h of `instant`. A device-clock resync or manually adjusted time
    /// regresses the wall clock with no transition anywhere near — left
    /// untouched.
    private func clocksFellBackNear(_ instant: Date) -> Bool {
        let searchStart = instant.addingTimeInterval(-Self.maximumBackwardJump)
        guard let transition = timeZone.nextDaylightSavingTimeTransition(after: searchStart),
              transition <= instant.addingTimeInterval(Self.maximumBackwardJump) else {
            return false
        }
        let before = timeZone.secondsFromGMT(for: transition.addingTimeInterval(-1))
        let after = timeZone.secondsFromGMT(for: transition)
        return after < before
    }
}
