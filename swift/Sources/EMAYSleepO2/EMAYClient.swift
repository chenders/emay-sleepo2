import Foundation
import CoreBluetooth

/// A CoreBluetooth client for the EMAY SleepO2 pulse oximeter.
///
/// Handles BLE discovery, connection, protocol handshake, heartbeat
/// sustain, auto-reconnect on transient drops, and state restoration
/// for background survival.
///
/// ## Example
///
/// ```swift
/// let emay = EMAYClient()
/// emay.onReading = { reading in
///     print("SpO₂: \(reading.spo2 ?? 0)%  HR: \(reading.pulse ?? 0)")
/// }
/// try await emay.start()
/// ```
///
/// The client exposes simple start/stop controls. Internally it manages
/// a complex BLE state machine: scan → connect → discover services →
/// discover characteristics → enable notifications → send start sequence →
/// streaming → heartbeat sustain.
@MainActor
public final class EMAYClient: NSObject, @unchecked Sendable {

    // MARK: - Public callbacks

    /// Called at ~1 Hz with each new validated reading from the device.
    public var onReading: ((EMAYReading) -> Void)?

    /// Called whenever the connection/streaming status changes.
    public var onStatusChange: ((EMAYStatus) -> Void)?

    /// Called when finalized per-minute mean samples are produced.
    /// The caller decides what to persist or display.
    public var onMinuteSamples: (([EMAYLiveDownsampler.MinuteSample]) -> Void)?

    // MARK: - Configuration

    /// Heartbeat interval in seconds. The device stops transmitting after
    /// ~3–4 seconds without a heartbeat. Default 1.5 s.
    public var heartbeatInterval: TimeInterval = 1.5

    /// Duration after the last received frame before the stream is
    /// considered stalled and the latest reading is dropped.
    public var staleTimeout: TimeInterval = 4.0

    /// Whether to automatically reconnect on transient disconnects.
    /// Default true.
    public var autoReconnect: Bool = true

    // MARK: - Public state (read-only)

    /// Current connection/streaming status.
    public private(set) var status: EMAYStatus = .idle {
        didSet {
            if oldValue != status {
                onStatusChange?(status)
            }
        }
    }

    /// Best-effort reason for the most recent ``EMAYStatus/failed(_:)``.
    /// Meaningful only while `status` is `.failed`; otherwise `.none`. It is
    /// reset to `.none` at the start of each session.
    public private(set) var failureReason: FailureReason = .none

    /// The most recent validated reading, or nil when no reading is
    /// available (including when the stream is stalled).
    public private(set) var latestReading: EMAYReading?

    /// Whether the service is actively streaming data.
    public var isStreaming: Bool { status == .streaming }

    // MARK: - Private state

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var pendingWrites: [[UInt8]] = []
    private var inFlightWrite: [UInt8]?
    private var heartbeatTask: Task<Void, Never>?
    private var wantScan = false
    private var lastReadingAt: Date?
    private let downsampler = EMAYLiveDownsampler()

    /// Remembered device identifier. Persisted by the caller via
    /// `persistentIdentifier` property; the client only uses it for
    /// pending-connect bypass of the slow background scan path.
    public var knownPeripheralUUID: UUID?

    // MARK: - Init

    public override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "EMAYSleepO2.restore"]
        )
    }

    // MARK: - Public API

    /// Begin monitoring for the oximeter. Safe to call before Bluetooth is
    /// powered on — monitoring starts when it becomes ready.
    ///
    /// No-op while a session is already active.
    public func start() {
        guard !status.isActive else { return }
        failureReason = .none
        wantScan = true
        if let notReady = Self.startupStatus(for: central.state) {
            status = notReady
        } else {
            beginMonitoring()
        }
    }

    /// Connect to a specific device by UUID. Must match a previously
    /// discovered/remembered peripheral identifier.
    public func start(address uuid: UUID) {
        guard !status.isActive else { return }
        failureReason = .none
        wantScan = true
        knownPeripheralUUID = uuid
        if central.state == .poweredOn {
            beginMonitoring()
        } else {
            status = .scanning
        }
    }

    /// Stop streaming and disconnect.
    public func stop() {
        wantScan = false
        if let peripheral, let writeChar {
            peripheral.writeValue(
                Data(EMAYProtocol.stopRealtime),
                for: writeChar,
                type: .withResponse
            )
        }
        if central.state == .poweredOn {
            central.stopScan()
        }
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        resetConnectionState()
        status = .idle
    }

    // MARK: - Private: monitoring

    private func beginMonitoring() {
        if let held = peripheral {
            adoptAndConnect(held)
            return
        }
        if let uuid = knownPeripheralUUID,
           let known = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            adoptAndConnect(known)
            return
        }
        beginScan()
    }

    private func adoptAndConnect(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        switch p.state {
        case .connected:
            status = .connecting
            p.discoverServices([CBUUID(string: EMAYProtocol.serviceUUID)])
        case .connecting:
            status = .connecting
        default:
            status = .scanning
            central.connect(p)
        }
    }

    private func beginScan() {
        status = .scanning
        central.scanForPeripherals(withServices: [CBUUID(string: EMAYProtocol.serviceUUID)])
    }

    // MARK: - Private: BLE write

    private func write(_ bytes: [UInt8]) {
        guard let peripheral, let writeChar else { return }
        peripheral.writeValue(Data(bytes), for: writeChar, type: .withResponse)
    }

    private func sendNextWrite() {
        guard !pendingWrites.isEmpty else { inFlightWrite = nil; return }
        let next = pendingWrites.removeFirst()
        inFlightWrite = next
        write(next)
    }

    // MARK: - Private: connection teardown

    private func resetConnectionState(flushPartialBucket: Bool = true) {
        if flushPartialBucket {
            let minutes = downsampler.flush()
            if !minutes.isEmpty {
                onMinuteSamples?(minutes)
            }
        }
        heartbeatTask?.cancel()
        heartbeatTask = nil
        pendingWrites = []
        inFlightWrite = nil
        peripheral?.delegate = nil
        peripheral = nil
        writeChar = nil
        notifyChar = nil
        latestReading = nil
        lastReadingAt = nil
    }

    private func fail(_ message: String) {
        // All callers are post-discovery failures: the device was found but the
        // connection or GATT setup failed.
        failureReason = .connectionFailed
        status = .failed(message)
        if central.state == .poweredOn, let peripheral {
            central.cancelPeripheralConnection(peripheral)
        } else {
            resetConnectionState()
        }
    }

    // MARK: - Private: heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int((self?.heartbeatInterval ?? 1.5) * 1000)))
                guard let self, self.status == .streaming else { return }
                self.write(EMAYProtocol.heartbeat)
                // Staleness watchdog
                if let last = self.lastReadingAt,
                   Date().timeIntervalSince(last) > self.staleTimeout {
                    if self.latestReading != nil {
                        self.latestReading = nil
                        _ = self.downsampler.flush()
                    }
                }
            }
        }
    }

    // MARK: - Static helpers

    nonisolated static func startupStatus(for state: CBManagerState) -> EMAYStatus? {
        switch state {
        case .poweredOn: return nil
        case .poweredOff: return .bluetoothOff
        case .unauthorized: return .bluetoothUnauthorized
        case .unsupported: return .bluetoothUnsupported
        case .resetting, .unknown: return .scanning
        @unknown default: return .scanning
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension EMAYClient: CBCentralManagerDelegate {
    public nonisolated func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        guard let firstPeripheral = restored.first else { return }
        let identifier = firstPeripheral.identifier  // UUID is Sendable
        Task { @MainActor [weak self] in
            guard let self, self.peripheral == nil else { return }
            guard let p = self.central.retrievePeripherals(withIdentifiers: [identifier]).first else { return }
            p.delegate = self
            self.peripheral = p
            self.wantScan = true
            self.status = .scanning
        }
    }

    public nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state  // CBManagerState is Sendable
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .poweredOn:
                if self.wantScan {
                    self.beginMonitoring()
                } else if let orphan = self.peripheral {
                    self.central.cancelPeripheralConnection(orphan)
                    self.resetConnectionState()
                }
            case .poweredOff:
                self.resetConnectionState()
                self.status = .bluetoothOff
            case .unauthorized:
                self.resetConnectionState()
                self.status = .bluetoothUnauthorized
            case .unsupported:
                self.resetConnectionState()
                self.status = .bluetoothUnsupported
            case .resetting, .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? ""
        let identifier = peripheral.identifier
        Task { @MainActor [weak self] in
            guard let self, self.peripheral == nil else { return }
            guard name.isEmpty || name.hasPrefix(EMAYProtocol.namePrefix) else { return }
            guard let p = self.central.retrievePeripherals(withIdentifiers: [identifier]).first else { return }
            self.central.stopScan()
            self.peripheral = p
            p.delegate = self
            self.status = .connecting
            self.central.connect(p)
            self.knownPeripheralUUID = identifier
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        let identifier = peripheral.identifier
        Task { @MainActor [weak self] in
            guard let self, identifier == self.peripheral?.identifier else { return }
            if self.status == .scanning { self.status = .connecting }
            guard let p = self.peripheral else { return }
            p.discoverServices([CBUUID(string: EMAYProtocol.serviceUUID)])
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let message = error?.localizedDescription ?? "unknown"
        Task { @MainActor [weak self] in
            guard let self else { return }
            let msg = "connect failed: \(message)"
            self.resetConnectionState()
            if self.wantScan && self.autoReconnect {
                self.beginMonitoring()
            } else {
                self.failureReason = .connectionFailed
                self.status = .failed(msg)
            }
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let wasFailure = { if case .failed = self.status { true } else { false } }()
            let isTransient = self.wantScan && !wasFailure && self.autoReconnect
            self.resetConnectionState(flushPartialBucket: !isTransient)
            if isTransient {
                self.beginMonitoring()
            } else if !wasFailure {
                self.status = .idle
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension EMAYClient: CBPeripheralDelegate {
    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        let identifier = peripheral.identifier
        let errMsg = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self, identifier == self.peripheral?.identifier else { return }
            if let errMsg { self.fail("service discovery failed: \(errMsg)"); return }
            guard let p = self.peripheral else { return }
            guard let svc = p.services?.first(where: {
                $0.uuid == CBUUID(string: EMAYProtocol.serviceUUID)
            }) else {
                self.fail("EMAY service \(EMAYProtocol.serviceUUID) not found"); return
            }
            p.discoverCharacteristics(
                [
                    CBUUID(string: EMAYProtocol.writeUUID),
                    CBUUID(string: EMAYProtocol.notifyUUID)
                ],
                for: svc
            )
        }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let identifier = peripheral.identifier
        let errMsg = error?.localizedDescription
        nonisolated(unsafe) let writeUUID = CBUUID(string: EMAYProtocol.writeUUID)
        nonisolated(unsafe) let notifyUUID = CBUUID(string: EMAYProtocol.notifyUUID)
        Task { @MainActor [weak self] in
            guard let self, identifier == self.peripheral?.identifier else { return }
            if let errMsg {
                self.fail("characteristic discovery failed: \(errMsg)")
                return
            }
            for ch in (self.peripheral?.services?.first?.characteristics) ?? [] {
                if ch.uuid == writeUUID { self.writeChar = ch }
                if ch.uuid == notifyUUID { self.notifyChar = ch }
            }
            guard let notifyChar = self.notifyChar, self.writeChar != nil else {
                self.fail("EMAY characteristics not found"); return
            }
            self.peripheral?.setNotifyValue(true, for: notifyChar)
        }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        nonisolated(unsafe) let chUUID = characteristic.uuid
        let isNotifying = characteristic.isNotifying
        let errMsg = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self, chUUID == CBUUID(string: EMAYProtocol.notifyUUID) else { return }
            if let errMsg {
                self.fail("enabling notifications failed: \(errMsg)")
                return
            }
            guard isNotifying else {
                self.fail("notifications not enabled"); return
            }
            self.pendingWrites = EMAYProtocol.startSequence
            self.sendNextWrite()
        }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let errMsg = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            let completed = self.inFlightWrite
            self.inFlightWrite = nil
            if let errMsg {
                if self.status != .streaming {
                    self.fail("start-sequence write failed: \(errMsg)")
                }
                return
            }
            if completed == EMAYProtocol.startRealtime, self.status != .streaming {
                self.status = .streaming
                self.startHeartbeat()
            }
            self.sendNextWrite()
        }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        nonisolated(unsafe) let chUUID = characteristic.uuid
        let data = characteristic.value.flatMap { Data($0) }
        Task { @MainActor [weak self] in
            guard let self,
                  chUUID == CBUUID(string: EMAYProtocol.notifyUUID),
                  self.status == .streaming,
                  let data else { return }
            let raw = [UInt8](data)
            guard let reading = EMAYProtocol.parseReading(raw) else { return }
            self.latestReading = reading
            self.lastReadingAt = Date()
            self.onReading?(reading)

            let minutes = self.downsampler.add(reading)
            if !minutes.isEmpty {
                self.onMinuteSamples?(minutes)
            }
        }
    }
}
