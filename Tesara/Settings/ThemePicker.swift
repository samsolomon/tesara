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

    private var builtInThemes: [TerminalTheme] {
        themes.filter { !$0.id.hasPrefix("ghostty-") && !importedIDs.contains($0.id) }
    }

    private var ghosttyThemes: [TerminalTheme] {
        themes.filter { $0.id.hasPrefix("ghostty-") }
    }

    private var importedThemes: [TerminalTheme] {
        themes.filter { importedIDs.contains($0.id) }
    }

    private var importedIDs: Set<String> {
        let builtInIDs = Set(BuiltInTheme.allCases.map(\.id))
        return Set(themes.filter { !$0.id.hasPrefix("ghostty-") && !builtInIDs.contains($0.id) }.map(\.id))
    }

    private var filteredBuiltIn: [TerminalTheme] {
        filterThemes(builtInThemes)
    }

    private var filteredGhostty: [TerminalTheme] {
        filterThemes(ghosttyThemes)
    }

    private var filteredImported: [TerminalTheme] {
        filterThemes(importedThemes)
    }

    private var allFilteredIDs: [String] {
        filteredBuiltIn.map(\.id) + filteredGhostty.map(\.id) + filteredImported.map(\.id)
    }

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
                            if !filteredBuiltIn.isEmpty {
                                sectionHeader("Tesara")
                                ForEach(filteredBuiltIn) { theme in
                                    themeRow(for: theme).id(theme.id)
                                }
                            }

                            if !filteredGhostty.isEmpty {
                                sectionHeader("Community")
                                ForEach(filteredGhostty) { theme in
                                    themeRow(for: theme).id(theme.id)
                                }
                            }

                            if !filteredImported.isEmpty {
                                sectionHeader("Imported")
                                ForEach(filteredImported) { theme in
                                    themeRow(for: theme).id(theme.id)
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
            highlightedThemeID = reconciledHighlight(current: nil)
        }
        .onChange(of: allFilteredIDs) { _, _ in
            highlightedThemeID = reconciledHighlight(current: highlightedThemeID)
        }
        .onChange(of: highlightedThemeID) { _, newID in
            schedulePreview(for: newID)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func themeRow(for theme: TerminalTheme) -> some View {
        let isSelected = theme.id == selection
        let isHovered = theme.id == hoveredThemeID
        let isHighlighted = theme.id == highlightedThemeID

        return Button {
            selection = theme.id
            settingsStore.previewThemeID = nil
            dismiss()
        } label: {
            HStack(spacing: 10) {
                colorSwatches(for: theme)

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
                    .fill(backgroundColor(isSelected: isSelected, isHighlighted: isHighlighted, isHovered: isHovered))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor(isSelected: isSelected, isHovered: isHovered), lineWidth: borderWidth(isSelected: isSelected, isHovered: isHovered))
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hovering in
            if hovering {
                hoveredThemeID = theme.id
                highlightedThemeID = theme.id
            } else if hoveredThemeID == theme.id {
                hoveredThemeID = nil
            }
        }
    }

    private func colorSwatches(for theme: TerminalTheme) -> some View {
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
            selection = id
            settingsStore.previewThemeID = nil
            dismiss()
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

    // MARK: - Styling

    private func backgroundColor(isSelected: Bool, isHighlighted: Bool, isHovered: Bool) -> Color {
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

    private func borderColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.45)
        }
        if isHovered {
            return Color.primary.opacity(0.16)
        }
        return .clear
    }

    private func borderWidth(isSelected: Bool, isHovered: Bool) -> CGFloat {
        (isSelected || isHovered) ? 1 : 0
    }

    // MARK: - Filtering

    private func filterThemes(_ list: [TerminalTheme]) -> [TerminalTheme] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
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
