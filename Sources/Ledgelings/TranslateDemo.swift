import AppKit
import LedgelingsCore

/// The translator from a terminal (§7.14):
///
///     Ledgelings --translate "Привет, как дела?" [--to he] [--model id]
///     Ledgelings --translate-bench [--runs 10]
///     Ledgelings --translate-sheet "text" [--snapshot out.png]
///
/// The first prints what it detected, where it went, the answer, the time and
/// the price, through the real call. The bench times each candidate model on the
/// same phrases. The sheet opens on the real screen with the text, waits for the
/// translation and the guess, writes the paper to a PNG and closes; nothing is
/// copied or pasted. All three are priced on Costs like any translation.
@MainActor
enum TranslateDemo {
    static func once(_ text: String, to code: String?, model: String?, controller: TranslateController, settings: AppSettings, spend: SpendLedger) async -> Bool {
        let translator = controller.translator
        translator.modelOverride = model
        translator.refresh()
        let on = settings.translateLanguagesOn
        guard let source = Translate.detect(Translate.protect(text).text, among: on) else { say("translate: nothing to translate in \"\(text)\""); return false }
        let target = code.flatMap(Translate.language) ?? Translate.target(for: source, targets: settings.translateTargets, on: on)
        let before = spend.summary.allTime
        say("translate detect \(source.englishName) → \(target.englishName), model \(translator.client()?.model ?? "none")")
        switch await translator.translate(text, from: source, to: target) {
        case .success(let done):
            let after = spend.summary.allTime
            say(String(format: "translate answer in %.2f s, %@, %d tokens in, %d out%@", done.seconds, Spend.label(after.cost - before.cost),
                       after.promptTokens - before.promptTokens, after.completionTokens - before.completionTokens, done.markersLost ? ", links may be changed" : ""))
            say("translate: \(done.text)")
            return true
        case .failure(let trouble):
            say("translate trouble: \(trouble.line)")
            return false
        }
    }

    static let candidates = ["google/gemini-2.5-flash-lite", "openai/gpt-4.1-nano", "anthropic/claude-haiku-5.5",
                             "mistralai/mistral-small-3.2-24b-instruct", "google/gemini-3.1-flash-lite"]
    static let phrases: [(String, String)] = [
        ("en", "Can you send me the report before Friday's meeting?"),
        ("ru", "Не забудь купить молоко и хлеб по дороге домой."),
        ("he", "אני אגיע מאוחר היום, תתחילו בלעדיי."),
        ("en", "The build failed again; see https://ci.example.com/run/42 for the log."),
        ("ru", "Встреча перенесена на 10:30, комната «Мох»."),
    ]

    /// Each candidate on the same phrases, `runs` times round: the median and the slowest time, and one Hebrew answer.
    static func bench(runs: Int, controller: TranslateController, settings: AppSettings, spend: SpendLedger) async -> Bool {
        let translator = controller.translator
        var ok = true
        for model in candidates {
            translator.modelOverride = model
            translator.refresh()
            var times: [Double] = [], sample = "", failures = 0
            let before = spend.summary.allTime.cost
            for run in 0..<runs {
                let (code, phrase) = phrases[run % phrases.count]
                let source = Translate.language(code)!
                let target = code == "en" ? Translate.hebrew : Translate.english
                // The cache would answer the second time round: a different text each run.
                let text = run < phrases.count ? phrase : phrase + " (\(run))"
                let started = Date()
                switch await translator.translate(text, from: source, to: target) {
                case .success(let done):
                    times.append(Date().timeIntervalSince(started))
                    if target == Translate.hebrew, sample.isEmpty { sample = done.text }
                case .failure(let trouble):
                    failures += 1
                    say("bench \(model) trouble: \(trouble.line)")
                }
            }
            times.sort()
            let median = times.isEmpty ? 0 : times[times.count / 2], slowest = times.last ?? 0
            say(String(format: "bench %@ median %.2f s, slowest %.2f s, %d of %d answered, %@ in all", model, median, slowest, times.count, runs,
                       Spend.label(spend.summary.allTime.cost - before)))
            if !sample.isEmpty { say("bench \(model) Hebrew: \(sample)") }
            ok = ok && failures < runs
        }
        translator.modelOverride = nil
        return ok
    }

    /// The sheet with `text`, on the real screen, until the translation (and a guess) came; then a PNG.
    static func sheet(_ text: String, into target: Translate.Language?, snapshot: URL?, controller: TranslateController) async -> Bool {
        let sheet = controller.sheet
        sheet.pressKeys = false
        sheet.show(text: text, into: target)
        let started = Date()
        while Date().timeIntervalSince(started) < 15, [.waiting, .idle].contains(sheet.model.state) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        say(String(format: "sheet %@ after %.1f s: %@", "\(sheet.model.state)", Date().timeIntervalSince(started), sheet.model.status))
        say("sheet result: \(sheet.model.result)")
        // A moment for the guess and the unfolding.
        try? await Task.sleep(for: .seconds(1.5))
        if !sheet.model.guess.isEmpty { say("sheet guess: \(sheet.model.guess)") }
        if let snapshot {
            do { try sheet.snapshot(to: snapshot); say("sheet snapshot \(snapshot.path)") } catch { say("sheet snapshot: \(error)") }
        }
        sheet.close()
        return sheet.model.state == .done
    }

    // MARK: A stand-in model

    /// Hand-written translations of the film's phrases, so the film and a headless
    /// `--translate-sheet` need no key and no network (`LEDGELINGS_FAKE_TRANSLATE=1`).
    static let known: [String: String] = [
        "en>ru|Can you send me the report before Friday's meeting?": "Можешь прислать мне отчёт до встречи в пятницу?",
        "en>he|Can you send me the report before Friday's meeting?": "תוכל לשלוח לי את הדוח לפני הפגישה ביום שישי?",
        "ru>en|Можешь прислать мне отчёт до встречи в пятницу?": "Can you send me the report before the Friday meeting?",
        "ru>en|Встреча перенесена на ⟦1⟧, комната «Мох».": "The meeting has moved to ⟦1⟧, room “Moss”.",
        "he>en|אני אגיע מאוחר היום, תתחילו בלעדיי.": "I'll be late today, start without me.",
        "ru>en|Не забудь купить молоко и хлеб по дороге домой.": "Don't forget to buy milk and bread on the way home.",
    ]

    static func fake(system: String, user: String) async throws -> ChatClient.Answer {
        try await Task.sleep(for: .milliseconds(350))
        if system.hasPrefix("You complete") {
            let guesses = ["Can you send me": " the report before Friday", "Не забудь": " купить молоко", "See you": " tomorrow at ten"]
            return ChatClient.Answer(text: guesses.first { user.hasSuffix($0.key) }?.value ?? "", usage: nil)
        }
        let pair = Translate.languages.flatMap { a in Translate.languages.map { b in (a, b) } }
            .first { system.contains("from \($0.0.englishName) into \($0.1.englishName)") }
        let key = "\(pair?.0.code ?? "?")>\(pair?.1.code ?? "?")|\(user)"
        return ChatClient.Answer(text: known[key] ?? "[\(pair?.1.code ?? "?")] \(user)", usage: nil)
    }

    private static func say(_ line: String) { FileHandle.standardError.write(Data((line + "\n").utf8)) }
}
