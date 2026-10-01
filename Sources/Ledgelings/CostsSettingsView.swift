import LedgelingsCore
import SwiftUI

/// Settings › Costs: what every model call has cost, by period, by feature and by
/// model on the left; the latest calls one by one on the right.
struct CostsSettingsView: View {
    @ObservedObject var spend: SpendLedger

    var body: some View {
        TwoColumns {
            Section {
                let s = spend.summary
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("")
                        Text(tr("Cost")).font(.caption).foregroundStyle(.secondary)
                        Text(tr("Calls")).font(.caption).foregroundStyle(.secondary)
                        Text(tr("Tokens")).font(.caption).foregroundStyle(.secondary)
                    }
                    row(tr("Today"), s.today)
                    row(tr("This month"), s.month)
                    row(tr("All time"), s.allTime)
                }
            } header: {
                Text(tr("Spent"))
            } footer: {
                Text(footer(spend.summary))
            }

            Section {
                if spend.summary.byPurpose.isEmpty { Text(tr("Nothing yet.")).foregroundStyle(.secondary) }
                ForEach(spend.summary.byPurpose, id: \.purpose) { p in
                    LabeledContent(p.purpose) { Text(total(p.total)).foregroundStyle(.secondary).monospacedDigit() }
                }
            } header: {
                Text(tr("By feature"))
            } footer: {
                Text(tr("Talk is the meetings and pokes (two calls a conversation); paper planes the notes and the catcher's thought; voice every line said by a paid speech model; voice casting each Cast with Model; relationship plots one call per story a pair gets (Bonds tab). Calls from before features were labelled are counted apart."))
            }

            Section {
                ForEach(spend.summary.byModel.prefix(10), id: \.model) { m in
                    LabeledContent(m.model) { Text(total(m.total)).foregroundStyle(.secondary).monospacedDigit() }
                        .font(.callout)
                }
            } header: {
                Text(tr("By model"))
            }
        } right: {
            Section {
                if spend.recent.isEmpty { Text(tr("No calls yet.")).foregroundStyle(.secondary) }
                ForEach(spend.recent.indices, id: \.self) { i in call(spend.recent[i]) }
            } header: {
                Text(tr("Latest calls"))
            } footer: {
                Text(tr("The last %d, newest first.", SpendLedger.recentCount))
            }

            Section {
                HStack {
                    Text(spend.file.path).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button(tr("Reveal in Finder")) { spend.revealInFinder() }
                }
            } header: {
                Text(tr("The file"))
            } footer: {
                Text(tr("spend.jsonl, one JSON line per call: time, provider, model, feature, tokens and cost. Plain text on purpose."))
            }
        }
    }

    private func call(_ r: Spend.Record) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(r.model).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Text(verbatim: "\(r.time.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: Language.current.code)))) · \(Spend.Purpose.title(of: r.purpose)) · \(trCount(r.usage.promptTokens + r.usage.completionTokens, "token", "tokens"))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(r.usage.cost.map(Spend.label) ?? tr("no price")).monospacedDigit().foregroundStyle(r.usage.cost == nil ? .orange : .primary)
        }
    }

    private func total(_ t: Spend.Total) -> String {
        "\(Spend.label(t.cost))\(t.unpriced > 0 ? "+" : "") · \(trCount(t.calls, "call", "calls"))"
    }

    private func row(_ name: String, _ t: Spend.Total) -> some View {
        GridRow {
            Text(name)
            Text(Spend.label(t.cost) + (t.unpriced > 0 ? "+" : "")).monospacedDigit()
            Text(verbatim: "\(t.calls)").monospacedDigit()
            Text(verbatim: "\(t.tokens)").monospacedDigit()
        }
    }

    private func footer(_ s: Spend.Summary) -> String {
        var text = tr("Every call to a model, text or voice, is priced as OpenRouter reports it; LM Studio, a local speech server and the Mac's own voices are free.")
        if s.allTime.unpriced > 0 { text += " " + tr("%d calls had no price; a + marks a total that is missing some.", s.allTime.unpriced) }
        return text
    }
}
