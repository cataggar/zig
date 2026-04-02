const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const c = @import("../c.zig");

comptime {
    if (builtin.target.isMuslLibC()) {
        c.symbol(&sched_yieldLinux, "sched_yield");

        c.symbol(&sched_get_priority_maxLinux, "sched_get_priority_max");
        c.symbol(&sched_get_priority_minLinux, "sched_get_priority_min");

        c.symbol(&sched_getparamLinux, "sched_getparam");
        c.symbol(&sched_setparamLinux, "sched_setparam");

        c.symbol(&sched_getschedulerLinux, "sched_getscheduler");
        c.symbol(&sched_setschedulerLinux, "sched_setscheduler");

        c.symbol(&sched_rr_get_intervalLinux, "sched_rr_get_interval");

        c.symbol(&__sched_cpucount, "__sched_cpucount");
    }
}

fn sched_yieldLinux() callconv(.c) c_int {
    return c.errno(linux.sched_yield());
}

fn sched_get_priority_maxLinux(policy: c_int) callconv(.c) c_int {
    return c.errno(linux.sched_get_priority_max(@bitCast(@as(u32, @bitCast(policy)))));
}

fn sched_get_priority_minLinux(policy: c_int) callconv(.c) c_int {
    return c.errno(linux.sched_get_priority_min(@bitCast(@as(u32, @bitCast(policy)))));
}

fn sched_getparamLinux(_: linux.pid_t, _: *anyopaque) callconv(.c) c_int {
    std.c._errno().* = @intFromEnum(linux.E.NOSYS);
    return -1;
}

fn sched_setparamLinux(_: linux.pid_t, _: *const anyopaque) callconv(.c) c_int {
    std.c._errno().* = @intFromEnum(linux.E.NOSYS);
    return -1;
}

fn sched_getschedulerLinux(_: linux.pid_t) callconv(.c) c_int {
    std.c._errno().* = @intFromEnum(linux.E.NOSYS);
    return -1;
}

fn sched_setschedulerLinux(_: linux.pid_t, _: c_int, _: *const anyopaque) callconv(.c) c_int {
    std.c._errno().* = @intFromEnum(linux.E.NOSYS);
    return -1;
}

fn sched_rr_get_intervalLinux(pid: linux.pid_t, tp: *linux.timespec) callconv(.c) c_int {
    return c.errno(linux.sched_rr_get_interval(pid, tp));
}

fn __sched_cpucount(size: usize, set: [*]const u8) callconv(.c) c_int {
    var cnt: c_int = 0;
    for (set[0..size]) |byte| {
        cnt += @popCount(byte);
    }
    return cnt;
}
