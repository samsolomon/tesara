# AGENTS.md

Tesara exists to become the most beautiful, performant, and usable terminal on macOS.

## Principles
- Native over novel.
- Beauty through restraint.
- Performance is a feature.
- Keyboard-first, always.
- Precision beats decoration.
- Cohesion across window chrome, navigation, and terminal content.
- Use Liquid Glass only when it improves clarity or interaction.
- Prefer system APIs and long-term correctness over hacks.
- Every change should make the product clearer, faster, calmer, or more delightful.
- UI labels use sentence case: capitalize only the first word and proper nouns.

## Ghostty Submodule

`vendor/ghostty` contains a vendored copy of libghostty with **local patches** that must be preserved:

- **`src/termio/Exec.zig`** — Darwin `login(1)` wrapper removed. `/usr/bin/login` spins at 100% CPU on macOS Tahoe; the patch falls through to POSIX `/bin/sh -c` instead.
- **`build.zig`** — Modified to emit `libghostty.a` static library + headers on macOS.

If you update the ghostty submodule to a newer upstream commit, re-apply these patches or verify upstream has equivalent fixes. Deleting `vendor/ghostty/zig-out/lib/libghostty.a` forces a full Zig rebuild (~minutes).
