/**
 * BLE client for the EMAY SleepO2 (Node.js / noble).
 */

import { EventEmitter } from "events";
import {
  Reading, MinuteSample, Status
} from "./types.js";
import {
  SERVICE_UUID, WRITE_UUID, NOTIFY_UUID, NAME_PREFIX,
  HEARTBEAT, START_SEQUENCE, STOP_REALTIME,
  parseReading,
} from "./protocol.js";
import { LiveDownsampler } from "./downsampler.js";

// ---- BLE adapter interface (for injecting noble forks) ----

export interface BLEAdapter {
  startScanning(serviceUUIDs: string[]): Promise<void>;
  stopScanning(): void;
  connect(peripheralId: string): Promise<BLEPeripheral>;
  on(event: "discover", cb: (p: BLEPeripheral) => void): void;
  on(event: "stateChange", cb: (state: string) => void): void;
}

export interface BLEPeripheral {
  id: string;
  address: string;
  advertisement: { localName?: string };
  connect(): Promise<void>;
  disconnect(): Promise<void>;
  discoverServices(): Promise<BLEService[]>;
  on(event: "disconnect", cb: () => void): void;
}

export interface BLEService {
  uuid: string;
  characteristics: BLECharacteristic[];
  discoverCharacteristics(): Promise<BLECharacteristic[]>;
}

export interface BLECharacteristic {
  uuid: string;
  write(data: Buffer, withoutResponse?: boolean): Promise<void>;
  subscribe(cb: (data: Buffer) => void): Promise<void>;
  unsubscribe(): Promise<void>;
}

// ---- Noble BLE Adapter (default) ----

class NobleAdapter implements BLEAdapter {
  private noble: any;

  constructor() {
    // Lazy-load noble so this module can be imported without BLE hardware
    try {
      this.noble = require("@abandonware/noble");
    } catch {
      this.noble = require("noble");
    }
  }

  async startScanning(serviceUUIDs: string[]): Promise<void> {
    await this.noble.startScanningAsync(serviceUUIDs, false);
  }

  stopScanning(): void {
    this.noble.stopScanning();
  }

  async connect(id: string): Promise<BLEPeripheral> {
    const p = await this.noble.connectAsync(id);
    return new NoblePeripheral(p);
  }

  on(event: "discover" | "stateChange", cb: any): void {
    if (event === "discover") {
      this.noble.on("discover", (p: any) => cb(new NoblePeripheral(p)));
    } else if (event === "stateChange") {
      this.noble.on("stateChange", cb);
    }
  }
}

class NoblePeripheral implements BLEPeripheral {
  constructor(private p: any) {}
  get id(): string { return this.p.id; }
  get address(): string { return this.p.address; }
  get advertisement() { return this.p.advertisement; }

  async connect(): Promise<void> { await this.p.connectAsync(); }
  async disconnect(): Promise<void> { await this.p.disconnectAsync(); }

  async discoverServices(): Promise<BLEService[]> {
    const services = await this.p.discoverServicesAsync();
    return services.map((s: any) => new NobleService(s));
  }

  on(event: "disconnect", cb: () => void): void {
    this.p.on(event, cb);
  }
}

class NobleService implements BLEService {
  constructor(private s: any) {}
  get uuid(): string { return this.s.uuid; }
  get characteristics(): BLECharacteristic[] {
    return (this.s.characteristics || []).map((c: any) => new NobleCharacteristic(c));
  }

  async discoverCharacteristics(): Promise<BLECharacteristic[]> {
    const chars = await this.s.discoverCharacteristicsAsync();
    return chars.map((c: any) => new NobleCharacteristic(c));
  }
}

class NobleCharacteristic implements BLECharacteristic {
  constructor(private c: any) {}
  get uuid(): string { return this.c.uuid; }
  async write(data: Buffer, withoutResponse?: boolean): Promise<void> {
    await this.c.writeAsync(data, withoutResponse ?? false);
  }
  async subscribe(cb: (data: Buffer) => void): Promise<void> {
    await this.c.subscribeAsync();
    this.c.on("data", cb);
  }
  async unsubscribe(): Promise<void> {
    await this.c.unsubscribeAsync();
  }
}

// ---- EMAY Client ----

export class EMAYClient extends EventEmitter {
  heartbeatInterval: number = 1.5;
  staleTimeout: number = 4.0;
  autoReconnect: boolean = true;

  private adapter: BLEAdapter;
  private _status: Status = Status.Idle;
  private _latestReading: Reading | null = null;
  private peripheral: BLEPeripheral | null = null;
  private writeChar: BLECharacteristic | null = null;
  private notifyChar: BLECharacteristic | null = null;
  private heartbeatTimer: NodeJS.Timeout | null = null;
  private wantScan = false;
  private lastReadingAt: Date | null = null;
  private downsampler = new LiveDownsampler();
  private knownAddress: string | null = null;

  constructor(adapter?: BLEAdapter) {
    super();
    this.adapter = adapter || new NobleAdapter();
  }

  get status(): Status { return this._status; }
  set status(s: Status) {
    if (this._status !== s) {
      this._status = s;
      this.emit("statusChange", s);
    }
  }

  get latestReading(): Reading | null { return this._latestReading; }
  get isStreaming(): boolean { return this._status === Status.Streaming; }

  async start(address?: string): Promise<void> {
    if (this._status === Status.Scanning ||
        this._status === Status.Connecting ||
        this._status === Status.Streaming) return;
    this.wantScan = true;
    if (address) this.knownAddress = address;
    this.status = Status.Scanning;
    await this.beginMonitoring();
  }

  async stop(): Promise<void> {
    this.wantScan = false;
    if (this.heartbeatTimer) { clearInterval(this.heartbeatTimer); this.heartbeatTimer = null; }
    if (this.writeChar && this.peripheral) {
      try { await this.writeChar.write(STOP_REALTIME); } catch {}
    }
    if (this.peripheral) {
      try { await this.peripheral.disconnect(); } catch {}
    }
    this.resetConnectionState();
    this.status = Status.Idle;
  }

  private async beginMonitoring(): Promise<void> {
    return new Promise((resolve) => {
      this.adapter.on("stateChange", async (state: string) => {
        if (state === "poweredOn" && this.wantScan) {
          await this.doScan();
          resolve();
        }
      });
      // If noble already knows state, trigger manually
      try { (this.adapter as any).noble?.emit("stateChange", (this.adapter as any).noble?.state); } catch {}
    });
  }

  private async doScan(): Promise<void> {
    this.status = Status.Scanning;
    let resolved = false;

    return new Promise((resolve) => {
      this.adapter.on("discover", async (p: BLEPeripheral) => {
        if (resolved) return;
        const name = p.advertisement?.localName || "";
        if (name && !name.startsWith(NAME_PREFIX)) return;
        this.adapter.stopScanning();
        resolved = true;
        this.knownAddress = p.address;
        await this.connectTo(p);
        resolve();
      });

      this.adapter.startScanning([SERVICE_UUID]).catch(resolve);

      setTimeout(() => {
        if (!resolved) { this.adapter.stopScanning(); this.status = Status.Failed; resolve(); }
      }, 10000);
    });
  }

  private async connectTo(peripheral: BLEPeripheral): Promise<void> {
    this.peripheral = peripheral;
    this.status = Status.Connecting;
    try {
      await peripheral.connect();
      peripheral.on("disconnect", () => this.onDisconnect());
      const services = await peripheral.discoverServices();
      const svc = services.find((s: any) => s.uuid.includes(SERVICE_UUID));
      if (!svc) { this.status = Status.Failed; return; }
      const chars = await svc.discoverCharacteristics();
      this.writeChar = chars.find((c: any) => c.uuid.includes(WRITE_UUID)) || null;
      this.notifyChar = chars.find((c: any) => c.uuid.includes(NOTIFY_UUID)) || null;
      if (!this.writeChar || !this.notifyChar) { this.status = Status.Failed; return; }

      await this.notifyChar.subscribe(this.onData.bind(this));
      for (const cmd of START_SEQUENCE) {
        await this.writeChar.write(cmd);
      }
      this.status = Status.Streaming;
      this.startHeartbeat();
    } catch {
      this.status = Status.Failed;
    }
  }

  private onData(data: Buffer): void {
    const reading = parseReading(data);
    if (!reading) return;
    this._latestReading = reading;
    this.lastReadingAt = new Date();
    this.emit("reading", reading);
    const minutes = this.downsampler.add(reading);
    if (minutes.length) this.emit("minuteSamples", minutes);
  }

  private onDisconnect(): void {
    const wasFailure = this._status === Status.Failed;
    const isTransient = this.wantScan && !wasFailure && this.autoReconnect;
    if (!isTransient) this.downsampler.flush();
    this.resetConnectionState();
    if (isTransient) {
      setTimeout(() => this.doScan(), 100);
    } else if (!wasFailure) {
      this.status = Status.Idle;
    }
  }

  private startHeartbeat(): void {
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
    this.heartbeatTimer = setInterval(async () => {
      if (this._status !== Status.Streaming || !this.writeChar) return;
      try { await this.writeChar.write(HEARTBEAT); } catch {}
      if (this.lastReadingAt &&
          (Date.now() - this.lastReadingAt.getTime()) > this.staleTimeout * 1000) {
        this._latestReading = null;
        this.downsampler.flush();
      }
    }, this.heartbeatInterval * 1000);
  }

  private resetConnectionState(): void {
    if (this.heartbeatTimer) { clearInterval(this.heartbeatTimer); this.heartbeatTimer = null; }
    this.peripheral = null;
    this.writeChar = null;
    this.notifyChar = null;
    this._latestReading = null;
    this.lastReadingAt = null;
  }
}
