const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
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
}