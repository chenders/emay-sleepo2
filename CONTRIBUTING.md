# Contributing

## Adding a new language binding

Each language binding should expose the [same core API](README.md#api-reference):

- `EMAYClient` with `start()`, `stop()`, `isStreaming`, `onReading`
- `EMAYProtocol` with `parseReading(raw)`, `checksum(payload)`, prebuilt commands
- `LiveDownsampler` with `add(reading)` and `flush()`

### Checklist for a new binding

1. Implement the protocol layer first — checksums, frame parsing, sentinel detection
2. Write tests against the raw-byte fixtures (same test cases as Swift/Python)
3. Implement the BLE client on top of the platform's BLE stack
4. Add a CI job in `.github/workflows/ci.yml`
5. Add a publish job in `.github/workflows/publish.yml`
6. Document in `README.md` quick-start section

### Test conventions

All tests must pass these cases:

- **Checksum**: verify `0x89 → 0x09`, `0x9A → 0x1A`, `0x9B,0x01 → 0x1C`
- **Frame parse**: valid 8-byte frame → correct spo2/pulse
- **Sentinels**: `0x00` and `0xFF` in byte 3 or 4 → nil for that field
- **Plausibility**: pulse < 30 or > 220 → nil; spo2 > 100 → nil
- **Downsampler**: ≤ min count → no output; 2+ samples → mean output; minute boundary → flush

## Protocol changes

The protocol spec (`SPEC.md`) is the source of truth. If you discover new
behavior (e.g., a firmware variant with different frame format), update
`SPEC.md` first, then implement in all language bindings.

## Pull requests

- Branch from `main`
- Run the language's test suite before opening the PR
- CI runs all languages — green CI is required to merge
