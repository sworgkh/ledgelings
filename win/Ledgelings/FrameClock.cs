using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Threading;

namespace Ledgelings;

/// <summary>
/// A steady frame timer on its own thread, ticking the colony on the UI thread.
/// Windows' ordinary timers round to 15.6 ms; a high-resolution waitable timer
/// gives an even 30 fps without raising the whole system's timer rate.
/// </summary>
public sealed class FrameClock : IDisposable
{
    private readonly Dispatcher dispatcher;
    private readonly Action tick;
    private readonly Thread thread;
    private volatile bool running = true;
    private double fps = 30;

    /// <summary>Frames per second; changed at any time, takes effect next frame.</summary>
    public double Fps { get => fps; set => fps = Math.Max(1, value); }

    public FrameClock(Dispatcher dispatcher, Action tick)
    {
        this.dispatcher = dispatcher;
        this.tick = tick;
        thread = new Thread(Loop) { IsBackground = true, Name = "Ledgelings frames" };
        thread.Start();
    }

    private void Loop()
    {
        var timer = CreateWaitableTimerExW(IntPtr.Zero, null, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
        if (timer == IntPtr.Zero) timer = CreateWaitableTimerExW(IntPtr.Zero, null, 0, TIMER_ALL_ACCESS);
        var watch = Stopwatch.StartNew();
        var next = watch.Elapsed.TotalSeconds;
        while (running)
        {
            next += 1 / fps;
            var now = watch.Elapsed.TotalSeconds;
            if (next < now - 0.25) next = now;      // fell far behind (a sleep, a debugger): do not race to catch up
            var wait = next - now;
            if (wait > 0)
            {
                if (timer != IntPtr.Zero)
                {
                    long due = -(long)(wait * 10_000_000);
                    SetWaitableTimer(timer, ref due, 0, IntPtr.Zero, IntPtr.Zero, false);
                    WaitForSingleObject(timer, 1000);
                }
                else Thread.Sleep(TimeSpan.FromSeconds(wait));
            }
            if (!running) break;
            try { dispatcher.Invoke(tick, DispatcherPriority.Render); }
            catch (TaskCanceledException) { break; }
            catch (InvalidOperationException) { break; }
        }
        if (timer != IntPtr.Zero) CloseHandle(timer);
    }

    public void Dispose() { running = false; }

    private const uint CREATE_WAITABLE_TIMER_HIGH_RESOLUTION = 0x2;
    private const uint TIMER_ALL_ACCESS = 0x1F0003;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWaitableTimerExW(IntPtr attributes, string? name, uint flags, uint access);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetWaitableTimer(IntPtr timer, ref long dueTime, int period, IntPtr routine, IntPtr arg, bool resume);

    [DllImport("kernel32.dll")]
    private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);
}
