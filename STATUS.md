# Tesara Status

Last updated: 2026-03-11

## Current State

Tesara is at the first functional local alpha milestone.

Working now:
- Native macOS SwiftUI app shell with generated Xcode project
- PTY-backed terminal session management
- Bundled local `xterm.js` renderer inside `WKWebView`
- Incremental native-to-WebKit output bridge
- WebKit-to-native keyboard input bridge
- Fit/resize handling with PTY window size propagation
- Settings foundation for theme, shell, working directory, keyboard, updates, and privacy
- Bundled theme system with JSON import/export support scaffolding
- OSC 133 parsing for command block boundaries
- GRDB-backed session/block persistence
- History screen showing captured command blocks
- Shell integration for both `zsh` and `bash`
- Graceful fallback if the history database cannot start

## What Has Been Built

### Foundation
- Created `Tesara.xcodeproj` from `project.yml`
- Set bundle ID to `com.samsolomon.tesara`
- Targeting `macOS 14+`
- Added dependencies:
  - `GRDB.swift`
  - `Sparkle`
  - bundled `xterm.js`

### App and Settings
- `Tesara/TesaraApp.swift`
- `Tesara/MainWindowView.swift`
- `Tesara/Settings/AppSettings.swift`
- `Tesara/Settings/SettingsStore.swift`
- `Tesara/Settings/SettingsView.swift`
- `Tesara/Theme/TerminalTheme.swift`
- `Tesara/Theme/BuiltInTheme.swift`

### Terminal Stack
- `Tesara/Terminal/TerminalLauncher.swift`
- `Tesara/Terminal/TerminalSession.swift`
- `Tesara/Terminal/TerminalWebView.swift`
- `Tesara/Terminal/TerminalWorkspaceView.swift`
- `Tesara/Terminal/OSC133Parser.swift`
- `Tesara/Resources/TerminalAssets/`
- `Tesara/Resources/TerminalIntegration/`

### History / Block Capture
- `Tesara/History/BlockStore.swift`
- `Tesara/History/HistoryView.swift`
- `Tesara/History/TerminalBlockCapture.swift`

### Tests
- `TesaraTests/TesaraTests.swift`
- `TesaraTests/OSC133ParserTests.swift`

## Recent Commits

- `e5c616a` Add bash shell integration support
- `015cbcc` Add local alpha block capture milestone
- `252b210` Add xterm-based terminal renderer
- `c98e4c9` Create initial Tesara macOS terminal scaffold

## First Test Milestone Reached

The first meaningful local alpha is ready.

You can now test:
- terminal startup
- direct shell interaction in the terminal surface
- command block capture in `zsh`
- command block capture in `bash`
- persisted history entries in the History screen

Recommended manual test flow:
1. Launch Tesara from Xcode
2. Set shell to `zsh`
3. Run `pwd`, `ls`, `echo hello`, `false`
4. Open History and confirm command, output, exit state, and timestamps
5. Repeat with shell set to `bash`

## Known Gaps

- Multiline command capture still needs polish
- Paste behavior and special key handling still need polish
- Shell integration currently focuses on `zsh` and `bash`, not `fish`
- No TUI passthrough mode yet
- No block metadata beyond core prompt / command / finish lifecycle
- No release signing, notarization, or updater wiring yet
- Settings UI exists as scaffolding, not finished production behavior

## Next Plan

### Immediate next session
1. Test real capture quality in `zsh` and `bash`
2. Fix multiline command capture edge cases
3. Improve paste behavior and special key handling
4. Reduce reliance on shell-hook assumptions where possible

### After capture quality is solid
1. Add TUI passthrough toggle
2. Expand block model and storage schema as needed
3. Tighten settings validation and persistence behavior
4. Start release-system work: signing, notarization, Sparkle, privacy docs

## Resume Notes

If resuming later, start from this question:

"Does block capture behave correctly for multiline commands, pasted commands, and normal interactive use in both zsh and bash?"

That is the highest-value next checkpoint before moving deeper into polish and release work.
