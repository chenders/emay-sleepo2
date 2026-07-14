package emay

import "time"

// ---- Protocol constants ----

const (
	serviceUUID = "0000ff12-0000-1000-8000-00805f9b34fb"
	writeUUID   = "0000ff01-0000-1000-8000-00805f9b34fb"
	notifyUUID  = "0000ff02-0000-1000-8000-00805f9b34fb"
	namePrefix  = "SleepO2"
)

// ---- Commands ----
var (
	hello        = []byte{0x89, 0x09}
	deviceState  = []byte{0x8E, 0x05, 0x13}
	startRealtimeVal = []byte{0x9B, 0x01, 0x1C}
	stopRealtime = []byte{0x9B, 0x7F, 0x1A}
	getBattery   = []byte{0x86, 0x06}
	heartbeat    = []byte{0x9A, 0x1A}
	startSequence = [][]byte{hello, deviceState, startRealtimeVal, getBattery}
)

// ---- Data frame constants ----
var (
	frameHeader  = []byte{0xEB, 0x01, 0x05}
	frameTrailer = []byte{0x7F, 0x00}
)

// ---- Parse ----

func parseReading(raw []byte) *Reading {
	if len(raw) != 8 { return nil }
	if raw[0] != frameHeader[0] || raw[1] != frameHeader[1] || raw[2] != frameHeader[2] {
		return nil
	}
	if raw[5] != frameTrailer[0] || raw[6] != frameTrailer[1] { return nil }

	var cks int
	for i := 0; i < 7; i++ { cks += int(raw[i]) }
	cks &= 0x7F
	if int(raw[7]) != cks { return nil }

	rawPR := int(raw[3])
	rawSpO2 := int(raw[4])

	var pulse, spo2 *int
	if rawPR != 0 && rawPR != 0xFF {
		if rawPR < 30 || rawPR > 220 { return nil }
		v := rawPR; pulse = &v
	}
	if rawSpO2 != 0 && rawSpO2 != 0xFF {
		if rawSpO2 > 100 { return nil }
		v := rawSpO2; spo2 = &v
	}

	return &Reading{SpO2: spo2, Pulse: pulse, Timestamp: time.Now()}
}
