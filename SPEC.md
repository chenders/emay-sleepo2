# EMAY SleepO2 BLE Protocol Specification

> Reverse-engineered from the EMAY SleepO2 "S50" firmware. The device is a
> consumer pulse oximeter (~$30–40) that streams SpO₂ and pulse rate at 1 Hz
> over Bluetooth Low Energy. As far as we've been able to find, no public
> documentation existed prior to this — see
> [`REVERSE_ENGINEERING.md`](REVERSE_ENGINEERING.md) for how it was
> recovered. This document is unofficial and not affiliated with EMAY.

**Contents:** [Hardware](#hardware) · [Scope & Compatibility](#scope--compatibility)
· [GATT Profile](#gatt-profile) · [Command Protocol](#command-protocol) ·
[Data Frame Format](#data-frame-format) · [Revision History](#revision-history)

## Hardware

| Attribute       | Detail                                         |
|-----------------|------------------------------------------------|
| Device name     | SleepO2 (advertised local name prefix)         |
| Firmware        | S50 (confirmed on 2026 unit)                   |
| Connection      | Bluetooth Low Energy 4.0+                      |
| Stream rate     | ~1 Hz (one frame per second with finger on)    |

## Scope & Compatibility

Everything in this document is confirmed against a single physical unit
running "S50" firmware, captured in 2026. It is not confirmed against other
SleepO2 hardware or firmware revisions, regional SKUs, or the vendor's
other device models.

If you own a SleepO2 (or a similarly-branded EMAY device) and find it
doesn't match this spec — different service/characteristic UUIDs, a
handshake that doesn't respond, or a frame layout that doesn't parse —
please open an issue with the device's advertised local name,
manufacturer data, and firmware string (visible during a raw BLE scan)
plus a description of what diverges. Treat a mismatch as a firmware
variant to document, not a bug in your client.

This is spec version 1.0 — see [Revision History](#revision-history).

## GATT Profile

| Role                | UUID   | Type                  |
|---------------------|--------|-----------------------|
| Primary service     | `FF12` (full: `0000FF12-0000-1000-8000-00805F9B34FB`) | —                     |
| Write characteristic | `FF01` (full: `0000FF01-0000-1000-8000-00805F9B34FB`) | Write with response   |
| Notify characteristic| `FF02` (full: `0000FF02-0000-1000-8000-00805F9B34FB`) | Notifications         |

All writes use **write-with-response**. Commands are serialized — do not issue
the next command until the write completion callback fires.

**Security**: Security Mode 1, Level 1 — no pairing, no bonding, no
encryption. The device accepts an open GATT connection from any central.

**Enabling notifications**: After discovering `FF02`, write `0x01 0x00` to
its Client Characteristic Configuration Descriptor (CCCD, UUID `0x2902`)
to subscribe, before issuing the Start Sequence below. Most BLE platform
APIs (CoreBluetooth, bleak, noble, btleplug, Android `BluetoothGatt`) do
this as part of their "subscribe to notifications" call — but if you're
implementing directly against a raw GATT client, this write is easy to
forget and the symptom is silence: commands appear to succeed but no data
frame ever arrives.

**Discovery**: Scan for `FF12` service UUID. Optionally filter by advertised
local-name prefix `SleepO2` as defense-in-depth against other products
advertising a colliding vendor-specific UUID. Accept a nameless device
rather than risk rejecting a genuine unit whose name isn't available.

## Command Protocol

### Checksum Algorithm

Every command is `payload + checksum` where:

```
checksum = sum(payload bytes) & 0x7F
```

The `0x7F` mask (NOT `0xFF`) is critical. A `0xFF` mask produces incorrect
checksums that the device silently ignores — commands appear to succeed but
produce no response.

### Command Reference

| Command       | Payload    | Full Frame   | Purpose                        |
|---------------|------------|--------------|--------------------------------|
| Hello         | `89`       | `89 09`      | Open handshake                 |
| Device State  | `8E 05`    | `8E 05 13`   | Query device status            |
| Start Realtime| `9B 01`    | `9B 01 1C`   | Begin streaming (mode 1)       |
| Stop Realtime | `9B 7F`    | `9B 7F 1A`   | End streaming (mode 0x7F)      |
| Get Battery   | `86`       | `86 06`      | Query battery level            |
| Heartbeat     | `9A`       | `9A 1A`      | Keep-alive sustain             |

### Start Sequence

Ordered and serialized — each command's write-with-response must complete
before the next is issued:

```
hello → deviceState → startRealtime → getBattery
```

None of `hello`, `deviceState`, `startRealtime`, or `getBattery` produce a
distinguishable application-level reply payload on `FF02` — "acknowledged"
here means the ATT write-with-response completed successfully at the GATT
layer, nothing more. Do not wait for a notification before issuing the
next queued command in the sequence. Once `startRealtime` is acknowledged,
the device begins sending data frames on the notify characteristic.

### Sustain (Heartbeat)

Clients **must** send a heartbeat at an interval no greater than 2
seconds. The device stops transmitting after approximately 3–4 seconds
without one — implementations use 1.5s as a comfortable safety margin
below that cutoff. The start sequence does **not** need to be replayed
after a heartbeat gap — just resume heartbeats.

### Stop Sequence

Send `stopRealtime` before disconnecting. The device stops streaming and
the BLE connection can be torn down.

## Data Frame Format

Real-time data arrives on notify characteristic `FF02` as exactly **8 bytes**:

```
Byte 0:  [magic]     0xEB — frame start marker
Byte 1:  [version]   0x01 — protocol version/flags
Byte 2:  [length]    0x05 — payload length (5 bytes follow)
Byte 3:  [pulse]     PR — pulse rate, uint8, beats per minute
Byte 4:  [spo2]      SpO2 — oxygen saturation, uint8, percent (0–100)
Byte 5:  [trailer]   0x7F — fixed sentinel
Byte 6:  [reserved]  0x00 — always zero
Byte 7:  [checksum]  sum(bytes[0..<7]) & 0x7F
```

### Sentinel Values

The device signals "no finger detected" with these byte values in the
pulse and SpO₂ fields:

```
No pulse:  PR = 0x00 or PR = 0xFF
No SpO₂:   SpO2 = 0x00 or SpO2 = 0xFF
```

A single frame can carry a valid pulse with no SpO₂ (finger partially off),
or vice versa. All other byte values (1–254) are **genuine physiological
readings** — the protocol does not reuse the sentinel range for any other
purpose.

Check sentinel values **before** applying the plausibility ranges below.
`SpO2 == 0x00` is always "no reading," never a genuine 0% — even though
0 technically falls inside the plausibility range's lower bound.

### Frame Validation

All of the following checks must pass. Reject the entire frame if any fails:

1. Exact 8-byte frame length
2. Header bytes match: `[0] == 0xEB, [1] == 0x01, [2] == 0x05`
3. Trailer bytes match: `[5] == 0x7F, [6] == 0x00`
4. Checksum: `sum(bytes[0..<7]) & 0x7F == bytes[7]`

Notifications on `FF02` that aren't exactly 8 bytes **must be silently
ignored**, not treated as a malformed data frame — frame length is checked
first for exactly this reason. Rejecting a frame (of any length) should
never be treated as a fatal error; log it if useful, but keep streaming.

### Application-Level Plausibility Ranges

The BLE checksum validates transport integrity. Beyond that, apply
physiological plausibility guards to reject corrupted bytes that happen
to pass the checksum:

| Field     | Range        | Rationale                                              |
|-----------|--------------|--------------------------------------------------------|
| Pulse     | 30–220 bpm   | Below 30 = asystole/brady-asystole (corrupted byte);   |
|           |              | above 220 exceeds adult max HR (corrupted)              |
| SpO₂      | 0–100%       | Above 100% is non-physiological                        |

Values **inside** these ranges are trusted as genuine, even if extreme.
Silently filtering a real 40 bpm bradycardia or 70% SpO₂ because it
"looks implausible" is a false-reassurance hazard for medical monitoring.

### DST Fall-Back Fold Correction

On the night clocks fall back, the 1:00–2:00 AM hour repeats — producing
duplicate wall-clock timestamps. Without correction, the repeated hour's
samples collide in deduplication and an hour of real data silently
vanishes.

**Detection algorithm**: Track the previous corrected timestamp. When a
backward jump of 5–7200 seconds is detected, cross-check: if the parse
timezone actually transitioned clocks back within ±2 hours of the jump,
add 3600 seconds of correction. The correction accumulates across multiple
folds (rare but possible with device-resets) and auto-resets when the
naive parse catches up to the corrected timeline.

A backward jump with **no nearby DST transition** (device clock resync,
manual time change) is left untouched — falsifying monotonicity would
shift the entire night's timestamps an hour, which is worse than
reporting the discontinuity honestly.

**Worked example** (US fall-back, clocks repeat 1:00–2:00 AM local time):

```
11/1/2026,1:58:00 AM,97,58   -> parsed 01:58:00 (first pass)
11/1/2026,1:59:00 AM,97,59   -> parsed 01:59:00
11/1/2026,1:00:00 AM,96,58   -> parsed 01:00:00  <- backward jump of 3540s
```

The jump from `01:59:00` to `01:00:00` is 3540 seconds — inside the
5–7200s detection window. Cross-checking confirms a DST fall-back
transition at 2:00 AM in the file's timezone, within ±2 hours of the
jump, so row 120 onward gets +3600s applied: row 120 becomes `02:00:00`,
preserving chronological order and disambiguating it from row 118's
`01:58:00` rather than colliding with it.

## Revision History

| Version | Date | Change |
|---------|------|--------|
| 1.0 | 2026-07-09 | Initial publication. Reverse-engineered and verified against one EMAY SleepO2 unit running "S50" firmware. |
