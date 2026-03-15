import AppKit
import SwiftUI

struct ThemePicker: View {
    @Binding var selection: String
    let themes: [TerminalTheme]
    @ObservedObject var settingsStore: SettingsStore

    @State private var isPresented = false
    @State private var searchText = ""

    private var selectedThemeName: String {
        themes.first { $0.id == selection }?.name ?? selection
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 10) {
                Text(selectedThemeName)
                    .foregroundStyle(.primary)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ThemePickerPopover(
                selection: $selection,
                searchText: $searchText,
                themes: themes,
                settingsStore: settingsStore,
                dismiss: dismissPicker
            )
        }
        .onChange(of: isPresented) { _, newValue in
            if !newValue {
                searchText = ""
                settingsStore.previewThemeID = nil
            }
        }
    }

    private func dismissPicker() {
        searchText = ""
        isPresented = false
    }
}

private struct ThemePickerPopover: View {
    @Binding var selection: String
    @Binding var searchText: String

    let themes: [TerminalTheme]
    @ObservedObject var settingsStore: SettingsStore
    let dismiss: () -> Void

    @State private var highlightedThemeID: String?
    @State private var hoveredThemeID: String?
    @State private var previewTask: Task<Void, Never>?

    // Cached theme categories — stable for the popover's lifetime
    @State private var cachedBuiltIn: [TerminalTheme] = []
    @State private var cachedGhostty: [TerminalTheme] = []
    @State private var cachedImported: [TerminalTheme] = []

    // Cached filtered results — only recomputed on search text change
    @State private var filteredBuiltIn: [TerminalTheme] = []
    @State private var filteredGhostty: [TerminalTheme] = []
    @State private var filteredImported: [TerminalTheme] = []
    @State private var allFilteredIDs: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Theme")
                .font(.headline)

            ThemeSearchField(text: $searchText, onCommand: handleSearchCommand)
                .frame(height: 28)

            if allFilteredIDs.isEmpty {
                ContentUnavailableView(
                    "No themes found",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search term.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(themeSections, id: \.title) { section in
                                sectionHeader(section.title)
                                ForEach(section.themes) { theme in
                                    ThemeRowView(
                                        theme: theme,
                                        isSelected: theme.id == selection,
                                        isHighlighted: theme.id == highlightedThemeID,
                                        isHovered: theme.id == hoveredThemeID,
                                        onSelect: { commitTheme(theme.id) },
                                        onHover: { handleHover(theme.id, hovering: $0) }
                                    )
                                    .id(theme.id)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        scrollToHighlighted(proxy: proxy)
                    }
                    .onChange(of: highlightedThemeID) { _, _ in
                        scrollToHighlighted(proxy: proxy)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 360, height: 480)
        .onAppear {
            categorizeThemes()
            refilter()
            highlightedThemeID = reconciledHighlight(current: nil)
        }
        .onChange(of: searchText) { _, _ in
            refilter()
            highlightedThemeID = reconciledHighlight(current: highlightedThemeID)
        }
        .onChange(of: highlightedThemeID) { _, newID in
            schedulePreview(for: newID)
        }
        .onDisappear {
            previewTask?.cancel()
        }
    }

    private var themeSections: [(title: String, themes: [TerminalTheme])] {
        [("Tesara", filteredBuiltIn), ("Community", filteredGhostty), ("Imported", filteredImported)]
            .filter { !$0.themes.isEmpty }
    }

    // MARK: - Theme categorization (computed once)

    private func categorizeThemes() {
        let builtInIDs = Set(BuiltInTheme.allCases.map(\.id))
        var builtIn: [TerminalTheme] = []
        var ghostty: [TerminalTheme] = []
        var imported: [TerminalTheme] = []

        for theme in themes {
            if theme.id.hasPrefix("ghostty-") {
                ghostty.append(theme)
            } else if builtInIDs.contains(theme.id) {
                builtIn.append(theme)
            } else {
                imported.append(theme)
            }
        }

        cachedBuiltIn = builtIn
        cachedGhostty = ghostty
        cachedImported = imported
    }

    // MARK: - Filtering (recomputed only on search text change)

    private func refilter() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredBuiltIn = filterThemes(cachedBuiltIn, query: trimmed)
        filteredGhostty = filterThemes(cachedGhostty, query: trimmed)
        filteredImported = filterThemes(cachedImported, query: trimmed)
        allFilteredIDs = filteredBuiltIn.map(\.id) + filteredGhostty.map(\.id) + filteredImported.map(\.id)
    }

    private func filterThemes(_ list: [TerminalTheme], query: String) -> [TerminalTheme] {
        guard !query.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func commitTheme(_ id: String) {
        selection = id
        settingsStore.previewThemeID = nil
        dismiss()
    }

    private func handleHover(_ id: String, hovering: Bool) {
        if hovering {
            hoveredThemeID = id
            highlightedThemeID = id
        } else if hoveredThemeID == id {
            hoveredThemeID = nil
        }
    }

    private func handleSearchCommand(_ command: ThemeSearchField.Command) {
        switch command {
        case .moveUp:
            highlightedThemeID = moveHighlight(direction: .up)
        case .moveDown:
            highlightedThemeID = moveHighlight(direction: .down)
        case .confirmSelection:
            guard let id = highlightedThemeID, allFilteredIDs.contains(id) else {
                NSSound.beep()
                return
            }
            commitTheme(id)
        case .cancel:
            settingsStore.previewThemeID = nil
            dismiss()
        }
    }

    private func schedulePreview(for themeID: String?) {
        previewTask?.cancel()
        guard let themeID else {
            settingsStore.previewThemeID = nil
            return
        }
        previewTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            settingsStore.previewThemeID = themeID
        }
    }

    // MARK: - Navigation

    private enum Direction { case up, down }

    private func moveHighlight(direction: Direction) -> String? {
        let ids = allFilteredIDs
        guard !ids.isEmpty else { return nil }

        guard let current = highlightedThemeID, let index = ids.firstIndex(of: current) else {
            return direction == .up ? ids.last : ids.first
        }

        switch direction {
        case .up:
            return index > 0 ? ids[index - 1] : ids.first
        case .down:
            return index < ids.count - 1 ? ids[index + 1] : ids.last
        }
    }

    private func reconciledHighlight(current: String?) -> String? {
        let ids = allFilteredIDs
        if let current, ids.contains(current) { return current }
        if ids.contains(selection) { return selection }
        return ids.first
    }

    private func scrollToHighlighted(proxy: ScrollViewProxy) {
        guard let highlightedThemeID else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.12)) {
                proxy.scrollTo(highlightedThemeID, anchor: .center)
            }
        }
    }
}

// MARK: - ThemeRowView (Equatable for skip-rendering optimization)

private struct ThemeRowView: View, Equatable {
    let theme: TerminalTheme
    let isSelected: Bool
    let isHighlighted: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    static func == (lhs: ThemeRowView, rhs: ThemeRowView) -> Bool {
        lhs.theme.id == rhs.theme.id
            && lhs.isSelected == rhs.isSelected
            && lhs.isHighlighted == rhs.isHighlighted
            && lhs.isHovered == rhs.isHovered
    }

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 10) {
                colorSwatches

                Text(theme.name)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hovering in
            onHover(hovering)
        }
    }

    private var colorSwatches: some View {
        HStack(spacing: 3) {
            swatchCircle(hex: theme.background)
            swatchCircle(hex: theme.foreground)
            swatchCircle(hex: theme.red)
            swatchCircle(hex: theme.green)
            swatchCircle(hex: theme.blue)
        }
    }

    private func swatchCircle(hex: String) -> some View {
        Circle()
            .fill(Color(hex: hex) ?? .gray)
            .frame(width: 12, height: 12)
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(isHovered || isHighlighted ? 0.20 : 0.12)
        }
        if isHovered {
            return Color.primary.opacity(0.11)
        }
        if isHighlighted {
            return Color.primary.opacity(0.08)
        }
        return .clear
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.45)
        }
        if isHovered {
            return Color.primary.opacity(0.16)
        }
        return .clear
    }

    private var borderWidth: CGFloat {
        (isSelected || isHovered) ? 1 : 0
    }
}

private struct ThemeSearchField: NSViewRepresentable {
    enum Command {
        case moveUp
        case moveDown
        case confirmSelection
        case cancel
    }

    @Binding var text: String
    let onCommand: (Command) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommand: onCommand)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.delegate = context.coordinator
        searchField.placeholderString = "Search themes"
        searchField.focusRingType = .default
        searchField.sendsSearchStringImmediately = true
        searchField.maximumRecents = 0
        searchField.recentsAutosaveName = nil
        searchField.alignment = .left
        searchField.stringValue = text

        DispatchQueue.main.async {
            searchField.window?.makeFirstResponder(searchField)
            searchField.currentEditor()?.alignment = .left
        }

        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.alignment = .left
        nsView.currentEditor()?.alignment = .left
        context.coordinator.onCommand = onCommand
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate, NSTextFieldDelegate {
        @Binding var text: String
        var onCommand: (Command) -> Void

        init(text: Binding<String>, onCommand: @escaping (Command) -> Void) {
            _text = text
            self.onCommand = onCommand
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                onCommand(.moveUp)
                return true
            case #selector(NSResponder.moveDown(_:)):
                onCommand(.moveDown)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                onCommand(.confirmSelection)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onCommand(.cancel)
                return true
            default:
                return false
            }
        }
    }
}
