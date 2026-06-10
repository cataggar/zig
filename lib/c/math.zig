const builtin = @import("builtin");

const std = @import("std");
const math = std.math;
const ld = math.long_double;

const symbol = @import("../c.zig").symbol;

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
        symbol(&lrintl, "lrintl");
        symbol(&modfl, "modfl");
        symbol(&rintl, "rintl");
    }

    if ((builtin.target.isMinGW() and @sizeOf(f64) != @sizeOf(c_longdouble)) or builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&atanl, "atanl");
        symbol(&copysignl, "copysignl");
        symbol(&fdiml, "fdiml");
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
        symbol(&asin, "asin");
        symbol(&atan, "atan");
        symbol(&cbrt, "cbrt");
        symbol(&cbrtf, "cbrtf");
        symbol(&cosh, "cosh");
        symbol(&exp10, "exp10");
        symbol(&exp10f, "exp10f");
        symbol(&fdim, "fdim");
        symbol(&fdimf, "fdimf");
        symbol(&finite, "finite");
        symbol(&finitef, "finitef");
        symbol(&frexp, "frexp");
        symbol(&hypot, "hypot");
        symbol(&lrint, "lrint");
        symbol(&lrintf, "lrintf");
        symbol(&modf, "modf");
        symbol(&nan, "nan");
        symbol(&nanf, "nanf");
        symbol(&pow10, "pow10");
        symbol(&pow10f, "pow10f");
        symbol(&powf, "powf");
        symbol(&tanh, "tanh");
    }

    if (builtin.target.isMuslLibC()) {
        symbol(&copysign, "copysign");
        symbol(&copysignf, "copysignf");
        symbol(&rint, "rint");
        symbol(&rintf, "rintf");
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
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => std.c.atan(x),
        else => math.atan(x),
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
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => std.c.copysign(x, y),
        else => math.copysign(x, y),
    };
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

fn fdimGeneric(comptime T: type, x: T, y: T) T {
    if (math.isNan(x))
        return x;

    if (math.isNan(y))
        return y;

    if (x > y)
        return x - y;
    return 0;
}

fn fdim(x: f64, y: f64) callconv(.c) f64 {
    return fdimGeneric(f64, x, y);
}

fn fdimf(x: f32, y: f32) callconv(.c) f32 {
    return fdimGeneric(f32, x, y);
}

fn fdiml(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => std.c.fdim(x, y),
        else => fdimGeneric(c_longdouble, x, y),
    };
}

fn finite(x: f64) callconv(.c) c_int {
    return @intFromBool(math.isFinite(x));
}

fn finitef(x: f32) callconv(.c) c_int {
    return @intFromBool(math.isFinite(x));
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
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => std.c.frexp(x, e),
        else => frexpGeneric(c_longdouble, x, e),
    };
}

fn hypot(x: f64, y: f64) callconv(.c) f64 {
    return math.hypot(x, y);
}

fn hypotf(x: f32, y: f32) callconv(.c) f32 {
    return math.hypot(x, y);
}

fn hypotl(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => std.c.hypot(x, y),
        else => math.hypot(x, y),
    };
}

fn isnan(x: f64) callconv(.c) c_int {
    return @intFromBool(math.isNan(x));
}

fn isnanf(x: f32) callconv(.c) c_int {
    return @intFromBool(math.isNan(x));
}

fn isnanl(x: c_longdouble) callconv(.c) c_int {
    return @intFromBool(math.isNan(x));
}

fn lrint(x: f64) callconv(.c) c_long {
    return @trunc(rint(x));
}

fn lrintf(x: f32) callconv(.c) c_long {
    return @trunc(rintf(x));
}

fn lrintl(x: c_longdouble) callconv(.c) c_long {
    return @trunc(rintl(x));
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
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => std.c.modf(x, iptr),
        else => modfGeneric(c_longdouble, x, iptr),
    };
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

fn pow10(x: f64) callconv(.c) f64 {
    return exp10(x);
}

fn pow10f(x: f32) callconv(.c) f32 {
    return exp10f(x);
}

/// Port of musl powf — IEEE 754 conformant single-precision power function.
fn powf(x: f32, y: f32) callconv(.c) f32 {
    return powf_impl.call(x, y);
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

fn rintl(x: c_longdouble) callconv(.c) c_longdouble {
    if (@typeInfo(c_longdouble).float.bits == 64)
        return rint(x);

    const toint: c_longdouble = 1 << math.floatFractionalBits(c_longdouble);
    const se = ld.signExponent(x);

    if (se & 0x7fff >= 0x3fff + math.floatFractionalBits(c_longdouble))
        return x;

    var y: c_longdouble = undefined;
    if ((se >> 15) == 1) {
        y = x - toint + toint;
    } else {
        y = x + toint - toint;
    }

    if (y == 0)
        return 0 * x;
    return y;
}

fn tanh(x: f64) callconv(.c) f64 {
    return math.tanh(x);
}

fn tanhf(x: f32) callconv(.c) f32 {
    return math.tanh(x);
}
