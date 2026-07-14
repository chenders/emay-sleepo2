// Package emay provides a BLE client for the EMAY SleepO2 pulse oximeter.
package emay

import (
	"errors"
	"fmt"
	"time"
)

// ---- Types ----

// Reading is a single physiological measurement from the EMAY SleepO2.
type Reading struct {
	SpO2      *int     // Oxygen saturation percent (0–100), nil = not acquired
	Pulse     *int     // Pulse rate in bpm, nil = not acquired
	Timestamp time.Time
}

// MinuteSample is a finalized per-minute mean.
type MinuteSample struct {
	MinuteStart time.Time
	MetricType  string // "SpO2" or "PulseRate"
	Value       float64
	UnitString  string // "%" or "count/min"
}

// Status represents the connection state.
type Status int

const (
	StatusIdle Status = iota
	StatusScanning
	StatusConnecting
	StatusStreaming
	StatusBluetoothOff
	StatusBluetoothUnauthorized
	StatusBluetoothUnsupported
	StatusFailed
)

func (s Status) String() string {
	switch s {
	case StatusIdle: return "idle"
	case StatusScanning: return "scanning"
	case StatusConnecting: return "connecting"
	case StatusStreaming: return "streaming"
	case StatusBluetoothOff: return "bluetoothOff"
	case StatusBluetoothUnauthorized: return "bluetoothUnauthorized"
	case StatusBluetoothUnsupported: return "bluetoothUnsupported"
	case StatusFailed: return "failed"
	default: return "unknown"
	}
}

func (s Status) IsActive() bool {
	return s == StatusScanning || s == StatusConnecting || s == StatusStreaming
}

// ---- BLE Adapter Interface ----

// BLEAdapter abstracts platform-specific BLE operations.
type BLEAdapter interface {
	Scan(serviceUUID string, onDiscover func(addr string, name string))
	StopScan()
	Connect(addr string) (BLEPeripheral, error)
}

// BLEPeripheral represents a connected BLE device.
type BLEPeripheral interface {
	Address() string
	Disconnect() error
	DiscoverServices() ([]BLEService, error)
}

// BLEService is a BLE GATT service.
type BLEService interface {
	UUID() string
	DiscoverCharacteristics() ([]BLECharacteristic, error)
}

// BLECharacteristic is a BLE GATT characteristic.
type BLECharacteristic interface {
	UUID() string
	Write(data []byte) error
	Subscribe(callback func([]byte)) error
	Unsubscribe() error
}

// ---- EMAY Client ----

// Client manages a connection to the EMAY SleepO2.
type Client struct {
	adapter      BLEAdapter
	status       Status
	OnReading    func(Reading)
	OnStatus     func(Status)
	OnMinute     func([]MinuteSample)
	peripheral   BLEPeripheral
	writeChar    BLECharacteristic
	notifyChar   BLECharacteristic
	latest       *Reading
	lastReadAt   time.Time
	wantScan     bool
	hbDone       chan struct{}
	downsampler  LiveDownsampler
	knownAddr    string
	autoReconnect bool
	hbInterval   time.Duration
	staleTimeout time.Duration
}

// NewClient creates a client with the given BLE adapter.
func NewClient(adapter BLEAdapter) *Client {
	return &Client{
		adapter:       adapter,
		status:        StatusIdle,
		autoReconnect:  true,
		hbInterval:    1500 * time.Millisecond,
		staleTimeout:  4 * time.Second,
		downsampler:   *NewLiveDownsampler(2),
	}
}

// Status returns the current connection state.
func (c *Client) Status() Status { return c.status }

func (c *Client) setStatus(s Status) {
	if c.status != s {
		c.status = s
		if c.OnStatus != nil { c.OnStatus(s) }
	}
}

// LatestReading returns the most recent reading.
func (c *Client) LatestReading() *Reading { return c.latest }

// IsStreaming returns whether the device is currently streaming.
func (c *Client) IsStreaming() bool { return c.status == StatusStreaming }

// Start begins monitoring for the oximeter. If addr is non-empty,
// connects to that specific device.
func (c *Client) Start(addr string) error {
	if c.status.IsActive() { return nil }
	c.wantScan = true
	if addr != "" { c.knownAddr = addr }
	c.setStatus(StatusScanning)
	return c.beginMonitoring()
}

// Stop ends streaming and disconnects.
func (c *Client) Stop() error {
	c.wantScan = false
	if c.hbDone != nil { close(c.hbDone); c.hbDone = nil }
	if c.writeChar != nil {
		c.writeChar.Write(stopRealtime)
	}
	if c.peripheral != nil {
		c.peripheral.Disconnect()
	}
	c.resetState()
	c.setStatus(StatusIdle)
	return nil
}

func (c *Client) beginMonitoring() error {
	done := make(chan error, 1)

	c.adapter.Scan(serviceUUID, func(addr string, name string) {
		c.adapter.StopScan()
		c.knownAddr = addr
		go func() {
			done <- c.connectAndStream(addr)
		}()
	})

	// Timeout after 10s
	go func() {
		time.Sleep(10 * time.Second)
		select {
		case done <- errors.New("scan timeout"):
		default:
		}
	}()

	return <-done
}

func (c *Client) connectAndStream(addr string) error {
	c.setStatus(StatusConnecting)
	p, err := c.adapter.Connect(addr)
	if err != nil {
		c.setStatus(StatusFailed)
		return fmt.Errorf("connect: %w", err)
	}
	c.peripheral = p

	services, err := p.DiscoverServices()
	if err != nil {
		c.setStatus(StatusFailed)
		return fmt.Errorf("discover services: %w", err)
	}

	for _, svc := range services {
		if !containsUUID(svc.UUID(), serviceUUID) { continue }
		chars, err := svc.DiscoverCharacteristics()
		if err != nil { continue }
		for _, ch := range chars {
			if containsUUID(ch.UUID(), writeUUID) { c.writeChar = ch }
			if containsUUID(ch.UUID(), notifyUUID) { c.notifyChar = ch }
		}
	}

	if c.writeChar == nil || c.notifyChar == nil {
		c.setStatus(StatusFailed)
		return errors.New("characteristics not found")
	}

	c.notifyChar.Subscribe(func(data []byte) {
		reading := parseReading(data)
		if reading == nil { return }
		c.latest = reading
		c.lastReadAt = time.Now()
		if c.OnReading != nil { c.OnReading(*reading) }
		minutes := c.downsampler.Add(*reading)
		if len(minutes) > 0 && c.OnMinute != nil { c.OnMinute(minutes) }
	})

	// Serialized start sequence
	for _, cmd := range startSequence {
		if err := c.writeChar.Write(cmd); err != nil {
			c.setStatus(StatusFailed)
			return fmt.Errorf("write: %w", err)
		}
	}

	c.setStatus(StatusStreaming)
	c.startHeartbeat()
	return nil
}

func (c *Client) startHeartbeat() {
	c.hbDone = make(chan struct{})
	go func() {
		ticker := time.NewTicker(c.hbInterval)
		defer ticker.Stop()
		for {
			select {
			case <-c.hbDone:
				return
			case <-ticker.C:
				if c.status != StatusStreaming { return }
				if c.writeChar != nil { c.writeChar.Write(heartbeat) }
				if c.lastReadAt.IsZero() { continue }
				if time.Since(c.lastReadAt) > c.staleTimeout {
					c.latest = nil
					c.downsampler.Flush()
				}
			}
		}
	}()
}

func (c *Client) resetState() {
	if c.hbDone != nil { close(c.hbDone); c.hbDone = nil }
	c.peripheral = nil
	c.writeChar = nil
	c.notifyChar = nil
	c.latest = nil
}

func containsUUID(uuidStr, target string) bool {
	return len(uuidStr) >= len(target) && uuidStr[len(uuidStr)-len(target):] == target
}
