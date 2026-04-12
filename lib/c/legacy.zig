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
}
