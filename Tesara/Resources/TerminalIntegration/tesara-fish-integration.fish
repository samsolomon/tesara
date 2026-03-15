# Tesara Fish Shell Integration

# Ensure system PATH entries are present (non-login shell may be missing them)
if test -f /etc/paths
    for p in (cat /etc/paths /etc/paths.d/* 2>/dev/null)
        if test -d $p; and not contains -- $p $PATH
            set -gxa PATH $p
        end
    end
end

# Emits OSC 133 sequences for command block capture

function __tesara_emit_osc133 --argument-names code
    printf '\033]133;%s\007' $code
end

set -g __tesara_has_seen_prompt 0

function __tesara_fish_prompt --on-event fish_prompt
    if test $__tesara_has_seen_prompt -eq 1
        __tesara_emit_osc133 "D;$status"
    else
        # On first prompt, push cursor to bottom of terminal for bottom-aligned output.
        # Brief sleep lets the app's layout pass set the correct PTY dimensions
        # before we query with tput (split panes resize after shell start).
        if test "$TESARA_BOTTOM_ALIGN" = 1
            sleep 0.15
            printf '\033[%d;1H' (tput lines)
        end
    end
    set -g __tesara_has_seen_prompt 1
    __tesara_emit_osc133 "A"
    __tesara_emit_osc133 "B"
end

function __tesara_fish_preexec --on-event fish_preexec
    __tesara_emit_osc133 "C"
    # Write command text for Tesara's command history capture
    if set -q TESARA_SESSION_ID; and set -q TESARA_TMPDIR
        printf '%s' "$argv" > "$TESARA_TMPDIR/tesara-cmd-$TESARA_SESSION_ID.txt" 2>/dev/null; or true
    end
end

# Re-align cursor to bottom row when the app signals via a temp file.
# Triggered by SIGWINCH after the input bar appears/resizes the terminal.
function __tesara_fish_winch --on-signal WINCH
    if set -q TESARA_TMPDIR; and set -q TESARA_SESSION_ID
        set -l sigfile "$TESARA_TMPDIR/tesara-ba-$TESARA_SESSION_ID"
        if test -f "$sigfile"
            rm -f "$sigfile"
            printf '\033[%d;1H' (tput lines)
        end
    end
end
