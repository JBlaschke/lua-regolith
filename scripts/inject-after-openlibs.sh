#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# inject-after-openlibs.sh LUA_C OUTPUT STATEMENT [STATEMENT]...
#
# Copies lua.c to OUTPUT with the given C statements inserted immediately after
# the openlibs call in pmain().  The regex matches both call-site spellings --
# luaL_openlibs(L); on Lua <= 5.4, luai_openlibs(L); on 5.5 -- and the trailing
# ";" is load-bearing: it excludes 5.5's `#define luai_openlibs(L) ...` line (a
# statement at file scope would be a syntax error).
#
# NOTE: awk -v processes escape sequences in the value, so the literal \n built
# below becomes a real newline inside awk.  Statements containing backslashes
# would be mangled -- none of ours do, and the grep check below catches total
# failure.
set -euo pipefail

src=$1; out=$2; shift 2

inject=""
for stmt in "$@"; do
    inject="$inject  $stmt\n"
done

# The awk program itself is the classic two-pattern-action idiom:
# * {print} — no pattern, so it fires for every line: pass the input through
#   unchanged. The whole file gets copied.
# * /lua[iL]_openlibs\(L\);/{printf "%s", inject} — pattern-guarded: after
#   printing any line matching the regex, additionally emit the payload. printf
#   "%s" rather than print because the payload already ends in its own newline
#   and print would add a second (a blank line — harmless in C, but sloppy).
awk -v inject="$inject" '{print} /lua[iL]_openlibs\(L\);/{printf "%s", inject}' \
    "$src" > "$out"
# Note about the trailing ; is the subtle one — called "load-bearing" above:
# Lua 5.5's lua.c contains the token luai_openlibs(L) twice. Once as the call
# site in pmain() — luai_openlibs(L); — and once as a preprocessor definition
# near the top: #define luai_openlibs(L) .... The #define line has no semicolon
# after the closing paren. Without the ; in the regex, awk would match both
# lines and inject the payload after each — and a C statement sitting at file
# scope, outside any function, right after a #define, is a syntax error. The
# compile would fail with a baffling diagnostic pointing at generated code.

if ! grep -qF "$1" "$out"; then
    echo "ERROR: openlibs anchor not found in $src" >&2
    rm -f "$out"
    exit 1
fi
