autoload -Uz add-zsh-hook

typeset -g TESARA_HAS_SEEN_PROMPT=0

function _tesara_precmd() {
  local last_status=$?

  if [[ ${TESARA_HAS_SEEN_PROMPT} -eq 1 ]]; then
    printf '\e]133;D;%d\a' "$last_status"
  else
    TESARA_HAS_SEEN_PROMPT=1
    # On first prompt, push cursor to bottom of terminal for bottom-aligned output.
    # Brief sleep lets the app's layout pass set the correct PTY dimensions
    # before we query with tput (split panes resize after shell start).
    if [[ "${TESARA_BOTTOM_ALIGN:-}" == "1" ]]; then
      sleep 0.15
      printf '\e[%d;1H' "$(tput lines)"
    fi
  fi

  printf '\e]133;A\a'
  printf '\e]133;B\a'
}

function _tesara_preexec() {
  printf '\e]133;C\a'
  # Write command text for Tesara's command history capture
  if [[ -n "${TESARA_SESSION_ID:-}" && -n "${TESARA_TMPDIR:-}" ]]; then
    printf '%s' "$1" > "${TESARA_TMPDIR}/tesara-cmd-${TESARA_SESSION_ID}.txt" 2>/dev/null || true
  fi
}

function _tesara_report_pwd() {
  printf '\e]7;kitty-shell-cwd://%s%s\a' "${HOST}" "${PWD}"
}

add-zsh-hook precmd _tesara_precmd
add-zsh-hook preexec _tesara_preexec
chpwd_functions+=(_tesara_report_pwd)

# Report initial working directory
_tesara_report_pwd

# Re-align cursor to bottom row when the app signals via a temp file.
# Triggered by SIGWINCH after the input bar appears/resizes the terminal.
function TRAPWINCH() {
  if [[ -n "${TESARA_TMPDIR:-}" && -n "${TESARA_SESSION_ID:-}" ]]; then
    local sigfile="${TESARA_TMPDIR}/tesara-ba-${TESARA_SESSION_ID}"
    if [[ -f "$sigfile" ]]; then
      rm -f "$sigfile"
      printf '\e[%d;1H' "$(tput lines)"
    fi
  fi
}
