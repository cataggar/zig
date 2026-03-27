const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

const NSIG = linux.NSIG;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&killLinux, "kill");
        symbol(&killpgLinux, "killpg");
        symbol(&sigpendingLinux, "sigpending");
    }
}

fn killLinux(pid: linux.pid_t, sig: c_int) callconv(.c) c_int {
    return errno(linux.kill(pid, @enumFromInt(@as(u32, @bitCast(sig)))));
}

fn killpgLinux(pgid: linux.pid_t, sig: c_int) callconv(.c) c_int {
    if (pgid < 0) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    return killLinux(-pgid, sig);
}

fn sigpendingLinux(set: *linux.sigset_t) callconv(.c) c_int {
    return errno(linux.syscall2(.rt_sigpending, @intFromPtr(set), NSIG / 8));
}
