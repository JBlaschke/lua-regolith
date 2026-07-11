# 🌑 lua-regolith

**The foundation layer for your Lua environment.**

Like the [regolith](https://en.wikipedia.org/wiki/Regolith) that blankets
the Moon's surface, this project is the loose but essential layer everything
else sits on.

lua-regolith builds a self-contained, relocatable Lua installation —
no system packages required. Use it to:

- **Run [Lmod](https://github.com/TACC/Lmod)** on HPC clusters, containers,
  or any system where you control the software stack.
- **Create standalone executables** with
  [luastatic](https://github.com/ers35/luastatic).
- **Embed a batteries-included Lua interpreter** in your own projects.

## Why lua-regolith?

Lmod's [SourceForge tarball](https://sourceforge.net/projects/lmod/) bundles
its Lua dependencies for Lua 5.1. If you want to run Lmod on **Lua 5.4+**,
you need to provide those dependencies yourself — luaposix, luafilesystem,
lpeg, dkjson, and lua-term — compiled against the same interpreter and
installed where it can find them.

lua-regolith does exactly that: one `make install` gives you a Lua
interpreter with hardcoded package paths pointing at all the bundled modules.
No `LUA_PATH` or `LUA_CPATH` juggling, no version mismatches, no chasing
down five separate build systems.

Developers benefit too: every C module is also installed as a static library
(`.a`), so you can link them into standalone binaries with luastatic or
embed them in your own C/C++ application.

---

## Quick Start

```bash
git clone https://github.com/JBlaschke/lua-regolith.git
cd lua-regolith

make download
make verify
make PREFIX=/opt/lua-regolith all
make PREFIX=/opt/lua-regolith static-lua
make PREFIX=/opt/lua-regolith test
make PREFIX=/opt/lua-regolith install
```

> **No cmake?** Substitute `make -f Makefile.lite` throughout — it needs
> only `cc`, GNU make, and `wget`. See
> [Repository Layout & Build Internals](#repository-layout--build-internals).

---

## For Lmod Users

Once lua-regolith is installed, point Lmod's configure at it:

```bash
git clone https://github.com/TACC/Lmod.git
cd Lmod
./configure --prefix=/opt/lmod \
  --with-lua=/opt/lua-regolith/bin/lua \
  --with-luac=/opt/lua-regolith/bin/luac
make install
```

Lmod's configure detects luaposix, lfs, lpeg, dkjson, and lua-term from the
bundled interpreter's hardcoded package paths. No environment variables
needed. To activate:

```bash
source /opt/lmod/lmod/lmod/init/bash   # or .csh, .zsh, .fish
module avail
```

**Things to know:**

- Lmod hardcodes `LUA_PATH`/`LUA_CPATH` at configure time. Your
  lua-regolith prefix must be **final** before you `./configure` Lmod
  (or use `RELOCATABLE=1`, or re-run `make relocate PREFIX=...`).
- **luafilesystem** is a hard Lmod requirement. Without it, spider cache
  generation and many internal operations fail immediately.
- **lua-term** isn't strictly required, but without it `module avail`
  defaults to 80 columns regardless of terminal width.
- **lpeg** and **dkjson** are used by various Lmod internals. They're small
  and easy to include, so there's no good reason to skip them.

---

## For Developers

### Install Layout

```
$PREFIX/
├── bin/
│   ├── lua              # interpreter (paths hardcoded to $PREFIX)
│   ├── luac             # compiler
│   └── lua-static       # (optional) fully static interpreter
├── include/
│   ├── lua.h, luaconf.h, lualib.h, lauxlib.h
│   └── luv.h
├── lib/
│   ├── liblua.a          ─┐
│   ├── liblua.so          │
│   ├── libluaposix.a      │ static + shared libs
│   ├── libluv.a           │ for luastatic / linking
│   ├── libluv.so          │
│   ├── libluv_libuv.a     │
│   ├── liblfs.a           │
│   ├── liblpeg.a          │
│   ├── libluaterm.a       │
│   ├── static-lua.a       │ merged fat archive
│   ├── static-lua.o      ─┘ merged relocatable object (preferred)
│   ├── lua/<ver>/         # shared modules loaded at runtime
│   │   ├── posix/ (+ sys/)
│   │   ├── luv.so
│   │   ├── lfs.so
│   │   ├── lpeg.so
│   │   └── term/core.so
│   └── pkgconfig/
│       └── lua<ver>.pc
└── share/lua/<ver>/
    ├── posix/             # pure-Lua parts of luaposix
    ├── term/              # init.lua, cursor.lua, colors.lua
    ├── re.lua             # regex module built on lpeg
    └── dkjson.lua         # JSON library
```

### Using with luastatic

The simplest path is the merged artifacts produced by `make static-lua`:

```bash
luastatic main.lua \
  /opt/lua-regolith/lib/static-lua.o \
  -I/opt/lua-regolith/include \
  -lpthread -lm -ldl
```

`static-lua.o` is a single relocatable object (`ld -r` output), so every
symbol is included unconditionally — no special linker flags needed. The
`static-lua.a` fat archive is also installed for toolchains that expect
`.a` files, but archives may need
`-Wl,--whole-archive ... -Wl,--no-whole-archive` (Linux) or
`-Wl,-force_load,...` (macOS) to pull in all symbols.

You can also link individual module archives (`liblua.a`, `libluaposix.a`,
`liblfs.a`, ...) — include only what your script actually requires.

### Fully Static Interpreter

```bash
make PREFIX=/opt/lua-regolith static-lua
make PREFIX=/opt/lua-regolith install
```

Produces `$PREFIX/bin/lua-static` — the real `lua.c` interpreter (readline,
`-e`, `-l`, `-i`, full REPL) with all C modules registered in
`package.preload` and all pure-Lua modules (dkjson, term/*.lua, re.lua,
posix/*.lua) embedded as byte arrays. It runs with **zero** external files.

**Platform notes:**

- **Linux (glibc)**: `-static` works; NSS caveats apply. For clean static
  builds, build on Alpine (musl).
- **macOS**: Can't fully static-link; dynamically links libSystem.

### Relocating an Install

Only the Lua core embeds `PREFIX`; the C modules contain no hardcoded
paths. To move an existing tree without a full rebuild:

```bash
make relocate PREFIX=/new/path
make PREFIX=/new/path install
```

Or build with `RELOCATABLE=1`, which makes the interpreter resolve
`package.path`/`package.cpath` relative to its own location at runtime —
the whole prefix can then be moved freely (`cp -a`, `rsync`, `tar`).

---

## Bundled Modules

| Module    | Type       | Purpose                                      |
|-----------|------------|----------------------------------------------|
| luaposix  | C + Lua    | POSIX bindings (required by Lmod)            |
| luv       | C          | libuv bindings for async I/O                 |
| lfs       | C (1 file) | Filesystem operations (required by Lmod)     |
| lpeg      | C          | PEG parsing library (used by Lmod)           |
| lua-term  | C + Lua    | Terminal detection (used by Lmod for width)  |
| dkjson    | pure Lua   | JSON encode/decode (used by Lmod)            |

The `re.lua` module ships with lpeg and provides a regex-like interface on
top of PEG patterns. It's installed automatically.

---

## Build Guide

### Requirements

**Makefile** (full): cc (C99), GNU make, cmake ≥ 3.10, wget,
libreadline-dev. Any POSIX system — cmake handles platform detection.

**Makefile.lite** (minimal): cc (C99), GNU make, wget, libreadline-dev.
Linux, macOS, FreeBSD, or OpenBSD (use `gmake` on the BSDs).

```bash
# Debian/Ubuntu (full)
sudo apt install build-essential cmake wget libreadline-dev

# Debian/Ubuntu (lite — no cmake)
sudo apt install build-essential wget libreadline-dev

# Alpine (for fully static builds)
apk add build-base cmake wget readline-dev readline-static linux-headers
```

Both Makefiles produce **identical install layouts** and are
interchangeable — `make test` validates the same things either way. The
only difference is how libuv and luv are built:

| | `Makefile` | `Makefile.lite` |
|---|---|---|
| Build deps | cc, make, cmake | cc, make |
| libuv/luv build | cmake (auto platform detection) | direct compilation |
| Platform support | any POSIX (cmake handles it) | Linux, macOS, FreeBSD, OpenBSD |

The tradeoff: `Makefile.lite` maintains libuv's platform-specific source
list by hand (in `mk/uv-source.mk`). It's stable within a libuv minor
series; on a `LIBUV_VER` bump, diff it against the new `CMakeLists.txt`.

### Configuration Variables

| Variable      | Default      | Purpose                           |
|---------------|--------------|-----------------------------------|
| `PREFIX`      | `/usr/local` | Install location                  |
| `RELOCATABLE` | `0`          | `1` = exe-relative package paths  |
| `CC` / `AR` / `RANLIB` | gcc / ar / ranlib | Toolchain          |
| `LUA_VER`     | `5.5.0`      | Lua version                       |
| `LUAPOSIX_VER`| `36.3`       | luaposix version                  |
| `LUV_VER`     | `1.52.1-0`   | luv version                       |
| `LIBUV_VER`   | `1.52.1`     | libuv version                     |
| `LFS_VER`     | `1.9.0`      | luafilesystem version             |
| `LPEG_VER`    | `1.1.0`      | lpeg version                      |
| `LUATERM_VER` | `0.8`        | lua-term version                  |
| `DKJSON_VER`  | `2.8`        | dkjson version                    |

`LUA_SHORT` (e.g. `5.5`) is derived automatically from `LUA_VER` — you
don't need to set it separately. SHA-256 checksums live next to the
version numbers in `mk/common.mk` and must be updated together
(`make verify` will tell you).

### Tests

```bash
make test        # comprehensive: test/test_bundled.lua
make quicktest   # fast smoke test: test/test_quick.lua
```

Both exercise every module: luaposix (including nested `posix.sys.stat`),
luv (including an event-loop timer), lfs (dir listing, attributes), lpeg
(pattern matching), lua-term (isatty function), and dkjson (JSON
roundtrip). If the static interpreter has been built, it is tested too.

---

## Repository Layout & Build Internals

```
Makefile            # entry point: cmake-based libuv/luv build
Makefile.lite       # entry point: cmake-free build
mk/
├── common.mk       # all shared build logic (~90% of the system)
├── uv-cmake.mk     # libuv+luv via cmake
└── uv-source.mk    # libuv+luv compiled directly; source lists live here
scripts/            # POSIX sh helpers invoked by recipes
├── verify-checksums.sh      # SHA-256 verification
├── patch-luaconf.sh         # append PREFIX overrides to luaconf.h
├── inject-after-openlibs.sh # insert preload/relocation calls into lua.c
├── luaposix-config.sh       # autoconf-style feature probes -> HAVE_* header
├── build-luaposix-so.sh     # .o -> .so paths derived from luaopen_* symbols
├── luaposix-modules.sh      # discover pure-Lua luaposix modules
├── compile-sources.sh       # batch-compile a source list (libuv, lite mode)
├── merge-static.sh          # merge libs+objects -> static-lua.{a,o}
├── gen-pkgconfig.sh         # emit lua<ver>.pc
└── lua2c.sh                 # Lua sources -> C byte arrays for embedding
src/                # C support code (preload registration, relocation)
test/               # test_quick.lua, test_bundled.lua
```

### Version Resilience

The build is designed to survive Lua version bumps without edits beyond
`LUA_VER` (plus checksums). Things that commonly break in version-pinned
build systems are handled dynamically:

1. **Source file list** — the Lua core is compiled with a `*.c` glob and
   `lua.o`/`luac.o` are removed afterward. New or removed source files are
   picked up automatically.
2. **`luaconf.h` patching** — `scripts/patch-luaconf.sh` *appends*
   `#undef`/`#define` overrides rather than sed-matching internal
   formatting. The preprocessor uses the last definition, so `LUA_ROOT`,
   `LUA_PATH_DEFAULT`, and `LUA_CPATH_DEFAULT` always win regardless of
   how the stock file changes between releases.
3. **Interpreter patching** — `scripts/inject-after-openlibs.sh` anchors on
   the openlibs *call site*, matching both `luaL_openlibs(L);` (Lua ≤ 5.4)
   and `luai_openlibs(L);` (5.5), and fails loudly if the anchor moves.
4. **Header installation** — all `.h` files in `src/` are installed
   dynamically rather than from a hardcoded list.
5. **luaposix feature detection** — `scripts/luaposix-config.sh` probes the
   actual toolchain/headers (autoconf-style) instead of hardcoding a
   platform matrix.

**What still needs manual attention** on a new major Lua version: the C
modules (luaposix, luv, lfs, lpeg, lua-term) must support that version's
C API — check their release notes. On a libuv bump, audit
`mk/uv-source.mk` against upstream's `CMakeLists.txt`.

---

## License

`lua-regolith` is offered under a **dual-licensing** model. You may choose
**one** of the following licenses:

1. **Open Source License**: GNU Affero General Public License, version 3 or
   later — SPDX: `AGPL-3.0-or-later`
   See: `LICENSE-AGPL` (and/or `LICENSE`)

2. **Commercial License**: A separate commercial license is available from
   Johannes Blaschke without the conditions of the GNU Affero GPL.
   See: `COMMERCIAL.md`

If you do not have a commercial license agreement with Johannes Blaschke,
your use of this project is governed by the **AGPL-3.0-or-later**.

The bundled components have their own licenses (all permissive): Lua (MIT),
luaposix (MIT), luv (Apache 2.0), libuv (MIT), luafilesystem (MIT),
lpeg (MIT), lua-term (MIT), dkjson (MIT).

### What this means (high level)

- The AGPL is an OSI-approved open-source license. You may use
  `lua-regolith` commercially under the AGPL if you comply with its terms.
- If you modify `lua-regolith` and run it to provide network access to
  users (e.g., as a service), the AGPL includes obligations related to
  offering the corresponding source code of the version you run.
- If your organization cannot or does not want to comply with the AGPL's
  requirements, you can obtain a commercial license.

For commercial licensing inquiries: **Johannes Blaschke,
johannes@blaschke.science**

---

## Contributing

We welcome contributions!

To preserve the ability to offer `lua-regolith` under both open-source and
commercial licenses, all contributions must be made under the Contributor
License Agreement:

- See: `CLA.md`

By submitting a pull request (or otherwise contributing code), you agree
that your contribution is made under the terms of the CLA.

---

Copyright (c) 2026 Johannes Blaschke
