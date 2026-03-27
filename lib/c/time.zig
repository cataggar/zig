const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
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
