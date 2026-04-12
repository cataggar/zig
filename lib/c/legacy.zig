const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;
const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;
const SI_LOAD_SHIFT = 16;
const UL_SETFSIZE = 2;
const FTW_PHYS = 1;
extern "c" fn nftw(
    path: [*:0]const u8,
    func: *const anyopaque,
    fd_limit: c_int,
    flags: c_int,
) c_int;
const VaList = std.builtin.VaList;
extern "c" var stderr: *anyopaque;
extern "c" var __progname: [*:0]const u8;
extern "c" fn fprintf(stream: *anyopaque, fmt: [*:0]const u8, ...) c_int;
extern "c" fn vfprintf(stream: *anyopaque, fmt: [*:0]const u8, ap: VaList) c_int;
extern "c" fn fputs(s: [*:0]const u8, stream: *anyopaque) c_int;
extern "c" fn putc(c: c_int, stream: *anyopaque) c_int;
extern "c" fn perror(s: ?[*:0]const u8) void;
extern "c" fn exit(status: c_int) noreturn;
const FILE = anyopaque;
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE;
extern "c" fn fclose(stream: *FILE) c_int;
extern "c" fn fmemopen(buf: *const anyopaque, size: usize, mode: [*:0]const u8) ?*FILE;
extern "c" fn getline(lineptr: *?[*:0]u8, n: *usize, stream: *FILE) isize;
const defshells = "/bin/sh\n/bin/csh\n";
var us_line: ?[*:0]u8 = null;
var us_linesize: usize = 0;
var us_f: ?*FILE = null;
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

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&getpagesize, "getpagesize");
        symbol(&getdtablesizeLinux, "getdtablesize");
        symbol(&euidaccessLinux, "euidaccess");
        symbol(&endutxent, "endutxent");
        symbol(&setutxent, "setutxent");
        symbol(&getutxent, "getutxent");
        symbol(&getutxid, "getutxid");
        symbol(&getutxline, "getutxline");
        symbol(&pututxline, "pututxline");
        symbol(&updwtmpx, "updwtmpx");
        symbol(&utmpxname, "utmpname");
        symbol(&getloadavgLinux, "getloadavg");
        symbol(&daemonLinux, "daemon");
        symbol(&ulimitLinux, "ulimit");
    }
    if (builtin.target.isWasiLibC()) {
    }
    if (builtin.link_libc) {
        symbol(&ftw, "ftw");
        symbol(&vwarn, "vwarn");
        symbol(&vwarnx, "vwarnx");
        symbol(&verr, "verr");
        symbol(&verrx, "verrx");
        symbol(&warn_fn, "warn");
        symbol(&warnx_fn, "warnx");
        symbol(&err_fn, "err");
        symbol(&errx_fn, "errx");
        symbol(&endusershell, "endusershell");
        symbol(&setusershell, "setusershell");
        symbol(&getusershell, "getusershell");
        symbol(&getpass, "getpass");
        symbol(&cuserid, "cuserid");
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
}

fn getloadavgLinux(a: [*]f64, n: c_int) callconv(.c) c_int {
    if (n <= 0) return if (n != 0) -1 else 0;
    var si: linux.Sysinfo = undefined;
    _ = linux.sysinfo(&si);
    const count: usize = if (n > 3) 3 else @intCast(n);
    for (0..count) |i| {
        a[i] = @as(f64, @floatFromInt(si.loads[i])) / @as(f64, @floatFromInt(@as(u64, 1) << SI_LOAD_SHIFT));
    }
    return @intCast(count);
}

fn daemonLinux(nochdir: c_int, noclose: c_int) callconv(.c) c_int {
    if (nochdir == 0) {
        if (errno(linux.chdir("/")) < 0) return -1;
    }

    if (noclose == 0) {
        const rc: isize = @bitCast(linux.open("/dev/null", .{ .ACCMODE = .RDWR }, 0));
        if (rc < 0) {
            @branchHint(.unlikely);
            std.c._errno().* = @intCast(-rc);
            return -1;
        }
        const fd: i32 = @intCast(rc);
        var failed = false;
        if (@as(isize, @bitCast(linux.dup2(fd, 0))) < 0) failed = true;
        if (@as(isize, @bitCast(linux.dup2(fd, 1))) < 0) failed = true;
        if (@as(isize, @bitCast(linux.dup2(fd, 2))) < 0) failed = true;
        if (fd > 2) _ = linux.close(fd);
        if (failed) return -1;
    }

    // First fork.
    const f1: isize = @bitCast(linux.fork());
    if (f1 < 0) return -1;
    if (f1 > 0) linux.exit_group(0);

    if (@as(isize, @bitCast(linux.setsid())) < 0) return -1;

    // Second fork.
    const f2: isize = @bitCast(linux.fork());
    if (f2 < 0) return -1;
    if (f2 > 0) linux.exit_group(0);

    return 0;
}

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

fn ftw(
    path: [*:0]const u8,
    func: *const anyopaque,
    fd_limit: c_int,
) callconv(.c) c_int {
    return nftw(path, func, fd_limit, FTW_PHYS);
}

fn vwarn(fmt: ?[*:0]const u8, ap: VaList) callconv(.c) void {
    _ = fprintf(stderr, "%s: ", __progname);
    if (fmt) |f| {
        _ = vfprintf(stderr, f, ap);
        _ = fputs(": ", stderr);
    }
    perror(null);
}

fn vwarnx(fmt: ?[*:0]const u8, ap: VaList) callconv(.c) void {
    _ = fprintf(stderr, "%s: ", __progname);
    if (fmt) |f| _ = vfprintf(stderr, f, ap);
    _ = putc('\n', stderr);
}

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
}

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
}

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
