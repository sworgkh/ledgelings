namespace Ledgelings.Core.Tests;

/// <summary>Emoji are not read out; symbols that are not emoji are, exactly as on the Mac
/// (Unicode's emoji properties, which .NET lacks, as a table).</summary>
public class SpeakableTests
{
    [Fact]
    public void EmojiOfEveryShapeAreLeftOut()
    {
        Assert.Equal("Love.", Voices.Speakable("Love. ❤️"));                    // with its variation selector
        Assert.Equal("Tea in", Voices.Speakable("Tea in 🇬🇧"));                 // a flag: two regional indicators
        Assert.Equal("Family", Voices.Speakable("Family 👨‍👩‍👧"));                 // joined with ZWJ
        Assert.Equal("Fine", Voices.Speakable("Fine 👍🏽"));                     // with a skin tone
        Assert.Equal("Melting", Voices.Speakable("Melting 🫠 ⭐ ⏏"));
    }

    [Fact]
    public void SymbolsThatAreNotEmojiAreKept()
    {
        Assert.Equal("★ ♪ ✓ ☐ ™ ↔", Voices.Speakable("★ ♪ ✓ ☐ ™ ↔"));
        Assert.Equal("© ® 2026, digits 0-9 stay", Voices.Speakable("© ® 2026, digits 0-9 stay"));
    }
}
