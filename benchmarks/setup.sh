#!/usr/bin/env bash
# setup.sh — install benchmark dependencies

set -euo pipefail

echo "==> Installing benchmark dependencies..."

if ! command -v brew &>/dev/null; then
  echo "Error: Homebrew is required. Install from https://brew.sh" >&2
  exit 1
fi

brew install hyperfine jq

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Compile the latency probe
PROBE_SRC="${SCRIPT_DIR}/latency/latency-probe.swift"
PROBE_BIN="${SCRIPT_DIR}/latency/latency-probe"

if [[ -f "$PROBE_SRC" ]]; then
  echo "==> Compiling latency-probe.swift..."
  swiftc -O -o "$PROBE_BIN" "$PROBE_SRC" -framework Cocoa -framework ApplicationServices
  echo "    Built: ${PROBE_BIN}"
fi

# Clone and build doom-fire-zig for FPS benchmarks
VENDOR_DIR="${SCRIPT_DIR}/vendor"
DOOM_DIR="${VENDOR_DIR}/doom-fire-zig"

if [[ ! -d "$DOOM_DIR" ]]; then
  echo "==> Cloning doom-fire-zig..."
  mkdir -p "$VENDOR_DIR"
  git clone https://github.com/const-void/DOOM-fire-zig.git "$DOOM_DIR"
fi

if command -v zig &>/dev/null; then
  if [[ ! -x "${DOOM_DIR}/zig-out/bin/doom-fire-zig" ]]; then
    echo "==> Building doom-fire-zig..."
    (cd "$DOOM_DIR" && zig build -Doptimize=ReleaseFast)
    echo "    Built: ${DOOM_DIR}/zig-out/bin/doom-fire-zig"
  else
    echo "  doom-fire-zig already built, skipping."
  fi
else
  echo "  Warning: zig not found — doom-fire-zig (FPS benchmark) will be skipped." >&2
  echo "  Install with: brew install zig" >&2
fi

echo "==> Setup complete."
