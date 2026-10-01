using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>
/// XAML text in the current language (SPEC §1.2). The English is written in the markup,
/// <c>ui:Tr.Text="How many"</c>, <c>ui:Tr.Header="Creatures"</c>, and goes through
/// <see cref="L10n.Tr"/> into the element; <see cref="Refresh"/> puts every such element
/// into a newly chosen language. Inside data templates too: each copy registers as it is made.
///
/// A number with its unit: <c>ui:Tr.Value="{Binding DayMinutes}" ui:Tr.Unit=" min"</c>, or
/// <c>ui:Tr.Format="%d in a row"</c>, or <c>ui:Tr.Count="token|tokens"</c>; <c>ui:Tr.Zero="never"</c>
/// in place of a 0, and <c>ui:Tr.Number="0.00"</c> for the digits. Numbers are written the
/// language's way (2,5 in Russian). The sweep in LanguageTests reads these attributes as keys.
/// </summary>
public static class Tr
{
    public static readonly DependencyProperty TextProperty = Register("Text");
    public static readonly DependencyProperty ContentProperty = Register("Content");
    public static readonly DependencyProperty HeaderProperty = Register("Header");
    public static readonly DependencyProperty ToolTipProperty = Register("ToolTip");
    public static readonly DependencyProperty TitleProperty = Register("Title");
    public static readonly DependencyProperty UnitProperty = Register("Unit");
    public static readonly DependencyProperty FormatProperty = Register("Format");
    public static readonly DependencyProperty CountProperty = Register("Count");
    public static readonly DependencyProperty ZeroProperty = Register("Zero");
    public static readonly DependencyProperty NumberProperty = Register("Number");
    public static readonly DependencyProperty ValueProperty = DependencyProperty.RegisterAttached(
        "Value", typeof(object), typeof(Tr), new PropertyMetadata(null, Changed));

    public static string? GetText(DependencyObject d) => (string?)d.GetValue(TextProperty);
    public static void SetText(DependencyObject d, string? v) => d.SetValue(TextProperty, v);
    public static string? GetContent(DependencyObject d) => (string?)d.GetValue(ContentProperty);
    public static void SetContent(DependencyObject d, string? v) => d.SetValue(ContentProperty, v);
    public static string? GetHeader(DependencyObject d) => (string?)d.GetValue(HeaderProperty);
    public static void SetHeader(DependencyObject d, string? v) => d.SetValue(HeaderProperty, v);
    public static string? GetToolTip(DependencyObject d) => (string?)d.GetValue(ToolTipProperty);
    public static void SetToolTip(DependencyObject d, string? v) => d.SetValue(ToolTipProperty, v);
    public static string? GetTitle(DependencyObject d) => (string?)d.GetValue(TitleProperty);
    public static void SetTitle(DependencyObject d, string? v) => d.SetValue(TitleProperty, v);
    public static string? GetUnit(DependencyObject d) => (string?)d.GetValue(UnitProperty);
    public static void SetUnit(DependencyObject d, string? v) => d.SetValue(UnitProperty, v);
    public static string? GetFormat(DependencyObject d) => (string?)d.GetValue(FormatProperty);
    public static void SetFormat(DependencyObject d, string? v) => d.SetValue(FormatProperty, v);
    public static string? GetCount(DependencyObject d) => (string?)d.GetValue(CountProperty);
    public static void SetCount(DependencyObject d, string? v) => d.SetValue(CountProperty, v);
    public static string? GetZero(DependencyObject d) => (string?)d.GetValue(ZeroProperty);
    public static void SetZero(DependencyObject d, string? v) => d.SetValue(ZeroProperty, v);
    public static string? GetNumber(DependencyObject d) => (string?)d.GetValue(NumberProperty);
    public static void SetNumber(DependencyObject d, string? v) => d.SetValue(NumberProperty, v);
    public static object? GetValue(DependencyObject d) => d.GetValue(ValueProperty);
    public static void SetValue(DependencyObject d, object? v) => d.SetValue(ValueProperty, v);

    // Weakly: list rows are made afresh on every refresh, and the old ones must be free to go.
    private static readonly List<WeakReference<DependencyObject>> marked = new();
    private static readonly ConditionalWeakTable<DependencyObject, object> seen = new();

    private static DependencyProperty Register(string name) => DependencyProperty.RegisterAttached(
        name, typeof(string), typeof(Tr), new PropertyMetadata(null, Changed));

    private static void Changed(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (!seen.TryGetValue(d, out _))
        {
            seen.Add(d, true);
            if (marked.Count % 512 == 511) marked.RemoveAll(w => !w.TryGetTarget(out _));
            marked.Add(new WeakReference<DependencyObject>(d));
        }
        Apply(d);
    }

    /// <summary>Every marked element, again in the current language.</summary>
    public static void Refresh()
    {
        marked.RemoveAll(w => !w.TryGetTarget(out _));
        foreach (var w in marked.ToList())
            if (w.TryGetTarget(out var d)) Apply(d);
    }

    /// <summary>A number the way the current language writes it: "2,5" in Russian.</summary>
    public static string Number(double value, string pattern = "0.##") => value.ToString(pattern, Languages.Current.Culture());

    private static void Apply(DependencyObject d)
    {
        if (GetText(d) is string text)
        {
            if (d is TextBlock block) block.Text = L10n.Tr(text);
            else if (d is Run run) run.Text = L10n.Tr(text);
        }
        if (GetContent(d) is string content && d is ContentControl control) control.Content = L10n.Tr(content);
        if (GetHeader(d) is string header)
        {
            if (d is HeaderedContentControl hc) hc.Header = L10n.Tr(header);
            else if (d is HeaderedItemsControl hi) hi.Header = L10n.Tr(header);
        }
        if (GetToolTip(d) is string tip && d is FrameworkElement fe) fe.ToolTip = L10n.Tr(tip);
        if (GetTitle(d) is string title && d is Window window) window.Title = L10n.Tr(title);
        if (d.ReadLocalValue(ValueProperty) != DependencyProperty.UnsetValue && d is TextBlock shown) shown.Text = Valued(d);
    }

    private static string Valued(DependencyObject d)
    {
        double number;
        try { number = Convert.ToDouble(GetValue(d), System.Globalization.CultureInfo.InvariantCulture); }
        catch (Exception e) when (e is FormatException or InvalidCastException or OverflowException) { return ""; }
        if (number == 0 && GetZero(d) is string zero) return L10n.Tr(zero);
        var digits = Number(number, GetNumber(d) ?? "0.##");
        if (GetCount(d) is string count && count.Split('|') is [var one, var other]) return L10n.TrCount((int)Math.Round(number), one, other);
        if (GetFormat(d) is string format) return L10n.Tr(format, digits);
        return digits + (GetUnit(d) is string unit ? L10n.Tr(unit) : "");
    }
}
