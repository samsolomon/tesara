#!/usr/bin/env bash
# setup.sh — install benchmark dependencies

set -euo pipefail

echo "==> Installing benchmark dependencies..."

if ! command -v brew &>/dev/null; then
  echo "Error: Homebrew is required. Install from https://brew.sh" >&2
  exit 1
fi

brew install hyperfine jq

# Compile the latency probe
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_SRC="${SCRIPT_DIR}/latency/latency-probe.swift"
PROBE_BIN="${SCRIPT_DIR}/latency/latency-probe"

if [[ -f "$PROBE_SRC" ]]; then
  echo "==> Compiling latency-probe.swift..."
  swiftc -O -o "$PROBE_BIN" "$PROBE_SRC" -framework Cocoa -framework ApplicationServices
  echo "    Built: ${PROBE_BIN}"
fi

echo "==> Setup complete."
