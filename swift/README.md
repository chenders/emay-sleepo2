# EMAY SleepO2 BLE SDK — Swift

> Swift BLE client and CSV parser for the EMAY SleepO2 pulse oximeter's
> real-time Bluetooth streaming protocol. Read SpO₂ and pulse rate at 1 Hz
> from a $30 consumer device.

This is the Swift package of the multi-language EMAY SleepO2 SDK. For the
other bindings (Python, Node.js, Rust, Go, Kotlin) see the
[repository README](https://github.com/chenders/emay-sleepo2#readme). The
reverse-engineered protocol is documented in
[spec.md](https://github.com/chenders/emay-sleepo2/blob/main/spec.md).

## Installation

The package manifest lives in this `swift/` subdirectory, so add it as a
local package: clone the repository, then use **File → Add Package
Dependencies… → Add Local…** in Xcode and select the `swift/` directory,
or reference it by path from another `Package.swift`:

```swift
dependencies: [
    .package(path: "../emay-sleepo2/swift"),
]
```

Two library products are available:

- `EMAYSleepO2` — BLE client (CoreBluetooth), protocol layer, downsampler
- `EMAYSleepO2CSV` — CSV parser (links the core module for shared types,
  but needs no BLE hardware or active session)

Supports iOS 15+, macOS 13+, and watchOS 9+. Apps that stream over BLE
must include `NSBluetoothAlwaysUsageDescription` in their Info.plist.

## Quick Start

```swift
import EMAYSleepO2

let emay = EMAYClient()
emay.onReading = { reading in
    let spo2 = reading.spo2.map { "\($0)%" } ?? "—"
    let pulse = reading.pulse.map(String.init) ?? "—"
    print("SpO₂: \(spo2)  HR: \(pulse)")
}
emay.start()

// ... stream ...

emay.stop()
```

`EMAYClient` scans for the device, connects, runs the protocol start
sequence, and keeps the stream alive with a heartbeat command. Useful
surface:

- `emay.start(address:)` — connect to a specific peripheral by `UUID`
  instead of scanning.
- `emay.onStatusChange` — observe the `EMAYStatus` state machine
  (`.idle`, `.scanning`, `.connecting`, `.streaming`, `.failed`, …).
- `emay.onMinuteSamples` — receive finalized per-minute mean samples from
  the built-in `EMAYLiveDownsampler`.
- `emay.isStreaming` / `emay.latestReading` — current state and last
  reading.
- `heartbeatInterval` (1.5 s), `staleTimeout` (4 s), and `autoReconnect`
  are configurable properties.

`reading.spo2` and `reading.pulse` are optionals: `nil` means the sensor
couldn't acquire that measurement (finger off), **not** zero.

## CSV Parsing (no BLE required)

The EMAY app exports session CSVs. Parse them with the `EMAYSleepO2CSV`
product — no BLE hardware or active session required:

```swift
import EMAYSleepO2CSV

let result = try EMAYCSVParser.parseFile(at: url)
print(result.readings.count, result.warnings)
```

Malformed rows become warnings — `EMAYCSVParser.Error` is thrown only for
CSVs with no data rows, and `parseFile(at:)` can also throw file-read
errors. `EMAYCSVParser.timezone` and
`EMAYCSVParser.correctDSTFold` control timestamp interpretation — DST fold
correction disambiguates timestamps recorded during the repeated fall-back
hour.

## Development

```bash
cd swift
swift test
```

## License

MIT
