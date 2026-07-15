#!/usr/bin/env python3
"""Quick CLI test for the EMAY SleepO2 BLE SDK.

Make sure your EMAY SleepO2 is on and nearby, then run:

    pip install emay-sleepo2[ble]
    python live_demo.py

Press Ctrl-C to quit cleanly.
"""

import asyncio
import logging
import signal
import sys
from datetime import datetime

# If running from the repo root, add python/src to the path
# so we use the local package. Installed users get it from pip.
try:
    from emay_sleepo2 import EMAYClient, Status
except ImportError:
    import os

    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "python", "src"))
    from emay_sleepo2 import EMAYClient, Status


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def ts() -> str:
    """Current time as HH:MM:SS."""
    return datetime.now().strftime("%H:%M:%S")


def hr(bpm: int | None) -> str:
    """Pretty-print a heart rate value (None → '--')."""
    return (
        f"\033[91m{bpm:>3}\033[0m bpm" if bpm is not None else "\033[90m --\033[0m bpm"
    )


def spo2(pct: int | None) -> str:
    """Pretty-print an SpO₂ value (None → '--')."""
    return f"\033[94m{pct:>3}\033[0m %" if pct is not None else "\033[90m --\033[0m %"


# ANSI colours
BOLD = "\033[1m"
DIM = "\033[2m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
CYAN = "\033[36m"
RESET = "\033[0m"


# ---------------------------------------------------------------------------
# callbacks
# ---------------------------------------------------------------------------


def on_reading(reading) -> None:
    """Called ~1×/second while streaming."""
    print(
        f"{DIM}[{ts()}]{RESET}  SpO₂ {spo2(reading.spo2)}   │   HR {hr(reading.pulse)}"
    )


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def setup_logging() -> None:
    """Surface the SDK's own log messages (INFO+) while keeping bleak quiet.

    Without this, warnings like a disconnect that leaves the link up would be
    emitted by the SDK but never printed, since Python logging is silent by
    default. We keep the root at WARNING so third-party libs don't spam, and
    lift just the SDK logger to INFO so its teardown diagnostics show through.
    """
    logging.basicConfig(
        level=logging.WARNING,
        format=f"{DIM}[%(asctime)s]{RESET} {YELLOW}%(levelname)s{RESET} %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )
    logging.getLogger("emay_sleepo2").setLevel(logging.INFO)


async def main() -> None:
    print(f"\n{BOLD}{CYAN}EMAY SleepO2 — Live Demo{RESET}\n")
    print(f"{DIM}Make sure your device is on and within Bluetooth range.{RESET}")
    print(f"{DIM}Press {BOLD}Ctrl-C{RESET}{DIM} to stop.{RESET}\n")

    setup_logging()

    client = EMAYClient()

    def on_status(status: Status) -> None:
        """Print each state change; on FAILED, add the best-effort reason hint."""
        emoji = {
            Status.IDLE: "💤",
            Status.SCANNING: "🔍",
            Status.CONNECTING: "🔗",
            Status.STREAMING: "📡",
            Status.FAILED: "❌",
        }
        e = emoji.get(status, "")
        label = status.name.capitalize()
        print(f"{DIM}[{ts()}]{RESET} {e} {BOLD}{GREEN}{label}{RESET}")
        if status == Status.FAILED and client.failure_reason.message:
            print(
                f"{DIM}[{ts()}]{RESET}    ↳ {YELLOW}{client.failure_reason.message}{RESET}"
            )

    client.on_status_change = on_status
    client.on_reading = on_reading

    # Handle Ctrl-C gracefully
    stop_event = asyncio.Event()

    def _sig_handler() -> None:
        print(f"\n{DIM}[{ts()}]{RESET} 🛑 {YELLOW}Shutting down…{RESET}")
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _sig_handler)
        except NotImplementedError:
            # Windows doesn't support add_signal_handler
            signal.signal(sig, lambda s, f: _sig_handler())

    try:
        await client.start()

        # Keep running until Ctrl-C
        await stop_event.wait()

    finally:
        await client.stop()
        print(f"{DIM}[{ts()}]{RESET} ✅ {GREEN}Done.{RESET}")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass  # handled by signal handler above
