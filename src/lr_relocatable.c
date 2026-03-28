// SPDX-License-Identifier: AGPL-3.0-or-later

/*
 * lr_relocatable.c — exe-relative path resolution for lua-regolith
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Resolves the running executable's absolute path, computes the
 * installation root (dirname twice: bin/lua → root), and overrides
 * package.path and package.cpath with exe-relative values.
 *
 * Platform support:
 *   Linux:   readlink("/proc/self/exe")
 *   macOS:   _NSGetExecutablePath() + realpath()
 *   FreeBSD: sysctl(KERN_PROC_PATHNAME)
 *   Other:   falls back to /proc/self/exe (works on many Unices)
 *
 * If resolution fails, the interpreter silently keeps the compiled-in
 * defaults from luaconf.h — no error, no warning.
 *
 * Compile with:
 *   -DLR_LUA_SHORT='"5.4"'   (or whatever LUA_SHORT is)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#ifdef __linux__
#include <unistd.h>
#endif

#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

#ifdef __FreeBSD__
#include <sys/types.h>
#include <sys/sysctl.h>
#endif

#include "lua.h"
#include "lauxlib.h"
#include "lr_relocatable.h"

#ifndef LR_LUA_SHORT
#error "LR_LUA_SHORT must be defined at compile time (e.g. -DLR_LUA_SHORT='\"5.4\"')"
#endif

/* --------------------------------------------------------------------
 * Platform-specific exe resolution
 * -------------------------------------------------------------------- */

static int lr_get_exe_path(char *buf, size_t bufsz) {
#if defined(__linux__)

    ssize_t n = readlink("/proc/self/exe", buf, bufsz - 1);
    if (n < 0) return -1;
    buf[n] = '\0';
    return 0;

#elif defined(__APPLE__)

    uint32_t sz = (uint32_t)bufsz;
    if (_NSGetExecutablePath(buf, &sz) != 0) return -1;
    /* _NSGetExecutablePath may return a relative or symlinked path;
     * resolve to a canonical absolute path. */
    char *real = realpath(buf, NULL);
    if (!real) return -1;
    if (strlen(real) >= bufsz) { free(real); return -1; }
    strcpy(buf, real);
    free(real);
    return 0;

#elif defined(__FreeBSD__)

    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PATHNAME, -1 };
    size_t sz = bufsz;
    if (sysctl(mib, 4, buf, &sz, NULL, 0) != 0) return -1;
    return 0;

#else
    /* Best-effort fallback: try procfs anyway. */
    ssize_t n = readlink("/proc/self/exe", buf, bufsz - 1);
    if (n < 0) return -1;
    buf[n] = '\0';
    return 0;

#endif
}

/* --------------------------------------------------------------------
 * Path helpers
 * -------------------------------------------------------------------- */

/* Strip the last path component in-place (like dirname(3)).
 * "/a/b/c" → "/a/b",  "/a" → "/",  "/" → "/" */
static void lr_dirname(char *path) {
    char *last = strrchr(path, '/');
    if (!last) {
        /* No slash — shouldn't happen for absolute paths. */
        path[0] = '.'; path[1] = '\0';
    } else if (last == path) {
        /* Root slash — keep it. */
        path[1] = '\0';
    } else {
        *last = '\0';
    }
}

/* --------------------------------------------------------------------
 * Public entry point
 * -------------------------------------------------------------------- */

void lr_set_relocatable_paths(lua_State *L) {
    char exe[PATH_MAX];
    char root[PATH_MAX];

    /* Enough room for root + two template paths with expansions.
     * Each template is roughly:  root/share/lua/5.4/?.lua  (~40 chars)
     * We build 5 Lua-path templates + 3 C-path templates. */
    char path_buf[PATH_MAX * 4];
    char cpath_buf[PATH_MAX * 2];

    if (lr_get_exe_path(exe, sizeof(exe)) != 0)
        return;  /* silent fallback to luaconf.h defaults */

    /* exe   = /prefix/bin/lua
     * root  = /prefix               */
    if (strlen(exe) >= sizeof(root)) return;
    strcpy(root, exe);
    lr_dirname(root);   /* → /prefix/bin */
    lr_dirname(root);   /* → /prefix     */

    /* Build package.path — mirrors LUA_PATH_DEFAULT from luaconf.h */
    snprintf(path_buf, sizeof(path_buf),
        "%s/share/lua/%s/?.lua;"
        "%s/share/lua/%s/?/init.lua;"
        "%s/lib/lua/%s/?.lua;"
        "%s/lib/lua/%s/?/init.lua;"
        "./?.lua;"
        "./?/init.lua",
        root, LR_LUA_SHORT,
        root, LR_LUA_SHORT,
        root, LR_LUA_SHORT,
        root, LR_LUA_SHORT);

    /* Build package.cpath — mirrors LUA_CPATH_DEFAULT from luaconf.h */
    snprintf(cpath_buf, sizeof(cpath_buf),
        "%s/lib/lua/%s/?.so;"
        "%s/lib/lua/%s/loadall.so;"
        "./?.so",
        root, LR_LUA_SHORT,
        root, LR_LUA_SHORT);

    /* Override package.path and package.cpath */
    lua_getglobal(L, "package");
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        return;  /* package table not yet loaded — shouldn't happen */
    }

    lua_pushstring(L, path_buf);
    lua_setfield(L, -2, "path");

    lua_pushstring(L, cpath_buf);
    lua_setfield(L, -2, "cpath");

    lua_pop(L, 1);  /* pop package table */
}
