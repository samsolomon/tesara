#!/usr/bin/env bash
# bench-latency.sh — keystroke-to-screen latency measurement
#
# Uses latency-probe (compiled Swift CLI) to post CGEvents and poll
# AXUIElement for the character appearing on screen.
#
# NOTE: AX-based measurement only works for terminals that expose text
# content via the Accessibility API (AXValue on text elements).
# This includes Tesara, Apple Terminal, and iTerm2.
# GPU-rendered terminals (Ghostty, Alacritty, Kitty) render to Metal/OpenGL
# surfaces without AX text — these are skipped (see MANUAL_ONLY_LATENCY).
# For those, use an external tool like Typometer or Is It Snappy.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/terminals.sh"
source "${SCRIPT_DIR}/../lib/helpers.sh"

PROBE="${SCRIPT_DIR}/latency-probe"
TARGETS=("${@:-$(detect_terminals)}")

if [[ ! -x "$PROBE" ]]; then
  echo "Error: latency-probe not compiled. Run setup.sh first." >&2
  echo "  swiftc -O -o ${PROBE} ${SCRIPT_DIR}/latency-probe.swift -framework Cocoa -framework ApplicationServices" >&2
  exit 1
fi

# Check Accessibility permissions
if ! osascript -e 'tell application "System Events" to get name of first process' &>/dev/null; then
  echo "Warning: Accessibility permission may be required." >&2
  echo "  Grant access in System Settings > Privacy & Security > Accessibility" >&2
fi

run_latency_bench() {
  local name="$1"
  local bundle_id
  bundle_id=$(get_bundle_id "$name")

  # Check if this terminal is manual-only
  if is_manual_only "$name"; then
    echo "    Skipping ${name}: marked manual-only for latency tests"
    return
  fi

  echo "  Benchmarking latency: ${name} (${LATENCY_KEYSTROKES} keystrokes, ${LATENCY_WARMUP} warmup)"

  quit_terminal "$bundle_id"
  sleep 2
  launch_terminal "$bundle_id"
  sleep 2

  local pid
  pid=$(get_pid "$bundle_id" | head -1)
  if [[ -z "$pid" ]]; then
    echo "    Could not find PID for ${name}, skipping." >&2
    return
  fi

  local outfile="${RESULTS_DIR}/latency-${name}.json"

  # Run the probe (may fail if terminal doesn't expose AX text)
  if "$PROBE" \
    --pid "$pid" \
    --keystrokes "$LATENCY_KEYSTROKES" \
    --warmup "$LATENCY_WARMUP" \
    --output "$outfile" \
    --terminal "$name" \
    --bundle-id "$bundle_id"; then

    if [[ -f "$outfile" ]]; then
      echo "  Results saved to ${outfile}"
    fi
  else
    echo "  Warning: latency probe failed for ${name} (AX text may not be exposed)" >&2
  fi

  quit_terminal "$bundle_id"
}

mkdir -p "$RESULTS_DIR"

echo "==> Latency Benchmark"
for target in "${TARGETS[@]}"; do
  target=$(echo "$target" | tr -d '[:space:]')
  if [[ -n "$(get_bundle_id "$target")" ]]; then
    run_latency_bench "$target"
  else
    echo "  Unknown terminal: ${target}" >&2
  fi
done
