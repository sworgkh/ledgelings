namespace Ledgelings.Tests;

/// <summary>The chat history as the app uses it: what each character said lately survives a
/// relaunch, and the voice's charges find their conversation. (The window-free half of the Mac's
/// <c>whatTheySayIsRememberedEvenAfterARelaunch</c>; the colony half needs a live colony.)</summary>
public class ChatHistoryTests
{
    [Fact]
    public void WhatTheySayIsRememberedEvenAfterARelaunch()
    {
        var dir = Path.Combine(Path.GetTempPath(), "ledgelings-history-" + Guid.NewGuid());
        try
        {
            var history = new ChatHistory(dir);
            history.Remember(12);
            history.Record(new ChatLog.Exchange { Time = DateTimeOffset.Now, Lines = new() { new("Blocky", "Hi."), new("Pip", "Ho.") } });
            Assert.Equal(new[] { "Hi." }, history.Memory.Recent("Blocky"));
            var relaunched = new ChatHistory(dir);
            relaunched.Remember(12);
            Assert.True(relaunched.Memory.Recent("Pip").SequenceEqual(new[] { "Ho." }), "read back from the log on disk");
            relaunched.Remember(0);
            Assert.True(relaunched.Memory.Recent("Blocky").Count == 0, "off forgets");
        }
        finally { try { Directory.Delete(dir, true); } catch (IOException) { } }
    }

    [Fact]
    public void AVoiceChargeLandsBesideItsConversation()
    {
        var dir = Path.Combine(Path.GetTempPath(), "ledgelings-history-" + Guid.NewGuid());
        try
        {
            var history = new ChatHistory(dir);
            var now = DateTimeOffset.FromUnixTimeSeconds(DateTimeOffset.Now.ToUnixTimeSeconds());
            history.Record(new ChatLog.Exchange { Time = now, Lines = new() { new("Blocky", "*sighs* Hi.") } });
            history.RecordVoice(new ChatLog.VoiceCharge(now, "Blocky", "Hi.", "m", 0.002));
            var day = ChatLog.Day(now);
            var totals = history.VoiceTotals(day, history.Exchanges(day));
            Assert.True(totals[0].Lines == 1 && totals[0].Cost == 0.002);
        }
        finally { try { Directory.Delete(dir, true); } catch (IOException) { } }
    }

    [Fact]
    public void BondsAreSavedBesideTheSpendFileAndForgotten()
    {
        var dir = Path.Combine(Path.GetTempPath(), "ledgelings-bonds-" + Guid.NewGuid());
        try
        {
            var book = new BondBook(dir);
            book.Change(b => b.LiveTogether(600, new[] { "Blocky", "Pip" }));
            Assert.Equal(600, new BondBook(dir).Bond("Pip", "Blocky")!.Together);
            book.Forget(Bonds.Key("Pip", "Blocky"));
            Assert.Empty(new BondBook(dir).Book.Bonds);
        }
        finally { try { Directory.Delete(dir, true); } catch (IOException) { } }
    }
}
