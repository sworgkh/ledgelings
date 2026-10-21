namespace Ledgelings.Core.Tests;

/// <summary>Deeds (SPEC §6.5.2.2): the tag taken off a line, read leniently, checked against what was
/// offered and against the owner's limits, and the built-in lines. The Mac's DeedsTests.</summary>
public class DeedsTests
{
    private static readonly string Root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../.."));
    private static Deeds.Deed Invite(Plays.Kind kind) => Deeds.Deed.Invite(Deeds.Offer.Game(kind));

    [Fact]
    public void TheTagComesOffTheLineWhereverItIs()
    {
        var own = Deeds.Split("Soccer? Bottom edge, now.\nDO: invite soccer");
        Assert.True(own.Text == "Soccer? Bottom edge, now." && own.Deed == Invite(Plays.Kind.Soccer));
        var inline = Deeds.Split("Fine. Soccer. DO: accept");
        Assert.True(inline.Text == "Fine. Soccer." && inline.Deed == Deeds.Deed.Accept);
        var bracketed = Deeds.Split("Tea? [DO: invite tea]");
        Assert.True(bracketed.Text == "Tea?" && bracketed.Deed == Deeds.Deed.Invite(Deeds.Offer.Tea));
        var starred = Deeds.Split("**DO:** decline\nNo.");
        Assert.Equal(Deeds.Deed.Decline, starred.Deed);
        var noted = Deeds.Split("You owe me a sunflower.\nNOTE: Boo owes Blocky a sunflower\nDO: none");
        Assert.True(noted.Text == "You owe me a sunflower." && noted.Note == "Boo owes Blocky a sunflower" && noted.Deed is null && noted.Unknown is null);
        var plain = Deeds.Split("Just a line, nothing to do.");
        Assert.Equal(new Deeds.Tagged("Just a line, nothing to do."), plain);
        // An ordinary word that happens to end in "do" is not a tag.
        Assert.Null(Deeds.Split("Who do: you think you are?").Deed);
    }

    [Fact]
    public void AThinkingModelsTagIsReadAfterItsThinking()
    {
        var t = Deeds.Split("<think>maybe DO: flower?</think>Here, a daisy. DO: flower");
        Assert.True(t.Deed == Deeds.Deed.Flower && t.Text.EndsWith("Here, a daisy.", StringComparison.Ordinal));
    }

    [Fact]
    public void TheDeedIsReadLeniently()
    {
        Assert.Equal((true, Invite(Plays.Kind.Tag)), Deeds.Parse("play tag"));
        Assert.Equal((true, Invite(Plays.Kind.Baseball)), Deeds.Parse("invite to a game of baseball"));
        Assert.Equal((true, Invite(Plays.Kind.Soccer)), Deeds.Parse("Soccer"));
        Assert.Equal((true, Invite(Plays.Kind.Soccer)), Deeds.Parse("футбол"));
        Assert.True(Deeds.Parse("yes") == (true, Deeds.Deed.Accept) && Deeds.Parse("нет") == (true, Deeds.Deed.Decline));
        Assert.Equal((true, Deeds.Deed.Visit("Unit 7")), Deeds.Parse("visit Unit 7"));
        Assert.True(Deeds.Parse("go to sleep") == (true, Deeds.Deed.Sleep) && !Deeds.Parse("go").Known, "go needs somewhere");
        Assert.True(Deeds.Parse("sleep") == (true, Deeds.Deed.Sleep) && Deeds.Parse("nap") == (true, Deeds.Deed.Sleep));
        Assert.True(Deeds.Parse("none") == (true, null) && Deeds.Parse("") == (true, null));
        Assert.False(Deeds.Parse("dance").Known, "not a deed");
        Assert.False(Deeds.Parse("invite rope").Known, "the rope is played alone");
        var unknown = Deeds.Split("Let's dance! DO: dance");
        Assert.True(unknown.Deed is null && unknown.Unknown == "dance" && unknown.Text == "Let's dance!");
    }

    [Fact]
    public void OnlyWhatWasOfferedIsDone()
    {
        var o = new Deeds.Options { Games = { Plays.Kind.Soccer }, Flower = true, Visit = { "Boo" } };
        Assert.Null(Deeds.Check(Invite(Plays.Kind.Soccer), o));
        Assert.Equal(Deeds.Refusal.NotOffered, Deeds.Check(Invite(Plays.Kind.Basketball), o));
        Assert.Equal(Deeds.Refusal.NotOffered, Deeds.Check(Deeds.Deed.Invite(Deeds.Offer.Tea), o));
        Assert.True(Deeds.Check(Deeds.Deed.Visit("boo"), o) is null && Deeds.Check(Deeds.Deed.Visit("Zed"), o) == Deeds.Refusal.NotOffered);
        Assert.Equal(Deeds.Refusal.NothingToAnswer, Deeds.Check(Deeds.Deed.Accept, o));
        o.Answering = new Deeds.Invitation("Zed", "Pip", Deeds.Offer.Tea, 0, false);
        Assert.Null(Deeds.Check(Deeds.Deed.Decline, o));
        Assert.Equal(new[] { "invite soccer", "flower", "visit Boo" }, o.Tags);
    }

    [Fact]
    public void ThePromptOffersOnlyWhatIsPossible()
    {
        Languages.With(Language.English, () =>
        {
            var o = new Deeds.Options();
            Assert.Empty(Deeds.Prompt(o));
            o.Games = new() { Plays.Kind.Tag, Plays.Kind.Soccer };
            o.Tea = true;
            var menu = Deeds.Prompt(o);
            Assert.Contains("invite tag | invite soccer | invite tea | none", menu);
            o.Answering = new Deeds.Invitation("Boo", "Blocky", Deeds.Offer.Game(Plays.Kind.Soccer), 0, true);
            var answer = Deeds.Prompt(o, notes: true, listener: "Boo");
            Assert.True(answer.StartsWith("Boo has invited you to a game of soccer.", StringComparison.Ordinal) && answer.Contains("DO: accept or DO: decline"));
            Assert.True(answer.Contains("NOTE:") && answer.Contains("about Boo"));
            var russian = Languages.With(Language.Russian, () => Deeds.Prompt(o));
            Assert.True(russian.Contains("DO: accept") && russian.Contains("зовёт тебя"), "tags stay in Latin letters");
        });
    }

    [Fact]
    public void TheLimitsHoldAndTheLoopGuardStaysWhenTheyAreOff()
    {
        var ledger = new Deeds.Ledger();
        var limits = new Deeds.Limits(240, 2, 1200);
        Assert.Null(ledger.RefusalFor("flower", "A", "B", 0, limits));
        ledger.Record("flower", "A", "B", 0);
        Assert.Equal(Deeds.Refusal.LoopGuard, ledger.RefusalFor("flower", "B", "A", 10, limits));
        Assert.Equal(Deeds.Refusal.TooSoon, ledger.RefusalFor("tea", "C", "D", 100, limits));
        Assert.Equal(Deeds.Refusal.PairTooSoon, ledger.RefusalFor("flower", "A", "B", 300, limits));
        Assert.Null(ledger.RefusalFor("tea", "A", "B", 300, limits));
        ledger.Record("tea", "C", "D", 300);
        Assert.Equal(Deeds.Refusal.TooMany, ledger.RefusalFor("letter", "E", "F", 3000, limits));
        Assert.Null(ledger.RefusalFor("letter", "E", "F", 3700, limits));          // an hour later
        Assert.Null(ledger.RefusalFor("accept", "C", "D", 301, limits));           // an answer is never held back
        var off = new Deeds.Limits(0, 0, 0);
        Assert.Equal(Deeds.Refusal.LoopGuard, ledger.RefusalFor("tea", "C", "D", 310, off));
        Assert.Null(ledger.RefusalFor("tea", "C", "D", 300 + Deeds.LoopGuard, off));
    }

    [Fact]
    public void BuiltInLinesInviteAndAnswerInEachVoice()
    {
        Languages.With(Language.English, () =>
        {
            Assert.Equal("Blocky. Proposal: Soccer. My odds of winning: 61%. Accept?", Deeds.InviteLine("Unit 7", "Blocky", Deeds.Offer.Game(Plays.Kind.Soccer)));
            Assert.Equal("Fine. Soccer. But on a respectable edge, Unit 7.", Deeds.AnswerLine("Blocky", "Unit 7", Deeds.Offer.Game(Plays.Kind.Soccer), yes: true));
            Assert.Equal("Pip! Tea together? You and me, right now.", Deeds.InviteLine("Someone New", "Pip", Deeds.Offer.Tea));
        });
        var russian = Languages.With(Language.Russian, () => Deeds.AnswerLine("Zed", "Pip", Deeds.Offer.Game(Plays.Kind.Tag), yes: false));
        Assert.StartsWith("...нет...", russian);
        // Every built-in character has its lines in both languages, with the one spoken to in each.
        Assert.True(Deeds.EnglishVoices.Keys.ToHashSet().SetEquals(Letters.EnglishVoices.Keys));
        var russianVoices = Deeds.VoicesIn(Language.Russian);
        Assert.True(russianVoices.Keys.ToHashSet().SetEquals(Deeds.EnglishVoices.Keys));
        foreach (var v in Deeds.EnglishVoices.Values.Concat(russianVoices.Values))
            Assert.True(v.Invite.Contains("{game}") && v.Invite.Contains("{reader}") && v.Yes.Contains("{reader}") && v.No.Contains("{reader}"), v.Invite);
    }

    [Fact]
    public void BuiltInAnswersFollowTheChanceAndTheFriendship()
    {
        var rng = new Random(7);
        var strangers = Enumerable.Range(0, 2000).Count(_ => Deeds.BuiltInYes(0, 60, rng));
        var friends = Enumerable.Range(0, 2000).Count(_ => Deeds.BuiltInYes(1, 60, rng));
        Assert.True(strangers is >= 800 and <= 1000 && friends is >= 1400 and <= 1600, $"{strangers} {friends}");
        Assert.DoesNotContain(Enumerable.Range(0, 200), _ => Deeds.BuiltInYes(1, 0, rng));
        var o = new Deeds.Options { Games = { Plays.Kind.Soccer, Plays.Kind.Tag } };
        Assert.Equal(Deeds.Offer.Game(Plays.Kind.Tag), Deeds.BuiltInOffer(o, rng, rematch: Plays.Kind.Tag));      // a rematch first
        Assert.Null(Deeds.BuiltInOffer(new Deeds.Options(), rng));
    }

    // Windows only: the English is the Mac's, word for word.

    [Fact]
    public void TheEnglishIsTheMacsWordForWord()
    {
        var lines = File.ReadAllText(Path.Combine(Root, "Sources/LedgelingsCore/Deeds+Lines.swift"));
        foreach (var v in Deeds.EnglishVoices.Values.Append(Deeds.EnglishAnyone))
            foreach (var line in new[] { v.Invite, v.Yes, v.No }) Assert.Contains("\"" + line + "\"", lines);
        var deeds = File.ReadAllText(Path.Combine(Root, "Sources/LedgelingsCore/Deeds.swift")).Replace("\r", "");
        Assert.Contains("\"" + Deeds.EnglishAnswer + "\"", deeds);
        foreach (var (name, text) in new[] { ("englishMenu", Deeds.EnglishMenu), ("englishNote", Deeds.EnglishNote) })
            Assert.Equal(text, SwiftLiteral(deeds, name));
    }

    /// <summary>A Swift multi-line literal, its indentation and line continuations taken out.</summary>
    internal static string SwiftLiteral(string swift, string name)
    {
        var literal = System.Text.RegularExpressions.Regex.Match(swift.Replace("\r", ""), name + " = \"\"\"\n(.*?)\n    \"\"\"",
            System.Text.RegularExpressions.RegexOptions.Singleline).Groups[1].Value;
        return string.Join("\n", literal.Split('\n').Select(l => l.StartsWith("    ") ? l[4..] : l)).Replace("\\\n", "");
    }
}
