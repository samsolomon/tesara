#!/usr/bin/env bash
# generate-payloads.sh — create test data files for throughput benchmarks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

echo "==> Generating throughput payloads..."

# 1. 10MB random ASCII
PAYLOAD_ASCII="${PAYLOAD_DIR}/.payload-ascii"
if [[ ! -f "$PAYLOAD_ASCII" ]]; then
  echo "  Generating 10MB ASCII payload..."
  cat /dev/urandom | base64 | head -c 10485760 > "$PAYLOAD_ASCII"
  echo "  Done: ${PAYLOAD_ASCII} ($(wc -c < "$PAYLOAD_ASCII") bytes)"
else
  echo "  ASCII payload exists, skipping."
fi

# 2. 1M lines via seq
PAYLOAD_SEQ="${PAYLOAD_DIR}/.payload-seq"
if [[ ! -f "$PAYLOAD_SEQ" ]]; then
  echo "  Generating 1M-line seq payload..."
  seq 1 1000000 > "$PAYLOAD_SEQ"
  echo "  Done: ${PAYLOAD_SEQ} ($(wc -c < "$PAYLOAD_SEQ") bytes)"
else
  echo "  Seq payload exists, skipping."
fi

# 3. 200K lines of Unicode (CJK + emoji)
PAYLOAD_UNICODE="${PAYLOAD_DIR}/.payload-unicode"
if [[ ! -f "$PAYLOAD_UNICODE" ]]; then
  echo "  Generating 200K-line Unicode payload..."
  python3 -c "
import random
cjk = list(range(0x4E00, 0x9FFF))
emoji = list(range(0x1F600, 0x1F64F)) + list(range(0x1F680, 0x1F6FF))
chars = cjk + emoji
for _ in range(200000):
    line = ''.join(chr(random.choice(chars)) for _ in range(40))
    print(line)
" > "$PAYLOAD_UNICODE"
  echo "  Done: ${PAYLOAD_UNICODE} ($(wc -c < "$PAYLOAD_UNICODE") bytes)"
else
  echo "  Unicode payload exists, skipping."
fi

# 4. 200K lines of ANSI SGR color sequences
PAYLOAD_ANSI="${PAYLOAD_DIR}/.payload-ansi"
if [[ ! -f "$PAYLOAD_ANSI" ]]; then
  echo "  Generating 200K-line ANSI color payload..."
  python3 -c "
import random, string
for _ in range(200000):
    fg = random.randint(30, 37)
    bg = random.randint(40, 47)
    bold = random.choice(['1;', ''])
    text = ''.join(random.choices(string.ascii_letters + string.digits, k=60))
    print(f'\033[{bold}{fg};{bg}m{text}\033[0m')
" > "$PAYLOAD_ANSI"
  echo "  Done: ${PAYLOAD_ANSI} ($(wc -c < "$PAYLOAD_ANSI") bytes)"
else
  echo "  ANSI payload exists, skipping."
fi

# 5. Ligature-heavy payload (fi, fl, ffi sequences)
PAYLOAD_LIGATURE="${PAYLOAD_DIR}/.payload-ligature"
if [[ ! -f "$PAYLOAD_LIGATURE" ]]; then
  echo "  Generating 10MB ligature-heavy payload..."
  python3 -c "
import random, string
ligatures = ['fi', 'fl', 'ffi', 'ffl', 'ff', 'ft', 'st']
normal = string.ascii_letters + string.digits
total = 0
target = 10 * 1024 * 1024
while total < target:
    parts = []
    for _ in range(20):
        parts.append(random.choice(ligatures))
        parts.append(''.join(random.choices(normal, k=random.randint(2, 6))))
    line = ''.join(parts)
    print(line)
    total += len(line) + 1
" > "$PAYLOAD_LIGATURE"
  echo "  Done: ${PAYLOAD_LIGATURE} ($(wc -c < "$PAYLOAD_LIGATURE") bytes)"
else
  echo "  Ligature payload exists, skipping."
fi

# 6. Emoji ZWJ sequences (flags, skin tones, family combos)
PAYLOAD_ZWJ="${PAYLOAD_DIR}/.payload-zwj"
if [[ ! -f "$PAYLOAD_ZWJ" ]]; then
  echo "  Generating ZWJ emoji payload..."
  python3 -c "
import random
# Skin tone modifiers
skin_tones = [0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF]
# Base people/gesture emoji that accept skin tones
people = [0x1F44B, 0x1F44D, 0x1F44E, 0x1F44F, 0x1F64C, 0x1F64F, 0x270B, 0x270C, 0x261D]
# Flag pairs (regional indicators A-Z = 0x1F1E6..0x1F1FF)
ri_base = 0x1F1E6
# ZWJ family components
zwj = chr(0x200D)
man = chr(0x1F468)
woman = chr(0x1F469)
boy = chr(0x1F466)
girl = chr(0x1F467)
heart = chr(0x2764) + chr(0xFE0F)
kiss = chr(0x1F48B)

for _ in range(100000):
    parts = []
    for _ in range(8):
        r = random.random()
        if r < 0.3:
            # Skin-toned emoji
            base = chr(random.choice(people))
            tone = chr(random.choice(skin_tones))
            parts.append(base + tone)
        elif r < 0.5:
            # Flag sequence (two regional indicators)
            a = chr(ri_base + random.randint(0, 25))
            b = chr(ri_base + random.randint(0, 25))
            parts.append(a + b)
        elif r < 0.7:
            # ZWJ family
            family = [random.choice([man, woman]), zwj, random.choice([man, woman]),
                       zwj, random.choice([boy, girl])]
            parts.append(''.join(family))
        else:
            # ZWJ couple with heart
            parts.append(man + zwj + heart + zwj + kiss + zwj + woman)
        parts.append(' ')
    print(''.join(parts))
" > "$PAYLOAD_ZWJ"
  echo "  Done: ${PAYLOAD_ZWJ} ($(wc -c < "$PAYLOAD_ZWJ") bytes)"
else
  echo "  ZWJ emoji payload exists, skipping."
fi

echo "==> All payloads ready."
