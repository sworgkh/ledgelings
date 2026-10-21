import AppKit
import LedgelingsCore
import SwiftUI

/// Relationships…: every pair on the left, closest first, with how close they
/// have grown day by day; the chosen pair on the right: how they get on, what
/// they remember, their games, and their timeline, a line a day. At the bottom,
/// exactly what each of them carries into a conversation. This is where the
/// owner watches relationships emerge.
@MainActor
final class RelationshipsWindowController {
    static let size = CGSize(width: 980, height: 640)
    private let settings: AppSettings
    private let bonds: BondBook
    private var window: NSWindow?

    init(settings: AppSettings, bonds: BondBook) {
        self.settings = settings
        self.bonds = bonds
    }

    func show() {
        if window == nil {
            let made = NSWindow(contentViewController: NSHostingController(rootView: RelationshipsView(settings: settings, bonds: bonds)))
            made.title = tr("Relationships")
            made.styleMask = [.titled, .closable, .resizable]
            made.isReleasedWhenClosed = false
            made.setContentSize(Self.size)
            made.center()
            window = made
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func snapshot(to url: URL) throws {
        guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

struct RelationshipsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var bonds: BondBook
    @State private var selected: String?

    private var pairs: [Bonds.Bond] { bonds.book.closest }
    private func key(_ bond: Bonds.Bond) -> String { bond.names.joined(separator: " & ") }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(pairs, id: \.names) { bond in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: key(bond)).font(.headline)
                        Text(Bonds.tallied(bond.tally).isEmpty ? tr("only just met") : Bonds.tallied(bond.tally))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Growth(days: bond.days).frame(height: 14)
                    }
                    .padding(.vertical, 2)
                    .tag(key(bond))
                }
            }
            .frame(width: 280)
            Divider()
            if let bond = pairs.first(where: { key($0) == (selected ?? pairs.first.map(key)) }) {
                List { detail(bond).padding(.vertical, 8) }
            } else {
                Text(tr("Nobody has shared the screen yet.")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 460)
    }

    @ViewBuilder
    private func detail(_ bond: Bonds.Bond) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: key(bond)).font(.title2.bold())
            if let met = bond.met {
                Text(tr("Met on %@ · %@ together on screen", Bonds.day(met), Bonds.duration(bond.together)))
                    .foregroundStyle(.secondary)
            }
            if let summary = bond.summary { Text(summary).italic() }
            block(tr("Their story so far"), bond.chronicle ?? tr("nothing yet; they have only just met"))
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("What they remember")).font(.headline)
                if bond.facts.isEmpty { Text(tr("(nothing yet)")).foregroundStyle(.secondary) }
                ForEach(Array(bond.facts.enumerated().reversed()), id: \.offset) { _, fact in
                    Text("· " + fact.text + "  ").font(.callout)
                        + Text(Bonds.day(fact.time)).font(.caption).foregroundColor(.secondary)
                }
            }
            block(tr("Their games"), Bonds.recordLine(bond) ?? tr("(nothing yet)"))
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Day by day")).font(.headline)
                if bond.days.isEmpty { Text(tr("(nothing yet)")).foregroundStyle(.secondary) }
                ForEach(bond.days.reversed(), id: \.day) { day in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Bonds.date(ofDay: day.day).map(Bonds.day) ?? day.day).font(.callout.monospacedDigit()).frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            if let line = day.line { Text(line).font(.callout) }
                            Text(Bonds.dayLine(day)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("What they carry into a conversation")).font(.headline)
                ForEach([(bond.names[0], bond.names[1]), (bond.names[1], bond.names[0])], id: \.0) { a, b in
                    let block = Bonds.memory(bond, speaker: a, other: b, budget: settings.memoryEnabled ? settings.memoryTokens : 0)
                    Text(tr("%@ (%@):", a, trCount(Bonds.tokens(block), "token", "tokens"))).font(.callout.bold())
                    Text(block.isEmpty ? tr("(nothing)") : block).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let cost = bond.memoryCost { Text(tr("Their memory has cost %@ so far.", Spend.label(cost))).font(.caption).foregroundStyle(.tertiary) }
            }
        }
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text).font(.callout).textSelection(.enabled)
        }
    }
}

/// How much a pair shared each day, oldest left: one square bar a day, in the
/// game's style (square pixels, flat fill).
struct Growth: View {
    let days: [Bonds.Day]
    var body: some View {
        GeometryReader { g in
            let shown = Array(days.suffix(30))
            let most = max(1, shown.map { $0.counts.values.reduce(0, +) }.max() ?? 1)
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(shown, id: \.day) { day in
                    let n = day.counts.values.reduce(0, +)
                    Rectangle().fill(Color.accentColor.opacity(0.75))
                        .frame(width: 5, height: max(2, g.size.height * CGFloat(n) / CGFloat(most)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}
