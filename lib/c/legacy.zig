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
