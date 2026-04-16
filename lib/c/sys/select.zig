const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../../c.zig").symbol;
const errno = @import("../../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&pollLinux, "poll");
        symbol(&ppollLinux, "ppoll");
        symbol(&pselectLinux, "pselect");
        symbol(&selectLinux, "select");
    }
}

fn pollLinux(fds: [*]linux.pollfd, n: linux.nfds_t, timeout: c_int) callconv(.c) c_int {
    return errno(linux.poll(fds, n, timeout));
}

fn ppollLinux(fds: [*]linux.pollfd, n: linux.nfds_t, timeout: ?*const linux.timespec, sigmask: ?*const linux.sigset_t) callconv(.c) c_int {
    return errno(linux.ppoll(fds, n, @constCast(timeout), sigmask));
}

fn pselectLinux(
    nfds: c_int,
    readfds: ?*anyopaque,
    writefds: ?*anyopaque,
    exceptfds: ?*anyopaque,
    timeout: ?*const linux.timespec,
    sigmask: ?*const linux.sigset_t,
) callconv(.c) c_int {
    const data = [2]usize{ @intFromPtr(sigmask), linux.NSIG / 8 };
    return errno(linux.syscall6(
        .pselect6,
        @as(usize, @intCast(@as(c_uint, @bitCast(nfds)))),
        @intFromPtr(readfds),
        @intFromPtr(writefds),
        @intFromPtr(exceptfds),
        @intFromPtr(timeout),
        @intFromPtr(&data),
    ));
}

fn selectLinux(
    nfds: c_int,
    readfds: ?*anyopaque,
    writefds: ?*anyopaque,
    exceptfds: ?*anyopaque,
    timeout: ?*linux.timeval,
) callconv(.c) c_int {
    if (timeout) |tv| {
        if (tv.sec < 0 or tv.usec < 0) {
            std.c._errno().* = @intFromEnum(linux.E.INVAL);
            return -1;
        }
        const ts = linux.timespec{
            .sec = @intCast(tv.sec + @divTrunc(tv.usec, 1000000)),
            .nsec = @intCast(@rem(tv.usec, 1000000) * 1000),
        };
        const data = [2]usize{ 0, linux.NSIG / 8 };
        return errno(linux.syscall6(
            .pselect6,
            @as(usize, @intCast(@as(c_uint, @bitCast(nfds)))),
            @intFromPtr(readfds),
            @intFromPtr(writefds),
            @intFromPtr(exceptfds),
            @intFromPtr(&ts),
            @intFromPtr(&data),
        ));
    } else {
        const data = [2]usize{ 0, linux.NSIG / 8 };
        return errno(linux.syscall6(
            .pselect6,
            @as(usize, @intCast(@as(c_uint, @bitCast(nfds)))),
            @intFromPtr(readfds),
            @intFromPtr(writefds),
            @intFromPtr(exceptfds),
            0,
            @intFromPtr(&data),
        ));
    }
}