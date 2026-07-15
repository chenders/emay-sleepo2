/*
 * EMAY SleepO2 — C# types, protocol, and BLE client
 * Copyright (c) 2026 Ground Effect Software, LLC · MIT
 *
 * BLE backends:
 *   Windows:  Windows.Devices.Bluetooth (UWP / .NET 8+)
 *   Linux:    BlueZ via D-Bus (Tmds.DBus or similar)
 *   macOS:    CoreBluetooth via Xamarin.Mac or .NET MAUI
 *   Android:  Android.Bluetooth via Xamarin.Android / .NET MAUI
 *
 * This reference implementation shows the abstract workflow.
 * A production library would use a platform DI strategy.
 */
namespace GroundEffectSoftware.EMAYSleepO2;

using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

/* ---- Types ---- */

public record EMAYReading(int? Spo2, int? Pulse, long TimestampMs);

public record MinuteSample(long MinuteStartMs, string MetricType, double Value, string UnitString);

/* ---- Protocol ---- */

public static class EMAYProtocol
{
    public static readonly Guid SvcUuid = Guid.Parse("0000ff12-0000-1000-8000-00805f9b34fb");
    public static readonly Guid WrUuid  = Guid.Parse("0000ff01-0000-1000-8000-00805f9b34fb");
    public static readonly Guid NfyUuid = Guid.Parse("0000ff02-0000-1000-8000-00805f9b34fb");
    public const string NamePrefix = "SleepO2";

    public static readonly byte[] Hello       = { 0x89, 0x09 };
    public static readonly byte[] DeviceState = { 0x8E, 0x05, 0x13 };
    public static readonly byte[] StartCmd    = { 0x9B, 0x01, 0x1C };
    public static readonly byte[] StopCmd     = { 0x9B, 0x7F, 0x1A };
    public static readonly byte[] Battery     = { 0x86, 0x06 };
    public static readonly byte[] Heartbeat   = { 0x9A, 0x1A };
    public static readonly byte[][] StartSeq  = { Hello, DeviceState, StartCmd, Battery };

    public static byte Checksum(byte[] p) => (byte)(p.Sum(b => (int)b) & 0x7F);
    public static byte[] Command(byte[] p) => [..p, Checksum(p)];

    public static EMAYReading? Parse(byte[] raw)
    {
        if (raw is not { Length: 8 }) return null;
        if (raw[0] != 0xEB || raw[1] != 1 || raw[2] != 5) return null;
        if (raw[5] != 0x7F || raw[6] != 0) return null;
        int sum = 0; for (int i = 0; i < 7; i++) sum += raw[i];
        if (raw[7] != (byte)(sum & 0x7F)) return null;
        int pr = raw[3], so = raw[4];
        int? pulse = (pr == 0 || pr == 0xFF) ? null : pr;
        int? spo2  = (so == 0 || so == 0xFF) ? null : so;
        if (pulse is < 30 or > 220) return null;
        if (spo2 is < 0 or > 100) return null;
        return new EMAYReading(spo2, pulse, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
    }
}

/* ---- BLE Client (abstract — backends below) ---- */

public abstract class EMAYBLEClient : IDisposable
{
    public event Action<EMAYReading>? OnReading;
    public event Action<string>? OnStatus;

    protected void Emit(EMAYReading r) => OnReading?.Invoke(r);
    protected void Emit(string s) => OnStatus?.Invoke(s);

    public abstract Task StartAsync(CancellationToken ct = default);
    public abstract Task StopAsync();

    public virtual void Dispose() => StopAsync().GetAwaiter().GetResult();
}

/* ---- Windows BLE backend ---- */
#if WINDOWS

using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Advertisement;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Storage.Streams;

public class EMAYWindowsBLEClient : EMAYBLEClient
{
    private BluetoothLEDevice? _device;
    private GattCharacteristic? _wr, _nfy;
    private Timer? _heartbeat;

    public override async Task StartAsync(CancellationToken ct = default)
    {
        Emit("scanning");
        var watcher = new BluetoothLEAdvertisementWatcher
        {
            ScanningMode = BluetoothLEScanningMode.Active
        };
        var tcs = new TaskCompletionSource<BluetoothLEDevice>();

        watcher.Received += (s, args) =>
        {
            if (args.Advertisement.LocalName?.StartsWith(EMAYProtocol.NamePrefix) == true)
            {
                watcher.Stop();
                _ = Task.Run(async () =>
                {
                    var dev = await BluetoothLEDevice.FromBluetoothAddressAsync(args.BluetoothAddress);
                    if (dev != null) tcs.TrySetResult(dev);
                }, ct);
            }
        };
        watcher.Start();
        _device = await tcs.Task;

        Emit("connecting");
        var svcResult = await _device.GetGattServiceAsync(EMAYProtocol.SvcUuid);
        var svc = svcResult.Service;
        _wr  = (await svc.GetCharacteristicsAsync(EMAYProtocol.WrUuid)).Characteristics.FirstOrDefault();
        _nfy = (await svc.GetCharacteristicsAsync(EMAYProtocol.NfyUuid)).Characteristics.FirstOrDefault();

        await _nfy!.WriteClientCharacteristicConfigurationDescriptorAsync(
            GattClientCharacteristicConfigurationDescriptorValue.Notify);

        Emit("streaming");
        _nfy.ValueChanged += (s, args) =>
        {
            var r = EMAYProtocol.Parse(args.CharacteristicValue.ToArray());
            if (r != null) Emit(r);
        };

        foreach (var cmd in EMAYProtocol.StartSeq)
            await _wr.WriteValueAsync(cmd.AsBuffer());

        _heartbeat = new Timer(async _ =>
        {
            if (_wr != null)
                await _wr.WriteValueAsync(EMAYProtocol.Heartbeat.AsBuffer());
        }, null, 1000, 1000);
    }

    public override async Task StopAsync()
    {
        _heartbeat?.Dispose();
        _device?.Dispose();
        Emit("stopped");
        await Task.CompletedTask;
    }
}
#endif

/* ---- Linux BlueZ backend (reference — requires Tmds.DBus) ---- */
#if LINUX
public class EMAYLinuxBLEClient : EMAYBLEClient
{
    // Uses org.bluez via Tmds.DBus.
    // Workflow: Adapter1.StartDiscovery → Device1.Connect →
    //           GattCharacteristic1.StartNotify → WriteValue for commands.
    // Full implementation ~150 lines of D-Bus method calls.
    public override Task StartAsync(CancellationToken ct = default)
    {
        Emit("Linux BlueZ BLE client — requires Tmds.DBus and org.bluez");
        return Task.CompletedTask;
    }
    public override Task StopAsync() { Emit("stopped"); return Task.CompletedTask; }
}
#endif
