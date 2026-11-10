using System.Drawing;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The button for one frame, in GLOBAL coordinates (y up): on overlay <c>Overlay</c>, its picture at
/// <c>Scale</c> screen pixels per pixel, and its tag under it while the pointer rests on it.</summary>
public sealed record StopButtonSnapshot(int Overlay, Bitmap Image, Rect Frame, double Scale, Bitmap? Tag, Rect TagFrame);

/// <summary>The Stop button (SPEC §7.17), drawn on the overlay while an activity runs (<see cref="Activities"/>): in the
/// top-right corner of the monitor the activity is on, under a taskbar along the top and clear of a score board. The
/// only part of the overlay a click lands on outside the creatures; the click stops the activity. Hovering it shows
/// its tag under it, drawn in the overlay: a WPF ToolTip has no element to hang on in this layered window. The Mac's
/// <c>Colony+StopButton</c>.</summary>
public sealed partial class Colony
{
    /// <summary>Whether the pointer rests on the button.</summary>
    internal bool StopButtonHovered { get; private set; }
    private (string Label, Bitmap? Plain, Bitmap? Hovered, Bitmap? Tag)? stopButtonImages;

    /// <summary>The shortcut in words, or null while it is off.</summary>
    internal string? StopShortcutSpoken =>
        Settings.StopActivityShortcutEnabled ? ShortcutKeys.Spoken(Settings.StopActivityShortcut) : null;

    /// <summary>The button as it stands now; null while nothing runs or the button is switched off.</summary>
    internal StopButtonSnapshot? StopButtonNow()
    {
        if (!Settings.StopButtonShown || !Activities.Shared.IsRunning || overlays.Count == 0) return null;
        var label = StopButton.Label(StopShortcutSpoken);
        if (stopButtonImages?.Label != label)
        {
            if (stopButtonImages is { } old) { old.Plain?.Dispose(); old.Hovered?.Dispose(); old.Tag?.Dispose(); }
            stopButtonImages = (label, StopButtonPainter.Button(label, hovered: false), StopButtonPainter.Button(label, hovered: true),
                                StopButtonPainter.Tag(StopButton.Tag(StopShortcutSpoken)));
        }
        if (stopButtonImages is not { Plain: Bitmap plain } images) return null;
        var k = ActivityOverlay();
        var monitor = overlays[k].Monitor;
        var scale = Math.Max(2, Math.Round(2 * monitor.DpiScale));
        var boards = PlayProps().Where(p => p.Size is not null).Select(p =>
        {
            double w = p.Size!.Value.Width * p.Scale, h = p.Size!.Value.Height * p.Scale;
            return new Rect(p.Position.X - w / 2, p.Position.Y - h / 2, w, h);
        }).ToList();
        var frame = StopButton.Frame(plain.Width * scale, plain.Height * scale, monitor.Frame, monitor.TopInset, boards);
        var hovered = StopButtonHovered;
        Bitmap? tag = hovered ? images.Tag : null;
        var tagFrame = tag is null ? default
            : new Rect(frame.MaxX - tag.Width * scale, frame.MinY - 6 - tag.Height * scale, tag.Width * scale, tag.Height * scale);
        return new StopButtonSnapshot(k, hovered && images.Hovered is Bitmap lit ? lit : plain, frame, scale, tag, tagFrame);
    }

    /// <summary>The overlay of the monitor the activity is on: the players' for a game or a surf, the water's for a
    /// dive (its first pool, when it covers every monitor), else the first.</summary>
    private int ActivityOverlay()
    {
        Pt? at = null;
        if (play is { } s && s.Players.Length > 0 && s.Players[0] < creatures.Count) at = creatures[s.Players[0]].Position;
        else if (dive is { } d && d.Model.Pools.Count > 0) at = new Pt(d.Model.Pools[0].X + d.Model.Pools[0].Width / 2, d.Model.Pools[0].Y + d.Model.Pools[0].Height / 2);
        if (at is not Pt p) return 0;
        var k = overlays.FindIndex(o => o.Monitor.Frame.Contains(p));
        return k < 0 ? 0 : k;
    }

    /// <summary>Whether <paramref name="point"/> (global) is on the Stop button.</summary>
    internal bool OnStopButton(Pt point) => StopButtonNow() is { } b && b.Frame.Contains(point);

    /// <summary>A click on the Stop button: whatever runs stops, as the shortcut does.</summary>
    internal void PressStopButton()
    {
        var stopped = Activities.Shared.StopAll("the Stop button");
        Trace?.Invoke($"stop button pressed: {(stopped.Count == 0 ? "nothing running" : string.Join(", ", stopped.Select(k => k.ToString().ToLowerInvariant())))}");
        StopButtonHovered = false;
    }
}

/// <summary>The Stop button and its tag drawn in pixels, in the game's style: a flat plate, a 1-pixel dark outline,
/// a light line along the top and left, a shade line along the bottom and right; the stop sign beside the words.
/// The Mac's <c>StopButtonPainter</c>, the same colours.</summary>
public static class StopButtonPainter
{
    /// <summary>The plate: the score board's dark blue, a step lighter under the pointer.</summary>
    public static readonly Color Plate = Color.FromArgb(46, 50, 74), PlateHovered = Color.FromArgb(72, 78, 112);
    public static readonly Color Ink = Color.FromArgb(250, 240, 214);
    private static readonly Dictionary<char, Color> SignColours = new()
    {
        ['o'] = Color.FromArgb(70, 16, 20), ['l'] = Color.FromArgb(238, 110, 100), ['r'] = Color.FromArgb(204, 46, 40),
        ['s'] = Color.FromArgb(150, 30, 28), ['w'] = Color.FromArgb(255, 250, 240),
    };

    public static Bitmap? Button(string label, bool hovered)
    {
        using var words = PixelText.Image(label, new PixelText.Style(Ink, null, 9));
        if (words is null) return null;
        var sign = StopButton.Icon;
        int signW = sign.Max(r => r.Length), signH = sign.Length, pad = 4, gap = 4;
        int w = pad + signW + gap + words.Width + pad, h = Math.Max(signH, words.Height) + pad * 2;
        var made = PlateOf(w, h, hovered ? PlateHovered : Plate);
        for (int y = 0; y < signH; y++)
            for (int x = 0; x < sign[y].Length; x++)
                if (SignColours.TryGetValue(sign[y][x], out var c)) made.SetPixel(pad + x, (h - signH) / 2 + y, c);
        int top = (h - words.Height) / 2;
        for (int y = 0; y < words.Height; y++)
            for (int x = 0; x < words.Width; x++)
                if (words.GetPixel(x, y) is { A: > 0 } p) made.SetPixel(pad + signW + gap + x, top + y, p);
        return made;
    }

    public static Bitmap? Tag(string text) => PixelText.Image(text, new PixelText.Style(Ink, Plate, 9));

    private static Bitmap PlateOf(int w, int h, Color plate)
    {
        static Color Mix(Color c, int to, double share) => Color.FromArgb(
            (int)(c.R + (to - c.R) * share), (int)(c.G + (to - c.G) * share), (int)(c.B + (to - c.B) * share));
        var made = new Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                var edge = x == 0 || y == 0 || x == w - 1 || y == h - 1;
                made.SetPixel(x, y, edge ? Mix(plate, 0, 0.6) : x == 1 || y == 1 ? Mix(plate, 255, 0.25)
                    : x == w - 2 || y == h - 2 ? Mix(plate, 0, 0.25) : plate);
            }
        return made;
    }
}
