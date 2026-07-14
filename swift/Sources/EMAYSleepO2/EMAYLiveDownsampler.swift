import Foundation

// MARK: - Downsampler

/// Buffers the ~1 Hz EMAY stream into per-minute mean samples.
///
/// The device produces readings at approximately 1 Hz while a finger is
/// detected. This downsampler buckets those readings by wall-clock minute
/// and emits a single mean value per metric per minute when the bucket
/// finalizes.
///
/// Thread-safe: all methods can be called from any thread (the internal
/// buffer is accessed under a lock), though the EMAYClient typically drives
/// it from a single BLE callback queue.
public final class EMAYLiveDownsampler: @unchecked Sendable {
    /// A finalized per-minute sample ready for persistence or display.
    public struct MinuteSample: Sendable, Equatable {
        public let minuteStart: Date
        public let metricType: String
        public let value: Double
        public let unitString: String

        public init(minuteStart: Date, metricType: String, value: Double, unitString: String) {
            self.minuteStart = minuteStart
            self.metricType = metricType
            self.value = value
            self.unitString = unitString
        }
    }

    /// Minimum number of readings in a minute bucket before it is emitted.
    /// Below this count, the partial bucket is dropped (a single outlier
    /// reading doesn't constitute a valid minute of data).
    public var minimumSamplesPerMinute: Int = 2

    private let lock = NSLock()
    private var spo2Values: [Double] = []
    private var pulseValues: [Double] = []
    private var currentMinute: Date?

    public init() {}

    /// Feed a new reading into the current minute bucket.
    ///
    /// If `reading` starts a new wall-clock minute, the previous bucket is
    /// finalized and flushed before this reading is added to the new bucket.
    ///
    /// Returns any finalized `MinuteSample`s — typically zero or two (one
    /// SpO₂ mean, one pulse mean), but can be empty if the old bucket was
    /// below the minimum sample count.
    @discardableResult
    public func add(_ reading: EMAYReading) -> [MinuteSample] {
        lock.lock()
        defer { lock.unlock() }

        let minute = reading.timestamp.startOfMinute
        var flushed: [MinuteSample] = []

        if let current = currentMinute, minute != current {
            flushed = finalizeLocked()
        }

        currentMinute = minute
        if let spo2 = reading.spo2 { spo2Values.append(Double(spo2)) }
        if let pulse = reading.pulse { pulseValues.append(Double(pulse)) }
        return flushed
    }

    /// Finalize and return the current partial bucket, regardless of sample
    /// count (the caller manages the minimum-sample gate if desired).
    ///
    /// Use this at session teardown to capture the final partial minute; at
    /// transient disconnects, prefer keeping the bucket open so a same-minute
    /// reconnect continues accumulating into one correctly-weighted mean.
    @discardableResult
    public func flush() -> [MinuteSample] {
        lock.lock()
        defer { lock.unlock() }
        return finalizeLocked()
    }

    /// Finalize current bucket under lock. Caller holds the lock.
    private func finalizeLocked() -> [MinuteSample] {
        guard let minute = currentMinute else { return [] }
        defer {
            spo2Values.removeAll(keepingCapacity: true)
            pulseValues.removeAll(keepingCapacity: true)
            currentMinute = nil
        }

        var samples: [MinuteSample] = []

        if spo2Values.count >= minimumSamplesPerMinute {
            let mean = spo2Values.reduce(0, +) / Double(spo2Values.count)
            samples.append(MinuteSample(
                minuteStart: minute,
                metricType: "SpO2",
                value: mean / 100.0,  // fraction 0–1 for storage consistency
                unitString: "%"
            ))
        }

        if pulseValues.count >= minimumSamplesPerMinute {
            let mean = pulseValues.reduce(0, +) / Double(pulseValues.count)
            samples.append(MinuteSample(
                minuteStart: minute,
                metricType: "PulseRate",
                value: mean,
                unitString: "count/min"
            ))
        }

        return samples
    }
}

// MARK: - Date helpers

extension Date {
    /// Truncate to the start of this wall-clock minute.
    var startOfMinute: Date {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        return Calendar.current.date(from: components) ?? self
    }
}
