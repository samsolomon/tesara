import Foundation

enum OSC133Event: Equatable {
    case promptStart
    case commandInputStart
    case commandExecuted
    case commandFinished(exitCode: Int?)
}

enum OSC133Token: Equatable {
    case text(String)
    case event(OSC133Event)
}

protocol OSC133Parsing {
    func feed(_ chunk: String) -> [OSC133Token]
    func reset()
}

final class OSC133Parser: OSC133Parsing {
    private var pending = ""

    func reset() {
        pending = ""
    }

    func feed(_ chunk: String) -> [OSC133Token] {
        pending.append(chunk)

        var tokens: [OSC133Token] = []
        var textBuffer = ""
        var index = pending.startIndex

        while index < pending.endIndex {
            let character = pending[index]

            if character == "\u{1B}", let nextIndex = pending.index(index, offsetBy: 1, limitedBy: pending.endIndex), nextIndex < pending.endIndex, pending[nextIndex] == "]" {
                if !textBuffer.isEmpty {
                    tokens.append(.text(textBuffer))
                    textBuffer = ""
                }

                let sequenceStart = index
                let contentStart = pending.index(index, offsetBy: 2)
                guard let terminatorRange = terminatorRange(in: pending, from: contentStart) else {
                    pending = String(pending[sequenceStart...])
                    return tokens
                }

                let content = String(pending[contentStart..<terminatorRange.lowerBound])
                if let event = parseEvent(from: content) {
                    tokens.append(.event(event))
                }

                index = terminatorRange.upperBound
                continue
            }

            textBuffer.append(character)
            index = pending.index(after: index)
        }

        if !textBuffer.isEmpty {
            tokens.append(.text(textBuffer))
        }

        pending = ""
        return tokens
    }

    private func parseEvent(from content: String) -> OSC133Event? {
        guard content.hasPrefix("133;") else {
            return nil
        }

        let payload = content.dropFirst(4)
        if payload == "A" {
            return .promptStart
        }

        if payload == "B" {
            return .commandInputStart
        }

        if payload == "C" {
            return .commandExecuted
        }

        if payload.hasPrefix("D") {
            let parts = payload.split(separator: ";", omittingEmptySubsequences: false)
            let exitCode = parts.count > 1 ? Int(parts[1]) : nil
            return .commandFinished(exitCode: exitCode)
        }

        return nil
    }

    private func terminatorRange(in source: String, from start: String.Index) -> Range<String.Index>? {
        var index = start

        while index < source.endIndex {
            let character = source[index]

            if character == "\u{07}" {
                let endIndex = source.index(after: index)
                return index..<endIndex
            }

            if character == "\u{1B}", let nextIndex = source.index(index, offsetBy: 1, limitedBy: source.endIndex), nextIndex < source.endIndex, source[nextIndex] == "\\" {
                let endIndex = source.index(after: nextIndex)
                return index..<endIndex
            }

            index = source.index(after: index)
        }

        return nil
    }
}
