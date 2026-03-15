import AppKit
import SwiftUI

enum FixedPitchFontLibrary {
    static func allFamilies() -> [String] {
        normalize(NSFontManager.shared.availableFontFamilies.filter(isFixedPitchFamily))
    }

    static func normalize(_ families: [String]) -> [String] {
        var seen: Set<String> = []
        let uniqueFamilies = families.compactMap { family -> String? in
            let trimmed = family.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }

        return uniqueFamilies.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    static func filter(_ families: [String], query: String) -> [String] {
        let normalizedFamilies = normalize(families)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return normalizedFamilies }

        return normalizedFamilies.filter {
            $0.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    static func contains(_ family: String, in families: [String]) -> Bool {
        families.contains { $0.caseInsensitiveCompare(family) == .orderedSame }
    }

    private static func isFixedPitchFamily(_ family: String) -> Bool {
        if let font = NSFont(name: family, size: 13), font.isFixedPitch {
            return true
        }

        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family) else {
            return false
        }

        for member in members {
            for value in member {
                guard let fontName = value as? String else { continue }
                if let font = NSFont(name: fontName, size: 13), font.isFixedPitch {
                    return true
                }
            }
        }

        return false
    }
}

enum FixedPitchFontNavigation {
    enum Direction {
        case up
        case down
    }

    static func canonicalSelection(_ family: String, in families: [String]) -> String? {
        families.first { $0.caseInsensitiveCompare(family) == .orderedSame }
    }

    static func reconciledHighlight(current: String?, selection: String, in families: [String]) -> String? {
        if let current, let canonical = canonicalSelection(current, in: families) {
            return canonical
        }

        if let canonicalSelection = canonicalSelection(selection, in: families) {
            return canonicalSelection
        }

        return families.first
    }

    static func move(current: String?, direction: Direction, in families: [String]) -> String? {
        guard !families.isEmpty else { return nil }

        guard let current, let index = families.firstIndex(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) else {
            return direction == .up ? families.last : families.first
        }

        switch direction {
        case .up:
            return index > 0 ? families[index - 1] : families.first
        case .down:
            return index < families.count - 1 ? families[index + 1] : families.last
        }
    }

    static func selectionToApply(highlighted: String?, in families: [String]) -> String? {
        if let highlighted, let canonical = canonicalSelection(highlighted, in: families) {
            return canonical
        }

        return families.first
    }
}

struct FixedPitchFontPicker: View {
    @Binding var selection: String
    let previewSize: Double

    @State private var isPresented = false
    @State private var searchText = ""

    private let availableFamilies = FixedPitchFontLibrary.allFamilies()

    private var selectedFamilyLabel: String {
        selection.isEmpty ? "SF Mono" : selection
    }

    private var selectedFamilyAvailable: Bool {
        FixedPitchFontLibrary.contains(selectedFamilyLabel, in: availableFamilies)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Font Family") {
                Button {
                    isPresented = true
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(selectedFamilyLabel)
                                .foregroundStyle(.primary)
                            Text(selectedFamilyAvailable ? "Fixed-pitch font" : "Unavailable on this Mac")
                                .font(.caption)
                                .foregroundStyle(selectedFamilyAvailable ? .secondary : Color.orange)
                        }

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                    FixedPitchFontPickerPopover(
                        selection: $selection,
                        searchText: $searchText,
                        availableFamilies: availableFamilies,
                        previewSize: previewSize,
                        dismiss: dismissPicker
                    )
                }
            }

            Text("Choose from installed fixed-pitch fonts with live search.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: isPresented) { _, newValue in
            if !newValue {
                searchText = ""
            }
        }
    }

    private func dismissPicker() {
        searchText = ""
        isPresented = false
    }
}

private struct FixedPitchFontPickerPopover: View {
    @Binding var selection: String
    @Binding var searchText: String

    let availableFamilies: [String]
    let previewSize: Double
    let dismiss: () -> Void

    @State private var highlightedFamily: String?
    @State private var hoveredFamily: String?

    private var filteredFamilies: [String] {
        FixedPitchFontLibrary.filter(availableFamilies, query: searchText)
    }

    private var selectedFamilyAvailable: Bool {
        FixedPitchFontLibrary.contains(selection, in: availableFamilies)
    }

    private var previewFontSize: Double {
        min(max(previewSize, 11), 16)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Font Family")
                .font(.headline)

            FontSearchField(text: $searchText, onCommand: handleSearchCommand)
                .frame(height: 28)

            if !selectedFamilyAvailable, !selection.isEmpty {
                Label("Current selection is not installed on this Mac.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }

            if filteredFamilies.isEmpty {
                ContentUnavailableView(
                    "No Fonts Found",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search term.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(filteredFamilies, id: \.self) { family in
                                fontRow(for: family)
                                    .id(family)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        scrollHighlightedRow(intoView: proxy)
                    }
                    .onChange(of: highlightedFamily) { _, _ in
                        scrollHighlightedRow(intoView: proxy)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 360, height: 420)
        .onAppear {
            highlightedFamily = FixedPitchFontNavigation.reconciledHighlight(
                current: highlightedFamily,
                selection: selection,
                in: filteredFamilies
            )
        }
        .onChange(of: filteredFamilies) { _, newFamilies in
            highlightedFamily = FixedPitchFontNavigation.reconciledHighlight(
                current: highlightedFamily,
                selection: selection,
                in: newFamilies
            )
        }
    }

    private func fontRow(for family: String) -> some View {
        let isSelected = family.caseInsensitiveCompare(selection) == .orderedSame
        let isHovered = family.caseInsensitiveCompare(hoveredFamily ?? "") == .orderedSame
        let isHighlighted = family.caseInsensitiveCompare(highlightedFamily ?? "") == .orderedSame

        return Button {
            selection = family
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(family)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(.primary)
                    Text("Aa 0O {} ~/src")
                        .font(.custom(family, size: previewFontSize))
                        .foregroundStyle(.secondary)
                }

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
                hoveredFamily = family
                highlightedFamily = family
            } else if hoveredFamily?.caseInsensitiveCompare(family) == .orderedSame {
                hoveredFamily = nil
            }
        }
    }

    private func handleSearchCommand(_ command: FontSearchField.Command) {
        switch command {
        case .moveUp:
            highlightedFamily = FixedPitchFontNavigation.move(
                current: highlightedFamily,
                direction: .up,
                in: filteredFamilies
            )
        case .moveDown:
            highlightedFamily = FixedPitchFontNavigation.move(
                current: highlightedFamily,
                direction: .down,
                in: filteredFamilies
            )
        case .confirmSelection:
            guard let family = FixedPitchFontNavigation.selectionToApply(
                highlighted: highlightedFamily,
                in: filteredFamilies
            ) else {
                NSSound.beep()
                return
            }
            selection = family
            dismiss()
        case .cancel:
            dismiss()
        }
    }

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

    private func scrollHighlightedRow(intoView proxy: ScrollViewProxy) {
        guard let highlightedFamily else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.12)) {
                proxy.scrollTo(highlightedFamily, anchor: .center)
            }
        }
    }
}

private struct FontSearchField: NSViewRepresentable {
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
        searchField.placeholderString = "Search fixed-pitch fonts"
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
