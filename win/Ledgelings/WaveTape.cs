using System.Text;

namespace Ledgelings;

/// <summary>
/// A WAV clip played faster like a tape: <c>rate</c> times quicker and so that much
/// higher. The Mac does this with a varispeed audio unit as the clip plays; Windows
/// ships no such thing to a .NET app, so the 16-bit samples are resampled here
/// before playing, which sounds the same: no time-stretching, so no echo.
/// </summary>
public static class WaveTape
{
    /// <summary>16-bit little-endian samples, channels interleaved.</summary>
    public sealed record Pcm(int Rate, int Channels, short[] Samples)
    {
        public int Frames => Channels == 0 ? 0 : Samples.Length / Channels;
        public double Duration => Rate == 0 ? 0 : (double)Frames / Rate;
    }

    /// <summary>The samples of a 16-bit PCM WAV; null for anything else (MP3, float, compressed).
    /// A data chunk that claims more than the file holds, as a streaming server writes it, is read to the end.</summary>
    public static Pcm? Read(byte[] wav)
    {
        if (wav.Length < 12 || Encoding.ASCII.GetString(wav, 0, 4) != "RIFF" || Encoding.ASCII.GetString(wav, 8, 4) != "WAVE") return null;
        int at = 12, channels = 0, rate = 0, bits = 0, format = 0;
        while (at + 8 <= wav.Length)
        {
            var id = Encoding.ASCII.GetString(wav, at, 4);
            var size = (long)BitConverter.ToUInt32(wav, at + 4);
            var body = at + 8;
            if (id == "fmt " && body + 16 <= wav.Length)
            {
                format = BitConverter.ToUInt16(wav, body);
                channels = BitConverter.ToUInt16(wav, body + 2);
                rate = (int)BitConverter.ToUInt32(wav, body + 4);
                bits = BitConverter.ToUInt16(wav, body + 14);
                // WAVE_FORMAT_EXTENSIBLE carries the real format in its sub-format GUID's first two bytes.
                if (format == 0xFFFE && size >= 26 && body + 26 <= wav.Length) format = BitConverter.ToUInt16(wav, body + 24);
            }
            else if (id == "data")
            {
                if (format != 1 || bits != 16 || channels < 1 || rate < 1) return null;
                var length = (int)Math.Min(size, wav.Length - body);
                length -= length % (2 * channels);
                var samples = new short[length / 2];
                Buffer.BlockCopy(wav, body, samples, 0, length);
                return new Pcm(rate, channels, samples);
            }
            at = body + (int)Math.Min(size + (size & 1), wav.Length);
        }
        return null;
    }

    public static byte[] Write(Pcm pcm)
    {
        var bytes = new byte[pcm.Samples.Length * 2];
        Buffer.BlockCopy(pcm.Samples, 0, bytes, 0, bytes.Length);
        return SpeechClient.Wav(bytes, pcm.Rate, pcm.Channels);
    }

    /// <summary>The clip <paramref name="rate"/> times faster and higher, at its own sample rate,
    /// each output sample read between the two input samples it falls on.</summary>
    public static Pcm Speed(Pcm pcm, double rate)
    {
        if (Math.Abs(rate - 1) < 0.001 || pcm.Frames < 2) return pcm;
        var c = pcm.Channels;
        var frames = (int)Math.Floor((pcm.Frames - 1) / rate) + 1;
        var output = new short[frames * c];
        for (int i = 0; i < frames; i++)
        {
            var position = i * rate;
            var j = (int)position;
            var k = Math.Min(j + 1, pcm.Frames - 1);
            var t = position - j;
            for (int ch = 0; ch < c; ch++)
            {
                var a = pcm.Samples[j * c + ch];
                var b = pcm.Samples[k * c + ch];
                output[i * c + ch] = (short)Math.Round(a + (b - a) * t);
            }
        }
        return pcm with { Samples = output };
    }
}
