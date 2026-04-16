const builtin = @import("builtin");

const std = @import("std");
const assert = std.debug.assert;
const div_t = std.c.div_t;
const ldiv_t = std.c.ldiv_t;
const lldiv_t = std.c.lldiv_t;

const symbol = @import("../c.zig").symbol;

comptime {
    _ = @import("stdlib/rand.zig");
    _ = @import("stdlib/random.zig");
    _ = @import("stdlib/drand48.zig");

    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        // Functions specific to musl and wasi-libc.
        symbol(&abs, "abs");
        symbol(&labs, "labs");
        symbol(&llabs, "llabs");

        symbol(&div, "div");
        symbol(&ldiv, "ldiv");
        symbol(&lldiv, "lldiv");

        symbol(&atoi, "atoi");
        symbol(&atol, "atol");
        symbol(&atoll, "atoll");

        symbol(&strtol, "strtol");
        symbol(&strtoll, "strtoll");
        symbol(&strtoul, "strtoul");
        symbol(&strtoull, "strtoull");
        symbol(&strtoimax, "strtoimax");
        symbol(&strtoumax, "strtoumax");


        symbol(&qsort_r, "qsort_r");
        symbol(&qsort, "qsort");

        symbol(&bsearch, "bsearch");

        if (builtin.link_libc) {
            // These functions depend on musl internals (__floatscan, __intscan,
            // sprintf) that are still compiled as C, so we can only export them
            // when linking libc.

            // strtod family
            symbol(&strtof_c, "strtof");
            symbol(&strtod_c, "strtod");
            symbol(&strtold_c, "strtold");

            // atof
            symbol(&atof_c, "atof");

            // wcstod family
            symbol(&wcstof_c, "wcstof");
            symbol(&wcstod_c, "wcstod");
            symbol(&wcstold_c, "wcstold");

            // wcstol family
            symbol(&wcstol_c, "wcstol");
            symbol(&wcstoll_c, "wcstoll");
            symbol(&wcstoul_c, "wcstoul");
            symbol(&wcstoull_c, "wcstoull");
            symbol(&wcstoimax_c, "wcstoimax");
            symbol(&wcstoumax_c, "wcstoumax");

            // ecvt/fcvt/gcvt
            symbol(&ecvt_c, "ecvt");
            symbol(&fcvt_c, "fcvt");
            symbol(&gcvt_c, "gcvt");
        }
    }
}

fn abs(a: c_int) callconv(.c) c_int {
    return @intCast(@abs(a));
}

fn labs(a: c_long) callconv(.c) c_long {
    return @intCast(@abs(a));
}

fn llabs(a: c_longlong) callconv(.c) c_longlong {
    return @intCast(@abs(a));
}

fn div(a: c_int, b: c_int) callconv(.c) div_t {
    return .{
        .quot = @divTrunc(a, b),
        .rem = @rem(a, b),
    };
}

fn ldiv(a: c_long, b: c_long) callconv(.c) ldiv_t {
    return .{
        .quot = @divTrunc(a, b),
        .rem = @rem(a, b),
    };
}

fn lldiv(a: c_longlong, b: c_longlong) callconv(.c) lldiv_t {
    return .{
        .quot = @divTrunc(a, b),
        .rem = @rem(a, b),
    };
}

fn atoi(str: [*:0]const c_char) callconv(.c) c_int {
    return asciiToInteger(c_int, @ptrCast(str));
}

fn atol(str: [*:0]const c_char) callconv(.c) c_long {
    return asciiToInteger(c_long, @ptrCast(str));
}

fn atoll(str: [*:0]const c_char) callconv(.c) c_longlong {
    return asciiToInteger(c_longlong, @ptrCast(str));
}

fn asciiToInteger(comptime T: type, buf: [*:0]const u8) T {
    comptime assert(std.math.isPowerOfTwo(@bitSizeOf(T)));

    var current = buf;
    while (std.ascii.isWhitespace(current[0])) : (current += 1) {}

    // The behaviour *is* undefined if the result cannot be represented
    // but as they are usually called with untrusted input we can just handle overflow gracefully.
    if (current[0] == '-') return parseDigitsWithSignGenericCharacter(T, u8, current + 1, null, 10, .neg) catch std.math.minInt(T);
    if (current[0] == '+') current += 1;
    return parseDigitsWithSignGenericCharacter(T, u8, current, null, 10, .pos) catch std.math.maxInt(T);
}

fn strtol(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) c_long {
    return stringToInteger(c_long, @ptrCast(str), if (str_end) |end| @ptrCast(end) else null, base);
}

fn strtoll(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) c_longlong {
    return stringToInteger(c_longlong, @ptrCast(str), if (str_end) |end| @ptrCast(end) else null, base);
}

fn strtoul(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) c_ulong {
    return stringToInteger(c_ulong, @ptrCast(str), if (str_end) |end| @ptrCast(end) else null, base);
}

fn strtoull(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) c_ulonglong {
    return stringToInteger(c_ulonglong, @ptrCast(str), if (str_end) |end| @ptrCast(end) else null, base);
}

// XXX: These belong in inttypes.zig but we'd have to make stringToInteger pub or move it somewhere else.
fn strtoimax(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) std.c.intmax_t {
    return stringToInteger(std.c.intmax_t, @ptrCast(str), if (str_end) |end| @ptrCast(end) else null, base);
}

fn strtoumax(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) std.c.uintmax_t {
    return stringToInteger(std.c.uintmax_t, @ptrCast(str), if (str_end) |end| @ptrCast(end) else null, base);
}

fn stringToInteger(comptime T: type, noalias buf: [*:0]const u8, noalias maybe_end: ?*[*:0]const u8, base: c_int) T {
    comptime assert(std.math.isPowerOfTwo(@bitSizeOf(T)));

    if (base < 0 or base == 1 or base > 36) {
        if (maybe_end) |end| {
            end.* = buf;
        }

        std.c._errno().* = @intFromEnum(std.c.E.INVAL);
        return 0;
    }

    var current = buf;
    while (std.ascii.isWhitespace(current[0])) : (current += 1) {}

    const negative: bool = switch (current[0]) {
        '-' => blk: {
            current += 1;
            break :blk true;
        },
        '+' => blk: {
            current += 1;
            break :blk false;
        },
        else => false,
    };

    // The prefix is allowed iff base == 0 or base == base of the prefix
    const real_base: u6 = if (current[0] == '0') blk: {
        current += 1;

        if ((base == 0 or base == 16) and std.ascii.toLower(current[0]) == 'x' and std.ascii.isHex(current[1])) {
            current += 1;
            break :blk 16;
        }

        if ((base == 0 or base == 8) and std.ascii.isDigit(current[0])) {
            break :blk 8;
        }

        break :blk switch (base) {
            0 => 10,
            else => @intCast(base),
        };
    } else switch (base) {
        0 => 10,
        else => @intCast(base),
    };

    if (@typeInfo(T).int.signedness == .unsigned) {
        const result = parseDigitsWithSignGenericCharacter(T, u8, current, maybe_end, real_base, .pos) catch {
            std.c._errno().* = @intFromEnum(std.c.E.RANGE);
            return std.math.maxInt(T);
        };

        return if (negative) -%result else result;
    }

    if (negative) return parseDigitsWithSignGenericCharacter(T, u8, current, maybe_end, real_base, .neg) catch blk: {
        std.c._errno().* = @intFromEnum(std.c.E.RANGE);
        break :blk std.math.minInt(T);
    };

    return parseDigitsWithSignGenericCharacter(T, u8, current, maybe_end, real_base, .pos) catch blk: {
        std.c._errno().* = @intFromEnum(std.c.E.RANGE);
        break :blk std.math.maxInt(T);
    };
}

fn parseDigitsWithSignGenericCharacter(
    comptime T: type,
    comptime Char: type,
    noalias buf: [*:0]const Char,
    noalias maybe_end: ?*[*:0]const Char,
    base: u6,
    comptime sign: enum { pos, neg },
) error{Overflow}!T {
    assert(base >= 2 and base <= 36);

    var current = buf;
    defer if (maybe_end) |end| {
        end.* = current;
    };

    const add = switch (sign) {
        .pos => std.math.add,
        .neg => std.math.sub,
    };

    var value: T = 0;
    while (true) {
        const c: u8 = std.math.cast(u8, current[0]) orelse break;
        if (!std.ascii.isAlphanumeric(c)) break;

        const digit: u6 = @intCast(std.fmt.charToDigit(c, base) catch break);
        defer current += 1;

        value = try std.math.mul(T, value, base);
        value = try add(T, value, digit);
    }

    return value;
}

// NOTE: Despite its name, `qsort` doesn't have to use quicksort or make any complexity or stability guarantee.
fn qsort_r(base: *anyopaque, n: usize, size: usize, compare: *const fn (a: *const anyopaque, b: *const anyopaque, arg: ?*anyopaque) callconv(.c) c_int, arg: ?*anyopaque) callconv(.c) void {
    const Context = struct {
        base: [*]u8,
        size: usize,
        compare: *const fn (a: *const anyopaque, b: *const anyopaque, arg: ?*anyopaque) callconv(.c) c_int,
        arg: ?*anyopaque,

        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            return ctx.compare(&ctx.base[a * ctx.size], &ctx.base[b * ctx.size], ctx.arg) < 0;
        }

        pub fn swap(ctx: @This(), a: usize, b: usize) void {
            const a_bytes: []u8 = ctx.base[a * ctx.size ..][0..ctx.size];
            const b_bytes: []u8 = ctx.base[b * ctx.size ..][0..ctx.size];

            for (a_bytes, b_bytes) |*ab, *bb| {
                const tmp = ab.*;
                ab.* = bb.*;
                bb.* = tmp;
            }
        }
    };

    std.mem.sortUnstableContext(0, n, Context{
        .base = @ptrCast(base),
        .size = size,
        .compare = compare,
        .arg = arg,
    });
}

fn qsort(base: *anyopaque, n: usize, size: usize, compare: *const fn (a: *const anyopaque, b: *const anyopaque) callconv(.c) c_int) callconv(.c) void {
    return qsort_r(base, n, size, (struct {
        fn wrap(a: *const anyopaque, b: *const anyopaque, arg: ?*anyopaque) callconv(.c) c_int {
            const cmp: *const fn (a: *const anyopaque, b: *const anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(arg.?));
            return cmp(a, b);
        }
    }).wrap, @constCast(compare));
}

// NOTE: Despite its name, `bsearch` doesn't need to be implemented using binary search or make any complexity guarantee.
fn bsearch(key: *const anyopaque, base: *const anyopaque, n: usize, size: usize, compare: *const fn (a: *const anyopaque, b: *const anyopaque) callconv(.c) c_int) callconv(.c) ?*anyopaque {
    const base_bytes: [*]const u8 = @ptrCast(base);
    var low: usize = 0;
    var high: usize = n;

    while (low < high) {
        // Avoid overflowing in the midpoint calculation
        const mid = low + (high - low) / 2;
        const elem = &base_bytes[mid * size];

        switch (std.math.order(compare(key, elem), 0)) {
            .eq => return @constCast(elem),
            .gt => low = mid + 1,
            .lt => high = mid,
        }
    }
    return null;
}

// ---------------------------------------------------------------------------
// Musl FILE struct — matches struct _IO_FILE from musl's stdio_impl.h.
// Needed to call musl's internal __floatscan/__shlim which expect FILE*.
// ---------------------------------------------------------------------------

const wchar_t = std.c.wchar_t;
const off_t = c_longlong; // musl off_t is always long long

const MuFILE = extern struct {
    flags: c_uint,
    rpos: ?[*]u8,
    rend: ?[*]u8,
    close_fn: ?*anyopaque,
    wend: ?[*]u8,
    wpos: ?[*]u8,
    mustbezero_1: ?[*]u8,
    wbase: ?[*]u8,
    read_fn: ?*anyopaque,
    write_fn: ?*anyopaque,
    seek_fn: ?*anyopaque,
    buf: ?[*]u8,
    buf_size: usize,
    prev: ?*anyopaque,
    next: ?*anyopaque,
    fd: c_int,
    pipe_pid: c_int,
    lockcount: c_long,
    mode: c_int,
    lock: c_int,
    lbf: c_int,
    cookie: ?*anyopaque,
    off: off_t,
    getln_buf: ?[*]u8,
    mustbezero_2: ?*anyopaque,
    shend: ?[*]u8,
    shlim_val: off_t,
    shcnt_val: off_t,
    prev_locked: ?*anyopaque,
    next_locked: ?*anyopaque,
    locale: ?*anyopaque,

    // Inline equivalent of musl's sh_fromstring macro:
    //   ((f)->buf = (f)->rpos = (void *)(s), (f)->rend = (void*)-1)
    fn shFromString(f: *MuFILE, s: [*:0]const u8) void {
        const ptr: [*]u8 = @ptrCast(@constCast(s));
        f.buf = ptr;
        f.rpos = ptr;
        f.rend = @ptrFromInt(std.math.maxInt(usize));
    }

    // Inline equivalent of musl's shcnt macro:
    //   ((f)->shcnt + ((f)->rpos - (f)->buf))
    fn shcnt(f: *MuFILE) off_t {
        const rpos_addr = @intFromPtr(f.rpos.?);
        const buf_addr = @intFromPtr(f.buf.?);
        return f.shcnt_val + @as(off_t, @intCast(rpos_addr - buf_addr));
    }
};

extern "c" fn __floatscan(f: *MuFILE, prec: c_int, pok: c_int) c_longdouble;
extern "c" fn __shlim(f: *MuFILE, lim: off_t) void;

// ---------------------------------------------------------------------------
// strtod / strtof / strtold — float parsing via musl's __floatscan
// ---------------------------------------------------------------------------

fn strtox(s: [*:0]const u8, p: ?*[*:0]const u8, prec: c_int) c_longdouble {
    var f: MuFILE = std.mem.zeroes(MuFILE);
    f.shFromString(s);
    __shlim(&f, 0);
    const y = __floatscan(&f, prec, 1);
    const cnt = f.shcnt();
    if (p) |pp| {
        pp.* = if (cnt != 0) s + @as(usize, @intCast(cnt)) else s;
    }
    return y;
}

fn strtof_c(noalias s: [*:0]const u8, noalias p: ?*[*:0]const u8) callconv(.c) f32 {
    return @floatCast(strtox(s, p, 0));
}

fn strtod_c(noalias s: [*:0]const u8, noalias p: ?*[*:0]const u8) callconv(.c) f64 {
    return @floatCast(strtox(s, p, 1));
}

fn strtold_c(noalias s: [*:0]const u8, noalias p: ?*[*:0]const u8) callconv(.c) c_longdouble {
    return strtox(s, p, 2);
}

// ---------------------------------------------------------------------------
// atof — trivial wrapper around strtod
// ---------------------------------------------------------------------------

fn atof_c(s: [*:0]const u8) callconv(.c) f64 {
    return strtod_c(s, null);
}

// ---------------------------------------------------------------------------
// wcstod / wcstof / wcstold — wide-char float parsing.
// Converts wchar_t to narrow ASCII then calls strtox (matching musl behavior
// where non-ASCII chars are replaced with '@').
// ---------------------------------------------------------------------------

extern "c" fn iswspace(wchar_t) c_int;

fn wcsToNarrow(comptime N: usize, s: [*:0]const wchar_t, out_t: *[*:0]const wchar_t) [N:0]u8 {
    var t = s;
    while (iswspace(t[0]) != 0) : (t += 1) {}
    out_t.* = t;

    var buf: [N:0]u8 = undefined;
    var i: usize = 0;
    var src = t;
    while (src[0] != 0 and i < N) : ({
        src += 1;
        i += 1;
    }) {
        buf[i] = if (std.math.cast(u8, src[0])) |b| b else '@';
    }
    buf[i] = 0;
    return buf;
}

fn wcstox_impl(s: [*:0]const wchar_t, p: ?*[*:0]const wchar_t, prec: c_int) c_longdouble {
    var t: [*:0]const wchar_t = undefined;
    var buf = wcsToNarrow(256, s, &t);

    var end_ptr: [*:0]const u8 = undefined;
    const y = strtox(&buf, &end_ptr, prec);

    if (p) |pp| {
        const cnt = @intFromPtr(end_ptr) - @intFromPtr(&buf);
        pp.* = if (cnt != 0) t + cnt else s;
    }
    return y;
}

fn wcstof_c(noalias s: [*:0]const wchar_t, noalias p: ?*[*:0]const wchar_t) callconv(.c) f32 {
    return @floatCast(wcstox_impl(s, p, 0));
}

fn wcstod_c(noalias s: [*:0]const wchar_t, noalias p: ?*[*:0]const wchar_t) callconv(.c) f64 {
    return @floatCast(wcstox_impl(s, p, 1));
}

fn wcstold_c(noalias s: [*:0]const wchar_t, noalias p: ?*[*:0]const wchar_t) callconv(.c) c_longdouble {
    return wcstox_impl(s, p, 2);
}

// ---------------------------------------------------------------------------
// wcstol / wcstoll / wcstoul / wcstoull / wcstoimax / wcstoumax
// Converts wchar_t to narrow ASCII then calls the narrow strtol family.
// ---------------------------------------------------------------------------

fn wcsToInt(comptime T: type, s: [*:0]const wchar_t, p: ?*[*:0]const wchar_t, base: c_int) T {
    var t: [*:0]const wchar_t = undefined;
    var buf = wcsToNarrow(64, s, &t);

    var end_ptr: [*:0]const c_char = undefined;
    const result = stringToInteger(T, @ptrCast(&buf), @ptrCast(&end_ptr), base);

    if (p) |pp| {
        const cnt = @intFromPtr(end_ptr) - @intFromPtr(&buf);
        pp.* = if (cnt != 0) t + cnt else s;
    }
    return result;
}

fn wcstol_c(noalias s: [*:0]const wchar_t, noalias p: ?*[*:0]const wchar_t, base: c_int) callconv(.c) c_long {
    return wcsToInt(c_long, s, p, base);
}

fn wcstoll_c(noalias s: [*:0]const wchar_t, noalias p: ?*[*:0]const wchar_t, base: c_int) callconv(.c) c_longlong {
    return wcsToInt(c_longlong, s, p, base);
}

fn wcstoul_c(noalias s: [*:0]const wchar_t, noalias p: ?*[*:0]const wchar_t, base: c_int) callconv(.c) c_ulong {
    return wcsToInt(c_ulong, s, p, base);
}

fn wcstoull_c(noalias s: [*:0]const wchar_t, noalias p: ?*[*:0]const wchar_t, base: c_int) callconv(.c) c_ulonglong {
    return wcsToInt(c_ulonglong, s, p, base);
}

fn wcstoimax_c(noalias s: [*:0]const wchar_t, noalias p: ?*[*:0]const wchar_t, base: c_int) callconv(.c) std.c.intmax_t {
    return wcsToInt(std.c.intmax_t, s, p, base);
}

fn wcstoumax_c(noalias s: [*:0]const wchar_t, noalias p: ?*[*:0]const wchar_t, base: c_int) callconv(.c) std.c.uintmax_t {
    return wcsToInt(std.c.uintmax_t, s, p, base);
}

// ---------------------------------------------------------------------------
// ecvt / fcvt / gcvt — float-to-string conversion using sprintf
// ---------------------------------------------------------------------------

extern "c" fn sprintf(buf: [*]u8, fmt: [*:0]const u8, ...) c_int;
extern "c" fn strspn(s: [*:0]const u8, accept: [*:0]const u8) usize;
extern "c" fn strcspn(s: [*:0]const u8, reject: [*:0]const u8) usize;

var ecvt_buf: [16:0]u8 = std.mem.zeroes([16:0]u8);

fn ecvt_c(x: f64, n_arg: c_int, dp: *c_int, sign_out: *c_int) callconv(.c) [*:0]u8 {
    var tmp: [32]u8 = undefined;
    const n: c_int = if (@as(c_uint, @bitCast(n_arg -% 1)) > 15) 15 else n_arg;
    _ = sprintf(&tmp, "%.*e", n - 1, x);

    var i: usize = 0;
    if (tmp[0] == '-') {
        sign_out.* = 1;
        i = 1;
    } else {
        sign_out.* = 0;
    }

    var j: usize = 0;
    while (tmp[i] != 'e') {
        if (tmp[i] != '.') {
            ecvt_buf[j] = tmp[i];
            j += 1;
        }
        i += 1;
    }
    ecvt_buf[j] = 0;

    dp.* = parseExpInt(tmp[i + 1 ..].ptr) + 1;

    return @ptrCast(&ecvt_buf);
}

fn parseExpInt(s: [*]const u8) c_int {
    var neg = false;
    var i: usize = 0;
    if (s[i] == '+') {
        i += 1;
    } else if (s[i] == '-') {
        neg = true;
        i += 1;
    }
    var val: c_int = 0;
    while (s[i] >= '0' and s[i] <= '9') : (i += 1) {
        val = val * 10 + @as(c_int, @intCast(s[i] - '0'));
    }
    return if (neg) -val else val;
}

const zeros_str: *const [15:0]u8 = "000000000000000";

fn fcvt_c(x: f64, n_arg: c_int, dp: *c_int, sign_out: *c_int) callconv(.c) [*:0]u8 {
    var tmp: [1500]u8 = undefined;
    var n = n_arg;
    if (n > 1400) n = 1400;
    _ = sprintf(&tmp, "%.*f", n, x);

    var i: usize = 0;
    if (tmp[0] == '-') i = 1;

    var lz: c_int = undefined;
    if (tmp[i] == '0') {
        lz = @intCast(strspn(@ptrCast(tmp[i + 2 ..].ptr), "0"));
    } else {
        lz = -@as(c_int, @intCast(strcspn(@ptrCast(tmp[i..].ptr), ".")));
    }

    if (n <= lz) {
        sign_out.* = @intCast(i);
        dp.* = 1;
        if (n > 14) n = 14;
        return @constCast(@ptrCast(zeros_str[14 - @as(usize, @intCast(n)) ..].ptr));
    }

    return ecvt_c(x, n - lz, dp, sign_out);
}

fn gcvt_c(x: f64, n: c_int, b: [*]u8) callconv(.c) [*]u8 {
    _ = sprintf(b, "%.*g", n, x);
    return b;
}

test abs {
    const val: c_int = -10;
    try std.testing.expectEqual(10, abs(val));
}

test labs {
    const val: c_long = -10;
    try std.testing.expectEqual(10, labs(val));
}

test llabs {
    const val: c_longlong = -10;
    try std.testing.expectEqual(10, llabs(val));
}

test div {
    const expected: div_t = .{ .quot = 5, .rem = 5 };
    try std.testing.expectEqual(expected, div(55, 10));
}

test ldiv {
    const expected: ldiv_t = .{ .quot = -6, .rem = 2 };
    try std.testing.expectEqual(expected, ldiv(38, -6));
}

test lldiv {
    const expected: lldiv_t = .{ .quot = 1, .rem = 2 };
    try std.testing.expectEqual(expected, lldiv(5, 3));
}

test atoi {
    try std.testing.expectEqual(0, atoi(@ptrCast("stop42true")));
    try std.testing.expectEqual(42, atoi(@ptrCast("42true")));
    try std.testing.expectEqual(-1, atoi(@ptrCast("-01")));
    try std.testing.expectEqual(1, atoi(@ptrCast("+001")));
    try std.testing.expectEqual(100, atoi(@ptrCast("            100")));
    try std.testing.expectEqual(500, atoi(@ptrCast("000000000000500")));
    try std.testing.expectEqual(1111, atoi(@ptrCast("0000000000001111_0000")));
    try std.testing.expectEqual(0, atoi(@ptrCast("0xAA")));
    try std.testing.expectEqual(700, atoi(@ptrCast("700B")));
    try std.testing.expectEqual(32453, atoi(@ptrCast("+32453more")));
    try std.testing.expectEqual(std.math.maxInt(c_int), atoi(@ptrCast(std.fmt.comptimePrint("{d}", .{std.math.maxInt(c_int)}))));
    try std.testing.expectEqual(std.math.minInt(c_int), atoi(@ptrCast(std.fmt.comptimePrint("{d}", .{std.math.minInt(c_int)}))));
}

test atol {
    try std.testing.expectEqual(0, atol(@ptrCast("stop42true")));
    try std.testing.expectEqual(42, atol(@ptrCast("42true")));
    try std.testing.expectEqual(-1, atol(@ptrCast("-01")));
    try std.testing.expectEqual(1, atol(@ptrCast("+001")));
    try std.testing.expectEqual(100, atol(@ptrCast("            100")));
    try std.testing.expectEqual(500, atol(@ptrCast("000000000000500")));
    try std.testing.expectEqual(1111, atol(@ptrCast("0000000000001111_0000")));
    try std.testing.expectEqual(0, atol(@ptrCast("0xAA")));
    try std.testing.expectEqual(700, atol(@ptrCast("700B")));
    try std.testing.expectEqual(32453, atol(@ptrCast("+32453more")));
    try std.testing.expectEqual(std.math.maxInt(c_long), atol(@ptrCast(std.fmt.comptimePrint("{d}", .{std.math.maxInt(c_long)}))));
    try std.testing.expectEqual(std.math.minInt(c_long), atol(@ptrCast(std.fmt.comptimePrint("{d}", .{std.math.minInt(c_long)}))));
}

test atoll {
    try std.testing.expectEqual(0, atoll(@ptrCast("stop42true")));
    try std.testing.expectEqual(42, atoll(@ptrCast("42true")));
    try std.testing.expectEqual(-1, atoll(@ptrCast("-01")));
    try std.testing.expectEqual(1, atoll(@ptrCast("+001")));
    try std.testing.expectEqual(100, atoll(@ptrCast("            100")));
    try std.testing.expectEqual(500, atoll(@ptrCast("000000000000500")));
    try std.testing.expectEqual(1111, atoll(@ptrCast("0000000000001111_0000")));
    try std.testing.expectEqual(0, atoll(@ptrCast("0xAA")));
    try std.testing.expectEqual(700, atoll(@ptrCast("700B")));
    try std.testing.expectEqual(32453, atoll(@ptrCast("   +32453more")));
    try std.testing.expectEqual(std.math.maxInt(c_longlong), atoll(@ptrCast(std.fmt.comptimePrint("{d}", .{std.math.maxInt(c_longlong)}))));
    try std.testing.expectEqual(std.math.minInt(c_longlong), atoll(@ptrCast(std.fmt.comptimePrint("{d}", .{std.math.minInt(c_longlong)}))));
}

// FIXME: We cannot test strtol, strtoll, strtoul, etc.. here as it must modify errno and libc is not linked in tests

test bsearch {
    const Comparison = struct {
        pub fn compare(a: *const anyopaque, b: *const anyopaque) callconv(.c) c_int {
            const a_u16: *const u16 = @ptrCast(@alignCast(a));
            const b_u16: *const u16 = @ptrCast(@alignCast(b));

            return switch (std.math.order(a_u16.*, b_u16.*)) {
                .gt => 1,
                .eq => 0,
                .lt => -1,
            };
        }
    };

    const items: []const u16 = &.{ 0, 5, 7, 9, 10, 200, 512, 768 };

    try std.testing.expectEqual(@as(?*anyopaque, null), bsearch(&@as(u16, 2000), items.ptr, items.len, @sizeOf(u16), Comparison.compare));

    for (items) |*value| {
        try std.testing.expectEqual(@as(*const anyopaque, value), bsearch(value, items.ptr, items.len, @sizeOf(u16), Comparison.compare));
    }
}
