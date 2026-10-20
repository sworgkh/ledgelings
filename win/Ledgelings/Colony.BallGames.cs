using System.Drawing;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Soccer and baseball (<see cref="Plays.Soccer"/>, <see cref="Plays.Baseball"/>): a game for however many
/// are free, closest friends joining first. Soccer is played on the widest floor, the players leaping there first;
/// baseball on every edge, the game hopping everyone to their places itself. The players are off their edges
/// (playing) for the whole game and the colony puts each where the game says, every frame; a scoreboard in pixel
/// letters sits at the top of the screen while it lasts and fades after. The Mac's <c>Colony+BallGames</c>.</summary>
public sealed partial class Colony
{
    /// <summary>Everything a ball game needs besides the game itself.</summary>
    public sealed class BallGame
    {
        /// <summary>A cheer across the screen ("GOAL!"), from <c>Since</c> until <c>Until</c>.</summary>
        public (Bitmap? Image, Size Size, Pt At, double Since, double Until)? Banner;
        /// <summary>Fireworks still to go off, by when.</summary>
        public List<(double At, Pt Point)> Fireworks = new();
        /// <summary>Where the scoreboard goes: the top of the screen the game is on.</summary>
        public required Pt BoardAt;
        public required double Scale;
        /// <summary>The screens the game is on, to keep a cheer inside them.</summary>
        public Rect? Bounds;
        /// <summary>Who has had an "oops" or wandered off already: once a game each.</summary>
        public HashSet<string> Said = new();
    }

    private const double BoardShown = 3.0;

    /// <summary>When each ball game last ended, on the colony's clock: each may start only every so often.</summary>
    private readonly Dictionary<Plays.Kind, double> ballGameEnded = new();
    /// <summary>The scoreboard of the ball game just over, fading out until <c>Until</c>.</summary>
    private (PropSnapshot Prop, double Until)? fadingBoard;
    /// <summary>When the last line of a ball game was said: small moments keep quiet if one was just said.</summary>
    private double lastBallLine = -100;
    /// <summary>Pixel text drawn once per wording (<see cref="PixelText"/>).</summary>
    private readonly Dictionary<string, Bitmap?> pixelTexts = new();

    private double BodyHalf(int i) => atlas.BodyHalfSize * sizes[i];

    /// <summary>The ball games that may start now: on, and not played too lately.</summary>
    internal IReadOnlySet<Plays.Kind> BallGamesDue => BallGamesDueAt(Settings, ballGameEnded, Elapsed);

    /// <summary>The ball games <paramref name="settings"/> lets start at <paramref name="now"/>, each having last ended
    /// at <paramref name="ended"/> on the same clock (never, if missing).</summary>
    public static IReadOnlySet<Plays.Kind> BallGamesDueAt(AppSettings settings, IReadOnlyDictionary<Plays.Kind, double> ended, double now) =>
        Plays.AllKinds.Where(kind => kind.IsTeamGame() && settings.EnabledPlays.Contains(kind)
            && (!ended.TryGetValue(kind, out var at) || now - at >= settings.BallGameEvery(kind) * 60)).ToHashSet();

    /// <summary>Everyone else free to play, wherever they are, with how close each is to <paramref name="i"/>.</summary>
    private List<(int Index, double Closeness)> Crowd(int i) =>
        Enumerable.Range(0, creatures.Count).Where(j => j != i && FreeToPlay(j)).Select(j => (j, Closeness(i, j))).ToList();

    /// <summary>Two sides for team play, friends together, and their keepers (soccer, from six).</summary>
    private (int[][] Teams, HashSet<int> Keepers) TeamSides(int[] players, bool keepers)
    {
        var teams = Plays.Split(players, Closeness);
        if (!keepers || players.Length < 6) return (teams, new HashSet<int>());
        return (teams, teams.Select(t => Plays.Keeper(t, Closeness)).OfType<int>().ToHashSet());
    }

    // MARK: Starting

    /// <summary>The pitch for soccer, and everyone leaping onto it, spread along it.</summary>
    private bool BeginSoccer(PlaySession session)
    {
        var i = session.Players[0];
        if (Plays.Pitch.Choose(creatures[i].World, BodyHalf(i)) is not { } pitch) return false;
        var n = session.Players.Length;
        for (int k = 0; k < n; k++)
        {
            var p = session.Players[k];
            var w = creatures[p].World;
            var x = pitch.From + pitch.Length * (0.2 + 0.6 * (k + 0.5) / n);
            if (w.Floor(new Pt(x, pitch.FloorY + BodyHalf(p) + 1)) is not { } level
                || Math.Abs(level.Y - (pitch.FloorY + BodyHalf(p))) >= 2) return false;
            if (!OnPitch(p, pitch)) session.Reaching[p] = SpotOn(level, x, p);
        }
        session.Pitch = pitch;
        return true;
    }

    private bool OnPitch(int p, Plays.Pitch pitch)
    {
        var c = creatures[p];
        return c.Loop.Direction(c.Segment).Dx > 0.5 && Math.Abs(c.Position.Y - (pitch.FloorY + BodyHalf(p))) < 2
            && pitch.Covers(c.Position.X);
    }

    /// <summary>Everyone is on the pitch: the match begins.</summary>
    private bool StartSoccer(PlaySession session)
    {
        if (session.Pitch is not { } pitch) return false;
        var players = session.Players;
        var lineup = players.Length >= 4 ? TeamSides(players, true) : (Array.Empty<int[]>(), new HashSet<int>());
        var halves = new Dictionary<int, double>();
        var at = new Dictionary<int, double>();
        foreach (var p in players)
        {
            halves[p] = BodyHalf(p);
            at[p] = creatures[p].Position.X;
            creatures[p].TakeOff();
        }
        var scale = players.Average(p => sizes[p]);
        session.Soccer = new Plays.Soccer(players, lineup.Item1.Length == 0 ? null : lineup.Item1, lineup.Item2, halves, at, pitch, scale,
                                          Settings.SoccerGoals, Settings.SoccerMinutes * 60, rng);
        var w = creatures[players[0]].World;
        session.BallGame = new BallGame
        {
            BoardAt = BoardPlace(new Pt((pitch.From + pitch.To) / 2, pitch.FloorY + BodyHalf(players[0])), w, BodyHalf(players[0])),
            Scale = scale, Bounds = BoundsOf(w, BodyHalf(players[0])),
        };
        if (lineup.Item1.Length > 0)
            Trace?.Invoke("play soccer teams: " + string.Join(" v ", lineup.Item1.Select(t => string.Join(", ", t.Select(PlayerName))))
                          + (lineup.Item2.Count == 0 ? "" : "; in goal " + string.Join(" and ", lineup.Item2.Select(PlayerName).Order(StringComparer.Ordinal))));
        return true;
    }

    /// <summary>The field for baseball, from where the first player stands; the game takes it from there.</summary>
    private bool BeginBaseball(PlaySession session)
    {
        var i = session.Players[0];
        if (Plays.Field.Choose(creatures[i].World, BodyHalf(i), creatures[i].Spot) is not { } field) return false;
        var players = session.Players;
        var halves = new Dictionary<int, double>();
        var starts = new Dictionary<int, Plays.Place>();
        foreach (var p in players)
        {
            halves[p] = BodyHalf(p);
            starts[p] = Plays.Place.At(creatures[p].Spot, creatures[p].World, BodyHalf(p));
        }
        var teams = players.Length >= 6 ? TeamSides(players, false).Teams : null;
        var mood = CursorMoods.Current switch { CursorMood.Good => 0.5, CursorMood.Neutral => 0.0, _ => -0.4 };
        session.Baseball = new Plays.Baseball(players, teams, starts, halves, field, Settings.BaseballInnings, mood, Closeness);
        var scale = players.Average(p => sizes[p]);
        var middle = new[] { field.Home }.Concat(field.Bases).Average(b => b.Edge.X);
        // Under the ceiling, clear of a base there and whoever stands on it.
        session.BallGame = new BallGame
        {
            BoardAt = new Pt(middle, field.Top - 110 * scale / 2.5), Scale = scale, Bounds = BoundsOf(creatures[i].World, BodyHalf(i)),
        };
        foreach (var p in players) creatures[p].TakeOff();
        session.Now = PlaySession.Stage.On;
        if (teams is not null)
            Trace?.Invoke("play baseball teams: " + string.Join(" v ", teams.Select(t => string.Join(", ", t.Select(PlayerName)))));
        Trace?.Invoke("play baseball bases: " + string.Join(" ", new[] { field.Home }.Concat(field.Bases).Select(b => $"({b.Edge.X:F0}, {b.Edge.Y:F0})")));
        return true;
    }

    /// <summary>Round every screen of <paramref name="world"/>.</summary>
    private static Rect? BoundsOf(EdgeWorld world, double inset)
    {
        var points = world.Loops.SelectMany(l => l.Vertices).ToList();
        if (points.Count == 0) return null;
        double x0 = points.Min(p => p.X), x1 = points.Max(p => p.X), y0 = points.Min(p => p.Y), y1 = points.Max(p => p.Y);
        return new Rect(x0 - inset, y0 - inset, x1 - x0 + inset * 2, y1 - y0 + inset * 2);
    }

    /// <summary>Just under the top of the screen over <paramref name="point"/>.</summary>
    private static Pt BoardPlace(Pt point, EdgeWorld world, double inset)
    {
        var top = world.Ceiling(point) is { } c ? c.Y + inset : point.Y + 500;
        return new Pt(point.X, top - 24);
    }

    private string PlayerName(int i) => i >= 0 && i < creatures.Count ? CharacterFor(i).Name : "?";

    // MARK: Running

    private void RunSoccer(PlaySession s, double dt)
    {
        if (s.Soccer is not { } match || !s.Players.All(p => creatures[p].IsPlaying)) { EndPlay(false); return; }
        foreach (var e in match.Update(dt, rng)) SoccerEvent(e, match, s);
        foreach (var p in match.Players)
        {
            var at = new Pt(p.X, match.Pitch.FloorY + p.Half + p.Lift);
            creatures[p.Index].Face(p.Facing);
            creatures[p.Index].Carry(at, p.Rotation, p.Pose);
        }
        RunExtras(s);
        if (match.IsFinished)
        {
            var best = match.GoalsBy.Count > 0 ? match.GoalsBy.MaxBy(g => g.Value).Key : s.Players[0];
            Trace?.Invoke($"play soccer over: {match.Board(PlayerName)}");
            foreach (var p in s.Players) creatures[p].TouchDown(double.PositiveInfinity);
            WrapUp(s, best);
        }
    }

    private void SoccerEvent(Plays.Soccer.Event e, Plays.Soccer match, PlaySession s)
    {
        switch (e)
        {
            case Plays.Soccer.Event.Kickoff k: Trace?.Invoke($"play soccer {PlayerName(k.By)} kicks off"); break;
            case Plays.Soccer.Event.Touches t: Trace?.Invoke($"play soccer {PlayerName(t.By)} keepy-uppy: {t.Count} touches"); break;
            case Plays.Soccer.Event.Pass p: Trace?.Invoke($"play soccer {PlayerName(p.From)} passes to {PlayerName(p.To)}"); break;
            case Plays.Soccer.Event.Shot sh: Trace?.Invoke($"play soccer {PlayerName(sh.By)} shoots"); break;
            case Plays.Soccer.Event.Header h: Trace?.Invoke($"play soccer {PlayerName(h.By)} heads it"); break;
            case Plays.Soccer.Event.Goal g:
            {
                var score = SoccerScore(match);
                Trace?.Invoke($"play soccer {PlayerName(g.By)} scores {score}");
                var ballX = match.TheBall.Position.X;
                var goal = match.Goals.Count == 0 ? null : match.Goals.MinBy(x => Math.Abs(x.X - ballX));
                // High over the goal, clear of the scorer's bubble.
                var at = new Pt(goal is { } gl ? gl.X - gl.Side * 160 : ballX, match.Pitch.FloorY + 230 * (s.BallGame?.Scale ?? 2.5) / 2.5);
                Cheer(L10n.Tr("GOAL!"), at, s);
                for (int k = 0; k < 3; k++)
                    sparks.Burst(new Pt((goal?.X ?? at.X) + (k - 1) * 14, match.Pitch.FloorY + 30), new Vec(0, 1), 8, rng);
                BallLine(Plays.Moment.Goal, g.By, s, score);
                break;
            }
            case Plays.Soccer.Event.Save sv: Trace?.Invoke($"play soccer {PlayerName(sv.By)} saves"); break;
            case Plays.Soccer.Event.Woodwork w: Trace?.Invoke($"play soccer {PlayerName(w.By)} hits the bar"); break;
            case Plays.Soccer.Event.Whiff wf:
                Trace?.Invoke($"play soccer {PlayerName(wf.By)} kicks the air");
                BallLine(Plays.Moment.Oops, wf.By, s, SoccerScore(match));
                break;
            case Plays.Soccer.Event.Tackle t: Trace?.Invoke($"play soccer {PlayerName(t.By)} slides in and takes it off {PlayerName(t.From)}"); break;
            case Plays.Soccer.Event.Out o: Trace?.Invoke("play soccer out" + (o.By is int by ? $" off {PlayerName(by)}" : "")); break;
            case Plays.Soccer.Event.ThrowIn ti: Trace?.Invoke($"play soccer {PlayerName(ti.By)} throws it in"); break;
            case Plays.Soccer.Event.WandersOff wo:
                Trace?.Invoke($"play soccer {PlayerName(wo.Index)} wanders off");
                BallLine(Plays.Moment.Wander, wo.Index, s, SoccerScore(match));
                break;
            case Plays.Soccer.Event.ComesBack cb: Trace?.Invoke($"play soccer {PlayerName(cb.Index)} comes back"); break;
            case Plays.Soccer.Event.KeeperNow kn: Trace?.Invoke($"play soccer {PlayerName(kn.Index)} goes in goal"); break;
        }
    }

    /// <summary>The score in short: "2-1" for two sides, each player's goals otherwise.</summary>
    private static string SoccerScore(Plays.Soccer match) => match.Lineup switch
    {
        Plays.Lineup.Solo => $"{match.GoalsBy.Values.Sum()}",
        Plays.Lineup.Keeper => string.Join("-", match.Players.Select(p => $"{match.GoalsBy.GetValueOrDefault(p.Index)}")),
        _ => $"{match.TeamGoals[0]}-{match.TeamGoals[1]}",
    };

    private void RunBaseball(PlaySession s, double dt)
    {
        if (s.Baseball is not { } game || !s.Players.All(p => creatures[p].IsPlaying)) { EndPlay(false); return; }
        foreach (var e in game.Update(dt, rng)) BaseballEvent(e, game, s);
        foreach (var p in s.Players)
        {
            if (game.PoseOf(p) is not { } pose) continue;
            creatures[p].Face(pose.Facing);
            creatures[p].Carry(pose.Position, pose.Rotation, pose.Pose);
        }
        RunExtras(s);
        if (game.IsFinished)
        {
            var best = game.RunsBy.Count > 0 ? game.RunsBy.MaxBy(r => r.Value).Key : s.Players[0];
            Trace?.Invoke($"play baseball over: {game.Board(PlayerName)}");
            foreach (var p in s.Players) creatures[p].TouchDown(double.PositiveInfinity);
            WrapUp(s, best);
        }
    }

    private void BaseballEvent(Plays.Baseball.Event e, Plays.Baseball game, PlaySession s)
    {
        string[] bases = { "first", "second", "third", "home" };
        string Base(int n) => bases[Math.Min(3, Math.Max(0, n - 1))];
        switch (e)
        {
            case Plays.Baseball.Event.Pitch p: Trace?.Invoke($"play baseball {PlayerName(p.By)} pitches"); break;
            case Plays.Baseball.Event.Toss t: Trace?.Invoke($"play baseball {PlayerName(t.By)} tosses it up"); break;
            case Plays.Baseball.Event.Swung sw: Trace?.Invoke($"play baseball {PlayerName(sw.By)} swings: {sw.Result.ToString().ToLowerInvariant()}"); break;
            case Plays.Baseball.Event.Strike st: Trace?.Invoke($"play baseball {PlayerName(st.By)} strike {st.Count}"); break;
            case Plays.Baseball.Event.Out o:
                Trace?.Invoke($"play baseball {PlayerName(o.By)} is out, {o.How}");
                if (o.How == "struck out") BallLine(Plays.Moment.Oops, o.By, s, BaseballScore(game));
                break;
            case Plays.Baseball.Event.Caught c: Trace?.Invoke($"play baseball {PlayerName(c.By)} catches it"); break;
            case Plays.Baseball.Event.Fumble f:
                Trace?.Invoke($"play baseball {PlayerName(f.By)} drops it");
                BallLine(Plays.Moment.Oops, f.By, s, BaseballScore(game));
                break;
            case Plays.Baseball.Event.Runs r: Trace?.Invoke($"play baseball {PlayerName(r.By)} runs to {Base(r.To)}"); break;
            case Plays.Baseball.Event.Safe sa: Trace?.Invoke($"play baseball {PlayerName(sa.By)} is safe at {Base(sa.At)}"); break;
            case Plays.Baseball.Event.Scored sc:
                Trace?.Invoke($"play baseball {PlayerName(sc.By)} scores {(game.Lineup == Plays.Lineup.Solo ? $"{game.Hits}" : sc.Score)}");
                break;
            case Plays.Baseball.Event.HomeRun hr:
            {
                Trace?.Invoke($"play baseball HOME RUN {PlayerName(hr.By)}, {hr.RunsIn} in");
                var exit = game.LastHomeRun ?? game.Field.Home.Edge;
                Cheer(L10n.Tr("HOME RUN!"), new Pt(exit.X, exit.Y - 140), s);
                for (int k = 0; k < 6; k++)
                {
                    var point = new Pt(exit.X + rng.Range(-180, 180), exit.Y - rng.Range(30, 170));
                    s.BallGame?.Fireworks.Add((Elapsed + 0.25 * k + 0.6, point));
                }
                BallLine(Plays.Moment.HomeRun, hr.By, s, BaseballScore(game));
                break;
            }
            case Plays.Baseball.Event.Fetch fe: Trace?.Invoke($"play baseball {PlayerName(fe.By)} fetches it"); break;
            case Plays.Baseball.Event.SidesChange sc:
                Trace?.Invoke($"play baseball inning {sc.Inning}: {string.Join(", ", sc.Batting.Select(PlayerName))} to bat");
                break;
            case Plays.Baseball.Event.Ghost g: Trace?.Invoke($"play baseball {PlayerName(g.Index)} leaves a ghost on {Base(g.Base)}"); break;
        }
    }

    private static string BaseballScore(Plays.Baseball game) =>
        game.Lineup == Plays.Lineup.Solo ? $"{game.Hits}" : string.Join("-", game.SideRuns);

    /// <summary>A cheer across the screen, popping up, for a little under two seconds.</summary>
    private void Cheer(string text, Pt point, PlaySession s)
    {
        if (s.BallGame is not { } extras) return;
        var image = PixelTextImage(text, PixelText.Banner);
        var size = image?.Size ?? Size.Empty;
        var at = point;
        if (extras.Bounds is { } b)
        {
            double w = size.Width * extras.Scale / 2 + 12, h = size.Height * extras.Scale / 2 + 12;
            at = new Pt(Math.Min(Math.Max(point.X, b.MinX + w), b.MaxX - w), Math.Min(Math.Max(point.Y, b.MinY + h), b.MaxY - h));
        }
        extras.Banner = (image, size, at, Elapsed, Elapsed + 1.8);
    }

    private void RunExtras(PlaySession s)
    {
        if (s.BallGame is not { } extras) return;
        while (extras.Fireworks.Count > 0 && extras.Fireworks[0].At <= Elapsed)
        {
            var next = extras.Fireworks[0];
            extras.Fireworks.RemoveAt(0);
            sparks.Burst(next.Point, new Vec(0, 1), 10, rng);
            sparks.Burst(next.Point, new Vec(0, -1), 6, rng);
        }
        if (extras.Banner is { } banner && Elapsed > banner.Until) extras.Banner = null;
    }

    /// <summary><paramref name="text"/> in pixel letters, drawn once.</summary>
    private Bitmap? PixelTextImage(string text, PixelText.Style style)
    {
        var key = $"{style.Size}|{text}";
        if (pixelTexts.TryGetValue(key, out var made)) return made;
        if (pixelTexts.Count > 60) pixelTexts.Clear();
        made = PixelText.Image(text, style);
        pixelTexts[key] = made;
        return made;
    }

    // MARK: Words

    /// <summary>A line at a big moment: built in, or from the model for a goal or a home run.</summary>
    private void BallLine(Plays.Moment moment, int i, PlaySession s, string score)
    {
        if (!PlayCanTalk || i < 0 || i >= creatures.Count) return;
        // A small moment keeps quiet when someone has only just spoken.
        if (!moment.AsksTheModel() && Elapsed - lastBallLine <= 5) return;
        if (!moment.AsksTheModel())
        {
            var key = $"{moment.Raw()} {i}";
            if (s.BallGame is not { } extras || !extras.Said.Add(key)) return;
        }
        lastBallLine = Elapsed;
        var me = CharacterFor(i);
        var builtIn = Plays.CheerLine(me.Name, moment);
        var situation = string.Join(" ", new[] { TimeOfDay }.Concat(s.Players.Take(4).Where(p => p < creatures.Count).Select(p => Describe(p) + ".")));
        var service = moment.AsksTheModel() && Settings.Brain != BrainKind.Script ? Settings.ChatClient() : null;
        if (service is null)
        {
            SayPlayLine(builtIn, i, situation, AppSettings.BrainTitle(BrainKind.Script), "", null, null);
            return;
        }
        var vars = new Dictionary<string, string>
        {
            ["speaker"] = me.Name, ["speakerKind"] = Banter.Spoken(KindOf(i)), ["speakerPersona"] = Banter.Persona(me.Persona),
            ["play"] = s.Kind.Title(), ["moment"] = moment.Happening(), ["score"] = score, ["situation"] = situation,
        };
        _ = BallLineByModel(service, s.Serial, i, me.Name, builtIn, situation, vars);
    }

    private async Task BallLineByModel(ChatClient service, int serial, int i, string name, string builtIn, string situation,
                                       Dictionary<string, string> vars)
    {
        var line = "";
        double? cost = null;
        int? tokens = null;
        try
        {
            var answer = await service.Line(Plays.LineSystemPrompt, Banter.Render(Plays.CheerPrompt, vars));
            if (answer.Usage is Core.Spend.Usage usage)
            {
                if (service.Kind == ChatClient.Provider.LmStudio) usage.Cost = 0;       // a local model is free
                cost = usage.Cost;
                tokens = usage.PromptTokens + usage.CompletionTokens;
                Spend.Record(service.Kind, service.Model, usage, Core.Spend.Purpose.BallGames);
            }
            line = Banter.CleanLine(answer.Text, name, cut: answer.Cut);
        }
        catch (Exception e)
        {
            Console.Error.WriteLine("Ledgelings ball game: " + e.Message);
        }
        if (play?.Serial != serial) return;
        if (line.Length == 0) SayPlayLine(builtIn, i, situation, AppSettings.BrainTitle(BrainKind.Script), "", null, null);
        else SayPlayLine(line, i, situation, service.ProviderTitle, service.Model, cost, tokens, builtIn: false);
    }

    // MARK: Their story

    /// <summary>Who played whom: in a team game teammates; otherwise everyone together.</summary>
    private static List<(int, int)> BallGamePairs(PlaySession s)
    {
        IEnumerable<IReadOnlyList<int>> groups;
        if (s.Soccer is { Lineup: Plays.Lineup.Teams } m)
            groups = new[] { 0, 1 }.Select(t => (IReadOnlyList<int>)m.Players.Where(p => p.Team == t).Select(p => p.Index).ToList());
        else if (s.Baseball is { Lineup: Plays.Lineup.Teams } g)
            groups = g.Sides;
        else
            groups = new[] { s.Players };
        var pairs = new List<(int, int)>();
        foreach (var side in groups)
            for (int a = 0; a < side.Count; a++)
                for (int b = a + 1; b < side.Count; b++) pairs.Add((side[a], side[b]));
        return pairs;
    }

    // MARK: Drawing

    private List<PropSnapshot> BallGameProps(PlaySession s)
    {
        var props = new List<PropSnapshot>();
        Bitmap? Image(string animation, double time = 0) => playFrames.Frame(animation, time);
        var extras = s.BallGame;
        var scale = extras?.Scale ?? 2.5;
        if (s.Soccer is { } m)
        {
            foreach (var g in m.Goals)
            {
                // The post (the cell's mouth column) on the goal line, the cell's foot on the floor.
                var centre = new Pt(g.X + g.Side * (PlayCell.Width / 2.0 - Plays.Soccer.Net.MouthColumn) * m.Scale,
                                    m.Pitch.FloorY + PlayCell.Height / 2.0 * m.Scale);
                props.Add(new PropSnapshot(Image("net"), centre, 0, m.Scale, Mirrored: g.Side < 0));
            }
            if (m.TheBall.Opacity > 0)
                props.Add(new PropSnapshot(Image("soccer", Math.Abs(m.TheBall.Turn) / (Math.PI / 2) / 8), m.TheBall.Position, 0, m.Scale,
                                           Opacity: (float)m.TheBall.Opacity, InFront: true));
            props.Add(Board(m.Board(PlayerName), extras?.BoardAt, scale));
        }
        if (s.Baseball is { } bb)
        {
            for (int n = 0; n < bb.Field.Bases.Count; n++)
            {
                var place = bb.Field.Bases[n];
                var taken = bb.Bases[n]?.Ghost == true;
                props.Add(new PropSnapshot(Image(taken ? "base-taken" : "base"), BaseCentre(place, scale), place.Rotation, scale));
            }
            props.Add(new PropSnapshot(Image("base"), BaseCentre(bb.Field.Home, scale), bb.Field.Home.Rotation, scale));
            if (bb.ActorOf(bb.Batter) is { IsHopping: false } b && bb.PoseOf(bb.Batter) is { } pose && bb.CurrentPhase != Plays.Baseball.Phase.Over)
            {
                // The bat over the batter's shoulder, swung through in front of it.
                var up = new Vec(-Math.Sin(pose.Rotation), Math.Cos(pose.Rotation));
                var ahead = new Vec(up.Dy * pose.Facing, -up.Dx * pose.Facing);
                var hands = new Pt(pose.Position.X + up.Dx * b.Half * 0.2 + ahead.Dx * b.Half * 0.5,
                                   pose.Position.Y + up.Dy * b.Half * 0.2 + ahead.Dy * b.Half * 0.5);
                var angle = pose.Rotation + -pose.Facing * (0.5 - bb.BatSwing * 2.3);
                var along = new Vec(-Math.Sin(angle), Math.Cos(angle));
                props.Add(new PropSnapshot(Image("bat"), new Pt(hands.X + along.Dx * 6 * scale, hands.Y + along.Dy * 6 * scale), angle, scale, InFront: true));
            }
            if (bb.BallPosition is { } at) props.Add(new PropSnapshot(Image("baseball"), at, 0, scale, InFront: true));
            props.Add(Board(bb.Board(PlayerName), extras?.BoardAt, scale));
        }
        if (extras?.Banner is { } banner)
        {
            var age = Elapsed - banner.Since;
            var pop = Math.Min(1, 0.5 + age * 4);
            var fade = (float)Math.Min(1, Math.Max(0, (banner.Until - Elapsed) / 0.4));
            props.Add(new PropSnapshot(banner.Image, banner.At, 0, scale * pop, Opacity: fade, InFront: true, Size: banner.Size));
        }
        return props;
    }

    /// <summary>A base lies flat on its edge, its bag just inside it.</summary>
    private Pt BaseCentre(Plays.Place place, double scale)
    {
        // The bag's outline ends 3 sheet pixels below the cell's middle (rows 12 to 16 of 28).
        var below = (17 - PlayCell.Height / 2.0) * scale;
        return new Pt(place.Edge.X + place.Inward.Dx * below, place.Edge.Y + place.Inward.Dy * below);
    }

    /// <summary>The scoreboard: pixel letters on a dark plate at <paramref name="at"/>.</summary>
    private PropSnapshot Board(string text, Pt? at, double scale)
    {
        var image = PixelTextImage(text, PixelText.Board);
        var size = image?.Size ?? Size.Empty;
        var boardScale = Math.Max(2, Math.Round(scale * 0.8, MidpointRounding.AwayFromZero));
        // Behind the creatures and their bubbles: a line said near the top stays readable.
        return new PropSnapshot(image, at ?? Pt.Zero, 0, boardScale, Size: size);
    }
}
