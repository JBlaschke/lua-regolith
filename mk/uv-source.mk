# SPDX-License-Identifier: AGPL-3.0-or-later
# =============================================================================
# libuv + luv compiled directly from source  (selected by Makefile.lite)
# =============================================================================
# No cmake: libuv's per-platform source list is maintained here instead of
# discovered from its CMakeLists.txt.
#
# Maintenance: last audited against the libuv v1.x CMakeLists.txt (1.52.x).
# Changes since the 1.48 lists:
#   - src/thread-common.c added to the common tier (barrier code shared
#     between the unix and win backends).
#   - src/unix/epoll.c gone -- the epoll/io_uring backend now lives entirely
#     in src/unix/linux.c (the 1.45 io_uring rework).
#   - -lkvm dropped on FreeBSD -- upstream only links kvm on NetBSD.
# On the next LIBUV_VER bump, diff these lists against the new
# CMakeLists.txt; `make test` exercises libuv (via luv) thoroughly enough
# to catch missing files.

LIBUV_SRC_COMMON := \
	src/fs-poll.c \
	src/idna.c \
	src/inet.c \
	src/random.c \
	src/strscpy.c \
	src/strtok.c \
	src/thread-common.c \
	src/threadpool.c \
	src/timer.c \
	src/uv-common.c \
	src/uv-data-getter-setters.c \
	src/version.c

LIBUV_SRC_UNIX := \
	src/unix/async.c \
	src/unix/core.c \
	src/unix/dl.c \
	src/unix/fs.c \
	src/unix/getaddrinfo.c \
	src/unix/getnameinfo.c \
	src/unix/loop.c \
	src/unix/loop-watcher.c \
	src/unix/pipe.c \
	src/unix/poll.c \
	src/unix/process.c \
	src/unix/random-devurandom.c \
	src/unix/signal.c \
	src/unix/stream.c \
	src/unix/tcp.c \
	src/unix/thread.c \
	src/unix/tty.c \
	src/unix/udp.c

# _FILE_OFFSET_BITS=64 / _LARGEFILE_SOURCE: large-file support on 32-bit
# targets, no-ops on 64-bit.  Applied by libuv's cmake on every non-Windows
# platform.
LIBUV_COMMON_DEFS := -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE

ifeq ($(UNAME_S),Linux)
  LIBUV_SRC_PLAT := \
	src/unix/linux.c \
	src/unix/procfs-exepath.c \
	src/unix/proctitle.c \
	src/unix/random-getrandom.c \
	src/unix/random-sysctl-linux.c
  LIBUV_PLAT_DEFS := -D_GNU_SOURCE -D_POSIX_C_SOURCE=200112
else ifeq ($(UNAME_S),Darwin)
  LIBUV_SRC_PLAT := \
	src/unix/bsd-ifaddrs.c \
	src/unix/darwin.c \
	src/unix/darwin-proctitle.c \
	src/unix/fsevents.c \
	src/unix/kqueue.c \
	src/unix/proctitle.c \
	src/unix/random-getentropy.c
  LIBUV_PLAT_DEFS := -D_DARWIN_UNLIMITED_SELECT=1 -D_DARWIN_USE_64_BIT_INODE=1
else ifeq ($(UNAME_S),FreeBSD)
  LIBUV_SRC_PLAT := \
	src/unix/bsd-ifaddrs.c \
	src/unix/bsd-proctitle.c \
	src/unix/freebsd.c \
	src/unix/kqueue.c \
	src/unix/posix-hrtime.c \
	src/unix/random-getrandom.c
  LIBUV_PLAT_DEFS :=
else ifeq ($(UNAME_S),OpenBSD)
  LIBUV_SRC_PLAT := \
	src/unix/bsd-ifaddrs.c \
	src/unix/bsd-proctitle.c \
	src/unix/kqueue.c \
	src/unix/openbsd.c \
	src/unix/posix-hrtime.c \
	src/unix/random-getentropy.c
  LIBUV_PLAT_DEFS :=
else
  $(error Makefile.lite supports Linux, macOS, FreeBSD, and OpenBSD. For other platforms use the full Makefile with cmake.)
endif

LIBUV_SRC_ALL := $(LIBUV_SRC_COMMON) $(LIBUV_SRC_UNIX) $(LIBUV_SRC_PLAT)

# -I include: public API.  -I src: libuv's own .c files include internal
# headers by bare name.  $(CURDIR) makes both survive recipe cd's.
LIBUV_INC    := -I$(CURDIR)/$(LIBUV_DIR)/include -I$(CURDIR)/$(LIBUV_DIR)/src
LIBUV_CFLAGS := $(CFLAGS) $(SHARED_FLAGS) $(LIBUV_INC) \
                $(LIBUV_COMMON_DEFS) $(LIBUV_PLAT_DEFS)

$(BUILD)/libuv-obj/.built: $(LIBUV_DIR)
	@mkdir -p $(BUILD)/libuv-obj
	CC='$(CC)' CFLAGS='$(LIBUV_CFLAGS)' \
	  sh scripts/compile-sources.sh $(CURDIR)/$(LIBUV_DIR) $(BUILD)/libuv-obj $(LIBUV_SRC_ALL)
	@touch $@

$(LIBUV_A): $(BUILD)/libuv-obj/.built
	$(AR) rcs $@ $(BUILD)/libuv-obj/*.o
	$(RANLIB) $@

# --- luv ----------------------------------------------------------------
# Single-translation-unit build: luv.c #includes every other src/*.c, whose
# internals are `static` (private.h).  Compile ONLY luv.c -- compiling the
# other files individually yields duplicate symbols (already in luv.c's TU)
# plus unresolved statics.  cmake knows this; here we must.

# Compat shim include -- luv release tarballs ship deps/lua-compat-5.3,
# some checkouts don't; empty when absent (a missing -I is harmless).
LUV_COMPAT_INC := $(shell test -d $(LUV_DIR)/deps/lua-compat-5.3/c-api \
	&& echo "-I$(CURDIR)/$(LUV_DIR)/deps/lua-compat-5.3/c-api")

LUV_INC := -I$(CURDIR)/$(LUA_SRC) \
           -I$(CURDIR)/$(LIBUV_DIR)/include \
           -I$(CURDIR)/$(LUV_DIR)/src \
           $(LUV_COMPAT_INC)

LUV_CFLAGS := $(CFLAGS) $(SHARED_FLAGS) $(LUV_INC)

$(BUILD)/luv-obj/.built: $(LUA_A) $(LUV_DIR) $(LIBUV_A)
	@mkdir -p $(BUILD)/luv-obj
	$(CC) $(LUV_CFLAGS) -c -o $(BUILD)/luv-obj/luv.o $(LUV_DIR)/src/luv.c
	@touch $@

$(BUILD)/libluv.a: $(BUILD)/luv-obj/.built
	$(AR) rcs $@ $(BUILD)/luv-obj/*.o
	$(RANLIB) $@

# luv.so embeds libuv statically: self-contained module, no runtime libuv
# dependency or version-mismatch risk.
$(BUILD)/luv.$(LUA_MOD_EXT): $(BUILD)/luv-obj/.built $(LIBUV_A) $(LUA_SO)
	$(CC) $(SHARED_LINK) -o $@ $(BUILD)/luv-obj/*.o \
	  $(LIBUV_A) -L$(BUILD) -llua $(LIBUV_PLAT_LIBS) $(LDFLAGS_LUA)

# Same contents as luv.so; only the filename/install location differ.
$(BUILD)/libluv.$(SHARED_EXT): $(BUILD)/luv.$(LUA_MOD_EXT)
	cp $< $@
