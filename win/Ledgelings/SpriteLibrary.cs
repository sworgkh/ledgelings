using System.Text.Json;
using System.Text.RegularExpressions;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>
/// Every creature sheet the app can use: the built-in ones, plus whatever the
/// user imported into <c>%APPDATA%\Ledgelings\sprites\&lt;name&gt;\</c>.
///
/// An import takes either the text format (<see cref="SpriteText"/>) or a painted PNG in
/// the same 288×96 layout on magenta, and writes a normal atlas (PNG + JSON)
/// the app loads like its own.
/// </summary>
public sealed partial class SpriteLibrary
{
    public sealed record Species(string Name, bool IsBuiltIn, SpriteAtlas Atlas);

    public sealed class ImportException : Exception
    {
        public ImportException(string message) : base(message) { }
    }

    /// <summary>The sheets shipped in the app, in the order the Sprites tab shows them.</summary>
    public static readonly IReadOnlyList<string> BuiltIn = new[] { "blocky", "frog", "cat", "ghost", "slime", "robot", "triangle", "mushroom" };

    public static readonly SpriteText.Tint KeyColour = new(255, 0, 255);
    public const int KeyTolerance = 60;

    public string Directory { get; }
    public IReadOnlyList<Species> AllSpecies { get; private set; } = Array.Empty<Species>();
    public event Action? Changed;

    public SpriteLibrary(string? directory = null)
    {
        Directory = directory ?? AppFolders.Sprites;
        Reload();
    }

    public void Reload()
    {
        var found = new List<Species>();
        foreach (var name in BuiltIn)
        {
            try { found.Add(new Species(name, true, SpriteAtlas.Named(name))); }
            catch (Exception e) when (e is IOException or InvalidDataException or JsonException) { Console.Error.WriteLine($"Ledgelings: sheet {name}: {e.Message}"); }
        }
        if (System.IO.Directory.Exists(Directory))
        {
            foreach (var folder in System.IO.Directory.GetDirectories(Directory).OrderBy(f => f, StringComparer.Ordinal))
            {
                var name = Path.GetFileName(folder);
                if (BuiltIn.Contains(name)) continue;
                try { found.Add(new Species(name, false, new SpriteAtlas(folder, name))); }
                catch (Exception e) when (e is IOException or InvalidDataException or JsonException) { Console.Error.WriteLine($"Ledgelings: sheet {name}: {e.Message}"); }
            }
        }
        AllSpecies = found;
        Changed?.Invoke();
    }

    public SpriteAtlas? Atlas(string name) => AllSpecies.FirstOrDefault(s => s.Name == name)?.Atlas;

    /// <summary>What a species is, for the prompt: from its sheet, or the built-in wording.</summary>
    public string Kind(string name)
    {
        if (name == "blocky") return Banter.DefaultKind;
        return Atlas(name)?.Info.Kind ?? "a small pixel creature";
    }

    /// <summary>Who a species' creatures are, before the user edits them.</summary>
    public IReadOnlyList<Character> Cast(string name)
    {
        if (name == "blocky") return Banter.DefaultCharacters;
        var cast = Atlas(name)?.Info.Cast ?? new List<Character>();
        return cast.Count == 0 ? new[] { new Character(Capitalised(name), "Curious and new here.") } : cast;
    }

    private static string Capitalised(string name) => name.Length == 0 ? name : char.ToUpperInvariant(name[0]) + name[1..];

    /// <summary>What a creature of this species is painted in: the sheet's own colour when
    /// it names one, otherwise <paramref name="slot"/>, the colour of the creature's number.</summary>
    public RGB BodyColour(string name, RGB slot) => RGB.FromHex(Atlas(name)?.Info.Colour) ?? slot;

    /// <summary>Import a text sheet or a painted PNG. Returns the species name.</summary>
    public string ImportFile(string path)
    {
        var ext = Path.GetExtension(path).ToLowerInvariant();
        SpriteText.Image sheet;
        string name;
        string? kind = null;
        IReadOnlyList<Character> cast = Array.Empty<Character>();
        SpriteText.Tint? colour = null;
        string? sourceText = null;
        if (ext == ".png")
        {
            SpriteText.Image raw;
            try { raw = PngIO.Read(path); }
            catch (Exception e) when (e is ArgumentException or IOException or OutOfMemoryException) { throw new ImportException("cannot read " + Path.GetFileName(path) + ": " + e.Message); }
            sheet = KeyedOut(raw);
            name = Path.GetFileNameWithoutExtension(path).ToLowerInvariant();
        }
        else if (ext is ".txt" or ".md" or ".text" or "")
        {
            string text;
            try { text = File.ReadAllText(path); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { throw new ImportException("cannot read " + Path.GetFileName(path) + ": " + e.Message); }
            SpriteText.Sheet parsed;
            try { parsed = SpriteText.Parse(text); }
            catch (SpriteText.ParseException e) { throw new ImportException(e.Message); }
            sheet = SpriteText.Pixels(parsed, SpriteText.Palette.Blocky);
            name = parsed.Name;
            kind = parsed.Kind;
            cast = parsed.Cast;
            colour = parsed.Colour;
            sourceText = text;
        }
        else throw new ImportException(Path.GetFileName(path) + " is neither a sprite text file (.txt, .md) nor a PNG");

        if (!Regex.IsMatch(name, "^[a-z0-9][a-z0-9-]*$") || BuiltIn.Contains(name))
            throw new ImportException($"\"{name}\" cannot be used: lowercase letters, digits and dashes only, and not a built-in name");
        var folder = Path.Combine(Directory, name);
        System.IO.Directory.CreateDirectory(folder);
        PngIO.Write(sheet, Path.Combine(folder, name + ".png"));
        var meta = SpriteText.Atlas(name, kind: kind, cast: cast, colour: colour);
        File.WriteAllText(Path.Combine(folder, name + ".json"), meta.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        if (sourceText is not null) File.WriteAllText(Path.Combine(folder, name + ".txt"), sourceText);
        Reload();
        return name;
    }

    public void Remove(string name)
    {
        var found = AllSpecies.FirstOrDefault(s => s.Name == name);
        if (found is null || found.IsBuiltIn) return;
        try { System.IO.Directory.Delete(Path.Combine(Directory, name), true); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Console.Error.WriteLine("Ledgelings: " + e.Message); }
        Reload();
    }

    public void OpenFolder()
    {
        System.IO.Directory.CreateDirectory(Directory);
        Shell.OpenFolder(Directory);
    }
}
