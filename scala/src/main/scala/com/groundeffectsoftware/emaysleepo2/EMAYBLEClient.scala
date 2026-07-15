/*
 * EMAY SleepO2 — Scala types, protocol, and Android BLE client
 * Copyright (c) 2026 Ground Effect Software, LLC · MIT
 *
 * Requires Android API 26+ and the same permissions as the Java version.
 */
package com.groundeffectsoftware.emaysleepo2

import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.ParcelUuid
import java.util.UUID
import java.util.concurrent.{Executors, ScheduledExecutorService, TimeUnit}
import scala.concurrent.{Future, Promise}
import scala.util.{Failure, Success, Try}

/* ---- Types ---- */

case class EMAYReading(spo2: Option[Int], pulse: Option[Int], timestampMs: Long)

case class MinuteSample(minuteStartMs: Long, metricType: String, value: Double, unitString: String)

/* ---- Protocol ---- */

object EMAYProtocol:
  val SvcUuid: UUID = UUID.fromString("0000ff12-0000-1000-8000-00805f9b34fb")
  val WrUuid:  UUID = UUID.fromString("0000ff01-0000-1000-8000-00805f9b34fb")
  val NfyUuid: UUID = UUID.fromString("0000ff02-0000-1000-8000-00805f9b34fb")
  val NamePrefix = "SleepO2"

  val Hello:       Array[Byte] = Array(0x89.toByte, 0x09.toByte)
  val DeviceState: Array[Byte] = Array(0x8E.toByte, 0x05.toByte, 0x13.toByte)
  val StartCmd:    Array[Byte] = Array(0x9B.toByte, 0x01.toByte, 0x1C.toByte)
  val StopCmd:     Array[Byte] = Array(0x9B.toByte, 0x7F.toByte, 0x1A.toByte)
  val Battery:     Array[Byte] = Array(0x86.toByte, 0x06.toByte)
  val Heartbeat:   Array[Byte] = Array(0x9A.toByte, 0x1A.toByte)
  val StartSeq: List[Array[Byte]] = List(Hello, DeviceState, StartCmd, Battery)

  def checksum(payload: Array[Byte]): Byte =
    ((payload.map(_ & 0xFF).sum) & 0x7F).toByte

  def command(payload: Array[Byte]): Array[Byte] =
    payload :+ checksum(payload)

  def parse(raw: Array[Byte]): Option[EMAYReading] =
    if raw == null || raw.length != 8 then return None
    if raw(0) != 0xEB.toByte || raw(1) != 1 || raw(2) != 5 then return None
    if raw(5) != 0x7F || raw(6) != 0 then return None
    val sum = raw.take(7).map(_ & 0xFF).sum
    if raw(7) != (sum & 0x7F).toByte then return None
    val pr   = raw(3) & 0xFF
    val spo2 = raw(4) & 0xFF
    def sentinel(b: Int): Boolean = b == 0 || b == 0xFF
    val pulse = if sentinel(pr) then None else Some(pr)
    val o2    = if sentinel(spo2) then None else Some(spo2)
    if pulse.exists(p => p < 30 || p > 220) then return None
    if o2.exists(s => s < 0 || s > 100) then return None
    Some(EMAYReading(o2, pulse, System.currentTimeMillis()))

/* ---- BLE Client ---- */

class EMAYBLEClient(ctx: Context):
  private val mgr = ctx.getSystemService(Context.BLUETOOTH_SERVICE).asInstanceOf[BluetoothManager]
  private var gatt: Option[BluetoothGatt] = None
  private var wrCh: Option[BluetoothGattCharacteristic] = None
  private var nfyCh: Option[BluetoothGattCharacteristic] = None
  private var callback: Option[(Either[String, EMAYReading]) => Unit] = None
  private val scheduler: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor()
  @volatile private var streaming = false

  def onEvent(cb: Either[String, EMAYReading] => Unit): Unit = callback = Some(cb)

  def start(): Unit =
    val adapter = mgr.getAdapter
    if adapter == null then { emit("no BT adapter"); return }
    emit("scanning")
    val scanner = adapter.getBluetoothLeScanner
    val filter = new ScanFilter.Builder()
      .setServiceUuid(new ParcelUuid(EMAYProtocol.SvcUuid)).build()
    val settings = new ScanSettings.Builder()
      .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
    scanner.startScan(java.util.List.of(filter), settings, new ScanCallback:
      override def onScanResult(callbackType: Int, result: ScanResult): Unit =
        scanner.stopScan(this)
        emit("connecting")
        val dev = result.getDevice
        gatt = Some(dev.connectGatt(ctx, false, gattCallback))
      override def onScanFailed(errorCode: Int): Unit =
        emit(s"scan failed: $errorCode"))

  private val gattCallback = new BluetoothGattCallback:
    override def onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int): Unit =
      if newState == BluetoothProfile.STATE_CONNECTED then
        emit("discovering"); g.discoverServices()
      else
        stop(); emit("disconnected")

    override def onServicesDiscovered(g: BluetoothGatt, status: Int): Unit =
      val svc = Option(g.getService(EMAYProtocol.SvcUuid))
      svc match
        case None => emit("service not found")
        case Some(s) =>
          wrCh  = Option(s.getCharacteristic(EMAYProtocol.WrUuid))
          nfyCh = Option(s.getCharacteristic(EMAYProtocol.NfyUuid))
          (wrCh, nfyCh) match
            case (Some(w), Some(n)) =>
              g.setCharacteristicNotification(n, true)
              Option(n.getDescriptor(UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")))
                .foreach: desc =>
                  desc.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                  g.writeDescriptor(desc)
              emit("streaming")
              EMAYProtocol.StartSeq.foreach: cmd =>
                w.setValue(cmd); g.writeCharacteristic(w)
              streaming = true
              scheduler.scheduleAtFixedRate(
                () => if streaming && gatt.isDefined then
                  w.setValue(EMAYProtocol.Heartbeat); g.writeCharacteristic(w),
                1, 1, TimeUnit.SECONDS)
            case _ => emit("characteristics missing")

    override def onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic): Unit =
      if nfyCh.exists(_ == c) then
        EMAYProtocol.parse(c.getValue).foreach(r => emit(r))

  def stop(): Unit =
    streaming = false
    scheduler.shutdownNow()
    gatt.foreach(_.close())
    gatt = None
    emit("stopped")

  private def emit(status: String): Unit = callback.foreach(_(Left(status)))
  private def emit(reading: EMAYReading): Unit = callback.foreach(_(Right(reading)))
