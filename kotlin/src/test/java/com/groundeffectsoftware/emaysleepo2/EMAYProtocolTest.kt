package com.groundeffectsoftware.emaysleepo2

import org.junit.Test
import kotlin.test.*

class EMAYProtocolTest {

    private fun frame(pr: Int, spo2: Int): ByteArray {
        val buf = byteArrayOf(
            0xEB.toByte(), 0x01.toByte(), 0x05.toByte(),
            pr.toByte(), spo2.toByte(), 0x7F.toByte(), 0x00.toByte(), 0x00.toByte()
        )
        val ck = buf.take(7).fold(0) { acc, b -> acc + (b.toInt() and 0xFF) } and 0x7F
        buf[7] = ck.toByte()
        return buf
    }

    @Test fun `checksum computes correct values`() {
        assertEquals(0x09.toByte(), EMAYProtocol.checksum(byteArrayOf(0x89.toByte())))
        assertEquals(0x1A.toByte(), EMAYProtocol.checksum(byteArrayOf(0x9A.toByte())))
        assertEquals(0x1C.toByte(), EMAYProtocol.checksum(byteArrayOf(0x9B.toByte(), 0x01.toByte())))
    }

    @Test fun `valid frame parses`() {
        val r = EMAYProtocol.parseReading(frame(62, 98))
        assertNotNull(r)
        assertEquals(62, r.pulse)
        assertEquals(98, r.spo2)
    }

    @Test fun `wrong length rejects`() {
        assertNull(EMAYProtocol.parseReading(byteArrayOf(0xEB.toByte(), 0x01.toByte())))
    }

    @Test fun `bad checksum rejects`() {
        val bad = byteArrayOf(0xEB.toByte(), 0x01.toByte(), 0x05.toByte(), 62, 98, 0x7F.toByte(), 0x00, 0x7F.toByte())
        assertNull(EMAYProtocol.parseReading(bad))
    }

    @Test fun `PR=0x00 means null pulse`() {
        val r = EMAYProtocol.parseReading(frame(0x00, 98))
        assertNotNull(r)
        assertNull(r.pulse)
        assertEquals(98, r.spo2)
    }

    @Test fun `PR=0xFF means null pulse`() {
        val r = EMAYProtocol.parseReading(frame(0xFF, 98))
        assertNotNull(r)
        assertNull(r.pulse)
    }

    @Test fun `SpO2=0xFF means null SpO2`() {
        val r = EMAYProtocol.parseReading(frame(62, 0xFF))
        assertNotNull(r)
        assertNull(r.spo2)
    }

    @Test fun `both sentinels null`() {
        val r = EMAYProtocol.parseReading(frame(0xFF, 0xFF))
        assertNotNull(r)
        assertNull(r.pulse)
        assertNull(r.spo2)
    }

    @Test fun `pulse below 30 rejected`() {
        assertNull(EMAYProtocol.parseReading(frame(29, 98)))
    }

    @Test fun `pulse above 220 rejected`() {
        assertNull(EMAYProtocol.parseReading(frame(221, 98)))
    }

    @Test fun `pulse 30 accepted`() {
        assertEquals(30, EMAYProtocol.parseReading(frame(30, 98))?.pulse)
    }

    @Test fun `pulse 220 accepted`() {
        assertEquals(220, EMAYProtocol.parseReading(frame(220, 98))?.pulse)
    }

    @Test fun `SpO2 above 100 rejected`() {
        assertNull(EMAYProtocol.parseReading(frame(62, 101)))
    }

    @Test fun `SpO2 100 accepted`() {
        assertEquals(100, EMAYProtocol.parseReading(frame(62, 100))?.spo2)
    }
}
