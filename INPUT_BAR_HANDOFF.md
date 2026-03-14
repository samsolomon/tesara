# Input Bar Handoff

Last updated: 2026-03-14

## Goal

Tesara now has a bottom-pinned native input editor region that is optional, toggleable, and hidden when the shell is not at a prompt.

The current blocker is that the input bar shows a cursor, but typed text is still not visibly rendering in the bottom editor during live manual testing.

## What Works

- The input editor is rendered as a real bottom region instead of an overlay.
- The UI chrome has been simplified to a thin divider and a terminal-matched background.
- The input editor can be toggled on and off.
- Prompt-time show/hide is wired through `session.isAtPrompt`.
- The input bar height is now stable and no longer collapses when the placeholder disappears.
- Build is green and targeted tests are green.

## Current User-Visible Problem

Repro from a fresh prompt:

1. Launch Tesara with the input editor enabled.
2. Run a command like `pwd` so the bottom input bar appears.
3. Click the bottom input region and type.

Observed:

- The bottom input region shows a cursor.
- Typed glyphs are not visible in the bottom editor.
- The latest manual report says the height no longer changes, so the collapse issue appears fixed.

Important nuance:

- This may still be a focus/event-routing bug, a rendering bug, or both.
- The screenshots suggest the bottom editor owns a visible cursor, but that does not prove text is being drawn there.

## Likely Investigation Areas

### 1. Verify whether text is reaching `InputBarState.editorSession`

Key files:

- `Tesara/Terminal/InputBarView.swift`
- `Tesara/Ghostty/GhosttySurfaceView.swift`
- `Tesara/Editor/EditorView.swift`

Questions to answer first:

- Does `editorSession.storage.entireString()` change while the user types at the prompt?
- If yes, this is probably a rendering/theme/viewport bug in `EditorView`.
- If no, this is still a responder-chain or event-routing issue.

### 2. Check first responder ownership at runtime

Relevant code:

- `Tesara/Terminal/PaneContainerView.swift` (`focusInputBar`, `syncInputBarPresentation`)
- `Tesara/Ghostty/GhosttySurfaceView.swift` (`keyboardFocusDisabled`, `keyDown(with:)`)
- `Tesara/Editor/EditorView.swift` (`keyDown(with:)`, `focusDidChange(_:)`)

The current fallback forwards key events from `GhosttySurfaceView` into the editor when `keyboardFocusDisabled` is true, but the manual result still does not show typed glyphs.

### 3. Check editor drawing in the input-bar host geometry

Relevant code:

- `Tesara/Terminal/InputBarView.swift`
- `Tesara/Editor/EditorView.swift`
- `Tesara/Editor/EditorRenderer.swift`

Things to verify:

- `EditorView.contentSize` is non-zero in the input bar.
- `renderFrame()` sees glyphs when typing.
- Theme foreground/background values are correct for the bottom editor.
- The cursor can render while glyph drawing still fails because of viewport sizing, clipping, or color state.

## Relevant Files

- `Tesara/Terminal/InputBarView.swift`
- `Tesara/Terminal/PaneContainerView.swift`
- `Tesara/Terminal/TerminalSession.swift`
- `Tesara/Ghostty/GhosttySurfaceView.swift`
- `Tesara/App/KeyBindingDispatcher.swift`
- `Tesara/App/TesaraAppCommands.swift`
- `Tesara/Settings/AppSettings.swift`
- `Tesara/Settings/ConfigFile.swift`
- `Tesara/Settings/SettingsStore.swift`
- `Tesara/Settings/SettingsView.swift`
- `Tesara/Terminal/TerminalWorkspaceView.swift`
- `TesaraTests/TerminalSessionTests.swift`
- `TesaraTests/KeyBindingDispatcherTests.swift`

## Verification Status

Most recent checks:

- `xcodebuild -project Tesara.xcodeproj -scheme Tesara -destination 'platform=macOS' build`
- `xcodebuild -project Tesara.xcodeproj -scheme Tesara -destination 'platform=macOS' -only-testing:TesaraTests/TerminalSessionTests -only-testing:TesaraTests/KeyBindingDispatcherTests test`

Result:

- Build succeeded.
- Targeted tests succeeded.

## Suggested Next Move

Do not spend more time on visual chrome until the text visibility bug is understood.

The fastest next debugging pass is:

1. instrument whether the input editor session storage changes while typing
2. instrument whether `EditorView.renderFrame()` receives glyph instances for the bottom editor
3. only after that, adjust theme/color logic if storage is updating and glyphs are present but invisible
