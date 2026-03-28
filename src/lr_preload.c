/* SPDX-License-Identifier: AGPL-3.0-or-later */
/*
 * lr_preload.c — Register bundled C modules into package.preload
 *
 * This replaces the dynamically-generated preload_modules.c that the
 * Makefile used to produce via nm + shell scripts.  The module list is
 * hardcoded — if a symbol doesn't exist (e.g. luaposix drops a module
 * in a future release), the linker will catch it immediately.
 *
 * The luaposix module list matches luaposix 36.x's ext/posix/ layout.
 * When bumping LUAPOSIX_VER to a new major, audit the .c files in
 * ext/posix/ and ext/posix/sys/ for added/removed luaopen_* symbols.
 */

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "lr_preload.h"

/* ---- Forward declarations of all bundled luaopen functions ---- */

/* luaposix — top-level modules in ext/posix/ */
int luaopen_posix_ctype(lua_State *L);
int luaopen_posix_dirent(lua_State *L);
int luaopen_posix_errno(lua_State *L);
int luaopen_posix_fcntl(lua_State *L);
int luaopen_posix_fnmatch(lua_State *L);
int luaopen_posix_glob(lua_State *L);
int luaopen_posix_grp(lua_State *L);
int luaopen_posix_libgen(lua_State *L);
int luaopen_posix_poll(lua_State *L);
int luaopen_posix_pwd(lua_State *L);
int luaopen_posix_sched(lua_State *L);
int luaopen_posix_signal(lua_State *L);
int luaopen_posix_stdio(lua_State *L);
int luaopen_posix_stdlib(lua_State *L);
int luaopen_posix_syslog(lua_State *L);
int luaopen_posix_termio(lua_State *L);
int luaopen_posix_time(lua_State *L);
int luaopen_posix_unistd(lua_State *L);
int luaopen_posix_utime(lua_State *L);

/* luaposix — sys/ submodules in ext/posix/sys/ */
int luaopen_posix_sys_msg(lua_State *L);
int luaopen_posix_sys_resource(lua_State *L);
int luaopen_posix_sys_socket(lua_State *L);
int luaopen_posix_sys_stat(lua_State *L);
int luaopen_posix_sys_statvfs(lua_State *L);
int luaopen_posix_sys_time(lua_State *L);
int luaopen_posix_sys_times(lua_State *L);
int luaopen_posix_sys_utsname(lua_State *L);
int luaopen_posix_sys_wait(lua_State *L);

/* luv, lfs, lpeg, lua-term */
int luaopen_luv(lua_State *L);
int luaopen_lfs(lua_State *L);
int luaopen_lpeg(lua_State *L);
int luaopen_term_core(lua_State *L);

/* ---- Module registration table ---- */

static const struct {
    const char *name;
    lua_CFunction func;
} bundled_modules[] = {
    /* luaposix top-level */
    { "posix.ctype",          luaopen_posix_ctype },
    { "posix.dirent",         luaopen_posix_dirent },
    { "posix.errno",          luaopen_posix_errno },
    { "posix.fcntl",          luaopen_posix_fcntl },
    { "posix.fnmatch",        luaopen_posix_fnmatch },
    { "posix.glob",           luaopen_posix_glob },
    { "posix.grp",            luaopen_posix_grp },
    { "posix.libgen",         luaopen_posix_libgen },
    { "posix.poll",           luaopen_posix_poll },
    { "posix.pwd",            luaopen_posix_pwd },
    { "posix.sched",          luaopen_posix_sched },
    { "posix.signal",         luaopen_posix_signal },
    { "posix.stdio",          luaopen_posix_stdio },
    { "posix.stdlib",         luaopen_posix_stdlib },
    { "posix.syslog",         luaopen_posix_syslog },
    { "posix.termio",         luaopen_posix_termio },
    { "posix.time",           luaopen_posix_time },
    { "posix.unistd",         luaopen_posix_unistd },
    { "posix.utime",          luaopen_posix_utime },

    /* luaposix sys/ */
    { "posix.sys.msg",        luaopen_posix_sys_msg },
    { "posix.sys.resource",   luaopen_posix_sys_resource },
    { "posix.sys.socket",     luaopen_posix_sys_socket },
    { "posix.sys.stat",       luaopen_posix_sys_stat },
    { "posix.sys.statvfs",    luaopen_posix_sys_statvfs },
    { "posix.sys.time",       luaopen_posix_sys_time },
    { "posix.sys.times",      luaopen_posix_sys_times },
    { "posix.sys.utsname",    luaopen_posix_sys_utsname },
    { "posix.sys.wait",       luaopen_posix_sys_wait },

    /* other bundled modules */
    { "luv",                  luaopen_luv },
    { "lfs",                  luaopen_lfs },
    { "lpeg",                 luaopen_lpeg },
    { "term.core",            luaopen_term_core },

    { NULL, NULL }
};

/* ---- Public API ---- */

void preload_bundled_modules(lua_State *L) {
    luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
    for (int i = 0; bundled_modules[i].name != NULL; i++) {
        lua_pushcfunction(L, bundled_modules[i].func);
        lua_setfield(L, -2, bundled_modules[i].name);
    }
    lua_pop(L, 1);
}
