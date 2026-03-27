const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

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
}
