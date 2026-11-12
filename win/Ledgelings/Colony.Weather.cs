using System.Drawing;
using Ledgelings.Core;
using Ledgelings.Core.PixelFX;

namespace Ledgelings;

/// <summary>What the weather keeps between frames, the Mac's <c>WeatherState</c>.</summary>
internal sealed class WeatherState
{
    /// <summary>The sky of one home monitor, its frame and its last picture.</summary>
    public sealed class SkyEntry
    {
        public Rect Display;
        public Weather.Sky Sky = null!;
        public FXFrame Frame = null!;
        public double TopInset;
        public Bitmap? Image;
    }

    /// <summary>An umbrella falling or fallen: where, how fast, its turn, and its picture.</summary>
    public sealed class Dropped
    {
        public Pt At;
        public double Vy, Rotation, Spin, Scale;
        public Bitmap? Image;
        public Size Size;
        public bool Landed;
    }

    public Weather.Switches Switches = new();
    public Weather.Spell? Spell;
    public Weather.Wind? Wind;
    public List<SkyEntry> Skies = new();
    public double NextDraw;
    /// <summary>The cursor's path, for "the cursor barely moved".</summary>
    public readonly Weather.CursorTrail Trail = new();
    public double NextSample, NextCheck;
    /// <summary>When the last spell ended: the next comes a quiet while later, not at once.</summary>
    public double EndedAt = -1e9;
    public List<WeatherWatch.Window> Windows = new();
    public double NextWindows;
    public bool FullScreen;
    /// <summary>The windows were just read again: the ledges follow.</summary>
    public bool WindowsFresh;
    public bool Microphone;
    public double NextMicrophone;
    /// <summary>Each creature's own walking pace, kept while the weather slows or speeds it.</summary>
    public Dictionary<int, double> Pace = new();
    /// <summary>Where each walker last left a footprint, by creature.</summary>
    public Dictionary<int, double> PrintedAt = new();
    /// <summary>The umbrellas: who shares with whom.</summary>
    public List<List<int>> Groups = new();
    public double NextGroups;
    public HashSet<string> Said = new();
    /// <summary>The umbrellas of creatures hanging from the top edge, filling with rain.</summary>
    public Dictionary<int, Weather.Bowl> Bowls = new();
    public List<Dropped> DroppedUmbrellas = new();
    /// <summary>Creatures dripping wet until then.</summary>
    public Dictionary<int, double> WetUntil = new();
    /// <summary>Umbrellas blown inside out until then.</summary>
    public Dictionary<int, double> InsideOutUntil = new();
    public List<(Pt At, int Sky, int Column)> Snowmen = new();
    public List<(Pt From, int By, int To, double Age)> Snowballs = new();
    public double NextDeed;
    public double LastLine = -1e9;
    public double Time;
    public readonly Dictionary<string, Bitmap?> UmbrellaImages = new();
    private Bitmap? snowman, snowball, drip;
    public Bitmap? SnowmanImage => snowman ??= Image(Weather.Snowman());
    public Bitmap? SnowballImage => snowball ??= Image(Weather.Snowball());
    public Bitmap? DripImage => drip ??= Image(Weather.Drip());
    /// <summary><c>--weather</c>: every step, as it happens.</summary>
    public Action<string>? Trace;
    /// <summary>A test says where the windows are rather than Windows.</summary>
    public List<WeatherWatch.Window>? FakeWindows;

    public static Bitmap? Image(Weather.Art art) => EffectPlayer.Image(art.Rgba, art.W, art.H);
}

/// <summary>One monitor's weather as a picture: its bottom-left corner in global points and its size there.</summary>
public sealed record WeatherPicture(Bitmap? Image, Rect Frame);

/// <summary>
/// Weather on a quiet screen (SPEC §7.20), the Mac's <c>Colony+Weather</c>: it comes when nobody has typed or moved
/// the cursor for a while, falls over the creatures' monitors, piles up, and eases off when the owner comes back.
/// The creatures wade, shiver, build snowmen, throw snowballs, open umbrellas, get soaked on the top edge and are
/// pushed by the wind. Everything is drawn on the click-through overlay. Windows has no calendar to read, so only
/// a microphone in use counts as a meeting.
/// </summary>
public sealed partial class Colony
{
    /// <summary>Screen points per art pixel of the sky, before the monitor's own pixel scale.</summary>
    public const double SkyScale = 2;
    /// <summary>Seconds between two weather lines from anyone.</summary>
    private const double WeatherLineGap = 9;
    private const double SnowballFlight = 0.8;

    private readonly WeatherState weather = new();

    /// <summary>Screen pixels per art pixel of the sky.</summary>
    private double SkyPixel => SkyScale * pixelScale;

    public bool WeatherShowing => weather.Spell is not null;
    /// <summary>The weather now, null when the sky is clear or clearing: the tray's tick.</summary>
    public Weather.Kind? WeatherNow => weather.Spell is { IsEasing: false } s ? s.Kind : null;
    /// <summary><c>--weather</c>: every step, as it happens.</summary>
    internal Action<string>? WeatherTrace { get => weather.Trace; set => weather.Trace = value; }

    // MARK: Starting and stopping

    /// <summary>Weather starts now: from the menu, Play now, Creature Actions, or the quiet screen. False when it is off.</summary>
    public bool StartWeather(Weather.Kind kind, bool byHand = true)
    {
        RefreshWeatherSwitches();
        if (!byHand && !weather.Switches.Allows(kind)) return false;
        weather.Spell = new Weather.Spell(kind, weather.Switches.LastsMinutes * 60, byHand);
        weather.Wind = kind.Blows() ? new Weather.Wind(rng.Coin(), weather.Switches.WindStrength) : null;
        weather.Time = 0;
        weather.Said = new();
        weather.Groups = new();
        weather.Bowls = new();
        weather.InsideOutUntil = new();
        weather.NextDeed = Elapsed + 12;
        LayOutSkies();
        weather.Trace?.Invoke($"weather {kind.Name()} starts");
        // The light season particles give way to the heavier weather.
        if (fxAmbient is { } a && a.Tiles.FirstOrDefault()?.ByHand != true) a.Tiles.ForEach(t => t.Instance.Stop());
        if (kind.Snows()) WeatherLine("snow", WeatherSpeaker());
        if (kind.Rains()) WeatherLine("rain", WeatherSpeaker());
        if (kind == Weather.Kind.Wind) WeatherLine("wind", WeatherSpeaker());
        return true;
    }

    /// <summary>Clear: whatever falls eases off; the snow on the ground melts slowly.</summary>
    public void ClearWeather()
    {
        if (weather.Spell is null) return;
        weather.Spell.Ease();
        weather.Trace?.Invoke("weather eases off");
    }

    /// <summary>A weather by name now, or <c>clear</c>: from the tray, the Weather page and Creature Actions.</summary>
    public bool PlayWeather(string code)
    {
        if (Weather.KindNamed(code) is { } kind) return StartWeather(kind);
        ClearWeather();
        return true;
    }

    /// <summary>Everything gone at once (the monitors changed, a test).</summary>
    public void ResetWeather()
    {
        weather.Spell = null;
        weather.Wind = null;
        RestorePaces();
        foreach (var e in weather.Skies) e.Image?.Dispose();
        weather.Skies = new();
        weather.DroppedUmbrellas = new();
        weather.Snowmen = new();
        weather.Snowballs = new();
        weather.Bowls = new();
        weather.WetUntil = new();
        weather.Groups = new();
    }

    private void RefreshWeatherSwitches()
    {
        var s = Settings.WeatherSwitches(ReduceMotionFromSystem);
        if (s == weather.Switches) return;
        if (s.SnowDepth != weather.Switches.SnowDepth) foreach (var e in weather.Skies) e.Sky.SetDepth(s.SnowDepth);
        weather.Switches = s;
    }

    /// <summary>One sky per home monitor, made afresh when the monitors change (the snow lying there goes with them).</summary>
    private void LayOutSkies()
    {
        var home = HomeMonitors;
        if (weather.Skies.Select(e => e.Display).SequenceEqual(home.Select(m => m.Frame))) return;
        foreach (var e in weather.Skies) e.Image?.Dispose();
        var scale = SkyPixel;
        weather.Skies = home.Select((m, k) =>
        {
            int w = (int)(m.Frame.Width / scale), h = (int)(m.Frame.Height / scale);
            var sky = new Weather.Sky(w, h, weather.Switches.SnowDepth, seed: 7 + k * 13);
            sky.OnShower = (x, n) => weather.Trace?.Invoke($"snow falls off a window at {x}: {n} flakes");
            return new WeatherState.SkyEntry { Display = m.Frame, Sky = sky, Frame = new FXFrame(w, h), TopInset = m.TopInset };
        }).ToList();
    }

    // MARK: Every frame

    private void UpdateWeather(double dt)
    {
        RefreshWeatherSwitches();
        var s = weather.Switches;
        if (!s.Enabled && weather.Spell is { ByHand: false }) weather.Spell.Ease();
        WatchTheScreen();
        if (weather.Spell is { } spell)
        {
            weather.Time += dt;
            if (!spell.ByHand && !spell.IsEasing && Weather.IsBack(WeatherWatch.KeyIdle(keyCounter), weather.Trail.Travel(Elapsed - 2) / pixelScale))
            {
                spell.Ease();
                weather.Trace?.Invoke("weather eases off: someone is back");
            }
            var was = spell.IsEasing;
            spell.Update(dt);
            if (spell.IsEasing && !was) weather.Trace?.Invoke("weather eases off");
            if (spell.IsOver)
            {
                weather.Spell = null;
                weather.Wind = null;
                weather.EndedAt = Elapsed;
                RestorePaces();
                weather.Trace?.Invoke($"weather {spell.Kind.Name()} over");
            }
        }
        if (weather.Skies.Count == 0 && weather.Spell is null) return;
        LayOutSkies();
        UpdateSkies(dt);
        UpdateWeatherCreatures(dt);
        if (weather.Spell is null && weather.Skies.All(e => e.Sky.IsEmpty) && weather.DroppedUmbrellas.Count == 0)
        {
            foreach (var e in weather.Skies) e.Image?.Dispose();
            weather.Skies = new();
            weather.Snowmen = new();
            weather.WetUntil = new();
            weather.Trace?.Invoke("weather all melted");
        }
    }

    /// <summary>The cursor, the keys, a full-screen app and the microphone: whether the screen is quiet, and weather may come.</summary>
    private void WatchTheScreen()
    {
        if (Elapsed >= weather.NextSample)
        {
            weather.NextSample = Elapsed + 0.5;
            weather.Trail.Add(Desktop.Cursor(), Elapsed, Math.Max(60, weather.Switches.QuietMinutes * 60));
        }
        if (Elapsed >= weather.NextWindows)
        {
            weather.NextWindows = Elapsed + 0.5;
            weather.Windows = weather.FakeWindows ?? WeatherWatch.Windows();
            weather.FullScreen = weather.FakeWindows is null && WeatherWatch.FullScreen(weather.Windows, monitors.Select(m => m.Frame).ToList());
            weather.WindowsFresh = true;
        }
        if (weather.Spell is not null || Elapsed < weather.NextCheck) return;
        const double step = 10;
        weather.NextCheck = Elapsed + step;
        var s = weather.Switches;
        if (!s.Enabled) return;
        // Typing starts the keyboard counter, which the quiet rule reads too.
        keyCounter ??= Native.KeyCounter.Start();
        if (Elapsed >= weather.NextMicrophone)
        {
            weather.NextMicrophone = Elapsed + 30;
            weather.Microphone = WeatherWatch.MicrophoneInUse;
        }
        // The cursor's travel in points, as the Mac counts it, whatever the monitor's pixel scale.
        var screen = new Weather.Screen(WeatherWatch.KeyIdle(keyCounter), weather.Trail.Travel(Elapsed - s.QuietMinutes * 60) / pixelScale,
                                        weather.FullScreen, Activities.Shared.IsRunning, weather.Microphone);
        // A whole quiet stretch watched, and one since the last spell ended.
        if (weather.Trail.Span < Math.Min(s.QuietMinutes * 60, 60) - 1 || Elapsed - weather.EndedAt < s.QuietMinutes * 60
            || !Weather.IsQuiet(screen, s.QuietMinutes)) return;
        if (rng.NextDouble() >= Weather.Chance(step, s.Frequency)) return;
        if (Weather.Pick(Effects.SeasonOf(Now().LocalDateTime), s, rng.NextDouble()) is not { } kind) return;
        StartWeather(kind, byHand: false);
    }

    private void UpdateSkies(double dt)
    {
        var s = weather.Switches;
        var spell = weather.Spell;
        var drift = spell is not null && weather.Wind is { } wind ? wind.Drift(weather.Time, spell.Intensity) : 0;
        var leafy = Effects.SeasonOf(Now().LocalDateTime) == Effects.Season.Autumn;
        foreach (var e in weather.Skies)
        {
            e.Sky.Leafy = leafy;
            if (s.WindowTops && weather.WindowsFresh)
                e.Sky.SetLedges(WeatherWatch.Ledges(weather.Windows, e.Display, SkyPixel, e.TopInset), s.SnowDepth);
            e.Sky.Update(dt, spell?.Kind, spell?.Intensity ?? 0, drift, s.RainHeaviness, s.SnowDepth, s.WindowTops, s.ReduceMotion);
        }
        weather.WindowsFresh = false;
    }

    /// <summary>The sky under <paramref name="point"/>, and the column there.</summary>
    private (int Index, int Column)? SkyAt(Pt point)
    {
        var k = weather.Skies.FindIndex(e => e.Display.InsetBy(-1, -1).Contains(point));
        if (k < 0) return null;
        return (k, (int)((point.X - weather.Skies[k].Display.MinX) / SkyPixel));
    }

    // MARK: The creatures in it

    /// <summary>On the floor (the bottom edge), or hanging from the top edge, or neither (a wall).</summary>
    private (bool Floor, bool Ceiling) SideOf(int i)
    {
        var c = creatures[i];
        if (c.IsPlaying || c.IsHeld || c.IsJumping) return (false, false);
        var up = c.Loop.Inward(c.Segment).Dy;
        return (up > 0.9, up < -0.9);
    }

    private bool Outside(int i) => !hideout.IsInside(i) && !IsMoving(i);

    private void UpdateWeatherCreatures(double dt)
    {
        var spell = weather.Spell;
        var s = weather.Switches;
        var intensity = spell?.Intensity ?? 0;
        var kind = spell?.Kind;
        var force = weather.Wind?.Force(weather.Time) ?? 0;
        for (int i = 0; i < creatures.Count; i++)
        {
            if (!Outside(i)) continue;
            var c = creatures[i];
            var (floor, ceiling) = SideOf(i);
            // Wading and the wind: a slower or a faster pace.
            if (c.IsAtLeisure)
            {
                var basePace = weather.Pace.TryGetValue(i, out var kept) ? kept : c.Settings.WalkSpeed;
                weather.Pace[i] = basePace;
                var pace = 1.0;
                if (floor && SkyAt(c.Position) is { } at)
                {
                    var d = weather.Skies[at.Index].Sky.Depth(at.Column);
                    pace *= Weather.Wading(d.Depth, d.Cap);
                }
                if (weather.Wind is { } wind && (floor || ceiling) && intensity > 0)
                {
                    var rightwards = c.Loop.Direction(c.Segment).Dx * (c.IsMirrored ? -1 : 1);
                    pace *= Weather.WindPace(rightwards, wind, force * intensity);
                }
                c.Settings.WalkSpeed = basePace * pace;
            }
            // Footprints in the snow along the bottom.
            if (floor && c.Animation == "walk" && SkyAt(c.Position) is { } print)
            {
                if (!weather.PrintedAt.TryGetValue(i, out var last)) weather.PrintedAt[i] = c.Position.X;
                else if (Math.Abs(c.Position.X - last) >= 6 * SkyPixel)
                {
                    weather.PrintedAt[i] = c.Position.X;
                    if (weather.Skies[print.Index].Sky.Depth(print.Column).Depth >= 2) weather.Skies[print.Index].Sky.Footprint(print.Column);
                }
            }
        }
        if (kind is { } k && k.Rains()) UpdateUmbrellas(dt, intensity);
        else if (weather.Groups.Count > 0) weather.Groups = new();
        if (kind?.Rains() != true && weather.Bowls.Count > 0 && spell is null) weather.Bowls = new();
        if (weather.Wind is { } w && spell is not null && !s.ReduceMotion && w.Peaks(weather.Time, dt)) Gust(w, spell.Intensity);
        UpdateDropped(dt);
        UpdateSnowballs(dt);
        if (kind == Weather.Kind.Snow && intensity > 0.6 && Elapsed >= weather.NextDeed) SnowDeed();
        // Snowmen melt with the snow they stand in.
        weather.Snowmen.RemoveAll(m => m.Sky >= weather.Skies.Count || weather.Skies[m.Sky].Sky.Depth(m.Column).Depth < 1);
    }

    /// <summary>Everyone walks at their own pace again.</summary>
    private void RestorePaces()
    {
        foreach (var (i, pace) in weather.Pace)
            if (i < creatures.Count) creatures[i].Settings.WalkSpeed = pace;
        weather.Pace = new();
    }

    // MARK: Umbrellas

    /// <summary>Who is out in the rain on the floor or the top edge, grouped by the sharing distance, every second.</summary>
    private void UpdateUmbrellas(double dt, double intensity)
    {
        if (Elapsed >= weather.NextGroups)
        {
            weather.NextGroups = Elapsed + 1;
            var standing = new List<Weather.Standing>();
            for (int i = 0; i < creatures.Count; i++)
            {
                if (!Outside(i)) continue;
                var (floor, ceiling) = SideOf(i);
                if (!floor && !ceiling) continue;
                var c = creatures[i];
                // The same edge: the same loop's segment. Along it in points, as the sharing distance is.
                standing.Add(new Weather.Standing(i, c.Spot.Loop * 1000 + c.Segment, c.Position.X / pixelScale));
            }
            var groups = Weather.UmbrellaGroups(standing, weather.Switches.ShareDistance);
            if (!SameGroups(groups, weather.Groups))
            {
                foreach (var g in groups)
                {
                    if (g.Count <= 1 || weather.Groups.Any(o => o.SequenceEqual(g))) continue;
                    weather.Trace?.Invoke("rain " + string.Join(" & ", g.Select(j => CharacterFor(j).Name)) + " share an umbrella");
                    var holder = Weather.Holder(g);
                    var key = "share" + string.Join(",", g);
                    if (g.FirstOrDefault(j => j != holder, -1) is var guest and >= 0 && weather.Said.Add(key))
                        WeatherLine("share", guest, friend: holder);
                }
                weather.Groups = groups;
            }
        }
        // Those sharing keep close to whoever holds it.
        foreach (var g in weather.Groups.Where(g => g.Count > 1))
        {
            var holder = Weather.Holder(g);
            foreach (var i in g)
                if (i != holder && i < creatures.Count && creatures[i].IsAtLeisure)
                    creatures[i].HeadToward(creatures[holder].T, atlas.BodyHalfSize * sizes[i] * 1.6);
        }
        // The top edge: the umbrella is a bowl, and it fills.
        foreach (var g in weather.Groups)
        {
            var holder = Weather.Holder(g);
            if (holder >= creatures.Count || !SideOf(holder).Ceiling) { weather.Bowls.Remove(holder); continue; }
            if (!weather.Bowls.TryGetValue(holder, out var bowl)) weather.Bowls[holder] = bowl = new Weather.Bowl();
            if (bowl.Now == Weather.Bowl.State.Fallen) continue;
            var happened = bowl.Update(dt, intensity, weather.Switches.RainHeaviness);
            var name = CharacterFor(holder).Name;
            switch (happened)
            {
                case Weather.Bowl.Event.Full: weather.Trace?.Invoke($"rain {name} umbrella full, tips"); break;
                case Weather.Bowl.Event.Spills:
                    weather.Trace?.Invoke($"rain {name} umbrella full, falls");
                    SpillBowl(holder, g);
                    break;
            }
        }
    }

    private static bool SameGroups(List<List<int>> a, List<List<int>> b) => a.Count == b.Count && a.Zip(b).All(p => p.First.SequenceEqual(p.Second));

    /// <summary>The bowl tips: water everywhere, the creatures under it soaked, and the umbrella falls to the floor.</summary>
    private void SpillBowl(int holder, List<int> group)
    {
        var p = UmbrellaPlace(holder, group);
        if (SkyAt(p.Position) is { } at)
        {
            var d = weather.Skies[at.Index].Display;
            weather.Skies[at.Index].Sky.Spill((p.Position.X - d.MinX) / SkyPixel, (d.MaxY - p.Position.Y) / SkyPixel);
        }
        weather.DroppedUmbrellas.Add(new WeatherState.Dropped
        {
            At = p.Position, Rotation = p.Rotation, Spin = rng.Range(-5, 5), Image = p.Image, Scale = p.Scale, Size = p.Size ?? default,
        });
        foreach (var i in group)
        {
            weather.WetUntil[i] = Elapsed + 25;
            StyleTrigger(Effects.Trigger.Winter, i);
        }
        WeatherLine("soaked", holder);
    }

    /// <summary>Umbrellas falling down the screen, and lying on the floor once down; gone when the weather is.</summary>
    private void UpdateDropped(double dt)
    {
        foreach (var d in weather.DroppedUmbrellas)
        {
            if (d.Landed) continue;
            d.Vy -= 900 * pixelScale * dt;
            d.At = new Pt(d.At.X, d.At.Y + d.Vy * dt);
            d.Rotation += d.Spin * dt;
            var below = HomeFrames.Where(f => f.MinX <= d.At.X && d.At.X <= f.MaxX).Select(f => (double?)f.MinY).FirstOrDefault() ?? 0;
            var floorY = below + 6 * d.Scale;
            if (d.At.Y > floorY) continue;
            d.At = new Pt(d.At.X, floorY);
            d.Landed = true;
            d.Rotation = Math.PI / 2 * (d.Spin > 0 ? 1 : -1);
            if (SkyAt(new Pt(d.At.X, floorY)) is { } at)
            {
                var disp = weather.Skies[at.Index].Display;
                weather.Skies[at.Index].Sky.Spill((d.At.X - disp.MinX) / SkyPixel, (disp.MaxY - floorY) / SkyPixel + 6 * d.Scale / SkyPixel);
            }
            weather.Trace?.Invoke("rain umbrella lands on the floor with a splash");
        }
        if (weather.Spell is null) weather.DroppedUmbrellas.Clear();
    }

    /// <summary>Where <paramref name="holder"/>'s umbrella goes: over its head along its edge's inward line, a little bigger when shared.</summary>
    private PropSnapshot UmbrellaPlace(int holder, List<int> group)
    {
        var width = Weather.UmbrellaWidth(group.Count);
        var c = creatures[holder];
        var scale = sizes[holder];
        // Over the middle of everyone under it, along their edge.
        var p = DrawnPosition(holder);
        var mates = group.Where(j => j < creatures.Count).ToList();
        if (mates.Count > 1) p = new Pt(mates.Average(j => DrawnPosition(j).X), p.Y);
        var colour = Weather.UmbrellaColour(CharacterFor(holder).Name);
        var insideOut = weather.InsideOutUntil.GetValueOrDefault(holder) > Elapsed;
        var water = weather.Bowls.TryGetValue(holder, out var bowl) ? bowl.Water : 0;
        var key = $"{width} {colour} {insideOut} {(int)(water * 5)}";
        if (!weather.UmbrellaImages.TryGetValue(key, out var image))
        {
            var art = Weather.Umbrella(width, colour, insideOut);
            Fill(art, water);
            if (weather.UmbrellaImages.Count > 64)
            {
                // Those still falling keep their own picture.
                var falling = weather.DroppedUmbrellas.Select(d => d.Image).ToHashSet();
                foreach (var old in weather.UmbrellaImages.Values) if (old is not null && !falling.Contains(old)) old.Dispose();
                weather.UmbrellaImages.Clear();
            }
            weather.UmbrellaImages[key] = image = WeatherState.Image(art);
        }
        var inward = c.Loop.Inward(c.Segment);
        var w = Math.Max(12, width | 1);
        var height = Weather.UmbrellaDome(w) + 10;
        var up = (height / 2.0 - 2) * scale + atlas.BodyHalfSize * scale * 0.2;
        var tip = bowl?.Tip ?? 0;
        return new PropSnapshot(image, new Pt(p.X + inward.Dx * up, p.Y + inward.Dy * up), c.Rotation + WeatherLean(holder) + tip * Math.PI / 2, scale,
                                Size: new Size(w, height));
    }

    /// <summary>The rain collected in an upside-down umbrella: its top rows, which hang lowest, turn to water.</summary>
    internal static void Fill(Weather.Art art, double water)
    {
        if (water <= 0.05) return;
        var rows = (int)Math.Ceiling(water * 4);
        uint blue = FX.Hex("#4f82d6"), light = FX.Hex("#b4d4ff");
        for (int y = 1; y <= rows; y++)
            for (int x = 1; x < art.W - 1; x++)
                if (art.At(x, y) != 0 && art.At(x - 1, y) != 0 && art.At(x + 1, y) != 0) art.Pixels[y * art.W + x] = y == rows ? light : blue;
    }

    // MARK: Wind

    /// <summary>How far a creature on the floor or the top edge leans into the wind, in radians.</summary>
    internal double WeatherLean(int i)
    {
        if (weather.Wind is not { } wind || weather.Spell is not { } spell || i >= creatures.Count || !Outside(i)) return 0;
        var (floor, ceiling) = SideOf(i);
        if (!floor && !ceiling) return 0;
        return wind.Lean(weather.Time, spell.Intensity) * (ceiling ? -1 : 1);
    }

    /// <summary>A gust at its height: the light ones pushed, one on the top edge maybe blown off, umbrellas inside out.</summary>
    private void Gust(Weather.Wind wind, double intensity)
    {
        var force = wind.Force(weather.Time) * intensity;
        weather.Trace?.Invoke($"wind gust {force:F2} from the {(wind.From > 0 ? "left" : "right")}");
        var blown = false;
        for (int i = 0; i < creatures.Count; i++)
        {
            if (!Outside(i) || !creatures[i].IsAtLeisure) continue;
            var (floor, ceiling) = SideOf(i);
            if (!floor && !ceiling) continue;
            var size = sizes[i] / pixelScale / Math.Max(0.5, Settings.MinSize);        // the smallest on screen counts as 1
            var c = creatures[i];
            var name = CharacterFor(i).Name;
            if (ceiling && !blown && Weather.BlowsOff(size, force, wind.Strength))
            {
                blown = true;
                var below = HomeFrames.Where(f => f.MinX <= c.Position.X && c.Position.X <= f.MaxX).Select(f => (double?)f.MinY).FirstOrDefault() ?? 0;
                c.Leap(c.World.Nearest(new Pt(c.Position.X + wind.From * 80 * pixelScale, below)));
                weather.Trace?.Invoke($"wind blows {name} off the top edge");
                WeatherLine("blown", i, force: true);
                continue;
            }
            var push = Weather.Push(size, force, wind.Strength);
            if (push <= 0) continue;
            var along = c.Loop.Direction(c.Segment).Dx;
            c.Shove(push * pixelScale * wind.From * along);
            weather.Trace?.Invoke($"wind gust pushes {name} {(int)push} px");
        }
        if (weather.Spell?.Kind.Rains() == true)
        {
            foreach (var g in weather.Groups)
            {
                var holder = Weather.Holder(g);
                if (!Weather.TurnsInsideOut(force, wind.Strength, rng.NextDouble())) continue;
                weather.InsideOutUntil[holder] = Elapsed + 4;
                weather.Trace?.Invoke($"storm {CharacterFor(holder).Name} umbrella inside out");
                WeatherLine("insideOut", holder);
            }
        }
        else if (WeatherSpeaker() is int speaker && weather.Said.Add($"gust{(int)(weather.Time / 30)}"))
            WeatherLine("wind", speaker);
    }

    // MARK: Snow

    /// <summary>Now and then in deep enough snow: someone shivers, builds a snowman, or throws a snowball at a friend.</summary>
    private void SnowDeed()
    {
        weather.NextDeed = Elapsed + rng.Range(14, 26);
        var onFloor = Enumerable.Range(0, creatures.Count)
            .Where(j => Outside(j) && SideOf(j).Floor && creatures[j].IsAtLeisure && !creatures[j].LooksAsleep).ToList();
        if (onFloor.Count == 0) return;
        var i = rng.Pick(onFloor);
        if (SkyAt(creatures[i].Position) is not { } at) return;
        var name = CharacterFor(i).Name;
        var roll = rng.NextDouble();
        var friends = onFloor.Where(j => j != i && Bonds.Bond(name, CharacterFor(j).Name) is not null
                                         && Math.Abs(creatures[j].Position.X - creatures[i].Position.X) < 500 * pixelScale).ToList();
        if (roll < 0.35 && friends.Count > 0)
            ThrowSnowball(i, rng.Pick(friends));
        else if (roll < 0.7 && weather.Snowmen.Count < 3 && weather.Skies[at.Index].Sky.CanBuildSnowman(at.Column))
        {
            creatures[i].Pause(3);
            var x = creatures[i].Position.X + (creatures[i].IsMirrored ? -1 : 1) * atlas.BodyHalfSize * sizes[i] * 2.2;
            var d = weather.Skies[at.Index].Display;
            weather.Snowmen.Add((new Pt(x, d.MinY), at.Index, (int)((x - d.MinX) / SkyPixel)));
            weather.Trace?.Invoke($"snow {name} builds a snowman");
            WeatherLine("snowman", i, force: true);
        }
        else
        {
            StyleTrigger(Effects.Trigger.Winter, i);
            if (!fxOn.ContainsKey(i)) Wear(Effects.Style.Frost, i);
            weather.Trace?.Invoke($"snow {name} shivers");
            WeatherLine("cold", i);
        }
    }

    internal void ThrowSnowball(int i, int j)
    {
        var c = creatures[i];
        var dx = c.Loop.Direction(c.Segment).Dx;
        c.Face(creatures[j].Position.X > c.Position.X ? dx : -dx);
        c.Pause(1.5);
        var p = DrawnPosition(i);
        weather.Snowballs.Add((new Pt(p.X, p.Y + atlas.BodyHalfSize * sizes[i]), i, j, 0));
        weather.Trace?.Invoke($"snow {CharacterFor(i).Name} throws a snowball at {CharacterFor(j).Name}");
        WeatherLine("throw", i, friend: j, force: true);
    }

    /// <summary>Snowballs fly in an arc for most of a second; the one hit gets a puff of snow and says so.</summary>
    private void UpdateSnowballs(double dt)
    {
        for (int k = weather.Snowballs.Count - 1; k >= 0; k--)
        {
            var b = weather.Snowballs[k];
            b.Age += dt;
            weather.Snowballs[k] = b;
            if (b.Age < SnowballFlight) continue;
            weather.Snowballs.RemoveAt(k);
            if (b.To >= creatures.Count) continue;
            var p = DrawnPosition(b.To);
            if (SkyAt(p) is { } at)
            {
                var d = weather.Skies[at.Index].Display;
                weather.Skies[at.Index].Sky.Puff((p.X - d.MinX) / SkyPixel, (d.MaxY - p.Y) / SkyPixel);
            }
            weather.Trace?.Invoke($"snow {CharacterFor(b.To).Name} is hit");
            weather.LastLine = Elapsed - WeatherLineGap;
            WeatherLine("hit", b.To, friend: b.By, force: true);
        }
    }

    // MARK: Words

    /// <summary>Someone awake and outside to say the weather's first line.</summary>
    private int? WeatherSpeaker()
    {
        var awake = Enumerable.Range(0, creatures.Count).Where(i => Outside(i) && !creatures[i].LooksAsleep && !bubbles.ContainsKey(i)).ToList();
        return awake.Count == 0 ? null : rng.Pick(awake);
    }

    /// <summary><paramref name="i"/> says its line for <paramref name="kind"/> (<paramref name="friend"/> fills
    /// <c>{friend}</c>), unless someone said one just now.</summary>
    private void WeatherLine(string kind, int? i, int? friend = null, bool force = false)
    {
        if (i is not int who || !Settings.WeatherTalk || !Settings.TalkEnabled || VoiceIsTakenNow || who >= creatures.Count || !Outside(who)) return;
        if (!force && Elapsed - weather.LastLine < WeatherLineGap) return;
        weather.LastLine = Elapsed;
        var name = CharacterFor(who).Name;
        var text = Weather.Line(name, kind, friend is int f ? CharacterFor(f).Name : "", rng);
        if (text.Length == 0) return;
        Say(text, who, builtIn: true);
        weather.Trace?.Invoke($"say {name}: {text}");
        History.Record(new ChatLog.Exchange
        {
            Time = DateTimeOffset.Now,
            Situation = L10n.Tr("The weather: %@.", weather.Spell?.Kind.Title().ToLowerInvariant() ?? "") + " " + Describe(who) + ".",
            Provider = AppSettings.BrainTitle(BrainKind.Script), Model = "",
            Lines = new List<ChatLog.Line> { new(name, text) },
        });
    }

    // MARK: Drawing

    /// <summary>Each home monitor's sky as one picture: redrawn fifteen times a second.</summary>
    private List<WeatherPicture> WeatherPictures()
    {
        if (weather.Skies.Count == 0) return new();
        if (Elapsed >= weather.NextDraw)
        {
            weather.NextDraw = Elapsed + 1.0 / 15;
            foreach (var e in weather.Skies)
            {
                e.Sky.Draw(e.Frame);
                e.Image?.Dispose();
                e.Image = EffectPlayer.Image(FXComposite.Rgba(e.Frame), e.Frame.W, e.Frame.H);
            }
        }
        var scale = SkyPixel;
        return weather.Skies.Select(e => new WeatherPicture(e.Image,
            new Rect(e.Display.MinX, e.Display.MaxY - e.Frame.H * scale, e.Frame.W * scale, e.Frame.H * scale))).ToList();
    }

    /// <summary>The umbrellas, the falling ones, the snowmen, the snowballs in the air and the drips off the wet.</summary>
    private List<PropSnapshot> WeatherProps()
    {
        var props = new List<PropSnapshot>();
        var scale = SkyPixel;
        if (weather.Spell is { } spell && spell.Kind.Rains() && spell.Intensity > 0.15)
            foreach (var g in weather.Groups)
            {
                var holder = Weather.Holder(g);
                if (holder >= creatures.Count) continue;
                if (weather.Bowls.TryGetValue(holder, out var bowl) && bowl.Now == Weather.Bowl.State.Fallen) continue;
                props.Add(UmbrellaPlace(holder, g));
            }
        foreach (var d in weather.DroppedUmbrellas)
            props.Add(new PropSnapshot(d.Image, d.At, d.Rotation, d.Scale, Size: d.Size));
        foreach (var m in weather.Snowmen)
        {
            if (m.Sky >= weather.Skies.Count) continue;
            var e = weather.Skies[m.Sky];
            var ground = e.Sky.Depth(m.Column).Depth * scale;
            props.Add(new PropSnapshot(weather.SnowmanImage, new Pt(m.At.X, e.Display.MinY + Math.Max(0, ground - scale * 2) + 15 * scale / 2), 0, scale,
                                       Size: new Size(11, 15)));
        }
        foreach (var b in weather.Snowballs)
        {
            if (b.To >= creatures.Count) continue;
            var to = DrawnPosition(b.To);
            var k = b.Age / SnowballFlight;
            var x = b.From.X + (to.X - b.From.X) * k;
            var y = b.From.Y + (to.Y - b.From.Y) * k + Math.Sin(Math.PI * k) * 70 * pixelScale;
            props.Add(new PropSnapshot(weather.SnowballImage, new Pt(x, y), 0, scale, InFront: true, Size: new Size(4, 4)));
        }
        foreach (var (i, until) in weather.WetUntil)
        {
            if (until <= Elapsed || i >= creatures.Count) continue;
            var p = DrawnPosition(i);
            var half = atlas.BodyHalfSize * sizes[i];
            var inward = creatures[i].Loop.Inward(creatures[i].Segment);
            for (int k = 0; k < 3; k++)
            {
                var phase = (Elapsed * 1.3 + k / 3.0) % 1;
                var x = p.X + (k - 1) * half * 0.7;
                var y = p.Y - inward.Dy * half - phase * 24 * pixelScale * (inward.Dy >= 0 ? 1 : -1);
                props.Add(new PropSnapshot(weather.DripImage, new Pt(x, y), 0, scale, Opacity: (float)(1 - phase), InFront: true, Size: new Size(1, 2)));
            }
        }
        return props;
    }
}
