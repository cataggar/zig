const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&timesLinux, "times");
    }
}

fn timesLinux(tms_ptr: ?*anyopaque) callconv(.c) c_long {
    return @bitCast(linux.syscall1(.times, @intFromPtr(tms_ptr)));
const errno = @import("../c.zig").errno;

const NSIG = linux.NSIG;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&sigtimedwaitLinux, "sigtimedwait");
        symbol(&sigwaitLinux, "sigwait");
        symbol(&sigwaitinfoLinux, "sigwaitinfo");
        symbol(&nanosleepLinux, "nanosleep");
        symbol(&clock_nanosleepLinux, "clock_nanosleep");
        symbol(&clock_nanosleepLinux, "__clock_nanosleep");
        symbol(&utimeLinux, "utime");
    }
}

fn sigtimedwaitLinux(
    mask: *const linux.sigset_t,
    si: ?*linux.siginfo_t,
    timeout: ?*const linux.timespec,
) callconv(.c) c_int {
    while (true) {
        const r: isize = @bitCast(linux.syscall4(
            if (@hasField(linux.SYS, "rt_sigtimedwait_time64")) .rt_sigtimedwait_time64 else .rt_sigtimedwait,
            @intFromPtr(mask),
            @intFromPtr(si),
            @intFromPtr(timeout),
            NSIG / 8,
        ));
        if (r != -@as(isize, @intFromEnum(linux.E.INTR))) {
            if (r < 0) {
                std.c._errno().* = @intCast(-r);
                return -1;
            }
            return @intCast(r);
        }
    }
}

fn sigwaitLinux(mask: *const linux.sigset_t, sig: *c_int) callconv(.c) c_int {
    var si: linux.siginfo_t = undefined;
    if (sigtimedwaitLinux(mask, &si, null) < 0) return -1;
    sig.* = @intCast(@intFromEnum(si.signo));
    return 0;
}

fn sigwaitinfoLinux(mask: *const linux.sigset_t, si: ?*linux.siginfo_t) callconv(.c) c_int {
    return sigtimedwaitLinux(mask, si, null);
}

fn clock_nanosleepLinux(clk: c_int, flags: c_int, req: *const linux.timespec, rem: ?*linux.timespec) callconv(.c) c_int {
    const clk_id: linux.clockid_t = @enumFromInt(@as(u32, @bitCast(clk)));
    if (clk_id == .THREAD_CPUTIME_ID) return @intFromEnum(linux.E.INVAL);
    const r: isize = @bitCast(linux.clock_nanosleep(clk_id, @bitCast(@as(u32, @bitCast(flags))), req, rem));
    if (r < 0) return @intCast(-r);
    return 0;
}

fn nanosleepLinux(req: *const linux.timespec, rem: ?*linux.timespec) callconv(.c) c_int {
    const r: isize = @bitCast(linux.clock_nanosleep(.REALTIME, @bitCast(@as(u32, 0)), req, rem));
    if (r < 0) {
        std.c._errno().* = @intCast(-r);
        return -1;
    }
    return 0;
}

const utimbuf = extern struct {
    actime: linux.time_t,
    modtime: linux.time_t,
};

fn utimeLinux(path: [*:0]const u8, times_ptr: ?*const utimbuf) callconv(.c) c_int {
    if (times_ptr) |t| {
        const ts = [2]linux.timespec{
            .{ .sec = @intCast(t.actime), .nsec = 0 },
            .{ .sec = @intCast(t.modtime), .nsec = 0 },
        };
        return errno(linux.utimensat(linux.AT.FDCWD, path, &ts, 0));
    }
    return errno(linux.utimensat(linux.AT.FDCWD, path, null, 0));
const errno = @import("../c.zig").errno;

const timeb = extern struct {
    time: linux.time_t,
    millitm: c_ushort,
    timezone: c_short,
    dstflag: c_short,
};

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&ftimeLinux, "ftime");
        symbol(&timespec_getLinux, "timespec_get");
    }
}

fn ftimeLinux(tp: *timeb) callconv(.c) c_int {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.REALTIME, &ts);
    tp.time = @intCast(ts.sec);
    tp.millitm = @intCast(@divTrunc(ts.nsec, 1000000));
    tp.timezone = 0;
    tp.dstflag = 0;
    return 0;
}

fn timespec_getLinux(ts: *linux.timespec, base: c_int) callconv(.c) c_int {
    if (base != 1) return 0; // TIME_UTC = 1
    if (errno(linux.clock_gettime(.REALTIME, ts)) < 0) return 0;
    return base;
}
