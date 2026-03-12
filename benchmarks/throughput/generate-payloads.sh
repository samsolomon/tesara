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
  base64 /dev/urandom | head -c 10485760 > "$PAYLOAD_ASCII"
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

echo "==> All payloads ready."
