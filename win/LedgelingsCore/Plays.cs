namespace Ledgelings.Core;

/// <summary>
/// Plays (SPEC §7.10): now and then a creature stops walking and plays, the way the worms in Worms
/// fool about between turns, with nobody hurt. Tag round the edges, a swing on a ninja rope, a
/// parachute jump from the ceiling, a few throws at a hoop on a wall; and soccer and baseball for a crowd
/// (<c>Plays.Soccer.cs</c>, <c>Plays.Baseball.cs</c>). Closer pairs play more often,
/// and only friends play together. Everything here is pure: the colony asks each game where the
/// creature and the props are, frame by frame. The macOS app's <c>Plays.swift</c>.
/// </summary>
public static partial class Plays
{
    public enum Kind { Tag, Rope, Parachute, Basketball, Soccer, Baseball }

    public static readonly IReadOnlyList<Kind> AllKinds = new[] { Kind.Tag, Kind.Rope, Kind.Parachute, Kind.Basketball, Kind.Soccer, Kind.Baseball };

    /// <summary>"tag", "basketball": as the Mac writes it into a storyline moment.</summary>
    public static string Raw(this Kind kind) => kind.ToString().ToLowerInvariant();

    public static Kind? FromRaw(string? raw) => AllKinds.Cast<Kind?>().FirstOrDefault(k => k!.Value.Raw() == raw);

    /// <summary>Needs two: tag.</summary>
    public static bool NeedsPair(this Kind kind) => kind == Kind.Tag;
    /// <summary>Can be played by two: tag, and turns at the hoop.</summary>
    public static bool CanPair(this Kind kind) => kind is Kind.Tag or Kind.Basketball;
    /// <summary>Played by however many are free, one to a crowd: soccer and baseball.</summary>
    public static bool IsTeamGame(this Kind kind) => kind is Kind.Soccer or Kind.Baseball;
    public static bool CanSolo(this Kind kind) => !kind.NeedsPair() && !kind.IsTeamGame();

    /// <summary>In words, for a prompt and a storyline: "a game of catch me if you can".</summary>
    public static string Title(this Kind kind) => kind switch
    {
        Kind.Tag => L10n.Tr("a game of catch me if you can"),
        Kind.Rope => L10n.Tr("a swing on a ninja rope"),
        Kind.Parachute => L10n.Tr("a parachute jump from the ceiling"),
        Kind.Soccer => L10n.Tr("a game of soccer"),
        Kind.Baseball => L10n.Tr("a game of baseball"),
        _ => L10n.Tr("a game of basketball"),
    };

    /// <summary>The game in a few words, for a storyline: a stored raw value.</summary>
    public static string Name(string? detail) => FromRaw(detail)?.Title() ?? detail ?? "";

    /// <summary>Screen points per second per second: what the rope, the parachute's first drop and the ball fall with.</summary>
    public const double Gravity = 1600;
    /// <summary>Share of throws at the hoop aimed true; the rest are a little short or long.</summary>
    public const double MakeChance = 0.5;

    // MARK: Who plays, and when

    /// <summary>Moments shared before a pair counts as close as can be.</summary>
    public const double CloseAt = 20;
    /// <summary>Moments shared before a pair plays together at all.</summary>
    public const int FriendsAt = 3;

    /// <summary>How close two characters are, 0...1: the moments of their storyline (or, before
    /// storylines, their talks) out of <see cref="CloseAt"/>.</summary>
    public static double Closeness(Bonds.Bond? bond)
    {
        if (bond is null) return 0;
        var moments = Math.Max(bond.Tally.Values.Sum(), bond.Talks);
        return Math.Min(1, moments / CloseAt);
    }

    /// <summary>Seconds until the next play: about <paramref name="everyMinutes"/> (0.6 to 1.4 of it),
    /// shorter the closer the closest pair on screen is. <paramref name="boost"/> is the percentage a
    /// perfectly close pair speeds it up by: 100 halves the wait.</summary>
    public static double Wait(double everyMinutes, double boost, double closeness, Random rng)
    {
        var baseWait = Math.Max(0.1, everyMinutes) * 60 * rng.Range(0.6, 1.4);
        return baseWait / (1 + Math.Max(0, boost) / 100 * Math.Min(Math.Max(closeness, 0), 1));
    }

    /// <summary>The chance a close pair plays together rather than one of them alone.</summary>
    public static double PairChance(double closeness) => Math.Min(0.85, 0.2 + 0.65 * closeness);

    /// <summary>What <paramref name="initiator"/> plays, and with whom: with its closest friend among
    /// <paramref name="others"/> (<see cref="PairChance"/>), a game for two; else a game alone. Null when
    /// nothing it may play is on.</summary>
    public static (Kind Kind, int[] Players)? Choose(int initiator, IReadOnlyList<(int Index, double Closeness)> others,
                                                      IReadOnlySet<Kind> enabled, Random rng)
    {
        var pairs = AllKinds.Where(k => enabled.Contains(k) && k.CanPair()).ToList();
        var solos = AllKinds.Where(k => enabled.Contains(k) && k.CanSolo()).ToList();
        var friends = others.Where(o => o.Closeness >= FriendsAt / CloseAt).ToList();
        if (friends.Count > 0 && pairs.Count > 0)
        {
            var friend = friends.OrderByDescending(o => o.Closeness).First();
            if (solos.Count == 0 || rng.NextDouble() < PairChance(friend.Closeness))
                return (rng.Pick(pairs), new[] { initiator, friend.Index });
        }
        if (solos.Count == 0) return null;
        return (rng.Pick(solos), new[] { initiator });
    }

    // MARK: Tag

    /// <summary>A game of tag between two; <c>It</c> chases. ready → chase → puffing → over.</summary>
    public sealed class Tag
    {
        public enum Phase { Ready, Chase, Puffing, Over }
        public abstract record Event
        {
            public sealed record Go : Event;
            /// <summary><c>By</c> touched the other: <c>Now</c> is "it".</summary>
            public sealed record Tagged(int By, int Now) : Event;
            public sealed record Puffing : Event;
            public sealed record Over : Event;
        }

        public const double ReadyTime = 1.2;
        public const double Counting = 1.0;
        public const double PuffTime = 3.5;
        /// <summary>Points per second: the one running away, and "it", a little faster.</summary>
        public const double FleeSpeed = 130;
        public const double ChaseSpeed = 190;

        public IReadOnlyList<int> Players { get; }
        public double Length { get; }
        public int It { get; private set; }
        public Phase CurrentPhase { get; private set; } = Phase.Ready;
        public int Touches { get; private set; }
        private double clock;
        private double total;
        private double countUntil = ReadyTime;

        public Tag(int it, int other, double length)
        {
            Players = new[] { it, other };
            It = it;
            Length = Math.Max(1, length);
        }

        public int Runner => Players[0] == It ? Players[1] : Players[0];
        /// <summary>"It" stands still, counting, before it runs after the other.</summary>
        public bool ItIsCounting => CurrentPhase == Phase.Ready || (CurrentPhase == Phase.Chase && clock < countUntil);

        /// <summary>The chaser caught up: <paramref name="gap"/> points between their centres along the edge,
        /// <paramref name="reach"/> the two half sizes added up.</summary>
        public Event.Tagged? Near(double gap, double reach)
        {
            if (CurrentPhase != Phase.Chase || ItIsCounting || gap > reach) return null;
            var was = It;
            It = Runner;
            Touches++;
            countUntil = clock + Counting;
            return new Event.Tagged(was, It);
        }

        public List<Event> Update(double dt)
        {
            clock += dt;
            total += dt;
            switch (CurrentPhase)
            {
                case Phase.Ready:
                    if (clock < ReadyTime) return new();
                    CurrentPhase = Phase.Chase;
                    return new() { new Event.Go() };
                case Phase.Chase:
                    if (total < ReadyTime + Length) return new();
                    CurrentPhase = Phase.Puffing;
                    clock = 0;
                    return new() { new Event.Puffing() };
                case Phase.Puffing:
                    if (clock < PuffTime) return new();
                    CurrentPhase = Phase.Over;
                    return new() { new Event.Over() };
                default:
                    return new();
            }
        }
    }

    // MARK: The rope

    /// <summary>A swing on a ninja rope, from <c>Start</c> (the creature's centre on a floor) to a hook in the
    /// ceiling above and ahead of it. aim → fire → reel → swing → fly → landed.</summary>
    public sealed class Rope
    {
        public enum Phase { Aim, Fire, Reel, Swing, Fly, Landed }
        public enum Event { Fired, Hooked, Swinging, LetGo, Landed }
        public const double AimTime = 0.5;
        public const double FireTime = 0.3;
        public const double ReelTime = 0.55;
        public const double ReleaseShare = 0.55;
        /// <summary>The steepest the rope may start, from straight up, and the shallowest.</summary>
        public const double Steepest = 45 * Math.PI / 180;
        public const double Shallowest = 20 * Math.PI / 180;

        public Pt Start { get; }
        public Pt Anchor { get; }
        public double FloorY { get; }
        /// <summary>Where along the floor it may come down: the floor's two ends.</summary>
        public double FloorFrom { get; }
        public double FloorTo { get; }
        /// <summary>+1 swings toward growing x.</summary>
        public double Way { get; }
        /// <summary>The rope as fired, and once reeled in.</summary>
        public double FiredLength { get; }
        public double Length { get; }
        public double StartAngle { get; }
        public Phase CurrentPhase { get; private set; } = Phase.Aim;
        public Pt Position { get; private set; }
        public double Rotation { get; private set; }
        /// <summary>Where the hook is: flying up while fired, then in the ceiling.</summary>
        public Pt Hook { get; private set; }
        public double Angle { get; private set; }
        public double Spin { get; private set; }
        public Vec Velocity { get; private set; }
        private double clock;
        private double flightTurn;
        private double flightTime = 1;

        private Rope(Pt start, Pt anchor, double floorFrom, double floorTo, double way, double firedLength, double length, double startAngle)
        {
            Start = start; Anchor = anchor; FloorY = start.Y; FloorFrom = floorFrom; FloorTo = floorTo; Way = way;
            FiredLength = firedLength; Length = length; StartAngle = startAngle;
            Angle = startAngle; Position = start; Hook = start;
        }

        /// <summary>Plan a swing from <paramref name="start"/>, under a ceiling at <paramref name="ceilingY"/>,
        /// along a floor running from <paramref name="floorFrom"/> to <paramref name="floorTo"/>, going
        /// <paramref name="preferred"/> if there is room (else the other way). Null when the ceiling is too low
        /// or the floor too short either way.</summary>
        public static Rope? Plan(Pt start, double ceilingY, double floorFrom, double floorTo, double preferred, double clearance)
        {
            var height = ceilingY - start.Y;
            var length = height - clearance;
            if (length < 60) return null;
            foreach (var way in new double[] { preferred < 0 ? -1 : 1, preferred < 0 ? 1 : -1 })
            {
                var room = way > 0 ? floorTo - start.X : start.X - floorFrom;
                for (var theta = Steepest; theta >= Shallowest - 1e-9; theta -= 5 * Math.PI / 180)
                {
                    // Ahead to the hook, on past it to where it lets go, and the flight from there to the floor.
                    var needed = height * Math.Tan(theta) + Reach(length, theta, clearance) + 10;
                    if (needed > room) continue;
                    return new Rope(start, new Pt(start.X + way * height * Math.Tan(theta), ceilingY), floorFrom, floorTo, way,
                                    height / Math.Cos(theta), length, -way * theta);
                }
            }
            return null;
        }

        /// <summary>How far past the hook a swing from <paramref name="angle"/> (from straight down) on a rope
        /// <paramref name="length"/> long carries it: to where it lets go, then its flight down to a floor
        /// <paramref name="above"/> below the bottom of the swing.</summary>
        public static double Reach(double length, double angle, double above)
        {
            var release = angle * ReleaseShare;
            var speed = Math.Sqrt(Math.Max(0, 2 * Gravity * length * (Math.Cos(release) - Math.Cos(angle))));
            var vx = speed * Math.Cos(release);
            var vy = speed * Math.Sin(release);
            var h = above + length * (1 - Math.Cos(release));
            var time = (vy + Math.Sqrt(vy * vy + 2 * Gravity * h)) / Gravity;
            return length * Math.Sin(release) + vx * time;
        }

        public string Pose => CurrentPhase switch
        {
            Phase.Aim or Phase.Fire => "idle",
            Phase.Landed => "land",
            _ => "jump",
        };

        /// <summary>The rope is out, from the creature to the hook.</summary>
        public bool RopeIsOut => CurrentPhase is Phase.Fire or Phase.Reel or Phase.Swing;

        private Pt Hanging(double angle, double length) =>
            new(Anchor.X + length * Math.Sin(angle), Anchor.Y - length * Math.Cos(angle));

        public List<Event> Update(double dt)
        {
            clock += dt;
            switch (CurrentPhase)
            {
                case Phase.Aim:
                    if (clock < AimTime) return new();
                    Enter(Phase.Fire);
                    return new() { Event.Fired };
                case Phase.Fire:
                {
                    var p = Math.Min(1, clock / FireTime);
                    Hook = new Pt(Start.X + (Anchor.X - Start.X) * p, Start.Y + (Anchor.Y - Start.Y) * p);
                    if (p < 1) return new();
                    Enter(Phase.Reel);
                    return new() { Event.Hooked };
                }
                case Phase.Reel:
                {
                    var p = Math.Min(1, clock / ReelTime);
                    var eased = p * p * (3 - 2 * p);
                    Position = Hanging(StartAngle, FiredLength + (Length - FiredLength) * eased);
                    Rotation = Angle * eased;
                    if (p < 1) return new();
                    Enter(Phase.Swing);
                    return new() { Event.Swinging };
                }
                case Phase.Swing:
                {
                    // A pendulum, stepped finely so it neither gains nor loses much.
                    var left = dt;
                    while (left > 0)
                    {
                        var h = Math.Min(left, 1.0 / 240);
                        Spin += -(Gravity / Length) * Math.Sin(Angle) * h;
                        Angle += Spin * h;
                        left -= h;
                    }
                    Position = Hanging(Angle, Length);
                    Rotation = Angle;
                    if (!(Angle * Way >= Math.Abs(StartAngle) * ReleaseShare && Spin * Way > 0)) return new();
                    Velocity = new Vec(Length * Spin * Math.Cos(Angle), Length * Spin * Math.Sin(Angle));
                    var height = Position.Y - FloorY;
                    var time = (Velocity.Dy + Math.Sqrt(Math.Max(0, Velocity.Dy * Velocity.Dy + 2 * Gravity * height))) / Gravity;
                    // A whole somersault forwards, landing upright.
                    flightTurn = Rotation;
                    flightTime = Math.Max(0.2, time);
                    Enter(Phase.Fly);
                    return new() { Event.LetGo };
                }
                case Phase.Fly:
                {
                    Velocity = Velocity with { Dy = Velocity.Dy - Gravity * dt };
                    var x = Position.X + Velocity.Dx * dt;
                    var y = Position.Y + Velocity.Dy * dt;
                    if (x < FloorFrom || x > FloorTo)
                    {
                        x = Math.Min(Math.Max(x, FloorFrom), FloorTo);
                        Velocity = Velocity with { Dx = 0 };
                    }
                    Position = new Pt(x, y);
                    var share = Math.Min(1, clock / flightTime);
                    Rotation = flightTurn + (-2 * Math.PI * Way - flightTurn) * share;
                    if (Position.Y > FloorY) return new();
                    Position = new Pt(Position.X, FloorY);
                    Rotation = 0;
                    Enter(Phase.Landed);
                    return new() { Event.Landed };
                }
                default:
                    return new();
            }
        }

        private void Enter(Phase next)
        {
            CurrentPhase = next;
            clock = 0;
        }
    }

    // MARK: The parachute

    /// <summary>A parachute jump from <c>Top</c> (the creature's centre, upside down on a ceiling) down to the
    /// floor. hang → drop → open → float → landed → packed.</summary>
    public sealed class Chute
    {
        public enum Phase { Hang, Drop, Open, Float, Landed, Packed }
        public enum Event { Jumped, Opened, Landed, Packed }
        public const double HangTime = 0.8;
        public const double DropTime = 0.4;
        public const double OpenTime = 0.4;
        public const double PackTime = 0.7;
        public const double SwayPeriod = 2.6;
        public const double Sway = 16;
        public const double Tilt = 0.14;

        public Pt Top { get; }
        public double FloorY { get; }
        public double FloorFrom { get; }
        public double FloorTo { get; }
        public double FallSpeed { get; }
        public Phase CurrentPhase { get; private set; } = Phase.Hang;
        public Pt Position { get; private set; }
        public double Rotation { get; private set; } = Math.PI;
        /// <summary>How open the canopy is: 0 folded, 1 open.</summary>
        public double Canopy { get; private set; }
        private double clock;
        private double floatTime;
        private double speed;
        private readonly double swayFrom;

        public Chute(Pt top, double floorY, double floorFrom, double floorTo, double fallSpeed)
        {
            Top = top; FloorY = floorY; FloorFrom = floorFrom; FloorTo = floorTo;
            FallSpeed = Math.Max(10, fallSpeed);
            Position = top;
            swayFrom = top.X;
        }

        public string Pose => CurrentPhase switch
        {
            Phase.Hang => "idle",
            Phase.Drop or Phase.Open or Phase.Float => "jump",
            _ => clock < 0.3 ? "land" : "idle",
        };

        public List<Event> Update(double dt)
        {
            clock += dt;
            switch (CurrentPhase)
            {
                case Phase.Hang:
                    if (clock < HangTime) return new();
                    Enter(Phase.Drop);
                    return new() { Event.Jumped };
                case Phase.Drop:
                {
                    var p = Math.Min(1, clock / DropTime);
                    speed = Gravity * clock;
                    Position = new Pt(Position.X, Top.Y - Gravity * clock * clock / 2);
                    Rotation = Math.PI * (1 - p * p * (3 - 2 * p));
                    if (Landed()) return new() { Event.Landed };
                    if (p < 1) return new();
                    Enter(Phase.Open);
                    return new() { Event.Opened };
                }
                case Phase.Open:
                {
                    var p = Math.Min(1, clock / OpenTime);
                    Canopy = p;
                    var v = speed + (FallSpeed - speed) * p;
                    Position = new Pt(Position.X, Position.Y - v * dt);
                    Rotation = 0;
                    if (Landed()) return new() { Event.Landed };
                    if (p < 1) return new();
                    Enter(Phase.Float);
                    return new();
                }
                case Phase.Float:
                {
                    floatTime += dt;
                    var phaseAngle = 2 * Math.PI * floatTime / SwayPeriod;
                    var x = Math.Min(Math.Max(swayFrom + Sway * Math.Sin(phaseAngle), FloorFrom), FloorTo);
                    Position = new Pt(x, Position.Y - FallSpeed * dt);
                    Rotation = -Tilt * Math.Cos(phaseAngle);
                    return Landed() ? new() { Event.Landed } : new();
                }
                case Phase.Landed:
                    Rotation = 0;
                    Canopy = Math.Max(0, 1 - clock / PackTime);
                    if (clock < PackTime) return new();
                    Enter(Phase.Packed);
                    return new() { Event.Packed };
                default:
                    return new();
            }
        }

        private bool Landed()
        {
            if (Position.Y > FloorY) return false;
            Position = new Pt(Math.Min(Math.Max(Position.X, FloorFrom), FloorTo), FloorY);
            Rotation = 0;
            Canopy = Math.Max(Canopy, 0.0001);
            Enter(Phase.Landed);
            return true;
        }

        private void Enter(Phase next)
        {
            CurrentPhase = next;
            clock = 0;
        }
    }

    // MARK: Basketball

    /// <summary>The hoop's shape, in sheet pixels, as <c>spritetool/painters/play.py</c> draws it in its 32×28
    /// cell: hung on a wall to its right, the rim's top row <c>RimRow</c> pixels from the cell's top, running
    /// from column <c>RimFrom</c> to <c>RimTo</c>.</summary>
    public static class Props
    {
        public const double CellWidth = 32, CellHeight = 28;
        public const double RimRow = 14;
        public const double RimFrom = 8;
        public const double RimTo = 25;
        /// <summary>The ball's radius, in sheet pixels: 10 across, its outline a soft edge.</summary>
        public const double BallRadius = 5;
    }

    /// <summary>A hoop on a wall, in screen points: <c>WallX</c> is the wall, <c>Side</c> +1 when the wall is on
    /// the right of the court (the hoop opens leftwards).</summary>
    public sealed record Hoop
    {
        public double WallX { get; }
        public double Side { get; }
        /// <summary>The rim's height: its top.</summary>
        public double RimY { get; }
        /// <summary>The middle of the rim, and half its width.</summary>
        public double RimX { get; }
        public double RimHalf { get; }
        /// <summary>Where the cell's middle goes, to draw it.</summary>
        public Pt Centre { get; }

        /// <summary>A hoop drawn at <paramref name="scale"/> points per pixel, its rim <paramref name="height"/> points
        /// above <paramref name="floorY"/> (the screen's floor).</summary>
        public Hoop(double wallX, double side, double floorY, double height, double scale)
        {
            WallX = wallX;
            Side = side < 0 ? -1 : 1;
            var fromWall = (Props.CellWidth - (Props.RimFrom + Props.RimTo + 1) / 2) * scale;
            RimX = wallX - Side * fromWall;
            RimHalf = (Props.RimTo + 1 - Props.RimFrom) / 2 * scale;
            RimY = floorY + height;
            var cellTop = RimY + Props.RimRow * scale;
            Centre = new Pt(wallX - Side * Props.CellWidth / 2 * scale, cellTop - Props.CellHeight / 2 * scale);
        }

        /// <summary>The rim's end away from the wall: the ball bounces off it.</summary>
        public Pt Front => new(RimX - Side * RimHalf, RimY);
    }

    /// <summary>The ball: thrown, falling, bouncing on the floor, the wall behind the hoop and the rim's front
    /// end, coming to rest. It is in when it drops down through the rim.</summary>
    public sealed class Ball
    {
        public enum Event { Floor, Rim, Board, Scored }
        public Pt Position { get; private set; }
        public Vec Velocity { get; private set; }
        public double Radius { get; }
        /// <summary>Share of its speed kept on each bounce, 0...0.95.</summary>
        public double Bounce { get; }
        public Hoop Hoop { get; }
        /// <summary>The floor's height (the screen's), and the court's two ends.</summary>
        public double FloorY { get; }
        public double CourtFrom { get; }
        public double CourtTo { get; }
        public bool Scored { get; private set; }
        /// <summary>Spun this far, for drawing: it turns as it flies and rolls.</summary>
        public double Turn { get; private set; }
        public bool Resting { get; private set; }

        public Ball(Pt position, Vec velocity, double radius, double bounce, Hoop hoop, double floorY, double courtFrom, double courtTo)
        {
            Position = position; Velocity = velocity; Radius = radius;
            Bounce = Math.Min(Math.Max(bounce, 0), 0.95);
            Hoop = hoop; FloorY = floorY; CourtFrom = courtFrom; CourtTo = courtTo;
        }

        /// <summary>The throw from <paramref name="from"/> that peaks <paramref name="apex"/> points above the rim and
        /// comes down through its middle.</summary>
        public static Vec Aim(Pt from, Hoop hoop, double apex)
        {
            var top = Math.Max(hoop.RimY, from.Y) + Math.Max(10, apex);
            var up = Math.Sqrt(2 * Gravity * (top - from.Y));
            var rise = up / Gravity;
            var fall = Math.Sqrt(2 * (top - (hoop.RimY + 1)) / Gravity);
            return new Vec((hoop.RimX - from.X) / (rise + fall), up);
        }

        public List<Event> Step(double dt)
        {
            var events = new List<Event>();
            var left = dt;
            while (left > 0 && !Resting)
            {
                var h = Math.Min(left, 1.0 / 240);
                left -= h;
                var before = Position;
                double vx = Velocity.Dx, vy = Velocity.Dy - Gravity * h;
                double x = Position.X + vx * h, y = Position.Y + vy * h;
                Turn += vx * h / Math.Max(Radius, 1);
                // Down through the rim, between its ends: in.
                if (!Scored && before.Y >= Hoop.RimY && y < Hoop.RimY && vy < 0 && Math.Abs(x - Hoop.RimX) <= Hoop.RimHalf - Radius * 0.4)
                {
                    Scored = true;
                    events.Add(Event.Scored);
                }
                // The rim's front end: a hard little point.
                var f = Hoop.Front;
                double dx = x - f.X, dy = y - f.Y, d = Math.Sqrt(dx * dx + dy * dy);
                if (d < Radius && d > 0)
                {
                    double nx = dx / d, ny = dy / d;
                    var along = vx * nx + vy * ny;
                    if (along < 0)
                    {
                        vx -= (1 + Bounce) * along * nx;
                        vy -= (1 + Bounce) * along * ny;
                        events.Add(Event.Rim);
                    }
                    x = f.X + nx * Radius;
                    y = f.Y + ny * Radius;
                }
                // The wall the hoop hangs on (the board), and the court's other end.
                var wall = Hoop.WallX - Hoop.Side * Radius;
                if (Hoop.Side > 0 ? x > wall : x < wall)
                {
                    x = wall;
                    if (vx * Hoop.Side > 0) { vx = -vx * Bounce; events.Add(Event.Board); }
                }
                double lo = CourtFrom + Radius, hi = CourtTo - Radius;
                if (x < lo && vx < 0) { x = lo; vx = -vx * Bounce; }
                if (x > hi && vx > 0) { x = hi; vx = -vx * Bounce; }
                if (y < FloorY + Radius)
                {
                    y = FloorY + Radius;
                    if (vy < -40) events.Add(Event.Floor);
                    vy = Math.Abs(vy) * Bounce;
                    vx *= 0.9;
                    if (vy < 30) vy = 0;
                    if (Math.Abs(vx) < 8 && vy == 0) Resting = true;
                }
                Position = new Pt(x, y);
                Velocity = new Vec(vx, vy);
            }
            return events;
        }
    }

    // MARK: Words

    /// <summary>Each character's English start lines for the first games and the ball games, in one table.
    /// Made on first use: the two tables are in other files, whose statics may not be set yet.</summary>
    public static IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>> EnglishStart => englishStart ??=
        EnglishStartLines.ToDictionary(kv => kv.Key, kv => (IReadOnlyDictionary<string, string>)kv.Value
            .Concat(EnglishBallStartLines.TryGetValue(kv.Key, out var ball) ? ball : new Dictionary<string, string>())
            .ToDictionary(p => p.Key, p => p.Value));

    private static IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>>? englishStart;

    public static IReadOnlyDictionary<string, string> EnglishAllStartAnyone => englishAllStartAnyone ??=
        EnglishStartAnyone.Concat(EnglishBallStartAnyone).ToDictionary(p => p.Key, p => p.Value);

    private static IReadOnlyDictionary<string, string>? englishAllStartAnyone;

    public static IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>> StartLinesIn(Language l) =>
        Shared.In(l)?.PlayStart is { Count: > 0 } t
            ? EnglishStart.ToDictionary(kv => kv.Key, kv => t.TryGetValue(kv.Key, out var mine) && mine.Count > 0
                ? (IReadOnlyDictionary<string, string>)mine : kv.Value)
            : EnglishStart;

    public static IReadOnlyDictionary<string, string> StartAnyoneIn(Language l) =>
        Shared.In(l)?.PlayStartAnyone is { Count: > 0 } t ? t : EnglishAllStartAnyone;

    public static IReadOnlyDictionary<string, string[]> DoneLinesIn(Language l) =>
        Translated.Lists(Shared.In(l)?.PlayDone, EnglishDoneLines, t => t);

    public static IReadOnlyList<string> DoneAnyoneIn(Language l) => Translated.List(Shared.In(l)?.PlayDoneAnyone, EnglishDoneAnyone);

    /// <summary>The line <paramref name="name"/> says as it starts <paramref name="kind"/>; <paramref name="other"/>
    /// is its partner at tag.</summary>
    public static string StartLine(string name, Kind kind, string other)
    {
        var l = Languages.Current;
        var line = StartLinesIn(l).TryGetValue(name, out var mine) && mine.TryGetValue(kind.Raw(), out var s) ? s
            : StartAnyoneIn(l).TryGetValue(kind.Raw(), out var a) ? a : "";
        return CursorMoods.Current.Adjust(line.Replace("{other}", other));
    }

    /// <summary>The line <paramref name="name"/> says once the game is over.</summary>
    public static string DoneLine(string name, Random rng)
    {
        var l = Languages.Current;
        IReadOnlyList<string> pool = DoneLinesIn(l).TryGetValue(name, out var mine) ? mine : DoneAnyoneIn(l);
        return pool.Count == 0 ? "" : CursorMoods.Current.Adjust(rng.Pick(pool));
    }

    /// <summary>The values a model's line takes: the speaker's, the game, who else plays, the moment.</summary>
    public static readonly IReadOnlyList<string> Placeholders = new[] { "speaker", "speakerKind", "speakerPersona", "play", "others", "situation" };
    public static string LineSystemPrompt => Shared.Prompt("playSystem", EnglishLineSystemPrompt);
    public static string LinePrompt => Shared.Prompt("play", EnglishLinePrompt);
}
