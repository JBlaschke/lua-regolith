#!/usr/bin/env bash
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
set -euo pipefail

mode=$1; output=$2; shift 2
: "${AR:=ar}"
: "${RANLIB:=ranlib}"
# assigns the default if AR is unset or empty, and : is the do-nothing builtin
# that exists to host the expansion (you need some command for the side effect
# to hang off — bare ${AR:=ar} on a line would try to execute the result).

# mktemp -d gives every invocation a fresh unique directory; trap ... EXIT
# guarantees teardown on any exit — success, set -eu failure, SIGINT (the shell
# runs EXIT traps on signal-induced exits). Single quotes on the trap string
# are deliberate: the expansion of `mergedir` happens when the trap fires.
mergedir=$(mktemp -d)
trap 'rm -rf "$mergedir"' EXIT

n=0
excludes=""

# hand-rolled option parser — while [ $# -gt 0 ]; case $1 in — because getopts
# can't do repeatable options accumulating in order
while [ $# -gt 0 ]; do
    case $1 in
        -l)
            lib=$2; shift 2
            n=$((n + 1))
            # ar x extracts into the current directory, no output-dir flag — so
            # we must cd into the staging slot. But then a relative archive
            # path breaks. The libpath line is the POSIX absolutize idiom: cd
            # to the containing dir, pwd for its absolute form, reattach the
            # basename. (No realpath/readlink -f — the former is
            # nonstandard-ish, the latter's -f doesn't exist on macOS.) The
            # subshell parens are the second trick: the cd happens in a child,
            # so the parent's cwd never moves — no cd-back bookkeeping, no
            # wrong-directory fallout if extraction fails under set -e.
            mkdir -p "$mergedir/lib$n"
            libpath=$(cd "$(dirname "$lib")" && pwd)/$(basename "$lib")
            (cd "$mergedir/lib$n" && $AR x "$libpath")
            ;;
        -d)
            srcdir=$2; shift 2
            n=$((n + 1))
            # luaposix compiles ext/posix/time.c and ext/posix/sys/time.c. Both
            # produce time.o. The build keeps them apart as luaposix-obj/time.o
            # and luaposix-obj/sys/time.o — and ar happily stores both in
            # libluaposix.a, because archive members are just named blobs and
            # duplicate names are legal. But extract that archive and the flat
            # directory can only hold one time.o: the second overwrites the
            # first, one module's symbols vanish, and the static binary's
            # require("posix.sys.time") (or posix.time, depending on member
            # order) fails at runtime
            mkdir -p "$mergedir/dir$n"
            # for our own modules, skip the archive round-trip entirely and
            # copy the object tree, structure intact
            (cd "$srcdir" && find . -name '*.o' -exec sh -c '
                mkdir -p "$0/$(dirname "$1")"; cp "$1" "$0/$1"
            ' "$mergedir/dir$n" {} \;)
            ;;
        -o)
            obj=$2; shift 2
            n=$((n + 1))
            # single-object copy, trivially into its numbered slot: the two
            # preload objects
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
        # conventional format, but a .a is a lazy container — the consuming
        # linker pulls only members that resolve currently-undefined symbols,
        # so package.preload registrations reachable only through the preload
        # objects can get skipped unless the consumer says
        # --whole-archive/-force_load. ld -r — partial/incremental linking —
        # instead performs an actual link without resolving external symbols,
        # welding all inputs into one relocatable .o. A plain object file is
        # eager: any linker given a .o includes all of it, no flags, no
        # per-platform incantations. That's why static-lua.o is the documented
        # preferred interface and the .a exists for toolchains that insist on
        # archives.
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
