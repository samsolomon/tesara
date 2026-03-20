#!/usr/bin/env bash
# bench-scrollback.sh — measure memory growth as scrollback buffer fills
#
# Generates increasing volumes of output through the terminal and measures
# RSS at checkpoints. The terminal's own scrollback limit naturally caps
# retention, so at high line counts we measure the steady-state cost of
# a full buffer. The flattening at higher checkpoints reveals the real
# memory cost of scrollback.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/terminals.sh"
source "${SCRIPT_DIR}/../lib/helpers.sh"

TARGETS=("${@:-$(detect_terminals)}")

run_scrollback_bench() {
  local name="$1"
  local bundle_id
  bundle_id=$(get_bundle_id "$name")

  echo "  Benchmarking scrollback: ${name}"

  quit_terminal "$bundle_id"
  sleep 2
  launch_terminal "$bundle_id"
  sleep 3  # Let initial window settle

  local pid
  pid=$(get_pid "$bundle_id" | head -1)
  if [[ -z "$pid" ]]; then
    echo "    Could not find PID for ${name}, skipping." >&2
    return
  fi

  # ── Baseline RSS (before any output) ──────────────────────────────
  local baseline_sum=0
  local samples=3
  for s in $(seq 1 "$samples"); do
    local rss
    rss=$(get_tree_rss "$pid")
    baseline_sum=$((baseline_sum + rss))
    sleep 1
  done
  local baseline_rss=$((baseline_sum / samples))
  local baseline_mb
  baseline_mb=$(awk "BEGIN{printf \"%.1f\", ${baseline_rss} / 1024}")
  echo "    Baseline: ${baseline_mb} MB"

  # ── Checkpoints ───────────────────────────────────────────────────
  local checkpoints=($SCROLLBACK_CHECKPOINTS)
  local results="{}"
  local sentinel="${SENTINEL_PREFIX}-scrollback-$$"
  trap 'rm -f "${SENTINEL_PREFIX}-scrollback-$$"' EXIT INT TERM

  for lines in "${checkpoints[@]}"; do
    local label
    if (( lines >= 1000 )); then
      label="$((lines / 1000))k"
    else
      label="${lines}"
    fi

    echo "    Generating ${label} lines..."

    # Clean up any previous sentinel
    rm -f "$sentinel"

    # Send seq command through the terminal to generate output
    send_command "seq 1 ${lines} && echo done > ${sentinel}"

    # Wait for output to complete (poll for sentinel file)
    local timeout=120
    local elapsed=0
    while [[ ! -f "$sentinel" ]] && (( elapsed < timeout )); do
      sleep 1
      elapsed=$((elapsed + 1))
    done

    if [[ ! -f "$sentinel" ]]; then
      echo "    Warning: timed out waiting for ${label} lines to complete" >&2
      continue
    fi

    rm -f "$sentinel"
    sleep 2  # Let memory settle

    # Refresh PID in case process tree changed
    pid=$(get_pid "$bundle_id" | head -1)
    if [[ -z "$pid" ]]; then
      echo "    Lost PID for ${name} at ${label} lines" >&2
      continue
    fi

    # Sample RSS 3 times and average
    local rss_sum=0
    for s in $(seq 1 "$samples"); do
      local rss
      rss=$(get_tree_rss "$pid")
      rss_sum=$((rss_sum + rss))
      sleep 1
    done
    local avg_rss=$((rss_sum / samples))
    local avg_mb
    avg_mb=$(awk "BEGIN{printf \"%.1f\", ${avg_rss} / 1024}")

    echo "    ${label} lines: ${avg_mb} MB"

    results=$(echo "$results" | jq \
      --arg key "$label" \
      --argjson lines_generated "$lines" \
      --argjson rss_kb "$avg_rss" \
      '. + {($key): {lines_generated: $lines_generated, rss_kb: $rss_kb}}')
  done

  quit_terminal "$bundle_id"

  local outfile="${RESULTS_DIR}/scrollback-${name}.json"
  jq -n \
    --arg terminal "$name" \
    --arg bundle_id "$bundle_id" \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson baseline_rss_kb "$baseline_rss" \
    --argjson checkpoints "$results" \
    '{
      terminal: $terminal,
      bundle_id: $bundle_id,
      date: $date,
      benchmark: "scrollback",
      unit: "rss_kb",
      baseline_rss_kb: $baseline_rss_kb,
      checkpoints: $checkpoints,
      buffer_cost_kb: ([$checkpoints[].rss_kb] | max) - $baseline_rss_kb
    }' > "$outfile"

  echo "  Results saved to ${outfile}"
}

mkdir -p "$RESULTS_DIR"

echo "==> Scrollback Memory Benchmark"
for target in "${TARGETS[@]}"; do
  target=$(echo "$target" | tr -d '[:space:]')
  if [[ -n "$(get_bundle_id "$target")" ]]; then
    run_scrollback_bench "$target"
  else
    echo "  Unknown terminal: ${target}" >&2
  fi
done
