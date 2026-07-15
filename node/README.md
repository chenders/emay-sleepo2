# EMAY SleepO2 BLE SDK — Node.js

> Node.js/TypeScript BLE client for the EMAY SleepO2 pulse oximeter's
> real-time Bluetooth streaming protocol. Read SpO₂ and pulse rate at 1 Hz
> from a $30 consumer device.

This is the Node.js package of the multi-language EMAY SleepO2 SDK. For the
other bindings (Swift, Python, Rust, Go, Kotlin) see the
[repository README](https://github.com/chenders/emay-sleepo2#readme). The
reverse-engineered protocol is documented in
[SPEC.md](https://github.com/chenders/emay-sleepo2/blob/main/SPEC.md).

## Installation

```bash
npm install @groundeffect/emay-sleepo2

# For live BLE streaming, also install the optional peer dependency:
npm install @abandonware/noble
```

The protocol layer has no dependencies —
[noble](https://github.com/abandonware/noble) is only needed for live
streaming, and works on macOS, Linux, Windows, and Raspberry Pi. The
package is ESM-only and ships TypeScript type declarations.

## Quick Start

```js
import { EMAYClient } from "@groundeffect/emay-sleepo2";

const emay = new EMAYClient();
emay.on("reading", (r) => {
  const spo2 = r.spo2 == null ? "—" : `${r.spo2}%`;
  const pulse = r.pulse ?? "—";
  console.log(`SpO₂: ${spo2}  HR: ${pulse}`);
});
await emay.start();

// ... stream ...

await emay.stop();
```

`EMAYClient` is an `EventEmitter` that scans for the device, connects, runs
the protocol start sequence, and keeps the stream alive with a heartbeat
command. Useful surface:

- `await emay.start(address)` — connect to a specific device address
  instead of scanning.
- `"statusChange"` event — observe the `Status` state machine
  (`Idle`, `Scanning`, `Connecting`, `Streaming`, `Failed`, …).
- `"minuteSamples"` event — receive finalized per-minute mean
  `MinuteSample` values from the built-in `LiveDownsampler`.
- `emay.status` / `emay.latestReading` — current state and last reading.

`reading.spo2` and `reading.pulse` are nullable: `null` means the sensor
couldn't acquire that measurement (finger off), **not** zero.

## Protocol Layer

The raw protocol building blocks are exported for advanced use:
`parseReading`, `checksum`, `command`, the prebuilt commands (`HELLO`,
`DEVICE_STATE`, `START_REALTIME`, `STOP_REALTIME`, `GET_BATTERY`,
`HEARTBEAT`, `START_SEQUENCE`), and the BLE UUIDs (`SERVICE_UUID`,
`WRITE_UUID`, `NOTIFY_UUID`).

## Development

```bash
npm ci
npm test        # node --test via tsx
npm run check   # tsc --noEmit
npm run build   # emit dist/
```

## License

MIT
