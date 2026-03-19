#!/usr/bin/env bash
# lib/helpers.sh — shared utility functions

# Returns current time in milliseconds.
timestamp_ms() {
  perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000'
}

# Wait for a window to appear for the given bundle ID.
# Usage: wait_for_window "com.apple.Terminal" [timeout_seconds]
wait_for_window() {
  local bundle_id="$1"
  local timeout="${2:-15}"
  local app_name
  app_name=$(app_name_from_bundle "$bundle_id" 2>/dev/null || basename "$bundle_id")

  local iterations=$(( timeout * 5 ))  # 0.2s per iteration
  local elapsed=0
  while (( elapsed < iterations )); do
    local count
    count=$(osascript -e "
      tell application \"System Events\"
        tell process \"${app_name}\"
          count of windows
        end tell
      end tell
    " 2>/dev/null || echo 0)
    if (( count > 0 )); then
      return 0
    fi
    sleep 0.2
    elapsed=$((elapsed + 1))
  done

  echo "Warning: timed out waiting for window from ${app_name} (${timeout}s)" >&2
  return 1
}

# Get PID(s) for a bundle ID. Returns all matching PIDs.
# Usage: get_pid "com.apple.Terminal"
get_pid() {
  local bundle_id="$1"
  local app_path
  app_path=$(mdfind "kMDItemCFBundleIdentifier == '${bundle_id}'" 2>/dev/null | head -1)
  if [[ -n "$app_path" ]]; then
    local app_name
    app_name=$(basename "$app_path" .app)
    pgrep -f "$app_name" 2>/dev/null || true
  fi
}

# Get total RSS (KB) and CPU (%) for a process tree. Outputs "rss_kb cpu_pct".
# Single ps call with BFS tree walk in awk.
# Usage: get_tree_stats <pid>
get_tree_stats() {
  local root="$1"
  ps -eo pid=,ppid=,rss=,%cpu= 2>/dev/null | awk -v root="$root" '
    {
      rss_of[$1] = $3
      cpu_of[$1] = $4
      children[$2] = children[$2] " " $1
    }
    END {
      total_rss = rss_of[root] + 0
      total_cpu = cpu_of[root] + 0.0
      queue = children[root]
      while (queue != "") {
        split(queue, q, " ")
        queue = ""
        for (i in q) {
          pid = q[i]
          if (pid == "") continue
          total_rss += rss_of[pid] + 0
          total_cpu += cpu_of[pid] + 0.0
          if (pid in children) queue = queue children[pid]
        }
      }
      printf "%d %.1f\n", total_rss, total_cpu
    }
  '
}

# Get total RSS (in KB) for a process and its entire descendant tree.
# Usage: get_tree_rss <pid>
get_tree_rss() {
  get_tree_stats "$1" | awk '{print $1}'
}

# Send a keystroke to the frontmost application via System Events.
# Usage: send_keystroke "some text"
send_keystroke() {
  local text="$1"
  osascript -e "
    tell application \"System Events\"
      keystroke \"${text}\"
    end tell
  "
}

# Send a keystroke followed by Return.
# Usage: send_command "echo hello"
send_command() {
  local cmd="$1"
  osascript -e "
    tell application \"System Events\"
      keystroke \"${cmd}\"
      keystroke return
    end tell
  "
}

# Compute statistics from a newline-separated list of numbers.
# Usage: echo "1\n2\n3" | compute_stats
# Outputs JSON: {"mean":..., "stddev":..., "min":..., "max":..., "p50":..., "p95":..., "p99":...}
compute_stats() {
  python3 -c "
import sys, json, statistics
vals = [float(x.strip()) for x in sys.stdin if x.strip()]
if not vals:
    print(json.dumps({}))
    sys.exit()
vals.sort()
n = len(vals)
result = {
    'mean': round(statistics.mean(vals), 2),
    'stddev': round(statistics.stdev(vals), 2) if n > 1 else 0,
    'min': round(min(vals), 2),
    'max': round(max(vals), 2),
    'median': round(statistics.median(vals), 2),
    'p50': round(vals[int(n * 0.50)], 2),
    'p95': round(vals[int(n * 0.95)], 2),
    'p99': round(vals[int(n * 0.99)], 2),
    'count': n
}
print(json.dumps(result))
"
}
