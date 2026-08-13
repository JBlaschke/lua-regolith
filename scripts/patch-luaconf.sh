#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# patch-luaconf.sh LUACONF_H PREFIX LUA_SHORT LUA_MOD_EXT
# patch-luaconf.sh --strip LUACONF_H
#
# Lua's compiled-in search paths live in luaconf.h as a chain of macros:
# LUA_ROOT (the prefix), LUA_LDIR/LUA_CDIR (share and lib dirs derived from
# it), and LUA_PATH_DEFAULT/LUA_CPATH_DEFAULT (the actual ?-template search
# strings baked into package.path/package.cpath). Stock value: /usr/local/. We
# need /opt/lua-regolith/ or wherever.
#
# Hardcodes the install prefix into the Lua interpreter by APPENDING
# #undef/#define overrides to the end of luaconf.h.  The preprocessor uses the
# last #define, so our values win regardless of how the stock file is formatted
# -- this is what makes the patch survive Lua version bumps (sed-matching
# internal formatting would not).
#
# Also appends a platform block reverting Lua 5.5.1's macOS readline change:
# upstream replaced LUA_READLINELIB "libedit.dylib" (dlopen'd at run time, the
# 5.5.0 mechanism) with LUA_USE_READLINE (compile-time <readline/readline.h>,
# link-time -lreadline) in the LUA_USE_MACOSX block. The append trick covers
# these too: like the path macros, both are consumed only by lua.c, never
# inside luaconf.h itself, so the state at end-of-file is the state lua.c's #if
# branches see.
#
# Idempotent: any existing override blocks are stripped before appending.
# --strip removes the blocks without appending (used by `make relocate`).
set -eu

# Append-only patching has one failure mode of its own: append twice and you
# get two copies of a block — still functionally correct (last-wins means the
# later copy governs), but the file grows on every rebuild and a PREFIX change
# would leave the old prefix visibly present, lying to anyone who reads the
# file. The markers make the operation idempotent: every entry point strips any
# existing blocks before appending fresh ones, so the file always contains
# exactly zero or one copy of each block, and re-running with the same or
# different arguments converges to the same state. This matters concretely
# because of common.mk's .prefix content-stamp — change PREFIX on the command
# line and make re-runs this script on the already-patched file;
# strip-then-append is what makes that a clean replacement rather than an
# accretion.

MARK_PREFIX='BUNDLED_LUA_PREFIX_OVERRIDE'
MARK_PLATFORM='BUNDLED_LUA_PLATFORM_OVERRIDE'

# strip_block FILE MARKER
strip_block() {
    if grep -q "$2" "$1"; then
        # two /regex/ addresses joined by a comma select every line from the
        # first match of the start pattern through the next match of the end
        # pattern, inclusive, and d deletes them.
        sed "/\/\* ---- $2 ----/,/\/\* ---- end $2 ----/d" "$1" > "$1.new"
        mv "$1.new" "$1"
    fi
}

strip_all() {
    strip_block "$1" "$MARK_PREFIX"
    strip_block "$1" "$MARK_PLATFORM"
}

if [ "$1" = "--strip" ]; then
    strip_all "$2"
    exit 0
fi

luaconf=$1; prefix=$2; lua_short=$3; mod_ext=$4

strip_all "$luaconf"

cat >> "$luaconf" <<EOF

/* ---- $MARK_PREFIX ---- */
/* Appended by lua-regolith (scripts/patch-luaconf.sh). */

#ifdef LUA_ROOT
#undef LUA_ROOT
#endif
#define LUA_ROOT "$prefix/"

#ifdef LUA_LDIR
#undef LUA_LDIR
#endif
#define LUA_LDIR LUA_ROOT "share/lua/$lua_short/"

#ifdef LUA_CDIR
#undef LUA_CDIR
#endif
#define LUA_CDIR LUA_ROOT "lib/lua/$lua_short/"

#ifdef LUA_PATH_DEFAULT
#undef LUA_PATH_DEFAULT
#endif
#define LUA_PATH_DEFAULT LUA_LDIR"?.lua;"LUA_LDIR"?/init.lua;"LUA_CDIR"?.lua;"LUA_CDIR"?/init.lua;""./?.lua;./?/init.lua"

#ifdef LUA_CPATH_DEFAULT
#undef LUA_CPATH_DEFAULT
#endif
#define LUA_CPATH_DEFAULT LUA_CDIR"?.$mod_ext;"LUA_CDIR"loadall.$mod_ext;""./?.$mod_ext"

/* ---- end $MARK_PREFIX ---- */

/* ---- $MARK_PLATFORM ---- */
/* Appended by lua-regolith (scripts/patch-luaconf.sh).
**
** Lua 5.5.1 switched macOS from run-time dlopen of libedit (LUA_READLINELIB,
** the 5.5.0 mechanism) to compile-time readline (LUA_USE_READLINE), giving
** lua.c hard link-time references to readline/add_history/rl_readline_name.
** Revert to the 5.5.0 behaviour: zero link-time dependencies; the REPL dlopens
** Apple's libedit, and the library can be swapped at run time via the
** LUA_READLINELIB environment variable (new in 5.5.1).  Linux keeps upstream's
** dlopen default and is untouched by this block.
*/
#if defined(LUA_USE_MACOSX)
#ifdef LUA_USE_READLINE
#undef LUA_USE_READLINE
#endif
#ifndef LUA_READLINELIB
#define LUA_READLINELIB "libedit.dylib"
#endif
#endif
/* ---- end $MARK_PLATFORM ---- */
EOF
