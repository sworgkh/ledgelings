// Every effect ported from pixelfx, by its pixelfx name ("status/frozen"), for the styles and moments
// and for the films and checks that play them by name. Unlike the Mac's generated FXCatalog.swift, this
// one finds the effects itself: every class in this assembly that implements IFXEffect, has
// `public static readonly FXMeta Meta` and a constructor taking FXOptions. A new effect file needs no
// other change.

using System.Reflection;

namespace Ledgelings.Core.PixelFX;

/// <summary>An effect class: its meta and how to make one.</summary>
public sealed record FXEffectType(Type Type, FXMeta Meta, Func<FXOptions, IFXEffect> Make)
{
    /// <summary>The entry for an effect class, by its type.</summary>
    public static FXEffectType Of<T>() where T : IFXEffect => Of(typeof(T)) ?? throw new ArgumentException($"{typeof(T).Name} is not a complete effect");

    public static FXEffectType? Of(Type t)
    {
        if (t.IsAbstract || t.IsInterface || !typeof(IFXEffect).IsAssignableFrom(t)) return null;
        var meta = t.GetField("Meta", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)?.GetValue(null) as FXMeta;
        var ctor = t.GetConstructor(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance, [typeof(FXOptions)]);
        if (meta == null || ctor == null) return null;
        return new FXEffectType(t, meta, o => (IFXEffect)ctor.Invoke([o]));
    }
}

public static class FXCatalog
{
    /// <summary>Every effect, by its pixelfx id.</summary>
    public static readonly IReadOnlyDictionary<string, FXEffectType> All = Scan(typeof(FXCatalog).Assembly);

    /// <summary>Every effect in an assembly (the checker also scans its own, for effects still being ported).</summary>
    public static Dictionary<string, FXEffectType> Scan(Assembly assembly)
    {
        var all = new Dictionary<string, FXEffectType>();
        foreach (var t in assembly.GetTypes())
        {
            if (FXEffectType.Of(t) is not { } e) continue;
            if (all.TryGetValue(e.Meta.Id, out var other))
                throw new InvalidOperationException($"Two effects are called {e.Meta.Id}: {other.Type.Name} and {t.Name}");
            all[e.Meta.Id] = e;
        }
        return all;
    }
}
