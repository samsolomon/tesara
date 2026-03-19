#!/usr/bin/env bash
# bench-throughput.sh — measure terminal rendering throughput with various payloads
#
# Injects a timed `cat` command, then uses a DSR/CPR handshake (ESC[6n) to
# wait until the terminal has actually rendered all output before stopping
# the timer. This measures true rendering throughput, not just PTY write speed.
#
# The terminal is launched once per target and reused across all payloads/runs
# to avoid startup noise and reduce total benchmark time.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/terminals.sh"
source "${SCRIPT_DIR}/../lib/helpers.sh"

TARGETS=("${@:-$(detect_terminals)}")

PAYLOAD_NAMES="ascii seq unicode ansi ligature zwj"

# Generate payloads if missing
bash "${SCRIPT_DIR}/generate-payloads.sh"

run_throughput_bench() {
  local name="$1"
  local bundle_id
  bundle_id=$(get_bundle_id "$name")
  local all_results="{}"
  local grid_logged=0
  local grid_sentinel="${SENTINEL_PREFIX}-grid-$$"
  local bench_script="/tmp/tesara-bench-tp-$$.sh"

  echo "  Benchmarking throughput: ${name}"

  # Launch terminal once and normalize window size
  quit_terminal "$bundle_id"
  sleep 2
  launch_terminal "$bundle_id"
  sleep 1

  local app_name
  app_name=$(app_name_from_bundle "$bundle_id" 2>/dev/null || echo "$name")
  osascript -e "
    tell application \"${app_name}\"
      set bounds of front window to {100, 100, 740, 580}
    end tell
  " 2>/dev/null || true
  sleep 0.5

  for payload_name in $PAYLOAD_NAMES; do
    local payload_file="${PAYLOAD_DIR}/.payload-${payload_name}"
    if [[ ! -f "$payload_file" ]]; then
      echo "    Skipping ${payload_name}: payload not found" >&2
      continue
    fi

    local payload_size
    payload_size=$(wc -c < "$payload_file" | tr -d ' ')
    local results=()

    echo "    Payload: ${payload_name} (${payload_size} bytes, ${THROUGHPUT_ITERATIONS} runs)"

    for i in $(seq 1 "$THROUGHPUT_ITERATIONS"); do
      local sentinel="${SENTINEL_PREFIX}-tp-$$-${i}"
      rm -f "$sentinel"

      # Write bench script that measures rendering time via DSR/CPR handshake.
      # After `cat` flushes the payload to the PTY, ESC[6n requests a Cursor
      # Position Report. The terminal can only respond after rendering all
      # preceding bytes. We read the CPR response (ends with 'R') to sync.
      cat > "$bench_script" << BENCHEOF
#!/bin/bash
stty rows 24 cols 80
[ ! -f ${grid_sentinel} ] && echo "\$(tput cols)x\$(tput lines)" > ${grid_sentinel}
T0=\$(perl -MTime::HiRes -e 'print Time::HiRes::time()')
cat ${payload_file}
printf '\033[6n'
read -d R -t 30 _cpr 2>/dev/null || true
T1=\$(perl -MTime::HiRes -e 'print Time::HiRes::time()')
perl -e "print \$T1 - \$T0" > ${sentinel}
clear
BENCHEOF
      chmod +x "$bench_script"
      send_command "bash ${bench_script}"

      # Poll for sentinel
      local max_polls=$(( 120 * 10 ))
      local elapsed=0
      while [[ ! -f "$sentinel" ]] && (( elapsed < max_polls )); do
        sleep 0.1
        elapsed=$((elapsed + 1))
      done

      # Log grid size once per terminal (verify stty normalization worked)
      if (( ! grid_logged )) && [[ -f "$grid_sentinel" ]]; then
        echo "    Grid: $(tr -d '[:space:]' < "$grid_sentinel")"
        grid_logged=1
      fi

      if [[ -f "$sentinel" ]]; then
        local duration
        duration=$(tr -d '[:space:]' < "$sentinel")
        if [[ -n "$duration" && "$duration" != "0" ]]; then
          local bytes_per_sec
          bytes_per_sec=$(perl -e "printf '%.2f', ${payload_size} / ${duration}")
          results+=("$bytes_per_sec")
          printf "      Run %2d: %.2f sec (%.2f MB/s)\n" "$i" "$duration" "$(perl -e "printf '%.2f', ${bytes_per_sec}/1048576")"
        fi
      else
        echo "      Run ${i}: TIMEOUT" >&2
      fi

      rm -f "$sentinel"
      sleep 0.5
    done

    if (( ${#results[@]} > 0 )); then
      local stats
      stats=$(printf '%s\n' "${results[@]}" | compute_stats)
      all_results=$(echo "$all_results" | jq \
        --arg key "$payload_name" \
        --argjson stats "$stats" \
        --argjson size "$payload_size" \
        --argjson raw "$(printf '%s\n' "${results[@]}" | jq -R 'tonumber' | jq -s '.')" \
        '. + {($key): {payload_bytes: $size, unit: "bytes/sec", stats: $stats, raw: $raw}}')
    fi
  done

  rm -f "$grid_sentinel" "$bench_script"

  # Quit terminal after all payloads complete
  quit_terminal "$bundle_id"

  local outfile="${RESULTS_DIR}/throughput-${name}.json"
  jq -n \
    --arg terminal "$name" \
    --arg bundle_id "$bundle_id" \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson payloads "$all_results" \
    '{terminal: $terminal, bundle_id: $bundle_id, date: $date, benchmark: "throughput", payloads: $payloads}' \
    > "$outfile"

  echo "  Results saved to ${outfile}"
}

mkdir -p "$RESULTS_DIR"

echo "==> Throughput Benchmark"
for target in "${TARGETS[@]}"; do
  target=$(echo "$target" | tr -d '[:space:]')
  if [[ -n "$(get_bundle_id "$target")" ]]; then
    run_throughput_bench "$target"
  else
    echo "  Unknown terminal: ${target}" >&2
  fi
done
