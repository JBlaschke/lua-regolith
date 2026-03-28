# 🌑 lua-regolith

**The foundation layer for your Lua environment.**

Like the [regolith](https://en.wikipedia.org/wiki/Regolith) that blankets
the Moon's surface, this project is the loose but essential layer everything
else sits on.

lua-regolith builds a self-contained, relocatable Lua 5.4 installation —
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

## Table of Contents

- [Quick Start](#quick-start)
- [For Lmod Users](#for-lmod-users)
- [For Developers](#for-developers)
  - [Install Layout](#install-layout)
  - [Using with luastatic](#using-with-luastatic)
  - [Fully Static Interpreter](#fully-static-interpreter)
- [Bundled Modules](#bundled-modules)
- [Build Guide](#build-guide)
  - [Requirements](#requirements)
  - [Makefile vs Makefile.lite](#makefile-vs-makefilelite)
  - [Configuration Variables](#configuration-variables)
  - [Smoke Tests](#smoke-tests)
- [Version Resilience](#version-resilience)
- [License](#license)
- [Contributing](#contributing)

---

## Quick Start

```bash
git clone https://github.com/JBlaschke/lua-regolith.git
cd lua-regolith

make download
make PREFIX=/opt/lua-regolith all
make PREFIX=/opt/lua-regolith test
make PREFIX=/opt/lua-regolith install
```

This downloads all sources, builds everything, runs the test suite, and
installs to `PREFIX`. See [Build Guide](#build-guide) for requirements and
options.

> **No cmake?** Use `make -f Makefile.lite` instead — it needs only `cc`,
> `make`, and `wget`. See [Makefile vs Makefile.lite](#makefile-vs-makefilelite).

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

Lmod's configure will detect luaposix, lfs, lpeg, dkjson, and lua-term
from the bundled interpreter's hardcoded package paths. No `LUA_PATH` or
`LUA_CPATH` environment variables needed.

To activate:

```bash
source /opt/lmod/lmod/lmod/init/bash   # or .csh, .zsh, .fish
module avail
```

**Things to know:**

- Lmod hardcodes `LUA_PATH`/`LUA_CPATH` at configure time to protect itself
  from user environment changes. Your lua-regolith prefix must be **final**
  before you `./configure` Lmod.
- **luafilesystem** is a hard Lmod requirement. Without it, spider cache
  generation and many internal operations fail immediately.
- **lua-term** isn't strictly required, but without it `module avail` output
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
│   ├── liblua.a         ─┐
│   ├── liblua.so         │
│   ├── libluaposix.a     │ static + shared libs
│   ├── libluv.a          │ for luastatic / linking
│   ├── libluv.so         │
│   ├── libluv_libuv.a    │
│   ├── liblfs.a          │
│   ├── liblpeg.a         │
│   ├── libluaterm.a     ─┘
│   ├── lua/5.4/
│   │   ├── posix.so     ─┐
│   │   ├── posix/        │ shared modules loaded by
│   │   │   └── sys/      │ the interpreter at runtime
│   │   ├── luv.so        │
│   │   ├── lfs.so        │
│   │   ├── lpeg.so       │
│   │   └── term/         │
│   │       └── core.so  ─┘
│   └── pkgconfig/
│       └── lua5.4.pc
└── share/lua/5.4/
    ├── posix/           # pure-Lua parts of luaposix
    ├── term/            # init.lua, cursor.lua, colors.lua
    ├── re.lua           # regex module built on lpeg
    └── dkjson.lua       # JSON library
```

### Using with luastatic

```bash
luastatic main.lua \
  /opt/lua-regolith/lib/liblua.a \
  /opt/lua-regolith/lib/libluaposix.a \
  /opt/lua-regolith/lib/liblfs.a \
  /opt/lua-regolith/lib/liblpeg.a \
  /opt/lua-regolith/lib/libluaterm.a \
  /opt/lua-regolith/lib/libluv.a \
  /opt/lua-regolith/lib/libluv_libuv.a \
  -I/opt/lua-regolith/include \
  -lpthread -lm -ldl
```

Include only the `.a` files for modules your script actually uses.

### Fully Static Interpreter

```bash
make PREFIX=/opt/lua-regolith static-lua
make PREFIX=/opt/lua-regolith install
```

Produces `$PREFIX/bin/lua-static` — the real `lua.c` interpreter (readline,
`-e`, `-l`, `-i`, full REPL) with all C modules registered in
`package.preload`. The pure-Lua modules (dkjson, term/*.lua, re.lua,
posix/*.lua) still need to be on `LUA_PATH` or baked in via luastatic.

**Platform notes:**

- **Linux (glibc)**: `-static` works; NSS caveats apply.
  For clean static builds, build on Alpine (musl).
- **macOS**: Can't fully static-link; dynamically links libSystem.

---

## Bundled Modules

| Module    | Type       | Purpose                                      |
|-----------|------------|----------------------------------------------|
| luaposix  | C + Lua    | POSIX bindings (required by Lmod)            |
| luv       | C (cmake)  | libuv bindings for async I/O                 |
| lfs       | C (1 file) | Filesystem operations (required by Lmod)     |
| lpeg      | C          | PEG parsing library (used by Lmod)           |
| lua-term  | C + Lua    | Terminal detection (used by Lmod for width)  |
| dkjson    | pure Lua   | JSON encode/decode (used by Lmod)            |

The `re.lua` module ships with lpeg and provides a regex-like interface on
top of PEG patterns. It's installed automatically.

---

## Build Guide

### Requirements

**Makefile** (full):
- GCC or Clang (C99), GNU Make, CMake ≥ 3.10, wget
- libreadline-dev, python3
- POSIX system (Linux, macOS, \*BSD)

**Makefile.lite** (minimal):
- GCC or Clang (C99), GNU Make, wget
- libreadline-dev
- Linux, macOS, or FreeBSD

```bash
# Debian/Ubuntu (full)
sudo apt install build-essential cmake wget libreadline-dev python3

# Debian/Ubuntu (lite — no cmake or python3)
sudo apt install build-essential wget libreadline-dev

# Alpine (for fully static builds)
apk add build-base cmake wget readline-dev readline-static linux-headers python3
```

### Makefile vs Makefile.lite

If cmake isn't available (minimal HPC nodes, containers, locked-down
environments), use `Makefile.lite`:

```bash
make -f Makefile.lite download
make -f Makefile.lite PREFIX=/opt/lua-regolith all
make -f Makefile.lite PREFIX=/opt/lua-regolith test
make -f Makefile.lite PREFIX=/opt/lua-regolith install
```

Both Makefiles produce **identical install layouts** and are
interchangeable — `make test` validates the same things either way.

| | `Makefile` | `Makefile.lite` |
|---|---|---|
| Build deps | cc, make, cmake, python3 | cc, make |
| libuv build | cmake (auto platform detection) | Direct compilation (manual file list) |
| luv build | cmake | Direct compilation |
| linit.c patch | python3 | sed + tac |
| Platform support | Any (cmake handles it) | Linux, macOS, FreeBSD |

The tradeoff with `Makefile.lite` is that libuv's platform-specific source
file list is maintained in the Makefile rather than discovered by cmake.
The list is stable across libuv 1.4x releases; if you bump to libuv 2.x,
audit it against their `CMakeLists.txt`.

### Configuration Variables

| Variable      | Default      | Purpose                           |
|---------------|--------------|-----------------------------------|
| `PREFIX`      | `/usr/local` | Install location                  |
| `RELOCATABLE` | `0`          | `1` = exe-relative package paths  |
| `LUA_VER`     | `5.4.7`      | Lua version                       |
| `LUAPOSIX_VER`| `36.2.1`     | luaposix version                  |
| `LUV_VER`     | `1.48.0-2`   | luv version                       |
| `LIBUV_VER`   | `1.48.0`     | libuv version                     |
| `LFS_VER`     | `1.9.0`      | luafilesystem version             |
| `LPEG_VER`    | `1.1.0`      | lpeg version                      |
| `LUATERM_VER` | `0.8`        | lua-term version                  |
| `DKJSON_VER`  | `2.8`        | dkjson version                    |

`LUA_SHORT` (e.g. `5.4`) is derived automatically from `LUA_VER` — you
don't need to set it separately.

### Smoke Tests

```bash
make test
```

Tests every module: luaposix (including nested `posix.sys.stat`), luv
(including event loop timer), lfs (dir listing, attributes), lpeg (pattern
matching), lua-term (isatty function), and dkjson (JSON roundtrip).

---

## Version Resilience

The Makefile is designed to survive Lua version bumps (including to 5.5)
without edits beyond changing `LUA_VER`. Three things that commonly break in
version-pinned build systems are handled dynamically:

**1. Source file list** — Instead of hardcoding the list of `.c` files, the
Makefile uses `$(wildcard $(LUA_SRC)/*.c)` and filters out `lua.c` and
`luac.c`. If Lua 5.5 adds or removes source files, they're picked up
automatically.

**2. `luaconf.h` patching** — Instead of `sed`-matching internal formatting
(which changes between releases), the Makefile appends `#undef` / `#define`
overrides to the *end* of `luaconf.h`. The C preprocessor uses the last
definition, so our `LUA_ROOT`, `LUA_PATH_DEFAULT`, and `LUA_CPATH_DEFAULT`
always win, regardless of how the stock file is formatted.

**3. Static interpreter's `linit.c`** — Instead of hardcoding the standard
library opener table (`luaopen_base`, `luaopen_math`, etc.), the Makefile
copies the real `linit.c` from the source tree and patches it with a small
`python3` script (or `sed` in `Makefile.lite`) that inserts the
`preload_bundled_modules()` call before the closing brace of
`luaL_openlibs`. If Lua 5.5 adds a new standard library, it's included
automatically.

**4. Header installation** — All `.h` and `.hpp` files in `src/` are
installed dynamically rather than from a hardcoded list.

**What still needs manual attention** when bumping to a new major Lua
version: the C modules (luaposix, luv, lfs, lpeg, lua-term) must support
that version's C API. Check their release notes.

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
- If you modify `lua-regolith` and run it to provide network access to users
  (e.g., as a service), the AGPL includes obligations related to offering
  the corresponding source code of the version you run.
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
