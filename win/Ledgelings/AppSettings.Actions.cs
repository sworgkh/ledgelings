namespace Ledgelings;

/// <summary>The Creature Actions sheet the tray menu opens.</summary>
public sealed partial class AppSettings
{
    private bool actionsStayOpen;

    private void LoadActions()
    {
        // On: the sheet is somewhere to play from, so it waits for another go until Done.
        actionsStayOpen = store.Get<bool?>("actionsStayOpen") ?? true;
    }

    /// <summary>The Creature Actions sheet stays up after a tile is pressed, for another go. Off: it folds away.</summary>
    public bool ActionsStayOpen { get => actionsStayOpen; set => Put(ref actionsStayOpen, value, "actionsStayOpen"); }
}
