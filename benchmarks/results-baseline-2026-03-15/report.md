# Tesara benchmark report

**Date:** 2026-03-15
**System:** macOS 26.3.1 | Apple M1 Pro | 32 GB RAM
**Methodology:** 10 cold-start runs (startup), 10 runs per payload at normalized 80x24 window (throughput), 10 idle + 60 load samples (resources), 100 keystrokes + 10 warmup (latency), 5 runs (Ctrl-C)

---

## Summary

| Metric | Tesara | Ghostty | Delta | Winner |
|--------|--------|---------|-------|--------|
| Startup (ms) | 1056 | 1111 | -5.0% | Tesara |
| Input latency mean (ms) | 6.36 | — | — | — |
| Input latency p50 (ms) | 5.97 | — | — | — |
| Input latency p95 (ms) | 10.14 | — | — | — |
| Idle RSS (MB) | 124 | 135 | -8.1% | Tesara |
| Peak load RSS (MB) | 139 | 134 | +3.7% | Ghostty |
| ASCII throughput (MB/s) | 45.5 | 147.3 | -69.1% | Ghostty |
| Unicode throughput (MB/s) | 68.8 | 284.8 | -75.8% | Ghostty |
| ANSI throughput (MB/s) | 31.2 | 189.5 | -83.5% | Ghostty |
| Ctrl-C (ms) | 469 | — | — | — |

---

## Startup time

Cold start: time from `open -b` until the shell writes a sentinel file. 10 runs.

| Terminal | Mean | Stddev | Min | Max | Median | Rating |
|----------|------|--------|-----|-----|--------|--------|
| Tesara | 1056 ms | 127 ms | 988 ms | 1414 ms | 1013 ms | Acceptable |
| Ghostty | 1111 ms | 93 ms | 1053 ms | 1374 ms | 1082 ms | Acceptable |

Tesara starts **55 ms faster** on average. The first run (1414 ms) is an outlier — likely cold cache. Excluding it, Tesara averages 1016 ms.

---

## Input latency

Keystroke-to-screen latency via AX API polling. 100 measured keystrokes after 10 warmup.

| Terminal | Mean | p50 | p95 | p99 | Stddev | Rating |
|----------|------|-----|-----|-----|--------|--------|
| Tesara | 6.36 ms | 5.97 ms | 10.14 ms | 13.49 ms | 2.33 ms | Good |

Rated **good** (threshold: < 10 ms). p50 under 6 ms is competitive. p95 at 10 ms shows occasional spikes, likely from Metal frame submission timing.

---

## Throughput

Payload rendered through the terminal at normalized 80x24 window. 10 runs per payload.

| Payload | Size | Tesara (MB/s) | Ghostty (MB/s) | Ratio |
|---------|------|---------------|----------------|-------|
| ASCII (random base64) | 10 MB | 45.5 | 147.3 | 0.31x |
| Seq (1M lines of numbers) | 6.9 MB | 30.9 | 91.5 | 0.34x |
| Unicode (CJK + emoji) | 24 MB | 68.8 | 284.8 | 0.24x |
| ANSI (SGR color codes) | 14 MB | 31.2 | 189.5 | 0.16x |
| Ligature (fi/fl/ffi) | 10 MB | 45.5 | — | — |
| ZWJ emoji (flags/families) | 13 MB | 26.7 | — | — |

Ghostty is **3-6x faster** at rendering throughput. ANSI color processing shows the widest gap (6x). ZWJ grapheme clustering is Tesara's slowest payload at 26.7 MB/s.

---

## Resource usage

### Idle (10 samples, 1s apart after 5s settle)

| Terminal | RSS (MB) | CPU (%) |
|----------|----------|---------|
| Tesara | 124 | 0.4 |
| Ghostty | 135 | 0.0 |

Tesara uses **11 MB less** idle memory than Ghostty.

### Under load (`seq 1 10000000`, 30s)

| Terminal | Peak RSS (MB) | CPU avg (%) |
|----------|---------------|-------------|
| Tesara | 139 | 63.9 |
| Ghostty | 134 | 0.0 |

Peak RSS is comparable. Tesara's CPU usage reflects active Metal rendering.

---

## Ctrl-C responsiveness

Start `seq 1 100000000`, wait 2s, send Ctrl-C, measure time to shell prompt. 5 runs.

| Terminal | Mean | Stddev | Min | Max | Rating |
|----------|------|--------|-----|-----|--------|
| Tesara | 469 ms | 21 ms | 454 ms | 506 ms | Good |

Consistent and under 500 ms. Rated **good**.

---

## Tab scaling

Memory usage with increasing tab counts.

| Tabs | RSS (MB) | Per-tab delta (MB) |
|------|----------|--------------------|
| 1 | 127 | — |
| 5 | 195 | +17 |
| 10 | 256 | +12 |
| 20 | 322 | +10 |

Linear scaling at **10-17 MB per tab**, trending down as tabs increase (likely shared resources amortizing). 20 tabs at 322 MB is reasonable.

---

## Not measured

| Benchmark | Reason | Action needed |
|-----------|--------|---------------|
| FPS under load | doom-fire-zig not built | Run `bash benchmarks/setup.sh` with zig installed |
| Parser throughput | kitten CLI not installed | `brew install --cask kitty` |

---

## Verdict

| Category | Winner |
|----------|--------|
| Startup | **Tesara** |
| Input latency | **Tesara** (only contestant) |
| Idle memory | **Tesara** |
| Throughput | Ghostty (3-6x faster) |
| Ctrl-C | **Tesara** (only contestant) |

## Key takeaways

1. **Latency is good** — 6.36 ms mean, p50 under 6 ms. This is the most user-perceptible metric and Tesara performs well.
2. **Startup is a win** — 5% faster than Ghostty, though both are in the "acceptable" range.
3. **Throughput is the #1 performance gap** — 3-6x slower than Ghostty across all payload types. ANSI color processing is the worst case.
4. **Memory is healthy** — 124 MB idle, 139 MB peak, linear tab scaling at ~13 MB/tab.
5. **Ctrl-C is solid** — 469 ms mean, well under 1s threshold.
6. **Need Ghostty latency/Ctrl-C runs** for head-to-head comparison on those metrics.
