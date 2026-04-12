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
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

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
    return c.errno(linux.sched_yield());
}

fn sched_get_priority_maxLinux(policy: c_int) callconv(.c) c_int {
    return c.errno(linux.sched_get_priority_max(@bitCast(@as(u32, @bitCast(policy)))));
}

fn sched_get_priority_minLinux(policy: c_int) callconv(.c) c_int {
    return c.errno(linux.sched_get_priority_min(@bitCast(@as(u32, @bitCast(policy)))));
}

fn sched_getparamLinux(_: linux.pid_t, _: *anyopaque) callconv(.c) c_int {
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

fn sched_setparamLinux(_: linux.pid_t, _: *const anyopaque) callconv(.c) c_int {
fn sched_setparamStub(pid: linux.pid_t, param: *const linux.sched_param) callconv(.c) c_int {
    _ = pid;
    _ = param;
    std.c._errno().* = @intFromEnum(linux.E.NOSYS);
    return -1;
}

fn sched_getschedulerLinux(_: linux.pid_t) callconv(.c) c_int {
fn sched_getschedulerStub(pid: linux.pid_t) callconv(.c) c_int {
    _ = pid;
    std.c._errno().* = @intFromEnum(linux.E.NOSYS);
    return -1;
}

fn sched_setschedulerLinux(_: linux.pid_t, _: c_int, _: *const anyopaque) callconv(.c) c_int {
fn sched_setschedulerStub(pid: linux.pid_t, sched: c_int, param: *const linux.sched_param) callconv(.c) c_int {
    _ = pid;
    _ = sched;
    _ = param;
    std.c._errno().* = @intFromEnum(linux.E.NOSYS);
    return -1;
}

fn sched_rr_get_intervalLinux(pid: linux.pid_t, tp: *linux.timespec) callconv(.c) c_int {
    return c.errno(linux.sched_rr_get_interval(pid, tp));
fn sched_rr_get_intervalLinux(pid: linux.pid_t, ts: *linux.timespec) callconv(.c) c_int {
    return errno(linux.sched_rr_get_interval(pid, ts));
}

fn __sched_cpucount(size: usize, set: [*]const u8) callconv(.c) c_int {
    var cnt: c_int = 0;
    for (set[0..size]) |byte| {
        cnt += @popCount(byte);
    }
    return cnt;
}
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

test __sched_cpucount {
    const set = [_]u8{ 0b10101010, 0b11001100, 0b11110000 };
    try std.testing.expectEqual(@as(c_int, 12), __sched_cpucount(set.len, &set));
    try std.testing.expectEqual(@as(c_int, 0), __sched_cpucount(0, &set));
}
