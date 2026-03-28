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

# Force POSIX shell for recipes (critical on systems where SHELL may be
# inherited from the environment, e.g. fish shell on macOS).

SHELL := /bin/sh
.SUFFIXES:
MAKEFLAGS += --no-builtin-rules

# ---- User-configurable knobs ------------------------------------------------

PREFIX     ?= /usr/local
CC         ?= gcc
AR         ?= ar
RANLIB     ?= ranlib
CMAKE      ?= cmake
WGET       ?= wget -q
NPROC      := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# ---- Versions ---------------------------------------------------------------

LUA_VER       := 5.4.7
LUAPOSIX_VER  := 36.2.1
LUV_VER       := 1.48.0-2
LIBUV_VER     := 1.48.0
LFS_VER       := 1.8.0
# luafilesystem uses underscores in tags: v1.8.0 → v1_8_0
LFS_TAG       := v$(subst .,_,$(LFS_VER))
LPEG_VER      := 1.1.0
LUATERM_VER   := 0.8
DKJSON_VER    := 2.8

# SHA-256 checksums (set to empty to skip)
LUA_SHA256      :=
LUAPOSIX_SHA256 :=
LUV_SHA256      :=
LIBUV_SHA256    :=
LFS_SHA256      :=
LPEG_SHA256     :=
LUATERM_SHA256  :=
DKJSON_SHA256   :=

# ---- Derived paths ----------------------------------------------------------

# Extract major.minor automatically from LUA_VER
LUA_SHORT     := $(shell echo $(LUA_VER) | sed 's/\([0-9]*\.[0-9]*\).*/\1/')

LUA_DIR       := lua-$(LUA_VER)
LUA_URL       := https://www.lua.org/ftp/lua-$(LUA_VER).tar.gz

LUAPOSIX_DIR  := luaposix-$(LUAPOSIX_VER)
LUAPOSIX_URL  := https://github.com/luaposix/luaposix/archive/refs/tags/v$(LUAPOSIX_VER).tar.gz

LUV_DIR       := luv-$(LUV_VER)
LUV_URL       := https://github.com/luvit/luv/releases/download/$(LUV_VER)/luv-$(LUV_VER).tar.gz

LIBUV_DIR     := libuv-$(LIBUV_VER)
LIBUV_URL     := https://github.com/libuv/libuv/archive/refs/tags/v$(LIBUV_VER).tar.gz

LFS_DIR       := luafilesystem-$(LFS_TAG)
LFS_URL       := https://github.com/lunarmodules/luafilesystem/archive/refs/tags/$(LFS_TAG).tar.gz

LPEG_DIR      := lpeg-$(LPEG_VER)
LPEG_URL      := http://www.inf.puc-rio.br/~roberto/lpeg/lpeg-$(LPEG_VER).tar.gz

LUATERM_DIR   := lua-term-$(LUATERM_VER)
LUATERM_URL   := https://github.com/hoelzro/lua-term/archive/refs/tags/$(LUATERM_VER).tar.gz

DKJSON_FILE   := dkjson-$(DKJSON_VER).lua
DKJSON_URL    := http://dkolf.de/dkjson-lua/dkjson-$(DKJSON_VER).lua

BUILD         := $(CURDIR)/build

# ---- Compiler flags ---------------------------------------------------------

CFLAGS        ?= -O2 -Wall
LUA_CFLAGS    := $(CFLAGS) -DLUA_USE_POSIX -DLUA_USE_DLOPEN
SHARED_FLAGS  := -fPIC

# ---- Platform detection -----------------------------------------------------

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
  LDFLAGS_LUA   := -lm -ldl -lreadline
  STATIC_EXTRA  := -static
  RPATH_FLAG     = -Wl,-rpath,'$(PREFIX)/lib'
  NM_LUAOPEN_RE := luaopen_
endif

# luaposix needs net/if.h for if_nametoindex / IFNAMSIZ.
# On Linux it's pulled in transitively; on macOS/FreeBSD it isn't.
# -include is harmless when the header is already included (header guards).
LUAPOSIX_PLAT_CFLAGS := -include net/if.h

# =============================================================================
# TOP-LEVEL TARGETS
# =============================================================================

.PHONY: all install clean distclean download verify test static-lua

all: lua liblua-shared luaposix luv lfs lpeg luaterm dkjson

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

clean:
	rm -rf $(BUILD)

distclean: clean
	rm -rf $(LUA_DIR) $(LUAPOSIX_DIR) $(LUV_DIR) $(LIBUV_DIR) \
	       $(LFS_DIR) $(LPEG_DIR) $(LUATERM_DIR)
	rm -f lua-$(LUA_VER).tar.gz luaposix-$(LUAPOSIX_VER).tar.gz \
	      luv-$(LUV_VER).tar.gz libuv-$(LIBUV_VER).tar.gz \
	      lfs-$(LFS_VER).tar.gz lpeg-$(LPEG_VER).tar.gz \
	      luaterm-$(LUATERM_VER).tar.gz $(DKJSON_FILE)

# =============================================================================
# DOWNLOAD + VERIFY
# =============================================================================

TARBALLS := lua-$(LUA_VER).tar.gz luaposix-$(LUAPOSIX_VER).tar.gz \
            luv-$(LUV_VER).tar.gz libuv-$(LIBUV_VER).tar.gz \
            lfs-$(LFS_VER).tar.gz lpeg-$(LPEG_VER).tar.gz \
            luaterm-$(LUATERM_VER).tar.gz $(DKJSON_FILE)

download: $(TARBALLS)

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

SHA256_CMD := $(shell command -v sha256sum 2>/dev/null || echo "shasum -a 256")

# Verify writes a helper script to avoid Make/shell escaping issues
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

# ---- Extract ----------------------------------------------------------------

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
# 1. LUA
# =============================================================================
#
# IMPORTANT — macOS compatibility note:
#
# macOS ships GNU Make 3.81, which has broken $$ escaping in multi-line
# recipes.  Writing $$src gets parsed as $$s + rc (Make expands $s as
# empty, leaving "rc").  Even $${src} doesn't help — Make expands
# ${src} as a Make variable.
#
# The fix throughout this Makefile: NEVER use shell loop variables in
# Make recipes.  Instead use one of:
#   a) "cd dir && cc -c *.c" then "mv *.o dest/ && rm unwanted.o"
#   b) Write a helper .sh script with printf, then sh it
#   c) Use find -exec sh -c '...' for install loops

LUA_SRC   := $(LUA_DIR)/src
LUA_A     := $(BUILD)/liblua.a
LUA_SO    := $(BUILD)/liblua.$(SHARED_EXT)
LUA_BIN   := $(BUILD)/lua
LUAC_BIN  := $(BUILD)/luac

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
	    echo '#define LUA_CPATH_DEFAULT LUA_CDIR"?.$(SHARED_EXT);"LUA_CDIR"loadall.$(SHARED_EXT);""./?.$(SHARED_EXT)"'; \
	    echo ''; \
	    echo '/* ---- end BUNDLED_LUA_PREFIX_OVERRIDE ---- */'; \
	  } >> $(LUA_SRC)/luaconf.h; \
	fi
	touch $@

# Compile all .c in src/, then remove lua.o and luac.o
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
	$(CC) $(SHARED_LINK) -o $@ $(BUILD)/lua-obj/*.o $(LDFLAGS_LUA)

$(LUA_BIN): $(LUA_SRC)/lua.c $(LUA_A)
	$(CC) $(LUA_CFLAGS) -I$(LUA_SRC) -o $@ $< \
	  $(LUA_A) $(LDFLAGS_LUA) \
	  $(RPATH_FLAG) -rdynamic

$(LUAC_BIN): $(LUA_SRC)/luac.c $(LUA_A)
	$(CC) $(LUA_CFLAGS) -I$(LUA_SRC) -o $@ $< $(LUA_A) $(LDFLAGS_LUA)

.PHONY: lua liblua-shared
lua: $(LUA_A) $(LUA_BIN) $(LUAC_BIN)
liblua-shared: $(LUA_SO)

# =============================================================================
# 2. LUAPOSIX
# =============================================================================

# Compile all .c in ext/posix/ via cd + glob
$(BUILD)/luaposix-obj/.built: $(LUA_A) $(LUAPOSIX_DIR)
	@mkdir -p $(BUILD)/luaposix-obj
	cd $(LUAPOSIX_DIR)/ext/posix && $(CC) $(CFLAGS) $(SHARED_FLAGS) $(LUAPOSIX_PLAT_CFLAGS) \
	  -I$(CURDIR)/$(LUA_SRC) \
	  -I$(CURDIR)/$(LUAPOSIX_DIR)/ext/include \
	  -I$(CURDIR)/$(LUAPOSIX_DIR)/ext/posix \
	  -DPACKAGE='"luaposix"' \
	  -DVERSION='"$(LUAPOSIX_VER)"' \
	  -c *.c
	mv $(LUAPOSIX_DIR)/ext/posix/*.o $(BUILD)/luaposix-obj/
	@touch $@

$(BUILD)/libluaposix.a: $(BUILD)/luaposix-obj/.built
	$(AR) rcs $@ $(BUILD)/luaposix-obj/*.o
	$(RANLIB) $@

# Build .so modules — uses a helper script to avoid Make $$ issues
$(BUILD)/luaposix-so/.built: $(BUILD)/luaposix-obj/.built
	@mkdir -p $(BUILD)/luaposix-so
	@printf '%s\n' '#!/bin/sh' \
	  'set -e' \
	  'for obj in '"$(BUILD)"'/luaposix-obj/*.o; do' \
	  '  sym=$$(nm -g "$$obj" 2>/dev/null | grep " T.*luaopen_" | head -1 | awk '"'"'{print $$NF}'"'"' | sed "s/^_//")' \
	  '  if [ -z "$$sym" ]; then continue; fi' \
	  '  relpath=$$(echo "$$sym" | sed "s/^luaopen_//" | sed "s/_/\//g")' \
	  '  dir=$$(dirname "$$relpath")' \
	  '  mkdir -p "'"$(BUILD)"'/luaposix-so/$$dir"' \
	  '  $(CC) $(SHARED_LINK) -o "'"$(BUILD)"'/luaposix-so/$${relpath}.$(SHARED_EXT)" "$$obj" -L'"$(BUILD)"' -llua $(LDFLAGS_LUA)' \
	  'done' > $(BUILD)/_build_posix_so.sh
	@sh $(BUILD)/_build_posix_so.sh
	@touch $@

.PHONY: luaposix
luaposix: $(BUILD)/libluaposix.a $(BUILD)/luaposix-so/.built $(LUA_SO)

# =============================================================================
# 3. LIBUV + LUV
# =============================================================================

LIBUV_BUILD := $(BUILD)/libuv-build
# libuv cmake produces libuv.a (not libuv_a.a) on some platforms
LIBUV_A     := $(LIBUV_BUILD)/libuv.a

$(LIBUV_A): $(LIBUV_DIR)
	@mkdir -p $(LIBUV_BUILD)
	cd $(LIBUV_BUILD) && $(CMAKE) \
	  -DCMAKE_C_FLAGS="$(CFLAGS) $(SHARED_FLAGS)" \
	  -DCMAKE_BUILD_TYPE=Release \
	  -DBUILD_TESTING=OFF \
	  -DLIBUV_BUILD_SHARED=OFF \
	  $(CURDIR)/$(LIBUV_DIR)
	$(MAKE) -C $(LIBUV_BUILD) -j$(NPROC)
	@# Normalize: cmake may produce libuv.a or libuv_a.a depending on version
	@if [ ! -f $@ ] && [ -f $(LIBUV_BUILD)/libuv_a.a ]; then \
	  cp $(LIBUV_BUILD)/libuv_a.a $@; \
	fi
	@test -f $@ || { echo "ERROR: libuv.a not found"; ls -la $(LIBUV_BUILD)/lib*.a 2>/dev/null; exit 1; }

LUV_BUILD := $(BUILD)/luv-build

$(BUILD)/libluv.a: $(LUA_A) $(LIBUV_A) $(LUV_DIR)
	@mkdir -p $(LUV_BUILD)
	cd $(LUV_BUILD) && $(CMAKE) \
	  -DCMAKE_C_FLAGS="$(CFLAGS) $(SHARED_FLAGS)" \
	  -DCMAKE_BUILD_TYPE=Release \
	  -DWITH_LUA_ENGINE=Lua \
	  -DLUA_BUILD_TYPE=System \
	  -DLUA_INCLUDE_DIR=$(CURDIR)/$(LUA_SRC) \
	  -DLUA_LIBRARY=$(LUA_A) \
	  -DLIBUV_BUILDTYPE=External \
	  -DLIBUV_INCLUDE_DIR=$(CURDIR)/$(LIBUV_DIR)/include \
	  -DLIBUV_LIBRARY=$(LIBUV_A) \
	  -DBUILD_MODULE=OFF \
	  -DBUILD_SHARED_LIBS=OFF \
	  $(CURDIR)/$(LUV_DIR)
	$(MAKE) -C $(LUV_BUILD) -j$(NPROC)
	@# luv names the static lib differently depending on version
	@for f in $(LUV_BUILD)/libluv_a.a $(LUV_BUILD)/libluv.a; do \
	  if [ -f "$f" ]; then cp "$f" $@; break; fi; \
	done
	@test -f $@ || { echo "ERROR: could not find libluv static library"; ls -la $(LUV_BUILD)/lib*.a 2>/dev/null; exit 1; }

$(BUILD)/luv.$(SHARED_EXT): $(BUILD)/libluv.a $(LUA_SO) $(LIBUV_A)
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
	@found=""; \
	for f in $(find $(LUV_BUILD)/shared -name 'luv.$(SHARED_EXT)' 2>/dev/null); do \
	  found="$f"; break; \
	done; \
	if [ -n "$found" ]; then cp "$found" $@; \
	else echo "ERROR: luv.$(SHARED_EXT) not found"; find $(LUV_BUILD)/shared -name '*.$(SHARED_EXT)' 2>/dev/null; exit 1; \
	fi

$(BUILD)/libluv.$(SHARED_EXT): $(BUILD)/luv.$(SHARED_EXT)
	cp $< $@

.PHONY: luv
luv: $(BUILD)/libluv.a $(BUILD)/luv.$(SHARED_EXT) $(BUILD)/libluv.$(SHARED_EXT)

# =============================================================================
# 4. LUAFILESYSTEM (lfs)
# =============================================================================

$(BUILD)/lfs-obj/lfs.o: $(LFS_DIR) $(LUA_A)
	@mkdir -p $(BUILD)/lfs-obj
	$(CC) $(CFLAGS) $(SHARED_FLAGS) \
	  -I$(LUA_SRC) -I$(LFS_DIR)/src \
	  -c -o $@ $(LFS_DIR)/src/lfs.c

$(BUILD)/liblfs.a: $(BUILD)/lfs-obj/lfs.o
	$(AR) rcs $@ $<
	$(RANLIB) $@

$(BUILD)/lfs.$(SHARED_EXT): $(BUILD)/lfs-obj/lfs.o $(LUA_SO)
	$(CC) $(SHARED_LINK) -o $@ $< -L$(BUILD) -llua $(LDFLAGS_LUA)

.PHONY: lfs
lfs: $(BUILD)/liblfs.a $(BUILD)/lfs.$(SHARED_EXT)

# =============================================================================
# 5. LPEG
# =============================================================================

# Compile via cd + glob (same pattern as lua)
$(BUILD)/lpeg-obj/.built: $(LUA_A) $(LPEG_DIR)
	@mkdir -p $(BUILD)/lpeg-obj
	cd $(LPEG_DIR) && $(CC) $(CFLAGS) $(SHARED_FLAGS) \
	  -I$(CURDIR)/$(LUA_SRC) -c lp*.c
	mv $(LPEG_DIR)/lp*.o $(BUILD)/lpeg-obj/
	@touch $@

$(BUILD)/liblpeg.a: $(BUILD)/lpeg-obj/.built
	$(AR) rcs $@ $(BUILD)/lpeg-obj/*.o
	$(RANLIB) $@

$(BUILD)/lpeg.$(SHARED_EXT): $(BUILD)/lpeg-obj/.built $(LUA_SO)
	$(CC) $(SHARED_LINK) -o $@ $(BUILD)/lpeg-obj/*.o -L$(BUILD) -llua $(LDFLAGS_LUA)

.PHONY: lpeg
lpeg: $(BUILD)/liblpeg.a $(BUILD)/lpeg.$(SHARED_EXT)

# =============================================================================
# 6. LUA-TERM
# =============================================================================

$(BUILD)/luaterm-obj/core.o: $(LUATERM_DIR) $(LUA_A)
	@mkdir -p $(BUILD)/luaterm-obj
	$(CC) $(CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) \
	  -c -o $@ $(LUATERM_DIR)/core.c

$(BUILD)/libluaterm.a: $(BUILD)/luaterm-obj/core.o
	$(AR) rcs $@ $<
	$(RANLIB) $@

$(BUILD)/term_core.$(SHARED_EXT): $(BUILD)/luaterm-obj/core.o $(LUA_SO)
	$(CC) $(SHARED_LINK) -o $@ $< -L$(BUILD) -llua $(LDFLAGS_LUA)

.PHONY: luaterm
luaterm: $(BUILD)/libluaterm.a $(BUILD)/term_core.$(SHARED_EXT)

# =============================================================================
# 7. DKJSON (pure Lua)
# =============================================================================

.PHONY: dkjson
dkjson: $(DKJSON_FILE)

# =============================================================================
# 8. FULLY STATIC LUA INTERPRETER  (bonus)
# =============================================================================

STATIC_LUA_BIN := $(BUILD)/lua-static

# Generate preload_modules.c via helper script
$(BUILD)/preload_modules.c: $(BUILD)/libluaposix.a $(BUILD)/libluv.a \
                             $(BUILD)/liblfs.a $(BUILD)/liblpeg.a \
                             $(BUILD)/libluaterm.a
	@mkdir -p $(BUILD)
	@printf '%s\n' '#!/bin/sh' \
	  'echo "/* Auto-generated */"' \
	  'echo "#include \"lua.h\""' \
	  'echo "#include \"lauxlib.h\""' \
	  'echo "#include \"lualib.h\""' \
	  'echo ""' \
	  'for obj in '"$(BUILD)"'/luaposix-obj/*.o; do' \
	  '  nm -g "$$obj" 2>/dev/null | grep " T.*luaopen_" | awk '"'"'{print $$NF}'"'"' | sed "s/^_//" | while read s; do' \
	  '    echo "int $${s}(lua_State *L);"' \
	  '  done' \
	  'done' \
	  'echo "int luaopen_luv(lua_State *L);"' \
	  'echo "int luaopen_lfs(lua_State *L);"' \
	  'echo "int luaopen_lpeg(lua_State *L);"' \
	  'echo "int luaopen_term_core(lua_State *L);"' \
	  'echo ""' \
	  'echo "static const struct { const char *name; lua_CFunction func; } bundled[] = {"' \
	  'for obj in '"$(BUILD)"'/luaposix-obj/*.o; do' \
	  '  nm -g "$$obj" 2>/dev/null | grep " T.*luaopen_" | awk '"'"'{print $$NF}'"'"' | sed "s/^_//" | while read s; do' \
	  '    m=$$(echo "$$s" | sed "s/^luaopen_//" | sed "s/_/./g")' \
	  '    echo "  { \"$$m\", $$s },"' \
	  '  done' \
	  'done' \
	  'echo "  { \"luv\", luaopen_luv },"' \
	  'echo "  { \"lfs\", luaopen_lfs },"' \
	  'echo "  { \"lpeg\", luaopen_lpeg },"' \
	  'echo "  { \"term.core\", luaopen_term_core },"' \
	  'echo "  { NULL, NULL }"' \
	  'echo "};"' \
	  'echo ""' \
	  'echo "void preload_bundled_modules(lua_State *L) {"' \
	  'echo "  luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);"' \
	  'echo "  for (int i = 0; bundled[i].name; i++) {"' \
	  'echo "    lua_pushcfunction(L, bundled[i].func);"' \
	  'echo "    lua_setfield(L, -2, bundled[i].name);"' \
	  'echo "  }"' \
	  'echo "  lua_pop(L, 1);"' \
	  'echo "}"' > $(BUILD)/_gen_preload.sh
	@sh $(BUILD)/_gen_preload.sh > $@

# Patch linit.c using awk (no shell variables needed)
$(BUILD)/static-lua/linit_bundled.c: $(BUILD)/.lua-patched $(BUILD)/preload_modules.c
	@mkdir -p $(BUILD)/static-lua
	@awk '/^#include/{last=NR} {lines[NR]=$$0} END{for(i=1;i<=NR;i++){print lines[i]; if(i==last) print "extern void preload_bundled_modules(lua_State *L);"}}' \
	  $(LUA_SRC)/linit.c > $@.tmp
	@awk '/luaL_openlibs/{fn=1} fn && /^}/{print "  preload_bundled_modules(L);"; fn=0} {print}' \
	  $@.tmp > $@
	@rm -f $@.tmp

# Compile static binary: cd+glob pattern, no shell variables
$(STATIC_LUA_BIN): $(BUILD)/static-lua/linit_bundled.c $(BUILD)/preload_modules.c \
                    $(BUILD)/libluaposix.a $(BUILD)/libluv.a $(LIBUV_A) \
                    $(BUILD)/liblfs.a $(BUILD)/liblpeg.a $(BUILD)/libluaterm.a \
                    $(BUILD)/.lua-patched
	@mkdir -p $(BUILD)/static-lua/obj
	@# Compile all .c, then remove the three we don't want
	cd $(LUA_SRC) && $(CC) $(LUA_CFLAGS) $(SHARED_FLAGS) -c *.c
	mv $(LUA_SRC)/*.o $(BUILD)/static-lua/obj/
	rm -f $(BUILD)/static-lua/obj/lua.o $(BUILD)/static-lua/obj/luac.o \
	      $(BUILD)/static-lua/obj/linit.o
	@# Compile patched linit + preload
	$(CC) $(LUA_CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) \
	  -c -o $(BUILD)/static-lua/obj/linit_bundled.o \
	  $(BUILD)/static-lua/linit_bundled.c
	$(CC) $(LUA_CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) \
	  -I$(CURDIR)/$(LUAPOSIX_DIR)/ext/include \
	  -I$(CURDIR)/$(LIBUV_DIR)/include \
	  -I$(CURDIR)/$(LFS_DIR)/src \
	  -I$(CURDIR)/$(LPEG_DIR) \
	  -c -o $(BUILD)/static-lua/obj/preload_modules.o \
	  $(BUILD)/preload_modules.c
	@# Archive and link
	$(AR) rcs $(BUILD)/static-lua/liblua-bundled.a $(BUILD)/static-lua/obj/*.o
	$(RANLIB) $(BUILD)/static-lua/liblua-bundled.a
	$(CC) $(LUA_CFLAGS) $(STATIC_EXTRA) -I$(LUA_SRC) -o $@ \
	  $(LUA_SRC)/lua.c \
	  $(BUILD)/static-lua/liblua-bundled.a \
	  $(BUILD)/libluaposix.a \
	  $(BUILD)/libluv.a \
	  $(LIBUV_A) \
	  $(BUILD)/liblfs.a \
	  $(BUILD)/liblpeg.a \
	  $(BUILD)/libluaterm.a \
	  -lpthread $(LDFLAGS_LUA)
	@echo ""
	@echo "Built static lua interpreter: $@"
	@echo "  Bundled: luaposix luv lfs lpeg lua-term"
	@file $@

static-lua: $(STATIC_LUA_BIN)

# =============================================================================
# 9. TEST
# =============================================================================

TEST_LUA = LUA_PATH="$(CURDIR)/$(LUAPOSIX_DIR)/lib/?.lua;$(CURDIR)/$(LUAPOSIX_DIR)/lib/?/init.lua;$(CURDIR)/$(LUATERM_DIR)/?.lua;$(CURDIR)/$(LUATERM_DIR)/?/init.lua;$(CURDIR)/$(LPEG_DIR)/?.lua;$(CURDIR)/$(DKJSON_FILE);;" \
           LUA_CPATH="$(BUILD)/luaposix-so/?.$(SHARED_EXT);$(BUILD)/luaposix-so/?/init.$(SHARED_EXT);$(BUILD)/?.$(SHARED_EXT);$(BUILD)/term_core.$(SHARED_EXT);;" \
           $(LUA_BIN)

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

-- luaposix
test("require posix", function()
  assert(require("posix"), "nil")
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
test("lpeg.version()", function()
  local v = require("lpeg").version()
  assert(type(v) == "string" and #v > 0, "bad ver")
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

test: $(LUA_BIN) $(BUILD)/luaposix-so/.built $(BUILD)/luv.$(SHARED_EXT) \
      $(BUILD)/lfs.$(SHARED_EXT) $(BUILD)/lpeg.$(SHARED_EXT) \
      $(BUILD)/term_core.$(SHARED_EXT) $(DKJSON_FILE)
	@mkdir -p $(BUILD)
	@echo "$$TEST_SCRIPT" > $(BUILD)/test_bundled.lua
	$(TEST_LUA) $(BUILD)/test_bundled.lua
	@if [ -f $(STATIC_LUA_BIN) ]; then \
	  echo ""; echo "=== Testing static binary ==="; echo ""; \
	  LUA_PATH="$(CURDIR)/$(LUAPOSIX_DIR)/lib/?.lua;$(CURDIR)/$(LUAPOSIX_DIR)/lib/?/init.lua;$(CURDIR)/$(LUATERM_DIR)/?.lua;$(CURDIR)/$(LUATERM_DIR)/?/init.lua;$(CURDIR)/$(LPEG_DIR)/?.lua;$(CURDIR)/$(DKJSON_FILE);;" \
	    $(STATIC_LUA_BIN) $(BUILD)/test_bundled.lua; \
	fi

# =============================================================================
# 10. INSTALL
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

install-luaposix: $(BUILD)/libluaposix.a $(BUILD)/luaposix-so/.built
	install -d $(PREFIX)/lib $(PREFIX)/share/lua/$(LUA_SHORT)/posix
	install -m 644 $(BUILD)/libluaposix.a $(PREFIX)/lib/
	cd $(BUILD)/luaposix-so && \
	  find . -name '*.$(SHARED_EXT)' -exec sh -c \
	    'd="$(PREFIX)/lib/lua/$(LUA_SHORT)/$$(dirname "{}")"; install -d "$$d"; install -m 755 "{}" "$$d/"' \;
	@if [ -d $(LUAPOSIX_DIR)/lib/posix ]; then \
	  cd $(LUAPOSIX_DIR)/lib && \
	  find posix -name '*.lua' -exec sh -c \
	    'd="$(PREFIX)/share/lua/$(LUA_SHORT)/$$(dirname "{}")"; install -d "$$d"; install -m 644 "{}" "$$d/"' \; ; \
	fi

install-luv: $(BUILD)/libluv.a $(BUILD)/luv.$(SHARED_EXT) $(LIBUV_A)
	install -d $(PREFIX)/lib $(PREFIX)/lib/lua/$(LUA_SHORT) $(PREFIX)/include
	install -m 644 $(BUILD)/libluv.a $(PREFIX)/lib/
	install -m 644 $(LIBUV_A) $(PREFIX)/lib/libluv_libuv.a
	install -m 755 $(BUILD)/luv.$(SHARED_EXT) $(PREFIX)/lib/lua/$(LUA_SHORT)/luv.$(SHARED_EXT)
	install -m 755 $(BUILD)/libluv.$(SHARED_EXT) $(PREFIX)/lib/
	@if [ -d $(LUV_DIR)/src ]; then \
	  find $(LUV_DIR)/src -name '*.h' -exec install -m 644 {} $(PREFIX)/include/ \; ; \
	fi

install-lfs: $(BUILD)/liblfs.a $(BUILD)/lfs.$(SHARED_EXT)
	install -d $(PREFIX)/lib $(PREFIX)/lib/lua/$(LUA_SHORT)
	install -m 644 $(BUILD)/liblfs.a $(PREFIX)/lib/
	install -m 755 $(BUILD)/lfs.$(SHARED_EXT) $(PREFIX)/lib/lua/$(LUA_SHORT)/lfs.$(SHARED_EXT)

install-lpeg: $(BUILD)/liblpeg.a $(BUILD)/lpeg.$(SHARED_EXT)
	install -d $(PREFIX)/lib $(PREFIX)/lib/lua/$(LUA_SHORT) $(PREFIX)/share/lua/$(LUA_SHORT)
	install -m 644 $(BUILD)/liblpeg.a $(PREFIX)/lib/
	install -m 755 $(BUILD)/lpeg.$(SHARED_EXT) $(PREFIX)/lib/lua/$(LUA_SHORT)/lpeg.$(SHARED_EXT)
	@if [ -f $(LPEG_DIR)/re.lua ]; then \
	  install -m 644 $(LPEG_DIR)/re.lua $(PREFIX)/share/lua/$(LUA_SHORT)/re.lua; \
	fi

install-luaterm: $(BUILD)/libluaterm.a $(BUILD)/term_core.$(SHARED_EXT)
	install -d $(PREFIX)/lib \
	           $(PREFIX)/lib/lua/$(LUA_SHORT)/term \
	           $(PREFIX)/share/lua/$(LUA_SHORT)/term
	install -m 644 $(BUILD)/libluaterm.a $(PREFIX)/lib/
	install -m 755 $(BUILD)/term_core.$(SHARED_EXT) \
	  $(PREFIX)/lib/lua/$(LUA_SHORT)/term/core.$(SHARED_EXT)
	cd $(LUATERM_DIR)/term && find . -name '*.lua' -exec install -m 644 {} \
	  $(PREFIX)/share/lua/$(LUA_SHORT)/term/ \;

install-dkjson: $(DKJSON_FILE)
	install -d $(PREFIX)/share/lua/$(LUA_SHORT)
	install -m 644 $(DKJSON_FILE) $(PREFIX)/share/lua/$(LUA_SHORT)/dkjson.lua

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
