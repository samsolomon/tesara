import Foundation

struct TerminalBlockCapture {
    enum Stage {
        case command
        case output
    }

    var commandText: String = ""
    var outputText: String = ""
    var exitCode: Int?
    var startedAt: Date
    var finishedAt: Date
    var stage: Stage
}
