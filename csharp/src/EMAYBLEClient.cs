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

public abstract class EMAYBLEClient : IDisposable
{
    public event Action<EMAYReading>? OnReading;
    public event Action<string>? OnStatus;

    /// <summary>
    /// Best-effort reason for the most recent failed session. Reset to
    /// <see cref="FailureReason.None"/> at the start of a scan and set immediately
    /// before a failing transition. See <see cref="FailureReasonExtensions.Message"/>
    /// for user-facing text.
    /// </summary>
    public FailureReason FailureReason { get; private set; } = FailureReason.None;

    protected void Emit(EMAYReading r) => OnReading?.Invoke(r);
    protected void Emit(string s) => OnStatus?.Invoke(s);

    /// <summary>Record why the session failed; call immediately before signaling failure.</summary>
    protected void SetFailureReason(FailureReason reason) => FailureReason = reason;

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
        SetFailureReason(FailureReason.None);
        Emit("scanning");
        // NOTE: this scan awaits a TaskCompletionSource with no timeout, so there is
        // no not-found site to set FailureReason.NotFound on. A production port would
        // add a scan timeout and set NotFound before failing here.
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
        if (svc == null)
        {
            SetFailureReason(FailureReason.ConnectionFailed);
            Emit("failed");
            return;
        }
        _wr  = (await svc.GetCharacteristicsAsync(EMAYProtocol.WrUuid)).Characteristics.FirstOrDefault();
        _nfy = (await svc.GetCharacteristicsAsync(EMAYProtocol.NfyUuid)).Characteristics.FirstOrDefault();
        if (_wr == null || _nfy == null)
        {
            SetFailureReason(FailureReason.ConnectionFailed);
            Emit("failed");
            return;
        }

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
