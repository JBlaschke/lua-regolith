#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# gen-pkgconfig.sh OUTPUT PREFIX LUA_SHORT LUA_VER LDFLAGS_LUA
# ${prefix} etc. below are pkg-config variables, resolved when pkg-config
# reads the file -- the backslash escapes keep them literal through the
# expanding heredoc.  LDFLAGS_LUA is passed through rather than hardcoding
# "-lm -ldl": OpenBSD has no libdl.
set -eu

out=$1; prefix=$2; lua_short=$3; lua_ver=$4; ldflags=$5

cat > "$out" <<EOF
prefix=$prefix
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: lua-regolith $lua_short
Description: lua-regolith -- Lua $lua_short with bundled luaposix, luv, lfs, lpeg, lua-term, dkjson
Version: $lua_ver
Libs: -L\${libdir} -llua $ldflags
Libs.private: -lpthread
Cflags: -I\${includedir}
EOF
