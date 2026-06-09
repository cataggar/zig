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
        symbol(&sched_rr_get_intervalLinux, "__sched_rr_get_interval_time64");
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

const Timespec = if (@sizeOf(c_long) >= 8)
    extern struct { sec: i64, nsec: c_long }
else if (builtin.cpu.arch.endian() == .little)
    extern struct { sec: i64, nsec: c_long, __pad: c_long = 0 }
else
    extern struct { sec: i64, __pad: c_long = 0, nsec: c_long };

fn syscallArg(val: anytype) linux.syscall_arg_t {
    const T = @TypeOf(val);
    return switch (@typeInfo(T)) {
        .pointer => @intFromPtr(val),
        .optional => if (val) |p| @intFromPtr(p) else 0,
        .int => |i| if (i.signedness == .signed)
            @bitCast(@as(@Int(.signed, @bitSizeOf(linux.syscall_arg_t)), @intCast(val)))
        else
            @intCast(val),
        .@"enum" => @intCast(@intFromEnum(val)),
        else => @compileError("unsupported syscall argument type"),
    };
}

fn sched_rr_get_intervalLinux(pid: linux.pid_t, ts: *Timespec) callconv(.c) c_int {
    if (@hasField(linux.SYS, "sched_rr_get_interval_time64")) {
        if (@hasField(linux.SYS, "sched_rr_get_interval")) {
            if (linux.SYS.sched_rr_get_interval != linux.SYS.sched_rr_get_interval_time64) {
                var ts32: [2]c_long = undefined;
                const rc: isize = @bitCast(linux.syscall2(
                    .sched_rr_get_interval,
                    syscallArg(pid),
                    syscallArg(&ts32),
                ));
                if (rc < 0) {
                    @branchHint(.unlikely);
                    std.c._errno().* = @intCast(-rc);
                    return -1;
                }
                ts.sec = ts32[0];
                ts.nsec = ts32[1];
                return 0;
            }
        }
        return errno(linux.syscall2(
            .sched_rr_get_interval_time64,
            syscallArg(pid),
            syscallArg(ts),
        ));
    } else if (@hasField(linux.SYS, "sched_rr_get_interval")) {
        return errno(linux.syscall2(
            .sched_rr_get_interval,
            syscallArg(pid),
            syscallArg(ts),
        ));
    } else {
        std.c._errno().* = @intFromEnum(linux.E.NOSYS);
        return -1;
    }
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
