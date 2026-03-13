import SwiftUI

/// Thin NSViewRepresentable that hosts a pre-existing `GhosttySurfaceView`.
///
/// Critical: this wrapper returns a pre-existing view — it never creates one.
/// `ghostty_surface_new()` permanently binds a Metal layer to the NSView.
/// If SwiftUI recreated the view, all terminal state would be destroyed.
/// The session owns the view; SwiftUI just hosts it.
struct GhosttySurfaceRepresentable: NSViewRepresentable {
    let surfaceView: GhosttySurfaceView

    func makeNSView(context: Context) -> GhosttySurfaceView {
        surfaceView
    }

    func updateNSView(_ nsView: GhosttySurfaceView, context: Context) {
        // No updates needed — the session manages the view directly
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GhosttySurfaceView, context: Context) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    // No dismantleNSView — the session retains the view
}
