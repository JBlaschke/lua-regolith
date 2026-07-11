#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# build-luaposix-so.sh OBJ_DIR OUT_DIR
# Env: CC, SHARED_LINK, LUA_MOD_EXT, LINK_LIBS
#
# Links each luaposix .o into a .so at the path implied by its exported
# luaopen_* symbol:
#   posix_unistd.o    (luaopen_posix_unistd)    -> posix/unistd.so
#   posix_sys_stat.o  (luaopen_posix_sys_stat)  -> posix/sys/stat.so
#
# sed 's/.* //'  -- last field of the nm line (the symbol name)
# sed 's/^_//'   -- macOS prepends _ to all C symbols
set -eu

objdir=$1; outdir=$2

find "$objdir" -name '*.o' | while read -r obj; do
    sym=$(nm -g "$obj" 2>/dev/null | grep ' T.*luaopen_' | head -1 | sed 's/.* //;s/^_//')
    [ -n "$sym" ] || continue
    relpath=$(echo "$sym" | sed 's/^luaopen_//;s|_|/|g')
    mkdir -p "$outdir/$(dirname "$relpath")"
    # shellcheck disable=SC2086  -- SHARED_LINK and LINK_LIBS must word-split
    $CC $SHARED_LINK -o "$outdir/$relpath.$LUA_MOD_EXT" "$obj" $LINK_LIBS
done
