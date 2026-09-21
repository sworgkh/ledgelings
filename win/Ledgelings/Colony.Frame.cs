using System.Windows.Threading;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Reacting to change, and the frame itself.</summary>
public sealed partial class Colony
{
    private bool applying;

    private void ApplySettings()
    {
        if (applying) return;      // KeepSpecies below may fire Changed; the outer pass reads the result anyway
        applying = true;
        try
        {
            dayNight = new DayNight(Settings.DayMinutes * 60, Settings.NightMinutes * 60);
            Settings.KeepSpecies(Library.AllSpecies.Select(s => s.Name).ToList());

            if (held is { } h && h.Index >= Settings.CreatureCount) LetGo();
            while (creatures.Count > Settings.CreatureCount)
            {
                var last = creatures.Count - 1;
                creatures.RemoveAt(last); asleepFor.RemoveAt(last); sizeShares.RemoveAt(last); sizes.RemoveAt(last);
            }
            gifts.Forget(creatures.Count);
            while (creatures.Count < Settings.CreatureCount)
            {
                var share = rng.NextDouble();
                var size = Settings.SizeForShare(share) * pixelScale;
                creatures.Add(Spawn(size)); asleepFor.Add(0); sizeShares.Add(share); sizes.Add(size);
            }
            for (int i = 0; i < creatures.Count; i++)
            {
                var size = Settings.SizeForShare(sizeShares[i]) * pixelScale;
                if (size == sizes[i]) continue;
                sizes[i] = size;
                creatures[i].Rehome(World(size));
                creatures[i].Settings.FleeRadius = FleeRadius(size);
            }

            frames.Clear();
            for (int i = 0; i < creatures.Count; i++)
            {
                var name = Settings.SpeciesFor(i);
                var colour = Library.BodyColour(name, Settings.ColorFor(i));
                var key = name + " " + colour.Hex;
                if (!frameCache.TryGetValue(key, out var made))
                {
                    made = (Library.Atlas(name) ?? atlas).MakeFrames(colour);
                    frameCache[key] = made;
                }
                frames.Add(made);
            }
        }
        finally { applying = false; }
        Render();
    }

    private void ScreensChanged()
    {
        RebuildOverlays();
        worlds.Clear();
        for (int i = 0; i < creatures.Count; i++) creatures[i].Rehome(World(sizes[i]));
        ApplySettings();      // the pixel scale may have changed with the primary monitor
    }

    private EdgeWorld World(double size)
    {
        if (worlds.TryGetValue(size, out var made)) return made;
        made = new EdgeWorld(monitors.Select(m => m.Frame).ToList(), atlas.BodyHalfSize * size);
        worlds[size] = made;
        return made;
    }

    /// <summary>Measured from the creature's centre, so a big one needs a bigger bubble
    /// to feel equally skittish.</summary>
    private double FleeRadius(double size) => atlas.BodyHalfSize * size + 68;

    private void RebuildOverlays()
    {
        clock?.Dispose();
        clock = null;
        foreach (var o in overlays) o.Dispose();
        overlays.Clear();
        monitors = Desktop.Monitors();
        pixelScale = Desktop.PixelScale;
        foreach (var m in monitors)
        {
            var overlay = new ScreenOverlay(m);
            overlay.Hand += Hand;
            overlays.Add(overlay);
        }
        LetGo();
        lastTick = null;
        if (overlays.Count == 0) return;
        clock = new FrameClock(Dispatcher.CurrentDispatcher, Tick);
        SetFrameRate(false);
    }

    private Creature Spawn(double size)
    {
        var world = World(size);
        var place = rng.Pick(world.Segments);
        var t = world.Loops[place.Loop].T(place.Segment, rng.Range(0.1, 0.9));
        var config = new Creature.Config { WalkSpeed = rng.Range(38, 72), FleeRadius = FleeRadius(size) };      // no two walk in lockstep
        return new Creature(world, new EdgeWorld.Spot(place.Loop, t), rng.Coin(), config);
    }

    // MARK: The frame

    private void Tick()
    {
        var now = stopwatch.Elapsed.TotalSeconds;
        if (lastTick is not double last) { lastTick = now; return; }
        var dt = Math.Min(now - last, MaxStep);
        lastTick = now;
        Elapsed += dt;

        var night = IsNight;
        var cursor = Desktop.Cursor();          // global, and needs no permission
        // Holding Shift calms them: nobody flees, so you can get close enough to click.
        var shift = Desktop.IsShiftDown;
        for (int i = 0; i < creatures.Count; i++)
        {
            if (hideout.IsInside(i)) continue;
            creatures[i].Update(dt, shift || hideout.IsActive ? null : cursor, night, rng);
            asleepFor[i] = creatures[i].LooksAsleep ? asleepFor[i] + dt : 0;
        }
        UpdateHideout();
        UpdateClickability(cursor, shift);

        foreach (var i in bubbles.Where(b => b.Value.Until <= Elapsed || b.Key >= creatures.Count).Select(b => b.Key).ToList()) bubbles.Remove(i);
        gifts.Update(Elapsed, Settings.FlowerMinutes * 60);
        if (Settings.FollowGiver) FollowGivers();
        sparks.Update(dt);
        ReleaseChatIfOver();
        foreach (var bump in meetings.Update(Parties(), Elapsed)) Bumped(bump);
        Render();
        SetFrameRate(hideout.CurrentPhase == Hideout.Phase.Hidden || (held is null && creatures.Count > 0 && creatures.All(c => c.IsSleeping)));
    }

    /// <summary>A sleeping colony only breathes and floats Zs: 12 fps is plenty.</summary>
    private void SetFrameRate(bool asleep)
    {
        if (clock is not null) clock.Fps = asleep ? 12 : 30;
    }
}
