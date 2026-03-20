# Tesara Terminal Benchmark Results

## System

| Property | Value |
|----------|-------|
| macOS | 26.3.1 |
| Chip | Apple M1 Pro |
| RAM | 32 GB |
| Display refresh | — Hz |
| Date | 2026-03-15T18:50:35Z |

## Startup time (ms)

Thresholds: <500 excellent | <1000 good | <2000 acceptable | >=2000 poor

| Terminal | Mean | Stddev | Min | Max | Median | Rating |
|----------|------|--------|-----|-----|--------|--------|
| Ghostty | 1111.2 | 93.25 | 1053.0 | 1374.0 | 1083.0 | Acceptable |
| Tesara | 1055.9 | 127.38 | 988.0 | 1414.0 | 1022.0 | Acceptable |

## Throughput (MB/s)

| Terminal | ASCII | Seq | Unicode | ANSI | Ligature | ZWJ |
|----------|-------|-----|---------|------|----------|-----|
| Ghostty | 66.38 | 50.06 | 78.84 | 40.96 | 66.27 | 37.26 |
| Tesara | 47.94 | 36.39 | 71.3 | 32.28 | 50.28 | 27.36 |

## Resource usage

Thresholds (idle RSS): <100 MB excellent | <200 MB good | <500 MB acceptable | >=500 MB poor

| Terminal | Idle RSS (MB) | Idle CPU (%) | Load RSS peak (MB) | Load CPU avg (%) | Rating |
|----------|---------------|--------------|--------------------|--------------------|--------|
| Ghostty | 135.2 | 0.0 | 134.3 | 0.01 | Good |
| Tesara | 123.7 | 0.41 | 138.7 | 63.87 | Good |

## Input latency (ms)

Thresholds: <5 ms excellent | <10 ms good | <20 ms acceptable | >=20 ms poor

| Terminal | Mean | p50 | p95 | p99 | Stddev | Rating |
|----------|------|-----|-----|-----|--------|--------|
| Tesara | 6.3600000000000003 | 5.9699999999999998 | 10.140000000000001 | 13.49 | 2.3300000000000001 | Good |

## Ctrl-C responsiveness (ms)

Thresholds: <200 ms excellent | <500 ms good | <1000 ms acceptable | >=1000 ms poor

| Terminal | Mean | Stddev | Min | Max | Rating |
|----------|------|--------|-----|-----|--------|
| Tesara | 469.16 | 21.31 | 453.7 | 505.6 | Good |

## Tab scaling (RSS in MB)

| Terminal | 1 tab | 5 tabs | 10 tabs | 20 tabs |
|----------|-------|--------|---------|---------|
| Tesara | 127 | 195 | 256 | 322 |

## Verdict

| Category | Winner |
|----------|--------|
| Startup | Tesara |
| Throughput (ASCII) | Ghostty |
| Idle memory | Tesara |
| Input latency | Tesara |
| Ctrl-C responsiveness | Tesara |
| Scrollback buffer cost | — |

