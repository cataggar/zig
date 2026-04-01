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
        symbol(&asin, "asin");
        symbol(&atan, "atan");
        symbol(&atanf, "atanf");
        symbol(&atanl, "atanl");
        symbol(&cbrt, "cbrt");
        symbol(&cbrtf, "cbrtf");
        symbol(&cosh, "cosh");
        symbol(&erf_, "erf");
        symbol(&erfc_, "erfc");
        symbol(&erff_, "erff");
        symbol(&erfcf_, "erfcf");
        symbol(&erfl_, "erfl");
        symbol(&erfcl_, "erfcl");
        symbol(&exp10, "exp10");
        symbol(&exp10f, "exp10f");
        symbol(&hypot, "hypot");
        symbol(&modf, "modf");
        symbol(&pow, "pow");
        symbol(&pow10, "pow10");
        symbol(&pow10f, "pow10f");
        symbol(&tanh, "tanh");
        symbol(&tgamma_, "tgamma");
        symbol(&tgammaf_, "tgammaf");
        symbol(&tgammal_, "tgammal");
    }

    if (builtin.target.isMuslLibC()) {
        symbol(&copysign, "copysign");
        symbol(&copysignf, "copysignf");
        symbol(&rint, "rint");
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

// Gamma function implementations
fn tgamma_(x: f64) callconv(.c) f64 {
    return math.gamma(f64, x);
}

fn tgammaf_(x: f32) callconv(.c) f32 {
    return math.gamma(f32, x);
}

fn tgammal_(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(@TypeOf(x)).float.bits) {
        16 => math.gamma(f16, @as(f16, @floatCast(x))),
        32 => math.gamma(f32, @as(f32, @floatCast(x))),
        64 => math.gamma(f64, @as(f64, @floatCast(x))),
        80 => math.gamma(f80, @as(f80, @floatCast(x))),
        128 => math.gamma(f128, @as(f128, @floatCast(x))),
        else => unreachable,
    };
}

// Error function implementations - ported from musl erf.c, erff.c, erfl.c

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

fn erfl_(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(@TypeOf(x)).float.bits) {
        16 => erf_(@as(f64, @floatCast(x))),
        32 => erff_(@as(f32, @floatCast(x))),
        64 => erf_(@as(f64, @floatCast(x))),
        80, 128 => erf_(@as(f64, @floatCast(x))), // fallback to f64 for long double
        else => unreachable,
    };
}

fn erfcl_(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(@TypeOf(x)).float.bits) {
        16 => erfc_(@as(f64, @floatCast(x))),
        32 => erfcf_(@as(f32, @floatCast(x))),
        64 => erfc_(@as(f64, @floatCast(x))),
        80, 128 => erfc_(@as(f64, @floatCast(x))), // fallback to f64 for long double
        else => unreachable,
    };
}
