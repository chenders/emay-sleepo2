import Testing
import Foundation
@testable import EMAYSleepO2

struct EMAYProtocolTests {

    // MARK: - Checksum

    @Test("checksum produces correct 0x7F-masked values")
    func checksum() {
        // hello payload [0x89]: sum = 0x89 = 137, 137 & 0x7F = 9 → 0x09
        #expect(EMAYProtocol.checksum([0x89]) == 0x09)

        // heartbeat payload [0x9A]: sum = 154, 154 & 0x7F = 26 → 0x1A
        #expect(EMAYProtocol.checksum([0x9A]) == 0x1A)

        // startRealtime payload [0x9B, 0x01]: sum = 156, 156 & 0x7F = 28 → 0x1C
        #expect(EMAYProtocol.checksum([0x9B, 0x01]) == 0x1C)

        // deviceState payload [0x8E, 0x05]: sum = 147, 147 & 0x7F = 19 → 0x13
        #expect(EMAYProtocol.checksum([0x8E, 0x05]) == 0x13)

        // stopRealtime payload [0x9B, 0x7F]: sum = 282, 282 & 0x7F = 26 → 0x1A
        #expect(EMAYProtocol.checksum([0x9B, 0x7F]) == 0x1A)

        // getBattery payload [0x86]: sum = 134, 134 & 0x7F = 6 → 0x06
        #expect(EMAYProtocol.checksum([0x86]) == 0x06)
    }

    // MARK: - Command construction

    @Test("command appends checksum to payload")
    func commandConstruction() {
        #expect(EMAYProtocol.command(payload: [0x89]) == [0x89, 0x09])
        #expect(EMAYProtocol.command(payload: [0x9A]) == [0x9A, 0x1A])
        #expect(EMAYProtocol.command(payload: [0x9B, 0x01]) == [0x9B, 0x01, 0x1C])
    }

    // MARK: - Frame validation: valid frame

    @Test("valid frame parses correctly")
    func validFrame() {
        // SpO2=98, PR=62, timestamped now
        // Build frame manually: EB 01 05 [PR=62=0x3E] [SpO2=98=0x62] 7F 00 [cks]
        let bytes: [UInt8] = [0xEB, 0x01, 0x05, 0x3E, 0x62, 0x7F, 0x00, 0x00]
        // Checksum of first 7 bytes: 0xEB+0x01+0x05+0x3E+0x62+0x7F+0x00 =
        // 235+1+5+62+98+127+0 = 528, 528 & 0x7F = 16 → 0x10
        let sum = 235 + 1 + 5 + 62 + 98 + 127 + 0
        let cks = UInt8(sum & 0x7F)
        var frame = bytes
        frame[7] = cks

        let reading = EMAYProtocol.parseReading(frame)
        #expect(reading != nil)
        let unwrapped = reading!
        #expect(unwrapped.pulse == 62)
        #expect(unwrapped.spo2 == 98)
    }

    // MARK: - Frame validation: invalid frames

    @Test("wrong length rejects")
    func wrongLength() {
        let frame: [UInt8] = [0xEB, 0x01, 0x05, 0x3E, 0x62, 0x7F]  // 6 bytes
        #expect(EMAYProtocol.parseReading(frame) == nil)
    }

    @Test("bad header rejects")
    func badHeader() {
        var frame: [UInt8] = [0x00, 0x01, 0x05, 0x3E, 0x62, 0x7F, 0x00, 0x00]
        frame[7] = UInt8(frame[0..<7].reduce(0, +) & 0x7F)
        #expect(EMAYProtocol.parseReading(frame) == nil)
    }

    @Test("bad trailer rejects")
    func badTrailer() {
        var frame: [UInt8] = [0xEB, 0x01, 0x05, 0x3E, 0x62, 0x00, 0x00, 0x00]
        frame[7] = UInt8(frame[0..<7].reduce(0, +) & 0x7F)
        #expect(EMAYProtocol.parseReading(frame) == nil)
    }

    @Test("bad checksum rejects")
    func badChecksum() {
        let frame: [UInt8] = [0xEB, 0x01, 0x05, 0x3E, 0x62, 0x7F, 0x00, 0xFF]
        #expect(EMAYProtocol.parseReading(frame) == nil)
    }

    // MARK: - Sentinel value detection

    @Test("PR=0x00 means no pulse")
    func sentinelPR0() {
        var frame: [UInt8] = [0xEB, 0x01, 0x05, 0x00, 0x62, 0x7F, 0x00, 0x00]
        frame[7] = UInt8(frame[0..<7].reduce(0, +) & 0x7F)
        let reading = EMAYProtocol.parseReading(frame)
        #expect(reading != nil)
        let r = reading!
        #expect(r.pulse == nil)
        #expect(r.spo2 == 98)
    }

    @Test("PR=0xFF means no pulse")
    func sentinelPRFF() {
        var frame: [UInt8] = [0xEB, 0x01, 0x05, 0xFF, 0x62, 0x7F, 0x00, 0x00]
        frame[7] = UInt8(frame[0..<7].reduce(0, +) & 0x7F)
        let reading = EMAYProtocol.parseReading(frame)
        #expect(reading != nil)
        let r = reading!
        #expect(r.pulse == nil)
    }

    @Test("SpO2=0x00 means no SpO2")
    func sentinelSpO2_0() {
        var frame: [UInt8] = [0xEB, 0x01, 0x05, 0x3E, 0x00, 0x7F, 0x00, 0x00]
        frame[7] = UInt8(frame[0..<7].reduce(0, +) & 0x7F)
        let reading = EMAYProtocol.parseReading(frame)
        #expect(reading != nil)
        let r = reading!
        #expect(r.spo2 == nil)
        #expect(r.pulse == 62)
    }

    @Test("SpO2=0xFF means no SpO2")
    func sentinelSpO2FF() {
        var frame: [UInt8] = [0xEB, 0x01, 0x05, 0x3E, 0xFF, 0x7F, 0x00, 0x00]
        frame[7] = UInt8(frame[0..<7].reduce(0, +) & 0x7F)
        let reading = EMAYProtocol.parseReading(frame)
        #expect(reading != nil)
        let r = reading!
        #expect(r.spo2 == nil)
    }

    @Test("both sentinels → pulse and SpO2 nil")
    func bothSentinels() {
        var frame: [UInt8] = [0xEB, 0x01, 0x05, 0xFF, 0xFF, 0x7F, 0x00, 0x00]
        frame[7] = UInt8(frame[0..<7].reduce(0, +) & 0x7F)
        let reading = EMAYProtocol.parseReading(frame)
        #expect(reading != nil)
        let r = reading!
        #expect(r.pulse == nil)
        #expect(r.spo2 == nil)
    }

    // MARK: - Plausibility bounds

    @Test("pulse below 30 rejected")
    func pulseTooLow() {
        var frame: [UInt8] = [0xEB, 0x01, 0x05, 29, 0x62, 0x7F, 0x00, 0x00]
        frame[7] = UInt8(frame[0..<7].reduce(0, +) & 0x7F)
        #expect(EMAYProtocol.parseReading(frame) == nil)
    }

    @Test("pulse above 220 rejected")
    func pulseTooHigh() {
        var frame: [UInt8] = [0xEB, 0x01, 0x05, 221, 0x62, 0x7F, 0x00, 0x00]
        frame[7] = UInt8(frame[0..<7].reduce(0, +) & 0x7F)
        #expect(EMAYProtocol.parseReading(frame) == nil)
    }

    @Test("pulse at boundary 30 accepted")
    func pulseMinBoundary() {
        var frame: [UInt8] = [0xEB, 0x01, 0x05, 30, 0x62, 0x7F, 0x00, 0x00]
        frame[7] = UInt8(frame[0..<7].reduce(0, +) & 0x7F)
        #expect(EMAYProtocol.parseReading(frame)?.pulse == 30)
    }

    @Test("pulse at boundary 220 accepted")
    func pulseMaxBoundary() {
        var frame: [UInt8] = [0xEB, 0x01, 0x05, 220, 0x62, 0x7F, 0x00, 0x00]
        frame[7] = UInt8(frame[0..<7].reduce(0, +) & 0x7F)
        #expect(EMAYProtocol.parseReading(frame)?.pulse == 220)
    }

    @Test("SpO2 above 100 rejected")
    func spo2TooHigh() {
        var frame: [UInt8] = [0xEB, 0x01, 0x05, 0x3E, 101, 0x7F, 0x00, 0x00]
        frame[7] = UInt8(frame[0..<7].reduce(0, +) & 0x7F)
        #expect(EMAYProtocol.parseReading(frame) == nil)
    }

    @Test("SpO2 at boundary 0 accepted")
    func spo2MinBoundary() {
        // Not a sentinel value (0x00 is a sentinel, but 0 is also the min bound)
        // Test with value 1 as the boundary
        var frame: [UInt8] = [0xEB, 0x01, 0x05, 0x3E, 1, 0x7F, 0x00, 0x00]
        frame[7] = UInt8(frame[0..<7].reduce(0, +) & 0x7F)
        #expect(EMAYProtocol.parseReading(frame)?.spo2 == 1)
    }

    @Test("SpO2 at boundary 100 accepted")
    func spo2MaxBoundary() {
        var frame: [UInt8] = [0xEB, 0x01, 0x05, 0x3E, 100, 0x7F, 0x00, 0x00]
        frame[7] = UInt8(frame[0..<7].reduce(0, +) & 0x7F)
        #expect(EMAYProtocol.parseReading(frame)?.spo2 == 100)
    }

    // MARK: - Protocol constants

    @Test("pre-built commands have correct checksums")
    func prebuiltCommands() {
        // Every pre-built command should pass its own parse
        #expect(EMAYProtocol.hello.count == 2)
        #expect(EMAYProtocol.hello[1] == EMAYProtocol.checksum([EMAYProtocol.hello[0]]))

        #expect(EMAYProtocol.heartbeat.count == 2)
        #expect(EMAYProtocol.heartbeat[1] == EMAYProtocol.checksum([EMAYProtocol.heartbeat[0]]))

        #expect(EMAYProtocol.startRealtime.count == 3)
        #expect(EMAYProtocol.startRealtime[2] == EMAYProtocol.checksum([EMAYProtocol.startRealtime[0], EMAYProtocol.startRealtime[1]]))

        #expect(EMAYProtocol.stopRealtime.count == 3)
        #expect(EMAYProtocol.stopRealtime[2] == EMAYProtocol.checksum([EMAYProtocol.stopRealtime[0], EMAYProtocol.stopRealtime[1]]))

        #expect(EMAYProtocol.startSequence.count == 4)
    }

    @Test("start sequence is correctly ordered")
    func startSequenceOrder() {
        #expect(EMAYProtocol.startSequence[0] == EMAYProtocol.hello)
        #expect(EMAYProtocol.startSequence[1] == EMAYProtocol.deviceState)
        #expect(EMAYProtocol.startSequence[2] == EMAYProtocol.startRealtime)
        #expect(EMAYProtocol.startSequence[3] == EMAYProtocol.getBattery)
    }
}
