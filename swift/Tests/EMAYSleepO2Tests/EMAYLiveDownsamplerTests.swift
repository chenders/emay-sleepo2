import Testing
import Foundation
@testable import EMAYSleepO2

struct EMAYLiveDownsamplerTests {

    @Test("single reading below minimum produces no output")
    func belowMinimum() {
        let ds = EMAYLiveDownsampler()
        ds.minimumSamplesPerMinute = 2
        let reading = EMAYReading(spo2: 98, pulse: 60, timestamp: date(minute: 10, second: 30))
        let result = ds.add(reading)
        #expect(result.isEmpty)
    }

    @Test("two readings in same minute produce a finalized mean")
    func twoSamples() {
        let ds = EMAYLiveDownsampler()
        ds.minimumSamplesPerMinute = 2
        _ = ds.add(EMAYReading(spo2: 98, pulse: 60, timestamp: date(minute: 10, second: 30)))
        _ = ds.add(EMAYReading(spo2: 96, pulse: 62, timestamp: date(minute: 10, second: 31)))
        let result = ds.flush()
        #expect(result.count == 2)

        let spo2Sample = result.first { $0.metricType == "SpO2" }
        #expect(spo2Sample != nil)
        #expect(spo2Sample!.value == 0.97)  // (98+96)/2 = 97, /100 = 0.97

        let pulseSample = result.first { $0.metricType == "PulseRate" }
        #expect(pulseSample != nil)
        #expect(pulseSample!.value == 61.0)  // (60+62)/2 = 61
    }

    @Test("crossing minute boundary flushes previous minute")
    func minuteBoundary() {
        let ds = EMAYLiveDownsampler()
        ds.minimumSamplesPerMinute = 1  // trigger on single reading

        _ = ds.add(EMAYReading(spo2: 98, pulse: nil, timestamp: date(minute: 10, second: 30)))
        let flushed = ds.add(EMAYReading(spo2: 95, pulse: 60, timestamp: date(minute: 11, second: 1)))

        #expect(flushed.count == 1)
        #expect(flushed[0].metricType == "SpO2")
        #expect(flushed[0].value == 0.98)
    }

    @Test("partial minute below minimum is discarded at boundary")
    func boundaryBelowMinimum() {
        let ds = EMAYLiveDownsampler()
        ds.minimumSamplesPerMinute = 5
        _ = ds.add(EMAYReading(spo2: 98, pulse: 60, timestamp: date(minute: 10, second: 30)))
        let flushed = ds.add(EMAYReading(spo2: 95, pulse: 62, timestamp: date(minute: 11, second: 1)))
        // Only 1 sample in minute 10, below min count → discarded
        #expect(flushed.isEmpty)
    }

    @Test("nil metrics don't contribute to means")
    func nilMetricsExcluded() {
        let ds = EMAYLiveDownsampler()
        ds.minimumSamplesPerMinute = 2
        // pulse nil on first reading
        _ = ds.add(EMAYReading(spo2: 98, pulse: nil, timestamp: date(minute: 10, second: 30)))
        _ = ds.add(EMAYReading(spo2: 96, pulse: 60, timestamp: date(minute: 10, second: 31)))
        let result = ds.flush()

        let pulseSample = result.first { $0.metricType == "PulseRate" }
        // Only 1 pulse sample (< min of 2) → no pulse output
        #expect(pulseSample == nil)

        let spo2Sample = result.first { $0.metricType == "SpO2" }
        #expect(spo2Sample != nil)
        #expect(spo2Sample!.value == 0.97)  // (98+96)/2 / 100
    }

    @Test("flush empties the buffer")
    func flushEmpties() {
        let ds = EMAYLiveDownsampler()
        ds.minimumSamplesPerMinute = 1
        _ = ds.add(EMAYReading(spo2: 98, pulse: 60, timestamp: date(minute: 10, second: 30)))
        _ = ds.flush()
        // Second flush should produce nothing
        let empty = ds.flush()
        #expect(empty.isEmpty)
    }

    @Test("SpO2 mean is stored as fraction 0–1")
    func spo2AsFraction() {
        let ds = EMAYLiveDownsampler()
        ds.minimumSamplesPerMinute = 1
        _ = ds.add(EMAYReading(spo2: 50, pulse: 60, timestamp: date(minute: 10, second: 30)))
        let result = ds.flush()
        let spo2Sample = result.first { $0.metricType == "SpO2" }
        #expect(spo2Sample!.value == 0.50)
        #expect(spo2Sample!.unitString == "%")
    }

    @Test("pulse mean is raw bpm")
    func pulseUnit() {
        let ds = EMAYLiveDownsampler()
        ds.minimumSamplesPerMinute = 1
        _ = ds.add(EMAYReading(spo2: 98, pulse: 75, timestamp: date(minute: 10, second: 30)))
        let result = ds.flush()
        let pulseSample = result.first { $0.metricType == "PulseRate" }
        #expect(pulseSample!.value == 75.0)
        #expect(pulseSample!.unitString == "count/min")
    }

    // MARK: - Helpers

    private func date(minute: Int, second: Int) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour], from: Date())
        comps.minute = minute
        comps.second = second
        return cal.date(from: comps)!
    }
}
