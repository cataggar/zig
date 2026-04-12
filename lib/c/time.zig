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
const time_t = linux.time_t;

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

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&__month_to_secs, "__month_to_secs");
        symbol(&__year_to_secs, "__year_to_secs");
        symbol(&__secs_to_tm, "__secs_to_tm");
        symbol(&__tm_to_secs, "__tm_to_secs");
        symbol(&timegmImpl, "timegm");
        symbol(&__gmtime_r, "__gmtime_r");
        symbol(&__gmtime_r, "gmtime_r");
        symbol(&gmtimeImpl, "gmtime");
        symbol(&__utc, "__utc");
    }
}

const __utc: [3:0]u8 = "UTC".*;

const secs_through_month = [12]c_int{
    0,          31 * 86400,  59 * 86400,  90 * 86400,
    120 * 86400, 151 * 86400, 181 * 86400, 212 * 86400,
    243 * 86400, 273 * 86400, 304 * 86400, 334 * 86400,
};

fn __month_to_secs(month: c_int, is_leap: c_int) callconv(.c) c_int {
    var t = secs_through_month[@intCast(@as(c_uint, @bitCast(month)))];
    if (is_leap != 0 and month >= 2) t += 86400;
    return t;
}

fn __year_to_secs(year: c_longlong, is_leap: ?*c_int) callconv(.c) c_longlong {
    const y_u: u64 = @bitCast(year);
    if (y_u -% 2 <= 136) {
        const y: c_int = @intCast(year);
        var leaps = @divTrunc(y - 68, 4);
        if (@rem(y - 68, 4) == 0) {
            leaps -= 1;
            if (is_leap) |p| p.* = 1;
        } else {
            if (is_leap) |p| p.* = 0;
        }
        return @as(c_longlong, 31536000) * (y - 70) + @as(c_longlong, 86400) * leaps;
    }

    var dummy: c_int = undefined;
    const leap_ptr = is_leap orelse &dummy;

    var cycles: c_int = @intCast(@divTrunc(year - 100, 400));
    var rem: c_int = @intCast(@rem(year - 100, 400));
    if (rem < 0) {
        cycles -= 1;
        rem += 400;
    }

    var centuries: c_int = undefined;
    var leaps: c_int = undefined;
    if (rem == 0) {
        leap_ptr.* = 1;
        centuries = 0;
        leaps = 0;
    } else {
        if (rem >= 200) {
            if (rem >= 300) {
                centuries = 3;
                rem -= 300;
            } else {
                centuries = 2;
                rem -= 200;
            }
        } else {
            if (rem >= 100) {
                centuries = 1;
                rem -= 100;
            } else {
                centuries = 0;
            }
        }
        if (rem == 0) {
            leap_ptr.* = 0;
            leaps = 0;
        } else {
            leaps = @intCast(@divTrunc(@as(c_uint, @bitCast(rem)), 4));
            rem = @intCast(@as(c_uint, @bitCast(rem)) % 4);
            leap_ptr.* = @intFromBool(rem == 0);
        }
    }

    leaps += 97 * cycles + 24 * centuries - leap_ptr.*;
    return (year - 100) * 31536000 + @as(c_longlong, leaps) * 86400 + 946684800 + 86400;
}

const LEAPOCH = 946684800 + 86400 * (31 + 29);
const DAYS_PER_400Y = 365 * 400 + 97;
const DAYS_PER_100Y = 365 * 100 + 24;
const DAYS_PER_4Y = 365 * 4 + 1;
const days_in_month = [12]u8{ 31, 30, 31, 30, 31, 31, 30, 31, 30, 31, 31, 29 };

fn __secs_to_tm(t: c_longlong, r: *tm) callconv(.c) c_int {
    if (t < @as(c_longlong, std.math.minInt(c_int)) * 31622400 or
        t > @as(c_longlong, std.math.maxInt(c_int)) * 31622400) return -1;

    const secs = t - LEAPOCH;
    var days = @divTrunc(secs, 86400);
    var remsecs: c_int = @intCast(@rem(secs, 86400));
    if (remsecs < 0) {
        remsecs += 86400;
        days -= 1;
    }

    var wday: c_int = @intCast(@rem(3 + days, 7));
    if (wday < 0) wday += 7;

    var qc_cycles: c_int = @intCast(@divTrunc(days, DAYS_PER_400Y));
    var remdays: c_int = @intCast(@rem(days, DAYS_PER_400Y));
    if (remdays < 0) {
        remdays += DAYS_PER_400Y;
        qc_cycles -= 1;
    }

    var c_cycles = @divTrunc(remdays, DAYS_PER_100Y);
    if (c_cycles == 4) c_cycles -= 1;
    remdays -= c_cycles * DAYS_PER_100Y;

    var q_cycles = @divTrunc(remdays, DAYS_PER_4Y);
    if (q_cycles == 25) q_cycles -= 1;
    remdays -= q_cycles * DAYS_PER_4Y;

    var remyears = @divTrunc(remdays, 365);
    if (remyears == 4) remyears -= 1;
    remdays -= remyears * 365;

    const leap: c_int = @intFromBool(remyears == 0 and (q_cycles != 0 or c_cycles == 0));
    var yday = remdays + 31 + 28 + leap;
    if (yday >= 365 + leap) yday -= 365 + leap;

    const years: c_longlong = @as(c_longlong, remyears) + 4 * q_cycles + 100 * c_cycles + @as(c_longlong, 400) * qc_cycles;

    var months: c_int = 0;
    while (days_in_month[@intCast(@as(c_uint, @bitCast(months)))] <= @as(u8, @intCast(@as(c_uint, @bitCast(remdays))))) {
        remdays -= @intCast(days_in_month[@intCast(@as(c_uint, @bitCast(months)))]);
        months += 1;
    }

    if (months >= 10) {
        months -= 12;
        const y2 = years + 1;
        if (y2 + 100 > std.math.maxInt(c_int) or y2 + 100 < std.math.minInt(c_int)) return -1;
        r.tm_year = @intCast(y2 + 100);
    } else {
        if (years + 100 > std.math.maxInt(c_int) or years + 100 < std.math.minInt(c_int)) return -1;
        r.tm_year = @intCast(years + 100);
    }
    r.tm_mon = months + 2;
    r.tm_mday = remdays + 1;
    r.tm_wday = wday;
    r.tm_yday = yday;
    r.tm_hour = @divTrunc(remsecs, 3600);
    r.tm_min = @rem(@divTrunc(remsecs, 60), 60);
    r.tm_sec = @rem(remsecs, 60);
    return 0;
}

fn __tm_to_secs(t: *const tm) callconv(.c) c_longlong {
    var year: c_longlong = t.tm_year;
    var month = t.tm_mon;
    if (month >= 12 or month < 0) {
        var adj = @divTrunc(month, 12);
        month = @rem(month, 12);
        if (month < 0) {
            adj -= 1;
            month += 12;
        }
        year += adj;
    }
    var result = __year_to_secs(year, null);
    result += __month_to_secs(month, @intFromBool(false));
    result += @as(c_longlong, 86400) * (t.tm_mday - 1);
    result += @as(c_longlong, 3600) * t.tm_hour;
    result += @as(c_longlong, 60) * t.tm_min;
    result += t.tm_sec;
    return result;
}

fn timegmImpl(t: *tm) callconv(.c) time_t {
    var new: tm = undefined;
    const secs = __tm_to_secs(t);
    if (__secs_to_tm(secs, &new) < 0) {
        std.c._errno().* = @intFromEnum(linux.E.OVERFLOW);
        return -1;
    }
    new.tm_isdst = 0;
    new.__tm_gmtoff = 0;
    new.__tm_zone = &__utc;
    t.* = new;
    return @intCast(secs);
}

var gmtime_buf: tm = undefined;

fn __gmtime_r(t: *const time_t, r: *tm) callconv(.c) ?*tm {
    if (__secs_to_tm(t.*, r) < 0) {
        std.c._errno().* = @intFromEnum(linux.E.OVERFLOW);
        return null;
    }
    r.tm_isdst = 0;
    r.__tm_gmtoff = 0;
    r.__tm_zone = &__utc;
    return r;
}

fn gmtimeImpl(t: *const time_t) callconv(.c) ?*tm {
    return __gmtime_r(t, &gmtime_buf);
        symbol(&__asctime_r, "__asctime_r");
        symbol(&__asctime_r, "asctime_r");
        symbol(&asctimeImpl, "asctime");
    }
    if (builtin.link_libc) {
        symbol(&ctimeImpl, "ctime");
        symbol(&ctime_rImpl, "ctime_r");
    }
}

const day_abbr = [7]*const [3]u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
const mon_abbr = [12]*const [3]u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

fn writeDecimal(buf: [*]u8, value: c_int, width: u8) void {
    var v: u32 = if (value < 0) @intCast(-value) else @intCast(value);
    var i: u8 = width;
    while (i > 0) {
        i -= 1;
        buf[i] = '0' + @as(u8, @intCast(v % 10));
        v /= 10;
    }
    if (value < 0 and width > 0) buf[0] = '-';
}

fn __asctime_r(t: *const tm, buf: [*]u8) callconv(.c) [*]u8 {
    const wday: usize = @intCast(@as(c_uint, @bitCast(t.tm_wday)) % 7);
    const mon: usize = @intCast(@as(c_uint, @bitCast(t.tm_mon)) % 12);

    // "Sun Jan  1 00:00:00 2000\n\0" = 26 bytes
    @memcpy(buf[0..3], day_abbr[wday]);
    buf[3] = ' ';
    @memcpy(buf[4..7], mon_abbr[mon]);

    // day of month (space-padded to 3 chars)
    const mday = t.tm_mday;
    if (mday < 10) {
        buf[7] = ' ';
        buf[8] = ' ';
        buf[9] = '0' + @as(u8, @intCast(@as(c_uint, @bitCast(mday))));
    } else if (mday < 100) {
        buf[7] = ' ';
        buf[8] = '0' + @as(u8, @intCast(@as(c_uint, @bitCast(mday)) / 10));
        buf[9] = '0' + @as(u8, @intCast(@as(c_uint, @bitCast(mday)) % 10));
    } else {
        writeDecimal(buf + 7, mday, 3);
    }
    buf[10] = ' ';

    writeDecimal(buf + 11, t.tm_hour, 2);
    buf[13] = ':';
    writeDecimal(buf + 14, t.tm_min, 2);
    buf[16] = ':';
    writeDecimal(buf + 17, t.tm_sec, 2);
    buf[19] = ' ';

    // year (1900 + tm_year)
    const year = 1900 + t.tm_year;
    if (year >= 0 and year <= 9999) {
        writeDecimal(buf + 20, year, 4);
    } else {
        writeDecimal(buf + 20, year, 4);
    }
    buf[24] = '\n';
    buf[25] = 0;
    return buf;
}

var asctime_buf: [26]u8 = undefined;

fn asctimeImpl(t: *const tm) callconv(.c) [*]u8 {
    return __asctime_r(t, &asctime_buf);
}

// ctime/ctime_r depend on localtime which is provided by the C library
extern "c" fn localtime(t: *const time_t) callconv(.c) ?*tm;
extern "c" fn localtime_r(t: *const time_t, result: *tm) callconv(.c) ?*tm;

fn ctimeImpl(t: *const time_t) callconv(.c) ?[*]u8 {
    const r = localtime(t) orelse return null;
    return asctimeImpl(r);
}

fn ctime_rImpl(t: *const time_t, buf: [*]u8) callconv(.c) ?[*]u8 {
    var result: tm = undefined;
    const r = localtime_r(t, &result) orelse return null;
    return __asctime_r(r, buf);
}
