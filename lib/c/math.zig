const builtin = @import("builtin");

const std = @import("std");
const math = std.math;
const maxInt = std.math.maxInt;
const minInt = std.math.minInt;
const mem = std.mem;
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
        symbol(&frexpf, "frexpf");
        symbol(&frexpl, "frexpl");
        symbol(&hypotf, "hypotf");
        symbol(&hypotl, "hypotl");
        symbol(&modfl, "modfl");
    }

    if ((builtin.target.isMinGW() and @sizeOf(f64) != @sizeOf(c_longdouble)) or builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&atanl, "atanl");
        symbol(&copysignl, "copysignl");
        symbol(&nanl, "nanl");
    }

    if ((builtin.target.isMinGW() and builtin.cpu.arch == .x86) or builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&acosf, "acosf");
        symbol(&atanf, "atanf");
        symbol(&coshf, "coshf");
        symbol(&modff, "modff");
        symbol(&tanhf, "tanhf");
    }

    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&acos, "acos");
        symbol(&acoshf, "acoshf");
        symbol(&acosl, "acosl");
        symbol(&asin, "asin");
        symbol(&asinhf, "asinhf");
        symbol(&asinl, "asinl");
        symbol(&asinf, "asinf");
        symbol(&atan, "atan");
        symbol(&atan2, "atan2");
        symbol(&atan2f, "atan2f");
        symbol(&atanf, "atanf");
        symbol(&atanhf, "atanhf");
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
        symbol(&cosl, "cosl");
        symbol(&coshl_, "coshl");
        symbol(&erf_, "erf");
        symbol(&erfc_, "erfc");
        symbol(&erff_, "erff");
        symbol(&erfcf_, "erfcf");
        symbol(&exp10, "exp10");
        symbol(&exp10f, "exp10f");
        symbol(&fdim, "fdim");
        symbol(&finite, "finite");
        symbol(&finitef, "finitef");
        symbol(&frexp, "frexp");
        symbol(&fdim_, "fdim");
        symbol(&fdimf_, "fdimf");
        symbol(&fdiml_, "fdiml");
        symbol(&finite_, "finite");
        symbol(&finitef_, "finitef");
        symbol(&fma, "fma");
        symbol(&hypot, "hypot");
        symbol(&lrint, "lrint");
        symbol(&lrintf, "lrintf");
        symbol(&frexp_, "frexp");
        symbol(&frexpf_, "frexpf");
        symbol(&frexpl_, "frexpl");
        symbol(&hypot, "hypot");
        symbol(&ilogb_, "ilogb");
        symbol(&ilogbf_, "ilogbf");
        symbol(&ilogbl_, "ilogbl");
        symbol(&ldexp_, "ldexp");
        symbol(&ldexpf_, "ldexpf");
        symbol(&ldexpl_, "ldexpl");
        symbol(&logb_, "logb");
        symbol(&logbf_, "logbf");
        symbol(&logbl_, "logbl");
        symbol(&llrint, "llrint");
        symbol(&lrint, "lrint");
        symbol(&modf, "modf");
        symbol(&nan, "nan");
        symbol(&nanf, "nanf");
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
        symbol(&log1pf, "log1pf");
        symbol(&lrintf, "lrintf");
        symbol(&lrintl, "lrintl");
        symbol(&lroundf, "lroundf");
        symbol(&lroundl, "lroundl");
        symbol(&modf, "modf");
        symbol(&nearbyintf, "nearbyintf");
        symbol(&nearbyintl, "nearbyintl");
        symbol(&nextafterf, "nextafterf");
        symbol(&nextafterl, "nextafterl");
        symbol(&nexttowardf, "nexttowardf");
        symbol(&nexttowardl, "nexttowardl");
        symbol(&pow, "pow");
        symbol(&pow10, "pow10");
        symbol(&pow10f, "pow10f");

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
        symbol(&powf, "powf");
        symbol(&scalbln_, "scalbln");
        symbol(&scalblnf_, "scalblnf");
        symbol(&scalblnl_, "scalblnl");
        symbol(&scalbn_, "scalbn");
        symbol(&scalbnf_, "scalbnf");
        symbol(&scalbnl_, "scalbnl");
        symbol(&significand_, "significand");
        symbol(&significandf_, "significandf");
        symbol(&rintl, "rintl");
        symbol(&remainder_, "remainder");
        symbol(&remainder_, "drem");
        symbol(&remainderf_, "remainderf");
        symbol(&remainderf_, "dremf");
        symbol(&remainderl_, "remainderl");
        symbol(&remquo_, "remquo");
        symbol(&remquof_, "remquof");
        symbol(&remquol_, "remquol");
        symbol(&tanh, "tanh");
        symbol(&tanl, "tanl");
        symbol(&rintl, "rintl");
        symbol(&sinh_, "sinh");
        symbol(&sinhl_, "sinhl");
        symbol(&tanh, "tanh");
        symbol(&tanhl_, "tanhl");

    }

    if (builtin.target.isMuslLibC()) {
        symbol(&copysign, "copysign");
        symbol(&copysignf, "copysignf");
        symbol(&finitef, "finitef");
        symbol(&nearbyint, "nearbyint");
        symbol(&rint, "rint");
        symbol(&rintf, "rintf");
        symbol(&scalbf, "scalbf");
        symbol(&significandf, "significandf");
        symbol(&__fpclassify, "__fpclassify");
        symbol(&__fpclassifyf, "__fpclassifyf");
        symbol(&__fpclassifyl, "__fpclassifyl");
        symbol(&rint, "rint");
        symbol(&__signbit, "__signbit");
        symbol(&__signbitf, "__signbitf");
        symbol(&__signbitl, "__signbitl");
        symbol(&nextafter, "nextafter");
        symbol(&nexttoward, "nexttoward");
        symbol(&rint, "rint");
        symbol(&scalb, "scalb");
    }
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

fn asinf(x: f32) callconv(.c) f32 {
    return math.asin(x);
fn asinhf_(x: f32) callconv(.c) f32 {
    return math.asinh(x);
}

/// Compute log(1+x) using the identity log(1+x) = 2*atanh(x/(x+2))
/// and the series atanh(s) = s + s³/3 + s⁵/5 + ...
/// Uses only basic arithmetic (+, -, *, /) — no @log.
fn log1p_wide(comptime T: type, x: T) T {
    if (x == 0) return x;
    const one: T = 1.0;
    const u = one + x;
    if (u == one) return x;

    // For large |x|, delegate to log_pure which does its own range reduction.
    // Thresholds chosen so that log_pure's callback into log1p_wide always
    // has |x| in [-0.293, 0.414], preventing infinite recursion.
    if (x > 0.5 or x < -0.3) return log_pure(T, u);

    // log(1+x) = 2*atanh(s) where s = x/(x+2)
    const s = x / (x + 2.0);
    const s2 = s * s;

    // Horner evaluation: atanh(s)/s = 1 + s²/3 + s⁴/5 + ...
    // For |x| <= 0.5: |s| <= 0.2, s² <= 0.04, 30 terms → error < 2^(-130).
    const num_terms = 30;
    var w: T = one / @as(T, @floatFromInt(2 * num_terms + 1));
    comptime var i: u32 = num_terms;
    inline while (i > 0) : (i -= 1) {
        w = w * s2 + one / @as(T, @floatFromInt(2 * i - 1));
    }
    return 2 * s * w;
}

/// Compute log(x) for x > 0 using frexp range reduction + log1p_wide.
/// Uses only basic arithmetic — no @log.
fn log_pure(comptime T: type, x: T) T {
    const fr = math.frexp(x);
    var sig = fr.significand;
    var exp_val = fr.exponent;
    // Adjust so significand ∈ [√2/2, √2) for tighter log1p_wide input range
    const sqrt2_over_2: T = 0.70710678118654752440084436210484903928;
    if (sig < sqrt2_over_2) {
        sig *= 2.0;
        exp_val -= 1;
    }
    const ln2: T = 0.6931471805599453094172321214581765680755001343602552541206800094;
    const k: T = @floatFromInt(exp_val);
    return k * ln2 + log1p_wide(T, sig - 1.0);
}

/// Taylor series for exp(x)-1: x + x²/2! + x³/3! + ...
fn taylor_expm1(comptime T: type, x: T) T {
    var term: T = x;
    var sum: T = x;
    var n: u32 = 2;
    while (n < 50) : (n += 1) {
        term *= x / @as(T, @floatFromInt(n));
        const old = sum;
        sum += term;
        if (sum == old) break;
    }
    return sum;
}

/// Compute exp(x)-1 using Taylor series with range reduction.
/// Uses only basic arithmetic — no @exp.
fn expm1_wide(comptime T: type, x: T) T {
    if (x == 0) return x;
    if (math.isNan(x)) return x;
    if (!math.isFinite(x)) {
        if (x > 0) return math.inf(T);
        return -1.0;
    }

    if (@abs(x) < 0.5) return taylor_expm1(T, x);

    // Range reduction: x = k*ln2 + r, |r| <= ln2/2
    const ln2: T = 0.6931471805599453094172321214581765680755001343602552541206800094;
    const inv_ln2: T = 1.4426950408889634073599246810018921374266459541529859341354494069;
    const k_f: T = @round(x * inv_ln2);
    const r = x - k_f * ln2;

    if (k_f > 0x1p30 or k_f < -0x1p30) {
        if (x > 0) return math.inf(T);
        return -1.0;
    }
    const k: i32 = @intFromFloat(k_f);

    const sum = taylor_expm1(T, r);
    if (k == 0) return sum;
    // expm1(x) = 2^k * (1 + expm1(r)) - 1 = 2^k * expm1(r) + (2^k - 1)
    const two_k = math.scalbn(@as(T, 1.0), k);
    return two_k * sum + (two_k - 1);
}

/// Compute exp(x) using expm1. Uses only basic arithmetic — no @exp.
fn exp_pure(comptime T: type, x: T) T {
    return 1.0 + expm1_wide(T, x);
}

/// Port of musl asinh.c using f128 intermediates for < 1.5 ULP accuracy.
/// The extra mantissa bits of f128 (112 vs 52 for f64) eliminate the log1p
/// precision issue that causes 1.5+ ULP errors in the f64 [0.125,0.5] range.
/// f128 is available on all targets via software emulation.
fn asinh_(x_: f64) callconv(.c) f64 {
    @setFloatMode(.strict);
    const u: u64 = @bitCast(x_);
    const e = (u >> 52) & 0x7FF;
    const s = u >> 63;
    const x: f128 = @floatCast(@as(f64, @bitCast(u & (std.math.maxInt(u64) >> 1))));

    if (e >= 0x3FF + 26) {
        // |x| >= 0x1p26 or inf or nan
        const r: f64 = @floatCast(log_pure(f128, x) + @as(f128, 0.693147180559945309417232121458176568));
        return if (s != 0) -r else r;
    } else if (e >= 0x3FF + 1) {
        // |x| >= 2
        const r: f64 = @floatCast(log_pure(f128, 2 * x + 1 / (@sqrt(x * x + 1) + x)));
        return if (s != 0) -r else r;
    } else if (e >= 0x3FF - 26) {
        // |x| >= 0x1p-26: compute in f128 to avoid log1p precision loss
        const y = x + x * x / (@sqrt(x * x + 1) + 1);
        const r: f64 = @floatCast(log1p_wide(f128, y));
        return if (s != 0) -r else r;
    } else {
        // |x| < 0x1p-26, raise inexact if x != 0
        std.mem.doNotOptimizeAway(x + @as(f128, 0x1p120));
        return x_;
    }
}

fn asinhl_(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => @bitCast(asinh_(@bitCast(x))),
        else => asinhl_impl(c_longdouble, x),
    };
}

/// Native long double asinh (port of musl asinhl.c).
fn asinhl_impl(comptime T: type, x_: T) T {
    @setFloatMode(.strict);
    const ax = @abs(x_);

    if (ax >= 0x1p32) {
        const r = log_pure(T, ax) + @as(T, 0.693147180559945309417232121458176568);
        return if (math.signbit(x_)) -r else r;
    } else if (ax >= 2.0) {
        const r = log_pure(T, 2 * ax + 1 / (@sqrt(ax * ax + 1) + ax));
        return if (math.signbit(x_)) -r else r;
    } else if (ax >= 0x1p-32) {
        const y = ax + ax * ax / (@sqrt(ax * ax + 1) + 1);
        const r = log1p_wide(T, y);
        return if (math.signbit(x_)) -r else r;
    } else {
        // |x| < 0x1p-32, raise inexact if x != 0
        std.mem.doNotOptimizeAway(ax + @as(T, 0x1p120));
        return x_;
    }
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
fn atan2(y: f64, x: f64) callconv(.c) f64 {
    return math.atan2(y, x);
}

fn atan2f(y: f32, x: f32) callconv(.c) f32 {
    return math.atan2(y, x);
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

/// musl FP classification constants (from math.h):
/// FP_NAN=0, FP_INFINITE=1, FP_ZERO=2, FP_SUBNORMAL=3, FP_NORMAL=4

fn __fpclassify(x: f64) callconv(.c) c_int {
    const u: u64 = @bitCast(x);
    const e: u32 = @truncate((u >> 52) & 0x7ff);
    if (e == 0) return if ((u << 1) != 0) 3 else 2;
    if (e == 0x7ff) return if ((u << 12) != 0) 0 else 1;
    return 4;
}

fn __fpclassifyf(x: f32) callconv(.c) c_int {
    const u: u32 = @bitCast(x);
    const e: u32 = (u >> 23) & 0xff;
    if (e == 0) return if ((u << 1) != 0) 3 else 2;
    if (e == 0xff) return if ((u << 9) != 0) 0 else 1;
    return 4;
}

fn __fpclassifyl(x: c_longdouble) callconv(.c) c_int {
    return switch (@typeInfo(c_longdouble).float.bits) {
        16 => __fpclassifyf(@floatCast(x)),
        32 => __fpclassifyf(@floatCast(x)),
        64 => __fpclassify(@floatCast(x)),
        80 => blk: {
            const ux: u80 = @bitCast(x);
            const e: u32 = @truncate((ux >> 64) & 0x7fff);
            if (e == 0) break :blk if ((ux << 1) != 0) @as(c_int, 3) else @as(c_int, 2);
            const msb: u1 = @truncate(ux >> 63);
            if (e == 0x7fff) {
                if (msb == 0) break :blk @as(c_int, 0);
                break :blk if ((ux & ((@as(u80, 1) << 63) - 1)) != 0) @as(c_int, 0) else @as(c_int, 1);
            }
            break :blk if (msb != 0) @as(c_int, 4) else @as(c_int, 0);
        },
        128 => blk: {
            const ux: u128 = @bitCast(x);
            const e: u32 = @truncate((ux >> 112) & 0x7fff);
            if (e == 0) break :blk if ((ux << 1) != 0) @as(c_int, 3) else @as(c_int, 2);
            if (e == 0x7fff) break :blk if ((ux << 17) != 0) @as(c_int, 0) else @as(c_int, 1);
            break :blk @as(c_int, 4);
        },
        else => unreachable,
    };
}

fn __signbit(x: f64) callconv(.c) c_int {
    const u: u64 = @bitCast(x);
    return @intCast(u >> 63);
}

fn __signbitf(x: f32) callconv(.c) c_int {
    const u: u32 = @bitCast(x);
    return @intCast(u >> 31);
}

fn __signbitl(x: c_longdouble) callconv(.c) c_int {
    return switch (@typeInfo(c_longdouble).float.bits) {
        16, 32 => __signbitf(@floatCast(x)),
        64 => __signbit(@floatCast(x)),
        80 => blk: {
            const ux: u80 = @bitCast(x);
            break :blk @intCast(ux >> 79);
        },
        128 => blk: {
            const ux: u128 = @bitCast(x);
            break :blk @intCast(ux >> 127);
        },
        else => unreachable,
    };
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

/// Port of musl sinh.c using f128 intermediates.
/// f128 exp handles values up to ~11356 without overflow, so the
/// overflow path (|x| > log(DBL_MAX) ≈ 710) works without the
/// exp(x/2)² trick that causes directed rounding errors.
/// f128 is available on all targets via software emulation.
fn sinh_(x_: f64) callconv(.c) f64 {
    @setFloatMode(.strict);
    const u: u64 = @bitCast(x_);
    const absu = u & (std.math.maxInt(u64) >> 1);
    const w: u32 = @intCast(absu >> 32);
    const absx: f128 = @abs(@as(f128, @floatCast(x_)));
    var h: f128 = 0.5;
    if (u >> 63 != 0) h = -h;

    // |x| < log(DBL_MAX)
    if (w < 0x40862e42) {
        const t: f128 = expm1_wide(f128, absx);
        if (w < 0x3ff00000) {
            if (w < 0x3ff00000 - (26 << 20))
                return x_;
            return @floatCast(h * (2 * t - t * t / (t + 1)));
        }
        return @floatCast(h * (t + t / (t + 1)));
    }

    // |x| > log(DBL_MAX) or nan: f128 exp won't overflow here
    const t: f128 = exp_pure(f128, absx);
    return @floatCast(h * t);
}

fn sinhl_(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => @bitCast(sinh_(@bitCast(x))),
        else => sinhl_impl(c_longdouble, x),
    };
}

/// Native long double sinh (port of musl sinhl.c).
fn sinhl_impl(comptime T: type, x_: T) T {
    @setFloatMode(.strict);
    const absx = @abs(x_);
    var h: T = 0.5;
    if (math.signbit(x_)) h = -h;

    // |x| < log(FLT_MAX) for extended/f128 (≈ 11356.52)
    if (absx < @as(T, 0x1.62e42fefa39efp+13)) {
        const t = expm1_wide(T, absx);
        if (absx < 1.0) {
            if (absx < 0x1p-32)
                return x_;
            return h * (2 * t - t * t / (t + 1));
        }
        return h * (t + t / (t + 1));
    }

    // |x| > log(FLT_MAX) or nan
    const t = exp_pure(T, @as(T, 0.5) * absx);
    return h * t * t;
}

fn exp10(x: f64) callconv(.c) f64 {
    return math.pow(f64, 10.0, x);
}

fn exp10f(x: f32) callconv(.c) f32 {
    return math.pow(f32, 10.0, x);
}

fn fdim(x: f64, y: f64) callconv(.c) f64 {
    if (math.isNan(x)) {
        return x;
    }
    if (math.isNan(y)) {
        return y;
    }
    if (x > y) {
        return x - y;
    }
    return 0;
}

fn finite(x: f64) callconv(.c) c_int {
    return if (math.isFinite(x)) 1 else 0;
}

fn finitef(x: f32) callconv(.c) c_int {
    return if (math.isFinite(x)) 1 else 0;
}

fn frexpGeneric(comptime T: type, x: T, e: *c_int) T {
    // libc expects `*e` to be unspecified in this case; an unspecified C value
    // should be a valid value of the relevant type, yet Zig's std
    // implementation sets it to `undefined` -- which can even be nonsense
    // according to the type (int). Therefore, we're setting it to a valid
    // int value in Zig -- a zero.
    //
    // This mirrors the handling of infinities, where libc also expects
    // unspecified for the value of `*e` and Zig std sets it to a zero.
    if (math.isNan(x)) {
        e.* = 0;
        return x;
    }

fn frexp_(x: f64, e: *c_int) callconv(.c) f64 {
    const r = math.frexp(x);
    e.* = r.exponent;
    return r.significand;
}

fn frexp(x: f64, e: *c_int) callconv(.c) f64 {
    return frexpGeneric(f64, x, e);
}

fn frexpf(x: f32, e: *c_int) callconv(.c) f32 {
    return frexpGeneric(f32, x, e);
}

fn frexpl(x: c_longdouble, e: *c_int) callconv(.c) c_longdouble {
    return frexpGeneric(c_longdouble, x, e);
fn fdimGeneric(comptime T: type, x: T, y: T) T {
    if (math.isNan(x)) return x;
    if (math.isNan(y)) return y;
    // Use early return to prevent LLVM from converting to branchless select,
    // which would speculatively compute x - y even when x <= y,
    // raising an invalid FP exception for cases like fdim(-inf, -inf).
    if (x > y) return x - y;
    return 0;
}

fn fdim_(x: f64, y: f64) callconv(.c) f64 {
    return fdimGeneric(f64, x, y);
}

fn fdimf_(x: f32, y: f32) callconv(.c) f32 {
    return fdimGeneric(f32, x, y);
}

fn fdiml_(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => @bitCast(fdim_(@bitCast(x), @bitCast(y))),
        else => fdimGeneric(c_longdouble, x, y),
    };
}

test "fdim" {
    try expectEqual(@as(f64, 3.0), fdim_(5.0, 2.0));
    try expectEqual(@as(f64, 0.0), fdim_(2.0, 5.0));
    try expect(math.isNan(fdim_(math.nan(f64), 1.0)));
    try expect(math.isNan(fdim_(1.0, math.nan(f64))));
    try expectEqual(@as(f64, 0.0), fdim_(-math.inf(f64), -math.inf(f64)));
    try expectEqual(@as(f64, 0.0), fdim_(math.inf(f64), math.inf(f64)));
    try expectEqual(math.inf(f64), fdim_(math.inf(f64), -math.inf(f64)));
    try expectEqual(@as(f32, 3.0), fdimf_(5.0, 2.0));
    try expectEqual(@as(f32, 0.0), fdimf_(2.0, 5.0));
    try expectEqual(@as(f32, 0.0), fdimf_(-math.inf(f32), -math.inf(f32)));
}

fn finite_(x: f64) callconv(.c) c_int {
    return if (math.isFinite(x)) 1 else 0;
}

fn finitef_(x: f32) callconv(.c) c_int {
    return if (math.isFinite(x)) 1 else 0;
}

test "finite" {
    try expectEqual(@as(c_int, 1), finite_(1.0));
    try expectEqual(@as(c_int, 0), finite_(math.inf(f64)));
    try expectEqual(@as(c_int, 0), finite_(math.nan(f64)));
    try expectEqual(@as(c_int, 1), finitef_(1.0));
    try expectEqual(@as(c_int, 0), finitef_(math.inf(f32)));
fn frexpf_(x: f32, e: *c_int) callconv(.c) f32 {
    const r = math.frexp(x);
    e.* = r.exponent;
    return r.significand;
}

fn frexpl_(x: c_longdouble, e: *c_int) callconv(.c) c_longdouble {
    const r = math.frexp(x);
    e.* = r.exponent;
    return r.significand;
}

test "frexp" {
    var e: c_int = undefined;
    try expectEqual(@as(f64, 0.75), frexp_(1.5, &e));
    try expectEqual(@as(c_int, 1), e);
    try expectEqual(@as(f64, 0.5), frexp_(1.0, &e));
    try expectEqual(@as(c_int, 1), e);
    try expectEqual(@as(f32, 0.75), frexpf_(1.5, &e));
    try expectEqual(@as(c_int, 1), e);
}

fn ilogb_(x: f64) callconv(.c) c_int {
    return math.ilogb(x);
}

fn ilogbf_(x: f32) callconv(.c) c_int {
    return math.ilogb(x);
}

fn ilogbl_(x: c_longdouble) callconv(.c) c_int {
    return math.ilogb(x);
}

test "ilogb" {
    try expectEqual(@as(c_int, 0), ilogb_(1.0));
    try expectEqual(@as(c_int, 3), ilogb_(10.0));
    try expectEqual(@as(c_int, 0), ilogbf_(1.0));
    try expectEqual(@as(c_int, 3), ilogbf_(10.0));
}

fn ldexp_(x: f64, n: c_int) callconv(.c) f64 {
    return math.ldexp(x, n);
}

fn ldexpf_(x: f32, n: c_int) callconv(.c) f32 {
    return math.ldexp(x, n);
}

fn ldexpl_(x: c_longdouble, n: c_int) callconv(.c) c_longdouble {
    return math.ldexp(x, n);
}

test "ldexp" {
    try expectEqual(@as(f64, 8.0), ldexp_(1.0, 3));
    try expectEqual(@as(f64, 0.5), ldexp_(1.0, -1));
    try expectEqual(@as(f32, 8.0), ldexpf_(1.0, 3));
}

fn logbGeneric(comptime T: type, x: T) T {
    if (math.isNan(x)) return x;
    if (math.isInf(x)) return math.inf(T);
    if (x == 0) {
        return -1.0 / @as(T, 0.0);
    }
    return @floatFromInt(math.ilogb(x));
}

fn logb_(x: f64) callconv(.c) f64 {
    return logbGeneric(f64, x);
}

fn logbf_(x: f32) callconv(.c) f32 {
    return logbGeneric(f32, x);
}

fn logbl_(x: c_longdouble) callconv(.c) c_longdouble {
    return logbGeneric(c_longdouble, x);
}

test "logb" {
    try expectEqual(@as(f64, 0.0), logb_(1.0));
    try expectEqual(@as(f64, 3.0), logb_(10.0));
    try expectEqual(math.inf(f64), logb_(math.inf(f64)));
    try expect(math.isNan(logb_(math.nan(f64))));
    try expectEqual(@as(f32, 0.0), logbf_(1.0));
    try expectEqual(@as(f32, 3.0), logbf_(10.0));
fn fma(x: f64, y: f64, z: f64) callconv(.c) f64 {
    return @mulAdd(f64, x, y, z);
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

fn intFromFloat(comptime I: type, x: anytype) I {
    const F = @TypeOf(x);
    if (math.isNan(x) or !math.isFinite(x)) return math.minInt(I);
    const upper: F = @floatFromInt(@as(comptime_int, math.maxInt(I)) + 1);
    const lower: F = @floatFromInt(math.minInt(I));
    if (x >= upper or x < lower) return math.minInt(I);
    return @intFromFloat(x);
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

fn lrint(x: f64) callconv(.c) c_long {
    return @intFromFloat(rint(x));
}

fn lrintf(x: f32) callconv(.c) c_long {
    return @intFromFloat(rintf(x));
fn llrint(x: f64) callconv(.c) c_longlong {
    return intFromFloat(c_longlong, rint(x));
}

fn lrint(x: f64) callconv(.c) c_long {
    return intFromFloat(c_long, rint(x));
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

fn nearbyint(x: f64) callconv(.c) f64 {
    return rint(x);
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

/// Port of musl powf — IEEE 754 conformant single-precision power function.
/// Uses double-precision log2+exp2 internally for 0.82 ULP accuracy.
/// Copyright (c) 2017-2018, Arm Limited. SPDX-License-Identifier: MIT
fn powf(x: f32, y: f32) callconv(.c) f32 {
    return powf_impl.call(x, y);
}

const powf_impl = struct {
    const POWF_LOG2_TABLE_BITS = 4;
    const POWF_LOG2_POLY_ORDER = 5;
    // Without TOINT_INTRINSICS, POWF_SCALE_BITS = 0, POWF_SCALE = 1.0
    const POWF_SCALE: comptime_float = 1.0;

    const EXP2F_TABLE_BITS = 5;
    const EXP2F_N = 1 << EXP2F_TABLE_BITS; // 32
    const SIGN_BIAS = 1 << (EXP2F_TABLE_BITS + 11); // 0x10000

    const OFF = 0x3f330000;

    // -- powf log2 data --
    const Log2Tab = struct { invc: f64, logc: f64 };
    const log2_tab = [1 << POWF_LOG2_TABLE_BITS]Log2Tab{
        .{ .invc = 0x1.661ec79f8f3bep+0, .logc = -0x1.efec65b963019p-2 * POWF_SCALE },
        .{ .invc = 0x1.571ed4aaf883dp+0, .logc = -0x1.b0b6832d4fca4p-2 * POWF_SCALE },
        .{ .invc = 0x1.49539f0f010bp+0, .logc = -0x1.7418b0a1fb77bp-2 * POWF_SCALE },
        .{ .invc = 0x1.3c995b0b80385p+0, .logc = -0x1.39de91a6dcf7bp-2 * POWF_SCALE },
        .{ .invc = 0x1.30d190c8864a5p+0, .logc = -0x1.01d9bf3f2b631p-2 * POWF_SCALE },
        .{ .invc = 0x1.25e227b0b8eap+0, .logc = -0x1.97c1d1b3b7afp-3 * POWF_SCALE },
        .{ .invc = 0x1.1bb4a4a1a343fp+0, .logc = -0x1.2f9e393af3c9fp-3 * POWF_SCALE },
        .{ .invc = 0x1.12358f08ae5bap+0, .logc = -0x1.960cbbf788d5cp-4 * POWF_SCALE },
        .{ .invc = 0x1.0953f419900a7p+0, .logc = -0x1.a6f9db6475fcep-5 * POWF_SCALE },
        .{ .invc = 0x1p+0, .logc = 0x0p+0 * POWF_SCALE },
        .{ .invc = 0x1.e608cfd9a47acp-1, .logc = 0x1.338ca9f24f53dp-4 * POWF_SCALE },
        .{ .invc = 0x1.ca4b31f026aap-1, .logc = 0x1.476a9543891bap-3 * POWF_SCALE },
        .{ .invc = 0x1.b2036576afce6p-1, .logc = 0x1.e840b4ac4e4d2p-3 * POWF_SCALE },
        .{ .invc = 0x1.9c2d163a1aa2dp-1, .logc = 0x1.40645f0c6651cp-2 * POWF_SCALE },
        .{ .invc = 0x1.886e6037841edp-1, .logc = 0x1.88e9c2c1b9ff8p-2 * POWF_SCALE },
        .{ .invc = 0x1.767dcf5534862p-1, .logc = 0x1.ce0a44eb17bccp-2 * POWF_SCALE },
    };

    const log2_poly = [POWF_LOG2_POLY_ORDER]f64{
        0x1.27616c9496e0bp-2 * POWF_SCALE,
        -0x1.71969a075c67ap-2 * POWF_SCALE,
        0x1.ec70a6ca7baddp-2 * POWF_SCALE,
        -0x1.7154748bef6c8p-1 * POWF_SCALE,
        0x1.71547652ab82bp0 * POWF_SCALE,
    };

    // -- exp2f data (non-intrinsic path uses shift_scaled and poly, not poly_scaled) --
    const exp2f_tab = [EXP2F_N]u64{
        0x3ff0000000000000, 0x3fefd9b0d3158574, 0x3fefb5586cf9890f, 0x3fef9301d0125b51,
        0x3fef72b83c7d517b, 0x3fef54873168b9aa, 0x3fef387a6e756238, 0x3fef1e9df51fdee1,
        0x3fef06fe0a31b715, 0x3feef1a7373aa9cb, 0x3feedea64c123422, 0x3feece086061892d,
        0x3feebfdad5362a27, 0x3feeb42b569d4f82, 0x3feeab07dd485429, 0x3feea47eb03a5585,
        0x3feea09e667f3bcd, 0x3fee9f75e8ec5f74, 0x3feea11473eb0187, 0x3feea589994cce13,
        0x3feeace5422aa0db, 0x3feeb737b0cdc5e5, 0x3feec49182a3f090, 0x3feed503b23e255d,
        0x3feee89f995ad3ad, 0x3feeff76f2fb5e47, 0x3fef199bdd85529c, 0x3fef3720dcef9069,
        0x3fef5818dcfba487, 0x3fef7c97337b9b5f, 0x3fefa4afa2a490da, 0x3fefd0765b6e4540,
    };

    const exp2f_shift: f64 = 0x1.8p+52 / EXP2F_N;

    const exp2f_poly = [3]f64{
        0x1.c6af84b912394p-5,
        0x1.ebfce50fac4f3p-3,
        0x1.62e42ff0c52d6p-1,
    };

    // -- bit manipulation helpers --
    inline fn asfloat(i: u32) f32 {
        return @bitCast(i);
    }

    inline fn asuint(f: f32) u32 {
        return @bitCast(f);
    }

    inline fn asdouble(i: u64) f64 {
        return @bitCast(i);
    }

    inline fn asuint64(f: f64) u64 {
        return @bitCast(f);
    }

    // -- FP barrier: prevents compiler from optimizing away FP side-effects --
    inline fn fpBarrier(x: f32) f32 {
        var val = x;
        const ptr: *volatile f32 = &val;
        return ptr.*;
    }

    // -- FP exception helpers --
    // xflowf: only the first operand gets the sign; second is always positive.
    // This ensures the result has the correct sign.
    inline fn xflowf(sign: u32, y_val: f32) f32 {
        return fpBarrier(if (sign != 0) -y_val else y_val) * y_val;
    }

    inline fn mathOflowf(sign: u32) f32 {
        return xflowf(sign, 0x1p97);
    }

    inline fn mathUflowf(sign: u32) f32 {
        return xflowf(sign, 0x1p-95);
    }

    inline fn mathDivzerof(sign: u32) f32 {
        return fpBarrier(if (sign != 0) @as(f32, -1.0) else @as(f32, 1.0)) / 0.0;
    }

    inline fn mathInvalidf(x: f32) f32 {
        return (x - x) / (x - x);
    }

    /// Returns 0 if not int, 1 if odd int, 2 if even int.
    inline fn checkint(iy: u32) u32 {
        const e = (iy >> 23) & 0xff;
        if (e < 0x7f) return 0;
        if (e > 0x7f + 23) return 2;
        if (iy & ((@as(u32, 1) << @intCast(0x7f + 23 - e)) - 1) != 0) return 0;
        if (iy & (@as(u32, 1) << @intCast(0x7f + 23 - e)) != 0) return 1;
        return 2;
    }

    inline fn zeroinfnan(ix: u32) bool {
        return 2 *% ix -% 1 >= 2 *% @as(u32, 0x7f800000) -% 1;
    }

    /// Subnormal input is normalized so ix has negative biased exponent.
    inline fn log2Inline(ix: u32) f64 {
        const N = 1 << POWF_LOG2_TABLE_BITS;
        const A = &log2_poly;

        // x = 2^k z; where z is in range [OFF,2*OFF] and exact.
        const tmp = ix - OFF;
        const i: usize = @intCast((tmp >> (23 - POWF_LOG2_TABLE_BITS)) % N);
        const top = tmp & 0xff800000;
        const iz = ix - top;
        const k: f64 = @floatFromInt(@as(i32, @bitCast(top)) >> 23); // arithmetic shift, POWF_SCALE_BITS=0
        const invc = log2_tab[i].invc;
        const logc = log2_tab[i].logc;
        const z: f64 = @floatCast(asfloat(iz));

        // log2(x) = log1p(z/c-1)/ln2 + log2(c) + k
        const r = z * invc - 1;
        const y0 = logc + k;

        // Pipelined polynomial evaluation to approximate log1p(r)/ln2.
        const r2 = r * r;
        var yy = A[0] * r + A[1];
        const p = A[2] * r + A[3];
        const r4 = r2 * r2;
        var q = A[4] * r + y0;
        q = p * r2 + q;
        yy = yy * r4 + q;
        return yy;
    }

    /// exp2 inline for powf. sign_bias sets the sign of the result.
    inline fn exp2Inline(xd: f64, sign_bias: u64) f32 {
        const T = &exp2f_tab;
        const C = &exp2f_poly;
        const SHIFT = exp2f_shift;

        // x = k/N + r with r in [-1/(2N), 1/(2N)]
        const kd = @as(f64, xd + SHIFT);
        const ki: u64 = asuint64(kd);
        const kd2 = kd - SHIFT;
        const r = xd - kd2;

        // exp2(x) = 2^(k/N) * 2^r ~= s * (C0*r^3 + C1*r^2 + C2*r + 1)
        var t: u64 = T[@as(usize, @intCast(ki % EXP2F_N))];
        const ski: u64 = ki +% sign_bias;
        t +%= ski << (52 - EXP2F_TABLE_BITS);
        const s = asdouble(t);
        const z = C[0] * r + C[1];
        const r2 = r * r;
        var result = C[2] * r + 1;
        result = z * r2 + result;
        result = result * s;
        return @floatCast(result);
    }

    fn call(x: f32, y: f32) f32 {
        // Return x for y == 1.0 without any FP operations that could raise
        // spurious exception flags (e.g. INEXACT|OVERFLOW for x = FLT_MAX).
        if (asuint(y) == 0x3f800000) return x;

        var sign_bias: u64 = 0;
        var ix = asuint(x);
        const iy = asuint(y);

        if (ix -% 0x00800000 >= 0x7f800000 -% 0x00800000 or zeroinfnan(iy)) {
            // Either (x < 0x1p-126 or inf or nan) or (y is 0 or inf or nan).
            if (zeroinfnan(iy)) {
                if (2 *% iy == 0)
                    return 1.0;
                if (ix == 0x3f800000)
                    return 1.0;
                if (2 *% ix > 2 *% @as(u32, 0x7f800000) or
                    2 *% iy > 2 *% @as(u32, 0x7f800000))
                    return x + y;
                if (2 *% ix == 2 *% @as(u32, 0x3f800000))
                    return 1.0;
                if ((2 *% ix < 2 *% @as(u32, 0x3f800000)) == (iy & 0x80000000 == 0))
                    return 0.0; // |x|<1 && y==inf or |x|>1 && y==-inf.
                return y * y;
            }
            if (zeroinfnan(ix)) {
                var x2 = x * x;
                if (ix & 0x80000000 != 0 and checkint(iy) == 1)
                    x2 = -x2;
                // Without the barrier some versions of clang hoist the 1/x2 and
                // thus division by zero exception can be signaled spuriously.
                return if (iy & 0x80000000 != 0) fpBarrier(1 / x2) else x2;
            }
            // x and y are non-zero finite.
            if (ix & 0x80000000 != 0) {
                // Finite x < 0.
                const yint = checkint(iy);
                if (yint == 0)
                    return mathInvalidf(x);
                if (yint == 1)
                    sign_bias = SIGN_BIAS;
                ix &= 0x7fffffff;
            }
            if (ix < 0x00800000) {
                // Normalize subnormal x so exponent becomes negative.
                ix = asuint(x * 0x1p23);
                ix &= 0x7fffffff;
                ix -%= 23 << 23;
            }
        }
        const logx = log2Inline(ix);
        const ylogx = @as(f64, y) * logx; // cannot overflow, y is single prec.
        if ((asuint64(ylogx) >> 47 & 0xffff) >=
            asuint64(126.0 * POWF_SCALE) >> 47)
        {
            // |y*log(x)| >= 126.
            if (ylogx > 0x1.fffffffd1d571p+6 * POWF_SCALE)
                return mathOflowf(@intCast(sign_bias));
            if (ylogx <= -150.0 * POWF_SCALE)
                return mathUflowf(@intCast(sign_bias));
        }
        return exp2Inline(ylogx, sign_bias);
    }
};

fn pow10(x: f64) callconv(.c) f64 {
    return exp10(x);
}

fn pow10f(x: f32) callconv(.c) f32 {
    return exp10f(x);
}

fn remainder_(x: f64, y: f64) callconv(.c) f64 {
    var q: c_int = undefined;
    return remquo_(x, y, &q);
}

fn remainderf_(x: f32, y: f32) callconv(.c) f32 {
    var q: c_int = undefined;
    return remquof_(x, y, &q);
}

fn remainderl_(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    var q: c_int = undefined;
    return remquol_(x, y, &q);
}

/// Translated from musl/src/math/remquof.c
fn remquof_(x_: f32, y_: f32, quo: *c_int) callconv(.c) f32 {
    var x: f32 = x_;
    var y: f32 = y_;
    var uxi: u32 = @bitCast(x);
    var uyi: u32 = @bitCast(y);
    var ex: i32 = @intCast(uxi >> 23 & 0xff);
    var ey: i32 = @intCast(uyi >> 23 & 0xff);
    const sx: u32 = uxi >> 31;
    const sy: u32 = uyi >> 31;
    var q: u32 = undefined;

    quo.* = 0;
    if (uyi << 1 == 0 or math.isNan(y) or ex == 0xff)
        return (x * y) / (x * y);
    if (uxi << 1 == 0)
        return x;

    // normalize x and y
    if (ex == 0) {
        var i = uxi << 9;
        while (i >> 31 == 0) : (i <<= 1) {
            ex -= 1;
        }
        uxi <<= @intCast(@as(u32, @bitCast(-ex + 1)));
    } else {
        uxi &= 0x007fffff;
        uxi |= 0x00800000;
    }
    if (ey == 0) {
        var i = uyi << 9;
        while (i >> 31 == 0) : (i <<= 1) {
            ey -= 1;
        }
        uyi <<= @intCast(@as(u32, @bitCast(-ey + 1)));
    } else {
        uyi &= 0x007fffff;
        uyi |= 0x00800000;
    }

    q = 0;
    if (ex >= ey) {
        // x mod y
        while (ex > ey) : (ex -= 1) {
            const i = uxi -% uyi;
            if (i >> 31 == 0) {
                uxi = i;
                q +%= 1;
            }
            uxi <<= 1;
            q = q *% 2;
        }
        {
            const i = uxi -% uyi;
            if (i >> 31 == 0) {
                uxi = i;
                q +%= 1;
            }
        }
        if (uxi == 0) {
            ex = -30;
        } else {
            while (uxi >> 23 == 0) {
                uxi <<= 1;
                ex -= 1;
            }
        }
    } else if (ex + 1 != ey) {
        return x;
    }

    // scale result and decide between |x| and |x|-|y|
    if (ex > 0) {
        uxi -= 1 << 23;
        uxi |= @as(u32, @intCast(ex)) << 23;
    } else {
        uxi >>= @intCast(@as(u32, @bitCast(-ex + 1)));
    }
    x = @bitCast(uxi);
    if (sy != 0) y = -y;
    if (ex == ey or (ex + 1 == ey and (2.0 * x > y or (2.0 * x == y and q % 2 != 0)))) {
        x -= y;
        q +%= 1;
    }
    q &= 0x7fffffff;
    const qi: c_int = @intCast(q);
    quo.* = if (sx ^ sy != 0) -qi else qi;
    return if (sx != 0) -x else x;
}

/// Translated from musl/src/math/remquo.c
fn remquo_(x_: f64, y_: f64, quo: *c_int) callconv(.c) f64 {
    var x: f64 = x_;
    var y: f64 = y_;
    var uxi: u64 = @bitCast(x);
    var uyi: u64 = @bitCast(y);
    var ex: i32 = @intCast(uxi >> 52 & 0x7ff);
    var ey: i32 = @intCast(uyi >> 52 & 0x7ff);
    const sx: u64 = uxi >> 63;
    const sy: u64 = uyi >> 63;
    var q: u32 = undefined;

    quo.* = 0;
    if (uyi << 1 == 0 or math.isNan(y) or ex == 0x7ff)
        return (x * y) / (x * y);
    if (uxi << 1 == 0)
        return x;

    // normalize x and y
    if (ex == 0) {
        var i = uxi << 12;
        while (i >> 63 == 0) : (i <<= 1) {
            ex -= 1;
        }
        uxi <<= @intCast(@as(u32, @bitCast(-ex + 1)));
    } else {
        uxi &= 0x000fffffffffffff;
        uxi |= 0x0010000000000000;
    }
    if (ey == 0) {
        var i = uyi << 12;
        while (i >> 63 == 0) : (i <<= 1) {
            ey -= 1;
        }
        uyi <<= @intCast(@as(u32, @bitCast(-ey + 1)));
    } else {
        uyi &= 0x000fffffffffffff;
        uyi |= 0x0010000000000000;
    }

    q = 0;
    if (ex >= ey) {
        // x mod y
        while (ex > ey) : (ex -= 1) {
            const i = uxi -% uyi;
            if (i >> 63 == 0) {
                uxi = i;
                q +%= 1;
            }
            uxi <<= 1;
            q = q *% 2;
        }
        {
            const i = uxi -% uyi;
            if (i >> 63 == 0) {
                uxi = i;
                q +%= 1;
            }
        }
        if (uxi == 0) {
            ex = -60;
        } else {
            while (uxi >> 52 == 0) {
                uxi <<= 1;
                ex -= 1;
            }
        }
    } else if (ex + 1 != ey) {
        return x;
    }

    // scale result and decide between |x| and |x|-|y|
    if (ex > 0) {
        uxi -= @as(u64, 1) << 52;
        uxi |= @as(u64, @intCast(ex)) << 52;
    } else {
        uxi >>= @intCast(@as(u32, @bitCast(-ex + 1)));
    }
    x = @bitCast(uxi);
    if (sy != 0) y = -y;
    if (ex == ey or (ex + 1 == ey and (2.0 * x > y or (2.0 * x == y and q % 2 != 0)))) {
        x -= y;
        q +%= 1;
    }
    q &= 0x7fffffff;
    const qi: c_int = @intCast(q);
    quo.* = if (sx ^ sy != 0) -qi else qi;
    return if (sx != 0) -x else x;
}

/// Translated from musl/src/math/remquol.c
fn remquol_(x_: c_longdouble, y_: c_longdouble, quo: *c_int) callconv(.c) c_longdouble {
    const ld = @typeInfo(c_longdouble).float;
    if (ld.bits == 64) {
        return @floatCast(remquo_(@as(f64, @floatCast(x_)), @as(f64, @floatCast(y_)), quo));
    }
    if (ld.bits == 80) {
        return remquox(f80, x_, y_, quo);
    }
    if (ld.bits == 128) {
        return remquox(f128, x_, y_, quo);
    }
    unreachable;
}

fn remquox(comptime F: type, x_: c_longdouble, y_: c_longdouble, quo: *c_int) c_longdouble {
    const bits = @typeInfo(F).float.bits;
    const Bits = std.meta.Int(.unsigned, bits);
    const se_shift: comptime_int = bits - 16;
    const se_mask: Bits = @as(Bits, 0xFFFF) << se_shift;

    var x: F = @floatCast(x_);
    var y: F = @floatCast(y_);
    var ux: Bits = @bitCast(x);
    var uy: Bits = @bitCast(y);
    var ux_se: u16 = @truncate(ux >> se_shift);
    const uy_se: u16 = @truncate(uy >> se_shift);
    var ex: i32 = @intCast(ux_se & 0x7fff);
    var ey: i32 = @intCast(uy_se & 0x7fff);
    const sx: u16 = ux_se >> 15;
    const sy: u16 = uy_se >> 15;
    var q: u32 = 0;

    quo.* = 0;
    if (y == 0 or math.isNan(y) or ex == 0x7fff)
        return @floatCast((x * y) / (x * y));
    if (x == 0)
        return @floatCast(x);

    // normalize x
    if (ex == 0) {
        ux = ux & ~se_mask;
        x = @bitCast(ux);
        x *= 0x1p120;
        ux = @bitCast(x);
        ux_se = @truncate(ux >> se_shift);
        ex = @as(i32, @intCast(ux_se & 0x7fff)) - 120;
    }
    // normalize y
    if (ey == 0) {
        uy = uy & ~se_mask;
        y = @bitCast(uy);
        y *= 0x1p120;
        uy = @bitCast(y);
        ey = @as(i32, @intCast(@as(u16, @truncate(uy >> se_shift)) & 0x7fff)) - 120;
    }

    q = 0;
    if (ex >= ey) {
        if (bits == 80) {
            // f80: 64-bit mantissa in bits[63:0]
            var mx: u64 = @truncate(ux);
            const my: u64 = @truncate(uy);
            while (ex > ey) : (ex -= 1) {
                if (mx >= my) {
                    mx = (mx - my) *% 2;
                    q +%= 1;
                    q = q *% 2;
                } else if (mx *% 2 < mx) {
                    mx = mx *% 2 -% my;
                    q = q *% 2;
                    q +%= 1;
                } else {
                    mx = mx * 2;
                    q = q *% 2;
                }
            }
            if (mx >= my) {
                mx = mx - my;
                q +%= 1;
            }
            if (mx == 0) {
                ex = -120;
            } else {
                while (mx >> 63 == 0) {
                    mx *%= 2;
                    ex -= 1;
                }
            }
            ux = (ux & se_mask) | @as(Bits, mx);
        } else {
            // f128: mantissa split into hi (48 bits) and lo (64 bits)
            var xhi: u64 = (@as(u64, @truncate(ux >> 64)) & (std.math.maxInt(u64) >> 16)) | (@as(u64, 1) << 48);
            const yhi: u64 = (@as(u64, @truncate(uy >> 64)) & (std.math.maxInt(u64) >> 16)) | (@as(u64, 1) << 48);
            var xlo: u64 = @truncate(ux);
            const ylo: u64 = @truncate(uy);
            while (ex > ey) : (ex -= 1) {
                var hi = xhi -% yhi;
                const lo = xlo -% ylo;
                if (xlo < ylo)
                    hi -%= 1;
                if (hi >> 63 == 0) {
                    xhi = hi *% 2 +% (lo >> 63);
                    xlo = lo *% 2;
                    q +%= 1;
                } else {
                    xhi = xhi *% 2 +% (xlo >> 63);
                    xlo = xlo *% 2;
                }
                q = q *% 2;
            }
            {
                var hi = xhi -% yhi;
                const lo = xlo -% ylo;
                if (xlo < ylo)
                    hi -%= 1;
                if (hi >> 63 == 0) {
                    xhi = hi;
                    xlo = lo;
                    q +%= 1;
                }
            }
            if ((xhi | xlo) == 0) {
                ex = -120;
            } else {
                while (xhi >> 48 == 0) {
                    xhi = xhi *% 2 +% (xlo >> 63);
                    xlo = xlo *% 2;
                    ex -= 1;
                }
            }
            ux = (@as(Bits, xhi) << 64) | @as(Bits, xlo);
        }
    }

    // scale result and decide between |x| and |x|-|y|
    if (ex <= 0) {
        ux_se = @intCast(@as(u32, @bitCast(ex + 120)));
        ux = (ux & ~se_mask) | (@as(Bits, ux_se) << se_shift);
        x = @bitCast(ux);
        x *= 0x1p-120;
    } else {
        ux_se = @intCast(@as(u32, @bitCast(ex)));
        ux = (ux & ~se_mask) | (@as(Bits, ux_se) << se_shift);
        x = @bitCast(ux);
    }
    if (sy != 0) y = -y;
    if (ex == ey or (ex + 1 == ey and (2.0 * x > y or (2.0 * x == y and q % 2 != 0)))) {
        x -= y;
        q +%= 1;
    }
    q &= 0x7fffffff;
    const qi: c_int = @intCast(q);
    quo.* = if (sx ^ sy != 0) -qi else qi;
    return @floatCast(if (sx != 0) -x else x);
}

test "remquof" {
    var q: c_int = undefined;

    // basic: 10 mod 3 = 1, quotient 3
    try expectEqual(@as(f32, 1.0), remquof_(10.0, 3.0, &q));
    try expectEqual(@as(c_int, 3), q & 0x7);

    // negative x: -10 mod 3 = -1, quotient -3
    try expectEqual(@as(f32, -1.0), remquof_(-10.0, 3.0, &q));
    try expectEqual(@as(c_int, -3), q);

    // remainder rounds to nearest: remquo(5.5, 2) -> -0.5 quotient 3
    try expectEqual(@as(f32, -0.5), remquof_(5.5, 2.0, &q));
    try expectEqual(@as(c_int, 3), q);

    // y == 0 -> NaN
    try expect(math.isNan(remquof_(1.0, 0.0, &q)));

    // x == NaN -> NaN
    try expect(math.isNan(remquof_(math.nan(f32), 1.0, &q)));

    // x == inf -> NaN
    try expect(math.isNan(remquof_(math.inf(f32), 1.0, &q)));

    // x == 0 -> 0
    try expectEqual(@as(f32, 0.0), remquof_(0.0, 1.0, &q));
    try expectEqual(@as(c_int, 0), q);
}

test "remquo" {
    var q: c_int = undefined;

    try expectEqual(@as(f64, 1.0), remquo_(10.0, 3.0, &q));
    try expectEqual(@as(c_int, 3), q & 0x7);

    try expectEqual(@as(f64, -1.0), remquo_(-10.0, 3.0, &q));
    try expectEqual(@as(c_int, -3), q);

    try expectEqual(@as(f64, -0.5), remquo_(5.5, 2.0, &q));
    try expectEqual(@as(c_int, 3), q);

    try expect(math.isNan(remquo_(1.0, 0.0, &q)));
    try expect(math.isNan(remquo_(math.nan(f64), 1.0, &q)));
    try expect(math.isNan(remquo_(math.inf(f64), 1.0, &q)));

    try expectEqual(@as(f64, 0.0), remquo_(0.0, 1.0, &q));
    try expectEqual(@as(c_int, 0), q);
}

test "remainderf" {
    try expectEqual(@as(f32, 1.0), remainderf_(10.0, 3.0));
    try expectEqual(@as(f32, -1.0), remainderf_(-10.0, 3.0));
    try expectEqual(@as(f32, -0.5), remainderf_(5.5, 2.0));
    try expect(math.isNan(remainderf_(1.0, 0.0)));
}

test "remainder" {
    try expectEqual(@as(f64, 1.0), remainder_(10.0, 3.0));
    try expectEqual(@as(f64, -1.0), remainder_(-10.0, 3.0));
    try expectEqual(@as(f64, -0.5), remainder_(5.5, 2.0));
    try expect(math.isNan(remainder_(1.0, 0.0)));
}

fn rint(x: f64) callconv(.c) f64 {
    const toint: f64 = 1.0 / math.floatEps(f64);
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

fn rintf(x: f32) callconv(.c) f32 {
    const toint: f32 = 1.0 / math.floatEps(f32);
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
        return if (s == 1) -0.0 else 0;
    }
    return y;
}

fn testRint(comptime T: type) !void {
    const f = switch (T) {
        f32 => rintf,
        f64 => rint,
        else => @compileError("rint not implemented for" ++ @typeName(T)),
    };

    // Positive numbers round correctly
    try expectEqual(@as(T, 42.0), f(42.2));
    try expectEqual(@as(T, 42.0), f(41.8));

    // Negative numbers round correctly
    try expectEqual(@as(T, -6.0), f(-5.9));
    try expectEqual(@as(T, -6.0), f(-6.1));

    // No rounding needed test
    try expectEqual(@as(T, 5.0), f(5.0));
    try expectEqual(@as(T, -10.0), f(-10.0));
    try expectEqual(@as(T, 0.0), f(0.0));

    // Very large numbers return unchanged
    const large: T = 9007199254740992.0; // 2^53
    try expectEqual(large, f(large));
    try expectEqual(-large, f(-large));

    // Small positive numbers round to zero
    const pos_result = f(0.3);
    try expect(math.isPositiveZero(pos_result));

    // Small negative numbers round to negative zero
    const neg_result = f(-0.3);
    try expect(math.isNegativeZero(neg_result));

    // Exact half rounds to nearest even (banker's rounding)
    try expectEqual(@as(T, 2.0), f(2.5));
    try expectEqual(@as(T, 4.0), f(3.5));
}

test "rint" {
    try testRint(f32);
    try testRint(f64);
}

fn scalbln_(x: f64, n: c_long) callconv(.c) f64 {
    const ni: c_int = if (n > maxInt(c_int)) maxInt(c_int) else if (n < minInt(c_int)) minInt(c_int) else @intCast(n);
    return math.scalbn(x, ni);
}

fn scalblnf_(x: f32, n: c_long) callconv(.c) f32 {
    const ni: c_int = if (n > maxInt(c_int)) maxInt(c_int) else if (n < minInt(c_int)) minInt(c_int) else @intCast(n);
    return math.scalbn(x, ni);
}

fn scalblnl_(x: c_longdouble, n: c_long) callconv(.c) c_longdouble {
    const ni: c_int = if (n > maxInt(c_int)) maxInt(c_int) else if (n < minInt(c_int)) minInt(c_int) else @intCast(n);
    return math.scalbn(x, ni);
}

test "scalbln" {
    try expectEqual(@as(f64, 8.0), scalbln_(1.0, 3));
    try expectEqual(@as(f64, 0.5), scalbln_(1.0, -1));
    try expectEqual(@as(f32, 8.0), scalblnf_(1.0, 3));
}

fn scalbn_(x: f64, n: c_int) callconv(.c) f64 {
    return math.scalbn(x, n);
}

fn scalbnf_(x: f32, n: c_int) callconv(.c) f32 {
    return math.scalbn(x, n);
}

fn scalbnl_(x: c_longdouble, n: c_int) callconv(.c) c_longdouble {
    return math.scalbn(x, n);
}

test "scalbn" {
    try expectEqual(@as(f64, 8.0), scalbn_(1.0, 3));
    try expectEqual(@as(f64, 0.5), scalbn_(1.0, -1));
    try expectEqual(@as(f32, 8.0), scalbnf_(1.0, 3));
}

fn significand_(x: f64) callconv(.c) f64 {
    return math.scalbn(x, -math.ilogb(x));
}

fn significandf_(x: f32) callconv(.c) f32 {
    return math.scalbn(x, -math.ilogb(x));
}

test "significand" {
    try expectEqual(@as(f64, 1.5), significand_(3.0));
    try expectEqual(@as(f64, 1.25), significand_(10.0));
    try expectEqual(@as(f32, 1.5), significandf_(3.0));
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

fn nextafterf(x: f32, y: f32) callconv(.c) f32 {
    return math.nextAfter(f32, x, y);
}

fn nextafterl(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    return math.nextAfter(c_longdouble, x, y);
}

fn nexttowardf(x: f32, y: c_longdouble) callconv(.c) f32 {
    var ux: u32 = @bitCast(x);
    if (math.isNan(x) or math.isNan(y)) return math.nan(f32);
    const xl: c_longdouble = @floatCast(x);
    if (xl == y) return @floatCast(y);
    if (x == 0) {
        ux = 1;
        if (math.signbit(y)) ux |= 0x80000000;
    } else if (xl < y) {
        if (ux >> 31 != 0) {
            ux -= 1;
        } else {
            ux += 1;
        }
    } else {
        if (ux >> 31 != 0) {
            ux += 1;
        } else {
            ux -= 1;
        }
fn nextafter(x: f64, y: f64) callconv(.c) f64 {
    var ux: u64 = @bitCast(x);
    const uy: u64 = @bitCast(y);

    if (math.isNan(x) or math.isNan(y)) return x + y;
    if (ux == uy) return y;

    const ax = ux & (math.maxInt(u64) >> 1);
    const ay = uy & (math.maxInt(u64) >> 1);
    if (ax == 0) {
        if (ay == 0) return y;
        ux = (uy & (@as(u64, 1) << 63)) | 1;
    } else if (ax > ay or ((ux ^ uy) & (@as(u64, 1) << 63)) != 0) {
        ux -= 1;
    } else {
        ux += 1;
    }
    const e: u32 = @truncate((ux >> 52) & 0x7ff);
    // raise overflow if ux is infinite and x is finite
    if (e == 0x7ff) {
        mem.doNotOptimizeAway(x + x);
    }
    // raise underflow if ux is subnormal or zero
    if (e == 0) {
        const val: f64 = @bitCast(ux);
        mem.doNotOptimizeAway(val * val);
    }
    return @bitCast(ux);
}

fn nexttowardl(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    return math.nextAfter(c_longdouble, x, y);
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
// Error function implementations - ported from musl erf.c, erff.c

// Constants for f64 erf/erfc implementation
const erf_erx: f64 = 8.45062911510467529297e-01; // 0x3FEB0AC1, 0x60000000
const erf_efx8: f64 = 1.02703333676410069053e+00; // 0x3FF06EBA, 0x8214DB69
const erf_pp0: f64 = 1.28379167095512558561e-01; // 0x3FC06EBA, 0x8214DB68
const erf_pp1: f64 = -3.25042107247001499370e-01; // 0xBFD4CD7D, 0x691CB913
const erf_pp2: f64 = -2.84817495755985104766e-02; // 0xBF9D2A51, 0xDBD7194F
const erf_pp3: f64 = -5.77027029648944159157e-03; // 0xBF77A291, 0x236668E4
const erf_pp4: f64 = -2.37630166566501626084e-05; // 0xBEF8EAD6, 0x120016AC
const erf_qq1: f64 = 3.97917223959155352819e-01; // 0x3FD97779, 0xCDDADC09
const erf_qq2: f64 = 6.50222499887672944485e-02; // 0x3FB0A54C, 0x5536CEBA
const erf_qq3: f64 = 5.08130628187576562776e-03; // 0x3F74D022, 0xC4D36B0F
const erf_qq4: f64 = 1.32494738004321644526e-04; // 0x3F215DC9, 0x221C1A10
const erf_qq5: f64 = -3.96022827877536812320e-06; // 0xBED09C43, 0x42A26120

// Coefficients for approximation to erf in [0.84375,1.25]
const erf_pa0: f64 = -2.36211856075265944077e-03;
const erf_pa1: f64 = 4.14856118683748331666e-01;
const erf_pa2: f64 = -3.72207876035701323847e-01;
const erf_pa3: f64 = 3.18346619901161753674e-01;
const erf_pa4: f64 = -1.10894694282396677476e-01;
const erf_pa5: f64 = 3.54783043256182359371e-02;
const erf_pa6: f64 = -2.16637559486879084300e-03;
const erf_qa1: f64 = 1.06420880400844228286e-01;
const erf_qa2: f64 = 5.40397917702171048937e-01;
const erf_qa3: f64 = 7.18286544141962662868e-02;
const erf_qa4: f64 = 1.26171219808761642112e-01;
const erf_qa5: f64 = 1.36370839120290507362e-02;
const erf_qa6: f64 = 1.19844998467991074170e-02;

// Coefficients for approximation to erfc in [1.25,1/0.35]
const erf_ra0: f64 = -9.86494403484714822705e-03;
const erf_ra1: f64 = -6.93858572707181764372e-01;
const erf_ra2: f64 = -1.05586262253232909814e+01;
const erf_ra3: f64 = -6.23753324503260060396e+01;
const erf_ra4: f64 = -1.62396669462573470355e+02;
const erf_ra5: f64 = -1.84605092906711035994e+02;
const erf_ra6: f64 = -8.12874355063065934246e+01;
const erf_ra7: f64 = -9.81432934416914548592e+00;
const erf_sa1: f64 = 1.96512716674392571292e+01;
const erf_sa2: f64 = 1.37657754143519042600e+02;
const erf_sa3: f64 = 4.34565877475229228821e+02;
const erf_sa4: f64 = 6.45387271733267880336e+02;
const erf_sa5: f64 = 4.29008140027567833386e+02;
const erf_sa6: f64 = 1.08635005541779435134e+02;
const erf_sa7: f64 = 6.57024977031928170135e+00;
const erf_sa8: f64 = -6.04244152148580987438e-02;

// Coefficients for approximation to erfc in [1/.35,28]
const erf_rb0: f64 = -9.86494292470009928597e-03;
const erf_rb1: f64 = -7.99283237680523006574e-01;
const erf_rb2: f64 = -1.77579549177547519889e+01;
const erf_rb3: f64 = -1.60636384855821916062e+02;
const erf_rb4: f64 = -6.37566443368389627722e+02;
const erf_rb5: f64 = -1.02509513161107724954e+03;
const erf_rb6: f64 = -4.83519191608651397019e+02;
const erf_sb1: f64 = 3.03380607434824582924e+01;
const erf_sb2: f64 = 3.25792512996573918826e+02;
const erf_sb3: f64 = 1.53672958608443695994e+03;
const erf_sb4: f64 = 3.19985821950859553908e+03;
const erf_sb5: f64 = 2.55305040643316442583e+03;
const erf_sb6: f64 = 4.74528541206955367215e+02;
const erf_sb7: f64 = -2.24409524465858183362e+01;

fn erf_erfc1(x: f64) f64 {
    const s = @abs(x) - 1;
    const P = erf_pa0 + s * (erf_pa1 + s * (erf_pa2 + s * (erf_pa3 + s * (erf_pa4 + s * (erf_pa5 + s * erf_pa6)))));
    const Q = 1 + s * (erf_qa1 + s * (erf_qa2 + s * (erf_qa3 + s * (erf_qa4 + s * (erf_qa5 + s * erf_qa6)))));
    return 1 - erf_erx - P / Q;
}

fn erf_erfc2(ix: u32, x: f64) f64 {
    if (ix < 0x3ff40000) // |x| < 1.25
        return erf_erfc1(x);

    const abs_x = @abs(x);
    const s = 1 / (abs_x * abs_x);
    var R: f64 = undefined;
    var S: f64 = undefined;
    
    if (ix < 0x4006db6d) { // |x| < 1/.35 ~ 2.85714
        R = erf_ra0 + s * (erf_ra1 + s * (erf_ra2 + s * (erf_ra3 + s * (erf_ra4 + s * (erf_ra5 + s * (erf_ra6 + s * erf_ra7))))));
        S = 1.0 + s * (erf_sa1 + s * (erf_sa2 + s * (erf_sa3 + s * (erf_sa4 + s * (erf_sa5 + s * (erf_sa6 + s * (erf_sa7 + s * erf_sa8)))))));
    } else { // |x| > 1/.35
        R = erf_rb0 + s * (erf_rb1 + s * (erf_rb2 + s * (erf_rb3 + s * (erf_rb4 + s * (erf_rb5 + s * erf_rb6)))));
        S = 1.0 + s * (erf_sb1 + s * (erf_sb2 + s * (erf_sb3 + s * (erf_sb4 + s * (erf_sb5 + s * (erf_sb6 + s * erf_sb7))))));
    }
    
    // SET_LOW_WORD equivalent: clear lower 32 bits
    var z = abs_x;
    const z_bits: u64 = @bitCast(z);
    const z_cleared: u64 = z_bits & 0xFFFFFFFF00000000;
    z = @bitCast(z_cleared);
    
    return @exp(-z * z - 0.5625) * @exp((z - abs_x) * (z + abs_x) + R / S) / abs_x;
}

fn erf_(x: f64) callconv(.c) f64 {
    // GET_HIGH_WORD equivalent
    const x_bits: u64 = @bitCast(x);
    var ix: u32 = @truncate(x_bits >> 32);
    const sign = ix >> 31;
    ix &= 0x7fffffff;
    
    if (ix >= 0x7ff00000) {
        // erf(nan)=nan, erf(+-inf)=+-1
        return @as(f64, @floatFromInt(1 - 2 * @as(i32, @intCast(sign)))) + 1 / x;
    }
    
    if (ix < 0x3feb0000) { // |x| < 0.84375
        if (ix < 0x3e300000) { // |x| < 2**-28
            // avoid underflow
            return 0.125 * (8 * x + erf_efx8 * x);
        }
        const z = x * x;
        const r = erf_pp0 + z * (erf_pp1 + z * (erf_pp2 + z * (erf_pp3 + z * erf_pp4)));
        const s = 1.0 + z * (erf_qq1 + z * (erf_qq2 + z * (erf_qq3 + z * (erf_qq4 + z * erf_qq5))));
        const y = r / s;
        return x + x * y;
    }
    
    var y: f64 = undefined;
    if (ix < 0x40180000) { // 0.84375 <= |x| < 6
        y = 1 - erf_erfc2(ix, x);
    } else {
        y = 1 - 0x1p-1022;
    }
    
    return if (sign != 0) -y else y;
}

fn erfc_(x: f64) callconv(.c) f64 {
    // GET_HIGH_WORD equivalent
    const x_bits: u64 = @bitCast(x);
    var ix: u32 = @truncate(x_bits >> 32);
    const sign = ix >> 31;
    ix &= 0x7fffffff;
    
    if (ix >= 0x7ff00000) {
        // erfc(nan)=nan, erfc(+-inf)=0,2
        return @as(f64, @floatFromInt(2 * @as(i32, @intCast(sign)))) + 1 / x;
    }
    
    if (ix < 0x3feb0000) { // |x| < 0.84375
        if (ix < 0x3c700000) // |x| < 2**-56
            return 1.0 - x;
        const z = x * x;
        const r = erf_pp0 + z * (erf_pp1 + z * (erf_pp2 + z * (erf_pp3 + z * erf_pp4)));
        const s = 1.0 + z * (erf_qq1 + z * (erf_qq2 + z * (erf_qq3 + z * (erf_qq4 + z * erf_qq5))));
        const y = r / s;
        if (sign != 0 or ix < 0x3fd00000) { // x < 1/4
            return 1.0 - (x + x * y);
        }
        return 0.5 - (x - 0.5 + x * y);
    }
    
    if (ix < 0x403c0000) { // 0.84375 <= |x| < 28
        return if (sign != 0) 2 - erf_erfc2(ix, x) else erf_erfc2(ix, x);
    }
    
    return if (sign != 0) 2 - 0x1p-1022 else 0x1p-1022 * 0x1p-1022;
}

// f32 erf/erfc constants and implementation
const erff_erx: f32 = 8.4506291151e-01;
const erff_efx8: f32 = 1.0270333290e+00;
const erff_pp0: f32 = 1.2837916613e-01;
const erff_pp1: f32 = -3.2504209876e-01;
const erff_pp2: f32 = -2.8481749818e-02;
const erff_pp3: f32 = -5.7702702470e-03;
const erff_pp4: f32 = -2.3763017452e-05;
const erff_qq1: f32 = 3.9791721106e-01;
const erff_qq2: f32 = 6.5022252500e-02;
const erff_qq3: f32 = 5.0813062117e-03;
const erff_qq4: f32 = 1.3249473704e-04;
const erff_qq5: f32 = -3.9602282413e-06;

// Coefficients for approximation to erf in [0.84375,1.25]
const erff_pa0: f32 = -2.3621185683e-03;
const erff_pa1: f32 = 4.1485610604e-01;
const erff_pa2: f32 = -3.7220788002e-01;
const erff_pa3: f32 = 3.1834661961e-01;
const erff_pa4: f32 = -1.1089469492e-01;
const erff_pa5: f32 = 3.5478305072e-02;
const erff_pa6: f32 = -2.1663755178e-03;
const erff_qa1: f32 = 1.0642088205e-01;
const erff_qa2: f32 = 5.4039794207e-01;
const erff_qa3: f32 = 7.1828655899e-02;
const erff_qa4: f32 = 1.2617121637e-01;
const erff_qa5: f32 = 1.3637083583e-02;
const erff_qa6: f32 = 1.1984500103e-02;

// Coefficients for approximation to erfc in [1.25,1/0.35]
const erff_ra0: f32 = -9.8649440333e-03;
const erff_ra1: f32 = -6.9385856390e-01;
const erff_ra2: f32 = -1.0558626175e+01;
const erff_ra3: f32 = -6.2375331879e+01;
const erff_ra4: f32 = -1.6239666748e+02;
const erff_ra5: f32 = -1.8460508728e+02;
const erff_ra6: f32 = -8.1287437439e+01;
const erff_ra7: f32 = -9.8143291473e+00;
const erff_sa1: f32 = 1.9651271820e+01;
const erff_sa2: f32 = 1.3765776062e+02;
const erff_sa3: f32 = 4.3456588745e+02;
const erff_sa4: f32 = 6.4538726807e+02;
const erff_sa5: f32 = 4.2900814819e+02;
const erff_sa6: f32 = 1.0863500214e+02;
const erff_sa7: f32 = 6.5702495575e+00;
const erff_sa8: f32 = -6.0424413532e-02;

// Coefficients for approximation to erfc in [1/.35,28]
const erff_rb0: f32 = -9.8649431020e-03;
const erff_rb1: f32 = -7.9928326607e-01;
const erff_rb2: f32 = -1.7757955551e+01;
const erff_rb3: f32 = -1.6063638306e+02;
const erff_rb4: f32 = -6.3756646729e+02;
const erff_rb5: f32 = -1.0250950928e+03;
const erff_rb6: f32 = -4.8351919556e+02;
const erff_sb1: f32 = 3.0338060379e+01;
const erff_sb2: f32 = 3.2579251099e+02;
const erff_sb3: f32 = 1.5367296143e+03;
const erff_sb4: f32 = 3.1998581543e+03;
const erff_sb5: f32 = 2.5530502930e+03;
const erff_sb6: f32 = 4.7452853394e+02;
const erff_sb7: f32 = -2.2440952301e+01;

fn erff_erfc1(x: f32) f32 {
    const s = @abs(x) - 1;
    const P = erff_pa0 + s * (erff_pa1 + s * (erff_pa2 + s * (erff_pa3 + s * (erff_pa4 + s * (erff_pa5 + s * erff_pa6)))));
    const Q = 1 + s * (erff_qa1 + s * (erff_qa2 + s * (erff_qa3 + s * (erff_qa4 + s * (erff_qa5 + s * erff_qa6)))));
    return 1 - erff_erx - P / Q;
}

fn erff_erfc2(ix: u32, x: f32) f32 {
    if (ix < 0x3fa00000) // |x| < 1.25
        return erff_erfc1(x);

    const abs_x = @abs(x);
    const s = 1 / (abs_x * abs_x);
    var R: f32 = undefined;
    var S: f32 = undefined;
    
    if (ix < 0x4036db6d) { // |x| < 1/0.35
        R = erff_ra0 + s * (erff_ra1 + s * (erff_ra2 + s * (erff_ra3 + s * (erff_ra4 + s * (erff_ra5 + s * (erff_ra6 + s * erff_ra7))))));
        S = 1.0 + s * (erff_sa1 + s * (erff_sa2 + s * (erff_sa3 + s * (erff_sa4 + s * (erff_sa5 + s * (erff_sa6 + s * (erff_sa7 + s * erff_sa8)))))));
    } else { // |x| >= 1/0.35
        R = erff_rb0 + s * (erff_rb1 + s * (erff_rb2 + s * (erff_rb3 + s * (erff_rb4 + s * (erff_rb5 + s * erff_rb6)))));
        S = 1.0 + s * (erff_sb1 + s * (erff_sb2 + s * (erff_sb3 + s * (erff_sb4 + s * (erff_sb5 + s * (erff_sb6 + s * erff_sb7))))));
    }
    
    // SET_FLOAT_WORD equivalent: clear lower bits
    var z = abs_x;
    const z_bits: u32 = @bitCast(z);
    const z_cleared: u32 = z_bits & 0xffffe000;
    z = @bitCast(z_cleared);
    
    return @exp(-z * z - 0.5625) * @exp((z - abs_x) * (z + abs_x) + R / S) / abs_x;
}

fn erff_(x: f32) callconv(.c) f32 {
    // GET_FLOAT_WORD equivalent
    const ix_raw: u32 = @bitCast(x);
    const sign = ix_raw >> 31;
    const ix = ix_raw & 0x7fffffff;
    
    if (ix >= 0x7f800000) {
        // erf(nan)=nan, erf(+-inf)=+-1
        return @as(f32, @floatFromInt(1 - 2 * @as(i32, @intCast(sign)))) + 1 / x;
    }
    
    if (ix < 0x3f580000) { // |x| < 0.84375
        if (ix < 0x31800000) { // |x| < 2**-28
            // avoid underflow
            return 0.125 * (8 * x + erff_efx8 * x);
        }
        const z = x * x;
        const r = erff_pp0 + z * (erff_pp1 + z * (erff_pp2 + z * (erff_pp3 + z * erff_pp4)));
        const s = 1 + z * (erff_qq1 + z * (erff_qq2 + z * (erff_qq3 + z * (erff_qq4 + z * erff_qq5))));
        const y = r / s;
        return x + x * y;
    }
    
    var y: f32 = undefined;
    if (ix < 0x40c00000) { // |x| < 6
        y = 1 - erff_erfc2(ix, x);
    } else {
        y = 1 - 0x1p-120;
    }
    
    return if (sign != 0) -y else y;
}

fn erfcf_(x: f32) callconv(.c) f32 {
    // GET_FLOAT_WORD equivalent
    const ix_raw: u32 = @bitCast(x);
    const sign = ix_raw >> 31;
    const ix = ix_raw & 0x7fffffff;
    
    if (ix >= 0x7f800000) {
        // erfc(nan)=nan, erfc(+-inf)=0,2
        return @as(f32, @floatFromInt(2 * @as(i32, @intCast(sign)))) + 1 / x;
    }
    
    if (ix < 0x3f580000) { // |x| < 0.84375
        if (ix < 0x23800000) // |x| < 2**-56
            return 1.0 - x;
        const z = x * x;
        const r = erff_pp0 + z * (erff_pp1 + z * (erff_pp2 + z * (erff_pp3 + z * erff_pp4)));
        const s = 1.0 + z * (erff_qq1 + z * (erff_qq2 + z * (erff_qq3 + z * (erff_qq4 + z * erff_qq5))));
        const y = r / s;
        if (sign != 0 or ix < 0x3e800000) { // x < 1/4
            return 1.0 - (x + x * y);
        }
        return 0.5 - (x - 0.5 + x * y);
    }
    
    if (ix < 0x41e00000) { // |x| < 28
        return if (sign != 0) 2 - erff_erfc2(ix, x) else erff_erfc2(ix, x);
    }
    
    return if (sign != 0) 2 - 0x1p-120 else 0x1p-120 * 0x1p-120;
}

fn nexttoward(x: f64, y: c_longdouble) callconv(.c) f64 {
    var ux: u64 = @bitCast(x);

    if (math.isNan(x) or math.isNan(y)) return x + @as(f64, @floatCast(y));

    const xld: c_longdouble = @floatCast(x);
    if (xld == y) return @floatCast(y);

    const ax = ux & (math.maxInt(u64) >> 1);
    if (ax == 0) {
        ux = 1;
        if (math.copysign(@as(c_longdouble, 1.0), y) < 0) {
            ux |= @as(u64, 1) << 63;
        }
    } else if ((xld < y) == (ux < (@as(u64, 1) << 63))) {
        ux += 1;
    } else {
        ux -= 1;
    }
    const e: u32 = @truncate((ux >> 52) & 0x7ff);
    if (e == 0x7ff) {
        mem.doNotOptimizeAway(x + x);
    }
    if (e == 0) {
        const val: f64 = @bitCast(ux);
        mem.doNotOptimizeAway(val * val);
    }
    return @bitCast(ux);
}

fn scalb(x: f64, fn_: f64) callconv(.c) f64 {
    if (math.isNan(x) or math.isNan(fn_)) return x * fn_;
    if (!math.isFinite(fn_)) {
        if (fn_ > 0.0) return x * fn_;
        return x / (-fn_);
    }
    if (rint(fn_) != fn_) return (fn_ - fn_) / (fn_ - fn_);
    if (fn_ > 65000.0) return math.scalbn(x, 65000);
    if (-fn_ > 65000.0) return math.scalbn(x, -65000);
    const n: i32 = @intFromFloat(fn_);
    return math.scalbn(x, n);
}
