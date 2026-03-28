// SPDX-License-Identifier: AGPL-3.0-or-later

/*
 * lr_relocatable.h — exe-relative path resolution for lua-regolith
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * When lua-regolith is built with RELOCATABLE=1, this header is
 * force-included (-include) into the patched lua.c.  It declares
 * the single entry point that overrides package.path / package.cpath
 * at interpreter startup based on the executable's real location.
 *
 * LR_LUA_SHORT (e.g. "5.4") must be defined at compile time via
 * -DLR_LUA_SHORT='"5.4"'.
 */

#ifndef LR_RELOCATABLE_H
#define LR_RELOCATABLE_H

#include "lua.h"

/*
 * Resolve the running executable's absolute path, derive the
 * installation root (two levels up from bin/lua), and set
 * package.path and package.cpath to exe-relative values.
 *
 * Falls back silently to the compiled-in luaconf.h defaults
 * if exe resolution fails (e.g. unsupported platform, /proc
 * not mounted).
 */
void lr_set_relocatable_paths(lua_State *L);

#endif /* LR_RELOCATABLE_H */
