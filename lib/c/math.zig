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
        symbol(&acoshf, "acoshf");
        symbol(&acosl, "acosl");
        symbol(&asin, "asin");
        symbol(&asinhf, "asinhf");
        symbol(&asinl, "asinl");
        symbol(&atan, "atan");
        symbol(&atanf, "atanf");
        symbol(&atanhf, "atanhf");
        symbol(&atanl, "atanl");
        symbol(&cbrt, "cbrt");
        symbol(&cbrtf, "cbrtf");
        symbol(&cosh, "cosh");
        symbol(&cosl, "cosl");
        symbol(&exp10, "exp10");
        symbol(&exp10f, "exp10f");
        symbol(&exp2l, "exp2l");
        symbol(&expl, "expl");
        symbol(&expm1f, "expm1f");
        symbol(&fdimf, "fdimf");
        symbol(&fdiml, "fdiml");
        symbol(&fmaf, "fmaf");
        symbol(&fmal, "fmal");
        symbol(&frexpf, "frexpf");
        symbol(&frexpl, "frexpl");
        symbol(&hypot, "hypot");
        symbol(&ilogbf, "ilogbf");
        symbol(&ilogbl, "ilogbl");
        symbol(&ldexpf, "ldexpf");
        symbol(&ldexpl, "ldexpl");
        symbol(&llrintf, "llrintf");
        symbol(&llrintl, "llrintl");
        symbol(&llroundf, "llroundf");
        symbol(&llroundl, "llroundl");
        symbol(&log10l, "log10l");
        symbol(&log1pf, "log1pf");
        symbol(&log2l, "log2l");
        symbol(&logbf, "logbf");
        symbol(&logbl, "logbl");
        symbol(&logl, "logl");
        symbol(&lrintf, "lrintf");
        symbol(&lrintl, "lrintl");
        symbol(&lroundf, "lroundf");
        symbol(&lroundl, "lroundl");
        symbol(&modf, "modf");
        symbol(&nearbyintf, "nearbyintf");
        symbol(&nearbyintl, "nearbyintl");

        symbol(&pow, "pow");
        symbol(&pow10, "pow10");
        symbol(&pow10f, "pow10f");
        symbol(&scalblnf, "scalblnf");
        symbol(&scalblnl, "scalblnl");
        symbol(&scalbnf, "scalbnf");
        symbol(&scalbnl, "scalbnl");
        symbol(&sincosl, "sincosl");
        symbol(&sinhf, "sinhf");
        symbol(&sinl, "sinl");
        symbol(&tanh, "tanh");
        symbol(&tanl, "tanl");
    }

    if (builtin.target.isMuslLibC()) {
        symbol(&copysign, "copysign");
        symbol(&copysignf, "copysignf");
        symbol(&finitef, "finitef");
        symbol(&rint, "rint");
        symbol(&scalbf, "scalbf");
        symbol(&significandf, "significandf");
    }

    symbol(&copysignl, "copysignl");
}

fn acos(x: f64) callconv(.c) f64 {
    return math.acos(x);
}

fn acosf(x: f32) callconv(.c) f32 {
    return math.acos(x);
}

fn acoshf(x: f32) callconv(.c) f32 {
    return math.acosh(x);
}

fn asin(x: f64) callconv(.c) f64 {
    return math.asin(x);
}

fn atan(x: f64) callconv(.c) f64 {
    return math.atan(x);
}

fn atanf(x: f32) callconv(.c) f32 {
    return math.atan(x);
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

fn tanh(x: f64) callconv(.c) f64 {
    return math.tanh(x);
}

fn tanhf(x: f32) callconv(.c) f32 {
    return math.tanh(x);
}

fn acosl(x: c_longdouble) callconv(.c) c_longdouble {
    return math.acos(x);
}

fn asinhf(x: f32) callconv(.c) f32 {
    return math.asinh(x);
}

fn asinl(x: c_longdouble) callconv(.c) c_longdouble {
    return math.asin(x);
}

fn atanhf(x: f32) callconv(.c) f32 {
    return math.atanh(x);
}

fn cosl(x: c_longdouble) callconv(.c) c_longdouble {
    return math.cos(x);
}

fn exp2l(x: c_longdouble) callconv(.c) c_longdouble {
    return math.exp2(x);
}

fn expl(x: c_longdouble) callconv(.c) c_longdouble {
    return math.exp(x);
}

fn expm1f(x: f32) callconv(.c) f32 {
    return math.expm1(x);
}

fn fdimGeneric(comptime T: type, x: T, y: T) T {
    if (math.isNan(x)) return math.nan(T);
    if (math.isNan(y)) return math.nan(T);
    return if (x > y) x - y else 0;
}

fn fdimf(x: f32, y: f32) callconv(.c) f32 {
    return fdimGeneric(f32, x, y);
}

fn fdiml(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    return fdimGeneric(c_longdouble, x, y);
}

fn finitef(x: f32) callconv(.c) c_int {
    return if (math.isFinite(x)) 1 else 0;
}

fn fmaf(x: f32, y: f32, z: f32) callconv(.c) f32 {
    return @mulAdd(f32, x, y, z);
}

fn fmal(x: c_longdouble, y: c_longdouble, z: c_longdouble) callconv(.c) c_longdouble {
    return @mulAdd(c_longdouble, x, y, z);
}

fn frexpGeneric(comptime T: type, x: T, exp: *c_int) T {
    const result = math.frexp(x);
    exp.* = result.exponent;
    return result.significand;
}

fn frexpf(x: f32, exp: *c_int) callconv(.c) f32 {
    return frexpGeneric(f32, x, exp);
}

fn frexpl(x: c_longdouble, exp: *c_int) callconv(.c) c_longdouble {
    return frexpGeneric(c_longdouble, x, exp);
}

fn ilogbf(x: f32) callconv(.c) c_int {
    return math.ilogb(x);
}

fn ilogbl(x: c_longdouble) callconv(.c) c_int {
    return math.ilogb(x);
}

fn ldexpf(x: f32, n: c_int) callconv(.c) f32 {
    return math.ldexp(x, n);
}

fn ldexpl(x: c_longdouble, n: c_int) callconv(.c) c_longdouble {
    return math.ldexp(x, n);
}

fn llrintf(x: f32) callconv(.c) c_longlong {
    return @intFromFloat(rintGeneric(f32, x));
}

fn llrintl(x: c_longdouble) callconv(.c) c_longlong {
    return @intFromFloat(rintGeneric(c_longdouble, x));
}

fn llroundf(x: f32) callconv(.c) c_longlong {
    return @intFromFloat(math.round(x));
}

fn llroundl(x: c_longdouble) callconv(.c) c_longlong {
    return @intFromFloat(math.round(x));
}

fn log10l(x: c_longdouble) callconv(.c) c_longdouble {
    return math.log10(x);
}

fn log1pf(x: f32) callconv(.c) f32 {
    return math.log1p(x);
}

fn log2l(x: c_longdouble) callconv(.c) c_longdouble {
    return math.log2(x);
}

fn logbGeneric(comptime T: type, x: T) T {
    if (!math.isFinite(x)) return x * x;
    if (x == 0) return -math.inf(T);
    return @floatFromInt(math.ilogb(x));
}

fn logbf(x: f32) callconv(.c) f32 {
    return logbGeneric(f32, x);
}

fn logbl(x: c_longdouble) callconv(.c) c_longdouble {
    return logbGeneric(c_longdouble, x);
}

fn logl(x: c_longdouble) callconv(.c) c_longdouble {
    return @log(x);
}

fn lrintf(x: f32) callconv(.c) c_long {
    return @intFromFloat(rintGeneric(f32, x));
}

fn lrintl(x: c_longdouble) callconv(.c) c_long {
    return @intFromFloat(rintGeneric(c_longdouble, x));
}

fn lroundf(x: f32) callconv(.c) c_long {
    return @intFromFloat(math.round(x));
}

fn lroundl(x: c_longdouble) callconv(.c) c_long {
    return @intFromFloat(math.round(x));
}

fn nearbyintf(x: f32) callconv(.c) f32 {
    return rintGeneric(f32, x);
}

fn nearbyintl(x: c_longdouble) callconv(.c) c_longdouble {
    return rintGeneric(c_longdouble, x);
}



/// Generic rint for any IEEE 754 float type.
fn rintGeneric(comptime T: type, x: T) T {
    const toint: T = 1.0 / math.floatEps(T);
    const FloatBits = std.meta.Int(.unsigned, @typeInfo(T).float.bits);
    const mant_bits = math.floatMantissaBits(T);
    const frac_bits = math.floatFractionalBits(T);
    const exp_bits = math.floatExponentBits(T);
    const bias: comptime_int = (@as(comptime_int, 1) << (exp_bits - 1)) - 1;
    const exp_mask: u32 = (@as(u32, 1) << @intCast(exp_bits)) - 1;

    const a: FloatBits = @bitCast(x);
    const e: u32 = @truncate(a >> mant_bits);
    const e_masked = e & exp_mask;
    const s: u1 = @truncate(a >> (@typeInfo(T).float.bits - 1));

    if (e_masked >= bias + frac_bits) return x;

    const y: T = if (s == 1) x - toint + toint else x + toint - toint;
    if (y == 0) return if (s == 1) -@as(T, 0.0) else @as(T, 0.0);
    return y;
}

fn scalbf(x: f32, fn_arg: f32) callconv(.c) f32 {
    if (math.isNan(x) or math.isNan(fn_arg)) return x * fn_arg;
    if (!math.isFinite(fn_arg)) {
        if (fn_arg > 0.0) return x * fn_arg;
        return x / (-fn_arg);
    }
    if (rintGeneric(f32, fn_arg) != fn_arg) return (fn_arg - fn_arg) / (fn_arg - fn_arg);
    if (fn_arg > 65000.0) return math.scalbn(x, 65000);
    if (-fn_arg > 65000.0) return math.scalbn(x, -65000);
    return math.scalbn(x, @intFromFloat(fn_arg));
}

fn scalblnGeneric(comptime T: type, x: T, n: c_long) T {
    const clamped: i32 = if (n > std.math.maxInt(i32))
        std.math.maxInt(i32)
    else if (n < std.math.minInt(i32))
        std.math.minInt(i32)
    else
        @intCast(n);
    return math.scalbn(x, clamped);
}

fn scalblnf(x: f32, n: c_long) callconv(.c) f32 {
    return scalblnGeneric(f32, x, n);
}

fn scalblnl(x: c_longdouble, n: c_long) callconv(.c) c_longdouble {
    return scalblnGeneric(c_longdouble, x, n);
}

fn scalbnf(x: f32, n: c_int) callconv(.c) f32 {
    return math.scalbn(x, n);
}

fn scalbnl(x: c_longdouble, n: c_int) callconv(.c) c_longdouble {
    return math.scalbn(x, n);
}

fn significandf(x: f32) callconv(.c) f32 {
    const e = math.ilogb(x);
    return math.scalbn(x, if (e == std.math.minInt(i32)) 0 else -e);
}

fn sincosl(x: c_longdouble, sin_ptr: *c_longdouble, cos_ptr: *c_longdouble) callconv(.c) void {
    sin_ptr.* = math.sin(x);
    cos_ptr.* = math.cos(x);
}

fn sinhf(x: f32) callconv(.c) f32 {
    return math.sinh(x);
}

fn sinl(x: c_longdouble) callconv(.c) c_longdouble {
    return math.sin(x);
}

fn tanl(x: c_longdouble) callconv(.c) c_longdouble {
    return math.tan(x);
}
