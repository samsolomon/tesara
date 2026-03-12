import Foundation

struct TranscriptLog {
    struct Segment {
        let offset: Int
        let text: String
    }

    private(set) var segments: [Segment] = []
    private(set) var totalLength: Int = 0

    mutating func append(_ text: String) {
        guard !text.isEmpty else { return }
        segments.append(Segment(offset: totalLength, text: text))
        totalLength += text.utf8.count
    }

    func contentSince(offset: Int) -> String {
        guard offset < totalLength else { return "" }

        var result = ""
        for segment in segments {
            let segmentEnd = segment.offset + segment.text.utf8.count
            if segmentEnd <= offset { continue }

            if segment.offset >= offset {
                result.append(segment.text)
            } else {
                let bytesToSkip = offset - segment.offset
                let utf8 = segment.text.utf8
                if let startIndex = utf8.index(utf8.startIndex, offsetBy: bytesToSkip, limitedBy: utf8.endIndex),
                   let sliced = String(utf8[startIndex...]) {
                    result.append(sliced)
                }
            }
        }

        return result
    }

    mutating func pruneSegments(before offset: Int) {
        segments.removeAll { $0.offset + $0.text.utf8.count <= offset }
    }

    mutating func reset() {
        segments.removeAll()
        totalLength = 0
    }
}
