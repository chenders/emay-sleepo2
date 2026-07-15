# EMAY SleepO2 BLE SDK — Python

> Python BLE client for the EMAY SleepO2 pulse oximeter's real-time
> Bluetooth streaming protocol. Read SpO₂ and pulse rate at 1 Hz from a
> $30 consumer device.

This is the Python package of the multi-language EMAY SleepO2 SDK. For the
other bindings (Swift, Node.js, Rust, Go, Kotlin) see the
[repository README](https://github.com/chenders/emay-sleepo2#readme). The
reverse-engineered protocol is documented in
[SPEC.md](https://github.com/chenders/emay-sleepo2/blob/main/SPEC.md).

## Installation

```bash
pip install emay-sleepo2          # protocol layer only — zero dependencies
pip install "emay-sleepo2[ble]"   # + live BLE streaming (installs bleak)
```

Requires Python 3.10+. BLE streaming works anywhere
[bleak](https://github.com/hbldh/bleak) does: macOS, Linux, Windows, and
Raspberry Pi.

## Quick Start

Live streaming requires the `ble` extra — with a plain
`pip install emay-sleepo2`, `emay_sleepo2.EMAYClient` is `None` because
bleak isn't installed.

```python
import asyncio
from emay_sleepo2 import EMAYClient

def show(reading):
    spo2 = f"{reading.spo2}%" if reading.spo2 is not None else "—"
    pulse = reading.pulse if reading.pulse is not None else "—"
    print(f"SpO₂: {spo2}  HR: {pulse}")

async def main():
    emay = EMAYClient()
    emay.on_reading = show
    await emay.start()
    await asyncio.sleep(30)  # stream for 30 seconds
    await emay.stop()

asyncio.run(main())
```

`EMAYClient` scans for the device, connects, runs the protocol start
sequence, and keeps the stream alive with a heartbeat command. Useful knobs:

- `await emay.start(address)` — connect to a specific device address
  instead of scanning.
- `emay.on_status_change` — observe the `Status` state machine
  (`IDLE`, `SCANNING`, `CONNECTING`, `STREAMING`, `FAILED`, …).
- `emay.on_minute_samples` — receive finalized per-minute mean
  `MinuteSample` values from the built-in `LiveDownsampler`.
- `EMAYClient(heartbeat_interval=1.5, stale_timeout=4.0, auto_reconnect=True)`
  — tune keepalive, staleness detection, and reconnect behavior.

`Reading.spo2` and `Reading.pulse` are `Optional[int]`: `None` means the
sensor couldn't acquire that measurement (finger off), **not** zero.

## Protocol Layer

The raw protocol building blocks are exported for advanced use:
`parse_reading`, `checksum`, `command`, the prebuilt commands (`HELLO`,
`DEVICE_STATE`, `START_REALTIME`, `STOP_REALTIME`, `GET_BATTERY`,
`HEARTBEAT`), and the BLE UUIDs (`SERVICE_UUID`, `WRITE_UUID`,
`NOTIFY_UUID`).

## Development

```bash
pip install -e ".[all]"
pytest
ruff check .
```

## License

MIT
