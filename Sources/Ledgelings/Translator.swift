import Foundation
import LedgelingsCore

/// The calls the translator makes (§7.14): a translation, cut into parts when it
/// is long and with links, code and numbers kept out of reach; a guess at how a
/// phrase goes on. Every call is priced as Translation or Autocomplete, empty
/// answers and cancelled ones the server already answered too. Answers are kept
/// in a small cache in memory, so backspacing and retyping cost nothing.
@MainActor
final class Translator {
    enum Trouble: Error, Equatable {
        /// No OpenRouter key, and LM Studio is not the brain.
        case noModel
        case timedOut(Double)
        case network(String)
        case refused(String)
        case empty
        /// A newer text came first: nobody waits for this answer.
        case cancelled

        var line: String {
            switch self {
            case .noModel: tr("Translating needs an OpenRouter key (Settings › Talk), or LM Studio as the brain.")
            case .timedOut(let s): tr("No answer in %d s: offline? ⏎ to try again", Int(s))
            case .network(let why): tr("Could not reach the model: %@", why)
            case .refused(let why): tr("The model refused: %@", why)
            case .empty: tr("The model sent nothing back. ⏎ to try again")
            case .cancelled: ""
            }
        }
    }

    /// A finished translation: the words, how long it took, and whether a link,
    /// code or number may have come back changed (the markers were lost and the
    /// text went again without them).
    struct Done: Equatable {
        let text: String
        let seconds: Double
        var markersLost = false
        var cached = false
    }

    private let settings: AppSettings
    private let spend: SpendLedger
    private var cache = Translate.Cache()
    /// The key, read from the keychain once per sheet, not once per keystroke.
    private var key: String?
    /// Every call with its time, for `--translate` and the film.
    var trace: ((String) -> Void)?
    /// A model to use instead of the chosen one, for `--translate --model` and the bench.
    var modelOverride: String?
    /// Replaces the network in tests and the film: the system prompt and the text in, the answer out.
    var fake: ((String, String) async throws -> ChatClient.Answer)?

    init(settings: AppSettings, spend: SpendLedger) {
        self.settings = settings
        self.spend = spend
    }

    /// Reads the key again: the sheet opens, or the settings changed.
    func refresh() {
        // A stand-in model never needs the key, and reading it would put up the keychain's dialog.
        guard fake == nil else { return }
        settings.retryOpenRouterKey()
        key = settings.openRouterKey.trimmingCharacters(in: .whitespaces)
    }

    /// The model that answers: OpenRouter with the chosen model when a key is
    /// saved, else LM Studio when it is the brain (free), else none.
    func client(guessing: Bool = false) -> ChatClient? {
        if key == nil { refresh() }
        if let key, !key.isEmpty {
            let own = settings.translateAutocompleteModel.trimmingCharacters(in: .whitespaces)
            let model = modelOverride ?? (guessing && !own.isEmpty ? own : settings.translateModel.trimmingCharacters(in: .whitespaces))
            var client = ChatClient.openRouter(key: key, model: model.isEmpty ? Translate.defaultModel : model)
            client.timeout = guessing ? Translate.guessTimeout : Translate.translationTimeout
            return client
        }
        if settings.brain == .lmStudio, let url = settings.talkServerURL {
            var client = ChatClient.lmStudio(server: url, model: settings.talkModel.trimmingCharacters(in: .whitespaces))
            client.timeout = guessing ? Translate.guessTimeout : Translate.translationTimeout
            return client
        }
        return nil
    }

    var hasModel: Bool { fake != nil || client() != nil }

    /// What a stand-in call is recorded as: nothing is paid, so nothing is recorded.
    var isFake: Bool { fake != nil }

    // MARK: Translating

    /// `text` from `source` into `target`. Cancelling the task stops waiting; a
    /// call the server answered anyway is still recorded.
    func translate(_ text: String, from source: Translate.Language, to target: Translate.Language) async -> Result<Done, Trouble> {
        let started = Date()
        let model = client()?.model ?? "fake"
        let key = Translate.Cache.Key(text: text, from: source.code, to: target.code, model: model)
        if let hit = cache.get(key) {
            trace?("translate cached \(source.code)→\(target.code): \(hit.prefix(60))")
            return .success(Done(text: hit, seconds: 0, cached: true))
        }
        let parts = Translate.parts(text)
        var results = [String](repeating: "", count: parts.count)
        var lost = false
        do {
            // Three parts at a time, joined back in order.
            for batch in stride(from: 0, to: parts.count, by: Translate.partsAtOnce) {
                let tasks = (batch..<min(batch + Translate.partsAtOnce, parts.count)).map { i in
                    (i, Task { @MainActor in try await self.part(parts[i], from: source, to: target) })
                }
                try await withTaskCancellationHandler {
                    for (i, task) in tasks {
                        let (words, lostMarkers) = try await task.value
                        results[i] = words
                        lost = lost || lostMarkers
                    }
                } onCancel: {
                    for (_, task) in tasks { task.cancel() }
                }
            }
        } catch let trouble as Trouble {
            return .failure(trouble)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
        let joined = results.joined()
        guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.empty) }
        if !lost { cache.put(key, joined) }
        let seconds = Date().timeIntervalSince(started)
        trace?(String(format: "translate %@→%@ in %.2f s, %d part%@: %@", source.code, target.code, seconds, parts.count,
                      parts.count == 1 ? "" : "s", String(joined.prefix(80))))
        return .success(Done(text: joined, seconds: seconds, markersLost: lost))
    }

    /// One part, its protected pieces put back; again without markers when the model lost one.
    private func part(_ text: String, from source: Translate.Language, to target: Translate.Language) async throws -> (String, Bool) {
        let protected = Translate.protect(text)
        let marked = !protected.pieces.isEmpty
        let answer = try await ask(system: Translate.instruction(from: source, to: target, markers: marked),
                                   user: protected.text, maxTokens: Self.room(for: text), purpose: .translation)
        let words = Translate.cleaned(answer.text, original: protected.text)
        guard marked else { return (words, false) }
        if let restored = Translate.restore(words, pieces: protected.pieces) { return (restored, false) }
        trace?("markers lost: again without them")
        let again = try await ask(system: Translate.instruction(from: source, to: target, markers: false),
                                  user: text, maxTokens: Self.room(for: text), purpose: .translation)
        return (Translate.cleaned(again.text, original: text), true)
    }

    /// Room for the answer: a translation is about as long as the text, Russian
    /// and Hebrew in tokens a little longer, plus some to spare.
    static func room(for text: String) -> Int { max(200, min(8_000, text.count / 2 + 200)) }

    // MARK: Guessing

    /// The next few words after `text`, or "" when there is no guess (or no model).
    func guess(after text: String, in language: Translate.Language) async -> String {
        guard settings.translateAutocomplete, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
        guard let answer = try? await ask(system: Translate.guessInstruction(in: language), user: Translate.guessPrompt(text),
                                          maxTokens: Translate.guessTokens, purpose: .autocomplete, guessing: true) else { return "" }
        return Translate.cleanedGuess(answer.text, after: text)
    }

    // MARK: The call

    private func ask(system: String, user: String, maxTokens: Int, purpose: Spend.Purpose, guessing: Bool = false) async throws -> ChatClient.Answer {
        if let fake { return try await fake(system, user) }
        guard let client = client(guessing: guessing) else { throw Trouble.noModel }
        let sent = Date()
        do {
            // Temperature 0: the same text, the same translation.
            let request = try client.request(system: system, user: user, maxTokens: maxTokens, temperature: guessing ? 0.3 : 0)
            // Its own task, which a newer keystroke does not cancel: a call the server
            // answers is paid for, so it runs to the end and is priced even when the
            // text it was for is gone (AGENTS rule 1). Only the waiting stops.
            let call = Task { try await URLSession.shared.data(for: request).0 }
            let data: Data
            do { data = try await call.value } catch {
                if (error as? URLError)?.code == .timedOut { throw Trouble.timedOut(client.timeout) }
                throw Trouble.network(error.localizedDescription)
            }
            let answer = try ChatClient.parseReply(data)
            spend.record(provider: client.provider, model: client.model, usage: answer.usage ?? Spend.Usage(promptTokens: 0, completionTokens: 0, cost: nil), purpose: purpose)
            trace?(String(format: "%@ %@ answered in %.2f s, %d in, %d out, %@", purpose.rawValue, client.model, Date().timeIntervalSince(sent),
                          answer.usage?.promptTokens ?? 0, answer.usage?.completionTokens ?? 0, answer.usage?.cost.map(Spend.label) ?? "price unknown"))
            if Task.isCancelled { throw CancellationError() }
            return answer
        } catch let failure as ChatClient.Failure {
            switch failure {
            case .refused(let why): throw Trouble.refused(why)
            case .serverDown(let why): throw Trouble.network(why)
            default: throw Trouble.refused(failure.description)
            }
        }
    }
}
