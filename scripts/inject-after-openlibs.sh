#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# inject-after-openlibs.sh LUA_C OUTPUT STATEMENT [STATEMENT]...
#
# Copies lua.c to OUTPUT with the given C statements inserted immediately
# after the openlibs call in pmain().  The regex matches both call-site
# spellings -- luaL_openlibs(L); on Lua <= 5.4, luai_openlibs(L); on 5.5 --
# and the trailing ; is load-bearing: it excludes 5.5's
# `#define luai_openlibs(L) ...` line (a statement at file scope would be
# a syntax error).
#
# NOTE: awk -v processes escape sequences in the value, so the literal \n
# built below becomes a real newline inside awk.  Statements containing
# backslashes would be mangled -- none of ours do, and the grep check
# below catches total failure.
set -eu

src=$1; out=$2; shift 2

inject=""
for stmt in "$@"; do
    inject="$inject  $stmt\n"
done

awk -v inject="$inject" '{print} /lua[iL]_openlibs\(L\);/{printf "%s", inject}' \
    "$src" > "$out"

if ! grep -qF "$1" "$out"; then
    echo "ERROR: openlibs anchor not found in $src" >&2
    rm -f "$out"
    exit 1
fi
