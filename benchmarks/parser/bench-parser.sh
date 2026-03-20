#!/usr/bin/env bash
# bench-parser.sh — standardized parser throughput using kitten __benchmark__
#
# If kitty's `kitten` CLI is available, runs the standardized cross-terminal
# parser benchmark that measures MB/s for ASCII, Unicode, and CSI sequences.
# Falls back gracefully if kitten is not installed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/terminals.sh"
source "${SCRIPT_DIR}/../lib/helpers.sh"

init_targets "$@"

# Check for kitten binary
KITTEN=""
if command -v kitten &>/dev/null; then
  KITTEN="kitten"
elif [[ -x "/Applications/kitty.app/Contents/MacOS/kitten" ]]; then
  KITTEN="/Applications/kitty.app/Contents/MacOS/kitten"
fi

if [[ -z "$KITTEN" ]]; then
  echo "Warning: kitten not found. Install kitty to run parser benchmarks." >&2
  echo "  brew install --cask kitty" >&2
  echo "  Skipping parser benchmark." >&2
  exit 0
fi

run_parser_bench() {
  local name="$1"
  local bundle_id
  bundle_id=$(get_bundle_id "$name")

  echo "  Benchmarking parser: ${name}"

  quit_terminal "$bundle_id"
  sleep 2
  launch_terminal "$bundle_id"
  sleep 2

  local sentinel="${SENTINEL_PREFIX}-parser-$$"
  local parser_log="/tmp/tesara-bench-parser-$$.log"
  rm -f "$sentinel" "$parser_log"

  # Run kitten __benchmark__ and capture output
  local bench_script="/tmp/tesara-bench-parser-$$.sh"
  cat > "$bench_script" << PARSEREOF
#!/bin/bash
${KITTEN} __benchmark__ 2>&1 | tee ${parser_log}
echo "DONE" > ${sentinel}
PARSEREOF
  chmod +x "$bench_script"
  send_command "bash ${bench_script}"

  # Poll for completion (benchmark takes ~30s)
  local timeout=60
  local elapsed=0
  while [[ ! -f "$sentinel" ]] && (( elapsed < timeout * 10 )); do
    sleep 0.1
    elapsed=$((elapsed + 1))
  done

  quit_terminal "$bundle_id"

  # Parse results from log
  local ascii_mbps="null"
  local unicode_mbps="null"
  local csi_mbps="null"

  if [[ -f "$parser_log" ]]; then
    # kitten __benchmark__ output format varies but typically shows MB/s per category
    # Try to extract numeric MB/s values from lines containing ASCII/Unicode/CSI
    ascii_mbps=$(grep -i 'ascii\|plain' "$parser_log" | grep -oE '[0-9]+\.?[0-9]*\s*MB/s' | head -1 | grep -oE '[0-9]+\.?[0-9]*' || echo "null")
    unicode_mbps=$(grep -i 'unicode\|utf' "$parser_log" | grep -oE '[0-9]+\.?[0-9]*\s*MB/s' | head -1 | grep -oE '[0-9]+\.?[0-9]*' || echo "null")
    csi_mbps=$(grep -i 'csi\|escape\|sgr' "$parser_log" | grep -oE '[0-9]+\.?[0-9]*\s*MB/s' | head -1 | grep -oE '[0-9]+\.?[0-9]*' || echo "null")

    [[ -z "$ascii_mbps" ]] && ascii_mbps="null"
    [[ -z "$unicode_mbps" ]] && unicode_mbps="null"
    [[ -z "$csi_mbps" ]] && csi_mbps="null"
  fi

  local outfile="${RESULTS_DIR}/parser-${name}.json"
  jq -n \
    --arg terminal "$name" \
    --arg bundle_id "$bundle_id" \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson ascii "$ascii_mbps" \
    --argjson unicode "$unicode_mbps" \
    --argjson csi "$csi_mbps" \
    '{
      terminal: $terminal,
      bundle_id: $bundle_id,
      date: $date,
      benchmark: "parser",
      unit: "MB/s",
      ascii: $ascii,
      unicode: $unicode,
      csi: $csi
    }' > "$outfile"

  echo "    ASCII: ${ascii_mbps} MB/s | Unicode: ${unicode_mbps} MB/s | CSI: ${csi_mbps} MB/s"
  echo "  Results saved to ${outfile}"

  rm -f "$sentinel" "$parser_log" "$bench_script"
}

mkdir -p "$RESULTS_DIR"

echo "==> Parser Benchmark (kitten __benchmark__)"
for target in "${TARGETS[@]}"; do
  target=$(echo "$target" | tr -d '[:space:]')
  if [[ -n "$(get_bundle_id "$target")" ]]; then
    run_parser_bench "$target"
  else
    echo "  Unknown terminal: ${target}" >&2
  fi
done
