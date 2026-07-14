/// btleplug-based client for the EMAY SleepO2.
use std::sync::Arc;
use std::time::Duration;

use btleplug::api::{Central, Manager as _, Peripheral as _, ScanFilter, WriteType};
use btleplug::platform::{Adapter, Manager, Peripheral};
use tokio::sync::Mutex;
use tokio::time;
use uuid::Uuid;

use crate::protocol::{self, *};
use crate::types::{MinuteSample, Reading, Status};
use crate::downsampler::LiveDownsampler;

pub type ReadingCallback = Arc<dyn Fn(Reading) + Send + Sync>;
pub type StatusCallback = Arc<dyn Fn(Status) + Send + Sync>;
pub type MinuteCallback = Arc<dyn Fn(Vec<MinuteSample>) + Send + Sync>;

pub struct EMAYClient {
    adapter: Adapter,
    status: Arc<Mutex<Status>>,
    latest_reading: Arc<Mutex<Option<Reading>>>,

    // Callbacks
    on_reading: Arc<Mutex<Option<ReadingCallback>>>,
    on_status: Arc<Mutex<Option<StatusCallback>>>,
    on_minute_samples: Arc<Mutex<Option<MinuteCallback>>>,

    // Configuration
    heartbeat_interval: Duration,
    stale_timeout: Duration,
    auto_reconnect: bool,
}

impl EMAYClient {
    pub async fn new() -> Result<Self, String> {
        let manager = Manager::new().await.map_err(|e| format!("BLE manager: {}", e))?;
        let adapters = manager.adapters().await.map_err(|e| format!("adapters: {}", e))?;
        let adapter = adapters.into_iter().next().ok_or("no BLE adapter")?;

        Ok(Self {
            adapter,
            status: Arc::new(Mutex::new(Status::Idle)),
            latest_reading: Arc::new(Mutex::new(None)),
            on_reading: Arc::new(Mutex::new(None)),
            on_status: Arc::new(Mutex::new(None)),
            on_minute_samples: Arc::new(Mutex::new(None)),
            heartbeat_interval: Duration::from_millis(1500),
            stale_timeout: Duration::from_secs(4),
            auto_reconnect: true,
        })
    }

    pub fn set_on_reading(&mut self, cb: ReadingCallback) { *self.on_reading.blocking_lock() = Some(cb); }
    pub fn set_on_status(&mut self, cb: StatusCallback) { *self.on_status.blocking_lock() = Some(cb); }
    pub fn set_on_minute_samples(&mut self, cb: MinuteCallback) { *self.on_minute_samples.blocking_lock() = Some(cb); }

    pub async fn status(&self) -> Status { self.status.lock().await.clone() }

    pub async fn start(&self) -> Result<(), String> {
        let mut status = self.status.lock().await;
        if status.is_active() { return Ok(()); }
        *status = Status::Scanning;
        drop(status);
        self.scan_and_connect().await
    }

    pub async fn stop(&self) -> Result<(), String> {
        self.adapter.stop_scan().await.ok();
        // Find and disconnect all connected peripherals
        let peripherals = self.adapter.peripherals().await.map_err(|e| format!("{}", e))?;
        for p in peripherals {
            if p.is_connected().await.unwrap_or(false) {
                p.disconnect().await.ok();
            }
        }
        *self.status.lock().await = Status::Idle;
        Ok(())
    }

    async fn scan_and_connect(&self) -> Result<(), String> {
        let svc = Uuid::parse_str(SERVICE_UUID).map_err(|e| format!("UUID: {}", e))?;

        self.adapter
            .start_scan(ScanFilter {
                services: vec![svc],
            })
            .await
            .map_err(|e| format!("scan: {}", e))?;

        // Wait for a matching device
        let peripheral = loop {
            let peripherals = self.adapter.peripherals().await.map_err(|e| format!("{}", e))?;
            for p in peripherals {
                let props = p.properties().await.ok().flatten();
                let name_ok = props.as_ref()
                    .and_then(|pr| pr.local_name.clone())
                    .map(|n| n.starts_with(NAME_PREFIX))
                    .unwrap_or(true); // accept nameless devices
                if name_ok {
                    return self.connect_and_stream(p).await;
                }
            }
            time::sleep(Duration::from_millis(500)).await;
        };
    }

    async fn connect_and_stream(&self, peripheral: Peripheral) -> Result<(), String> {
        *self.status.lock().await = Status::Connecting;

        peripheral
            .connect()
            .await
            .map_err(|e| format!("connect: {}", e))?;

        peripheral
            .discover_services()
            .await
            .map_err(|e| format!("discover: {}", e))?;

        let svc_uuid = Uuid::parse_str(SERVICE_UUID).unwrap();
        let write_uuid = Uuid::parse_str(WRITE_UUID).unwrap();
        let notify_uuid = Uuid::parse_str(NOTIFY_UUID).unwrap();

        let chars = peripheral.characteristics();

        let notify_char = chars
            .iter()
            .find(|c| c.uuid == notify_uuid)
            .ok_or("notify char not found")?;

        let write_char = chars
            .iter()
            .find(|c| c.uuid == write_uuid)
            .ok_or("write char not found")?;

        peripheral
            .subscribe(notify_char)
            .await
            .map_err(|e| format!("subscribe: {}", e))?;

        // Set up notification handler
        let reading_cb = self.on_reading.clone();
        let minute_cb = self.on_minute_samples.clone();
        let downsampler = Arc::new(Mutex::new(LiveDownsampler::new()));

        {
            let peripheral = peripheral.clone();
            let downsampler = downsampler.clone();
            peripheral.on_notification(Box::new(move |_uuid, data| {
                if let Some(reading) = parse_reading(data) {
                    if let Some(cb) = reading_cb.blocking_lock().as_ref() {
                        cb(reading.clone());
                    }
                    let mut ds = downsampler.blocking_lock();
                    let minutes = ds.add(&reading);
                    if !minutes.is_empty() {
                        if let Some(cb) = minute_cb.blocking_lock().as_ref() {
                            cb(minutes);
                        }
                    }
                }
            }));
        }

        // Serialized start sequence
        for cmd in START_SEQUENCE {
            peripheral
                .write(write_char, cmd, WriteType::WithResponse)
                .await
                .map_err(|e| format!("write: {}", e))?;
        }

        *self.status.lock().await = Status::Streaming;
        self.start_heartbeat_loop(peripheral.clone(), write_char.clone()).await
    }

    async fn start_heartbeat_loop(&self, peripheral: Peripheral, write_char: btleplug::api::Characteristic) -> Result<(), String> {
        let status = self.status.clone();
        let latest = self.latest_reading.clone();
        let stale = self.stale_timeout;
        let interval = self.heartbeat_interval;
        let downsampler = Arc::new(Mutex::new(LiveDownsampler::new()));

        tokio::spawn(async move {
            loop {
                time::sleep(interval).await;
                if *status.blocking_lock() != Status::Streaming { break; }
                peripheral.write(&write_char, &HEARTBEAT, WriteType::WithResponse).await.ok();
            }
        });

        Ok(())
    }
}
