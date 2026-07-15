<?php
/*
 * EMAY SleepO2 — PHP types, protocol, and BlueZ FFI BLE client
 * Copyright (c) 2026 Ground Effect Software, LLC · MIT
 *
 * PHP is not a native BLE runtime. This reference implementation
 * provides the protocol layer plus an FFI bridge to libbluetooth
 * for Linux/BlueZ. On other platforms, use a sidecar process
 * (Python/C) for BLE I/O and communicate via pipe/socket.
 *
 * Requires PHP 8.1+ with FFI enabled, and libbluetooth:
 *   sudo apt install libbluetooth-dev
 *   echo 'ffi.enable=true' >> /etc/php/8.3/cli/conf.d/20-ffi.ini
 */

declare(strict_types=1);

namespace GroundEffectSoftware\EMAYSleepO2;

/* ---- Types ---- */

class EMAYReading
{
    public function __construct(
        public readonly ?int $spo2,
        public readonly ?int $pulse,
        public readonly float $timestampSecs,
    ) {}
}

class MinuteSample
{
    public function __construct(
        public readonly float $minuteStartSecs,
        public readonly string $metricType,
        public readonly float $value,
        public readonly string $unitString,
    ) {}
}

/* ---- Protocol ---- */

final class EMAYProtocol
{
    public const string SVC_UUID = '0000ff12-0000-1000-8000-00805f9b34fb';
    public const string WR_UUID  = '0000ff01-0000-1000-8000-00805f9b34fb';
    public const string NFY_UUID = '0000ff02-0000-1000-8000-00805f9b34fb';
    public const string NAME_PFX = 'SleepO2';

    public const string HELLO        = "\x89\x09";
    public const string DEVICE_STATE = "\x8E\x05\x13";
    public const string START_CMD    = "\x9B\x01\x1C";
    public const string STOP_CMD     = "\x9B\x7F\x1A";
    public const string BATTERY      = "\x86\x06";
    public const string HEARTBEAT    = "\x9A\x1A";

    public const array START_SEQ = [
        self::HELLO, self::DEVICE_STATE, self::START_CMD, self::BATTERY
    ];

    public static function checksum(string $p): int
    {
        return array_sum(array_map('ord', str_split($p))) & 0x7F;
    }

    public static function command(string $p): string
    {
        return $p . chr(self::checksum($p));
    }

    public static function parse(string $raw): ?EMAYReading
    {
        if (strlen($raw) !== 8) return null;
        $b = array_map('ord', str_split($raw));
        if ($b[0] !== 0xEB || $b[1] !== 1 || $b[2] !== 5) return null;
        if ($b[5] !== 0x7F || $b[6] !== 0) return null;
        if ($b[7] !== (array_sum(array_slice($b, 0, 7)) & 0x7F)) return null;
        $pulse = in_array($b[3], [0, 0xFF], true) ? null : $b[3];
        $spo2  = in_array($b[4], [0, 0xFF], true) ? null : $b[4];
        if ($pulse !== null && ($pulse < 30 || $pulse > 220)) return null;
        if ($spo2  !== null && ($spo2  < 0  || $spo2  > 100)) return null;
        return new EMAYReading($spo2, $pulse, microtime(true));
    }
}

/* ---- FFI BLE Client (Linux/BlueZ) ---- */

final class EMAYBLEClient
{
    private ?\FFI $ffi = null;
    private ?\Closure $onReading = null;
    private ?\Closure $onStatus = null;
    private bool $running = false;

    /**
     * @param callable(EMAYReading):void $onReading
     * @param callable(string):void $onStatus
     */
    public function __construct(
        ?callable $onReading = null,
        ?callable $onStatus = null,
    ) {
        $this->onReading = $onReading ? $onReading(...) : null;
        $this->onStatus  = $onStatus  ? $onStatus(...)  : null;

        // FFI bridge to libbluetooth (HCI sockets)
        // HCI socket operations for BLE scanning are low-level;
        // a production implementation would use a sidecar or
        // the C reference client via FFI.
        try {
            $this->ffi = \FFI::cdef('
                typedef struct { int dd; } hci_dev;
                int hci_open_dev(int dev_id);
                int hci_close_dev(int dd);
                int hci_le_set_scan_parameters(int dd, int type, int interval, int window,
                                                int own_type, int filter_policy, int to);
                int hci_le_set_scan_enable(int dd, int enable, int filter_dup, int to);
            ', 'libbluetooth.so');
        } catch (\FFI\Exception) {
            $this->emit('FFI: libbluetooth.so not available — BLE requires a sidecar');
        }
    }

    public function start(): void
    {
        $this->emit('scanning for SleepO2...');
        /*
         * Reference workflow (requires a sidecar or native extension):
         * 1. HCI LE scan for devices advertising the SleepO2 service UUID
         * 2. HCI LE connect
         * 3. GATT discover → find write + notify characteristics
         * 4. Write START_SEQ commands
         * 5. Read notifications → parse frames → call onReading
         * 6. Heartbeat loop every 1 second
         */
    }

    public function stop(): void
    {
        $this->running = false;
        $this->emit('stopped');
    }

    private function emit(string|EMAYReading $event): void
    {
        if ($event instanceof EMAYReading) {
            $this->onReading?->__invoke($event);
        } else {
            $this->onStatus?->__invoke($event);
        }
    }
}
