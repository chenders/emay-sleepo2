/*
 * EMAY SleepO2 — Java types + protocol
 * Copyright (c) 2026 Ground Effect Software, LLC · MIT
 */
package com.groundeffectsoftware.emaysleepo2;

import java.util.*;

public final class EMAYReading {
    public final Integer spo2, pulse;
    public final long timestampMs;
    public EMAYReading(Integer spo2, Integer pulse, long ts) { this.spo2=spo2; this.pulse=pulse; this.timestampMs=ts; }
}

public final class MinuteSample {
    public final long minuteStartMs; public final String metricType; public final double value, unitString;
    public MinuteSample(long ms, String mt, double v, String u) { minuteStartMs=ms; metricType=mt; value=v; unitString=u; }
}

/* ---- Protocol ---- */
public final class EMAYProtocol {
    public static final String SVC="0000ff12-0000-1000-8000-00805f9b34fb", WR="0000ff01-0000-1000-8000-00805f9b34fb", NFY="0000ff02-0000-1000-8000-00805f9b34fb";
    public static final byte[] HELLO={-0x77,0x09}, DEVICE_STATE={-0x72,0x05,0x13}, START_REALTIME={-0x65,0x01,0x1C}, STOP={-0x65,0x7F,0x1A}, BATTERY={-0x7A,0x06}, HEARTBEAT={-0x66,0x1A};
    public static final List<byte[]> START_SEQ = List.of(HELLO, DEVICE_STATE, START_REALTIME, BATTERY);

    public static byte cks(byte[] p) { int s=0; for(byte b:p) s+=b&0xFF; return (byte)(s&0x7F); }
    public static byte[] cmd(byte[] p) { byte[] r=Arrays.copyOf(p,p.length+1); r[p.length]=cks(p); return r; }

    public static EMAYReading parse(byte[] raw) {
        if(raw==null||raw.length!=8) return null;
        if(raw[0]!=-0x15||raw[1]!=1||raw[2]!=5) return null;
        if(raw[5]!=0x7F||raw[6]!=0) return null;
        int s=0; for(int i=0;i<7;i++) s+=raw[i]&0xFF;
        if(raw[7]!=(byte)(s&0x7F)) return null;
        int pr=raw[3]&0xFF, spo2=raw[4]&0xFF;
        Integer pulse=(pr==0||pr==0xFF)?null:pr, o2=(spo2==0||spo2==0xFF)?null:spo2;
        if(pulse!=null&&(pulse<30||pulse>220)) return null;
        if(o2!=null&&(o2<0||o2>100)) return null;
        return new EMAYReading(o2,pulse,System.currentTimeMillis());
    }
}
