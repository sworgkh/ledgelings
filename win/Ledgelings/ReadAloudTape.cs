namespace Ledgelings;

/// <summary>
/// Read aloud's sound pieces (SPEC §7.16), the Mac's <c>decode</c>, <c>silence</c> and <c>join</c>: every part, whatever
/// sent it, as one format, 24 kHz mono 16-bit, so the parts and the rests between them join into one WAV. The Mac
/// converts with <c>AVAudioConverter</c>; Windows gives a .NET app nothing of the kind, so the samples are mixed down
/// and resampled here, between the two samples each output sample falls on: the pitch and the length are kept.
/// An MP3 has no decoder here: it is played as it came, and cannot be joined.
/// </summary>
public static class ReadAloudTape
{
    public const int Rate = 24_000;

    /// <summary>A WAV reply (PCM from OpenRouter with its header, a local server's, SAPI's) as 24 kHz mono; null for
    /// anything else (an MP3).</summary>
    public static WaveTape.Pcm? Decode(byte[] audio) => WaveTape.Read(audio) is { } pcm ? Resampled(Mono(pcm), Rate) : null;

    /// <summary>The channels averaged into one.</summary>
    public static WaveTape.Pcm Mono(WaveTape.Pcm pcm)
    {
        if (pcm.Channels <= 1) return pcm;
        var c = pcm.Channels;
        var output = new short[pcm.Frames];
        for (var i = 0; i < output.Length; i++)
        {
            var sum = 0;
            for (var ch = 0; ch < c; ch++) sum += pcm.Samples[i * c + ch];
            output[i] = (short)(sum / c);
        }
        return new WaveTape.Pcm(pcm.Rate, 1, output);
    }

    /// <summary>The same sound at <paramref name="rate"/> samples a second, as long as before.</summary>
    public static WaveTape.Pcm Resampled(WaveTape.Pcm pcm, int rate)
    {
        if (pcm.Frames == 0) return new WaveTape.Pcm(rate, pcm.Channels, Array.Empty<short>());
        if (pcm.Rate == rate) return pcm;
        // Read faster or slower like a tape, then labelled with the new rate: the same seconds, the same pitch.
        return WaveTape.Speed(pcm, (double)pcm.Rate / rate) with { Rate = rate };
    }

    /// <summary>Quiet, <paramref name="seconds"/> long.</summary>
    public static WaveTape.Pcm Silence(double seconds) => new(Rate, 1, new short[Math.Max(0, (int)(seconds * Rate))]);

    /// <summary>The pieces one after the other, in the tape's format.</summary>
    public static WaveTape.Pcm Join(IEnumerable<WaveTape.Pcm> pieces)
    {
        var all = pieces.Select(p => Resampled(Mono(p), Rate)).ToList();
        var samples = new short[all.Sum(p => p.Samples.Length)];
        var at = 0;
        foreach (var p in all)
        {
            Array.Copy(p.Samples, 0, samples, at, p.Samples.Length);
            at += p.Samples.Length;
        }
        return new WaveTape.Pcm(Rate, 1, samples);
    }

    /// <summary>The pieces as one 16-bit WAV file's bytes.</summary>
    public static byte[] Wav(IEnumerable<WaveTape.Pcm> pieces) => WaveTape.Write(Join(pieces));
}
