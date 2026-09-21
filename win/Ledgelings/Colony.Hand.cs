using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The user's hand: clicks, pokes, drags and what the overlay lets through.</summary>
public sealed partial class Colony
{
    /// <summary>The topmost creature whose body is under <paramref name="point"/>.</summary>
    private int? CreatureAt(Pt point)
    {
        for (int i = creatures.Count - 1; i >= 0; i--)
        {
            if (hideout.IsInside(i)) continue;
            var half = atlas.BodyHalfSize * sizes[i] + 4;      // a little forgiveness
            var p = creatures[i].Position;
            if (Math.Abs(point.X - p.X) <= half && Math.Abs(point.Y - p.Y) <= half) return i;
        }
        return null;
    }

    /// <summary>A plain press on a sleeper picks it up. A Shift-press is a poke if it lets
    /// go where it started, a carry if it moves. Right-click naps or wakes. A press
    /// on a speech bubble closes it.</summary>
    private void Hand(HandEvent e)
    {
        switch (e)
        {
            case HandEvent.Down(var point, var shift):
                if (CreatureAt(point) is not int i)
                {
                    if (BubbleAt(point) is int spoken) bubbles.Remove(spoken);
                    break;
                }
                if (shift) poke = (i, point);          // decided on release: a poke, or a drag
                else if (creatures[i].PickUp())
                {
                    var p = creatures[i].Position;
                    held = (i, new Vec(p.X - point.X, p.Y - point.Y));
                }
                break;
            case HandEvent.Dragged(var point):
                if (poke is { } pending && point.DistanceTo(pending.At) >= DragThreshold)
                {
                    poke = null;
                    if (pending.Index < creatures.Count && creatures[pending.Index].PickUp(evenAwake: true))
                    {
                        var p = creatures[pending.Index].Position;
                        held = (pending.Index, new Vec(p.X - pending.At.X, p.Y - pending.At.Y));
                    }
                }
                if (held is not { } h) return;
                creatures[h.Index].Drag(new Pt(point.X + h.Grab.Dx, point.Y + h.Grab.Dy));
                break;
            case HandEvent.Up:
                if (poke is { } tap) { poke = null; TalkNow(tap.Index); }
                LetGo();
                break;
            case HandEvent.SecondaryDown(var point):
                if (CreatureAt(point) is int j) creatures[j].ToggleNap(rng);
                break;
        }
        Render();      // follow the hand at the mouse's rate, not the frame clock's
    }

    private void LetGo()
    {
        if (held is { } h && h.Index < creatures.Count) creatures[h.Index].Drop();
        held = null;
    }

    /// <summary>Make an overlay clickable only while the cursor is on something the user
    /// can act on: any sleeper, any creature at all while Shift is down, or a
    /// speech bubble. Shift is also how you get close enough to right-click one.</summary>
    private void UpdateClickability(Pt cursor, bool shift)
    {
        var under = CreatureAt(cursor);
        var target = held is not null || (under is int i && (shift || creatures[i].IsSleeping)) || BubbleAt(cursor) is not null;
        foreach (var overlay in overlays) overlay.SetClickable(target && overlay.Monitor.Frame.Contains(cursor));
    }
}
