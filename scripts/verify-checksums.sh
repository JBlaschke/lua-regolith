#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# verify-checksums.sh FILE SHA256 [FILE SHA256]...
# An empty SHA256 skips that file (useful for untested new upstream releases).
set -euo pipefail

if command -v sha256sum >/dev/null 2>&1; then
    SHA256_CMD="sha256sum"
else
    SHA256_CMD="shasum -a 256"
fi

failed=0
while [ $# -ge 2 ]; do
    file=$1; expected=$2; shift 2
    if [ -z "$expected" ]; then
        echo "SKIP  $file (no checksum)"
        continue
    fi
    got=$($SHA256_CMD "$file" | awk '{print $1}')
    if [ "$got" = "$expected" ]; then
        echo "OK    $file"
    else
        echo "FAIL  $file"
        echo "  expected: $expected"
        echo "  got:      $got"
        failed=1
    fi
done

if [ $# -ne 0 ]; then
    echo "verify-checksums.sh: odd argument count (unpaired: $*)" >&2
    exit 2
fi

[ "$failed" -eq 0 ] || { echo "FAILED"; exit 1; }
echo "All checksums passed."
