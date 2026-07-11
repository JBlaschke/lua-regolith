# SPDX-License-Identifier: AGPL-3.0-or-later
# =============================================================================
# lua-regolith -- shared build core
# =============================================================================
#
# https://github.com/JBlaschke/lua-regolith
#
# Builds a self-contained Lua installation with luaposix, luv, lfs, lpeg,
# lua-term, and dkjson.  Suitable for running Lmod, creating standalone
# executables with luastatic, or embedding Lua anywhere.
#
# Included by the two entry points, which differ only in how libuv + luv
# are built:
#
#   Makefile       ->  UV_BUILD = cmake    (mk/uv-cmake.mk)
#   Makefile.lite  ->  UV_BUILD = source   (mk/uv-source.mk)
#
# Usage (substitute `make -f Makefile.lite` throughout for the lite build):
#   make download                            # fetch all source tarballs
#   make verify                              # check SHA-256 checksums
#   make PREFIX=/opt/lua-regolith all        # build everything
#   make PREFIX=/opt/lua-regolith install    # install to prefix
#   make static-lua                          # fully static interpreter
#   make test / quicktest                    # exercise the build
#   make relocate PREFIX=/new/path           # re-prefix without full rebuild
#   make clean / distclean
#
# After install, configure Lmod with:
#   ./configure --prefix=/opt/lmod \
#     --with-lua=$(PREFIX)/bin/lua --with-luac=$(PREFIX)/bin/luac
#
# Design rules for this file:
#   * Shell logic longer than a line or two lives in scripts/*.sh.  Recipes
#     here stay single-command so they behave identically on every GNU Make
#     from 3.81 (macOS) up.  (Historical note: the helper scripts used to be
#     *generated at build time* via printf with \044 escapes to dodge Make
#     3.81's broken $$ handling in backslash-continued recipes.  External
#     scripts retire that whole class of workaround.)
#   * The Lua source file list, stdlib table, and luaconf.h patching are all
#     derived dynamically from the extracted tree: bump LUA_VER (even to a
#     new minor) and the build adapts.

ifeq ($(UV_BUILD),)
$(error Do not run mk/common.mk directly; use Makefile (cmake) or Makefile.lite)
endif

# The entry point that included us -- needed for recursive $(MAKE) calls.
THIS_MAKEFILE := $(firstword $(MAKEFILE_LIST))

# SHELL: force POSIX sh regardless of the user's login shell (fish/zsh would
# break Bourne-syntax recipes).  .SUFFIXES + --no-builtin-rules: every compile
# step is explicit, so disable Make's ~100 implicit rules entirely.
# NOTE: --no-builtin-variables is deliberately absent -- under GNU Make 4.4's
# changed MAKEFLAGS handling it blanks CC & friends *after* our ?= defaults
# have already deferred to the builtins, silently emptying CC (see git log).
SHELL := /bin/sh
.SUFFIXES:
MAKEFLAGS += --no-builtin-rules

# =============================================================================
# USER-CONFIGURABLE KNOBS   (?= so environment / command line win)
# =============================================================================
# RELOCATABLE=1: lua resolves its own exe path at runtime and derives
# package.(c)path relative to the install root, so the whole $PREFIX tree
# can be moved (cp, rsync, tar) without rebuilding.  0 = hardcoded paths.

RELOCATABLE ?= 0
PREFIX      ?= /usr/local
CC          ?= gcc
AR          ?= ar
RANLIB      ?= ranlib
WGET        ?= wget -q
NPROC       := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# =============================================================================
# VERSIONS + CHECKSUMS
# =============================================================================
# := (expand once, constant) rather than ?=: an environment variable
# accidentally overriding LUA_VER would break the build in confusing ways.
# Command-line overrides still work.

LUA_VER       := 5.5.0
LUAPOSIX_VER  := 36.3
LUV_VER       := 1.52.1-0
LIBUV_VER     := 1.52.1
LFS_VER       := 1.9.0
# luafilesystem tags/dirs use underscores: v1.9.0 -> v1_9_0
LFS_TAG       := v$(subst .,_,$(LFS_VER))
LFS_VER_US    := $(subst .,_,$(LFS_VER))
LPEG_VER      := 1.1.0
LUATERM_VER   := 0.8
DKJSON_VER    := 2.8

# SHA-256, from upstream announcements / trusted package repos.  Update on
# every version bump; set one to empty to skip verification for that file.
LUA_SHA256      := 57ccc32bbbd005cab75bcc52444052535af691789dba2b9016d5c50640d68b3d
LUAPOSIX_SHA256 := 82cd9a96c41a4a3205c050206f0564ff4456f773a8f9ffc9235ff8f1907ca5e6
LUV_SHA256      := 3e6eb820a3aee034f85f9cce9bd77b5d42f34d128a1ccec877adf28c913577c7
LIBUV_SHA256    := 478baf2599bfbc882c355288c9cb6f92e0e7dda435fa04031fa5b607cf3f414c
LFS_SHA256      := 1142c1876e999b3e28d1c236bf21ffd9b023018e336ac25120fb5373aade1450
LPEG_SHA256     := 4b155d67d2246c1ffa7ad7bc466c1ea899bbc40fef0257cc9c03cecbaed4352a
LUATERM_SHA256  := 0cb270be22dfc262beec2f4ffc66b878ccaf236f537d693fa36c8f578fc51aa6
DKJSON_SHA256   := eb3bf160688fb395a2db6bc52eeff4f7855a6321d2b41bdc754554d13f4e7d44

# =============================================================================
# DERIVED PATHS  (cascade automatically from the versions above)
# =============================================================================

# "5.5" from "5.5.0" -- used for lib/lua/5.5, share/lua/5.5, etc.
LUA_SHORT     := $(shell echo $(LUA_VER) | sed 's/\([0-9]*\.[0-9]*\).*/\1/')

LUA_DIR       := lua-$(LUA_VER)
LUA_URL       := https://www.lua.org/ftp/lua-$(LUA_VER).tar.gz
# LUA_SRC must be defined *here*, not in section 1: the uv fragments'
# := include-path variables reference it at parse time.
LUA_SRC       := $(LUA_DIR)/src

LUAPOSIX_DIR  := luaposix-$(LUAPOSIX_VER)
LUAPOSIX_URL  := https://github.com/luaposix/luaposix/archive/refs/tags/v$(LUAPOSIX_VER).tar.gz

LUV_DIR       := luv-$(LUV_VER)
LUV_URL       := https://github.com/luvit/luv/releases/download/$(LUV_VER)/luv-$(LUV_VER).tar.gz

LIBUV_DIR     := libuv-$(LIBUV_VER)
LIBUV_URL     := https://github.com/libuv/libuv/archive/refs/tags/v$(LIBUV_VER).tar.gz

LFS_DIR       := luafilesystem-$(LFS_VER_US)
LFS_URL       := https://github.com/lunarmodules/luafilesystem/archive/refs/tags/$(LFS_TAG).tar.gz

LPEG_DIR      := lpeg-$(LPEG_VER)
LPEG_URL      := http://www.inf.puc-rio.br/~roberto/lpeg/lpeg-$(LPEG_VER).tar.gz

LUATERM_DIR   := lua-term-$(LUATERM_VER)
LUATERM_URL   := https://github.com/hoelzro/lua-term/archive/refs/tags/$(LUATERM_VER).tar.gz

DKJSON_FILE   := dkjson-$(DKJSON_VER).lua
DKJSON_URL    := http://dkolf.de/dkjson-lua/dkjson-$(DKJSON_VER).lua

BUILD         := $(CURDIR)/build

# =============================================================================
# PLATFORM DETECTION
# =============================================================================
# LUA_USE_LINUX / LUA_USE_MACOSX expand to POSIX+DLOPEN on Lua <= 5.4; on 5.5
# they additionally set LUA_READLINELIB so lua.c dlopen()s readline at runtime.
# LIBUV_PLAT_LIBS is the link set libuv needs on each OS -- used both by the
# source-mode luv.so link and by the static interpreter in either mode.

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  LUA_SYS_DEFS        := -DLUA_USE_MACOSX
  SHARED_EXT          := dylib
  SHARED_LINK         := -dynamiclib
  # @rpath/: resolve via the consuming binary's LC_RPATH at runtime instead
  # of baking in the build-time output path (which breaks anywhere else).
  SHARED_INSTALL_NAME := -install_name @rpath/liblua.$(SHARED_EXT)
  SHARED_SONAME       :=
  LDFLAGS_LUA         := -lm
  STATIC_EXTRA        :=
  LIBUV_PLAT_LIBS     := -lpthread
else ifeq ($(UNAME_S),OpenBSD)
  # dlopen(3) and crypt(3) live in libc on OpenBSD: no -ldl, no libcrypt.
  LUA_SYS_DEFS        := -DLUA_USE_LINUX
  SHARED_EXT          := so
  SHARED_LINK         := -shared
  SHARED_INSTALL_NAME :=
  SHARED_SONAME       := -Wl,-soname,liblua.so
  LDFLAGS_LUA         := -lm
  STATIC_EXTRA        := -static
  LIBUV_PLAT_LIBS     := -lpthread
else ifeq ($(UNAME_S),FreeBSD)
  LUA_SYS_DEFS        := -DLUA_USE_LINUX
  SHARED_EXT          := so
  SHARED_LINK         := -shared
  SHARED_INSTALL_NAME :=
  SHARED_SONAME       := -Wl,-soname,liblua.so
  LDFLAGS_LUA         := -lm -ldl
  STATIC_EXTRA        := -static
  LIBUV_PLAT_LIBS     := -lpthread
else
  # Linux and anything else POSIX-ish.
  LUA_SYS_DEFS        := -DLUA_USE_LINUX
  SHARED_EXT          := so
  SHARED_LINK         := -shared
  SHARED_INSTALL_NAME :=
  SHARED_SONAME       := -Wl,-soname,liblua.so
  LDFLAGS_LUA         := -lm -ldl
  STATIC_EXTRA        := -static
  # -lrt matches upstream libuv: needed for clock_/timer_ on old glibc,
  # harmless no-op on modern glibc and musl.
  LIBUV_PLAT_LIBS     := -lpthread -ldl -lrt
endif

# Separate libcrypt only exists on some systems (glibc via libxcrypt; macOS
# and OpenBSD keep crypt() in libc/libSystem).  Probe once; empty if absent.
# Only the luaposix .so links and the static binary need it.
LCRYPT := $(shell printf 'int main(void){return 0;}\n' | $(CC) -x c - -lcrypt -o /dev/null 2>/dev/null && echo -lcrypt)

# How binaries find liblua at runtime.  Both modes also embed $(BUILD) as an
# RPATH so `make test` works before install.
ifeq ($(RELOCATABLE),1)
  ifeq ($(UNAME_S),Darwin)
    RPATH_FLAG = -Wl,-rpath,'@executable_path/../lib' -Wl,-rpath,'$(PREFIX)/lib'
  else
    RPATH_FLAG = -Wl,-rpath,'$$ORIGIN/../lib' -Wl,-rpath,'$(PREFIX)/lib'
  endif
else
  RPATH_FLAG = -Wl,-rpath,'$(PREFIX)/lib'
endif

# Feature-test macros luaposix expects (mirrors its lukefile).  Without them,
# headers hide declarations and the errors look like missing functions.
# OpenBSD deliberately gets none: its headers expose the full BSD API by
# default, and feature-test macros only *restrict* visibility there.
ifeq ($(UNAME_S),Darwin)
  LUAPOSIX_PLAT_DEFS := -D_DARWIN_C_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700
else ifeq ($(UNAME_S),Linux)
  LUAPOSIX_PLAT_DEFS := -D_BSD_SOURCE -D_DEFAULT_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700
else ifeq ($(UNAME_S),FreeBSD)
  LUAPOSIX_PLAT_DEFS := -D__BSD_VISIBLE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700
else ifeq ($(UNAME_S),OpenBSD)
  LUAPOSIX_PLAT_DEFS :=
else
  LUAPOSIX_PLAT_DEFS := -D_POSIX_C_SOURCE=200809L
endif

# =============================================================================
# COMPILER FLAGS
# =============================================================================
# All objects get -fPIC so the same .o feeds both .a and .so/.dylib outputs.

CFLAGS        ?= -O3 -Wall
LUA_CFLAGS    = $(CFLAGS) $(LUA_SYS_DEFS)
SHARED_FLAGS  := -fPIC

# Lua C modules are ALWAYS named .so -- even on macOS, where native shared
# libraries are .dylib.  package.cpath searches for .so on every platform;
# this is baked into Lua and followed by the whole ecosystem.  Hence two
# variables: SHARED_EXT (native libs) vs LUA_MOD_EXT (Lua-loadable modules).
LUA_MOD_EXT := so

# =============================================================================
# TOP-LEVEL TARGETS
# =============================================================================

.PHONY: all install clean distclean download verify test quicktest \
        static-lua relocate lua liblua-shared luaposix luv lfs lpeg \
        lpeg-lua-modules luaterm dkjson FORCE

all: lua liblua-shared luaposix luv lfs lpeg luaterm dkjson

install: all install-lua install-luaposix install-luv \
         install-lfs install-lpeg install-luaterm install-dkjson \
         install-pkgconfig
	@echo ""
	@echo "================================================================"
	@echo " lua-regolith $(LUA_VER) installed to: $(PREFIX)"
	@echo "   (built via $(THIS_MAKEFILE))"
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

# Re-prefix without a full rebuild.  Only the Lua core embeds PREFIX (via
# luaconf.h); the C modules contain no hardcoded paths.  A plain
# `make PREFIX=/new/path install` also works (the .prefix content-stamp
# below invalidates the core); this target is the explicit, minimal spelling.
relocate: $(LUA_DIR)
	@echo "  Relocating to PREFIX=$(PREFIX) ..."
	sh scripts/patch-luaconf.sh --strip $(LUA_SRC)/luaconf.h
	rm -f $(BUILD)/.lua-patched $(BUILD)/lua-obj/.built
	rm -f $(LUA_A) $(LUA_SO) $(LUA_BIN) $(LUAC_BIN)
	$(MAKE) -f $(THIS_MAKEFILE) lua liblua-shared
	@echo ""
	@echo " Relocated to $(PREFIX).  C modules unchanged (no embedded paths)."
	@echo " Run '$(MAKE) -f $(THIS_MAKEFILE) PREFIX=$(PREFIX) install' to install."

clean:
	rm -rf $(LUA_DIR) $(LUAPOSIX_DIR) $(LUV_DIR) $(LIBUV_DIR) \
	       $(LFS_DIR) $(LPEG_DIR) $(LUATERM_DIR)
	rm -rf $(BUILD)

distclean: clean
	rm -f $(TARBALLS)

# =============================================================================
# DOWNLOAD + VERIFY + EXTRACT
# =============================================================================
# Each tarball rule's target is the file itself, so `make download` is
# idempotent: only missing files are fetched.

TARBALLS := lua-$(LUA_VER).tar.gz \
            luaposix-$(LUAPOSIX_VER).tar.gz \
            luv-$(LUV_VER).tar.gz \
            libuv-$(LIBUV_VER).tar.gz \
            lfs-$(LFS_VER).tar.gz \
            lpeg-$(LPEG_VER).tar.gz \
            luaterm-$(LUATERM_VER).tar.gz \
            $(DKJSON_FILE)

download: $(TARBALLS)

lua-$(LUA_VER).tar.gz:            ; $(WGET) -O $@ "$(LUA_URL)"
luaposix-$(LUAPOSIX_VER).tar.gz:  ; $(WGET) -O $@ "$(LUAPOSIX_URL)"
luv-$(LUV_VER).tar.gz:            ; $(WGET) -O $@ "$(LUV_URL)"
libuv-$(LIBUV_VER).tar.gz:        ; $(WGET) -O $@ "$(LIBUV_URL)"
lfs-$(LFS_VER).tar.gz:            ; $(WGET) -O $@ "$(LFS_URL)"
lpeg-$(LPEG_VER).tar.gz:          ; $(WGET) -O $@ "$(LPEG_URL)"
luaterm-$(LUATERM_VER).tar.gz:    ; $(WGET) -O $@ "$(LUATERM_URL)"
$(DKJSON_FILE):                   ; $(WGET) -O $@ "$(DKJSON_URL)"

verify: download
	@sh scripts/verify-checksums.sh \
	  lua-$(LUA_VER).tar.gz           "$(LUA_SHA256)" \
	  luaposix-$(LUAPOSIX_VER).tar.gz "$(LUAPOSIX_SHA256)" \
	  luv-$(LUV_VER).tar.gz           "$(LUV_SHA256)" \
	  libuv-$(LIBUV_VER).tar.gz       "$(LIBUV_SHA256)" \
	  lfs-$(LFS_VER).tar.gz           "$(LFS_SHA256)" \
	  lpeg-$(LPEG_VER).tar.gz         "$(LPEG_SHA256)" \
	  luaterm-$(LUATERM_VER).tar.gz   "$(LUATERM_SHA256)" \
	  $(DKJSON_FILE)                  "$(DKJSON_SHA256)"

# `touch $@` after extraction: tar restores archive timestamps, which may be
# older than the tarball -- without it, Make would re-extract every run.
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

LUA_A         := $(BUILD)/liblua.a
LUA_SO        := $(BUILD)/liblua.$(SHARED_EXT)
LUA_BIN_PLAIN := $(BUILD)/lua-plain
LUA_BIN_RELOC := $(BUILD)/lua-reloc
LUAC_BIN      := $(BUILD)/luac

ifeq ($(RELOCATABLE),1)
LUA_BIN := $(LUA_BIN_RELOC)
else
LUA_BIN := $(LUA_BIN_PLAIN)
endif

# Content-stamp: rewritten only when PREFIX actually changes, so a PREFIX
# change automatically invalidates .lua-patched and the lua-core rebuild.
$(BUILD)/.prefix: FORCE
	@mkdir -p $(BUILD)
	@echo '$(PREFIX)' | cmp -s - $@ || echo '$(PREFIX)' > $@

FORCE:

# Hardcode PREFIX into luaconf.h (append-override strategy; see the script).
# Stamp file: the real output is an in-place edit, so an empty marker tracks
# "has this been done" for Make.
$(BUILD)/.lua-patched: $(LUA_DIR) $(BUILD)/.prefix
	@mkdir -p $(BUILD)
	sh scripts/patch-luaconf.sh $(LUA_SRC)/luaconf.h '$(PREFIX)' '$(LUA_SHORT)' '$(LUA_MOD_EXT)'
	touch $@

# Compile the whole core with a glob ("version resilience": Lua 5.x adding
# or removing source files is picked up automatically), then drop lua.o and
# luac.o -- their main()s would collide with anything linking liblua.
$(BUILD)/lua-obj/.built: $(BUILD)/.lua-patched
	@mkdir -p $(BUILD)/lua-obj
	cd $(LUA_SRC) && $(CC) $(LUA_CFLAGS) $(SHARED_FLAGS) -c *.c
	mv $(LUA_SRC)/*.o $(BUILD)/lua-obj/
	rm -f $(BUILD)/lua-obj/lua.o $(BUILD)/lua-obj/luac.o
	@touch $@

$(LUA_A): $(BUILD)/lua-obj/.built
	$(AR) rcs $@ $(BUILD)/lua-obj/*.o
	$(RANLIB) $@

$(LUA_SO): $(BUILD)/lua-obj/.built
	$(CC) $(SHARED_LINK) $(SHARED_INSTALL_NAME) $(SHARED_SONAME) -o $@ $(BUILD)/lua-obj/*.o $(LDFLAGS_LUA)

# --- RELOCATABLE=1 support ---------------------------------------------------
# lua.c gets a call to lr_set_relocatable_paths(L) injected after openlibs;
# src/lr_relocatable.c resolves the exe path (readlink /proc/self/exe,
# _NSGetExecutablePath, sysctl) and derives package.(c)path from it.
# luaconf.h keeps the build-time PREFIX as fallback for embedders and luac.

$(BUILD)/relocatable/lua.c: $(BUILD)/.lua-patched
	@mkdir -p $(BUILD)/relocatable
	sh scripts/inject-after-openlibs.sh $(LUA_SRC)/lua.c $@ \
	  'lr_set_relocatable_paths(L);'

$(BUILD)/relocatable/lr_relocatable.o: src/lr_relocatable.c src/lr_relocatable.h $(LUA_DIR)
	@mkdir -p $(BUILD)/relocatable
	$(CC) $(LUA_CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) -Isrc \
	  -DLR_LUA_SHORT='"$(LUA_SHORT)"' \
	  -c -o $@ $<

$(LUA_BIN_RELOC): $(BUILD)/relocatable/lua.c $(BUILD)/relocatable/lr_relocatable.o $(LUA_SO)
	$(CC) $(LUA_CFLAGS) -I$(LUA_SRC) -Isrc \
	  -include src/lr_relocatable.h \
	  -DLR_LUA_SHORT='"$(LUA_SHORT)"' \
	  -o $@ $(BUILD)/relocatable/lua.c $(BUILD)/relocatable/lr_relocatable.o \
	  -L$(BUILD) -llua $(LDFLAGS_LUA) \
	  $(RPATH_FLAG)

$(LUA_BIN_PLAIN): $(LUA_SRC)/lua.c $(LUA_SO)
	$(CC) $(LUA_CFLAGS) -I$(LUA_SRC) -o $@ $< \
	  -L$(BUILD) -llua $(LDFLAGS_LUA) \
	  -Wl,-rpath,$(BUILD) $(RPATH_FLAG)

# luac: always static against liblua.a; simple offline tool, no relocation.
$(LUAC_BIN): $(LUA_SRC)/luac.c $(LUA_A)
	$(CC) $(LUA_CFLAGS) -I$(LUA_SRC) -o $@ $< $(LUA_A) $(LDFLAGS_LUA)

lua: $(LUA_A) $(LUA_BIN) $(LUAC_BIN)
liblua-shared: $(LUA_SO)

# =============================================================================
# 2. LUAPOSIX
# =============================================================================
# Feature detection replaces luaposix's own build system (luke): probe-built
# HAVE_* macros land in a config header that is force-included (-include is
# processed before the file's own #includes) into every compilation unit.

LUAPOSIX_CONFIG_H := $(BUILD)/luaposix-config.h

$(LUAPOSIX_CONFIG_H): $(LUA_DIR)
	@mkdir -p $(BUILD)
	@CC='$(CC)' CFLAGS='$(CFLAGS) $(LUAPOSIX_PLAT_DEFS)' \
	  sh scripts/luaposix-config.sh $@

# -include net/if.h: some luaposix files use IFNAMSIZ without guarding the
# include; cc silently ignores a missing -include file, so this is safe on
# platforms without it.  PACKAGE/VERSION are expected from luke.
LUAPOSIX_INC := -I$(CURDIR)/$(LUA_SRC) \
	-I$(CURDIR)/$(LUAPOSIX_DIR)/ext/include \
	-I$(CURDIR)/$(LUAPOSIX_DIR)/ext/posix \
	-include $(LUAPOSIX_CONFIG_H) \
	-include net/if.h \
	$(LUAPOSIX_PLAT_DEFS) \
	-DPACKAGE='"luaposix"' -DVERSION='"$(LUAPOSIX_VER)"'

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

$(BUILD)/luaposix-obj/.built: $(BUILD)/luaposix-obj/.built-top $(BUILD)/luaposix-obj/.built-sys
	@touch $@

# posix.o is excluded: it's the monolithic convenience module re-exporting
# every luaopen_* the submodules already define -> duplicate symbols.
# require("posix") is served by the pure-Lua posix/init.lua instead.
$(BUILD)/libluaposix.a: $(BUILD)/luaposix-obj/.built
	rm -f $@
	find $(BUILD)/luaposix-obj -name '*.o' ! -name 'posix.o' | sort | xargs $(AR) rcs $@
	$(RANLIB) $@

$(BUILD)/luaposix-so/.built: $(BUILD)/luaposix-obj/.built $(LUA_SO)
	@mkdir -p $(BUILD)/luaposix-so
	CC='$(CC)' SHARED_LINK='$(SHARED_LINK)' LUA_MOD_EXT='$(LUA_MOD_EXT)' \
	  LINK_LIBS='-L$(BUILD) -llua $(LDFLAGS_LUA) $(LCRYPT)' \
	  sh scripts/build-luaposix-so.sh $(BUILD)/luaposix-obj $(BUILD)/luaposix-so
	@touch $@

luaposix: $(BUILD)/libluaposix.a $(BUILD)/luaposix-so/.built $(LUA_SO)

# =============================================================================
# 3. LIBUV + LUV  (method selected by the entry point)
# =============================================================================

LIBUV_A := $(BUILD)/libluv_libuv.a

include mk/uv-$(UV_BUILD).mk

luv: $(BUILD)/libluv.a $(BUILD)/luv.$(LUA_MOD_EXT) $(BUILD)/libluv.$(SHARED_EXT)

# =============================================================================
# 4. LUAFILESYSTEM (lfs) -- single source file
# =============================================================================

$(BUILD)/lfs-obj/lfs.o: $(LFS_DIR) $(LUA_A)
	@mkdir -p $(BUILD)/lfs-obj
	$(CC) $(CFLAGS) $(SHARED_FLAGS) \
	  -I$(LUA_SRC) -I$(LFS_DIR)/src \
	  -c -o $@ $(LFS_DIR)/src/lfs.c

$(BUILD)/liblfs.a: $(BUILD)/lfs-obj/lfs.o
	$(AR) rcs $@ $<
	$(RANLIB) $@

$(BUILD)/lfs.$(LUA_MOD_EXT): $(BUILD)/lfs-obj/lfs.o $(LUA_SO)
	$(CC) $(SHARED_LINK) -o $@ $< -L$(BUILD) -llua $(LDFLAGS_LUA)

lfs: $(BUILD)/liblfs.a $(BUILD)/lfs.$(LUA_MOD_EXT)

# =============================================================================
# 5. LPEG  (the lp* glob catches all sources without hardcoding the list)
# =============================================================================

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

lpeg: $(BUILD)/liblpeg.a $(BUILD)/lpeg.$(LUA_MOD_EXT) lpeg-lua-modules

# re.lua ships with lpeg; stage it where the test harness's LUA_PATH looks.
lpeg-lua-modules: $(LPEG_DIR)
	@mkdir -p $(BUILD)/lua-modules
	cp $(LPEG_DIR)/re.lua $(BUILD)/lua-modules/re.lua

# =============================================================================
# 6. LUA-TERM  (C core + pure-Lua wrappers)
# =============================================================================

$(BUILD)/luaterm-obj/core.o: $(LUATERM_DIR) $(LUA_A)
	@mkdir -p $(BUILD)/luaterm-obj
	$(CC) $(CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) \
	  -c -o $@ $(LUATERM_DIR)/core.c

$(BUILD)/libluaterm.a: $(BUILD)/luaterm-obj/core.o
	$(AR) rcs $@ $<
	$(RANLIB) $@

# Installed as term/core.so, where require("term.core") looks on cpath.
$(BUILD)/term/core.$(LUA_MOD_EXT): $(BUILD)/luaterm-obj/core.o $(LUA_SO)
	@mkdir -p $(BUILD)/term
	$(CC) $(SHARED_LINK) -o $@ $< -L$(BUILD) -llua $(LDFLAGS_LUA)

luaterm: $(BUILD)/libluaterm.a $(BUILD)/term/core.$(LUA_MOD_EXT)

# =============================================================================
# 7. DKJSON (pure Lua)
# =============================================================================

dkjson: $(DKJSON_FILE)
	@mkdir -p $(BUILD)/lua-modules
	cp $(DKJSON_FILE) $(BUILD)/lua-modules/dkjson.lua

# =============================================================================
# 8. FULLY STATIC LUA INTERPRETER
# =============================================================================
# One binary with every C module registered in package.preload
# (src/lr_preload.c) and every pure-Lua module embedded as byte arrays
# (src/lr_preload_lua.c + a header generated by scripts/lua2c.sh).

STATIC_LUA_BIN := $(BUILD)/lua-static
STATIC_LUA_A   := $(BUILD)/static-lua.a
STATIC_LUA_O   := $(BUILD)/static-lua.o

# module.name:path pairs for embedding.
LUA_EMBED_MODULES = \
	re:$(LPEG_DIR)/re.lua \
	dkjson:$(DKJSON_FILE) \
	term:$(LUATERM_DIR)/term/init.lua \
	term.cursor:$(LUATERM_DIR)/term/cursor.lua \
	term.colors:$(LUATERM_DIR)/term/colors.lua

# luaposix's pure-Lua modules, discovered dynamically (empty until extracted).
LUAPOSIX_LUA_MODULES := $(shell sh scripts/luaposix-modules.sh $(LUAPOSIX_DIR))

# posix.version doesn't exist in the source tree -- luke generates it at
# build time, so we do too (require("posix") loads it internally).
$(BUILD)/posix_version.lua: $(LUAPOSIX_DIR)
	@mkdir -p $(BUILD)
	@echo 'return "luaposix $(LUAPOSIX_VER)"' > $@

LUA_EMBED_ALL = $(LUA_EMBED_MODULES) \
	$(LUAPOSIX_LUA_MODULES) \
	posix.version:$(BUILD)/posix_version.lua

$(BUILD)/static-lua/lr_lua_module_data.h: $(LPEG_DIR) $(LUATERM_DIR) \
                                           $(LUAPOSIX_DIR) $(BUILD)/posix_version.lua
	@mkdir -p $(BUILD)/static-lua
	sh scripts/lua2c.sh $@ $(LUA_EMBED_ALL)

$(BUILD)/static-lua/lua_static.c: $(BUILD)/.lua-patched
	@mkdir -p $(BUILD)/static-lua
	sh scripts/inject-after-openlibs.sh $(LUA_SRC)/lua.c $@ \
	  'preload_bundled_modules(L);' \
	  'preload_bundled_lua_modules(L);'

$(BUILD)/static-lua/lr_preload.o: src/lr_preload.c src/lr_preload.h $(LUA_DIR)
	@mkdir -p $(BUILD)/static-lua
	$(CC) $(LUA_CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) -Isrc \
	  -c -o $@ $<

$(BUILD)/static-lua/lr_preload_lua.o: src/lr_preload_lua.c src/lr_preload_lua.h \
                                       $(BUILD)/static-lua/lr_lua_module_data.h $(LUA_DIR)
	@mkdir -p $(BUILD)/static-lua
	$(CC) $(LUA_CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) -Isrc \
	  -I$(BUILD)/static-lua \
	  -c -o $@ $<

# Shared input set for the two merged outputs.  -d (copy object trees) is
# used for our own modules instead of extracting their archives: luaposix
# has both time.o and sys/time.o, and `ar x` would silently clobber one.
STATIC_MERGE_DEPS := $(BUILD)/static-lua/lr_preload.o \
                     $(BUILD)/static-lua/lr_preload_lua.o \
                     $(BUILD)/lua-obj/.built \
                     $(BUILD)/luaposix-obj/.built \
                     $(BUILD)/lpeg-obj/.built \
                     $(BUILD)/lfs-obj/lfs.o \
                     $(BUILD)/luaterm-obj/core.o \
                     $(BUILD)/libluv.a $(LIBUV_A)

STATIC_MERGE_INPUTS := -l $(BUILD)/libluv.a -l $(LIBUV_A) \
                       -d $(BUILD)/lua-obj \
                       -d $(BUILD)/luaposix-obj \
                       -d $(BUILD)/lpeg-obj \
                       -o $(BUILD)/lfs-obj/lfs.o \
                       -o $(BUILD)/luaterm-obj/core.o \
                       -o $(BUILD)/static-lua/lr_preload.o \
                       -o $(BUILD)/static-lua/lr_preload_lua.o \
                       -x posix.o

$(STATIC_LUA_A): $(STATIC_MERGE_DEPS)
	AR='$(AR)' RANLIB='$(RANLIB)' \
	  sh scripts/merge-static.sh archive $@ $(STATIC_MERGE_INPUTS)
	@echo "Built static archive: $@"

# Preferred consumer interface: `ld -r` output is a plain object, so linkers
# include it unconditionally (no --whole-archive / -force_load dance).
$(STATIC_LUA_O): $(STATIC_MERGE_DEPS)
	sh scripts/merge-static.sh object $@ $(STATIC_MERGE_INPUTS)
	@echo "Built relocatable object: $@"
	@echo "  luastatic main.lua $(PREFIX)/lib/static-lua.o -I$(PREFIX)/include -lpthread -lm -ldl"

$(STATIC_LUA_BIN): $(BUILD)/static-lua/lua_static.c $(STATIC_LUA_A)
	$(CC) $(LUA_CFLAGS) $(STATIC_EXTRA) -I$(LUA_SRC) -Isrc \
	  -include src/lr_preload.h \
	  -include src/lr_preload_lua.h \
	  -o $@ \
	  $(BUILD)/static-lua/lua_static.c \
	  $(STATIC_LUA_A) \
	  $(LIBUV_PLAT_LIBS) $(LDFLAGS_LUA) $(LCRYPT)
	@echo "Built static lua interpreter: $@"
	@file $@

static-lua: $(STATIC_LUA_BIN) $(STATIC_LUA_A) $(STATIC_LUA_O)

# =============================================================================
# 9. TEST
# =============================================================================
# Paths point at the build tree so tests run pre-install; the trailing ;;
# appends Lua's compiled-in defaults to each search list.

$(BUILD)/lua-modules/posix/version.lua: $(LUAPOSIX_DIR)
	@mkdir -p $(BUILD)/lua-modules/posix
	@echo 'return "luaposix $(LUAPOSIX_VER)"' > $@

TEST_LUA = LUA_PATH="$(BUILD)/lua-modules/?.lua;$(LUAPOSIX_DIR)/lib/?.lua;$(LUAPOSIX_DIR)/lib/?/init.lua;;" \
           LUA_CPATH="$(BUILD)/luaposix-so/?.$(LUA_MOD_EXT);$(BUILD)/luaposix-so/?/init.$(LUA_MOD_EXT);$(BUILD)/?.$(LUA_MOD_EXT);;" \
           LD_LIBRARY_PATH="$(BUILD)" DYLD_LIBRARY_PATH="$(BUILD)" \
           $(LUA_BIN)

TEST_DEPS = $(LUA_BIN) $(BUILD)/luaposix-so/.built $(BUILD)/luv.$(LUA_MOD_EXT) \
            $(BUILD)/lfs.$(LUA_MOD_EXT) $(BUILD)/lpeg.$(LUA_MOD_EXT) \
            $(BUILD)/term/core.$(LUA_MOD_EXT) $(DKJSON_FILE)

quicktest: $(TEST_DEPS)
	$(TEST_LUA) test/test_quick.lua
	@if [ -f $(STATIC_LUA_BIN) ]; then \
	  echo ""; echo "=== Testing static binary (quick) ==="; echo ""; \
	  LUA_PATH="$(BUILD)/lua-modules/?.lua;;" \
	    $(STATIC_LUA_BIN) test/test_quick.lua; \
	fi

test: $(TEST_DEPS)
	$(TEST_LUA) test/test_bundled.lua
	@if [ -f $(STATIC_LUA_BIN) ]; then \
	  echo ""; echo "=== Testing static binary ==="; echo ""; \
	  LUA_PATH="$(BUILD)/lua-modules/?.lua;;" \
	    $(STATIC_LUA_BIN) test/test_bundled.lua; \
	fi

# =============================================================================
# 10. INSTALL   (install(1): atomic -d dirs, explicit -m modes)
# =============================================================================

.PHONY: install-lua install-luaposix install-luv install-lfs install-lpeg \
        install-luaterm install-dkjson install-pkgconfig

install-lua: $(LUA_A) $(LUA_SO) $(LUA_BIN) $(LUAC_BIN)
	install -d $(PREFIX)/bin $(PREFIX)/lib $(PREFIX)/include $(PREFIX)/include/lua$(LUA_SHORT)
	install -m 755 $(LUA_BIN) $(PREFIX)/bin/lua
	install -m 755 $(LUAC_BIN) $(PREFIX)/bin/luac
	install -m 644 $(LUA_A) $(PREFIX)/lib/liblua.a
	install -m 755 $(LUA_SO) $(PREFIX)/lib/liblua.$(SHARED_EXT)
	cd $(PREFIX)/lib && ln -sf liblua.$(SHARED_EXT) liblua$(LUA_SHORT).$(SHARED_EXT)
	cd $(LUA_SRC) && find . -name '*.h' -exec install -m 644 {} $(PREFIX)/include/ \;
	cd $(LUA_SRC) && find . -name '*.h' -exec install -m 644 {} $(PREFIX)/include/lua$(LUA_SHORT)/ \;
	@if [ -f $(STATIC_LUA_BIN) ]; then \
	  install -m 755 $(STATIC_LUA_BIN) $(PREFIX)/bin/lua-static; \
	fi
	@if [ -f $(STATIC_LUA_A) ]; then \
	  install -m 644 $(STATIC_LUA_A) $(PREFIX)/lib/static-lua.a; \
	fi
	@if [ -f $(STATIC_LUA_O) ]; then \
	  install -m 644 $(STATIC_LUA_O) $(PREFIX)/lib/static-lua.o; \
	fi

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
	@echo 'return "luaposix $(LUAPOSIX_VER)"' \
	  > $(PREFIX)/share/lua/$(LUA_SHORT)/posix/version.lua

install-luv: $(BUILD)/libluv.a $(BUILD)/luv.$(LUA_MOD_EXT) $(LIBUV_A)
	install -d $(PREFIX)/lib $(PREFIX)/lib/lua/$(LUA_SHORT) $(PREFIX)/include
	install -m 644 $(BUILD)/libluv.a $(PREFIX)/lib/
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
	@if [ -f $(LPEG_DIR)/re.lua ]; then \
	  install -m 644 $(LPEG_DIR)/re.lua $(PREFIX)/share/lua/$(LUA_SHORT)/re.lua; \
	fi

install-luaterm: $(BUILD)/libluaterm.a $(BUILD)/term/core.$(LUA_MOD_EXT)
	install -d $(PREFIX)/lib \
	           $(PREFIX)/lib/lua/$(LUA_SHORT)/term \
	           $(PREFIX)/share/lua/$(LUA_SHORT)/term
	install -m 644 $(BUILD)/libluaterm.a $(PREFIX)/lib/
	install -m 755 $(BUILD)/term/core.$(LUA_MOD_EXT) \
	  $(PREFIX)/lib/lua/$(LUA_SHORT)/term/core.$(LUA_MOD_EXT)
	cd $(LUATERM_DIR)/term && find . -name '*.lua' -exec install -m 644 {} \
	  $(PREFIX)/share/lua/$(LUA_SHORT)/term/ \;

install-dkjson: $(DKJSON_FILE)
	install -d $(PREFIX)/share/lua/$(LUA_SHORT)
	install -m 644 $(DKJSON_FILE) $(PREFIX)/share/lua/$(LUA_SHORT)/dkjson.lua

install-pkgconfig:
	install -d $(PREFIX)/lib/pkgconfig
	sh scripts/gen-pkgconfig.sh $(PREFIX)/lib/pkgconfig/lua$(LUA_SHORT).pc \
	  '$(PREFIX)' '$(LUA_SHORT)' '$(LUA_VER)' '$(LDFLAGS_LUA)'
