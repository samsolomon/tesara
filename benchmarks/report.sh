#!/usr/bin/env bash
# report.sh — generate markdown tables and CSV from benchmark JSON results

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

REPORT="${RESULTS_DIR}/report.md"
CSV="${RESULTS_DIR}/report.csv"

echo "Generating report..."

# ── Rating helper ────────────────────────────────────────────────────
# Usage: rate_metric <value> <excellent> <good> <acceptable>
# Prints: Excellent, Good, Acceptable, or Poor
rate_metric() {
  awk "BEGIN{v=$1; if(v<$2) print \"Excellent\"; else if(v<$3) print \"Good\"; else if(v<$4) print \"Acceptable\"; else print \"Poor\"}"
}

# ── Header ───────────────────────────────────────────────────────────
cat > "$REPORT" << 'HEADER'
# Tesara Terminal Benchmark Results

HEADER

# System info (prominent)
if [[ -f "${RESULTS_DIR}/system.json" ]]; then
  IFS=$'\t' read -r local_macos local_chip local_ram local_date < <(
    jq -r '[.macos, .chip, (.ram_gb|tostring), .date] | @tsv' "${RESULTS_DIR}/system.json"
  )

  # Get display refresh rate from system.json if available, else query once
  local_refresh=$(jq -r '.display_refresh // empty' "${RESULTS_DIR}/system.json" 2>/dev/null || true)
  if [[ -z "$local_refresh" ]]; then
    local_refresh=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -i 'refresh\|hertz\|hz' | head -1 | grep -oE '[0-9]+' | head -1 || echo "—")
  fi

  cat >> "$REPORT" << EOF
## System

| Property | Value |
|----------|-------|
| macOS | ${local_macos} |
| Chip | ${local_chip} |
| RAM | ${local_ram} GB |
| Display refresh | ${local_refresh} Hz |
| Date | ${local_date} |

EOF
fi

# Thresholds from competitive research:
#   Startup:  <500ms excellent, <1000ms good, <2000ms acceptable, >=2000ms poor
#   Latency:  <5ms excellent, <10ms good, <20ms acceptable, >=20ms poor
#   Ctrl-C:   <200ms excellent, <500ms good, <1000ms acceptable, >=1000ms poor
#   Memory:   <100MB excellent, <200MB good, <500MB acceptable, >=500MB poor

# ── Startup Table ────────────────────────────────────────────────────
startup_files=("${RESULTS_DIR}"/startup-*.json)
if [[ -f "${startup_files[0]}" ]]; then
  cat >> "$REPORT" << 'EOF'
## Startup time (ms)

Thresholds: <500 excellent | <1000 good | <2000 acceptable | >=2000 poor

| Terminal | Mean | Stddev | Min | Max | Median | Rating |
|----------|------|--------|-----|-----|--------|--------|
EOF

  for f in "${RESULTS_DIR}"/startup-*.json; do
    IFS=$'\t' read -r name mean stddev min max median < <(
      jq -r '[.terminal, (.stats.mean|tostring), (.stats.stddev|tostring), (.stats.min|tostring), (.stats.max|tostring), ((.stats.median // .stats.p50)|tostring)] | @tsv' "$f"
    )
    rating=$(rate_metric "$mean" 500 1000 2000)
    echo "| ${name} | ${mean} | ${stddev} | ${min} | ${max} | ${median} | ${rating} |" >> "$REPORT"
  done
  echo "" >> "$REPORT"
fi

# ── Throughput Table ─────────────────────────────────────────────────
throughput_files=("${RESULTS_DIR}"/throughput-*.json)
if [[ -f "${throughput_files[0]}" ]]; then
  cat >> "$REPORT" << 'EOF'
## Throughput (MB/s)

| Terminal | ASCII | Seq | Unicode | ANSI | Ligature | ZWJ |
|----------|-------|-----|---------|------|----------|-----|
EOF

  for f in "${RESULTS_DIR}"/throughput-*.json; do
    IFS=$'\t' read -r name ascii seq_val unicode ansi ligature zwj < <(
      jq -r '[
        .terminal,
        (if .payloads.ascii then (.payloads.ascii.stats.mean / 1048576 * 100 | round / 100 | tostring) else "—" end),
        (if .payloads.seq then (.payloads.seq.stats.mean / 1048576 * 100 | round / 100 | tostring) else "—" end),
        (if .payloads.unicode then (.payloads.unicode.stats.mean / 1048576 * 100 | round / 100 | tostring) else "—" end),
        (if .payloads.ansi then (.payloads.ansi.stats.mean / 1048576 * 100 | round / 100 | tostring) else "—" end),
        (if .payloads.ligature then (.payloads.ligature.stats.mean / 1048576 * 100 | round / 100 | tostring) else "—" end),
        (if .payloads.zwj then (.payloads.zwj.stats.mean / 1048576 * 100 | round / 100 | tostring) else "—" end)
      ] | @tsv' "$f"
    )
    echo "| ${name} | ${ascii} | ${seq_val} | ${unicode} | ${ansi} | ${ligature} | ${zwj} |" >> "$REPORT"
  done
  echo "" >> "$REPORT"
fi

# ── Resource Table ───────────────────────────────────────────────────
resource_files=("${RESULTS_DIR}"/resources-*.json)
if [[ -f "${resource_files[0]}" ]]; then
  cat >> "$REPORT" << 'EOF'
## Resource usage

Thresholds (idle RSS): <100 MB excellent | <200 MB good | <500 MB acceptable | >=500 MB poor

| Terminal | Idle RSS (MB) | Idle CPU (%) | Load RSS peak (MB) | Load CPU avg (%) | Rating |
|----------|---------------|--------------|--------------------|--------------------|--------|
EOF

  for f in "${RESULTS_DIR}"/resources-*.json; do
    IFS=$'\t' read -r name idle_rss idle_cpu load_peak load_cpu < <(
      jq -r '[.terminal, (.idle.rss_kb.mean / 1024 * 10 | round / 10 | tostring), (.idle.cpu_pct.mean|tostring), (.load.peak_rss_kb / 1024 * 10 | round / 10 | tostring), (.load.cpu_pct.mean|tostring)] | @tsv' "$f"
    )
    rating=$(rate_metric "$idle_rss" 100 200 500)
    echo "| ${name} | ${idle_rss} | ${idle_cpu} | ${load_peak} | ${load_cpu} | ${rating} |" >> "$REPORT"
  done
  echo "" >> "$REPORT"
fi

# ── Latency Table ────────────────────────────────────────────────────
latency_files=("${RESULTS_DIR}"/latency-*.json)
if [[ -f "${latency_files[0]}" ]]; then
  cat >> "$REPORT" << 'EOF'
## Input latency (ms)

Thresholds: <5 ms excellent | <10 ms good | <20 ms acceptable | >=20 ms poor

| Terminal | Mean | p50 | p95 | p99 | Stddev | Rating |
|----------|------|-----|-----|-----|--------|--------|
EOF

  for f in "${RESULTS_DIR}"/latency-*.json; do
    IFS=$'\t' read -r name mean p50 p95 p99 stddev < <(
      jq -r '[.terminal, (.stats.mean|tostring), (.stats.p50|tostring), (.stats.p95|tostring), (.stats.p99|tostring), (.stats.stddev|tostring)] | @tsv' "$f"
    )
    rating=$(rate_metric "$mean" 5 10 20)
    echo "| ${name} | ${mean} | ${p50} | ${p95} | ${p99} | ${stddev} | ${rating} |" >> "$REPORT"
  done
  echo "" >> "$REPORT"
fi

# ── FPS Table ────────────────────────────────────────────────────────
fps_files=("${RESULTS_DIR}"/fps-*.json)
if [[ -f "${fps_files[0]}" ]]; then
  cat >> "$REPORT" << 'EOF'
## FPS under load

| Terminal | Avg FPS | Duration (s) |
|----------|---------|--------------|
EOF

  for f in "${RESULTS_DIR}"/fps-*.json; do
    IFS=$'\t' read -r name avg_fps duration < <(
      jq -r '[.terminal, (.avg_fps // "—" | tostring), (.duration_sec|tostring)] | @tsv' "$f"
    )
    echo "| ${name} | ${avg_fps} | ${duration} |" >> "$REPORT"
  done
  echo "" >> "$REPORT"
fi

# ── Ctrl-C Table ─────────────────────────────────────────────────────
ctrlc_files=("${RESULTS_DIR}"/ctrlc-*.json)
if [[ -f "${ctrlc_files[0]}" ]]; then
  cat >> "$REPORT" << 'EOF'
## Ctrl-C responsiveness (ms)

Thresholds: <200 ms excellent | <500 ms good | <1000 ms acceptable | >=1000 ms poor

| Terminal | Mean | Stddev | Min | Max | Rating |
|----------|------|--------|-----|-----|--------|
EOF

  for f in "${RESULTS_DIR}"/ctrlc-*.json; do
    IFS=$'\t' read -r name mean stddev min max < <(
      jq -r '[.terminal, (.stats.mean|tostring), (.stats.stddev|tostring), (.stats.min|tostring), (.stats.max|tostring)] | @tsv' "$f"
    )
    rating=$(rate_metric "$mean" 200 500 1000)
    echo "| ${name} | ${mean} | ${stddev} | ${min} | ${max} | ${rating} |" >> "$REPORT"
  done
  echo "" >> "$REPORT"
fi

# ── Parser Table ─────────────────────────────────────────────────────
parser_files=("${RESULTS_DIR}"/parser-*.json)
if [[ -f "${parser_files[0]}" ]]; then
  cat >> "$REPORT" << 'EOF'
## Parser throughput (MB/s)

Via `kitten __benchmark__`

| Terminal | ASCII | Unicode | CSI |
|----------|-------|---------|-----|
EOF

  for f in "${RESULTS_DIR}"/parser-*.json; do
    IFS=$'\t' read -r name ascii unicode csi < <(
      jq -r '[.terminal, (.ascii // "—" | tostring), (.unicode // "—" | tostring), (.csi // "—" | tostring)] | @tsv' "$f"
    )
    echo "| ${name} | ${ascii} | ${unicode} | ${csi} |" >> "$REPORT"
  done
  echo "" >> "$REPORT"
fi

# ── Scaling Table ────────────────────────────────────────────────────
scaling_files=("${RESULTS_DIR}"/scaling-*.json)
if [[ -f "${scaling_files[0]}" ]]; then
  cat >> "$REPORT" << 'EOF'
## Tab scaling (RSS in MB)

| Terminal | 1 tab | 5 tabs | 10 tabs | 20 tabs |
|----------|-------|--------|---------|---------|
EOF

  for f in "${RESULTS_DIR}"/scaling-*.json; do
    IFS=$'\t' read -r name t1 t5 t10 t20 < <(
      jq -r '[
        .terminal,
        (if .scaling."1_tabs" then (.scaling."1_tabs".rss_kb / 1024 | round | tostring) else "—" end),
        (if .scaling."5_tabs" then (.scaling."5_tabs".rss_kb / 1024 | round | tostring) else "—" end),
        (if .scaling."10_tabs" then (.scaling."10_tabs".rss_kb / 1024 | round | tostring) else "—" end),
        (if .scaling."20_tabs" then (.scaling."20_tabs".rss_kb / 1024 | round | tostring) else "—" end)
      ] | @tsv' "$f"
    )
    echo "| ${name} | ${t1} | ${t5} | ${t10} | ${t20} |" >> "$REPORT"
  done
  echo "" >> "$REPORT"
fi

# ── Verdict Summary ─────────────────────────────────────────────────
cat >> "$REPORT" << 'EOF'
## Verdict

EOF

# Find winner for each category
find_winner() {
  local category="$1"
  local metric_path="$2"
  local lower_is_better="${3:-1}"

  local best_name=""; local best_val=""
  for f in "${RESULTS_DIR}"/${category}-*.json; do
    [[ -f "$f" ]] || continue
    local name val
    name=$(jq -r '.terminal' "$f")
    val=$(jq -r "${metric_path}" "$f")
    [[ "$val" == "null" || -z "$val" ]] && continue

    if [[ -z "$best_val" ]]; then
      best_name="$name"; best_val="$val"
    else
      local is_better
      if (( lower_is_better )); then
        is_better=$(awk "BEGIN{print ($val < $best_val) ? 1 : 0}")
      else
        is_better=$(awk "BEGIN{print ($val > $best_val) ? 1 : 0}")
      fi
      if (( is_better )); then
        best_name="$name"; best_val="$val"
      fi
    fi
  done

  if [[ -n "$best_name" ]]; then
    echo "$best_name"
  else
    echo "—"
  fi
}

startup_winner=$(find_winner "startup" ".stats.mean" 1)
throughput_winner=$(find_winner "throughput" ".payloads.ascii.stats.mean" 0)
idle_rss_winner=$(find_winner "resources" ".idle.rss_kb.mean" 1)
latency_winner=$(find_winner "latency" ".stats.mean" 1)
ctrlc_winner=$(find_winner "ctrlc" ".stats.mean" 1)

cat >> "$REPORT" << EOF
| Category | Winner |
|----------|--------|
| Startup | ${startup_winner} |
| Throughput (ASCII) | ${throughput_winner} |
| Idle memory | ${idle_rss_winner} |
| Input latency | ${latency_winner} |
| Ctrl-C responsiveness | ${ctrlc_winner} |

EOF

# ── CSV export ───────────────────────────────────────────────────────
echo "terminal,benchmark,metric,value" > "$CSV"

for f in "${RESULTS_DIR}"/startup-*.json; do
  [[ -f "$f" ]] || continue
  jq -r '[.terminal, "startup", "mean_ms", (.stats.mean|tostring)] | @csv' "$f" >> "$CSV"
done

for f in "${RESULTS_DIR}"/throughput-*.json; do
  [[ -f "$f" ]] || continue
  jq -r '
    .terminal as $t |
    .payloads | to_entries[] |
    [$t, "throughput_" + .key, "mean_bytes_per_sec", (.value.stats.mean|tostring)] | @csv
  ' "$f" >> "$CSV"
done

for f in "${RESULTS_DIR}"/resources-*.json; do
  [[ -f "$f" ]] || continue
  jq -r '[.terminal, "resources", "idle_rss_kb", (.idle.rss_kb.mean|tostring)] | @csv' "$f" >> "$CSV"
  jq -r '[.terminal, "resources", "peak_rss_kb", (.load.peak_rss_kb|tostring)] | @csv' "$f" >> "$CSV"
done

for f in "${RESULTS_DIR}"/latency-*.json; do
  [[ -f "$f" ]] || continue
  jq -r '[[.terminal, "latency", "mean_ms", (.stats.mean|tostring)], [.terminal, "latency", "p95_ms", (.stats.p95|tostring)]] | .[] | @csv' "$f" >> "$CSV"
done

for f in "${RESULTS_DIR}"/fps-*.json; do
  [[ -f "$f" ]] || continue
  jq -r 'select(.avg_fps != null) | [.terminal, "fps", "avg_fps", (.avg_fps|tostring)] | @csv' "$f" >> "$CSV"
done

for f in "${RESULTS_DIR}"/ctrlc-*.json; do
  [[ -f "$f" ]] || continue
  jq -r '[.terminal, "ctrlc", "mean_ms", (.stats.mean|tostring)] | @csv' "$f" >> "$CSV"
done

for f in "${RESULTS_DIR}"/parser-*.json; do
  [[ -f "$f" ]] || continue
  jq -r '
    .terminal as $t |
    [["ascii", .ascii], ["unicode", .unicode], ["csi", .csi]] |
    .[] | select(.[1] != null) |
    [$t, "parser_" + .[0], "mbps", (.[1]|tostring)] | @csv
  ' "$f" >> "$CSV"
done

for f in "${RESULTS_DIR}"/scaling-*.json; do
  [[ -f "$f" ]] || continue
  jq -r '
    .terminal as $t |
    .scaling | to_entries[] |
    [$t, "scaling", .key + "_rss_kb", (.value.rss_kb|tostring)] | @csv
  ' "$f" >> "$CSV"
done

echo "Report: ${REPORT}"
echo "CSV:    ${CSV}"
