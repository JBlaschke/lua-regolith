#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# compile-sources.sh SRC_ROOT OBJ_DIR FILE.c [FILE.c]...
# Env: CC, CFLAGS
#
# Compiles each relative source path to OBJ_DIR, flattening / to _ in the
# object name (src/unix/core.c -> src_unix_core.o).  The flattening keeps
# the object dir flat and prevents basename collisions between directories.
set -eu

srcroot=$1; objdir=$2; shift 2

for f in "$@"; do
    obj=$(echo "$f" | sed 's|/|_|g;s|\.c$|.o|')
    # shellcheck disable=SC2086  -- CFLAGS must word-split
    $CC $CFLAGS -c -o "$objdir/$obj" "$srcroot/$f"
done
