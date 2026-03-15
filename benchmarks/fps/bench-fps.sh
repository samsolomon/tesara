#!/usr/bin/env bash
# bench-fps.sh — measure terminal FPS under load using DOOM-fire-zig
#
# Requires doom-fire-zig built in vendor/doom-fire-zig (see setup.sh).
# Runs the fire animation for FPS_DURATION seconds and parses average FPS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/terminals.sh"
source "${SCRIPT_DIR}/../lib/helpers.sh"

TARGETS=("${@:-$(detect_terminals)}")

DOOM_FIRE="${BENCH_DIR}/vendor/doom-fire-zig/zig-out/bin/doom-fire-zig"

if [[ ! -x "$DOOM_FIRE" ]]; then
  echo "Warning: doom-fire-zig not built. Run setup.sh first." >&2
  echo "  Expected at: ${DOOM_FIRE}" >&2
  echo "  Skipping FPS benchmark." >&2
  exit 0
fi

run_fps_bench() {
  local name="$1"
  local bundle_id
  bundle_id=$(get_bundle_id "$name")

  echo "  Benchmarking FPS: ${name} (${FPS_DURATION}s)"

  quit_terminal "$bundle_id"
  sleep 2
  launch_terminal "$bundle_id"
  sleep 2

  local sentinel="${SENTINEL_PREFIX}-fps-$$"
  local fps_log="/tmp/tesara-bench-fps-$$.log"
  rm -f "$sentinel" "$fps_log"

  # Run doom-fire-zig for FPS_DURATION seconds, capture output
  local bench_script="/tmp/tesara-bench-fps-$$.sh"
  cat > "$bench_script" << FPSEOF
#!/bin/bash
timeout ${FPS_DURATION} ${DOOM_FIRE} 2>"${fps_log}" || true
echo "DONE" > ${sentinel}
FPSEOF
  chmod +x "$bench_script"

  send_command "bash ${bench_script}"

  # Poll for completion
  local timeout_secs=$((FPS_DURATION + 10))
  local elapsed=0
  while [[ ! -f "$sentinel" ]] && (( elapsed < timeout_secs * 10 )); do
    sleep 0.1
    elapsed=$((elapsed + 1))
  done

  # Meanwhile, sample FPS by counting frame renders via process CPU usage
  # Many fire demos don't report FPS directly, so we'll also measure via
  # screen refresh observation if available

  local avg_fps="null"

  # Try to parse FPS from the log output
  if [[ -f "$fps_log" ]]; then
    # doom-fire-zig may print "FPS: <number>" or "avg: <number>"
    avg_fps=$(grep -oE '[0-9]+\.?[0-9]*\s*(fps|FPS)' "$fps_log" | tail -1 | grep -oE '[0-9]+\.?[0-9]*' || echo "null")
  fi

  # If no FPS in output, estimate from terminal refresh rate
  if [[ "$avg_fps" == "null" || -z "$avg_fps" ]]; then
    # Fallback: frame-counting approach using pure bash (no python3 per iteration)
    # Pre-generate random lines, then blast them as fast as the terminal can render
    local frame_script="/tmp/tesara-bench-frame-$$.sh"
    cat > "$frame_script" << FRAMEEOF
#!/bin/bash
DURATION=${FPS_DURATION}
# Pre-generate 20 random lines to avoid subprocess overhead per frame
LINES=()
for i in \$(seq 1 20); do
  LINES+=("\$(head -c 80 /dev/urandom | base64 | head -c 80)")
done
FRAMES=0
SECONDS=0
while (( SECONDS < DURATION )); do
  printf '\033[2J\033[H'
  printf "Frame %d\n" \$FRAMES
  for line in "\${LINES[@]}"; do
    printf '%s\n' "\$line"
  done
  FRAMES=\$((FRAMES + 1))
done
awk "BEGIN{printf \"%.1f\", \$FRAMES / \$SECONDS}"
FRAMEEOF
    chmod +x "$frame_script"

    local frame_sentinel="${SENTINEL_PREFIX}-frame-$$"
    rm -f "$frame_sentinel"

    local frame_bench="/tmp/tesara-bench-frame-run-$$.sh"
    cat > "$frame_bench" << FBEOF
#!/bin/bash
bash ${frame_script} > ${frame_sentinel}
FBEOF
    chmod +x "$frame_bench"
    send_command "bash ${frame_bench}"

    elapsed=0
    while [[ ! -f "$frame_sentinel" ]] && (( elapsed < (FPS_DURATION + 10) * 10 )); do
      sleep 0.1
      elapsed=$((elapsed + 1))
    done

    if [[ -f "$frame_sentinel" ]]; then
      avg_fps=$(cat "$frame_sentinel" | tr -d '[:space:]')
    fi

    rm -f "$frame_script" "$frame_bench" "$frame_sentinel"
  fi

  quit_terminal "$bundle_id"

  # Save results
  local outfile="${RESULTS_DIR}/fps-${name}.json"
  jq -n \
    --arg terminal "$name" \
    --arg bundle_id "$bundle_id" \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson duration "$FPS_DURATION" \
    --argjson avg_fps "${avg_fps:-null}" \
    '{
      terminal: $terminal,
      bundle_id: $bundle_id,
      date: $date,
      benchmark: "fps",
      duration_sec: $duration,
      avg_fps: $avg_fps
    }' > "$outfile"

  if [[ "$avg_fps" != "null" && -n "$avg_fps" ]]; then
    echo "    Average FPS: ${avg_fps}"
  else
    echo "    FPS: could not determine"
  fi
  echo "  Results saved to ${outfile}"

  rm -f "$sentinel" "$fps_log" "$bench_script"
}

mkdir -p "$RESULTS_DIR"

echo "==> FPS Benchmark"
for target in "${TARGETS[@]}"; do
  target=$(echo "$target" | tr -d '[:space:]')
  if [[ -n "$(get_bundle_id "$target")" ]]; then
    run_fps_bench "$target"
  else
    echo "  Unknown terminal: ${target}" >&2
  fi
done
