using Ledgelings.Core.PixelFX;

namespace Ledgelings.Core.Tests;

/// <summary>The effects' drawing, as on the Mac (SPEC §7.19): every style and moment has its effect, a frame is whole
/// pixels only, the creature is left where it stands, and the port steps like pixelfx number for number.</summary>
public class EffectsPixelTests
{
    [Fact]
    public void EveryStyleAndMomentHasItsEffect()
    {
        Assert.All(Effects.Styles, s => Assert.True(FXCatalog.All.ContainsKey(s.Effect()), s.ToString()));
        Assert.All(Effects.Moments, m => Assert.True(FXCatalog.All.ContainsKey(m.Effect()), m.ToString()));
        Assert.Equal(25, FXCatalog.All.Count);
    }

    /// <summary>A 10×10 square body with an outline and two black eyes, like a tiny Blocky.</summary>
    static FXActor Blocky()
    {
        var px = Enumerable.Repeat(FX.Hex("#ff8a3d"), 100).ToArray();
        for (var i = 0; i < 10; i++) { px[i] = px[90 + i] = px[i * 10] = px[i * 10 + 9] = FX.Hex("#3b1f0f"); }
        px[35] = px[37] = px[45] = px[47] = FX.Black;
        return new FXActor(10, 10, px);
    }

    [Fact]
    public void AnEffectFrameIsWholePixelsAndLeavesTheCreatureInPlace()
    {
        var a = Blocky();
        foreach (var (id, type) in FXCatalog.All.OrderBy(e => e.Key, StringComparer.Ordinal))
        {
            var o = new FXOptions(type.Meta, a, 5) { X = type.Meta.Origin.X, Y = type.Meta.Origin.Y };
            var fx = new FXInstance(type, o);
            var whole = new FXFrame(type.Meta.Size.W, type.Meta.Size.H);
            var behind = new FXFrame(type.Meta.Size.W, type.Meta.Size.H);
            int ax = (int)o.X + a.X, ay = (int)o.Y + a.Y;
            var t = 0.0;
            foreach (var step in new[] { 0.2, 0.5, 0.7, 0.6 })
            {
                fx.Update(step); t += step;
                var shown = fx.Render(whole);
                var rgba = FXComposite.Rgba(whole);
                for (var k = 3; k < rgba.Length; k += 4) Assert.True(rgba[k] is 0 or 255, $"{id} at {t} s");
                if (!shown) continue;
                // What is behind it never paints over it: back and creature alone, the creature is all there.
                behind.Clear();
                fx.Draw(behind, FXLayer.Back);
                for (var yy = 0; yy < a.H; yy++)
                    for (var xx = 0; xx < a.W; xx++)
                        if (a.Pixels[yy * a.W + xx] != 0) behind.Color[(ay + yy) * behind.W + ax + xx] = a.Pixels[yy * a.W + xx];
                // Where the front left the creature alone, the picture is the creature's own colour, exactly.
                for (var yy = 0; yy < a.H; yy++)
                    for (var xx = 0; xx < a.W; xx++)
                    {
                        var c = a.Pixels[yy * a.W + xx];
                        var i = (ay + yy) * whole.W + ax + xx;
                        if (c == 0 || whole.Color[i] != behind.Color[i] || whole.Light[i] != 0) continue;
                        Assert.True(rgba[i * 4] == (c & 255) && rgba[i * 4 + 1] == ((c >> 8) & 255) && rgba[i * 4 + 2] == ((c >> 16) & 255) && rgba[i * 4 + 3] == 255,
                                    $"{id}: the creature's pixel at {xx},{yy} moved or changed");
                    }
            }
        }
    }

    [Fact]
    public void TheNativePortStepsLikePixelfx()
    {
        // pixelfx's mulberry32 and hash, number for number, as the Mac's test has them.
        Assert.Equal("0.720226783771", new Rng(3).Next().ToString("F12", System.Globalization.CultureInfo.InvariantCulture));
        Assert.Equal(2_901_138_804u, FX.Hash(1, 2, 3));
        Assert.True(FX.Round(-2.5) == -2 && FX.Round(2.5) == 3);
        Assert.True(FX.I32(-1.5) == -1 && FX.Byte(-1.5) == 255 && FX.I32(4_294_967_297) == 1);
    }
}
