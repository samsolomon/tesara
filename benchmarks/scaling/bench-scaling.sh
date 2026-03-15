#!/usr/bin/env bash
# bench-scaling.sh — measure memory scaling as tabs are opened
#
# Tesara-specific: opens 1/5/10/20 tabs and measures idle RSS at each level.
# Important because Tesara manages tabs natively while some competitors
# delegate to the window manager.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/terminals.sh"
source "${SCRIPT_DIR}/../lib/helpers.sh"

TARGETS=("${@:-$(detect_terminals)}")

# Open a new tab via Cmd+T (standard macOS shortcut)
open_new_tab() {
  osascript -e '
    tell application "System Events"
      keystroke "t" using command down
    end tell
  '
}

run_scaling_bench() {
  local name="$1"
  local bundle_id
  bundle_id=$(get_bundle_id "$name")

  echo "  Benchmarking scaling: ${name}"

  quit_terminal "$bundle_id"
  sleep 2
  launch_terminal "$bundle_id"
  sleep 3  # Let initial tab settle

  local pid
  pid=$(get_pid "$bundle_id" | head -1)
  if [[ -z "$pid" ]]; then
    echo "    Could not find PID for ${name}, skipping." >&2
    return
  fi

  local tab_counts=($SCALING_TAB_COUNTS)
  local results="{}"
  local current_tabs=1

  for count in "${tab_counts[@]}"; do
    # Open tabs until we reach the target count
    local to_open=$((count - current_tabs))
    if (( to_open > 0 )); then
      echo "    Opening ${to_open} tabs (total: ${count})..."
      for _ in $(seq 1 "$to_open"); do
        open_new_tab
        sleep 0.5
      done
      current_tabs=$count
      sleep 2  # Let tabs settle
    fi

    # Refresh PID in case process tree changed
    pid=$(get_pid "$bundle_id" | head -1)
    if [[ -z "$pid" ]]; then
      echo "    Lost PID for ${name} at ${count} tabs" >&2
      continue
    fi

    # Sample RSS 3 times and take the average
    local rss_sum=0
    local samples=3
    for s in $(seq 1 "$samples"); do
      local rss
      rss=$(get_tree_rss "$pid")
      rss_sum=$((rss_sum + rss))
      sleep 1
    done
    local avg_rss=$((rss_sum / samples))
    local avg_mb
    avg_mb=$(python3 -c "print(round(${avg_rss} / 1024, 1))")

    echo "    ${count} tabs: ${avg_mb} MB"

    results=$(echo "$results" | jq \
      --argjson tabs "$count" \
      --argjson rss_kb "$avg_rss" \
      '. + {("\($tabs)_tabs"): {tabs: $tabs, rss_kb: $rss_kb}}')
  done

  quit_terminal "$bundle_id"

  local outfile="${RESULTS_DIR}/scaling-${name}.json"
  jq -n \
    --arg terminal "$name" \
    --arg bundle_id "$bundle_id" \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson scaling "$results" \
    '{
      terminal: $terminal,
      bundle_id: $bundle_id,
      date: $date,
      benchmark: "scaling",
      unit: "rss_kb",
      scaling: $scaling
    }' > "$outfile"

  echo "  Results saved to ${outfile}"
}

mkdir -p "$RESULTS_DIR"

echo "==> Tab Scaling Benchmark"
for target in "${TARGETS[@]}"; do
  target=$(echo "$target" | tr -d '[:space:]')
  if [[ -n "$(get_bundle_id "$target")" ]]; then
    run_scaling_bench "$target"
  else
    echo "  Unknown terminal: ${target}" >&2
  fi
done
