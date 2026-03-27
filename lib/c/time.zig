const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&clock_gettimeLinux, "clock_gettime");
        symbol(&clock_gettimeLinux, "__clock_gettime");
        symbol(&clock_settimeLinux, "clock_settime");
        symbol(&clock_getresLinux, "clock_getres");
        symbol(&gettimeofdayLinux, "gettimeofday");
        symbol(&timeLinux, "time");
        symbol(&clockLinux, "clock");
        symbol(&clock_getcpuclockidLinux, "clock_getcpuclockid");
    }
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&difftimeImpl, "difftime");
    }
}

fn clock_gettimeLinux(clk: c_int, ts: *linux.timespec) callconv(.c) c_int {
    return errno(linux.clock_gettime(@enumFromInt(@as(u32, @bitCast(clk))), ts));
}

fn clock_settimeLinux(clk: c_int, ts: *const linux.timespec) callconv(.c) c_int {
    return errno(linux.clock_settime(@enumFromInt(@as(u32, @bitCast(clk))), ts));
}

fn clock_getresLinux(clk: c_int, ts: *linux.timespec) callconv(.c) c_int {
    return errno(linux.clock_getres(@enumFromInt(@as(u32, @bitCast(clk))), ts));
}

fn gettimeofdayLinux(tv: ?*linux.timeval, _: ?*anyopaque) callconv(.c) c_int {
    const t = tv orelse return 0;
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.REALTIME, &ts);
    t.sec = ts.sec;
    t.usec = @intCast(@divTrunc(ts.nsec, 1000));
    return 0;
}

fn timeLinux(t: ?*linux.time_t) callconv(.c) linux.time_t {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.REALTIME, &ts);
    const sec: linux.time_t = @intCast(ts.sec);
    if (t) |ptr| ptr.* = sec;
    return sec;
}

fn clockLinux() callconv(.c) c_long {
    var ts: linux.timespec = undefined;
    if (errno(linux.clock_gettime(.PROCESS_CPUTIME_ID, &ts)) != 0) return -1;
    const max = std.math.maxInt(c_long);
    if (ts.sec > @divTrunc(max, 1000000)) return -1;
    const usec: c_long = @intCast(@divTrunc(ts.nsec, 1000));
    const sec_usec: c_long = @as(c_long, @intCast(ts.sec)) * 1000000;
    if (usec > max - sec_usec) return -1;
    return sec_usec + usec;
}

fn clock_getcpuclockidLinux(pid: linux.pid_t, clk: *linux.clockid_t) callconv(.c) c_int {
    var ts: linux.timespec = undefined;
    const id_raw: u32 = @bitCast((-pid -% 1) *% 8 +% 2);
    const id: linux.clockid_t = @enumFromInt(id_raw);
    const signed: isize = @bitCast(linux.clock_getres(id, &ts));
    if (signed == -@as(isize, @intFromEnum(linux.E.INVAL))) {
        return @intFromEnum(linux.E.SRCH);
    }
    if (signed < 0) return @intCast(-signed);
    clk.* = id;
    return 0;
}

fn difftimeImpl(t1: linux.time_t, t0: linux.time_t) callconv(.c) f64 {
    return @floatFromInt(t1 -% t0);
}
