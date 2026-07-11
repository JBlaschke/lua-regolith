#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# patch-luaconf.sh LUACONF_H PREFIX LUA_SHORT LUA_MOD_EXT
# patch-luaconf.sh --strip LUACONF_H
#
# Hardcodes the install prefix into the Lua interpreter by APPENDING
# #undef/#define overrides to the end of luaconf.h.  The preprocessor uses
# the last #define, so our values win regardless of how the stock file is
# formatted -- this is what makes the patch survive Lua version bumps
# (sed-matching internal formatting would not).
#
# Idempotent: any existing override block is stripped before appending.
# --strip removes the block without appending (used by `make relocate`).
set -eu

MARK_START='/* ---- BUNDLED_LUA_PREFIX_OVERRIDE ---- */'
MARK_END='/* ---- end BUNDLED_LUA_PREFIX_OVERRIDE ---- */'

strip_block() {
    if grep -q 'BUNDLED_LUA_PREFIX_OVERRIDE' "$1"; then
        sed '/\/\* ---- BUNDLED_LUA_PREFIX_OVERRIDE ----/,/\/\* ---- end BUNDLED_LUA_PREFIX_OVERRIDE ----/d' \
            "$1" > "$1.new"
        mv "$1.new" "$1"
    fi
}

if [ "$1" = "--strip" ]; then
    strip_block "$2"
    exit 0
fi

luaconf=$1; prefix=$2; lua_short=$3; mod_ext=$4

strip_block "$luaconf"

cat >> "$luaconf" <<EOF

$MARK_START
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

$MARK_END
EOF
