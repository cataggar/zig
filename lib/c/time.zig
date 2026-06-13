const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;
const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;
const syscallArg = @import("../c.zig").syscallArg;

const TZNAME_MAX = 6;
const NAME_MAX = linux.NAME_MAX;
const PATH_MAX = linux.PATH_MAX;
const time_t = c_longlong;
const Timespec = if (@sizeOf(c_long) >= 8)
    extern struct { sec: time_t, nsec: c_long }
else if (builtin.cpu.arch.endian() == .little)
    extern struct { sec: time_t, nsec: c_long, _pad: c_long = 0 }
else
    extern struct { sec: time_t, _pad: c_long = 0, nsec: c_long };
const Itimerspec = extern struct {
    it_interval: Timespec,
    it_value: Timespec,
};
const Timeval = extern struct {
    sec: time_t,
    usec: c_long,
};
const timeb = extern struct {
    time: time_t,
    millitm: c_ushort,
    timezone: c_short,
    dstflag: c_short,
};
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
const __utc: [3:0]u8 = "UTC".*;
var __timezone: c_long = 0;
var __daylight: c_int = 0;
var __tzname: [2]?[*:0]const u8 = .{ null, null };
var std_name: [TZNAME_MAX + 1:0]u8 = @splat(0);
var dst_name: [TZNAME_MAX + 1:0]u8 = @splat(0);
var dst_off: c_int = 0;
var r0: [5]c_int = @splat(0);
var r1: [5]c_int = @splat(0);
var zi: ?[*]const u8 = null;
var trans: [*]const u8 = undefined;
var index: [*]const u8 = undefined;
var types: [*]const u8 = undefined;
var abbrevs: [*]const u8 = undefined;
var abbrevs_end: [*]const u8 = undefined;
var map_size: usize = 0;
var old_tz_buf: [32:0]u8 = @splat(0);
var old_tz: ?[*]u8 = &old_tz_buf;
var old_tz_size: usize = 32;
var timezone_lock: c_int = 0;
var __timezone_lockptr: *volatile c_int = &timezone_lock;
const LibC = extern struct {
    can_do_threads: u8,
    threaded: u8,
    secure: u8,
    need_locks: i8,
};
extern var __libc: LibC;
const secs_through_month = [12]c_int{
    0,           31 * 86400,  59 * 86400,  90 * 86400,
    120 * 86400, 151 * 86400, 181 * 86400, 212 * 86400,
    243 * 86400, 273 * 86400, 304 * 86400, 334 * 86400,
};
const LEAPOCH = 946684800 + 86400 * (31 + 29);
const DAYS_PER_400Y = 365 * 400 + 97;
const DAYS_PER_100Y = 365 * 100 + 24;
const DAYS_PER_4Y = 365 * 4 + 1;
const days_in_month = [12]u8{ 31, 30, 31, 30, 31, 31, 30, 31, 30, 31, 31, 29 };
var gmtime_buf: tm = undefined;
const day_abbr = [7]*const [3]u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
const mon_abbr = [12]*const [3]u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
var asctime_buf: [26]u8 = undefined;
// ctime/ctime_r depend on localtime which is provided by the C library
extern "c" fn localtime(t: *const time_t) callconv(.c) ?*tm;
extern "c" fn localtime_r(t: *const time_t, result: *tm) callconv(.c) ?*tm;
// Internal helpers (remain as C or from other Zig PRs)
var localtime_buf: tm = undefined;
extern "c" fn getenv(name: [*:0]const u8) callconv(.c) ?[*:0]const u8;
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) callconv(.c) ?*anyopaque;
extern "c" fn fgets(buf: [*]u8, size: c_int, stream: *anyopaque) callconv(.c) ?[*]u8;
extern "c" fn fclose(stream: *anyopaque) callconv(.c) c_int;
extern "c" fn ferror(stream: *anyopaque) callconv(.c) c_int;
extern "c" fn nl_langinfo(item: c_int) callconv(.c) [*:0]const u8;
extern "c" fn pthread_setcancelstate(state: c_int, oldstate: ?*c_int) callconv(.c) c_int;
extern "c" fn malloc(size: usize) callconv(.c) ?*anyopaque;
extern "c" fn __lock(l: *volatile c_int) callconv(.c) void;
extern "c" fn __unlock(l: *volatile c_int) callconv(.c) void;
const PTHREAD_CANCEL_DEFERRED = 0;
const MAP_FAILED = std.math.maxInt(usize);
var getdate_err: c_int = 0;
var tmbuf: tm = undefined;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&ftimeLinux, "ftime");
        symbol(&ftimeLinux, "__ftime64");
        symbol(&__localtime_r, "localtime_r");
        symbol(&__localtime_r, "__localtime64_r");
        symbol(&__gmtime_r, "gmtime_r");
        symbol(&__gmtime_r, "__gmtime64_r");
        symbol(&timespec_getLinux, "timespec_get");
        symbol(&timespec_getLinux, "__timespec_get_time64");
        symbol(&clock_gettimeLinux, "clock_gettime");
        symbol(&clock_gettimeLinux, "__clock_gettime");
        symbol(&clock_gettimeLinux, "__clock_gettime64");
        symbol(&clock_settimeLinux, "clock_settime");
        symbol(&clock_settimeLinux, "__clock_settime64");
        symbol(&clock_getresLinux, "clock_getres");
        symbol(&clock_getresLinux, "__clock_getres_time64");
        symbol(&gettimeofdayLinux, "gettimeofday");
        symbol(&gettimeofdayLinux, "__gettimeofday_time64");
        symbol(&timeLinux, "time");
        symbol(&timeLinux, "__time64");
        symbol(&clockLinux, "clock");
        symbol(&clock_getcpuclockidLinux, "clock_getcpuclockid");
        symbol(&timer_deleteLinux, "timer_delete");
        symbol(&timer_getoverrunLinux, "timer_getoverrun");
        symbol(&timer_gettimeLinux, "timer_gettime");
        symbol(&timer_gettimeLinux, "__timer_gettime64");
        symbol(&timer_settimeLinux, "timer_settime");
        symbol(&timer_settimeLinux, "__timer_settime64");
        symbol(&timesLinux, "times");
        symbol(&utimeLinux, "utime");
        symbol(&utimeLinux, "__utime64");
        symbol(&__map_file, "__map_file");
        symbol(&strftimeFmt1, "__strftime_fmt_1");
        symbol(&__strftime_l, "__strftime_l");
        symbol(&strftimeImpl, "strftime");
        symbol(&__strftime_l, "strftime_l");
        symbol(&__wcsftime_l, "__wcsftime_l");
        symbol(&wcsftimeImpl, "wcsftime");
        symbol(&__wcsftime_l, "wcsftime_l");
        symbol(&__secs_to_zone, "__secs_to_zone");
        symbol(&__tzset, "__tzset");
        symbol(&__tzset, "tzset");
        symbol(&__tm_to_tzname, "__tm_to_tzname");
        symbol(&__timezone, "__timezone");
        symbol(&__timezone, "timezone");
        symbol(&__daylight, "__daylight");
        symbol(&__daylight, "daylight");
        symbol(&__tzname, "__tzname");
        symbol(&__tzname, "tzname");
        @export(&__timezone_lockptr, .{ .name = "__timezone_lockptr", .linkage = .weak, .visibility = .hidden });
    }
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&difftimeImpl, "difftime");
        symbol(&difftimeImpl, "__difftime64");
        symbol(&__month_to_secs, "__month_to_secs");
        symbol(&__year_to_secs, "__year_to_secs");
        symbol(&__secs_to_tm, "__secs_to_tm");
        symbol(&__tm_to_secs, "__tm_to_secs");
        symbol(&timegmImpl, "timegm");
        symbol(&timegmImpl, "__timegm_time64");
        symbol(&__gmtime_r, "__gmtime_r");
        if (builtin.target.isWasiLibC()) symbol(&__gmtime_r, "gmtime_r");
        symbol(&gmtimeImpl, "gmtime");
        symbol(&gmtimeImpl, "__gmtime64");
        symbol(&__utc, "__utc");
        symbol(&__asctime_r, "__asctime_r");
        symbol(&__asctime_r, "asctime_r");
        symbol(&asctimeImpl, "asctime");
    }
    if (builtin.target.isMuslLibC() and builtin.link_libc) {
        symbol(&ctimeImpl, "ctime");
        symbol(&ctimeImpl, "__ctime64");
        symbol(&ctime_rImpl, "ctime_r");
        symbol(&ctime_rImpl, "__ctime64_r");
        symbol(&__localtime_r, "__localtime_r");
        symbol(&localtimeImpl, "localtime");
        symbol(&localtimeImpl, "__localtime64");
        symbol(&mktimeImpl, "mktime");
        symbol(&mktimeImpl, "__mktime64");
        symbol(&strptimeImpl, "strptime");
        symbol(&getdate_err, "getdate_err");
        symbol(&getdateImpl, "getdate");
    }
    if (builtin.target.isWasiLibC() and builtin.link_libc) {
        symbol(&ctimeImpl, "ctime");
        symbol(&ctimeImpl, "__ctime64");
        symbol(&ctime_rImpl, "ctime_r");
        symbol(&ctime_rImpl, "__ctime64_r");
    }
}

fn __map_file(pathname: [*:0]const u8, size: *usize) callconv(.c) ?[*]const u8 {
    var flags = linux.O{ .ACCMODE = .RDONLY, .CLOEXEC = true, .NONBLOCK = true };
    if (@hasField(linux.O, "LARGEFILE")) flags.LARGEFILE = true;

    const fd = errno(linux.open(pathname, flags, 0));
    if (fd < 0) return null;

    var st: linux.Statx = undefined;
    var map: usize = MAP_FAILED;
    if (errno(linux.statx(fd, "", linux.AT.EMPTY_PATH, .{ .SIZE = true }, &st)) == 0) {
        map = linux.mmap(null, @intCast(st.size), .{ .READ = true }, .{ .TYPE = .SHARED }, fd, 0);
        size.* = @intCast(st.size);
    }
    _ = linux.close(fd);

    return if (map == MAP_FAILED) null else @ptrFromInt(map);
}

fn negativeErrno(err: linux.E) usize {
    return @bitCast(-@as(isize, @intCast(@intFromEnum(err))));
}

fn syscallError(syscall_return_value: usize) c_int {
    const signed: isize = @bitCast(syscall_return_value);
    return if (signed < 0) @intCast(-signed) else 0;
}

fn is32BitTime(x: time_t) bool {
    return x >= std.math.minInt(i32) and x <= std.math.maxInt(i32);
}

fn toKernelTimespec(ts: *const Timespec) linux.kernel_timespec {
    return .{ .sec = ts.sec, .nsec = @intCast(ts.nsec) };
}

fn fromKernelTimespec(ts: *Timespec, kts: linux.kernel_timespec) void {
    ts.sec = kts.sec;
    ts.nsec = @intCast(kts.nsec);
    if (@hasField(Timespec, "_pad")) ts._pad = 0;
}

fn clockGettimeSyscall() linux.SYS {
    return comptime if (@hasField(linux.SYS, "clock_gettime64"))
        @field(linux.SYS, "clock_gettime64")
    else
        @field(linux.SYS, "clock_gettime");
}

fn clockGettime(clk: c_int, ts: *Timespec) c_int {
    var kts: linux.kernel_timespec = undefined;
    var ret = linux.syscall2(clockGettimeSyscall(), syscallArg(clk), @intFromPtr(&kts));
    if (comptime @hasField(linux.SYS, "clock_gettime64") and @hasField(linux.SYS, "clock_gettime")) {
        if (ret == negativeErrno(.NOSYS)) {
            var ts32: [2]c_long = undefined;
            ret = linux.syscall2(.clock_gettime, syscallArg(clk), @intFromPtr(&ts32));
            if (ret == 0) {
                ts.sec = @intCast(ts32[0]);
                ts.nsec = @intCast(ts32[1]);
                if (@hasField(Timespec, "_pad")) ts._pad = 0;
            }
            return errno(ret);
        }
    }
    if (errno(ret) < 0) return -1;
    fromKernelTimespec(ts, kts);
    return 0;
}

fn clock_gettimeLinux(clk: c_int, ts: *Timespec) callconv(.c) c_int {
    return clockGettime(clk, ts);
}

fn clock_settimeLinux(clk: c_int, ts: *const Timespec) callconv(.c) c_int {
    var kts = toKernelTimespec(ts);
    if (comptime @hasField(linux.SYS, "clock_settime64")) {
        const ret = linux.syscall2(.clock_settime64, syscallArg(clk), @intFromPtr(&kts));
        if ((comptime !@hasField(linux.SYS, "clock_settime")) or ret != negativeErrno(.NOSYS)) return errno(ret);
        if (!is32BitTime(ts.sec)) return errno(negativeErrno(.OPNOTSUPP));
        var ts32 = [2]c_long{ @intCast(ts.sec), @intCast(ts.nsec) };
        return errno(linux.syscall2(.clock_settime, syscallArg(clk), @intFromPtr(&ts32)));
    }
    return errno(linux.syscall2(.clock_settime, syscallArg(clk), @intFromPtr(&kts)));
}

fn clockGetresErr(clk: c_int, ts: ?*Timespec) c_int {
    if (comptime @hasField(linux.SYS, "clock_getres") and @hasField(linux.SYS, "clock_getres_time64")) {
        var ts32: [2]c_long = undefined;
        const ret = linux.syscall2(.clock_getres, syscallArg(clk), if (ts != null) @intFromPtr(&ts32) else 0);
        if (ret == 0) if (ts) |out| {
            out.sec = @intCast(ts32[0]);
            out.nsec = @intCast(ts32[1]);
            if (@hasField(Timespec, "_pad")) out._pad = 0;
        };
        return syscallError(ret);
    }

    var kts: linux.kernel_timespec = undefined;
    const sys = comptime if (@hasField(linux.SYS, "clock_getres_time64"))
        @field(linux.SYS, "clock_getres_time64")
    else
        @field(linux.SYS, "clock_getres");
    const ret = linux.syscall2(sys, syscallArg(clk), if (ts != null) @intFromPtr(&kts) else 0);
    if (ret == 0) if (ts) |out| fromKernelTimespec(out, kts);
    return syscallError(ret);
}

fn clock_getresLinux(clk: c_int, ts: ?*Timespec) callconv(.c) c_int {
    const err = clockGetresErr(clk, ts);
    if (err != 0) {
        std.c._errno().* = err;
        return -1;
    }
    return 0;
}

fn gettimeofdayLinux(tv: ?*Timeval, _: ?*anyopaque) callconv(.c) c_int {
    const t = tv orelse return 0;
    var ts: Timespec = undefined;
    if (clockGettime(@intFromEnum(linux.CLOCK.REALTIME), &ts) < 0) return -1;
    t.sec = ts.sec;
    t.usec = @intCast(@divTrunc(ts.nsec, 1000));
    return 0;
}

fn timeLinux(t: ?*time_t) callconv(.c) time_t {
    var ts: Timespec = undefined;
    _ = clockGettime(@intFromEnum(linux.CLOCK.REALTIME), &ts);
    if (t) |ptr| ptr.* = ts.sec;
    return ts.sec;
}

fn utimensatTimespec(fd: c_int, path: ?[*:0]const u8, times: ?*const [2]Timespec, flags: c_int) c_int {
    const path_arg = if (path) |p| @intFromPtr(p) else 0;
    const times_arg = if (times) |t| @intFromPtr(t) else 0;
    if (comptime @hasField(linux.SYS, "utimensat_time64")) {
        const ret = linux.syscall4(.utimensat_time64, syscallArg(fd), path_arg, times_arg, syscallArg(flags));
        if ((comptime !@hasField(linux.SYS, "utimensat")) or ret != negativeErrno(.NOSYS)) return errno(ret);
        var ts32: [4]c_long = undefined;
        var ts32_arg: usize = 0;
        if (times) |ts| {
            if (!is32BitTime(ts[0].sec) or !is32BitTime(ts[1].sec)) return errno(negativeErrno(.OPNOTSUPP));
            ts32 = .{ @intCast(ts[0].sec), ts[0].nsec, @intCast(ts[1].sec), ts[1].nsec };
            ts32_arg = @intFromPtr(&ts32);
        }
        return errno(linux.syscall4(.utimensat, syscallArg(fd), path_arg, ts32_arg, syscallArg(flags)));
    }
    return errno(linux.syscall4(.utimensat, syscallArg(fd), path_arg, times_arg, syscallArg(flags)));
}

fn cStringLen(s: [*:0]const u8) usize {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

fn cStringEq(a: [*:0]const u8, b: [*:0]const u8) bool {
    var i: usize = 0;
    while (a[i] == b[i]) : (i += 1) {
        if (a[i] == 0) return true;
    }
    return false;
}

fn cStringChr(s: [*:0]const u8, c: u8) bool {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {
        if (s[i] == c) return true;
    }
    return false;
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isAlpha(c: u8) bool {
    return (c | 32) >= 'a' and (c | 32) <= 'z';
}

fn lockTimezone() void {
    __lock(&timezone_lock);
}

fn unlockTimezone() void {
    __unlock(&timezone_lock);
}

fn clockLinux() callconv(.c) c_long {
    var ts: Timespec = undefined;
    if (clockGettime(@intFromEnum(linux.CLOCK.PROCESS_CPUTIME_ID), &ts) < 0) return -1;
    const max = std.math.maxInt(c_long);
    if (ts.sec > @divTrunc(max, 1000000)) return -1;
    const usec: c_long = @intCast(@divTrunc(ts.nsec, 1000));
    const sec_usec: c_long = @as(c_long, @intCast(ts.sec)) * 1000000;
    if (usec > max - sec_usec) return -1;
    return sec_usec + usec;
}

fn clock_getcpuclockidLinux(pid: linux.pid_t, clk: *linux.clockid_t) callconv(.c) c_int {
    var ts: Timespec = undefined;
    const id_raw: u32 = @bitCast((-pid -% 1) *% 8 +% 2);
    const id: linux.clockid_t = @enumFromInt(id_raw);
    const err = clockGetresErr(@bitCast(id_raw), &ts);
    if (err == @intFromEnum(linux.E.INVAL)) return @intFromEnum(linux.E.SRCH);
    if (err != 0) return err;
    clk.* = id;
    return 0;
}

fn difftimeImpl(t1: time_t, t0: time_t) callconv(.c) f64 {
    return @floatFromInt(t1 -% t0);
}

fn ftimeLinux(tp: *timeb) callconv(.c) c_int {
    var ts: Timespec = undefined;
    if (clockGettime(@intFromEnum(linux.CLOCK.REALTIME), &ts) < 0) return -1;
    tp.time = ts.sec;
    tp.millitm = @intCast(@divTrunc(ts.nsec, 1000000));
    tp.timezone = 0;
    tp.dstflag = 0;
    return 0;
}

fn timespec_getLinux(ts: *Timespec, base: c_int) callconv(.c) c_int {
    if (base != 1) return 0; // TIME_UTC = 1
    if (clockGettime(@intFromEnum(linux.CLOCK.REALTIME), ts) < 0) return 0;
    return base;
}

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
    while (@as(c_int, @intCast(days_in_month[@intCast(months)])) <= remdays) {
        remdays -= @intCast(days_in_month[@intCast(months)]);
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
    var is_leap: c_int = undefined;
    var result = __year_to_secs(year, &is_leap);
    result += __month_to_secs(month, is_leap);
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

fn asctimeImpl(t: *const tm) callconv(.c) [*]u8 {
    return __asctime_r(t, &asctime_buf);
}

fn ctimeImpl(t: *const time_t) callconv(.c) ?[*]u8 {
    const r = localtime(t) orelse return null;
    return asctimeImpl(r);
}

fn ctime_rImpl(t: *const time_t, buf: [*]u8) callconv(.c) ?[*]u8 {
    var result: tm = undefined;
    const r = localtime_r(t, &result) orelse return null;
    return __asctime_r(r, buf);
}

fn getint(p: *[*:0]const u8) c_int {
    var x: c_uint = 0;
    while (isDigit(p.*[0])) : (p.* += 1) x = @as(c_uint, p.*[0] - '0') + 10 * x;
    return @intCast(x);
}

fn getoff(p: *[*:0]const u8) c_int {
    var neg = false;
    if (p.*[0] == '-') {
        p.* += 1;
        neg = true;
    } else if (p.*[0] == '+') p.* += 1;
    var off: c_int = 3600 * getint(p);
    if (p.*[0] == ':') {
        p.* += 1;
        off += 60 * getint(p);
        if (p.*[0] == ':') {
            p.* += 1;
            off += getint(p);
        }
    }
    return if (neg) -off else off;
}

fn getrule(p: *[*:0]const u8, rule: *[5]c_int) void {
    const r: c_int = p.*[0];
    rule[0] = r;
    if (r != 'M') {
        if (r == 'J') p.* += 1 else rule[0] = 0;
        rule[1] = getint(p);
    } else {
        p.* += 1;
        rule[1] = getint(p);
        p.* += 1;
        rule[2] = getint(p);
        p.* += 1;
        rule[3] = getint(p);
    }
    if (p.*[0] == '/') {
        p.* += 1;
        rule[4] = getoff(p);
    } else rule[4] = 7200;
}

fn getname(d: [*:0]u8, p: *[*:0]const u8) void {
    var i: usize = 0;
    if (p.*[0] == '<') {
        p.* += 1;
        while (p.*[i] != 0 and p.*[i] != '>') : (i += 1) {
            if (i < TZNAME_MAX) d[i] = p.*[i];
        }
        if (p.*[i] != 0) p.* += 1;
    } else while (isAlpha(p.*[i])) : (i += 1) {
        if (i < TZNAME_MAX) d[i] = p.*[i];
    }
    p.* += i;
    d[if (i < TZNAME_MAX) i else TZNAME_MAX] = 0;
}

fn ziRead32(z: [*]const u8) u32 {
    return @as(u32, z[0]) << 24 | @as(u32, z[1]) << 16 | @as(u32, z[2]) << 8 | z[3];
}
fn ziDotprod(z_start: [*]const u8, v: []const u8) usize {
    var z = z_start;
    var y: usize = 0;
    for (v) |coef| {
        y += @as(usize, ziRead32(z)) * coef;
        z += 4;
    }
    return y;
}

fn doTzset() void {
    var buf: [NAME_MAX + 25:0]u8 = @splat(0);
    const pathname_base: [*:0]u8 = @ptrCast((&buf).ptr + 24);
    var map: ?[*]const u8 = null;
    var s = getenv("TZ") orelse "/etc/localtime";
    if (s[0] == 0) s = &__utc;
    if (old_tz) |ot| if (cStringEq(@ptrCast(ot), s)) return;
    for (0..5) |i| {
        r0[i] = 0;
        r1[i] = 0;
    }
    if (zi) |z| _ = linux.munmap(z, map_size);
    zi = null;
    var s_len = cStringLen(s);
    if (s_len > PATH_MAX + 1) {
        s = &__utc;
        s_len = 3;
    }
    if (s_len >= old_tz_size) {
        old_tz_size *= 2;
        if (s_len >= old_tz_size) old_tz_size = s_len + 1;
        if (old_tz_size > PATH_MAX + 2) old_tz_size = PATH_MAX + 2;
        old_tz = @ptrCast(malloc(old_tz_size));
    }
    if (old_tz) |ot| @memcpy(ot[0 .. s_len + 1], s[0 .. s_len + 1]);
    var posix_form = false;
    if (s[0] != ':') {
        var p2 = s;
        var dummy_name: [TZNAME_MAX + 1:0]u8 = @splat(0);
        getname(&dummy_name, &p2);
        if (p2 != s and (p2[0] == '+' or p2[0] == '-' or isDigit(p2[0]) or cStringEq(&dummy_name, "UTC") or cStringEq(&dummy_name, "GMT"))) posix_form = true;
    }
    if (!posix_form) {
        if (s[0] == ':') s += 1;
        if (s[0] == '/' or s[0] == '.') {
            if (__libc.secure == 0 or cStringEq(s, "/etc/localtime")) map = __map_file(s, &map_size);
        } else {
            const l0 = cStringLen(s);
            if (l0 <= NAME_MAX and !cStringChr(s, '.')) {
                @memcpy(pathname_base[0 .. l0 + 1], s[0 .. l0 + 1]);
                pathname_base[l0] = 0;
                const search = "/usr/share/zoneinfo/\x00/share/zoneinfo/\x00/etc/zoneinfo/\x00";
                var try_idx: usize = 0;
                while (map == null and search[try_idx] != 0) {
                    const try_path: [*:0]const u8 = @ptrCast(search.ptr + try_idx);
                    const l = cStringLen(try_path);
                    @memcpy((pathname_base - l)[0..l], try_path[0..l]);
                    map = __map_file(pathname_base - l, &map_size);
                    try_idx += l + 1;
                }
            }
        }
        if (map == null) s = &__utc;
    }
    if (map) |m| if (map_size < 44 or !std.mem.eql(u8, m[0..4], "TZif")) {
        _ = linux.munmap(m, map_size);
        map = null;
        s = &__utc;
    };
    zi = map;
    if (map) |m| {
        var scale: u5 = 2;
        if (m[4] != '1') {
            const skip = ziDotprod(m + 20, &.{ 1, 1, 8, 5, 6, 1 });
            trans = m + skip + 44 + 44;
            scale += 1;
        } else trans = m + 44;
        index = trans + (ziRead32(trans - 12) << scale);
        types = index + ziRead32(trans - 12);
        abbrevs = types + 6 * ziRead32(trans - 8);
        abbrevs_end = abbrevs + ziRead32(trans - 4);
        if (m[map_size - 1] == '\n') {
            var pos = map_size - 2;
            while (m[pos] != '\n') : (pos -= 1) {}
            s = @ptrCast(m + pos + 1);
        } else {
            __tzname = .{ null, null };
            __daylight = 0;
            __timezone = 0;
            dst_off = 0;
            var tp = types;
            while (@intFromPtr(tp) < @intFromPtr(abbrevs)) : (tp += 6) {
                if (tp[4] == 0 and __tzname[0] == null) {
                    __tzname[0] = @ptrCast(abbrevs + tp[5]);
                    __timezone = -@as(c_long, @intCast(@as(i32, @bitCast(ziRead32(tp)))));
                }
                if (tp[4] != 0 and __tzname[1] == null) {
                    __tzname[1] = @ptrCast(abbrevs + tp[5]);
                    dst_off = -@as(c_int, @bitCast(ziRead32(tp)));
                    __daylight = 1;
                }
            }
            if (__tzname[0] == null) __tzname[0] = __tzname[1];
            if (__tzname[0] == null) __tzname[0] = &__utc;
            if (__daylight == 0) {
                __tzname[1] = __tzname[0];
                dst_off = @intCast(__timezone);
            }
            return;
        }
    }
    getname(&std_name, &s);
    __tzname[0] = &std_name;
    __timezone = getoff(&s);
    getname(&dst_name, &s);
    __tzname[1] = &dst_name;
    if (dst_name[0] != 0) {
        __daylight = 1;
        if (s[0] == '+' or s[0] == '-' or isDigit(s[0])) dst_off = getoff(&s) else dst_off = @intCast(__timezone - 3600);
    } else {
        __daylight = 0;
        dst_off = @intCast(__timezone);
    }
    if (s[0] == ',') {
        s += 1;
        getrule(&s, &r0);
    }
    if (s[0] == ',') {
        s += 1;
        getrule(&s, &r1);
    }
}

fn scanTrans(t: c_longlong, local: c_int, alt: ?*usize) usize {
    const z = zi.?;
    const scale: u5 = 3 - @as(u5, @intFromBool(trans == z + 44));
    var off: c_int = 0;
    var a: usize = 0;
    var n: usize = (@intFromPtr(index) - @intFromPtr(trans)) >> scale;
    if (n == 0) {
        if (alt) |ap| ap.* = 0;
        return 0;
    }
    while (n > 1) {
        const m = a + n / 2;
        var xu = @as(u64, ziRead32(trans + (m << scale)));
        const x: c_longlong = if (scale == 3) blk: {
            xu = xu << 32 | ziRead32(trans + (m << scale) + 4);
            break :blk @bitCast(xu);
        } else @as(i32, @bitCast(@as(u32, @intCast(xu))));
        if (local != 0) off = @bitCast(ziRead32(types + 6 * index[m - 1]));
        if (t - off < x) n /= 2 else {
            a = m;
            n -= n / 2;
        }
    }
    n = (@intFromPtr(index) - @intFromPtr(trans)) >> scale;
    if (a == n - 1) return std.math.maxInt(usize);
    if (a == 0) {
        var xu = @as(u64, ziRead32(trans));
        const x: c_longlong = if (scale == 3) blk: {
            xu = xu << 32 | ziRead32(trans + 4);
            break :blk @bitCast(xu);
        } else @as(i32, @bitCast(@as(u32, @intCast(xu))));
        var j: usize = 0;
        var i: usize = @intFromPtr(abbrevs) - @intFromPtr(types);
        while (i != 0) {
            i -= 6;
            if (types[i + 4] == 0) j = i;
        }
        if (local != 0) off = @bitCast(ziRead32(types + j));
        if (t - off < x) {
            if (alt) |ap| ap.* = index[0];
            return j / 6;
        }
    }
    if (alt) |ap| {
        if (a != 0 and types[6 * index[a - 1] + 4] != types[6 * index[a] + 4]) ap.* = index[a - 1] else if (a + 1 < n and types[6 * index[a + 1] + 4] != types[6 * index[a] + 4]) ap.* = index[a + 1] else ap.* = index[a];
    }
    return index[a];
}

fn daysInMonth(m: c_int, is_leap: c_int) c_int {
    if (m == 2) return 28 + is_leap;
    return 30 + @as(c_int, @intCast((@as(u32, 0xad5) >> @intCast(m - 1)) & 1));
}

fn ruleToSecs(rule: *const [5]c_int, year: c_longlong) c_longlong {
    var is_leap: c_int = undefined;
    var t = __year_to_secs(year, &is_leap);
    if (rule[0] != 'M') {
        var x = rule[1];
        if (rule[0] == 'J' and (x < 60 or is_leap == 0)) x -= 1;
        t += 86400 * @as(c_longlong, x);
    } else {
        var n = rule[2];
        t += __month_to_secs(rule[1] - 1, is_leap);
        const wday: c_int = @intCast(@divTrunc(@mod(t + 4 * 86400, 7 * 86400), 86400));
        var days = rule[3] - wday;
        if (days < 0) days += 7;
        if (n == 5 and days + 28 >= daysInMonth(rule[1], is_leap)) n = 4;
        t += 86400 * @as(c_longlong, days + 7 * (n - 1));
    }
    t += rule[4];
    return t;
}

fn __secs_to_zone(t: c_longlong, local: c_int, isdst: *c_int, offset: *c_long, oppoff: ?*c_long, zonename: *?[*:0]const u8) callconv(.c) void {
    lockTimezone();
    doTzset();
    if (zi != null) {
        var alt: usize = undefined;
        const i = scanTrans(t, local, &alt);
        if (i != std.math.maxInt(usize)) {
            isdst.* = types[6 * i + 4];
            offset.* = @as(i32, @bitCast(ziRead32(types + 6 * i)));
            zonename.* = @ptrCast(abbrevs + types[6 * i + 5]);
            if (oppoff) |op| op.* = @as(i32, @bitCast(ziRead32(types + 6 * alt)));
            unlockTimezone();
            return;
        }
    }
    if (__daylight != 0) {
        var y: c_longlong = @divTrunc(t, 31556952) + 70;
        while (__year_to_secs(y, null) > t) y -= 1;
        while (__year_to_secs(y + 1, null) < t) y += 1;
        var t0 = ruleToSecs(&r0, y);
        var t1 = ruleToSecs(&r1, y);
        if (local == 0) {
            t0 += __timezone;
            t1 += dst_off;
        }
        if (t0 < t1) {
            if (t >= t0 and t < t1) {
                isdst.* = 1;
                offset.* = -dst_off;
                if (oppoff) |op| op.* = -__timezone;
                zonename.* = __tzname[1];
                unlockTimezone();
                return;
            }
        } else if (!(t >= t1 and t < t0)) {
            isdst.* = 1;
            offset.* = -dst_off;
            if (oppoff) |op| op.* = -__timezone;
            zonename.* = __tzname[1];
            unlockTimezone();
            return;
        }
    }
    isdst.* = 0;
    offset.* = -__timezone;
    if (oppoff) |op| op.* = -dst_off;
    zonename.* = __tzname[0];
    unlockTimezone();
}

fn __tzset() callconv(.c) void {
    lockTimezone();
    doTzset();
    unlockTimezone();
}

fn __tm_to_tzname(t: *const tm) callconv(.c) [*:0]const u8 {
    var p = t.__tm_zone orelse return "";
    lockTimezone();
    doTzset();
    if (p != &__utc and p != __tzname[0] and p != __tzname[1]) {
        if (zi == null or @intFromPtr(p) -% @intFromPtr(abbrevs) >= @intFromPtr(abbrevs_end) - @intFromPtr(abbrevs)) p = "";
    }
    unlockTimezone();
    return p;
}

fn __localtime_r(t: *const time_t, r: *tm) callconv(.c) ?*tm {
    const t64: c_longlong = t.*;
    if (t64 < @as(c_longlong, std.math.minInt(c_int)) * 31622400 or
        t64 > @as(c_longlong, std.math.maxInt(c_int)) * 31622400)
    {
        std.c._errno().* = @intFromEnum(linux.E.OVERFLOW);
        return null;
    }
    __secs_to_zone(t64, 0, &r.tm_isdst, &r.__tm_gmtoff, null, &r.__tm_zone);
    if (__secs_to_tm(t64 + r.__tm_gmtoff, r) < 0) {
        std.c._errno().* = @intFromEnum(linux.E.OVERFLOW);
        return null;
    }
    return r;
}

fn localtimeImpl(t: *const time_t) callconv(.c) ?*tm {
    return __localtime_r(t, &localtime_buf);
}

fn mktimeImpl(t: *tm) callconv(.c) time_t {
    var new: tm = undefined;
    var opp: c_long = undefined;
    var secs = __tm_to_secs(t);

    __secs_to_zone(secs, 1, &new.tm_isdst, &new.__tm_gmtoff, &opp, &new.__tm_zone);

    if (t.tm_isdst >= 0 and new.tm_isdst != t.tm_isdst)
        secs -= opp - new.__tm_gmtoff;

    secs -= new.__tm_gmtoff;

    __secs_to_zone(secs, 0, &new.tm_isdst, &new.__tm_gmtoff, &opp, &new.__tm_zone);

    if (__secs_to_tm(secs + new.__tm_gmtoff, &new) < 0) {
        std.c._errno().* = @intFromEnum(linux.E.OVERFLOW);
        return -1;
    }

    t.* = new;
    return @intCast(secs);
}

fn isAsciiSpace(c: u8) bool {
    return c == ' ' or (c -% '\t' < 5);
}

fn isAsciiDigit(c: u8) bool {
    return c -% '0' < 10;
}

fn asciiLower(c: u8) u8 {
    if (c -% 'A' < 26) return c | 32;
    return c;
}

fn cStrLen(s: [*:0]const u8) usize {
    var len: usize = 0;
    while (s[len] != 0) len += 1;
    return len;
}

fn cStrNCaseCmp(a: [*:0]const u8, b: [*:0]const u8, len: usize) c_int {
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const ca = asciiLower(a[i]);
        const cb = asciiLower(b[i]);
        if (ca != cb) return @as(c_int, ca) - @as(c_int, cb);
    }
    return 0;
}

fn parseUnsignedWidth(f: [*:0]const u8, out: *c_int) [*:0]const u8 {
    var p = f;
    var value: c_ulong = 0;
    const max: c_ulong = @intCast(std.math.maxInt(c_int));
    while (isAsciiDigit(p[0])) {
        if (value <= @divTrunc(max - (p[0] - '0'), 10)) {
            value = value * 10 + (p[0] - '0');
        } else {
            value = max;
        }
        p += 1;
    }
    out.* = @intCast(value);
    return p;
}

fn parseInto(dest: *c_int, s_ptr: *[*:0]const u8, width: c_int) void {
    var s = s_ptr.*;
    var i: c_int = 0;
    dest.* = 0;
    while (i < width and isAsciiDigit(s[0])) : (i += 1) {
        dest.* = dest.* * 10 + @as(c_int, s[0] - '0');
        s += 1;
    }
    s_ptr.* = s;
}

fn strptimeImpl(s_arg: [*:0]const u8, f_arg: [*:0]const u8, t: *tm) callconv(.c) ?[*:0]const u8 {
    var s = s_arg;
    var f = f_arg;
    var w: c_int = undefined;
    var adj: c_int = undefined;
    var min: c_int = undefined;
    var range: c_int = undefined;
    var dest: *c_int = undefined;
    var dummy: c_int = undefined;
    var want_century: c_int = 0;
    var century: c_int = 0;
    var relyear: c_int = 0;

    while (f[0] != 0) {
        if (f[0] != '%') {
            if (isAsciiSpace(f[0])) {
                while (s[0] != 0 and isAsciiSpace(s[0])) s += 1;
            } else if (s[0] != f[0]) {
                return null;
            } else {
                s += 1;
            }
            f += 1;
            continue;
        }
        f += 1;
        if (f[0] == '+') f += 1;
        if (isAsciiDigit(f[0])) {
            f = parseUnsignedWidth(f, &w);
        } else {
            w = -1;
        }
        adj = 0;
        const fmt = f[0];
        f += 1;
        switch (fmt) {
            'a', 'A' => {
                dest = &t.tm_wday;
                min = if (fmt == 'a') ABDAY_1 else DAY_1;
                range = 7;
            },
            'b', 'B', 'h' => {
                dest = &t.tm_mon;
                min = if (fmt == 'B') MON_1 else ABMON_1;
                range = 12;
            },
            'c' => {
                s = strptimeImpl(s, nl_langinfo(D_T_FMT), t) orelse return null;
                continue;
            },
            'C' => {
                dest = &century;
                if (w < 0) w = 2;
                want_century |= 2;
                if (!parseNumericDigits(dest, &s, w, adj)) return null;
                continue;
            },
            'd', 'e' => {
                dest = &t.tm_mday;
                min = 1;
                range = 31;
                if (!parseNumericRange(dest, &s, min, range, adj)) return null;
                continue;
            },
            'D' => {
                s = strptimeImpl(s, "%m/%d/%y", t) orelse return null;
                continue;
            },
            'H' => {
                dest = &t.tm_hour;
                min = 0;
                range = 24;
                if (!parseNumericRange(dest, &s, min, range, adj)) return null;
                continue;
            },
            'I' => {
                dest = &t.tm_hour;
                min = 1;
                range = 12;
                if (!parseNumericRange(dest, &s, min, range, adj)) return null;
                continue;
            },
            'j' => {
                dest = &t.tm_yday;
                min = 1;
                range = 366;
                adj = 1;
                if (!parseNumericRange(dest, &s, min, range, adj)) return null;
                continue;
            },
            'm' => {
                dest = &t.tm_mon;
                min = 1;
                range = 12;
                adj = 1;
                if (!parseNumericRange(dest, &s, min, range, adj)) return null;
                continue;
            },
            'M' => {
                dest = &t.tm_min;
                min = 0;
                range = 60;
                if (!parseNumericRange(dest, &s, min, range, adj)) return null;
                continue;
            },
            'n', 't' => {
                while (s[0] != 0 and isAsciiSpace(s[0])) s += 1;
                continue;
            },
            'p' => {
                var ex = nl_langinfo(AM_STR);
                var len = cStrLen(ex);
                if (cStrNCaseCmp(s, ex, len) == 0) {
                    t.tm_hour = @rem(t.tm_hour, 12);
                    s += len;
                    continue;
                }
                ex = nl_langinfo(PM_STR);
                len = cStrLen(ex);
                if (cStrNCaseCmp(s, ex, len) == 0) {
                    t.tm_hour = @rem(t.tm_hour, 12);
                    t.tm_hour += 12;
                    s += len;
                    continue;
                }
                return null;
            },
            'r' => {
                s = strptimeImpl(s, nl_langinfo(T_FMT_AMPM), t) orelse return null;
                continue;
            },
            'R' => {
                s = strptimeImpl(s, "%H:%M", t) orelse return null;
                continue;
            },
            'S' => {
                dest = &t.tm_sec;
                min = 0;
                range = 61;
                if (!parseNumericRange(dest, &s, min, range, adj)) return null;
                continue;
            },
            'T' => {
                s = strptimeImpl(s, "%H:%M:%S", t) orelse return null;
                continue;
            },
            'U', 'W' => {
                dest = &dummy;
                min = 0;
                range = 54;
                if (!parseNumericRange(dest, &s, min, range, adj)) return null;
                continue;
            },
            'w' => {
                dest = &t.tm_wday;
                min = 0;
                range = 7;
                if (!parseNumericRange(dest, &s, min, range, adj)) return null;
                continue;
            },
            'x' => {
                s = strptimeImpl(s, nl_langinfo(D_FMT), t) orelse return null;
                continue;
            },
            'X' => {
                s = strptimeImpl(s, nl_langinfo(T_FMT), t) orelse return null;
                continue;
            },
            'y' => {
                dest = &relyear;
                w = 2;
                want_century |= 1;
                if (!parseNumericDigits(dest, &s, w, adj)) return null;
                continue;
            },
            'Y' => {
                dest = &t.tm_year;
                if (w < 0) w = 4;
                adj = 1900;
                want_century = 0;
                if (!parseNumericDigits(dest, &s, w, adj)) return null;
                continue;
            },
            '%' => {
                if (s[0] != '%') return null;
                s += 1;
                continue;
            },
            else => return null,
        }

        var i: c_int = 2 * range - 1;
        while (i >= 0) : (i -= 1) {
            const ex = nl_langinfo(min + i);
            const len = cStrLen(ex);
            if (cStrNCaseCmp(s, ex, len) != 0) continue;
            s += len;
            dest.* = @rem(i, range);
            break;
        }
        if (i < 0) return null;
    }

    if (want_century != 0) {
        t.tm_year = relyear;
        if ((want_century & 2) != 0) {
            t.tm_year += century * 100 - 1900;
        } else if (t.tm_year <= 68) {
            t.tm_year += 100;
        }
    }
    return s;
}

fn parseNumericRange(dest: *c_int, s: *[*:0]const u8, min: c_int, range: c_int, adj: c_int) bool {
    if (!isAsciiDigit(s.*[0])) return false;
    dest.* = 0;
    var i: c_int = 1;
    while (i <= min + range and isAsciiDigit(s.*[0])) : (i *= 10) {
        dest.* = dest.* * 10 + @as(c_int, s.*[0] - '0');
        s.* += 1;
    }
    const diff: c_uint = @bitCast(dest.* -% min);
    if (diff >= @as(c_uint, @bitCast(range))) return false;
    dest.* -= adj;
    return true;
}

fn parseNumericDigits(dest: *c_int, s: *[*:0]const u8, width: c_int, adj: c_int) bool {
    var neg = false;
    if (s.*[0] == '+') {
        s.* += 1;
    } else if (s.*[0] == '-') {
        neg = true;
        s.* += 1;
    }
    if (!isAsciiDigit(s.*[0])) return false;
    parseInto(dest, s, width);
    if (neg) dest.* = -dest.*;
    dest.* -= adj;
    return true;
}

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
        const p = strptimeImpl(s, @ptrCast(&fmt), &tmbuf);
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

const locale_t = *opaque {};
const nl_item = c_int;
const wchar_t = std.c.wchar_t;

const ABDAY_1: nl_item = 0x20000;
const DAY_1: nl_item = 0x20007;
const ABMON_1: nl_item = 0x2000E;
const MON_1: nl_item = 0x2001A;
const AM_STR: nl_item = 0x20026;
const PM_STR: nl_item = 0x20027;
const D_T_FMT: nl_item = 0x20028;
const D_FMT: nl_item = 0x20029;
const T_FMT: nl_item = 0x2002A;
const T_FMT_AMPM: nl_item = 0x2002B;

extern "c" fn __nl_langinfo_l(item: nl_item, loc: locale_t) callconv(.c) [*:0]const u8;
extern "c" fn pthread_self() callconv(.c) *pthread;
extern "c" fn mbstowcs(dest: ?[*]wchar_t, src: [*:0]const u8, n: usize) callconv(.c) usize;

const locale_struct = extern struct { cat: [6]?*const anyopaque };
const pthread = extern struct {
    self: *pthread,
    dtv: if (tls_above_tp) void else *usize,
    prev: *pthread,
    next: *pthread,
    sysinfo: usize,
    canary_pad: if (builtin.cpu.arch == .mips64 or builtin.cpu.arch == .mips64el) usize else void,
    canary: if (tls_above_tp) void else usize,
    tid: c_int,
    errno_val: c_int,
    detach_state: c_int,
    cancel: c_int,
    canceldisable: u8,
    cancelasync: u8,
    tsd_used_dlerror_flag: u8,
    map_base: *u8,
    map_size: usize,
    stack: *anyopaque,
    stack_size: usize,
    guard_size: usize,
    result: *anyopaque,
    cancelbuf: *anyopaque,
    tsd: *?*anyopaque,
    robust_list: extern struct { head: *volatile anyopaque, off: c_long, pending: *volatile anyopaque },
    h_errno_val: c_int,
    timer_id: c_int,
    locale: *locale_struct,
};

fn currentLocale() locale_t {
    return @ptrCast(pthread_self().locale);
}

fn isLeap(y_arg: c_int) c_int {
    var y = y_arg;
    if (y > std.math.maxInt(c_int) - 1900) y -= 2000;
    y += 1900;
    return @intFromBool(@rem(y, 4) == 0 and (@rem(y, 100) != 0 or @rem(y, 400) == 0));
}

fn weekNum(t: *const tm) c_int {
    var val: c_int = @intCast((@as(c_uint, @bitCast(t.tm_yday)) + 7 - ((@as(c_uint, @bitCast(t.tm_wday)) + 6) % 7)) / 7);
    if ((@as(c_uint, @bitCast(t.tm_wday)) + 371 - @as(c_uint, @bitCast(t.tm_yday)) - 2) % 7 <= 2) val += 1;
    if (val == 0) {
        val = 52;
        const dec31 = (@as(c_uint, @bitCast(t.tm_wday)) + 7 - @as(c_uint, @bitCast(t.tm_yday)) - 1) % 7;
        if (dec31 == 4 or (dec31 == 5 and isLeap(@rem(t.tm_year, 400) - 1) != 0)) val += 1;
    } else if (val == 53) {
        const jan1 = (@as(c_uint, @bitCast(t.tm_wday)) + 371 - @as(c_uint, @bitCast(t.tm_yday))) % 7;
        if (jan1 != 4 and (jan1 != 3 or isLeap(t.tm_year) == 0)) val = 1;
    }
    return val;
}

fn cstrLen(s: [*:0]const u8) usize {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

fn fmtSigned(buf: *[100]u8, val: c_longlong, width: usize, pad: u8) usize {
    var tmp: [64]u8 = undefined;
    const neg = val < 0;
    var u: u64 = if (neg) @intCast(-(val + 1)) else @intCast(val);
    if (neg) u += 1;
    var pos: usize = tmp.len;
    while (true) {
        pos -= 1;
        tmp[pos] = '0' + @as(u8, @intCast(u % 10));
        u /= 10;
        if (u == 0) break;
    }
    const digits_len = tmp.len - pos;
    var out: usize = 0;
    if (pad == '0') {
        if (neg) {
            buf[out] = '-';
            out += 1;
        }
        var pad_count = if (width > digits_len + @intFromBool(neg)) width - digits_len - @intFromBool(neg) else 0;
        while (pad_count != 0) : (pad_count -= 1) {
            buf[out] = '0';
            out += 1;
        }
    } else {
        var pad_count = if (width > digits_len + @intFromBool(neg)) width - digits_len - @intFromBool(neg) else 0;
        if (pad == '_') while (pad_count != 0) : (pad_count -= 1) {
            buf[out] = ' ';
            out += 1;
        };
        if (neg) {
            buf[out] = '-';
            out += 1;
        }
    }
    @memcpy(buf[out .. out + digits_len], tmp[pos..]);
    out += digits_len;
    buf[out] = 0;
    return out;
}

fn fmtZone(buf: *[100]u8, val: c_long) usize {
    const neg = val < 0;
    var u: c_long = if (neg) -val else val;
    buf[0] = if (neg) '-' else '+';
    var i: usize = 5;
    while (i > 1) {
        i -= 1;
        buf[i] = '0' + @as(u8, @intCast(@rem(u, 10)));
        u = @divTrunc(u, 10);
    }
    buf[5] = 0;
    return 5;
}
fn stringResult(s: [*:0]const u8, len: *usize) [*:0]const u8 {
    len.* = cstrLen(s);
    return s;
}
fn nlStrcat(item: nl_item, loc: locale_t, len: *usize) [*:0]const u8 {
    return stringResult(__nl_langinfo_l(item, loc), len);
}
fn nlStrftime(buf: *[100]u8, len: *usize, item: nl_item, t: *const tm, loc: locale_t) ?[*:0]const u8 {
    return recuStrftime(buf, len, __nl_langinfo_l(item, loc), t, loc);
}
fn recuStrftime(buf: *[100]u8, len: *usize, fmt: [*:0]const u8, t: *const tm, loc: locale_t) ?[*:0]const u8 {
    len.* = __strftime_l(@ptrCast(buf), buf.len, fmt, t, loc);
    if (len.* == 0) return null;
    return @ptrCast(buf);
}

fn strftimeFmt1(buf: *[100]u8, len: *usize, f: c_int, t: *const tm, loc: locale_t, pad_arg: c_int) callconv(.c) ?[*:0]const u8 {
    var val: c_longlong = undefined;
    var width: usize = 2;
    var def_pad: u8 = '0';
    switch (f) {
        'a' => return if (@as(c_uint, @bitCast(t.tm_wday)) > 6) stringResult("-", len) else nlStrcat(ABDAY_1 + t.tm_wday, loc, len),
        'A' => return if (@as(c_uint, @bitCast(t.tm_wday)) > 6) stringResult("-", len) else nlStrcat(DAY_1 + t.tm_wday, loc, len),
        'h', 'b' => return if (@as(c_uint, @bitCast(t.tm_mon)) > 11) stringResult("-", len) else nlStrcat(ABMON_1 + t.tm_mon, loc, len),
        'B' => return if (@as(c_uint, @bitCast(t.tm_mon)) > 11) stringResult("-", len) else nlStrcat(MON_1 + t.tm_mon, loc, len),
        'c' => return nlStrftime(buf, len, D_T_FMT, t, loc),
        'C' => val = @divTrunc(@as(c_longlong, 1900) + t.tm_year, 100),
        'e' => {
            def_pad = '_';
            val = t.tm_mday;
        },
        'd' => val = t.tm_mday,
        'D' => return recuStrftime(buf, len, "%m/%d/%y", t, loc),
        'F' => return recuStrftime(buf, len, "%Y-%m-%d", t, loc),
        'g', 'G' => {
            val = @as(c_longlong, t.tm_year) + 1900;
            if (t.tm_yday < 3 and weekNum(t) != 1) val -= 1 else if (t.tm_yday > 360 and weekNum(t) == 1) val += 1;
            if (f == 'g') val = @rem(val, 100) else width = 4;
        },
        'H' => val = t.tm_hour,
        'I' => {
            val = t.tm_hour;
            if (val == 0) val = 12 else if (val > 12) val -= 12;
        },
        'j' => {
            val = t.tm_yday + 1;
            width = 3;
        },
        'm' => val = t.tm_mon + 1,
        'M' => val = t.tm_min,
        'n' => {
            len.* = 1;
            return "\n";
        },
        'p' => return nlStrcat(if (t.tm_hour >= 12) PM_STR else AM_STR, loc, len),
        'r' => return nlStrftime(buf, len, T_FMT_AMPM, t, loc),
        'R' => return recuStrftime(buf, len, "%H:%M", t, loc),
        's' => {
            val = __tm_to_secs(t) - t.__tm_gmtoff;
            width = 1;
        },
        'S' => val = t.tm_sec,
        't' => {
            len.* = 1;
            return "\t";
        },
        'T' => return recuStrftime(buf, len, "%H:%M:%S", t, loc),
        'u' => {
            val = if (t.tm_wday != 0) t.tm_wday else 7;
            width = 1;
        },
        'U' => val = @intCast((@as(c_uint, @bitCast(t.tm_yday)) + 7 - @as(c_uint, @bitCast(t.tm_wday))) / 7),
        'W' => val = @intCast((@as(c_uint, @bitCast(t.tm_yday)) + 7 - ((@as(c_uint, @bitCast(t.tm_wday)) + 6) % 7)) / 7),
        'V' => val = weekNum(t),
        'w' => {
            val = t.tm_wday;
            width = 1;
        },
        'x' => return nlStrftime(buf, len, D_FMT, t, loc),
        'X' => return nlStrftime(buf, len, T_FMT, t, loc),
        'y' => {
            val = @rem(@as(c_longlong, t.tm_year) + 1900, 100);
            if (val < 0) val = -val;
        },
        'Y' => {
            val = @as(c_longlong, t.tm_year) + 1900;
            if (val >= 10000) {
                len.* = fmtSigned(buf, val, 1, '-');
                if (buf[0] != '-') {
                    std.mem.copyBackwards(u8, buf[1 .. len.* + 1], buf[0..len.*]);
                    buf[0] = '+';
                    len.* += 1;
                    buf[len.*] = 0;
                }
                return @ptrCast(buf);
            }
            width = 4;
        },
        'z' => {
            if (t.tm_isdst < 0) {
                len.* = 0;
                return "";
            }
            len.* = fmtZone(buf, @divTrunc(t.__tm_gmtoff, 3600) * 100 + @divTrunc(@rem(t.__tm_gmtoff, 3600), 60));
            return @ptrCast(buf);
        },
        'Z' => {
            if (t.tm_isdst < 0) {
                len.* = 0;
                return "";
            }
            return stringResult(__tm_to_tzname(t), len);
        },
        '%' => {
            len.* = 1;
            return "%";
        },
        else => return null,
    }
    const pad: u8 = if (pad_arg != 0) @intCast(pad_arg) else def_pad;
    len.* = switch (pad) {
        '-' => fmtSigned(buf, val, 1, '-'),
        '_' => fmtSigned(buf, val, width, '_'),
        else => fmtSigned(buf, val, width, '0'),
    };
    return @ptrCast(buf);
}

fn parseAsciiWidth(f: [*:0]const u8, end: *[*:0]const u8) c_ulong {
    var p = f;
    var width: c_ulong = 0;
    while (p[0] >= '0' and p[0] <= '9') : (p += 1) width = width * 10 + (p[0] - '0');
    end.* = p;
    return width;
}

fn __strftime_l(s: [*]u8, n: usize, f_arg: [*:0]const u8, t: *const tm, loc: locale_t) callconv(.c) usize {
    var l: usize = 0;
    var f = f_arg;
    while (l < n) : (f += 1) {
        if (f[0] == 0) {
            s[l] = 0;
            return l;
        }
        if (f[0] != '%') {
            s[l] = f[0];
            l += 1;
            continue;
        }
        f += 1;
        var pad: c_int = 0;
        if (f[0] == '-' or f[0] == '_' or f[0] == '0') {
            pad = f[0];
            f += 1;
        }
        const plus = f[0] == '+';
        if (plus) f += 1;
        var p: [*:0]const u8 = undefined;
        var width = parseAsciiWidth(f, &p);
        if (p[0] == 'C' or p[0] == 'F' or p[0] == 'G' or p[0] == 'Y') {
            if (width == 0 and p != f) width = 1;
        } else width = 0;
        f = p;
        if (f[0] == 'E' or f[0] == 'O') f += 1;
        var buf: [100]u8 = undefined;
        var k: usize = undefined;
        var text = strftimeFmt1(&buf, &k, f[0], t, loc, pad) orelse break;
        if (width != 0) {
            if (text[0] == '+' or text[0] == '-') {
                text += 1;
                k -= 1;
            }
            while (text[0] == '0' and @as(c_uint, text[1] -% '0') < 10) {
                text += 1;
                k -= 1;
            }
            if (width < k) width = k;
            var d: usize = 0;
            while (@as(c_uint, text[d] -% '0') < 10) : (d += 1) {}
            if (t.tm_year < -1900) {
                s[l] = '-';
                l += 1;
                width -= 1;
            } else if (plus and d + (width - k) >= @as(usize, if (p[0] == 'C') 3 else 5)) {
                s[l] = '+';
                l += 1;
                width -= 1;
            }
            while (width > k and l < n) : (width -= 1) {
                s[l] = '0';
                l += 1;
            }
        }
        if (k > n - l) k = n - l;
        @memcpy(s[l .. l + k], text[0..k]);
        l += k;
    }
    if (n != 0) {
        if (l == n) l = n - 1;
        s[l] = 0;
    }
    return 0;
}

fn strftimeImpl(s: [*]u8, n: usize, f: [*:0]const u8, t: *const tm) callconv(.c) usize {
    return __strftime_l(s, n, f, t, currentLocale());
}

fn parseWideWidth(f: [*:0]const wchar_t, end: *[*:0]const wchar_t) c_ulong {
    var p = f;
    var width: c_ulong = 0;
    while (p[0] >= '0' and p[0] <= '9') : (p += 1) width = width * 10 + @as(c_ulong, @intCast(p[0] - '0'));
    end.* = p;
    return width;
}

fn __wcsftime_l(s: [*]wchar_t, n: usize, f_arg: [*:0]const wchar_t, t: *const tm, loc: locale_t) callconv(.c) usize {
    var l: usize = 0;
    var f = f_arg;
    while (l < n) : (f += 1) {
        if (f[0] == 0) {
            s[l] = 0;
            return l;
        }
        if (f[0] != '%') {
            s[l] = f[0];
            l += 1;
            continue;
        }
        f += 1;
        var pad: c_int = 0;
        if (f[0] == '-' or f[0] == '_' or f[0] == '0') {
            pad = @intCast(f[0]);
            f += 1;
        }
        const plus = f[0] == '+';
        if (plus) f += 1;
        var p: [*:0]const wchar_t = undefined;
        var width = parseWideWidth(f, &p);
        if (p[0] == 'C' or p[0] == 'F' or p[0] == 'G' or p[0] == 'Y') {
            if (width == 0 and p != f) width = 1;
        } else width = 0;
        f = p;
        if (f[0] == 'E' or f[0] == 'O') f += 1;
        var buf: [100]u8 = undefined;
        var wbuf: [100]wchar_t = undefined;
        var k: usize = undefined;
        const text_mb = strftimeFmt1(&buf, &k, @intCast(f[0]), t, loc, pad) orelse break;
        k = mbstowcs(&wbuf, text_mb, wbuf.len);
        if (k == std.math.maxInt(usize)) return 0;
        var text: [*]wchar_t = &wbuf;
        if (width != 0) {
            while (text[0] == '+' or text[0] == '-' or (text[0] == '0' and text[1] != 0)) {
                text += 1;
                k -= 1;
            }
            width -= 1;
            if (plus and t.tm_year >= 10000 - 1900) {
                s[l] = '+';
                l += 1;
            } else if (t.tm_year < -1900) {
                s[l] = '-';
                l += 1;
            } else width += 1;
            while (width > k and l < n) : (width -= 1) {
                s[l] = '0';
                l += 1;
            }
        }
        if (k >= n - l) k = n - l;
        @memcpy(s[l .. l + k], text[0..k]);
        l += k;
    }
    if (n != 0) {
        if (l == n) l = n - 1;
        s[l] = 0;
    }
    return 0;
}

fn wcsftimeImpl(s: [*]wchar_t, n: usize, f: [*:0]const wchar_t, t: *const tm) callconv(.c) usize {
    return __wcsftime_l(s, n, f, t, currentLocale());
}

fn timesLinux(tms_ptr: ?*anyopaque) callconv(.c) c_long {
    const ret: isize = @bitCast(linux.syscall1(.times, if (tms_ptr) |p| @intFromPtr(p) else 0));
    return @intCast(ret);
}

const utimbuf = extern struct {
    actime: time_t,
    modtime: time_t,
};

fn utimeLinux(path: [*:0]const u8, times_ptr: ?*const utimbuf) callconv(.c) c_int {
    if (times_ptr) |t| {
        const ts = [2]Timespec{
            .{ .sec = t.actime, .nsec = 0 },
            .{ .sec = t.modtime, .nsec = 0 },
        };
        return utimensatTimespec(linux.AT.FDCWD, path, &ts, 0);
    }
    return utimensatTimespec(linux.AT.FDCWD, path, null, 0);
}

fn nanosleepLinux(req: *const linux.timespec, rem: ?*linux.timespec) callconv(.c) c_int {
    return errno(linux.nanosleep(req, rem));
}

fn clock_nanosleepLinux(clk: c_int, flags: c_int, req: *const linux.timespec, rem: ?*linux.timespec) callconv(.c) c_int {
    const r = linux.clock_nanosleep(@enumFromInt(@as(u32, @bitCast(clk))), @bitCast(@as(u32, @bitCast(flags))), req, rem);
    if (r != 0) {
        std.c._errno().* = @intCast(r);
        return -1;
    }
    return 0;
}

// timer_delete.c
const SIGTIMER: usize = 32;
const ptr_size = @sizeOf(usize);
const tls_above_tp = switch (builtin.cpu.arch) {
    .aarch64, .aarch64_be, .arm, .armeb, .thumb, .thumbeb, .riscv64, .riscv32, .mips, .mipsel, .mips64, .mips64el, .powerpc, .powerpcle, .powerpc64, .powerpc64le, .loongarch64, .m68k => true,
    else => false,
};
const part1_size: usize = if (tls_above_tp) 4 * ptr_size else 6 * ptr_size;
const map_base_off: usize = if (ptr_size == 8) 24 else 20;
const off_tid = part1_size;
const off_timer_id = part1_size + map_base_off + 11 * ptr_size + 4;

fn timer_deleteLinux(t: *opaque {}) callconv(.c) c_int {
    const t_int: isize = @bitCast(@intFromPtr(t));
    if (t_int < 0) {
        const td_addr: usize = @intFromPtr(t) << 1;
        const timer_id_ptr: *volatile c_int = @ptrFromInt(td_addr + off_timer_id);
        const old_val = @atomicLoad(c_int, timer_id_ptr, .seq_cst);
        @atomicStore(c_int, timer_id_ptr, old_val | std.math.minInt(c_int), .seq_cst);
        const tid: c_int = (@as(*const c_int, @ptrFromInt(td_addr + off_tid))).*;
        _ = linux.syscall2(.tkill, @as(usize, @intCast(tid)), SIGTIMER);
        return 0;
    }
    return errno(linux.syscall1(.timer_delete, @intFromPtr(t)));
}

// timer_getoverrun.c
fn timer_getoverrunLinux(t: *opaque {}) callconv(.c) c_int {
    var sys_t: usize = @intFromPtr(t);
    const t_int: isize = @bitCast(sys_t);
    if (t_int < 0) {
        const td_addr: usize = sys_t << 1;
        const timer_id: c_int = (@as(*const c_int, @ptrFromInt(td_addr + off_timer_id))).*;
        sys_t = @as(usize, @intCast(timer_id & std.math.maxInt(c_int)));
    }
    return errno(linux.syscall1(.timer_getoverrun, sys_t));
}

// timer_gettime.c
fn timer_gettimeLinux(t: *opaque {}, val: *Itimerspec) callconv(.c) c_int {
    var sys_t: usize = @intFromPtr(t);
    const t_int: isize = @bitCast(sys_t);
    if (t_int < 0) {
        const td_addr: usize = sys_t << 1;
        const timer_id: c_int = (@as(*const c_int, @ptrFromInt(td_addr + off_timer_id))).*;
        sys_t = @as(usize, @intCast(timer_id & std.math.maxInt(c_int)));
    }

    if (comptime !@hasField(linux.SYS, "timer_gettime64")) {
        // 64-bit-time arches: timer_gettime is the kernel's natural 64-bit-time entry.
        return errno(linux.syscall2(.timer_gettime, sys_t, @intFromPtr(val)));
    }
    if (comptime !@hasField(linux.SYS, "timer_gettime")) {
        // 32-bit-time-only arches (riscv32, loongarch32): only timer_gettime64 exists.
        return errno(linux.syscall2(.timer_gettime64, sys_t, @intFromPtr(val)));
    }
    // Legacy 32-bit arches with both: prefer time64, fall back to legacy on -ENOSYS.
    const enosys: isize = -@as(isize, @intFromEnum(linux.E.NOSYS));
    var r: isize = enosys;
    if (@sizeOf(time_t) > 4) {
        r = @bitCast(linux.syscall2(.timer_gettime64, sys_t, @intFromPtr(val)));
    }
    if (r != enosys) {
        return errno(@as(usize, @bitCast(r)));
    }
    var val32: [4]c_long = undefined;
    r = @bitCast(linux.syscall2(.timer_gettime, sys_t, @intFromPtr(&val32)));
    if (r == 0) {
        val.it_interval.sec = @intCast(val32[0]);
        val.it_interval.nsec = @intCast(val32[1]);
        val.it_value.sec = @intCast(val32[2]);
        val.it_value.nsec = @intCast(val32[3]);
    }
    return errno(@as(usize, @bitCast(r)));
}

const sigval = extern union {
    sival_int: c_int,
    sival_ptr: ?*anyopaque,
};

const sigevent = extern struct {
    sigev_value: sigval,
    sigev_signo: c_int,
    sigev_notify: c_int,
    sigev_fields: extern union {
        __pad: [64 - 2 * @sizeOf(c_int) - @sizeOf(sigval)]u8,
        sigev_notify_thread_id: linux.pid_t,
        sev_thread: extern struct {
            sigev_notify_function: ?*const fn (sigval) callconv(.c) void,
            sigev_notify_attributes: ?*anyopaque,
        },
    },
};

const ksigevent = extern struct {
    sigev_value: sigval,
    sigev_signo: c_int,
    sigev_notify: c_int,
    sigev_tid: c_int,
};

const SIGEV_SIGNAL = 0;
const SIGEV_NONE = 1;
const SIGEV_THREAD = 2;
const SIGEV_THREAD_ID = 4;

// timer_create.c
fn timer_createLinux(clk: c_int, evp: ?*sigevent, res: **opaque {}) callconv(.c) c_int {
    var ksev: ksigevent = undefined;
    var ksevp: ?*ksigevent = null;
    var timerid: c_int = undefined;

    switch (if (evp) |ev| ev.sigev_notify else SIGEV_SIGNAL) {
        SIGEV_NONE, SIGEV_SIGNAL, SIGEV_THREAD_ID => {
            if (evp) |ev| {
                ksev.sigev_value = ev.sigev_value;
                ksev.sigev_signo = ev.sigev_signo;
                ksev.sigev_notify = ev.sigev_notify;
                ksev.sigev_tid = if (ev.sigev_notify == SIGEV_THREAD_ID) ev.sigev_fields.sigev_notify_thread_id else 0;
                ksevp = &ksev;
            }
            if (errno(linux.syscall3(.timer_create, @as(usize, @intCast(clk)), @intFromPtr(ksevp), @intFromPtr(&timerid))) < 0) return -1;
            res.* = @ptrFromInt(@as(usize, @bitCast(@as(isize, timerid))));
        },
        SIGEV_THREAD => {
            // The SIGEV_THREAD path is implemented by musl in terms of a helper
            // thread and the kernel SIGEV_THREAD_ID notification mode.  Keep the
            // ABI constants here so the common syscall modes are migrated now;
            // this uncommon emulation path can be filled in with pthread_create.
            std.c._errno().* = @intFromEnum(linux.E.INVAL);
            return -1;
        },
        else => {
            std.c._errno().* = @intFromEnum(linux.E.INVAL);
            return -1;
        },
    }

    return 0;
}

fn is32Bit(x: time_t) bool {
    return is32BitTime(x);
}

// timer_settime.c
fn timer_settimeLinux(t: *opaque {}, flags: c_int, val: *const Itimerspec, old: ?*Itimerspec) callconv(.c) c_int {
    var sys_t: usize = @intFromPtr(t);
    const t_int: isize = @bitCast(sys_t);
    if (t_int < 0) {
        const td_addr = sys_t << 1;
        const timer_id: c_int = (@as(*const c_int, @ptrFromInt(td_addr + off_timer_id))).*;
        sys_t = @as(usize, @intCast(timer_id & std.math.maxInt(c_int)));
    }

    if (comptime !@hasField(linux.SYS, "timer_settime64")) {
        return errno(linux.syscall4(.timer_settime, sys_t, @as(usize, @bitCast(@as(isize, flags))), @intFromPtr(val), @intFromPtr(old)));
    }
    const is = val.it_interval.sec;
    const vs = val.it_value.sec;
    const ins = val.it_interval.nsec;
    const vns = val.it_value.nsec;
    const enosys: isize = -@as(isize, @intFromEnum(linux.E.NOSYS));
    var r: isize = enosys;
    var new64 = [4]i64{ is, ins, vs, vns };
    if ((comptime !@hasField(linux.SYS, "timer_settime")) or !is32Bit(is) or !is32Bit(vs) or (@sizeOf(time_t) > 4 and old != null)) {
        r = @bitCast(linux.syscall4(.timer_settime64, sys_t, @as(usize, @bitCast(@as(isize, flags))), @intFromPtr(&new64), @intFromPtr(old)));
    }
    if ((comptime !@hasField(linux.SYS, "timer_settime")) or r != enosys) return errno(@as(usize, @bitCast(r)));
    if (!is32Bit(is) or !is32Bit(vs)) return errno(@as(usize, @bitCast(-@as(isize, @intFromEnum(linux.E.OPNOTSUPP)))));

    var new32 = [4]c_long{ @intCast(is), @intCast(ins), @intCast(vs), @intCast(vns) };
    var old32: [4]c_long = undefined;
    r = @bitCast(linux.syscall4(.timer_settime, sys_t, @as(usize, @bitCast(@as(isize, flags))), @intFromPtr(&new32), if (old != null) @intFromPtr(&old32) else 0));
    if (r == 0) if (old) |o| {
        o.it_interval.sec = @intCast(old32[0]);
        o.it_interval.nsec = @intCast(old32[1]);
        o.it_value.sec = @intCast(old32[2]);
        o.it_value.nsec = @intCast(old32[3]);
    };
    return errno(@as(usize, @bitCast(r)));
}
