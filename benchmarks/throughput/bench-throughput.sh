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

PAYLOAD_NAMES="ascii seq unicode ansi"

get_payload_file() {
  case "$1" in
    ascii)   echo ".payload-ascii" ;;
    seq)     echo ".payload-seq" ;;
    unicode) echo ".payload-unicode" ;;
    ansi)    echo ".payload-ansi" ;;
  esac
}

# Generate payloads if missing
bash "${SCRIPT_DIR}/generate-payloads.sh"

run_throughput_bench() {
  local name="$1"
  local bundle_id
  bundle_id=$(get_bundle_id "$name")
  local all_results="{}"

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

      # Inject timed cat command — records elapsed time to sentinel
      local cmd="T0=\$(python3 -c 'import time;print(time.time())'); cat ${payload_file} > /dev/null; T1=\$(python3 -c 'import time;print(time.time())'); python3 -c \"print(\$T1 - \$T0)\" > ${sentinel}"
      send_command "$cmd"

      # Poll for sentinel
      local timeout=120
      local elapsed=0
      while [[ ! -f "$sentinel" ]] && (( elapsed < timeout )); do
        sleep 0.1
        elapsed=$((elapsed + 1))
      done

      if [[ -f "$sentinel" ]]; then
        local duration
        duration=$(cat "$sentinel" | tr -d '[:space:]')
        if [[ -n "$duration" && "$duration" != "0" ]]; then
          local bytes_per_sec
          bytes_per_sec=$(python3 -c "print(round(${payload_size} / ${duration}, 2))")
          results+=("$bytes_per_sec")
          printf "      Run %2d: %.2f sec (%.2f MB/s)\n" "$i" "$duration" "$(python3 -c "print(round(${bytes_per_sec}/1048576, 2))")"
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
