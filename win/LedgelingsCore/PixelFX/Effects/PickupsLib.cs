// Shared by the pickup effects: pixelfx's `fx/pickups/_lib.js` (MIT), the parts the ported effects use.
// The Mac's twin is PickupsLib.swift.

namespace Ledgelings.Core.PixelFX;

public static class FXPickups
{
    /// <summary>A four-point star glint: arms of arm px in c, dimmer tips, a white heart, its own light.</summary>
    public static void Glint(Painter p, double x, double y, double arm, FXColor c, double k = 0.4, FXColor? tip = null)
    {
        var tp = tip ?? FX.Scale(c, 0.8);
        double n = FX.Round(arm), X = FX.Floor(x), Y = FX.Floor(y);
        if (n < 0) return;
        for (var d = 1.0; d <= n; d++)
        {
            var cc = d == n && n > 1 ? tp : c;
            p.Px(X + d, Y, cc); p.Px(X - d, Y, cc); p.Px(X, Y + d, cc); p.Px(X, Y - d, cc);
        }
        p.Px(X, Y, n > 0 ? FX.White : c);
        p.Glow(X + 0.5, Y + 0.5, 3 + n * 2.5, c, k);
    }
}
