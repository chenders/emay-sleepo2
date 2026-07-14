# EMAY SleepO2 BLE SDK

> A multi-language SDK for the EMAY SleepO2 pulse oximeter's real-time
> Bluetooth streaming protocol. Read SpO₂ and pulse rate at 1 Hz from a
> $30 consumer device.

Every package exposes the **same simple API**. Pick your language — the
`EMAYClient` interface is identical across Swift, Python, Node.js, Rust,
Go, and Kotlin.

## Quick Start

### Swift

```swift
import EMAYSleepO2

let emay = EMAYClient()
emay.onReading = { reading in
    print("SpO₂: \(reading.spo2 ?? 0)%  HR: \(reading.pulse ?? 0)")
}
try await emay.start()
```

### Python

```python
import asyncio
from emay_sleepo2 import EMAYClient

async def main():
    emay = EMAYClient()
    emay.on_reading = lambda r: print(f"SpO₂: {r.spo2}%  HR: {r.pulse}")
    await emay.start()
    await asyncio.sleep(30)  # stream for 30 seconds
    await emay.stop()

asyncio.run(main())
```

### Node.js

```js
import { EMAYClient } from 'emay-sleepo2';

const emay = new EMAYClient();
emay.on('reading', (r) => {
    console.log(`SpO₂: ${r.spo2}%  HR: ${r.pulse}`);
});
await emay.start();

// ... stream ...

await emay.stop();
```

### Rust

```rust
use emay_sleepo2::EMAYClient;

#[tokio::main]
async fn main() {
    let mut emay = EMAYClient::new().await?;
    emay.on_reading(|r| println!("SpO₂: {}%  HR: {}", r.spo2, r.pulse));
    emay.start().await?;
    tokio::time::sleep(Duration::from_secs(30)).await;
    emay.stop().await?;
}
```

### Go

```go
package main

import (
    "fmt"
    "time"
    emay "github.com/chenders/emay-sleepo2"
)

func main() {
    client, _ := emay.NewClient(emay.DefaultAdapter())
    client.OnReading = func(r emay.Reading) {
        fmt.Printf("SpO₂: %d%%  HR: %d\n", r.SpO2, r.Pulse)
    }
    client.Start()
    time.Sleep(30 * time.Second)
    client.Stop()
}
```

### Kotlin (Android)

```kotlin
val emay = EMAYClient(context)
emay.onReading = { reading ->
    println("SpO₂: ${reading.spo2}%  HR: ${reading.pulse}")
}
emay.start(scope = lifecycleScope)
```

## API Reference

Every binding exposes the same minimal interface:

```
class EMAYClient {
    // Lifecycle
    start()                  — connect and begin streaming
    stop()                   — stop streaming and disconnect
    isStreaming: bool        — whether currently streaming

    // Data
    onReading: (Reading) -> void   — called at ~1 Hz with new readings

    // Status
    status: Status           — Idle | Scanning | Connecting | Streaming | Failed
    onStatusChange: (Status) -> void

    // Advanced
    start(address)           — connect to a specific device by address
    batteryLevel: Int?       — battery percentage (after connection)
    heartbeatInterval: Duration — default 1.5s

    // CSV (parse only, no BLE)
    static parseCSV(data) -> [Reading]
    static parseCSVFile(path) -> [Reading]
}
```

## Reading Type

```
Reading {
    spo2: Int?          // SpO₂ percent (0–100), nil when finger off
    pulse: Int?         // Pulse rate in bpm, nil when no reading
    timestamp: Instant  // When this reading was captured
}
```

## The Protocol (tl;dr)

- BLE service `FF12`, write `FF01`, notify `FF02`
- Commands: `payload + sum(payload) & 0x7F`
- Start sequence: `hello → deviceState → startRealtime → getBattery`
- Sustain with a heartbeat command every ~1.5 s
- Data frames: 8 bytes — `EB 01 05 [PR] [SpO2] 7F 00 [cks]`
- Full specification: [`spec.md`](spec.md)

## Packages

| Language | Source           | Platform       | BLE Library    |
|----------|------------------|----------------|----------------|
| Swift    | [`swift/`](swift)| iOS/macOS      | CoreBluetooth  |
| Python   | [`python/`](python) | macOS/Linux/Windows/RPi | bleak |
| Node.js  | [`node/`](node)  | macOS/Linux/Windows/RPi | noble |
| Rust     | [`rust/`](rust)  | macOS/Linux/Windows | btleplug |
| Go       | [`go/`](go)      | macOS/Linux/Windows/embedded | TinyGo BLE |
| Kotlin   | [`kotlin/`](kotlin) | Android 8.0+ | Android BLE |

## CSM

The EMAY SleepO2 is a $30 continuous pulse oximeter capable of overnight streaming.
No public documentation existed for its protocol. We reverse-engineered it and
open-source the result so health-app developers, researchers, and tinkerers can
stream oxygen data without cracking the spec themselves.

## License

MIT
