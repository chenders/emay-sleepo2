package com.groundeffectsoftware.com.emaysleepo2

import android.bluetooth.*
import android.bluetooth.BluetoothGatt.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import kotlinx.coroutines.*
import java.util.UUID

/**
 * Android BLE client for the EMAY SleepO2 pulse oximeter.
 *
 * Requires permissions: BLUETOOTH_SCAN, BLUETOOTH_CONNECT,
 * ACCESS_FINE_LOCATION (Android <12), and location services enabled.
 *
 * Example::
 *
 *     val emay = EMAYClient(context)
 *     emay.onReading = { r -> println("SpO2: ${r.spo2}%  HR: ${r.pulse}") }
 *     emay.start(scope = lifecycleScope)
 */
class EMAYClient(private val context: Context) {

    // Callbacks
    var onReading: ((EMAYReading) -> Unit)? = null
    var onStatusChange: ((EMAYStatus) -> Unit)? = null
    var onMinuteSamples: ((List<MinuteSample>) -> Unit)? = null

    // Configuration
    var heartbeatIntervalMs: Long = 1500
    var staleTimeoutMs: Long = 4000
    var autoReconnect: Boolean = true

    // State
    private var _status: EMAYStatus = EMAYStatus.Idle
    val status: EMAYStatus get() = _status
    private fun setStatus(s: EMAYStatus) {
        if (_status != s) { _status = s; onStatusChange?.invoke(s) }
    }

    var latestReading: EMAYReading? = null
        private set
    val isStreaming: Boolean get() = _status == EMAYStatus.Streaming

    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothGatt: BluetoothGatt? = null
    private var writeChar: BluetoothGattCharacteristic? = null
    private var notifyChar: BluetoothGattCharacteristic? = null
    private var wantScan = false
    private var lastReadingAt: Long = 0
    private val downsampler = EMAYLiveDownsampler()
    private val handler = Handler(Looper.getMainLooper())
    private var knownAddress: String? = null
    private var scope: CoroutineScope? = null

    private val serviceUUID = UUID.fromString(EMAYProtocol.SERVICE_UUID)
    private val writeUUID = UUID.fromString(EMAYProtocol.WRITE_UUID)
    private val notifyUUID = UUID.fromString(EMAYProtocol.NOTIFY_UUID)

    init {
        bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter
    }

    // ---- Public API ----

    /**
     * Start monitoring for the oximeter.
     * @param scope CoroutineScope for heartbeat and reconnect tasks.
     * @param address Optional known device MAC address.
     */
    fun start(scope: CoroutineScope, address: String? = null) {
        if (_status.isActive) return
        this.scope = scope
        wantScan = true
        if (address != null) knownAddress = address
        beginMonitoring()
    }

    fun stop() {
        wantScan = false
        bluetoothGatt?.let { gatt ->
            writeChar?.let { ch ->
                ch.value = EMAYProtocol.STOP_REALTIME
                gatt.writeCharacteristic(ch)
            }
            gatt.disconnect()
            gatt.close()
        }
        resetState()
        setStatus(EMAYStatus.Idle)
    }

    // ---- Private: monitoring ----

    private fun beginMonitoring() {
        val adapter = bluetoothAdapter ?: run {
            setStatus(EMAYStatus.BluetoothUnsupported)
            return
        }
        if (!adapter.isEnabled) {
            setStatus(EMAYStatus.BluetoothOff)
            return
        }
        // If we have a known address, try direct connect
        if (knownAddress != null) {
            val device = adapter.getRemoteDevice(knownAddress)
            connectTo(device)
            return
        }
        beginScan()
    }

    private fun beginScan() {
        setStatus(EMAYStatus.Scanning)
        val scanner = bluetoothAdapter?.bluetoothLeScanner ?: return

        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(serviceUUID))
            .build()

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        scanner.startScan(listOf(filter), settings, scanCallback)
        // Timeout after 10s
        handler.postDelayed({
            scanner.stopScan(scanCallback)
            if (_status == EMAYStatus.Scanning) {
                setStatus(EMAYStatus.Failed)
            }
        }, 10000)
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            val name = result.scanRecord?.deviceName ?: device.name ?: ""
            if (name.isNotEmpty() && !name.startsWith(EMAYProtocol.NAME_PREFIX)) return
            bluetoothAdapter?.bluetoothLeScanner?.stopScan(this)
            knownAddress = device.address
            connectTo(device)
        }
    }

    private fun connectTo(device: BluetoothDevice) {
        setStatus(EMAYStatus.Connecting)
        bluetoothGatt = device.connectGatt(context, false, gattCallback)
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED && status == GATT_SUCCESS) {
                gatt.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                val wasFailure = _status == EMAYStatus.Failed
                val isTransient = wantScan && !wasFailure && autoReconnect
                if (!isTransient) downsampler.flush()
                resetState()
                if (isTransient) {
                    scope?.launch {
                        delay(200)
                        if (wantScan) beginMonitoring()
                    }
                } else if (!wasFailure && _status != EMAYStatus.Failed) {
                    setStatus(EMAYStatus.Idle)
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val svc = gatt.getService(serviceUUID)
            if (svc == null) { setStatus(EMAYStatus.Failed); return }
            writeChar = svc.getCharacteristic(writeUUID)
            notifyChar = svc.getCharacteristic(notifyUUID)
            if (writeChar == null || notifyChar == null) {
                setStatus(EMAYStatus.Failed); return
            }
            gatt.setCharacteristicNotification(notifyChar, true)

            // Serialized start sequence
            writeSequence(gatt, 0)
        }

        private fun writeSequence(gatt: BluetoothGatt, index: Int) {
            if (index >= EMAYProtocol.START_SEQUENCE.size) {
                setStatus(EMAYStatus.Streaming)
                startHeartbeat()
                return
            }
            writeChar?.let { ch ->
                ch.value = EMAYProtocol.START_SEQUENCE[index]
                ch.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            }
            gatt.writeCharacteristic(writeChar)
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            // Find which command just completed and send next
            val idx = EMAYProtocol.START_SEQUENCE.indexOfFirst {
                it.contentEquals(characteristic.value)
            }
            if (idx >= 0 && idx < EMAYProtocol.START_SEQUENCE.size - 1) {
                writeSequence(gatt, idx + 1)
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic
        ) {
            if (characteristic.uuid != notifyUUID) return
            val raw = characteristic.value ?: return
            val reading = EMAYProtocol.parseReading(raw) ?: return
            latestReading = reading
            lastReadingAt = System.currentTimeMillis()
            onReading?.invoke(reading)

            val minutes = downsampler.add(reading)
            if (minutes.isNotEmpty()) {
                onMinuteSamples?.invoke(minutes)
            }
        }
    }

    private fun startHeartbeat() {
        scope?.launch {
            while (isActive) {
                delay(heartbeatIntervalMs)
                if (_status != EMAYStatus.Streaming) break
                val gatt = bluetoothGatt ?: break
                val ch = writeChar ?: break
                ch.value = EMAYProtocol.HEARTBEAT
                gatt.writeCharacteristic(ch)
                // Staleness watchdog
                if (lastReadingAt > 0 &&
                    System.currentTimeMillis() - lastReadingAt > staleTimeoutMs) {
                    latestReading = null
                    downsampler.flush()
                }
            }
        }
    }

    private fun resetState() {
        bluetoothGatt?.close()
        bluetoothGatt = null
        writeChar = null
        notifyChar = null
        latestReading = null
        lastReadingAt = 0
    }
}
