import LedgelingsCore
import SwiftUI

/// The settings window's left side: a search box, then every page under its
/// group's heading; while the box holds words, the places they were found instead.
struct SettingsSidebar: View {
    static let width: CGFloat = 220
    @ObservedObject var navigation: SettingsNavigation
    @FocusState private var searching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBox
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if navigation.query.trimmingCharacters(in: .whitespaces).isEmpty { pages } else { hits }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .background(.background.secondary)
        // ⌘F from anywhere in the window puts the cursor in the search box.
        .background {
            Button("") { searching = true }.keyboardShortcut("f", modifiers: .command).hidden()
        }
    }

    private var searchBox: some View {
        HStack(spacing: 6) {
            PixelGlyph(rows: Self.searchIcon).foregroundStyle(.secondary)
            TextField(tr("Search settings"), text: $navigation.query)
                .textFieldStyle(.plain)
                .focused($searching)
                .onSubmit { if let first = found.first { navigation.open(first) } }
                .onKeyPress(.escape) {
                    guard !navigation.query.isEmpty else { return .ignored }
                    navigation.query = ""
                    return .handled
                }
            if !navigation.query.isEmpty {
                Button { navigation.query = "" } label: {
                    PixelGlyph(rows: Self.clearIcon).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(Self.clearTip)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .help(tr("Search every setting (⌘F); ⏎ opens the first place"))
    }

    private var pages: some View {
        ForEach(SettingsGroup.allCases, id: \.self) { group in
            Text(group.title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .padding(.leading, 8)
                .padding(.top, group == SettingsGroup.allCases.first ? 2 : 12)
                .padding(.bottom, 2)
            ForEach(group.pages, id: \.self) { page in
                row(selected: navigation.page == page, action: { navigation.page = page }) {
                    HStack(spacing: 8) {
                        PixelGlyph(rows: Self.icon(group))
                        Text(page.title)
                    }
                }
            }
        }
    }

    private var found: [SettingsIndex.Hit] { SettingsIndex.search(navigation.query) }

    @ViewBuilder private var hits: some View {
        let found = found
        Text(found.isEmpty ? tr("Nothing found.") : trCount(found.count, "place", "places").uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(.tertiary)
            .padding(.leading, 8)
            .padding(.bottom, 2)
        ForEach(found, id: \.self) { hit in
            let selected = navigation.page == hit.page && navigation.flash == hit.section && !hit.section.isEmpty
            row(selected: selected, action: { navigation.open(hit) }) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.text).lineLimit(2)
                    Text(hit.section.isEmpty ? hit.page.title : "\(hit.page.title) › \(tr(hit.section))")
                        .font(.caption)
                        .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
            }
        }
    }

    /// A row of the list: the whole width answers a click, the chosen one filled.
    private func row(selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(RoundedRectangle(cornerRadius: 5).fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    static let clearTip = tr("Clear the search (⎋)")

    // 11×11, drawn like the game: square pixels, no curves.
    static func icon(_ group: SettingsGroup) -> [String] {
        switch group {
        case .creaturesAndWorld: ["...........", ".##.....##.", ".##.....##.", "...........", "....###....", "...#####...", "...#####...", "....###....", "...........", "...........", "..........."]
        case .games: ["...#####...", "..#.....#..", ".#..###..#.", ".#.#...#.#.", ".#.#...#.#.", ".#..###..#.", "..#.....#..", "...#####...", "...........", "...........", "..........."]
        case .talkAndFriends: ["#########..", "#.......#..", "#.##.##.#..", "#.......#..", "#########..", "..##.......", "..#........", "...........", "...........", "...........", "..........."]
        case .tools: ["......###..", ".....#..#..", "....#..#...", "...#.##....", "..#.#......", ".#.#.......", "#.#........", "##.........", "...........", "...........", "..........."]
        case .moneyAndHistory: ["...#####...", "..#.....#..", ".#...#...#.", ".#..###..#.", ".#...#...#.", ".#..###..#.", "..#.....#..", "...#####...", "...........", "...........", "..........."]
        }
    }
    static let searchIcon = ["..####.....", ".#....#....", "#......#...", "#......#...", "#......#...", ".#....#....", "..####.#...", ".......#...", "........#..", ".........#.", "..........."]
    static let clearIcon = ["#.......#..", ".#.....#...", "..#...#....", "...#.#.....", "....#......", "...#.#.....", "..#...#....", ".#.....#...", "#.......#..", "...........", "..........."]
}

/// A pixel picture in the colour around it (`foregroundStyle`), so it reads
/// on a chosen row and in dark mode alike.
struct PixelGlyph: View {
    var rows: [String]
    var pixel: CGFloat = 1.5

    var body: some View {
        let w = CGFloat(rows.map(\.count).max() ?? 0), h = CGFloat(rows.count)
        PixelShape(rows: rows).frame(width: w * pixel, height: h * pixel)
    }
}

private struct PixelShape: Shape {
    var rows: [String]

    func path(in rect: CGRect) -> Path {
        let w = CGFloat(rows.map(\.count).max() ?? 1), h = CGFloat(max(rows.count, 1))
        let px = rect.width / w, py = rect.height / h
        var path = Path()
        for (y, row) in rows.enumerated() {
            for (x, c) in row.enumerated() where c == "#" {
                path.addRect(CGRect(x: rect.minX + CGFloat(x) * px, y: rect.minY + CGFloat(y) * py, width: px, height: py))
            }
        }
        return path
    }
}

/// A section's heading that a search can land on: the window scrolls to it and
/// it lights up gold for a moment. Takes the English, as `tr` does.
struct SettingsHeader: View {
    static let flashSeconds = 1.4
    let english: String
    @Environment(\.settingsFlash) private var flash

    init(_ english: String) { self.english = english }

    var body: some View {
        Text(tr(english))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.98, green: 0.78, blue: 0.25).opacity(flash == english ? 0.55 : 0)))
            .padding(.horizontal, -6)
            .animation(.easeInOut(duration: 0.3), value: flash)
            .id(english)
    }
}

private struct SettingsFlashKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The heading a search just landed on, while it flashes.
    var settingsFlash: String? {
        get { self[SettingsFlashKey.self] }
        set { self[SettingsFlashKey.self] = newValue }
    }
}
