const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&futimesLinux, "futimes");
        symbol(&lutimesLinux, "lutimes");
    }
}

fn futimesLinux(fd: c_int, tv: ?*const [2]linux.timeval) callconv(.c) c_int {
    if (tv) |t| {
        const times = [2]linux.timespec{
            .{ .sec = t[0].sec, .nsec = @intCast(t[0].usec * 1000) },
            .{ .sec = t[1].sec, .nsec = @intCast(t[1].usec * 1000) },
        };
        return errno(linux.futimens(fd, &times));
    }
    return errno(linux.futimens(fd, null));
}

fn lutimesLinux(path: [*:0]const u8, tv: ?*const [2]linux.timeval) callconv(.c) c_int {
    if (tv) |t| {
        const times = [2]linux.timespec{
            .{ .sec = t[0].sec, .nsec = @intCast(t[0].usec * 1000) },
            .{ .sec = t[1].sec, .nsec = @intCast(t[1].usec * 1000) },
        };
        return errno(linux.utimensat(linux.AT.FDCWD, path, &times, linux.AT.SYMLINK_NOFOLLOW));
    }
    return errno(linux.utimensat(linux.AT.FDCWD, path, null, linux.AT.SYMLINK_NOFOLLOW));

comptime {
    if (builtin.target.isMuslLibC()) {
        // utmpx stubs — Linux does not implement utmp/wtmp in musl
        symbol(&euidaccessLinux, "euidaccess");
        symbol(&euidaccessLinux, "eaccess");
        // isastream is exported by stropts.zig
        symbol(&getdtablesizeLinux, "getdtablesize");
        symbol(&getloadavgLinux, "getloadavg");
        // utmpx stubs
        symbol(&endutxent, "endutxent");
        symbol(&endutxent, "endutent");
        symbol(&setutxent, "setutxent");
        symbol(&setutxent, "setutent");
        symbol(&getutxent, "getutxent");
        symbol(&getutxent, "getutent");
        symbol(&getutxid, "getutxid");
        symbol(&getutxid, "getutid");
        symbol(&getutxline, "getutxline");
        symbol(&getutxline, "getutline");
        symbol(&pututxline, "pututxline");
        symbol(&pututxline, "pututline");
        symbol(&updwtmpx, "updwtmpx");
        symbol(&updwtmpx, "updwtmp");
        symbol(&utmpxname, "utmpname");
        symbol(&utmpxname, "utmpxname");
    }
}

fn endutxent() callconv(.c) void {}
fn setutxent() callconv(.c) void {}

fn getutxent() callconv(.c) ?*anyopaque {
    return null;
}

fn getutxid(_: ?*const anyopaque) callconv(.c) ?*anyopaque {
    return null;
}

fn getutxline(_: ?*const anyopaque) callconv(.c) ?*anyopaque {
    return null;
}

fn pututxline(_: ?*const anyopaque) callconv(.c) ?*anyopaque {
    return null;
}

fn updwtmpx(_: ?[*:0]const u8, _: ?*const anyopaque) callconv(.c) void {}

fn utmpxname(_: ?[*:0]const u8) callconv(.c) c_int {
    std.c._errno().* = @intFromEnum(linux.E.OPNOTSUPP);
    return -1;
        symbol(&ulimitLinux, "ulimit");
    }
    if (builtin.link_libc) {
        symbol(&ftw, "ftw");
    }
}

const UL_SETFSIZE = 2;

fn ulimitLinux(cmd: c_int, ...) callconv(.c) c_long {
    var rl: linux.rlimit = undefined;
    _ = linux.getrlimit(.FSIZE, &rl);
    if (cmd == UL_SETFSIZE) {
        var ap = @cVaStart();
        const val = @cVaArg(&ap, c_long);
        @cVaEnd(&ap);
        rl.cur = @as(u64, 512) * @as(u64, @intCast(val));
        if (errno(linux.setrlimit(.FSIZE, &rl)) < 0) return -1;
    }
    return if (rl.cur / 512 > std.math.maxInt(c_long)) std.math.maxInt(c_long) else @intCast(rl.cur / 512);
}

const FTW_PHYS = 1;

extern "c" fn nftw(
    path: [*:0]const u8,
    func: *const anyopaque,
    fd_limit: c_int,
    flags: c_int,
) c_int;

fn ftw(
    path: [*:0]const u8,
    func: *const anyopaque,
    fd_limit: c_int,
) callconv(.c) c_int {
    return nftw(path, func, fd_limit, FTW_PHYS);

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.link_libc) {
        symbol(&vwarn, "vwarn");
        symbol(&vwarnx, "vwarnx");
        symbol(&verr, "verr");
        symbol(&verrx, "verrx");
        symbol(&warn_fn, "warn");
        symbol(&warnx_fn, "warnx");
        symbol(&err_fn, "err");
        symbol(&errx_fn, "errx");
    }
}

const VaList = std.builtin.VaList;

extern "c" var stderr: *anyopaque;
extern "c" var __progname: [*:0]const u8;
        symbol(&utmpxname, "utmpxname");
        symbol(&utmpxname, "utmpname");
        if (builtin.link_libc) {
            symbol(&futimes, "futimes");
            symbol(&lutimes, "lutimes");
            symbol(&getpass, "getpass");
            symbol(&ulimit_fn, "ulimit");
            symbol(&vwarn, "vwarn");
            symbol(&vwarnx, "vwarnx");
            symbol(&verr, "verr");
            symbol(&verrx, "verrx");
            symbol(&warn_fn, "warn");
            symbol(&warnx_fn, "warnx");
            symbol(&err_fn, "err");
            symbol(&errx_fn, "errx");
            symbol(&cuserid, "cuserid");
            symbol(&ftw_fn, "ftw");
            symbol(&endusershell, "endusershell");
            symbol(&setusershell, "setusershell");
            symbol(&getusershell, "getusershell");
            symbol(&daemon, "daemon");
            symbol(&getpagesize, "getpagesize");
            // valloc is exported by malloc.zig
        }
    }
}

const AT_EACCESS: u32 = 0x200;

fn euidaccessLinux(path: [*:0]const u8, amode: c_int) callconv(.c) c_int {
    return errno(linux.faccessat(linux.AT.FDCWD, path, @bitCast(amode), AT_EACCESS));
}
fn isastreamLinux(fd: c_int) callconv(.c) c_int {
    const rc: isize = @bitCast(linux.fcntl(fd, linux.F.GETFD, 0));
    if (rc < 0) { std.c._errno().* = @intCast(-rc); return -1; }
    return 0;
}
fn getdtablesizeLinux() callconv(.c) c_int {
    var rl: linux.rlimit = undefined;
    const rc: isize = @bitCast(linux.getrlimit(.NOFILE, &rl));
    if (rc < 0) return std.math.maxInt(c_int);
    return if (rl.cur < std.math.maxInt(c_int)) @intCast(rl.cur) else std.math.maxInt(c_int);
}
const SI_LOAD_SHIFT = 16;
fn getloadavgLinux(a: [*]f64, n_arg: c_int) callconv(.c) c_int {
    if (n_arg <= 0) return if (n_arg != 0) @as(c_int, -1) else 0;
    var si: linux.Sysinfo = undefined;
    const rc: isize = @bitCast(linux.sysinfo(&si));
    if (rc < 0) return -1;
    const n: usize = @intCast(@min(n_arg, 3));
    const scale = 1.0 / @as(f64, @floatFromInt(@as(u32, 1) << SI_LOAD_SHIFT));
    for (0..n) |i| { a[i] = scale * @as(f64, @floatFromInt(si.loads[i])); }
    return @intCast(n);
}

// utmpx stubs
fn endutxent() callconv(.c) void {}
fn setutxent() callconv(.c) void {}
fn getutxent() callconv(.c) ?*anyopaque { return null; }
fn getutxid(ut: ?*const anyopaque) callconv(.c) ?*anyopaque { _ = ut; return null; }
fn getutxline(ut: ?*const anyopaque) callconv(.c) ?*anyopaque { _ = ut; return null; }
fn pututxline(ut: ?*const anyopaque) callconv(.c) ?*anyopaque { _ = ut; return null; }
fn updwtmpx(f: ?[*:0]const u8, u: ?*const anyopaque) callconv(.c) void { _ = f; _ = u; }
fn utmpxname(f: ?[*:0]const u8) callconv(.c) c_int {
    _ = f;
    std.c._errno().* = @intFromEnum(linux.E.OPNOTSUPP);
    return -1;
}

// --- Extern libc ---
extern "c" fn futimens(fd: c_int, times: ?*const [2]linux.timespec) c_int;
extern "c" fn utimensat(fd: c_int, path: ?[*:0]const u8, times: ?*const [2]linux.timespec, flags: c_int) c_int;
extern "c" fn chdir(path: [*:0]const u8) c_int;
extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn dup2(oldfd: c_int, newfd: c_int) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn fork() c_int;
extern "c" fn setsid() c_int;
extern "c" fn _exit(status: c_int) noreturn;
extern "c" fn sysconf(name: c_int) c_long;
extern "c" fn memalign(alignment: usize, size: usize) ?*anyopaque;
extern "c" fn tcgetattr(fd: c_int, tio: *linux.termios) c_int;
extern "c" fn tcsetattr(fd: c_int, act: c_int, tio: *const linux.termios) c_int;
extern "c" fn tcdrain(fd: c_int) c_int;
extern "c" fn dprintf(fd: c_int, fmt: [*:0]const u8, ...) c_int;
extern "c" fn getrlimit(resource: c_int, rlim: *linux.rlimit) c_int;
extern "c" fn setrlimit(resource: c_int, rlim: *const linux.rlimit) c_int;

const timeval = extern struct { tv_sec: isize, tv_usec: isize };

fn futimes(fd: c_int, tv: ?*const [2]timeval) callconv(.c) c_int {
    if (tv == null) return futimens(fd, null);
    const times = [2]linux.timespec{
        .{ .sec = tv.?[0].tv_sec, .nsec = tv.?[0].tv_usec * 1000 },
        .{ .sec = tv.?[1].tv_sec, .nsec = tv.?[1].tv_usec * 1000 },
    };
    return futimens(fd, &times);
}
fn lutimes(filename: [*:0]const u8, tv: ?*const [2]timeval) callconv(.c) c_int {
    if (tv == null) return utimensat(linux.AT.FDCWD, filename, null, linux.AT.SYMLINK_NOFOLLOW);
    const times = [2]linux.timespec{
        .{ .sec = tv.?[0].tv_sec, .nsec = tv.?[0].tv_usec * 1000 },
        .{ .sec = tv.?[1].tv_sec, .nsec = tv.?[1].tv_usec * 1000 },
    };
    return utimensat(linux.AT.FDCWD, filename, &times, linux.AT.SYMLINK_NOFOLLOW);
}

// --- daemon ---

const O_RDWR = 2;

fn daemon(nochdir: c_int, noclose: c_int) callconv(.c) c_int {
    if (nochdir == 0 and chdir("/") != 0) return -1;
    if (noclose == 0) {
        const fd = open("/dev/null", O_RDWR);
        if (fd < 0) return -1;
        var failed: c_int = 0;
        if (dup2(fd, 0) < 0) failed += 1;
        if (dup2(fd, 1) < 0) failed += 1;
        if (dup2(fd, 2) < 0) failed += 1;
        if (fd > 2) _ = close(fd);
        if (failed != 0) return -1;
    }
    switch (fork()) {
        0 => {},
        -1 => return -1,
        else => _exit(0),
    }
    if (setsid() < 0) return -1;
    switch (fork()) {
        0 => {},
        -1 => return -1,
        else => _exit(0),
    }
    return 0;
}

// --- getpagesize / valloc ---

const SC_PAGE_SIZE: c_int = 30;

fn getpagesize() callconv(.c) c_int {
    return @intCast(sysconf(SC_PAGE_SIZE));
}

fn valloc(size: usize) callconv(.c) ?*anyopaque {
    return memalign(@intCast(sysconf(SC_PAGE_SIZE)), size);
}

// --- getpass ---

const TCSAFLUSH: c_int = 2;
const O_NOCTTY = 0o400;
const O_CLOEXEC_LEGACY = 0o2000000;

var password_buf: [128]u8 = undefined;

fn getpass(prompt: [*:0]const u8) callconv(.c) ?[*:0]u8 {
    const fd = open("/dev/tty", O_RDWR | O_NOCTTY | O_CLOEXEC_LEGACY);
    if (fd < 0) return null;

    var s: linux.termios = undefined;
    var t: linux.termios = undefined;
    _ = tcgetattr(fd, &t);
    s = t;
    t.lflag.ECHO = false;
    t.lflag.ISIG = false;
    t.lflag.ICANON = true;
    t.iflag.INLCR = false;
    t.iflag.IGNCR = false;
    t.iflag.ICRNL = true;
    _ = tcsetattr(fd, TCSAFLUSH, &t);
    _ = tcdrain(fd);

    _ = dprintf(fd, "%s", prompt);

    const l = @import("../c.zig").errno(linux.read(fd, @ptrCast(&password_buf), password_buf.len));
    if (l >= 0) {
        var end: usize = @intCast(l);
        if (end > 0 and password_buf[end - 1] == '\n') end -= 1;
        if (end >= password_buf.len) end = password_buf.len - 1;
        password_buf[end] = 0;
    }

    _ = tcsetattr(fd, TCSAFLUSH, &s);
    _ = dprintf(fd, "\n");
    _ = close(fd);

    return if (l < 0) null else @ptrCast(&password_buf);
}

// --- ulimit ---

const RLIMIT_FSIZE: c_int = 1;
const UL_SETFSIZE: c_int = 2;

fn ulimit_fn(cmd: c_int, ...) callconv(.c) c_long {
    var rl: linux.rlimit = undefined;
    _ = getrlimit(RLIMIT_FSIZE, &rl);
    if (cmd == UL_SETFSIZE) {
        var ap = @cVaStart();
        defer @cVaEnd(&ap);
        const val: c_long = @cVaArg(&ap, c_long);
        rl.cur = @intCast(@as(u64, 512) * @as(u64, @intCast(val)));
        if (setrlimit(RLIMIT_FSIZE, &rl) != 0) return -1;
    }
    return @intCast(rl.cur / 512);
}

// --- err.c (variadic via @cVaStart/@cVaCopy) ---

const VaList = std.builtin.VaList;

extern "c" fn fprintf(stream: *anyopaque, fmt: [*:0]const u8, ...) c_int;
extern "c" fn vfprintf(stream: *anyopaque, fmt: [*:0]const u8, ap: VaList) c_int;
extern "c" fn fputs(s: [*:0]const u8, stream: *anyopaque) c_int;
extern "c" fn putc(c: c_int, stream: *anyopaque) c_int;
extern "c" fn perror(s: ?[*:0]const u8) void;
extern "c" fn exit(status: c_int) noreturn;

fn vwarn(fmt: ?[*:0]const u8, ap: VaList) callconv(.c) void {
    _ = fprintf(stderr, "%s: ", __progname);
    if (fmt) |f| {
        _ = vfprintf(stderr, f, ap);
        _ = fputs(": ", stderr);

fn getStderrAndProgname() struct { stderr_p: *anyopaque, progname: [*:0]const u8 } {
    const stderr_ptr = @extern(**anyopaque, .{ .name = "stderr" });
    const progname_ptr = @extern(*[*:0]const u8, .{ .name = "__progname" });
    return .{ .stderr_p = stderr_ptr.*, .progname = progname_ptr.* };
}

fn vwarn(fmt: ?[*:0]const u8, ap: VaList) callconv(.c) void {
    const ctx = getStderrAndProgname();
    _ = fprintf(ctx.stderr_p, "%s: ", ctx.progname);
    if (fmt) |f| {
        _ = vfprintf(ctx.stderr_p, f, ap);
        _ = fputs(": ", ctx.stderr_p);
    }
    perror(null);
}

fn vwarnx(fmt: ?[*:0]const u8, ap: VaList) callconv(.c) void {
    _ = fprintf(stderr, "%s: ", __progname);
    if (fmt) |f| _ = vfprintf(stderr, f, ap);
    _ = putc('\n', stderr);
}

    const ctx = getStderrAndProgname();
    _ = fprintf(ctx.stderr_p, "%s: ", ctx.progname);
    if (fmt) |f| _ = vfprintf(ctx.stderr_p, f, ap);
    _ = putc('\n', ctx.stderr_p);
}

extern "c" fn exit(code: c_int) noreturn;

fn verr(status: c_int, fmt: ?[*:0]const u8, ap: VaList) callconv(.c) noreturn {
    vwarn(fmt, ap);
    exit(status);
}

fn verrx(status: c_int, fmt: ?[*:0]const u8, ap: VaList) callconv(.c) noreturn {
    vwarnx(fmt, ap);
    exit(status);
}

fn warn_fn(fmt: ?[*:0]const u8, ...) callconv(.c) void {
    const ap = @cVaStart();
    vwarn(fmt, @as(VaList, @bitCast(ap)));
}

fn warnx_fn(fmt: ?[*:0]const u8, ...) callconv(.c) void {
    const ap = @cVaStart();
    vwarnx(fmt, @as(VaList, @bitCast(ap)));
}

fn err_fn(status: c_int, fmt: ?[*:0]const u8, ...) callconv(.c) noreturn {
    const ap = @cVaStart();
    verr(status, fmt, @as(VaList, @bitCast(ap)));
}

fn errx_fn(status: c_int, fmt: ?[*:0]const u8, ...) callconv(.c) noreturn {
    const ap = @cVaStart();
    verrx(status, fmt, @as(VaList, @bitCast(ap)));
        symbol(&endusershell, "endusershell");
        symbol(&setusershell, "setusershell");
        symbol(&getusershell, "getusershell");
        symbol(&getpass, "getpass");
    }
}

// ── getusershell ───────────────────────────────────────────────────────

const FILE = anyopaque;
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE;
extern "c" fn fclose(stream: *FILE) c_int;
extern "c" fn fmemopen(buf: *const anyopaque, size: usize, mode: [*:0]const u8) ?*FILE;
extern "c" fn getline(lineptr: *?[*:0]u8, n: *usize, stream: *FILE) isize;

const defshells = "/bin/sh\n/bin/csh\n";

var us_line: ?[*:0]u8 = null;
var us_linesize: usize = 0;
var us_f: ?*FILE = null;

fn endusershell() callconv(.c) void {
    if (us_f) |stream| {
        _ = fclose(stream);
        us_f = null;
    }
}

fn setusershell() callconv(.c) void {
    if (us_f == null) us_f = fopen("/etc/shells", "rbe");
    if (us_f == null) us_f = fmemopen(@ptrCast(@constCast(defshells)), defshells.len, "rb");
}

fn getusershell() callconv(.c) ?[*:0]u8 {
    if (us_f == null) setusershell();
    const stream = us_f orelse return null;
    const l = getline(&us_line, &us_linesize, stream);
    if (l <= 0) return null;
    const line = us_line orelse return null;
    if (line[@intCast(l - 1)] == '\n') line[@intCast(l - 1)] = 0;
    return line;
}

// ── getpass ─────────────────────────────────────────────────────────────

extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, count: usize) isize;
extern "c" fn tcgetattr(fd: c_int, termios_p: *anyopaque) c_int;
extern "c" fn tcsetattr(fd: c_int, action: c_int, termios_p: *const anyopaque) c_int;
extern "c" fn tcdrain(fd: c_int) c_int;
extern "c" fn dprintf(fd: c_int, fmt: [*:0]const u8, ...) c_int;

const O_RDWR = 2;
const O_NOCTTY = 0o400;
const O_CLOEXEC = 0o2000000;
const TCSAFLUSH = 2;

// termios struct is large and arch-specific; use an opaque buffer
const TERMIOS_SIZE = 60; // sizeof(struct termios) on Linux

var password: [128]u8 = undefined;

fn getpass(prompt: [*:0]const u8) callconv(.c) ?[*:0]u8 {
    const fd = open("/dev/tty", O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (fd < 0) return null;

    var saved: [TERMIOS_SIZE]u8 = undefined;
    var current: [TERMIOS_SIZE]u8 = undefined;
    _ = tcgetattr(fd, &current);
    saved = current;

    // Modify c_lflag: clear ECHO (0o10) and ISIG (1), set ICANON (2)
    // c_lflag is at offset 12 in struct termios on Linux (after c_iflag, c_oflag, c_cflag)
    const lflag_offset = 12;
    var lflag: u32 = @bitCast(current[lflag_offset..][0..4].*);
    lflag &= ~@as(u32, 0o10 | 1); // clear ECHO | ISIG
    lflag |= 2; // set ICANON
    current[lflag_offset..][0..4].* = @bitCast(lflag);

    // Modify c_iflag: clear INLCR (0o100) and IGNCR (0o200), set ICRNL (0o400)
    var iflag: u32 = @bitCast(current[0..4].*);
    iflag &= ~@as(u32, 0o100 | 0o200); // clear INLCR | IGNCR
    iflag |= 0o400; // set ICRNL
    current[0..4].* = @bitCast(iflag);

    _ = tcsetattr(fd, TCSAFLUSH, &current);
    _ = tcdrain(fd);

    _ = dprintf(fd, "%s", prompt);

    const l = read(fd, &password, password.len);

    if (l >= 0) {
        var end: usize = @intCast(l);
        if ((end > 0 and password[end - 1] == '\n') or end == password.len) end -= 1;
        password[end] = 0;
    }

    _ = tcsetattr(fd, TCSAFLUSH, &saved);
    _ = dprintf(fd, "\n");
    _ = close(fd);

    return if (l < 0) null else @ptrCast(&password);
        symbol(&cuserid, "cuserid");
    }
}

const L_cuserid = 20;

const passwd = extern struct {
    pw_name: ?[*:0]const u8,
    pw_passwd: ?[*:0]const u8,
    pw_uid: c_uint,
    pw_gid: c_uint,
    pw_gecos: ?[*:0]const u8,
    pw_dir: ?[*:0]const u8,
    pw_shell: ?[*:0]const u8,
};

extern "c" fn getpwuid_r(uid: c_uint, pwd: *passwd, buf: [*]u8, buflen: usize, result: *?*passwd) c_int;
extern "c" fn geteuid() c_uint;
extern "c" fn strnlen(s: [*]const u8, maxlen: usize) usize;
extern "c" fn memcpy(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;

var usridbuf: [L_cuserid]u8 = undefined;

fn cuserid(buf: ?[*]u8) callconv(.c) ?[*:0]u8 {
    if (buf) |b| b[0] = 0;

    var pw: passwd = undefined;
    var ppw: ?*passwd = null;
    var pwb: [256 * @sizeOf(c_long)]u8 = undefined;
    _ = getpwuid_r(geteuid(), &pw, &pwb, pwb.len, &ppw);
    if (ppw == null) return if (buf) |b| @ptrCast(b) else null;

    const name = pw.pw_name orelse return if (buf) |b| @ptrCast(b) else null;
    const len = strnlen(name, L_cuserid);
    if (len == L_cuserid) return if (buf) |b| @ptrCast(b) else null;

    const dest: [*]u8 = buf orelse &usridbuf;
    _ = memcpy(dest, name, len + 1);
    return @ptrCast(dest);
}
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    vwarn(fmt, @cVaCopy(&ap));
}

fn warnx_fn(fmt: ?[*:0]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    vwarnx(fmt, @cVaCopy(&ap));
}

fn err_fn(status: c_int, fmt: ?[*:0]const u8, ...) callconv(.c) noreturn {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    verr(status, fmt, @cVaCopy(&ap));
}

fn errx_fn(status: c_int, fmt: ?[*:0]const u8, ...) callconv(.c) noreturn {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    verrx(status, fmt, @cVaCopy(&ap));
}

// --- cuserid ---

const L_CUSERID = 20;
extern "c" fn geteuid() c_uint;
extern "c" fn getpwuid_r(uid: c_uint, pwd: *anyopaque, buf: [*]u8, buflen: usize, result: *?*anyopaque) c_int;

var usridbuf: [L_CUSERID]u8 = .{0} ** L_CUSERID;

const Passwd = extern struct { pw_name: ?[*:0]u8 };

fn cuserid(buf: ?[*]u8) callconv(.c) ?[*]u8 {
    if (buf) |b| b[0] = 0;
    var pw: Passwd = std.mem.zeroes(Passwd);
    var ppw: ?*anyopaque = null;
    var pwb: [256 * @sizeOf(c_long)]u8 = undefined;
    _ = getpwuid_r(geteuid(), &pw, &pwb, pwb.len, &ppw);
    if (ppw == null) return buf;
    const name = pw.pw_name orelse return buf;
    var len: usize = 0;
    while (len < L_CUSERID and name[len] != 0) len += 1;
    if (len == L_CUSERID) return buf;
    const dest: [*]u8 = buf orelse &usridbuf;
    @memcpy(dest[0 .. len + 1], name[0 .. len + 1]);
    return dest;
}

// --- ftw ---

const FTW_PHYS: c_int = 1;
extern "c" fn nftw(path: [*:0]const u8, func: *const anyopaque, fd_limit: c_int, flags: c_int) c_int;

fn ftw_fn(
    path: [*:0]const u8,
    func: *const anyopaque,
    fd_limit: c_int,
) callconv(.c) c_int {
    return nftw(path, func, fd_limit, FTW_PHYS);
}

// --- getusershell ---

extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn fmemopen(buf: ?*const anyopaque, size: usize, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn fclose(stream: *anyopaque) c_int;
extern "c" fn getline(lineptr: *?[*]u8, n: *usize, stream: *anyopaque) isize;

const defshells = "/bin/sh\n/bin/csh\n";

var shell_line: ?[*]u8 = null;
var shell_linesize: usize = 0;
var shell_f: ?*anyopaque = null;

fn endusershell() callconv(.c) void {
    if (shell_f) |stream| { _ = fclose(stream); shell_f = null; }
}

fn setusershell() callconv(.c) void {
    if (shell_f == null) shell_f = fopen("/etc/shells", "rbe");
    if (shell_f == null) shell_f = fmemopen(defshells.ptr, defshells.len, "rb");
}

fn getusershell() callconv(.c) ?[*:0]u8 {
    if (shell_f == null) setusershell();
    const f = shell_f orelse return null;
    const l = getline(&shell_line, &shell_linesize, f);
    if (l <= 0) return null;
    const line = shell_line orelse return null;
    const ul: usize = @intCast(l);
    if (line[ul - 1] == '\n') line[ul - 1] = 0;
    return @ptrCast(line);
        symbol(&getpagesize, "getpagesize");
        symbol(&getdtablesizeLinux, "getdtablesize");
        symbol(&isastreamLinux, "isastream");
        symbol(&euidaccessLinux, "euidaccess");
        symbol(&euidaccessLinux, "eaccess");
    }
    if (builtin.target.isWasiLibC()) {
        symbol(&getpagesize, "getpagesize");
    }
}

fn getpagesize() callconv(.c) c_int {
    return std.heap.page_size_min;
}

fn getdtablesizeLinux() callconv(.c) c_int {
    var rl: linux.rlimit = undefined;
    _ = linux.getrlimit(.NOFILE, &rl);
    return if (rl.cur < std.math.maxInt(c_int)) @intCast(rl.cur) else std.math.maxInt(c_int);
}

fn isastreamLinux(fd: c_int) callconv(.c) c_int {
    const F_GETFD = 1;
    const rc: isize = @bitCast(linux.fcntl(fd, F_GETFD, 0));
    return if (rc < 0) -1 else 0;
}

fn euidaccessLinux(path: [*:0]const u8, amode: c_uint) callconv(.c) c_int {
    const AT_EACCESS = 0x200;
    return errno(linux.faccessat(linux.AT.FDCWD, path, amode, AT_EACCESS));
}
