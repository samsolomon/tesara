# Split Pane Resize Investigation Handoff

Last updated: 2026-03-13

## Problem

In Tesara, split panes cannot be dragged narrower than roughly 35-40% of the window width.

The original assumption was that the split ratio clamp in the pane tree was too conservative, but lowering it did not change the visible minimum width.

## Relevant Files

- `Tesara/Terminal/PaneDividerView.swift`
- `Tesara/Terminal/PaneContainerView.swift`
- `Tesara/Terminal/PaneNode.swift`
- `Tesara/Terminal/WorkspaceManager.swift`
- `Tesara/Terminal/TerminalWorkspaceView.swift`
- `Tesara/Ghostty/GhosttySurfaceView.swift`
- `Tesara/Ghostty/GhosttySurfaceRepresentable.swift`
- `Tesara/Editor/EditorView.swift`
- `Tesara/Editor/EditorViewRepresentable.swift`
- `vendor/ghostty/include/ghostty.h`
- `vendor/ghostty/src/apprt/embedded.zig`

## Current Understanding

The issue does not currently look like a minimum-width clamp in Ghostty.

The stronger current hypothesis is that divider interaction and hit testing are failing, or are being intermittently stolen by the AppKit-backed pane views (`NSViewRepresentable` content). The logs collected so far do not show the split drag callback path firing during the user repro.

## Architecture

Expected split resize flow:

1. `PaneDividerView` detects drag movement and computes a new ratio.
2. `PaneContainerView` forwards the new ratio through `onUpdateRatio`.
3. `WorkspaceManager.updatePaneRatio(splitID:ratio:)` updates the active tab's `rootPane`.
4. `PaneNode.updatingRatio(splitID:ratio:)` clamps and stores the new ratio.
5. `PaneContainerView` re-renders with updated child sizes.
6. Leaf views notify `GhosttySurfaceView.sizeDidChange(_:)` or `EditorView.sizeDidChange(_:)`.

## What Was Tried

### 1. Lowered the pane ratio clamp

File:
- `Tesara/Terminal/PaneNode.swift`

Change:
- `min(max(ratio, 0.1), 0.9)` -> `min(max(ratio, 0.05), 0.95)`

Result:
- No visible change.

Conclusion:
- The stored split ratio clamp is not the active bottleneck.

### 2. Added `sizeThatFits` to `NSViewRepresentable` wrappers

Files:
- `Tesara/Ghostty/GhosttySurfaceRepresentable.swift`
- `Tesara/Editor/EditorViewRepresentable.swift`

Change:
- Added `sizeThatFits(_ proposal:nsView:context:) -> CGSize` returning `proposal.replacingUnspecifiedDimensions()`

Result:
- No visible change.

Conclusion:
- SwiftUI wrapper preferred sizing alone did not explain the minimum width.

### 3. Replaced `HStack` / `VStack` split layout with explicit rect positioning

File:
- `Tesara/Terminal/PaneContainerView.swift`

Change:
- Switched split layout to explicit `ZStack` positioning, explicit pane frames, and clipping.

Result:
- No visible change.

Conclusion:
- Generic stack negotiation was probably not the main cause.

### 4. Forced AppKit views to behave like flexible content

Files:
- `Tesara/Ghostty/GhosttySurfaceView.swift`
- `Tesara/Editor/EditorView.swift`
- `Tesara/Terminal/PaneContainerView.swift`

Changes:
- Overrode `intrinsicContentSize` to use `NSView.noIntrinsicMetric`
- Lowered hugging and compression resistance priorities
- Explicitly synced view frame sizes from `GeometryReader`

Result:
- No visible change.

Conclusion:
- AppKit intrinsic size pressure was not sufficient to explain the problem.

### 5. Changed divider drag math to use global coordinates

File:
- `Tesara/Terminal/PaneDividerView.swift`

Change:
- Switched drag delta computation away from local `translation` to stable global positions.

Result:
- No visible change.

Conclusion:
- Divider delta self-cancellation was not the whole problem.

### 6. Widened the SwiftUI divider hit target

Files:
- `Tesara/Terminal/PaneDividerView.swift`
- `Tesara/Terminal/PaneContainerView.swift`

Changes:
- Expanded hit area from a thin visible line to a wider invisible drag region
- Raised divider above pane content using `zIndex`

Result:
- User reported it still felt almost pixel perfect.

Conclusion:
- SwiftUI hit testing still appears unreliable over the hosted AppKit views.

### 7. Added logging for split ratio, pane size, and Ghostty resize acceptance

Files:
- `Tesara/Terminal/WorkspaceManager.swift`
- `Tesara/Terminal/PaneContainerView.swift`
- `Tesara/Ghostty/GhosttySurfaceView.swift`

Log categories:
- `SplitDrag`
- `TerminalPane`
- `EditorPane`
- `GhosttyResize`
- `DividerDrag`

Result:
- `GhosttyResize` consistently showed `actualPx == requestPx`
- During user repros, there were no `SplitDrag` lines
- During user repros, there were no `DividerDrag` lines
- Logged pane resizes looked like normal window/pane size changes, not confirmed divider interaction updates

Conclusion:
- Ghostty is accepting the exact size it is asked to render
- The split drag callback path is likely not firing during repro
- The issue is upstream of Ghostty and upstream of pane-ratio storage

### 8. Began switching divider drag ownership to an AppKit overlay

Files:
- `Tesara/Terminal/PaneDividerView.swift`
- `Tesara/Terminal/PaneContainerView.swift`

Change:
- Replaced the SwiftUI drag-gesture approach with an `NSViewRepresentable` overlay intended to capture mouse drag events above both panes

Status:
- This work currently compiles
- User has not yet confirmed whether this version changes behavior

Rationale:
- The evidence strongly suggests SwiftUI gesture hit testing is losing to the hosted AppKit pane views

## What The Logs Proved

### Proven

- `ghostty_surface_set_size` is not clamping the size in embedded Ghostty.
- `GhosttyResize` logs show `requestPx == actualPx`.
- Vendor Ghostty embedded runtime forwards `ghostty_surface_set_size` directly to `Surface.updateSize`.
- Ghostty minimum-window constants (`min_window_width_cells`, `min_window_height_cells`) are used for initial or window-level limits, not confirmed split-pane limits in Tesara's embedded path.

### Not Proven

- We do not yet have a clean log showing divider drag events flowing through:
  - `DividerDrag`
  - `SplitDrag`
  - pane resize updates from the same interaction

Without that sequence, the exact break point in the interaction path is still unproven.

## Current Working Theory

The split divider interaction is being lost before it updates the pane tree.

Most likely causes:

1. The divider is not reliably winning hit testing against `NSViewRepresentable` content.
2. The drag interaction needs to live in AppKit, not pure SwiftUI.
3. The draggable region may still be visually aligned with the divider but not event-aligned in the real view hierarchy.

Less likely at this point:

1. Ratio clamp bug
2. Ghostty internal minimum grid size
3. AppKit intrinsic content size on the hosted pane views

## Unrelated Issues Seen In Xcode

These showed up in Issue Navigator during the investigation but do not appear to be directly related to the split-width bug:

- Concurrency diagnostics in `Tesara/Editor/EditorLayoutEngine.swift`
- Concurrency / sendability diagnostics in `Tesara/Ghostty/GhosttyApp.swift`

These should be treated as separate cleanup work unless new evidence connects them to split behavior.

## Recommended Next Steps

### Immediate next step

Test the AppKit divider overlay version and immediately inspect the local log for:

- `DividerDrag`
- `SplitDrag`
- `TerminalPane`
- `GhosttyResize`

Goal:
- Confirm whether the AppKit overlay receives drag events at all.

### If `DividerDrag` appears but `SplitDrag` does not

Investigate the closure routing between:

- `PaneDividerDragOverlay`
- `PaneContainerView`
- `WorkspaceManager.updatePaneRatio`

Focus on whether the closure is being called on the correct split node and active tab.

### If `DividerDrag` and `SplitDrag` both appear

Compare:

- requested ratio
- resulting pane widths in `PaneContainerView`
- leaf pane sizes

This would mean the interaction path is working and the floor would then likely be in layout application rather than hit testing.

### If `DividerDrag` still does not appear

Stop iterating on SwiftUI-based divider interaction and move fully to an AppKit-owned split drag layer.

Recommended implementation direction:

1. Put a dedicated `NSView` drag strip above the split branch.
2. Capture `mouseDown`, `mouseDragged`, and `mouseUp` entirely in AppKit.
3. Convert that directly into split ratio updates.
4. Keep SwiftUI responsible only for visual layout, not drag recognition.

## Useful Commands

Check recent investigation logs:

```sh
rg -n "\\[(DividerDrag|SplitDrag|TerminalPane|GhosttyResize|EditorPane)\\]" ~/Library/Logs/Tesara/Tesara.log | tail -n 200
```

Build the app:

```sh
xcodebuild -project Tesara.xcodeproj -scheme Tesara -destination 'platform=macOS' -derivedDataPath /tmp/tesara-derived build
```

## Files Modified During This Investigation

These files were touched during the current investigation and may contain experimental work:

- `Tesara/Terminal/PaneNode.swift`
- `Tesara/Ghostty/GhosttySurfaceRepresentable.swift`
- `Tesara/Editor/EditorViewRepresentable.swift`
- `Tesara/Terminal/PaneContainerView.swift`
- `Tesara/Terminal/PaneDividerView.swift`
- `Tesara/Ghostty/GhosttySurfaceView.swift`
- `Tesara/Editor/EditorView.swift`
- `Tesara/Terminal/WorkspaceManager.swift`

Another agent should review current diffs before continuing, especially the divider overlay work.
