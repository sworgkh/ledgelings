namespace Ledgelings.Core.Tests;

/// <summary>Revenge (SPEC §4.7.3): when it is due, what counts as shaking the cursor off, and the words in
/// every mood and language. The Mac's RevengeTests.</summary>
public class RevengeTests
{
    [Fact]
    public void TheTenthHuntInsideTheWindowMakesItDue()
    {
        var fuse = new Revenge.Fuse { After = 10, Window = 120, Cooldown = 600 };
        for (int k = 0; k < 9; k++) Assert.False(fuse.Hunted(0, k * 10), $"hunt {k + 1}");
        Assert.True(fuse.Hunted(0, 95));      // the tenth inside two minutes
        Assert.Equal(10, fuse.Recent(0, 95));
        Assert.Equal(0, fuse.Recent(1, 95));  // counted per creature
    }

    [Fact]
    public void HuntsSpreadOutNeverAddUp()
    {
        var fuse = new Revenge.Fuse { After = 3, Window = 60, Cooldown = 0 };
        foreach (var t in new[] { 0.0, 50, 115 }) Assert.False(fuse.Hunted(0, t), $"at {t}");
        Assert.Equal(1, fuse.Recent(0, 115));      // the first two fell out of the window
        fuse.Hunted(0, 116);
        Assert.True(fuse.Hunted(0, 117));
    }

    [Fact]
    public void AfterAGrabNobodyGrabsAgainUntilTheCooldownIsOver()
    {
        var fuse = new Revenge.Fuse { After = 2, Window = 60, Cooldown = 600 };
        fuse.Hunted(0, 0);
        Assert.True(fuse.Hunted(0, 1));
        fuse.Grabbed(1);
        Assert.Equal(0, fuse.Recent(0, 1));      // the count starts over
        fuse.Hunted(1, 100);
        Assert.False(fuse.Hunted(1, 101));       // another creature waits out the cooldown too
        fuse.Hunted(1, 650);
        Assert.True(fuse.Hunted(1, 651));
    }

    [Fact]
    public void QuickStrokesBackAndForthShakeItOff()
    {
        var shake = new Revenge.Shake(6);
        double t = 0;
        bool shaken = false;
        int strokes = 0;
        while (!shaken && strokes < 20)
        {
            var way = strokes % 2 == 0 ? 1 : -1;
            for (int f = 0; f < 3; f++) { t += 1.0 / 60; shaken = shake.Moved(way * 20, 0, t) || shaken; }
            strokes++;
        }
        Assert.True(shaken);
        Assert.Equal(7, strokes);      // six turns back after full strokes
    }

    [Fact]
    public void JitterAndSlowDriftDoNotCount()
    {
        var jitter = new Revenge.Shake(3);
        for (int k = 0; k < 200; k++) Assert.False(jitter.Moved(k % 2 == 0 ? 5 : -5, k % 3 == 0 ? 4 : -4, k / 60.0));
        var drift = new Revenge.Shake(3);
        // A long stroke each way, two seconds apart: turns too slow to add up.
        for (int k = 0; k < 12; k++) Assert.False(drift.Moved(k % 2 == 0 ? 200 : -200, 0, k * 2));
        Assert.True(drift.Vigour(24) < 1);
    }

    [Fact]
    public void ShakingUpAndDownCountsToo()
    {
        var shake = new Revenge.Shake(2);
        Assert.False(shake.Moved(0, 40, 0));
        Assert.False(shake.Moved(0, -40, 0.1));
        Assert.Equal(0.5, shake.Vigour(0.1));
        Assert.True(shake.Moved(0, 40, 0.2));
        Assert.Equal(0, shake.Vigour(5));      // it fades when the shaking stops
    }

    [Fact]
    public void EveryCharacterHasItsLinesInEveryMoodAndLanguage()
    {
        var shipped = Complaints.EnglishLines.Keys.ToHashSet();
        var allowed = new HashSet<string> { "today", "all" };
        static HashSet<string> Used(string line) =>
            System.Text.RegularExpressions.Regex.Matches(line, @"\{(\w+)\}").Select(m => m.Groups[1].Value).ToHashSet();
        foreach (var mood in CursorMoods.All)
            foreach (var l in Languages.All)
            {
                var sets = Revenge.LinesIn(mood, l);
                var last = Revenge.LastWordsIn(mood, l);
                Assert.True(shipped.SetEquals(sets.Keys), $"{mood} {l.Code()}");
                Assert.True(shipped.SetEquals(last.Keys), $"{mood} {l.Code()} last words");
                Assert.NotEmpty(Revenge.AnyoneIn(mood, l));
                Assert.NotEmpty(Revenge.AnyoneLastWordsIn(mood, l));
                foreach (var line in sets.Values.SelectMany(x => x).Concat(Revenge.AnyoneIn(mood, l)))
                    Assert.True(Used(line).IsSubsetOf(allowed), $"{mood} {l.Code()}: {line}");
                foreach (var line in last.Values.SelectMany(x => x).Concat(Revenge.AnyoneLastWordsIn(mood, l)))
                    Assert.Empty(Used(line));
                var prompt = Revenge.PromptIn(mood, l);
                Assert.Contains("{situation}", prompt);
                Assert.Contains("{times}", prompt);
                if (l == Language.English) continue;
                Assert.NotEqual(Revenge.PromptIn(mood, Language.English), prompt);      // its own text, from ru.json
                foreach (var name in shipped)
                {
                    Assert.NotEqual(Revenge.LinesIn(mood, Language.English)[name], sets[name]);
                    Assert.Equal(Revenge.LinesIn(mood, Language.English)[name].Length, sets[name].Length);
                    Assert.NotEqual(Revenge.LastWordsIn(mood, Language.English)[name], last[name]);
                }
            }
        Assert.NotEqual(Revenge.EnglishBadLines["Blocky"], Revenge.EnglishGoodLines["Blocky"]);      // each mood its own words
        Assert.NotEqual(Revenge.EnglishGoodLines["Blocky"], Revenge.EnglishNeutralLines["Blocky"]);
    }

    [Fact]
    public void TheEnglishPromptIsTheMacsWordForWord()
    {
        Assert.StartsWith("{situation}\nThe person whose screen you live on has chased you with the mouse cursor and picked you up far too often: {times} times",
                          Revenge.EnglishBadPrompt);
        Assert.EndsWith("in your own voice. At most 20 words. Output only the line: no quotes, no name.", Revenge.EnglishGoodPrompt);
    }

    [Fact]
    public void ALineHasItsNumbersFilledIn()
    {
        var rng = new Random(7);
        foreach (var mood in CursorMoods.All)
            foreach (var name in new[] { "Blocky", "Somebody New" })
            {
                for (int k = 0; k < 10; k++) Assert.DoesNotContain("{", Revenge.Line(name, 17, 403, mood, rng));
                Assert.NotEmpty(Revenge.LastWord(name, mood, rng));
            }
    }

    [Fact]
    public void RevengeIsItsOwnLineInTheCosts()
    {
        var usage = new Spend.Usage(120, 20, 0.0001);
        var records = new[] { new Spend.Record(DateTimeOffset.Now, "OpenRouter", "m", usage, Spend.Purpose.Revenge) };
        Assert.Equal(new[] { "Revenge" }, Spend.Summarise(records, DateTimeOffset.Now).ByPurpose.Select(p => p.Purpose));
        Assert.Equal("revenge", Spend.Purpose.Revenge.Raw());      // the Mac's raw value
    }

    [Fact]
    public void TheStrokeAndTheWindowAreTunable()
    {
        var gentle = new Revenge.Shake(2, stroke: 10, window: 2);
        gentle.Moved(12, 0, 0);
        gentle.Moved(-12, 0, 0.8);
        Assert.True(gentle.Moved(12, 0, 1.6));      // short strokes count when the stroke is short
        var strict = new Revenge.Shake(2, stroke: 40, window: 1);
        strict.Moved(50, 0, 0);
        strict.Moved(-50, 0, 0.8);
        Assert.False(strict.Moved(50, 0, 1.9));     // too slow for a one-second window
    }

    [Fact]
    public void AGentleWiggleShakesItOffWithTheDefaults()
    {
        var shake = new Revenge.Shake();
        var off = false;
        for (int k = 0; k < 8 && !off; k++) off = shake.Moved(k % 2 == 0 ? 25 : -25, 0, k * 0.1);
        Assert.True(off);
    }

    [Fact]
    public void NoLimitMeansUntilShakenOffExceptWhenHeldStill()
    {
        Assert.Equal(double.PositiveInfinity, Revenge.LongestHold(0, pinned: false));
        Assert.Equal(Revenge.PinnedHoldCap, Revenge.LongestHold(0, pinned: true));
        Assert.Equal(10, Revenge.LongestHold(20, pinned: true));
        Assert.Equal(5, Revenge.LongestHold(5, pinned: false));
    }

    [Fact]
    public void AClingerTumblesDownWhenShakenOff()
    {
        var world = new EdgeWorld(new[] { new Rect(0, 0, 800, 600) }, 10);
        var c = new Creature(world);
        var rng = new Random(3);
        c.ToggleNap(rng);
        Assert.True(c.Cling() && c.IsHeld && !c.IsSleeping);      // awake, whatever it was doing
        Assert.False(c.Cling());                                   // already holding on
        c.Drag(new Pt(400, 300));
        c.Drop(tumbling: true);
        var jump = Assert.IsType<Creature.Mode.Jumping>(c.CurrentMode).Jump;
        Assert.Equal(4 * Math.PI, Math.Abs(jump.Spin), 6);
        Assert.True(jump.Duration >= 0.6);
        double turned = 0, last = c.Rotation;
        for (int k = 0; k < 60; k++) { c.Update(1.0 / 60, null, false, rng); turned += Math.Abs(c.Rotation - last); last = c.Rotation; }
        Assert.True(turned > 2 * Math.PI);      // head over heels on the way down
        Assert.False(c.IsJumping);
    }
}
