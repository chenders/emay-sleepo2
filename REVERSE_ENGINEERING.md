# How the EMAY SleepO2 BLE protocol was reverse-engineered

This is the origin story of the protocol documented in [`SPEC.md`](SPEC.md) — a
blow-by-blow of how the EMAY SleepO2's real-time Bluetooth protocol was
decoded, verified against hardware, and turned into working code. It happened
in a single focused session, while working on another project of mine,
[AnxietyWatch](https://github.com/chenders/AnxietyWatch), an open-source
anxiety-tracking app. This SDK is that work, extracted and generalized so
other developers don't have to repeat it.

If you're only after the protocol itself, `SPEC.md` is the canonical
reference. This document is for anyone curious about the *process* — dead
ends included.

This document is independent of and not affiliated with, endorsed by, or
sponsored by EMAY. It's an unofficial account of decoding a device's own
Bluetooth traffic for interoperability — no vendor systems were touched and
no authentication or encryption was bypassed (the device uses none). Full
version: [A note on scope and ethics](#a-note-on-scope-and-ethics), at the
end.

---

## Why: CSV import wasn't enough anymore

EMAY had already been a supported data source in AnxietyWatch for two months
by this point, but only through the device's official flow: record overnight,
then share the exported CSV into the app after the fact. That's fine for
trend charts, but a new safety feature — an early-warning monitor for
CNS-depression risk (the interaction between sedating medications and
respiratory suppression) — needed **live** SpO₂ and pulse while someone is
actually asleep, not a file exported the next morning. (This SDK itself makes
no such claim on its own — see README.md's notice: it's the data pipe
underneath a safety feature, not a safety system by itself.)

There was no official path to that. EMAY publishes no BLE SDK, no API
documentation, and no real-time integration guide. The only way to find out
whether live streaming was even possible was to go looking for the protocol
directly.

## Step 1: Is there anything here at all?

The first move was the cheapest possible test: scan for the device with
[`bleak`](https://github.com/hbldh/bleak) (a cross-platform Python BLE
library) and see what it advertises.

It showed up immediately as `SleepO2-#_####`, broadcasting a proprietary
128-bit service built from the 16-bit UUID **`0xFF12`** — a classic
vendor-specific streaming service pattern. Manufacturer data decoded to an
ASCII firmware string (`"TA;DT260709"`). Better still: the device accepted a
GATT connection — GATT (Generic Attribute Profile) is the standard
framework BLE devices use to expose readable/writable/notifiable data
slots called characteristics — with **no pairing, no bonding, no
encryption**. That's the single biggest green light a reverse-engineering
effort can get — it means the protocol, once found, would be usable by
anyone without vendor cooperation.

Enumerating the connected GATT tree turned up two candidate notify
characteristics: `FF02` (paired with a `FF01` write characteristic, both
under the `FF12` service) and a second `FF04`/`FF05`/`FF06` trio under a
`FF00` service. Both looked plausible.

## Step 2: The wall — nothing streams on its own

Some OEM oximeters start streaming the instant you subscribe to their notify
characteristic. This one doesn't. Subscribing to both candidate
characteristics and just listening for 20 seconds — device on, finger on the
sensor — produced **zero notifications**.

That ruled out the easy case: this is a **command-gated** stream. Something
has to be written to a write characteristic before the device starts
sending data, and that command was completely unknown.

## Step 3: Confirming no one else had already solved this

Before spending hours guessing command bytes, it was worth checking whether
someone else had already published a decoder. A search turned up two
existing open-source BLE oximeter projects — but both targeted a Viatom /
Wellue "Checkme O2 / O2Ring" firmware family: a different 128-bit service
UUID entirely, and a completely different framing scheme (`0xAA`-prefixed
packets with a CRC-8 trailer, vs. this device's `FF12`/`FF01`/`FF02` layout
with an unknown checksum). Related product category, unrelated protocol —
useful as a pattern reference (both are "write a command, get a framed
response" designs), but not a shortcut. As far as the search could tell,
nobody had published a decoder for *this* firmware.

## Step 4: Decompiling the vendor Android app

With no public reference and no willingness to brute-force command bytes
blindly against real hardware, the deterministic path was to read the
official app's own source. `jadx` and `apktool` were already available
locally, so I obtained the APK manually and we were off.

Once `jadx` had it, decompiling ~5,000 classes surfaced the app's Bluetooth
layer almost immediately by grepping for the known UUIDs:

```
grep -rilE "ff0[1245]|ff12|0000ff" jadx-out --include=*.java
```

This landed on `com.fei.bluelibrary` — a small BLE transport library bundled
into the `com.jack.emaybloodoxygen` app — and confirmed the guess from
Step 1: the transport layer checks for service `0000ff12-…`, characteristic
`0000ff01-…` with the write property, before it will send anything.

## Step 5: A maze of single-letter classes

`com.fei.bluelibrary` was aggressively minified — most classes are named
`a.java` through `z6.java`, with no source-level names surviving
obfuscation. Still, the pattern was recoverable: every command is built as
`payload bytes + checksum`, where the checksum comes from one small shared
routine, and several separate builder classes construct different command
payloads (handshake, real-time start/stop, heartbeat, battery query). The
device's internal firmware family name, "S50," turned up repeatedly in
`Log.i()` tags and class names — the vendor's own label for this protocol
generation, not something invented for this write-up.

The checksum routine looked simple enough to read directly:

```java
public static byte a(List list, Integer num, Integer num2) {
    int iByteValue = 0;
    for (int iIntValue = num.intValue(); iIntValue < num2.intValue(); iIntValue++) {
        iByteValue = (iByteValue + (((Byte) list.get(iIntValue)).byteValue() & 255)) & 255;
        ...
```

That reads as "sum the bytes, mask with `0xFF`" — a completely reasonable
assumption for a checksum, and **wrong** in a way that cost the next hour.

(This six-line excerpt is the only vendor source quoted anywhere in this
repository, shown only as far as needed to document the checksum
algorithm for interoperability commentary. No decompiled code is reused in
the SDK itself — every language binding is written independently against
the recovered byte sequences below, not against this source.)

## Step 6: First live test — command bytes recovered, still silent

With a plausible checksum algorithm and command family in hand, the recovered
bytes were:

- Device state / handshake: `8E 05 93`
- Start real-time: `9B 01 9C`
- Heartbeat: `9A 9A`

Writing `9B 01 9C` to `FF01` and listening on `FF02` produced… nothing.
Neither did replaying a full handshake → start → heartbeat sequence with
write-with-response. Even the simple device-state query got no reply at all,
which was the strange part — a query, not a stream command, going completely
unanswered suggested the problem wasn't which command to send, but something
more fundamental about the session.

One command *did* get a response: writing `9B 7F 1A` (a variant the decompile
suggested might mean "stop") produced a real reply on `FF02` — `eb 7f 6a`,
which parses cleanly as an acknowledgment: response opcode `0xEB`, echoing
type `0x7F`, checksum `(0xEB + 0x7F) & 0xFF = 0x6A`. That this "stop" command
was the *only* one that worked triggered a wrong hypothesis (Step 7), but
it was actually a clue in disguise — its checksum happens to be identical
whether you mask with `0x7F` or `0xFF`, because both reductions land on the
same low byte for that particular sum. It was the one command guaranteed to
work no matter which mask was right, so it was never useful evidence for
picking between them.

## Step 7: A wrong turn — is "start" actually "stop"?

The one working command's type byte was `0x7F`. Reading further into the
decompile, that value also matched a named constant used elsewhere as a
"maximum" sentinel, which — combined with getting an ACK from it — led to a
brief, wrong theory: maybe `type = 0x7F` is *start* and `type = 1` is *stop*,
the reverse of the original assumption.

The way to settle it definitively was to find the actual UI code that fires
these commands, not the low-level builders. Locating the activity class
behind the app's "Real-time Display" screen (the same screen that, on a
physical test, showed a clean 96% SpO₂ / 68 bpm reading) resolved it: the
method that runs when that screen *opens* sends type `1`; the method that
runs when the user taps *stop* sends type `0x7F`. So the original reading was
right — `1` is start, `0x7F` is stop — and the `eb 7f 6a` response earlier had
simply been the device acknowledging a stop it was never really streaming
against in the first place.

Static analysis had now been pushed about as far as it could go without
either brute-forcing bytes against a real device (risky, slow, and rude to
the hardware) or capturing what the real app actually sends. Time to sniff
traffic.

## Step 8: Capturing real traffic with PacketLogger

Apple's `PacketLogger` (bundled with Xcode's Additional Tools) captures
Bluetooth HCI traffic. It has two capture modes that look almost identical in
the UI and behave completely differently: a default **local capture**, which
sniffs the Mac's own Bluetooth radio, and **File → New iOS Trace**, which
attaches to a connected iPhone over USB and captures *its* Bluetooth traffic
instead.

The first attempt used the wrong one. After installing Apple's Bluetooth
diagnostics logging profile on the phone (required for the phone to emit
loggable HCI events at all) and running a capture through a full EMAY
connect → stream → disconnect cycle, the resulting log showed only the Mac's
own local radio identifying itself — no EMAY traffic, no phone traffic at
all. The fix was the iOS-trace mode specifically: **File → New iOS Trace**,
picking the connected phone from the device list, *then* recording. Same
EMAY connect/stream/disconnect sequence, this time captured from the correct
radio.

## Step 9: The actual breakthrough

Parsing the real capture surfaced two corrections at once, and both of them
explain every failure up to this point in one stroke:

**The checksum mask is `0x7F`, not `0xFF`.** The decompiled checksum routine
does mask with `0xFF` in the snippet quoted above — but that's the *low-level
byte-store* mask (Java bytes are signed, so intermediate arithmetic gets
masked to fit in a byte). The actual command-layer routine referenced a
named constant — `WorkQueueKt.MASK`, an unrelated Kotlin coroutine internals
constant that happens to be `0x7F` — as its final mask before appending the
checksum. That's an easy thing to misread in heavily obfuscated,
decompiled-with-errors code, and it silently broke *every* command whose
correct checksum differs between the two masks. `9B 7F` happened to survive
either way (Step 6); everything else didn't.

**The real command bytes**, checksum-corrected:

```
89 09        hello / handshake
8E 05 13     device state query
9B 01 1C     start real-time (mode 1)
86 06        get battery
9A 1A        heartbeat (repeat ~every 1.5s)
9B 7F 1A     stop real-time
```

And the **data frame format** on `FF02`, decoded against a live packet and
checksum-verified:

```
eb 01 05 44 5e 7f 00 12
│  │  │  │  │  │  │  └─ checksum: sum(bytes[0..6]) & 0x7F
│  │  │  │  │  │  └──── reserved, always 0x00
│  │  │  │  │  └─────── trailer, always 0x7F
│  │  │  │  └────────── SpO2 = 0x5E = 94%
│  │  │  └───────────── pulse = 0x44 = 68 bpm
│  │  └──────────────── payload length (5 bytes follow)
│  └─────────────────── protocol version
└────────────────────── frame marker
```

Checksum arithmetic, worked by hand as a sanity check against a second live
packet (`eb 01 05 3e 5f 7f 00 0d`):
`0xEB + 0x01 + 0x05 + 0x3E + 0x5F + 0x7F + 0x00 = 525`; `525 & 0x7F = 13 =
0x0D` — matching the packet's trailing byte exactly.

## Step 10: Live verification

A small `bleak`-based Python script implementing the corrected sequence —
hello → device state → start real-time → get battery, then a heartbeat every
1.5 seconds — connected, sent the sequence, and started printing real,
continuously updating readings: SpO₂ in the mid-90s, pulse ticking between
61 and 62 bpm as an actual pulse does, matching what the device's own screen
showed at the same moment. That was the point the protocol counted as
decoded rather than theorized.

## Step 11: From a Python script to production Swift

The Python reader proved the protocol; shipping it in AnxietyWatch meant a
CoreBluetooth implementation. The port split cleanly into two pieces on
purpose:

- A pure, hardware-independent protocol layer (checksum, command framing,
  frame parsing) with no Bluetooth dependency at all — fully unit-testable
  against the exact byte sequences captured from the real device, so the
  protocol logic can never silently regress.
- A thin CoreBluetooth driver on top, responsible only for the state
  machine: scan, connect, discover characteristics, subscribe, drive the
  command sequence, run the heartbeat timer, and hand parsed readings to the
  rest of the app.

## What shipped

Three pull requests landed in AnxietyWatch the same day: the protocol +
CoreBluetooth service itself, a live status view surfacing it in Settings,
and integration into the app's trend charts — on top of the CSV-only import
path that had already existed for two months. The full protocol was also
written down in durable form immediately after it was decoded, specifically
so it would never have to be re-derived from scratch.

## Epilogue: this SDK

The reverse-engineered protocol lived inside AnxietyWatch as
AnxietyWatch-specific Swift for a while. *This repository* is that protocol
knowledge extracted into a standalone, dependency-light, multi-language form
— the same command bytes, the same checksum, the same frame layout,
documented once in [`SPEC.md`](SPEC.md) and implemented independently across
Swift, Python, Node.js, Rust, Go, and Kotlin, so the next person who owns one
of these devices doesn't have to repeat any of the above.

## Tools used

| Tool | Role |
|------|------|
| [`bleak`](https://github.com/hbldh/bleak) | Cross-platform Python BLE scan/connect/notify — the initial probing and the final live-verification script |
| `jadx` | Decompiled the vendor Android APK to readable (if obfuscated) Java |
| `apktool` | Available as a fallback decompiler; `jadx` proved sufficient |
| Apple `PacketLogger` (Xcode Additional Tools) | Captured real Bluetooth HCI traffic from a connected iPhone running the vendor's official app, via **File → New iOS Trace** |
| Apple's Bluetooth diagnostics logging profile | Required on the iPhone before PacketLogger's iOS-trace mode can capture anything from it |
| `grep` over the decompiled source tree | The actual workhorse — locating UUID constants, command builders, and the checksum routine |

## A note on scope and ethics

This work connects to a consumer device you already own, using the same
unauthenticated Bluetooth GATT interface its own official app uses, to read
the same data that app already displays to you. No firmware was modified, no
authentication or encryption was bypassed (the device uses none), and no
vendor systems or servers were touched — everything here happened between a
local computer, a Bluetooth radio, and a piece of hardware sitting on a
desk. This document exists so the process is reproducible and so this
protocol doesn't need to be reverse-engineered a second time by anyone else.
