# SPDX-License-Identifier: AGPL-3.0-or-later
# =============================================================================
# libuv + luv via cmake  (selected by the top-level Makefile)
# =============================================================================
# libuv's source tree is symlinked into luv's deps/; luv's CMakeLists.txt
# finds it there and builds both with compatible flags -- no separate cmake
# invocation for libuv, no version skew.  libuv.a is then extracted from
# luv's build tree for the static interpreter and install.

CMAKE ?= cmake

LUV_BUILD := $(BUILD)/luv-build

# Absolute symlink target: a relative link inside deps/ breaks if the
# working directory changes.
$(LUV_DIR)/.libuv-linked: $(LUV_DIR) $(LIBUV_DIR)
	mkdir -p $(LUV_DIR)/deps
	rm -rf $(LUV_DIR)/deps/libuv
	ln -sf $(CURDIR)/$(LIBUV_DIR) $(LUV_DIR)/deps/libuv
	touch $@

# Static build: LUA_BUILD_TYPE=System points luv at our pre-built Lua;
# BUILD_MODULE=OFF because the shared module is built separately below
# (against liblua.so, not liblua.a).
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
	find $(LUV_BUILD) -maxdepth 2 -name 'libluv*.a' -exec cp {} $@ \;
	@test -f $@ || { echo "ERROR: libluv.a not found"; find $(LUV_BUILD) -name '*.a'; exit 1; }
	find $(LUV_BUILD) \( -name 'libuv.a' -o -name 'libuv_a.a' \) -exec cp {} $(LIBUV_A) \;
	@test -f $(LIBUV_A) || { echo "ERROR: libuv.a not found in luv build tree"; find $(LUV_BUILD) -name '*.a'; exit 1; }

# libuv.a is produced as a side effect of the libluv.a build above.
$(LIBUV_A): $(BUILD)/libluv.a ;

# Shared module + shared library, in a separate cmake dir to avoid clashing
# with the static configure.  Links against liblua.so to avoid duplicating
# the Lua runtime at load time.
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
	find $(LUV_BUILD)/shared -name 'luv.so' -exec cp {} $@ \;
	@test -f $@ || { echo "ERROR: luv.so not found"; \
	  find $(LUV_BUILD)/shared -name '*.so' -o -name '*.dylib'; exit 1; }

$(BUILD)/libluv.$(SHARED_EXT): $(BUILD)/luv.$(LUA_MOD_EXT)
	find $(LUV_BUILD)/shared -name 'libluv.$(SHARED_EXT)' -exec cp {} $@ \;
	@test -f $@ || { echo "ERROR: libluv.$(SHARED_EXT) not found"; \
	  find $(LUV_BUILD)/shared -name 'libluv*'; exit 1; }
