import Foundation

@MainActor
final class TextStorage {

    // MARK: - Types

    struct Position: Equatable, Comparable {
        var line: Int
        var column: Int  // UTF-16 offset

        static func < (lhs: Position, rhs: Position) -> Bool {
            if lhs.line != rhs.line { return lhs.line < rhs.line }
            return lhs.column < rhs.column
        }
    }

    struct Range: Equatable {
        var start: Position
        var end: Position

        var normalized: Range {
            start <= end ? self : Range(start: end, end: start)
        }

        var isEmpty: Bool {
            start == end
        }
    }

    enum Direction {
        case left, right
    }

    // MARK: - State

    private(set) var lines: [NSMutableString] = [NSMutableString()]

    var lineCount: Int { lines.count }

    // MARK: - Queries

    func lineContent(_ index: Int) -> String {
        guard index >= 0, index < lines.count else { return "" }
        return lines[index] as String
    }

    func lineLength(_ index: Int) -> Int {
        guard index >= 0, index < lines.count else { return 0 }
        return lines[index].length
    }

    func clampPosition(_ pos: Position) -> Position {
        let line = max(0, min(pos.line, lines.count - 1))
        let col = max(0, min(pos.column, lines[line].length))
        return Position(line: line, column: col)
    }

    func entireString() -> String {
        (lines as [NSString]).map { $0 as String }.joined(separator: "\n")
    }

    // MARK: - Bulk Load

    func loadString(_ string: String) {
        lines = string.split(separator: "\n", omittingEmptySubsequences: false)
            .map { NSMutableString(string: String($0)) }
        if lines.isEmpty {
            lines = [NSMutableString()]
        }
    }

    // MARK: - Mutations

    /// Insert text at position. Returns the position after the inserted text.
    @discardableResult
    func insert(_ text: String, at pos: Position, undoManager: UndoManager?) -> Position {
        let clamped = clampPosition(pos)

        // Register undo: delete the inserted text
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] storage in
            // After insert, the text spans from `clamped` to the end position
            let endPos = storage.positionAfterInserting(text, at: clamped)
            storage.delete(range: Range(start: clamped, end: endPos), undoManager: undoManager)
        }

        return performInsert(text, at: clamped)
    }

    /// Delete text in range. Returns the deleted text.
    @discardableResult
    func delete(range: Range, undoManager: UndoManager?) -> String {
        let norm = range.normalized
        let deletedText = textInRange(norm)

        // Register undo: re-insert the deleted text
        let capturedText = deletedText
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] storage in
            storage.insert(capturedText, at: norm.start, undoManager: undoManager)
        }

        performDelete(range: norm)
        return deletedText
    }

    /// Replace text in range. Returns position after the replacement.
    @discardableResult
    func replace(range: Range, with text: String, undoManager: UndoManager?) -> Position {
        let norm = range.normalized
        let oldText = textInRange(norm)

        // Register undo: replace back to old text
        let capturedOld = oldText
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] storage in
            let endPos = storage.positionAfterInserting(text, at: norm.start)
            storage.replace(range: Range(start: norm.start, end: endPos), with: capturedOld, undoManager: undoManager)
        }

        performDelete(range: norm)
        return performInsert(text, at: norm.start)
    }

    // MARK: - Word Boundary

    func wordBoundary(from pos: Position, direction: Direction) -> Position {
        let clamped = clampPosition(pos)

        switch direction {
        case .right:
            return nextWordBoundary(from: clamped)
        case .left:
            return previousWordBoundary(from: clamped)
        }
    }

    // MARK: - Private Helpers

    func textInRange(_ range: Range) -> String {
        let norm = range.normalized
        if norm.start.line == norm.end.line {
            let line = lines[norm.start.line]
            let nsRange = NSRange(location: norm.start.column, length: norm.end.column - norm.start.column)
            return line.substring(with: nsRange)
        }

        var parts: [String] = []
        // First line: from start.column to end
        let firstLine = lines[norm.start.line]
        parts.append(firstLine.substring(from: norm.start.column))

        // Middle lines: full content
        for i in (norm.start.line + 1)..<norm.end.line {
            parts.append(lines[i] as String)
        }

        // Last line: from 0 to end.column
        let lastLine = lines[norm.end.line]
        parts.append(lastLine.substring(to: norm.end.column))

        return parts.joined(separator: "\n")
    }

    private func performInsert(_ text: String, at pos: Position) -> Position {
        let insertLines = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }

        if insertLines.count == 1 {
            // Single-line insert
            lines[pos.line].insert(insertLines[0], at: pos.column)
            return Position(line: pos.line, column: pos.column + (insertLines[0] as NSString).length)
        }

        // Multi-line insert: split current line at cursor
        let currentLine = lines[pos.line]
        let afterCursor = currentLine.substring(from: pos.column)
        currentLine.deleteCharacters(in: NSRange(location: pos.column, length: currentLine.length - pos.column))

        // Append first insert segment to current line
        currentLine.append(insertLines[0])

        // Insert middle lines
        var insertIndex = pos.line + 1
        for i in 1..<(insertLines.count - 1) {
            lines.insert(NSMutableString(string: insertLines[i]), at: insertIndex)
            insertIndex += 1
        }

        // Last insert segment + remainder
        let lastSegment = insertLines[insertLines.count - 1]
        let newLastLine = NSMutableString(string: lastSegment + afterCursor)
        lines.insert(newLastLine, at: insertIndex)

        return Position(line: insertIndex, column: (lastSegment as NSString).length)
    }

    private func performDelete(range: Range) {
        let norm = range.normalized
        guard !norm.isEmpty else { return }

        if norm.start.line == norm.end.line {
            // Single-line delete
            let nsRange = NSRange(location: norm.start.column, length: norm.end.column - norm.start.column)
            lines[norm.start.line].deleteCharacters(in: nsRange)
            return
        }

        // Multi-line delete: keep content before start and after end
        let firstLine = lines[norm.start.line]
        let lastLine = lines[norm.end.line]
        let afterEnd = lastLine.substring(from: norm.end.column)

        // Truncate first line and append remainder
        firstLine.deleteCharacters(in: NSRange(location: norm.start.column, length: firstLine.length - norm.start.column))
        firstLine.append(afterEnd)

        // Remove lines between (inclusive of end line)
        let removeRange = (norm.start.line + 1)...norm.end.line
        lines.removeSubrange(removeRange)
    }

    private func positionAfterInserting(_ text: String, at pos: Position) -> Position {
        let insertLines = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        if insertLines.count == 1 {
            return Position(line: pos.line, column: pos.column + (insertLines[0] as NSString).length)
        }
        let lastLine = insertLines[insertLines.count - 1]
        return Position(line: pos.line + insertLines.count - 1, column: (lastLine as NSString).length)
    }

    // MARK: - Word Boundary Helpers

    private func nextWordBoundary(from pos: Position) -> Position {
        let line = lines[pos.line]

        // At end of line, go to start of next line
        if pos.column >= line.length {
            if pos.line < lines.count - 1 {
                return Position(line: pos.line + 1, column: 0)
            }
            return pos
        }

        let str = line as String
        let utf16 = str.utf16
        var idx = utf16.index(utf16.startIndex, offsetBy: pos.column)

        // Skip current word characters
        let startCategory = characterCategory(at: idx, in: utf16)
        while idx < utf16.endIndex {
            let cat = characterCategory(at: idx, in: utf16)
            if cat != startCategory { break }
            idx = utf16.index(after: idx)
        }

        // Skip whitespace after word
        while idx < utf16.endIndex {
            let cat = characterCategory(at: idx, in: utf16)
            if cat != .whitespace { break }
            idx = utf16.index(after: idx)
        }

        return Position(line: pos.line, column: utf16.distance(from: utf16.startIndex, to: idx))
    }

    private func previousWordBoundary(from pos: Position) -> Position {
        // At start of line, go to end of previous line
        if pos.column == 0 {
            if pos.line > 0 {
                return Position(line: pos.line - 1, column: lines[pos.line - 1].length)
            }
            return pos
        }

        let line = lines[pos.line]
        let str = line as String
        let utf16 = str.utf16
        var idx = utf16.index(utf16.startIndex, offsetBy: min(pos.column, utf16.count))

        // Step back one first
        guard idx > utf16.startIndex else { return Position(line: pos.line, column: 0) }

        // Skip whitespace before cursor
        while idx > utf16.startIndex {
            let prevIdx = utf16.index(before: idx)
            let cat = characterCategory(at: prevIdx, in: utf16)
            if cat != .whitespace { break }
            idx = prevIdx
        }

        // Skip word characters
        guard idx > utf16.startIndex else { return Position(line: pos.line, column: 0) }
        let prevIdx = utf16.index(before: idx)
        let targetCategory = characterCategory(at: prevIdx, in: utf16)
        while idx > utf16.startIndex {
            let prevIdx = utf16.index(before: idx)
            let cat = characterCategory(at: prevIdx, in: utf16)
            if cat != targetCategory { break }
            idx = prevIdx
        }

        return Position(line: pos.line, column: utf16.distance(from: utf16.startIndex, to: idx))
    }

    private enum CharCategory {
        case word, punctuation, whitespace
    }

    private func characterCategory(at index: String.UTF16View.Index, in utf16: String.UTF16View) -> CharCategory {
        let unit = utf16[index]
        let scalar = Unicode.Scalar(unit)
        if let scalar {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return .whitespace
            }
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                return .word
            }
        }
        // Surrogate pairs (emoji, CJK above BMP) treated as word characters
        if unit >= 0xD800 && unit <= 0xDFFF {
            return .word
        }
        // CJK in BMP
        if let scalar, scalar.value >= 0x3000 && scalar.value <= 0x9FFF {
            return .word
        }
        return .punctuation
    }
}

