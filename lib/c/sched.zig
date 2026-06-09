const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;
const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;
const c = @import("../c.zig");

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&sched_yieldLinux, "sched_yield");
        symbol(&sched_get_priority_maxLinux, "sched_get_priority_max");
        symbol(&sched_get_priority_minLinux, "sched_get_priority_min");
        symbol(&sched_getparamStub, "sched_getparam");
        symbol(&sched_setparamStub, "sched_setparam");
        symbol(&sched_getschedulerStub, "sched_getscheduler");
        symbol(&sched_setschedulerStub, "sched_setscheduler");
        symbol(&sched_rr_get_intervalLinux, "sched_rr_get_interval");
        symbol(&__sched_cpucount, "__sched_cpucount");
        symbol(&sched_getcpuLinux, "sched_getcpu");
    }
}

fn sched_yieldLinux() callconv(.c) c_int {
    return errno(linux.sched_yield());
}

fn sched_get_priority_maxLinux(policy: c_int) callconv(.c) c_int {
    return errno(linux.sched_get_priority_max(@bitCast(policy)));
}

fn sched_get_priority_minLinux(policy: c_int) callconv(.c) c_int {
    return errno(linux.sched_get_priority_min(@bitCast(policy)));
}

/// musl deliberately returns -ENOSYS for these scheduling functions.
fn sched_getparamStub(pid: linux.pid_t, param: *linux.sched_param) callconv(.c) c_int {
    _ = pid;
    _ = param;
    std.c._errno().* = @intFromEnum(linux.E.NOSYS);
    return -1;
}

fn sched_setparamStub(pid: linux.pid_t, param: *const linux.sched_param) callconv(.c) c_int {
    _ = pid;
    _ = param;
    std.c._errno().* = @intFromEnum(linux.E.NOSYS);
    return -1;
}

fn sched_getschedulerStub(pid: linux.pid_t) callconv(.c) c_int {
    _ = pid;
    std.c._errno().* = @intFromEnum(linux.E.NOSYS);
    return -1;
}

fn sched_setschedulerStub(pid: linux.pid_t, sched: c_int, param: *const linux.sched_param) callconv(.c) c_int {
    _ = pid;
    _ = sched;
    _ = param;
    std.c._errno().* = @intFromEnum(linux.E.NOSYS);
    return -1;
}

fn sched_rr_get_intervalLinux(pid: linux.pid_t, ts: *linux.timespec) callconv(.c) c_int {
    return errno(linux.sched_rr_get_interval(pid, ts));
}

fn __sched_cpucount(size: usize, set: [*]const u8) callconv(.c) c_int {
    var cnt: c_int = 0;
    for (set[0..size]) |byte| {
        cnt += @intCast(@popCount(byte));
    }
    return cnt;
}

/// sched_getcpu — returns the CPU the calling thread is running on.
/// Drops musl's vdso optimization; uses raw getcpu syscall.
fn sched_getcpuLinux() callconv(.c) c_int {
    var cpu: usize = 0;
    const rc: isize = @bitCast(linux.getcpu(&cpu, null));
    if (rc < 0) {
        @branchHint(.unlikely);
        std.c._errno().* = @intCast(-rc);
        return -1;
    }
    return @intCast(cpu);
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
