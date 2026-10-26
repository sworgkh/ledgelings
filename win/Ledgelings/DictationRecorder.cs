using System.Runtime.InteropServices;
using Ledgelings.Core;
using Ledgelings.Native;

namespace Ledgelings;

/// <summary>
/// The microphone for dictation (SPEC §7.13), the Mac's <c>DictationRecorder.swift</c>: the default recording
/// device through winmm, asked for 16 kHz mono 16-bit, so Windows does the converting. Ten buffers of a tenth of
/// a second go round; <see cref="Collect"/>, called every tick, takes the full ones, keeps their samples in
/// memory only and puts them back. Nothing is written to disk; the samples are dropped once the model has them.
/// </summary>
public sealed class DictationRecorder : IDisposable
{
    public sealed class Failure : Exception
    {
        public bool NoMicrophone { get; }
        public Failure(string message, bool noMicrophone) : base(message) { NoMicrophone = noMicrophone; }
    }

    private const int Buffers = 10, BufferSamples = Dictation.SampleRate / 10;
    private static readonly int HeaderSize = Marshal.SizeOf<WaveIn.WAVEHDR>();
    private IntPtr device;
    private readonly IntPtr[] headers = new IntPtr[Buffers];
    private readonly IntPtr[] data = new IntPtr[Buffers];
    private readonly List<short> samples = new(Dictation.SampleRate * 30);
    /// <summary>The buffers in the order Windows fills them: the oldest first.</summary>
    private readonly Queue<int> queued = new();
    private double lastRms;
    private bool running;

    /// <summary>The microphone Windows would record from, by name, or null when there is none.</summary>
    public static string? MicrophoneName
    {
        get
        {
            if (WaveIn.waveInGetNumDevs() == 0) return null;
            return WaveIn.waveInGetDevCapsW(new IntPtr(WaveIn.WAVE_MAPPER), out var caps, (uint)Marshal.SizeOf<WaveIn.WAVEINCAPSW>()) == WaveIn.MMSYSERR_NOERROR
                ? caps.szPname : L10n.Tr("Microphone");
        }
    }

    /// <summary>Windows' microphone switch for desktop apps; refused there, a recording is silence.</summary>
    public static void OpenPrivacySettings()
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("ms-settings:privacy-microphone") { UseShellExecute = true }); }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException) { Console.Error.WriteLine("Ledgelings: " + e.Message); }
    }

    /// <summary>Starts listening. Throws when there is no microphone or it will not open.</summary>
    public void Start()
    {
        if (WaveIn.waveInGetNumDevs() == 0) throw new Failure(new Dictation.Trouble(Dictation.TroubleKind.NoMicrophone).Line, true);
        var format = new WaveIn.WAVEFORMATEX
        {
            wFormatTag = 1, nChannels = 1, nSamplesPerSec = Dictation.SampleRate, nAvgBytesPerSec = Dictation.SampleRate * 2,
            nBlockAlign = 2, wBitsPerSample = 16, cbSize = 0,
        };
        var opened = WaveIn.waveInOpen(out device, WaveIn.WAVE_MAPPER, ref format, IntPtr.Zero, IntPtr.Zero, WaveIn.CALLBACK_NULL);
        if (opened != WaveIn.MMSYSERR_NOERROR)
            throw new Failure(L10n.Tr("The microphone would not start: %@", "waveInOpen " + opened),
                              opened is WaveIn.MMSYSERR_NODRIVER or WaveIn.MMSYSERR_BADDEVICEID);
        for (int k = 0; k < Buffers; k++)
        {
            data[k] = Marshal.AllocHGlobal(BufferSamples * 2);
            headers[k] = Marshal.AllocHGlobal(HeaderSize);
            Marshal.StructureToPtr(new WaveIn.WAVEHDR { lpData = data[k], dwBufferLength = BufferSamples * 2 }, headers[k], false);
            WaveIn.waveInPrepareHeader(device, headers[k], (uint)HeaderSize);
            WaveIn.waveInAddBuffer(device, headers[k], (uint)HeaderSize);
            queued.Enqueue(k);
        }
        samples.Clear();
        lastRms = 0;
        WaveIn.waveInStart(device);
        running = true;
    }

    /// <summary>Takes in every buffer Windows has filled and hands it back for more. Every tick.</summary>
    public void Collect()
    {
        if (!running) return;
        while (queued.Count > 0 && Take(queued.Peek(), requeue: true)) { }
    }

    /// <summary>The oldest buffer's samples, when it is full; false while Windows is still filling it.</summary>
    private bool Take(int k, bool requeue)
    {
        var header = Marshal.PtrToStructure<WaveIn.WAVEHDR>(headers[k]);
        if ((header.dwFlags & WaveIn.WHDR_DONE) == 0) return false;
        queued.Dequeue();
        var count = (int)header.dwBytesRecorded / 2;
        if (count > 0)
        {
            var chunk = new short[count];
            Marshal.Copy(data[k], chunk, 0, count);
            samples.AddRange(chunk);
            double sum = 0;
            foreach (var s in chunk) { var f = s / 32768.0; sum += f * f; }
            lastRms = Math.Sqrt(sum / count);
        }
        if (!requeue) return true;
        header.dwFlags &= ~WaveIn.WHDR_DONE;
        header.dwBytesRecorded = 0;
        Marshal.StructureToPtr(header, headers[k], false);
        WaveIn.waveInAddBuffer(device, headers[k], (uint)HeaderSize);
        queued.Enqueue(k);
        return true;
    }

    /// <summary>How loud the last tenth of a second was, 0 to 1.</summary>
    public double Level => Dictation.Level(lastRms);

    public double Seconds => (double)samples.Count / Dictation.SampleRate;

    /// <summary>Stops listening and hands back everything heard; the recorder keeps nothing.</summary>
    public short[] Stop()
    {
        if (!running) return Array.Empty<short>();
        Collect();
        running = false;
        // Reset hands back every buffer still queued, the half-full one too, marked done, in order.
        WaveIn.waveInReset(device);
        while (queued.Count > 0 && Take(queued.Peek(), requeue: false)) { }
        queued.Clear();
        var heard = samples.ToArray();
        samples.Clear();
        Free();
        return heard;
    }

    private void Free()
    {
        for (int k = 0; k < Buffers; k++)
        {
            if (headers[k] != IntPtr.Zero)
            {
                WaveIn.waveInUnprepareHeader(device, headers[k], (uint)HeaderSize);
                Marshal.FreeHGlobal(headers[k]);
                headers[k] = IntPtr.Zero;
            }
            if (data[k] != IntPtr.Zero) { Marshal.FreeHGlobal(data[k]); data[k] = IntPtr.Zero; }
        }
        if (device != IntPtr.Zero) { WaveIn.waveInClose(device); device = IntPtr.Zero; }
    }

    public void Dispose()
    {
        if (running) Stop();
        else Free();
    }
}
