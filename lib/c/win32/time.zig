//! Windows (Win32) implementations of POSIX time primitives that were
//! previously provided by `libc/mingw/winpthreads/clock.c`,
//! `libc/mingw/winpthreads/nanosleep.c`, and
//! `libc/mingw/misc/gettimeofday.c`.
//!
//! Issue #248 Phase 2. These functions replace the mingw-w64 sources
//! that are dropped from `src/libs/mingw.zig` in the same commit.
//!
//! Semantics match what mingw-w64 winpthreads + libmingwex provided:
//!   * CLOCK_REALTIME (+COARSE): UNIX epoch, derived from the Windows
//!     FILETIME clock via GetSystemTimePreciseAsFileTime
//!     (or GetSystemTimeAsFileTime pre-Win8). 100ns resolution.
//!   * CLOCK_MONOTONIC: QueryPerformanceCounter scaled to ns.
//!   * CLOCK_PROCESS_CPUTIME_ID / CLOCK_THREAD_CPUTIME_ID: GetProcessTimes
//!     / GetThreadTimes summed (user+kernel).
//!   * nanosleep: NtDelayExecution with 100ns relative time.

const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const symbol = @import("../../c.zig").symbol;

const clockid_t = std.c.clockid_t;
const timespec = std.c.timespec;
const timeval = std.c.timeval;
const timezone = std.c.timezone;

// 100ns units between 1601-01-01 (Windows epoch) and 1970-01-01 (Unix epoch).
const FILETIME_1970: u64 = 116_444_736_000_000_000;

extern "kernel32" fn QueryPerformanceCounter(counter: *windows.LARGE_INTEGER) callconv(.winapi) windows.BOOL;
extern "kernel32" fn QueryPerformanceFrequency(freq: *windows.LARGE_INTEGER) callconv(.winapi) windows.BOOL;
extern "kernel32" fn GetSystemTimeAsFileTime(ft: *windows.FILETIME) callconv(.winapi) void;
extern "kernel32" fn GetSystemTimePreciseAsFileTime(ft: *windows.FILETIME) callconv(.winapi) void;
extern "kernel32" fn GetTimeZoneInformation(tzi: *TIME_ZONE_INFORMATION) callconv(.winapi) windows.DWORD;
extern "kernel32" fn GetCurrentProcess() callconv(.winapi) windows.HANDLE;
extern "kernel32" fn GetCurrentThread() callconv(.winapi) windows.HANDLE;
extern "kernel32" fn GetProcessTimes(
    process: windows.HANDLE,
    creation: *windows.FILETIME,
    exit: *windows.FILETIME,
    kernel: *windows.FILETIME,
    user: *windows.FILETIME,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn GetThreadTimes(
    thread: windows.HANDLE,
    creation: *windows.FILETIME,
    exit: *windows.FILETIME,
    kernel: *windows.FILETIME,
    user: *windows.FILETIME,
) callconv(.winapi) windows.BOOL;
extern "ntdll" fn NtDelayExecution(
    alertable: windows.BOOLEAN,
    interval: *const windows.LARGE_INTEGER,
) callconv(.winapi) windows.NTSTATUS;

const TIME_ZONE_ID_INVALID: windows.DWORD = 0xFFFF_FFFF;
const TIME_ZONE_ID_DAYLIGHT: windows.DWORD = 2;

const TIME_ZONE_INFORMATION = extern struct {
    Bias: windows.LONG,
    StandardName: [32]u16,
    StandardDate: SYSTEMTIME,
    StandardBias: windows.LONG,
    DaylightName: [32]u16,
    DaylightDate: SYSTEMTIME,
    DaylightBias: windows.LONG,
};

const SYSTEMTIME = extern struct {
    wYear: windows.WORD,
    wMonth: windows.WORD,
    wDayOfWeek: windows.WORD,
    wDay: windows.WORD,
    wHour: windows.WORD,
    wMinute: windows.WORD,
    wSecond: windows.WORD,
    wMilliseconds: windows.WORD,
};

const TIMER_ABSTIME: c_int = 1;

fn setErrno(e: std.posix.E) c_int {
    std.c._errno().* = @intFromEnum(e);
    return -1;
}

fn filetimeToU64(ft: windows.FILETIME) u64 {
    return (@as(u64, ft.dwHighDateTime) << 32) | @as(u64, ft.dwLowDateTime);
}

fn filetimeToTimespec(ft: windows.FILETIME, tp: *timespec) void {
    const u: u64 = filetimeToU64(ft) - FILETIME_1970;
    tp.sec = @intCast(u / 10_000_000);
    tp.nsec = @intCast((u % 10_000_000) * 100);
}

fn cpuTimespec(ft_kernel: windows.FILETIME, ft_user: windows.FILETIME, tp: *timespec) void {
    // GetProcessTimes / GetThreadTimes return intervals in 100ns units,
    // NOT FILETIMEs with the 1601 epoch baked in. Sum kernel+user.
    const total: u64 = filetimeToU64(ft_kernel) +% filetimeToU64(ft_user);
    tp.sec = @intCast(total / 10_000_000);
    tp.nsec = @intCast((total % 10_000_000) * 100);
}

// clockid_t values (from lib/libc/include/any-windows-any/pthread_time.h):
const CLOCK_REALTIME: clockid_t = @enumFromInt(0);
const CLOCK_MONOTONIC: clockid_t = @enumFromInt(1);
const CLOCK_PROCESS_CPUTIME_ID: clockid_t = @enumFromInt(2);
const CLOCK_THREAD_CPUTIME_ID: clockid_t = @enumFromInt(3);
const CLOCK_REALTIME_COARSE: clockid_t = @enumFromInt(4);

// ---------- clock_gettime ----------

fn clock_gettimeImpl(id: clockid_t, tp: *timespec) callconv(.c) c_int {
    switch (id) {
        CLOCK_REALTIME, CLOCK_REALTIME_COARSE => {
            var ft: windows.FILETIME = undefined;
            GetSystemTimePreciseAsFileTime(&ft);
            filetimeToTimespec(ft, tp);
            return 0;
        },
        CLOCK_MONOTONIC => {
            var freq: windows.LARGE_INTEGER = undefined;
            var count: windows.LARGE_INTEGER = undefined;
            if (QueryPerformanceFrequency(&freq) == .FALSE) return setErrno(.INVAL);
            if (QueryPerformanceCounter(&count) == .FALSE) return setErrno(.INVAL);
            const f: u64 = @intCast(freq);
            const c: u64 = @intCast(count);
            tp.sec = @intCast(c / f);
            tp.nsec = @intCast(((c % f) * 1_000_000_000) / f);
            return 0;
        },
        CLOCK_PROCESS_CPUTIME_ID => {
            var cr: windows.FILETIME = undefined;
            var ex: windows.FILETIME = undefined;
            var k: windows.FILETIME = undefined;
            var u: windows.FILETIME = undefined;
            if (GetProcessTimes(GetCurrentProcess(), &cr, &ex, &k, &u) == .FALSE)
                return setErrno(.INVAL);
            cpuTimespec(k, u, tp);
            return 0;
        },
        CLOCK_THREAD_CPUTIME_ID => {
            var cr: windows.FILETIME = undefined;
            var ex: windows.FILETIME = undefined;
            var k: windows.FILETIME = undefined;
            var u: windows.FILETIME = undefined;
            if (GetThreadTimes(GetCurrentThread(), &cr, &ex, &k, &u) == .FALSE)
                return setErrno(.INVAL);
            cpuTimespec(k, u, tp);
            return 0;
        },
        else => return setErrno(.INVAL),
    }
}

fn clock_getresImpl(id: clockid_t, tp: *timespec) callconv(.c) c_int {
    switch (id) {
        CLOCK_REALTIME, CLOCK_REALTIME_COARSE, CLOCK_PROCESS_CPUTIME_ID, CLOCK_THREAD_CPUTIME_ID => {
            tp.sec = 0;
            tp.nsec = 100;
            return 0;
        },
        CLOCK_MONOTONIC => {
            var freq: windows.LARGE_INTEGER = undefined;
            if (QueryPerformanceFrequency(&freq) == .FALSE) return setErrno(.INVAL);
            const f: i64 = freq;
            tp.sec = 0;
            const ns = @divTrunc(1_000_000_000 + @divTrunc(f, 2), f);
            tp.nsec = if (ns < 1) 1 else @intCast(ns);
            return 0;
        },
        else => return setErrno(.INVAL),
    }
}

// ---------- nanosleep / clock_nanosleep ----------

fn nanosleepImpl(req: *const timespec, rem: ?*timespec) callconv(.c) c_int {
    if (req.nsec < 0 or req.nsec >= 1_000_000_000 or req.sec < 0)
        return setErrno(.INVAL);

    const sec_as_ns: i128 = @as(i128, req.sec) * 1_000_000_000;
    const total: i128 = sec_as_ns + @as(i128, req.nsec);
    // Round up to next 100ns tick so we sleep at least the requested ns.
    const ticks_i128: i128 = @divTrunc(total + 99, 100);
    const saturated: i128 = if (ticks_i128 > std.math.maxInt(i64))
        std.math.maxInt(i64)
    else
        ticks_i128;
    const ticks_100ns: i64 = @intCast(saturated);

    // NtDelayExecution takes a relative interval as negative 100ns units.
    const interval: windows.LARGE_INTEGER = -ticks_100ns;
    const status = NtDelayExecution(.FALSE, &interval);
    if (rem) |r| {
        r.sec = 0;
        r.nsec = 0;
    }
    if (status != .SUCCESS) {
        return setErrno(.INTR);
    }
    return 0;
}

fn clock_nanosleepImpl(
    id: clockid_t,
    flags: c_int,
    req: *const timespec,
    rem: ?*timespec,
) callconv(.c) c_int {
    switch (id) {
        CLOCK_REALTIME, CLOCK_REALTIME_COARSE, CLOCK_MONOTONIC => {},
        else => return @intFromEnum(std.posix.E.INVAL),
    }

    if (req.nsec < 0 or req.nsec >= 1_000_000_000 or req.sec < 0)
        return @intFromEnum(std.posix.E.INVAL);

    var rel = req.*;
    if ((flags & TIMER_ABSTIME) != 0) {
        var now: timespec = undefined;
        if (clock_gettimeImpl(id, &now) != 0)
            return @intFromEnum(std.posix.E.INVAL);
        var sec = req.sec - now.sec;
        var nsec: c_long = @intCast(@as(i64, req.nsec) - @as(i64, now.nsec));
        if (nsec < 0) {
            nsec += 1_000_000_000;
            sec -= 1;
        }
        if (sec < 0) return 0; // deadline already passed
        rel.sec = sec;
        rel.nsec = nsec;
    }

    if (nanosleepImpl(&rel, rem) == 0) return 0;
    // clock_nanosleep returns the error code directly (not via errno).
    return std.c._errno().*;
}

// ---------- gettimeofday ----------

fn gettimeofdayImpl(tv: ?*timeval, tz: ?*anyopaque) callconv(.c) c_int {
    if (tv) |p| {
        var ft: windows.FILETIME = undefined;
        GetSystemTimePreciseAsFileTime(&ft);
        const u: u64 = filetimeToU64(ft) - FILETIME_1970;
        p.sec = @intCast(u / 10_000_000);
        p.usec = @intCast((u % 10_000_000) / 10);
    }
    if (tz) |p| {
        const z: *timezone = @ptrCast(@alignCast(p));
        var tzi: TIME_ZONE_INFORMATION = undefined;
        const id = GetTimeZoneInformation(&tzi);
        if (id != TIME_ZONE_ID_INVALID) {
            z.minuteswest = tzi.Bias;
            z.dsttime = if (id == TIME_ZONE_ID_DAYLIGHT) 1 else 0;
        } else {
            z.minuteswest = 0;
            z.dsttime = 0;
        }
    }
    return 0;
}

// mingw_gettimeofday is a strongly-typed alias.
fn mingw_gettimeofdayImpl(tv: ?*timeval, tz: ?*timezone) callconv(.c) c_int {
    return gettimeofdayImpl(tv, @ptrCast(tz));
}

// getntptimeofday is mingw-internal (timespec + timezone).
fn getntptimeofdayImpl(tp: ?*timespec, tz: ?*timezone) callconv(.c) c_int {
    if (tp) |p| {
        var ft: windows.FILETIME = undefined;
        GetSystemTimePreciseAsFileTime(&ft);
        filetimeToTimespec(ft, p);
    }
    if (tz) |z| {
        var tzi: TIME_ZONE_INFORMATION = undefined;
        const id = GetTimeZoneInformation(&tzi);
        if (id != TIME_ZONE_ID_INVALID) {
            z.minuteswest = tzi.Bias;
            z.dsttime = if (id == TIME_ZONE_ID_DAYLIGHT) 1 else 0;
        } else {
            z.minuteswest = 0;
            z.dsttime = 0;
        }
    }
    return 0;
}

// ---------- 32-bit-time_t stubs ----------
//
// Obsolete on modern mingw targets; stub with ENOSYS / PERM rather than
// implementing the 32-bit overflow logic. Keeps the symbols resolvable
// for any lingering caller.

fn clock_gettime32Stub(_: clockid_t, _: *anyopaque) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn clock_getres32Stub(_: clockid_t, _: *anyopaque) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn clock_nanosleep32Stub(_: clockid_t, _: c_int, _: *const anyopaque, _: ?*anyopaque) callconv(.c) c_int {
    return @intFromEnum(std.posix.E.NOSYS);
}
fn nanosleep32Stub(_: *const anyopaque, _: ?*anyopaque) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn clock_settime32Stub(_: clockid_t, _: *const anyopaque) callconv(.c) c_int {
    return setErrno(.PERM);
}
fn clock_settimeStub(_: clockid_t, _: *const timespec) callconv(.c) c_int {
    return setErrno(.PERM);
}

comptime {
    // Plain POSIX names — what std.c and well-written C code call.
    symbol(&clock_gettimeImpl, "clock_gettime");
    symbol(&clock_getresImpl, "clock_getres");
    symbol(&clock_nanosleepImpl, "clock_nanosleep");
    symbol(&nanosleepImpl, "nanosleep");
    symbol(&gettimeofdayImpl, "gettimeofday");
    symbol(&clock_settimeStub, "clock_settime");

    // mingw-w64 winpthreads names referenced by pthread_time.h inlines.
    symbol(&clock_gettimeImpl, "clock_gettime64");
    symbol(&clock_getresImpl, "clock_getres64");
    symbol(&clock_nanosleepImpl, "clock_nanosleep64");
    symbol(&nanosleepImpl, "nanosleep64");
    symbol(&clock_settimeStub, "clock_settime64");

    // 32-bit time_t variants: ENOSYS.
    symbol(&clock_gettime32Stub, "clock_gettime32");
    symbol(&clock_getres32Stub, "clock_getres32");
    symbol(&clock_nanosleep32Stub, "clock_nanosleep32");
    symbol(&nanosleep32Stub, "nanosleep32");
    symbol(&clock_settime32Stub, "clock_settime32");

    // mingw-w64 misc/gettimeofday.c extras.
    symbol(&mingw_gettimeofdayImpl, "mingw_gettimeofday");
    symbol(&getntptimeofdayImpl, "getntptimeofday");
}
