using System.Globalization;
using System.Windows.Data;

namespace Ledgelings.UI;

/// <summary>Prints a number, or the parameter when it is zero: "never" for a night of 0 minutes.</summary>
public sealed class ZeroAsText : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        var number = System.Convert.ToDouble(value, CultureInfo.InvariantCulture);
        return number == 0 && parameter is string text ? text : number.ToString("0.#", CultureInfo.CurrentCulture) + " min";
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
}

public enum SettingsTab { Creatures, Sprites, Talk, Chats }
