namespace Ledgelings.Core.Tests;

/// <summary>Chat with the creatures, the Mac's <c>OwnerChatTests</c>: who answers Everyone and in what order, the prompt
/// each one gets, what it remembers of the owner, the cost, the keys and the controls.</summary>
public class OwnerChatTests
{
    [Fact]
    public void AChatCallLandsUnderItsOwnPurpose() => Languages.With(Language.English, () =>
    {
        var now = DateTimeOffset.Now;
        var records = new[]
        {
            new Spend.Record(now, "OpenRouter", "m", new Spend.Usage(300, 40, 0.002), Spend.Purpose.Chat),
            new Spend.Record(now, "OpenRouter", "m", new Spend.Usage(200, 0, 0.001), Spend.Purpose.Chat),      // an empty answer is a call too
            new Spend.Record(now, "OpenRouter", "m", new Spend.Usage(10, 5, 0.0001), Spend.Purpose.Talk),
        };
        var chat = Spend.Summarise(records, now).ByPurpose.Single(p => p.Purpose == "Chat with you");
        Assert.Equal(2, chat.Total.Calls);
        Assert.Equal(0.003, chat.Total.Cost, 9);
        Assert.Equal("chat", Spend.Purpose.Chat.Raw());
    });

    [Fact]
    public void ThePromptCarriesThePersonaAndTheKind() => Languages.With(Language.English, () =>
    {
        var values = OwnerChat.Values("Unit 7", "a boxy little robot", "Talks in numbers. Counts everything.", OwnerChat.Length.Medium, "",
                                      "On the edge it is day.", "How was your night?", false, Array.Empty<(string, string)>());
        var (system, user) = OwnerChat.Prompt(values);
        Assert.Contains("Unit 7", system);
        Assert.Contains("a boxy little robot", system);
        Assert.Contains("Talks in numbers. Counts everything.", system);
        Assert.Contains("at most 60 words", system);
        Assert.Contains("How was your night?", user);
        Assert.Contains("to you", user);
        Assert.DoesNotContain("{", system + user);
        foreach (var p in new[] { "speakerPersona", "speakerKind", "speaker" }) Assert.Contains("{" + p + "}", OwnerChat.EnglishSystemPrompt);
    });

    [Fact]
    public void TheRussianPromptAsksForRussian() => Languages.With(Language.Russian, () =>
    {
        var (system, user) = OwnerChat.Prompt(OwnerChat.Values("Blocky", "", "", OwnerChat.Length.Short, "", "", "привет", true, Array.Empty<(string, string)>()));
        Assert.Contains("по-русски", system);
        Assert.Contains("не больше 25 слов", system);
        Assert.Contains("всем вам", user);
        Assert.Contains("«привет»", user);
    });

    [Fact]
    public void LaterOnesHearTheEarlierAnswers() => Languages.With(Language.English, () =>
    {
        var user = OwnerChat.Prompt(OwnerChat.Values("Pip", "", "", OwnerChat.Length.Short, "", "", "Hi all", true,
                                                     new[] { ("Blocky", "Go away."), ("Zed", "Mm… sleep…") })).User;
        Assert.Contains("Blocky: \"Go away.\"", user);
        Assert.Contains("Zed: \"Mm… sleep…\"", user);
        Assert.Contains("never the same answer", user);
        Assert.Contains("to all of you", user);
    });

    [Fact]
    public void EveryoneIsAtMostNAndEachOnceAwakeFirst()
    {
        var rng = new Random(7);
        var six = new[] { "Blocky", "Pip", "Zed", "Dot", "Ruth", "Mortimer" }.Select(n => new OwnerChat.Candidate(n, n is "Zed" or "Ruth")).ToList();
        for (var n = 1; n <= 8; n++)
        {
            var who = OwnerChat.Answerers(six.Concat(six), n, rng);
            Assert.Equal(Math.Min(n, 6), who.Count);
            Assert.Equal(who.Count, who.Distinct().Count());
            if (n <= 4) { Assert.DoesNotContain("Zed", who); Assert.DoesNotContain("Ruth", who); }     // the awake answer first
        }
        Assert.Empty(OwnerChat.Answerers(six, 0, rng));
    }

    [Fact]
    public void MemoryIsKeptCappedAndForgotten()
    {
        var book = new OwnerChat.Book();
        var start = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);
        var dropped = new List<OwnerChat.Exchange>();
        for (var k = 0; k < 5; k++) dropped.AddRange(book.Remember("Blocky", new OwnerChat.Exchange { Time = start.AddMinutes(k), Said = $"m{k}", Answer = $"a{k}" }, 3));
        Assert.Equal(new[] { "m2", "m3", "m4" }, book.MemoryOf("Blocky")!.Exchanges.Select(e => e.Said));
        Assert.Equal(new[] { "m0", "m1" }, dropped.Select(e => e.Said));      // the rest come back, oldest first, for the summary
        book.Summarised("Blocky", "The owner went to the dentist.", start, 0.001);
        book.Summarised("Blocky", null, start, 0.002);
        Assert.Equal("The owner went to the dentist.", book.MemoryOf("Blocky")!.Summary);    // an empty summary keeps the old one
        Assert.Equal(0.003, book.MemoryOf("Blocky")!.SummaryCost!.Value, 9);
        var cut = book.Keep(1);
        Assert.Equal(new[] { "m2", "m3" }, cut["Blocky"].Select(e => e.Said));
        Assert.Single(book.MemoryOf("Blocky")!.Exchanges);
        book.Remember("Zed", new OwnerChat.Exchange { Time = start, Said = "hi", Answer = "zz" }, 0);
        Assert.Empty(book.MemoryOf("Zed")!.Exchanges);                         // 0 keeps nothing word for word
        book.Forget("Blocky");
        Assert.Null(book.MemoryOf("Blocky"));
        book.Remember("Pip", new OwnerChat.Exchange { Time = start, Said = "hi", Answer = "yay" }, 3);
        book.ForgetAll();
        Assert.Empty(book.Names);
    }

    [Fact]
    public void MemorySurvivesARelaunchInTheMacsFormat()
    {
        var dir = Path.Combine(Path.GetTempPath(), "owner-chat-" + Guid.NewGuid());
        try
        {
            var store = new OwnerChat.Store(dir);
            Assert.Empty(store.Load().Memories);
            var book = new OwnerChat.Book();
            book.Remember("Blocky", new OwnerChat.Exchange { Time = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000), Said = "I have a cat", Answer = "Keep it off my edge.", Everyone = true }, 10);
            book.Summarised("Blocky", "The owner has a cat.", DateTimeOffset.FromUnixTimeSeconds(1_800_000_100), null);
            store.Save(book);
            var again = new OwnerChat.Store(dir).Load();
            Assert.Equal("The owner has a cat.", again.MemoryOf("Blocky")!.Summary);
            Assert.Equal(book.MemoryOf("Blocky")!.Exchanges, again.MemoryOf("Blocky")!.Exchanges);
            // The Mac's file reads too: its keys and its ISO dates.
            File.WriteAllText(store.File, """{"memories":{"Boo":{"exchanges":[{"time":"2026-11-12T10:17:00Z","said":"Hi","answer":"Бу!","everyone":true}],"summary":"Likes rain."}}}""");
            var mac = store.Load().MemoryOf("Boo")!;
            Assert.Equal("Бу!", mac.Exchanges[0].Answer);
            Assert.True(mac.Exchanges[0].Everyone);
            Assert.Equal("Likes rain.", mac.Summary);
            File.WriteAllText(store.File, "nonsense");
            Assert.Empty(store.Load().Memories);                                 // a damaged file reads as empty
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    [Fact]
    public void TheMemoryBlockGoesIntoThePrompt() => Languages.With(Language.English, () =>
    {
        var now = DateTimeOffset.Now;
        var memory = new OwnerChat.Memory { Summary = "The owner's name is Sam." };
        memory.Exchanges.Add(new OwnerChat.Exchange { Time = now.AddDays(-1), Said = "I'm off to the dentist", Answer = "Bite them." });
        var block = OwnerChat.MemoryBlock(memory, now);
        Assert.Contains("The owner's name is Sam.", block);
        Assert.Contains("yesterday", block);
        Assert.Contains("I'm off to the dentist", block);
        Assert.Contains("I'm off to the dentist", OwnerChat.Prompt(OwnerChat.Values("Blocky", "", "", OwnerChat.Length.Short, block, "", "Back!", false, Array.Empty<(string, string)>())).System);
        Assert.Equal("", OwnerChat.MemoryBlock(null, now));
        Assert.Equal("", OwnerChat.MemoryBlock(new OwnerChat.Memory(), now));
        var summary = OwnerChat.SummaryPromptFor("Blocky", "", null, memory.Exchanges, now);
        Assert.Contains("I'm off to the dentist", summary);
        Assert.Contains("(nothing yet)", summary);
        Assert.DoesNotContain("{", summary);
    });

    [Fact]
    public void AnAnswerIsCleanedToItsLength()
    {
        Assert.Equal("Fine. Go away.", OwnerChat.Clean("<think>hmm</think>\nBlocky: \"Fine.\nGo away.\"", "Blocky", OwnerChat.Length.Short));
        Assert.Equal("", OwnerChat.Clean("<think>still going", "Blocky", OwnerChat.Length.Short));
        var longText = string.Concat(Enumerable.Repeat("Word word word. ", 80));
        Assert.True(OwnerChat.Clean(longText, "Zed", OwnerChat.Length.Short).Length <= OwnerChat.Length.Short.MaxCharacters());
        Assert.True(OwnerChat.Clean(longText, "Zed", OwnerChat.Length.Long).Length > OwnerChat.Length.Short.MaxCharacters());
        Assert.Equal("Sam has a cat.", OwnerChat.CleanSummary("\n\"Sam has a cat.\"\n"));
        Assert.Null(OwnerChat.CleanSummary("  "));
    }

    [Fact]
    public void TheShortcutIsCtrlAltC()
    {
        Assert.Equal(new Shortcut(0x43, ShortcutModifiers.Control | ShortcutModifiers.Option), Shortcut.Chat);
        var ours = new[] { Shortcut.Standard, Shortcut.ClipHistory, Shortcut.ClipSnippets, Shortcut.Dictation, Shortcut.Translate, Shortcut.TranslateClip,
                           Shortcut.ReadAloud, Shortcut.Tools, Shortcut.StopActivity };
        Assert.DoesNotContain(Shortcut.Chat, ours);                             // none of the app's own keys
    }

    [Fact]
    public void EveryControlHasAPictureAndATagNamingItsKey() => Languages.With(Language.English, () =>
    {
        foreach (var b in OwnerChat.Buttons)
        {
            Assert.Equal(11, b.Icon().Count);
            Assert.All(b.Icon(), row => { Assert.Equal(11, row.Length); Assert.True(row.All(ch => ch is '.' or '#')); });
            Assert.Contains('#', string.Concat(b.Icon()));
            Assert.Contains("(", b.Tooltip());
        }
        Assert.Equal(OwnerChat.Buttons.Count, OwnerChat.Buttons.Select(b => string.Concat(b.Icon())).Distinct().Count());   // each its own picture
        Assert.Equal("Send (Enter)", OwnerChat.Button.Send.Tooltip());
        Assert.Equal("Write to everyone (Ctrl+0)", OwnerChat.Button.Everyone.Tooltip());
        Assert.Equal("Write to Blocky (Ctrl+1)", OwnerChat.WriteTo("Blocky", 1));
        Assert.Equal(OwnerChat.SheetIcon, Tools.Tool.Chat.Icon());
        Assert.Equal(SettingsPage.ChatWithYou, Tools.Tool.Chat.Page());
        Assert.Contains("Talk & friends › Chat with you", Tools.Tool.Chat.Tooltip(8, null, false));
        Assert.Equal("Отправить (Enter)", Languages.With(Language.Russian, () => OwnerChat.Button.Send.Tooltip()));
    });

    [Fact]
    public void ThePageSitsUnderTalk()
    {
        Assert.Equal(SettingsGroup.TalkAndFriends, SettingsPage.ChatWithYou.Group());
        Assert.Equal("Chat with you", SettingsPage.ChatWithYou.EnglishTitle());
        Assert.Equal(SettingsPage.ChatWithYou, SettingsPages.Named("chatwithyou"));
        Assert.Equal("chat", WindowPlaces.Window.Chat.Key());
        Assert.True(WindowPlaces.Window.Chat.Movable());
    }
}
