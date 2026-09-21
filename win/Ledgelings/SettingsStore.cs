using System.Text.Json;
using System.Text.Json.Nodes;

namespace Ledgelings;

/// <summary>A key-value store for settings: the JSON file in the app's folder, or memory for tests.</summary>
public interface ISettingsStore
{
    T? Get<T>(string key);
    void Set<T>(string key, T value);
    void Remove(string key);
}

/// <summary>One JSON object in <c>%APPDATA%\Ledgelings\settings.json</c>, rewritten on every change.</summary>
public sealed class JsonSettingsStore : ISettingsStore
{
    public string Path { get; }
    private readonly JsonObject root;

    public JsonSettingsStore(string path)
    {
        Path = path;
        try { root = File.Exists(path) ? JsonNode.Parse(File.ReadAllText(path)) as JsonObject ?? new JsonObject() : new JsonObject(); }
        catch (JsonException) { root = new JsonObject(); }
    }

    public T? Get<T>(string key)
    {
        if (!root.TryGetPropertyValue(key, out var node) || node is null) return default;
        try { return node.Deserialize<T>(); } catch (JsonException) { return default; } catch (InvalidOperationException) { return default; }
    }

    public void Set<T>(string key, T value)
    {
        root[key] = JsonSerializer.SerializeToNode(value);
        Save();
    }

    public void Remove(string key)
    {
        if (root.Remove(key)) Save();
    }

    private void Save()
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
            File.WriteAllText(Path, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (IOException e) { Console.Error.WriteLine("Ledgelings settings: " + e.Message); }
    }
}

public sealed class MemorySettingsStore : ISettingsStore
{
    private readonly Dictionary<string, JsonNode?> items = new();
    public T? Get<T>(string key) => items.TryGetValue(key, out var node) && node is not null ? node.Deserialize<T>() : default;
    public void Set<T>(string key, T value) => items[key] = JsonSerializer.SerializeToNode(value);
    public void Remove(string key) => items.Remove(key);
    public bool Has(string key) => items.ContainsKey(key);
}

/// <summary>Where the app keeps its files: <c>%APPDATA%\Ledgelings</c>.</summary>
public static class AppFolders
{
    public static string Root => System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Ledgelings");
    public static string Chats => System.IO.Path.Combine(Root, "chats");
    public static string Sprites => System.IO.Path.Combine(Root, "sprites");
    public static string SettingsFile => System.IO.Path.Combine(Root, "settings.json");
}
