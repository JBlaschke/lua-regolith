#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# compile-sources.sh SRC_ROOT OBJ_DIR FILE.c [FILE.c]...
# Env: CC, CFLAGS
#
# Compiles each relative source path to OBJ_DIR, flattening / to _ in the
# object name (src/unix/core.c -> src_unix_core.o).  The flattening keeps
# the object dir flat and prevents basename collisions between directories.
# This script enables the entire "compile libuv" step of lite mode, reduced to
# its essence. The caller in mk/uv-source.mk hands it three things: a source
# root (`(CURDIR)/(LIBUV_DIR)`), an output dir (`(BUILD)/libuv−obj‘),and then
# the whole `LIBUV_SRC_ALL` list splatted onto the command line.
set -eu

srcroot=$1; objdir=$2; shift 2

for f in "$@"; do
    # The flattening transform, two substitutions in one sed:
    # * s|/|_|g — every slash becomes an underscore, globally:
    #   src/unix/core.c → src_unix_core.c. Pipe delimiters again, since the
    #   pattern is a slash.
    # * s|\.c$|.o| — swap the extension. The \. matches a literal dot
    #   (unescaped, . matches anything), and the $ anchor pins it to
    #   end-of-string so a .c appearing mid-path could never be touched.
    #   Result: src_unix_core.o.
    obj=$(echo "$f" | sed 's|/|_|g;s|\.c$|.o|')
    # shellcheck disable=SC2086   # CFLAGS must word-split
    $CC $CFLAGS -c -o "$objdir/$obj" "$srcroot/$f"
done
