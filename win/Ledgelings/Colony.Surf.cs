using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The surfing's water for one frame: one picture in square pixels and where it sits, in GLOBAL points, drawn
/// at <c>Opacity</c> behind the creatures. Only drawn, as everything on the glass: clicks go through it.</summary>
public sealed record SurfWaterSnapshot(Bitmap Image, Rect Frame, float Opacity);

/// <summary>Surfing (<see cref="Plays.Surf"/>), the Mac's <c>Colony+Surf</c>: the tide comes in along the widest floor (the
/// screen's bottom edge), everyone who plays leaps there first, and waves roll along it. The players are off their edges
/// (playing) for the whole session and the colony puts each, and its board, where the game says, every frame. The water is
/// drawn in code, a fresh picture each frame in square pixels at the creatures' own scale: flat see-through bands, a
/// 1-pixel dark top, a light line under it, the wave's lip thrown forward over a hollow, foam, and the drops of a splash
/// flying (particles). Boards, splashes and spray come from the play sheet. The scoreboard sits at the top, as in the
/// ball games.</summary>
public sealed partial class Colony
{
    /// <summary>What surfing needs besides the game: drops in the air, splashes, its scale.</summary>
    public sealed class Surfing
    {
        public required double Scale;
        public readonly List<Drop> Drops = new();
        public readonly List<(Pt At, double Since)> Splashes = new();
        /// <summary>Each rider's board on the play sheet.</summary>
        public readonly Dictionary<int, string> Boards = new();

        public sealed class Drop
        {
            public Pt Position;
            public Vec Velocity;
            public double Life;
        }
    }

    /// <summary>The colours of the water, traced flat from the owner's chosen Wixel wave (its soft edges taken off): the
    /// body, the deep band, the top's outline, the light line and the streaks, the foam. Nearly solid here: how much of
    /// the desktop shows through is the owner's, <c>SurfWaterOpacity</c>, laid over it all.</summary>
    private static class SurfWaterColours
    {
        public static readonly int Body = Argb(24, 166, 246, 225);
        public static readonly int Deep = Argb(6, 134, 230, 240);
        public static readonly int Outline = Argb(8, 70, 198, 255);
        public static readonly int Light = Argb(88, 228, 246, 215);
        public static readonly int Foam = Argb(244, 246, 250, 255);
        /// <summary>The lip thrown over the hollow: the body's colour, nearly solid, so it reads against the sky.</summary>
        public static readonly int Lip = Argb(16, 150, 240, 235);

        /// <summary>Premultiplied, as <c>Format32bppPArgb</c> keeps it.</summary>
        private static int Argb(int r, int g, int b, int a) =>
            unchecked((int)((uint)a << 24 | (uint)(r * a / 255) << 16 | (uint)(g * a / 255) << 8 | (uint)(b * a / 255)));
    }

    /// <summary>Last frame's water, let go of once the next one is painted.</summary>
    private Bitmap? surfWaterPicture;

    // MARK: Starting

    /// <summary>Surfing is on the widest floor, as soccer is: everyone leaps there first.</summary>
    private bool BeginSurf(PlaySession session) => BeginSoccer(session);

    /// <summary>Everyone is on the floor: the tide comes in.</summary>
    private bool StartSurf(PlaySession session)
    {
        if (session.Pitch is not { } pitch) return false;
        var players = session.Players;
        var halves = new Dictionary<int, double>();
        var at = new Dictionary<int, double>();
        foreach (var p in players)
        {
            halves[p] = BodyHalf(p);
            at[p] = creatures[p].Position.X;
            creatures[p].TakeOff();
        }
        var scale = players.Average(p => sizes[p]);
        var body = players.Average(p => BodyHalf(p) * 2);
        session.Surf = new Plays.Surf(players, halves, at, pitch.FloorY, pitch.From, pitch.To,
                                      body * Settings.SurfWaveHeight, body * AppSettings.SurfDepth,
                                      Settings.SurfWaves, Settings.SurfMinutes * 60, rng);
        var surfing = new Surfing { Scale = scale };
        foreach (var p in players) surfing.Boards[p] = $"board-{Plays.Surf.Board(PlayerName(p))}";
        session.Surfing = surfing;
        var w = creatures[players[0]].World;
        session.BallGame = new BallGame
        {
            BoardAt = BoardPlace(new Pt((pitch.From + pitch.To) / 2, pitch.FloorY + BodyHalf(players[0])), w, BodyHalf(players[0])),
            Scale = scale, Bounds = BoundsOf(w, BodyHalf(players[0])),
        };
        Trace?.Invoke("play surf boards: " + string.Join(", ", players.Select(p => $"{PlayerName(p)} {surfing.Boards[p]}")));
        return true;
    }

    // MARK: Running

    private void RunSurf(PlaySession s, double dt)
    {
        if (s.Surf is not { } game || !s.Players.All(p => creatures[p].IsPlaying)) { EndPlay(false); return; }
        foreach (var e in game.Update(dt, rng)) SurfEvent(e, game, s);
        foreach (var r in game.Riders)
        {
            creatures[r.Index].Face(r.Facing);
            creatures[r.Index].Carry(new Pt(r.X, r.Y), r.Rotation, r.Pose);
        }
        RunDrops(s, dt);
        RunExtras(s);
        if (game.IsFinished)
        {
            Trace?.Invoke($"play surf over: {game.Board(PlayerName)}");
            foreach (var p in s.Players) creatures[p].TouchDown(double.PositiveInfinity);
            var best = game.Winners.Count > 0 ? game.Winners[0] : s.Players[0];
            WrapUp(s, best);
        }
    }

    private void SurfEvent(Plays.Surf.Event e, Plays.Surf game, PlaySession s)
    {
        switch (e)
        {
            case Plays.Surf.Event.TideIn: Trace?.Invoke("play surf the tide comes in"); break;
            case Plays.Surf.Event.Wave w: Trace?.Invoke($"play surf wave {w.Number} rolls in {(w.Way > 0 ? "left to right" : "right to left")}"); break;
            case Plays.Surf.Event.Caught c:
                Trace?.Invoke($"play surf {PlayerName(c.By)} catches the wave");
                BallLine(Plays.Moment.Wave, c.By, s, game.Board(PlayerName));
                break;
            case Plays.Surf.Event.Missed m: Trace?.Invoke($"play surf {PlayerName(m.By)} lets it roll by"); break;
            case Plays.Surf.Event.Landed l:
                Trace?.Invoke($"play surf {PlayerName(l.By)} lands a {l.Trick.ToString().ToLowerInvariant()}");
                BallLine(Plays.Moment.Trick, l.By, s, game.Board(PlayerName));
                break;
            case Plays.Surf.Event.Wipeout wo:
                Trace?.Invoke($"play surf {PlayerName(wo.By)} wipes out at {wo.At.X:F0}");
                Splash(wo.At, s);
                Cheer(L10n.Tr("WIPEOUT!"), new Pt(wo.At.X, wo.At.Y + 140 * (s.Surfing?.Scale ?? 2.5) / 2.5), s);
                BallLine(Plays.Moment.Wipeout, wo.By, s, game.Board(PlayerName));
                break;
            case Plays.Surf.Event.KickOut k: Trace?.Invoke($"play surf {PlayerName(k.By)} rides it out: {k.Points} points"); break;
            case Plays.Surf.Event.Back b: Trace?.Invoke($"play surf {PlayerName(b.By)} waits for a wave"); break;
            case Plays.Surf.Event.TideOut: Trace?.Invoke("play surf the tide goes out"); break;
            case Plays.Surf.Event.Won won:
                Trace?.Invoke($"play surf won by {(won.By.Count == 0 ? "nobody" : string.Join(" and ", won.By.Select(PlayerName)))}");
                if (won.By.Count > 0) BallLine(Plays.Moment.SurfWin, won.By[0], s, game.Board(PlayerName));
                break;
        }
    }

    /// <summary>A splash: the sheet's crown rising and falling, and drops flying out of it.</summary>
    private void Splash(Pt point, PlaySession s)
    {
        if (s.Surfing is not { } surfing) return;
        surfing.Splashes.Add((point, Elapsed));
        for (int k = 0; k < 14; k++)
        {
            var v = new Vec(rng.Range(-160, 160), rng.Range(160, 380));
            surfing.Drops.Add(new Surfing.Drop { Position = point, Velocity = v, Life = rng.Range(0.6, 1.1) });
        }
    }

    private void RunDrops(PlaySession s, double dt)
    {
        if (s.Surfing is not { } surfing || s.Surf is not { } game) return;
        foreach (var d in surfing.Drops)
        {
            d.Velocity = d.Velocity with { Dy = d.Velocity.Dy - Plays.Gravity * 0.6 * dt };
            d.Position = new Pt(d.Position.X + d.Velocity.Dx * dt, d.Position.Y + d.Velocity.Dy * dt);
            d.Life -= dt;
        }
        surfing.Drops.RemoveAll(d => d.Life <= 0 || (d.Velocity.Dy < 0 && d.Position.Y < game.Surface(d.Position.X)));
        // Spray off the lip of a wave someone rides.
        if (game.Wave is { } wave && game.Riders.Any(r => r.IsRiding) && rng.NextDouble() < dt * 12)
        {
            var top = new Pt(wave.Crest + game.Way * game.Height * 0.5, game.Surface(wave.Crest) - game.Height * 0.4);
            surfing.Drops.Add(new Surfing.Drop
            {
                Position = top, Velocity = new Vec(game.Way * rng.Range(60, 160), rng.Range(40, 160)), Life = rng.Range(0.4, 0.8),
            });
        }
        surfing.Splashes.RemoveAll(x => Elapsed - x.Since > 0.6);
    }

    /// <summary>Stop surfing at once (Stop activity): the water, the boards and the scoreboard go, everyone back on the edge.</summary>
    public void StopSurf()
    {
        if (play?.Kind != Plays.Kind.Surf) return;
        EndPlay(false);
        fadingBoard = null;
    }

    // MARK: Drawing

    private List<PropSnapshot> SurfProps(PlaySession s)
    {
        var props = new List<PropSnapshot>();
        if (s.Surf is not { } game || s.Surfing is not { } surfing) return props;
        Bitmap? Image(string animation, double time = 0) => playFrames.Frame(animation, time);
        var scale = surfing.Scale;
        foreach (var r in game.Riders)
        {
            var name = surfing.Boards.TryGetValue(r.Index, out var b) ? b : "board-0";
            props.Add(new PropSnapshot(Image(name), r.Board, r.BoardRotation, scale, Mirrored: r.Facing < 0));
            if (r.IsRiding)
            {
                var tail = new Pt(r.Board.X - r.Facing * 12 * scale, r.Board.Y + 3 * scale);
                props.Add(new PropSnapshot(Image("spray", Elapsed), tail, 0, scale, Mirrored: r.Facing < 0, InFront: true));
            }
        }
        foreach (var (at, since) in surfing.Splashes)
        {
            // The crown's pool sits on the cell's bottom rows: lift the cell so it sits on the water.
            var big = scale * 1.6;
            var lifted = new Pt(at.X, at.Y + (PlayCell.Height / 2.0 - 2) * big);
            props.Add(new PropSnapshot(Image("splash", Elapsed - since), lifted, 0, big, InFront: true));
        }
        return props;
    }

    /// <summary>The surfing's water this frame, or null when there is none (no surf, or the tide all the way out).</summary>
    internal SurfWaterSnapshot? SurfWater()
    {
        surfWaterPicture?.Dispose();
        surfWaterPicture = null;
        if (play is not { Surf: { } game, Surfing: { } surfing }) return null;
        if (SurfWaterImage(game, surfing) is not { } made) return null;
        surfWaterPicture = made.Image;
        return new SurfWaterSnapshot(made.Image, made.Frame, (float)(Settings.SurfWaterOpacity / 100));
    }

    /// <summary>The water as one picture in square pixels, <c>Scale</c> points each: from the screen's floor up to the
    /// wave's top and the drops above it. The Mac's <c>waterImage</c>, pixel for pixel.</summary>
    private (Bitmap Image, Rect Frame)? SurfWaterImage(Plays.Surf g, Surfing surfing)
    {
        if (g.Tide <= 0) return null;
        var scale = surfing.Scale;
        double x0 = g.From - 30, x1 = g.To + 30;
        int w = (int)Math.Ceiling((x1 - x0) / scale), h = (int)Math.Ceiling((g.Depth + g.Height * 2.2) / scale) + 4;
        if (w <= 0 || h <= 0 || (long)w * h >= 4_000_000) return null;
        var pixels = new int[w * h];
        void Put(int x, int y, int c)
        {
            if (x < 0 || x >= w || y < 0 || y >= h) return;
            pixels[(h - 1 - y) * w + x] = c;
        }
        int Px(double xPoints) => (int)Math.Floor((xPoints - x0) / scale);
        static int Rounded(double v) => (int)Math.Round(v, MidpointRounding.AwayFromZero);
        var deep = Math.Max(1, (int)(g.Depth * g.Tide / scale / 2));
        var frame = (int)(Elapsed * 8);
        uint Noise(int a, int b)
        {
            var z = unchecked((uint)a * 73_856_093u ^ (uint)b * 19_349_663u ^ (uint)frame * 83_492_791u);
            z ^= z >> 13;
            z = unchecked(z * 0x5bd1e995u);
            z ^= z >> 15;
            return z % 100;
        }
        var tops = new int[w];
        for (int x = 0; x < w; x++)
        {
            var xp = x0 + (x + 0.5) * scale;
            var top = Rounded((g.Surface(xp) - g.FloorY) / scale);
            tops[x] = top;
            if (top <= 0) continue;
            // The wave's body carries light streaks slanting up toward the crest, as the chosen wave does.
            var rising = g.LiftAt(xp) > 2 * scale;
            for (int y = 0; y < top; y++)
            {
                var streak = rising && y > top * 2 / 5 && y < top - 3 && ((x * (g.Way > 0 ? 1 : -1) + y * 2) % 17 + 17) % 17 < 2;
                Put(x, y, streak ? SurfWaterColours.Light : y < deep ? SurfWaterColours.Deep : SurfWaterColours.Body);
            }
            Put(x, top - 1, SurfWaterColours.Outline);
            if (top - 2 >= deep) Put(x, top - 2, SurfWaterColours.Light);
        }
        // Little ripples on the calm water, drifting.
        for (int x = frame / 2 % 11; x < w; x += 11)
        {
            if (g.LiftAt(x0 + x * scale) != 0 || tops[x] <= 3) continue;
            Put(x, tops[x] - 2, SurfWaterColours.Foam); Put(x + 1, tops[x] - 2, SurfWaterColours.Foam);
        }
        if (g.Wave is { } wave)
        {
            int c = Px(wave.Crest), way = g.Way > 0 ? 1 : -1;
            int height = (int)(g.Height * g.Tide / scale), lift = (int)(g.LiftAt(wave.Crest) / scale);
            var top = c >= 0 && c < w ? tops[c] : (int)((g.Depth + g.Height) / scale);
            // The lip, thrown forward off the crest and drooping, a hollow under it.
            var length = Math.Max(3, (int)(height * 0.6));
            if (lift > 4)
            {
                for (int k = 0; k <= length; k++)
                {
                    var u = (double)k / length;
                    var y = top + 1 - (int)(u * u * height * 0.4);
                    var thick = Math.Max(3, (int)(7 * (1 - u)) + 3);
                    var x = c + way * k;
                    Put(x, y, SurfWaterColours.Outline);
                    for (int t = 0; t < thick; t++)
                        Put(x, y - 1 - t, t < 2 ? SurfWaterColours.Foam : t < 4 ? SurfWaterColours.Light : SurfWaterColours.Lip);
                    Put(x, y - thick - 1, SurfWaterColours.Outline);
                }
                // The tip curls back under, toward the face: a hook of foam.
                var (tipX, tipY) = (c + way * length, top + 1 - (int)(height * 0.4));
                for (int k = 1; k <= Math.Max(1, height / 6); k++)
                {
                    Put(tipX - way * (k / 2), tipY - 1 - k, SurfWaterColours.Foam);
                    Put(tipX - way * (k / 2) + way, tipY - 1 - k, SurfWaterColours.Outline);
                }
                for (int k = 0; k < 6; k++)
                    if (Noise(k, 1) < 70) Put(tipX + way * (int)(Noise(k, 2) % 5), tipY - 2 - (int)(Noise(k, 3) % 8), SurfWaterColours.Foam);
            }
            // Foam along the crest's back, and whitewater at the foot of the face.
            int back = (int)(g.BackWidth * 0.35 / scale), face = (int)(g.FaceWidth / scale);
            for (int k = -back; k <= 0; k++)
            {
                var x = c + way * k;
                if (x < 0 || x >= w || tops[x] <= 2) continue;
                if (Noise(x, 4) < 60) Put(x, tops[x] - 1, SurfWaterColours.Foam);
                if (Noise(x, 5) < 30) Put(x, tops[x] - 2, SurfWaterColours.Foam);
                if (Noise(x, 6) < 10) Put(x, tops[x], SurfWaterColours.Foam);
            }
            int from = (int)(face * 0.55), to = Math.Max(from, (int)(face * 1.05));
            for (int k = from; k <= to; k++)
            {
                var x = c + way * k;
                if (x < 0 || x >= w || tops[x] <= 2) continue;
                if (Noise(x, 7) < 50) Put(x, tops[x] - 1, SurfWaterColours.Foam);
            }
        }
        // The drops, two pixels each.
        foreach (var d in surfing.Drops)
        {
            int x = Px(d.Position.X), y = Rounded((d.Position.Y - g.FloorY) / scale);
            Put(x, y, SurfWaterColours.Foam); Put(x + 1, y, SurfWaterColours.Light); Put(x, y - 1, SurfWaterColours.Light);
        }
        var bitmap = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
        var data = bitmap.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
        for (int row = 0; row < h; row++) Marshal.Copy(pixels, row * w, data.Scan0 + row * data.Stride, w);
        bitmap.UnlockBits(data);
        return (bitmap, new Rect(x0, g.FloorY, w * scale, h * scale));
    }
}
