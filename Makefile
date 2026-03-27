# SPDX-License-Identifier: AGPL-3.0-or-later
# =============================================================================
# lua-regolith — The foundation layer for your Lua environment
# =============================================================================
#
# https://github.com/<you>/lua-regolith
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

LIBUV_DIR     := libuv-v$(LIBUV_VER)
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

verify: download
	@failed=0; \
	for pair in \
	  "lua-$(LUA_VER).tar.gz $(LUA_SHA256)" \
	  "luaposix-$(LUAPOSIX_VER).tar.gz $(LUAPOSIX_SHA256)" \
	  "luv-$(LUV_VER).tar.gz $(LUV_SHA256)" \
	  "libuv-$(LIBUV_VER).tar.gz $(LIBUV_SHA256)" \
	  "lfs-$(LFS_VER).tar.gz $(LFS_SHA256)" \
	  "lpeg-$(LPEG_VER).tar.gz $(LPEG_SHA256)" \
	  "luaterm-$(LUATERM_VER).tar.gz $(LUATERM_SHA256)" \
	  "$(DKJSON_FILE) $(DKJSON_SHA256)" \
	; do \
	  file=$$(echo $$pair | cut -d' ' -f1); \
	  expect=$$(echo $$pair | cut -d' ' -f2); \
	  if [ -z "$$expect" ]; then \
	    echo "SKIP  $$file (no checksum configured)"; \
	    continue; \
	  fi; \
	  actual=$$($(SHA256_CMD) "$$file" | cut -d' ' -f1); \
	  if [ "$$actual" = "$$expect" ]; then \
	    echo "OK    $$file"; \
	  else \
	    echo "FAIL  $$file"; \
	    echo "  expected: $$expect"; \
	    echo "  got:      $$actual"; \
	    failed=1; \
	  fi; \
	done; \
	if [ $$failed -ne 0 ]; then \
	  echo ""; echo "Checksum verification FAILED."; exit 1; \
	fi; \
	echo ""; echo "All configured checksums passed."

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
# KEY DESIGN: The source file list is discovered dynamically from the
# extracted tree.  Every .c in src/ except lua.c and luac.c is a library
# source.  This means a Lua version bump (even to 5.5) just works —
# new files are picked up, removed files are dropped.
#
# The luaconf.h patch uses #undef / #define appended to the END of the
# file, so it doesn't depend on matching any particular formatting
# inside the stock luaconf.h.
# =============================================================================

LUA_SRC   := $(LUA_DIR)/src
LUA_A     := $(BUILD)/liblua.a
LUA_SO    := $(BUILD)/liblua.$(SHARED_EXT)
LUA_BIN   := $(BUILD)/lua
LUAC_BIN  := $(BUILD)/luac

# --- Dynamic source discovery ------------------------------------------------
# After extraction, discover every .c file in src/ except the two mains.
# This is evaluated lazily (= not :=) so it works even before extraction
# on first pass — the actual file list is resolved when the targets need it.

LUA_LIB_C_FILES = $(filter-out $(LUA_SRC)/lua.c $(LUA_SRC)/luac.c, \
                    $(wildcard $(LUA_SRC)/*.c))
LUA_LIB_OBJS    = $(patsubst $(LUA_SRC)/%.c,$(BUILD)/lua-obj/%.o,$(LUA_LIB_C_FILES))

# --- Patch luaconf.h --------------------------------------------------------
#
# Instead of trying to sed-match internal formatting (which varies between
# Lua versions), we APPEND overrides to the end of luaconf.h.  The C
# preprocessor sees the last #define, so our values win.
#
# We override LUA_ROOT (the install prefix) and, as a safety net, also
# override LUA_LDIR and LUA_CDIR with explicit paths.  This works for
# any Lua version that uses these macros (5.1 through 5.4+).
#
# For Lua versions that don't define these macros (hypothetical), the
# extra #undefs are harmless.

$(BUILD)/.lua-patched: $(LUA_DIR)
	@mkdir -p $(BUILD)
	@if ! grep -q 'BUNDLED_LUA_PREFIX_OVERRIDE' $(LUA_SRC)/luaconf.h; then \
	  { \
	    echo ''; \
	    echo '/* ---- BUNDLED_LUA_PREFIX_OVERRIDE ---- */'; \
	    echo '/* Appended by lua-regolith Makefile.  Overrides default paths so     */'; \
	    echo '/* that the interpreter finds modules installed under PREFIX.          */'; \
	    echo '/* This approach is version-resilient: it works regardless of the     */'; \
	    echo '/* formatting or layout of the stock luaconf.h.                        */'; \
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
	    echo '#define LUA_PATH_DEFAULT \\'; \
	    echo '  LUA_LDIR "?.lua;" LUA_LDIR "?/init.lua;" \\'; \
	    echo '  LUA_CDIR "?.lua;" LUA_CDIR "?/init.lua;" \\'; \
	    echo '  "./?.lua;./?/init.lua"'; \
	    echo ''; \
	    echo '#ifdef LUA_CPATH_DEFAULT'; \
	    echo '#undef LUA_CPATH_DEFAULT'; \
	    echo '#endif'; \
	    echo '#define LUA_CPATH_DEFAULT \\'; \
	    echo '  LUA_CDIR "?.$(SHARED_EXT);" LUA_CDIR "loadall.$(SHARED_EXT);" \\'; \
	    echo '  "./?.$(SHARED_EXT)"'; \
	    echo ''; \
	    echo '/* ---- end BUNDLED_LUA_PREFIX_OVERRIDE ---- */'; \
	  } >> $(LUA_SRC)/luaconf.h; \
	fi
	touch $@

$(BUILD)/lua-obj/%.o: $(LUA_SRC)/%.c $(BUILD)/.lua-patched
	@mkdir -p $(BUILD)/lua-obj
	$(CC) $(LUA_CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) -c -o $@ $<

$(LUA_A): $(LUA_LIB_OBJS)
	$(AR) rcs $@ $^
	$(RANLIB) $@

$(LUA_SO): $(LUA_LIB_OBJS)
	$(CC) $(SHARED_LINK) -o $@ $^ $(LDFLAGS_LUA)

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

LUAPOSIX_C_SRCS := $(wildcard $(LUAPOSIX_DIR)/ext/posix/*.c)
LUAPOSIX_OBJS   := $(patsubst $(LUAPOSIX_DIR)/ext/posix/%.c,$(BUILD)/luaposix-obj/%.o,$(LUAPOSIX_C_SRCS))

$(BUILD)/luaposix-obj/%.o: $(LUAPOSIX_DIR)/ext/posix/%.c $(LUA_A)
	@mkdir -p $(BUILD)/luaposix-obj
	$(CC) $(CFLAGS) $(SHARED_FLAGS) \
	  -I$(LUA_SRC) \
	  -I$(LUAPOSIX_DIR)/ext/include \
	  -I$(LUAPOSIX_DIR)/ext/posix \
	  -DPACKAGE='"luaposix"' \
	  -DVERSION='"$(LUAPOSIX_VER)"' \
	  -c -o $@ $<

$(BUILD)/libluaposix.a: $(LUAPOSIX_OBJS)
	$(AR) rcs $@ $^
	$(RANLIB) $@

$(BUILD)/luaposix-so/.built: $(LUAPOSIX_OBJS)
	@mkdir -p $(BUILD)/luaposix-so
	@for obj in $(LUAPOSIX_OBJS); do \
	  sym=$$(nm -g "$$obj" 2>/dev/null \
	    | grep ' T.*$(NM_LUAOPEN_RE)' \
	    | head -1 \
	    | awk '{print $$NF}' \
	    | sed 's/^_//'); \
	  if [ -z "$$sym" ]; then continue; fi; \
	  relpath=$$(echo "$$sym" \
	    | sed 's/^luaopen_//' \
	    | sed 's/_/\//g'); \
	  dir=$$(dirname "$$relpath"); \
	  mkdir -p "$(BUILD)/luaposix-so/$$dir"; \
	  $(CC) $(SHARED_LINK) -o "$(BUILD)/luaposix-so/$${relpath}.$(SHARED_EXT)" \
	    "$$obj" -L$(BUILD) -llua $(LDFLAGS_LUA); \
	done
	touch $@

.PHONY: luaposix
luaposix: $(BUILD)/libluaposix.a $(BUILD)/luaposix-so/.built $(LUA_SO)

# =============================================================================
# 3. LIBUV + LUV
# =============================================================================

LIBUV_BUILD := $(BUILD)/libuv-build
LIBUV_A     := $(LIBUV_BUILD)/libuv_a.a

$(LIBUV_A): $(LIBUV_DIR)
	@mkdir -p $(LIBUV_BUILD)
	cd $(LIBUV_BUILD) && $(CMAKE) \
	  -DCMAKE_C_FLAGS="$(CFLAGS) $(SHARED_FLAGS)" \
	  -DCMAKE_BUILD_TYPE=Release \
	  -DBUILD_TESTING=OFF \
	  -DLIBUV_BUILD_SHARED=OFF \
	  $(CURDIR)/$(LIBUV_DIR)
	$(MAKE) -C $(LIBUV_BUILD) -j$(NPROC)

LUV_BUILD := $(BUILD)/luv-build

$(BUILD)/libluv.a: $(LUA_A) $(LIBUV_A) $(LUV_DIR)
	@mkdir -p $(LUV_BUILD)
	cd $(LUV_BUILD) && $(CMAKE) \
	  -DCMAKE_C_FLAGS="$(CFLAGS) $(SHARED_FLAGS)" \
	  -DCMAKE_BUILD_TYPE=Release \
	  -DLUA_BUILD_TYPE=System \
	  -DLUA_INCLUDE_DIR=$(CURDIR)/$(LUA_SRC) \
	  -DLUA_LIBRARIES=$(LUA_A) \
	  -DLIBUV_INCLUDE_DIR=$(CURDIR)/$(LIBUV_DIR)/include \
	  -DLIBUV_LIBRARIES=$(LIBUV_A) \
	  -DBUILD_MODULE=OFF \
	  -DBUILD_SHARED_LIBS=OFF \
	  -DWITH_SHARED_LIBUV=OFF \
	  $(CURDIR)/$(LUV_DIR)
	$(MAKE) -C $(LUV_BUILD) -j$(NPROC)
	cp $(LUV_BUILD)/libluv_a.a $@ 2>/dev/null || cp $(LUV_BUILD)/libluv.a $@

$(BUILD)/luv.$(SHARED_EXT): $(BUILD)/libluv.a $(LUA_SO) $(LIBUV_A)
	@mkdir -p $(LUV_BUILD)/shared
	cd $(LUV_BUILD)/shared && $(CMAKE) \
	  -DCMAKE_C_FLAGS="$(CFLAGS) $(SHARED_FLAGS)" \
	  -DCMAKE_BUILD_TYPE=Release \
	  -DLUA_BUILD_TYPE=System \
	  -DLUA_INCLUDE_DIR=$(CURDIR)/$(LUA_SRC) \
	  -DLUA_LIBRARIES=$(LUA_SO) \
	  -DLIBUV_INCLUDE_DIR=$(CURDIR)/$(LIBUV_DIR)/include \
	  -DLIBUV_LIBRARIES=$(LIBUV_A) \
	  -DBUILD_MODULE=ON \
	  -DBUILD_SHARED_LIBS=ON \
	  -DWITH_SHARED_LIBUV=OFF \
	  $(CURDIR)/$(LUV_DIR)
	$(MAKE) -C $(LUV_BUILD)/shared -j$(NPROC)
	find $(LUV_BUILD)/shared -name 'luv.$(SHARED_EXT)' -exec cp {} $@ \;

$(BUILD)/libluv.$(SHARED_EXT): $(BUILD)/luv.$(SHARED_EXT)
	cp $< $@

.PHONY: luv
luv: $(BUILD)/libluv.a $(BUILD)/luv.$(SHARED_EXT) $(BUILD)/libluv.$(SHARED_EXT)

# =============================================================================
# 4. LUAFILESYSTEM (lfs)
# =============================================================================

LFS_OBJ := $(BUILD)/lfs-obj/lfs.o

$(LFS_OBJ): $(LFS_DIR) $(LUA_A)
	@mkdir -p $(BUILD)/lfs-obj
	$(CC) $(CFLAGS) $(SHARED_FLAGS) \
	  -I$(LUA_SRC) -I$(LFS_DIR)/src \
	  -c -o $@ $(LFS_DIR)/src/lfs.c

$(BUILD)/liblfs.a: $(LFS_OBJ)
	$(AR) rcs $@ $^
	$(RANLIB) $@

$(BUILD)/lfs.$(SHARED_EXT): $(LFS_OBJ) $(LUA_SO)
	$(CC) $(SHARED_LINK) -o $@ $(LFS_OBJ) -L$(BUILD) -llua $(LDFLAGS_LUA)

.PHONY: lfs
lfs: $(BUILD)/liblfs.a $(BUILD)/lfs.$(SHARED_EXT)

# =============================================================================
# 5. LPEG
# =============================================================================

LPEG_C_SRCS := $(wildcard $(LPEG_DIR)/lp*.c)
LPEG_OBJS   := $(patsubst $(LPEG_DIR)/%.c,$(BUILD)/lpeg-obj/%.o,$(LPEG_C_SRCS))

$(BUILD)/lpeg-obj/%.o: $(LPEG_DIR)/%.c $(LUA_A) $(LPEG_DIR)
	@mkdir -p $(BUILD)/lpeg-obj
	$(CC) $(CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) -I$(LPEG_DIR) -c -o $@ $<

$(BUILD)/liblpeg.a: $(LPEG_OBJS)
	$(AR) rcs $@ $^
	$(RANLIB) $@

$(BUILD)/lpeg.$(SHARED_EXT): $(LPEG_OBJS) $(LUA_SO)
	$(CC) $(SHARED_LINK) -o $@ $(LPEG_OBJS) -L$(BUILD) -llua $(LDFLAGS_LUA)

.PHONY: lpeg
lpeg: $(BUILD)/liblpeg.a $(BUILD)/lpeg.$(SHARED_EXT)

# =============================================================================
# 6. LUA-TERM
# =============================================================================

LUATERM_OBJ := $(BUILD)/luaterm-obj/core.o

$(LUATERM_OBJ): $(LUATERM_DIR) $(LUA_A)
	@mkdir -p $(BUILD)/luaterm-obj
	$(CC) $(CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) \
	  -c -o $@ $(LUATERM_DIR)/core.c

$(BUILD)/libluaterm.a: $(LUATERM_OBJ)
	$(AR) rcs $@ $^
	$(RANLIB) $@

$(BUILD)/term_core.$(SHARED_EXT): $(LUATERM_OBJ) $(LUA_SO)
	$(CC) $(SHARED_LINK) -o $@ $(LUATERM_OBJ) -L$(BUILD) -llua $(LDFLAGS_LUA)

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
#
# KEY DESIGN for version resilience:
#
#   a) preload_modules.c — auto-generated from nm, same as before.
#
#   b) linit_bundled.c — instead of hardcoding the standard library
#      table, we COPY the stock linit.c from the source tree and
#      PATCH it with sed to insert our preload call.  This means if
#      Lua 5.5 adds a new standard library (e.g. luaopen_newlib),
#      it's automatically included because we use THEIR linit.c.
#
#   c) Source file list — derived dynamically, same as the main build.
# =============================================================================

STATIC_LUA_BIN := $(BUILD)/lua-static

# ---- Generate preload_modules.c --------------------------------------------

$(BUILD)/preload_modules.c: $(BUILD)/libluaposix.a $(BUILD)/libluv.a \
                             $(BUILD)/liblfs.a $(BUILD)/liblpeg.a \
                             $(BUILD)/libluaterm.a
	@mkdir -p $(BUILD)
	@exec > $@; \
	echo '/* Auto-generated — do not edit */'; \
	echo '#include "lua.h"'; \
	echo '#include "lauxlib.h"'; \
	echo '#include "lualib.h"'; \
	echo ''; \
	echo '/* Forward declarations */'; \
	for obj in $(BUILD)/luaposix-obj/*.o; do \
	  nm -g "$$obj" 2>/dev/null \
	    | grep ' T.*$(NM_LUAOPEN_RE)' \
	    | awk '{print $$NF}' \
	    | sed 's/^_//' \
	    | while read sym; do \
	      echo "int $$sym(lua_State *L);"; \
	    done; \
	done; \
	echo 'int luaopen_luv(lua_State *L);'; \
	echo 'int luaopen_lfs(lua_State *L);'; \
	echo 'int luaopen_lpeg(lua_State *L);'; \
	echo 'int luaopen_term_core(lua_State *L);'; \
	echo ''; \
	echo 'static const struct { const char *name; lua_CFunction func; } bundled_modules[] = {'; \
	for obj in $(BUILD)/luaposix-obj/*.o; do \
	  nm -g "$$obj" 2>/dev/null \
	    | grep ' T.*$(NM_LUAOPEN_RE)' \
	    | awk '{print $$NF}' \
	    | sed 's/^_//' \
	    | while read sym; do \
	      modname=$$(echo "$$sym" | sed 's/^luaopen_//' | sed 's/_/./g'); \
	      echo "  { \"$$modname\", $$sym },"; \
	    done; \
	done; \
	echo '  { "luv", luaopen_luv },'; \
	echo '  { "lfs", luaopen_lfs },'; \
	echo '  { "lpeg", luaopen_lpeg },'; \
	echo '  { "term.core", luaopen_term_core },'; \
	echo '  { NULL, NULL }'; \
	echo '};'; \
	echo ''; \
	echo 'void preload_bundled_modules(lua_State *L) {'; \
	echo '  luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);'; \
	echo '  for (int i = 0; bundled_modules[i].name; i++) {'; \
	echo '    lua_pushcfunction(L, bundled_modules[i].func);'; \
	echo '    lua_setfield(L, -2, bundled_modules[i].name);'; \
	echo '  }'; \
	echo '  lua_pop(L, 1);'; \
	echo '}';

# ---- Patched linit.c (derived from the REAL linit.c) -----------------------
#
# Strategy: copy the stock linit.c, then:
#   1. Add a forward declaration of preload_bundled_modules()
#   2. Insert a call to it at the end of the luaL_openlibs function body,
#      right before the closing brace.
#
# We find the closing "}" of luaL_openlibs by looking for the LAST "}"
# in the file (linit.c is a small file with luaL_openlibs as the only
# or last function).  We insert our call just before it.
#
# This is deliberately conservative: if the sed fails to match, you get
# the stock linit.c (modules just won't be preloaded in the static binary,
# but the interpreter still works — it just falls back to .so loading).

$(BUILD)/static-lua/linit_bundled.c: $(BUILD)/.lua-patched $(BUILD)/preload_modules.c
	@mkdir -p $(BUILD)/static-lua
	@cp $(LUA_SRC)/linit.c $@
	@# Step 1: Add the forward declaration after the last #include
	@#   Find the line number of the last #include and insert after it
	@last_inc=$$(grep -n '#include' $@ | tail -1 | cut -d: -f1); \
	if [ -n "$$last_inc" ]; then \
	  sed -i.bak "$${last_inc}a\\
extern void preload_bundled_modules(lua_State *L);" $@; \
	fi
	@# Step 2: Insert preload call before the closing brace of luaL_openlibs.
	@#   We find "luaL_openlibs" then find the next "}" after it and insert before.
	@#   Use a Python one-liner for reliability across sed variants.
	@python3 -c " \
import sys; \
lines = open('$@').readlines(); \
found_fn = False; \
insert_at = None; \
for i, line in enumerate(lines): \
    if 'luaL_openlibs' in line and '(' in line: \
        found_fn = True; \
    if found_fn and line.strip() == '}': \
        insert_at = i; \
        break; \
if insert_at is not None: \
    lines.insert(insert_at, '  preload_bundled_modules(L);\n'); \
open('$@', 'w').writelines(lines); \
" 2>/dev/null || \
	  echo "Warning: python3 not found; static binary won't preload bundled modules"
	@rm -f $@.bak

# ---- Compile static binary using the real lua.c ----------------------------
#
# Source list derived dynamically: every .c in src/ except lua.c, luac.c,
# and linit.c (we supply our patched version).

$(STATIC_LUA_BIN): $(BUILD)/static-lua/linit_bundled.c $(BUILD)/preload_modules.c \
                    $(BUILD)/libluaposix.a $(BUILD)/libluv.a $(LIBUV_A) \
                    $(BUILD)/liblfs.a $(BUILD)/liblpeg.a $(BUILD)/libluaterm.a \
                    $(BUILD)/.lua-patched
	@mkdir -p $(BUILD)/static-lua/obj
	@# Compile every Lua lib source except lua.c, luac.c, linit.c
	@for src in $(filter-out $(LUA_SRC)/lua.c $(LUA_SRC)/luac.c $(LUA_SRC)/linit.c, \
	              $(wildcard $(LUA_SRC)/*.c)); do \
	  base=$$(basename $$src .c); \
	  $(CC) $(LUA_CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) \
	    -c -o $(BUILD)/static-lua/obj/$$base.o $$src; \
	done
	@# Compile patched linit
	$(CC) $(LUA_CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) \
	  -c -o $(BUILD)/static-lua/obj/linit_bundled.o \
	  $(BUILD)/static-lua/linit_bundled.c
	@# Compile preload registration
	$(CC) $(LUA_CFLAGS) $(SHARED_FLAGS) -I$(LUA_SRC) \
	  -I$(CURDIR)/$(LUAPOSIX_DIR)/ext/include \
	  -I$(CURDIR)/$(LIBUV_DIR)/include \
	  -I$(CURDIR)/$(LFS_DIR)/src \
	  -I$(CURDIR)/$(LPEG_DIR) \
	  -c -o $(BUILD)/static-lua/obj/preload_modules.o \
	  $(BUILD)/preload_modules.c
	@# Build static liblua-bundled.a
	$(AR) rcs $(BUILD)/static-lua/liblua-bundled.a \
	  $(BUILD)/static-lua/obj/*.o
	$(RANLIB) $(BUILD)/static-lua/liblua-bundled.a
	@# Link the real lua.c against everything
	$(CC) $(LUA_CFLAGS) $(STATIC_EXTRA) \
	  -I$(LUA_SRC) \
	  -o $@ \
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
#
# Headers are installed dynamically too: every .h and .hpp in src/.

.PHONY: install-lua install-luaposix install-luv install-lfs install-lpeg \
        install-luaterm install-dkjson install-pkgconfig

install-lua: $(LUA_A) $(LUA_SO) $(LUA_BIN) $(LUAC_BIN)
	install -d $(PREFIX)/bin $(PREFIX)/lib $(PREFIX)/include $(PREFIX)/include/lua$(LUA_SHORT)
	install -m 755 $(LUA_BIN) $(PREFIX)/bin/lua
	install -m 755 $(LUAC_BIN) $(PREFIX)/bin/luac
	install -m 644 $(LUA_A) $(PREFIX)/lib/liblua.a
	install -m 755 $(LUA_SO) $(PREFIX)/lib/liblua.$(SHARED_EXT)
	cd $(PREFIX)/lib && ln -sf liblua.$(SHARED_EXT) liblua$(LUA_SHORT).$(SHARED_EXT)
	@# Install all headers dynamically
	@for h in $(LUA_SRC)/*.h $(LUA_SRC)/*.hpp; do \
	  [ -f "$$h" ] || continue; \
	  install -m 644 "$$h" $(PREFIX)/include/; \
	  install -m 644 "$$h" $(PREFIX)/include/lua$(LUA_SHORT)/; \
	done
	@if [ -f $(STATIC_LUA_BIN) ]; then \
	  install -m 755 $(STATIC_LUA_BIN) $(PREFIX)/bin/lua-static; \
	fi

install-luaposix: $(BUILD)/libluaposix.a $(BUILD)/luaposix-so/.built
	install -d $(PREFIX)/lib $(PREFIX)/share/lua/$(LUA_SHORT)/posix
	install -m 644 $(BUILD)/libluaposix.a $(PREFIX)/lib/
	@cd $(BUILD)/luaposix-so && \
	  find . -name '*.$(SHARED_EXT)' | while read f; do \
	    dir=$(PREFIX)/lib/lua/$(LUA_SHORT)/$$(dirname "$$f"); \
	    install -d "$$dir"; \
	    install -m 755 "$$f" "$$dir/$$(basename $$f)"; \
	  done
	@if [ -d $(LUAPOSIX_DIR)/lib/posix ]; then \
	  cd $(LUAPOSIX_DIR)/lib && \
	  find posix -name '*.lua' | while read f; do \
	    dir=$(PREFIX)/share/lua/$(LUA_SHORT)/$$(dirname "$$f"); \
	    install -d "$$dir"; \
	    install -m 644 "$$f" "$$dir/$$(basename $$f)"; \
	  done; \
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
	@for f in $(LUATERM_DIR)/term/*.lua; do \
	  [ -f "$$f" ] || continue; \
	  install -m 644 "$$f" $(PREFIX)/share/lua/$(LUA_SHORT)/term/; \
	done

install-dkjson: $(DKJSON_FILE)
	install -d $(PREFIX)/share/lua/$(LUA_SHORT)
	install -m 644 $(DKJSON_FILE) $(PREFIX)/share/lua/$(LUA_SHORT)/dkjson.lua

install-pkgconfig:
	install -d $(PREFIX)/lib/pkgconfig
	@exec > $(PREFIX)/lib/pkgconfig/lua$(LUA_SHORT).pc; \
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
	echo 'Cflags: -I${includedir}';
