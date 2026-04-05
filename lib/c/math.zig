const builtin = @import("builtin");

const std = @import("std");
const math = std.math;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;
const expectApproxEqRel = std.testing.expectApproxEqRel;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMinGW()) {
        symbol(&isnan, "isnan");
        symbol(&isnan, "__isnan");
        symbol(&isnanf, "isnanf");
        symbol(&isnanf, "__isnanf");
        symbol(&isnanl, "isnanl");
        symbol(&isnanl, "__isnanl");

        symbol(&math.floatTrueMin(f64), "__DENORM");
        symbol(&math.inf(f64), "__INF");
        symbol(&math.nan(f64), "__QNAN");
        symbol(&math.snan(f64), "__SNAN");

        symbol(&math.floatTrueMin(f32), "__DENORMF");
        symbol(&math.inf(f32), "__INFF");
        symbol(&math.nan(f32), "__QNANF");
        symbol(&math.snan(f32), "__SNANF");

        symbol(&math.floatTrueMin(c_longdouble), "__DENORML");
        symbol(&math.inf(c_longdouble), "__INFL");
        symbol(&math.nan(c_longdouble), "__QNANL");
        symbol(&math.snan(c_longdouble), "__SNANL");
    }

    if (builtin.target.isMinGW() or builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&coshf, "coshf");
        symbol(&hypotf, "hypotf");
        symbol(&hypotl, "hypotl");
        symbol(&modff, "modff");
        symbol(&modfl, "modfl");
        symbol(&nan, "nan");
        symbol(&nanf, "nanf");
        symbol(&nanl, "nanl");
        symbol(&tanhf, "tanhf");
    }

    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&acos, "acos");
        symbol(&acosf, "acosf");
        symbol(&acosh_, "acosh");
        symbol(&acoshf, "acoshf");
        symbol(&acoshl_, "acoshl");
        symbol(&asin, "asin");
        symbol(&asinh_, "asinh");
        symbol(&asinhf_, "asinhf");
        symbol(&asinhl_, "asinhl");
        symbol(&atan, "atan");
        symbol(&atanf, "atanf");
        symbol(&atanh_, "atanh");
        symbol(&atanhf_, "atanhf");
        symbol(&atanhl_, "atanhl");
        symbol(&atanl, "atanl");
        symbol(&cbrt, "cbrt");
        symbol(&cbrtf, "cbrtf");
        symbol(&cosh, "cosh");
        symbol(&coshl_, "coshl");
        symbol(&exp10, "exp10");
        symbol(&exp10f, "exp10f");
        symbol(&hypot, "hypot");
        symbol(&modf, "modf");
        symbol(&pow, "pow");
        symbol(&pow10, "pow10");
        symbol(&pow10f, "pow10f");
        symbol(&rintl, "rintl");
        symbol(&sinh_, "sinh");
        symbol(&sinhl_, "sinhl");
        symbol(&tanh, "tanh");
        symbol(&tanhl_, "tanhl");
    }

    if (builtin.target.isMuslLibC()) {
        symbol(&copysign, "copysign");
        symbol(&copysignf, "copysignf");
        symbol(&rint, "rint");
        symbol(&rintf, "rintf");
    }

    symbol(&copysignl, "copysignl");
}

fn acos(x: f64) callconv(.c) f64 {
    return math.acos(x);
}

fn acosf(x: f32) callconv(.c) f32 {
    return math.acos(x);
}

fn acosh_(x: f64) callconv(.c) f64 {
    return math.acosh(x);
}

fn acoshf(x: f32) callconv(.c) f32 {
    return math.acosh(x);
}

fn acoshl_(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => math.acosh(@as(f64, @bitCast(x))),
        else => @floatCast(math.acosh(@as(f64, @floatCast(x)))),
    };
}

fn asin(x: f64) callconv(.c) f64 {
    return math.asin(x);
}

fn asinhf_(x: f32) callconv(.c) f32 {
    return math.asinh(x);
}

/// Port of musl asinh.c with @mulAdd improvement for x*x+1 computation.
/// Reduces ULP error below 1.5 in [0.125,0.5] range (musl C has up to 1.6).
fn asinh_(x: f64) callconv(.c) f64 {
    @setFloatMode(.strict);
    const u: u64 = @bitCast(x);
    const e = (u >> 52) & 0x7FF;
    const s = u >> 63;
    var rx: f64 = @bitCast(u & (std.math.maxInt(u64) >> 1)); // |x|

    if (e >= 0x3FF + 26) {
        // |x| >= 0x1p26 or inf or nan
        rx = @log(rx) + 0.693147180559945309417232121458176568;
    } else if (e >= 0x3FF + 1) {
        // |x| >= 2
        rx = @log(2 * rx + 1 / (@sqrt(@mulAdd(f64, rx, rx, 1)) + rx));
    } else if (e >= 0x3FF - 26) {
        // |x| >= 0x1p-26: use @mulAdd for x*x+1 to get < 1.5 ULP
        rx = math.log1p(rx + rx * rx / (@sqrt(@mulAdd(f64, rx, rx, 1)) + 1));
    } else {
        // |x| < 0x1p-26, raise inexact if x != 0
        std.mem.doNotOptimizeAway(rx + 0x1p120);
    }
    return if (s != 0) -rx else rx;
}

fn asinhl_(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => @bitCast(asinh_(@bitCast(x))),
        else => @floatCast(asinh_(@floatCast(x))),
    };
}

fn atan(x: f64) callconv(.c) f64 {
    return math.atan(x);
}

fn atanf(x: f32) callconv(.c) f32 {
    return math.atan(x);
}

fn atanh_(x: f64) callconv(.c) f64 {
    return math.atanh(x);
}

fn atanhf_(x: f32) callconv(.c) f32 {
    return math.atanh(x);
}

fn atanhl_(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => math.atanh(@as(f64, @bitCast(x))),
        else => @floatCast(math.atanh(@as(f64, @floatCast(x)))),
    };
}

fn atanl(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(@TypeOf(x)).float.bits) {
        16 => math.atan(@as(f16, @floatCast(x))),
        32 => math.atan(@as(f32, @floatCast(x))),
        64 => math.atan(@as(f64, @floatCast(x))),
        80 => math.atan(@as(f80, @floatCast(x))),
        128 => math.atan(@as(f128, @floatCast(x))),
        else => unreachable,
    };
}

fn cbrt(x: f64) callconv(.c) f64 {
    return math.cbrt(x);
}

fn cbrtf(x: f32) callconv(.c) f32 {
    return math.cbrt(x);
}

fn copysign(x: f64, y: f64) callconv(.c) f64 {
    return math.copysign(x, y);
}

fn copysignf(x: f32, y: f32) callconv(.c) f32 {
    return math.copysign(x, y);
}

fn copysignl(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    return math.copysign(x, y);
}

fn cosh(x: f64) callconv(.c) f64 {
    return math.cosh(x);
}

fn coshf(x: f32) callconv(.c) f32 {
    return math.cosh(x);
}

fn coshl_(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => math.cosh(@as(f64, @bitCast(x))),
        else => @floatCast(math.cosh(@as(f64, @floatCast(x)))),
    };
}

/// Port of musl sinh.c with direct exp(x/2) overflow handling
/// instead of __expo2, avoiding the intermediate overflow issue.
fn sinh_(x: f64) callconv(.c) f64 {
    @setFloatMode(.strict);
    const u: u64 = @bitCast(x);
    const w: u32 = @intCast(u >> 32);
    const absx: f64 = @bitCast(u & (std.math.maxInt(u64) >> 1));
    var h: f64 = 0.5;
    if (u >> 63 != 0) h = -h;

    // |x| < log(DBL_MAX)
    if (w < 0x40862e42) {
        const t = math.expm1(absx);
        if (w < 0x3ff00000) {
            if (w < 0x3ff00000 - (26 << 20))
                // avoid spurious underflow
                return x;
            return h * (2 * t - t * t / (t + 1));
        }
        return h * (t + t / (t + 1));
    }

    // |x| > log(DBL_MAX) or nan: use exp(x/2) trick to avoid overflow
    const t = @exp(0.5 * absx);
    return h * t * t;
}

fn sinhl_(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => @bitCast(sinh_(@bitCast(x))),
        else => @floatCast(sinh_(@as(f64, @floatCast(x)))),
    };
}

fn exp10(x: f64) callconv(.c) f64 {
    return math.pow(f64, 10.0, x);
}

fn exp10f(x: f32) callconv(.c) f32 {
    return math.pow(f32, 10.0, x);
}


fn hypot(x: f64, y: f64) callconv(.c) f64 {
    return math.hypot(x, y);
}

fn hypotf(x: f32, y: f32) callconv(.c) f32 {
    return math.hypot(x, y);
}

fn hypotl(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    return math.hypot(x, y);
}

fn isnan(x: f64) callconv(.c) c_int {
    return if (math.isNan(x)) 1 else 0;
}

fn isnanf(x: f32) callconv(.c) c_int {
    return if (math.isNan(x)) 1 else 0;
}

fn isnanl(x: c_longdouble) callconv(.c) c_int {
    return if (math.isNan(x)) 1 else 0;
}

fn modfGeneric(comptime T: type, x: T, iptr: *T) T {
    if (math.isNegativeInf(x)) {
        iptr.* = -math.inf(T);
        return -0.0;
    }

    if (math.isPositiveInf(x)) {
        iptr.* = math.inf(T);
        return 0.0;
    }

    if (math.isNan(x)) {
        iptr.* = math.nan(T);
        return math.nan(T);
    }

    const r = math.modf(x);
    iptr.* = r.ipart;

    // If the result is a negative zero, we must be explicit about
    // returning a negative zero.
    return if (math.isNegativeZero(x) or (x < 0.0 and x == r.ipart)) -0.0 else r.fpart;
}

fn modf(x: f64, iptr: *f64) callconv(.c) f64 {
    return modfGeneric(f64, x, iptr);
}

fn modff(x: f32, iptr: *f32) callconv(.c) f32 {
    return modfGeneric(f32, x, iptr);
}

fn modfl(x: c_longdouble, iptr: *c_longdouble) callconv(.c) c_longdouble {
    return modfGeneric(c_longdouble, x, iptr);
}

fn testModf(comptime T: type) !void {
    // Choose the appropriate `modf` impl to test based on type
    const f = switch (T) {
        f32 => modff,
        f64 => modf,
        c_longdouble => modfl,
        else => @compileError("modf not implemented for " ++ @typeName(T)),
    };

    var int: T = undefined;
    const iptr = &int;
    const eps_val: comptime_float = @max(1e-6, math.floatEps(T));

    const normal_frac = f(@as(T, 1234.567), iptr);
    // Account for precision error
    const expected = 1234.567 - @as(T, 1234);
    try expectApproxEqAbs(expected, normal_frac, eps_val);
    try expectApproxEqRel(@as(T, 1234.0), iptr.*, eps_val);

    // When `x` is a NaN, NaN is returned and `*iptr` is set to NaN
    const nan_frac = f(math.nan(T), iptr);
    try expect(math.isNan(nan_frac));
    try expect(math.isNan(iptr.*));

    // When `x` is positive infinity, +0 is returned and `*iptr` is set to
    // positive infinity
    const pos_zero_frac = f(math.inf(T), iptr);
    try expect(math.isPositiveZero(pos_zero_frac));
    try expect(math.isPositiveInf(iptr.*));

    // When `x` is negative infinity, -0 is returned and `*iptr` is set to
    // negative infinity
    const neg_zero_frac = f(-math.inf(T), iptr);
    try expect(math.isNegativeZero(neg_zero_frac));
    try expect(math.isNegativeInf(iptr.*));

    // Return -0 when `x` is a negative integer
    const nz_frac = f(@as(T, -1000.0), iptr);
    try expect(math.isNegativeZero(nz_frac));
    try expectEqual(@as(T, -1000.0), iptr.*);

    // Return +0 when `x` is a positive integer
    const pz_frac = f(@as(T, 1000.0), iptr);
    try expect(math.isPositiveZero(pz_frac));
    try expectEqual(@as(T, 1000.0), iptr.*);
}

test "modf" {
    try testModf(f32);
    try testModf(f64);
    try testModf(c_longdouble);
}

fn nan(_: [*:0]const c_char) callconv(.c) f64 {
    return math.nan(f64);
}

fn nanf(_: [*:0]const c_char) callconv(.c) f32 {
    return math.nan(f32);
}

fn nanl(_: [*:0]const c_char) callconv(.c) c_longdouble {
    return math.nan(c_longdouble);
}

fn pow(x: f64, y: f64) callconv(.c) f64 {
    return math.pow(f64, x, y);
}

fn pow10(x: f64) callconv(.c) f64 {
    return exp10(x);
}

fn pow10f(x: f32) callconv(.c) f32 {
    return exp10f(x);
}

fn rint(x: f64) callconv(.c) f64 {
    const toint: f64 = 1.0 / @as(f64, math.floatEps(f64));
    const a: u64 = @bitCast(x);
    const e = a >> 52 & 0x7ff;
    const s = a >> 63;
    var y: f64 = undefined;

    if (e >= 0x3ff + 52) {
        return x;
    }
    if (s == 1) {
        y = x - toint + toint;
    } else {
        y = x + toint - toint;
    }
    if (y == 0) {
        return if (s == 1) -0.0 else 0;
    }
    return y;
}

test "rint" {
    // Positive numbers round correctly
    try expectEqual(@as(f64, 42.0), rint(42.2));
    try expectEqual(@as(f64, 42.0), rint(41.8));

    // Negative numbers round correctly
    try expectEqual(@as(f64, -6.0), rint(-5.9));
    try expectEqual(@as(f64, -6.0), rint(-6.1));

    // No rounding needed test
    try expectEqual(@as(f64, 5.0), rint(5.0));
    try expectEqual(@as(f64, -10.0), rint(-10.0));
    try expectEqual(@as(f64, 0.0), rint(0.0));

    // Very large numbers return unchanged
    const large: f64 = 9007199254740992.0; // 2^53
    try expectEqual(large, rint(large));
    try expectEqual(-large, rint(-large));

    // Small positive numbers round to zero
    const pos_result = rint(0.3);
    try expectEqual(@as(f64, 0.0), pos_result);
    try expect(@as(u64, @bitCast(pos_result)) == 0);

    // Small negative numbers round to negative zero
    const neg_result = rint(-0.3);
    try expectEqual(@as(f64, 0.0), neg_result);
    const bits: u64 = @bitCast(neg_result);
    try expect((bits >> 63) == 1);

    // Exact half rounds to nearest even (banker's rounding)
    try expectEqual(@as(f64, 2.0), rint(2.5));
    try expectEqual(@as(f64, 4.0), rint(3.5));
}

fn rintf(x: f32) callconv(.c) f32 {
    const toint: f32 = 1.0 / @as(f32, math.floatEps(f32));
    const a: u32 = @bitCast(x);
    const e = a >> 23 & 0xff;
    const s = a >> 31;
    var y: f32 = undefined;

    if (e >= 0x7f + 23) {
        return x;
    }
    if (s == 1) {
        y = x - toint + toint;
    } else {
        y = x + toint - toint;
    }
    if (y == 0) {
        return if (s == 1) @as(f32, -0.0) else 0;
    }
    return y;
}

test "rintf" {
    try expectEqual(@as(f32, 42.0), rintf(42.2));
    try expectEqual(@as(f32, 42.0), rintf(41.8));
    try expectEqual(@as(f32, -6.0), rintf(-5.9));
    try expectEqual(@as(f32, -6.0), rintf(-6.1));
    try expectEqual(@as(f32, 5.0), rintf(5.0));
    try expectEqual(@as(f32, 0.0), rintf(0.0));
    try expectEqual(@as(f32, 2.0), rintf(2.5));
    try expectEqual(@as(f32, 4.0), rintf(3.5));
}

fn rintl(x: c_longdouble) callconv(.c) c_longdouble {
    const toint: c_longdouble = 1.0 / @as(c_longdouble, math.floatEps(c_longdouble));

    // NaN or already-integer (includes Inf since Inf >= toint)
    if (x != x or @abs(x) >= toint) return x;

    // Use copysign to detect negative zero
    const is_neg = math.copysign(@as(c_longdouble, 1.0), x) < 0;
    const y = if (is_neg) x - toint + toint else x + toint - toint;
    if (y == 0) return if (is_neg) @as(c_longdouble, -0.0) else @as(c_longdouble, 0);
    return y;
}

fn tanh(x: f64) callconv(.c) f64 {
    return math.tanh(x);
}

fn tanhf(x: f32) callconv(.c) f32 {
    return math.tanh(x);
}

fn tanhl_(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => math.tanh(@as(f64, @bitCast(x))),
        else => @floatCast(math.tanh(@as(f64, @floatCast(x)))),
    };
}

test "hyperbolic" {
    try expectApproxEqRel(@as(f64, 0.0), acosh_(1.0), 1e-15);
    try expectApproxEqRel(@as(f64, 1.31695789692481670862), acosh_(2.0), 1e-15);
    try expectApproxEqAbs(@as(f32, 0.0), asinhf_(0.0), 1e-6);
    try expectApproxEqRel(@as(f32, 0.88137358), asinhf_(1.0), 1e-6);
    try expectApproxEqAbs(@as(f64, 0.0), asinh_(0.0), 1e-15);
    try expectApproxEqRel(@as(f64, 0.88137358701954302519), asinh_(1.0), 1e-15);
    try expectApproxEqAbs(@as(f64, 0.0), atanh_(0.0), 1e-15);
    try expectApproxEqRel(@as(f64, 0.54930614433405484570), atanh_(0.5), 1e-15);
    try expectApproxEqAbs(@as(f64, 0.0), sinh_(0.0), 1e-15);
    try expectApproxEqRel(@as(f64, 1.17520119364380145688), sinh_(1.0), 1e-15);
}
