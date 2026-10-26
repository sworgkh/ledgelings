using System.Runtime.InteropServices;

namespace Ledgelings.Native;

/// <summary>The waveIn half of winmm: Windows' oldest way to record, still there on every PC, which converts
/// the microphone to the format asked for itself (16 kHz mono 16-bit here). No NAudio, no WASAPI COM.</summary>
internal static class WaveIn
{
    public const int WAVE_MAPPER = -1;
    public const uint CALLBACK_NULL = 0;
    public const uint WHDR_DONE = 0x1;
    public const int MMSYSERR_NOERROR = 0;
    public const int MMSYSERR_NODRIVER = 6, MMSYSERR_BADDEVICEID = 2;

    [StructLayout(LayoutKind.Sequential)]
    public struct WAVEFORMATEX
    {
        public ushort wFormatTag, nChannels;
        public uint nSamplesPerSec, nAvgBytesPerSec;
        public ushort nBlockAlign, wBitsPerSample, cbSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct WAVEHDR
    {
        public IntPtr lpData;
        public uint dwBufferLength, dwBytesRecorded;
        public IntPtr dwUser;
        public uint dwFlags, dwLoops;
        public IntPtr lpNext, reserved;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct WAVEINCAPSW
    {
        public ushort wMid, wPid;
        public uint vDriverVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szPname;
        public uint dwFormats;
        public ushort wChannels, wReserved1;
    }

    [DllImport("winmm.dll")] public static extern uint waveInGetNumDevs();
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)] public static extern int waveInGetDevCapsW(IntPtr device, out WAVEINCAPSW caps, uint size);
    [DllImport("winmm.dll")] public static extern int waveInOpen(out IntPtr handle, int device, ref WAVEFORMATEX format, IntPtr callback, IntPtr instance, uint flags);
    [DllImport("winmm.dll")] public static extern int waveInPrepareHeader(IntPtr handle, IntPtr header, uint size);
    [DllImport("winmm.dll")] public static extern int waveInUnprepareHeader(IntPtr handle, IntPtr header, uint size);
    [DllImport("winmm.dll")] public static extern int waveInAddBuffer(IntPtr handle, IntPtr header, uint size);
    [DllImport("winmm.dll")] public static extern int waveInStart(IntPtr handle);
    [DllImport("winmm.dll")] public static extern int waveInStop(IntPtr handle);
    [DllImport("winmm.dll")] public static extern int waveInReset(IntPtr handle);
    [DllImport("winmm.dll")] public static extern int waveInClose(IntPtr handle);
}
