namespace Ledgelings.Core;

/// <summary>
/// What the clipboard picker shows and where its selection is (SPEC §7.11): the rows for a search, grouped
/// RECENT and SNIPPETS with the shortcut's group first, the chosen row, and the moves the keys make. Kept here,
/// out of the window, so it is tested without one; the Mac keeps the same logic in <c>ClipPickerModel</c>.
/// </summary>
public sealed class ClipPicker
{
    public enum Group { Recent, Snippets }

    /// <param name="Text">The words on one line, or dots for a protected snippet.</param>
    /// <param name="Detail">Where it came from and when, or the snippet's folder.</param>
    /// <param name="Masked">A copy of a protected snippet's words: <paramref name="Text"/> is its mask, the row a shade apart.</param>
    public sealed record Row(Guid Id, Group Group, string Text, string Detail, string? Title, bool Pinned, bool Protected, bool Masked = false);

    private readonly Func<(Clipboard.History History, Clipboard.SnippetBook Snippets)> source;

    public ClipPicker(Func<(Clipboard.History, Clipboard.SnippetBook)> source) { this.source = source; }

    public string Query { get; private set; } = "";
    public Group First { get; set; } = Group.Recent;
    public IReadOnlyList<Row> Rows { get; private set; } = Array.Empty<Row>();
    public Guid? Selected { get; set; }
    public (int Recent, int Snippets) Counts { get; private set; }
    public Row? SelectedRow => Rows.FirstOrDefault(r => r.Id == Selected);

    /// <summary>A new search: the rows again, the first of the first group chosen.</summary>
    public void Search(string query)
    {
        if (query == Query && Rows.Count > 0) return;
        Query = query;
        Refresh(selectFirst: true);
    }

    /// <summary>The rows again, after a search or a change: the first chosen, or the same one kept, or the one now
    /// at <paramref name="keeping"/>'s place when that row went.</summary>
    public void Refresh(bool selectFirst = false, int? keeping = null, DateTimeOffset? now = null)
    {
        var (history, snippets) = source();
        var found = Clipboard.Search(Query, history, snippets);
        var at = now ?? DateTimeOffset.Now;
        var recent = found.Clips.Select(c => snippets.MaskFor(c) is { } mask
            ? new Row(c.Id, Group.Recent, mask, Detail(c, at), null, c.Pinned, false, Masked: true)
            : new Row(c.Id, Group.Recent, c.Preview(90), Detail(c, at), null, c.Pinned, false)).ToList();
        var saved = found.Snippets.Select(s => new Row(s.Id, Group.Snippets, s.Preview(90), snippets.FolderOf(s.Id)?.Title ?? "", s.Title, false, s.Protected)).ToList();
        Rows = First == Group.Recent ? recent.Concat(saved).ToList() : saved.Concat(recent).ToList();
        Counts = (recent.Count, saved.Count);
        if (keeping is int index && Rows.Count > 0 && SelectedRow is null) Selected = Rows[Math.Min(index, Rows.Count - 1)].Id;
        else if (selectFirst || SelectedRow is null) Selected = (Rows.FirstOrDefault(r => r.Group == First) ?? Rows.FirstOrDefault())?.Id;
    }

    public void Step(int by)
    {
        if (Rows.Count == 0) return;
        var at = Math.Max(0, Rows.ToList().FindIndex(r => r.Id == Selected));
        Selected = Rows[Math.Clamp(at + by, 0, Rows.Count - 1)].Id;
    }

    /// <summary>Tab: to the first row of the other group.</summary>
    public void JumpGroup()
    {
        var current = SelectedRow?.Group ?? First;
        if (Rows.FirstOrDefault(r => r.Group != current) is { } row) Selected = row.Id;
    }

    /// <summary>The row wearing number <paramref name="n"/> (1–9): the first nine rows.</summary>
    public Row? Numbered(int n) => n >= 1 && n <= Rows.Count && n <= 9 ? Rows[n - 1] : null;

    /// <summary>"Notepad · 5 min", "FILES · Explorer · now".</summary>
    public static string Detail(Clipboard.Clip clip, DateTimeOffset now)
    {
        var parts = new List<string>();
        if (clip.Kind == Clipboard.Kind.Files) parts.Add(L10n.Tr("FILES"));
        if (!string.IsNullOrEmpty(clip.App)) parts.Add(clip.App);
        parts.Add(Ago(clip.CopiedAt, now));
        return string.Join(" · ", parts);
    }

    public static string Ago(DateTimeOffset date, DateTimeOffset now)
    {
        var seconds = Math.Max((now - date).TotalSeconds, 0);
        return seconds switch
        {
            < 60 => L10n.Tr("now"),
            < 3600 => L10n.Tr("%d min", (int)(seconds / 60)),
            < 86_400 => L10n.Tr("%d h", (int)(seconds / 3600)),
            _ => L10n.Tr("%d d", (int)(seconds / 86_400)),
        };
    }
}
