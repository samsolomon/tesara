# AGENTS.md

Tesara exists to become the most beautiful, performant, and usable terminal on macOS.

## Principles
- Native over novel.
- Beauty through restraint.
- Performance is a feature.
- Keyboard-first, always.
- Precision beats decoration.
- Cohesion across window chrome, navigation, and terminal content.
- Prefer system APIs and long-term correctness over hacks.
- Every change should make the product clearer, faster, calmer, or more delightful.
- UI labels use sentence case: capitalize only the first word and proper nouns.

## Ghostty Fork

`vendor/ghostty` is a submodule pointing at [`samsolomon/ghostty`](https://github.com/samsolomon/ghostty), a fork of `ghostty-org/ghostty`. The fork's `tesara` branch carries a `build.zig` patch that emits `libghostty.a` + headers on macOS.

The submodule is pinned to an **immutable tag** (e.g. `tesara/v1`), not the branch. The branch can be force-pushed during rebases; tags never move. This guarantees old Tesara commits always resolve.

### Updating to a newer upstream Ghostty

```bash
cd vendor/ghostty
git fetch upstream                        # (add remote once: git remote add upstream https://github.com/ghostty-org/ghostty.git)
git checkout tesara
git rebase upstream/main                  # resolve conflicts if build.zig changed
zig build -Doptimize=ReleaseFast -Dapp-runtime=none -Demit-xcframework=false  # verify it builds
git tag tesara/vN                         # increment: v2, v3, ...
git push origin tesara --force-with-lease # branch — force push is fine
git push origin tesara/vN                 # tag — immutable, never force pushed
cd ../..
git add vendor/ghostty
git commit -m "vendor: update ghostty to tesara/vN"
```

Deleting `vendor/ghostty/zig-out/lib/libghostty.a` forces a full Zig rebuild (~minutes).
