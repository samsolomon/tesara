#!/usr/bin/env bash
# bench-throughput.sh — measure terminal throughput with various payloads
#
# Injects a timed `cat` command via keystroke, reads elapsed time from sentinel.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/terminals.sh"
source "${SCRIPT_DIR}/../lib/helpers.sh"

TARGETS=("${@:-$(detect_terminals)}")

PAYLOAD_NAMES="ascii seq unicode ansi ligature zwj"

get_payload_file() {
  case "$1" in
    ascii)    echo ".payload-ascii" ;;
    seq)      echo ".payload-seq" ;;
    unicode)  echo ".payload-unicode" ;;
    ansi)     echo ".payload-ansi" ;;
    ligature) echo ".payload-ligature" ;;
    zwj)      echo ".payload-zwj" ;;
  esac
}

# Generate payloads if missing
bash "${SCRIPT_DIR}/generate-payloads.sh"

run_throughput_bench() {
  local name="$1"
  local bundle_id
  bundle_id=$(get_bundle_id "$name")
  local all_results="{}"
  local grid_logged=false
  local grid_sentinel="${SENTINEL_PREFIX}-grid-$$"

  echo "  Benchmarking throughput: ${name}"

  for payload_name in $PAYLOAD_NAMES; do
    local payload_file="${PAYLOAD_DIR}/$(get_payload_file "$payload_name")"
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

      # Ensure fresh terminal
      quit_terminal "$bundle_id"
      sleep 2
      launch_terminal "$bundle_id"
      sleep 1

      # Normalize window size for consistent results across terminals
      local app_name
      app_name=$(app_name_from_bundle "$bundle_id" 2>/dev/null || echo "$name")
      osascript -e "
        tell application \"${app_name}\"
          set bounds of front window to {100, 100, 740, 580}
        end tell
      " 2>/dev/null || true
      sleep 0.5

      # Write a temp script — output must flow through the terminal to measure rendering
      # (no > /dev/null redirect; clear after to reset scrollback between runs)
      local bench_script="/tmp/tesara-bench-tp-$$.sh"
      cat > "$bench_script" << BENCHEOF
#!/bin/bash
stty rows 24 cols 80
[ ! -f ${grid_sentinel} ] && echo "\$(tput cols)x\$(tput lines)" > ${grid_sentinel}
T0=\$(perl -MTime::HiRes -e 'print Time::HiRes::time()')
cat ${payload_file}
T1=\$(perl -MTime::HiRes -e 'print Time::HiRes::time()')
perl -e "print \$T1 - \$T0" > ${sentinel}
clear
BENCHEOF
      chmod +x "$bench_script"
      send_command "bash ${bench_script}"

      # Poll for sentinel
      local timeout=120
      local elapsed=0
      while [[ ! -f "$sentinel" ]] && (( elapsed < timeout )); do
        sleep 0.1
        elapsed=$((elapsed + 1))
      done

      # Log grid size once per terminal (verification that stty normalization worked)
      if [[ "$grid_logged" == "false" && -f "$grid_sentinel" ]]; then
        echo "    Grid: $(cat "$grid_sentinel" | tr -d '[:space:]')"
        grid_logged=true
      fi

      if [[ -f "$sentinel" ]]; then
        local duration
        duration=$(cat "$sentinel" | tr -d '[:space:]')
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
      quit_terminal "$bundle_id"
      sleep 1
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

  rm -f "$grid_sentinel"

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
