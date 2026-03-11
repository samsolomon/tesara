import SwiftUI
import WebKit

struct TerminalWebView: NSViewRepresentable {
    let theme: TerminalTheme
    let fontFamily: String
    let fontSize: Double
    let transcript: String
    let onInput: (String) -> Void
    let onResize: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput, onResize: onResize)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: Coordinator.inputHandlerName)
        configuration.userContentController.add(context.coordinator, name: Coordinator.resizeHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.setValue(false, forKey: "drawsBackground")

        if let pageURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "TerminalAssets") {
            webView.loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
        }

        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.inputHandlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.resizeHandlerName)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.renderScript = context.coordinator.makeRenderScript(
            theme: theme,
            fontFamily: fontFamily,
            fontSize: fontSize,
            transcript: transcript
        )
        context.coordinator.flushIfPossible()
    }

    private struct Payload: Encodable {
        let theme: TerminalTheme
        let fontFamily: String
        let fontSize: Double
        let replace: Bool
        let content: String
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let inputHandlerName = "terminalInput"
        static let resizeHandlerName = "terminalResize"

        weak var webView: WKWebView?
        var isReady = false
        var renderScript: String?
        private let onInput: (String) -> Void
        private let onResize: (Int, Int) -> Void
        private var lastRenderedTranscript = ""
        private var lastReportedSize: (cols: Int, rows: Int)?
        private var pendingRenderState: RenderState?

        init(onInput: @escaping (String) -> Void, onResize: @escaping (Int, Int) -> Void) {
            self.onInput = onInput
            self.onResize = onResize
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            lastRenderedTranscript = ""
            if let pendingRenderState {
                renderScript = makeRenderScript(
                    theme: pendingRenderState.theme,
                    fontFamily: pendingRenderState.fontFamily,
                    fontSize: pendingRenderState.fontSize,
                    transcript: pendingRenderState.transcript
                )
            }
            flushIfPossible()
        }

        func makeRenderScript(theme: TerminalTheme, fontFamily: String, fontSize: Double, transcript: String) -> String? {
            pendingRenderState = RenderState(
                theme: theme,
                fontFamily: fontFamily,
                fontSize: fontSize,
                transcript: transcript
            )

            let payload: Payload

            if transcript.isEmpty {
                payload = Payload(theme: theme, fontFamily: fontFamily, fontSize: fontSize, replace: true, content: "")
                lastRenderedTranscript = ""
            } else if transcript.hasPrefix(lastRenderedTranscript) {
                let chunk = String(transcript.dropFirst(lastRenderedTranscript.count))
                payload = Payload(theme: theme, fontFamily: fontFamily, fontSize: fontSize, replace: false, content: chunk)
                lastRenderedTranscript = transcript
            } else {
                payload = Payload(theme: theme, fontFamily: fontFamily, fontSize: fontSize, replace: true, content: transcript)
                lastRenderedTranscript = transcript
            }

            guard
                let data = try? JSONEncoder().encode(payload),
                let json = String(data: data, encoding: .utf8)
            else {
                return nil
            }

            return "window.tesaraRender(\(json));"
        }

        func flushIfPossible() {
            guard isReady, let webView, let renderScript else {
                return
            }

            webView.evaluateJavaScript(renderScript)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case Self.inputHandlerName:
                guard let data = message.body as? String else {
                    return
                }
                onInput(data)
            case Self.resizeHandlerName:
                guard
                    let body = message.body as? [String: Any],
                    let cols = body["cols"] as? Int,
                    let rows = body["rows"] as? Int,
                    cols > 0,
                    rows > 0
                else {
                    return
                }

                let nextSize = (cols: cols, rows: rows)
                guard lastReportedSize?.cols != cols || lastReportedSize?.rows != rows else {
                    return
                }

                lastReportedSize = nextSize
                onResize(cols, rows)
            default:
                return
            }
        }

        private struct RenderState {
            let theme: TerminalTheme
            let fontFamily: String
            let fontSize: Double
            let transcript: String
        }
    }
}
