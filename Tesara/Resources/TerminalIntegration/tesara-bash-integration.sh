if [[ -n "${TESARA_BASH_INTEGRATION_LOADED:-}" ]]; then
  return
fi
TESARA_BASH_INTEGRATION_LOADED=1

__tesara_prompt_command() {
  local last_status=$?

  if [[ -n "${TESARA_HAS_SEEN_PROMPT:-}" ]]; then
    printf '\033]133;D;%d\a' "$last_status"
  else
    TESARA_HAS_SEEN_PROMPT=1
    # On first prompt, push cursor to bottom of terminal for bottom-aligned output.
    # Brief sleep lets the app's layout pass set the correct PTY dimensions
    # before we query with tput (split panes resize after shell start).
    if [[ "${TESARA_BOTTOM_ALIGN:-}" == "1" ]]; then
      sleep 0.15
      printf '\033[%d;1H' "$(tput lines)"
    fi
  fi

  printf '\033]133;A\a'
  printf '\033]133;B\a'
}

__tesara_preexec() {
  printf '\033]133;C\a'
  # Write command text for Tesara's command history capture
  # Use `history 1` for the full command line — $BASH_COMMAND only has the last simple command in pipelines
  if [[ -n "${TESARA_SESSION_ID:-}" && -n "${TESARA_TMPDIR:-}" ]]; then
    builtin history 1 | sed 's/^[ ]*[0-9]*[ ]*//' > "${TESARA_TMPDIR}/tesara-cmd-${TESARA_SESSION_ID}.txt" 2>/dev/null || true
  fi
}

__tesara_debug_trap() {
  __tesara_preexec
}

__tesara_chain_existing_debug_trap() {
  local existing_trap
  existing_trap=$(trap -p DEBUG)

  if [[ -z "${existing_trap}" ]]; then
    trap '__tesara_debug_trap' DEBUG
    return
  fi

  local existing_handler
  existing_handler=${existing_trap#trap -- \\'}
  existing_handler=${existing_handler%\\' DEBUG}

  if [[ "${existing_handler}" == *"__tesara_debug_trap"* ]]; then
    return
  fi

  trap "__tesara_debug_trap; ${existing_handler}" DEBUG
}

if [[ ";${PROMPT_COMMAND:-};" != *";__tesara_prompt_command;"* ]]; then
  if [[ -n "${PROMPT_COMMAND:-}" ]]; then
    PROMPT_COMMAND="__tesara_prompt_command;${PROMPT_COMMAND}"
  else
    PROMPT_COMMAND="__tesara_prompt_command"
  fi
fi

if [[ -z "${TESARA_BASH_DEBUG_TRAP:-}" ]]; then
  __tesara_chain_existing_debug_trap
  TESARA_BASH_DEBUG_TRAP=1
fi

# Re-align cursor to bottom row when the app signals via a temp file.
# Triggered by SIGWINCH after the input bar appears/resizes the terminal.
__tesara_winch() {
  if [[ -n "${TESARA_TMPDIR:-}" && -n "${TESARA_SESSION_ID:-}" ]]; then
    local sigfile="${TESARA_TMPDIR}/tesara-ba-${TESARA_SESSION_ID}"
    if [[ -f "$sigfile" ]]; then
      rm -f "$sigfile"
      printf '\033[%d;1H' "$(tput lines)"
    fi
  fi
}
trap '__tesara_winch' WINCH
