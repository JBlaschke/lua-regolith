/* SPDX-License-Identifier: AGPL-3.0-or-later */
/*
 * lr_preload.h — Register bundled C modules into package.preload
 *
 * Used by the fully-static lua interpreter (lua-static) so that
 * require("luv"), require("posix.unistd"), etc. resolve without
 * needing .so files on disk.
 *
 * Call preload_bundled_modules(L) after luaL_openlibs(L) in pmain().
 */

#ifndef LR_PRELOAD_H
#define LR_PRELOAD_H

#include "lua.h"

void preload_bundled_modules(lua_State *L);

#endif /* LR_PRELOAD_H */
