# Connection Failure Reason — Design

**Date:** 2026-07-15
**Status:** Approved (design), implementation in progress
**Feature:** Replace the opaque `FAILED` status with a structured, best-effort
`FailureReason` so callers can tell *why* a session failed — in particular, that
the device may be **connected to another app** rather than simply absent.

## Motivation

When a monitoring session fails, every binding currently collapses the cause
into a single opaque `Status.FAILED`. The user cannot distinguish:

- the device was never found (off / out of range / **busy with another app**), from
- the device was found but the connection or GATT setup failed.

The original request: *"ideally be able to see if it's connected elsewhere and
let the user know that, through the API, rather than an opaque message."* This
matters because the SleepO2 is **single-central** — when the EMAY app or
AnxietyWatch holds the connection, our client can't get in, and today that looks
identical to the device being off.

## Key constraint: "busy elsewhere" is NOT reliably detectable in-band

This was established empirically, not assumed:

- **PacketLogger captures** (`lots-o-weird.pklg`, `during_experiment.pklg`): the
  device advertises as connectable only while idle, and goes silent the instant
  it connects to any central (advertising resumes ~19 ms after release).
- **Mac probe (decisive)** — an independent second scanner: while the device was
  connected to the phone, a 12 s scan saw **nothing**, and a direct connect to
  the device's CoreBluetooth identifier **timed out → `BleakDeviceNotFoundError`**
  after the full window. Identical signature to "off / out of range."

**Why it's fundamental, not incidental:** BLE connection establishment is
*advertisement-gated* — a central can only initiate a connection in response to a
connectable advertisement. A device connected elsewhere stops advertising, so it
never hears a connection request and emits nothing in response. There is no
"busy" NAK at the link layer; "busy" manifests as "not advertising," which is
radio-indistinguishable from "powered off." A normal BLE central
(CoreBluetooth / bleak / noble / btleplug / Android `BluetoothGatt`) cannot see
it. Only a **promiscuous over-the-air sniffer** (e.g. an nRF52840 dongle running
nRF Sniffer) could observe the device's ongoing connection and infer "alive and
busy" — that is out-of-band hardware and out of scope for the SDK.

**Consequence:** we surface an honest *enumerated hint*, not a false-certain
`BUSY`. `NOT_FOUND` names "connected to another app" as one of the possibilities.

## Design

### `FailureReason` (new enum, per binding)

| Value | Meaning |
|-------|---------|
| `NONE` | Not in a failed state (default). |
| `NOT_FOUND` | Scan completed without discovering the device. Could be off, out of range, **or connected to another app**. |
| `CONNECTION_FAILED` | The device *was* discovered, but connecting or GATT service/characteristic setup failed. |

Each binding exposes a reason → human-readable **message** helper so the text is
consistent everywhere:

- `NOT_FOUND` → *"Device not found — it may be off, out of range, or connected to
  another app (the SleepO2 allows only one connection at a time)."*
- `CONNECTION_FAILED` → *"Found the device but the connection failed — it may
  have moved out of range or been taken by another app mid-connect."*
- `NONE` → `""`.

### Client surface

- A read-only accessor `failure_reason` (property / getter, per language idiom).
- Set to the appropriate reason **immediately before** every transition to
  `FAILED`.
- Reset to `NONE` at the start of `start()`.
- **Non-breaking:** the `Status` enum, the 5-state machine, and the
  `on_status_change` callback signature are all **unchanged**. Consumers read
  `failure_reason` when they observe `FAILED`. This keeps the state machine
  identical across bindings, which `SPEC.md` documents.

### Classification rules (where each reason is set)

| Code path | Reason |
|-----------|--------|
| Scan/discovery completes with no device (scan timeout) | `NOT_FOUND` |
| `connect()` throws / connection fails | `CONNECTION_FAILED` |
| Service or characteristics not found after connect | `CONNECTION_FAILED` |

Adapter-level failures that already have dedicated states (`BLUETOOTH_OFF`,
`BLUETOOTH_UNAUTHORIZED`, `BLUETOOTH_UNSUPPORTED` where present) keep those
states and are out of scope for `FailureReason`.

### Demos

`live_demo.py` (and each binding's demo where one exists) prints the
`failure_reason.message` on `FAILED` instead of a bare "Failed".

## Non-goals (explicit)

- **No hard `BUSY` / `CONNECTED_ELSEWHERE` status** — not reliably detectable
  in-band (see above).
- **No session-history heuristic** for this iteration (e.g. "we were streaming,
  then it vanished → probably taken by another app"). The user chose the simplest
  cold-start hint; the heuristic is a possible future refinement.
- **No sniffer integration.** True "busy" detection requires an external
  over-the-air sniffer (nRF52840 + nRF Sniffer) and is noted as a future,
  hardware-dependent option only.

## Testing

Deterministic, mock-based (no hardware needed):

- scan-not-found → `Status.FAILED` + `failure_reason == NOT_FOUND`.
- connect-failure → `Status.FAILED` + `failure_reason == CONNECTION_FAILED`.
- `failure_reason` resets to `NONE` on a subsequent `start()`.

Plus an opportunistic on-device check of the `NOT_FOUND` path (scan with the
device off/busy) where hardware is available.

## Rollout

1. **Python** reference implementation + tests, verified.
2. Propagate the same `FailureReason` enum + `failure_reason` accessor +
   classification to every binding that has a live client: Rust, Go, Node,
   Swift, Kotlin, Java, Scala, C#, C++ (and the C / PHP reference stubs where it
   is meaningful to define the enum).
3. Document `FailureReason` in `SPEC.md` under the Client Connection Lifecycle,
   including *why* in-band busy detection is impossible and the sniffer as a
   future option.

## SPEC.md addition (summary)

A short subsection under **Client Connection Lifecycle** introducing
`FailureReason` as a parallel, best-effort detail on the `FAILED` state (the
state machine itself is unchanged), the `NOT_FOUND` vs `CONNECTION_FAILED`
distinction, and a note that "connected to another app" is not distinguishable
from "off / out of range" without an external sniffer.
