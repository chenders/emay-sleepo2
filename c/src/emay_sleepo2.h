/*
 * EMAY SleepO2 — C types, protocol, and BlueZ D-Bus BLE client
 * Copyright (c) 2026 Ground Effect Software, LLC · MIT
 *
 * Linux only. Requires: sudo apt install libdbus-1-dev libbluetooth-dev
 * Build: cc -std=c11 -Wall -o example example.c emay_sleepo2.c $(pkg-config --cflags --libs dbus-1)
 */
#ifndef EMAY_SLEEPO2_H
#define EMAY_SLEEPO2_H

#include <stdbool.h>
#include <stdint.h>
#include <time.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Types ---- */
typedef struct { int spo2, pulse; double timestamp_secs; } emay_reading_t;
typedef struct { double minute_start_secs; char metric_type[16]; double value; char unit_string[16]; } emay_minute_sample_t;

/* ---- Protocol ---- */
uint8_t emay_checksum(const uint8_t *p, size_t n);
uint8_t *emay_command(const uint8_t *p, size_t n, size_t *out);
int emay_parse_reading(const uint8_t *raw, size_t n, emay_reading_t *out); /* 0=ok */

/* ---- BLE Client ---- */
typedef struct emay_ble_s emay_ble_t;
typedef void (*emay_reading_cb)(const emay_reading_t *r, void *ctx);
typedef void (*emay_status_cb)(const char *status, void *ctx);

emay_ble_t *emay_ble_create(void);
void emay_ble_free(emay_ble_t *b);
void emay_ble_set_callbacks(emay_ble_t *b, emay_reading_cb rcb, emay_status_cb scb, void *ctx);
int  emay_ble_scan_and_connect(emay_ble_t *b, int timeout_sec);
int  emay_ble_start_stream(emay_ble_t *b);
void emay_ble_stop(emay_ble_t *b);

#ifdef __cplusplus
}
#endif
#endif
