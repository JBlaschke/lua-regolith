/* SPDX-License-Identifier: AGPL-3.0-or-later */
/*
 * lr_preload_lua.h — Register embedded pure-Lua modules into package.preload
 *
 * Makes the static interpreter fully self-contained by embedding
 * dkjson, re, term, and posix Lua sources as C byte arrays.
 *
 * Call preload_bundled_lua_modules(L) after preload_bundled_modules(L).
 */

#ifndef LR_PRELOAD_LUA_H
#define LR_PRELOAD_LUA_H

#include "lua.h"

void preload_bundled_lua_modules(lua_State *L);

#endif /* LR_PRELOAD_LUA_H */
