#!/usr/bin/env bash
# bench-wide-throughput.sh — throughput at 200 columns
#
# Delegates to bench-throughput.sh with wider window geometry.
# Quantifies rendering cost at typical ultrawide/split-pane widths.

set -euo pipefail

export THROUGHPUT_GRID_COLS=200
export THROUGHPUT_BENCHMARK_NAME=wide-throughput

exec "$(dirname "$0")/../throughput/bench-throughput.sh" "$@"
