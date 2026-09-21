using System.Diagnostics;
using System.Drawing;
using System.Windows.Threading;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>All the creatures, the monitors they live on, and the one clock that moves them.</summary>
public sealed partial class Colony : IDisposable
{
    /// <summary>Cap on one simulation step, so a stalled timer cannot teleport anyone.</summary>
    public const double MaxStep = 1.0 / 10;

    public AppSettings Settings { get; }
    /// <summary>Every conversation, written to disk as it ends.</summary>
    public ChatHistory History { get; }
    /// <summary>The built-in and imported creature sheets.</summary>
    public SpriteLibrary Library { get; }
    public SpendLedger Spend { get; }
    /// <summary>The built-in sheet: every sheet shares its cell and body box, so it is the geometry for all.</summary>
    private readonly SpriteAtlas atlas;
    private readonly SpriteAtlas.Frames zFrames;
    private readonly Size zCell;
    private readonly SpriteAtlas.Frames flowerFrames;
    private readonly Size flowerCell;
    private readonly SpriteAtlas.Frames houseFrames;
    private readonly Size houseCell;

    /// <summary>A bigger body walks further from the screen edge, so each size has its
    /// own outline. Sizes come in half steps, so this stays a handful of entries.</summary>
    private readonly Dictionary<double, EdgeWorld> worlds = new();
    private readonly List<Creature> creatures = new();
    /// <summary>Where each creature sits in the min...max size range, 0...1. Fixed at
    /// birth, so moving the sliders resizes everyone without reshuffling who is big.</summary>
    private readonly List<double> sizeShares = new();
    /// <summary>Screen pixels per sheet pixel, per creature: the setting times the monitor's pixel scale.</summary>
    private readonly List<double> sizes = new();
    private readonly List<double> asleepFor = new();
    private readonly List<SpriteAtlas.Frames> frames = new();
    private readonly Dictionary<string, SpriteAtlas.Frames> frameCache = new();
    private readonly List<ScreenOverlay> overlays = new();
    private List<Monitor> monitors = new();
    private double pixelScale = 1;
    private readonly Random rng = new();

    private FrameClock? clock;
    private readonly Stopwatch stopwatch = Stopwatch.StartNew();
    private double? lastTick;
    /// <summary>The creature in the user's hand, and where on its body it was grabbed.</summary>
    private (int Index, Vec Grab)? held;

    private DayNight dayNight;
    /// <summary>One line per talking creature, and when it stops showing.</summary>
    private readonly Dictionary<int, (string Text, double Until)> bubbles = new();
    /// <summary>Creatures in a running conversation: a bump or a poke involving them waits.</summary>
    private readonly HashSet<int> busy = new();
    /// <summary>Who has walked into whom, and how often.</summary>
    private readonly Meetings meetings = new();
    /// <summary>Flowers in the air and on heads.</summary>
    private readonly Gifts gifts = new();
    /// <summary>A Shift-press on a creature that has not moved yet: a poke if it lets go, a carry if it drags.</summary>
    private (int Index, Pt At)? poke;
    private const double DragThreshold = 4;
    /// <summary>Every pair stopped face to face right now. <c>ReleaseAt</c> is null while the words are still coming.</summary>
    private readonly List<Conversation> chats = new();
    /// <summary>Pixel stars from the last bump, and the colours they wear.</summary>
    private readonly Sparks sparks = new();
    private List<Color> sparkPalette = new();
    /// <summary>The house they hide in when asked to go away for a while.</summary>
    private readonly Hideout hideout = new();
    /// <summary>Creatures shrinking into the doorway, and creatures growing out of it, by when they started.</summary>
    private readonly Dictionary<int, double> entering = new();
    private readonly Dictionary<int, double> leaving = new();
    /// <summary>The last thing that happened with the model, for the menu.</summary>
    public string TalkStatus { get; private set; } = "not tried yet";
    public double Elapsed { get; private set; }

    public bool IsNight => dayNight.IsNight(Elapsed);
    public double SecondsLeftInPhase => dayNight.Remaining(Elapsed);
    public Hideout Hideout => hideout;

    public Colony(AppSettings settings, ChatHistory history, SpriteLibrary library, SpendLedger spend)
    {
        Settings = settings;
        History = history;
        Library = library;
        Spend = spend;
        atlas = SpriteAtlas.Named("blocky");
        var zzz = SpriteAtlas.Named("zzz");
        zFrames = zzz.MakeFrames();
        zCell = zzz.CellSize;
        var flowers = SpriteAtlas.Named("flowers");
        flowerFrames = flowers.MakeFrames();
        flowerCell = flowers.CellSize;
        var house = SpriteAtlas.Named("house");
        houseFrames = house.MakeFrames();
        houseCell = house.CellSize;
        dayNight = new DayNight(settings.DayMinutes * 60, settings.NightMinutes * 60);

        RebuildOverlays();
        ApplySettings();
        settings.Changed += ApplySettings;
        library.Changed += () => { frameCache.Clear(); ApplySettings(); };
        Desktop.MonitorsChanged += ScreensChanged;
    }

    // MARK: Commands

    public void StartleEveryone()
    {
        foreach (var c in creatures) c.Startle(rng);
    }

    /// <summary>Jump the clock to the next dusk or dawn.</summary>
    public void SkipPhase() => Elapsed = dayNight.SkippingToNextPhase(Elapsed);

    public void Dispose()
    {
        Settings.Changed -= ApplySettings;
        Desktop.MonitorsChanged -= ScreensChanged;
        clock?.Dispose();
        foreach (var o in overlays) o.Dispose();
        overlays.Clear();
    }
}
