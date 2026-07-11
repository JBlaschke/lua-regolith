#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# luaposix-modules.sh LUAPOSIX_DIR
# Emits module.name:path pairs for every pure-Lua luaposix file, for embedding
# via lua2c.sh.  Discovered rather than hardcoded so upstream adding/removing
# files doesn't break the static build:
#   lib/posix/init.lua      -> posix
#   lib/posix/sys/stat.lua  -> posix.sys.stat
# Silent no-op before the source tree is extracted ($(shell) runs at parse time
# on every invocation, including `make download`).
#
# Note about the execution context: The output lands in a variable that feeds
# LUA_EMBED_ALL, which only the static-lua machinery consumes. Why parse-time
# rather than a build-time rule? Because the module list must exist as a make
# variable to appear in the lua2c.sh recipe's argument list — make can't grow a
# variable from a recipe that runs later. The list is data the makefile needs,
# not an artifact the build produces.
#
# Warning: an underscore in a luaposix filename would survive to the module
# name here, but its C-module sibling going through build-luaposix-so.sh would
# get that underscore exploded into a slash. Three scripts, three lossy
# transforms (_↔ / twice, /→_ once), all safe because luaposix and libuv
# respectively never put the ambiguous character where it would bite.
set -eu

dir=$1
[ -d "$dir/lib/posix" ] || exit 0

find "$dir/lib/posix" -name '*.lua' | sort | while read -r f; do
    # Four substitutions turning a filesystem path into a require() name:
    #  1. s|^$dir/lib/|| — strip the tree prefix, anchored at start:
    #     luaposix-36.3/lib/posix/sys/stat.lua →  posix/sys/stat.lua.
    #  2. s|/init\.lua$|| — order-critical: posix/init.lua →  posix. This
    #     encodes Lua's package convention where a directory's init.lua is the
    #     module named by the directory — require("posix") loads posix/init.lua.
    #     The leading / in the pattern means it only fires on init.lua as a
    #     basename under a directory, and consuming the slash along with the
    #     filename leaves the bare directory path.
    #  3. s|\.lua$|| — for everything step 2 didn't eat: posix/compat.lua →
    #     posix/compat. Run these two in the opposite order and posix/init.lua
    #     →  posix/init — step 3 strips .lua first, then step 2's pattern (which
    #     wants /init.lua, with extension) no longer matches. You'd get a
    #     module named posix.init instead of posix, and require("posix") in the
    #     static binary would fail while everything else looked fine. The
    #     semicolon-chain order is doing semantic work.
    #  4. s|/|.|g — separators: posix/sys/stat →  posix.sys.stat.
    rel=$(echo "$f" | sed "s|^$dir/lib/||;s|/init\.lua\$||;s|\.lua\$||;s|/|.|g")
    # Emit the pair — posix.sys.stat:luaposix-36.3/lib/posix/sys/stat.lua — one
    # per line to stdout, which $(shell) captures and (this is easy to miss)
    # converts newlines to spaces.
    echo "$rel:$f"
done
