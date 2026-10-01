namespace Ledgelings.Core.Tests;

/// <summary>The wind, a plane's flight and trail, the quiet spell, and the letters.</summary>
public class PaperPlanesTests
{
    private static double Hypot(double x, double y) => Math.Sqrt(x * x + y * y);

    [Fact]
    public void TheWindIsSmoothBoundedAndTheSameForTheSamePlaceAndTime()
    {
        var wind = new Wind(100);
        Assert.Equal(wind.At(new Pt(300, 200), 5), wind.At(new Pt(300, 200), 5));
        double biggest = 0;
        for (double x = 0; x < 3000; x += 97)
            for (double t = 0; t < 60; t += 1.3)
                biggest = Math.Max(biggest, wind.At(new Pt(x, x / 2), t).Length);
        Assert.True(biggest <= 100 * 1.8, "never much past its strength");
        var here = wind.At(new Pt(500, 500), 10);
        var near = wind.At(new Pt(502, 500), 10.01);
        Assert.True(Hypot(here.Dx - near.Dx, here.Dy - near.Dy) < 5, "no sudden jolts");
    }

    [Fact]
    public void APlaneAlwaysReachesItsCatcherEvenInAStrongWind()
    {
        var rng = new Random(7);
        for (int n = 0; n < 40; n++)
        {
            var start = new Pt(rng.Range(0, 2500), 20);
            var target = new Pt(rng.Range(0, 2500), rng.Range(20, 1400));
            var plane = new PaperPlane(0, 1, start, new Vec(0, 1), target) { Wind = new Wind(400) };
            var time = rng.Range(0, 100);
            while (plane.DistanceTo(target) > 40 && plane.Age < 30)
            {
                target = new Pt(target.X + 50 * 0.02, target.Y);      // the catcher keeps walking
                plane.Fly(0.02, target, time);
                time += 0.02;
            }
            Assert.True(plane.Age < 25, $"arrived in {plane.Age} s from {start} to {target}");
        }
    }

    [Fact]
    public void ItDoesNotFlyStraightTheWindBendsItsPath()
    {
        var plane = new PaperPlane(0, 1, new Pt(0, 0), new Vec(0, 1), new Pt(2000, 0));
        double furthestOffLine = 0;
        for (int k = 0; k < 200; k++)
        {
            plane.Fly(0.02, new Pt(2000, 0), k * 0.02);
            furthestOffLine = Math.Max(furthestOffLine, Math.Abs(plane.Position.Y));
        }
        Assert.True(furthestOffLine > 20);
    }

    [Fact]
    public void FiveDrawingsCoverAWholeRollAndPastAQuarterTurnItIsFlipped()
    {
        Assert.Equal((PaperPlane.View.Side, false), PaperPlane.ViewAt(0));
        Assert.Equal((PaperPlane.View.Bank, false), PaperPlane.ViewAt(0.6));
        Assert.Equal((PaperPlane.View.Top, false), PaperPlane.ViewAt(Math.PI / 2));
        Assert.Equal((PaperPlane.View.Tilt, false), PaperPlane.ViewAt(-0.6));
        Assert.Equal((PaperPlane.View.Belly, false), PaperPlane.ViewAt(-Math.PI / 2));
        // Upside down is the side view mirrored; just short of it, the bank mirrored.
        Assert.Equal((PaperPlane.View.Side, true), PaperPlane.ViewAt(Math.PI));
        Assert.Equal((PaperPlane.View.Side, true), PaperPlane.ViewAt(-Math.PI));
        Assert.Equal((PaperPlane.View.Bank, true), PaperPlane.ViewAt(Math.PI - 0.6));
        Assert.Equal((PaperPlane.View.Tilt, true), PaperPlane.ViewAt(-Math.PI + 0.6));
        Assert.Equal((PaperPlane.View.Bank, false), PaperPlane.ViewAt(2 * Math.PI + 0.6));      // a roll goes round
        foreach (var view in Enum.GetValues<PaperPlane.View>().Where(v => v != PaperPlane.View.Side))
            Assert.Equal(view.ToString().ToLowerInvariant(), PaperPlane.Animation(view));      // each drawing is the animation of its name
        Assert.Equal("fly", PaperPlane.Animation(PaperPlane.View.Side));
    }

    [Fact]
    public void ThrownLeftItStartsTheOtherWayUpAndFlyingStraightItStaysLevel()
    {
        var left = new PaperPlane(0, 1, new Pt(2000, 0), new Vec(0, 0), Pt.Zero);
        Assert.Equal((PaperPlane.View.Side, true), left.CurrentView);
        var right = new PaperPlane(0, 1, Pt.Zero, new Vec(0, 0), new Pt(5000, 0));
        for (int k = 0; k < 100; k++) right.Fly(0.02, new Pt(5000, 0), k * 0.02);
        Assert.True(Math.Abs(right.Roll) < 0.35, $"no turning, next to no bank: {right.Roll}");
        Assert.Equal((PaperPlane.View.Side, false), right.CurrentView);
    }

    [Fact]
    public void TurningItBanksAndComingRoundItRollsOverThroughTheOtherViews()
    {
        // Thrown right, the catcher behind it: it has to come round to fly left.
        var plane = new PaperPlane(0, 1, new Pt(1000, 500), new Vec(1, 0), new Pt(1600, 500));
        var target = new Pt(-3000, 500);
        var seen = new List<PaperPlane.View>();
        double biggestStep = 0, banked = 0;
        var last = plane.Roll;
        for (int k = 0; k < 250; k++)
        {
            plane.Fly(1.0 / 60, target, k / 60.0);
            biggestStep = Math.Max(biggestStep, Math.Abs(PaperPlane.Wrap(plane.Roll - last)));
            banked = Math.Max(banked, Math.Min(Math.Abs(plane.Roll), Math.Abs(Math.Abs(plane.Roll) - Math.PI)));
            last = plane.Roll;
            if (seen.Count == 0 || seen[^1] != plane.CurrentView.View) seen.Add(plane.CurrentView.View);
        }
        Assert.True(Math.Cos(plane.Heading) < 0, "it came round");
        Assert.True(plane.CurrentView.Flipped, "flying left it is the other way up, wing on top");
        Assert.True(biggestStep <= PaperPlane.RollRate / 60 + 1e-9, "it never snaps over");
        Assert.True(banked > 0.4, $"it banks into the turn: {banked}");
        Assert.True(seen.Contains(PaperPlane.View.Top) || seen.Contains(PaperPlane.View.Belly),
            $"turning over it shows its top or its underside: {string.Join(", ", seen)}");
    }

    [Fact]
    public void TheTrailIsDottedAndFadesAway()
    {
        var plane = new PaperPlane(0, 1, Pt.Zero, new Vec(0, 1), new Pt(3000, 0));
        for (int k = 0; k < 100; k++) plane.Fly(0.02, new Pt(3000, 0), k * 0.02);
        Assert.True(plane.Trail.Count > 10);
        var gaps = plane.Trail.Zip(plane.Trail.Skip(1), (a, b) => a.Position.DistanceTo(b.Position)).ToList();
        Assert.True(gaps.All(g => g >= plane.PuffSpacing * 0.9), "puffs, not a solid line");
        Assert.True(plane.Trail.All(p => p.Age < plane.PuffLife));
        for (int k = 0; k < 60; k++) plane.FadeTrail(0.02);
        Assert.Empty(plane.Trail);      // gone a second after the plane is
    }

    [Fact]
    public void EveryThrownPlaneFliesInItsOwnWeatherAndMostAreQuick()
    {
        var rng = new Random(21);
        var planes = Enumerable.Range(0, 200)
            .Select(_ => PaperPlane.Thrown(0, 1, Pt.Zero, new Vec(0, 1), new Pt(900, 400), rng)).ToList();
        Assert.Equal(200, planes.Select(p => p.Wind.Phases[0]).Distinct().Count());      // no two share a wind
        var quick = planes.Count(p => p.Cruise >= 380);
        Assert.True(quick > 130 && quick < 190, $"about four in five are quick: {quick}");
        Assert.True(planes.All(p => p.Swirl > 0 && p.Cruise > 240 * 0.9));
    }

    [Fact]
    public void ASwirlingQuickPlaneStillAlwaysReachesItsCatcherAtTheAppsFrameRate()
    {
        var rng = new Random(5);
        for (int n = 0; n < 60; n++)
        {
            var start = new Pt(rng.Range(0, 2500), 20);
            var target = new Pt(rng.Range(0, 2500), rng.Range(20, 1400));
            var plane = PaperPlane.Thrown(0, 1, start, new Vec(0, 1), target, rng);
            double time = 0;
            var caught = false;
            while (!caught && plane.Age < 30)
            {
                target = new Pt(target.X, target.Y + 40 / 30.0);
                plane.Fly(1 / 30.0, target, time);
                time += 1 / 30.0;
                caught = plane.Passed(30, target);
            }
            Assert.True(caught && plane.Age < 25, $"caught after {plane.Age} s, cruise {plane.Cruise}, swirl {plane.Swirl}");
        }
    }

    [Fact]
    public void TheSwirlCurlsThePathFarMoreThanStillAir()
    {
        static double Wander(PaperPlane plane)
        {
            double furthest = 0;
            for (int k = 0; k < 90; k++)
            {
                plane.Fly(1 / 30.0, new Pt(3000, 0), k / 30.0);
                furthest = Math.Max(furthest, Math.Abs(plane.Position.Y));
            }
            return furthest;
        }
        var still = new PaperPlane(0, 1, Pt.Zero, new Vec(1, 0), new Pt(3000, 0)) { Wind = new Wind(0) };
        var swirly = still.Clone();
        swirly.Swirl = 1000;
        swirly.SwirlRate = 2;
        double a = Wander(still), b = Wander(swirly);
        Assert.True(b > a + 40, $"swirl {b} vs still {a}");
    }

    [Fact]
    public void AFastPlaneCannotSkipPastItsCatcherBetweenFrames()
    {
        var plane = new PaperPlane(0, 1, new Pt(0, 0), new Vec(1, 0), new Pt(1000, 0)) { Wind = new Wind(0), Cruise = 700 };
        for (int k = 0; k < 40; k++)
        {
            plane.Fly(0.1, new Pt(1000, 0), k * 0.1);
            if (plane.Position.X > 300) break;
        }
        var between = new Pt((plane.Previous.X + plane.Position.X) / 2, 0);
        Assert.True(plane.DistanceTo(between) > 20, "the step is long");
        Assert.True(plane.Passed(5, between));
    }

    /// <summary>A creature's head on one of the screen's four edges.</summary>
    private static Pt HeadOnEdge(Rect screen, Random rng)
    {
        var x = rng.Range(screen.MinX + 30, screen.MaxX - 30);
        var y = rng.Range(screen.MinY + 30, screen.MaxY - 30);
        return rng.Next(4) switch
        {
            0 => new Pt(x, screen.MinY + 30),
            1 => new Pt(x, screen.MaxY - 30),
            2 => new Pt(screen.MinX + 30, y),
            _ => new Pt(screen.MaxX - 30, y),
        };
    }

    [Fact]
    public void APlaneNeverFliesPastTheScreensEdgeAndIsStillCaught()
    {
        var rng = new Random(11);
        var screen = new Rect(0, 0, 1512, 982);
        var inner = screen.InsetBy(24, 24);
        for (int n = 0; n < 150; n++)
        {
            Pt start = HeadOnEdge(screen, rng), target = HeadOnEdge(screen, rng);
            var inward = new Vec(start.X < 100 ? 1 : start.X > 1400 ? -1 : 0, start.Y < 100 ? 1 : start.Y > 880 ? -1 : 0);
            var plane = PaperPlane.Thrown(0, 1, start, inward, target, rng);
            plane.Wind.Strength = 480;
            plane.Swirl = 1100;
            plane.Sky = new[] { screen };
            plane.Margin = 24;
            double time = 0;
            var caught = false;
            while (!caught && plane.Age < 30)
            {
                plane.Fly(1 / 30.0, target, time);
                time += 1 / 30.0;
                caught = plane.Passed(30, target);
                if (plane.InSky) Assert.True(inner.InsetBy(-0.5, -0.5).Contains(plane.Position), $"out at {plane.Position}");
            }
            Assert.True(caught && plane.Age < 25, $"caught after {plane.Age} s");
        }
    }

    [Fact]
    public void APlaneThrownFromBelowTheScreenFliesInAndStaysIn()
    {
        var screen = new Rect(0, 0, 1440, 900);
        var plane = new PaperPlane(0, 1, new Pt(700, -16), new Vec(0, 1), new Pt(720, 450)) { Sky = new[] { screen }, Margin = 30 };
        Assert.False(plane.InSky);
        for (int k = 0; k < 60; k++) plane.Fly(1 / 30.0, new Pt(720, 450), k / 30.0);
        Assert.True(plane.InSky, "not pinned to the edge on the way in");
    }

    [Fact]
    public void APlaneGoesOnFromOneScreenToTheNext()
    {
        Rect left = new(0, 0, 1440, 900), right = new(1440, 0, 1920, 1080);
        var plane = new PaperPlane(0, 1, new Pt(200, 450), new Vec(1, 0), new Pt(2800, 450)) { Sky = new[] { left, right }, Margin = 24 };
        double time = 0;
        while (plane.DistanceTo(new Pt(2800, 450)) > 30 && plane.Age < 20)
        {
            plane.Fly(1 / 30.0, new Pt(2800, 450), time);
            time += 1 / 30.0;
            Assert.True(plane.Position.Y >= 23.5 && plane.Position.Y <= 1080 - 23.5);
        }
        Assert.True(plane.Age < 20, "across the seam between the two screens");
    }

    [Fact]
    public void APlaneIsDueEveryIntervalFromTheLastOne()
    {
        var post = new Post(120);
        Assert.False(post.IsDue(119));
        Assert.True(post.IsDue(120));
        post.Stir(100);
        Assert.False(post.IsDue(200));
        Assert.True(post.IsDue(220));
        post.Retry(220, 10);
        Assert.True(!post.IsDue(229) && post.IsDue(230), "nobody free: ask again in ten seconds");
        Assert.False(new Post(0).IsDue(1e9), "zero means never");
    }

    [Fact]
    public void TheCatcherIsOneOfTheFartherHalfFromTheSender()
    {
        var rng = new Random(3);
        var free = new Dictionary<int, Pt>
        {
            [0] = new(0, 0), [1] = new(10, 0), [2] = new(900, 0), [3] = new(1000, 0), [4] = new(20, 0),
        };
        for (int n = 0; n < 50; n++)
        {
            var pair = Post.PickPair(free, rng)!.Value;
            Assert.NotEqual(pair.From, pair.To);
            var d = Math.Abs(free[pair.To].X - free[pair.From].X);
            var others = free.Where(kv => kv.Key != pair.From).Select(kv => Math.Abs(kv.Value.X - free[pair.From].X)).OrderByDescending(x => x);
            Assert.Contains(d, others.Take(2));
        }
        Assert.Null(Post.PickPair(new Dictionary<int, Pt> { [0] = Pt.Zero }, rng));      // one creature cannot write to itself
    }

    [Fact]
    public void EveryDefaultCharacterHasItsOwnVoiceAndEveryLineFillsIn()
    {
        var rng = new Random(11);
        foreach (var c in Banter.DefaultCharacters) Assert.True(Letters.Voices.ContainsKey(c.Name), $"{c.Name} has a voice");
        var all = Letters.Voices.Append(new KeyValuePair<string, Letters.Voice>("someone new", Letters.Anyone));
        foreach (var (name, voice) in all)
        {
            Assert.True(voice.Notes.Count >= 3 && voice.Musings.Count >= 3 && voice.Replies.Count >= 3 && voice.Topics.Count > 0, name);
            foreach (var line in voice.Notes.Concat(voice.Musings).Concat(voice.Replies))
            {
                var filled = Letters.Fill(line, "Ann", "Bob");
                Assert.True(!filled.Contains('{') && !filled.Contains('}'), $"{name}: {line}");
                Assert.True(filled.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length <= 22, $"{name} is too wordy: {line}");
            }
        }
        Assert.Same(Letters.Anyone, Letters.VoiceOf("Nobody we know"));
        Assert.NotEmpty(Letters.Note("Blocky", "Pip", rng));
        Assert.True(Letters.Musing("Zed", "Dot", rng).Length > 5);
        Assert.Equal("*reads* \"Hi.\" — Dot", Letters.Reading("Hi.", "Dot"));
    }

    [Fact]
    public void TheModelPromptsUseOnlyBantersPlaceholders()
    {
        foreach (var prompt in new[] { Letters.NotePrompt, Letters.MusingPrompt, Letters.ReplyPrompt })
        {
            var rest = prompt;
            foreach (var key in Banter.Placeholders) rest = rest.Replace("{" + key + "}", "");
            Assert.False(rest.Contains('{'), $"unknown placeholder in {prompt}");
        }
    }

    /// <summary>From the Mac's LineMemoryTests: it needs Letters, so it lives with them here.</summary>
    [Fact]
    public void ARoundOfLettersNeverRepeatsALine()
    {
        var memory = new LineMemory(12);
        var rng = new Random();
        var count = Letters.VoiceOf("Blocky").Musings.Count;
        var said = new List<string>();
        for (int n = 0; n < count * 3; n++)
        {
            var line = Letters.Musing("Blocky", "Pip", rng, memory);
            said.Add(line);
            memory.Remember(line, "Blocky");
        }
        for (int start = 0; start < said.Count; start += count)
            Assert.True(said.Skip(start).Take(count).Distinct().Count() == count, "every musing once before any comes back");
    }
}
