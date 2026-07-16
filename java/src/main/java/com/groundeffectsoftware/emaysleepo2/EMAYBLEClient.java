/*
 * EMAY SleepO2 — Java types, protocol, and Android BLE client
 * Copyright (c) 2026 Ground Effect Software, LLC · MIT
 *
 * Requires Android API 26+. Add to AndroidManifest.xml:
 *   <uses-permission android:name="android.permission.BLUETOOTH_SCAN"/>
 *   <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
 */
package com.groundeffectsoftware.emaysleepo2;

import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.Context;
import android.os.ParcelUuid;
import java.util.*;
import java.util.concurrent.*;

/* ---- Types ---- */

final class EMAYReading {
    final Integer spo2, pulse;  // null = absent
    final long timestampMs;
    EMAYReading(Integer s, Integer p, long t) { spo2=s; pulse=p; timestampMs=t; }
}

final class MinuteSample {
    final long minuteStartMs; final String metricType;
    final double value; final String unitString;
    MinuteSample(long m, String t, double v, String u) { minuteStartMs=m; metricType=t; value=v; unitString=u; }
}

/* ---- Protocol ---- */

final class EMAYProtocol {
    static final UUID SVC = UUID.fromString("0000ff12-0000-1000-8000-00805f9b34fb");
    static final UUID WR  = UUID.fromString("0000ff01-0000-1000-8000-00805f9b34fb");
    static final UUID NFY = UUID.fromString("0000ff02-0000-1000-8000-00805f9b34fb");
    static final String NAME_PREFIX = "SleepO2";

    static final byte[] HELLO={-0x77,0x09}, DEVICE_STATE={-0x72,0x05,0x13},
        START={-0x65,0x01,0x1C}, STOP={-0x65,0x7F,0x1A},
        BATTERY={-0x7A,0x06}, HEARTBEAT={-0x66,0x1A};
    static final List<byte[]> START_SEQ = List.of(HELLO, DEVICE_STATE, START, BATTERY);

    static byte cks(byte[] p) { int s=0; for(byte b:p) s+=b&0xFF; return (byte)(s&0x7F); }
    static byte[] cmd(byte[] p) { byte[] r=Arrays.copyOf(p,p.length+1); r[p.length]=cks(p); return r; }

    static EMAYReading parse(byte[] raw) {
        if(raw==null||raw.length!=8) return null;
        if(raw[0]!=-0x15||raw[1]!=1||raw[2]!=5) return null;
        if(raw[5]!=0x7F||raw[6]!=0) return null;
        int s=0; for(int i=0;i<7;i++) s+=raw[i]&0xFF;
        if(raw[7]!=(byte)(s&0x7F)) return null;
        int pr=raw[3]&0xFF, so=raw[4]&0xFF;
        Integer p=(pr==0||pr==0xFF)?null:pr, o2=(so==0||so==0xFF)?null:so;
        if(p!=null&&(p<30||p>220)) return null;
        if(o2!=null&&(o2<0||o2>100)) return null;
        return new EMAYReading(o2,p,System.currentTimeMillis());
    }
}

/* ---- BLE Client ---- */

public class EMAYBLEClient {
    public interface Callback {
        void onReading(EMAYReading r);
        void onStatus(String status);
    }

    /** Best-effort reason the client last transitioned to a failed status.
     *  Meaningful only after a failure; {@link #NONE} at all other times. */
    public enum FailureReason {
        NONE(""),
        NOT_FOUND("Device not found — it may be off, out of range, or connected to another app (the SleepO2 allows only one connection at a time)."),
        CONNECTION_FAILED("Found the device but the connection failed — it may have moved out of range or been taken by another app mid-connect.");

        private final String message;
        FailureReason(String message) { this.message = message; }
        public String message() { return message; }
    }

    private final BluetoothManager mgr;
    private BluetoothGatt gatt;
    private BluetoothGattCharacteristic wrCh, nfyCh;
    private Callback cb;
    private final ScheduledExecutorService scheduler = Executors.newSingleThreadScheduledExecutor();
    private volatile boolean streaming;
    private volatile FailureReason failureReason = FailureReason.NONE;

    public EMAYBLEClient(Context ctx) {
        mgr = (BluetoothManager) ctx.getSystemService(Context.BLUETOOTH_SERVICE);
    }

    public void setCallback(Callback c) { this.cb = c; }

    /** Why the last session failed. Meaningful only after a failure status. */
    public FailureReason getFailureReason() { return failureReason; }

    public void start() {
        failureReason = FailureReason.NONE;
        var adapter = mgr.getAdapter();
        if (adapter == null) { status("no BT adapter"); return; }

        var scanner = adapter.getBluetoothLeScanner();
        var filter = new ScanFilter.Builder()
            .setServiceUuid(new ParcelUuid(EMAYProtocol.SVC)).build();
        var settings = new ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build();

        status("scanning");
        scanner.startScan(List.of(filter), settings, new ScanCallback() {
            public void onScanResult(int type, ScanResult r) {
                scanner.stopScan(this);
                status("connecting");
                gatt = r.getDevice().connectGatt(ctx, false, gattCallback);
            }
            // onScanFailed fires when the BLE scanner itself cannot start
            // (SCAN_FAILED_APPLICATION_REGISTRATION_FAILED, ..._INTERNAL_ERROR,
            // etc.) — a local stack failure, NOT "scanned and did not find the
            // device". Tagging it NOT_FOUND would show a misleading hint about
            // the device being off/out-of-range/busy, so leave failureReason
            // unclassified and let the status string carry the real cause.
            public void onScanFailed(int e) { status("scan failed: " + e); }
        });
    }

    private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
        public void onConnectionStateChange(BluetoothGatt g, int st, int ns) {
            if (ns == BluetoothProfile.STATE_CONNECTED) {
                status("discovering");
                g.discoverServices();
            } else {
                stop(); status("disconnected");
            }
        }
        public void onServicesDiscovered(BluetoothGatt g, int s) {
            var svc = g.getService(EMAYProtocol.SVC);
            if (svc == null) { failureReason = FailureReason.CONNECTION_FAILED; status("service not found"); return; }
            wrCh = svc.getCharacteristic(EMAYProtocol.WR);
            nfyCh = svc.getCharacteristic(EMAYProtocol.NFY);
            if (wrCh == null || nfyCh == null) { failureReason = FailureReason.CONNECTION_FAILED; status("characteristics missing"); return; }
            g.setCharacteristicNotification(nfyCh, true);
            var desc = nfyCh.getDescriptor(UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"));
            if (desc != null) desc.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
            g.writeDescriptor(desc);
            status("streaming");
            // Send start sequence
            for (byte[] cmd : EMAYProtocol.START_SEQ) {
                wrCh.setValue(cmd); g.writeCharacteristic(wrCh);
            }
            // Heartbeat loop
            streaming = true;
            scheduler.scheduleAtFixedRate(() -> {
                if (!streaming || gatt == null) return;
                wrCh.setValue(EMAYProtocol.HEARTBEAT);
                gatt.writeCharacteristic(wrCh);
            }, 1, 1, TimeUnit.SECONDS);
        }
        public void onCharacteristicChanged(BluetoothGatt g, BluetoothGattCharacteristic c) {
            if (c.equals(nfyCh)) {
                var r = EMAYProtocol.parse(c.getValue());
                if (r != null && cb != null) cb.onReading(r);
            }
        }
    };

    public void stop() {
        streaming = false;
        scheduler.shutdownNow();
        if (gatt != null) { gatt.close(); gatt = null; }
        status("stopped");
    }

    private void status(String s) { if (cb != null) cb.onStatus(s); }
}
