// Package emay provides a BLE client for the EMAY SleepO2 pulse oximeter.
package emay

import (
	"errors"
	"fmt"
	"sync"
	"time"
)

// ---- Types ----

// Reading is a single physiological measurement from the EMAY SleepO2.
type Reading struct {
	SpO2      *int // Oxygen saturation percent (0–100), nil = not acquired
	Pulse     *int // Pulse rate in bpm, nil = not acquired
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
	case StatusIdle:
		return "idle"
	case StatusScanning:
		return "scanning"
	case StatusConnecting:
		return "connecting"
	case StatusStreaming:
		return "streaming"
	case StatusBluetoothOff:
		return "bluetoothOff"
	case StatusBluetoothUnauthorized:
		return "bluetoothUnauthorized"
	case StatusBluetoothUnsupported:
		return "bluetoothUnsupported"
	case StatusFailed:
		return "failed"
	default:
		return "unknown"
	}
}

func (s Status) IsActive() bool {
	return s == StatusScanning || s == StatusConnecting || s == StatusStreaming
}

// FailureReason explains why a session transitioned to StatusFailed.
type FailureReason int

const (
	FailureNone FailureReason = iota
	FailureNotFound
	FailureConnectionFailed
)

// Message returns a human-readable explanation of the failure reason.
// FailureNone returns the empty string.
func (r FailureReason) Message() string {
	switch r {
	case FailureNotFound:
		return "Device not found — it may be off, out of range, or connected to another app (the SleepO2 allows only one connection at a time)."
	case FailureConnectionFailed:
		return "Found the device but the connection failed — it may have moved out of range or been taken by another app mid-connect."
	default:
		return ""
	}
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
	adapter       BLEAdapter
	status        Status
	failureReason FailureReason
	OnReading     func(Reading)
	OnStatus      func(Status)
	OnMinute      func([]MinuteSample)
	peripheral    BLEPeripheral
	writeChar     BLECharacteristic
	notifyChar    BLECharacteristic
	latest        *Reading
	lastReadAt    time.Time
	wantScan      bool
	hbDone        chan struct{}
	hbWG          sync.WaitGroup
	downsampler   LiveDownsampler
	knownAddr     string
	autoReconnect bool
	hbInterval    time.Duration
	staleTimeout  time.Duration
}

// NewClient creates a client with the given BLE adapter.
func NewClient(adapter BLEAdapter) *Client {
	return &Client{
		adapter:       adapter,
		status:        StatusIdle,
		autoReconnect: true,
		hbInterval:    1500 * time.Millisecond,
		staleTimeout:  4 * time.Second,
		downsampler:   *NewLiveDownsampler(2),
	}
}

// Status returns the current connection state.
func (c *Client) Status() Status { return c.status }

// FailureReason returns why the last session failed. It is FailureNone unless
// the status is (or most recently was) StatusFailed.
func (c *Client) FailureReason() FailureReason { return c.failureReason }

func (c *Client) setStatus(s Status) {
	if c.status != s {
		c.status = s
		if c.OnStatus != nil {
			c.OnStatus(s)
		}
	}
}

// LatestReading returns the most recent reading.
func (c *Client) LatestReading() *Reading { return c.latest }

// IsStreaming returns whether the device is currently streaming.
func (c *Client) IsStreaming() bool { return c.status == StatusStreaming }

// Start begins monitoring for the oximeter. If addr is non-empty,
// connects to that specific device.
func (c *Client) Start(addr string) error {
	if c.status.IsActive() {
		return nil
	}
	c.failureReason = FailureNone
	c.wantScan = true
	if addr != "" {
		c.knownAddr = addr
	}
	c.setStatus(StatusScanning)
	return c.beginMonitoring()
}

// Stop ends streaming and disconnects.
func (c *Client) Stop() error {
	c.wantScan = false
	// Stop the heartbeat and WAIT for its goroutine to fully exit before any
	// teardown write. Otherwise a heartbeat write can still be in-flight on the
	// write characteristic when STOP_REALTIME / Disconnect run below; its
	// orphaned write-response wedges that call forever and the BLE link never
	// drops (the device "stays connected"). The join also removes the data race
	// on writeChar/hbDone between Stop and the heartbeat goroutine.
	c.stopHeartbeat()

	// Bound each teardown op so a wedged backend cannot hang Stop() forever.
	if c.writeChar != nil {
		withTimeout(2*time.Second, func() { c.writeChar.Write(stopRealtime) })
	}
	if c.peripheral != nil {
		withTimeout(5*time.Second, func() { c.peripheral.Disconnect() })
	}
	c.resetState()
	c.setStatus(StatusIdle)
	return nil
}

// stopHeartbeat signals the heartbeat goroutine to exit and blocks until it
// has fully returned, guaranteeing no heartbeat write is in-flight afterward.
func (c *Client) stopHeartbeat() {
	if c.hbDone != nil {
		close(c.hbDone)
		// Wait for the goroutine to observe the close and exit BEFORE clearing
		// hbDone. If we niled it first, the goroutine's next select would read a
		// nil channel — its <-c.hbDone case would be permanently disabled, it
		// would never see the close, and hbWG.Wait() would hang forever
		// (reintroducing the teardown hang). Clearing after Wait() also removes
		// the data race on hbDone, since the goroutine is gone by then.
		c.hbWG.Wait()
		c.hbDone = nil
	}
}

// withTimeout runs fn, returning when it completes or after d, whichever comes
// first. If fn is wedged on a BLE call it keeps running in its own goroutine
// (leaked) rather than blocking the caller past d — the right tradeoff for a
// best-effort teardown that must not hang.
func withTimeout(d time.Duration, fn func()) {
	done := make(chan struct{})
	go func() {
		fn()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(d):
	}
}

// errScanTimeout is produced when the 10s scan window elapses with no device
// discovered. It is a sentinel so the not-found path can be identified via
// errors.Is without matching on the error string.
var errScanTimeout = errors.New("scan timeout")

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
		case done <- errScanTimeout:
		default:
		}
	}()

	err := <-done
	// The scan timed out with no device discovered. Record why before the caller
	// can observe the failure. Setting the reason + status here (in the receiving
	// goroutine) rather than in the timeout goroutine keeps it race-free: the
	// send happens-before this receive, and Start's caller only reads after we
	// return. NOTE: the pre-existing code returned this timeout error while
	// leaving the status at StatusScanning; to make FailureNotFound observable
	// (a reason is only meaningful alongside StatusFailed) this now also
	// transitions to StatusFailed. No Status value, state, or callback signature
	// changed — only this previously-missing terminal transition was added.
	if errors.Is(err, errScanTimeout) {
		c.failureReason = FailureNotFound
		c.setStatus(StatusFailed)
	}
	return err
}

func (c *Client) connectAndStream(addr string) error {
	c.setStatus(StatusConnecting)
	p, err := c.adapter.Connect(addr)
	if err != nil {
		c.failureReason = FailureConnectionFailed
		c.setStatus(StatusFailed)
		return fmt.Errorf("connect: %w", err)
	}
	c.peripheral = p

	services, err := p.DiscoverServices()
	if err != nil {
		c.failureReason = FailureConnectionFailed
		c.setStatus(StatusFailed)
		return fmt.Errorf("discover services: %w", err)
	}

	for _, svc := range services {
		if !containsUUID(svc.UUID(), serviceUUID) {
			continue
		}
		chars, err := svc.DiscoverCharacteristics()
		if err != nil {
			continue
		}
		for _, ch := range chars {
			if containsUUID(ch.UUID(), writeUUID) {
				c.writeChar = ch
			}
			if containsUUID(ch.UUID(), notifyUUID) {
				c.notifyChar = ch
			}
		}
	}

	if c.writeChar == nil || c.notifyChar == nil {
		c.failureReason = FailureConnectionFailed
		c.setStatus(StatusFailed)
		return errors.New("characteristics not found")
	}

	c.notifyChar.Subscribe(func(data []byte) {
		reading := parseReading(data)
		if reading == nil {
			return
		}
		c.latest = reading
		c.lastReadAt = time.Now()
		if c.OnReading != nil {
			c.OnReading(*reading)
		}
		minutes := c.downsampler.Add(*reading)
		if len(minutes) > 0 && c.OnMinute != nil {
			c.OnMinute(minutes)
		}
	})

	// Serialized start sequence
	for _, cmd := range startSequence {
		if err := c.writeChar.Write(cmd); err != nil {
			c.failureReason = FailureConnectionFailed
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
	c.hbWG.Add(1)
	go func() {
		defer c.hbWG.Done()
		ticker := time.NewTicker(c.hbInterval)
		defer ticker.Stop()
		for {
			select {
			case <-c.hbDone:
				return
			case <-ticker.C:
				if c.status != StatusStreaming {
					return
				}
				if c.writeChar != nil {
					c.writeChar.Write(heartbeat)
				}
				if c.lastReadAt.IsZero() {
					continue
				}
				if time.Since(c.lastReadAt) > c.staleTimeout {
					c.latest = nil
					c.downsampler.Flush()
				}
			}
		}
	}()
}

func (c *Client) resetState() {
	c.stopHeartbeat()
	c.peripheral = nil
	c.writeChar = nil
	c.notifyChar = nil
	c.latest = nil
}

func containsUUID(uuidStr, target string) bool {
	return len(uuidStr) >= len(target) && uuidStr[len(uuidStr)-len(target):] == target
}
