# EMAY SleepO2 BLE SDK — Go

> Go BLE client and CSV parser for the EMAY SleepO2 pulse oximeter's
> real-time Bluetooth streaming protocol. Read SpO₂ and pulse rate at 1 Hz
> from a $30 consumer device.

This is the Go package of the multi-language EMAY SleepO2 SDK. For the
other bindings (Swift, Python, Node.js, Rust, Kotlin) see the
[repository README](https://github.com/chenders/emay-sleepo2#readme). The
reverse-engineered protocol is documented in
[spec.md](https://github.com/chenders/emay-sleepo2/blob/main/spec.md).

## Installation

The module lives in this `go/` subdirectory, so it can't be fetched with a
plain `go get` yet. Clone the repository and reference it with a `replace`
directive:

```bash
git clone https://github.com/chenders/emay-sleepo2.git
```

```go
// go.mod
require github.com/chenders/emay-sleepo2 v0.0.0

replace github.com/chenders/emay-sleepo2 => ../emay-sleepo2/go
```

The package is dependency-free pure Go. Rather than bundling a BLE stack,
the client is written against a small `BLEAdapter` interface — implement it
over your platform's BLE library of choice (e.g.
[TinyGo Bluetooth](https://github.com/tinygo-org/bluetooth)).

## Quick Start

```go
package main

import (
    "fmt"
    "time"

    emay "github.com/chenders/emay-sleepo2"
)

func main() {
    client := emay.NewClient(myAdapter) // your emay.BLEAdapter implementation
    client.OnReading = func(r emay.Reading) {
        if r.SpO2 != nil && r.Pulse != nil {
            fmt.Printf("SpO₂: %d%%  HR: %d\n", *r.SpO2, *r.Pulse)
        }
    }
    client.Start("") // empty address = scan for the device
    time.Sleep(30 * time.Second)
    client.Stop()
}
```

`Client` scans for the device, connects, runs the protocol start sequence,
and keeps the stream alive with a heartbeat command. Useful surface:

- `client.Start(addr)` — pass a device address to skip scanning.
- `client.OnStatus` — observe the `Status` state machine
  (`StatusIdle`, `StatusScanning`, `StatusConnecting`, `StatusStreaming`,
  `StatusFailed`, …).
- `client.OnMinute` — receive finalized per-minute mean `MinuteSample`
  values from the built-in `LiveDownsampler`.
- `client.Status()` / `client.LatestReading()` / `client.IsStreaming()` —
  current state and last reading.

`Reading.SpO2` and `Reading.Pulse` are `*int`: `nil` means the sensor
couldn't acquire that measurement (finger off), **not** zero.

## CSV Parsing (no BLE required)

The EMAY app exports session CSVs. The parser needs no BLE adapter:

```go
result, err := emay.ParseCSVFile("session.csv", true)
if err != nil {
    panic(err)
}
fmt.Println(len(result.Readings), result.Warnings)
```

`ParseCSV(content, correctDST)` accepts raw CSV text; malformed rows become
warnings, not errors. DST fold correction disambiguates timestamps recorded
during the repeated fall-back hour.

## Development

```bash
cd go
go test ./...
```

## License

MIT
