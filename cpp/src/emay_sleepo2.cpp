/*
 * EMAY SleepO2 — C++ SimpleBLE client implementation
 * Copyright (c) 2026 Ground Effect Software, LLC · MIT
 */
#include "emay_sleepo2.hpp"
#include <simpleble/Adapter.h>
#include <simpleble/Peripheral.h>
#include <atomic>
#include <chrono>
#include <ctime>
#include <thread>
#include <vector>

namespace emay {

struct BLEClient::Impl {
    std::unique_ptr<SimpleBLE::Adapter> adapter;
    std::unique_ptr<SimpleBLE::Peripheral> peripheral;
    SimpleBLE::BluetoothUUID wr_uuid{WR_UUID}, nfy_uuid{NFY_UUID};
    ReadingCallback on_reading;
    StatusCallback  on_status;
    FailureReason failure_reason{FailureReason::None};
    std::atomic<bool> running{false};
    std::thread heartbeat_thread;

    void emit(const std::string& s) const { if (on_status) on_status(s); }
    void emit(const Reading& r) const { if (on_reading) on_reading(r); }
};

BLEClient::BLEClient() : impl_(std::make_unique<Impl>()) {
    auto adapters = SimpleBLE::Adapter::get_adapters();
    if (adapters.empty()) { impl_->emit("no BLE adapter"); return; }
    impl_->adapter = std::make_unique<SimpleBLE::Adapter>(adapters[0]);
}

BLEClient::~BLEClient() { stop(); }

void BLEClient::setReadingCallback(ReadingCallback cb) { impl_->on_reading = std::move(cb); }
void BLEClient::setStatusCallback(StatusCallback cb)   { impl_->on_status  = std::move(cb); }

FailureReason BLEClient::failure_reason() const { return impl_->failure_reason; }

bool BLEClient::start() {
    impl_->failure_reason = FailureReason::None;
    if (!impl_->adapter) return false;
    impl_->emit("scanning");

    impl_->adapter->scan_for(5000);
    auto periphs = impl_->adapter->scan_get_results();

    for (auto& p : periphs) {
        if (p.identifier().find(NAME_PFX) != std::string::npos ||
            p.identifier().find("SleepO2") != std::string::npos) {
            impl_->emit("connecting");
            impl_->peripheral = std::make_unique<SimpleBLE::Peripheral>(p);
            impl_->peripheral->connect();
            impl_->adapter->scan_stop();
            break;
        }
    }
    if (!impl_->peripheral) {
        // Scan finished without discovering a SleepO2.
        impl_->failure_reason = FailureReason::NotFound;
        impl_->emit("device not found"); return false;
    }
    if (!impl_->peripheral->is_connected()) {
        // Found the device but the connect attempt did not stick.
        impl_->failure_reason = FailureReason::ConnectionFailed;
        impl_->emit("device not found"); return false;
    }

    // Discover and subscribe
    impl_->emit("streaming");
    impl_->peripheral->notify(impl_->nfy_uuid, [this](SimpleBLE::ByteArray& bytes) {
        auto r = parse(std::vector<uint8_t>(bytes.begin(), bytes.end()));
        if (r) impl_->emit(*r);
    });

    // Send start sequence
    for (const auto& cmd : START_SEQ) {
        impl_->peripheral->write_request(impl_->wr_uuid, std::string(cmd.begin(), cmd.end()));
    }

    // Heartbeat loop
    impl_->running = true;
    impl_->heartbeat_thread = std::thread([this] {
        while (impl_->running) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
            if (impl_->peripheral && impl_->peripheral->is_connected()) {
                impl_->peripheral->write_request(impl_->wr_uuid,
                    std::string(HEARTBEAT.begin(), HEARTBEAT.end()));
            }
        }
    });

    return true;
}

void BLEClient::stop() {
    impl_->running = false;
    if (impl_->heartbeat_thread.joinable())
        impl_->heartbeat_thread.join();
    if (impl_->peripheral) {
        impl_->peripheral->write_request(impl_->wr_uuid, std::string(STOP.begin(), STOP.end()));
        impl_->peripheral->disconnect();
    }
    impl_->emit("stopped");
}

} // namespace emay
