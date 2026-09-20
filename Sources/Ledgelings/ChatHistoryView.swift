import LedgelingsCore
import SwiftUI

/// Settings › Chats: the days down the left, one day's conversations on the right.
struct ChatHistoryView: View {
    @ObservedObject var history: ChatHistory
    @State private var days: [String] = []
    @State private var selected: String?
    @State private var exchanges: [ChatLog.Exchange] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                List(days, id: \.self, selection: $selected) { day in
                    Text(Self.pretty(day)).tag(day)
                }
                .frame(width: 150)
                Divider()
                if days.isEmpty {
                    empty("No chats yet. They talk when they meet on an edge, or pick \"Make Someone Talk\" in the menu.")
                } else if exchanges.isEmpty {
                    empty("Nothing on this day.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(exchanges.indices, id: \.self) { i in exchange(exchanges[i]) }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Divider()
            HStack {
                Text(history.directory.path)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button("Open in Finder") { history.revealInFinder() }
                Button("Open in Terminal") { history.openInTerminal() }
            }
            .padding(10)
        }
        .onAppear(perform: reload)
        .onChange(of: history.version) { reload() }
        .onChange(of: selected) { exchanges = selected.map(history.exchanges(on:)) ?? [] }
    }

    private func reload() {
        days = history.days()
        if selected == nil || !days.contains(selected!) { selected = days.first }
        exchanges = selected.map(history.exchanges(on:)) ?? []
    }

    private func empty(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func exchange(_ x: ChatLog.Exchange) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(x.time, style: .time).monospacedDigit()
                Text(x.model).lineLimit(1)
                Spacer()
                if let cost = x.cost { Text(Spend.label(cost)).monospacedDigit() }
                if let tokens = x.tokens { Text("\(tokens) tok").monospacedDigit() }
            }
            .font(.caption).foregroundStyle(.secondary)
            Text(x.situation).font(.caption).foregroundStyle(.tertiary)
            ForEach(x.lines.indices, id: \.self) { i in
                Text(Self.spoken(x.lines[i])).textSelection(.enabled)
            }
        }
    }

    /// "**Name:** what they said", as one selectable run of text.
    static func spoken(_ line: ChatLog.Line) -> AttributedString {
        var name = AttributedString(line.speaker + ": ")
        name.font = .body.bold()
        return name + AttributedString(line.text)
    }

    /// "2026-09-18" as the user would say it, with today and yesterday named.
    static func pretty(_ day: String) -> String {
        let today = ChatLog.day(of: Date()), yesterday = ChatLog.day(of: Date().addingTimeInterval(-86_400))
        if day == today { return "Today" }
        if day == yesterday { return "Yesterday" }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return day }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
