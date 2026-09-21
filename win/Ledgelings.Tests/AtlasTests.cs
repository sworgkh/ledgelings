using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Ledgelings.Tests;

public class AtlasTests
{
    /// <summary>Every distinct opaque colour in an image.</summary>
    private static HashSet<RGB> Colours(Bitmap image)
    {
        var found = new HashSet<RGB>();
        var data = image.LockBits(new Rectangle(0, 0, image.Width, image.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            var row = new byte[data.Stride];
            for (int y = 0; y < image.Height; y++)
            {
                Marshal.Copy(data.Scan0 + y * data.Stride, row, 0, data.Stride);
                for (int x = 0; x < image.Width; x++)
                {
                    var i = x * 4;   // BGRA
                    if (row[i + 3] == 255) found.Add(new RGB(row[i + 2], row[i + 1], row[i]));
                }
            }
        }
        finally { image.UnlockBits(data); }
        return found;
    }

    [Fact]
    public void HexRoundTrips()
    {
        Assert.Equal("#3dc7b5", RGB.FromHex("#3dc7b5")?.Hex);
        Assert.Null(RGB.FromHex("nope"));
    }

    [Fact]
    public void EveryAnimationTheBrainAsksForHasFramesForEveryEyeState()
    {
        var frames = SpriteAtlas.Named("blocky").MakeFrames();
        foreach (var animation in new[] { "walk", "idle", "jump", "land", "sleep" })
            foreach (var eyes in new[] { Eyes.Open, Eyes.Half, Eyes.Closed })
                Assert.True(frames.Frame(animation, 0.7, eyes) is not null, $"{animation} {eyes}");
        Assert.NotNull(SpriteAtlas.Named("zzz").MakeFrames().Frame("float", 0));
    }

    [Fact]
    public void RecolouringSwapsTheBodyAndLeavesTheEyesBlack()
    {
        var atlas = SpriteAtlas.Named("blocky");
        RGB orange = RGB.FromHex("#ff8a3d")!.Value, teal = RGB.FromHex("#3dc7b5")!.Value;

        var plain = Colours(atlas.MakeFrames().Frame("idle", 0)!);
        Assert.Contains(orange, plain);

        var tinted = Colours(atlas.MakeFrames(teal).Frame("idle", 0)!);
        Assert.Contains(teal, tinted);
        Assert.DoesNotContain(orange, tinted);
        Assert.Contains(RGB.Black, tinted);
        Assert.Equal(plain.Count, tinted.Count);      // body, light, shade, outline, eyes -- nothing smeared
    }

    [Fact]
    public void EveryFlowerTheColonyCanGiveIsInTheSheet()
    {
        var frames = SpriteAtlas.Named("flowers").MakeFrames();
        Assert.Equal(10, Gifts.Flowers.Count);
        foreach (var flower in Gifts.Flowers)
            Assert.True(frames.Frame(flower, 0) is not null, flower);
    }

    [Fact]
    public void TheHouseIsInItsSheet()
    {
        var house = SpriteAtlas.Named("house");
        Assert.NotNull(house.MakeFrames().Frame("house", 0));
        Assert.True(house.CellSize.Width >= 32 && house.CellSize.Height >= 32);
    }
}
