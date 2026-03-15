#!/usr/bin/env bash
# bench-ctrlc.sh — measure Ctrl-C responsiveness
#
# Starts a heavy workload (seq 1 100000000), waits 2 seconds, sends Ctrl-C,
# and measures time until the next shell prompt appears (via sentinel).
# Anything >1s is considered a failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/terminals.sh"
source "${SCRIPT_DIR}/../lib/helpers.sh"

TARGETS=("${@:-$(detect_terminals)}")

run_ctrlc_bench() {
  local name="$1"
  local bundle_id
  bundle_id=$(get_bundle_id "$name")
  local results=()

  echo "  Benchmarking Ctrl-C: ${name} (${CTRLC_ITERATIONS} runs)"

  for i in $(seq 1 "$CTRLC_ITERATIONS"); do
    local sentinel="${SENTINEL_PREFIX}-ctrlc-$$-${i}"
    rm -f "$sentinel"

    # Fresh terminal each run
    quit_terminal "$bundle_id"
    sleep 2
    launch_terminal "$bundle_id"
    sleep 1

    # Start heavy workload
    send_command "seq 1 100000000"

    # Wait for workload to get going
    sleep 2

    # Record time and send Ctrl-C via AppleScript
    local t_start
    t_start=$(python3 -c 'import time;print(time.time())')

    osascript -e '
      tell application "System Events"
        keystroke "c" using control down
      end tell
    '

    # Now send a sentinel command — it will execute once the shell is back
    sleep 0.1
    send_command "python3 -c 'import time;print(time.time())' > ${sentinel}"

    # Poll for sentinel
    local timeout=10
    local elapsed=0
    while [[ ! -f "$sentinel" ]] && (( elapsed < timeout * 10 )); do
      sleep 0.1
      elapsed=$((elapsed + 1))
    done

    if [[ -f "$sentinel" ]]; then
      local t_end
      t_end=$(cat "$sentinel" | tr -d '[:space:]')
      local duration
      duration=$(python3 -c "print(round(($t_end - $t_start) * 1000, 1))")
      results+=("$duration")

      local status="OK"
      if python3 -c "exit(0 if $duration > 1000 else 1)" 2>/dev/null; then
        status="SLOW"
      fi
      printf "    Run %2d: %s ms [%s]\n" "$i" "$duration" "$status"
    else
      echo "    Run ${i}: TIMEOUT — shell did not return" >&2
      results+=("10000")  # record as 10s timeout
    fi

    rm -f "$sentinel"
    quit_terminal "$bundle_id"
    sleep 1
  done

  # Compute stats and save
  if (( ${#results[@]} > 0 )); then
    local stats
    stats=$(printf '%s\n' "${results[@]}" | compute_stats)

    local outfile="${RESULTS_DIR}/ctrlc-${name}.json"
    jq -n \
      --arg terminal "$name" \
      --arg bundle_id "$bundle_id" \
      --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson stats "$stats" \
      --argjson raw "$(printf '%s\n' "${results[@]}" | jq -R 'tonumber' | jq -s '.')" \
      '{
        terminal: $terminal,
        bundle_id: $bundle_id,
        date: $date,
        benchmark: "ctrlc",
        unit: "ms",
        stats: $stats,
        raw: $raw
      }' > "$outfile"

    echo "  Results saved to ${outfile}"
  fi
}

mkdir -p "$RESULTS_DIR"

echo "==> Ctrl-C Responsiveness Benchmark"
for target in "${TARGETS[@]}"; do
  target=$(echo "$target" | tr -d '[:space:]')
  if [[ -n "$(get_bundle_id "$target")" ]]; then
    run_ctrlc_bench "$target"
  else
    echo "  Unknown terminal: ${target}" >&2
  fi
done
