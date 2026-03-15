#!/usr/bin/env bash
# run-all.sh — master benchmark runner
#
# Usage: bash benchmarks/run-all.sh [terminal1 terminal2 ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/terminals.sh"
source "${SCRIPT_DIR}/lib/helpers.sh"

# ── System metadata ─────────────────────────────────────────────────
echo "============================================="
echo "  Tesara Terminal Benchmark Suite"
echo "============================================="
echo ""

MACOS_VERSION=$(sw_vers -productVersion)
CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)
RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))

echo "System:"
echo "  macOS:  ${MACOS_VERSION}"
echo "  Chip:   ${CHIP}"
echo "  RAM:    ${RAM_GB} GB"
echo ""

# Save system metadata
mkdir -p "$RESULTS_DIR"
jq -n \
  --arg macos "$MACOS_VERSION" \
  --arg chip "$CHIP" \
  --argjson ram "$RAM_GB" \
  --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{macos: $macos, chip: $chip, ram_gb: $ram, date: $date}' \
  > "${RESULTS_DIR}/system.json"

# ── Detect terminals ────────────────────────────────────────────────
if (( $# > 0 )); then
  TARGETS=("$@")
else
  TARGETS=()
  while IFS= read -r line; do
    TARGETS+=("$line")
  done < <(detect_terminals)
fi

echo "Terminals to benchmark:"
for t in "${TARGETS[@]}"; do
  echo "  - ${t} ($(get_bundle_id "$t"))"
done
echo ""

if (( ${#TARGETS[@]} == 0 )); then
  echo "Error: no terminals detected." >&2
  exit 1
fi

# ── Run suites ──────────────────────────────────────────────────────
SUITES=(
  "startup/bench-startup.sh"
  "throughput/bench-throughput.sh"
  "resources/bench-resources.sh"
  "latency/bench-latency.sh"
  "fps/bench-fps.sh"
  "ctrlc/bench-ctrlc.sh"
  "parser/bench-parser.sh"
  "scaling/bench-scaling.sh"
  "scrollback/bench-scrollback.sh"
)

for suite in "${SUITES[@]}"; do
  local_path="${SCRIPT_DIR}/${suite}"
  suite_name=$(basename "$suite" .sh | sed 's/bench-//')

  echo "============================================="
  echo "  Running: ${suite_name}"
  echo "============================================="

  if [[ -f "$local_path" ]]; then
    bash "$local_path" "${TARGETS[@]}"
  else
    echo "  Warning: ${local_path} not found, skipping." >&2
  fi

  echo ""
done

# ── Generate report ─────────────────────────────────────────────────
echo "============================================="
echo "  Generating Report"
echo "============================================="
bash "${SCRIPT_DIR}/report.sh"

echo ""
echo "Done! Results in ${RESULTS_DIR}/"
