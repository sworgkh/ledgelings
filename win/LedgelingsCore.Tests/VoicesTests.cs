namespace Ledgelings.Core.Tests;

public class VoicesTests
{
    private readonly string[] pool = { "a", "b", "c", "d", "e" };

    [Fact]
    public void EveryCharacterGetsItsOwnVoiceWhileThePoolLasts()
    {
        var names = new[] { "Blocky", "Pip", "Mortimer", "Ribbit" };
        var voices = Voices.Assign(names, pool);
        Assert.Equal(names.ToHashSet(), voices.Keys.ToHashSet());
        Assert.Equal(names.Length, voices.Values.Distinct().Count());
    }

    [Fact]
    public void TheSameNameKeepsItsVoiceWhateverOrderTheCastComesIn()
    {
        var one = Voices.Assign(new[] { "Blocky", "Pip", "Mortimer" }, pool);
        var two = Voices.Assign(new[] { "Mortimer", "Blocky", "Pip", "Pip" }, pool);
        Assert.Equal(one, two);
    }

    [Fact]
    public void VoicesAreSharedOnlyOnceThePoolRunsOut()
    {
        var voices = Voices.Assign(new[] { "A", "B", "C" }, new[] { "x", "y" });
        Assert.Equal(new HashSet<string> { "x", "y" }, voices.Values.ToHashSet());
        Assert.Empty(Voices.Assign(new[] { "A" }, Array.Empty<string>()));
    }

    [Fact]
    public void TheHashIsTheSameEveryLaunch()
    {
        // FNV-1a of "a", a published test vector.
        Assert.Equal(0xaf63dc4c8601ec8cUL, Voices.StableHash("a"));
        Assert.InRange(Voices.PitchNudge("Blocky"), 0.9, 1.1);
        Assert.Equal(Voices.PitchNudge("Blocky"), Voices.PitchNudge("Blocky"));
    }

    [Fact]
    public void EnglishVoicesAreKeptWhenTheNamesSayWhichTheyAre()
    {
        Assert.Equal(new[] { "af_bella", "bm_george" }, Voices.EnglishFirst(new[] { "af_bella", "jf_alpha", "bm_george", "zf_xiaobei" }));
        Assert.Equal(new[] { "flux-kit-en" }, Voices.EnglishFirst(new[] { "flux-kit-en", "flux-x-de" }));
        Assert.Equal(new[] { "en_paul_happy", "gb_jane_sad" }, Voices.EnglishFirst(new[] { "en_paul_happy", "fr_marie_sad", "gb_jane_sad" }));
        Assert.Equal(new[] { "English_Comedian" }, Voices.EnglishFirst(new[] { "English_Comedian", "Chinese_Man" }));
        // Names that say nothing about language: keep them all.
        Assert.Equal(new[] { "Puck", "Kore" }, Voices.EnglishFirst(new[] { "Puck", "Kore" }));
        var orpheus = new[] { "tara", "leah", "jess", "leo", "dan", "mia", "zac", "zoe", "pierre", "amelie", "유나", "javi" };
        Assert.Equal(new[] { "tara", "leah", "jess", "leo", "dan", "mia", "zac", "zoe" }, Voices.EnglishFirst(orpheus));
    }

    [Fact]
    public void StageDirectionsEmojiAndMarkdownAreNotReadOut()
    {
        Assert.Equal("Fine. Take the ceiling.", Voices.Speakable("*sighs* Fine. 🌸 Take the **ceiling**."));
        Assert.Equal("Hello — it's 5:00 & 1!", Voices.Speakable("Hello — it's 5:00 & #1!"));
        Assert.Equal("", Voices.Speakable("🙂👍"));
    }

    [Fact]
    public void CartoonVoicesSqueakHigherEachAtItsOwnHeight()
    {
        var heights = new[] { "Blocky", "Pip", "Mortimer", "Zed" }.Select(Voices.CartoonPitch).ToList();
        Assert.All(heights, h => Assert.InRange(h, 1.15, 1.6));
        Assert.Equal(4, heights.Distinct().Count());
        Assert.Equal(Voices.CartoonPitch("Pip"), Voices.CartoonPitch("Pip"));
    }

    [Fact]
    public void PlayfulVoicesArePickedFirstWhenThereAreEnough()
    {
        var minimax = new[] { "English_expressive_narrator", "English_AnimeCharacter", "English_Trustworth_Man", "English_PlayfulGirl" };
        Assert.Equal(new[] { "English_AnimeCharacter", "English_PlayfulGirl" }, Voices.CartoonFirst(minimax));
        Assert.Equal(new[] { "en_paul_excited", "en_paul_cheerful" }, Voices.CartoonFirst(new[] { "en_paul_neutral", "en_paul_excited", "en_paul_cheerful" }));
        // Nothing says playful: keep them all.
        Assert.Equal(new[] { "Puck", "Kore" }, Voices.CartoonFirst(new[] { "Puck", "Kore" }));
        // One is not enough to go round.
        Assert.Equal(new[] { "am_santa", "am_adam" }, Voices.CartoonFirst(new[] { "am_santa", "am_adam" }));
    }

    [Fact]
    public void AVoiceChosenByHandIsKeptAndTheOthersAvoidIt()
    {
        var pool = new[] { "a", "b", "c" };
        var auto = Voices.Assign(new[] { "Blocky", "Pip" }, pool);
        var pipsOwn = auto["Blocky"];                  // give Pip the voice Blocky had
        var voices = Voices.Assign(new[] { "Blocky", "Pip" }, pool, new Dictionary<string, string> { ["Pip"] = pipsOwn, ["Nobody"] = "c" });
        Assert.Equal(pipsOwn, voices["Pip"]);
        Assert.NotEqual(pipsOwn, voices["Blocky"]);
        Assert.False(voices.ContainsKey("Nobody"), "a setting for someone not on screen changes nothing");
        // Everything taken by hand: the rest share from the whole pool.
        Assert.Equal("x", Voices.Assign(new[] { "A", "B" }, new[] { "x" }, new Dictionary<string, string> { ["A"] = "x" })["B"]);
    }

    [Fact]
    public void ACharacterWithNothingSetIsAutomatic()
    {
        Assert.True(new CharacterVoice().IsAutomatic);
        Assert.False(new CharacterVoice { Pitch = 1.3 }.IsAutomatic);
        Assert.False(new CharacterVoice { FollowPitch = false }.IsAutomatic, "even off by hand is a choice");
    }

    [Fact]
    public void WithSpeedFollowingPitchAVoiceIsNeverAskedToDrawl()
    {
        // Exact pace: a 1.6× lift means asking for 0.625×, slow enough to smear.
        Assert.True(Math.Abs(Voices.AskedSpeed(1, 1.6, false) - 0.625) < 1e-9);
        // Following: half the slowdown, and the line comes out a little quicker.
        var asked = Voices.AskedSpeed(1, 1.44, true);
        Assert.True(Math.Abs(asked - 1 / 1.2) < 1e-9);
        Assert.True(Math.Abs(asked * 1.44 - 1.2) < 1e-9, "played 1.44× faster: 1.2× the pace");
        Assert.Equal(1.3, Voices.AskedSpeed(1.3, 1, true));     // no lift, nothing changes
    }

    [Fact]
    public void ABlendIsUsableWhenEveryVoiceInItIs()
    {
        Assert.Equal(new[] { "af_bella", "am_puck" }, Voices.BlendParts("af_bella(2)+am_puck(1)"));
        Assert.Equal(new[] { "am_santa", "bf_emma" }, Voices.BlendParts(" am_santa + bf_emma "));
        Assert.Equal(new[] { "af_bella" }, Voices.BlendParts("af_bella"));
        var voices = new[] { "af_bella", "am_puck", "bf_emma" };
        Assert.True(Voices.IsUsable("af_bella(2)+am_puck(1)", voices));
        Assert.False(Voices.IsUsable("af_bella+zz_nobody", voices), "one unknown voice spoils the blend");
        Assert.True(Voices.IsUsable("anything", Array.Empty<string>()), "no list to check against: let the server decide");
        Assert.False(Voices.IsUsable(" + ", voices));
    }
}
