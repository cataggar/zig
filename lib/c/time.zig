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
