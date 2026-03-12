autoload -Uz add-zsh-hook

typeset -g TESARA_HAS_SEEN_PROMPT=0

function _tesara_precmd() {
  local last_status=$?

  if [[ ${TESARA_HAS_SEEN_PROMPT} -eq 1 ]]; then
    printf '\e]133;D;%d\a' "$last_status"
  else
    TESARA_HAS_SEEN_PROMPT=1
  fi

  printf '\e]133;A\a'
  printf '\e]133;B\a'
}

function _tesara_preexec() {
  printf '\e]133;C\a'
}

add-zsh-hook precmd _tesara_precmd
add-zsh-hook preexec _tesara_preexec
