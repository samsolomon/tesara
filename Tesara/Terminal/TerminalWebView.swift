import SwiftUI
import WebKit

struct TerminalWebView: NSViewRepresentable {
    let theme: TerminalTheme
    let fontFamily: String
    let fontSize: Double
    let transcriptLog: TranscriptLog
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

        let webView = TerminalWKWebView(frame: .zero, configuration: configuration)
        webView.onPasteText = { [onInput] text in onInput(text) }
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
            transcriptLog: transcriptLog
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
        private var lastRenderedOffset: Int = 0
        private var lastReportedSize: (cols: Int, rows: Int)?
        private var pendingRenderState: RenderState?

        // Track last-rendered theme/font to skip full renders on content-only updates
        private var lastTheme: TerminalTheme?
        private var lastFontFamily: String?
        private var lastFontSize: Double?
        private static let jsonEncoder = JSONEncoder()

        init(onInput: @escaping (String) -> Void, onResize: @escaping (Int, Int) -> Void) {
            self.onInput = onInput
            self.onResize = onResize
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            lastRenderedOffset = 0
            webView.window?.makeFirstResponder(webView)
            if let pendingRenderState {
                renderScript = makeRenderScript(
                    theme: pendingRenderState.theme,
                    fontFamily: pendingRenderState.fontFamily,
                    fontSize: pendingRenderState.fontSize,
                    transcriptLog: pendingRenderState.transcriptLog
                )
            }
            flushIfPossible()
        }

        func makeRenderScript(theme: TerminalTheme, fontFamily: String, fontSize: Double, transcriptLog: TranscriptLog) -> String? {
            let themeChanged = lastTheme != theme
            let fontChanged = lastFontFamily != fontFamily || lastFontSize != fontSize
            let needsFullRender = themeChanged || fontChanged

            // Determine content delta
            let replace: Bool
            let content: String

            if transcriptLog.totalLength == 0 {
                replace = true
                content = ""
                lastRenderedOffset = 0
            } else if transcriptLog.totalLength >= lastRenderedOffset {
                replace = false
                content = transcriptLog.contentSince(offset: lastRenderedOffset)
                lastRenderedOffset = transcriptLog.totalLength
            } else {
                // Log was reset — full replace
                replace = true
                content = transcriptLog.contentSince(offset: 0)
                lastRenderedOffset = transcriptLog.totalLength
            }

            // Nothing to do — no theme change and no new content
            if !needsFullRender && !replace && content.isEmpty {
                return nil
            }

            // Store pending state for replay after navigation finishes
            pendingRenderState = RenderState(
                theme: theme,
                fontFamily: fontFamily,
                fontSize: fontSize,
                transcriptLog: transcriptLog
            )

            // Fast path: content-only write (no theme/font JSON encoding)
            if !needsFullRender && !replace {
                guard let escaped = try? Self.jsonEncoder.encode(content),
                      let json = String(data: escaped, encoding: .utf8) else {
                    return nil
                }
                return "window.tesaraWrite(\(json));"
            }

            // Full render path: theme/font changed or log reset
            lastTheme = theme
            lastFontFamily = fontFamily
            lastFontSize = fontSize

            let payload = Payload(theme: theme, fontFamily: fontFamily, fontSize: fontSize, replace: replace, content: content)

            guard
                let data = try? Self.jsonEncoder.encode(payload),
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

            self.renderScript = nil
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
            let transcriptLog: TranscriptLog
        }
    }
}
