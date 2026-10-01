using System.Text;
using System.Text.RegularExpressions;

namespace Ledgelings.Core;

/// <summary>
/// Voices for the characters (Sources/LedgelingsCore/Voices.swift). Only the part the
/// chat log needs is here so far: the words of a line as they are said out loud, which
/// is how a voice charge finds its conversation. The rest of the Swift file (handing
/// out voices, cartoon pitch) is ported with the voice; keep this class partial.
/// </summary>
public static partial class Voices
{
    /// <summary>The line as it should be heard: no emoji, no *stage directions*, no
    /// markdown marks, no runs of spaces. Empty when nothing sayable is left.</summary>
    public static string Speakable(string line)
    {
        var text = Regex.Replace(line, @"\*\*(.+?)\*\*", "$1");       // **bold** is said
        text = Regex.Replace(text, @"\*[^*]+\*", " ");                 // *sighs* is not
        var kept = new StringBuilder(text.Length);
        foreach (var rune in text.EnumerateRunes())
        {
            var v = rune.Value;
            if (IsEmoji(v) || v == 0xFE0F || v == 0x200D || "*_~`#".Contains((char)Math.Min(v, 0xFFFF))) continue;
            kept.Append(rune.ToString());
        }
        var words = kept.ToString().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        return Regex.Replace(string.Join(" ", words), @" ([.,!?;:])", "$1");
    }
}
