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

  local elapsed=0
  while (( elapsed < timeout )); do
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

  echo "Warning: timed out waiting for window from ${app_name}" >&2
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

# Get total RSS (in KB) for a process and all its children.
# Usage: get_tree_rss <pid>
get_tree_rss() {
  local parent_pid="$1"
  local total=0
  local pids

  # Get parent + children
  pids=$(pgrep -P "$parent_pid" 2>/dev/null || true)
  pids="$parent_pid $pids"

  for pid in $pids; do
    local rss
    rss=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || echo 0)
    total=$((total + rss))
  done
  echo "$total"
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
