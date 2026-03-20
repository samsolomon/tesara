#!/usr/bin/env bash
# bench-startup.sh — cold-start timing using sentinel file approach
#
# Measures time from `open -b` until the shell is interactive by injecting
# a sentinel-writing command via System Events keystroke and polling for the file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/terminals.sh"
source "${SCRIPT_DIR}/../lib/helpers.sh"

# Which terminals to benchmark (default: all detected)
TARGETS=("${@:-$(detect_terminals)}")

run_startup_bench() {
  local name="$1"
  local bundle_id
  bundle_id=$(get_bundle_id "$name")
  local results=()

  echo "  Benchmarking startup: ${name} (${STARTUP_ITERATIONS} runs)"

  for i in $(seq 1 "$STARTUP_ITERATIONS"); do
    local sentinel="${SENTINEL_PREFIX}-startup-$$-${i}"
    rm -f "$sentinel"

    # Ensure the terminal is fully quit for a cold start
    quit_terminal "$bundle_id"
    sleep 2

    # Record start time and launch
    local t_start
    t_start=$(timestamp_ms)
    open -b "$bundle_id"

    # Wait for window, then inject sentinel command
    sleep 0.5
    local attempts=0
    while (( attempts < 30 )); do
      local wcount
      wcount=$(osascript -e "
        tell application \"System Events\"
          tell process \"$(app_name_from_bundle "$bundle_id")\"
            count of windows
          end tell
        end tell
      " 2>/dev/null || echo 0)
      if (( wcount > 0 )); then
        break
      fi
      sleep 0.2
      attempts=$((attempts + 1))
    done

    # Inject the sentinel command via keystroke
    send_command "echo READY > ${sentinel}"

    # Poll for sentinel file (timeout * 20 iterations at 0.05s each)
    local timeout=30
    local max_polls=$(( timeout * 20 ))
    local elapsed=0
    while [[ ! -f "$sentinel" ]] && (( elapsed < max_polls )); do
      sleep 0.05
      elapsed=$((elapsed + 1))
    done

    local t_end
    t_end=$(timestamp_ms)

    if [[ -f "$sentinel" ]]; then
      local duration=$(( t_end - t_start ))
      results+=("$duration")
      printf "    Run %2d: %d ms\n" "$i" "$duration"
    else
      echo "    Run ${i}: TIMEOUT (sentinel not created)" >&2
    fi

    rm -f "$sentinel"
    quit_terminal "$bundle_id"
    sleep 1
  done

  # Compute and save stats
  local stats
  stats=$(printf '%s\n' "${results[@]}" | compute_stats)

  local outfile="${RESULTS_DIR}/startup-${name}.json"
  jq -n \
    --arg terminal "$name" \
    --arg bundle_id "$bundle_id" \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson stats "$stats" \
    --argjson raw "$(printf '%s\n' "${results[@]}" | jq -R 'tonumber' | jq -s '.')" \
    '{terminal: $terminal, bundle_id: $bundle_id, date: $date, benchmark: "startup", unit: "ms", stats: $stats, raw: $raw}' \
    > "$outfile"

  echo "  Results saved to ${outfile}"
}

mkdir -p "$RESULTS_DIR"

echo "==> Startup Benchmark"
for target in "${TARGETS[@]}"; do
  target=$(echo "$target" | tr -d '[:space:]')
  if [[ -n "$(get_bundle_id "$target")" ]]; then
    run_startup_bench "$target"
  else
    echo "  Unknown terminal: ${target}" >&2
  fi
done
