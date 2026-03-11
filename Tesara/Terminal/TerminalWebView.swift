import SwiftUI
import WebKit

struct TerminalWebView: NSViewRepresentable {
    let theme: TerminalTheme
    let lines: [TerminalSession.Line]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.bootstrapHTML, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let payload = Payload(theme: theme, lines: lines)
        guard
            let data = try? JSONEncoder().encode(payload),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }

        context.coordinator.renderScript = "window.tesaraRender(\(json));"
        context.coordinator.flushIfPossible()
    }

    private struct Payload: Encodable {
        let theme: TerminalTheme
        let lines: [RenderableLine]

        init(theme: TerminalTheme, lines: [TerminalSession.Line]) {
            self.theme = theme
            self.lines = lines.map { RenderableLine(kind: $0.kind.rawValue, text: $0.text) }
        }
    }

    private struct RenderableLine: Encodable {
        let kind: String
        let text: String
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var isReady = false
        var renderScript: String?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            flushIfPossible()
        }

        func flushIfPossible() {
            guard isReady, let webView, let renderScript else {
                return
            }

            webView.evaluateJavaScript(renderScript)
        }
    }

    private static let bootstrapHTML = """
    <!doctype html>
    <html>
    <head>
      <meta charset=\"utf-8\">
      <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
      <style>
        :root {
          color-scheme: dark;
        }
        html, body {
          margin: 0;
          height: 100%;
          overflow: hidden;
          background: #0b1020;
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        }
        #terminal {
          box-sizing: border-box;
          height: 100%;
          overflow: auto;
          padding: 18px 20px 24px;
          white-space: pre-wrap;
          word-break: break-word;
          line-height: 1.45;
          font-size: 13px;
        }
        .line { margin: 0 0 4px; }
        .info { opacity: 0.72; }
        .input { font-weight: 600; }
        .error { color: #f87171; }
      </style>
    </head>
    <body>
      <div id=\"terminal\"></div>
      <script>
        const root = document.getElementById('terminal');
        window.tesaraRender = function(payload) {
          document.body.style.background = payload.theme.background;
          root.style.color = payload.theme.foreground;
          root.innerHTML = '';
          for (const line of payload.lines) {
            const element = document.createElement('div');
            element.className = 'line ' + line.kind;
            element.textContent = line.text;
            if (line.kind === 'input') element.style.color = payload.theme.yellow;
            if (line.kind === 'info') element.style.color = payload.theme.cyan;
            if (line.kind === 'error') element.style.color = payload.theme.red;
            root.appendChild(element);
          }
          root.scrollTop = root.scrollHeight;
        };
      </script>
    </body>
    </html>
    """
}
