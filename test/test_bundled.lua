-- SPDX-License-Identifier: AGPL-3.0-or-later
-- ============================================================================
-- lua-regolith — comprehensive smoke tests
-- ============================================================================
--
-- Tests every exported function in every bundled module.  Each test checks
-- at minimum that the function exists and is callable; where safe, it also
-- validates return values.
--
-- Functions that are destructive (kill, exec*, _exit, chown, setuid, …),
-- require special privileges (chroot, sethostid, …), or alter global
-- process state (signal handlers, umask changes) are tested for existence
-- only and marked with "(exists)" in the test name.

local pass, fail, skip = 0, 0, 0

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

-- Check that a value is a function (for existence-only tests)
local function is_func(v)
   assert(type(v) == "function", "expected function, got " .. type(v))
end

-- Check that a value is a table (for sub-module tables)
local function is_table(v)
   assert(type(v) == "table", "expected table, got " .. type(v))
end

-- Temporary file/dir helpers
local tmpdir  = os.getenv("TMPDIR") or "/tmp"
local tmpfile = tmpdir .. "/lua-regolith-test-" .. os.time()

print("")
print("=== lua-regolith Comprehensive Smoke Tests ===")
print("  Lua version: " .. _VERSION)
print("")

-- ============================================================================
-- 1. Lua core
-- ============================================================================

print("--- Lua core ---")

test("Lua version starts with 'Lua 5.'", function()
   assert(_VERSION:match("^Lua 5%."), "unexpected: " .. _VERSION)
end)

-- ============================================================================
-- 2. luaposix — posix.unistd
-- ============================================================================

print("")
print("--- posix.unistd ---")

local unistd = require("posix.unistd")

test("getpid()", function()
   local pid = unistd.getpid()
   assert(type(pid) == "number" and pid > 0)
end)

test("getppid()", function()
   local ppid = unistd.getppid()
   assert(type(ppid) == "number" and ppid > 0)
end)

test("getuid()", function()
   local uid = unistd.getuid()
   assert(type(uid) == "number" and uid >= 0)
end)

test("geteuid()", function()
   local euid = unistd.geteuid()
   assert(type(euid) == "number" and euid >= 0)
end)

test("getgid()", function()
   local gid = unistd.getgid()
   assert(type(gid) == "number" and gid >= 0)
end)

test("getegid()", function()
   local egid = unistd.getegid()
   assert(type(egid) == "number" and egid >= 0)
end)

-- gethostname lives in posix.sys.utsname (via uname), not posix.unistd
if unistd.gethostname then
   test("gethostname()", function()
      local h = unistd.gethostname()
      assert(type(h) == "string" and #h > 0)
   end)
end

test("getcwd()", function()
   local cwd = unistd.getcwd()
   assert(type(cwd) == "string" and #cwd > 0)
end)

test("isatty(0)", function()
   local r = unistd.isatty(0)
   assert(type(r) == "boolean" or type(r) == "number")
end)

test("access('/') readable", function()
   local r = unistd.access("/", "r")
   assert(r == 0)
end)

test("pathconf('/', '_PC_NAME_MAX')", function()
   local v = unistd.pathconf("/", unistd._PC_NAME_MAX or 3)
   assert(type(v) == "number")
end)

test("sysconf(_SC_PAGESIZE)", function()
   local v = unistd.sysconf(unistd._SC_PAGESIZE or 30)
   assert(type(v) == "number" and v > 0)
end)

test("write+read via pipe()", function()
   local r, w = unistd.pipe()
   assert(type(r) == "number" and type(w) == "number")
   local msg = "hello"
   assert(unistd.write(w, msg) == #msg)
   local got = unistd.read(r, 100)
   assert(got == msg, "got: " .. tostring(got))
   unistd.close(r)
   unistd.close(w)
end)

test("lseek (exists)", function() is_func(unistd.lseek) end)
test("chdir (exists)", function() is_func(unistd.chdir) end)
test("link (exists)", function() is_func(unistd.link) end)
test("unlink (exists)", function() is_func(unistd.unlink) end)
test("rmdir (exists)", function() is_func(unistd.rmdir) end)
test("sleep (exists)", function() is_func(unistd.sleep) end)

-- These exist but are dangerous to call
test("fork (exists)", function() is_func(unistd.fork) end)
test("exec (exists)", function() is_func(unistd.exec) end)
test("execp (exists)", function() is_func(unistd.execp) end)
test("_exit (exists)", function() is_func(unistd._exit) end)

-- Optional / platform-dependent
if unistd.ttyname then
   test("ttyname (exists)", function() is_func(unistd.ttyname) end)
end
if unistd.crypt then
   test("crypt (exists)", function() is_func(unistd.crypt) end)
end
if unistd.getgroups then
   test("getgroups()", function()
      local g = unistd.getgroups()
      assert(type(g) == "table")
   end)
end

-- ============================================================================
-- 3. luaposix — posix.sys.stat
-- ============================================================================

print("")
print("--- posix.sys.stat ---")

local stat = require("posix.sys.stat")

test("stat('/')", function()
   local info = stat.stat("/")
   assert(info and info.st_ino)
   assert(type(info.st_mode) == "number")
   assert(type(info.st_size) == "number")
   assert(type(info.st_uid) == "number")
   assert(type(info.st_gid) == "number")
end)

test("lstat('/')", function()
   local info = stat.lstat("/")
   assert(info and info.st_ino)
end)

test("S_ISDIR on stat('/')", function()
   local info = stat.stat("/")
   assert(stat.S_ISDIR(info.st_mode) ~= 0)
end)

test("S_ISREG (exists)", function() is_func(stat.S_ISREG) end)
test("S_ISLNK (exists)", function() is_func(stat.S_ISLNK) end)
test("S_ISCHR (exists)", function() is_func(stat.S_ISCHR) end)
test("S_ISBLK (exists)", function() is_func(stat.S_ISBLK) end)
test("S_ISFIFO (exists)", function() is_func(stat.S_ISFIFO) end)
test("S_ISSOCK (exists)", function()
   if stat.S_ISSOCK then is_func(stat.S_ISSOCK) else skip = skip + 1 end
end)
test("chmod (exists)", function() is_func(stat.chmod) end)
test("mkdir (exists)", function() is_func(stat.mkdir) end)
test("mkfifo (exists)", function() is_func(stat.mkfifo) end)
test("umask (exists)", function() is_func(stat.umask) end)

-- ============================================================================
-- 4. luaposix — posix.errno
-- ============================================================================

print("")
print("--- posix.errno ---")

local errno = require("posix.errno")

test("ENOENT defined", function()
   assert(type(errno.ENOENT) == "number" and errno.ENOENT > 0)
end)

test("EACCES defined", function()
   assert(type(errno.EACCES) == "number" and errno.EACCES > 0)
end)

test("EEXIST defined", function()
   assert(type(errno.EEXIST) == "number" and errno.EEXIST > 0)
end)

test("EINVAL defined", function()
   assert(type(errno.EINVAL) == "number" and errno.EINVAL > 0)
end)

test("EPERM defined", function()
   assert(type(errno.EPERM) == "number" and errno.EPERM > 0)
end)

if errno.set_errno then
   test("set_errno (exists)", function() is_func(errno.set_errno) end)
end

-- ============================================================================
-- 5. luaposix — posix.fcntl
-- ============================================================================

print("")
print("--- posix.fcntl ---")

local fcntl = require("posix.fcntl")

test("open+close", function()
   local fd = fcntl.open("/dev/null", fcntl.O_RDONLY)
   assert(type(fd) == "number" and fd >= 0)
   unistd.close(fd)
end)

test("O_RDONLY defined", function()
   assert(type(fcntl.O_RDONLY) == "number")
end)

test("O_WRONLY defined", function()
   assert(type(fcntl.O_WRONLY) == "number")
end)

test("O_RDWR defined", function()
   assert(type(fcntl.O_RDWR) == "number")
end)

test("O_CREAT defined", function()
   assert(type(fcntl.O_CREAT) == "number")
end)

test("O_TRUNC defined", function()
   assert(type(fcntl.O_TRUNC) == "number")
end)

test("O_APPEND defined", function()
   assert(type(fcntl.O_APPEND) == "number")
end)

test("fcntl (exists)", function() is_func(fcntl.fcntl) end)

if fcntl.posix_fadvise then
   test("posix_fadvise (exists)", function() is_func(fcntl.posix_fadvise) end)
end

-- ============================================================================
-- 6. luaposix — posix.time
-- ============================================================================

print("")
print("--- posix.time ---")

local ptime = require("posix.time")

test("clock_gettime(CLOCK_REALTIME)", function()
   local ts = ptime.clock_gettime(0)
   assert(ts and ts.tv_sec > 0, "clock_gettime failed")
   assert(type(ts.tv_nsec) == "number")
end)

if ptime.clock_getres then
   test("clock_getres(CLOCK_REALTIME)", function()
      local ts = ptime.clock_getres(0)
      assert(ts and type(ts.tv_sec) == "number")
   end)
end

test("time()", function()
   local t = ptime.time()
   assert(type(t) == "number" and t > 0)
end)

test("gmtime()", function()
   local tm = ptime.gmtime(ptime.time())
   assert(type(tm) == "table")
   assert(type(tm.tm_year) == "number")
   assert(type(tm.tm_mon) == "number")
end)

test("localtime()", function()
   local tm = ptime.localtime(ptime.time())
   assert(type(tm) == "table")
   assert(type(tm.tm_year) == "number")
end)

test("mktime()", function()
   local tm = ptime.localtime(ptime.time())
   local t = ptime.mktime(tm)
   assert(type(t) == "number" and t > 0)
end)

test("strftime()", function()
   local tm = ptime.gmtime(ptime.time())
   local s = ptime.strftime("%Y-%m-%d", tm)
   assert(type(s) == "string" and #s == 10)
end)

test("nanosleep (exists)", function() is_func(ptime.nanosleep) end)
test("strptime (exists)", function()
   if ptime.strptime then is_func(ptime.strptime) end
end)

-- ============================================================================
-- 7. luaposix — posix.dirent
-- ============================================================================

print("")
print("--- posix.dirent ---")

local dirent = require("posix.dirent")

test("dir('/')", function()
   local d = dirent.dir("/")
   assert(type(d) == "table" and #d > 0)
end)

test("files('/')", function()
   if dirent.files then
      local n = 0
      for _ in dirent.files("/") do n = n + 1 end
      assert(n > 0)
   else
      is_func(dirent.dir)  -- fallback: at least dir exists
   end
end)

-- ============================================================================
-- 8. luaposix — posix.stdlib
-- ============================================================================

print("")
print("--- posix.stdlib ---")

local stdlib = require("posix.stdlib")

test("getenv('PATH')", function()
   local p = stdlib.getenv("PATH")
   assert(type(p) == "string" and #p > 0)
end)

if stdlib.setenv then
   test("setenv/getenv roundtrip", function()
      stdlib.setenv("_LR_TEST_VAR", "42")
      assert(stdlib.getenv("_LR_TEST_VAR") == "42")
      stdlib.setenv("_LR_TEST_VAR")  -- unset
   end)
end

if stdlib.mkdtemp then
   test("mkdtemp()", function()
      local d, err = stdlib.mkdtemp(tmpdir .. "/lr-test-XXXXXX")
      if d == nil and type(err) == "string" and err:find("not implemented") then
         -- function exists in binding but host libc lacks it
         print("         (skipped: " .. err .. ")")
         return
      end
      assert(type(d) == "string" and #d > 0, "mkdtemp failed: " .. tostring(err))
      unistd.rmdir(d)
   end)
end

if stdlib.mkstemp then
   test("mkstemp()", function()
      local fd, path = stdlib.mkstemp(tmpdir .. "/lr-test-XXXXXX")
      assert(type(fd) == "number" and fd >= 0)
      assert(type(path) == "string")
      unistd.close(fd)
      os.remove(path)
   end)
end

if stdlib.realpath then
   test("realpath('/')", function()
      local p = stdlib.realpath("/")
      assert(type(p) == "string" and p == "/")
   end)
end

test("abort (exists)", function()
   if stdlib.abort then is_func(stdlib.abort) end
end)

-- ============================================================================
-- 9. luaposix — posix.stdio
-- ============================================================================

print("")
print("--- posix.stdio ---")

local stdio = require("posix.stdio")

if stdio.rename then
   test("rename (exists)", function() is_func(stdio.rename) end)
end

if stdio.ctermid then
   test("ctermid()", function()
      local t = stdio.ctermid()
      assert(type(t) == "string")
   end)
end

if stdio.fdopen then
   test("fdopen (exists)", function() is_func(stdio.fdopen) end)
end

if stdio.fileno then
   test("fileno (exists)", function() is_func(stdio.fileno) end)
end

-- ============================================================================
-- 10. luaposix — posix.signal
-- ============================================================================

print("")
print("--- posix.signal ---")

local signal = require("posix.signal")

test("SIGINT defined", function()
   assert(type(signal.SIGINT) == "number")
end)

test("SIGTERM defined", function()
   assert(type(signal.SIGTERM) == "number")
end)

test("SIGKILL defined", function()
   assert(type(signal.SIGKILL) == "number")
end)

test("SIGUSR1 defined", function()
   assert(type(signal.SIGUSR1) == "number")
end)

test("SIGCHLD defined", function()
   assert(type(signal.SIGCHLD) == "number")
end)

test("signal (exists)", function()
   if signal.signal then is_func(signal.signal) end
end)

test("kill (exists)", function() is_func(signal.kill) end)

if signal.raise then
   test("raise (exists)", function() is_func(signal.raise) end)
end

-- ============================================================================
-- 11. luaposix — posix.pwd
-- ============================================================================

print("")
print("--- posix.pwd ---")

local pwd = require("posix.pwd")

test("getpwuid(getuid())", function()
   local pw = pwd.getpwuid(unistd.getuid())
   assert(type(pw) == "table")
   assert(type(pw.pw_name) == "string" and #pw.pw_name > 0)
   assert(type(pw.pw_dir) == "string")
end)

test("getpwnam(username)", function()
   local me = pwd.getpwuid(unistd.getuid())
   local pw = pwd.getpwnam(me.pw_name)
   assert(pw and pw.pw_uid == unistd.getuid())
end)

if pwd.getpwent then
   test("getpwent (exists)", function() is_func(pwd.getpwent) end)
end

if pwd.endpwent then
   test("endpwent (exists)", function() is_func(pwd.endpwent) end)
end

-- ============================================================================
-- 12. luaposix — posix.grp
-- ============================================================================

print("")
print("--- posix.grp ---")

local grp = require("posix.grp")

test("getgrgid(getgid())", function()
   local g = grp.getgrgid(unistd.getgid())
   assert(type(g) == "table")
   assert(type(g.gr_name) == "string")
end)

if grp.getgrnam then
   test("getgrnam(name)", function()
      local g0 = grp.getgrgid(unistd.getgid())
      local g = grp.getgrnam(g0.gr_name)
      assert(g and g.gr_gid == unistd.getgid())
   end)
end

if grp.getgrent then
   test("getgrent (exists)", function() is_func(grp.getgrent) end)
end

-- ============================================================================
-- 13. luaposix — posix.libgen
-- ============================================================================

print("")
print("--- posix.libgen ---")

local libgen = require("posix.libgen")

test("basename('/usr/bin/lua')", function()
   assert(libgen.basename("/usr/bin/lua") == "lua")
end)

test("dirname('/usr/bin/lua')", function()
   assert(libgen.dirname("/usr/bin/lua") == "/usr/bin")
end)

-- ============================================================================
-- 14. luaposix — posix.fnmatch
-- ============================================================================

print("")
print("--- posix.fnmatch ---")

local fnmatch = require("posix.fnmatch")

test("fnmatch('*.lua', 'test.lua')", function()
   local r = fnmatch.fnmatch("*.lua", "test.lua", 0)
   assert(r == 0, "expected match (0), got " .. tostring(r))
end)

test("fnmatch('*.c', 'test.lua') no match", function()
   local r = fnmatch.fnmatch("*.c", "test.lua", 0)
   assert(r ~= 0, "expected non-match")
end)

test("FNM_PATHNAME defined", function()
   assert(type(fnmatch.FNM_PATHNAME) == "number")
end)

-- ============================================================================
-- 15. luaposix — posix.glob
-- ============================================================================

print("")
print("--- posix.glob ---")

local glob = require("posix.glob")

test("glob('/tmp/*')", function()
   if glob.glob then
      local r = glob.glob("/tmp/*", 0)
      -- may return nil on empty /tmp, just check it doesn't error
      assert(r == nil or type(r) == "table")
   end
end)

-- ============================================================================
-- 16. luaposix — posix.poll
-- ============================================================================

print("")
print("--- posix.poll ---")

local poll = require("posix.poll")

test("poll (exists)", function() is_func(poll.poll) end)

test("poll with pipe (immediate data)", function()
   local r, w = unistd.pipe()
   unistd.write(w, "x")
   local fds = { [r] = { events = { IN = true } } }
   local ready = poll.poll(fds, 0)
   assert(type(ready) == "number")
   unistd.close(r)
   unistd.close(w)
end)

if poll.rpoll then
   test("rpoll (exists)", function() is_func(poll.rpoll) end)
end

-- ============================================================================
-- 17. luaposix — posix.syslog
-- ============================================================================

print("")
print("--- posix.syslog ---")

local syslog = require("posix.syslog")

test("LOG_ERR defined", function()
   assert(type(syslog.LOG_ERR) == "number")
end)

test("LOG_WARNING defined", function()
   assert(type(syslog.LOG_WARNING) == "number")
end)

test("LOG_USER defined", function()
   assert(type(syslog.LOG_USER) == "number")
end)

test("openlog (exists)", function() is_func(syslog.openlog) end)
test("syslog (exists)", function() is_func(syslog.syslog) end)
test("closelog (exists)", function() is_func(syslog.closelog) end)

-- ============================================================================
-- 18. luaposix — posix.sys.resource
-- ============================================================================

print("")
print("--- posix.sys.resource ---")

local resource = require("posix.sys.resource")

test("getrlimit(RLIMIT_NOFILE)", function()
   if resource.getrlimit and resource.RLIMIT_NOFILE then
      local r = resource.getrlimit(resource.RLIMIT_NOFILE)
      assert(type(r) == "table")
      assert(type(r.rlim_cur) == "number")
   end
end)

test("setrlimit (exists)", function()
   if resource.setrlimit then is_func(resource.setrlimit) end
end)

test("getrusage (exists)", function()
   if resource.getrusage then is_func(resource.getrusage) end
end)

-- ============================================================================
-- 19. luaposix — posix.sys.socket
-- ============================================================================

print("")
print("--- posix.sys.socket ---")

local socket = require("posix.sys.socket")

test("AF_INET defined", function()
   assert(type(socket.AF_INET) == "number")
end)

test("AF_UNIX defined", function()
   assert(type(socket.AF_UNIX) == "number")
end)

test("SOCK_STREAM defined", function()
   assert(type(socket.SOCK_STREAM) == "number")
end)

test("SOCK_DGRAM defined", function()
   assert(type(socket.SOCK_DGRAM) == "number")
end)

test("socket+close (AF_INET, SOCK_STREAM)", function()
   local fd = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0)
   assert(type(fd) == "number" and fd >= 0)
   unistd.close(fd)
end)

test("bind (exists)", function() is_func(socket.bind) end)
test("listen (exists)", function() is_func(socket.listen) end)
test("accept (exists)", function() is_func(socket.accept) end)
test("connect (exists)", function() is_func(socket.connect) end)
test("send (exists)", function() is_func(socket.send) end)
test("recv (exists)", function() is_func(socket.recv) end)
test("sendto (exists)", function() is_func(socket.sendto) end)
test("recvfrom (exists)", function() is_func(socket.recvfrom) end)
test("setsockopt (exists)", function() is_func(socket.setsockopt) end)
test("getaddrinfo (exists)", function() is_func(socket.getaddrinfo) end)

-- ============================================================================
-- 20. luaposix — posix.sys.time
-- ============================================================================

print("")
print("--- posix.sys.time ---")

local systime = require("posix.sys.time")

test("gettimeofday()", function()
   local tv = systime.gettimeofday()
   assert(type(tv) == "table")
   assert(type(tv.tv_sec) == "number" and tv.tv_sec > 0)
   assert(type(tv.tv_usec) == "number")
end)

-- ============================================================================
-- 21. luaposix — posix.sys.times
-- ============================================================================

print("")
print("--- posix.sys.times ---")

local times = require("posix.sys.times")

test("times()", function()
   local t = times.times()
   assert(type(t) == "table")
   assert(type(t.tms_utime) == "number")
   assert(type(t.tms_stime) == "number")
end)

-- ============================================================================
-- 22. luaposix — posix.sys.utsname
-- ============================================================================

print("")
print("--- posix.sys.utsname ---")

local utsname = require("posix.sys.utsname")

test("uname()", function()
   local u = utsname.uname()
   assert(type(u) == "table")
   assert(type(u.sysname) == "string" and #u.sysname > 0)
   assert(type(u.nodename) == "string")
   assert(type(u.release) == "string")
   assert(type(u.machine) == "string")
end)

-- ============================================================================
-- 23. luaposix — posix.sys.wait
-- ============================================================================

print("")
print("--- posix.sys.wait ---")

local wait = require("posix.sys.wait")

test("wait (exists)", function() is_func(wait.wait) end)

test("fork+wait roundtrip", function()
   local pid = unistd.fork()
   if pid == 0 then
      unistd._exit(42)
   else
      local wpid, status, code = wait.wait(pid)
      assert(wpid == pid, "wrong pid")
   end
end)

-- ============================================================================
-- 24. luaposix — posix.sys.statvfs (optional — Linux only)
-- ============================================================================

print("")
print("--- posix.sys.statvfs ---")

local ok_statvfs, statvfs = pcall(require, "posix.sys.statvfs")
if ok_statvfs and statvfs.statvfs then
   test("statvfs('/')", function()
      local s = statvfs.statvfs("/")
      assert(type(s) == "table")
      assert(type(s.f_bsize) == "number" and s.f_bsize > 0)
   end)
else
   print("  SKIP  posix.sys.statvfs (not available on this platform)")
   skip = skip + 1
end

-- ============================================================================
-- 25. luaposix — posix.termio
-- ============================================================================

print("")
print("--- posix.termio ---")

local termio = require("posix.termio")

test("tcgetattr (exists)", function() is_func(termio.tcgetattr) end)
test("tcsetattr (exists)", function() is_func(termio.tcsetattr) end)

if termio.tcsendbreak then
   test("tcsendbreak (exists)", function() is_func(termio.tcsendbreak) end)
end
if termio.tcdrain then
   test("tcdrain (exists)", function() is_func(termio.tcdrain) end)
end
if termio.tcflush then
   test("tcflush (exists)", function() is_func(termio.tcflush) end)
end

-- ============================================================================
-- 26. luaposix — posix.utime
-- ============================================================================

print("")
print("--- posix.utime ---")

local utime = require("posix.utime")

test("utime on tmpfile", function()
   local f = io.open(tmpfile, "w")
   f:write("test")
   f:close()
   local now = os.time()
   local r = utime.utime(tmpfile, now, now)
   assert(r == 0 or r == nil or type(r) == "number")
   os.remove(tmpfile)
end)

-- ============================================================================
-- 27. luaposix — posix.ctype
-- ============================================================================

print("")
print("--- posix.ctype ---")

local ctype = require("posix.ctype")

if ctype.isalpha then
   test("isalpha('A')", function()
      assert(ctype.isalpha("A") ~= 0)
   end)
   test("isalpha('1') == 0", function()
      assert(ctype.isalpha("1") == 0)
   end)
end

if ctype.isdigit then
   test("isdigit('5')", function()
      assert(ctype.isdigit("5") ~= 0)
   end)
end

if ctype.isspace then
   test("isspace(' ')", function()
      assert(ctype.isspace(" ") ~= 0)
   end)
end

if ctype.isupper then
   test("isupper('A')", function()
      assert(ctype.isupper("A") ~= 0)
   end)
end

if ctype.islower then
   test("islower('a')", function()
      assert(ctype.islower("a") ~= 0)
   end)
end

-- ============================================================================
-- 28. luaposix — posix.sched (optional — mostly Linux)
-- ============================================================================

print("")
print("--- posix.sched ---")

local ok_sched, sched = pcall(require, "posix.sched")
if ok_sched then
   if sched.sched_getscheduler then
      test("sched_getscheduler (exists)", function()
         is_func(sched.sched_getscheduler)
      end)
   end
   if sched.sched_setscheduler then
      test("sched_setscheduler (exists)", function()
         is_func(sched.sched_setscheduler)
      end)
   end
else
   print("  SKIP  posix.sched (not available on this platform)")
   skip = skip + 1
end

-- ============================================================================
-- 29. luaposix — posix.sys.msg (optional — SysV message queues)
-- ============================================================================

print("")
print("--- posix.sys.msg ---")

local ok_msg, sysmsg = pcall(require, "posix.sys.msg")
if ok_msg then
   test("msgget (exists)", function()
      if sysmsg.msgget then is_func(sysmsg.msgget) end
   end)
else
   print("  SKIP  posix.sys.msg (not available on this platform)")
   skip = skip + 1
end

-- ============================================================================
-- 30. luv (libuv bindings)
-- ============================================================================

print("")
print("--- luv ---")

local luv = require("luv")

-- Version / metadata
test("luv.version()", function()
   local v = luv.version()
   assert(type(v) == "number" and v > 0)
end)

test("luv.version_string()", function()
   local v = luv.version_string()
   assert(type(v) == "string" and #v > 0)
end)

-- Loop
test("luv.loop_alive()", function()
   local r = luv.loop_alive()
   assert(type(r) == "boolean")
end)

test("luv.loop_close()", function()
   -- just verify exists; actual close may fail if handles open
   is_func(luv.loop_close)
end)

test("luv.run()", function()
   -- empty loop should return immediately
   luv.run("nowait")
end)

test("luv.now()", function()
   local t = luv.now()
   assert(type(t) == "number" and t >= 0)
end)

test("luv.hrtime()", function()
   local t = luv.hrtime()
   assert(type(t) == "number" and t > 0)
end)

-- Timers
test("luv timer fire", function()
   local fired = false
   local t = luv.new_timer()
   t:start(1, 0, function() fired = true; t:stop(); t:close() end)
   luv.run()
   assert(fired, "timer never fired")
end)

test("luv.new_timer()", function()
   local t = luv.new_timer()
   assert(t)
   t:close()
   luv.run("nowait")
end)

-- Filesystem
test("luv.fs_stat('/')", function()
   local s = luv.fs_stat("/")
   assert(s and s.type == "directory")
   assert(type(s.size) == "number")
   assert(type(s.ino) == "number")
end)

test("luv.fs_lstat('/')", function()
   local s = luv.fs_lstat("/")
   assert(s and s.type == "directory")
end)

test("luv.fs_open+read+close", function()
   local f = io.open(tmpfile, "w")
   f:write("hello from luv")
   f:close()
   local fd = luv.fs_open(tmpfile, "r", 438)
   assert(fd)
   local data = luv.fs_read(fd, 100, 0)
   assert(data == "hello from luv")
   luv.fs_close(fd)
   os.remove(tmpfile)
end)

test("luv.fs_write", function()
   local fd = luv.fs_open(tmpfile, "w", 438)
   assert(fd)
   luv.fs_write(fd, "test data", 0)
   luv.fs_close(fd)
   os.remove(tmpfile)
end)

test("luv.fs_scandir('/')", function()
   local req = luv.fs_scandir("/")
   assert(req)
   local name, typ = luv.fs_scandir_next(req)
   assert(type(name) == "string")
end)

test("luv.fs_realpath('/')", function()
   local p = luv.fs_realpath("/")
   assert(type(p) == "string" and p == "/")
end)

test("luv.fs_mkdir+rmdir", function()
   local d = tmpdir .. "/lr-luv-test-" .. os.time()
   assert(luv.fs_mkdir(d, 493))
   assert(luv.fs_rmdir(d))
end)

test("luv.fs_rename", function() is_func(luv.fs_rename) end)
test("luv.fs_unlink", function() is_func(luv.fs_unlink) end)
test("luv.fs_fstat", function() is_func(luv.fs_fstat) end)
test("luv.fs_access", function() is_func(luv.fs_access) end)
test("luv.fs_chmod", function() is_func(luv.fs_chmod) end)
test("luv.fs_link", function() is_func(luv.fs_link) end)
test("luv.fs_symlink", function() is_func(luv.fs_symlink) end)
test("luv.fs_readlink", function() is_func(luv.fs_readlink) end)
test("luv.fs_mkdtemp", function() is_func(luv.fs_mkdtemp) end)

if luv.fs_mkstemp then
   test("luv.fs_mkstemp", function() is_func(luv.fs_mkstemp) end)
end

if luv.fs_copyfile then
   test("luv.fs_copyfile", function() is_func(luv.fs_copyfile) end)
end

if luv.fs_statfs then
   test("luv.fs_statfs('/')", function()
      local s = luv.fs_statfs("/")
      assert(type(s) == "table")
   end)
end

-- DNS
test("luv.getaddrinfo('localhost')", function()
   local res = luv.getaddrinfo("localhost", nil, { family = "inet" })
   assert(type(res) == "table" and #res > 0)
   assert(type(res[1].addr) == "string")
end)

-- TCP
test("luv.new_tcp()", function()
   local t = luv.new_tcp()
   assert(t)
   t:close()
   luv.run("nowait")
end)

test("tcp:bind", function()
   local t = luv.new_tcp()
   local ok = t:bind("127.0.0.1", 0)
   assert(ok == 0 or ok == true)
   local addr = t:getsockname()
   assert(type(addr) == "table")
   assert(type(addr.port) == "number" and addr.port > 0)
   t:close()
   luv.run("nowait")
end)

-- UDP
test("luv.new_udp()", function()
   local u = luv.new_udp()
   assert(u)
   u:close()
   luv.run("nowait")
end)

-- Pipe
test("luv.new_pipe()", function()
   local p = luv.new_pipe()
   assert(p)
   p:close()
   luv.run("nowait")
end)

test("luv.pipe()", function()
   if luv.pipe then
      local a, b = luv.pipe()
      if type(a) == "table" then
         -- returns {read=fd, write=fd} or {read=handle, write=handle}
         assert(a.read and a.write)
         if type(a.read) == "number" then
            unistd.close(a.read)
            unistd.close(a.write)
         else
            a.read:close()
            a.write:close()
            luv.run("nowait")
         end
      elseif type(a) == "number" then
         -- two raw file descriptors
         assert(type(b) == "number", "expected two fds")
         unistd.close(a)
         unistd.close(b)
      else
         -- two userdata handles
         assert(a and b)
         a:close()
         if b then b:close() end
         luv.run("nowait")
      end
   end
end)

-- Process info
test("luv.os_getpid()", function()
   if luv.os_getpid then
      local pid = luv.os_getpid()
      assert(type(pid) == "number" and pid > 0)
   end
end)

test("luv.os_getppid()", function()
   if luv.os_getppid then
      local ppid = luv.os_getppid()
      assert(type(ppid) == "number" and ppid > 0)
   end
end)

test("luv.cwd()", function()
   local c = luv.cwd()
   assert(type(c) == "string" and #c > 0)
end)

test("luv.exepath()", function()
   local p = luv.exepath()
   assert(type(p) == "string" and #p > 0)
end)

test("luv.os_homedir()", function()
   if luv.os_homedir then
      local h = luv.os_homedir()
      assert(type(h) == "string" and #h > 0)
   end
end)

test("luv.os_tmpdir()", function()
   if luv.os_tmpdir then
      local t = luv.os_tmpdir()
      assert(type(t) == "string" and #t > 0)
   end
end)

test("luv.os_uname()", function()
   if luv.os_uname then
      local u = luv.os_uname()
      assert(type(u) == "table")
      assert(type(u.sysname) == "string")
   end
end)

-- Resource usage
test("luv.resident_set_memory()", function()
   local m = luv.resident_set_memory()
   assert(type(m) == "number" and m > 0)
end)

test("luv.get_total_memory()", function()
   local m = luv.get_total_memory()
   assert(type(m) == "number" and m > 0)
end)

test("luv.get_free_memory()", function()
   local m = luv.get_free_memory()
   assert(type(m) == "number" and m > 0)
end)

test("luv.getrusage()", function()
   local r = luv.getrusage()
   assert(type(r) == "table")
end)

test("luv.uptime()", function()
   local u = luv.uptime()
   assert(type(u) == "number" and u > 0)
end)

test("luv.cpu_info()", function()
   local c = luv.cpu_info()
   assert(type(c) == "table" and #c > 0)
end)

-- Misc
test("luv.sleep (exists)", function()
   if luv.sleep then is_func(luv.sleep) end
end)

test("luv.new_signal (exists)", function() is_func(luv.new_signal) end)
test("luv.new_poll (exists)", function() is_func(luv.new_poll) end)
test("luv.new_idle (exists)", function() is_func(luv.new_idle) end)
test("luv.new_check (exists)", function() is_func(luv.new_check) end)
test("luv.new_prepare (exists)", function() is_func(luv.new_prepare) end)
test("luv.new_async (exists)", function() is_func(luv.new_async) end)
test("luv.spawn (exists)", function() is_func(luv.spawn) end)

if luv.new_thread then
   test("luv.new_thread (exists)", function() is_func(luv.new_thread) end)
end

-- Environment
test("luv.os_environ()", function()
   if luv.os_environ then
      local e = luv.os_environ()
      assert(type(e) == "table")
   end
end)

test("luv.os_getenv('PATH')", function()
   if luv.os_getenv then
      local p = luv.os_getenv("PATH")
      assert(type(p) == "string" and #p > 0)
   end
end)

-- ============================================================================
-- 31. luafilesystem (lfs)
-- ============================================================================

print("")
print("--- lfs ---")

local lfs = require("lfs")

test("lfs.attributes('/')", function()
   local a = lfs.attributes("/")
   assert(a and a.mode == "directory")
   assert(type(a.size) == "number")
   assert(type(a.ino) == "number")
   assert(type(a.uid) == "number")
   assert(type(a.gid) == "number")
   assert(type(a.permissions) == "string")
end)

test("lfs.attributes('/', 'mode')", function()
   local m = lfs.attributes("/", "mode")
   assert(m == "directory")
end)

test("lfs.symlinkattributes (exists)", function()
   is_func(lfs.symlinkattributes)
end)

test("lfs.dir('/')", function()
   local entries = {}
   for name in lfs.dir("/") do
      entries[#entries + 1] = name
   end
   assert(#entries > 0)
   -- . and .. should be present
   local found_dot = false
   for _, e in ipairs(entries) do
      if e == "." then found_dot = true end
   end
   assert(found_dot, ". not found in dir listing")
end)

test("lfs.currentdir()", function()
   local d = lfs.currentdir()
   assert(type(d) == "string" and #d > 0)
end)

test("lfs.chdir+currentdir roundtrip", function()
   local orig = lfs.currentdir()
   assert(lfs.chdir("/"))
   assert(lfs.currentdir() == "/")
   assert(lfs.chdir(orig))
end)

test("lfs.mkdir+rmdir", function()
   local d = tmpdir .. "/lr-lfs-test-" .. os.time()
   assert(lfs.mkdir(d))
   local a = lfs.attributes(d)
   assert(a and a.mode == "directory")
   assert(lfs.rmdir(d))
end)

test("lfs.touch", function()
   local f = io.open(tmpfile, "w")
   f:write("touch test")
   f:close()
   local now = os.time()
   assert(lfs.touch(tmpfile, now, now))
   local a = lfs.attributes(tmpfile)
   assert(a.modification == now)
   os.remove(tmpfile)
end)

test("lfs.lock+unlock", function()
   local f = io.open(tmpfile, "w")
   f:write("lock test")
   assert(lfs.lock(f, "w"))
   assert(lfs.unlock(f))
   f:close()
   os.remove(tmpfile)
end)

test("lfs.link", function()
   is_func(lfs.link)
end)

test("lfs.setmode (exists)", function()
   if lfs.setmode then
      is_func(lfs.setmode)
   end
end)

test("lfs.lock_dir (exists)", function()
   if lfs.lock_dir then
      is_func(lfs.lock_dir)
   end
end)

-- ============================================================================
-- 32. lpeg
-- ============================================================================

print("")
print("--- lpeg ---")

local lpeg = require("lpeg")

test("lpeg.version", function()
   assert(type(lpeg.version) == "string" and #lpeg.version > 0)
end)

-- Pattern constructors
test("lpeg.P (literal)", function()
   local p = lpeg.P("hello")
   assert(lpeg.match(p, "hello world") == 6)
   assert(lpeg.match(p, "goodbye") == nil)
end)

test("lpeg.P (number)", function()
   assert(lpeg.match(lpeg.P(3), "abcde") == 4)
   assert(lpeg.match(lpeg.P(3), "ab") == nil)
end)

test("lpeg.P (boolean)", function()
   assert(lpeg.match(lpeg.P(true), "") == 1)
   assert(lpeg.match(lpeg.P(false), "abc") == nil)
end)

test("lpeg.R (range)", function()
   local digit = lpeg.R("09")
   assert(lpeg.match(digit, "5") == 2)
   assert(lpeg.match(digit, "a") == nil)
end)

test("lpeg.S (set)", function()
   local vowel = lpeg.S("aeiou")
   assert(lpeg.match(vowel, "a") == 2)
   assert(lpeg.match(vowel, "b") == nil)
end)

test("lpeg.B (behind)", function()
   -- Match 'b' only if preceded by 'a'
   local p = lpeg.P("a") * lpeg.B(lpeg.P("a")) * lpeg.P("b")
   assert(lpeg.match(p, "ab") == 3)
end)

test("lpeg.V (grammar variable)", function()
   local g = lpeg.P{ "S",
      S = lpeg.V("A") * lpeg.V("B"),
      A = lpeg.P("a"),
      B = lpeg.P("b"),
   }
   assert(lpeg.match(g, "ab") == 3)
end)

-- Repetition and combinators
test("pattern^n (repetition)", function()
   local digits = lpeg.R("09")^1
   assert(lpeg.match(digits, "12345abc") == 6)
end)

test("pattern * pattern (sequence)", function()
   local p = lpeg.P("ab") * lpeg.P("cd")
   assert(lpeg.match(p, "abcd") == 5)
end)

test("pattern + pattern (choice)", function()
   local p = lpeg.P("ab") + lpeg.P("cd")
   assert(lpeg.match(p, "ab") == 3)
   assert(lpeg.match(p, "cd") == 3)
end)

test("-pattern (not predicate)", function()
   local p = -lpeg.P("ab") * lpeg.P(1)
   assert(lpeg.match(p, "cd") == 2)
   assert(lpeg.match(p, "ab") == nil)
end)

-- Captures
test("lpeg.C (simple capture)", function()
   local p = lpeg.C(lpeg.R("az")^1)
   assert(lpeg.match(p, "hello") == "hello")
end)

test("lpeg.Cc (constant capture)", function()
   local p = lpeg.Cc("constant")
   assert(lpeg.match(p, "") == "constant")
end)

test("lpeg.Cp (position capture)", function()
   local p = lpeg.P("ab") * lpeg.Cp()
   assert(lpeg.match(p, "abc") == 3)
end)

test("lpeg.Cs (substitution capture)", function()
   local p = lpeg.Cs((lpeg.P("a") / "b" + lpeg.P(1))^0)
   assert(lpeg.match(p, "abac") == "bbbc")
end)

test("lpeg.Ct (table capture)", function()
   local p = lpeg.Ct(lpeg.C(lpeg.R("az")^1) * (lpeg.P(",") * lpeg.C(lpeg.R("az")^1))^0)
   local t = lpeg.match(p, "one,two,three")
   assert(type(t) == "table")
   assert(t[1] == "one" and t[2] == "two" and t[3] == "three")
end)

test("lpeg.Cf (fold capture)", function()
   local function add(a, b) return a + tonumber(b) end
   local digit = lpeg.C(lpeg.R("09")^1)
   local p = lpeg.Cf(digit * (lpeg.P("+") * digit)^0, add)
   assert(lpeg.match(p, "1+2+3") == 6)
end)

test("lpeg.Cg (group capture)", function()
   local p = lpeg.Ct(lpeg.Cg(lpeg.C(lpeg.P("a")), "letter"))
   local t = lpeg.match(p, "a")
   assert(type(t) == "table" and t.letter == "a")
end)

test("lpeg.Cb (back capture, exists)", function()
   -- Cb semantics vary across lpeg versions; just verify it exists
   -- and can be used to construct a pattern.
   assert(type(lpeg.Cb) == "function")
   local p = lpeg.Cb("tag")
   assert(lpeg.type(p) == "pattern")
end)

test("lpeg.Carg (argument capture)", function()
   local p = lpeg.Carg(1)
   assert(lpeg.match(p, "", 1, "extra") == "extra")
end)

test("lpeg.Cmt (match-time capture)", function()
   local p = lpeg.Cmt(lpeg.C(lpeg.R("az")^1), function(s, i, val)
      return i, val:upper()
   end)
   assert(lpeg.match(p, "hello") == "HELLO")
end)

-- Utilities
test("lpeg.locale()", function()
   local loc = lpeg.locale()
   assert(type(loc) == "table")
   assert(loc.digit)
   assert(loc.alpha)
   assert(loc.space)
   assert(loc.lower)
   assert(loc.upper)
   assert(loc.alnum)
   assert(loc.punct)
end)

test("lpeg.type()", function()
   assert(lpeg.type(lpeg.P("a")) == "pattern")
   assert(lpeg.type("hello") ~= "pattern")
end)

test("lpeg.setmaxstack (exists)", function() is_func(lpeg.setmaxstack) end)

-- ============================================================================
-- 33. re (regex module on top of lpeg)
-- ============================================================================

print("")
print("--- re ---")

local re = require("re")

test("re.find('hello', '[a-z]+')", function()
   local s, e = re.find("hello", "[a-z]+")
   assert(s == 1 and e == 5)
end)

test("re.match", function()
   local m = re.match("123", "[0-9]+")
   assert(m == 4)  -- returns position after match
end)

test("re.gsub", function()
   local result = re.gsub("hello world", "[a-z]+", "X")
   assert(result == "X X")
end)

test("re.compile", function()
   local p = re.compile("[a-z]+")
   assert(lpeg.type(p) == "pattern")
end)

-- ============================================================================
-- 34. lua-term
-- ============================================================================

print("")
print("--- term.core ---")

local term_core = require("term.core")

test("isatty (exists)", function()
   is_func(term_core.isatty)
end)

test("isatty(io.stdout) returns boolean/number", function()
   local r = term_core.isatty(io.stdout)
   assert(type(r) == "boolean" or type(r) == "number")
end)

-- ============================================================================
-- 35. dkjson
-- ============================================================================

print("")
print("--- dkjson ---")

local json = require("dkjson")

test("dkjson.encode (simple table)", function()
   local s = json.encode({ hello = "world", n = 42 })
   assert(type(s) == "string" and #s > 0)
end)

test("dkjson.decode (object)", function()
   local t = json.decode('{"a":1,"b":"two"}')
   assert(type(t) == "table")
   assert(t.a == 1 and t.b == "two")
end)

test("dkjson roundtrip (nested)", function()
   local orig = {
      name = "test",
      numbers = {1, 2, 3},
      nested = { x = true, y = false },
   }
   local decoded = json.decode(json.encode(orig))
   assert(decoded.name == "test")
   assert(#decoded.numbers == 3)
   assert(decoded.numbers[2] == 2)
   assert(decoded.nested.x == true)
   assert(decoded.nested.y == false)
end)

test("dkjson.encode (array)", function()
   local s = json.encode({1, 2, 3})
   assert(s == "[1,2,3]" or s:match("%["))  -- formatting may vary
end)

test("dkjson.encode (string escaping)", function()
   local s = json.encode({ s = 'hello "world"\nnewline' })
   assert(s:find('\\"world\\"'))
   assert(s:find('\\n'))
end)

test("dkjson.encode (unicode)", function()
   local s = json.encode({ s = "café" })
   assert(type(s) == "string")
end)

test("dkjson.null", function()
   assert(json.null ~= nil)
   local s = json.encode({ a = json.null })
   assert(s:find("null"))
end)

test("dkjson.decode returns position", function()
   local t, pos = json.decode('{"a":1}')
   assert(type(pos) == "number" and pos > 1)
end)

test("dkjson.decode (null handling)", function()
   -- dkjson decodes JSON null as json.null only when using the
   -- object/array metatable hooks.  By default, null becomes nil
   -- (absent from the table).  Just verify it doesn't error.
   local t = json.decode('{"a":null,"b":1}')
   assert(type(t) == "table")
   assert(t.b == 1)
   -- a is either nil or json.null depending on configuration
   assert(t.a == nil or t.a == json.null)
end)

test("dkjson.decode error handling", function()
   local t, pos, err = json.decode("{invalid json")
   assert(t == nil)
   assert(type(err) == "string")
end)

test("dkjson.quotestring (exists)", function()
   if json.quotestring then
      local q = json.quotestring('hello "world"')
      assert(type(q) == "string")
   end
end)

test("dkjson.encode with state (indent)", function()
   local s = json.encode({ a = 1 }, { indent = true })
   assert(type(s) == "string")
   assert(s:find("\n"))  -- should have newlines when indented
end)

test("dkjson.use_lpeg()", function()
   if json.use_lpeg then
      json.use_lpeg()
   end
end)

-- ============================================================================
-- Summary
-- ============================================================================

print("")
print(string.format("Results: %d passed, %d failed, %d skipped", pass, fail, skip))
if fail > 0 then
   print("SOME TESTS FAILED")
   os.exit(1)
else
   print("ALL TESTS PASSED")
end
