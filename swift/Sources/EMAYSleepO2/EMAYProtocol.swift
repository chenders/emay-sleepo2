import Foundation

// MARK: - Reading

/// A single physiological reading from the EMAY SleepO2.
///
/// Both `spo2` and `pulse` are nullable — the device can report a valid
/// pulse rate without SpO₂ (finger partially on) or vice versa. nil means
/// the sensor couldn't acquire that measurement ("no finger detected"),
/// NOT zero saturation or asystole.
public struct EMAYReading: Sendable, Equatable, Hashable {
    /// Oxygen saturation percent (0–100), or nil when not acquired.
    public let spo2: Int?
    /// Pulse rate in beats per minute, or nil when not acquired.
    public let pulse: Int?
    /// When this reading was produced by the device (approx 1 Hz).
    public let timestamp: Date

    public init(spo2: Int?, pulse: Int?, timestamp: Date) {
        self.spo2 = spo2
        self.pulse = pulse
        self.timestamp = timestamp
    }
}

// MARK: - Client status

/// Observable connection/streaming state of the oximeter client.
public enum EMAYStatus: Equatable, Sendable {
    /// No session active; not trying to connect.
    case idle
    /// Scanning for the EMAY service UUID.
    case scanning
    /// Connection established; protocol handshake in progress.
    case connecting
    /// Device connected and streaming data at ~1 Hz.
    case streaming
    /// Bluetooth is powered off on this device.
    case bluetoothOff
    /// Bluetooth permission denied by user.
    case bluetoothUnauthorized
    /// Bluetooth not supported on this hardware.
    case bluetoothUnsupported
    /// An error occurred. The associated message is human-readable.
    case failed(String)

    /// Whether a session is actively in progress (not necessarily streaming yet).
    public var isActive: Bool {
        switch self {
        case .scanning, .connecting, .streaming: true
        default: false
        }
    }
}

// MARK: - BLE Protocol Constants

/// Pure-protocol layer for the EMAY SleepO2 BLE protocol.
///
/// Contains no CoreBluetooth calls, no async, no platform dependencies. Each
/// language binding reimplements these static functions with that language's
/// byte-manipulation idioms.
public enum EMAYProtocol {
    /// BLE primary service UUID (vendor-specific FF12).
    public static let serviceUUID = "0000FF12-0000-1000-8000-00805F9B34FB"
    /// Write-characteristic UUID (commands go here).
    public static let writeUUID = "0000FF01-0000-1000-8000-00805F9B34FB"
    /// Notify-characteristic UUID (data frames arrive here).
    public static let notifyUUID = "0000FF02-0000-1000-8000-00805F9B34FB"

    /// Advertised local-name prefix for the SleepO2.
    public static let namePrefix = "SleepO2"

    // MARK: Commands

    public static let hello: [UInt8]       = [0x89, 0x09]
    public static let deviceState: [UInt8] = [0x8E, 0x05, 0x13]
    public static let startRealtime: [UInt8] = [0x9B, 0x01, 0x1C]
    public static let stopRealtime: [UInt8] = [0x9B, 0x7F, 0x1A]
    public static let getBattery: [UInt8]   = [0x86, 0x06]
    public static let heartbeat: [UInt8]    = [0x9A, 0x1A]

    /// Ordered start-sequence commands for the initial handshake. Serialized:
    /// each sent one at a time with write-response acknowledged before the next.
    public static let startSequence: [[UInt8]] = [hello, deviceState, startRealtime, getBattery]

    /// Compute the EMAY checksum for a payload: sum of bytes masked to 0x7F.
    /// The 0x7F mask (NOT 0xFF) is crucial — 0xFF produces invalid checksums
    /// the device silently ignores.
    public static func checksum(_ payload: [UInt8]) -> UInt8 {
        UInt8(payload.reduce(0) { $0 + Int($1) } & 0x7F)
    }

    /// Build a full command frame: payload + checksum.
    public static func command(payload: [UInt8]) -> [UInt8] {
        payload + [checksum(payload)]
    }

    // MARK: Data-frame validation

    /// Expected data-frame length (8 bytes).
    public static let frameLength = 8
    /// Expected header bytes: magic, version, payload-length.
    public static let frameHeader: [UInt8] = [0xEB, 0x01, 0x05]
    /// Expected trailer bytes.
    public static let frameTrailer: [UInt8] = [0x7F, 0x00]

    /// Plausibility bounds for application-level filtering
    /// (applied AFTER checksum validation).
    public static let pulseMinBPM: Int = 30
    public static let pulseMaxBPM: Int = 220
    public static let spo2MaxPercent: Int = 100
    /// Below this is almost certainly a corrupted byte, not real severe
    /// hypoxemia — but if a real 40 BPM or 70% SpO₂ is inside the range,
    /// it is trusted. Silently filtering genuine extreme values is a
    /// false-reassurance hazard.
    public static let spo2MinPercent: Int = 0

    // MARK: Frame parsing

    /// Attempt to parse an 8-byte raw frame from the BLE notify characteristic.
    ///
    /// Returns nil if the frame fails ANY validation check (length, header,
    /// trailer, checksum, or implausible values).
    public static func parseReading(_ raw: [UInt8]) -> EMAYReading? {
        guard raw.count == frameLength else { return nil }
        guard raw[0] == frameHeader[0],
              raw[1] == frameHeader[1],
              raw[2] == frameHeader[2] else { return nil }
        guard raw[5] == frameTrailer[0],
              raw[6] == frameTrailer[1] else { return nil }
        let cks = UInt8(raw[0..<7].reduce(0) { $0 + Int($1) } & 0x7F)
        guard raw[7] == cks else { return nil }

        let rawPR = Int(raw[3])
        let rawSpO2 = Int(raw[4])

        // Decode sentinel values to nil
        let pr: Int? = (rawPR == 0 || rawPR == 0xFF) ? nil : rawPR
        let spo2: Int? = (rawSpO2 == 0 || rawSpO2 == 0xFF) ? nil : rawSpO2

        // Application-level plausibility bounds
        if let p = pr, p < pulseMinBPM || p > pulseMaxBPM { return nil }
        if let s = spo2, s < spo2MinPercent || s > spo2MaxPercent { return nil }

        return EMAYReading(spo2: spo2, pulse: pr, timestamp: Date())
    }
}
