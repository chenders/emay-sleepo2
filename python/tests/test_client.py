"""Tests for EMAYClient status callbacks."""

import asyncio

from emay_sleepo2.client import EMAYClient
from emay_sleepo2.types import Status


def test_scan_failure_fires_failed_once(monkeypatch):
    async def no_device(*args, **kwargs):
        return None

    monkeypatch.setattr("emay_sleepo2.client.BleakScanner.find_device_by_filter", no_device)

    client = EMAYClient()
    statuses = []
    client.on_status_change = statuses.append

    asyncio.run(client.start())

    assert statuses == [Status.SCANNING, Status.FAILED]


def test_connect_failure_fires_failed_once(monkeypatch):
    class FakeDevice:
        address = "AA:BB:CC:DD:EE:FF"
        name = "SleepO2 Test"

    async def found_device(*args, **kwargs):
        return FakeDevice()

    class FailingBleakClient:
        def __init__(self, device, disconnected_callback=None):
            pass

        async def connect(self):
            raise OSError("connect refused")

    monkeypatch.setattr("emay_sleepo2.client.BleakScanner.find_device_by_filter", found_device)
    monkeypatch.setattr("emay_sleepo2.client.BleakClient", FailingBleakClient)

    client = EMAYClient()
    statuses = []
    client.on_status_change = statuses.append

    asyncio.run(client.start())

    assert statuses == [Status.SCANNING, Status.CONNECTING, Status.FAILED]
