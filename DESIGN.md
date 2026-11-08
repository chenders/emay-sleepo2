# Design System: EMAY SleepO2 BLE SDK
**Project ID:** None. This is not a Stitch project; the system is derived from the repository's own illustrations (`banner.svg` and `diagrams/*.svg`).

## 1. Visual Theme & Atmosphere

A **nocturnal, instrument-panel** aesthetic: dark, quiet, and technical. That suits a device worn overnight. Every illustration reads like the glowing readout of a bedside monitor in a dark room. The mood is **calm, precise, and legible**: dense with real protocol data (byte values, UUIDs, state names) but never cluttered, because each scene has one focal point that is lit up and everything else recedes into muted slate.

The visual language mixes two registers:

- **Hardware mockups:** a stylized oximeter and phone, drawn as simple rounded slabs with inset screens. These make abstract protocol events physical.
- **Data diagrams:** byte chips, state cards, and connection arcs that annotate the wire format.

Motion is **purposeful and sparse**: pulsing radio ripples, a scrolling ECG trace, payload bytes that softly breathe. Every animation honors `prefers-reduced-motion` by freezing on its most informative frame, never on an empty one.

## 2. Color Palette & Roles

**Foundations (the night)**
- **Midnight Ink** (#0c1219 → #090d12): the canvas, a near-black vertical gradient behind every illustration. It sets the "dark room" tone.
- **Deep Slate Navy** (#12202b): fill for cards, byte chips, and device bodies; the primary surface one step above the canvas.
- **Graphite Shell** (#161f28): the oximeter's casing, slightly warmer than the card surface so the hardware reads as a physical object.
- **Screen Black** (#0b141a): inset device screens, darker than the card that holds them, so they read as recessed glass.
- **Hairline Slate** (#1a2530): the 1px frame stroke around every canvas, barely visible and only there to define the edge.
- **Muted Steel Border** (#2b3a48): resting stroke on neutral cards and device bodies.

**Text**
- **Frost White** (#e8eef2): highest-emphasis text, such as headline numbers at rest (14–16:1 contrast).
- **Pale Silver** (#c9d3db): primary labels and state names (11–12:1).
- **Fog Gray** (#8798a6): secondary captions, annotations, field names, and neutral connector lines. It is the most-used color in the system (5.6–6.3:1).
- **Dusk Steel** (#5f7688): leader lines from byte chips to their labels; decorative only, never used for text.

**Signal (the meaning-bearing colors)**
- **Electric Teal-Cyan** (#2ee6c8): *the Bluetooth link*. Radio ripples, connection arcs, active transitions, and chip outlines. The project's signature color.
- **Glacier Mint** (#7ff0dd): text set on teal-outlined elements (byte values, the `SPEC.md` card title), a lighter teal so values read clearly inside teal frames.
- **Vital Green** (#57d68d): *healthy, live readings*, such as the SpO₂ number on the device screen, status LEDs, and "success" transition labels like `start()`, `found` and `ack'd`.
- **Payload Gold** (#ffcf5c): *the live data itself*. Reserved for the pulse and SpO₂ bytes of a frame, the only bytes that carry measurements. Bytes "are born gold" and settle to their resting color once decoded. Paired with **Amber Shadow** (#241b0c) as a chip fill and **Old Brass** (#c9a04a) for its leader lines.
- **Alarm Coral** (#ff5c6c): *failure and broken links*. Error glyphs, dashed failure paths, and the broken-connection zig-zag.
- **Soft Rose** (#ff8a95): text on failure states, a lighter coral for readability. Paired with **Bruised Plum** (#161016) as the fill and **Oxblood** (#4a2229) as the border of the Failed state card.

**Why:** Color in this system is *semantic, never decorative*. Teal means "radio", green means "healthy reading", gold means "this byte carries the measurement", coral means "failed". A reader who learns the code in one diagram can read every other diagram without a legend.

## 3. Typography Rules

- **Family:** a single monospace stack throughout: `ui-monospace, 'SF Mono', Menlo, monospace`. Byte values, UUIDs and code identifiers are the content, so the whole system speaks in the voice of a terminal or hex dump. Columns of hex align naturally.
- **Weight:** a strict two-weight system. **Bold (700)** is used for anything the eye should land on: byte values, state names, card titles, readings. Regular weight is used for captions and explanatory annotations. There are no intermediate weights.
- **Scale:** compact and fine-grained, tuned for diagrams rather than pages:
  - Hero numerals: 34px (rare, banner only)
  - Device readouts and emphasis: 15–18px
  - Byte values and card titles: 13–15px
  - Labels: 11.5–12.5px (the workhorse range)
  - Transition labels and footnotes: 9–10.5px
- **Style:** italics only for secondary procedural notes (e.g., "start(address) skips to Connecting"). Labels are centered under the element they describe. Letter-spacing is left at the monospace default.

## 4. Component Stylings

* **Buttons:** None exist; the illustrations are non-interactive. If an interactive surface is ever built, derive buttons from the byte chip: a Deep Slate Navy fill, a 1.5px Electric Teal-Cyan outline, and gently rounded corners (8px). Glacier Mint bold label.
* **Cards/Containers:**
  - *Canvas frame:* generously rounded corners (18px) on a Midnight Ink gradient, with a Hairline Slate inner stroke inset by 1px (17px radius).
  - *Byte chips:* small, gently rounded tiles (8px corners), Deep Slate Navy fill, 1.5px teal outline. *Payload variant:* Amber Shadow fill with a slightly heavier 2px gold outline and a slow breathing opacity pulse (0.7 → 1.0).
  - *State cards (lifecycle):* tall rounded slabs (14px corners) with a recessed Screen Black inset (6px corners), like miniature phone screens. *Failure variant:* Bruised Plum fill with an Oxblood border.
  - *Device mockups:* softly rounded hardware slabs (14–16px corners) with darker inset screens (8–10px corners).
  - *Info cards* (e.g., the `SPEC.md` card): 12px corners with a teal outline that signals "this is the key".
* **Inputs/Forms:** None exist. Should one be needed, use a Screen Black recessed field with a Muted Steel Border stroke that brightens to teal on focus.
* **Lines & connectors:** solid 2px teal lines for successful transitions; dashed lines for alternative or failure paths (coral `3 6` dashes for failures, gray `2 5` dashes for deliberate or optional paths); thin Dusk Steel leader lines for annotation. Line caps are round.

**Depth & elevation:** The system is **flat and shadowless**. There are no drop shadows or blurs anywhere. Depth is expressed only through **tonal stepping**: canvas (darkest) → card surface → recessed screen (darker again). The only "light" in the system is emitted: glowing signal colors on dark surfaces, like LEDs.

## 5. Layout Principles

- **Wide, landscape canvases** (roughly 640–880px wide × 260–450px tall), sized to sit inline in a GitHub README or spec at native resolution.
- **Generous dark negative space.** Elements float on the canvas with room around them, and the darkness itself is part of the composition.
- **Left-to-right narrative flow.** Sequences (state lifecycle, frame bytes, handshake) read like a timeline. Failure branches drop *downward* from the happy path.
- **Strict rhythmic grids** where data is involved. For example, byte chips sit on a fixed 72px pitch (62px chip + 10px gutter), with labels alternating above and below to avoid crowding.
- **One focal point per scene.** Gold or teal marks what matters, and everything else stays in Fog Gray.
- **Accessibility is part of the layout.** Every SVG carries `role="img"` with a `<title>` and a full `<desc>` narrating the scene, all text meets WCAG AA contrast against its surface, and motion respects reduced-motion preferences.
