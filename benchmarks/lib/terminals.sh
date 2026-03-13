#!/usr/bin/env bash
# lib/terminals.sh — terminal launch, quit, and detection helpers

# Launch a terminal by bundle ID. Waits for a window to appear.
# Usage: launch_terminal "com.apple.Terminal"
launch_terminal() {
  local bundle_id="$1"
  open -b "$bundle_id"
  wait_for_window "$bundle_id"
}

# Quit a terminal by bundle ID via AppleScript.
# Usage: quit_terminal "com.apple.Terminal"
quit_terminal() {
  local bundle_id="$1"
  local app_name
  app_name=$(app_name_from_bundle "$bundle_id")

  osascript -e "
    tell application \"${app_name}\"
      if it is running then quit
    end tell
  " 2>/dev/null || true

  # Wait for process to exit
  local timeout=10
  local elapsed=0
  while pgrep -f "$bundle_id" &>/dev/null && (( elapsed < timeout )); do
    sleep 0.5
    elapsed=$((elapsed + 1))
  done
}

# Detect which benchmark terminals are installed.
# Prints installed terminal names (one per line).
detect_terminals() {
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.sh"

  for name in $TERMINAL_NAMES; do
    local bundle_id
    bundle_id=$(get_bundle_id "$name")
    if [[ -n "$bundle_id" ]] && mdfind "kMDItemCFBundleIdentifier == '${bundle_id}'" 2>/dev/null | head -1 | grep -q .; then
      echo "$name"
    fi
  done | sort
}

# Resolve app name from bundle ID (for AppleScript).
app_name_from_bundle() {
  local bundle_id="$1"
  local app_path
  app_path=$(mdfind "kMDItemCFBundleIdentifier == '${bundle_id}'" 2>/dev/null | head -1)
  if [[ -n "$app_path" ]]; then
    basename "$app_path" .app
  else
    echo "$bundle_id"
  fi
}
