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
                        Text("Cost").font(.caption).foregroundStyle(.secondary)
                        Text("Calls").font(.caption).foregroundStyle(.secondary)
                        Text("Tokens").font(.caption).foregroundStyle(.secondary)
                    }
                    row("Today", s.today)
                    row("This month", s.month)
                    row("All time", s.allTime)
                }
            } header: {
                Text("Spent")
            } footer: {
                Text(footer(spend.summary))
            }

            Section {
                if spend.summary.byPurpose.isEmpty { Text("Nothing yet.").foregroundStyle(.secondary) }
                ForEach(spend.summary.byPurpose, id: \.purpose) { p in
                    LabeledContent(p.purpose) { Text(total(p.total)).foregroundStyle(.secondary).monospacedDigit() }
                }
            } header: {
                Text("By feature")
            } footer: {
                Text("Talk is the meetings and pokes (two calls a conversation); paper planes the notes and the catcher's thought; voice every line said by a paid speech model; voice casting each Cast with Model. Calls from before features were labelled are counted apart.")
            }

            Section {
                ForEach(spend.summary.byModel.prefix(10), id: \.model) { m in
                    LabeledContent(m.model) { Text(total(m.total)).foregroundStyle(.secondary).monospacedDigit() }
                        .font(.callout)
                }
            } header: {
                Text("By model")
            }
        } right: {
            Section {
                if spend.recent.isEmpty { Text("No calls yet.").foregroundStyle(.secondary) }
                ForEach(spend.recent.indices, id: \.self) { i in call(spend.recent[i]) }
            } header: {
                Text("Latest calls")
            } footer: {
                Text("The last \(SpendLedger.recentCount), newest first.")
            }

            Section {
                HStack {
                    Text(spend.file.path).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Reveal in Finder") { spend.revealInFinder() }
                }
            } header: {
                Text("The file")
            } footer: {
                Text("spend.jsonl, one JSON line per call: time, provider, model, feature, tokens and cost. Plain text on purpose.")
            }
        }
    }

    private func call(_ r: Spend.Record) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(r.model).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Text("\(r.time.formatted(date: .abbreviated, time: .shortened)) · \(Spend.Purpose.title(of: r.purpose)) · \(r.usage.promptTokens + r.usage.completionTokens) tokens")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(r.usage.cost.map(Spend.label) ?? "no price").monospacedDigit().foregroundStyle(r.usage.cost == nil ? .orange : .primary)
        }
    }

    private func total(_ t: Spend.Total) -> String {
        "\(Spend.label(t.cost))\(t.unpriced > 0 ? "+" : "") · \(t.calls) call\(t.calls == 1 ? "" : "s")"
    }

    private func row(_ name: String, _ t: Spend.Total) -> some View {
        GridRow {
            Text(name)
            Text(Spend.label(t.cost) + (t.unpriced > 0 ? "+" : "")).monospacedDigit()
            Text("\(t.calls)").monospacedDigit()
            Text("\(t.tokens)").monospacedDigit()
        }
    }

    private func footer(_ s: Spend.Summary) -> String {
        var text = "Every call to a model, text or voice, is priced as OpenRouter reports it; LM Studio, a local speech server and the Mac's own voices are free."
        if s.allTime.unpriced > 0 { text += " \(s.allTime.unpriced) calls had no price; a + marks a total that is missing some." }
        return text
    }
}
