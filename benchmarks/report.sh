#!/usr/bin/env bash
# report.sh — generate markdown tables and CSV from benchmark JSON results

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

REPORT="${RESULTS_DIR}/report.md"
CSV="${RESULTS_DIR}/report.csv"

echo "Generating report..."

# ── Header ───────────────────────────────────────────────────────────
cat > "$REPORT" << 'HEADER'
# Tesara Terminal Benchmark Results

HEADER

# System info
if [[ -f "${RESULTS_DIR}/system.json" ]]; then
  local_macos=$(jq -r '.macos' "${RESULTS_DIR}/system.json")
  local_chip=$(jq -r '.chip' "${RESULTS_DIR}/system.json")
  local_ram=$(jq -r '.ram_gb' "${RESULTS_DIR}/system.json")
  local_date=$(jq -r '.date' "${RESULTS_DIR}/system.json")

  cat >> "$REPORT" << EOF
**System:** macOS ${local_macos} | ${local_chip} | ${local_ram} GB RAM
**Date:** ${local_date}

EOF
fi

# ── Startup Table ────────────────────────────────────────────────────
startup_files=("${RESULTS_DIR}"/startup-*.json)
if [[ -f "${startup_files[0]}" ]]; then
  cat >> "$REPORT" << 'EOF'
## Startup Time (ms)

| Terminal | Mean | Stddev | Min | Max | Median |
|----------|------|--------|-----|-----|--------|
EOF

  for f in "${RESULTS_DIR}"/startup-*.json; do
    name=$(jq -r '.terminal' "$f")
    mean=$(jq -r '.stats.mean' "$f")
    stddev=$(jq -r '.stats.stddev' "$f")
    min=$(jq -r '.stats.min' "$f")
    max=$(jq -r '.stats.max' "$f")
    median=$(jq -r '.stats.median // .stats.p50' "$f")
    echo "| ${name} | ${mean} | ${stddev} | ${min} | ${max} | ${median} |" >> "$REPORT"
  done
  echo "" >> "$REPORT"
fi

# ── Throughput Table ─────────────────────────────────────────────────
throughput_files=("${RESULTS_DIR}"/throughput-*.json)
if [[ -f "${throughput_files[0]}" ]]; then
  cat >> "$REPORT" << 'EOF'
## Throughput (MB/s)

| Terminal | ASCII | Seq | Unicode | ANSI |
|----------|-------|-----|---------|------|
EOF

  for f in "${RESULTS_DIR}"/throughput-*.json; do
    name=$(jq -r '.terminal' "$f")
    ascii=$(jq -r 'if .payloads.ascii then (.payloads.ascii.stats.mean / 1048576 * 100 | round / 100 | tostring) else "—" end' "$f")
    seq_val=$(jq -r 'if .payloads.seq then (.payloads.seq.stats.mean / 1048576 * 100 | round / 100 | tostring) else "—" end' "$f")
    unicode=$(jq -r 'if .payloads.unicode then (.payloads.unicode.stats.mean / 1048576 * 100 | round / 100 | tostring) else "—" end' "$f")
    ansi=$(jq -r 'if .payloads.ansi then (.payloads.ansi.stats.mean / 1048576 * 100 | round / 100 | tostring) else "—" end' "$f")
    echo "| ${name} | ${ascii} | ${seq_val} | ${unicode} | ${ansi} |" >> "$REPORT"
  done
  echo "" >> "$REPORT"
fi

# ── Resource Table ───────────────────────────────────────────────────
resource_files=("${RESULTS_DIR}"/resources-*.json)
if [[ -f "${resource_files[0]}" ]]; then
  cat >> "$REPORT" << 'EOF'
## Resource Usage

| Terminal | Idle RSS (MB) | Idle CPU (%) | Load RSS Peak (MB) | Load CPU Avg (%) |
|----------|---------------|--------------|--------------------|--------------------|
EOF

  for f in "${RESULTS_DIR}"/resources-*.json; do
    name=$(jq -r '.terminal' "$f")
    idle_rss=$(jq -r '.idle.rss_kb.mean / 1024 * 10 | round / 10' "$f")
    idle_cpu=$(jq -r '.idle.cpu_pct.mean' "$f")
    load_peak=$(jq -r '.load.peak_rss_kb / 1024 * 10 | round / 10' "$f")
    load_cpu=$(jq -r '.load.cpu_pct.mean' "$f")
    echo "| ${name} | ${idle_rss} | ${idle_cpu} | ${load_peak} | ${load_cpu} |" >> "$REPORT"
  done
  echo "" >> "$REPORT"
fi

# ── Latency Table ────────────────────────────────────────────────────
latency_files=("${RESULTS_DIR}"/latency-*.json)
if [[ -f "${latency_files[0]}" ]]; then
  cat >> "$REPORT" << 'EOF'
## Input Latency (ms)

| Terminal | Mean | p50 | p95 | p99 | Stddev |
|----------|------|-----|-----|-----|--------|
EOF

  for f in "${RESULTS_DIR}"/latency-*.json; do
    name=$(jq -r '.terminal' "$f")
    mean=$(jq -r '.stats.mean' "$f")
    p50=$(jq -r '.stats.p50' "$f")
    p95=$(jq -r '.stats.p95' "$f")
    p99=$(jq -r '.stats.p99' "$f")
    stddev=$(jq -r '.stats.stddev' "$f")
    echo "| ${name} | ${mean} | ${p50} | ${p95} | ${p99} | ${stddev} |" >> "$REPORT"
  done
  echo "" >> "$REPORT"
fi

# ── CSV export ───────────────────────────────────────────────────────
echo "terminal,benchmark,metric,value" > "$CSV"

for f in "${RESULTS_DIR}"/startup-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  mean=$(jq -r '.stats.mean' "$f")
  echo "${name},startup,mean_ms,${mean}" >> "$CSV"
done

for f in "${RESULTS_DIR}"/throughput-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  for payload in ascii seq unicode ansi; do
    val=$(jq -r "if .payloads.${payload} then .payloads.${payload}.stats.mean else \"\" end" "$f")
    [[ -n "$val" ]] && echo "${name},throughput_${payload},mean_bytes_per_sec,${val}" >> "$CSV"
  done
done

for f in "${RESULTS_DIR}"/resources-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  idle_rss=$(jq -r '.idle.rss_kb.mean' "$f")
  load_peak=$(jq -r '.load.peak_rss_kb' "$f")
  echo "${name},resources,idle_rss_kb,${idle_rss}" >> "$CSV"
  echo "${name},resources,peak_rss_kb,${load_peak}" >> "$CSV"
done

for f in "${RESULTS_DIR}"/latency-*.json; do
  [[ -f "$f" ]] || continue
  name=$(jq -r '.terminal' "$f")
  mean=$(jq -r '.stats.mean' "$f")
  p95=$(jq -r '.stats.p95' "$f")
  echo "${name},latency,mean_ms,${mean}" >> "$CSV"
  echo "${name},latency,p95_ms,${p95}" >> "$CSV"
done

echo "Report: ${REPORT}"
echo "CSV:    ${CSV}"
