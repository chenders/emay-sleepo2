/*
 * EMAY SleepO2 — C++ types, protocol, and SimpleBLE client
 * Copyright (c) 2026 Ground Effect Software, LLC · MIT
 *
 * Cross-platform BLE via SimpleBLE (https://simpleble.org).
 *   Linux:   BlueZ backend
 *   macOS:   CoreBluetooth backend
 *   Windows: WinRT backend
 *
 * Install: see https://github.com/OpenBluetoothToolbox/SimpleBLE
 * Build:   cmake -B build && cmake --build build
 */
#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace emay {

/* ---- Types ---- */

struct Reading {
    std::optional<int> spo2, pulse;
    double timestamp_secs = 0;
};

struct MinuteSample {
    double minute_start_secs;
    std::string metric_type;  // "SpO2" | "PulseRate"
    double value;
    std::string unit_string;  // "%" | "count/min"
};

using ReadingCallback = std::function<void(const Reading&)>;
using StatusCallback  = std::function<void(const std::string&)>;

/* ---- Protocol ---- */

inline constexpr const char* SVC_UUID = "0000ff12-0000-1000-8000-00805f9b34fb";
inline constexpr const char* WR_UUID  = "0000ff01-0000-1000-8000-00805f9b34fb";
inline constexpr const char* NFY_UUID = "0000ff02-0000-1000-8000-00805f9b34fb";
inline constexpr const char* NAME_PFX = "SleepO2";

inline uint8_t checksum(const std::vector<uint8_t>& p) {
    uint16_t s = 0; for (auto b : p) s += b; return s & 0x7F;
}

inline std::vector<uint8_t> command(std::vector<uint8_t> p) {
    p.push_back(checksum(p)); return p;
}

inline std::optional<Reading> parse(const std::vector<uint8_t>& raw) {
    if (raw.size() != 8) return {};
    if (raw[0] != 0xEB || raw[1] != 1 || raw[2] != 5) return {};
    if (raw[5] != 0x7F || raw[6] != 0) return {};
    uint16_t s = 0; for (int i = 0; i < 7; i++) s += raw[i];
    if (raw[7] != (uint8_t)(s & 0x7F)) return {};
    int pr = raw[3], so = raw[4];
    auto sentinel = [](uint8_t b) { return b == 0 || b == 0xFF; };
    Reading r;
    if (!sentinel(raw[3])) { if (pr < 30 || pr > 220) return {}; r.pulse = pr; }
    if (!sentinel(raw[4])) { if (so < 0  || so > 100) return {}; r.spo2  = so; }
    r.timestamp_secs = std::time(nullptr);
    return r;
}

// Pre-built commands
inline const std::vector<uint8_t> HELLO{0x89,0x09}, DEVICE_STATE{0x8E,0x05,0x13},
    START{0x9B,0x01,0x1C}, STOP{0x9B,0x7F,0x1A},
    BATTERY{0x86,0x06}, HEARTBEAT{0x9A,0x1A};
inline const std::vector<std::vector<uint8_t>> START_SEQ{HELLO, DEVICE_STATE, START, BATTERY};

/* ---- BLE Client (SimpleBLE) ---- */

class BLEClient {
public:
    BLEClient();
    ~BLEClient();

    void setReadingCallback(ReadingCallback cb);
    void setStatusCallback(StatusCallback cb);

    bool start();
    void stop();

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace emay
