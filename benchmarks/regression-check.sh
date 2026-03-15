#!/usr/bin/env bash
# regression-check.sh — compare current run against baseline, exit non-zero on regressions
#
# Usage: bash regression-check.sh <baseline_dir> [current_dir] [threshold_pct]
#   baseline_dir:  path to baseline results
#   current_dir:   path to current results (default: results/)
#   threshold_pct: regression threshold percentage (default: 5)
#
# Exits 0 if no regressions, 1 if any metric regresses beyond threshold.
# Designed to be wired into CI as a pre-merge gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

BASELINE_DIR="${1:?Usage: regression-check.sh <baseline_dir> [current_dir] [threshold_pct]}"
CURRENT_DIR="${2:-${RESULTS_DIR}}"
THRESHOLD="${3:-5}"

if [[ ! -d "$BASELINE_DIR" ]]; then
  echo "Error: baseline directory not found: ${BASELINE_DIR}" >&2
  exit 1
fi

if [[ ! -d "$CURRENT_DIR" ]]; then
  echo "Error: current directory not found: ${CURRENT_DIR}" >&2
  exit 1
fi

REGRESSIONS=0

# Check a metric: name, baseline, current, lower_is_better
check() {
  local label="$1"
  local baseline="$2"
  local current="$3"
  local lower_is_better="${4:-1}"

  if [[ "$baseline" == "null" || "$current" == "null" || -z "$baseline" || -z "$current" ]]; then
    return
  fi

  local result
  result=$(awk -v b="$baseline" -v c="$current" -v lib="$lower_is_better" -v thr="$THRESHOLD" 'BEGIN{
    if(b==0) { print "0 N/A"; exit }
    pct = (c - b) / b * 100
    if(lib) regressed = (c > b * (1 + thr / 100))
    else regressed = (c < b * (1 - thr / 100))
    printf "%d %.1f%%\n", regressed, pct
  }')

  local regressed pct
  regressed=$(echo "$result" | awk '{print $1}')
  pct=$(echo "$result" | awk '{print $2}')

  if (( regressed )); then
    echo "REGRESSION: ${label}: ${baseline} → ${current} (${pct}, threshold: ${THRESHOLD}%)"
    REGRESSIONS=$((REGRESSIONS + 1))
  fi
}

echo "Checking for regressions (threshold: ${THRESHOLD}%)..."
echo "  Baseline: ${BASELINE_DIR}"
echo "  Current:  ${CURRENT_DIR}"
echo ""

# ── Startup ──────────────────────────────────────────────────────────
for f in "${CURRENT_DIR}"/startup-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  baseline_f="${BASELINE_DIR}/startup-${name}.json"
  [[ -f "$baseline_f" ]] || continue
  check "startup/${name}/mean" "$(jq -r '.stats.mean' "$baseline_f")" "$(jq -r '.stats.mean' "$f")" 1
done

# ── Throughput ───────────────────────────────────────────────────────
for f in "${CURRENT_DIR}"/throughput-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  baseline_f="${BASELINE_DIR}/throughput-${name}.json"
  [[ -f "$baseline_f" ]] || continue
  for payload in ascii seq unicode ansi ligature zwj; do
    b=$(jq -r "if .payloads.${payload} then .payloads.${payload}.stats.mean else \"null\" end" "$baseline_f")
    c=$(jq -r "if .payloads.${payload} then .payloads.${payload}.stats.mean else \"null\" end" "$f")
    check "throughput/${name}/${payload}" "$b" "$c" 0
  done
done

# ── Resources ────────────────────────────────────────────────────────
for f in "${CURRENT_DIR}"/resources-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  baseline_f="${BASELINE_DIR}/resources-${name}.json"
  [[ -f "$baseline_f" ]] || continue
  check "resources/${name}/idle_rss" "$(jq -r '.idle.rss_kb.mean' "$baseline_f")" "$(jq -r '.idle.rss_kb.mean' "$f")" 1
  check "resources/${name}/peak_rss" "$(jq -r '.load.peak_rss_kb' "$baseline_f")" "$(jq -r '.load.peak_rss_kb' "$f")" 1
done

# ── Latency ──────────────────────────────────────────────────────────
for f in "${CURRENT_DIR}"/latency-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  baseline_f="${BASELINE_DIR}/latency-${name}.json"
  [[ -f "$baseline_f" ]] || continue
  check "latency/${name}/mean" "$(jq -r '.stats.mean' "$baseline_f")" "$(jq -r '.stats.mean' "$f")" 1
  check "latency/${name}/p95" "$(jq -r '.stats.p95' "$baseline_f")" "$(jq -r '.stats.p95' "$f")" 1
done

# ── Ctrl-C ───────────────────────────────────────────────────────────
for f in "${CURRENT_DIR}"/ctrlc-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  baseline_f="${BASELINE_DIR}/ctrlc-${name}.json"
  [[ -f "$baseline_f" ]] || continue
  check "ctrlc/${name}/mean" "$(jq -r '.stats.mean' "$baseline_f")" "$(jq -r '.stats.mean' "$f")" 1
done

# ── FPS ──────────────────────────────────────────────────────────────
for f in "${CURRENT_DIR}"/fps-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  baseline_f="${BASELINE_DIR}/fps-${name}.json"
  [[ -f "$baseline_f" ]] || continue
  check "fps/${name}/avg" "$(jq -r '.avg_fps // "null"' "$baseline_f")" "$(jq -r '.avg_fps // "null"' "$f")" 0
done

echo ""
if (( REGRESSIONS > 0 )); then
  echo "FAIL: ${REGRESSIONS} regression(s) detected."
  exit 1
else
  echo "PASS: no regressions detected."
  exit 0
fi
