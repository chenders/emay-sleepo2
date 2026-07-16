/*
 * EMAY SleepO2 — C protocol implementation (no BLE deps)
 * Copyright (c) 2026 Ground Effect Software, LLC · MIT
 * Always compiles: cc -std=c11 -Wall -c emay_sleepo2.c
 */
#include "emay_sleepo2.h"
#include <stdlib.h>
#include <string.h>

uint8_t emay_checksum(const uint8_t *p, size_t n) {
    uint16_t s = 0; for (size_t i=0;i<n;i++) s+=p[i]; return (uint8_t)(s&0x7F);
}
uint8_t *emay_command(const uint8_t *p, size_t n, size_t *out) {
    uint8_t *c = malloc(n+1); if(!c) return NULL;
    memcpy(c,p,n); c[n]=emay_checksum(p,n); *out=n+1; return c;
}
int emay_parse_reading(const uint8_t *raw, size_t n, emay_reading_t *out) {
    if(!raw||n!=8) return -1;
    if(raw[0]!=0xEB||raw[1]!=1||raw[2]!=5) return -2;
    if(raw[5]!=0x7F||raw[6]!=0) return -3;
    uint16_t s=0; for(int i=0;i<7;i++) s+=raw[i];
    if(raw[7]!=(uint8_t)(s&0x7F)) return -4;
    int pr=raw[3], so=raw[4];
    int pulse=(pr==0||pr==0xFF)?-1:pr, spo2=(so==0||so==0xFF)?-1:so;
    if(pulse>=0&&(pulse<30||pulse>220)) return -5;
    if(spo2>=0&&(spo2<0||spo2>100)) return -6;
    out->spo2=spo2; out->pulse=pulse; out->timestamp_secs=(double)time(NULL);
    return 0;
}
const char *emay_failure_reason_message(emay_failure_reason_t r) {
    switch (r) {
        case EMAY_FAILURE_NOT_FOUND:
            return "Device not found — it may be off, out of range, or connected to another app (the SleepO2 allows only one connection at a time).";
        case EMAY_FAILURE_CONNECTION_FAILED:
            return "Found the device but the connection failed — it may have moved out of range or been taken by another app mid-connect.";
        case EMAY_FAILURE_NONE:
        default:
            return "";
    }
}
/* BLE client stubs (full implementation in emay_sleepo2_ble.c) */
emay_ble_t *emay_ble_create(void) { return NULL; }
void emay_ble_free(emay_ble_t *b) { (void)b; }
void emay_ble_set_callbacks(emay_ble_t *b, emay_reading_cb r, emay_status_cb s, void *c) { (void)b;(void)r;(void)s;(void)c; }
int  emay_ble_scan_and_connect(emay_ble_t *b, int t) { (void)b;(void)t; return -1; }
int  emay_ble_start_stream(emay_ble_t *b) { (void)b; return -1; }
void emay_ble_stop(emay_ble_t *b) { (void)b; }
