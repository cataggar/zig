const builtin = @import("builtin");
const std = @import("std");
const math = std.math;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;
const expectApproxEqRel = std.testing.expectApproxEqRel;
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
        const y0_val = logc + k;

        // Pipelined polynomial evaluation to approximate log1p(r)/ln2.
        const r2 = r * r;
        var yy = A[0] * r + A[1];
        const p = A[2] * r + A[3];
        const r4 = r2 * r2;
        var q = A[4] * r + y0_val;
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
const maxInt = std.math.maxInt;
const minInt = std.math.minInt;
var __signgam: c_int = 0;
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
const erfl_erx: f80 = 0.845062911510467529296875;
const erfl_efx8: f80 = 1.0270333367641005911692712249723613735048E0;
const erfl_pp = [6]f80{
    1.122751350964552113068262337278335028553E6,
    -2.808533301997696164408397079650699163276E6,
    -3.314325479115357458197119660818768924100E5,
    -6.848684465326256109712135497895525446398E4,
    -2.657817695110739185591505062971929859314E3,
    -1.655310302737837556654146291646499062882E2,
};
const erfl_qq = [6]f80{
    8.745588372054466262548908189000448124232E6,
    3.746038264792471129367533128637019611485E6,
    7.066358783162407559861156173539693900031E5,
    7.448928604824620999413120955705448117056E4,
    4.511583986730994111992253980546131408924E3,
    1.368902937933296323345610240009071254014E2,
};
const erfl_pa = [8]f80{
    -1.076952146179812072156734957705102256059E0,
    1.884814957770385593365179835059971587220E2,
    -5.339153975012804282890066622962070115606E1,
    4.435910679869176625928504532109635632618E1,
    1.683219516032328828278557309642929135179E1,
    -2.360236618396952560064259585299045804293E0,
    1.852230047861891953244413872297940938041E0,
    9.394994446747752308256773044667843200719E-2,
};
const erfl_qa = [7]f80{
    4.559263722294508998149925774781887811255E2,
    3.289248982200800575749795055149780689738E2,
    2.846070965875643009598627918383314457912E2,
    1.398715859064535039433275722017479994465E2,
    6.060190733759793706299079050985358190726E1,
    2.078695677795422351040502569964299664233E1,
    4.641271134150895940966798357442234498546E0,
};
const erfl_ra = [9]f80{
    1.363566591833846324191000679620738857234E-1,
    1.018203167219873573808450274314658434507E1,
    1.862359362334248675526472871224778045594E2,
    1.411622588180721285284945138667933330348E3,
    5.088538459741511988784440103218342840478E3,
    8.928251553922176506858267311750789273656E3,
    7.264436000148052545243018622742770549982E3,
    2.387492459664548651671894725748959751119E3,
    2.220916652813908085449221282808458466556E2,
};
const erfl_sa = [9]f80{
    -1.382234625202480685182526402169222331847E1,
    -3.315638835627950255832519203687435946482E2,
    -2.949124863912936259747237164260785326692E3,
    -1.246622099070875940506391433635999693661E4,
    -2.673079795851665428695842853070996219632E4,
    -2.880269786660559337358397106518918220991E4,
    -1.450600228493968044773354186390390823713E4,
    -2.874539731125893533960680525192064277816E3,
    -1.402241261419067750237395034116942296027E2,
};
const erfl_rb = [8]f80{
    -4.869587348270494309550558460786501252369E-5,
    -4.030199390527997378549161722412466959403E-3,
    -9.434425866377037610206443566288917589122E-2,
    -9.319032754357658601200655161585539404155E-1,
    -4.273788174307459947350256581445442062291E0,
    -8.842289940696150508373541814064198259278E0,
    -7.069215249419887403187988144752613025255E0,
    -1.401228723639514787920274427443330704764E0,
};
const erfl_sb = [7]f80{
    4.936254964107175160157544545879293019085E-3,
    1.583457624037795744377163924895349412015E-1,
    1.850647991850328356622940552450636420484E0,
    9.927611557279019463768050710008450625415E0,
    2.531667257649436709617165336779212114570E1,
    2.869752886406743386458304052862814690045E1,
    1.182059497870819562441683560749192539345E1,
};
const erfl_rc = [6]f80{
    -8.299617545269701963973537248996670806850E-5,
    -6.243845685115818513578933902532056244108E-3,
    -1.141667210620380223113693474478394397230E-1,
    -7.521343797212024245375240432734425789409E-1,
    -1.765321928311155824664963633786967602934E0,
    -1.029403473103215800456761180695263439188E0,
};
const erfl_sc = [5]f80{
    8.413244363014929493035952542677768808601E-3,
    2.065114333816877479753334599639158060979E-1,
    1.639064941530797583766364412782135680148E0,
    4.936788463787115555582319302981666347450E0,
    5.005177727208955487404729933261347679090E0,
};
const mem = std.mem;
// lgamma_r f64 polynomial coefficients
const lg_pi: f64 = 3.14159265358979311600e+00; // 0x400921FB, 0x54442D18
const lg_a0: f64 = 7.72156649015328655494e-02; // 0x3FB3C467, 0xE37DB0C8
const lg_a1: f64 = 3.22467033424113591611e-01; // 0x3FD4A34C, 0xC4A60FAD
const lg_a2: f64 = 6.73523010531292681824e-02; // 0x3FB13E00, 0x1A5562A7
const lg_a3: f64 = 2.05808084325167332806e-02; // 0x3F951322, 0xAC92547B
const lg_a4: f64 = 7.38555086081402883957e-03; // 0x3F7E404F, 0xB68FEFE8
const lg_a5: f64 = 2.89051383673415629091e-03; // 0x3F67ADD8, 0xCCB7926B
const lg_a6: f64 = 1.19270763183362067845e-03; // 0x3F538A94, 0x116F3F5D
const lg_a7: f64 = 5.10069792153511336608e-04; // 0x3F40B6C6, 0x89B99C00
const lg_a8: f64 = 2.20862790713908385557e-04; // 0x3F2CF2EC, 0xED10E54D
const lg_a9: f64 = 1.08011567247583939954e-04; // 0x3F1C5088, 0x987DFB07
const lg_a10: f64 = 2.52144565451257326939e-05; // 0x3EFA7074, 0x428CFA52
const lg_a11: f64 = 4.48640949618915160150e-05; // 0x3F07858E, 0x90A45837
const lg_tc: f64 = 1.46163214496836224576e+00; // 0x3FF762D8, 0x6356BE3F
const lg_tf: f64 = -1.21486290535849611461e-01; // 0xBFBF19B9, 0xBCC38A42
const lg_tt: f64 = -3.63867699703950536541e-18; // 0xBC50C7CA, 0xA48A971F
const lg_t0: f64 = 4.83836122723810047042e-01; // 0x3FDEF72B, 0xC8EE38A2
const lg_t1: f64 = -1.47587722994593911752e-01; // 0xBFC2E427, 0x8DC6C509
const lg_t2: f64 = 6.46249402391333854778e-02; // 0x3FB08B42, 0x94D5419B
const lg_t3: f64 = -3.27885410759859649565e-02; // 0xBFA0C9A8, 0xDF35B713
const lg_t4: f64 = 1.79706750811820387126e-02; // 0x3F9266E7, 0x970AF9EC
const lg_t5: f64 = -1.03142241298341437450e-02; // 0xBF851F9F, 0xBA91EC6A
const lg_t6: f64 = 6.10053870246291332635e-03; // 0x3F78FCE0, 0xE370E344
const lg_t7: f64 = -3.68452016781138256760e-03; // 0xBF6E2EFF, 0xB3E914D7
const lg_t8: f64 = 2.25964780900612472250e-03; // 0x3F6282D3, 0x2E15C915
const lg_t9: f64 = -1.40346469989232843813e-03; // 0xBF56FE8E, 0xBF2D1AF1
const lg_t10: f64 = 8.81081882437654011382e-04; // 0x3F4CDF0C, 0xEF61A8E9
const lg_t11: f64 = -5.38595305356740546715e-04; // 0xBF41A610, 0x9C73E0EC
const lg_t12: f64 = 3.15632070903625950361e-04; // 0x3F34AF6D, 0x6C0EBBF7
const lg_t13: f64 = -3.12754168375120860518e-04; // 0xBF347F24, 0xECC38C38
const lg_t14: f64 = 3.35529192635519073543e-04; // 0x3F35FD3E, 0xE8C2D3F4
const lg_u0: f64 = -7.72156649015328655494e-02; // 0xBFB3C467, 0xE37DB0C8
const lg_u1: f64 = 6.32827064025093366517e-01; // 0x3FE4401E, 0x8B005DFF
const lg_u2: f64 = 1.45492250137234768737e+00; // 0x3FF7475C, 0xD119BD6F
const lg_u3: f64 = 9.77717527963372745603e-01; // 0x3FEF4976, 0x44EA8450
const lg_u4: f64 = 2.28963728064692451092e-01; // 0x3FCD4EAE, 0xF6010924
const lg_u5: f64 = 1.33810918536787660377e-02; // 0x3F8B678B, 0xBF2BAB09
const lg_v1: f64 = 2.45597793713041134822e+00; // 0x4003A5D7, 0xC2BD619C
const lg_v2: f64 = 2.12848976379893395361e+00; // 0x40010725, 0xA42B18F5
const lg_v3: f64 = 7.69285150456672783825e-01; // 0x3FE89DFB, 0xE45050AF
const lg_v4: f64 = 1.04222645593369134254e-01; // 0x3FBAAE55, 0xD6537C88
const lg_v5: f64 = 3.21709242282423911810e-03; // 0x3F6A5ABB, 0x57D0CF61
const lg_s0: f64 = -7.72156649015328655494e-02; // 0xBFB3C467, 0xE37DB0C8
const lg_s1: f64 = 2.14982415960608852501e-01; // 0x3FCB848B, 0x36E20878
const lg_s2: f64 = 3.25778796408930981787e-01; // 0x3FD4D98F, 0x4F139F59
const lg_s3: f64 = 1.46350472652464452805e-01; // 0x3FC2BB9C, 0xBEE5F2F7
const lg_s4: f64 = 2.66422703033638609560e-02; // 0x3F9B481C, 0x7E939961
const lg_s5: f64 = 1.84028451407337715652e-03; // 0x3F5E26B6, 0x7368F239
const lg_s6: f64 = 3.19475326584100867617e-05; // 0x3F00BFEC, 0xDD17E945
const lg_r1: f64 = 1.39200533467621045958e+00; // 0x3FF645A7, 0x62C4AB74
const lg_r2: f64 = 7.21935547567138069525e-01; // 0x3FE71A18, 0x93D3DCDC
const lg_r3: f64 = 1.71933865632803078993e-01; // 0x3FC601ED, 0xCCFBDF27
const lg_r4: f64 = 1.86459191715652901344e-02; // 0x3F9317EA, 0x742ED475
const lg_r5: f64 = 7.77942496381893596434e-04; // 0x3F497DDA, 0xCA41A95B
const lg_r6: f64 = 7.32668430744625636189e-06; // 0x3EDEBAF7, 0xA5B38140
const lg_w0: f64 = 4.18938533204672725052e-01; // 0x3FDACFE3, 0x90C97D69
const lg_w1: f64 = 8.33333333333329678849e-02; // 0x3FB55555, 0x5555553B
const lg_w2: f64 = -2.77777777728775536470e-03; // 0xBF66C16C, 0x16B02E5C
const lg_w3: f64 = 7.93650558643019558500e-04; // 0x3F4A019F, 0x98CF38B6
const lg_w4: f64 = -5.95187557450339963135e-04; // 0xBF4380CB, 0x8C0FE741
const lg_w5: f64 = 8.36339918996282139126e-04; // 0x3F4B67BA, 0x4CDAD5D1
const lg_w6: f64 = -1.63092934096575273989e-03; // 0xBF5AB89D, 0x0B9E43E4

/// sin(pi*x) assuming x > 2^-100, if sin(pi*x)==0 the sign is arbitrary
fn sin_pi64(x_: f64) f64 {
    var x = x_;
    x = 2.0 * (x * 0.5 - @floor(x * 0.5)); // x mod 2.0
    var n: usize = @intFromFloat(x * 4.0);
    n = (n + 1) / 2;
    x -= @as(f64, @floatFromInt(n)) * 0.5;
    x *= lg_pi;
    return switch (n) {
        0, 4 => @sin(x),
        1 => @cos(x),
        2 => @sin(-x),
        3 => -@cos(x),
        else => unreachable,
    };
}

fn lgamma_r(x_: f64, signgamp: *c_int) callconv(.c) f64 {
    const u: u64 = @bitCast(x_);
    const ix: u32 = @truncate(u >> 32);
    const ix_abs = ix & 0x7fffffff;
    const sign: bool = (u >> 63) != 0;

    var x = x_;
    var r: f64 = undefined;
    var nadj: f64 = undefined;

    // purge off +-inf, NaN, +-0, tiny and negative arguments
    signgamp.* = 1;
    if (ix_abs >= 0x7ff00000)
        return x * x;
    if (ix_abs < (0x3ff - 70) << 20) { // |x|<2**-70, return -log(|x|)
        if (sign) {
            x = -x;
            signgamp.* = -1;
        }
        return -@log(x);
    }
    if (sign) {
        x = -x;
        const t = sin_pi64(x);
        if (t == 0.0) // -integer
            return 1.0 / (x - x);
        if (t > 0.0)
            signgamp.* = -1;
        nadj = @log(lg_pi / (@abs(t) * x));
    }

    // purge off 1 and 2
    if ((ix_abs == 0x3ff00000 or ix_abs == 0x40000000) and @as(u32, @truncate(u)) == 0) {
        r = 0;
    } else if (ix_abs < 0x40000000) {
        // for x < 2.0
        var y: f64 = undefined;
        var i: u32 = undefined;
        if (ix_abs <= 0x3feccccc) { // lgamma(x) = lgamma(x+1)-log(x)
            r = -@log(x);
            if (ix_abs >= 0x3FE76944) {
                y = 1.0 - x;
                i = 0;
            } else if (ix_abs >= 0x3FCDA661) {
                y = x - (lg_tc - 1.0);
                i = 1;
            } else {
                y = x;
                i = 2;
            }
        } else {
            r = 0.0;
            if (ix_abs >= 0x3FFBB4C3) { // [1.7316,2]
                y = 2.0 - x;
                i = 0;
            } else if (ix_abs >= 0x3FF3B4C4) { // [1.23,1.73]
                y = x - lg_tc;
                i = 1;
            } else {
                y = x - 1.0;
                i = 2;
            }
        }
        switch (i) {
            0 => {
                const z = y * y;
                const p1 = lg_a0 + z * (lg_a2 + z * (lg_a4 + z * (lg_a6 + z * (lg_a8 + z * lg_a10))));
                const p2 = z * (lg_a1 + z * (lg_a3 + z * (lg_a5 + z * (lg_a7 + z * (lg_a9 + z * lg_a11)))));
                const p = y * p1 + p2;
                r += (p - 0.5 * y);
            },
            1 => {
                const z = y * y;
                const w = z * y;
                const p1 = lg_t0 + w * (lg_t3 + w * (lg_t6 + w * (lg_t9 + w * lg_t12)));
                const p2 = lg_t1 + w * (lg_t4 + w * (lg_t7 + w * (lg_t10 + w * lg_t13)));
                const p3 = lg_t2 + w * (lg_t5 + w * (lg_t8 + w * (lg_t11 + w * lg_t14)));
                const p = z * p1 - (lg_tt - w * (p2 + y * p3));
                r += lg_tf + p;
            },
            2 => {
                const p1 = y * (lg_u0 + y * (lg_u1 + y * (lg_u2 + y * (lg_u3 + y * (lg_u4 + y * lg_u5)))));
                const p2 = 1.0 + y * (lg_v1 + y * (lg_v2 + y * (lg_v3 + y * (lg_v4 + y * lg_v5))));
                r += -0.5 * y + p1 / p2;
            },
            else => unreachable,
        }
    } else if (ix_abs < 0x40200000) { // x < 8.0
        const i: usize = @intFromFloat(x);
        const y = x - @as(f64, @floatFromInt(i));
        const p = y * (lg_s0 + y * (lg_s1 + y * (lg_s2 + y * (lg_s3 + y * (lg_s4 + y * (lg_s5 + y * lg_s6))))));
        const q = 1.0 + y * (lg_r1 + y * (lg_r2 + y * (lg_r3 + y * (lg_r4 + y * (lg_r5 + y * lg_r6)))));
        r = 0.5 * y + p / q;
        // lgamma(1+s) = log(s) + lgamma(s)
        if (i >= 3) {
            var z: f64 = 1.0;
            var j: usize = i;
            while (j >= 3) : (j -= 1) {
                z *= y + @as(f64, @floatFromInt(j)) - 1.0;
            }
            r += @log(z);
        }
    } else if (ix_abs < 0x43900000) { // 8.0 <= x < 2**58
        const t = @log(x);
        const z = 1.0 / x;
        const y = z * z;
        const w = lg_w0 + z * (lg_w1 + y * (lg_w2 + y * (lg_w3 + y * (lg_w4 + y * (lg_w5 + y * lg_w6)))));
        r = (x - 0.5) * (t - 1.0) + w;
    } else {
        // 2**58 <= x <= inf
        r = x * (@log(x) - 1.0);
    }
    if (sign)
        r = nadj - r;
    return r;
}

fn lgamma_(x: f64) callconv(.c) f64 {
    return lgamma_r(x, &__signgam);
}

// =========================================================================
// lgammaf — float version
// Ported from musl libc (origin: FreeBSD /usr/src/lib/msun/src/e_lgammaf_r.c)
// =========================================================================

// lgammaf_r f32 polynomial coefficients
const lgf_pi: f32 = 3.1415927410e+00; // 0x40490fdb
const lgf_a0: f32 = 7.7215664089e-02; // 0x3d9e233f
const lgf_a1: f32 = 3.2246702909e-01; // 0x3ea51a66
const lgf_a2: f32 = 6.7352302372e-02; // 0x3d89f001
const lgf_a3: f32 = 2.0580807701e-02; // 0x3ca89915
const lgf_a4: f32 = 7.3855509982e-03; // 0x3bf2027e
const lgf_a5: f32 = 2.8905137442e-03; // 0x3b3d6ec6
const lgf_a6: f32 = 1.1927076848e-03; // 0x3a9c54a1
const lgf_a7: f32 = 5.1006977446e-04; // 0x3a05b634
const lgf_a8: f32 = 2.2086278477e-04; // 0x39679767
const lgf_a9: f32 = 1.0801156895e-04; // 0x38e28445
const lgf_a10: f32 = 2.5214456400e-05; // 0x37d383a2
const lgf_a11: f32 = 4.4864096708e-05; // 0x383c2c75
const lgf_tc: f32 = 1.4616321325e+00; // 0x3fbb16c3
const lgf_tf: f32 = -1.2148628384e-01; // 0xbdf8cdcd
const lgf_tt: f32 = 6.6971006518e-09; // 0x31e61c52
const lgf_t0: f32 = 4.8383611441e-01; // 0x3ef7b95e
const lgf_t1: f32 = -1.4758771658e-01; // 0xbe17213c
const lgf_t2: f32 = 6.4624942839e-02; // 0x3d845a15
const lgf_t3: f32 = -3.2788541168e-02; // 0xbd064d47
const lgf_t4: f32 = 1.7970675603e-02; // 0x3c93373d
const lgf_t5: f32 = -1.0314224288e-02; // 0xbc28fcfe
const lgf_t6: f32 = 6.1005386524e-03; // 0x3bc7e707
const lgf_t7: f32 = -3.6845202558e-03; // 0xbb7177fe
const lgf_t8: f32 = 2.2596477065e-03; // 0x3b141699
const lgf_t9: f32 = -1.4034647029e-03; // 0xbab7f476
const lgf_t10: f32 = 8.8108185446e-04; // 0x3a66f867
const lgf_t11: f32 = -5.3859531181e-04; // 0xba0d3085
const lgf_t12: f32 = 3.1563205994e-04; // 0x39a57b6b
const lgf_t13: f32 = -3.1275415677e-04; // 0xb9a3f927
const lgf_t14: f32 = 3.3552918467e-04; // 0x39afe9f7
const lgf_u0: f32 = -7.7215664089e-02; // 0xbd9e233f
const lgf_u1: f32 = 6.3282704353e-01; // 0x3f2200f4
const lgf_u2: f32 = 1.4549225569e+00; // 0x3fba3ae7
const lgf_u3: f32 = 9.7771751881e-01; // 0x3f7a4bb2
const lgf_u4: f32 = 2.2896373272e-01; // 0x3e6a7578
const lgf_u5: f32 = 1.3381091878e-02; // 0x3c5b3c5e
const lgf_v1: f32 = 2.4559779167e+00; // 0x401d2ebe
const lgf_v2: f32 = 2.1284897327e+00; // 0x4008392d
const lgf_v3: f32 = 7.6928514242e-01; // 0x3f44efdf
const lgf_v4: f32 = 1.0422264785e-01; // 0x3dd572af
const lgf_v5: f32 = 3.2170924824e-03; // 0x3b52d5db
const lgf_s0: f32 = -7.7215664089e-02; // 0xbd9e233f
const lgf_s1: f32 = 2.1498242021e-01; // 0x3e5c245a
const lgf_s2: f32 = 3.2577878237e-01; // 0x3ea6cc7a
const lgf_s3: f32 = 1.4635047317e-01; // 0x3e15dce6
const lgf_s4: f32 = 2.6642270386e-02; // 0x3cda40e4
const lgf_s5: f32 = 1.8402845599e-03; // 0x3af135b4
const lgf_s6: f32 = 3.1947532989e-05; // 0x3805ff67
const lgf_r1: f32 = 1.3920053244e+00; // 0x3fb22d3b
const lgf_r2: f32 = 7.2193557024e-01; // 0x3f38d0c5
const lgf_r3: f32 = 1.7193385959e-01; // 0x3e300f6e
const lgf_r4: f32 = 1.8645919859e-02; // 0x3c98bf54
const lgf_r5: f32 = 7.7794247773e-04; // 0x3a4beed6
const lgf_r6: f32 = 7.3266842264e-06; // 0x36f5d7bd
const lgf_w0: f32 = 4.1893854737e-01; // 0x3ed67f1d
const lgf_w1: f32 = 8.3333335817e-02; // 0x3daaaaab
const lgf_w2: f32 = -2.7777778450e-03; // 0xbb360b61
const lgf_w3: f32 = 7.9365057172e-04; // 0x3a500cfd
const lgf_w4: f32 = -5.9518753551e-04; // 0xba1c065c
const lgf_w5: f32 = 8.3633989561e-04; // 0x3a5b3dd2
const lgf_w6: f32 = -1.6309292987e-03; // 0xbad5c4e8

/// sin(pi*x) for float, assuming x > 2^-100
fn sin_pi32(x_: f64) f32 {
    var y: f64 = undefined;
    var x = x_;
    x = 2.0 * (x * 0.5 - @floor(x * 0.5)); // x mod 2.0
    var n: usize = @intFromFloat(x * 4.0);
    n = (n + 1) / 2;
    y = x - @as(f64, @floatFromInt(n)) * 0.5;
    y *= 3.14159265358979323846;
    const result: f64 = switch (n) {
        0, 4 => @sin(y),
        1 => @cos(y),
        2 => @sin(-y),
        3 => -@cos(y),
        else => unreachable,
    };
    return @floatCast(result);
}

fn lgammaf_r(x_: f32, signgamp: *c_int) callconv(.c) f32 {
    const u: u32 = @bitCast(x_);
    const ix: u32 = u & 0x7fffffff;
    const sign_bit: bool = (u >> 31) != 0;

    var x: f32 = x_;
    var r: f32 = undefined;
    var nadj: f32 = undefined;

    // purge off +-inf, NaN, +-0, tiny and negative arguments
    signgamp.* = 1;
    if (ix >= 0x7f800000)
        return x * x;
    if (ix < 0x35000000) { // |x| < 2**-21, return -log(|x|)
        if (sign_bit) {
            signgamp.* = -1;
            x = -x;
        }
        return -@log(x);
    }
    if (sign_bit) {
        x = -x;
        const t = sin_pi32(x);
        if (t == 0.0) // -integer
            return 1.0 / (x - x);
        if (t > 0.0)
            signgamp.* = -1;
        nadj = @log(lgf_pi / (@abs(t) * x));
    }

    // purge off 1 and 2
    if (ix == 0x3f800000 or ix == 0x40000000) {
        r = 0;
    } else if (ix < 0x40000000) {
        // for x < 2.0
        var y: f32 = undefined;
        var i: u32 = undefined;
        if (ix <= 0x3f666666) { // lgamma(x) = lgamma(x+1)-log(x)
            r = -@log(x);
            if (ix >= 0x3f3b4a20) {
                y = 1.0 - x;
                i = 0;
            } else if (ix >= 0x3e6d3308) {
                y = x - (lgf_tc - 1.0);
                i = 1;
            } else {
                y = x;
                i = 2;
            }
        } else {
            r = 0.0;
            if (ix >= 0x3fdda618) { // [1.7316,2]
                y = 2.0 - x;
                i = 0;
            } else if (ix >= 0x3F9da620) { // [1.23,1.73]
                y = x - lgf_tc;
                i = 1;
            } else {
                y = x - 1.0;
                i = 2;
            }
        }
        switch (i) {
            0 => {
                const z = y * y;
                const p1 = lgf_a0 + z * (lgf_a2 + z * (lgf_a4 + z * (lgf_a6 + z * (lgf_a8 + z * lgf_a10))));
                const p2 = z * (lgf_a1 + z * (lgf_a3 + z * (lgf_a5 + z * (lgf_a7 + z * (lgf_a9 + z * lgf_a11)))));
                const p = y * p1 + p2;
                r += p - 0.5 * y;
            },
            1 => {
                const z = y * y;
                const w = z * y;
                const p1 = lgf_t0 + w * (lgf_t3 + w * (lgf_t6 + w * (lgf_t9 + w * lgf_t12)));
                const p2 = lgf_t1 + w * (lgf_t4 + w * (lgf_t7 + w * (lgf_t10 + w * lgf_t13)));
                const p3 = lgf_t2 + w * (lgf_t5 + w * (lgf_t8 + w * (lgf_t11 + w * lgf_t14)));
                const p = z * p1 - (lgf_tt - w * (p2 + y * p3));
                r += (lgf_tf + p);
            },
            2 => {
                const p1 = y * (lgf_u0 + y * (lgf_u1 + y * (lgf_u2 + y * (lgf_u3 + y * (lgf_u4 + y * lgf_u5)))));
                const p2 = 1.0 + y * (lgf_v1 + y * (lgf_v2 + y * (lgf_v3 + y * (lgf_v4 + y * lgf_v5))));
                r += -0.5 * y + p1 / p2;
            },
            else => unreachable,
        }
    } else if (ix < 0x41000000) { // x < 8.0
        const i: usize = @intFromFloat(x);
        const y = x - @as(f32, @floatFromInt(i));
        const p = y * (lgf_s0 + y * (lgf_s1 + y * (lgf_s2 + y * (lgf_s3 + y * (lgf_s4 + y * (lgf_s5 + y * lgf_s6))))));
        const q = 1.0 + y * (lgf_r1 + y * (lgf_r2 + y * (lgf_r3 + y * (lgf_r4 + y * (lgf_r5 + y * lgf_r6)))));
        r = 0.5 * y + p / q;
        // lgamma(1+s) = log(s) + lgamma(s)
        if (i >= 3) {
            var z: f32 = 1.0;
            var j: usize = i;
            while (j >= 3) : (j -= 1) {
                z *= y + @as(f32, @floatFromInt(j)) - 1.0;
            }
            r += @log(z);
        }
    } else if (ix < 0x5c800000) { // 8.0 <= x < 2**58
        const t = @log(x);
        const z: f32 = 1.0 / x;
        const y = z * z;
        const w = lgf_w0 + z * (lgf_w1 + y * (lgf_w2 + y * (lgf_w3 + y * (lgf_w4 + y * (lgf_w5 + y * lgf_w6)))));
        r = (x - 0.5) * (t - 1.0) + w;
    } else {
        // 2**58 <= x <= inf
        r = x * (@log(x) - 1.0);
    }
    if (sign_bit)
        r = nadj - r;
    return r;
}

fn lgammaf_(x: f32) callconv(.c) f32 {
    return lgammaf_r(x, &__signgam);
}

fn tanh(x: f64) callconv(.c) f64 {
    return math.tanh(x);
}

fn tanhf(x: f32) callconv(.c) f32 {
    return math.tanh(x);
}

fn fpBarrierValue(comptime T: type, x: T) T {
    @setFloatMode(.strict);
    var y: T = undefined;
    const ptr: *volatile T = &y;
    ptr.* = x;
    return ptr.*;
}

fn forceEval(comptime T: type, x: T) void {
    @setFloatMode(.strict);
    var y: T = undefined;
    const ptr: *volatile T = &y;
    ptr.* = x;
}

fn __math_divzero(sign: u32) callconv(.c) f64 {
    @setFloatMode(.strict);
    return fpBarrierValue(f64, if (sign != 0) -1.0 else 1.0) / 0.0;
}

fn __math_divzerof(sign: u32) callconv(.c) f32 {
    @setFloatMode(.strict);
    return fpBarrierValue(f32, if (sign != 0) -1.0 else 1.0) / 0.0;
}

fn __math_invalid(x: f64) callconv(.c) f64 {
    @setFloatMode(.strict);
    return (x - x) / (x - x);
}

fn __math_invalidf(x: f32) callconv(.c) f32 {
    @setFloatMode(.strict);
    return (x - x) / (x - x);
}

fn __math_invalidl(x: c_longdouble) callconv(.c) c_longdouble {
    @setFloatMode(.strict);
    return (x - x) / (x - x);
}

fn __math_xflow(sign: u32, y: f64) callconv(.c) f64 {
    @setFloatMode(.strict);
    return fpBarrierValue(f64, if (sign != 0) -y else y) * y;
}

fn __math_xflowf(sign: u32, y: f32) callconv(.c) f32 {
    @setFloatMode(.strict);
    return fpBarrierValue(f32, if (sign != 0) -y else y) * y;
}

fn __math_oflow(sign: u32) callconv(.c) f64 {
    @setFloatMode(.strict);
    return __math_xflow(sign, 0x1p769);
}

fn __math_oflowf(sign: u32) callconv(.c) f32 {
    @setFloatMode(.strict);
    return __math_xflowf(sign, 0x1p97);
}

fn __math_uflow(sign: u32) callconv(.c) f64 {
    @setFloatMode(.strict);
    return __math_xflow(sign, 0x1p-767);
}

fn __math_uflowf(sign: u32) callconv(.c) f32 {
    @setFloatMode(.strict);
    return __math_xflowf(sign, 0x1p-95);
}

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
        symbol(&lroundl, "lroundl");
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
        symbol(&acosh_, "acosh");
        symbol(&acoshf, "acoshf");
        symbol(&acosl, "acosl");
        symbol(&asin, "asin");
        symbol(&asinh_, "asinh");
        symbol(&asinhf, "asinhf");
        symbol(&asinl, "asinl");
        symbol(&atan, "atan");
        symbol(&atan2l, "atan2l");
        symbol(&atanhf, "atanhf");
        symbol(&cbrt, "cbrt");
        symbol(&cbrtf, "cbrtf");
        symbol(&cbrtl_, "cbrtl");
        symbol(&cosh, "cosh");
        symbol(&cosl, "cosl");
        symbol(&erfl, "erfl");
        symbol(&erfcl, "erfcl");
        symbol(&exp10, "exp10");
        symbol(&exp10f, "exp10f");
        symbol(&exp10l, "exp10l");
        symbol(&exp2l, "exp2l");
        symbol(&expm1, "expm1");
        symbol(&expm1f, "expm1f");
        symbol(&expm1l, "expm1l");
        symbol(&fdimf, "fdimf");
        symbol(&fmaf, "fmaf");
        symbol(&fmal, "fmal");
        symbol(&hypot, "hypot");
        symbol(&ilogbf, "ilogbf");
        symbol(&ilogbl, "ilogbl");
        symbol(&j0, "j0");
        symbol(&y0, "y0");
        symbol(&j0f, "j0f");
        symbol(&y0f, "y0f");
        symbol(&j1, "j1");
        symbol(&y1, "y1");
        symbol(&j1f, "j1f");
        symbol(&y1f, "y1f");
        symbol(&jn, "jn");
        symbol(&yn, "yn");
        symbol(&jnf, "jnf");
        symbol(&ynf, "ynf");
        symbol(&ldexpf, "ldexpf");
        symbol(&ldexpl, "ldexpl");
        symbol(&lgammal_, "lgammal");
        symbol(&lgammal_r_, "__lgammal_r");
        symbol(&lgammal_r_, "lgammal_r");
        symbol(&llrintf, "llrintf");
        symbol(&llrintl, "llrintl");
        symbol(&llround, "llround");
        symbol(&llroundf, "llroundf");
        symbol(&llroundl, "llroundl");
        symbol(&log1p, "log1p");
        symbol(&log1pf, "log1pf");
        symbol(&log1pl, "log1pl");
        symbol(&lrintf, "lrintf");
        symbol(&lround, "lround");
        symbol(&lroundf, "lroundf");
        symbol(&modf, "modf");
        symbol(&nan, "nan");
        symbol(&nanf, "nanf");
        symbol(&nearbyintf, "nearbyintf");
        symbol(&nearbyintl, "nearbyintl");
        symbol(&nextafterf, "nextafterf");
        symbol(&nextafterl, "nextafterl");
        symbol(&nexttowardf, "nexttowardf");
        symbol(&nexttowardl, "nexttowardl");
        symbol(&pow, "pow");
        symbol(&pow10, "pow10");
        symbol(&pow10f, "pow10f");
        symbol(&pow10l, "pow10l");
        symbol(&sincosl, "sincosl");
        symbol(&sinh_, "sinh");
        symbol(&sinhf, "sinhf");
        symbol(&sinl, "sinl");
        symbol(&tanh, "tanh");
        symbol(&tanl, "tanl");
        symbol(&tgamma, "tgamma");
        symbol(&tgammaf, "tgammaf");
        symbol(&tgammal, "tgammal");
        symbol(&expl, "expl");
        symbol(&log10l, "log10l");
        symbol(&log2l, "log2l");
        symbol(&logbf, "logbf");
        symbol(&logbl, "logbl");
        symbol(&logl, "logl");
        symbol(&scalblnf, "scalblnf");
        symbol(&scalblnl, "scalblnl");
        symbol(&scalbnf, "scalbnf");
        symbol(&scalbnl, "scalbnl");
        symbol(&fdim, "fdim");
        symbol(&powf, "powf");
        symbol(&asinf, "asinf");
        symbol(&finite_, "finite");
        symbol(&finitef_, "finitef");
        symbol(&frexp_, "frexp");
        symbol(&ilogb_, "ilogb");
        symbol(&ldexp_, "ldexp");
        symbol(&logb_, "logb");
        symbol(&scalbln_, "scalbln");
        symbol(&scalbn_, "scalbn");
        symbol(&significand_, "significand");
        symbol(&significandf_, "significandf");
        symbol(&acoshl_, "acoshl");
        symbol(&asinhl_, "asinhl");
        symbol(&atanh_, "atanh");
        symbol(&atanhl_, "atanhl");
        symbol(&coshl_, "coshl");
        symbol(&sinhl_, "sinhl");
        symbol(&tanhl_, "tanhl");
        symbol(&remainder_, "remainder");
        symbol(&remainder_, "drem");
        symbol(&remainderf_, "remainderf");
        symbol(&remainderf_, "dremf");
        symbol(&remainderl_, "remainderl");
        symbol(&remquo_, "remquo");
        symbol(&remquof_, "remquof");
        symbol(&remquol_, "remquol");
        symbol(&erf_, "erf");
        symbol(&erfc_, "erfc");
        symbol(&erff_, "erff");
        symbol(&erfcf_, "erfcf");
        symbol(&atan2, "atan2");
        symbol(&atan2f, "atan2f");
        symbol(&fma, "fma");
        symbol(&llrint, "llrint");
        symbol(&lrint, "lrint");
        symbol(&lgamma_, "lgamma");
        symbol(&lgammaf_, "lgammaf");
        symbol(&lgamma_r, "__lgamma_r");
        symbol(&lgamma_r, "lgamma_r");
        symbol(&lgammaf_r, "__lgammaf_r");
        symbol(&lgammaf_r, "lgammaf_r");
        symbol(&powl, "powl");
    }
    if (builtin.target.isMuslLibC()) {
        symbol(&__math_divzero, "__math_divzero");
        symbol(&__math_divzerof, "__math_divzerof");
        symbol(&__math_invalid, "__math_invalid");
        symbol(&__math_invalidf, "__math_invalidf");
        symbol(&__math_invalidl, "__math_invalidl");
        symbol(&__math_oflow, "__math_oflow");
        symbol(&__math_oflowf, "__math_oflowf");
        symbol(&__math_uflow, "__math_uflow");
        symbol(&__math_uflowf, "__math_uflowf");
        symbol(&__math_xflow, "__math_xflow");
        symbol(&__math_xflowf, "__math_xflowf");
        symbol(&copysign, "copysign");
        symbol(&copysignf, "copysignf");
        symbol(&rint, "rint");
        symbol(&scalb, "scalb");
        symbol(&scalbf, "scalbf");
        symbol(&rintf, "rintf");
        symbol(&__fpclassify, "__fpclassify");
        symbol(&__fpclassifyf, "__fpclassifyf");
        symbol(&__fpclassifyl, "__fpclassifyl");
        symbol(&__signbit, "__signbit");
        symbol(&__signbitf, "__signbitf");
        symbol(&__signbitl, "__signbitl");
        symbol(&nextafter, "nextafter");
        symbol(&nexttoward, "nexttoward");
        symbol(&nearbyint, "nearbyint");
    }
    if (builtin.target.isWasiLibC()) {
        symbol(&__math_divzero, "__math_divzero");
        symbol(&__math_divzerof, "__math_divzerof");
        symbol(&__math_invalid, "__math_invalid");
        symbol(&__math_invalidf, "__math_invalidf");
        symbol(&__math_invalidl, "__math_invalidl");
        symbol(&__math_oflow, "__math_oflow");
        symbol(&__math_oflowf, "__math_oflowf");
        symbol(&__math_uflow, "__math_uflow");
        symbol(&__math_uflowf, "__math_uflowf");
        symbol(&__math_xflow, "__math_xflow");
        symbol(&__math_xflowf, "__math_xflowf");
        symbol(&scalbf, "scalbf");
        symbol(&nextafter, "nextafter");
        symbol(&nexttoward, "nexttoward");
    }
    symbol(&__signgam, "__signgam");
    symbol(&__signgam, "signgam");
}

fn acosWithFlags(comptime T: type, x: T) T {
    @setFloatMode(.strict);
    if (@abs(x) > 1.0) {
        std.math.raiseInvalid();
        return math.nan(T);
    }
    return math.acos(x);
}

fn acos(x: f64) callconv(.c) f64 {
    return acosWithFlags(f64, x);
}

fn acosf(x: f32) callconv(.c) f32 {
    return acosWithFlags(f32, x);
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
    @setFloatMode(.strict);
    const ux: u32 = @bitCast(x);
    const w = ux & 0x7fffffff;
    const absx: f32 = @bitCast(w);

    if (w < 0x42b17217) {
        const t = expm1f(absx);
        return 1.0 + t * t / (2.0 * (1.0 + t));
    }

    return expo2f(absx, 1.0);
}

fn exp10(x: f64) callconv(.c) f64 {
    return math.pow(f64, 10.0, x);
}

fn exp10f(x: f32) callconv(.c) f32 {
    return math.pow(f32, 10.0, x);
}

fn exp10l(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => @floatCast(exp10(@floatCast(x))),
        80 => @floatCast(exp10lWide(f80, @floatCast(x))),
        128 => @floatCast(exp10lWide(f128, @floatCast(x))),
        else => powl(10.0, x),
    };
}

fn exp10lWide(comptime T: type, x: T) T {
    @setFloatMode(.strict);
    const p10 = [31]T{
        1e-15, 1e-14, 1e-13, 1e-12, 1e-11, 1e-10,
        1e-9,  1e-8,  1e-7,  1e-6,  1e-5,  1e-4,
        1e-3,  1e-2,  1e-1,  1,     1e1,   1e2,
        1e3,   1e4,   1e5,   1e6,   1e7,   1e8,
        1e9,   1e10,  1e11,  1e12,  1e13,  1e14,
        1e15,
    };
    var n_ld: c_longdouble = undefined;
    var y: T = @floatCast(modfl(@floatCast(x), &n_ld));
    const n: T = @floatCast(n_ld);
    const U = @Int(.unsigned, @typeInfo(T).float.bits);
    const u_bits: U = @bitCast(n);
    const se: u16 = @truncate(u_bits >> (@typeInfo(T).float.bits - 16));
    if ((se & 0x7fff) < 0x3fff + 4) {
        const idx: usize = @intCast(@as(i32, @intFromFloat(n)) + 15);
        if (y == 0) return p10[idx];
        y = @floatCast(exp2l(@floatCast(@as(T, 3.32192809488736234787031942948939) * y)));
        return y * p10[idx];
    }
    return @floatCast(powl(10.0, @floatCast(x)));
}

fn hypot(x: f64, y: f64) callconv(.c) f64 {
    return math.hypot(x, y);
}

fn hypotf(x: f32, y: f32) callconv(.c) f32 {
    return math.hypot(x, y);
}

fn hypotl(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => hypot64Strict(@bitCast(x), @bitCast(y)),
        else => hypotWide(c_longdouble, x, y),
    };
}

const DoubleWord = struct { hi: f64, lo: f64 };

fn sq64(x: f64) DoubleWord {
    @setFloatMode(.strict);
    const split: f64 = 0x1p27 + 1;
    const xc = x * split;
    const xh = x - xc + xc;
    const xl = x - xh;
    const hi = x * x;
    const lo = xh * xh - hi + 2.0 * xh * xl + xl * xl;
    return .{ .hi = hi, .lo = lo };
}

fn hypot64Strict(x_: f64, y_: f64) f64 {
    @setFloatMode(.strict);
    var ux: u64 = @bitCast(x_);
    var uy: u64 = @bitCast(y_);
    ux &= std.math.maxInt(u64) >> 1;
    uy &= std.math.maxInt(u64) >> 1;
    if (ux < uy) {
        const ut = ux;
        ux = uy;
        uy = ut;
    }

    const ex: i32 = @intCast(ux >> 52);
    const ey: i32 = @intCast(uy >> 52);
    var x: f64 = @bitCast(ux);
    var y: f64 = @bitCast(uy);
    if (ey == 0x7ff) return y;
    if (ex == 0x7ff or uy == 0) return x;
    if (ex - ey > 64) return x + y;

    var z: f64 = 1.0;
    if (ex > 0x3ff + 510) {
        z = 0x1p700;
        x *= 0x1p-700;
        y *= 0x1p-700;
    } else if (ey < 0x3ff - 450) {
        z = 0x1p-700;
        x *= 0x1p700;
        y *= 0x1p700;
    }

    const hx = sq64(x);
    const hy = sq64(y);
    return z * @sqrt(hy.lo + hx.lo + hy.hi + hx.hi);
}

fn hypotWide(comptime T: type, x: T, y: T) T {
    @setFloatMode(.strict);
    const ax = @abs(x);
    const ay = @abs(y);
    if (math.isInf(ax) or math.isInf(ay)) return math.inf(T);
    if (math.isNan(ax) or math.isNan(ay)) return x + y;
    const hi = @max(ax, ay);
    const lo = @min(ax, ay);
    if (lo == 0.0) return hi;

    const fr = math.frexp(hi);
    const scale = scalbnStrict(T, 1.0, -fr.exponent);
    const r = @sqrt((hi * scale) * (hi * scale) + (lo * scale) * (lo * scale));
    return scalbnStrict(T, r, fr.exponent);
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

fn pow10l(x: c_longdouble) callconv(.c) c_longdouble {
    return exp10l(x);
}

fn rint(x: f64) callconv(.c) f64 {
    @setFloatMode(.strict);
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
    return atanhGeneric(f32, x);
}

fn cosl(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => math.cos(@as(f64, @bitCast(x))),
        80 => x87Cos(x),
        else => math.cos(x),
    };
}

fn expm1(x_: f64) callconv(.c) f64 {
    @setFloatMode(.strict);
    const o_threshold: f64 = 7.09782712893383973096e+02;
    const ln2_hi: f64 = 6.93147180369123816490e-01;
    const ln2_lo: f64 = 1.90821492927058770002e-10;
    const invln2: f64 = 1.44269504088896338700e+00;
    const Q1: f64 = -3.33333333333331316428e-02;
    const Q2: f64 = 1.58730158725481460165e-03;
    const Q3: f64 = -7.93650757867487942473e-05;
    const Q4: f64 = 4.00821782732936239552e-06;
    const Q5: f64 = -2.01099218183624371326e-07;

    var x = x_;
    const bits: u64 = @bitCast(x);
    var hx: u32 = @truncate(bits >> 32);
    const sign = (hx >> 31) != 0;
    hx &= 0x7fffffff;

    if (hx >= 0x4043687A) {
        if (math.isNan(x)) return x;
        if (sign) return -1.0;
        if (x > o_threshold) {
            return fpBarrierValue(f64, x) * 0x1p1023;
        }
    }

    var k: i32 = undefined;
    var hi: f64 = undefined;
    var lo: f64 = undefined;
    var c: f64 = 0.0;
    if (hx > 0x3fd62e42) {
        if (hx < 0x3FF0A2B2) {
            if (!sign) {
                hi = x - ln2_hi;
                lo = ln2_lo;
                k = 1;
            } else {
                hi = x + ln2_hi;
                lo = -ln2_lo;
                k = -1;
            }
        } else {
            k = @intFromFloat(invln2 * x + (if (sign) @as(f64, -0.5) else @as(f64, 0.5)));
            const t: f64 = @floatFromInt(k);
            hi = x - t * ln2_hi;
            lo = t * ln2_lo;
        }
        x = hi - lo;
        c = (hi - x) - lo;
    } else if (hx < 0x3c900000) {
        if (hx < 0x00100000) {
            forceEval(f32, @floatCast(x));
        }
        return x;
    } else {
        k = 0;
    }

    const hfx = 0.5 * x;
    const hxs = x * hfx;
    const r1 = 1.0 + hxs * (Q1 + hxs * (Q2 + hxs * (Q3 + hxs * (Q4 + hxs * Q5))));
    const t = 3.0 - r1 * hfx;
    var e = hxs * ((r1 - t) / (6.0 - x * t));
    if (k == 0) {
        return x - (x * e - hxs);
    }
    e = x * (e - c) - c;
    e -= hxs;
    if (k == -1) return 0.5 * (x - e) - 0.5;
    if (k == 1) {
        if (x < -0.25) return -2.0 * (e - (x + 0.5));
        return 1.0 + 2.0 * (x - e);
    }
    const twopk: f64 = @bitCast(@as(u64, @intCast(0x3ff + k)) << 52);
    if (k <= -2 or k > 56) {
        var y = x - e + 1.0;
        if (k == 1024) {
            y = fpBarrierValue(f64, y * 2.0) * 0x1p1023;
        } else {
            y = y * twopk;
        }
        return y - 1.0;
    }
    const uf: f64 = @bitCast(@as(u64, @intCast(0x3ff - k)) << 52);
    if (k < 20) {
        return (x - e + (1.0 - uf)) * twopk;
    } else {
        return (x - (e + uf) + 1.0) * twopk;
    }
}

fn expm1f(x_: f32) callconv(.c) f32 {
    @setFloatMode(.strict);
    const ln2_hi: f32 = 6.9313812256e-01;
    const ln2_lo: f32 = 9.0580006145e-06;
    const invln2: f32 = 1.4426950216e+00;
    const Q1: f32 = -3.3333212137e-02;
    const Q2: f32 = 1.5807170421e-03;

    var x = x_;
    var hx: u32 = @bitCast(x);
    const sign = (hx >> 31) != 0;
    hx &= 0x7fffffff;

    if (hx >= 0x4195b844) {
        if (hx > 0x7f800000) return x;
        if (sign) return -1.0;
        if (hx > 0x42b17217) {
            return fpBarrierValue(f32, x) * 0x1p127;
        }
    }

    var k: i32 = undefined;
    var hi: f32 = undefined;
    var lo: f32 = undefined;
    var c: f32 = 0.0;
    if (hx > 0x3eb17218) {
        if (hx < 0x3F851592) {
            if (!sign) {
                hi = x - ln2_hi;
                lo = ln2_lo;
                k = 1;
            } else {
                hi = x + ln2_hi;
                lo = -ln2_lo;
                k = -1;
            }
        } else {
            k = @intFromFloat(invln2 * x + (if (sign) @as(f32, -0.5) else @as(f32, 0.5)));
            const t: f32 = @floatFromInt(k);
            hi = x - t * ln2_hi;
            lo = t * ln2_lo;
        }
        x = hi - lo;
        c = (hi - x) - lo;
    } else if (hx < 0x33000000) {
        if (hx < 0x00800000) {
            forceEval(f32, x * x);
        }
        return x;
    } else {
        k = 0;
    }

    const hfx = 0.5 * x;
    const hxs = x * hfx;
    const r1 = 1.0 + hxs * (Q1 + hxs * Q2);
    const t = 3.0 - r1 * hfx;
    var e = hxs * ((r1 - t) / (6.0 - x * t));
    if (k == 0) {
        return x - (x * e - hxs);
    }
    e = x * (e - c) - c;
    e -= hxs;
    if (k == -1) return 0.5 * (x - e) - 0.5;
    if (k == 1) {
        if (x < -0.25) return -2.0 * (e - (x + 0.5));
        return 1.0 + 2.0 * (x - e);
    }
    const twopk: f32 = @bitCast(@as(u32, @intCast(0x7f + k)) << 23);
    if (k <= -2 or k > 56) {
        var y = x - e + 1.0;
        if (k == 128) {
            y = fpBarrierValue(f32, y * 2.0) * 0x1p127;
        } else {
            y = y * twopk;
        }
        return y - 1.0;
    }
    const uf: f32 = @bitCast(@as(u32, @intCast(0x7f - k)) << 23);
    if (k < 20) {
        return (x - e + (1.0 - uf)) * twopk;
    } else {
        return (x - (e + uf) + 1.0) * twopk;
    }
}

fn fdimGeneric(comptime T: type, x: T, y: T) T {
    if (math.isNan(x)) return x;
    if (math.isNan(y)) return y;
    if (x > y) return x - y;
    return 0;
}

fn fdimf(x: f32, y: f32) callconv(.c) f32 {
    const ux: u32 = @bitCast(x);
    const uy: u32 = @bitCast(y);
    if ((ux & 0x7fffffff) > 0x7f800000) return x;
    if ((uy & 0x7fffffff) > 0x7f800000) return y;
    if (x > y) return x - y;
    return 0.0;
}

fn fdiml(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    if (__fpclassifyl(x) == 0) return x;
    if (__fpclassifyl(y) == 0) return y;
    if (x > y) return x - y;
    return 0.0;
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
    return scalbnStrict(f32, x, n);
}

fn ldexpl(x: c_longdouble, n: c_int) callconv(.c) c_longdouble {
    return scalbnStrict(c_longdouble, x, n);
}

fn llrintf(x: f32) callconv(.c) c_longlong {
    return intFromFloat(c_longlong, rintGeneric(f32, x));
}

fn llrintl(x: c_longdouble) callconv(.c) c_longlong {
    return intFromFloat(c_longlong, rintGeneric(c_longdouble, x));
}

fn llround(x: f64) callconv(.c) c_longlong {
    return @intFromFloat(math.round(x));
}

fn llroundf(x: f32) callconv(.c) c_longlong {
    return @intFromFloat(math.round(x));
}

fn llroundl(x: c_longdouble) callconv(.c) c_longlong {
    return @intFromFloat(math.round(x));
}

fn log1p(x: f64) callconv(.c) f64 {
    return math.log1p(x);
}

fn log1pf(x: f32) callconv(.c) f32 {
    return math.log1p(x);
}

fn log1pl(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => log1p64Strict(@bitCast(x)),
        else => log1plChecked(c_longdouble, x),
    };
}

fn log1p64Strict(x: f64) f64 {
    @setFloatMode(.strict);
    if (math.isNan(x)) return x + x;
    if (x == math.inf(f64)) return x;
    if (x == 0.0) return x;
    if (x == -1.0) {
        std.math.raiseDivByZero();
        return -math.inf(f64);
    }
    if (x < -1.0) {
        std.math.raiseInvalid();
        return math.nan(f64);
    }
    if (@abs(x) < 0x1p-53) {
        if (@abs(x) < math.floatMin(f64)) std.math.raiseUnderflow();
        return x;
    }
    return @floatCast(log1p_wide(f128, @floatCast(x)));
}

fn lrintf(x: f32) callconv(.c) c_long {
    return intFromFloat(c_long, rintGeneric(f32, x));
}

fn lrintl(x: c_longdouble) callconv(.c) c_long {
    return intFromFloat(c_long, rintGeneric(c_longdouble, x));
}

fn lround(x: f64) callconv(.c) c_long {
    return @round(x);
}

fn lroundf(x: f32) callconv(.c) c_long {
    return @round(x);
}

fn lroundl(x: c_longdouble) callconv(.c) c_long {
    return @round(x);
}

extern fn fetestexcept(c_int) c_int;
extern fn feclearexcept(c_int) c_int;

fn nearbyintWithFlags(comptime T: type, comptime rint_fn: fn (T) callconv(.c) T, x: T) T {
    if (comptime builtin.target.cpu.arch == .aarch64 or builtin.target.cpu.arch == .aarch64_be) {
        const FE_INEXACT_AARCH64: u64 = 0x10;
        const fpsr_before = asm volatile ("mrs %[ret], fpsr"
            : [ret] "=r" (-> u64),
        );
        const y = rint_fn(x);
        if ((fpsr_before & FE_INEXACT_AARCH64) == 0) {
            const fpsr_after = asm volatile ("mrs %[ret], fpsr"
                : [ret] "=r" (-> u64),
            );
            if ((fpsr_after & FE_INEXACT_AARCH64) != 0) {
                const cleared = fpsr_after & ~FE_INEXACT_AARCH64;
                asm volatile ("msr fpsr, %[val]"
                    :
                    : [val] "r" (cleared),
                );
            }
        }
        return y;
    }
    if (comptime !builtin.is_test or builtin.link_libc) {
        const fe_inexact: c_int = switch (builtin.target.cpu.arch) {
            .x86_64, .x86, .hexagon => 0x20,
            .arm, .armeb, .thumb, .thumbeb => 0x10,
            .riscv32, .riscv64 => 0x01,
            .loongarch64 => 0x010000,
            .m68k => 0x08,
            .mips, .mipsel, .mips64, .mips64el => 0x04,
            .powerpc, .powerpcle, .powerpc64, .powerpc64le => 0x02000000,
            .s390x => 0x080000,
            else => 0,
        };
        if (fe_inexact != 0) {
            const e = fetestexcept(fe_inexact);
            const y = fpBarrierValue(T, rint_fn(fpBarrierValue(T, x)));
            if (e == 0) _ = feclearexcept(fe_inexact);
            return y;
        }
    }
    return rint_fn(x);
}

fn nearbyintf(x: f32) callconv(.c) f32 {
    return nearbyintWithFlags(f32, rintf, x);
}

fn nearbyintl(x: c_longdouble) callconv(.c) c_longdouble {
    return nearbyintWithFlags(c_longdouble, rintl, x);
}

fn nextafterf(x: f32, y: f32) callconv(.c) f32 {
    @setFloatMode(.strict);
    var ux: u32 = @bitCast(x);
    const uy: u32 = @bitCast(y);

    if (math.isNan(x) or math.isNan(y)) return x + y;
    if (ux == uy) return y;

    const ax = ux & (math.maxInt(u32) >> 1);
    const ay = uy & (math.maxInt(u32) >> 1);
    if (ax == 0) {
        if (ay == 0) return y;
        ux = (uy & (@as(u32, 1) << 31)) | 1;
    } else if (ax > ay or ((ux ^ uy) & (@as(u32, 1) << 31)) != 0) {
        ux -= 1;
    } else {
        ux += 1;
    }
    const e: u32 = (ux >> 23) & 0xff;
    if (e == 0xff) mem.doNotOptimizeAway(x + x);
    if (e == 0) {
        const val: f32 = @bitCast(ux);
        mem.doNotOptimizeAway(x * x + val * val);
    }
    return @bitCast(ux);
}

fn nextafterl(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    const r = math.nextAfter(c_longdouble, x, y);
    raiseNextafterExceptions(c_longdouble, x, r);
    return r;
}

fn nexttowardf(x: f32, y: c_longdouble) callconv(.c) f32 {
    @setFloatMode(.strict);
    var ux: u32 = @bitCast(x);
    if (math.isNan(x) or math.isNan(y)) return x + @as(f32, @floatCast(y));
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
    const e: u32 = (ux >> 23) & 0xff;
    if (e == 0xff) mem.doNotOptimizeAway(x + x);
    if (e == 0) {
        const val: f32 = @bitCast(ux);
        mem.doNotOptimizeAway(x * x + val * val);
    }
    return @bitCast(ux);
}

fn nexttowardl(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    const r = math.nextAfter(c_longdouble, x, y);
    raiseNextafterExceptions(c_longdouble, x, r);
    return r;
}

fn raiseNextafterExceptions(comptime T: type, x: T, r: T) void {
    if (math.isInf(r) and math.isFinite(x)) {
        std.math.raiseOverflow();
    }
    if ((r == 0 or @abs(r) < math.floatMin(T)) and r != x) {
        std.math.raiseUnderflow();
    }
}

/// Generic rint for any IEEE 754 float type.
fn rintGeneric(comptime T: type, x: T) T {
    @setFloatMode(.strict);
    const toint: T = 1.0 / math.floatEps(T);
    const FloatBits = @Int(.unsigned, @typeInfo(T).float.bits);
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

fn significandf(x: f32) callconv(.c) f32 {
    const e = math.ilogb(x);
    return math.scalbn(x, if (e == std.math.minInt(i32)) 0 else -e);
}

fn sincosl(x: c_longdouble, sin_ptr: *c_longdouble, cos_ptr: *c_longdouble) callconv(.c) void {
    sin_ptr.* = sinl(x);
    cos_ptr.* = cosl(x);
}

fn sinhf(x: f32) callconv(.c) f32 {
    @setFloatMode(.strict);
    const ux: u32 = @bitCast(x);
    const w = ux & 0x7fffffff;
    const absx: f32 = @bitCast(w);
    const h: f32 = if (ux >> 31 != 0) -0.5 else 0.5;

    if (w < 0x42b17217) {
        const t = expm1f(absx);
        if (w < 0x3f800000) {
            if (w < 0x3f800000 - (12 << 23)) return x;
            return h * (2 * t - t * t / (t + 1));
        }
        return h * (t + t / (t + 1));
    }

    return expo2f(absx, 2 * h);
}

fn expo2(x: f64, sign: f64) f64 {
    @setFloatMode(.strict);
    const k = 2043;
    const kln2: f64 = 0x1.62066151add8bp+10;
    const scale: f64 = @bitCast(@as(u64, 0x3ff + k / 2) << 52);
    return math.exp(x - kln2) * (sign * scale) * scale;
}

fn expo2f(x: f32, sign: f32) f32 {
    @setFloatMode(.strict);
    const k = 235;
    const kln2: f32 = 0x1.45c778p+7;
    const scale: f32 = @bitCast(@as(u32, (0x7f + k / 2) << 23));
    return math.exp(x - kln2) * (sign * scale) * scale;
}

fn sinl(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => math.sin(@as(f64, @bitCast(x))),
        80 => x87Sin(x),
        else => math.sin(x),
    };
}

fn tanl(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => math.tan(@as(f64, @bitCast(x))),
        80 => x87Tan(x),
        else => math.tan(x),
    };
}

fn x87Cos(x: c_longdouble) c_longdouble {
    if (math.isNan(x)) return x + x;
    if (!math.isFinite(x)) {
        std.math.raiseInvalid();
        return math.nan(c_longdouble);
    }
    return switch (builtin.target.cpu.arch) {
        .x86, .x86_64 => blk: {
            var input = x;
            var r: c_longdouble = undefined;
            if (comptime builtin.target.cpu.arch == .x86_64) {
                asm volatile (
                    \\fldt (%%rax)
                    \\fcos
                    \\fstpt (%%rcx)
                    :
                    : [in] "{rax}" (&input),
                      [out] "{rcx}" (&r),
                    : .{ .memory = true, .st0 = true });
            } else {
                asm volatile (
                    \\fldt (%%eax)
                    \\fcos
                    \\fstpt (%%ecx)
                    :
                    : [in] "{eax}" (&input),
                      [out] "{ecx}" (&r),
                    : .{ .memory = true, .st0 = true });
            }
            break :blk r;
        },
        else => math.cos(x),
    };
}

fn x87Sin(x: c_longdouble) c_longdouble {
    if (math.isNan(x)) return x + x;
    if (!math.isFinite(x)) {
        std.math.raiseInvalid();
        return math.nan(c_longdouble);
    }
    return switch (builtin.target.cpu.arch) {
        .x86, .x86_64 => blk: {
            var input = x;
            var r: c_longdouble = undefined;
            if (comptime builtin.target.cpu.arch == .x86_64) {
                asm volatile (
                    \\fldt (%%rax)
                    \\fsin
                    \\fstpt (%%rcx)
                    :
                    : [in] "{rax}" (&input),
                      [out] "{rcx}" (&r),
                    : .{ .memory = true, .st0 = true });
            } else {
                asm volatile (
                    \\fldt (%%eax)
                    \\fsin
                    \\fstpt (%%ecx)
                    :
                    : [in] "{eax}" (&input),
                      [out] "{ecx}" (&r),
                    : .{ .memory = true, .st0 = true });
            }
            break :blk r;
        },
        else => math.sin(x),
    };
}

fn x87Tan(x: c_longdouble) c_longdouble {
    if (math.isNan(x)) return x + x;
    if (!math.isFinite(x)) {
        std.math.raiseInvalid();
        return math.nan(c_longdouble);
    }
    return switch (builtin.target.cpu.arch) {
        .x86, .x86_64 => blk: {
            var input = x;
            var r: c_longdouble = undefined;
            var one: c_longdouble = undefined;
            if (comptime builtin.target.cpu.arch == .x86_64) {
                asm volatile (
                    \\fldt (%%rax)
                    \\fptan
                    \\fstpt (%%rdx)
                    \\fstpt (%%rcx)
                    :
                    : [in] "{rax}" (&input),
                      [out] "{rcx}" (&r),
                      [one] "{rdx}" (&one),
                    : .{ .memory = true, .st0 = true, .st1 = true });
            } else {
                asm volatile (
                    \\fldt (%%eax)
                    \\fptan
                    \\fstpt (%%edx)
                    \\fstpt (%%ecx)
                    :
                    : [in] "{eax}" (&input),
                      [out] "{ecx}" (&r),
                      [one] "{edx}" (&one),
                    : .{ .memory = true, .st0 = true, .st1 = true });
            }
            break :blk r;
        },
        else => math.tan(x),
    };
}

fn exp2l_ld80(x: f80) f80 {
    @setFloatMode(.strict);
    const TBLBITS = 7;
    const TBLSIZE: u32 = 1 << TBLBITS;
    const redux: f64 = 0x1.8p63 / @as(f64, TBLSIZE);
    const P1: f80 = 0x1.62e42fefa39ef35793c7673007e6p-1;
    const P2: f80 = 0x1.ebfbdff82c58ea86f16b06ec9736p-3;
    const P3: f80 = 0x1.c6b08d704a0bf8b33a762bad3459p-5;
    const P4: f80 = 0x1.3b2ab6fba4e7729ccbbe0b4f3fc2p-7;
    const P5: f80 = 0x1.5d87fe78a67311071dee13fd11d9p-10;
    const P6: f80 = 0x1.430912f86c7876f4b663b23c5fe5p-13;
    const tbl = [TBLSIZE * 2]f64{
        0x1.6a09e667f3bcdp-1, -0x1.bdd3413b2648p-55,
        0x1.6c012750bdabfp-1, -0x1.2895667ff0cp-57,
        0x1.6dfb23c651a2fp-1, -0x1.bbe3a683c88p-58,
        0x1.6ff7df9519484p-1, -0x1.83c0f25860fp-56,
        0x1.71f75e8ec5f74p-1, -0x1.16e4786887bp-56,
        0x1.73f9a48a58174p-1, -0x1.0a8d96c65d5p-55,
        0x1.75feb564267c9p-1, -0x1.0245957316ep-55,
        0x1.780694fde5d3fp-1, 0x1.866b80a0216p-55,
        0x1.7a11473eb0187p-1, -0x1.41577ee0499p-56,
        0x1.7c1ed0130c132p-1, 0x1.f124cd1164ep-55,
        0x1.7e2f336cf4e62p-1, 0x1.05d02ba157ap-57,
        0x1.80427543e1a12p-1, -0x1.27c86626d97p-55,
        0x1.82589994cce13p-1, -0x1.d4c1dd41533p-55,
        0x1.8471a4623c7adp-1, -0x1.8d684a341cep-56,
        0x1.868d99b4492edp-1, -0x1.fc6f89bd4f68p-55,
        0x1.88ac7d98a6699p-1, 0x1.994c2f37cb5p-55,
        0x1.8ace5422aa0dbp-1, 0x1.6e9f156864bp-55,
        0x1.8cf3216b5448cp-1, -0x1.0d55e32e9e4p-57,
        0x1.8f1ae99157736p-1, 0x1.5cc13a2e397p-56,
        0x1.9145b0b91ffc6p-1, -0x1.dd6792e5825p-55,
        0x1.93737b0cdc5e5p-1, -0x1.75fc781b58p-58,
        0x1.95a44cbc8520fp-1, -0x1.64b7c96a5fp-57,
        0x1.97d829fde4e5p-1,  -0x1.d185b7c1b86p-55,
        0x1.9a0f170ca07bap-1, -0x1.173bd91cee6p-55,
        0x1.9c49182a3f09p-1,  0x1.c7c46b071f2p-57,
        0x1.9e86319e32323p-1, 0x1.824ca78e64cp-57,
        0x1.a0c667b5de565p-1, -0x1.359495d1cd5p-55,
        0x1.a309bec4a2d33p-1, 0x1.6305c7ddc368p-55,
        0x1.a5503b23e255dp-1, -0x1.d2f6edb8d42p-55,
        0x1.a799e1330b358p-1, 0x1.bcb7ecac564p-55,
        0x1.a9e6b5579fdbfp-1, 0x1.0fac90ef7fdp-55,
        0x1.ac36bbfd3f37ap-1, -0x1.f9234cae76dp-56,
        0x1.ae89f995ad3adp-1, 0x1.7a1cd345dcc8p-55,
        0x1.b0e07298db666p-1, -0x1.bdef54c80e4p-55,
        0x1.b33a2b84f15fbp-1, -0x1.2805e3084d8p-58,
        0x1.b59728de5593ap-1, -0x1.c71dfbbba6ep-55,
        0x1.b7f76f2fb5e47p-1, -0x1.5584f7e54acp-57,
        0x1.ba5b030a1064ap-1, -0x1.efcd30e5429p-55,
        0x1.bcc1e904bc1d2p-1, 0x1.23dd07a2d9fp-56,
        0x1.bf2c25bd71e09p-1, -0x1.efdca3f6b9c8p-55,
        0x1.c199bdd85529cp-1, 0x1.11065895049p-56,
        0x1.c40ab5fffd07ap-1, 0x1.b4537e083c6p-55,
        0x1.c67f12e57d14bp-1, 0x1.2884dff483c8p-55,
        0x1.c8f6d9406e7b5p-1, 0x1.1acbc48805cp-57,
        0x1.cb720dcef9069p-1, 0x1.503cbd1e94ap-57,
        0x1.cdf0b555dc3fap-1, -0x1.dd83b53829dp-56,
        0x1.d072d4a07897cp-1, -0x1.cbc3743797a8p-55,
        0x1.d2f87080d89f2p-1, -0x1.d487b719d858p-55,
        0x1.d5818dcfba487p-1, 0x1.2ed02d75b37p-56,
        0x1.d80e316c98398p-1, -0x1.11ec18bedep-55,
        0x1.da9e603db3285p-1, 0x1.c2300696db5p-55,
        0x1.dd321f301b46p-1,  0x1.2da5778f019p-55,
        0x1.dfc97337b9b5fp-1, -0x1.1a5cd4f184b8p-55,
        0x1.e264614f5a129p-1, -0x1.7b627817a148p-55,
        0x1.e502ee78b3ff6p-1, 0x1.39e8980a9cdp-56,
        0x1.e7a51fbc74c83p-1, 0x1.2d522ca0c8ep-55,
        0x1.ea4afa2a490dap-1, -0x1.e9c23179c288p-55,
        0x1.ecf482d8e67f1p-1, -0x1.c93f3b411ad8p-55,
        0x1.efa1bee615a27p-1, 0x1.dc7f486a4b68p-55,
        0x1.f252b376bba97p-1, 0x1.3a1a5bf0d8e8p-55,
        0x1.f50765b6e454p-1,  0x1.9d3e12dd8a18p-55,
        0x1.f7bfdad9cbe14p-1, -0x1.dbb12d00635p-55,
        0x1.fa7c1819e90d8p-1, 0x1.74853f3a593p-56,
        0x1.fd3c22b8f71f1p-1, 0x1.2eb74966578p-58,
        0x1p+0,               0x0p+0,
        0x1.0163da9fb3335p+0, 0x1.b61299ab8cd8p-54,
        0x1.02c9a3e778061p+0, -0x1.19083535b08p-56,
        0x1.04315e86e7f85p+0, -0x1.0a31c1977c98p-54,
        0x1.059b0d3158574p+0, 0x1.d73e2a475b4p-55,
        0x1.0706b29ddf6dep+0, -0x1.c91dfe2b13cp-55,
        0x1.0874518759bc8p+0, 0x1.186be4bb284p-57,
        0x1.09e3ecac6f383p+0, 0x1.14878183161p-54,
        0x1.0b5586cf9890fp+0, 0x1.8a62e4adc61p-54,
        0x1.0cc922b7247f7p+0, 0x1.01edc16e24f8p-54,
        0x1.0e3ec32d3d1a2p+0, 0x1.03a1727c58p-59,
        0x1.0fb66affed31bp+0, -0x1.b9bedc44ebcp-57,
        0x1.11301d0125b51p+0, -0x1.6c51039449bp-54,
        0x1.12abdc06c31ccp+0, -0x1.1b514b36ca8p-58,
        0x1.1429aaea92dep+0,  -0x1.32fbf9af1368p-54,
        0x1.15a98c8a58e51p+0, 0x1.2406ab9eeabp-55,
        0x1.172b83c7d517bp+0, -0x1.19041b9d78ap-55,
        0x1.18af9388c8deap+0, -0x1.11023d1970f8p-54,
        0x1.1a35beb6fcb75p+0, 0x1.e5b4c7b4969p-55,
        0x1.1bbe084045cd4p+0, -0x1.95386352ef6p-54,
        0x1.1d4873168b9aap+0, 0x1.e016e00a264p-54,
        0x1.1ed5022fcd91dp+0, -0x1.1df98027bb78p-54,
        0x1.2063b88628cd6p+0, 0x1.dc775814a85p-55,
        0x1.21f49917ddc96p+0, 0x1.2a97e9494a6p-55,
        0x1.2387a6e756238p+0, 0x1.9b07eb6c7058p-54,
        0x1.251ce4fb2a63fp+0, 0x1.ac155bef4f5p-55,
        0x1.26b4565e27cddp+0, 0x1.2bd339940eap-55,
        0x1.284dfe1f56381p+0, -0x1.a4c3a8c3f0d8p-54,
        0x1.29e9df51fdee1p+0, 0x1.612e8afad12p-55,
        0x1.2b87fd0dad99p+0,  -0x1.10adcd6382p-59,
        0x1.2d285a6e4030bp+0, 0x1.0024754db42p-54,
        0x1.2ecafa93e2f56p+0, 0x1.1ca0f45d524p-56,
        0x1.306fe0a31b715p+0, 0x1.6f46ad23183p-55,
        0x1.32170fc4cd831p+0, 0x1.a9ce78e1804p-55,
        0x1.33c08b26416ffp+0, 0x1.327218436598p-54,
        0x1.356c55f929ff1p+0, -0x1.b5cee5c4e46p-55,
        0x1.371a7373aa9cbp+0, -0x1.63aeabf42ebp-54,
        0x1.38cae6d05d866p+0, -0x1.e958d3c99048p-54,
        0x1.3a7db34e59ff7p+0, -0x1.5e436d661f6p-56,
        0x1.3c32dc313a8e5p+0, -0x1.efff8375d2ap-54,
        0x1.3dea64c123422p+0, 0x1.ada0911f09fp-55,
        0x1.3fa4504ac801cp+0, -0x1.7d023f956fap-54,
        0x1.4160a21f72e2ap+0, -0x1.ef3691c309p-58,
        0x1.431f5d950a897p+0, -0x1.1c7dde35f7ap-55,
        0x1.44e086061892dp+0, 0x1.89b7a04ef8p-59,
        0x1.46a41ed1d0057p+0, 0x1.c944bd1648a8p-54,
        0x1.486a2b5c13cdp+0,  0x1.3c1a3b69062p-56,
        0x1.4a32af0d7d3dep+0, 0x1.9cb62f3d1be8p-54,
        0x1.4bfdad5362a27p+0, 0x1.d4397afec42p-56,
        0x1.4dcb299fddd0dp+0, 0x1.8ecdbbc6a78p-54,
        0x1.4f9b2769d2ca7p+0, -0x1.4b309d25958p-54,
        0x1.516daa2cf6642p+0, -0x1.f768569bd94p-55,
        0x1.5342b569d4f82p+0, -0x1.07abe1db13dp-55,
        0x1.551a4ca5d920fp+0, -0x1.d689cefede6p-55,
        0x1.56f4736b527dap+0, 0x1.9bb2c011d938p-54,
        0x1.58d12d497c7fdp+0, 0x1.295e15b9a1ep-55,
        0x1.5ab07dd485429p+0, 0x1.6324c0546478p-54,
        0x1.5c9268a5946b7p+0, 0x1.c4b1b81698p-60,
        0x1.5e76f15ad2148p+0, 0x1.ba6f93080e68p-54,
        0x1.605e1b976dc09p+0, -0x1.3e2429b56de8p-54,
        0x1.6247eb03a5585p+0, -0x1.383c17e40b48p-54,
        0x1.6434634ccc32p+0,  -0x1.c483c759d89p-55,
        0x1.6623882552225p+0, -0x1.bb60987591cp-54,
        0x1.68155d44ca973p+0, 0x1.038ae44f74p-57,
    };

    var u_bits: u80 = @bitCast(x);
    const se: u16 = @truncate(u_bits >> 64);
    const e: u16 = se & 0x7fff;

    if (e >= 0x3fff + 13) {
        if (se >= 0x3fff + 14 and (se >> 15) == 0)
            return x * 0x1p16383;
        if (e == 0x7fff)
            return -1.0 / x;
        if (x < -16382.0) {
            if (x <= -16446.0 or x - 0x1p63 + 0x1p63 != x)
                mem.doNotOptimizeAway(@as(f32, @floatCast(-0x1p-149 / x)));
            if (x <= -16446.0)
                return 0.0;
        }
    } else if (e < 0x3fff - 64) {
        return 1.0 + x;
    }

    var uf: f80 = x + redux;
    u_bits = @bitCast(uf);
    const m: u64 = @truncate(u_bits);
    var idx0: u32 = @as(u32, @truncate(m)) +% (TBLSIZE / 2);
    const ku: u32 = (idx0 / TBLSIZE) * TBLSIZE;
    const ki: c_int = @divTrunc(@as(i32, @bitCast(ku)), @as(i32, TBLSIZE));
    idx0 %= TBLSIZE;
    uf -= redux;
    const z: f80 = x - uf;

    const t_hi: f80 = tbl[2 * idx0];
    const t_lo: f80 = tbl[2 * idx0 + 1];
    const r: f80 = t_lo + (t_hi + t_lo) * z * (P1 + z * (P2 + z * (P3 + z * (P4 + z * (P5 + z * P6))))) + t_hi;

    return @floatCast(scalbnl(@floatCast(r), ki));
}

fn exp2l(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => math.exp2(@as(f64, @bitCast(x))),
        80 => @floatCast(exp2l_ld80(@floatCast(x))),
        else => exp_pure(c_longdouble, x * @as(c_longdouble, 0.6931471805599453094172321214581765680755001343602552541206800094)),
    };
}

fn expl(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => math.exp(@as(f64, @bitCast(x))),
        else => exp_pure(c_longdouble, x),
    };
}

fn expm1l(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => expm1(@as(f64, @bitCast(x))),
        else => expm1_wide(c_longdouble, x),
    };
}

fn log10l(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => math.log10(@as(f64, @bitCast(x))),
        else => loglChecked(c_longdouble, x) * @as(c_longdouble, 0.4342944819032518276511289189166050822943970058036665661144537832),
    };
}

fn log2l(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => math.log2(@as(f64, @bitCast(x))),
        else => loglChecked(c_longdouble, x) * @as(c_longdouble, 1.4426950408889634073599246810018921374266459541529859341354494069),
    };
}

fn logbGeneric(comptime T: type, x: T) T {
    if (!math.isFinite(x)) return x * x;
    if (x == 0) {
        std.math.raiseDivByZero();
        return -math.inf(T);
    }
    return @floatFromInt(math.ilogb(x));
}

fn logbf(x: f32) callconv(.c) f32 {
    return logbGeneric(f32, x);
}

fn logbl(x: c_longdouble) callconv(.c) c_longdouble {
    return logbGeneric(c_longdouble, x);
}

fn logl(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => @log(@as(f64, @bitCast(x))),
        else => loglChecked(c_longdouble, x),
    };
}

fn loglChecked(comptime T: type, x: T) T {
    @setFloatMode(.strict);
    if (math.isNan(x)) return x + x;
    if (x == math.inf(T)) return x;
    if (x == 0.0) {
        std.math.raiseDivByZero();
        return -math.inf(T);
    }
    if (x < 0.0) {
        std.math.raiseInvalid();
        return math.nan(T);
    }
    return log_pure(T, x);
}

fn log1plChecked(comptime T: type, x: T) T {
    @setFloatMode(.strict);
    if (math.isNan(x)) return x + x;
    if (x == math.inf(T)) return x;
    if (x == 0.0) return x;
    if (x == -1.0) {
        std.math.raiseDivByZero();
        return -math.inf(T);
    }
    if (x < -1.0) {
        std.math.raiseInvalid();
        return math.nan(T);
    }
    return log1p_wide(T, x);
}

fn scalbf(x: f32, fn_arg: f32) callconv(.c) f32 {
    if (math.isNan(x) or math.isNan(fn_arg)) return x * fn_arg;
    if (!math.isFinite(fn_arg)) {
        if (fn_arg > 0.0) return x * fn_arg;
        return x / (-fn_arg);
    }
    if (rintGeneric(f32, fn_arg) != fn_arg) return (fn_arg - fn_arg) / (fn_arg - fn_arg);
    if (fn_arg > 65000.0) return scalbnStrict(f32, x, 65000);
    if (-fn_arg > 65000.0) return scalbnStrict(f32, x, -65000);
    return scalbnStrict(f32, x, @intFromFloat(fn_arg));
}

fn scalblnGeneric(comptime T: type, x: T, n: c_long) T {
    const clamped: i32 = if (n > std.math.maxInt(i32))
        std.math.maxInt(i32)
    else if (n < std.math.minInt(i32))
        std.math.minInt(i32)
    else
        @intCast(n);
    return scalbnStrict(T, x, clamped);
}

fn scalblnf(x: f32, n: c_long) callconv(.c) f32 {
    return scalblnGeneric(f32, x, n);
}

fn scalblnl(x: c_longdouble, n: c_long) callconv(.c) c_longdouble {
    return scalblnGeneric(c_longdouble, x, n);
}

fn scalbnf(x: f32, n: c_int) callconv(.c) f32 {
    return scalbnStrict(f32, x, n);
}

fn scalbnl(x: c_longdouble, n: c_int) callconv(.c) c_longdouble {
    return scalbnStrict(c_longdouble, x, n);
}

fn scalbnStrict(comptime T: type, x: T, n: c_int) T {
    @setFloatMode(.strict);
    if (T == c_longdouble and @typeInfo(c_longdouble).float.bits == 80 and (builtin.target.cpu.arch == .x86 or builtin.target.cpu.arch == .x86_64)) {
        return x87Scalbn(x, n);
    }
    if (x == 0.0 or !math.isFinite(x)) return x;

    const y = math.scalbn(x, n);
    if (math.isInf(y)) {
        std.math.raiseOverflow();
        return y;
    }
    if (y == 0.0) {
        std.math.raiseUnderflow();
        return y;
    }
    if (@abs(y) < math.floatMin(T)) {
        const inverse_n: c_int = if (n == minInt(c_int)) maxInt(c_int) else -n;
        if (math.scalbn(y, inverse_n) != x) std.math.raiseUnderflow();
    }
    return y;
}

fn x87Scalbn(x: c_longdouble, n: c_int) c_longdouble {
    var input = x;
    var exp = n;
    var r: c_longdouble = undefined;
    var junk: c_longdouble = undefined;
    if (comptime builtin.target.cpu.arch == .x86_64) {
        asm volatile (
            \\fildl (%%rdx)
            \\fldt (%%rax)
            \\fscale
            \\fstpt (%%rcx)
            \\fstpt (%%rsi)
            :
            : [in] "{rax}" (&input),
              [out] "{rcx}" (&r),
              [exp] "{rdx}" (&exp),
              [junk] "{rsi}" (&junk),
            : .{ .memory = true, .st0 = true, .st1 = true });
    } else {
        asm volatile (
            \\fildl (%%edx)
            \\fldt (%%eax)
            \\fscale
            \\fstpt (%%ecx)
            \\fstpt (%%esi)
            :
            : [in] "{eax}" (&input),
              [out] "{ecx}" (&r),
              [exp] "{edx}" (&exp),
              [junk] "{esi}" (&junk),
            : .{ .memory = true, .st0 = true, .st1 = true });
    }
    return r;
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

/// Port of musl powf — IEEE 754 conformant single-precision power function.
/// Uses double-precision log2+exp2 internally for 0.82 ULP accuracy.
/// Copyright (c) 2017-2018, Arm Limited. SPDX-License-Identifier: MIT
fn powf(x: f32, y: f32) callconv(.c) f32 {
    return powf_impl.call(x, y);
}

fn asinf(x: f32) callconv(.c) f32 {
    return math.asin(x);
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

fn finite_(x: f64) callconv(.c) c_int {
    return if (math.isFinite(x)) 1 else 0;
}

fn finitef_(x: f32) callconv(.c) c_int {
    return if (math.isFinite(x)) 1 else 0;
}

fn frexp_(x: f64, e: *c_int) callconv(.c) f64 {
    const r = math.frexp(x);
    e.* = r.exponent;
    return r.significand;
}

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

fn ilogb_(x: f64) callconv(.c) c_int {
    return math.ilogb(x);
}

fn ilogbf_(x: f32) callconv(.c) c_int {
    return math.ilogb(x);
}

fn ilogbl_(x: c_longdouble) callconv(.c) c_int {
    return math.ilogb(x);
}

fn ldexp_(x: f64, n: c_int) callconv(.c) f64 {
    return scalbnStrict(f64, x, n);
}

fn ldexpf_(x: f32, n: c_int) callconv(.c) f32 {
    return scalbnStrict(f32, x, n);
}

fn ldexpl_(x: c_longdouble, n: c_int) callconv(.c) c_longdouble {
    return scalbnStrict(c_longdouble, x, n);
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

fn scalbln_(x: f64, n: c_long) callconv(.c) f64 {
    const ni: c_int = if (n > maxInt(c_int)) maxInt(c_int) else if (n < minInt(c_int)) minInt(c_int) else @intCast(n);
    return scalbnStrict(f64, x, ni);
}

fn scalblnf_(x: f32, n: c_long) callconv(.c) f32 {
    const ni: c_int = if (n > maxInt(c_int)) maxInt(c_int) else if (n < minInt(c_int)) minInt(c_int) else @intCast(n);
    return scalbnStrict(f32, x, ni);
}

fn scalblnl_(x: c_longdouble, n: c_long) callconv(.c) c_longdouble {
    const ni: c_int = if (n > maxInt(c_int)) maxInt(c_int) else if (n < minInt(c_int)) minInt(c_int) else @intCast(n);
    return scalbnStrict(c_longdouble, x, ni);
}

fn scalbn_(x: f64, n: c_int) callconv(.c) f64 {
    return scalbnStrict(f64, x, n);
}

fn scalbnf_(x: f32, n: c_int) callconv(.c) f32 {
    return scalbnStrict(f32, x, n);
}

fn scalbnl_(x: c_longdouble, n: c_int) callconv(.c) c_longdouble {
    return scalbnStrict(c_longdouble, x, n);
}

fn significand_(x: f64) callconv(.c) f64 {
    return math.scalbn(x, -math.ilogb(x));
}

fn significandf_(x: f32) callconv(.c) f32 {
    return math.scalbn(x, -math.ilogb(x));
}

fn rintf(x: f32) callconv(.c) f32 {
    @setFloatMode(.strict);
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

fn rintl(x: c_longdouble) callconv(.c) c_longdouble {
    @setFloatMode(.strict);
    const toint: c_longdouble = 1.0 / @as(c_longdouble, math.floatEps(c_longdouble));

    // NaN or already-integer (includes Inf since Inf >= toint)
    if (x != x or @abs(x) >= toint) return x;

    // Use copysign to detect negative zero
    const is_neg = math.copysign(@as(c_longdouble, 1.0), x) < 0;
    const y = if (is_neg) x - toint + toint else x + toint - toint;
    if (y == 0) return if (is_neg) @as(c_longdouble, -0.0) else @as(c_longdouble, 0);
    return y;
}

fn acosh_(x: f64) callconv(.c) f64 {
    return acosh64Strict(x);
}

fn acoshl_(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => acosh64Strict(@bitCast(x)),
        else => acoshl_impl(c_longdouble, x),
    };
}

fn acosh64Strict(x: f64) f64 {
    @setFloatMode(.strict);
    return @floatCast(acoshl_impl(f128, @floatCast(x)));
}

fn acoshl_impl(comptime T: type, x: T) T {
    @setFloatMode(.strict);
    if (math.isNan(x)) return x + x;
    if (x < 1.0) {
        std.math.raiseInvalid();
        return math.nan(T);
    }
    if (x < 2.0) {
        const xm1 = x - 1.0;
        return log1p_wide(T, xm1 + @sqrt(xm1 * xm1 + 2.0 * xm1));
    }
    if (x < 0x1p32) return log_pure(T, 2.0 * x - 1.0 / (x + @sqrt(x * x - 1.0)));
    return loglChecked(T, x) + @as(T, 0.6931471805599453094172321214581765680755001343602552541206800094);
}

fn asinhf_(x: f32) callconv(.c) f32 {
    return math.asinh(x);
}

/// Compute log(1+x) using the identity log(1+x) = 2*atanh(x/(x+2))
/// and the series atanh(s) = s + s³/3 + s⁵/5 + ...
/// Uses only basic arithmetic (+, -, *, /) — no @log.
fn log1p_wide(comptime T: type, x: T) T {
    if (math.isNan(x) or x == math.inf(T)) return x;
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
    if (math.isNan(x) or x == math.inf(T)) return x;
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
    if (T == c_longdouble and @typeInfo(c_longdouble).float.bits == 80) return @floatCast(expm1l_ld80(@floatCast(x)));
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
    const two_k = scalbnStrict(T, 1.0, k);
    return two_k * sum + (two_k - 1);
}

fn expm1l_ld80(x_: c_longdouble) c_longdouble {
    @setFloatMode(.strict);
    var x = x_;
    const T = c_longdouble;
    const P0: T = -1.586135578666346600772998894928250240826E4;
    const P1: T = 2.642771505685952966904660652518429479531E3;
    const P2: T = -3.423199068835684263987132888286791620673E2;
    const P3: T = 1.800826371455042224581246202420972737840E1;
    const P4: T = -5.238523121205561042771939008061958820811E-1;
    const Q0: T = -9.516813471998079611319047060563358064497E4;
    const Q1: T = 3.964866271411091674556850458227710004570E4;
    const Q2: T = -7.207678383830091850230366618190187434796E3;
    const Q3: T = 7.206038318724600171970199625081491823079E2;
    const Q4: T = -4.002027679107076077238836622982900945173E1;
    const C1: T = 6.93145751953125E-1;
    const C2: T = 1.428606820309417232121458176568075500134E-6;
    const minarg: T = -4.5054566736396445112120088E1;
    const maxarg: T = 1.1356523406294143949492E4;

    if (math.isNan(x)) return x;
    if (x > maxarg) return x * @as(T, 0x1p16383);
    if (x == 0.0) return x;
    if (x < minarg) return -1.0;

    const ln2 = C1 + C2;
    const px0 = @floor(0.5 + x / ln2);
    const k: c_int = @intFromFloat(px0);
    x -= px0 * C1;
    x -= px0 * C2;

    const px = ((((P4 * x + P3) * x + P2) * x + P1) * x + P0) * x;
    const qx = ((((x + Q4) * x + Q3) * x + Q2) * x + Q1) * x + Q0;
    const xx = x * x;
    const r = x + (0.5 * xx + xx * px / qx);
    const scale = scalbnStrict(T, 1.0, k);
    return scale * r + (scale - 1.0);
}

fn expl_ld80(x_: c_longdouble) c_longdouble {
    @setFloatMode(.strict);
    var x = x_;
    const T = c_longdouble;
    const P = [_]T{
        1.2617719307481059087798E-4,
        3.0299440770744196129956E-2,
        9.9999999999999999991025E-1,
    };
    const Q = [_]T{
        3.0019850513866445504159E-6,
        2.5244834034968410419224E-3,
        2.2726554820815502876593E-1,
        2.0000000000000000000897E0,
    };
    const LN2HI: T = 6.9314575195312500000000E-1;
    const LN2LO: T = 1.4286068203094172321215E-6;
    const LOG2E: T = 1.4426950408889634073599E0;

    if (math.isNan(x)) return x;
    if (x > 11356.5234062941439488) return x * @as(T, 0x1p16383);
    if (x < -11399.4985314888605581) return -@as(T, 0x1p-16445) / x;

    const px0 = @floor(LOG2E * x + 0.5);
    const k: c_int = @intFromFloat(px0);
    x -= px0 * LN2HI;
    x -= px0 * LN2LO;

    const xx = x * x;
    const px = x * polevl(T, xx, &P);
    const y = 1.0 + 2.0 * (px / (polevl(T, xx, &Q) - px));
    return scalbnStrict(T, y, k);
}

fn polevl(comptime T: type, x: T, coeffs: []const T) T {
    var y = coeffs[0];
    for (coeffs[1..]) |c| y = y * x + c;
    return y;
}

/// Compute exp(x) using expm1. Uses only basic arithmetic — no @exp.
fn exp_pure(comptime T: type, x: T) T {
    if (T == c_longdouble and @typeInfo(c_longdouble).float.bits == 80) return @floatCast(expl_ld80(@floatCast(x)));
    if (x == 0) return 1.0;
    if (math.isNan(x)) return x;
    if (!math.isFinite(x)) {
        if (x > 0) return math.inf(T);
        return 0.0;
    }
    const ln2: T = 0.6931471805599453094172321214581765680755001343602552541206800094;
    const inv_ln2: T = 1.4426950408889634073599246810018921374266459541529859341354494069;
    const k_f: T = @round(x * inv_ln2);
    const r = x - k_f * ln2;
    if (k_f > 0x1p30) return math.inf(T);
    if (k_f < -0x1p30) return 0.0;
    const k: i32 = @intFromFloat(k_f);
    return scalbnStrict(T, 1.0 + taylor_expm1(T, r), k);
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

fn atanhGeneric(comptime T: type, x: T) T {
    if (math.isNan(x)) return x + x;
    const ax = @abs(x);
    if (ax > 1.0) {
        std.math.raiseInvalid();
        return math.nan(T);
    }
    if (ax == 1.0) {
        std.math.raiseDivByZero();
        return math.copysign(math.inf(T), x);
    }
    if (ax != 0.0 and ax < math.floatMin(T)) {
        std.math.raiseUnderflow();
        return x;
    }
    if (T == f32 or T == f64) return math.atanh(x);

    const half: T = 0.5;
    const y = if (ax < half) blk: {
        if (ax < @sqrt(math.floatEps(T))) {
            if (ax != 0.0) mem.doNotOptimizeAway(ax + @as(T, 0x1p120));
            break :blk ax;
        }
        break :blk half * log1p_wide(T, 2.0 * ax + 2.0 * ax * ax / (1.0 - ax));
    } else half * log1p_wide(T, 2.0 * (ax / (1.0 - ax)));

    return if (math.signbit(x)) -y else y;
}

fn atanh_(x: f64) callconv(.c) f64 {
    return atanhGeneric(f64, x);
}

fn atanhf_(x: f32) callconv(.c) f32 {
    return atanhGeneric(f32, x);
}

fn atanhWide(comptime T: type, x: T) T {
    @setFloatMode(.strict);
    if (math.isNan(x)) return x + x;
    const ax = @abs(x);
    if (ax > 1.0) {
        std.math.raiseInvalid();
        return math.nan(T);
    }
    if (ax == 1.0) {
        std.math.raiseDivByZero();
        return math.copysign(math.inf(T), x);
    }
    if (ax != 0.0 and ax < math.floatMin(T)) {
        std.math.raiseUnderflow();
        return x;
    }

    const half: T = 0.5;
    const y = if (ax < half) blk: {
        if (ax < @sqrt(math.floatEps(T))) {
            if (ax != 0.0) mem.doNotOptimizeAway(ax + @as(T, 0x1p120));
            break :blk ax;
        }
        break :blk half * log1p_wide(T, 2.0 * ax + 2.0 * ax * ax / (1.0 - ax));
    } else half * log1p_wide(T, 2.0 * (ax / (1.0 - ax)));

    return if (math.signbit(x)) -y else y;
}

fn atanh64Strict(x: f64) f64 {
    @setFloatMode(.strict);
    const u: u64 = @bitCast(x);
    const e = (u >> 52) & 0x7ff;
    const s = u >> 63;
    const y: f64 = @bitCast(u & (std.math.maxInt(u64) >> 1));

    if (math.isNan(x)) return x + x;
    if (y > 1.0) {
        std.math.raiseInvalid();
        return math.nan(f64);
    }
    if (y == 1.0) {
        std.math.raiseDivByZero();
        return math.copysign(math.inf(f64), x);
    }
    if (e < 0x3ff - 32) {
        if (y != 0.0 and y < math.floatMin(f64)) std.math.raiseUnderflow();
        return x;
    }

    const ay: f128 = @floatCast(y);
    const r: f64 = if (e < 0x3ff - 1)
        @floatCast(0.5 * log1p_wide(f128, 2.0 * ay + 2.0 * ay * ay / (1.0 - ay)))
    else
        @floatCast(0.5 * log1p_wide(f128, 2.0 * (ay / (1.0 - ay))));

    return if (s != 0) -r else r;
}

fn atanhl_(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => atanh64Strict(@bitCast(x)),
        else => atanhWide(c_longdouble, x),
    };
}

fn coshl_(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => math.cosh(@as(f64, @bitCast(x))),
        else => coshl_impl(c_longdouble, x),
    };
}

fn coshl_impl(comptime T: type, x_: T) T {
    @setFloatMode(.strict);
    const x = @abs(x_);
    if (x < @as(T, 0.6931471805599453094172321214581765680755001343602552541206800094)) {
        if (x < 0x1p-32) {
            mem.doNotOptimizeAway(x + @as(T, 0x1p120));
            return 1.0;
        }
        const t = expm1_wide(T, x);
        return 1.0 + t * t / (2.0 * (1.0 + t));
    }
    if (x < @as(T, 0x1.62e42fefa39efp+13)) {
        const t = exp_pure(T, x);
        return 0.5 * (t + 1.0 / t);
    }
    if (math.isFinite(x_)) std.math.raiseOverflow();
    const t = exp_pure(T, 0.5 * x);
    return 0.5 * t * t;
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
    const absx: f64 = @bitCast(absu);
    const h: f64 = if (u >> 63 != 0) -0.5 else 0.5;

    if (w < 0x40862e42) {
        const t = expm1(absx);
        if (w < 0x3ff00000) {
            if (w < 0x3ff00000 - (26 << 20))
                return x_;
            return h * (2.0 * t - t * t / (t + 1.0));
        }
        return h * (t + t / (t + 1.0));
    }

    return expo2(absx, 2.0 * h);
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
    if (absx != 0 and absx < math.floatMin(T)) std.math.raiseUnderflow();
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
    if (math.isFinite(x_)) std.math.raiseOverflow();
    const t = exp_pure(T, @as(T, 0.5) * absx);
    return h * t * t;
}

fn tanhl_(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => math.tanh(@as(f64, @bitCast(x))),
        else => tanhl_impl(c_longdouble, x),
    };
}

fn tanhl_impl(comptime T: type, x_: T) T {
    @setFloatMode(.strict);
    const x = @abs(x_);
    const t = if (x > @as(T, 0.54930614433405484569762261846126285232374527891137472586735) or math.isNan(x)) blk: {
        if (x >= 32.0) break :blk 1.0 + 0.0 / (x + @as(T, 0x1p-120));
        const u = expm1_wide(T, 2.0 * x);
        break :blk 1.0 - 2.0 / (u + 2.0);
    } else if (x > @as(T, 0.25541281188299534160275704815183096747321036424720147422818)) blk: {
        const u = expm1_wide(T, 2.0 * x);
        break :blk u / (u + 2.0);
    } else blk: {
        const u = expm1_wide(T, -2.0 * x);
        break :blk -u / (u + 2.0);
    };
    return if (math.signbit(x_)) -t else t;
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
    const Bits = @Int(.unsigned, bits);
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

fn atan2(y: f64, x: f64) callconv(.c) f64 {
    return math.atan2(y, x);
}

fn atan2f(y: f32, x: f32) callconv(.c) f32 {
    return math.atan2(y, x);
}

fn fma(x: f64, y: f64, z: f64) callconv(.c) f64 {
    return @mulAdd(f64, x, y, z);
}

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
            const m: u64 = @truncate(ux);
            const msb: u1 = @truncate(m >> 63);
            if (e == 0 and msb == 0) break :blk if (m != 0) @as(c_int, 3) else @as(c_int, 2);
            if (e == 0x7fff) {
                if (msb == 0) break :blk @as(c_int, 0);
                break :blk if ((m << 1) != 0) @as(c_int, 0) else @as(c_int, 1);
            }
            break :blk if (msb != 0) @as(c_int, 4) else @as(c_int, 0);
        },
        128 => blk: {
            const ux: u128 = @bitCast(x);
            const e: u32 = @truncate((ux >> 112) & 0x7fff);
            if (e == 0) break :blk if ((ux << 1) != 0) @as(c_int, 3) else @as(c_int, 2);
            if (e == 0x7fff) break :blk if ((ux << 16) != 0) @as(c_int, 0) else @as(c_int, 1);
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

fn nextafter(x: f64, y: f64) callconv(.c) f64 {
    @setFloatMode(.strict);
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
        mem.doNotOptimizeAway(x * x + val * val);
    }
    return @bitCast(ux);
}

fn nexttoward(x: f64, y: c_longdouble) callconv(.c) f64 {
    @setFloatMode(.strict);
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
        mem.doNotOptimizeAway(x * x + val * val);
    }
    return @bitCast(ux);
}

fn scalb(x: f64, fn_: f64) callconv(.c) f64 {
    @setFloatMode(.strict);
    if (math.isNan(x) or math.isNan(fn_)) return x * fn_;
    if (!math.isFinite(fn_)) {
        if (fn_ > 0.0) return x * fn_;
        return x / (-fn_);
    }
    if (rint(fn_) != fn_) return (fn_ - fn_) / (fn_ - fn_);
    if (fn_ > 65000.0) return scalbnStrict(f64, x, 65000);
    if (-fn_ > 65000.0) return scalbnStrict(f64, x, -65000);
    const n: i32 = @intFromFloat(fn_);
    return scalbnStrict(f64, x, n);
}

fn intFromFloat(comptime I: type, x: anytype) I {
    const F = @TypeOf(x);
    if (math.isNan(x) or !math.isFinite(x)) {
        std.math.raiseInvalid();
        return math.minInt(I);
    }
    const upper: F = @floatFromInt(@as(comptime_int, math.maxInt(I)) + 1);
    const lower: F = @floatFromInt(math.minInt(I));
    if (x >= upper or x < lower) {
        std.math.raiseInvalid();
        return math.minInt(I);
    }
    return @intFromFloat(x);
}

fn llrint(x: f64) callconv(.c) c_longlong {
    return intFromFloat(c_longlong, rint(x));
}

fn lrint(x: f64) callconv(.c) c_long {
    return intFromFloat(c_long, rint(x));
}

fn nearbyint(x: f64) callconv(.c) f64 {
    return nearbyintWithFlags(f64, rint, x);
}

fn powl(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    return @floatCast(math.pow(f64, @floatCast(x), @floatCast(y)));
}

fn sinh(x: f64) callconv(.c) f64 {
    return math.sinh(x);
}

fn cbrtl80(x_: f80) f80 {
    @setFloatMode(.strict);
    const B1: u32 = 709958130;
    var u_bits: u80 = @bitCast(x_);
    const se: u16 = @truncate(u_bits >> 64);
    var e: i32 = @intCast(se & 0x7fff);
    const sign: u16 = se & 0x8000;

    if (e == 0x7fff) return x_ + x_;
    if (e == 0) {
        const u_norm: f80 = x_ * 0x1p120;
        u_bits = @bitCast(u_norm);
        e = @intCast(@as(u16, @truncate(u_bits >> 64)) & 0x7fff);
        if (e == 0) return x_;
        e -= 120;
    }
    e -= 0x3fff;
    u_bits = (u_bits & 0xffffffffffffffff) | (@as(u80, 0x3fff) << 64);
    var x: f80 = @bitCast(u_bits);
    switch (@rem(e, 3)) {
        1, -2 => {
            x *= 2.0;
            e -= 1;
        },
        2, -1 => {
            x *= 4.0;
            e -= 2;
        },
        else => {},
    }
    const v_se: u16 = sign | @as(u16, @intCast(0x3fff + @divTrunc(e, 3)));
    const v_f: f80 = @bitCast((@as(u80, v_se) << 64) | (@as(u80, 1) << 63));

    const uft_f: f32 = @floatCast(x);
    const uft_i: u32 = ((@as(u32, @bitCast(uft_f)) & 0x7fffffff) / 3) + B1;
    const ft: f32 = @bitCast(uft_i);

    const dx: f64 = @floatCast(x);
    var dt: f64 = @floatCast(ft);
    var dr: f64 = dt * dt * dt;
    dt = dt * (dx + dx + dr) / (dx + dr + dr);

    dr = dt * dt * dt;
    dt = dt * (dx + dx + dr) / (dx + dr + dr);

    var t: f80 = @as(f80, @floatCast(dt)) + (@as(f80, 0x1.0p32) + @as(f80, 0x1.0p-31)) - @as(f80, 0x1.0p32);

    const s: f80 = t * t;
    var r: f80 = x / s;
    const w: f80 = t + t;
    r = (r - t) / (w + r);
    t = t + t * r;

    t *= v_f;
    return t;
}

fn cbrtl128(x_: f128) f128 {
    @setFloatMode(.strict);
    const B1: u32 = 709958130;
    const mant_mask: u128 = (@as(u128, 1) << 112) - 1;
    var u_bits: u128 = @bitCast(x_);
    const se: u16 = @truncate(u_bits >> 112);
    var e: i32 = @intCast(se & 0x7fff);
    const sign: u16 = se & 0x8000;

    if (e == 0x7fff) return x_ + x_;
    if (e == 0) {
        const u_norm: f128 = x_ * 0x1p120;
        u_bits = @bitCast(u_norm);
        e = @intCast(@as(u16, @truncate(u_bits >> 112)) & 0x7fff);
        if (e == 0) return x_;
        e -= 120;
    }
    e -= 0x3fff;
    u_bits = (u_bits & mant_mask) | (@as(u128, 0x3fff) << 112);
    var x: f128 = @bitCast(u_bits);
    switch (@rem(e, 3)) {
        1, -2 => {
            x *= 2.0;
            e -= 1;
        },
        2, -1 => {
            x *= 4.0;
            e -= 2;
        },
        else => {},
    }
    const v_se: u16 = sign | @as(u16, @intCast(0x3fff + @divTrunc(e, 3)));
    const v_f: f128 = @bitCast(@as(u128, v_se) << 112);

    const uft_f: f32 = @floatCast(x);
    const uft_i: u32 = ((@as(u32, @bitCast(uft_f)) & 0x7fffffff) / 3) + B1;
    const ft: f32 = @bitCast(uft_i);

    const dx: f64 = @floatCast(x);
    var dt: f64 = @floatCast(ft);
    var dr: f64 = dt * dt * dt;
    dt = dt * (dx + dx + dr) / (dx + dr + dr);

    dr = dt * dt * dt;
    dt = dt * (dx + dx + dr) / (dx + dr + dr);

    var t: f128 = @as(f128, @floatCast(dt + 0x2.0p-46)) + @as(f128, 0x1.0p60) - @as(f128, 0x1.0p60);

    const s: f128 = t * t;
    var r: f128 = x / s;
    const w: f128 = t + t;
    r = (r - t) / (w + r);
    t = t + t * r;

    t *= v_f;
    return t;
}

fn cbrtl_(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => @floatCast(cbrt(@floatCast(x))),
        80 => @floatCast(cbrtl80(@floatCast(x))),
        128 => @floatCast(cbrtl128(@floatCast(x))),
        else => unreachable,
    };
}

fn x87Atan2(y: c_longdouble, x: c_longdouble) c_longdouble {
    var in_y = y;
    var in_x = x;
    var r: c_longdouble = undefined;
    if (comptime builtin.target.cpu.arch == .x86_64) {
        asm volatile (
            \\fldt (%%rax)
            \\fldt (%%rdx)
            \\fpatan
            \\fstpt (%%rcx)
            :
            : [y] "{rax}" (&in_y),
              [x] "{rdx}" (&in_x),
              [out] "{rcx}" (&r),
            : .{ .memory = true, .st0 = true, .st1 = true });
    } else {
        asm volatile (
            \\fldt (%%eax)
            \\fldt (%%edx)
            \\fpatan
            \\fstpt (%%ecx)
            :
            : [y] "{eax}" (&in_y),
              [x] "{edx}" (&in_x),
              [out] "{ecx}" (&r),
            : .{ .memory = true, .st0 = true, .st1 = true });
    }
    return r;
}

fn atan2l80(y: f80, x: f80) f80 {
    @setFloatMode(.strict);
    const pio2_hi: f80 = 0x1.921fb54442d1846ap+0;
    const pio2_lo: f80 = -0x1.fc8f8cbb5bf8f897p-66;
    if (math.isNan(x) or math.isNan(y)) return x + y;
    if (x == 1.0) return @floatCast(atanl(@floatCast(y)));

    const ux: u80 = @bitCast(x);
    const uy: u80 = @bitCast(y);
    const ex: u32 = @as(u16, @truncate(ux >> 64)) & 0x7fff;
    const ey: u32 = @as(u16, @truncate(uy >> 64)) & 0x7fff;
    const m: u32 = (2 * (@as(u32, @truncate(ux >> 64)) >> 15)) | (@as(u32, @truncate(uy >> 64)) >> 15);
    if (y == 0.0) {
        return switch (m) {
            0, 1 => y,
            2 => 2.0 * pio2_hi,
            3 => -2.0 * pio2_hi,
            else => unreachable,
        };
    }
    if (x == 0.0) return if ((m & 1) != 0) -pio2_hi else pio2_hi;
    if (ex == 0x7fff) {
        if (ey == 0x7fff) {
            return switch (m) {
                0 => pio2_hi / 2.0,
                1 => -pio2_hi / 2.0,
                2 => 1.5 * pio2_hi,
                3 => -1.5 * pio2_hi,
                else => unreachable,
            };
        } else {
            return switch (m) {
                0 => 0.0,
                1 => -0.0,
                2 => 2.0 * pio2_hi,
                3 => -2.0 * pio2_hi,
                else => unreachable,
            };
        }
    }
    if (ex +% 120 < ey or ey == 0x7fff) return if ((m & 1) != 0) -pio2_hi else pio2_hi;
    const z: f80 = if ((m & 2) != 0 and ey +% 120 < ex) 0.0 else @floatCast(atanl(@floatCast(@abs(y / x))));
    return switch (m) {
        0 => z,
        1 => -z,
        2 => 2.0 * pio2_hi - (z - 2.0 * pio2_lo),
        3 => (z - 2.0 * pio2_lo) - 2.0 * pio2_hi,
        else => unreachable,
    };
}

fn atan2l128(y: f128, x: f128) f128 {
    @setFloatMode(.strict);
    const pio2_hi: f128 = 0x1.921fb54442d18469898cc51701b8p+0;
    const pio2_lo: f128 = 0x1.f97b839a252049c1114cf98e804p-114;
    if (math.isNan(x) or math.isNan(y)) return x + y;
    if (x == 1.0) return @floatCast(atanl(@floatCast(y)));

    const ux: u128 = @bitCast(x);
    const uy: u128 = @bitCast(y);
    const ex: u32 = @as(u16, @truncate(ux >> 112)) & 0x7fff;
    const ey: u32 = @as(u16, @truncate(uy >> 112)) & 0x7fff;
    const m: u32 = (2 * (@as(u32, @truncate(ux >> 112)) >> 15)) | (@as(u32, @truncate(uy >> 112)) >> 15);
    if (y == 0.0) {
        return switch (m) {
            0, 1 => y,
            2 => 2.0 * pio2_hi,
            3 => -2.0 * pio2_hi,
            else => unreachable,
        };
    }
    if (x == 0.0) return if ((m & 1) != 0) -pio2_hi else pio2_hi;
    if (ex == 0x7fff) {
        if (ey == 0x7fff) {
            return switch (m) {
                0 => pio2_hi / 2.0,
                1 => -pio2_hi / 2.0,
                2 => 1.5 * pio2_hi,
                3 => -1.5 * pio2_hi,
                else => unreachable,
            };
        } else {
            return switch (m) {
                0 => 0.0,
                1 => -0.0,
                2 => 2.0 * pio2_hi,
                3 => -2.0 * pio2_hi,
                else => unreachable,
            };
        }
    }
    if (ex +% 120 < ey or ey == 0x7fff) return if ((m & 1) != 0) -pio2_hi else pio2_hi;
    const z: f128 = if ((m & 2) != 0 and ey +% 120 < ex) 0.0 else @floatCast(atanl(@floatCast(@abs(y / x))));
    return switch (m) {
        0 => z,
        1 => -z,
        2 => 2.0 * pio2_hi - (z - 2.0 * pio2_lo),
        3 => (z - 2.0 * pio2_lo) - 2.0 * pio2_hi,
        else => unreachable,
    };
}

fn atan2l(y: c_longdouble, x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => @floatCast(atan2(@floatCast(y), @floatCast(x))),
        80 => switch (builtin.target.cpu.arch) {
            .x86, .x86_64 => x87Atan2(y, x),
            else => @floatCast(atan2l80(@floatCast(y), @floatCast(x))),
        },
        128 => @floatCast(atan2l128(@floatCast(y), @floatCast(x))),
        else => unreachable,
    };
}

fn erflIx(x: f80) u32 {
    const u: u80 = @bitCast(x);
    const se: u32 = @truncate(u >> 64);
    const m: u64 = @truncate(u);
    return ((se & 0x7fff) << 16) | @as(u32, @truncate(m >> 48));
}

fn erflErfc1(x: f80) f80 {
    const s = @abs(x) - 1;
    const P = erfl_pa[0] + s * (erfl_pa[1] + s * (erfl_pa[2] +
        s * (erfl_pa[3] + s * (erfl_pa[4] + s * (erfl_pa[5] + s * (erfl_pa[6] + s * erfl_pa[7]))))));
    const Q = erfl_qa[0] + s * (erfl_qa[1] + s * (erfl_qa[2] +
        s * (erfl_qa[3] + s * (erfl_qa[4] + s * (erfl_qa[5] + s * (erfl_qa[6] + s))))));
    return 1 - erfl_erx - P / Q;
}

fn erflErfc2(ix: u32, x_: f80) f80 {
    if (ix < 0x3fffa000) return erflErfc1(x_);

    const x = @abs(x_);
    const s = 1 / (x * x);
    var R: f80 = undefined;
    var S: f80 = undefined;

    if (ix < 0x4000b6db) {
        R = erfl_ra[0] + s * (erfl_ra[1] + s * (erfl_ra[2] + s * (erfl_ra[3] + s * (erfl_ra[4] +
            s * (erfl_ra[5] + s * (erfl_ra[6] + s * (erfl_ra[7] + s * erfl_ra[8])))))));
        S = erfl_sa[0] + s * (erfl_sa[1] + s * (erfl_sa[2] + s * (erfl_sa[3] + s * (erfl_sa[4] +
            s * (erfl_sa[5] + s * (erfl_sa[6] + s * (erfl_sa[7] + s * (erfl_sa[8] + s))))))));
    } else if (ix < 0x4001d555) {
        R = erfl_rb[0] + s * (erfl_rb[1] + s * (erfl_rb[2] + s * (erfl_rb[3] + s * (erfl_rb[4] +
            s * (erfl_rb[5] + s * (erfl_rb[6] + s * erfl_rb[7]))))));
        S = erfl_sb[0] + s * (erfl_sb[1] + s * (erfl_sb[2] + s * (erfl_sb[3] + s * (erfl_sb[4] +
            s * (erfl_sb[5] + s * (erfl_sb[6] + s))))));
    } else {
        R = erfl_rc[0] + s * (erfl_rc[1] + s * (erfl_rc[2] + s * (erfl_rc[3] +
            s * (erfl_rc[4] + s * erfl_rc[5]))));
        S = erfl_sc[0] + s * (erfl_sc[1] + s * (erfl_sc[2] + s * (erfl_sc[3] +
            s * (erfl_sc[4] + s))));
    }

    const z: f80 = @bitCast(@as(u80, @bitCast(x)) & (~@as(u80, 0) << 40));
    const e1: f80 = @floatCast(expl(@floatCast(-z * z - 0.5625)));
    const e2: f80 = @floatCast(expl(@floatCast((z - x) * (z + x) + R / S)));
    return e1 * e2 / x;
}

fn erfl80(x: f80) f80 {
    const ix = erflIx(x);
    const sign = @as(u32, @truncate(@as(u80, @bitCast(x)) >> 79));

    if (ix >= 0x7fff0000) return @as(f80, @floatFromInt(1 - 2 * @as(i32, @intCast(sign)))) + 1 / x;
    if (ix < 0x3ffed800) {
        if (ix < 0x3fde8000) return 0.125 * (8 * x + erfl_efx8 * x);
        const z = x * x;
        const r = erfl_pp[0] + z * (erfl_pp[1] + z * (erfl_pp[2] + z * (erfl_pp[3] + z * (erfl_pp[4] + z * erfl_pp[5]))));
        const s = erfl_qq[0] + z * (erfl_qq[1] + z * (erfl_qq[2] + z * (erfl_qq[3] + z * (erfl_qq[4] + z * (erfl_qq[5] + z)))));
        const y = r / s;
        return x + x * y;
    }
    const y = if (ix < 0x4001d555) 1 - erflErfc2(ix, x) else 1 - @as(f80, 0x1p-16382);
    return if (sign != 0) -y else y;
}

fn erfcl80(x: f80) f80 {
    const ix = erflIx(x);
    const sign = @as(u32, @truncate(@as(u80, @bitCast(x)) >> 79));

    if (ix >= 0x7fff0000) return @as(f80, @floatFromInt(2 * @as(i32, @intCast(sign)))) + 1 / x;
    if (ix < 0x3ffed800) {
        if (ix < 0x3fbe0000) return 1.0 - x;
        const z = x * x;
        const r = erfl_pp[0] + z * (erfl_pp[1] + z * (erfl_pp[2] + z * (erfl_pp[3] + z * (erfl_pp[4] + z * erfl_pp[5]))));
        const s = erfl_qq[0] + z * (erfl_qq[1] + z * (erfl_qq[2] + z * (erfl_qq[3] + z * (erfl_qq[4] + z * (erfl_qq[5] + z)))));
        const y = r / s;
        if (ix < 0x3ffd8000) return 1.0 - (x + x * y);
        return 0.5 - (x - 0.5 + x * y);
    }
    if (ix < 0x4005d600) return if (sign != 0) 2 - erflErfc2(ix, x) else erflErfc2(ix, x);
    const y: f80 = 0x1p-16382;
    return if (sign != 0) 2 - y else y * y;
}

fn erfl(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => @floatCast(erf_(@floatCast(x))),
        80 => @floatCast(erfl80(@floatCast(x))),
        128 => @floatCast(erf_(@floatCast(x))),
        else => math.erf(x),
    };
}

fn erfcl(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => @floatCast(erfc_(@floatCast(x))),
        80 => @floatCast(erfcl80(@floatCast(x))),
        128 => @floatCast(erfc_(@floatCast(x))),
        else => math.erfc(x),
    };
}

// migrated from musl/src/math/j0.c
const bessel_invsqrtpi64: f64 = 5.64189583547756279280e-01;
const bessel_tpi64: f64 = 6.36619772367581382433e-01;

const j0_R02: f64 = 1.56249999999999947958e-02;
const j0_R03: f64 = -1.89979294238854721751e-04;
const j0_R04: f64 = 1.82954049532700665670e-06;
const j0_R05: f64 = -4.61832688532103189199e-09;
const j0_S01: f64 = 1.56191029464890010492e-02;
const j0_S02: f64 = 1.16926784663337450260e-04;
const j0_S03: f64 = 5.13546550207318111446e-07;
const j0_S04: f64 = 1.16614003333790000205e-09;

const y0_u00: f64 = -7.38042951086872317523e-02;
const y0_u01: f64 = 1.76666452509181115538e-01;
const y0_u02: f64 = -1.38185671945596898896e-02;
const y0_u03: f64 = 3.47453432093683650238e-04;
const y0_u04: f64 = -3.81407053724364161125e-06;
const y0_u05: f64 = 1.95590137035022920206e-08;
const y0_u06: f64 = -3.98205194132103398453e-11;
const y0_v01: f64 = 1.27304834834123699328e-02;
const y0_v02: f64 = 7.60068627350353253702e-05;
const y0_v03: f64 = 2.59150851840457805467e-07;
const y0_v04: f64 = 4.41110311332675467403e-10;

const j0_pR8 = [_]f64{ 0.00000000000000000000e+00, -7.03124999999900357484e-02, -8.08167041275349795626e+00, -2.57063105679704847262e+02, -2.48521641009428822144e+03, -5.25304380490729545272e+03 };
const j0_pS8 = [_]f64{ 1.16534364619668181717e+02, 3.83374475364121826715e+03, 4.05978572648472545552e+04, 1.16752972564375915681e+05, 4.76277284146730962675e+04 };
const j0_pR5 = [_]f64{ -1.14125464691894502584e-11, -7.03124940873599280078e-02, -4.15961064470587782438e+00, -6.76747652265167261021e+01, -3.31231299649172967747e+02, -3.46433388365604912451e+02 };
const j0_pS5 = [_]f64{ 6.07539382692300335975e+01, 1.05125230595704579173e+03, 5.97897094333855784498e+03, 9.62544514357774460223e+03, 2.40605815922939109441e+03 };
const j0_pR3 = [_]f64{ -2.54704601771951915620e-09, -7.03119616381481654654e-02, -2.40903221549529611423e+00, -2.19659774734883086467e+01, -5.80791704701737572236e+01, -3.14479470594888503854e+01 };
const j0_pS3 = [_]f64{ 3.58560338055209726349e+01, 3.61513983050303863820e+02, 1.19360783792111533330e+03, 1.12799679856907414432e+03, 1.73580930813335754692e+02 };
const j0_pR2 = [_]f64{ -8.87534333032526411254e-08, -7.03030995483624743247e-02, -1.45073846780952986357e+00, -7.63569613823527770791e+00, -1.11931668860356747786e+01, -3.23364579351335335033e+00 };
const j0_pS2 = [_]f64{ 2.22202997532088808441e+01, 1.36206794218215208048e+02, 2.70470278658083486789e+02, 1.53875394208320329881e+02, 1.46576176948256193810e+01 };

const j0_qR8 = [_]f64{ 0.00000000000000000000e+00, 7.32421874999935051953e-02, 1.17682064682252693899e+01, 5.57673380256401856059e+02, 8.85919720756468632317e+03, 3.70146267776887834771e+04 };
const j0_qS8 = [_]f64{ 1.63776026895689824414e+02, 8.09834494656449805916e+03, 1.42538291419120476348e+05, 8.03309257119514397345e+05, 8.40501579819060512818e+05, -3.43899293537866615225e+05 };
const j0_qR5 = [_]f64{ 1.84085963594515531381e-11, 7.32421766612684765896e-02, 5.83563508962056953777e+00, 1.35111577286449829671e+02, 1.02724376596164097464e+03, 1.98997785864605384631e+03 };
const j0_qS5 = [_]f64{ 8.27766102236537761883e+01, 2.07781416421392987104e+03, 1.88472887785718085070e+04, 5.67511122894947329769e+04, 3.59767538425114471465e+04, -5.35434275601944773371e+03 };
const j0_qR3 = [_]f64{ 4.37741014089738620906e-09, 7.32411180042911447163e-02, 3.34423137516170720929e+00, 4.26218440745412650017e+01, 1.70808091340565596283e+02, 1.66733948696651168575e+02 };
const j0_qS3 = [_]f64{ 4.87588729724587182091e+01, 7.09689221056606015736e+02, 3.70414822620111362994e+03, 6.46042516752568917582e+03, 2.51633368920368957333e+03, -1.49247451836156386662e+02 };
const j0_qR2 = [_]f64{ 1.50444444886983272379e-07, 7.32234265963079278272e-02, 1.99819174093815998816e+00, 1.44956029347885735348e+01, 3.16662317504781540833e+01, 1.62527075710929267416e+01 };
const j0_qS2 = [_]f64{ 3.03655848355219184498e+01, 2.69348118608049844624e+02, 8.44783757595320139444e+02, 8.82935845112488550512e+02, 2.12666388511798828631e+02, -5.31095493882666946917e+00 };

fn j0_common(ix: u32, x: f64, y0_: bool) f64 {
    const s = math.sin(x);
    var c = math.cos(x);
    if (y0_) c = -c;
    var cc = s + c;
    if (ix < 0x7fe00000) {
        var ss = s - c;
        const z = -math.cos(2 * x);
        if (s * c < 0)
            cc = z / ss
        else
            ss = z / cc;
        if (ix < 0x48000000) {
            if (y0_) ss = -ss;
            cc = j0_pzero(x) * cc - j0_qzero(x) * ss;
        }
    }
    return bessel_invsqrtpi64 * cc / @sqrt(x);
}

fn j0(x_: f64) callconv(.c) f64 {
    const bits: u64 = @bitCast(x_);
    var ix: u32 = @truncate(bits >> 32);
    ix &= 0x7fffffff;

    if (ix >= 0x7ff00000) return 1 / (x_ * x_);
    const x = @abs(x_);
    if (ix >= 0x40000000) return j0_common(ix, x, false);
    if (ix >= 0x3f200000) {
        const z = x * x;
        const r = z * (j0_R02 + z * (j0_R03 + z * (j0_R04 + z * j0_R05)));
        const s = 1 + z * (j0_S01 + z * (j0_S02 + z * (j0_S03 + z * j0_S04)));
        return (1 + x / 2) * (1 - x / 2) + z * (r / s);
    }
    var y = x;
    if (ix >= 0x38000000) y = 0.25 * y * y;
    return 1 - y;
}

fn y0(x: f64) callconv(.c) f64 {
    const bits: u64 = @bitCast(x);
    const ix: u32 = @truncate(bits >> 32);
    const lx: u32 = @truncate(bits);

    if (((ix << 1) | lx) == 0) return -1 / @as(f64, 0.0);
    if ((ix >> 31) != 0) return 0 / @as(f64, 0.0);
    if (ix >= 0x7ff00000) return 1 / x;
    if (ix >= 0x40000000) return j0_common(ix, x, true);
    if (ix >= 0x3e400000) {
        const z = x * x;
        const u = y0_u00 + z * (y0_u01 + z * (y0_u02 + z * (y0_u03 + z * (y0_u04 + z * (y0_u05 + z * y0_u06)))));
        const v = 1.0 + z * (y0_v01 + z * (y0_v02 + z * (y0_v03 + z * y0_v04)));
        return u / v + bessel_tpi64 * (j0(x) * math.log(f64, math.e, x));
    }
    return y0_u00 + bessel_tpi64 * math.log(f64, math.e, x);
}

fn j0_pzero(x: f64) f64 {
    var p: []const f64 = undefined;
    var q: []const f64 = undefined;
    const bits: u64 = @bitCast(x);
    const ix: u32 = @as(u32, @truncate(bits >> 32)) & 0x7fffffff;
    if (ix >= 0x40200000) {
        p = j0_pR8[0..];
        q = j0_pS8[0..];
    } else if (ix >= 0x40122E8B) {
        p = j0_pR5[0..];
        q = j0_pS5[0..];
    } else if (ix >= 0x4006DB6D) {
        p = j0_pR3[0..];
        q = j0_pS3[0..];
    } else {
        p = j0_pR2[0..];
        q = j0_pS2[0..];
    }
    const z = 1.0 / (x * x);
    const r = p[0] + z * (p[1] + z * (p[2] + z * (p[3] + z * (p[4] + z * p[5]))));
    const s = 1.0 + z * (q[0] + z * (q[1] + z * (q[2] + z * (q[3] + z * q[4]))));
    return 1.0 + r / s;
}

fn j0_qzero(x: f64) f64 {
    var p: []const f64 = undefined;
    var q: []const f64 = undefined;
    const bits: u64 = @bitCast(x);
    const ix: u32 = @as(u32, @truncate(bits >> 32)) & 0x7fffffff;
    if (ix >= 0x40200000) {
        p = j0_qR8[0..];
        q = j0_qS8[0..];
    } else if (ix >= 0x40122E8B) {
        p = j0_qR5[0..];
        q = j0_qS5[0..];
    } else if (ix >= 0x4006DB6D) {
        p = j0_qR3[0..];
        q = j0_qS3[0..];
    } else {
        p = j0_qR2[0..];
        q = j0_qS2[0..];
    }
    const z = 1.0 / (x * x);
    const r = p[0] + z * (p[1] + z * (p[2] + z * (p[3] + z * (p[4] + z * p[5]))));
    const s = 1.0 + z * (q[0] + z * (q[1] + z * (q[2] + z * (q[3] + z * (q[4] + z * q[5])))));
    return (-0.125 + r / s) / x;
}

// migrated from musl/src/math/j0f.c
const bessel_invsqrtpi32: f32 = 5.6418961287e-01;
const bessel_tpi32: f32 = 6.3661974669e-01;

const j0f_R02: f32 = 1.5625000000e-02;
const j0f_R03: f32 = -1.8997929874e-04;
const j0f_R04: f32 = 1.8295404516e-06;
const j0f_R05: f32 = -4.6183270541e-09;
const j0f_S01: f32 = 1.5619102865e-02;
const j0f_S02: f32 = 1.1692678527e-04;
const j0f_S03: f32 = 5.1354652442e-07;
const j0f_S04: f32 = 1.1661400734e-09;

const y0f_u00: f32 = -7.3804296553e-02;
const y0f_u01: f32 = 1.7666645348e-01;
const y0f_u02: f32 = -1.3818567619e-02;
const y0f_u03: f32 = 3.4745343146e-04;
const y0f_u04: f32 = -3.8140706238e-06;
const y0f_u05: f32 = 1.9559013964e-08;
const y0f_u06: f32 = -3.9820518410e-11;
const y0f_v01: f32 = 1.2730483897e-02;
const y0f_v02: f32 = 7.6006865129e-05;
const y0f_v03: f32 = 2.5915085189e-07;
const y0f_v04: f32 = 4.4111031494e-10;

const j0f_pR8 = [_]f32{ 0.0000000000e+00, -7.0312500000e-02, -8.0816707611e+00, -2.5706311035e+02, -2.4852163086e+03, -5.2530439453e+03 };
const j0f_pS8 = [_]f32{ 1.1653436279e+02, 3.8337448730e+03, 4.0597855469e+04, 1.1675296875e+05, 4.7627726562e+04 };
const j0f_pR5 = [_]f32{ -1.1412546255e-11, -7.0312492549e-02, -4.1596107483e+00, -6.7674766541e+01, -3.3123129272e+02, -3.4643338013e+02 };
const j0f_pS5 = [_]f32{ 6.0753936768e+01, 1.0512523193e+03, 5.9789707031e+03, 9.6254453125e+03, 2.4060581055e+03 };
const j0f_pR3 = [_]f32{ -2.5470459075e-09, -7.0311963558e-02, -2.4090321064e+00, -2.1965976715e+01, -5.8079170227e+01, -3.1447946548e+01 };
const j0f_pS3 = [_]f32{ 3.5856033325e+01, 3.6151397705e+02, 1.1936077881e+03, 1.1279968262e+03, 1.7358093262e+02 };
const j0f_pR2 = [_]f32{ -8.8753431271e-08, -7.0303097367e-02, -1.4507384300e+00, -7.6356959343e+00, -1.1193166733e+01, -3.2336456776e+00 };
const j0f_pS2 = [_]f32{ 2.2220300674e+01, 1.3620678711e+02, 2.7047027588e+02, 1.5387539673e+02, 1.4657617569e+01 };

const j0f_qR8 = [_]f32{ 0.0000000000e+00, 7.3242187500e-02, 1.1768206596e+01, 5.5767340088e+02, 8.8591972656e+03, 3.7014625000e+04 };
const j0f_qS8 = [_]f32{ 1.6377603149e+02, 8.0983447266e+03, 1.4253829688e+05, 8.0330925000e+05, 8.4050156250e+05, -3.4389928125e+05 };
const j0f_qR5 = [_]f32{ 1.8408595828e-11, 7.3242180049e-02, 5.8356351852e+00, 1.3511157227e+02, 1.0272437744e+03, 1.9899779053e+03 };
const j0f_qS5 = [_]f32{ 8.2776611328e+01, 2.0778142090e+03, 1.8847289062e+04, 5.6751113281e+04, 3.5976753906e+04, -5.3543427734e+03 };
const j0f_qR3 = [_]f32{ 4.3774099900e-09, 7.3241114616e-02, 3.3442313671e+00, 4.2621845245e+01, 1.7080809021e+02, 1.6673394775e+02 };
const j0f_qS3 = [_]f32{ 4.8758872986e+01, 7.0968920898e+02, 3.7041481934e+03, 6.4604252930e+03, 2.5163337402e+03, -1.4924745178e+02 };
const j0f_qR2 = [_]f32{ 1.5044444979e-07, 7.3223426938e-02, 1.9981917143e+00, 1.4495602608e+01, 3.1666231155e+01, 1.6252708435e+01 };
const j0f_qS2 = [_]f32{ 3.0365585327e+01, 2.6934811401e+02, 8.4478375244e+02, 8.8293585205e+02, 2.1266638184e+02, -5.3109550476e+00 };

fn j0f_common(ix: u32, x: f32, y0_: bool) f32 {
    const s = math.sin(x);
    var c = math.cos(x);
    if (y0_) c = -c;
    var cc = s + c;
    if (ix < 0x7f000000) {
        var ss = s - c;
        const z = -math.cos(2 * x);
        if (s * c < 0)
            cc = z / ss
        else
            ss = z / cc;
        if (ix < 0x58800000) {
            if (y0_) ss = -ss;
            cc = j0f_pzero(x) * cc - j0f_qzero(x) * ss;
        }
    }
    return bessel_invsqrtpi32 * cc / @sqrt(x);
}

fn j0f(x_: f32) callconv(.c) f32 {
    var ix: u32 = @bitCast(x_);
    ix &= 0x7fffffff;
    if (ix >= 0x7f800000) return 1 / (x_ * x_);
    const x = @abs(x_);
    if (ix >= 0x40000000) return j0f_common(ix, x, false);
    if (ix >= 0x3a000000) {
        const z = x * x;
        const r = z * (j0f_R02 + z * (j0f_R03 + z * (j0f_R04 + z * j0f_R05)));
        const s = 1 + z * (j0f_S01 + z * (j0f_S02 + z * (j0f_S03 + z * j0f_S04)));
        return (1 + x / 2) * (1 - x / 2) + z * (r / s);
    }
    var y = x;
    if (ix >= 0x21800000) y = 0.25 * y * y;
    return 1 - y;
}

fn y0f(x: f32) callconv(.c) f32 {
    const ix: u32 = @bitCast(x);
    if ((ix & 0x7fffffff) == 0) return -1 / @as(f32, 0.0);
    if ((ix >> 31) != 0) return 0 / @as(f32, 0.0);
    if (ix >= 0x7f800000) return 1 / x;
    if (ix >= 0x40000000) return j0f_common(ix, x, true);
    if (ix >= 0x39000000) {
        const z = x * x;
        const u = y0f_u00 + z * (y0f_u01 + z * (y0f_u02 + z * (y0f_u03 + z * (y0f_u04 + z * (y0f_u05 + z * y0f_u06)))));
        const v = 1 + z * (y0f_v01 + z * (y0f_v02 + z * (y0f_v03 + z * y0f_v04)));
        return u / v + bessel_tpi32 * (j0f(x) * math.log(f32, math.e, x));
    }
    return y0f_u00 + bessel_tpi32 * math.log(f32, math.e, x);
}

fn j0f_pzero(x: f32) f32 {
    var p: []const f32 = undefined;
    var q: []const f32 = undefined;
    const ix = @as(u32, @bitCast(x)) & 0x7fffffff;
    if (ix >= 0x41000000) {
        p = j0f_pR8[0..];
        q = j0f_pS8[0..];
    } else if (ix >= 0x409173eb) {
        p = j0f_pR5[0..];
        q = j0f_pS5[0..];
    } else if (ix >= 0x4036d917) {
        p = j0f_pR3[0..];
        q = j0f_pS3[0..];
    } else {
        p = j0f_pR2[0..];
        q = j0f_pS2[0..];
    }
    const z = 1.0 / (x * x);
    const r = p[0] + z * (p[1] + z * (p[2] + z * (p[3] + z * (p[4] + z * p[5]))));
    const s = 1.0 + z * (q[0] + z * (q[1] + z * (q[2] + z * (q[3] + z * q[4]))));
    return 1.0 + r / s;
}

fn j0f_qzero(x: f32) f32 {
    var p: []const f32 = undefined;
    var q: []const f32 = undefined;
    const ix = @as(u32, @bitCast(x)) & 0x7fffffff;
    if (ix >= 0x41000000) {
        p = j0f_qR8[0..];
        q = j0f_qS8[0..];
    } else if (ix >= 0x409173eb) {
        p = j0f_qR5[0..];
        q = j0f_qS5[0..];
    } else if (ix >= 0x4036d917) {
        p = j0f_qR3[0..];
        q = j0f_qS3[0..];
    } else {
        p = j0f_qR2[0..];
        q = j0f_qS2[0..];
    }
    const z = 1.0 / (x * x);
    const r = p[0] + z * (p[1] + z * (p[2] + z * (p[3] + z * (p[4] + z * p[5]))));
    const s = 1.0 + z * (q[0] + z * (q[1] + z * (q[2] + z * (q[3] + z * (q[4] + z * q[5])))));
    return (-0.125 + r / s) / x;
}

// migrated from musl/src/math/j1.c
const j1_r00: f64 = -6.25000000000000000000e-02;
const j1_r01: f64 = 1.40705666955189706048e-03;
const j1_r02: f64 = -1.59955631084035597520e-05;
const j1_r03: f64 = 4.96727999609584448412e-08;
const j1_s01: f64 = 1.91537599538363460805e-02;
const j1_s02: f64 = 1.85946785588630915560e-04;
const j1_s03: f64 = 1.17718464042623683263e-06;
const j1_s04: f64 = 5.04636257076217042715e-09;
const j1_s05: f64 = 1.23542274426137913908e-11;

const y1_U0 = [_]f64{ -1.96057090646238940668e-01, 5.04438716639811282616e-02, -1.91256895875763547298e-03, 2.35252600561610495928e-05, -9.19099158039878874504e-08 };
const y1_V0 = [_]f64{ 1.99167318236649903973e-02, 2.02552581025135171496e-04, 1.35608801097516229404e-06, 6.22741452364621501295e-09, 1.66559246207992079114e-11 };

const j1_pr8 = [_]f64{ 0.00000000000000000000e+00, 1.17187499999988647970e-01, 1.32394806593073575129e+01, 4.12051854307378562225e+02, 3.87474538913960532227e+03, 7.91447954031891731574e+03 };
const j1_ps8 = [_]f64{ 1.14207370375678408436e+02, 3.65093083420853463394e+03, 3.69562060269033463555e+04, 9.76027935934950801311e+04, 3.08042720627888811578e+04 };
const j1_pr5 = [_]f64{ 1.31990519556243522749e-11, 1.17187493190614097638e-01, 6.80275127868432871736e+00, 1.08308182990189109773e+02, 5.17636139533199752805e+02, 5.28715201363337541807e+02 };
const j1_ps5 = [_]f64{ 5.92805987221131331921e+01, 9.91401418733614377743e+02, 5.35326695291487976647e+03, 7.84469031749551231769e+03, 1.50404688810361062679e+03 };
const j1_pr3 = [_]f64{ 3.02503916137373618024e-09, 1.17186865567253592491e-01, 3.93297750033315640650e+00, 3.51194035591636932736e+01, 9.10550110750781271918e+01, 4.85590685197364919645e+01 };
const j1_ps3 = [_]f64{ 3.47913095001251519989e+01, 3.36762458747825746741e+02, 1.04687139975775130551e+03, 8.90811346398256432622e+02, 1.03787932439639277504e+02 };
const j1_pr2 = [_]f64{ 1.07710830106873743082e-07, 1.17176219462683348094e-01, 2.36851496667608785174e+00, 1.22426109148261232917e+01, 1.76939711271687727390e+01, 5.07352312588818499250e+00 };
const j1_ps2 = [_]f64{ 2.14364859363821409488e+01, 1.25290227168402751090e+02, 2.32276469057162813669e+02, 1.17679373287147100768e+02, 8.36463893371618283368e+00 };

const j1_qr8 = [_]f64{ 0.00000000000000000000e+00, -1.02539062499992714161e-01, -1.62717534544589987888e+01, -7.59601722513950107896e+02, -1.18498066702429587167e+04, -4.84385124285750353010e+04 };
const j1_qs8 = [_]f64{ 1.61395369700722909556e+02, 7.82538599923348465381e+03, 1.33875336287249578163e+05, 7.19657723683240939863e+05, 6.66601232617776375264e+05, -2.94490264303834643215e+05 };
const j1_qr5 = [_]f64{ -2.08979931141764104297e-11, -1.02539050241375426231e-01, -8.05644828123936029840e+00, -1.83669607474888380239e+02, -1.37319376065508163265e+03, -2.61244440453215656817e+03 };
const j1_qs5 = [_]f64{ 8.12765501384335777857e+01, 1.99179873460485964642e+03, 1.74684851924908907677e+04, 4.98514270910352279316e+04, 2.79480751638918118260e+04, -4.71918354795128470869e+03 };
const j1_qr3 = [_]f64{ -5.07831226461766561369e-09, -1.02537829820837089745e-01, -4.61011581139473403113e+00, -5.78472216562783643212e+01, -2.28244540737631695038e+02, -2.19210128478909325622e+02 };
const j1_qs3 = [_]f64{ 4.76651550323729509273e+01, 6.73865112676699709482e+02, 3.38015286679526343505e+03, 5.54772909720722782367e+03, 1.90311919338810798763e+03, -1.35201191444307340817e+02 };
const j1_qr2 = [_]f64{ -1.78381727510958865572e-07, -1.02517042607985553460e-01, -2.75220568278187460720e+00, -1.96636162643703720221e+01, -4.23253133372830490089e+01, -2.13719211703704061733e+01 };
const j1_qs2 = [_]f64{ 2.95333629060523854548e+01, 2.52981549982190529136e+02, 7.57502834868645436472e+02, 7.39393205320467245656e+02, 1.55949003336666123687e+02, -4.95949898822628210127e+00 };

fn j1_common(ix: u32, x: f64, y1_: bool, sign: bool) f64 {
    var s = math.sin(x);
    if (y1_) s = -s;
    const c = math.cos(x);
    var cc = s - c;
    if (ix < 0x7fe00000) {
        var ss = -s - c;
        const z = math.cos(2 * x);
        if (s * c > 0)
            cc = z / ss
        else
            ss = z / cc;
        if (ix < 0x48000000) {
            if (y1_) ss = -ss;
            cc = j1_pone(x) * cc - j1_qone(x) * ss;
        }
    }
    if (sign) cc = -cc;
    return bessel_invsqrtpi64 * cc / @sqrt(x);
}

fn j1(x: f64) callconv(.c) f64 {
    const bits: u64 = @bitCast(x);
    var ix: u32 = @truncate(bits >> 32);
    const sign = (ix >> 31) != 0;
    ix &= 0x7fffffff;
    if (ix >= 0x7ff00000) return 1 / (x * x);
    if (ix >= 0x40000000) return j1_common(ix, @abs(x), false, sign);
    const z = if (ix >= 0x38000000) blk: {
        const x2 = x * x;
        const r = x2 * (j1_r00 + x2 * (j1_r01 + x2 * (j1_r02 + x2 * j1_r03)));
        const s = 1 + x2 * (j1_s01 + x2 * (j1_s02 + x2 * (j1_s03 + x2 * (j1_s04 + x2 * j1_s05))));
        break :blk r / s;
    } else x;
    return (0.5 + z) * x;
}

fn y1(x: f64) callconv(.c) f64 {
    const bits: u64 = @bitCast(x);
    const ix: u32 = @truncate(bits >> 32);
    const lx: u32 = @truncate(bits);
    if (((ix << 1) | lx) == 0) return -1 / @as(f64, 0.0);
    if ((ix >> 31) != 0) return 0 / @as(f64, 0.0);
    if (ix >= 0x7ff00000) return 1 / x;
    if (ix >= 0x40000000) return j1_common(ix, x, true, false);
    if (ix < 0x3c900000) return -bessel_tpi64 / x;
    const z = x * x;
    const u = y1_U0[0] + z * (y1_U0[1] + z * (y1_U0[2] + z * (y1_U0[3] + z * y1_U0[4])));
    const v = 1 + z * (y1_V0[0] + z * (y1_V0[1] + z * (y1_V0[2] + z * (y1_V0[3] + z * y1_V0[4]))));
    return x * (u / v) + bessel_tpi64 * (j1(x) * math.log(f64, math.e, x) - 1 / x);
}

fn j1_pone(x: f64) f64 {
    var p: []const f64 = undefined;
    var q: []const f64 = undefined;
    const ix: u32 = @as(u32, @truncate(@as(u64, @bitCast(x)) >> 32)) & 0x7fffffff;
    if (ix >= 0x40200000) {
        p = j1_pr8[0..];
        q = j1_ps8[0..];
    } else if (ix >= 0x40122E8B) {
        p = j1_pr5[0..];
        q = j1_ps5[0..];
    } else if (ix >= 0x4006DB6D) {
        p = j1_pr3[0..];
        q = j1_ps3[0..];
    } else {
        p = j1_pr2[0..];
        q = j1_ps2[0..];
    }
    const z = 1.0 / (x * x);
    const r = p[0] + z * (p[1] + z * (p[2] + z * (p[3] + z * (p[4] + z * p[5]))));
    const s = 1.0 + z * (q[0] + z * (q[1] + z * (q[2] + z * (q[3] + z * q[4]))));
    return 1.0 + r / s;
}

fn j1_qone(x: f64) f64 {
    var p: []const f64 = undefined;
    var q: []const f64 = undefined;
    const ix: u32 = @as(u32, @truncate(@as(u64, @bitCast(x)) >> 32)) & 0x7fffffff;
    if (ix >= 0x40200000) {
        p = j1_qr8[0..];
        q = j1_qs8[0..];
    } else if (ix >= 0x40122E8B) {
        p = j1_qr5[0..];
        q = j1_qs5[0..];
    } else if (ix >= 0x4006DB6D) {
        p = j1_qr3[0..];
        q = j1_qs3[0..];
    } else {
        p = j1_qr2[0..];
        q = j1_qs2[0..];
    }
    const z = 1.0 / (x * x);
    const r = p[0] + z * (p[1] + z * (p[2] + z * (p[3] + z * (p[4] + z * p[5]))));
    const s = 1.0 + z * (q[0] + z * (q[1] + z * (q[2] + z * (q[3] + z * (q[4] + z * q[5])))));
    return (0.375 + r / s) / x;
}

// migrated from musl/src/math/j1f.c
const j1f_r00: f32 = -6.2500000000e-02;
const j1f_r01: f32 = 1.4070566976e-03;
const j1f_r02: f32 = -1.5995563444e-05;
const j1f_r03: f32 = 4.9672799207e-08;
const j1f_s01: f32 = 1.9153760746e-02;
const j1f_s02: f32 = 1.8594678841e-04;
const j1f_s03: f32 = 1.1771846857e-06;
const j1f_s04: f32 = 5.0463624390e-09;
const j1f_s05: f32 = 1.2354227016e-11;

const y1f_U0 = [_]f32{ -1.9605709612e-01, 5.0443872809e-02, -1.9125689287e-03, 2.3525259166e-05, -9.1909917899e-08 };
const y1f_V0 = [_]f32{ 1.9916731864e-02, 2.0255257550e-04, 1.3560879779e-06, 6.2274145840e-09, 1.6655924903e-11 };

const j1f_pr8 = [_]f32{ 0.0000000000e+00, 1.1718750000e-01, 1.3239480972e+01, 4.1205184937e+02, 3.8747453613e+03, 7.9144794922e+03 };
const j1f_ps8 = [_]f32{ 1.1420736694e+02, 3.6509309082e+03, 3.6956207031e+04, 9.7602796875e+04, 3.0804271484e+04 };
const j1f_pr5 = [_]f32{ 1.3199052094e-11, 1.1718749255e-01, 6.8027510643e+00, 1.0830818176e+02, 5.1763616943e+02, 5.2871520996e+02 };
const j1f_ps5 = [_]f32{ 5.9280597687e+01, 9.9140142822e+02, 5.3532670898e+03, 7.8446904297e+03, 1.5040468750e+03 };
const j1f_pr3 = [_]f32{ 3.0250391081e-09, 1.1718686670e-01, 3.9329774380e+00, 3.5119403839e+01, 9.1055007935e+01, 4.8559066772e+01 };
const j1f_ps3 = [_]f32{ 3.4791309357e+01, 3.3676245117e+02, 1.0468714600e+03, 8.9081134033e+02, 1.0378793335e+02 };
const j1f_pr2 = [_]f32{ 1.0771083225e-07, 1.1717621982e-01, 2.3685150146e+00, 1.2242610931e+01, 1.7693971634e+01, 5.0735230446e+00 };
const j1f_ps2 = [_]f32{ 2.1436485291e+01, 1.2529022980e+02, 2.3227647400e+02, 1.1767937469e+02, 8.3646392822e+00 };

const j1f_qr8 = [_]f32{ 0.0000000000e+00, -1.0253906250e-01, -1.6271753311e+01, -7.5960174561e+02, -1.1849806641e+04, -4.8438511719e+04 };
const j1f_qs8 = [_]f32{ 1.6139537048e+02, 7.8253862305e+03, 1.3387534375e+05, 7.1965775000e+05, 6.6660125000e+05, -2.9449025000e+05 };
const j1f_qr5 = [_]f32{ -2.0897993405e-11, -1.0253904760e-01, -8.0564479828e+00, -1.8366960144e+02, -1.3731937256e+03, -2.6124443359e+03 };
const j1f_qs5 = [_]f32{ 8.1276550293e+01, 1.9917987061e+03, 1.7468484375e+04, 4.9851425781e+04, 2.7948074219e+04, -4.7191835938e+03 };
const j1f_qr3 = [_]f32{ -5.0783124372e-09, -1.0253783315e-01, -4.6101160049e+00, -5.7847221375e+01, -2.2824453735e+02, -2.1921012878e+02 };
const j1f_qs3 = [_]f32{ 4.7665153503e+01, 6.7386511230e+02, 3.3801528320e+03, 5.5477290039e+03, 1.9031191406e+03, -1.3520118713e+02 };
const j1f_qr2 = [_]f32{ -1.7838172539e-07, -1.0251704603e-01, -2.7522056103e+00, -1.9663616180e+01, -4.2325313568e+01, -2.1371921539e+01 };
const j1f_qs2 = [_]f32{ 2.9533363342e+01, 2.5298155212e+02, 7.5750280762e+02, 7.3939318848e+02, 1.5594900513e+02, -4.9594988823e+00 };

fn j1f_common(ix: u32, x: f32, y1_: bool, sign: bool) f32 {
    var s: f64 = math.sin(@as(f64, x));
    if (y1_) s = -s;
    const c: f64 = math.cos(@as(f64, x));
    var cc = s - c;
    if (ix < 0x7f000000) {
        var ss = -s - c;
        const z = math.cos(2 * @as(f64, x));
        if (s * c > 0)
            cc = z / ss
        else
            ss = z / cc;
        if (ix < 0x58800000) {
            if (y1_) ss = -ss;
            cc = @as(f64, j1f_pone(x)) * cc - @as(f64, j1f_qone(x)) * ss;
        }
    }
    if (sign) cc = -cc;
    return @floatCast(@as(f64, bessel_invsqrtpi32) * cc / @sqrt(@as(f64, x)));
}

fn j1f(x: f32) callconv(.c) f32 {
    var ix: u32 = @bitCast(x);
    const sign = (ix >> 31) != 0;
    ix &= 0x7fffffff;
    if (ix >= 0x7f800000) return 1 / (x * x);
    if (ix >= 0x40000000) return j1f_common(ix, @abs(x), false, sign);
    const z: f32 = if (ix >= 0x39000000) blk: {
        const x2 = x * x;
        const r = x2 * (j1f_r00 + x2 * (j1f_r01 + x2 * (j1f_r02 + x2 * j1f_r03)));
        const s = 1 + x2 * (j1f_s01 + x2 * (j1f_s02 + x2 * (j1f_s03 + x2 * (j1f_s04 + x2 * j1f_s05))));
        break :blk 0.5 + r / s;
    } else 0.5;
    return z * x;
}

fn y1f(x: f32) callconv(.c) f32 {
    const ix: u32 = @bitCast(x);
    if ((ix & 0x7fffffff) == 0) return -1 / @as(f32, 0.0);
    if ((ix >> 31) != 0) return 0 / @as(f32, 0.0);
    if (ix >= 0x7f800000) return 1 / x;
    if (ix >= 0x40000000) return j1f_common(ix, x, true, false);
    if (ix < 0x33000000) return -bessel_tpi32 / x;
    const z = x * x;
    const u = y1f_U0[0] + z * (y1f_U0[1] + z * (y1f_U0[2] + z * (y1f_U0[3] + z * y1f_U0[4])));
    const v = 1.0 + z * (y1f_V0[0] + z * (y1f_V0[1] + z * (y1f_V0[2] + z * (y1f_V0[3] + z * y1f_V0[4]))));
    return x * (u / v) + bessel_tpi32 * (j1f(x) * math.log(f32, math.e, x) - 1.0 / x);
}

fn j1f_pone(x: f32) f32 {
    var p: []const f32 = undefined;
    var q: []const f32 = undefined;
    const ix = @as(u32, @bitCast(x)) & 0x7fffffff;
    if (ix >= 0x41000000) {
        p = j1f_pr8[0..];
        q = j1f_ps8[0..];
    } else if (ix >= 0x409173eb) {
        p = j1f_pr5[0..];
        q = j1f_ps5[0..];
    } else if (ix >= 0x4036d917) {
        p = j1f_pr3[0..];
        q = j1f_ps3[0..];
    } else {
        p = j1f_pr2[0..];
        q = j1f_ps2[0..];
    }
    const z = 1.0 / (x * x);
    const r = p[0] + z * (p[1] + z * (p[2] + z * (p[3] + z * (p[4] + z * p[5]))));
    const s = 1.0 + z * (q[0] + z * (q[1] + z * (q[2] + z * (q[3] + z * q[4]))));
    return 1.0 + r / s;
}

fn j1f_qone(x: f32) f32 {
    var p: []const f32 = undefined;
    var q: []const f32 = undefined;
    const ix = @as(u32, @bitCast(x)) & 0x7fffffff;
    if (ix >= 0x41000000) {
        p = j1f_qr8[0..];
        q = j1f_qs8[0..];
    } else if (ix >= 0x409173eb) {
        p = j1f_qr5[0..];
        q = j1f_qs5[0..];
    } else if (ix >= 0x4036d917) {
        p = j1f_qr3[0..];
        q = j1f_qs3[0..];
    } else {
        p = j1f_qr2[0..];
        q = j1f_qs2[0..];
    }
    const z = 1.0 / (x * x);
    const r = p[0] + z * (p[1] + z * (p[2] + z * (p[3] + z * (p[4] + z * p[5]))));
    const s = 1.0 + z * (q[0] + z * (q[1] + z * (q[2] + z * (q[3] + z * (q[4] + z * q[5])))));
    return (0.375 + r / s) / x;
}

// migrated from musl/src/math/jn.c
fn jn(n_: c_int, x_: f64) callconv(.c) f64 {
    @setFloatMode(.strict);
    var n = n_;
    var x = x_;
    const bits: u64 = @bitCast(x);
    var ix: u32 = @truncate(bits >> 32);
    const lx: u32 = @truncate(bits);
    const sign = (ix >> 31) != 0;
    ix &= 0x7fffffff;

    if ((ix | (lx | (~lx +% 1)) >> 31) > 0x7ff00000) return x;

    if (n < 0) {
        n = -n;
        x = -x;
    }
    if (n == 0) return j0(x);
    if (n == 1) return j1(x);
    const nm1: u32 = @intCast(n - 1);
    const odd = (n & 1) != 0;
    if (sign) x = -x;

    var b: f64 = undefined;
    if ((ix | lx) == 0 or ix == 0x7ff00000) {
        b = 0.0;
    } else if (@as(f64, @floatFromInt(n)) <= x) {
        if (ix >= 0x52d00000) {
            const temp: f64 = switch (n & 3) {
                0 => math.cos(x) + math.sin(x),
                1 => -math.cos(x) + math.sin(x),
                2 => -math.cos(x) - math.sin(x),
                3 => math.cos(x) - math.sin(x),
                else => unreachable,
            };
            b = bessel_invsqrtpi64 * temp / @sqrt(x);
        } else {
            var a = j0(x);
            b = j1(x);
            var i: u32 = 0;
            while (i < nm1) {
                i += 1;
                const temp = b;
                b = b * (2.0 * @as(f64, @floatFromInt(i)) / x) - a;
                a = temp;
            }
        }
    } else {
        if (ix < 0x3e100000) {
            if (nm1 > 32) {
                b = 0.0;
            } else {
                const temp = x * 0.5;
                b = temp;
                var a: f64 = 1.0;
                var i: u32 = 2;
                while (i <= nm1 + 1) : (i += 1) {
                    a *= @floatFromInt(i);
                    b *= temp;
                }
                b = b / a;
            }
        } else {
            const w = (2.0 * @as(f64, @floatFromInt(n))) / x;
            const h = 2.0 / x;
            var q0 = w;
            var z = w + h;
            var q1 = w * z - 1.0;
            var k: c_int = 1;
            while (q1 < 1.0e9) {
                k += 1;
                z += h;
                const tmp = z * q1 - q0;
                q0 = q1;
                q1 = tmp;
            }
            const m = n + n;
            var t: f64 = 0.0;
            var i: c_int = 2 * (n + k);
            while (i >= m) : (i -= 2) {
                t = 1.0 / (@as(f64, @floatFromInt(i)) / x - t);
            }
            var a = t;
            b = 1.0;
            const tmp_n: f64 = @floatFromInt(n);
            const v = 2.0 / x;
            const tmp = tmp_n * math.log(f64, math.e, @abs(v * tmp_n));
            if (tmp < 7.09782712893383973096e+02) {
                var idx: u32 = nm1;
                while (idx > 0) : (idx -= 1) {
                    const di: f64 = @floatFromInt(2 * idx);
                    const temp = b;
                    b = b * di / x - a;
                    a = temp;
                }
            } else {
                var idx: u32 = nm1;
                while (idx > 0) : (idx -= 1) {
                    const di: f64 = @floatFromInt(2 * idx);
                    const temp = b;
                    b = b * di / x - a;
                    a = temp;
                    if (b > 1e100) {
                        a /= b;
                        t /= b;
                        b = 1.0;
                    }
                }
            }
            const z0 = j0(x);
            const w0 = j1(x);
            if (@abs(z0) >= @abs(w0))
                b = t * z0 / b
            else
                b = t * w0 / a;
        }
    }
    return if (sign and odd) -b else b;
}

fn yn(n_: c_int, x: f64) callconv(.c) f64 {
    @setFloatMode(.strict);
    var n = n_;
    const bits: u64 = @bitCast(x);
    var ix: u32 = @truncate(bits >> 32);
    const lx: u32 = @truncate(bits);
    const sign = (ix >> 31) != 0;
    ix &= 0x7fffffff;

    if ((ix | (lx | (~lx +% 1)) >> 31) > 0x7ff00000) return x;
    if ((ix | lx) == 0) return -math.inf(f64) + x;
    if (sign) return 0.0 / (0.0 * x);
    var ib: u32 = undefined;
    const nm1: u32 = if (n < 0) blk: {
        n = -n;
        ib = @intCast((n & 1) ^ 1);
        break :blk @intCast(n - 1);
    } else blk: {
        ib = 1;
        break :blk @intCast(if (n > 0) n - 1 else 0);
    };
    if (n == 0) return y0(x);
    if (n == 1) return if (ib != 0) y1(x) else -y1(x);
    if (ix == 0x7ff00000) return 0.0;

    var b: f64 = undefined;
    if (ix >= 0x52d00000) {
        const temp: f64 = switch (n & 3) {
            0 => math.sin(x) - math.cos(x),
            1 => -math.sin(x) - math.cos(x),
            2 => -math.sin(x) + math.cos(x),
            3 => math.sin(x) + math.cos(x),
            else => unreachable,
        };
        b = bessel_invsqrtpi64 * temp / @sqrt(x);
    } else {
        var a = y0(x);
        b = y1(x);
        var i: u32 = 0;
        while (i < nm1 and (@as(u32, @truncate(@as(u64, @bitCast(b)) >> 32)) & 0x7fffffff) < 0x7ff00000) {
            i += 1;
            const temp = b;
            b = (2.0 * @as(f64, @floatFromInt(i)) / x) * b - a;
            a = temp;
        }
    }
    return if (ib != 0) b else -b;
}

// migrated from musl/src/math/jnf.c
fn jnf(n_: c_int, x_: f32) callconv(.c) f32 {
    @setFloatMode(.strict);
    var n = n_;
    var x = x_;
    var ix: u32 = @bitCast(x);
    const sign = (ix >> 31) != 0;
    ix &= 0x7fffffff;
    if (ix > 0x7f800000) return x;

    if (n < 0) {
        n = -n;
        x = -x;
    }
    if (n == 0) return j0f(x);
    if (n == 1) return j1f(x);
    const nm1: u32 = @intCast(n - 1);
    const odd = (n & 1) != 0;
    if (sign) x = -x;

    var b: f32 = undefined;
    if (ix == 0 or ix == 0x7f800000) {
        b = 0.0;
    } else if (@as(f32, @floatFromInt(n)) <= x) {
        if (ix >= 0x4e800000) {
            const temp: f32 = switch (n & 3) {
                0 => math.cos(x) + math.sin(x),
                1 => -math.cos(x) + math.sin(x),
                2 => -math.cos(x) - math.sin(x),
                3 => math.cos(x) - math.sin(x),
                else => unreachable,
            };
            b = bessel_invsqrtpi32 * temp / @sqrt(x);
        } else {
            var a = j0f(x);
            b = j1f(x);
            var i: u32 = 0;
            while (i < nm1) {
                i += 1;
                const temp = b;
                b = b * (2.0 * @as(f32, @floatFromInt(i)) / x) - a;
                a = temp;
            }
        }
    } else {
        if (ix < 0x35800000) {
            if (nm1 > 8) {
                b = 0.0;
            } else {
                const temp = x * 0.5;
                b = temp;
                var a: f32 = 1.0;
                var i: u32 = 2;
                while (i <= nm1 + 1) : (i += 1) {
                    a *= @floatFromInt(i);
                    b *= temp;
                }
                b = b / a;
            }
        } else {
            const w = (2.0 * @as(f32, @floatFromInt(n))) / x;
            const h = 2.0 / x;
            var q0 = w;
            var z = w + h;
            var q1 = w * z - 1.0;
            var k: c_int = 1;
            while (q1 < 1.0e9) {
                k += 1;
                z += h;
                const tmp = z * q1 - q0;
                q0 = q1;
                q1 = tmp;
            }
            const m = n + n;
            var t: f32 = 0.0;
            var i: c_int = 2 * (n + k);
            while (i >= m) : (i -= 2) {
                t = 1.0 / (@as(f32, @floatFromInt(i)) / x - t);
            }
            var a = t;
            b = 1.0;
            const tmp_n: f32 = @floatFromInt(n);
            const v = 2.0 / x;
            const tmp = tmp_n * math.log(f32, math.e, @abs(v * tmp_n));
            if (tmp < 8.8721679688e+01) {
                var idx: u32 = nm1;
                while (idx > 0) : (idx -= 1) {
                    const di: f32 = @floatFromInt(2 * idx);
                    const temp = b;
                    b = b * di / x - a;
                    a = temp;
                }
            } else {
                var idx: u32 = nm1;
                while (idx > 0) : (idx -= 1) {
                    const di: f32 = @floatFromInt(2 * idx);
                    const temp = b;
                    b = b * di / x - a;
                    a = temp;
                    if (b > 1e20) {
                        a /= b;
                        t /= b;
                        b = 1.0;
                    }
                }
            }
            const z0 = j0f(x);
            const w0 = j1f(x);
            if (@abs(z0) >= @abs(w0))
                b = t * z0 / b
            else
                b = t * w0 / a;
        }
    }
    return if (sign and odd) -b else b;
}

fn ynf(n_: c_int, x: f32) callconv(.c) f32 {
    @setFloatMode(.strict);
    var n = n_;
    var ix: u32 = @bitCast(x);
    const sign = (ix >> 31) != 0;
    ix &= 0x7fffffff;
    if (ix > 0x7f800000) return x;
    if (ix == 0) return -math.inf(f32) + x;
    if (sign) return 0.0 / (0.0 * x);
    var ib: u32 = undefined;
    const nm1: u32 = if (n < 0) blk: {
        n = -n;
        ib = @intCast((n & 1) ^ 1);
        break :blk @intCast(n - 1);
    } else blk: {
        ib = 1;
        break :blk @intCast(if (n > 0) n - 1 else 0);
    };
    if (n == 0) return y0f(x);
    if (n == 1) return if (ib != 0) y1f(x) else -y1f(x);
    if (ix == 0x7f800000) return 0.0;

    var b: f32 = undefined;
    if (ix >= 0x4e800000) {
        const temp: f32 = switch (n & 3) {
            0 => math.sin(x) - math.cos(x),
            1 => -math.sin(x) - math.cos(x),
            2 => -math.sin(x) + math.cos(x),
            3 => math.sin(x) + math.cos(x),
            else => unreachable,
        };
        b = bessel_invsqrtpi32 * temp / @sqrt(x);
    } else {
        var a = y0f(x);
        b = y1f(x);
        var i: u32 = 0;
        while (i < nm1 and (@as(u32, @bitCast(b)) & 0x7fffffff) < 0x7f800000) {
            i += 1;
            const temp = b;
            b = (2.0 * @as(f32, @floatFromInt(i)) / x) * b - a;
            a = temp;
        }
    }
    return if (ib != 0) b else -b;
}

// migrated from musl/src/math/tgamma.c
const tgamma_lanczos_g: f64 = 6.024680040776729583740234375;
const tgamma_lanczos_gmhalf: f64 = 5.524680040776729583740234375;
const tgamma_num = [13]f64{
    23531376880.410759688572007674451636754734846804940,
    42919803642.649098768957899047001988850926355848959,
    35711959237.355668049440185451547166705960488635843,
    17921034426.037209699919755754458931112671403265390,
    6039542586.3520280050642916443072979210699388420708,
    1439720407.3117216736632230727949123939715485786772,
    248874557.86205415651146038641322942321632125127801,
    31426415.585400194380614231628318205362874684987640,
    2876370.6289353724412254090516208496135991145378768,
    186056.26539522349504029498971604569928220784236328,
    8071.6720023658162106380029022722506138218516325024,
    210.82427775157934587250973392071336271166969580291,
    2.5066282746310002701649081771338373386264310793408,
};
const tgamma_den = [13]f64{
    0.0,
    39916800.0,
    120543840.0,
    150917976.0,
    105258076.0,
    45995730.0,
    13339535.0,
    2637558.0,
    357423.0,
    32670.0,
    1925.0,
    66.0,
    1.0,
};
const tgamma_fact = [23]f64{
    1,
    1,
    2,
    6,
    24,
    120,
    720,
    5040,
    40320,
    362880,
    3628800,
    39916800,
    479001600,
    6227020800,
    87178291200,
    1307674368000,
    20922789888000,
    355687428096000,
    6402373705728000,
    121645100408832000,
    2432902008176640000,
    51090942171709440000.0,
    1124000727777607680000.0,
};

fn tgamma(x_: f64) callconv(.c) f64 {
    @setFloatMode(.strict);
    var x = x_;
    const u: u64 = @bitCast(x);
    const ix: u32 = @as(u32, @truncate(u >> 32)) & 0x7fffffff;
    const sign: u32 = @truncate(u >> 63);

    if (ix >= 0x7ff00000) return x + math.inf(f64);
    if (ix < (0x3ff - 54) << 20) return 1.0 / x;

    if (x == @floor(x)) {
        if (sign != 0) return __math_invalid(x);
        if (x <= @as(f64, @floatFromInt(tgamma_fact.len))) {
            const idx: usize = @intFromFloat(x);
            return tgamma_fact[idx - 1];
        }
    }

    if (ix >= 0x40670000) {
        if (sign != 0) {
            _ = fpBarrierValue(f32, @floatCast(0x1p-126 / x));
            if (@floor(x) * 0.5 == @floor(x * 0.5)) return 0.0;
            return -0.0;
        }
        x *= 0x1p1023;
        return x;
    }

    const absx = if (sign != 0) -x else x;
    const y = absx + tgamma_lanczos_gmhalf;
    var dy: f64 = if (absx > tgamma_lanczos_gmhalf)
        (y - absx) - tgamma_lanczos_gmhalf
    else
        (y - tgamma_lanczos_gmhalf) - absx;

    var z = absx - 0.5;
    var n: f64 = 0.0;
    var d: f64 = 0.0;
    if (absx < 8.0) {
        var i: usize = 13;
        while (i > 0) {
            i -= 1;
            n = n * absx + tgamma_num[i];
            d = d * absx + tgamma_den[i];
        }
    } else {
        var i: usize = 0;
        while (i < 13) : (i += 1) {
            n = n / absx + tgamma_num[i];
            d = d / absx + tgamma_den[i];
        }
    }
    const exp_neg_y: f64 = @floatCast(exp_pure(f128, -@as(f128, y)));
    var r = (n / d) * exp_neg_y;
    if (x < 0.0) {
        r = -3.141592653589793238462643383279502884 / (sin_pi64(absx) * absx * r);
        dy = -dy;
        z = -z;
    }
    r += dy * tgamma_lanczos_g * r / y;
    z = @floatCast(exp_pure(f128, @as(f128, 0.5 * z) * log_pure(f128, @as(f128, y))));
    return r * z * z;
}

fn tgammaf(x: f32) callconv(.c) f32 {
    @setFloatMode(.strict);
    return @floatCast(tgamma(x));
}

// migrated from musl/src/math/tgammal.c
const tgammal80_P = [8]f80{
    4.212760487471622013093E-5,
    4.542931960608009155600E-4,
    4.092666828394035500949E-3,
    2.385363243461108252554E-2,
    1.113062816019361559013E-1,
    3.629515436640239168939E-1,
    8.378004301573126728826E-1,
    1.000000000000000000009E0,
};
const tgammal80_Q = [9]f80{
    -1.397148517476170440917E-5,
    2.346584059160635244282E-4,
    -1.237799246653152231188E-3,
    -7.955933682494738320586E-4,
    2.773706565840072979165E-2,
    -4.633887671244534213831E-2,
    -2.243510905670329164562E-1,
    4.150160950588455434583E-1,
    9.999999999999999999908E-1,
};
const tgammal80_STIR = [9]f80{
    7.147391378143610789273E-4,
    -2.363848809501759061727E-5,
    -5.950237554056330156018E-4,
    6.989332260623193171870E-5,
    7.840334842744753003862E-4,
    -2.294719747873185405699E-4,
    -2.681327161876304418288E-3,
    3.472222222230075327854E-3,
    8.333333333333331800504E-2,
};
const tgammal80_S = [9]f80{
    -1.193945051381510095614E-3,
    7.220599478036909672331E-3,
    -9.622023360406271645744E-3,
    -4.219773360705915470089E-2,
    1.665386113720805206758E-1,
    -4.200263503403344054473E-2,
    -6.558780715202540684668E-1,
    5.772156649015328608253E-1,
    1.000000000000000000000E0,
};
const tgammal80_SN = [9]f80{
    1.133374167243894382010E-3,
    7.220837261893170325704E-3,
    9.621911155035976733706E-3,
    -4.219773343731191721664E-2,
    -1.665386113944413519335E-1,
    -4.200263503402112910504E-2,
    6.558780715202536547116E-1,
    5.772156649015328608727E-1,
    -1.000000000000000000000E0,
};

fn polevll80(x: f80, p: []const f80) f80 {
    @setFloatMode(.strict);
    var ans = p[0];
    for (p[1..]) |c| {
        ans = ans * x + c;
    }
    return ans;
}

fn stirf80(x: f80) f80 {
    @setFloatMode(.strict);
    const MAXSTIR: f80 = 1024.0;
    const SQTPI: f80 = 2.50662827463100050242E0;
    var w = 1.0 / x;
    if (x > 1024.0) {
        w = (((((6.97281375836585777429E-5 * w + 7.84039221720066627474E-4) * w -
            2.29472093621399176955E-4) * w -
            2.68132716049382716049E-3) * w +
            3.47222222222222222222E-3) * w +
            8.33333333333333333333E-2) * w + 1.0;
    } else {
        w = 1.0 + w * polevll80(w, &tgammal80_STIR);
    }
    var y: f80 = @floatCast(expl(@floatCast(x)));
    const lx = log_pure(f128, @as(f128, x));
    if (x > MAXSTIR) {
        const v: f80 = @floatCast(exp_pure(f128, @as(f128, 0.5 * x - 0.25) * lx));
        y = v * (v / y);
    } else {
        y = @as(f80, @floatCast(exp_pure(f128, @as(f128, x - 0.5) * lx))) / y;
    }
    return SQTPI * y * w;
}

fn tgammal80(x_: f80) f80 {
    @setFloatMode(.strict);
    const MAXGAML: f80 = 1755.455;
    const PIL: f80 = 3.1415926535897932384626;
    var x = x_;
    if (!math.isFinite(x)) return x + math.inf(f80);

    var q = @abs(x);
    if (q > 13.0) {
        var z: f80 = undefined;
        if (x < 0.0) {
            var p = @floor(q);
            z = q - p;
            if (z == 0.0) return 0.0 / z;
            if (q > MAXGAML) {
                z = 0.0;
            } else {
                if (z > 0.5) {
                    p += 1.0;
                    z = q - p;
                }
                z = q * @as(f80, @floatCast(sinl(@floatCast(PIL * z))));
                z = @abs(z) * stirf80(q);
                z = PIL / z;
            }
            if (0.5 * p == @floor(q * 0.5)) z = -z;
        } else if (x > MAXGAML) {
            z = x * 0x1p16383;
        } else {
            z = stirf80(x);
        }
        return z;
    }

    var z: f80 = 1.0;
    while (x >= 3.0) {
        x -= 1.0;
        z *= x;
    }
    while (x < -0.03125) {
        z /= x;
        x += 1.0;
    }
    if (x <= 0.03125) {
        if (x == 0.0 and z != 1.0) return x / x;
        if (x < 0.0) {
            x = -x;
            return z / (x * polevll80(x, &tgammal80_SN));
        } else {
            return z / (x * polevll80(x, &tgammal80_S));
        }
    }
    while (x < 2.0) {
        z /= x;
        x += 1.0;
    }
    if (x == 2.0) return z;

    x -= 2.0;
    const p = polevll80(x, &tgammal80_P);
    q = polevll80(x, &tgammal80_Q);
    return z * p / q;
}

fn tgammal(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64, 128 => @floatCast(tgamma(@floatCast(x))),
        80 => @floatCast(tgammal80(@floatCast(x))),
        else => unreachable,
    };
}

// migrated from musl/src/math/lgammal.c
const lgammal80_pi: f80 = 3.14159265358979323846264;
const lgammal80_a0: f80 = -6.343246574721079391729402781192128239938E2;
const lgammal80_a1: f80 = 1.856560238672465796768677717168371401378E3;
const lgammal80_a2: f80 = 2.404733102163746263689288466865843408429E3;
const lgammal80_a3: f80 = 8.804188795790383497379532868917517596322E2;
const lgammal80_a4: f80 = 1.135361354097447729740103745999661157426E2;
const lgammal80_a5: f80 = 3.766956539107615557608581581190400021285E0;
const lgammal80_b0: f80 = 8.214973713960928795704317259806842490498E3;
const lgammal80_b1: f80 = 1.026343508841367384879065363925870888012E4;
const lgammal80_b2: f80 = 4.553337477045763320522762343132210919277E3;
const lgammal80_b3: f80 = 8.506975785032585797446253359230031874803E2;
const lgammal80_b4: f80 = 6.042447899703295436820744186992189445813E1;
const lgammal80_tc: f80 = 1.4616321449683623412626595423257213284682E0;
const lgammal80_tf: f80 = -1.2148629053584961146050602565082954242826E-1;
const lgammal80_tt: f80 = 3.3649914684731379602768989080467587736363E-18;
const lgammal80_g0: f80 = 3.645529916721223331888305293534095553827E-18;
const lgammal80_g1: f80 = 5.126654642791082497002594216163574795690E3;
const lgammal80_g2: f80 = 8.828603575854624811911631336122070070327E3;
const lgammal80_g3: f80 = 5.464186426932117031234820886525701595203E3;
const lgammal80_g4: f80 = 1.455427403530884193180776558102868592293E3;
const lgammal80_g5: f80 = 1.541735456969245924860307497029155838446E2;
const lgammal80_g6: f80 = 4.335498275274822298341872707453445815118E0;
const lgammal80_h0: f80 = 1.059584930106085509696730443974495979641E4;
const lgammal80_h1: f80 = 2.147921653490043010629481226937850618860E4;
const lgammal80_h2: f80 = 1.643014770044524804175197151958100656728E4;
const lgammal80_h3: f80 = 5.869021995186925517228323497501767586078E3;
const lgammal80_h4: f80 = 9.764244777714344488787381271643502742293E2;
const lgammal80_h5: f80 = 6.442485441570592541741092969581997002349E1;
const lgammal80_u0: f80 = -8.886217500092090678492242071879342025627E1;
const lgammal80_u1: f80 = 6.840109978129177639438792958320783599310E2;
const lgammal80_u2: f80 = 2.042626104514127267855588786511809932433E3;
const lgammal80_u3: f80 = 1.911723903442667422201651063009856064275E3;
const lgammal80_u4: f80 = 7.447065275665887457628865263491667767695E2;
const lgammal80_u5: f80 = 1.132256494121790736268471016493103952637E2;
const lgammal80_u6: f80 = 4.484398885516614191003094714505960972894E0;
const lgammal80_v0: f80 = 1.150830924194461522996462401210374632929E3;
const lgammal80_v1: f80 = 3.399692260848747447377972081399737098610E3;
const lgammal80_v2: f80 = 3.786631705644460255229513563657226008015E3;
const lgammal80_v3: f80 = 1.966450123004478374557778781564114347876E3;
const lgammal80_v4: f80 = 4.741359068914069299837355438370682773122E2;
const lgammal80_v5: f80 = 4.508989649747184050907206782117647852364E1;
const lgammal80_s0: f80 = 1.454726263410661942989109455292824853344E6;
const lgammal80_s1: f80 = -3.901428390086348447890408306153378922752E6;
const lgammal80_s2: f80 = -6.573568698209374121847873064292963089438E6;
const lgammal80_s3: f80 = -3.319055881485044417245964508099095984643E6;
const lgammal80_s4: f80 = -7.094891568758439227560184618114707107977E5;
const lgammal80_s5: f80 = -6.263426646464505837422314539808112478303E4;
const lgammal80_s6: f80 = -1.684926520999477529949915657519454051529E3;
const lgammal80_r0: f80 = -1.883978160734303518163008696712983134698E7;
const lgammal80_r1: f80 = -2.815206082812062064902202753264922306830E7;
const lgammal80_r2: f80 = -1.600245495251915899081846093343626358398E7;
const lgammal80_r3: f80 = -4.310526301881305003489257052083370058799E6;
const lgammal80_r4: f80 = -5.563807682263923279438235987186184968542E5;
const lgammal80_r5: f80 = -3.027734654434169996032905158145259713083E4;
const lgammal80_r6: f80 = -4.501995652861105629217250715790764371267E2;
const lgammal80_w0: f80 = 4.189385332046727417803E-1;
const lgammal80_w1: f80 = 8.333333333333331447505E-2;
const lgammal80_w2: f80 = -2.777777777750349603440E-3;
const lgammal80_w3: f80 = 7.936507795855070755671E-4;
const lgammal80_w4: f80 = -5.952345851765688514613E-4;
const lgammal80_w5: f80 = 8.412723297322498080632E-4;
const lgammal80_w6: f80 = -1.880801938119376907179E-3;
const lgammal80_w7: f80 = 4.885026142432270781165E-3;

fn sinl80Kernel(x: f80) f80 {
    @setFloatMode(.strict);
    const S1: f80 = -0.166666666666666666671;
    const S2: f64 = 0.0083333333333333332;
    const S3: f64 = -0.00019841269841269427;
    const S4: f64 = 0.0000027557319223597490;
    const S5: f64 = -0.000000025052108218074604;
    const S6: f64 = 1.6059006598854211e-10;
    const S7: f64 = -7.6429779983024564e-13;
    const S8: f64 = 2.6174587166648325e-15;
    const z = x * x;
    const v = z * x;
    const r = S2 + z * (S3 + z * (S4 + z * (S5 + z * (S6 + z * (S7 + z * S8)))));
    return x + v * (S1 + z * r);
}

fn cosl80Kernel(x: f80) f80 {
    @setFloatMode(.strict);
    const C1: f80 = 0.0416666666666666666136;
    const C2: f64 = -0.0013888888888888874;
    const C3: f64 = 0.000024801587301571716;
    const C4: f64 = -0.00000027557319215507120;
    const C5: f64 = 0.0000000020876754400407278;
    const C6: f64 = -1.1470297442401303e-11;
    const C7: f64 = 4.7383039476436467e-14;
    const z = x * x;
    const r = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * (C6 + z * C7))))));
    const hz = 0.5 * z;
    const w = 1.0 - hz;
    return w + (((1.0 - w) - hz) + z * r);
}

fn lgammal80_sin_pi(x_: f80) f80 {
    @setFloatMode(.strict);
    var x = x_;
    x *= 0.5;
    x = 2.0 * (x - @floor(x));
    var n: c_int = @intFromFloat(x * 4.0);
    n = @divTrunc(n + 1, 2);
    x -= @as(f80, @floatFromInt(n)) * 0.5;
    x *= lgammal80_pi;
    return switch (n) {
        0, 4 => sinl80Kernel(x),
        1 => cosl80Kernel(x),
        2 => sinl80Kernel(-x),
        3 => -cosl80Kernel(x),
        else => unreachable,
    };
}

fn lgammal80_r(x_: f80, signgamp: *c_int) f80 {
    const bits: u80 = @bitCast(x_);
    const se: u16 = @truncate(bits >> 64);
    const m: u64 = @truncate(bits);
    const ix: u32 = (@as(u32, se & 0x7fff) << 16) | @as(u32, @truncate(m >> 48));
    const sign = (se >> 15) != 0;

    var x = x_;
    var r: f80 = undefined;
    var nadj: f80 = undefined;
    signgamp.* = 1;

    if (ix >= 0x7fff0000) return x * x;
    if (ix < 0x3fc08000) {
        if (sign) {
            signgamp.* = -1;
            x = -x;
        }
        return -@as(f80, @floatCast(logl(@floatCast(x))));
    }
    if (sign) {
        x = -x;
        var t = lgammal80_sin_pi(x);
        if (t == 0.0) return 1.0 / (x - x);
        if (t > 0.0)
            signgamp.* = -1
        else
            t = -t;
        nadj = @floatCast(logl(@floatCast(lgammal80_pi / (t * x))));
    }

    if ((ix == 0x3fff8000 or ix == 0x40008000) and m == 0) {
        r = 0;
    } else if (ix < 0x40008000) {
        var y: f80 = undefined;
        var i: c_int = undefined;
        if (ix <= 0x3ffee666) {
            r = -@as(f80, @floatCast(logl(@floatCast(x))));
            if (ix >= 0x3ffebb4a) {
                y = x - 1.0;
                i = 0;
            } else if (ix >= 0x3ffced33) {
                y = x - (lgammal80_tc - 1.0);
                i = 1;
            } else {
                y = x;
                i = 2;
            }
        } else {
            r = 0.0;
            if (ix >= 0x3fffdda6) {
                y = x - 2.0;
                i = 0;
            } else if (ix >= 0x3fff9da6) {
                y = x - lgammal80_tc;
                i = 1;
            } else {
                y = x - 1.0;
                i = 2;
            }
        }
        switch (i) {
            0 => {
                const p1 = lgammal80_a0 + y * (lgammal80_a1 + y * (lgammal80_a2 + y * (lgammal80_a3 + y * (lgammal80_a4 + y * lgammal80_a5))));
                const p2 = lgammal80_b0 + y * (lgammal80_b1 + y * (lgammal80_b2 + y * (lgammal80_b3 + y * (lgammal80_b4 + y))));
                r += 0.5 * y + y * p1 / p2;
            },
            1 => {
                const p1 = lgammal80_g0 + y * (lgammal80_g1 + y * (lgammal80_g2 + y * (lgammal80_g3 + y * (lgammal80_g4 + y * (lgammal80_g5 + y * lgammal80_g6)))));
                const p2 = lgammal80_h0 + y * (lgammal80_h1 + y * (lgammal80_h2 + y * (lgammal80_h3 + y * (lgammal80_h4 + y * (lgammal80_h5 + y)))));
                const p = lgammal80_tt + y * p1 / p2;
                r += lgammal80_tf + p;
            },
            2 => {
                const p1 = y * (lgammal80_u0 + y * (lgammal80_u1 + y * (lgammal80_u2 + y * (lgammal80_u3 + y * (lgammal80_u4 + y * (lgammal80_u5 + y * lgammal80_u6))))));
                const p2 = lgammal80_v0 + y * (lgammal80_v1 + y * (lgammal80_v2 + y * (lgammal80_v3 + y * (lgammal80_v4 + y * (lgammal80_v5 + y)))));
                r += -0.5 * y + p1 / p2;
            },
            else => unreachable,
        }
    } else if (ix < 0x40028000) {
        const i: c_int = @intFromFloat(x);
        const y = x - @as(f80, @floatFromInt(i));
        const p = y * (lgammal80_s0 + y * (lgammal80_s1 + y * (lgammal80_s2 + y * (lgammal80_s3 + y * (lgammal80_s4 + y * (lgammal80_s5 + y * lgammal80_s6))))));
        const q = lgammal80_r0 + y * (lgammal80_r1 + y * (lgammal80_r2 + y * (lgammal80_r3 + y * (lgammal80_r4 + y * (lgammal80_r5 + y * (lgammal80_r6 + y))))));
        r = 0.5 * y + p / q;
        var z: f80 = 1.0;
        if (i >= 3) {
            z *= y + 2.0;
            if (i >= 4) z *= y + 3.0;
            if (i >= 5) z *= y + 4.0;
            if (i >= 6) z *= y + 5.0;
            if (i >= 7) z *= y + 6.0;
            r += @as(f80, @floatCast(logl(@floatCast(z))));
        }
    } else if (ix < 0x40418000) {
        const t: f80 = @floatCast(logl(@floatCast(x)));
        const z = 1.0 / x;
        const y = z * z;
        const w = lgammal80_w0 + z * (lgammal80_w1 + y * (lgammal80_w2 + y * (lgammal80_w3 + y * (lgammal80_w4 + y * (lgammal80_w5 + y * (lgammal80_w6 + y * lgammal80_w7))))));
        r = (x - 0.5) * (t - 1.0) + w;
    } else {
        r = x * (@as(f80, @floatCast(logl(@floatCast(x)))) - 1.0);
    }
    if (sign) r = nadj - r;
    return r;
}

fn lgammal_r_(x: c_longdouble, signgamp: *c_int) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64, 128 => @floatCast(lgamma_r(@floatCast(x), signgamp)),
        80 => @floatCast(lgammal80_r(@floatCast(x), signgamp)),
        else => unreachable,
    };
}

fn lgammal_(x: c_longdouble) callconv(.c) c_longdouble {
    return lgammal_r_(x, &__signgam);
}
