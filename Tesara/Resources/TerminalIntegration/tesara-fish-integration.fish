# Tesara Fish Shell Integration
# Emits OSC 133 sequences for command block capture

function __tesara_emit_osc133 --argument-names code
    printf '\033]133;%s\007' $code
end

set -g __tesara_has_seen_prompt 0

function __tesara_fish_prompt --on-event fish_prompt
    if test $__tesara_has_seen_prompt -eq 1
        __tesara_emit_osc133 "D;$status"
    end
    set -g __tesara_has_seen_prompt 1
    __tesara_emit_osc133 "A"
    __tesara_emit_osc133 "B"
end

function __tesara_fish_preexec --on-event fish_preexec
    __tesara_emit_osc133 "C"
end
