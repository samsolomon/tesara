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
  fi

  printf '\033]133;A\a'
  printf '\033]133;B\a'
}

__tesara_preexec() {
  printf '\033]133;C\a'
  # Write command text for Tesara's command history capture
  if [[ -n "${TESARA_SESSION_ID:-}" ]]; then
    printf '%s' "$BASH_COMMAND" > "${TMPDIR:-/tmp}/tesara-cmd-${TESARA_SESSION_ID}.txt"
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
