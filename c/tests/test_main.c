#include "emay_sleepo2.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;
#define T(name) printf("  %s... ", name)
#define OK()     printf("ok\n")
#define FAIL(m)  do { printf("FAIL: %s\n", m); failures++; } while(0)

static void test_checksum(void) {
    T("checksum");
    uint8_t p1[]={0x89}, p2[]={0x9A};
    uint8_t c1=emay_checksum(p1,1), c2=emay_checksum(p2,1);
    if(c1!=0x09) FAIL("expected 0x09");
    if(c2!=0x1A) FAIL("expected 0x1A");
    OK();
}
static void test_valid_frame(void) {
    T("valid frame");
    uint8_t f[]={0xEB,1,5,0x3E,0x62,0x7F,0,0x10};
    emay_reading_t r;
    if(emay_parse_reading(f,8,&r)!=0) FAIL("parse failed");
    if(r.pulse!=62) FAIL("pulse");
    if(r.spo2!=98) FAIL("spo2");
    OK();
}
static void test_bad_checksum(void) {
    T("bad checksum");
    uint8_t f[]={0xEB,1,5,0x3E,0x62,0x7F,0,0x7F};
    emay_reading_t r;
    if(emay_parse_reading(f,8,&r)==0) FAIL("should reject");
    OK();
}
static void test_sentinel(void) {
    T("sentinel");
    uint8_t f[]={0xEB,1,5,0,0x62,0x7F,0,0};
    int s=0; for(int i=0;i<7;i++) s+=f[i]; f[7]=s&0x7F;
    emay_reading_t r;
    if(emay_parse_reading(f,8,&r)!=0) FAIL("parse failed");
    if(r.pulse!=-1) FAIL("pulse should be null");
    if(r.spo2!=98) FAIL("spo2");
    OK();
}
int main(void) {
    printf("C protocol tests:\n");
    test_checksum();
    test_valid_frame();
    test_bad_checksum();
    test_sentinel();
    printf("%d failure(s)\n", failures);
    return failures;
}
