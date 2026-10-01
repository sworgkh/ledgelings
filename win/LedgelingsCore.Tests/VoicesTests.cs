namespace Ledgelings.Core.Tests;

/// <summary>Voices for the characters. Only the words-as-said part is ported so far
/// (the chat log needs it); the rest arrives with the voice.</summary>
public partial class VoicesTests
{
    [Fact]
    public void StageDirectionsEmojiAndMarkdownAreNotReadOut()
    {
        Assert.Equal("Fine. Take the ceiling.", Voices.Speakable("*sighs* Fine. 🌸 Take the **ceiling**."));
        Assert.Equal("Hello — it's 5:00 & 1!", Voices.Speakable("Hello — it's 5:00 & #1!"));
        Assert.Equal("", Voices.Speakable("🙂👍"));
    }
}
