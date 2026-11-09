using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Surfing (SPEC §7.10, <c>Plays.Surf</c>): on a wave along the bottom edge, for however many are free. The
/// Mac's keys, defaults and ranges; switched on or off on the Play page too, with the other games.</summary>
public sealed partial class AppSettings
{
    /// <summary>Minutes a surfing session lasts at most.</summary>
    public const double SurfMinutesMin = 0.5, SurfMinutesMax = 10;
    /// <summary>Waves in a session.</summary>
    public const int SurfWavesMin = 1, SurfWavesMax = 20;
    /// <summary>How tall a wave stands, in creature heights.</summary>
    public const double SurfWaveHeightMin = 1, SurfWaveHeightMax = 4;
    /// <summary>How solid the water is drawn, in percent: the desktop shows through the rest.</summary>
    public const double SurfWaterOpacityMin = 20, SurfWaterOpacityMax = 90;
    /// <summary>The calm water's depth, in creature heights: a little over one, so a board floats above the floor.</summary>
    public const double SurfDepth = 1.2;

    private bool playSurfEnabled;
    private double surfEveryMinutes, surfMinutes, surfWaveHeight, surfWaterOpacity;
    private int surfWaves, surfPlayers;

    private void LoadSurf()
    {
        playSurfEnabled = store.Get<bool?>("playSurfEnabled") ?? true;
        // 30 minutes: the sea fills the bottom of the screen, so it comes now and then, not with every game.
        surfEveryMinutes = Math.Clamp(store.Get<double?>("surfEveryMinutes") ?? 30, BallGameEveryMin, BallGameEveryMax);
        // Two minutes or five waves: each surfer gets a few rides, and it is over before it is in the way.
        surfMinutes = Math.Clamp(store.Get<double?>("surfMinutes") ?? 2, SurfMinutesMin, SurfMinutesMax);
        surfWaves = Math.Clamp(store.Get<int?>("surfWaves") ?? 5, SurfWavesMin, SurfWavesMax);
        // Two creatures tall: a wave worth riding that still leaves most of the screen clear.
        surfWaveHeight = Math.Clamp(store.Get<double?>("surfWaveHeight") ?? 2, SurfWaveHeightMin, SurfWaveHeightMax);
        // 55 %: plainly water, and the windows under it stay readable.
        surfWaterOpacity = Math.Clamp(store.Get<double?>("surfWaterOpacity") ?? 55, SurfWaterOpacityMin, SurfWaterOpacityMax);
        // Five: room for everyone to wait for a wave along the floor.
        surfPlayers = Math.Clamp(store.Get<int?>("surfPlayers") ?? 5, BallPlayersMin, BallPlayersMax);
    }

    /// <summary>Surfing on a wave along the bottom edge, for however many are free.</summary>
    public bool PlaySurfEnabled { get => playSurfEnabled; set => Put(ref playSurfEnabled, value, "playSurfEnabled"); }
    public double SurfEveryMinutes { get => surfEveryMinutes; set => Put(ref surfEveryMinutes, Math.Clamp(value, BallGameEveryMin, BallGameEveryMax), "surfEveryMinutes"); }
    public double SurfMinutes { get => surfMinutes; set => Put(ref surfMinutes, Math.Clamp(value, SurfMinutesMin, SurfMinutesMax), "surfMinutes"); }
    public int SurfWaves { get => surfWaves; set => Put(ref surfWaves, Math.Clamp(value, SurfWavesMin, SurfWavesMax), "surfWaves"); }
    public double SurfWaveHeight { get => surfWaveHeight; set => Put(ref surfWaveHeight, Math.Clamp(value, SurfWaveHeightMin, SurfWaveHeightMax), "surfWaveHeight"); }
    public int SurfPlayers { get => surfPlayers; set => Put(ref surfPlayers, Math.Clamp(value, BallPlayersMin, BallPlayersMax), "surfPlayers"); }
    public double SurfWaterOpacity { get => surfWaterOpacity; set => Put(ref surfWaterOpacity, Math.Clamp(value, SurfWaterOpacityMin, SurfWaterOpacityMax), "surfWaterOpacity"); }
}
