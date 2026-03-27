const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

const tm = extern struct {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
    __tm_gmtoff: c_long,
    __tm_zone: ?[*:0]const u8,
};

extern "c" fn getenv(name: [*:0]const u8) callconv(.c) ?[*:0]const u8;
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) callconv(.c) ?*anyopaque;
extern "c" fn fgets(buf: [*]u8, size: c_int, stream: *anyopaque) callconv(.c) ?[*]u8;
extern "c" fn fclose(stream: *anyopaque) callconv(.c) c_int;
extern "c" fn ferror(stream: *anyopaque) callconv(.c) c_int;
extern "c" fn strptime(s: [*:0]const u8, fmt: [*:0]const u8, t: *tm) callconv(.c) ?[*:0]const u8;
extern "c" fn pthread_setcancelstate(state: c_int, oldstate: ?*c_int) callconv(.c) c_int;

const PTHREAD_CANCEL_DEFERRED = 0;

comptime {
    if (builtin.link_libc) {
        symbol(&getdate_err, "getdate_err");
        symbol(&getdateImpl, "getdate");
    }
}

var getdate_err: c_int = 0;

var tmbuf: tm = undefined;

fn getdateImpl(s: [*:0]const u8) callconv(.c) ?*tm {
    var ret: ?*tm = null;
    var cs: c_int = undefined;
    _ = pthread_setcancelstate(PTHREAD_CANCEL_DEFERRED, &cs);

    const datemsk = getenv("DATEMSK") orelse {
        getdate_err = 1;
        _ = pthread_setcancelstate(cs, null);
        return null;
    };

    const f = fopen(datemsk, "rbe") orelse {
        if (std.c._errno().* == @intFromEnum(linux.E.NOMEM))
            getdate_err = 6
        else
            getdate_err = 2;
        _ = pthread_setcancelstate(cs, null);
        return null;
    };

    var fmt: [100]u8 = undefined;
    while (fgets(&fmt, 100, f)) |_| {
        const p = strptime(s, @ptrCast(&fmt), &tmbuf);
        if (p) |pp| {
            if (pp[0] == 0) {
                ret = &tmbuf;
                break;
            }
        }
    } else {
        if (ferror(f) != 0)
            getdate_err = 5
        else
            getdate_err = 7;
    }

    _ = fclose(f);
    _ = pthread_setcancelstate(cs, null);
    return ret;
}
