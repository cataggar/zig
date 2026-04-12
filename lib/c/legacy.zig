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
}
