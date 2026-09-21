using System.Text.Json;
using System.Text.Json.Serialization;

namespace Ledgelings.Core;

/// <summary>ISO-8601 in UTC with a trailing Z, the way the macOS app writes its files,
/// so a log written on one platform reads on the other.</summary>
public sealed class IsoTimeConverter : JsonConverter<DateTimeOffset>
{
    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => DateTimeOffset.Parse(reader.GetString() ?? throw new JsonException("time"), null, System.Globalization.DateTimeStyles.RoundtripKind);

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options)
        => writer.WriteStringValue(value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"));
}

public static class JsonLines
{
    /// <summary>camelCase keys, nulls left out, dates as ISO-8601 UTC.</summary>
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new IsoTimeConverter() },
    };

    /// <summary>Append one object as a line, making the folder if needed.</summary>
    public static void Append<T>(string file, T record)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        var line = JsonSerializer.Serialize(record, Options) + "\n";
        File.AppendAllText(file, line, new System.Text.UTF8Encoding(false));
    }

    /// <summary>Every line that parses, in file order. A damaged line is skipped.</summary>
    public static List<T> Read<T>(string file)
    {
        var found = new List<T>();
        if (!File.Exists(file)) return found;
        foreach (var line in File.ReadAllLines(file))
        {
            if (line.Trim().Length == 0) continue;
            try
            {
                var item = JsonSerializer.Deserialize<T>(line, Options);
                if (item is not null) found.Add(item);
            }
            catch (JsonException) { }
        }
        return found;
    }
}
