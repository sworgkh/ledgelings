using static Ledgelings.Core.Casting;

namespace Ledgelings.Core.Tests;

public class CastingTests
{
    private const string Blocky = "a small square creature";

    private static Dictionary<string, HashSet<Tag>> TagsFor(IEnumerable<string> pool) => pool.ToDictionary(v => v, v => TagsOfVoice(v));

    [Fact]
    public void TheShippedDescriptionsSayHowTheyShouldSound()
    {
        var mortimer = TraitsOf("Old and philosophical. Speaks slowly, quotes wisdom he made up, sighs a lot.", Blocky);
        Assert.True(mortimer.Want(Tag.Old) >= 2 && mortimer.Want(Tag.Male) > 0);
        Assert.True(mortimer.Pitch < 1 && mortimer.Speed < 1);

        var dot = TraitsOf("Tiny, fast and sarcastic. Brags about speed. Calls everyone else a boulder.", Blocky);
        Assert.True(dot.Pitch > 1 && dot.Speed > 1);

        var pip = TraitsOf("Cheerful and easily impressed. Loves the ceiling. Laughs at everything, including insults.", Blocky);
        Assert.True(pip.Want(Tag.Bright) >= 2 && pip.Pitch > 1);

        var unit7 = TraitsOf("Literal and precise. Reports its own status in numbers.", "a boxy little robot with an antenna");
        Assert.True(unit7.Want(Tag.Robot) >= 3);

        var wisp = TraitsOf("Wistful and poetic. Remembers monitors that are gone.", "a little round ghost with a wavy hem, hovering");
        Assert.True(wisp.Want(Tag.Whisper) >= 2);
    }

    [Fact]
    public void ShortWordsMustMatchWholeSoTheIsNotHe()
    {
        var t = TraitsOf("Thinks the edge is theirs. Other creatures bother them.", "");
        Assert.False(t.Wants.ContainsKey(Tag.Male) || t.Wants.ContainsKey(Tag.Female));
    }

    [Fact]
    public void PitchAndSpeedStayInTheirRange()
    {
        var t = TraitsOf("tiny tiny little small wee fast quick hyper cheerful giggly anxious nervous", "");
        Assert.InRange(t.Pitch, PitchMin, PitchMax);
        Assert.InRange(t.Speed, SpeedMin, SpeedMax);
        Assert.Equal(Traits.Neutral, TraitsOf("", ""));
    }

    [Fact]
    public void VoicesAreTaggedFromWhatTheirNamesSay()
    {
        Assert.Equal(new HashSet<Tag> { Tag.Old, Tag.Male, Tag.Deep }, TagsOfVoice("com.apple.eloquence.en-US.Grandpa", "Grandpa"));
        Assert.True(TagsOfVoice("af_nicole").IsSupersetOf(new[] { Tag.Female, Tag.Whisper }));
        Assert.Equal(new HashSet<Tag> { Tag.Male }, TagsOfVoice("bm_daniel"));
        Assert.True(TagsOfVoice("English_ManWithDeepVoice").IsSupersetOf(new[] { Tag.Male, Tag.Deep }));
        Assert.True(TagsOfVoice("English_Whispering_girl").IsSupersetOf(new[] { Tag.Female, Tag.Whisper, Tag.Young }));
        Assert.True(TagsOfVoice("English_Wiselady").IsSupersetOf(new[] { Tag.Female, Tag.Old }));
        Assert.Equal(new HashSet<Tag> { Tag.Male }, TagsOfVoice("leo"));
    }

    [Fact]
    public void EachCharacterGetsTheVoiceThatFitsIt()
    {
        var pool = new[] { "Grandpa", "Zarvox", "Whisper", "Junior", "Kathy", "Ralph" };
        var traits = new Dictionary<string, Traits>
        {
            ["Mortimer"] = TraitsOf("Old and philosophical. Speaks slowly, quotes wisdom he made up.", Blocky),
            ["Unit 7"] = TraitsOf("Literal and precise.", "a boxy little robot"),
            ["Wisp"] = TraitsOf("Wistful and poetic.", "a little round ghost"),
            ["Pip"] = TraitsOf("Cheerful. Laughs at everything.", Blocky),
            ["Croak"] = TraitsOf("Grumpy. Finds the screen edge too dry.", "a fat green frog"),
        };
        var cast = Assign(traits.Keys, traits, pool, TagsFor(pool));
        Assert.Equal("Grandpa", cast["Mortimer"]);
        Assert.Equal("Zarvox", cast["Unit 7"]);
        Assert.Equal("Whisper", cast["Wisp"]);
        Assert.Equal("Junior", cast["Pip"]);
        Assert.Equal("Ralph", cast["Croak"]);
        Assert.Equal(5, cast.Values.Distinct().Count());       // nobody shares while voices last
    }

    [Fact]
    public void NobodyIsGivenARobotOrAWhisperUnasked()
    {
        var pool = new[] { "Zarvox", "Whisper", "Kathy" };
        var plain = new Dictionary<string, Traits> { ["Ruth"] = TraitsOf("Bossy, organised, keeps count of everything.", Blocky) };
        Assert.Equal("Kathy", Assign(new[] { "Ruth" }, plain, pool, TagsFor(pool))["Ruth"]);
    }

    [Fact]
    public void HandPickedVoicesStayAndAreNotHandedOut()
    {
        var pool = new[] { "Grandpa", "Kathy" };
        var traits = new Dictionary<string, Traits> { ["Mortimer"] = TraitsOf("Old and wise.", ""), ["Pip"] = Traits.Neutral };
        var cast = Assign(new[] { "Mortimer", "Pip" }, traits, pool, TagsFor(pool), new Dictionary<string, string> { ["Pip"] = "Grandpa" });
        Assert.True(cast["Pip"] == "Grandpa" && cast["Mortimer"] == "Kathy");
    }

    [Fact]
    public void TheSameCastEveryTime()
    {
        var pool = new[] { "a", "b", "c", "d" };
        var traits = new Dictionary<string, Traits> { ["X"] = Traits.Neutral, ["Y"] = Traits.Neutral, ["Z"] = Traits.Neutral };
        var none = new Dictionary<string, HashSet<Tag>>();
        Assert.Equal(Assign(new[] { "X", "Y", "Z" }, traits, pool, none), Assign(new[] { "Z", "X", "Y" }, traits, pool, none));
    }

    [Fact]
    public void TheModelIsToldWhoTheCharacterIsAndWhatToChooseFrom()
    {
        var prompt = ModelPrompt("Mortimer", "Old and philosophical.", "a small square creature",
                                 new[] { ("Grandpa", "old, male"), ("Kathy", "") }, cartoon: true);
        Assert.Contains("Mortimer, a small square creature", prompt);
        Assert.Contains("- Grandpa: old, male\n- Kathy\n", prompt);      // a voice with nothing known is listed bare
        Assert.Contains("cartoon", prompt);
    }

    [Fact]
    public void TheModelsPickIsReadEvenWrappedInChatter()
    {
        var pick = ParsePick("Sure! ```json\n{\"voice\": \"Grandpa\", \"pitch\": 0.9, \"speed\": \"0.8\", \"why\": \"old and slow\"}\n```");
        Assert.Equal(new Pick("Grandpa", 0.9, 0.8, "old and slow"), pick);
        Assert.Equal(2, ParsePick("{\"voice\": \"x\", \"pitch\": 9}")?.Pitch);       // clamped
        Assert.Null(ParsePick("no json here"));
        // The reasoning before </think> is not the answer.
        Assert.Equal("Grandpa", ParsePick("<think>maybe {\"voice\": \"Kathy\"}? no.</think>{\"voice\": \"Grandpa\"}")?.Voice);
        Assert.Null(ParsePick("{\"pitch\": 1}"));       // no voice, no pick
    }

    [Fact]
    public void AnAloofCatOrAPoetIsNotGivenTheWhisper()
    {
        var pool = new[] { "Whisper", "Kathy", "Reed" };
        var traits = new Dictionary<string, Traits>
        {
            ["Whiskers"] = TraitsOf("Aloof. Pretends not to care, then asks what you are doing.", "a small square cat"),
            ["Poet"] = TraitsOf("Wistful and poetic.", "a small square creature"),
        };
        var cast = Assign(new[] { "Whiskers", "Poet" }, traits, pool, TagsFor(pool));
        Assert.True(cast["Whiskers"] != "Whisper" && cast["Poet"] != "Whisper");
    }
}
