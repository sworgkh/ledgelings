using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Patience: pushed around by the cursor too often in a row, a creature tells the user off.</summary>
public sealed partial class AppSettings
{
    /// <summary>Times in a row a creature can be chased by the cursor or picked up before it complains.</summary>
    public const int ComplainAfterMin = 1, ComplainAfterMax = 20;
    /// <summary>Seconds of peace that start its count over.</summary>
    public const double ComplainCalmMin = 5, ComplainCalmMax = 120;

    private bool complainEnabled;
    private int complainAfter;
    private double complainCalmSeconds;
    private CursorMood cursorMood;

    private void LoadPatience()
    {
        complainEnabled = store.Get<bool?>("complainEnabled") ?? true;
        // Four: the owner's own number. The fifth chase in a row gets a complaint.
        complainAfter = Math.Clamp(store.Get<int?>("complainAfter") ?? 4, ComplainAfterMin, ComplainAfterMax);
        // Twenty seconds: chasing one creature round the screen is a streak; the same thing an hour apart is not.
        complainCalmSeconds = Math.Clamp(store.Get<double?>("complainCalmSeconds") ?? 20, ComplainCalmMin, ComplainCalmMax);
        // A menace: how the creatures were first written, so nobody's colony changes its mind unasked.
        cursorMood = CursorMoods.FromCode(store.Get<string>("cursorMood")) ?? CursorMood.Bad;
    }

    /// <summary>Pushed around by the cursor too often in a row, a creature tells the user off.</summary>
    public bool ComplainEnabled { get => complainEnabled; set => Put(ref complainEnabled, value, "complainEnabled"); }
    public int ComplainAfter { get => complainAfter; set => Put(ref complainAfter, Math.Clamp(value, ComplainAfterMin, ComplainAfterMax), "complainAfter"); }
    public double ComplainCalmSeconds { get => complainCalmSeconds; set => Put(ref complainCalmSeconds, Math.Clamp(value, ComplainCalmMin, ComplainCalmMax), "complainCalmSeconds"); }

    /// <summary>What the creatures make of the cursor (SPEC §6.1.2): a playmate, nothing at all, or a menace.
    /// The app hands it to <see cref="CursorMoods.Choose"/>; prompts, built-in lines and complaints follow it.</summary>
    public CursorMood CursorMood
    {
        get => cursorMood;
        set
        {
            if (cursorMood == value) return;
            cursorMood = value;
            store.Set("cursorMood", value.Code());
            Raise(nameof(CursorMood));
        }
    }
}
