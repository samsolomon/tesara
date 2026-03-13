import AppKit
import SwiftUI

/// A SwiftUI view that captures a keyboard shortcut via an embedded NSView.
/// Displays the current shortcut or "Default" when idle, and "Press shortcut..." when recording.
struct KeyRecorderView: View {
    let action: KeyBindingAction
    let currentShortcut: KeyShortcut?
    let onRecord: (KeyShortcut) -> Void
    let onClear: () -> Void

    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 6) {
            if isRecording {
                KeyCaptureRepresentable { shortcut in
                    isRecording = false
                    if let shortcut {
                        onRecord(shortcut)
                    }
                }
                .frame(width: 0, height: 0)
                .opacity(0)

                Text("Press shortcut...")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.blue.opacity(0.6), lineWidth: 1.5)
                    )

                Button("Cancel") {
                    isRecording = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            } else {
                Button {
                    isRecording = true
                } label: {
                    Text(displayText)
                        .foregroundStyle(hasOverride ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                if hasOverride {
                    Button {
                        onClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Restore default")
                }
            }
        }
    }

    private var hasOverride: Bool {
        currentShortcut != action.defaultShortcut
    }

    private var displayText: String {
        if let currentShortcut {
            return currentShortcut.displayValue
        }
        if let defaultShortcut = action.defaultShortcut {
            return defaultShortcut.displayValue
        }
        return "None"
    }
}

// MARK: - NSView wrapper for key capture

private struct KeyCaptureRepresentable: NSViewRepresentable {
    let onCapture: (KeyShortcut?) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
    }
}

private final class KeyCaptureNSView: NSView {
    var onCapture: ((KeyShortcut?) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        // Escape cancels recording
        if event.keyCode == 53 {
            onCapture?(nil)
            return
        }

        guard let shortcut = KeyShortcut(event: event) else {
            // No valid modifier combo — ignore (e.g., bare letter key)
            NSSound.beep()
            return
        }

        if shortcut.isReserved {
            NSSound.beep()
            return
        }

        onCapture?(shortcut)
    }

    // Suppress system beep for unhandled keys
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        true
    }

    override func flagsChanged(with event: NSEvent) {
        // No-op: we capture on keyDown, not on modifier-only presses
    }
}
