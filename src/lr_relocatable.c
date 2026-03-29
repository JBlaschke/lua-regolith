// SPDX-License-Identifier: AGPL-3.0-or-later

/*
 * lr_relocatable.c — exe-relative path resolution for lua-regolith
 *
 * Resolves the running executable's absolute path, computes the installation
 * root (dirname twice: bin/lua → root), and overrides package.path and
 * package.cpath with exe-relative values. Called immediately after
 * luaL_openlibs(L) in the patched lua.c. Resolves the real path of the running
 * executable, derives PREFIX, and sets package.path / package.cpath relative
 * to it — respecting LUA_PATH / LUA_CPATH environment variable overrides.
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

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#if defined(__linux__)
#include <unistd.h>
#include <linux/limits.h>
#elif defined(__APPLE__)
#include <mach-o/dyld.h>
#include <sys/syslimits.h>
#elif defined(__FreeBSD__)
#include <sys/types.h>
#include <sys/sysctl.h>
#include <limits.h>
#endif

#include "lua.h"
#include "lauxlib.h"
#include "lr_relocatable.h"

/* LR_LUA_SHORT is passed via -D at compile time, e.g. "5.4" */
#ifndef LR_LUA_SHORT
#  define LR_LUA_SHORT "5.4"
#endif

/* -----------------------------------------------------------------------
 * Platform-specific exe path resolution
 * ----------------------------------------------------------------------- */

static int lr_get_exe_path(char *buf, size_t bufsize) {
#if defined(__linux__)
    ssize_t len = readlink("/proc/self/exe", buf, bufsize - 1);
    if (len < 0) return -1;
    buf[len] = '\0';
    return 0;
#elif defined(__APPLE__)
    uint32_t size = (uint32_t)bufsize;
    if (_NSGetExecutablePath(buf, &size) != 0) return -1;
    /* Resolve symlinks */
    char real[PATH_MAX];
    if (realpath(buf, real) == NULL) return -1;
    strncpy(buf, real, bufsize - 1);
    buf[bufsize - 1] = '\0';
    return 0;
#elif defined(__FreeBSD__)
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PATHNAME, -1 };
    size_t len = bufsize;
    if (sysctl(mib, 4, buf, &len, NULL, 0) != 0) return -1;
    return 0;
#else
    (void)buf; (void)bufsize;
    return -1;
#endif
}

/* -----------------------------------------------------------------------
 * Strip the last N path components from a path (in-place).
 * E.g. strip_components("/opt/lua-regolith/bin/lua", 2)
 *    → "/opt/lua-regolith"
 * ----------------------------------------------------------------------- */

static void lr_strip_components(char *path, int n) {
    for (int i = 0; i < n; i++) {
        char *last = strrchr(path, '/');
        if (last && last != path)
            *last = '\0';
        else
            break;
    }
}

/* -----------------------------------------------------------------------
 * lr_apply_env — replicate Lua's env-var override protocol
 *
 * Lua's standard startup checks (for package.path):
 *   1. LUA_PATH_5_4  (versioned)
 *   2. LUA_PATH      (generic)
 *   3. compiled-in LUA_PATH_DEFAULT
 *
 * If an env var is set, every occurrence of ";;" in its value is replaced with
 * ";" + default + ";", and the result becomes package.path.  If no env var is
 * set, the default is used as-is.
 *
 * This function does exactly that, using `relocatable_default` as the default
 * (instead of the compiled-in value from luaconf.h).
 * ----------------------------------------------------------------------- */

static void lr_apply_env(lua_State *L,
                         const char *field,           /* "path" or "cpath"   */
                         const char *envname_ver,     /* "LUA_PATH_5_4" etc. */
                         const char *envname_generic, /* "LUA_PATH" etc.     */
                         const char *relocatable_default) {
    const char *env = getenv(envname_ver);
    if (env == NULL)
        env = getenv(envname_generic);

    /* Get the "package" table */
    lua_getglobal(L, "package");

    if (env == NULL) {
        /* No env override — use the relocatable default directly. */
        lua_pushstring(L, relocatable_default);
    } else {
        /*
         * Replace every ";;" with ";" + default + ";".
         *
         * We build the result in a Lua buffer, scanning for ";;". A single ";"
         * that is NOT part of ";;" is copied literally.
         */
        luaL_Buffer b;
        luaL_buffinit(L, &b);
        const char *p = env;
        while (*p) {
            if (p[0] == ';' && p[1] == ';') {
                /* Found ";;" — substitute the relocatable default. The
                 * leading/trailing ";" merge with the ";;":
                 *   "foo;;bar"  →  "foo;<default>;bar"
                 */
                luaL_addchar(&b, ';');
                luaL_addstring(&b, relocatable_default);
                luaL_addchar(&b, ';');
                p += 2;
            } else {
                luaL_addchar(&b, *p);
                p++;
            }
        }
        luaL_pushresult(&b);
    }

    lua_setfield(L, -2, field);
    lua_pop(L, 1); /* pop "package" */
}

/* -----------------------------------------------------------------------
 * lr_set_relocatable_paths — the entry point called from lua.c
 * ----------------------------------------------------------------------- */

void lr_set_relocatable_paths(lua_State *L) {
    char exe[PATH_MAX];
    if (lr_get_exe_path(exe, sizeof(exe)) != 0)
        return;  /* can't resolve exe — fall back to compiled-in defaults */

    /* exe = "/some/prefix/bin/lua"  →  prefix = "/some/prefix" */
    char prefix[PATH_MAX];
    strncpy(prefix, exe, sizeof(prefix) - 1);
    prefix[sizeof(prefix) - 1] = '\0';
    lr_strip_components(prefix, 2);  /* strip /bin/lua */

    /* Build the relocatable defaults — same structure as LUA_PATH_DEFAULT
     * and LUA_CPATH_DEFAULT in luaconf.h. */
    char path_default[PATH_MAX * 2];
    snprintf(path_default, sizeof(path_default),
             "%s/share/lua/" LR_LUA_SHORT "/?.lua;"
             "%s/share/lua/" LR_LUA_SHORT "/?/init.lua;"
             "%s/lib/lua/"   LR_LUA_SHORT "/?.lua;"
             "%s/lib/lua/"   LR_LUA_SHORT "/?/init.lua;"
             "./?.lua;./?/init.lua",
             prefix, prefix, prefix, prefix);

    char cpath_default[PATH_MAX * 2];
    snprintf(cpath_default, sizeof(cpath_default),
             "%s/lib/lua/" LR_LUA_SHORT "/?.so;"
             "%s/lib/lua/" LR_LUA_SHORT "/loadall.so;"
             "./?.so",
             prefix, prefix);

    /* Build the versioned env-var names: LUA_PATH_5_4, LUA_CPATH_5_4
     * We replace the dot in "5.4" with "_" to get "5_4". */
    char ver_suffix[16];
    strncpy(ver_suffix, LR_LUA_SHORT, sizeof(ver_suffix) - 1);
    ver_suffix[sizeof(ver_suffix) - 1] = '\0';
    for (char *c = ver_suffix; *c; c++) {
        if (*c == '.') *c = '_';
    }

    char envname_path_ver[32], envname_cpath_ver[32];
    snprintf(envname_path_ver,  sizeof(envname_path_ver),  "LUA_PATH_%s",  ver_suffix);
    snprintf(envname_cpath_ver, sizeof(envname_cpath_ver), "LUA_CPATH_%s", ver_suffix);

    lr_apply_env(L, "path",  envname_path_ver, "LUA_PATH",  path_default);
    lr_apply_env(L, "cpath", envname_cpath_ver, "LUA_CPATH", cpath_default);
}
