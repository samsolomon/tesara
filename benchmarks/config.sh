#!/usr/bin/env bash
# config.sh — shared configuration for Tesara benchmark suite

set -euo pipefail

# ── Terminal bundle IDs ──────────────────────────────────────────────
declare -A TERMINAL_BUNDLE_IDS=(
  [Tesara]="com.samsolomon.Tesara"
  [Terminal]="com.apple.Terminal"
  [iTerm2]="com.googlecode.iterm2"
  [Ghostty]="com.mitchellh.ghostty"
  [Alacritty]="org.alacritty"
  [Kitty]="net.kovidgoyal.kitty"
  [Warp]="dev.warp.Warp-Stable"
)

# ── Iteration counts ────────────────────────────────────────────────
STARTUP_ITERATIONS=10
THROUGHPUT_ITERATIONS=5
LATENCY_KEYSTROKES=100
LATENCY_WARMUP=10
RESOURCE_IDLE_SAMPLES=10
RESOURCE_LOAD_DURATION=30

# ── Paths ────────────────────────────────────────────────────────────
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${BENCH_DIR}/results"
PAYLOAD_DIR="${BENCH_DIR}/throughput"
SENTINEL_PREFIX="/tmp/tesara-bench-sentinel"

# ── Terminals that don't support AppleScript keystroke injection ─────
# These will be marked manual-only for latency tests
MANUAL_ONLY_LATENCY=(Alacritty Kitty)
