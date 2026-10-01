using System.Text;
using Ledgelings.Core;
using System.Windows.Media;

namespace Ledgelings;

/// <summary>
/// Playing a clip, one at a time. The Mac's clips play through a varispeed, the
/// tape-machine way: faster is higher. Here a 16-bit WAV is resampled by
/// <see cref="WaveTape"/> to the same effect and played by WPF's <see cref="MediaPlayer"/>,
/// which ships with Windows. An MP3 (MiniMax sends nothing else) cannot be resampled
/// without a decoder, so it plays at <c>SpeedRatio</c> = pitch: the pace is kept, the lift is not.
/// </summary>
public sealed partial class Voice
{
    private MediaPlayer? player;

    private void StopPlayer()
    {
        player?.Stop();
        player?.Close();
    }

    /// <summary>Play a clip to its end, <paramref name="pitch"/> times faster and so that much higher.
    /// <paramref name="started"/> hears how long it takes the moment it starts; a clip that does not say
    /// (an MP3 whose length is unknown) is given <paramref name="estimate"/>, so its bubble and turn last as long as the words.</summary>
    private async Task Play(byte[] audio, double pitch, double estimate, Action<double> started, CancellationToken cancel)
    {
        var rate = Math.Clamp(pitch, 0.25, 4);
        var isWav = audio.Length >= 4 && Encoding.ASCII.GetString(audio, 0, 4) == "RIFF";
        var data = audio;
        double? duration = null;
        var speedRatio = 1.0;
        if (isWav && WaveTape.Read(audio) is WaveTape.Pcm pcm)
        {
            var fast = WaveTape.Speed(pcm, rate);
            data = WaveTape.Write(fast);
            duration = fast.Duration;
        }
        else speedRatio = rate;
        var file = Path.Combine(Path.GetTempPath(), $"ledgelings-{Guid.NewGuid()}.{(isWav ? "wav" : "mp3")}");
        File.WriteAllBytes(file, data);
        player ??= new MediaPlayer();
        var opened = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var ended = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        void Opened(object? s, EventArgs e) => opened.TrySetResult(true);
        void Failed(object? s, ExceptionEventArgs e) => opened.TrySetException(new IOException(L10n.Tr("the clip would not play: %@", e.ErrorException?.Message ?? "")));
        void Ended(object? s, EventArgs e) => ended.TrySetResult(true);
        var playing = player;
        playing.MediaOpened += Opened;
        playing.MediaFailed += Failed;
        playing.MediaEnded += Ended;
        try
        {
            playing.Open(new Uri(file));
            if (await Task.WhenAny(opened.Task, Task.Delay(TimeSpan.FromSeconds(10), cancel)) != opened.Task)
            {
                cancel.ThrowIfCancellationRequested();
                throw new IOException(L10n.Tr("the clip would not open"));
            }
            await opened.Task;
            playing.Volume = settings.VoiceVolume;
            playing.SpeedRatio = speedRatio;
            var known = duration ?? (playing.NaturalDuration.HasTimeSpan ? playing.NaturalDuration.TimeSpan.TotalSeconds / speedRatio : 0);
            var length = known > 0 ? known : estimate;
            playing.Play();
            started(length);
            // To its end, as long as it says it takes; a clip of unknown length until it ends, a minute at most.
            await Task.WhenAny(ended.Task, Task.Delay(TimeSpan.FromSeconds(known > 0 ? known + 0.15 : 60), cancel));
            cancel.ThrowIfCancellationRequested();
        }
        finally
        {
            playing.MediaOpened -= Opened;
            playing.MediaFailed -= Failed;
            playing.MediaEnded -= Ended;
            playing.Stop();
            playing.Close();
            _ = DeleteSoon(file);
        }
    }

    /// <summary>The player may hold the file a moment after Close: try again for a few seconds.</summary>
    private static async Task DeleteSoon(string file)
    {
        for (int attempt = 0; attempt < 5; attempt++)
        {
            try { File.Delete(file); return; }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { await Task.Delay(TimeSpan.FromSeconds(1 + attempt)); }
        }
    }

    /// <summary>Clips left in the temp folder by a run that ended mid-line, or a file that stayed locked: gone at start-up.</summary>
    private static void SweepOldClips()
    {
        try
        {
            foreach (var file in Directory.EnumerateFiles(Path.GetTempPath(), "ledgelings-*.*"))
            {
                if (!file.EndsWith(".wav", StringComparison.OrdinalIgnoreCase) && !file.EndsWith(".mp3", StringComparison.OrdinalIgnoreCase)) continue;
                try { if (File.GetLastWriteTimeUtc(file) < DateTime.UtcNow.AddHours(-1)) File.Delete(file); }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
}
