#!/usr/bin/env bash
# bench-resize.sh — measure terminal resize latency via SIGWINCH
#
# Measures time from osascript `set bounds` to when the terminal updates the
# PTY size (kernel delivers SIGWINCH to the shell). This is the core resize
# processing latency — the time the user waits before the terminal "knows"
# its new dimensions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/terminals.sh"
source "${SCRIPT_DIR}/../lib/helpers.sh"

init_targets "$@"

# Clean up sentinel files on exit (crash safety)
trap 'rm -f ${SENTINEL_PREFIX}-resize-ready-$$ ${SENTINEL_PREFIX}-resize-result-$$ ${SENTINEL_PREFIX}-resize-grid-$$ /tmp/tesara-bench-resize-$$.sh' EXIT

run_resize_bench() {
  local name="$1"
  local bundle_id
  bundle_id=$(get_bundle_id "$name")

  echo "  Benchmarking resize: ${name}"

  local narrow_right=$((RESIZE_NARROW_COLS * 8 + 160))
  local wide_right=$((RESIZE_WIDE_COLS * 8 + 160))

  # Inner measurement script: traps SIGWINCH and records timestamp.
  # Uses background sleep + wait so bash can interrupt on signal delivery.
  local bench_script="/tmp/tesara-bench-resize-$$.sh"
  cat > "$bench_script" << 'RESIZEOF'
#!/bin/bash
# Args: $1=ready_sentinel $2=result_sentinel
echo "READY" > "$1"
trap "perl -MTime::HiRes -e 'printf \"%.6f\", Time::HiRes::time()' > \"$2\"; kill %1 2>/dev/null; exit 0" WINCH
sleep 30 &
wait $!
RESIZEOF
  chmod +x "$bench_script"

  local ready_sentinel="${SENTINEL_PREFIX}-resize-ready-$$"
  local result_sentinel="${SENTINEL_PREFIX}-resize-result-$$"
  local grid_sentinel="${SENTINEL_PREFIX}-resize-grid-$$"

  # Launch terminal and set initial narrow bounds
  quit_terminal "$bundle_id"
  sleep 2
  launch_terminal "$bundle_id"
  sleep 1

  local app_name
  app_name=$(app_name_from_bundle "$bundle_id" 2>/dev/null || echo "$name")

  # Set narrow bounds and capture actual grid
  set_window_bounds "$app_name" 100 100 "$narrow_right" 580
  sleep 0.5

  rm -f "$grid_sentinel"
  send_command "echo \"\$(tput cols)x\$(tput lines)\" > ${grid_sentinel}"
  wait_for_sentinel "$grid_sentinel" 30 || true
  local actual_narrow="unknown"
  if [[ -f "$grid_sentinel" ]]; then
    actual_narrow=$(tr -d '[:space:]' < "$grid_sentinel")
  fi

  # Set wide bounds and capture actual grid
  set_window_bounds "$app_name" 100 100 "$wide_right" 580
  sleep 0.5

  rm -f "$grid_sentinel"
  send_command "echo \"\$(tput cols)x\$(tput lines)\" > ${grid_sentinel}"
  wait_for_sentinel "$grid_sentinel" 30 || true
  local actual_wide="unknown"
  if [[ -f "$grid_sentinel" ]]; then
    actual_wide=$(tr -d '[:space:]' < "$grid_sentinel")
  fi

  echo "    Narrow grid: ${actual_narrow} (target: ${RESIZE_NARROW_COLS}x24)"
  echo "    Wide grid:   ${actual_wide} (target: ${RESIZE_WIDE_COLS}x24)"

  local transitions='{}'

  # ── Run a set of resize iterations for one transition ──────────────
  run_transition() {
    local transition_name="$1"
    local from_right="$2"
    local to_right="$3"
    local from_label="$4"
    local to_label="$5"
    local actual_from_grid="$6"
    local actual_to_grid="$7"
    local results=()
    local total_runs=$((RESIZE_WARMUP + RESIZE_ITERATIONS))

    echo "    Transition: ${transition_name} (${from_label} → ${to_label})"

    for i in $(seq 1 "$total_runs"); do
      rm -f "$ready_sentinel" "$result_sentinel"

      # Set starting bounds
      set_window_bounds "$app_name" 100 100 "$from_right" 580
      sleep 0.5

      # Launch the SIGWINCH trap script inside the terminal
      send_command "bash ${bench_script} ${ready_sentinel} ${result_sentinel}"

      # Poll for ready sentinel (confirms trap is set)
      if ! wait_for_sentinel "$ready_sentinel"; then
        echo "      Run ${i}: TIMEOUT waiting for ready" >&2
        send_command "exit 2>/dev/null; true"
        sleep 0.5
        continue
      fi

      # Record T0
      local t0
      t0=$(perl -MTime::HiRes -e 'printf "%.6f", Time::HiRes::time()')

      # Trigger resize
      set_window_bounds "$app_name" 100 100 "$to_right" 580

      # Poll for result sentinel (contains T1)
      if wait_for_sentinel "$result_sentinel"; then
        local t1
        t1=$(tr -d '[:space:]' < "$result_sentinel")
        local delta_ms
        delta_ms=$(perl -e "printf '%.2f', ($t1 - $t0) * 1000")

        if (( i <= RESIZE_WARMUP )); then
          printf "      Warm-up %d: %s ms\n" "$i" "$delta_ms"
        else
          local run_num=$((i - RESIZE_WARMUP))
          results+=("$delta_ms")
          printf "      Run %2d: %s ms\n" "$run_num" "$delta_ms"
        fi
      else
        if (( i > RESIZE_WARMUP )); then
          echo "      Run $((i - RESIZE_WARMUP)): TIMEOUT waiting for SIGWINCH" >&2
        else
          echo "      Warm-up ${i}: TIMEOUT waiting for SIGWINCH" >&2
        fi
      fi

      rm -f "$ready_sentinel" "$result_sentinel"
      sleep 0.5
    done

    if (( ${#results[@]} > 0 )); then
      local stats
      stats=$(printf '%s\n' "${results[@]}" | compute_stats)
      transitions=$(echo "$transitions" | jq \
        --arg key "$transition_name" \
        --arg from "$from_label" \
        --arg to "$to_label" \
        --arg actual_from "$actual_from_grid" \
        --arg actual_to "$actual_to_grid" \
        --argjson stats "$stats" \
        --argjson raw "$(printf '%s\n' "${results[@]}" | jq -R 'tonumber' | jq -s '.')" \
        '. + {($key): {from: $from, to: $to, actual_from: $actual_from, actual_to: $actual_to, unit: "ms", stats: $stats, raw: $raw}}')
    fi
  }

  # ── Widen transition ─────────────────────────────────────────────
  run_transition "widen" "$narrow_right" "$wide_right" \
    "${RESIZE_NARROW_COLS}x24" "${RESIZE_WIDE_COLS}x24" "$actual_narrow" "$actual_wide"

  # Reset to wide bounds before narrow transition
  set_window_bounds "$app_name" 100 100 "$wide_right" 580
  sleep 0.5

  # ── Narrow transition ────────────────────────────────────────────
  run_transition "narrow" "$wide_right" "$narrow_right" \
    "${RESIZE_WIDE_COLS}x24" "${RESIZE_NARROW_COLS}x24" "$actual_wide" "$actual_narrow"

  # Quit terminal
  quit_terminal "$bundle_id"

  # Save results
  local outfile="${RESULTS_DIR}/resize-${name}.json"
  jq -n \
    --arg terminal "$name" \
    --arg bundle_id "$bundle_id" \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson transitions "$transitions" \
    '{terminal: $terminal, bundle_id: $bundle_id, date: $date, benchmark: "resize", transitions: $transitions}' \
    > "$outfile"

  echo "  Results saved to ${outfile}"

  rm -f "$bench_script" "$grid_sentinel"
}

mkdir -p "$RESULTS_DIR"

echo "==> Resize latency benchmark"
for target in "${TARGETS[@]}"; do
  target=$(echo "$target" | tr -d '[:space:]')
  if [[ -n "$(get_bundle_id "$target")" ]]; then
    run_resize_bench "$target"
  else
    echo "  Unknown terminal: ${target}" >&2
  fi
done
