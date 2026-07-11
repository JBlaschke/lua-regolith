#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# merge-static.sh {archive|object} OUTPUT [-l LIB.a]... [-d OBJDIR]... [-o FILE.o]... [-x NAME]...
# Env: AR, RANLIB (archive mode).
#
# Merges static libs and object files into one artifact:
#   archive -> .a via ar          (consumers may need --whole-archive)
#   object  -> .o via ld -r       (partial link; always fully included)
#
#   -l  extract an archive's members (safe only for archives without
#       internal basename collisions, e.g. the cmake-built libuv/libluv)
#   -d  copy an object tree recursively -- REQUIRED for luaposix, which has
#       both time.o and sys/time.o: `ar x` on its archive would silently
#       clobber one with the other
#   -o  copy a single object
#   -x  exclude objects by basename (posix.o: the monolithic module whose
#       luaopen_* symbols duplicate the individual submodules')
set -eu

mode=$1; output=$2; shift 2
: "${AR:=ar}"
: "${RANLIB:=ranlib}"

mergedir=$(mktemp -d)
trap 'rm -rf "$mergedir"' EXIT

n=0
excludes=""

while [ $# -gt 0 ]; do
    case $1 in
        -l)
            lib=$2; shift 2
            n=$((n + 1))
            mkdir -p "$mergedir/lib$n"
            libpath=$(cd "$(dirname "$lib")" && pwd)/$(basename "$lib")
            (cd "$mergedir/lib$n" && $AR x "$libpath")
            ;;
        -d)
            srcdir=$2; shift 2
            n=$((n + 1))
            mkdir -p "$mergedir/dir$n"
            (cd "$srcdir" && find . -name '*.o' -exec sh -c '
                mkdir -p "$0/$(dirname "$1")"; cp "$1" "$0/$1"
            ' "$mergedir/dir$n" {} \;)
            ;;
        -o)
            obj=$2; shift 2
            n=$((n + 1))
            mkdir -p "$mergedir/obj$n"
            cp "$obj" "$mergedir/obj$n/"
            ;;
        -x)
            excludes="$excludes $2"; shift 2
            ;;
        *)
            echo "merge-static.sh: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

for name in $excludes; do
    find "$mergedir" -name "$name" -exec rm -f {} +
done

rm -f "$output"
case $mode in
    archive)
        find "$mergedir" -name '*.o' | sort | xargs $AR rcs "$output"
        $RANLIB "$output"
        ;;
    object)
        find "$mergedir" -name '*.o' | sort | xargs ld -r -o "$output"
        ;;
    *)
        echo "merge-static.sh: mode must be 'archive' or 'object'" >&2
        exit 1
        ;;
esac
