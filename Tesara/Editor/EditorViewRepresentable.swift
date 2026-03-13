import SwiftUI

/// Thin NSViewRepresentable that hosts a pre-existing `EditorView`.
/// Same pattern as `GhosttySurfaceRepresentable` — never creates a new view.
struct EditorViewRepresentable: NSViewRepresentable {
    let editorView: EditorView

    func makeNSView(context: Context) -> EditorView {
        editorView
    }

    func updateNSView(_ nsView: EditorView, context: Context) {
        // No updates needed — the session manages the view directly
    }
}
