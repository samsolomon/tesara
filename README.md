<img src="icon.svg" width="128" height="128" alt="Tesara">

# Tesara

Tesara is an experimental macOS terminal built around a simple goal: make the terminal feel native, calm, and fast.

It combines a SwiftUI/AppKit app shell with Ghostty's embedded `libghostty` renderer, plus early work on split panes, native editor surfaces, themes, and command history.

## What It Has Today

Tesara is still early, but the core app is already real:

- native macOS windowing and workspace UI
- terminal tabs and split panes
- embedded Ghostty-backed terminal rendering
- native editor panes
- themes, settings, and updater plumbing
- local command history persistence via GRDB

## Stack

- SwiftUI + AppKit
- Swift 5.10
- macOS 14+
- Zig-built `libghostty`
- GRDB
- Sparkle

## Run Locally

Requirements:

- Xcode
- Zig `0.15.2`
- the `vendor/ghostty` submodule

Then open `Tesara.xcodeproj` and run the `Tesara` scheme.

The build links against a local `libghostty.a` and applies `vendor/patches/ghostty-build.patch` before building the vendored Ghostty library.

## Repo Map

- `Tesara/` — app source
- `Tesara/Terminal/` — panes, tabs, workspace, sessions
- `Tesara/Ghostty/` — embedded Ghostty bridge
- `Tesara/Editor/` — native editor stack
- `Tesara/History/` — command capture and storage
- `Tesara/Settings/` — settings and local logging
- `TesaraTests/` — tests
- `vendor/` — vendored dependencies and patches

## Status

For more detailed progress notes, see `STATUS.md`.
