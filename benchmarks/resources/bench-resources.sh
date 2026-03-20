#!/usr/bin/env bash
# bench-resources.sh — measure idle and under-load resource usage
#
# Metrics: RSS (KB), CPU%, sampled via ps. Sums across process tree for
# multi-process terminals (e.g., Tesara with WebKit helpers).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/terminals.sh"
source "${SCRIPT_DIR}/../lib/helpers.sh"

init_targets "$@"

run_resource_bench() {
  local name="$1"
  local bundle_id
  bundle_id=$(get_bundle_id "$name")

  echo "  Benchmarking resources: ${name}"

  # ── Idle measurement ──────────────────────────────────────────────
  quit_terminal "$bundle_id"
  sleep 2
  launch_terminal "$bundle_id"
  sleep 5  # Let it settle

  local pid
  pid=$(get_pid "$bundle_id" | head -1)
  if [[ -z "$pid" ]]; then
    echo "    Could not find PID for ${name}, skipping." >&2
    return
  fi

  local idle_rss=()
  local idle_cpu=()

  echo "    Sampling idle (${RESOURCE_IDLE_SAMPLES} samples)..."
  for i in $(seq 1 "$RESOURCE_IDLE_SAMPLES"); do
    local rss cpu
    read -r rss cpu <<< "$(get_tree_stats "$pid")"
    idle_rss+=("$rss")
    idle_cpu+=("$cpu")
    sleep 1
  done

  local idle_rss_stats
  idle_rss_stats=$(printf '%s\n' "${idle_rss[@]}" | compute_stats)
  local idle_cpu_stats
  idle_cpu_stats=$(printf '%s\n' "${idle_cpu[@]}" | compute_stats)

  # ── Under-load measurement ────────────────────────────────────────
  echo "    Sampling under load..."
  local load_rss=()
  local load_cpu=()
  local peak_rss=0

  # Start a heavy workload via keystroke
  send_command "seq 1 10000000"

  local samples=0
  local max_samples=$((RESOURCE_LOAD_DURATION * 2))  # sample every 500ms
  while (( samples < max_samples )); do
    local rss cpu
    read -r rss cpu <<< "$(get_tree_stats "$pid")"
    load_rss+=("$rss")
    load_cpu+=("$cpu")
    if (( rss > peak_rss )); then
      peak_rss=$rss
    fi
    sleep 0.5
    samples=$((samples + 1))
  done

  local load_rss_stats
  load_rss_stats=$(printf '%s\n' "${load_rss[@]}" | compute_stats)
  local load_cpu_stats
  load_cpu_stats=$(printf '%s\n' "${load_cpu[@]}" | compute_stats)

  # ── Memory growth check ───────────────────────────────────────────
  echo "    Checking memory growth..."
  local growth_rss=()

  # Generate a payload if we have one
  local payload="${PAYLOAD_DIR}/.payload-ascii"
  if [[ -f "$payload" ]]; then
    for round in $(seq 1 10); do
      send_command "cat ${payload} > /dev/null"
      sleep 2
      local rss
      read -r rss _ <<< "$(get_tree_stats "$pid")"
      growth_rss+=("$rss")
    done
  fi

  quit_terminal "$bundle_id"

  # ── Save results ──────────────────────────────────────────────────
  local outfile="${RESULTS_DIR}/resources-${name}.json"

  local growth_json="[]"
  if (( ${#growth_rss[@]} > 0 )); then
    growth_json=$(printf '%s\n' "${growth_rss[@]}" | jq -R 'tonumber' | jq -s '.')
  fi

  jq -n \
    --arg terminal "$name" \
    --arg bundle_id "$bundle_id" \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson idle_rss "$idle_rss_stats" \
    --argjson idle_cpu "$idle_cpu_stats" \
    --argjson load_rss "$load_rss_stats" \
    --argjson load_cpu "$load_cpu_stats" \
    --argjson peak_rss "$peak_rss" \
    --argjson growth "$growth_json" \
    '{
      terminal: $terminal,
      bundle_id: $bundle_id,
      date: $date,
      benchmark: "resources",
      idle: {rss_kb: $idle_rss, cpu_pct: $idle_cpu},
      load: {rss_kb: $load_rss, cpu_pct: $load_cpu, peak_rss_kb: $peak_rss},
      memory_growth: $growth
    }' > "$outfile"

  echo "  Results saved to ${outfile}"
}

mkdir -p "$RESULTS_DIR"

echo "==> Resource Benchmark"
for target in "${TARGETS[@]}"; do
  target=$(echo "$target" | tr -d '[:space:]')
  if [[ -n "$(get_bundle_id "$target")" ]]; then
    run_resource_bench "$target"
  else
    echo "  Unknown terminal: ${target}" >&2
  fi
done
