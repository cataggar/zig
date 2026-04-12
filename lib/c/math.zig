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
        symbol(&fdim, "fdim");
        symbol(&finite, "finite");
        symbol(&finitef, "finitef");
        symbol(&frexp, "frexp");
        symbol(&hypot, "hypot");
        symbol(&lrint, "lrint");
        symbol(&lrintf, "lrintf");
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
        symbol(&tanh, "tanh");
        symbol(&tanl, "tanl");
    }

    if (builtin.target.isMuslLibC()) {
        symbol(&copysign, "copysign");
        symbol(&copysignf, "copysignf");
        symbol(&finitef, "finitef");
        symbol(&rint, "rint");
        symbol(&rintf, "rintf");
        symbol(&scalbf, "scalbf");
        symbol(&significandf, "significandf");
    }
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

fn lrint(x: f64) callconv(.c) c_long {
    return @intFromFloat(rint(x));
}

fn lrintf(x: f32) callconv(.c) c_long {
    return @intFromFloat(rintf(x));
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
}
