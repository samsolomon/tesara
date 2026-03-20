#!/usr/bin/env bash
# report-compare.sh — compare two result sets and show deltas
#
# Usage: bash report-compare.sh <baseline_dir> [current_dir]
#   baseline_dir: path to baseline results (e.g., results-baseline/)
#   current_dir:  path to current results (default: results/)
#
# Shows percentage change per metric and flags regressions (>5% slower).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

BASELINE_DIR="${1:?Usage: report-compare.sh <baseline_dir> [current_dir]}"
CURRENT_DIR="${2:-${RESULTS_DIR}}"

if [[ ! -d "$BASELINE_DIR" ]]; then
  echo "Error: baseline directory not found: ${BASELINE_DIR}" >&2
  exit 1
fi

if [[ ! -d "$CURRENT_DIR" ]]; then
  echo "Error: current directory not found: ${CURRENT_DIR}" >&2
  exit 1
fi

REPORT="${CURRENT_DIR}/comparison.md"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Compare a single metric: print delta and flag regressions
# Args: label, baseline_val, current_val, lower_is_better (1 or 0)
compare_metric() {
  local label="$1"
  local baseline="$2"
  local current="$3"
  local lower_is_better="${4:-1}"

  if [[ "$baseline" == "null" || "$current" == "null" || -z "$baseline" || -z "$current" ]]; then
    printf "  %-30s  %10s → %10s  (no comparison)\n" "$label" "${baseline:-—}" "${current:-—}"
    return
  fi

  # Single awk call for delta, pct, and status
  local result
  result=$(awk -v b="$baseline" -v c="$current" -v lib="$lower_is_better" 'BEGIN{
    if(b==0) { print "N/A none"; exit }
    pct = (c - b) / b * 100
    printf "%.1f%% ", pct
    if(lib) {
      if(c > b * 1.05) print "regression"
      else if(c < b * 0.95) print "improved"
      else print "none"
    } else {
      if(c < b * 0.95) print "regression"
      else if(c > b * 1.05) print "improved"
      else print "none"
    }
  }')

  local pct status flag=""
  pct=$(echo "$result" | awk '{print $1}')
  status=$(echo "$result" | awk '{print $2}')

  case "$status" in
    regression) flag="${RED}REGRESSION${NC}" ;;
    improved)   flag="${GREEN}IMPROVED${NC}" ;;
  esac

  printf "  %-30s  %10s → %10s  (%s) %b\n" "$label" "$baseline" "$current" "$pct" "$flag"
}

echo "============================================="
echo "  Benchmark Comparison"
echo "============================================="
echo "  Baseline: ${BASELINE_DIR}"
echo "  Current:  ${CURRENT_DIR}"
echo ""

# Also write markdown report
cat > "$REPORT" << EOF
# Benchmark comparison

**Baseline:** \`${BASELINE_DIR}\`
**Current:** \`${CURRENT_DIR}\`

EOF

# ── Startup comparison ───────────────────────────────────────────────
echo "--- Startup (ms, lower is better) ---"
echo "| Terminal | Baseline | Current | Delta | Status |" >> "$REPORT"
echo "|----------|----------|---------|-------|--------|" >> "$REPORT"

for f in "${CURRENT_DIR}"/startup-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  baseline_f="${BASELINE_DIR}/startup-${name}.json"
  [[ -f "$baseline_f" ]] || continue

  b_mean=$(jq -r '.stats.mean' "$baseline_f")
  c_mean=$(jq -r '.stats.mean' "$f")
  compare_metric "${name}" "$b_mean" "$c_mean" 1

  # Write to markdown report (reuse awk instead of spawning python3 again)
  pct=$(awk "BEGIN{if($b_mean==0) print \"N/A\"; else printf \"%.1f%%\", ($c_mean - $b_mean) / $b_mean * 100}")
  status=$(awk "BEGIN{print ($c_mean > $b_mean * 1.05) ? \"REGRESSION\" : \"OK\"}")
  echo "| ${name} | ${b_mean} | ${c_mean} | ${pct} | ${status} |" >> "$REPORT"
done
echo "" >> "$REPORT"
echo ""

# ── Throughput comparison ────────────────────────────────────────────
echo "--- Throughput (bytes/sec, higher is better) ---"
for f in "${CURRENT_DIR}"/throughput-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  baseline_f="${BASELINE_DIR}/throughput-${name}.json"
  [[ -f "$baseline_f" ]] || continue

  echo "  ${name}:"
  for payload in ascii seq unicode ansi ligature zwj; do
    b_val=$(jq -r "if .payloads.${payload} then .payloads.${payload}.stats.mean else \"null\" end" "$baseline_f")
    c_val=$(jq -r "if .payloads.${payload} then .payloads.${payload}.stats.mean else \"null\" end" "$f")
    compare_metric "    ${payload}" "$b_val" "$c_val" 0
  done
done
echo ""

# ── Wide Throughput comparison ─────────────────────────────────────
echo "--- Wide Throughput (bytes/sec, higher is better) ---"
for f in "${CURRENT_DIR}"/wide-throughput-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  baseline_f="${BASELINE_DIR}/wide-throughput-${name}.json"
  [[ -f "$baseline_f" ]] || continue

  echo "  ${name}:"
  for payload in ascii seq unicode ansi ligature zwj; do
    b_val=$(jq -r "if .payloads.${payload} then .payloads.${payload}.stats.mean else \"null\" end" "$baseline_f")
    c_val=$(jq -r "if .payloads.${payload} then .payloads.${payload}.stats.mean else \"null\" end" "$f")
    compare_metric "    ${payload}" "$b_val" "$c_val" 0
  done
done
echo ""

# ── Resources comparison ────────────────────────────────────────────
echo "--- Resources (lower is better) ---"
for f in "${CURRENT_DIR}"/resources-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  baseline_f="${BASELINE_DIR}/resources-${name}.json"
  [[ -f "$baseline_f" ]] || continue

  echo "  ${name}:"
  b_idle=$(jq -r '.idle.rss_kb.mean' "$baseline_f")
  c_idle=$(jq -r '.idle.rss_kb.mean' "$f")
  compare_metric "    Idle RSS (KB)" "$b_idle" "$c_idle" 1

  b_peak=$(jq -r '.load.peak_rss_kb' "$baseline_f")
  c_peak=$(jq -r '.load.peak_rss_kb' "$f")
  compare_metric "    Peak RSS (KB)" "$b_peak" "$c_peak" 1
done
echo ""

# ── Latency comparison ──────────────────────────────────────────────
echo "--- Latency (ms, lower is better) ---"
for f in "${CURRENT_DIR}"/latency-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  baseline_f="${BASELINE_DIR}/latency-${name}.json"
  [[ -f "$baseline_f" ]] || continue

  echo "  ${name}:"
  for metric in mean p50 p95 p99; do
    b_val=$(jq -r ".stats.${metric}" "$baseline_f")
    c_val=$(jq -r ".stats.${metric}" "$f")
    compare_metric "    ${metric}" "$b_val" "$c_val" 1
  done
done
echo ""

# ── Ctrl-C comparison ───────────────────────────────────────────────
echo "--- Ctrl-C (ms, lower is better) ---"
for f in "${CURRENT_DIR}"/ctrlc-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  baseline_f="${BASELINE_DIR}/ctrlc-${name}.json"
  [[ -f "$baseline_f" ]] || continue

  b_mean=$(jq -r '.stats.mean' "$baseline_f")
  c_mean=$(jq -r '.stats.mean' "$f")
  compare_metric "${name}" "$b_mean" "$c_mean" 1
done
echo ""

# ── Resize comparison ──────────────────────────────────────────────
echo "--- Resize latency (ms, lower is better) ---"
for f in "${CURRENT_DIR}"/resize-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  baseline_f="${BASELINE_DIR}/resize-${name}.json"
  [[ -f "$baseline_f" ]] || continue

  echo "  ${name}:"
  for transition in widen narrow; do
    b_val=$(jq -r "if .transitions.${transition} then .transitions.${transition}.stats.mean else \"null\" end" "$baseline_f")
    c_val=$(jq -r "if .transitions.${transition} then .transitions.${transition}.stats.mean else \"null\" end" "$f")
    compare_metric "    ${transition}" "$b_val" "$c_val" 1
  done
done
echo ""

echo "Comparison report: ${REPORT}"
