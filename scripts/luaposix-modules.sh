#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# luaposix-modules.sh LUAPOSIX_DIR
# Emits module.name:path pairs for every pure-Lua luaposix file, for
# embedding via lua2c.sh.  Discovered rather than hardcoded so upstream
# adding/removing files doesn't break the static build:
#   lib/posix/init.lua      -> posix
#   lib/posix/sys/stat.lua  -> posix.sys.stat
# Silent no-op before the source tree is extracted ($(shell) runs at parse
# time on every invocation, including `make download`).
set -eu

dir=$1
[ -d "$dir/lib/posix" ] || exit 0

find "$dir/lib/posix" -name '*.lua' | sort | while read -r f; do
    rel=$(echo "$f" | sed "s|^$dir/lib/||;s|/init\.lua\$||;s|\.lua\$||;s|/|.|g")
    echo "$rel:$f"
done
