extension Strings {
    /// The Russian table, one part per area of the app so each stays readable.
    static let russian = merged(russianParts.map(\.value))

    /// Each area's part by name, for the test that no English key is in two of them.
    static let russianParts: [String: [String: String]] = [
        "app": ruApp,
        "settingsA": ruSettingsA,
        "settingsB": ruSettingsB,
        "runtime": ruRuntime,
        "runtimePrompts": ruRuntimePrompts,
        "lines": ruLines,
        "letters": ruLetters,
        "tea": ruTea,
        "lettersPrompts": ruLettersPrompts,
        "teaPrompts": ruTeaPrompts,
        "linesPrompts": ruLinesPrompts,
        "personas": ruPersonas,
        "cursorMood": ruCursorMood,
        "hunts": ruHunts,
    ]
}
