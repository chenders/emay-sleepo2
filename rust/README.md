# EMAY SleepO2 BLE SDK — Rust

> Rust BLE client and CSV parser for the EMAY SleepO2 pulse oximeter's
> real-time Bluetooth streaming protocol. Read SpO₂ and pulse rate at 1 Hz
> from a $30 consumer device.

This is the Rust crate of the multi-language EMAY SleepO2 SDK. For the
other bindings (Swift, Python, Node.js, Go, Kotlin) see the
[repository README](https://github.com/chenders/emay-sleepo2#readme). The
reverse-engineered protocol is documented in
[spec.md](https://github.com/chenders/emay-sleepo2/blob/main/spec.md).

## Installation

The crate is not yet published to crates.io — depend on it via git:

```toml
[dependencies]
emay-sleepo2 = { git = "https://github.com/chenders/emay-sleepo2", features = ["ble"] }
```

The `ble` feature pulls in [btleplug](https://github.com/deviceplug/btleplug)
(plus tokio, uuid, and futures) and supports macOS, Linux, and Windows.
On Linux, btleplug needs `libdbus-1-dev` and `pkg-config` at build time.

## Quick Start

```rust
use std::sync::Arc;
use std::time::Duration;

use emay_sleepo2::EMAYClient;

#[tokio::main]
async fn main() -> Result<(), String> {
    let mut emay = EMAYClient::new().await?;
    emay.set_on_reading(Arc::new(|r| {
        println!("SpO₂: {:?}  HR: {:?}", r.spo2, r.pulse);
    }));
    emay.start().await?;
    tokio::time::sleep(Duration::from_secs(30)).await;
    emay.stop().await?;
    Ok(())
}
```

`EMAYClient` scans for the device, connects, runs the protocol start
sequence, and keeps the stream alive with a heartbeat command. Useful
surface:

- `set_on_status(...)` — observe the `Status` state machine
  (`Idle`, `Scanning`, `Connecting`, `Streaming`, `Failed`, …).
- `set_on_minute_samples(...)` — receive finalized per-minute mean
  `MinuteSample` values from the built-in `LiveDownsampler`.
- `status().await` — current state.

`Reading::spo2` and `Reading::pulse` are `Option<u8>`: `None` means the
sensor couldn't acquire that measurement (finger off), **not** zero.

## CSV Parsing (no BLE required)

The EMAY app exports session CSVs. The parser has no BLE dependencies:

```rust
use emay_sleepo2::parse_csv_file;

let (readings, warnings) = parse_csv_file("session.csv", true)?;
```

`parse_csv(content, correct_dst_fold)` accepts raw CSV text; both return
`(Vec<Reading>, Vec<String>)` where malformed rows become warnings, not
errors. DST fold correction disambiguates timestamps recorded during the
repeated fall-back hour.

## Protocol Layer

The raw protocol building blocks are exported for advanced use:
`parse_reading`, `checksum`, `command`, the prebuilt commands (`HELLO`,
`DEVICE_STATE`, `START_REALTIME`, `STOP_REALTIME`, `GET_BATTERY`,
`HEARTBEAT`), and the BLE UUIDs (`SERVICE_UUID`, `WRITE_UUID`,
`NOTIFY_UUID`).

## Development

```bash
cd rust
cargo build --features ble
cargo test
cargo clippy --features ble
```

## License

MIT
