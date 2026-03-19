#!/usr/bin/env bash
# config.sh — shared configuration for Tesara benchmark suite

set -euo pipefail

# ── Terminal names (order matters for iteration) ─────────────────────
TERMINAL_NAMES="Tesara Terminal iTerm2 Ghostty Alacritty Kitty Warp cmux"

# ── Terminal bundle ID lookup ────────────────────────────────────────
get_bundle_id() {
  case "$1" in
    Tesara)    echo "com.samsolomon.tesara" ;;
    Terminal)  echo "com.apple.Terminal" ;;
    iTerm2)    echo "com.googlecode.iterm2" ;;
    Ghostty)   echo "com.mitchellh.ghostty" ;;
    Alacritty) echo "org.alacritty" ;;
    Kitty)     echo "net.kovidgoyal.kitty" ;;
    Warp)      echo "dev.warp.Warp-Stable" ;;
    cmux)      echo "com.cmuxterm.app" ;;
    *)         echo "" ;;
  esac
}

# ── Iteration counts ────────────────────────────────────────────────
STARTUP_ITERATIONS=10
THROUGHPUT_ITERATIONS=10
LATENCY_KEYSTROKES=100
LATENCY_WARMUP=10
RESOURCE_IDLE_SAMPLES=10
RESOURCE_LOAD_DURATION=30
FPS_DURATION=10
CTRLC_ITERATIONS=10
SCALING_TAB_COUNTS="1 5 10 20"
SCROLLBACK_CHECKPOINTS="1000 10000 50000 100000 200000"

# ── Paths ────────────────────────────────────────────────────────────
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${BENCH_DIR}/results"
PAYLOAD_DIR="${BENCH_DIR}/throughput"
SENTINEL_PREFIX="/tmp/tesara-bench-sentinel"

# ── Terminals that don't support AppleScript keystroke injection ─────
MANUAL_ONLY_LATENCY="Alacritty Kitty Ghostty"

# Check if a terminal is in the manual-only list
is_manual_only() {
  local name="$1"
  echo "$MANUAL_ONLY_LATENCY" | tr ' ' '\n' | grep -qx "$name"
}
