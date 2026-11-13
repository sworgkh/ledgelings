using System.Drawing;
using Ledgelings.Core;
using Ledgelings.Core.PixelFX;
using Ledgelings.Native;

namespace Ledgelings;

/// <summary>
/// The effects the creatures wear and the moments they mark (SPEC §7.19), the Mac's <c>Colony+Effects</c>: styles
/// that come and go, moments tied to the features, and the season's particles along the bottom edge. Every one
/// passes <see cref="Effects.Rules"/>: its switch, Reduce motion and its cooldown. The overlay stays click-through:
/// effects are only drawn. Windows has no calendar to read, so Clock ticking comes only by hand.
/// </summary>
public sealed partial class Colony
{
    /// <summary>Screen points per pixel of the ambient particles, before the monitor's own pixel scale.</summary>
    public const double AmbientScale = 2;
    /// <summary>Points dropped before a landing on the floor counts as hard: down from a window top.</summary>
    private const double HardDrop = 240;

    private readonly Effects.Rules fxRules = new();
    /// <summary>The effect each creature is wearing or marking, by index: one at a time.</summary>
    private readonly Dictionary<int, EffectPlayer> fxOn = new();
    /// <summary>Effects standing on their own at a place: a creature that went in a poof.</summary>
    private readonly List<LooseEffect> fxLoose = new();
    /// <summary>The season's particles or the fireflies along each home monitor's bottom edge, a tile at a time.</summary>
    private (Effects.Moment Moment, List<EffectPlayer> Tiles)? fxAmbient;
    private List<Bitmap?> fxAmbientImages = new();
    private double fxAmbientNextDraw;
    /// <summary>The ambient period Stop ended early: nothing comes back out until the next one.</summary>
    private int fxStoppedPeriod = -1;
    private readonly EffectActors fxActors = new();
    /// <summary>The colony's clock when each creature last met anyone: left alone too long, it may frost over.</summary>
    private readonly Dictionary<int, double> fxMetAt = new();
    private readonly Effects.TypingWatch fxTyping = new();
    private double fxNextNowAndThen, fxSeedCounter;
    /// <summary>The day the coins last dropped, so they drop once a day.</summary>
    private string fxCoinsDay = "";
    /// <summary>Where each creature in the air took off from, to know a hard landing when it comes down.</summary>
    private readonly Dictionary<int, double> fxAirFrom = new();
    /// <summary>The species the colony has had, so a new one is noticed when it joins; null until the first look.</summary>
    private HashSet<string>? fxKnownSpecies;
    private KeyCounter? keyCounter;

    /// <summary>How many creatures there are, for Creature Actions › Styles.</summary>
    public int CreatureCount => creatures.Count;

    /// <summary>Translate is waiting for its answer (the Translate sheet sets it).</summary>
    public bool EffectsTranslating { get; set; }

    /// <summary>Windows' Show animations switched off reads as Reduce motion.</summary>
    private static bool ReduceMotionFromSystem
    {
        get { try { return !System.Windows.SystemParameters.ClientAreaAnimation; } catch (InvalidOperationException) { return false; } }
    }

    /// <summary>The switches as they stand, read every frame (cheap) so a change applies at once.</summary>
    internal void RefreshEffectSwitches()
    {
        var s = Settings.EffectSwitches(ReduceMotionFromSystem);
        fxRules.Switches = s;
        // Switched off: whatever it was showing goes.
        foreach (var p in fxOn.Values)
            if (!p.ByHand && ((p.Style is { } st && !s.Allows(st)) || (p.Moment is { } m && !s.Allows(m)))) p.Instance.Stop();
        if (fxAmbient is { } a && !s.Allows(a.Moment) && a.Tiles.FirstOrDefault()?.ByHand != true) a.Tiles.ForEach(t => t.Instance.Stop());
    }

    // MARK: Starting one

    /// <summary>A style goes on <paramref name="i"/> for <c>EffectStyleSeconds</c>, unless something else is showing on it.</summary>
    public bool Wear(Effects.Style style, int i, bool byHand = false)
    {
        if (i < 0 || i >= creatures.Count || hideout.IsInside(i)) return false;
        if (fxOn.TryGetValue(i, out var now) && now.Moment is not null && !now.Done && !byHand) return false;
        if (MakePlayer(style.Effect(), i, style: style) is not { } player) return false;
        player.Until = Elapsed + Settings.EffectStyleSeconds;
        player.ByHand = byHand;
        fxOn[i] = player;
        Trace?.Invoke($"fx {Elapsed:F2} {style.Name()} on {CharacterFor(i).Name}");
        return true;
    }

    /// <summary>Something that may put a style on <paramref name="i"/> happened: the rules roll for it.</summary>
    internal void StyleTrigger(Effects.Trigger trigger, int i)
    {
        if (i < 0 || i >= creatures.Count) return;
        if (fxRules.TakeStyle(trigger, i, Elapsed, rng.NextDouble()) is { } style) Wear(style, i);
    }

    /// <summary>A moment happened to <paramref name="i"/>: its effect plays if the rules let it.</summary>
    internal void Mark(Effects.Moment moment, int i)
    {
        if (i < 0 || i >= creatures.Count || hideout.IsInside(i)) return;
        if (!fxRules.TakeMoment(moment, i, Elapsed)) return;
        Play(moment, i, byHand: false);
    }

    /// <summary>A moment's effect on <paramref name="i"/> now, rules or not (the settings' preview).</summary>
    public bool Play(Effects.Moment moment, int i, bool byHand = true)
    {
        if (moment.Ambient()) return StartAmbient(moment, preview: true);
        if (MakePlayer(moment.Effect(), i, moment: moment) is not { } player) return false;
        // The newcomer is inside the egg until it pops (pixelfx's egg-hatch pops at 1.98 s).
        if (moment == Effects.Moment.NewArrival) player.HiddenUntil = 1.98;
        if (byHand && moment.Held())
        {
            // A loop shown by hand plays a while, a one-shot once.
            player.ByHand = true;
            player.Until = Elapsed + Math.Max(6, player.Instance.Meta.Loop ? 6 : player.Instance.Meta.Duration);
        }
        fxOn[i] = player;
        Trace?.Invoke($"fx {Elapsed:F2} moment {moment.Code()} {CharacterFor(i).Name}");
        return true;
    }

    /// <summary>The settings' way in: a style's or a moment's code (or a pixelfx id) on creature <paramref name="i"/>, or on
    /// someone on screen. False when there is nobody to show it on.</summary>
    public bool Preview(string name, int? i = null)
    {
        var who = i ?? PreviewCreature();
        foreach (var style in Effects.Styles)
            if (style.Code() == name || style.Effect() == name) return who is int w && Wear(style, w, byHand: true);
        foreach (var moment in Effects.Moments)
        {
            if (moment.Code() != name && moment.Effect() != name) continue;
            if (moment.Ambient()) return StartAmbient(moment, preview: true);
            return who is int w && Play(moment, w);
        }
        return false;
    }

    /// <summary>Someone awake, on screen and not in the house; anyone at all failing that.</summary>
    public int? PreviewCreature()
    {
        var free = Enumerable.Range(0, creatures.Count).Where(k => !hideout.IsInside(k) && !creatures[k].LooksAsleep && !fxOn.ContainsKey(k)).ToList();
        if (free.Count > 0) return rng.Pick(free);
        var any = Enumerable.Range(0, creatures.Count).Where(k => !hideout.IsInside(k)).ToList();
        return any.Count > 0 ? any[0] : null;
    }

    private EffectPlayer? MakePlayer(string name, int i, Effects.Style? style = null, Effects.Moment? moment = null)
    {
        if (i < 0 || i >= frames.Count || !FXCatalog.All.TryGetValue(name, out var type)) return null;
        if (frames[i].Frame("idle", 0) is not { } standing || fxActors.Actor(standing) is not { } made) return null;
        fxSeedCounter += 1;
        return new EffectPlayer(type, name, made.Actor, made.Box, 3 + fxSeedCounter, style, moment);
    }

    // MARK: Every frame

    private void UpdateEffects(double dt)
    {
        RefreshEffectSwitches();
        foreach (var (i, p) in fxOn.ToList())
        {
            if (i >= creatures.Count) { fxOn.Remove(i); continue; }
            p.Instance.Update(dt);
            if (p.Until is double until && Elapsed >= until) p.Instance.Stop();
            if (p.Done) fxOn.Remove(i);
        }
        for (var k = fxLoose.Count - 1; k >= 0; k--)
        {
            fxLoose[k].Player.Instance.Update(dt);
            if (fxLoose[k].Player.Done) fxLoose.RemoveAt(k);
        }
        UpdateHeldMoments();
        UpdateLandings();
        UpdateAmbient(dt);
        UpdateNowAndThen();
    }

    /// <summary>A jump or a drop that ends on the floor far below where it started: dust flies.</summary>
    private void UpdateLandings()
    {
        for (var i = 0; i < creatures.Count; i++)
        {
            var c = creatures[i];
            switch (c.Animation)
            {
                case "jump" when !c.IsPlaying:
                    if (!fxAirFrom.ContainsKey(i)) fxAirFrom[i] = c.Position.Y;
                    break;
                case "land":
                    if (fxAirFrom.Remove(i, out var from) && from - c.Position.Y > HardDrop * pixelScale && c.Loop.Inward(c.Segment).Dy > 0.9)
                        Mark(Effects.Moment.HardLanding, i);
                    break;
                default:
                    if (!c.IsHeld) fxAirFrom.Remove(i);
                    break;
            }
        }
    }

    /// <summary>Asleep, listening, translating: shown for as long as they last, played again when a one-shot ends.</summary>
    private void UpdateHeldMoments()
    {
        var s = fxRules.Switches;
        for (var i = 0; i < creatures.Count; i++)
        {
            Effects.Moment? wanted =
                dictationHelp is { Stage: DictationStage.Listening } d && d.Index == i ? Effects.Moment.Listening
                : EffectsTranslating && clipHelp is { Stage: ClipStage.Holding } h && h.Index == i ? Effects.Moment.Translating
                : creatures[i].LooksAsleep && !hideout.IsInside(i) ? Effects.Moment.Asleep
                : null;
            fxOn.TryGetValue(i, out var current);
            if (current?.Moment is { } was && was.Held() && was != wanted && current.ByHand != true) current.Instance.Stop();
            if (wanted is not { } want || !s.Allows(want)) continue;
            if (current?.Moment == want && !current.Instance.Stopping) continue;
            // A one-shot moment or a style showing now finishes first; a stopping one gives way.
            if (current is not null && (current.ByHand || (current.Moment != want && !current.Instance.Stopping && current.Moment?.Held() != true))) continue;
            Play(want, i, byHand: false);
        }
    }

    /// <summary>The fireflies after dark, or the season's particles, for a while every so often. Paused for today, or
    /// while weather falls (it is heavier), none come; stopped, none until the next time out.</summary>
    private void UpdateAmbient(double dt)
    {
        var paused = Settings.WeatherPaused(Now().LocalDateTime) || WeatherStopping;
        var want = WeatherShowing || paused ? null : Effects.AmbientAt(Now().LocalDateTime, FireflyNight, fxRules.Switches);
        var period = Effects.AmbientPeriod(Elapsed, Settings.EffectsAmbientSeconds, Settings.EffectsAmbientEveryMinutes);
        var outNow = Effects.AmbientShowing(Elapsed, Settings.EffectsAmbientSeconds, Settings.EffectsAmbientEveryMinutes)
            && period != fxStoppedPeriod;
        if (fxAmbient is { } a)
        {
            var byHand = a.Tiles.FirstOrDefault()?.ByHand == true;
            if (byHand && a.Tiles.FirstOrDefault()?.Until is double until && Elapsed >= until) a.Tiles.ForEach(t => t.Instance.Stop());
            if (!byHand && (a.Moment != want || !outNow)) a.Tiles.ForEach(t => t.Instance.Stop());
            a.Tiles.ForEach(t => t.Instance.Update(dt));
            if (a.Tiles.All(t => t.Done)) { fxAmbient = null; fxAmbientImages = new(); }
        }
        else if (want == Effects.Moment.Night && outNow) StartAmbient(Effects.Moment.Night, preview: false);
        // The season's light particles fall over the whole monitor from the top, with the weather's sky.
        if (weather.Light is { } l)
        {
            if (!l.ByHand && (l.Moment != want || !outNow)) EaseLight();
        }
        else if (want is { } m && m != Effects.Moment.Night && outNow) StartLight(m, byHand: false);
    }

    /// <summary>Fireflies: tiles across every home monitor's bottom edge, each with its own seed, a sparse few in
    /// each. The season's particles fall from the top instead (<see cref="StartLight"/>).</summary>
    public bool StartAmbient(Effects.Moment moment, bool preview)
    {
        if (moment != Effects.Moment.Night) return StartLight(moment, preview);
        if (WeatherStopping) ResetWeather();
        if (!FXCatalog.All.TryGetValue(moment.Effect(), out var type) || frames.Count == 0
            || frames[0].Frame("idle", 0) is not { } standing || fxActors.Actor(standing) is not { } made) return false;
        var tileWidth = type.Meta.Size.W * AmbientScale * pixelScale;
        var count = Math.Max(1, HomeFrames.Sum(f => (int)Math.Ceiling(f.Width / tileWidth)));
        // "How many" is for a whole monitor of the reference width: each tile flies its share.
        var perTile = Math.Max(1, (int)Math.Round(Settings.SkyFirefliesCount * type.Meta.Size.W * AmbientScale / (Weather.ReferenceWidth * SkyScale)));
        var tiles = new List<EffectPlayer>();
        for (var k = 0; k < count; k++)
        {
            var p = new EffectPlayer(type, moment.Effect(), made.Actor, made.Box, 11 + k * 7, moment: moment);
            p.Instance.DropBackdrop();
            p.Instance.SetFireflies(perTile);
            if (preview) { p.Until = Elapsed + 6; p.ByHand = true; }
            tiles.Add(p);
        }
        fxAmbient = (moment, tiles);
        Trace?.Invoke($"fx {Elapsed:F2} moment {moment.Code()} along the bottom, {tiles.Count} tiles, {perTile} fireflies each");
        return true;
    }

    /// <summary>Winter frost and Halloween now and then; frost on whoever was left alone too long; a fast hour of typing.</summary>
    private void UpdateNowAndThen()
    {
        if (Elapsed < fxNextNowAndThen) return;
        const double step = 30;
        fxNextNowAndThen = Elapsed + step;
        var today = Now().LocalDateTime;
        var awake = Enumerable.Range(0, creatures.Count).Where(k => !hideout.IsInside(k) && !creatures[k].LooksAsleep && !fxOn.ContainsKey(k)).ToList();
        var chance = fxRules.NowAndThenChance(step);
        if (Effects.SeasonOf(today) == Effects.Season.Winter && rng.NextDouble() < chance && awake.Count > 0)
            StyleTrigger(Effects.Trigger.Winter, rng.Pick(awake));
        if (Effects.AroundHalloween(today) && rng.NextDouble() < chance && awake.Count > 0)
            StyleTrigger(Effects.Trigger.Halloween, rng.Pick(awake));
        foreach (var i in awake)
        {
            if (Elapsed - fxMetAt.GetValueOrDefault(i) <= Settings.EffectsAloneMinutes * 60) continue;
            fxMetAt[i] = Elapsed;
            StyleTrigger(Effects.Trigger.LeftAlone, i);
        }
        // Keys typed: only counted by a keyboard hook, never which keys.
        keyCounter ??= KeyCounter.Start();
        if (keyCounter is not null)
        {
            fxTyping.Add(keyCounter.Count, Elapsed);
            if (fxTyping.Fast(Settings.EffectsTypingKeys) && awake.Count > 0)
            {
                fxTyping.Reset();
                StyleTrigger(Effects.Trigger.FastTyping, rng.Pick(awake));
            }
        }
        CheckBudget(Now());
    }

    /// <summary>The day's spend past the budget drops the coins, once a day.</summary>
    private void CheckBudget(DateTimeOffset today)
    {
        var day = ChatLog.Day(today);
        // The summary is today's as of the last call: a call made today, or nothing counts.
        if (fxCoinsDay == day || Spend.Recent.FirstOrDefault() is not { } last || ChatLog.Day(last.Time) != day) return;
        var free = Enumerable.Range(0, creatures.Count).Where(k => !hideout.IsInside(k) && !fxOn.ContainsKey(k)).ToList();
        if (Spend.Summary.Today.Cost < Settings.EffectsDailyBudget || free.Count == 0) return;
        fxCoinsDay = day;
        Mark(Effects.Moment.MoneySpent, rng.Pick(free));
    }

    /// <summary>Two met: neither is alone. A bump between friends may make one smitten; Boo spooks.</summary>
    internal void EffectsMet(int a, int b, bool friends)
    {
        fxMetAt[a] = Elapsed;
        fxMetAt[b] = Elapsed;
        if (friends) StyleTrigger(Effects.Trigger.FriendsMeet, rng.Coin() ? a : b);
        foreach (var x in new[] { a, b })
            if (Settings.SpeciesFor(x) == "ghost") StyleTrigger(Effects.Trigger.BooSpooks, x);
    }

    /// <summary>Dictation or a translation just landed on the clipboard: a burst on <paramref name="i"/>, the helper who
    /// brought it, or on anyone free.</summary>
    public void EffectsCopied(int? i = null)
    {
        var free = Enumerable.Range(0, creatures.Count).Where(k => !hideout.IsInside(k) && !fxOn.ContainsKey(k)).ToList();
        var who = i ?? clipHelp?.Index ?? (free.Count > 0 ? rng.Pick(free) : null);
        if (who is int w) Mark(Effects.Moment.Copied, w);
    }

    /// <summary>The settings changed: a species the colony never had before hatches from an egg.</summary>
    private void EffectsNoticeSpecies()
    {
        var now = Enumerable.Range(0, creatures.Count).Select(Settings.SpeciesFor).ToHashSet();
        if (fxKnownSpecies is { } known)
            for (var i = 0; i < creatures.Count; i++)
                if (known.Add(Settings.SpeciesFor(i))) Mark(Effects.Moment.NewArrival, i);
        fxKnownSpecies = (fxKnownSpecies ?? new()).Union(now).ToHashSet();
    }

    /// <summary>A creature is about to go: a poof where it stood.</summary>
    private void EffectsPoof(int i)
    {
        if (i < 0 || i >= creatures.Count || hideout.IsInside(i) || !fxRules.TakeMoment(Effects.Moment.Poof, null, Elapsed)) return;
        if (MakePlayer(Effects.Moment.Poof.Effect(), i, moment: Effects.Moment.Poof) is not { } player) return;
        var c = creatures[i];
        fxLoose.Add(new LooseEffect(player, DrawnPosition(i), c.Rotation, sizes[i], c.IsMirrored));
        fxOn.Remove(i);
        Trace?.Invoke($"fx {Elapsed:F2} moment poof {CharacterFor(i).Name}");
    }

    /// <summary>Whether any effect is still on show.</summary>
    public bool EffectsShowing => fxOn.Count > 0 || fxLoose.Count > 0 || fxAmbient is not null;

    // MARK: What the overlay draws

    /// <summary>The pictures for creature <paramref name="i"/> this frame, and whether its own sprite is hidden under them.</summary>
    private CreatureEffect? EffectSnapshot(int i, Bitmap? image)
    {
        if (!fxOn.TryGetValue(i, out var p)) return null;
        var body = image is null ? null : fxActors.Pixels(image, p.Box);
        var (back, front, hides) = p.Pictures(body);
        return new CreatureEffect(back, front, p.CellOrigin, p.Size, hides, p.Moment == Effects.Moment.Asleep);
    }

    /// <summary>Effects standing on their own, in global points.</summary>
    private List<LooseEffectSnapshot> LooseEffectSnapshots()
    {
        var made = new List<LooseEffectSnapshot>();
        foreach (var l in fxLoose)
        {
            var (back, front, _) = l.Player.Pictures(null);
            made.Add(new LooseEffectSnapshot(back, front, l.Place, l.Player.CellOrigin, l.Player.Size, l.Scale, l.Rotation, l.Mirrored));
        }
        return made;
    }

    /// <summary>The ambient tiles, each standing on a home monitor's bottom edge, side by side.</summary>
    private List<AmbientTile> AmbientSnapshots()
    {
        var made = new List<AmbientTile>();
        if (fxAmbient is not { } a) return made;
        // The particles drift at their own pace; fifteen pictures a second is plenty and costs half.
        if (fxAmbientImages.Count != a.Tiles.Count || Elapsed >= fxAmbientNextDraw)
        {
            fxAmbientNextDraw = Elapsed + 1.0 / 15;
            foreach (var old in fxAmbientImages) old?.Dispose();
            fxAmbientImages = a.Tiles.Select(t => t.Whole()).ToList();
        }
        var scale = AmbientScale * pixelScale;
        var k = 0;
        foreach (var screen in HomeFrames)
        {
            var x = screen.MinX;
            while (x < screen.MaxX && k < a.Tiles.Count)
            {
                var size = a.Tiles[k].Size;
                made.Add(new AmbientTile(fxAmbientImages[k], new Pt(x, screen.MinY), scale));
                x += size.Width * scale;
                k++;
            }
        }
        return made;
    }

    private sealed record LooseEffect(EffectPlayer Player, Pt Place, double Rotation, double Scale, bool Mirrored);
}

/// <summary>An effect's two pictures on one creature: the frame's top-left in its sprite cell's pixels, its size in pixels.</summary>
public sealed record CreatureEffect(Bitmap? Back, Bitmap? Front, Point Origin, Size Size, bool HidesBody, bool HidesZs);

/// <summary>An effect at a place of its own, the creature it was drawn round gone; <c>Place</c> is where its centre was.</summary>
public sealed record LooseEffectSnapshot(Bitmap? Back, Bitmap? Front, Pt Place, Point Origin, Size Size, double Scale, double Rotation, bool Mirrored);

/// <summary>One tile of the ambient particles, its bottom-left corner on a monitor's bottom edge, <c>Scale</c> screen pixels a pixel.</summary>
public sealed record AmbientTile(Bitmap? Image, Pt BottomLeft, double Scale);
