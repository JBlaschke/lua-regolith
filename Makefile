# SPDX-License-Identifier: AGPL-3.0-or-later
# =============================================================================
# lua-regolith — The foundation layer for your Lua environment
# =============================================================================
#
# https://github.com/JBlaschke/lua-regolith
#
# Builds a self-contained Lua installation with luaposix, luv, lfs,
# lpeg, lua-term, and dkjson.  Suitable for running Lmod, creating
# standalone executables with luastatic, or embedding Lua anywhere.
#
# The Lua source file list, standard library table, and luaconf.h
# patching are all derived dynamically from the extracted source tree.
# You can bump LUA_VER (even to 5.5) and the build adapts automatically.
#
# Usage:
#   make download                            # fetch all source tarballs
#   make verify                              # check SHA-256 checksums
#   make PREFIX=/opt/lua-regolith all        # build everything
#   make PREFIX=/opt/lua-regolith install    # install to prefix
#   make static-lua                          # fully static interpreter
#   make test                                # smoke-test the build
#   make clean / distclean
#
# After install, configure Lmod with:
#   ./configure --prefix=/opt/lmod \
#     --with-lua=/opt/lua-regolith/bin/lua \
#     --with-luac=/opt/lua-regolith/bin/luac
#
# For minimal-dependency builds (no cmake), see Makefile.lite.
#
# =============================================================================

# ---------------------------------------------------------------------------
# Shell and Make configuration
# ---------------------------------------------------------------------------
#
# SHELL := /bin/sh
#   Force POSIX /bin/sh for all recipe lines.  By default, GNU Make uses
#   the value of the SHELL environment variable (or /bin/sh if unset).
#   On macOS, users running fish or zsh can inadvertently break recipes
#   that assume Bourne-shell syntax.  The explicit assignment here
#   guarantees every recipe runs under /bin/sh regardless of the user's
#   login shell.  (Note: Make's SHELL is independent of the environment
#   variable — setting it here does NOT change the user's interactive shell.)
#
# .SUFFIXES:
#   Clear all built-in suffix rules (e.g. .c → .o, .y → .c).  GNU Make
#   ships with ~100 implicit rules that attempt pattern-based compilation.
#   These are unnecessary here (we specify every compilation step explicitly)
#   and can cause confusing behavior when files match a built-in pattern.
#   Clearing the suffix list disables all suffix-based implicit rules.
#
# MAKEFLAGS += --no-builtin-rules
#   Disables ALL implicit rules, including both suffix rules AND pattern
#   rules (like %: %.o).  This is the belt-and-suspenders companion to
#   .SUFFIXES: — together they ensure Make never tries to "help" by
#   compiling something we didn't ask for.  This also speeds up Make
#   slightly, since it skips the implicit rule search for every target.

SHELL := /bin/sh
.SUFFIXES:
MAKEFLAGS += --no-builtin-rules

# =============================================================================
# USER-CONFIGURABLE KNOBS
# =============================================================================
#
# These use the ?= (conditional assignment) operator: the variable is set
# only if it doesn't already have a value.  This means the user can override
# any of them from the command line or environment:
#
#   make PREFIX=/opt/lua CC=clang all
#   CC=clang make all
#   export CC=clang; make all
#
# All three set CC to clang.  Without ?=, the Makefile value would silently
# win over the environment, which is surprising and hard to debug.
#
# RELOCATABLE: when set to 1, the lua binary resolves its own exe path at
#   runtime and computes package.path/package.cpath relative to the install
#   root.  This allows the entire $PREFIX tree to be moved (cp, rsync, tar)
#   without rebuilding.  Default 0 = hardcoded paths (simpler, faster startup).
#
# NPROC: auto-detects the number of CPU cores for parallel builds (-j).
#   Tries Linux nproc first, then macOS/BSD sysctl, then falls back to 4.
#   := (immediate assignment) is used because $(shell ...) is expensive —
#   we want it evaluated once at parse time, not re-evaluated every time
#   NPROC is referenced.

RELOCATABLE ?= 0
PREFIX      ?= /usr/local
CC          ?= gcc
AR          ?= ar
RANLIB      ?= ranlib
CMAKE       ?= cmake
WGET        ?= wget -q
NPROC       := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# =============================================================================
# VERSIONS
# =============================================================================
#
# All version variables use := (immediate/simple assignment).  Unlike =
# (recursive assignment), := expands the right-hand side once at parse time
# and stores the result as a literal string.  This is the right choice for
# constants — it's faster (no re-expansion on each use) and avoids
# accidental circular references.
#
# The ?= vs := distinction matters:
#   ?=  → "set if not already set"       (user can override)
#   :=  → "set unconditionally, expand now"  (constant, not overridable
#          via environment — but still overridable via command line)
#
# Versions are := because letting the environment accidentally override
# e.g. LUA_VER would silently break the build in hard-to-diagnose ways.

LUA_VER       := 5.4.7
LUAPOSIX_VER  := 36.2.1
LUV_VER       := 1.48.0-2
LIBUV_VER     := 1.48.0
LFS_VER       := 1.9.0

# luafilesystem uses underscores in its git tags: version 1.9.0 is tagged
# as "v1_9_0", not "v1.9.0".  We derive both the tag format and the
# directory name (which uses underscores after extraction) using $(subst):
#
# $(subst from,to,text) does global string replacement:
#   $(subst .,_,1.9.0)  →  1_9_0
#
# LFS_TAG adds the "v" prefix for the GitHub download URL.
# LFS_VER_US is the bare underscored version for the directory name.
LFS_TAG       := v$(subst .,_,$(LFS_VER))
LFS_VER_US    := $(subst .,_,$(LFS_VER))

LPEG_VER      := 1.1.0
LUATERM_VER   := 0.8
DKJSON_VER    := 2.8

# ---------------------------------------------------------------------------
# SHA-256 checksums
# ---------------------------------------------------------------------------
#
# Used by the `verify` target to ensure downloaded tarballs haven't been
# tampered with or corrupted in transit.  Set any individual checksum to
# empty to skip verification for that file (useful when testing with a
# new upstream release before the official checksum is published).
#
# These should be updated whenever a version number above changes.
# Confirmed from official upstream announcements / trusted package repos:

LUA_SHA256      := 9fbf5e28ef86c69858f6d3d34eccc32e911c1a28b4120ff3e84aaa70cfbf1e30
LUAPOSIX_SHA256 := 44e5087cd3c47058f9934b90c0017e4cf870b71619f99707dd433074622debb1
LUV_SHA256      := 2c3a1ddfebb4f6550293a40ee789f7122e97647eede51511f57203de48c03b7a
LIBUV_SHA256    := 8c253adb0f800926a6cbd1c6576abae0bc8eb86a4f891049b72f9e5b7dc58f33
LFS_SHA256      := 1142c1876e999b3e28d1c236bf21ffd9b023018e336ac25120fb5373aade1450
LPEG_SHA256     := 4b155d67d2246c1ffa7ad7bc466c1ea899bbc40fef0257cc9c03cecbaed4352a
LUATERM_SHA256  := 0cb270be22dfc262beec2f4ffc66b878ccaf236f537d693fa36c8f578fc51aa6
DKJSON_SHA256   := eb3bf160688fb395a2db6bc52eeff4f7855a6321d2b41bdc754554d13f4e7d44

# =============================================================================
# DERIVED PATHS
# =============================================================================
#
# These are computed from the version variables above.  Nothing here should
# need manual editing when bumping versions — change the version at the top
# and everything cascades.

# ---------------------------------------------------------------------------
# LUA_SHORT — extract major.minor from the full version string
# ---------------------------------------------------------------------------
#
# Lua's directory layout uses "5.4" (not "5.4.7") for paths like
# lib/lua/5.4/ and share/lua/5.4/.  We extract this with sed:
#
#   echo 5.4.7 | sed 's/\([0-9]*\.[0-9]*\).*/\1/'
#
# The regex captures one-or-more digits, a dot, and one-or-more digits
# into group \1, then matches (and discards) everything after.
# Result: "5.4"
#
# This runs inside $(shell ...), which executes a shell command at
# Makefile parse time and captures its stdout.
LUA_SHORT     := $(shell echo $(LUA_VER) | sed 's/\([0-9]*\.[0-9]*\).*/\1/')

# ---------------------------------------------------------------------------
# Source directories and download URLs
# ---------------------------------------------------------------------------
#
# Convention: FOO_DIR is the directory name after tar extraction,
# FOO_URL is the download URL.  These are derived mechanically from
# the version variables so that bumping a version automatically updates
# both the download URL and the expected directory name.

LUA_DIR       := lua-$(LUA_VER)
LUA_URL       := https://www.lua.org/ftp/lua-$(LUA_VER).tar.gz

LUAPOSIX_DIR  := luaposix-$(LUAPOSIX_VER)
LUAPOSIX_URL  := https://github.com/luaposix/luaposix/archive/refs/tags/v$(LUAPOSIX_VER).tar.gz

LUV_DIR       := luv-$(LUV_VER)
LUV_URL       := https://github.com/luvit/luv/releases/download/$(LUV_VER)/luv-$(LUV_VER).tar.gz

LIBUV_DIR     := libuv-$(LIBUV_VER)
LIBUV_URL     := https://github.com/libuv/libuv/archive/refs/tags/v$(LIBUV_VER).tar.gz

# LFS uses the underscored version in its extracted directory name
# (luafilesystem-1_9_0), matching its git tag convention.
LFS_DIR       := luafilesystem-$(LFS_VER_US)
LFS_URL       := https://github.com/lunarmodules/luafilesystem/archive/refs/tags/$(LFS_TAG).tar.gz

LPEG_DIR      := lpeg-$(LPEG_VER)
LPEG_URL      := http://www.inf.puc-rio.br/~roberto/lpeg/lpeg-$(LPEG_VER).tar.gz

LUATERM_DIR   := lua-term-$(LUATERM_VER)
LUATERM_URL   := https://github.com/hoelzro/lua-term/archive/refs/tags/$(LUATERM_VER).tar.gz

# dkjson is distributed as a single .lua file, not a tarball.
DKJSON_FILE   := dkjson-$(DKJSON_VER).lua
DKJSON_URL    := http://dkolf.de/dkjson-lua/dkjson-$(DKJSON_VER).lua

# BUILD — the out-of-tree build directory.
# $(CURDIR) is a built-in Make variable containing the absolute path of
# the directory where Make was invoked (the project root).  Using an
# absolute path here ensures recipes work correctly even when they `cd`
# into subdirectories.
BUILD         := $(CURDIR)/build

# =============================================================================
# COMPILER FLAGS
# =============================================================================
#
# CFLAGS uses ?= so the user can override optimization/warning flags.
#
# LUA_CFLAGS adds Lua-specific defines on top of the user's CFLAGS:
#   -DLUA_USE_POSIX   — use POSIX features (mkstemp, popen, etc.)
#   -DLUA_USE_DLOPEN  — use dlopen() for loading C modules at runtime
#
# SHARED_FLAGS: -fPIC (Position-Independent Code) is required for any
# object file that will be linked into a shared library (.so/.dylib).
# Without it, the linker will reject the objects with a relocation error.
# We compile ALL objects with -fPIC so that the same .o files can be used
# for both static (.a) and shared (.so) libraries.

CFLAGS        ?= -O2 -Wall
LUA_CFLAGS    := $(CFLAGS) -DLUA_USE_POSIX -DLUA_USE_DLOPEN
SHARED_FLAGS  := -fPIC

# =============================================================================
# PLATFORM DETECTION
# =============================================================================
#
# $(shell uname -s) returns the kernel name: "Linux", "Darwin" (macOS),
# "FreeBSD", etc.  We branch on this to set platform-specific variables.
#
# Key platform differences:
#
#   Shared library extension:
#     Linux/BSD: .so       macOS: .dylib
#
#   Shared library linker flag:
#     Linux/BSD: -shared   macOS: -dynamiclib
#
#   Lua link libraries:
#     Linux needs -ldl (for dlopen) and -lreadline (for the REPL).
#     macOS provides dlopen in libSystem (no -ldl needed) and links
#     readline differently.
#
#   Static linking:
#     Linux: -static works (with NSS caveats on glibc).
#     macOS: Apple's linker doesn't support -static for user binaries
#     (it always dynamically links libSystem.B.dylib).
#
#   RPATH: embeds a library search path into the binary so it can find
#   liblua.so at runtime without LD_LIBRARY_PATH.  The syntax is the
#   same on both platforms but the runtime behavior differs slightly.

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  SHARED_EXT    := dylib
  SHARED_LINK   := -dynamiclib
  LDFLAGS_LUA   := -lm
  STATIC_EXTRA  :=
  RPATH_FLAG     = -Wl,-rpath,'$(PREFIX)/lib'
  NM_LUAOPEN_RE := luaopen_
else
  SHARED_EXT    := so
  SHARED_LINK   := -shared
  LDFLAGS_LUA   := -lm -ldl -lreadline -lcrypt
  STATIC_EXTRA  := -static
  RPATH_FLAG     = -Wl,-rpath,'$(PREFIX)/lib'
  NM_LUAOPEN_RE := luaopen_
endif

# ---------------------------------------------------------------------------
# luaposix platform defines
# ---------------------------------------------------------------------------
#
# These mirror what luaposix's own build system (luke) would pass.
# They control which POSIX feature-test macros the system headers expose:
#
#   _BSD_SOURCE / _DEFAULT_SOURCE — BSD extensions (Linux)
#   _POSIX_C_SOURCE=200809L      — POSIX.1-2008 features
#   _XOPEN_SOURCE=700            — X/Open 7 (SUSv4) features
#   _DARWIN_C_SOURCE             — macOS-specific extensions
#   __BSD_VISIBLE                — FreeBSD's equivalent of _BSD_SOURCE
#
# Without these, system headers may hide declarations that luaposix needs
# (e.g., struct sigaction fields, clock_gettime, etc.), causing compile
# errors that look like missing functions but are actually missing macros.

ifeq ($(UNAME_S),Darwin)
  LUAPOSIX_PLAT_DEFS := -D_DARWIN_C_SOURCE
else ifeq ($(UNAME_S),Linux)
  LUAPOSIX_PLAT_DEFS := -D_BSD_SOURCE -D_DEFAULT_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700
else ifeq ($(UNAME_S),FreeBSD)
  LUAPOSIX_PLAT_DEFS := -D__BSD_VISIBLE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700
else
  LUAPOSIX_PLAT_DEFS := -D_POSIX_C_SOURCE=200809L
endif

# ---------------------------------------------------------------------------
# LUA_MOD_EXT — the extension for Lua C modules
# ---------------------------------------------------------------------------
#
# IMPORTANT: Lua C modules are ALWAYS named .so, even on macOS.
#
# This is a common source of confusion.  Native shared libraries on macOS
# use .dylib (liblua.dylib, libluv.dylib), but Lua's package.cpath
# searches for .so on ALL platforms.  This is baked into Lua's source code
# and is the convention followed by every Lua C module in the ecosystem.
#
# So we have two extension variables:
#   SHARED_EXT  — for native shared libraries (.so on Linux, .dylib on macOS)
#   LUA_MOD_EXT — for Lua-loadable C modules (.so everywhere)
LUA_MOD_EXT := so

# =============================================================================
# TOP-LEVEL TARGETS
# =============================================================================
#
# .PHONY declares targets that don't correspond to actual files.  Without
# this, if someone created a file called "all" or "clean" in the project
# directory, Make would see it as up-to-date and skip the recipe.  .PHONY
# tells Make to always run the recipe regardless of filesystem state.
#
# The `all` target lists the module-level phony targets as prerequisites.
# Make builds them left-to-right, but the real ordering comes from the
# dependency graph: each module depends on $(LUA_A) or $(LUA_SO), so
# Lua is always built first regardless of the order listed here.

.PHONY: all install clean distclean download verify test static-lua

all: lua liblua-shared luaposix luv lfs lpeg luaterm dkjson

# The install target depends on `all` (so a bare `make install` builds
# everything first), then runs each module's install sub-target.
# The trailing @echo block prints a summary banner.  The @ prefix
# suppresses Make's default behavior of printing each command before
# executing it — purely cosmetic, since echo output is the message itself.
install: all install-lua install-luaposix install-luv \
         install-lfs install-lpeg install-luaterm install-dkjson \
         install-pkgconfig
	@echo ""
	@echo "================================================================"
	@echo " lua-regolith $(LUA_VER) installed to: $(PREFIX)"
	@echo ""
	@echo " Bundled modules:"
	@echo "   luaposix $(LUAPOSIX_VER)   luv $(LUV_VER)"
	@echo "   lfs $(LFS_VER)          lpeg $(LPEG_VER)"
	@echo "   lua-term $(LUATERM_VER)       dkjson $(DKJSON_VER)"
	@echo ""
	@echo " To build Lmod:"
	@echo "   ./configure --prefix=<lmod-dir> \\"
	@echo "     --with-lua=$(PREFIX)/bin/lua \\"
	@echo "     --with-luac=$(PREFIX)/bin/luac"
	@echo "================================================================"

# =============================================================================
# RELOCATE — recompile lua/luac with a new PREFIX
# =============================================================================
#
# Usage:
#   make relocate PREFIX=/new/path
#   make PREFIX=/new/path install
#
# This is a lightweight alternative to a full rebuild when you just need to
# change the install prefix.  The key insight is that only the Lua core
# (liblua, lua, luac) embeds the PREFIX via luaconf.h — the C modules
# (luaposix, luv, lfs, lpeg, lua-term) don't contain any hardcoded paths,
# so they don't need recompilation.
#
# How it works:
#   1. Strip the existing BUNDLED_LUA_PREFIX_OVERRIDE block from luaconf.h
#      using sed with a range pattern: /start/,/end/d deletes all lines
#      between (and including) the start and end markers.
#   2. Remove stamp files and build artifacts to force recompilation.
#   3. Re-run the lua and liblua-shared targets, which will re-patch
#      luaconf.h with the new PREFIX and recompile.
#
# This is much faster than `make distclean && make all` and is useful when
# moving an existing installation without the overhead of RELOCATABLE=1's
# runtime exe resolution.

relocate: $(LUA_DIR)
	@echo "  Relocating to PREFIX=$(PREFIX) ..."
	@# Strip the existing override block from luaconf.h
	@if grep -q 'BUNDLED_LUA_PREFIX_OVERRIDE' $(LUA_SRC)/luaconf.h; then \
	  sed '/\/\* ---- BUNDLED_LUA_PREFIX_OVERRIDE ----/,/\/\* ---- end BUNDLED_LUA_PREFIX_OVERRIDE ----/d' \
	    $(LUA_SRC)/luaconf.h > $(LUA_SRC)/luaconf.h.new; \
	  mv $(LUA_SRC)/luaconf.h.new $(LUA_SRC)/luaconf.h; \
	fi
	@# Remove build markers to force recompilation of lua core only
	rm -f $(BUILD)/.lua-patched $(BUILD)/lua-obj/.built
	rm -f $(LUA_A) $(LUA_SO) $(LUA_BIN) $(LUAC_BIN)
	@# Rebuild lua core
	$(MAKE) lua liblua-shared
	@echo ""
	@echo "================================================================"
	@echo " Relocated lua-regolith to: $(PREFIX)"
	@echo ""
	@echo " The C modules (luaposix, luv, lfs, lpeg, lua-term) are"
	@echo " unchanged — they don't embed prefix paths."
	@echo ""
	@echo " Run 'make PREFIX=$(PREFIX) install' to install."
	@echo "================================================================"

clean:
	rm -rf $(LUA_DIR) $(LUAPOSIX_DIR) $(LUV_DIR) $(LIBUV_DIR) \
	       $(LFS_DIR) $(LPEG_DIR) $(LUATERM_DIR)
	rm -rf $(BUILD)

# distclean removes everything: build artifacts AND downloaded/extracted sources.
# After distclean, you need `make download` again before building.
distclean: clean
	rm -f lua-$(LUA_VER).tar.gz \
	      luaposix-$(LUAPOSIX_VER).tar.gz \
	      luv-$(LUV_VER).tar.gz \
	      libuv-$(LIBUV_VER).tar.gz \
	      lfs-$(LFS_VER).tar.gz \
	      lpeg-$(LPEG_VER).tar.gz \
	      luaterm-$(LUATERM_VER).tar.gz \
	      $(DKJSON_FILE)

# =============================================================================
# DOWNLOAD + VERIFY
# =============================================================================
#
# The download target depends on all tarball filenames.  Each tarball has
# its own implicit rule below (e.g. lua-5.4.7.tar.gz:).  Make checks
# whether the file exists — if it does, the download is skipped (Make sees
# the target as up-to-date).  If it doesn't, the recipe runs wget.
#
# This means `make download` is idempotent: running it twice only downloads
# files that are missing.

TARBALLS := lua-$(LUA_VER).tar.gz \
            luaposix-$(LUAPOSIX_VER).tar.gz \
            luv-$(LUV_VER).tar.gz \
            libuv-$(LIBUV_VER).tar.gz \
            lfs-$(LFS_VER).tar.gz \
            lpeg-$(LPEG_VER).tar.gz \
            luaterm-$(LUATERM_VER).tar.gz \
            $(DKJSON_FILE)

download: $(TARBALLS)

# Each tarball rule has no prerequisites (the target filename is the only
# thing that matters).  If the file doesn't exist, Make runs the recipe.
# -O $@ writes to the target filename ($@ is Make's automatic variable
# for "the name of the target being built").
lua-$(LUA_VER).tar.gz:
	$(WGET) -O $@ "$(LUA_URL)"

luaposix-$(LUAPOSIX_VER).tar.gz:
	$(WGET) -O $@ "$(LUAPOSIX_URL)"

luv-$(LUV_VER).tar.gz:
	$(WGET) -O $@ "$(LUV_URL)"

libuv-$(LIBUV_VER).tar.gz:
	$(WGET) -O $@ "$(LIBUV_URL)"

lfs-$(LFS_VER).tar.gz:
	$(WGET) -O $@ "$(LFS_URL)"

lpeg-$(LPEG_VER).tar.gz:
	$(WGET) -O $@ "$(LPEG_URL)"

luaterm-$(LUATERM_VER).tar.gz:
	$(WGET) -O $@ "$(LUATERM_URL)"

$(DKJSON_FILE):
	$(WGET) -O $@ "$(DKJSON_URL)"

# ---------------------------------------------------------------------------
# SHA-256 verification
# ---------------------------------------------------------------------------
#
# SHA256_CMD auto-detects the available checksum tool:
#   Linux:  sha256sum (from coreutils)
#   macOS:  shasum -a 256 (from perl, ships with macOS)
#
# $(shell command -v sha256sum 2>/dev/null || echo "shasum -a 256")
#   `command -v` checks whether sha256sum exists in PATH.  If it does,
#   its path is returned.  If not (macOS), the || fallback provides
#   the equivalent macOS command.  2>/dev/null suppresses the "not found"
#   error message.

SHA256_CMD := $(shell command -v sha256sum 2>/dev/null || echo "shasum -a 256")

# The verify target generates a shell script and then runs it.
#
# Why a generated script instead of inline shell?
# Because the verify logic requires shell functions, conditionals, and
# variable tracking (a `failed` counter) that would be extremely fragile
# as multi-line Make recipes due to Make's line-by-line execution model
# (each line runs in a separate shell by default) and the Make 3.81 $$
# escaping bugs documented in the Lua section below.
#
# The script uses a verify_one() function that:
#   1. Skips verification if the expected checksum is empty
#   2. Computes the actual checksum with SHA256_CMD
#   3. Compares expected vs actual, tracking failures
#
# The awk '{print $1}' extracts just the hash (both sha256sum and shasum
# print "hash  filename").  The elaborate single-quote escaping
# ('"'"') is the standard POSIX trick for embedding a literal single
# quote inside a single-quoted string:
#   '  — end the current single-quoted string
#   "'" — a single quote inside double quotes
#   '  — resume the single-quoted string
verify: download
	@mkdir -p $(BUILD)
	@printf '%s\n' '#!/bin/sh' \
	  'failed=0' \
	  'verify_one() {' \
	  '  if [ -z "$$2" ]; then echo "SKIP  $$1 (no checksum)"; return 0; fi' \
	  '  got=$$($(SHA256_CMD) "$$1" | awk '"'"'{print $$1}'"'"')' \
	  '  if [ "$$got" = "$$2" ]; then echo "OK    $$1"' \
	  '  else echo "FAIL  $$1"; echo "  expected: $$2"; echo "  got:      $$got"; return 1; fi' \
	  '}' \
	  'verify_one "lua-$(LUA_VER).tar.gz"           "$(LUA_SHA256)"      || failed=1' \
	  'verify_one "luaposix-$(LUAPOSIX_VER).tar.gz" "$(LUAPOSIX_SHA256)" || failed=1' \
	  'verify_one "luv-$(LUV_VER).tar.gz"           "$(LUV_SHA256)"      || failed=1' \
	  'verify_one "libuv-$(LIBUV_VER).tar.gz"       "$(LIBUV_SHA256)"    || failed=1' \
	  'verify_one "lfs-$(LFS_VER).tar.gz"           "$(LFS_SHA256)"      || failed=1' \
	  'verify_one "lpeg-$(LPEG_VER).tar.gz"         "$(LPEG_SHA256)"     || failed=1' \
	  'verify_one "luaterm-$(LUATERM_VER).tar.gz"   "$(LUATERM_SHA256)"  || failed=1' \
	  'verify_one "$(DKJSON_FILE)"                  "$(DKJSON_SHA256)"   || failed=1' \
	  'if [ $$failed -ne 0 ]; then echo "FAILED"; exit 1; fi' \
	  'echo "All checksums passed."' > $(BUILD)/_verify.sh
	@sh $(BUILD)/_verify.sh

# ---------------------------------------------------------------------------
# Extract tarballs
# ---------------------------------------------------------------------------
#
# Each extraction rule depends on its tarball.  The target is the directory
# name (e.g. lua-5.4.7).  Make checks: does the directory exist?  If yes,
# skip extraction.  If no, extract the tarball.
#
# The `touch $@` at the end updates the directory's timestamp.  This is
# important because tar preserves the original timestamps from the archive,
# which may be older than the tarball file.  Without touch, Make would see
# "directory is older than tarball" and re-extract every time.

$(LUA_DIR): lua-$(LUA_VER).tar.gz
	tar xf $<
	touch $@

$(LUAPOSIX_DIR): luaposix-$(LUAPOSIX_VER).tar.gz
	tar xf $<
	touch $@

$(LUV_DIR): luv-$(LUV_VER).tar.gz
	tar xf $<
	touch $@

$(LIBUV_DIR): libuv-$(LIBUV_VER).tar.gz
	tar xf $<
	touch $@

$(LFS_DIR): lfs-$(LFS_VER).tar.gz
	tar xf $<
	touch $@

$(LPEG_DIR): lpeg-$(LPEG_VER).tar.gz
	tar xf $<
	touch $@

$(LUATERM_DIR): luaterm-$(LUATERM_VER).tar.gz
	tar xf $<
	touch $@

# =============================================================================
# 1. LUA CORE
# =============================================================================
#
# IMPORTANT — macOS / Make 3.81 compatibility notes:
#
# macOS ships GNU Make 3.81 (from 2006!), which has two relevant bugs that
# affect how shell variables are written in recipes.  These bugs are fixed
# in Make 3.82+, but since we need to support macOS out of the box, we
# work around them throughout this Makefile:
#
# BUG 1 — Broken $$ escaping in multi-line recipes:
#
#   In Make, $$ is the escape sequence for a literal $ (needed for shell
#   variables: $$HOME → shell sees $HOME).  In Make 3.81, this escaping
#   breaks when a recipe line is continued with \ (backslash-newline):
#
#     my_rule:
#         for src in *.c; do \          # ← backslash continues the line
#           echo $$src; \               # ← BUG: Make 3.81 parses this as
#         done                          #    $$s + rc, expands $s as empty,
#                                       #    shell sees just "rc"
#
#   Even $${src} doesn't help — Make expands ${src} as a Make variable.
#
#   Workarounds used in this Makefile:
#     a) cd dir && cc -c *.c; mv *.o dest/    (use globs, no shell vars)
#     b) Write helper .sh scripts with printf, using \044 (printf octal
#        escape for $) so shell variables survive Make expansion intact.
#     c) find -exec sh -c '...' _ {} \;  (use positional args $1, no loop var)
#
# BUG 2 — awk '{print $NF}' in generated scripts:
#
#   When building scripts via printf inside a Make recipe, awk's $NF
#   would need $$NF to pass through Make.  But $$NF hits BUG 1 in
#   multi-line recipes.  Solution: replace awk with sed for field
#   extraction: sed 's/.* //' extracts the last field (equivalent to
#   awk '{print $NF}') without any $ characters.

LUA_SRC   := $(LUA_DIR)/src
LUA_A     := $(BUILD)/liblua.a
LUA_SO    := $(BUILD)/liblua.$(SHARED_EXT)
LUA_BIN   := $(BUILD)/lua
LUAC_BIN  := $(BUILD)/luac

# ---------------------------------------------------------------------------
# Patch luaconf.h — hardcode PREFIX into the interpreter
# ---------------------------------------------------------------------------
#
# This is the core mechanism that makes lua-regolith "self-contained":
# the Lua interpreter knows where to find its modules without relying
# on LUA_PATH / LUA_CPATH environment variables.
#
# Instead of using sed to find-and-replace the existing LUA_ROOT definition
# (which would break if Lua's formatting changes between releases), we
# APPEND #undef/#define overrides to the END of luaconf.h.  The C
# preprocessor always uses the last #define, so our values win regardless
# of what the stock file contains.  This is the "version resilience" strategy.
#
# The guard `grep -q 'BUNDLED_LUA_PREFIX_OVERRIDE'` prevents double-patching
# if the target is re-run (e.g., after a failed build).
#
# Stamp file pattern: $(BUILD)/.lua-patched
#   Make needs a file to track "has this been done?"  Since the actual
#   output (a modified luaconf.h) is in-place and not a new file, we
#   create an empty "stamp" file.  Make checks: does .lua-patched exist
#   and is it newer than its prerequisites?  If yes, skip the recipe.
#   `touch $@` creates/updates the stamp file after successful patching.
#
# The \ at the end of lines continues a single shell command across
# multiple lines.  The entire if/fi block runs as one shell invocation.

$(BUILD)/.lua-patched: $(LUA_DIR)
	@mkdir -p $(BUILD)
	@if ! grep -q 'BUNDLED_LUA_PREFIX_OVERRIDE' $(LUA_SRC)/luaconf.h; then \
	  { \
	    echo ''; \
	    echo '/* ---- BUNDLED_LUA_PREFIX_OVERRIDE ---- */'; \
	    echo '/* Appended by lua-regolith Makefile. */'; \
	    echo ''; \
	    echo '#ifdef LUA_ROOT'; \
	    echo '#undef LUA_ROOT'; \
	    echo '#endif'; \
	    echo '#define LUA_ROOT "$(PREFIX)/"'; \
	    echo ''; \
	    echo '#ifdef LUA_LDIR'; \
	    echo '#undef LUA_LDIR'; \
	    echo '#endif'; \
	    echo '#define LUA_LDIR LUA_ROOT "share/lua/$(LUA_SHORT)/"'; \
	    echo ''; \
	    echo '#ifdef LUA_CDIR'; \
	    echo '#undef LUA_CDIR'; \
	    echo '#endif'; \
	    echo '#define LUA_CDIR LUA_ROOT "lib/lua/$(LUA_SHORT)/"'; \
	    echo ''; \
	    echo '#ifdef LUA_PATH_DEFAULT'; \
	    echo '#undef LUA_PATH_DEFAULT'; \
	    echo '#endif'; \
	    echo '#define LUA_PATH_DEFAULT LUA_LDIR"?.lua;"LUA_LDIR"?/init.lua;"LUA_CDIR"?.lua;"LUA_CDIR"?/init.lua;""./?.lua;./?/init.lua"'; \
	    echo ''; \
	    echo '#ifdef LUA_CPATH_DEFAULT'; \
	    echo '#undef LUA_CPATH_DEFAULT'; \
	    echo '#endif'; \
	    echo '#define LUA_CPATH_DEFAULT LUA_CDIR"?.$(LUA_MOD_EXT);"LUA_CDIR"loadall.$(LUA_MOD_EXT);""./?.$(LUA_MOD_EXT)"'; \
	    echo ''; \
	    echo '/* ---- end BUNDLED_LUA_PREFIX_OVERRIDE ---- */'; \
	  } >> $(LUA_SRC)/luaconf.h; \
	fi
	touch $@

# ---------------------------------------------------------------------------
# Compile all Lua core .c files into object files
# ---------------------------------------------------------------------------
#
# Strategy: cd into the source directory, compile everything with a glob
# (*.c), move all .o files to our build directory, then remove lua.o and
# luac.o.  This is the "version resilience" approach: if Lua 5.5 adds or
# removes source files, the glob picks them up automatically.
#
# Why remove lua.o and luac.o?  These contain main() functions for the
# lua and luac executables respectively.  They can't go into liblua.a
# (which is the Lua runtime library) or you'd get duplicate main() errors
# when linking any program against it.  The executables are compiled
# separately below.
#
# The `cd dir && cc -c *.c` pattern avoids shell loop variables, which
# would require $$ escaping and hit the Make 3.81 bug on macOS.

$(BUILD)/lua-obj/.built: $(BUILD)/.lua-patched
	@mkdir -p $(BUILD)/lua-obj
	cd $(LUA_SRC) && $(CC) $(LUA_CFLAGS) $(SHARED_FLAGS) -c *.c
	mv $(LUA_SRC)/*.o $(BUILD)/lua-obj/
	rm -f $(BUILD)/lua-obj/lua.o $(BUILD)/lua-obj/luac.o
	@touch $@

# ---------------------------------------------------------------------------
# Build liblua.a (static library)
# ---------------------------------------------------------------------------
#
# $(AR) rcs $@ $(BUILD)/lua-obj/*.o
#   ar is the archiver — it bundles .o files into a .a (static library).
#   Flags:
#     r — replace or insert files into the archive
#     c — create the archive if it doesn't exist (suppress warning)
#     s — write an index (equivalent to running ranlib afterward)
#
# $(RANLIB) $@
#   Regenerate the archive's symbol index.  Technically redundant with
#   the 's' flag above, but some older toolchains need an explicit ranlib.
#   It's harmless on modern systems and ensures portability.

$(LUA_A): $(BUILD)/lua-obj/.built
	$(AR) rcs $@ $(BUILD)/lua-obj/*.o
	$(RANLIB) $@

# ---------------------------------------------------------------------------
# Build liblua.so / liblua.dylib (shared library)
# ---------------------------------------------------------------------------
#
# The shared library is used by the lua binary (linked via -llua) and by
# all C module .so files.  Using a shared liblua avoids duplicating the
# entire Lua runtime in every module.

$(LUA_SO): $(BUILD)/lua-obj/.built
	$(CC) $(SHARED_LINK) -o $@ $(BUILD)/lua-obj/*.o $(LDFLAGS_LUA)

# ---------------------------------------------------------------------------
# Relocatable support (RELOCATABLE=1)
# ---------------------------------------------------------------------------
#
# When RELOCATABLE=1, the lua binary resolves its own exe path at startup and
# computes package.path / package.cpath relative to the install root. This
# allows the entire prefix to be moved (cp -a, rsync, tar) without rebuilding.
#
# How it works:
#
#   1. lua.c is copied and patched: a call to lr_set_relocatable_paths(L)
#      is inserted immediately after luaL_openlibs(L) in pmain().
#
#   2. src/lr_relocatable.c is compiled and linked into the binary.  It uses
#      platform-specific APIs (readlink /proc/self/exe on Linux,
#      _NSGetExecutablePath on macOS, sysctl on FreeBSD) to find the exe's
#      real path, strips two directory levels to get the prefix, and sets
#      package.path / package.cpath.
#
#   3. luaconf.h is still patched with the build-time PREFIX (as usual). These
#      serve as fallback defaults for liblua embedders and for luac, which
#      doesn't get the relocatable treatment.
#
# When RELOCATABLE=0 (default), lua.c is compiled directly from the source tree
# with no modifications — identical to the original behavior.
#
# ifeq / else / endif is GNU Make's conditional syntax.  It's evaluated at
# parse time (not build time), so only one branch's rules are ever defined.

ifeq ($(RELOCATABLE),1)

# Patch lua.c: insert lr_set_relocatable_paths(L) after luaL_openlibs(L)
#
# awk '{print} /pattern/{print "extra"}' prints every line, and additionally
# prints "extra" after any line matching the pattern.  This inserts the
# function call right after the luaL_openlibs(L) line.
$(BUILD)/relocatable/lua.c: $(BUILD)/.lua-patched
	@mkdir -p $(BUILD)/relocatable
	awk '{print} /luaL_openlibs\(L\)/{print "  lr_set_relocatable_paths(L);"}' \
	  $(LUA_SRC)/lua.c > $@

# Compile the relocatable path-resolution module
#
# -DLR_LUA_SHORT='"$(LUA_SHORT)"' passes the Lua version as a string literal
# to the C code.  The outer double quotes are consumed by the shell; the
# inner single quotes become the C string delimiters.  The C code sees:
#   #define LR_LUA_SHORT "5.4"
$(BUILD)/relocatable/lr_relocatable.o: src/lr_relocatable.c src/lr_relocatable.h $(LUA_DIR)
	@mkdir -p $(BUILD)/relocatable
	$(CC) $(LUA_CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) -Isrc \
	  -DLR_LUA_SHORT='"$(LUA_SHORT)"' \
	  -c -o $@ $<

# Build lua binary with exe-relative path resolution
#
# -include src/lr_relocatable.h — force-includes the header before any
# source code.  This makes the lr_set_relocatable_paths() declaration
# visible to lua.c without modifying lua.c's #include directives.
#
# -Wl,-rpath,$(BUILD) — embed the build directory as an RPATH so the
# binary can find liblua.so during development/testing (before install).
# $(RPATH_FLAG) adds the install-time RPATH ($(PREFIX)/lib) as well.
$(LUA_BIN): $(BUILD)/relocatable/lua.c $(BUILD)/relocatable/lr_relocatable.o $(LUA_SO)
	$(CC) $(LUA_CFLAGS) -I$(LUA_SRC) -Isrc \
	  -include src/lr_relocatable.h \
	  -DLR_LUA_SHORT='"$(LUA_SHORT)"' \
	  -o $@ $(BUILD)/relocatable/lua.c $(BUILD)/relocatable/lr_relocatable.o \
	  -L$(BUILD) -llua $(LDFLAGS_LUA) \
	  -Wl,-rpath,$(BUILD) $(RPATH_FLAG)

else

# Default: build lua directly from source (hardcoded paths from luaconf.h).
#
# $< is Make's automatic variable for "the first prerequisite" — here,
# $(LUA_SRC)/lua.c.  Using $< instead of repeating the path keeps the
# recipe DRY and ensures it stays correct if the prerequisite changes.
#
# -L$(BUILD) -llua — link against liblua.so in the build directory.
# The linker searches -L paths for libraries named lib<name>.so.
$(LUA_BIN): $(LUA_SRC)/lua.c $(LUA_SO)
	$(CC) $(LUA_CFLAGS) -I$(LUA_SRC) -o $@ $< \
	  -L$(BUILD) -llua $(LDFLAGS_LUA) \
	  -Wl,-rpath,$(BUILD) $(RPATH_FLAG)

endif

# luac (the Lua compiler) is always statically linked against liblua.a.
# It doesn't need the shared library or relocatable paths — it's a
# simple offline tool that compiles .lua files to bytecode.
$(LUAC_BIN): $(LUA_SRC)/luac.c $(LUA_A)
	$(CC) $(LUA_CFLAGS) -I$(LUA_SRC) -o $@ $< $(LUA_A) $(LDFLAGS_LUA)

# Phony convenience targets that group related build products.
# `lua` builds the static lib + both executables.
# `liblua-shared` builds just the shared library.
.PHONY: lua liblua-shared
lua: $(LUA_A) $(LUA_BIN) $(LUAC_BIN)
liblua-shared: $(LUA_SO)

# =============================================================================
# 2. LUAPOSIX
# =============================================================================

# ---------------------------------------------------------------------------
# luaposix feature detection
# ---------------------------------------------------------------------------
#
# luaposix guards several modules behind HAVE_* preprocessor macros that its
# own build system (luke) would normally define.  Since we compile directly
# from source, we run small compile-and-link tests instead — same idea as
# autoconf's AC_CHECK_HEADERS / AC_CHECK_FUNCS, zero dependencies beyond cc.
#
# How it works:
#
#   Header probes: compile a file that #includes the header in question. If
#   cc succeeds, the header exists and we emit: #define HAVE_<header> 1.
#
#   Function probes: compile+link a file that calls the function.  The probe
#   tries linking with -lcrypt first (needed for crypt(3) on some systems),
#   then without.  If either succeeds, we emit #define HAVE_<fn> 1.
#
#   Both use the same colon-delimited format for compactness:
#     'name:MACRO:header:body'
#
#   The fields are parsed with POSIX shell parameter expansion operators:
#
#     ${var%%pattern}  — delete the LONGEST match of pattern from the END
#     ${var#pattern}   — delete the SHORTEST match of pattern from the START
#
#   These are applied repeatedly to peel off one field at a time:
#
#     pair='clock_gettime:HAVE_CLOCK_GETTIME:time.h:struct timespec ts; ...'
#     func=${pair%%:*}               → 'clock_gettime'
#       (delete longest :* from end → everything up to first colon)
#     rest=${pair#*:}                → 'HAVE_CLOCK_GETTIME:time.h:struct timespec ts; ...'
#       (delete shortest *: from start → everything after first colon)
#     macro=${rest%%:*}              → 'HAVE_CLOCK_GETTIME'
#     rest=${rest#*:}                → 'time.h:struct timespec ts; ...'
#     hdr=${rest%%:*}                → 'time.h'
#     body=${rest#*:}                → 'struct timespec ts; clock_gettime(0, &ts)'
#
#   (Header probes only need two fields — name:MACRO — so they use a single
#   ${pair%%:*} / ${pair#*:} split.)
#
#   The do block then builds a minimal C program from $hdr and $body:
#
#     #include <time.h>
#     int main(void) { struct timespec ts; clock_gettime(0, &ts); return 0; }
#
#   and tries to compile+link it.  If cc succeeds (exit 0), the feature exists
#   on this platform and we append  #define HAVE_CLOCK_GETTIME 1 to the config
#   header.  If cc fails, we skip it — luaposix will simply not register that
#   function.
#
# The results are written to $(BUILD)/luaposix-config.h, which is
# force-included (via -include) into every luaposix compilation unit.
# Because -include is processed before the source file's own #includes,
# the HAVE_* macros are visible to every guard in luaposix.
#
# macOS _POSIX_TIMERS fixup:
#
#   luaposix gates clock_gettime behind:
#     #if defined _POSIX_TIMERS && _POSIX_TIMERS != -1
#
#   macOS <unistd.h> unconditionally defines _POSIX_TIMERS as -1 because it
#   lacks the full POSIX timers API (timer_create, etc.), even though
#   clock_gettime itself has worked since macOS 10.12. Simply defining
#   _POSIX_TIMERS in the config header doesn't help — when the source file
#   later does #include <unistd.h>, the system header redefines it to -1,
#   clobbering our value.
#
#   The fix: the config header itself #includes <unistd.h>, consuming the
#   include guard.  It then checks whether _POSIX_TIMERS was set to -1 and our
#   HAVE_CLOCK_GETTIME probe passed; if so, it #undefs _POSIX_TIMERS and
#   redefines it to 200809L.  When the source file later includes <unistd.h>
#   again, the include guard makes it a no-op, so our override sticks.

LUAPOSIX_CONFIG_H := $(BUILD)/luaposix-config.h

$(LUAPOSIX_CONFIG_H): $(LUA_DIR)
	@mkdir -p $(BUILD)
	@echo "  luaposix: detecting platform features..."
	@printf '/* Auto-generated by lua-regolith feature detection */\n' > $@
	@# --- Header probes ---
	@# Each entry is 'header:MACRO'.  The for loop iterates over the
	@# single-quoted strings; the shell sees them as literal tokens
	@# (the semicolon-backslash at the end continues the for loop body
	@# across multiple Make recipe lines, which are joined into one shell).
	@for pair in \
	  'sys/statvfs.h:HAVE_SYS_STATVFS_H' \
	  'crypt.h:HAVE_CRYPT_H' \
	  'net/if.h:HAVE_NET_IF_H' \
	  'linux/netlink.h:HAVE_LINUX_NETLINK_H' \
	  'linux/if_packet.h:HAVE_LINUX_IF_PACKET_H' \
	; do \
	  hdr=$${pair%%:*}; macro=$${pair#*:}; \
	  printf '#include <%s>\nint main(void){return 0;}\n' "$$hdr" \
	    > $(BUILD)/_probe.c; \
	  if $(CC) $(CFLAGS) -o $(BUILD)/_probe $(BUILD)/_probe.c 2>/dev/null; then \
	    printf '#define %s 1\n' "$$macro" >> $@; \
	    echo "    $$macro = yes  ($$hdr)"; \
	  else \
	    echo "    $$macro = no   ($$hdr)"; \
	  fi; \
	done
	@# --- Function probes (compile + link) ---
	@# Each entry is 'function:MACRO:header:body'.  The probe tries with
	@# -lcrypt first (needed for crypt(3) on glibc), then without it.
	@# The || (OR) between the two cc invocations means: if the first
	@# fails, try the second.  If either succeeds, the feature is available.
	@for pair in \
	  'statvfs:HAVE_STATVFS:sys/statvfs.h:struct statvfs buf; statvfs("/", &buf)' \
	  'crypt:HAVE_CRYPT:unistd.h:crypt("x","ab")' \
	  'copy_file_range:HAVE_COPY_FILE_RANGE:unistd.h:copy_file_range(0,0,1,0,1,0)' \
	  'posix_fadvise:HAVE_POSIX_FADVISE:fcntl.h:posix_fadvise(0,0,0,0)' \
	  'fdatasync:HAVE_DECL_FDATASYNC:unistd.h:fdatasync(0)' \
	  'clock_gettime:HAVE_CLOCK_GETTIME:time.h:struct timespec ts; clock_gettime(0, &ts)' \
	; do \
	  func=$${pair%%:*}; rest=$${pair#*:}; \
	  macro=$${rest%%:*}; rest=$${rest#*:}; \
	  hdr=$${rest%%:*}; body=$${rest#*:}; \
	  printf '#include <%s>\nint main(void){%s;return 0;}\n' "$$hdr" "$$body" \
	    > $(BUILD)/_probe.c; \
	  if $(CC) $(CFLAGS) -o $(BUILD)/_probe $(BUILD)/_probe.c -lcrypt 2>/dev/null \
	  || $(CC) $(CFLAGS) -o $(BUILD)/_probe $(BUILD)/_probe.c 2>/dev/null; then \
	    printf '#define %s 1\n' "$$macro" >> $@; \
	    echo "    $$macro = yes  ($$func)"; \
	  else \
	    echo "    $$macro = no   ($$func)"; \
	  fi; \
	done
	@rm -f $(BUILD)/_probe.c $(BUILD)/_probe
	@# --- macOS _POSIX_TIMERS fixup ---
	@# See the detailed explanation in the comment block above this rule.
	@printf '\n/* macOS _POSIX_TIMERS fixup */\n' >> $@
	@printf '#include <unistd.h>\n' >> $@
	@printf '#if defined(HAVE_CLOCK_GETTIME) && defined(_POSIX_TIMERS) && _POSIX_TIMERS == -1\n' >> $@
	@printf '#undef _POSIX_TIMERS\n' >> $@
	@printf '#define _POSIX_TIMERS 200809L\n' >> $@
	@printf '#endif\n' >> $@
	@echo "  wrote $@"

# ---------------------------------------------------------------------------
# Compile luaposix
# ---------------------------------------------------------------------------
#
# LUAPOSIX_INC — the include flags passed to every luaposix compilation.
#
# -include $(LUAPOSIX_CONFIG_H)
#   Force-include the generated config header.  -include is a GCC/Clang
#   extension that acts as if the file were #included at the very top of
#   every source file, before any of its own #include directives.  This
#   is how the HAVE_* macros become visible to luaposix's code.
#
# -include net/if.h
#   Belt-and-suspenders: some luaposix files reference IFNAMSIZ (a constant
#   from <net/if.h>) without guarding the include behind HAVE_NET_IF_H.
#   Force-including it ensures the constant is always defined when the
#   header exists.  On systems where it doesn't exist, the header probe
#   already failed and this -include is harmless (cc silently ignores
#   missing -include files).
#
# -DPACKAGE / -DVERSION — luaposix expects these to be set by its build
#   system.  Without them, some modules fail to compile.

LUAPOSIX_INC := -I$(CURDIR)/$(LUA_SRC) \
	-I$(CURDIR)/$(LUAPOSIX_DIR)/ext/include \
	-I$(CURDIR)/$(LUAPOSIX_DIR)/ext/posix \
	-include $(LUAPOSIX_CONFIG_H) \
	-include net/if.h \
	$(LUAPOSIX_PLAT_DEFS) \
	-DPACKAGE='"luaposix"' -DVERSION='"$(LUAPOSIX_VER)"'

# Shorthand for the full command to compile a luaposix .so from source.
# This is a recursively-expanded variable (= not :=) so that it picks up
# any changes to its component variables if they're overridden later.
LUAPOSIX_SO_CMD = $(CC) $(SHARED_LINK) $(CFLAGS) $(SHARED_FLAGS) \
	$(LUAPOSIX_INC) -L$(BUILD) -llua $(LDFLAGS_LUA)

# Compile top-level C files (ext/posix/*.c) and sub-directory files
# (ext/posix/sys/*.c) separately, into the same build tree.
# Uses the cd+glob pattern to avoid shell loop variables.
$(BUILD)/luaposix-obj/.built-top: $(LUA_A) $(LUAPOSIX_DIR) $(LUAPOSIX_CONFIG_H)
	@mkdir -p $(BUILD)/luaposix-obj
	cd $(LUAPOSIX_DIR)/ext/posix && $(CC) $(CFLAGS) $(SHARED_FLAGS) \
	  $(LUAPOSIX_INC) -c *.c
	mv $(LUAPOSIX_DIR)/ext/posix/*.o $(BUILD)/luaposix-obj/
	@touch $@

$(BUILD)/luaposix-obj/.built-sys: $(LUA_A) $(LUAPOSIX_DIR) $(LUAPOSIX_CONFIG_H)
	@mkdir -p $(BUILD)/luaposix-obj/sys
	cd $(LUAPOSIX_DIR)/ext/posix/sys && $(CC) $(CFLAGS) $(SHARED_FLAGS) \
	  $(LUAPOSIX_INC) -c *.c
	mv $(LUAPOSIX_DIR)/ext/posix/sys/*.o $(BUILD)/luaposix-obj/sys/
	@touch $@

# Convenience stamp: both top-level and sys/ objects are built.
$(BUILD)/luaposix-obj/.built: $(BUILD)/luaposix-obj/.built-top $(BUILD)/luaposix-obj/.built-sys
	@touch $@

# ---------------------------------------------------------------------------
# Build libluaposix.a (static archive)
# ---------------------------------------------------------------------------
#
# IMPORTANT: we exclude posix.o from the archive.
#
# posix.o is the "monolithic convenience module" — it re-exports every
# luaopen_* symbol that the individual submodule .o files already define.
# Including it would cause "duplicate symbol" errors at link time.
#
# The top-level require("posix") is handled by the pure-Lua
# posix/init.lua instead, which lazy-loads submodules on demand.
#
# `find ... | sort | xargs $(AR) rcs $@`
#   find: recursively locates all .o files, excluding posix.o
#   sort: ensures deterministic archive ordering (reproducible builds)
#   xargs: passes the file list as arguments to ar (handles large lists)

$(BUILD)/libluaposix.a: $(BUILD)/luaposix-obj/.built
	rm -f $@
	find $(BUILD)/luaposix-obj -name '*.o' ! -name 'posix.o' | sort | xargs $(AR) rcs $@
	$(RANLIB) $@

# ---------------------------------------------------------------------------
# Build luaposix .so modules via a generated helper script
# ---------------------------------------------------------------------------
#
# luaposix has many submodules (posix.unistd, posix.sys.stat, posix.errno,
# etc.), each of which needs to be installed as a separate .so file in the
# correct directory hierarchy.  The mapping from .o file to .so path is
# derived from the luaopen_* symbol exported by each .o:
#
#   posix_unistd.o  exports  luaopen_posix_unistd  →  posix/unistd.so
#   posix_sys_stat.o exports luaopen_posix_sys_stat → posix/sys/stat.so
#
# The script does this for each .o file:
#   1. Run `nm -g` to find the luaopen_* symbol (the T flag = text/code)
#   2. Strip the "luaopen_" prefix
#   3. Replace underscores with slashes to get the relative path
#   4. Create the directory and link the .so
#
# --- Why a generated script? ---
#
# This logic requires shell variables in a loop, which hits the Make 3.81
# $$ escaping bug (see BUG 1 above).  The solution: use printf with the
# \044 octal escape for $.
#
# \044 is the octal representation of the ASCII dollar sign ($).  When
# printf processes the format string, it converts \044 → $.  This works
# because:
#   1. Make sees \044 as literal text (no $ to expand)
#   2. The shell's printf built-in interprets \044 as an octal escape
#   3. The resulting script file contains actual $ characters
#
# For example:
#   printf '  sym=\044(nm -g ...)\n' >> script.sh
# Make sees: printf '  sym=\044(nm -g ...)\n'  (no $ to expand)
# Shell runs: printf '  sym=\044(nm -g ...)\n'
# printf outputs: sym=$(nm -g ...)
# The script file now contains a valid shell command.
#
# sed 's/.* //' — extracts the last space-delimited field from nm output.
# This replaces awk '{print $NF}' which would need $NF in the generated
# script, requiring \044NF, but more importantly the original codebase
# avoids awk entirely in generated scripts to stay safe from BUG 2.
#
# sed 's/^_//' — strip leading underscore from symbols on macOS.
# macOS's linker prepends _ to all C symbols (luaopen_posix_unistd
# becomes _luaopen_posix_unistd in the object file).
#
# Each @printf is a separate recipe line (each @ suppresses the echo of
# that line).  This also sidesteps the Make 3.81 multi-line $$ bug,
# though \044 would be safe regardless.

$(BUILD)/luaposix-so/.built: $(BUILD)/luaposix-obj/.built
	@mkdir -p $(BUILD)/luaposix-so
	@printf '#!/bin/sh\nset -e\n' > $(BUILD)/_build_posix_so.sh
	@printf 'find %s/luaposix-obj -name "*.o" | while read obj; do\n' '$(BUILD)' >> $(BUILD)/_build_posix_so.sh
	@printf '  sym=\044(nm -g "\044obj" 2>/dev/null | grep " T.*luaopen_" | head -1 | sed '"'"'s/.* //;s/^_//'"'"')\n' >> $(BUILD)/_build_posix_so.sh
	@printf '  if [ -z "\044sym" ]; then continue; fi\n' >> $(BUILD)/_build_posix_so.sh
	@printf '  relpath=\044(echo "\044sym" | sed '"'"'s/^luaopen_//;s|_|/|g'"'"')\n' >> $(BUILD)/_build_posix_so.sh
	@printf '  dir=\044(dirname "\044relpath")\n' >> $(BUILD)/_build_posix_so.sh
	@printf '  mkdir -p "%s/luaposix-so/\044dir"\n' '$(BUILD)' >> $(BUILD)/_build_posix_so.sh
	@printf '  %s %s -o "%s/luaposix-so/\044{relpath}.%s" "\044obj" -L%s -llua %s\n' '$(CC)' '$(SHARED_LINK)' '$(BUILD)' '$(LUA_MOD_EXT)' '$(BUILD)' '$(LDFLAGS_LUA)' >> $(BUILD)/_build_posix_so.sh
	@printf 'done\n' >> $(BUILD)/_build_posix_so.sh
	@sh $(BUILD)/_build_posix_so.sh
	@touch $@

.PHONY: luaposix
luaposix: $(BUILD)/libluaposix.a $(BUILD)/luaposix-so/.built $(LUA_SO)

# =============================================================================
# 3. LIBUV + LUV
# =============================================================================
#
# libuv (the async I/O library) and luv (its Lua bindings) are built together.
#
# Strategy: instead of building libuv separately and then pointing luv at it,
# we symlink the extracted libuv source tree into luv's deps/ directory.
# luv's CMakeLists.txt is designed to find and build libuv from deps/libuv/
# when it's present, which avoids a separate cmake invocation and ensures
# the two are compiled with compatible flags.
#
# After luv's build completes, we extract libuv.a from luv's build tree
# for use by the static interpreter and for install.

LUV_BUILD   := $(BUILD)/luv-build
LIBUV_A     := $(BUILD)/libluv_libuv.a

# Create the symlink.  ln -sf creates a symbolic link, overwriting any
# existing one (-f = force).  $(CURDIR) is needed because the symlink
# target must be an absolute path (relative symlinks from inside deps/
# would break if the working directory changes).
$(LUV_DIR)/.libuv-linked: $(LUV_DIR) $(LIBUV_DIR)
	mkdir -p $(LUV_DIR)/deps
	rm -rf $(LUV_DIR)/deps/libuv
	ln -sf $(CURDIR)/$(LIBUV_DIR) $(LUV_DIR)/deps/libuv
	touch $@

# ---------------------------------------------------------------------------
# Build libluv.a (static) — also builds libuv as a side effect
# ---------------------------------------------------------------------------
#
# CMake flags explained:
#   -DCMAKE_C_FLAGS="$(CFLAGS) $(SHARED_FLAGS)"
#     Pass our CFLAGS and -fPIC through to cmake's compiler invocations.
#
#   -DWITH_LUA_ENGINE=Lua
#     Tell luv to use standard Lua (not LuaJIT).
#
#   -DLUA_BUILD_TYPE=System
#     Tell luv not to try building Lua itself — use our pre-built one.
#
#   -DLUA_INCLUDE_DIR / -DLUA_LIBRARY
#     Point luv at our Lua headers and static library.
#
#   -DBUILD_MODULE=OFF / -DBUILD_SHARED_LIBS=OFF / -DBUILD_STATIC_LIBS=ON
#     Build only the static library, not the shared .so module.
#     (The shared module is built separately below with different flags.)
#
# After cmake builds, we use `find` to locate the output files because
# cmake's output directory structure varies by platform and version.
# The `|| { echo ERROR; ... exit 1; }` pattern provides clear error
# messages if the expected files aren't found.
#
# The libuv.a extraction uses a temp file (_libuv_a_path) and sh -c to
# work around the Make 3.81 $$ bug — the shell variable $p is only used
# inside the sh -c invocation, never in a Make recipe line.

$(BUILD)/libluv.a: $(LUA_A) $(LUV_DIR)/.libuv-linked
	@mkdir -p $(LUV_BUILD)
	cd $(LUV_BUILD) && $(CMAKE) \
	  -DCMAKE_C_FLAGS="$(CFLAGS) $(SHARED_FLAGS)" \
	  -DCMAKE_BUILD_TYPE=Release \
	  -DWITH_LUA_ENGINE=Lua \
	  -DLUA_BUILD_TYPE=System \
	  -DLUA_INCLUDE_DIR=$(CURDIR)/$(LUA_SRC) \
	  -DLUA_LIBRARY=$(LUA_A) \
	  -DBUILD_MODULE=OFF \
	  -DBUILD_SHARED_LIBS=OFF \
	  -DBUILD_STATIC_LIBS=ON \
	  $(CURDIR)/$(LUV_DIR)
	$(MAKE) -C $(LUV_BUILD) -j$(NPROC)
	@# Copy libluv.a — use find -exec to avoid shell variable issues
	find $(LUV_BUILD) -maxdepth 2 -name 'libluv*.a' -exec cp {} $@ \;
	@test -f $@ || { echo "ERROR: libluv.a not found"; find $(LUV_BUILD) -name '*.a'; exit 1; }
	@# Extract libuv.a from luv's own build for the static interpreter + install
	find $(LUV_BUILD) -name 'libuv.a' -o -name 'libuv_a.a' | head -1 \
	  > $(BUILD)/_libuv_a_path
	@sh -c 'p=$$(cat $(BUILD)/_libuv_a_path); \
	  if [ -n "$$p" ]; then cp "$$p" $(LIBUV_A); \
	  else echo "ERROR: libuv.a not found in luv build tree"; \
	       find $(LUV_BUILD) -name "*.a"; exit 1; fi'

# ---------------------------------------------------------------------------
# Build luv.so (shared module) and libluv.so (shared library)
# ---------------------------------------------------------------------------
#
# Built in a separate cmake directory (shared/) to avoid conflicts with
# the static build above.  This time BUILD_MODULE=ON and BUILD_SHARED_LIBS=ON.
#
# Note: we link against $(LUA_SO) (shared liblua) here, not $(LUA_A).
# Shared modules must link against the shared library to avoid symbol
# duplication at runtime.

$(BUILD)/luv.$(LUA_MOD_EXT): $(BUILD)/libluv.a $(LUA_SO)
	@mkdir -p $(LUV_BUILD)/shared
	cd $(LUV_BUILD)/shared && $(CMAKE) \
	  -DCMAKE_C_FLAGS="$(CFLAGS) $(SHARED_FLAGS)" \
	  -DCMAKE_BUILD_TYPE=Release \
	  -DWITH_LUA_ENGINE=Lua \
	  -DLUA_BUILD_TYPE=System \
	  -DLUA_INCLUDE_DIR=$(CURDIR)/$(LUA_SRC) \
	  -DLUA_LIBRARY=$(LUA_SO) \
	  -DBUILD_MODULE=ON \
	  -DBUILD_SHARED_LIBS=ON \
	  $(CURDIR)/$(LUV_DIR)
	$(MAKE) -C $(LUV_BUILD)/shared -j$(NPROC)
	@# luv's Lua module is always named luv.so regardless of platform
	@# (see LUA_MOD_EXT discussion above)
	find $(LUV_BUILD)/shared -name 'luv.so' -exec cp {} $@ \;
	@test -f $@ || { echo "ERROR: luv.so not found"; \
	  find $(LUV_BUILD)/shared -name '*.so' -o -name '*.dylib'; exit 1; }

$(BUILD)/libluv.$(SHARED_EXT): $(BUILD)/luv.$(LUA_MOD_EXT)
	find $(LUV_BUILD)/shared -name 'libluv.$(SHARED_EXT)' -exec cp {} $@ \;
	@test -f $@ || { echo "ERROR: libluv.$(SHARED_EXT) not found"; \
	  find $(LUV_BUILD)/shared -name 'libluv*'; exit 1; }

.PHONY: luv
luv: $(BUILD)/libluv.a $(BUILD)/luv.$(LUA_MOD_EXT) $(BUILD)/libluv.$(SHARED_EXT)

# =============================================================================
# 4. LUAFILESYSTEM (lfs)
# =============================================================================
#
# The simplest C module — a single source file (lfs.c) that compiles to
# one object, which becomes both a static lib and a shared module.

$(BUILD)/lfs-obj/lfs.o: $(LFS_DIR) $(LUA_A)
	@mkdir -p $(BUILD)/lfs-obj
	$(CC) $(CFLAGS) $(SHARED_FLAGS) \
	  -I$(LUA_SRC) -I$(LFS_DIR)/src \
	  -c -o $@ $(LFS_DIR)/src/lfs.c

$(BUILD)/liblfs.a: $(BUILD)/lfs-obj/lfs.o
	$(AR) rcs $@ $<
	$(RANLIB) $@

# Link the shared module against liblua.so (-L$(BUILD) -llua).
$(BUILD)/lfs.$(LUA_MOD_EXT): $(BUILD)/lfs-obj/lfs.o $(LUA_SO)
	$(CC) $(SHARED_LINK) -o $@ $< -L$(BUILD) -llua $(LDFLAGS_LUA)

.PHONY: lfs
lfs: $(BUILD)/liblfs.a $(BUILD)/lfs.$(LUA_MOD_EXT)

# =============================================================================
# 5. LPEG
# =============================================================================
#
# lpeg has multiple C source files (lp*.c), so we use the cd+glob pattern.
# The lp* glob catches lpcode.c, lpcap.c, lptree.c, lpvm.c, lpprint.c
# without hardcoding the list.

$(BUILD)/lpeg-obj/.built: $(LUA_A) $(LPEG_DIR)
	@mkdir -p $(BUILD)/lpeg-obj
	cd $(LPEG_DIR) && $(CC) $(CFLAGS) $(SHARED_FLAGS) \
	  -I$(CURDIR)/$(LUA_SRC) -c lp*.c
	mv $(LPEG_DIR)/lp*.o $(BUILD)/lpeg-obj/
	@touch $@

$(BUILD)/liblpeg.a: $(BUILD)/lpeg-obj/.built
	$(AR) rcs $@ $(BUILD)/lpeg-obj/*.o
	$(RANLIB) $@

$(BUILD)/lpeg.$(LUA_MOD_EXT): $(BUILD)/lpeg-obj/.built $(LUA_SO)
	$(CC) $(SHARED_LINK) -o $@ $(BUILD)/lpeg-obj/*.o -L$(BUILD) -llua $(LDFLAGS_LUA)

.PHONY: lpeg
lpeg: $(BUILD)/liblpeg.a $(BUILD)/lpeg.$(LUA_MOD_EXT)

# =============================================================================
# 6. LUA-TERM
# =============================================================================
#
# Another single-file C module.  The C part (core.c) provides terminal
# detection (isatty, etc.); the Lua parts (term/init.lua, cursor.lua,
# colors.lua) provide the higher-level API.

$(BUILD)/luaterm-obj/core.o: $(LUATERM_DIR) $(LUA_A)
	@mkdir -p $(BUILD)/luaterm-obj
	$(CC) $(CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) \
	  -c -o $@ $(LUATERM_DIR)/core.c

$(BUILD)/libluaterm.a: $(BUILD)/luaterm-obj/core.o
	$(AR) rcs $@ $<
	$(RANLIB) $@

# The output is named term_core.so (not core.so) to avoid ambiguity.
# At install time, it's placed at lib/lua/5.4/term/core.so, which is
# where require("term.core") expects to find it.
$(BUILD)/term_core.$(LUA_MOD_EXT): $(BUILD)/luaterm-obj/core.o $(LUA_SO)
	$(CC) $(SHARED_LINK) -o $@ $< -L$(BUILD) -llua $(LDFLAGS_LUA)

.PHONY: luaterm
luaterm: $(BUILD)/libluaterm.a $(BUILD)/term_core.$(LUA_MOD_EXT)

# =============================================================================
# 7. DKJSON (pure Lua)
# =============================================================================
#
# No compilation needed — just copy the single .lua file to the build
# directory's lua-modules/ folder where the test harness can find it.
# Note: this target doesn't have a phony declaration with prerequisites
# in the standard pattern — it depends directly on the downloaded file.

dkjson: $(DKJSON_FILE)
	@mkdir -p $(BUILD)/lua-modules
	cp $(DKJSON_FILE) $(BUILD)/lua-modules/dkjson.lua

# =============================================================================
# 8. FULLY STATIC LUA INTERPRETER
# =============================================================================
#
# Builds a single binary (lua-static) that has ALL C modules linked in
# statically and ALL pure-Lua modules embedded as C byte arrays.
#
# Architecture:
#
#   src/lr_preload.c    — registers C module luaopen_* functions in
#                         package.preload so require() finds them without
#                         searching the filesystem.
#
#   src/lr_preload_lua.c — loads embedded Lua modules from C byte arrays.
#                          The byte arrays are generated by scripts/lua2c.sh
#                          into a header file at build time.
#
#   lua_static.c        — a patched copy of lua.c with calls to both
#                          preload functions inserted after luaL_openlibs(L).
#
# The result is a single binary that can run Lmod (or any Lua script using
# the bundled modules) without ANY external files.

STATIC_LUA_BIN := $(BUILD)/lua-static

# ---------------------------------------------------------------------------
# Collect pure-Lua module sources for embedding
# ---------------------------------------------------------------------------
#
# Each entry has the format:  module.name:path/to/file.lua
#
# The module name is what you'd pass to require().  For example:
#   term.cursor:$(LUATERM_DIR)/term/cursor.lua
# means that require("term.cursor") will load the embedded version
# of this file.

LUA_EMBED_MODULES = \
	re:$(LPEG_DIR)/re.lua \
	dkjson:$(DKJSON_FILE) \
	term:$(LUATERM_DIR)/term/init.lua \
	term.cursor:$(LUATERM_DIR)/term/cursor.lua \
	term.colors:$(LUATERM_DIR)/term/colors.lua

# ---------------------------------------------------------------------------
# Discover luaposix pure-Lua modules dynamically
# ---------------------------------------------------------------------------
#
# luaposix has many pure-Lua files (posix/init.lua, posix/compat.lua, etc.)
# that we need to embed.  Rather than hardcoding the list (which would break
# if upstream adds or removes files), we discover them with find+sed.
#
# The $(shell ...) call runs at Makefile parse time:
#   find $(LUAPOSIX_DIR)/lib/posix -name '*.lua' | sort | while read f; do
#     rel=$(echo "$f" | sed '...')
#     echo "$rel:$f"
#   done
#
# The sed transformations convert filesystem paths to Lua module names:
#   luaposix-36.2.1/lib/posix/init.lua   → posix      (init.lua → parent name)
#   luaposix-36.2.1/lib/posix/compat.lua → posix.compat
#   luaposix-36.2.1/lib/posix/sys/stat.lua → posix.sys.stat
#
# Specifically:
#   s|^$(LUAPOSIX_DIR)/lib/||   — strip the source tree prefix
#   s|/init\.lua$||             — init.lua files map to the directory name
#   s|\.lua$||                  — strip the .lua extension
#   s|/|.|g                     — convert path separators to dots
LUAPOSIX_LUA_MODULES := $(shell \
	if [ -d $(LUAPOSIX_DIR)/lib/posix ]; then \
	  find $(LUAPOSIX_DIR)/lib/posix -name '*.lua' | sort | while read f; do \
	    rel=$$(echo "$$f" | sed 's|^$(LUAPOSIX_DIR)/lib/||;s|/init\.lua$$||;s|\.lua$$||;s|/|.|g'); \
	    echo "$$rel:$$f"; \
	  done; \
	fi)

# posix.version doesn't exist in the luaposix source tree — it's normally
# generated by luke (luaposix's build system) at build time.  We create it
# ourselves so that require("posix.version") works in the static binary.
$(BUILD)/posix_version.lua: $(LUAPOSIX_DIR)
	@mkdir -p $(BUILD)
	@echo 'return "luaposix $(LUAPOSIX_VER)"' > $@

# Combine all module lists.  LUA_EMBED_ALL is the complete set of
# pure-Lua modules to embed in the static binary.
LUA_EMBED_ALL = $(LUA_EMBED_MODULES) \
	$(LUAPOSIX_LUA_MODULES) \
	posix.version:$(BUILD)/posix_version.lua

# ---------------------------------------------------------------------------
# Generate the byte-array header
# ---------------------------------------------------------------------------
#
# scripts/lua2c.sh reads each Lua file and converts it to a C byte array.
# The output is a header file containing declarations like:
#
#   static const unsigned char lr_lua_module_re[] = { 0x2d, 0x2d, ... };
#   static const unsigned char lr_lua_module_dkjson[] = { ... };
#   ...
#
# These arrays are compiled into the static binary and loaded at startup
# by lr_preload_lua.c.

$(BUILD)/static-lua/lr_lua_module_data.h: $(LPEG_DIR) $(LUATERM_DIR) \
                                           $(LUAPOSIX_DIR) $(BUILD)/posix_version.lua
	@mkdir -p $(BUILD)/static-lua
	sh scripts/lua2c.sh $@ $(LUA_EMBED_ALL)

# ---------------------------------------------------------------------------
# Patch lua.c for the static binary
# ---------------------------------------------------------------------------
#
# Same awk pattern as the RELOCATABLE case: insert function calls after
# luaL_openlibs(L).  Here we insert TWO calls:
#   preload_bundled_modules(L)      — registers C module luaopen_* functions
#   preload_bundled_lua_modules(L)  — registers embedded Lua modules

$(BUILD)/static-lua/lua_static.c: $(BUILD)/.lua-patched
	@mkdir -p $(BUILD)/static-lua
	awk '{print} /luaL_openlibs\(L\)/{print "  preload_bundled_modules(L);\n  preload_bundled_lua_modules(L);"}' \
	  $(LUA_SRC)/lua.c > $@

# ---------------------------------------------------------------------------
# Compile the preload modules
# ---------------------------------------------------------------------------
#
# $< is the first prerequisite (the .c file).  -c means "compile only,
# don't link" — produce a .o file.

$(BUILD)/static-lua/lr_preload.o: src/lr_preload.c src/lr_preload.h $(LUA_DIR)
	@mkdir -p $(BUILD)/static-lua
	$(CC) $(LUA_CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) -Isrc \
	  -c -o $@ $<

# -I$(BUILD)/static-lua is needed so lr_preload_lua.c can find the
# generated lr_lua_module_data.h header.
$(BUILD)/static-lua/lr_preload_lua.o: src/lr_preload_lua.c src/lr_preload_lua.h \
                                       $(BUILD)/static-lua/lr_lua_module_data.h $(LUA_DIR)
	@mkdir -p $(BUILD)/static-lua
	$(CC) $(LUA_CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) -Isrc \
	  -I$(BUILD)/static-lua \
	  -c -o $@ $<

# ---------------------------------------------------------------------------
# Link the static binary
# ---------------------------------------------------------------------------
#
# This is the final link step that produces lua-static.  It combines:
#   - The patched lua.c (with preload calls)
#   - The preload .o files (C module registration + Lua module embedding)
#   - liblua.a (the Lua runtime)
#   - All C module static libraries
#
# -include src/lr_preload.h / -include src/lr_preload_lua.h
#   Force-include the preload headers so the patched lua.c can call
#   preload_bundled_modules() and preload_bundled_lua_modules() without
#   modifying lua.c's #include directives.
#
# $(STATIC_EXTRA) expands to -static on Linux (truly static binary)
# or empty on macOS (can't fully static-link on macOS).
#
# The order of .a files matters for the linker: libraries must come AFTER
# the objects that reference them.  lua_static.c references liblua symbols,
# and the preload modules reference both liblua and the C module symbols.
#
# `file $@` at the end prints the binary's type (ELF, Mach-O, static vs
# dynamic) as a quick sanity check.

$(STATIC_LUA_BIN): $(BUILD)/static-lua/lua_static.c \
                    $(BUILD)/static-lua/lr_preload.o \
                    $(BUILD)/static-lua/lr_preload_lua.o \
                    $(LUA_A) \
                    $(BUILD)/libluaposix.a $(BUILD)/libluv.a $(LIBUV_A) \
                    $(BUILD)/liblfs.a $(BUILD)/liblpeg.a $(BUILD)/libluaterm.a
	$(CC) $(LUA_CFLAGS) $(STATIC_EXTRA) -I$(LUA_SRC) -Isrc \
	  -include src/lr_preload.h \
	  -include src/lr_preload_lua.h \
	  -o $@ \
	  $(BUILD)/static-lua/lua_static.c \
	  $(BUILD)/static-lua/lr_preload.o \
	  $(BUILD)/static-lua/lr_preload_lua.o \
	  $(LUA_A) \
	  $(BUILD)/libluaposix.a \
	  $(BUILD)/libluv.a \
	  $(LIBUV_A) \
	  $(BUILD)/liblfs.a \
	  $(BUILD)/liblpeg.a \
	  $(BUILD)/libluaterm.a \
	  -lpthread $(LDFLAGS_LUA)
	@echo ""
	@echo "Built static lua interpreter: $@"
	@echo "  Bundled C modules: luaposix luv lfs lpeg lua-term"
	@echo "  Bundled Lua modules: re dkjson term posix"
	@file $@

static-lua: $(STATIC_LUA_BIN)

# =============================================================================
# 9. TEST
# =============================================================================

# ---------------------------------------------------------------------------
# TEST_LUA — the command prefix for running tests
# ---------------------------------------------------------------------------
#
# Sets LUA_PATH and LUA_CPATH environment variables for the test run.
# These point at the build directory so the just-built modules can be
# found without installing first.
#
# The ;; at the end of each path appends Lua's compiled-in default paths
# (from luaconf.h) to the search list.  This means any module NOT in our
# build tree can still be found via the default paths.
#
# LUA_PATH: only dkjson needs this (it's pure Lua, copied to lua-modules/).
# LUA_CPATH: the complex path handles luaposix's nested .so layout
#   (posix/unistd.so, posix/sys/stat.so) plus flat modules (luv.so,
#   lfs.so, lpeg.so) and lua-term's oddly-named term_core.so.
TEST_LUA = LUA_PATH="$(BUILD)/lua-modules/?.lua;;" \
           LUA_CPATH="$(BUILD)/luaposix-so/?.$(LUA_MOD_EXT);$(BUILD)/luaposix-so/?/init.$(LUA_MOD_EXT);$(BUILD)/?.$(LUA_MOD_EXT);$(BUILD)/term_core.$(LUA_MOD_EXT);;" \
           $(LUA_BIN)

TEST_DEPS = $(LUA_BIN) $(BUILD)/luaposix-so/.built $(BUILD)/luv.$(LUA_MOD_EXT) \
            $(BUILD)/lfs.$(LUA_MOD_EXT) $(BUILD)/lpeg.$(LUA_MOD_EXT) \
            $(BUILD)/term_core.$(LUA_MOD_EXT) $(DKJSON_FILE)

# ---------------------------------------------------------------------------
# Quick smoke test — embedded Lua script via heredoc
# ---------------------------------------------------------------------------
#
# `define VAR ... endef` is GNU Make's multi-line variable syntax.  It
# captures everything between define and endef (including newlines) as the
# variable's value.  Combined with `export VAR`, the shell can access it
# as an environment variable.
#
# `echo "$$TEST_SCRIPT"` expands the environment variable (double $$ because
# Make eats one $) and writes it to a .lua file, which is then executed.
#
# This is a clever way to embed a complete Lua test script in the Makefile
# without needing an external test file.  The `quicktest` target uses this
# inline script, while the `test` target uses the external test/test_bundled.lua.

define TEST_SCRIPT
local pass, fail = 0, 0
local function test(name, fn)
  local ok, msg = pcall(fn)
  if ok then
    pass = pass + 1
    print("  PASS  " .. name)
  else
    fail = fail + 1
    print("  FAIL  " .. name .. ": " .. tostring(msg))
  end
end

print("")
print("=== lua-regolith Smoke Tests ===")
print("  Lua version: " .. _VERSION)
print("")

-- Lua core
test("Lua version starts with 'Lua 5.'", function()
  assert(_VERSION:match("^Lua 5%."), "unexpected: " .. _VERSION)
end)

-- luaposix C modules (tested directly, bypassing the top-level posix
-- meta-module which requires the optional std.strict dependency)
test("require posix.unistd", function()
  assert(require("posix.unistd"), "nil")
end)
test("posix.unistd.getpid()", function()
  local pid = require("posix.unistd").getpid()
  assert(type(pid) == "number" and pid > 0, "bad pid: " .. tostring(pid))
end)
test("posix.sys.stat.stat('/')", function()
  local info = require("posix.sys.stat").stat("/")
  assert(info and info.st_ino, "stat failed")
end)
test("posix.errno", function()
  assert(require("posix.errno"), "nil")
end)
test("posix.fcntl", function()
  assert(require("posix.fcntl"), "nil")
end)
test("posix.time.clock_gettime", function()
  local ts = require("posix.time").clock_gettime(0)
  assert(ts and ts.tv_sec > 0, "clock_gettime failed")
end)

-- luv
test("require luv", function()
  assert(require("luv"), "nil")
end)
test("luv.version()", function()
  local v = require("luv").version()
  assert(type(v) == "number" and v > 0, "bad: " .. tostring(v))
end)
test("luv.fs_stat('/')", function()
  local s = require("luv").fs_stat("/")
  assert(s and s.type == "directory", "not dir")
end)
test("luv timer (event loop)", function()
  local luv = require("luv")
  local fired = false
  local t = luv.new_timer()
  t:start(10, 0, function() fired = true; t:stop(); t:close() end)
  luv.run()
  assert(fired, "timer never fired")
end)

-- luafilesystem
test("require lfs", function()
  assert(require("lfs"), "nil")
end)
test("lfs.attributes('/')", function()
  local a = require("lfs").attributes("/")
  assert(a and a.mode == "directory", "bad attrs")
end)
test("lfs.dir('/')", function()
  local n = 0
  for _ in require("lfs").dir("/") do n = n + 1 end
  assert(n > 0, "empty")
end)

-- lpeg
test("require lpeg", function()
  assert(require("lpeg"), "nil")
end)
test("lpeg.match basic", function()
  local lpeg = require("lpeg")
  assert(lpeg.match(lpeg.P("hello"), "hello world") == 6)
end)
test("lpeg.version is a string", function()
  local v = require("lpeg").version
  assert(type(v) == "string" and #v > 0, "bad ver: " .. tostring(v))
end)

-- lua-term
test("require term.core", function()
  assert(require("term.core"), "nil")
end)
test("term.core.isatty exists", function()
  assert(type(require("term.core").isatty) == "function")
end)

-- dkjson
test("require dkjson", function()
  assert(require("dkjson"), "nil")
end)
test("dkjson roundtrip", function()
  local j = require("dkjson")
  local t = { hello = "world", n = 42, a = {1,2,3} }
  local d = j.decode(j.encode(t))
  assert(d.hello == "world" and d.n == 42, "mismatch")
end)

print("")
print(string.format("Results: %d passed, %d failed", pass, fail))
if fail > 0 then print("SOME TESTS FAILED"); os.exit(1)
else print("ALL TESTS PASSED") end
endef
export TEST_SCRIPT

.PHONY: quicktest
quicktest: $(TEST_DEPS)
	@mkdir -p $(BUILD)
	@echo "$$TEST_SCRIPT" > $(BUILD)/test_quick.lua
	$(TEST_LUA) $(BUILD)/test_quick.lua
	@# If the static binary exists, test it too.  The `if` guard avoids
	@# a hard failure when static-lua hasn't been built.
	@if [ -f $(STATIC_LUA_BIN) ]; then \
	  echo ""; echo "=== Testing static binary (quick) ==="; echo ""; \
	  LUA_PATH="$(BUILD)/lua-modules/?.lua;;" \
	    $(STATIC_LUA_BIN) $(BUILD)/test_quick.lua; \
	fi

# Comprehensive test using the external test file.
.PHONY: test
test: $(TEST_DEPS)
	$(TEST_LUA) test/test_bundled.lua
	@if [ -f $(STATIC_LUA_BIN) ]; then \
	  echo ""; echo "=== Testing static binary ==="; echo ""; \
	  LUA_PATH="$(BUILD)/lua-modules/?.lua;;" \
	    $(STATIC_LUA_BIN) test/test_bundled.lua; \
	fi

# =============================================================================
# 10. INSTALL
# =============================================================================
#
# Each install-* target creates its directories with `install -d` and copies
# files with `install -m <mode>`.  The install(1) command is preferred over
# cp because it:
#   - Creates parent directories atomically (-d flag)
#   - Sets file permissions explicitly (-m flag)
#   - Is the POSIX-standard tool for installation
#
# Mode 755 = rwxr-xr-x (executables and shared libraries)
# Mode 644 = rw-r--r-- (headers, static libraries, data files)

.PHONY: install-lua install-luaposix install-luv install-lfs install-lpeg \
        install-luaterm install-dkjson install-pkgconfig

install-lua: $(LUA_A) $(LUA_SO) $(LUA_BIN) $(LUAC_BIN)
	install -d $(PREFIX)/bin $(PREFIX)/lib $(PREFIX)/include $(PREFIX)/include/lua$(LUA_SHORT)
	install -m 755 $(LUA_BIN) $(PREFIX)/bin/lua
	install -m 755 $(LUAC_BIN) $(PREFIX)/bin/luac
	install -m 644 $(LUA_A) $(PREFIX)/lib/liblua.a
	install -m 755 $(LUA_SO) $(PREFIX)/lib/liblua.$(SHARED_EXT)
	# Create a versioned symlink (liblua5.4.so → liblua.so) for
	# build systems that look for the versioned name.
	cd $(PREFIX)/lib && ln -sf liblua.$(SHARED_EXT) liblua$(LUA_SHORT).$(SHARED_EXT)
	# Install ALL headers dynamically — version-resilient (no hardcoded list).
	cd $(LUA_SRC) && find . -name '*.h' -exec install -m 644 {} $(PREFIX)/include/ \;
	cd $(LUA_SRC) && find . -name '*.h' -exec install -m 644 {} $(PREFIX)/include/lua$(LUA_SHORT)/ \;
	@if [ -f $(STATIC_LUA_BIN) ]; then \
	  install -m 755 $(STATIC_LUA_BIN) $(PREFIX)/bin/lua-static; \
	fi

# ---------------------------------------------------------------------------
# install-luaposix
# ---------------------------------------------------------------------------
#
# The find -exec sh -c '...' _ {} pattern explained:
#
#   find . -name '*.so' -exec sh -c '
#     d="$(PREFIX)/lib/lua/5.4/$(dirname "$1")"
#     install -d "$d"
#     install -m 755 "$1" "$d/"
#   ' _ {} \;
#
# For each file found, find runs: sh -c '<script>' _ <found-file>
#
# Inside sh -c:
#   $0 = _ (a dummy placeholder — convention for the "script name")
#   $1 = the found file path (substituted for {})
#
# Why not just use {} directly inside the -exec command?
# Because {} might contain characters that the shell interprets specially,
# and some find implementations don't substitute {} inside quoted strings.
# The sh -c '...' _ {} pattern is the portable, POSIX-blessed way to use
# find results in complex commands.
install-luaposix: $(BUILD)/libluaposix.a $(BUILD)/luaposix-so/.built
	install -d $(PREFIX)/lib $(PREFIX)/share/lua/$(LUA_SHORT)/posix
	install -m 644 $(BUILD)/libluaposix.a $(PREFIX)/lib/
	cd $(BUILD)/luaposix-so && \
	  find . -name '*.$(LUA_MOD_EXT)' -exec sh -c \
	    'd="$(PREFIX)/lib/lua/$(LUA_SHORT)/$$(dirname "$$1")"; install -d "$$d"; install -m 755 "$$1" "$$d/"' \
	    _ {} \;
	@if [ -d $(LUAPOSIX_DIR)/lib/posix ]; then \
	  cd $(LUAPOSIX_DIR)/lib && \
	  find posix -name '*.lua' -exec sh -c \
	    'd="$(PREFIX)/share/lua/$(LUA_SHORT)/$$(dirname "$$1")"; install -d "$$d"; install -m 644 "$$1" "$$d/"' \
	    _ {} \; ; \
	fi
	@# posix.version is generated by luaposix's own build system (luke)
	@# at build time — it doesn't exist in the source tree.  We generate
	@# it ourselves so that require("posix") succeeds (posix/init.lua
	@# calls require("posix.version") internally).
	@echo 'return "luaposix $(LUAPOSIX_VER)"' \
	  > $(PREFIX)/share/lua/$(LUA_SHORT)/posix/version.lua

install-luv: $(BUILD)/libluv.a $(BUILD)/luv.$(LUA_MOD_EXT) $(LIBUV_A)
	install -d $(PREFIX)/lib $(PREFIX)/lib/lua/$(LUA_SHORT) $(PREFIX)/include
	install -m 644 $(BUILD)/libluv.a $(PREFIX)/lib/
	# Install libuv as libluv_libuv.a — the "luv_" prefix makes it clear
	# this is the libuv bundled with luv (avoids colliding with any
	# system-installed libuv).
	install -m 644 $(LIBUV_A) $(PREFIX)/lib/libluv_libuv.a
	install -m 755 $(BUILD)/luv.$(LUA_MOD_EXT) $(PREFIX)/lib/lua/$(LUA_SHORT)/luv.$(LUA_MOD_EXT)
	install -m 755 $(BUILD)/libluv.$(SHARED_EXT) $(PREFIX)/lib/
	@if [ -d $(LUV_DIR)/src ]; then \
	  find $(LUV_DIR)/src -name '*.h' -exec install -m 644 {} $(PREFIX)/include/ \; ; \
	fi

install-lfs: $(BUILD)/liblfs.a $(BUILD)/lfs.$(LUA_MOD_EXT)
	install -d $(PREFIX)/lib $(PREFIX)/lib/lua/$(LUA_SHORT)
	install -m 644 $(BUILD)/liblfs.a $(PREFIX)/lib/
	install -m 755 $(BUILD)/lfs.$(LUA_MOD_EXT) $(PREFIX)/lib/lua/$(LUA_SHORT)/lfs.$(LUA_MOD_EXT)

install-lpeg: $(BUILD)/liblpeg.a $(BUILD)/lpeg.$(LUA_MOD_EXT)
	install -d $(PREFIX)/lib $(PREFIX)/lib/lua/$(LUA_SHORT) $(PREFIX)/share/lua/$(LUA_SHORT)
	install -m 644 $(BUILD)/liblpeg.a $(PREFIX)/lib/
	install -m 755 $(BUILD)/lpeg.$(LUA_MOD_EXT) $(PREFIX)/lib/lua/$(LUA_SHORT)/lpeg.$(LUA_MOD_EXT)
	# re.lua ships with lpeg and provides a regex-like interface on top
	# of PEG patterns.  It's a pure-Lua file, so it goes in share/.
	@if [ -f $(LPEG_DIR)/re.lua ]; then \
	  install -m 644 $(LPEG_DIR)/re.lua $(PREFIX)/share/lua/$(LUA_SHORT)/re.lua; \
	fi

install-luaterm: $(BUILD)/libluaterm.a $(BUILD)/term_core.$(LUA_MOD_EXT)
	install -d $(PREFIX)/lib \
	           $(PREFIX)/lib/lua/$(LUA_SHORT)/term \
	           $(PREFIX)/share/lua/$(LUA_SHORT)/term
	install -m 644 $(BUILD)/libluaterm.a $(PREFIX)/lib/
	# Install as term/core.so — Lua's require("term.core") searches for
	# term/core.so on package.cpath.
	install -m 755 $(BUILD)/term_core.$(LUA_MOD_EXT) \
	  $(PREFIX)/lib/lua/$(LUA_SHORT)/term/core.$(LUA_MOD_EXT)
	cd $(LUATERM_DIR)/term && find . -name '*.lua' -exec install -m 644 {} \
	  $(PREFIX)/share/lua/$(LUA_SHORT)/term/ \;

install-dkjson: $(DKJSON_FILE)
	install -d $(PREFIX)/share/lua/$(LUA_SHORT)
	install -m 644 $(DKJSON_FILE) $(PREFIX)/share/lua/$(LUA_SHORT)/dkjson.lua

# ---------------------------------------------------------------------------
# Generate pkg-config file
# ---------------------------------------------------------------------------
#
# pkg-config (.pc) files let other build systems find our Lua installation:
#   pkg-config --cflags lua5.4   →  -I/opt/lua-regolith/include
#   pkg-config --libs lua5.4     →  -L/opt/lua-regolith/lib -llua -lm -ldl
#
# The $${prefix} syntax inside the heredoc is NOT a Make variable — the
# $$ escapes to a single $, and ${prefix} is a pkg-config variable
# reference that gets resolved when pkg-config reads the file.
# In the .pc file, the line reads: exec_prefix=${prefix}
install-pkgconfig:
	install -d $(PREFIX)/lib/pkgconfig
	@{ \
	  echo 'prefix=$(PREFIX)'; \
	  echo 'exec_prefix=$${prefix}'; \
	  echo 'libdir=$${exec_prefix}/lib'; \
	  echo 'includedir=$${prefix}/include'; \
	  echo ''; \
	  echo 'Name: lua-regolith $(LUA_SHORT)'; \
	  echo 'Description: lua-regolith — Lua $(LUA_SHORT) with bundled luaposix, luv, lfs, lpeg, lua-term, dkjson'; \
	  echo 'Version: $(LUA_VER)'; \
	  echo 'Libs: -L$${libdir} -llua -lm -ldl'; \
	  echo 'Libs.private: -lpthread'; \
	  echo 'Cflags: -I$${includedir}'; \
	} > $(PREFIX)/lib/pkgconfig/lua$(LUA_SHORT).pc
