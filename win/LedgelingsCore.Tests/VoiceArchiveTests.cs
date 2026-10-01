namespace Ledgelings.Core.Tests;

public class VoiceArchiveTests
{
    private static VoiceArchive Scratch() => new(Path.Combine(Path.GetTempPath(), "voices-" + Guid.NewGuid()));

    private static void Remove(VoiceArchive archive)
    {
        try { Directory.Delete(archive.Directory, true); } catch (IOException) { }
    }

    [Fact]
    public void AKeptLineIsFoundAgainByItsWordsVoiceAndSpeed()
    {
        var archive = Scratch();
        try
        {
            var sound = new byte[] { 1, 2, 3, 4 };
            var clip = archive.Keep(sound, "Blocky", "Nice edge.", "hexgrad/kokoro-82m", "am_puck", 1);
            var clips = archive.Clips();
            Assert.Equal(new[] { clip }, clips);
            var found = archive.Find(VoiceArchive.Key("Nice edge.", "hexgrad/kokoro-82m", "am_puck", 1.0000001), clips);
            Assert.NotNull(found);
            Assert.Equal(sound, File.ReadAllBytes(found!));
            // Another voice, another speed, other words: another clip.
            Assert.Null(archive.Find(VoiceArchive.Key("Nice edge.", "hexgrad/kokoro-82m", "af_bella", 1), clips));
            Assert.Null(archive.Find(VoiceArchive.Key("Nice edge.", "hexgrad/kokoro-82m", "am_puck", 1.5), clips));
            Assert.Null(archive.Find(VoiceArchive.Key("Nice ledge.", "hexgrad/kokoro-82m", "am_puck", 1), clips));
        }
        finally { Remove(archive); }
    }

    [Fact]
    public void FilesAreFiledByDayTimeAndSpeaker()
    {
        var archive = Scratch();
        try
        {
            var time = DateTimeOffset.FromUnixTimeSeconds(1_790_375_730);       // 2026-09-25 22:35:30 UTC
            var clip = archive.Keep(new byte[] { 0 }, "Unit 7/ö", "Beep.", "m", "v", 1, at: time, zone: TimeZoneInfo.Utc);
            Assert.StartsWith("2026-09-25/223530-Unit_7_ö-", clip.File);
            Assert.EndsWith(".wav", clip.File);
        }
        finally { Remove(archive); }
    }

    [Fact]
    public void AClipWhoseFileWasDeletedIsNotFound()
    {
        var archive = Scratch();
        try
        {
            var clip = archive.Keep(new byte[] { 0 }, "Pip", "Hi!", "m", "v", 1);
            File.Delete(Path.Combine(archive.Directory, clip.File));
            Assert.Null(archive.Find(clip.Key, archive.Clips()));
        }
        finally { Remove(archive); }
    }
}
