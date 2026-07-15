# EMAY SleepO2 BLE SDK — Kotlin (Android)

> Android BLE client for the EMAY SleepO2 pulse oximeter's real-time
> Bluetooth streaming protocol. Read SpO₂ and pulse rate at 1 Hz from a
> $30 consumer device.

This is the Kotlin/Android package of the multi-language EMAY SleepO2 SDK.
For the other bindings (Swift, Python, Node.js, Rust, Go) see the
[repository README](https://github.com/chenders/emay-sleepo2#readme). The
reverse-engineered protocol is documented in
[SPEC.md](https://github.com/chenders/emay-sleepo2/blob/main/SPEC.md).

## Installation

The library is not yet published to Maven Central — clone the repository,
publish to your local Maven repository, and depend on it from there:

```bash
git clone https://github.com/chenders/emay-sleepo2.git
cd emay-sleepo2/kotlin
./gradlew publishToMavenLocal
```

```kotlin
// settings.gradle.kts / repositories
mavenLocal()

// build.gradle.kts
implementation("com.groundeffectsoftware.com:emay-sleepo2:1.0.0")
```

Requires Android 8.0+ (minSdk 26). BLE streaming needs the
`BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` runtime permissions (plus
`ACCESS_FINE_LOCATION` with location services enabled on Android 11 and
below) — the library declares none itself, so request them in your app.

## Quick Start

```kotlin
import com.groundeffectsoftware.com.emaysleepo2.EMAYClient

val emay = EMAYClient(context)
emay.onReading = { reading ->
    val spo2 = reading.spo2?.let { "$it%" } ?: "—"
    val pulse = reading.pulse?.toString() ?: "—"
    println("SpO₂: $spo2  HR: $pulse")
}
emay.start(scope = lifecycleScope)

// ... stream ...

emay.stop()
```

`EMAYClient` scans for the device, connects, runs the protocol start
sequence, and keeps the stream alive with a heartbeat command. Useful
surface:

- `emay.start(scope, address)` — connect to a specific device address
  instead of scanning.
- `emay.onStatusChange` — observe the `EMAYStatus` state machine
  (`Idle`, `Scanning`, `Connecting`, `Streaming`, `Failed`, …).
- `emay.onMinuteSamples` — receive finalized per-minute mean
  `MinuteSample` values from the built-in `EMAYLiveDownsampler`.
- `emay.isStreaming` / `emay.latestReading` — current state and last
  reading.

`reading.spo2` and `reading.pulse` are nullable `Int?`: `null` means the
sensor couldn't acquire that measurement (finger off), **not** zero.

## Protocol Layer

`EMAYProtocol` exposes the raw building blocks for advanced use:
`parseReading`, `checksum`, `command`, the prebuilt commands (`HELLO`,
`DEVICE_STATE`, `START_REALTIME`, `STOP_REALTIME`, `GET_BATTERY`,
`HEARTBEAT`, `START_SEQUENCE`), and the BLE UUIDs.

## Development

```bash
cd kotlin
./gradlew test
```

## License

MIT
