const std = @import("std");
const math = std.math;
const expect = std.testing.expect;
const expectApproxEqRel = std.testing.expectApproxEqRel;

const symbol = @import("../c.zig").symbol;

comptime {
    const is_musl_or_wasi = @import("builtin").target.isMuslLibC() or @import("builtin").target.isWasiLibC();
    if (is_musl_or_wasi) {
        symbol(&j0_, "j0");
        symbol(&j0f_, "j0f");
        symbol(&j1_, "j1");
        symbol(&j1f_, "j1f");
        symbol(&jn_, "jn");
        symbol(&jnf_, "jnf");
        symbol(&y0_, "y0");
        symbol(&y0f_, "y0f");
        symbol(&y1_, "y1");
        symbol(&y1f_, "y1f");
        symbol(&yn_, "yn");
        symbol(&ynf_, "ynf");
    }
}

// ========== j0.c ==========

const invsqrtpi: f64 = 5.64189583547756279280e-01;
const tpi: f64 = 6.36619772367581382433e-01;

fn common_j0(ix: u32, x: f64, y0: bool) f64 {
    const s = math.sin(x);
    var c = math.cos(x);
    if (y0)
        c = -c;
    var cc = s + c;
    
    if (ix < 0x7fe00000) {
        var ss = s - c;
        const z = -math.cos(2 * x);
        if (s * c < 0) {
            cc = z / ss;
        } else {
            ss = z / cc;
        }
        if (ix < 0x48000000) {
            if (y0) {
                ss = -ss;
            }
            cc = pzero(x) * cc - qzero(x) * ss;
        }
    }
    return invsqrtpi * cc / @sqrt(x);
}

const R02: f64 = 1.56249999999999947958e-02;
const R03: f64 = -1.89979294238854721751e-04;
const R04: f64 = 1.82954049532700665670e-06;
const R05: f64 = -4.61832688532103189199e-09;
const S01: f64 = 1.56191029464890010492e-02;
const S02: f64 = 1.16926784663337450260e-04;
const S03: f64 = 5.13546550207318111446e-07;
const S04: f64 = 1.16614003333790000205e-09;

pub export fn j0_(x: f64) callconv(.c) f64 {
    const bits = @as(u64, @bitCast(x));
    var ix = @as(u32, @truncate(bits >> 32));
    ix &= 0x7fffffff;
    
    if (ix >= 0x7ff00000)
        return 1 / (x * x);
    const ax = @abs(x);
    
    if (ix >= 0x40000000) {
        return common_j0(ix, ax, false);
    }
    
    if (ix >= 0x3f200000) {
        const z = ax * ax;
        const r = z * (R02 + z * (R03 + z * (R04 + z * R05)));
        const s = 1 + z * (S01 + z * (S02 + z * (S03 + z * S04)));
        return (1 + ax / 2) * (1 - ax / 2) + z * (r / s);
    }
    
    if (ix >= 0x38000000) {
        return 1 - 0.25 * ax * ax;
    }
    return 1 - ax;
}

const bu00: f64 = -7.38042951086872317523e-02;
const bu01: f64 = 1.76666452509181115538e-01;
const bu02: f64 = -1.38185671945596898896e-02;
const bu03: f64 = 3.47453432093683650238e-04;
const bu04: f64 = -3.81407053724364161125e-06;
const bu05: f64 = 1.95590137035022920206e-08;
const bu06: f64 = -3.98205194132103398453e-11;
const v01: f64 = 1.27304834834123699328e-02;
const v02: f64 = 7.60068627350353253702e-05;
const v03: f64 = 2.59150851840457805467e-07;
const v04: f64 = 4.41110311332675467403e-10;

pub export fn y0_(x: f64) callconv(.c) f64 {
    const bits = @as(u64, @bitCast(x));
    const ix = @as(u32, @truncate(bits >> 32));
    const lx = @as(u32, @truncate(bits));
    
    if ((ix << 1 | lx) == 0)
        return -math.inf(f64);
    if (ix >> 31 != 0)
        return math.nan(f64);
    if (ix >= 0x7ff00000)
        return 1 / x;
    
    if (ix >= 0x40000000) {
        return common_j0(ix, x, true);
    }
    
    if (ix >= 0x3e400000) {
        const z = x * x;
        const u = bu00 + z * (bu01 + z * (bu02 + z * (bu03 + z * (bu04 + z * (bu05 + z * bu06)))));
        const v = 1.0 + z * (v01 + z * (v02 + z * (v03 + z * v04)));
        return u / v + tpi * (j0_(x) * @log(x));
    }
    return bu00 + tpi * @log(x);
}

const pR8 = [6]f64{
    0.00000000000000000000e+00,
    -7.03124999999900357484e-02,
    -8.08167041275349795626e+00,
    -2.57063105679704847262e+02,
    -2.48521641009428822144e+03,
    -5.25304380490729545272e+03,
};
const pS8 = [5]f64{
    1.16534364619668181717e+02,
    3.83374475364121826715e+03,
    4.05978572648472545552e+04,
    1.16752972564375915681e+05,
    4.76277284146730962675e+04,
};

const pR5 = [6]f64{
    -1.14125464691894502584e-11,
    -7.03124940873599280078e-02,
    -4.15961064470587782438e+00,
    -6.76747652265167261021e+01,
    -3.31231299649172967747e+02,
    -3.46433388365604912451e+02,
};
const pS5 = [5]f64{
    6.07539382692300335975e+01,
    1.05125230595704579173e+03,
    5.97897094333855784498e+03,
    9.62544514357774460223e+03,
    2.40605815922939109441e+03,
};

const pR3 = [6]f64{
    -2.54704601771951915620e-09,
    -7.03119616381481654654e-02,
    -2.40903221549529611423e+00,
    -2.19659774734883086467e+01,
    -5.80791704701737572236e+01,
    -3.14479470594888503854e+01,
};
const pS3 = [5]f64{
    3.58560338055209726349e+01,
    3.61513983050303863820e+02,
    1.19360783792111533330e+03,
    1.12799679856907414432e+03,
    1.73580930813335754692e+02,
};

const pR2 = [6]f64{
    -8.87534333032526411254e-08,
    -7.03030995483624743247e-02,
    -1.45073846780952986357e+00,
    -7.63569613823527770791e+00,
    -1.11931668860356747786e+01,
    -3.23364579351335335033e+00,
};
const pS2 = [5]f64{
    2.22202997532088808441e+01,
    1.36206794218215208048e+02,
    2.70470278658083486789e+02,
    1.53875394208320329881e+02,
    1.46576176948256193810e+01,
};

fn pzero(x: f64) f64 {
    const bits = @as(u64, @bitCast(x));
    var ix = @as(u32, @truncate(bits >> 32));
    ix &= 0x7fffffff;
    
    const p: [6]f64 = if (ix >= 0x40200000)
        pR8
    else if (ix >= 0x40122E8B)
        pR5
    else if (ix >= 0x4006DB6D)
        pR3
    else
        pR2;
    
    const q: [5]f64 = if (ix >= 0x40200000)
        pS8
    else if (ix >= 0x40122E8B)
        pS5
    else if (ix >= 0x4006DB6D)
        pS3
    else
        pS2;
    
    const z = 1.0 / (x * x);
    const r = p[0] + z * (p[1] + z * (p[2] + z * (p[3] + z * (p[4] + z * p[5]))));
    const s = 1.0 + z * (q[0] + z * (q[1] + z * (q[2] + z * (q[3] + z * q[4]))));
    return 1.0 + r / s;
}

const qR8 = [6]f64{
    0.00000000000000000000e+00,
    7.32421874999935051953e-02,
    1.17682064682252693899e+01,
    5.57673380256401856059e+02,
    8.85919720756468632317e+03,
    3.70146267776887834771e+04,
};
const qS8 = [6]f64{
    1.63776026895689824414e+02,
    8.09834494656449805916e+03,
    1.42538291419120476348e+05,
    8.03309257119514397345e+05,
    8.40501579819060512818e+05,
    -3.43899293537866615225e+05,
};

const qR5 = [6]f64{
    1.84085963594515531381e-11,
    7.32421766612684765896e-02,
    5.83563508962056953777e+00,
    1.35111577286449829671e+02,
    1.02724376596164097464e+03,
    1.98997785864605384631e+03,
};
const qS5 = [6]f64{
    8.27766102236537761883e+01,
    2.07781416421392987104e+03,
    1.88472887785718085070e+04,
    5.67511122894947329769e+04,
    3.59767538425114471465e+04,
    -5.35434275601944773371e+03,
};

const qR3 = [6]f64{
    4.37741014089738620906e-09,
    7.32411180042911447163e-02,
    3.34423137516170720929e+00,
    4.26218440745412650017e+01,
    1.70808091340565596283e+02,
    1.66733948696651168575e+02,
};
const qS3 = [6]f64{
    4.87588729724587182091e+01,
    7.09689221056606015736e+02,
    3.70414822620111362994e+03,
    6.46042516752568917582e+03,
    2.51633368920368957333e+03,
    -1.49247451836156386662e+02,
};

const qR2 = [6]f64{
    1.50444444886983272379e-07,
    7.32234265963079278272e-02,
    1.99819174093815998816e+00,
    1.44956029347885735348e+01,
    3.16662317504781540833e+01,
    1.62527075710929267416e+01,
};
const qS2 = [6]f64{
    3.03655848355219184498e+01,
    2.69348118608049844624e+02,
    8.44783757595320139444e+02,
    8.82935845112488550512e+02,
    2.12666388511798828631e+02,
    -5.31095493882666946917e+00,
};

fn qzero(x: f64) f64 {
    const bits = @as(u64, @bitCast(x));
    var ix = @as(u32, @truncate(bits >> 32));
    ix &= 0x7fffffff;
    
    const p: [6]f64 = if (ix >= 0x40200000)
        qR8
    else if (ix >= 0x40122E8B)
        qR5
    else if (ix >= 0x4006DB6D)
        qR3
    else
        qR2;
    
    const q: [6]f64 = if (ix >= 0x40200000)
        qS8
    else if (ix >= 0x40122E8B)
        qS5
    else if (ix >= 0x4006DB6D)
        qS3
    else
        qS2;
    
    const z = 1.0 / (x * x);
    const r = p[0] + z * (p[1] + z * (p[2] + z * (p[3] + z * (p[4] + z * p[5]))));
    const s = 1.0 + z * (q[0] + z * (q[1] + z * (q[2] + z * (q[3] + z * (q[4] + z * q[5])))));
    return (-0.125 + r / s) / x;
}

// ========== j0f.c ==========

const invsqrtpi_f: f32 = 5.6418961287e-01;
const tpi_f: f32 = 6.3661974669e-01;

fn common_j0f(ix: u32, x: f32, y0: bool) f32 {
    const s = math.sin(x);
    var c = math.cos(x);
    if (y0)
        c = -c;
    var cc = s + c;
    
    if (ix < 0x7f000000) {
        var ss = s - c;
        const z = -math.cos(2 * x);
        if (s * c < 0) {
            cc = z / ss;
        } else {
            ss = z / cc;
        }
        if (ix < 0x58800000) {
            if (y0) {
                ss = -ss;
            }
            cc = pzerof(x) * cc - qzerof(x) * ss;
        }
    }
    return invsqrtpi_f * cc / @sqrt(x);
}

const R02f: f32 = 1.5625000000e-02;
const R03f: f32 = -1.8997929874e-04;
const R04f: f32 = 1.8295404516e-06;
const R05f: f32 = -4.6183270541e-09;
const S01f: f32 = 1.5619102865e-02;
const S02f: f32 = 1.1692678527e-04;
const S03f: f32 = 5.1354652442e-07;
const S04f: f32 = 1.1661400734e-09;

pub export fn j0f_(x: f32) callconv(.c) f32 {
    var ix = @as(u32, @bitCast(x));
    ix &= 0x7fffffff;
    
    if (ix >= 0x7f800000)
        return 1 / (x * x);
    const ax = @abs(x);
    
    if (ix >= 0x40000000) {
        return common_j0f(ix, ax, false);
    }
    
    if (ix >= 0x3a000000) {
        const z = ax * ax;
        const r = z * (R02f + z * (R03f + z * (R04f + z * R05f)));
        const s = 1 + z * (S01f + z * (S02f + z * (S03f + z * S04f)));
        return (1 + ax / 2) * (1 - ax / 2) + z * (r / s);
    }
    
    if (ix >= 0x21800000) {
        return 1 - 0.25 * ax * ax;
    }
    return 1 - ax;
}

const bu00f: f32 = -7.3804296553e-02;
const bu01f: f32 = 1.7666645348e-01;
const bu02f: f32 = -1.3818567619e-02;
const bu03f: f32 = 3.4745343146e-04;
const bu04f: f32 = -3.8140706238e-06;
const bu05f: f32 = 1.9559013964e-08;
const bu06f: f32 = -3.9820518410e-11;
const v01f: f32 = 1.2730483897e-02;
const v02f: f32 = 7.6006865129e-05;
const v03f: f32 = 2.5915085189e-07;
const v04f: f32 = 4.4111031494e-10;

pub export fn y0f_(x: f32) callconv(.c) f32 {
    const ix = @as(u32, @bitCast(x));
    
    if ((ix & 0x7fffffff) == 0)
        return -math.inf(f32);
    if (ix >> 31 != 0)
        return math.nan(f32);
    if (ix >= 0x7f800000)
        return 1 / x;
    
    if (ix >= 0x40000000) {
        return common_j0f(ix, x, true);
    }
    
    if (ix >= 0x39000000) {
        const z = x * x;
        const u = bu00f + z * (bu01f + z * (bu02f + z * (bu03f + z * (bu04f + z * (bu05f + z * bu06f)))));
        const v = 1 + z * (v01f + z * (v02f + z * (v03f + z * v04f)));
        return u / v + tpi_f * (j0f_(x) * @log(x));
    }
    return bu00f + tpi_f * @log(x);
}

const pR8f = [6]f32{
    0.0000000000e+00,
    -7.0312500000e-02,
    -8.0816707611e+00,
    -2.5706311035e+02,
    -2.4852163086e+03,
    -5.2530439453e+03,
};
const pS8f = [5]f32{
    1.1653436279e+02,
    3.8337448730e+03,
    4.0597855469e+04,
    1.1675296875e+05,
    4.7627726562e+04,
};

const pR5f = [6]f32{
    -1.1412546255e-11,
    -7.0312492549e-02,
    -4.1596107483e+00,
    -6.7674766541e+01,
    -3.3123129272e+02,
    -3.4643338013e+02,
};
const pS5f = [5]f32{
    6.0753936768e+01,
    1.0512523193e+03,
    5.9789707031e+03,
    9.6254453125e+03,
    2.4060581055e+03,
};

const pR3f = [6]f32{
    -2.5470459075e-09,
    -7.0311963558e-02,
    -2.4090321064e+00,
    -2.1965976715e+01,
    -5.8079170227e+01,
    -3.1447946548e+01,
};
const pS3f = [5]f32{
    3.5856033325e+01,
    3.6151397705e+02,
    1.1936077881e+03,
    1.1279968262e+03,
    1.7358093262e+02,
};

const pR2f = [6]f32{
    -8.8753431271e-08,
    -7.0303097367e-02,
    -1.4507384300e+00,
    -7.6356959343e+00,
    -1.1193166733e+01,
    -3.2336456776e+00,
};
const pS2f = [5]f32{
    2.2220300674e+01,
    1.3620678711e+02,
    2.7047027588e+02,
    1.5387539673e+02,
    1.4657617569e+01,
};

fn pzerof(x: f32) f32 {
    var ix = @as(u32, @bitCast(x));
    ix &= 0x7fffffff;
    
    const p: [6]f32 = if (ix >= 0x41000000)
        pR8f
    else if (ix >= 0x409173eb)
        pR5f
    else if (ix >= 0x4036d917)
        pR3f
    else
        pR2f;
    
    const q: [5]f32 = if (ix >= 0x41000000)
        pS8f
    else if (ix >= 0x409173eb)
        pS5f
    else if (ix >= 0x4036d917)
        pS3f
    else
        pS2f;
    
    const z = 1.0 / (x * x);
    const r = p[0] + z * (p[1] + z * (p[2] + z * (p[3] + z * (p[4] + z * p[5]))));
    const s = 1.0 + z * (q[0] + z * (q[1] + z * (q[2] + z * (q[3] + z * q[4]))));
    return 1.0 + r / s;
}

const qR8f = [6]f32{
    0.0000000000e+00,
    7.3242187500e-02,
    1.1768206596e+01,
    5.5767340088e+02,
    8.8591972656e+03,
    3.7014625000e+04,
};
const qS8f = [6]f32{
    1.6377603149e+02,
    8.0983447266e+03,
    1.4253829688e+05,
    8.0330925000e+05,
    8.4050156250e+05,
    -3.4389928125e+05,
};

const qR5f = [6]f32{
    1.8408595828e-11,
    7.3242180049e-02,
    5.8356351852e+00,
    1.3511157227e+02,
    1.0272437744e+03,
    1.9899779053e+03,
};
const qS5f = [6]f32{
    8.2776611328e+01,
    2.0778142090e+03,
    1.8847289062e+04,
    5.6751113281e+04,
    3.5976753906e+04,
    -5.3543427734e+03,
};

const qR3f = [6]f32{
    4.3774099900e-09,
    7.3241114616e-02,
    3.3442313671e+00,
    4.2621845245e+01,
    1.7080809021e+02,
    1.6673394775e+02,
};
const qS3f = [6]f32{
    4.8758872986e+01,
    7.0968920898e+02,
    3.7041481934e+03,
    6.4604252930e+03,
    2.5163337402e+03,
    -1.4924745178e+02,
};

const qR2f = [6]f32{
    1.5044444979e-07,
    7.3223426938e-02,
    1.9981917143e+00,
    1.4495602608e+01,
    3.1666231155e+01,
    1.6252708435e+01,
};
const qS2f = [6]f32{
    3.0365585327e+01,
    2.6934811401e+02,
    8.4478375244e+02,
    8.8293585205e+02,
    2.1266638184e+02,
    -5.3109550476e+00,
};

fn qzerof(x: f32) f32 {
    var ix = @as(u32, @bitCast(x));
    ix &= 0x7fffffff;
    
    const p: [6]f32 = if (ix >= 0x41000000)
        qR8f
    else if (ix >= 0x409173eb)
        qR5f
    else if (ix >= 0x4036d917)
        qR3f
    else
        qR2f;
    
    const q: [6]f32 = if (ix >= 0x41000000)
        qS8f
    else if (ix >= 0x409173eb)
        qS5f
    else if (ix >= 0x4036d917)
        qS3f
    else
        qS2f;
    
    const z = 1.0 / (x * x);
    const r = p[0] + z * (p[1] + z * (p[2] + z * (p[3] + z * (p[4] + z * p[5]))));
    const s = 1.0 + z * (q[0] + z * (q[1] + z * (q[2] + z * (q[3] + z * (q[4] + z * q[5])))));
    return (-0.125 + r / s) / x;
}

// ========== j1.c ==========

fn common_j1(ix: u32, x: f64, y1: bool, sign: bool) f64 {
    var s = math.sin(x);
    if (y1)
        s = -s;
    const c = math.cos(x);
    var cc = s - c;
    
    if (ix < 0x7fe00000) {
        var ss = -s - c;
        const z = math.cos(2 * x);
        if (s * c > 0) {
            cc = z / ss;
        } else {
            ss = z / cc;
        }
        if (ix < 0x48000000) {
            if (y1) {
                ss = -ss;
            }
            cc = pone(x) * cc - qone(x) * ss;
        }
    }
    
    const result = invsqrtpi * cc / @sqrt(x);
    return if (sign) -result else result;
}

const r00: f64 = -6.25000000000000000000e-02;
const r01: f64 = 1.40705666955189706048e-03;
const r02: f64 = -1.59955631084035597520e-05;
const r03: f64 = 4.96727999609584448412e-08;
const s01: f64 = 1.91537599538363460805e-02;
const s02: f64 = 1.85946785588630915560e-04;
const s03: f64 = 1.17718464042623683263e-06;
const s04: f64 = 5.04636257076217042715e-09;
const s05: f64 = 1.23542274426137913908e-11;

pub export fn j1_(x: f64) callconv(.c) f64 {
    const bits = @as(u64, @bitCast(x));
    var ix = @as(u32, @truncate(bits >> 32));
    const sign = (ix >> 31) != 0;
    ix &= 0x7fffffff;
    
    if (ix >= 0x7ff00000)
        return 1 / (x * x);
    
    if (ix >= 0x40000000)
        return common_j1(ix, @abs(x), false, sign);
    
    var z: f64 = undefined;
    if (ix >= 0x38000000) {
        const x2 = x * x;
        const r = x2 * (r00 + x2 * (r01 + x2 * (r02 + x2 * r03)));
        const s = 1 + x2 * (s01 + x2 * (s02 + x2 * (s03 + x2 * (s04 + x2 * s05))));
        z = r / s;
    } else {
        z = x;
    }
    return (0.5 + z) * x;
}

const U0 = [5]f64{
    -1.96057090646238940668e-01,
    5.04438716639811282616e-02,
    -1.91256895875763547298e-03,
    2.35252600561610495928e-05,
    -9.19099158039878874504e-08,
};
const V0 = [5]f64{
    1.99167318236649903973e-02,
    2.02552581025135171496e-04,
    1.35608801097516229404e-06,
    6.22741452364621501295e-09,
    1.66559246207992079114e-11,
};

pub export fn y1_(x: f64) callconv(.c) f64 {
    const bits = @as(u64, @bitCast(x));
    const ix = @as(u32, @truncate(bits >> 32));
    const lx = @as(u32, @truncate(bits));
    
    if ((ix << 1 | lx) == 0)
        return -math.inf(f64);
    if (ix >> 31 != 0)
        return math.nan(f64);
    if (ix >= 0x7ff00000)
        return 1 / x;
    
    if (ix >= 0x40000000)
        return common_j1(ix, x, true, false);
    
    if (ix < 0x3c900000)
        return -tpi / x;
    
    const z = x * x;
    const u = U0[0] + z * (U0[1] + z * (U0[2] + z * (U0[3] + z * U0[4])));
    const v = 1 + z * (V0[0] + z * (V0[1] + z * (V0[2] + z * (V0[3] + z * V0[4]))));
    return x * (u / v) + tpi * (j1_(x) * @log(x) - 1 / x);
}

const pr8 = [6]f64{
    0.00000000000000000000e+00,
    1.17187499999988647970e-01,
    1.32394806593073575129e+01,
    4.12051854307378562225e+02,
    3.87474538913960532227e+03,
    7.91447954031891731574e+03,
};
const ps8 = [5]f64{
    1.14207370375678408436e+02,
    3.65093083420853463394e+03,
    3.69562060269033463555e+04,
    9.76027935934950801311e+04,
    3.08042720627888811578e+04,
};

const pr5 = [6]f64{
    1.31990519556243522749e-11,
    1.17187493190614097638e-01,
    6.80275127868432871736e+00,
    1.08308182990189109773e+02,
    5.17636139533199752805e+02,
    5.28715201363337541807e+02,
};
const ps5 = [5]f64{
    5.92805987221131331921e+01,
    9.91401418733614377743e+02,
    5.35326695291487976647e+03,
    7.84469031749551231769e+03,
    1.50404688810361062679e+03,
};

const pr3 = [6]f64{
    3.02503916137373618024e-09,
    1.17186865567253592491e-01,
    3.93297750033315640650e+00,
    3.51194035591636932736e+01,
    9.10550110750781271918e+01,
    4.85590685197364919645e+01,
};
const ps3 = [5]f64{
    3.47913095001251519989e+01,
    3.36762458747825746741e+02,
    1.04687139975775130551e+03,
    8.90811346398256432622e+02,
    1.03787932439639277504e+02,
};

const pr2 = [6]f64{
    1.07710830106873743082e-07,
    1.17176219462683348094e-01,
    2.36851496667608785174e+00,
    1.22426109148261232917e+01,
    1.76939711271687727390e+01,
    5.07352312588818499250e+00,
};
const ps2 = [5]f64{
    2.14364859363821409488e+01,
    1.25290227168402751090e+02,
    2.32276469057162813669e+02,
    1.17679373287147100768e+02,
    8.36463893371618283368e+00,
};

fn pone(x: f64) f64 {
    const bits = @as(u64, @bitCast(x));
    var ix = @as(u32, @truncate(bits >> 32));
    ix &= 0x7fffffff;
    
    const p: [6]f64 = if (ix >= 0x40200000)
        pr8
    else if (ix >= 0x40122E8B)
        pr5
    else if (ix >= 0x4006DB6D)
        pr3
    else
        pr2;
    
    const q: [5]f64 = if (ix >= 0x40200000)
        ps8
    else if (ix >= 0x40122E8B)
        ps5
    else if (ix >= 0x4006DB6D)
        ps3
    else
        ps2;
    
    const z = 1.0 / (x * x);
    const r = p[0] + z * (p[1] + z * (p[2] + z * (p[3] + z * (p[4] + z * p[5]))));
    const s = 1.0 + z * (q[0] + z * (q[1] + z * (q[2] + z * (q[3] + z * q[4]))));
    return 1.0 + r / s;
}

const qr8 = [6]f64{
    0.00000000000000000000e+00,
    -1.02539062499992714161e-01,
    -1.62717534544589987888e+01,
    -7.59601722513950107896e+02,
    -1.18498066702429587167e+04,
    -4.84385124285750353010e+04,
};
const qs8 = [6]f64{
    1.61395369700722909556e+02,
    7.82538599923348465381e+03,
    1.33875336287249578163e+05,
    7.19657723683240939863e+05,
    6.66601232617776375264e+05,
    -2.94490264303834643215e+05,
};

const qr5 = [6]f64{
    -2.08979931141764104297e-11,
    -1.02539050241375426231e-01,
    -8.05644828123936029840e+00,
    -1.83669607474888380239e+02,
    -1.37319376065508163265e+03,
    -2.61244440453215656817e+03,
};
const qs5 = [6]f64{
    8.12765501384335777857e+01,
    1.99179873460485964642e+03,
    1.74684851924908907677e+04,
    4.98514270910352279316e+04,
    2.79480751638918118260e+04,
    -4.71918354795128470869e+03,
};

const qr3 = [6]f64{
    -5.07831226461766561369e-09,
    -1.02537829820837089745e-01,
    -4.61011581139473403113e+00,
    -5.78472216562783643212e+01,
    -2.28244540737631695038e+02,
    -2.19210128478909325622e+02,
};
const qs3 = [6]f64{
    4.76651550323729509273e+01,
    6.73865112676699709482e+02,
    3.38015286679526343505e+03,
    5.54772909720722782367e+03,
    1.90311919338810798763e+03,
    -1.35201191444307340817e+02,
};

const qr2 = [6]f64{
    -1.78381727510958865572e-07,
    -1.02517042607985553460e-01,
    -2.75220568278187460720e+00,
    -1.96636162643703720221e+01,
    -4.23253133372830490089e+01,
    -2.13719211703704061733e+01,
};
const qs2 = [6]f64{
    2.95333629060523854548e+01,
    2.52981549982190529136e+02,
    7.57502834868645436472e+02,
    7.39393205320467245656e+02,
    1.55949003336666123687e+02,
    -4.95949898822628210127e+00,
};

fn qone(x: f64) f64 {
    const bits = @as(u64, @bitCast(x));
    var ix = @as(u32, @truncate(bits >> 32));
    ix &= 0x7fffffff;
    
    const p: [6]f64 = if (ix >= 0x40200000)
        qr8
    else if (ix >= 0x40122E8B)
        qr5
    else if (ix >= 0x4006DB6D)
        qr3
    else
        qr2;
    
    const q: [6]f64 = if (ix >= 0x40200000)
        qs8
    else if (ix >= 0x40122E8B)
        qs5
    else if (ix >= 0x4006DB6D)
        qs3
    else
        qs2;
    
    const z = 1.0 / (x * x);
    const r = p[0] + z * (p[1] + z * (p[2] + z * (p[3] + z * (p[4] + z * p[5]))));
    const s = 1.0 + z * (q[0] + z * (q[1] + z * (q[2] + z * (q[3] + z * (q[4] + z * q[5])))));
    return (0.375 + r / s) / x;
}

// ========== j1f.c ==========

fn common_j1f(ix: u32, x: f32, y1: bool, sign: bool) f32 {
    var s = math.sin(x);
    if (y1)
        s = -s;
    const c = math.cos(x);
    var cc = s - c;
    
    if (ix < 0x7f000000) {
        var ss = -s - c;
        const z = math.cos(2 * x);
        if (s * c > 0) {
            cc = z / ss;
        } else {
            ss = z / cc;
        }
        if (ix < 0x58800000) {
            if (y1) {
                ss = -ss;
            }
            cc = ponef(x) * cc - qonef(x) * ss;
        }
    }
    
    const result = invsqrtpi_f * cc / @sqrt(x);
    return if (sign) -result else result;
}

const r00f: f32 = -6.2500000000e-02;
const r01f: f32 = 1.4070566976e-03;
const r02f: f32 = -1.5995563444e-05;
const r03f: f32 = 4.9672799207e-08;
const s01f: f32 = 1.9153760746e-02;
const s02f: f32 = 1.8594678841e-04;
const s03f: f32 = 1.1771846857e-06;
const s04f: f32 = 5.0463624390e-09;
const s05f: f32 = 1.2354227016e-11;

pub export fn j1f_(x: f32) callconv(.c) f32 {
    var ix = @as(u32, @bitCast(x));
    const sign = (ix >> 31) != 0;
    ix &= 0x7fffffff;
    
    if (ix >= 0x7f800000)
        return 1 / (x * x);
    
    if (ix >= 0x40000000)
        return common_j1f(ix, @abs(x), false, sign);
    
    var z: f32 = undefined;
    if (ix >= 0x39000000) {
        const x2 = x * x;
        const r = x2 * (r00f + x2 * (r01f + x2 * (r02f + x2 * r03f)));
        const s = 1 + x2 * (s01f + x2 * (s02f + x2 * (s03f + x2 * (s04f + x2 * s05f))));
        z = 0.5 + r / s;
    } else {
        z = 0.5;
    }
    return z * x;
}

const U0f = [5]f32{
    -1.9605709612e-01,
    5.0443872809e-02,
    -1.9125689287e-03,
    2.3525259166e-05,
    -9.1909917899e-08,
};
const V0f = [5]f32{
    1.9916731864e-02,
    2.0255257550e-04,
    1.3560879779e-06,
    6.2274145840e-09,
    1.6655924903e-11,
};

pub export fn y1f_(x: f32) callconv(.c) f32 {
    const ix = @as(u32, @bitCast(x));
    
    if ((ix & 0x7fffffff) == 0)
        return -math.inf(f32);
    if (ix >> 31 != 0)
        return math.nan(f32);
    if (ix >= 0x7f800000)
        return 1 / x;
    
    if (ix >= 0x40000000)
        return common_j1f(ix, x, true, false);
    
    if (ix < 0x33000000)
        return -tpi_f / x;
    
    const z = x * x;
    const u = U0f[0] + z * (U0f[1] + z * (U0f[2] + z * (U0f[3] + z * U0f[4])));
    const v = 1.0 + z * (V0f[0] + z * (V0f[1] + z * (V0f[2] + z * (V0f[3] + z * V0f[4]))));
    return x * (u / v) + tpi_f * (j1f_(x) * @log(x) - 1.0 / x);
}

const pr8f = [6]f32{
    0.0000000000e+00,
    1.1718750000e-01,
    1.3239480972e+01,
    4.1205184937e+02,
    3.8747453613e+03,
    7.9144794922e+03,
};
const ps8f = [5]f32{
    1.1420736694e+02,
    3.6509309082e+03,
    3.6956207031e+04,
    9.7602796875e+04,
    3.0804271484e+04,
};

const pr5f = [6]f32{
    1.3199052094e-11,
    1.1718749255e-01,
    6.8027510643e+00,
    1.0830818176e+02,
    5.1763616943e+02,
    5.2871520996e+02,
};
const ps5f = [5]f32{
    5.9280597687e+01,
    9.9140142822e+02,
    5.3532670898e+03,
    7.8446904297e+03,
    1.5040468750e+03,
};

const pr3f = [6]f32{
    3.0250391081e-09,
    1.1718686670e-01,
    3.9329774380e+00,
    3.5119403839e+01,
    9.1055007935e+01,
    4.8559066772e+01,
};
const ps3f = [5]f32{
    3.4791309357e+01,
    3.3676245117e+02,
    1.0468714600e+03,
    8.9081134033e+02,
    1.0378793335e+02,
};

const pr2f = [6]f32{
    1.0771083225e-07,
    1.1717621982e-01,
    2.3685150146e+00,
    1.2242610931e+01,
    1.7693971634e+01,
    5.0735230446e+00,
};
const ps2f = [5]f32{
    2.1436485291e+01,
    1.2529022980e+02,
    2.3227647400e+02,
    1.1767937469e+02,
    8.3646392822e+00,
};

fn ponef(x: f32) f32 {
    var ix = @as(u32, @bitCast(x));
    ix &= 0x7fffffff;
    
    const p: [6]f32 = if (ix >= 0x41000000)
        pr8f
    else if (ix >= 0x409173eb)
        pr5f
    else if (ix >= 0x4036d917)
        pr3f
    else
        pr2f;
    
    const q: [5]f32 = if (ix >= 0x41000000)
        ps8f
    else if (ix >= 0x409173eb)
        ps5f
    else if (ix >= 0x4036d917)
        ps3f
    else
        ps2f;
    
    const z = 1.0 / (x * x);
    const r = p[0] + z * (p[1] + z * (p[2] + z * (p[3] + z * (p[4] + z * p[5]))));
    const s = 1.0 + z * (q[0] + z * (q[1] + z * (q[2] + z * (q[3] + z * q[4]))));
    return 1.0 + r / s;
}

const qr8f = [6]f32{
    0.0000000000e+00,
    -1.0253906250e-01,
    -1.6271753311e+01,
    -7.5960174561e+02,
    -1.1849806641e+04,
    -4.8438511719e+04,
};
const qs8f = [6]f32{
    1.6139537048e+02,
    7.8253862305e+03,
    1.3387534375e+05,
    7.1965775000e+05,
    6.6660125000e+05,
    -2.9449025000e+05,
};

const qr5f = [6]f32{
    -2.0897993405e-11,
    -1.0253904760e-01,
    -8.0564479828e+00,
    -1.8366960144e+02,
    -1.3731937256e+03,
    -2.6124443359e+03,
};
const qs5f = [6]f32{
    8.1276550293e+01,
    1.9917987061e+03,
    1.7468484375e+04,
    4.9851425781e+04,
    2.7948074219e+04,
    -4.7191835938e+03,
};

const qr3f = [6]f32{
    -5.0783124372e-09,
    -1.0253783315e-01,
    -4.6101160049e+00,
    -5.7847221375e+01,
    -2.2824453735e+02,
    -2.1921012878e+02,
};
const qs3f = [6]f32{
    4.7665153503e+01,
    6.7386511230e+02,
    3.3801528320e+03,
    5.5477290039e+03,
    1.9031191406e+03,
    -1.3520118713e+02,
};

const qr2f = [6]f32{
    -1.7838172539e-07,
    -1.0251704603e-01,
    -2.7522056103e+00,
    -1.9663616180e+01,
    -4.2325313568e+01,
    -2.1371921539e+01,
};
const qs2f = [6]f32{
    2.9533363342e+01,
    2.5298155212e+02,
    7.5750280762e+02,
    7.3939318848e+02,
    1.5594900513e+02,
    -4.9594988823e+00,
};

fn qonef(x: f32) f32 {
    var ix = @as(u32, @bitCast(x));
    ix &= 0x7fffffff;
    
    const p: [6]f32 = if (ix >= 0x41000000)
        qr8f
    else if (ix >= 0x409173eb)
        qr5f
    else if (ix >= 0x4036d917)
        qr3f
    else
        qr2f;
    
    const q: [6]f32 = if (ix >= 0x41000000)
        qs8f
    else if (ix >= 0x409173eb)
        qs5f
    else if (ix >= 0x4036d917)
        qs3f
    else
        qs2f;
    
    const z = 1.0 / (x * x);
    const r = p[0] + z * (p[1] + z * (p[2] + z * (p[3] + z * (p[4] + z * p[5]))));
    const s = 1.0 + z * (q[0] + z * (q[1] + z * (q[2] + z * (q[3] + z * (q[4] + z * q[5])))));
    return (0.375 + r / s) / x;
}

// ========== jn.c ==========

const invsqrtpi_jn: f64 = 5.64189583547756279280e-01;

pub export fn jn_(n: c_int, x: f64) callconv(.c) f64 {
    const bits = @as(u64, @bitCast(x));
    var ix = @as(u32, @truncate(bits >> 32));
    const lx = @as(u32, @truncate(bits));
    var sign = ix >> 31;
    ix &= 0x7fffffff;
    
    if ((ix | ((lx | -%lx) >> 31)) > 0x7ff00000)
        return x;
    
    var nm1: u32 = undefined;
    var x_abs = x;
    if (n == 0)
        return j0_(x);
    if (n < 0) {
        nm1 = @intCast(-(n + 1));
        x_abs = -x;
        sign ^= 1;
    } else {
        nm1 = @intCast(n - 1);
    }
    if (nm1 == 0)
        return j1_(x_abs);
    
    sign &= @intCast(n);
    x_abs = @abs(x_abs);
    
    var b: f64 = undefined;
    if ((ix | lx) == 0 or ix == 0x7ff00000) {
        b = 0.0;
    } else if (@as(f64, @floatFromInt(nm1)) < x_abs) {
        if (ix >= 0x52d00000) {
            const temp: f64 = switch (nm1 & 3) {
                0 => -math.cos(x_abs) + math.sin(x_abs),
                1 => -math.cos(x_abs) - math.sin(x_abs),
                2 => math.cos(x_abs) - math.sin(x_abs),
                else => math.cos(x_abs) + math.sin(x_abs),
            };
            b = invsqrtpi_jn * temp / @sqrt(x_abs);
        } else {
            var a = j0_(x_abs);
            b = j1_(x_abs);
            var i: u32 = 0;
            while (i < nm1) : (i += 1) {
                const temp = b;
                b = b * (2.0 * @as(f64, @floatFromInt(i + 1)) / x_abs) - a;
                a = temp;
            }
        }
    } else {
        if (ix < 0x3e100000) {
            if (nm1 > 32) {
                b = 0.0;
            } else {
                const temp = x_abs * 0.5;
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
            const nf = @as(f64, @floatFromInt(nm1)) + 1.0;
            const w = 2 * nf / x_abs;
            const h = 2 / x_abs;
            var z = w + h;
            var q0 = w;
            var q1 = w * z - 1.0;
            var k: i32 = 1;
            while (q1 < 1.0e9) {
                k += 1;
                z += h;
                const tmp = z * q1 - q0;
                q0 = q1;
                q1 = tmp;
            }
            var t: f64 = 0.0;
            var i: i32 = k;
            while (i >= 0) : (i -= 1) {
                t = 1.0 / (2.0 * (@as(f64, @floatFromInt(i)) + nf) / x_abs - t);
            }
            var a = t;
            b = 1.0;
            const tmp = nf * @log(@abs(w));
            if (tmp < 7.09782712893383973096e+02) {
                var j: i32 = @intCast(nm1);
                while (j > 0) : (j -= 1) {
                    const temp = b;
                    b = b * (2.0 * @as(f64, @floatFromInt(j))) / x_abs - a;
                    a = temp;
                }
            } else {
                var j: i32 = @intCast(nm1);
                while (j > 0) : (j -= 1) {
                    const temp = b;
                    b = b * (2.0 * @as(f64, @floatFromInt(j))) / x_abs - a;
                    a = temp;
                    if (b > 0x1p500) {
                        a /= b;
                        t /= b;
                        b = 1.0;
                    }
                }
            }
            const z_val = j0_(x_abs);
            const w_val = j1_(x_abs);
            if (@abs(z_val) >= @abs(w_val)) {
                b = t * z_val / b;
            } else {
                b = t * w_val / a;
            }
        }
    }
    return if (sign != 0) -b else b;
}

pub export fn yn_(n: c_int, x: f64) callconv(.c) f64 {
    const bits = @as(u64, @bitCast(x));
    var ix = @as(u32, @truncate(bits >> 32));
    const lx = @as(u32, @truncate(bits));
    const sign_bit = ix >> 31;
    ix &= 0x7fffffff;
    
    if ((ix | ((lx | -%lx) >> 31)) > 0x7ff00000)
        return x;
    if (sign_bit != 0 and (ix | lx) != 0)
        return math.nan(f64);
    if (ix == 0x7ff00000)
        return 0.0;
    
    var nm1: u32 = undefined;
    var sign: u32 = undefined;
    if (n == 0)
        return y0_(x);
    if (n < 0) {
        nm1 = @intCast(-(n + 1));
        sign = @intCast(n & 1);
    } else {
        nm1 = @intCast(n - 1);
        sign = 0;
    }
    if (nm1 == 0)
        return if (sign != 0) -y1_(x) else y1_(x);
    
    var b: f64 = undefined;
    if (ix >= 0x52d00000) {
        const temp: f64 = switch (nm1 & 3) {
            0 => -math.sin(x) - math.cos(x),
            1 => -math.sin(x) + math.cos(x),
            2 => math.sin(x) + math.cos(x),
            else => math.sin(x) - math.cos(x),
        };
        b = invsqrtpi_jn * temp / @sqrt(x);
    } else {
        var a = y0_(x);
        b = y1_(x);
        const b_bits = @as(u64, @bitCast(b));
        var ib = @as(u32, @truncate(b_bits >> 32));
        var i: u32 = 0;
        while (i < nm1 and ib != 0xfff00000) : (i += 1) {
            const temp = b;
            b = (2.0 * @as(f64, @floatFromInt(i + 1)) / x) * b - a;
            const b_bits_new = @as(u64, @bitCast(b));
            ib = @as(u32, @truncate(b_bits_new >> 32));
            a = temp;
        }
    }
    return if (sign != 0) -b else b;
}

// ========== jnf.c ==========

pub export fn jnf_(n: c_int, x: f32) callconv(.c) f32 {
    var ix = @as(u32, @bitCast(x));
    var sign = ix >> 31;
    ix &= 0x7fffffff;
    
    if (ix > 0x7f800000)
        return x;
    
    var nm1: u32 = undefined;
    var x_abs = x;
    if (n == 0)
        return j0f_(x);
    if (n < 0) {
        nm1 = @intCast(-(n + 1));
        x_abs = -x;
        sign ^= 1;
    } else {
        nm1 = @intCast(n - 1);
    }
    if (nm1 == 0)
        return j1f_(x_abs);
    
    sign &= @intCast(n);
    x_abs = @abs(x_abs);
    
    var b: f32 = undefined;
    if (ix == 0 or ix == 0x7f800000) {
        b = 0.0;
    } else if (@as(f32, @floatFromInt(nm1)) < x_abs) {
        var a = j0f_(x_abs);
        b = j1f_(x_abs);
        var i: u32 = 0;
        while (i < nm1) : (i += 1) {
            const temp = b;
            b = b * (2.0 * @as(f32, @floatFromInt(i + 1)) / x_abs) - a;
            a = temp;
        }
    } else {
        if (ix < 0x35800000) {
            var nm1_clamp = nm1;
            if (nm1 > 8)
                nm1_clamp = 8;
            const temp = 0.5 * x_abs;
            b = temp;
            var a: f32 = 1.0;
            var i: u32 = 2;
            while (i <= nm1_clamp + 1) : (i += 1) {
                a *= @floatFromInt(i);
                b *= temp;
            }
            b = b / a;
        } else {
            const nf = @as(f32, @floatFromInt(nm1)) + 1.0;
            const w = 2 * nf / x_abs;
            const h = 2 / x_abs;
            var z = w + h;
            var q0 = w;
            var q1 = w * z - 1.0;
            var k: i32 = 1;
            while (q1 < 1.0e4) {
                k += 1;
                z += h;
                const tmp = z * q1 - q0;
                q0 = q1;
                q1 = tmp;
            }
            var t: f32 = 0.0;
            var i: i32 = k;
            while (i >= 0) : (i -= 1) {
                t = 1.0 / (2.0 * (@as(f32, @floatFromInt(i)) + nf) / x_abs - t);
            }
            var a = t;
            b = 1.0;
            const tmp = nf * @log(@abs(w));
            if (tmp < 88.721679688) {
                var j: i32 = @intCast(nm1);
                while (j > 0) : (j -= 1) {
                    const temp = b;
                    b = 2.0 * @as(f32, @floatFromInt(j)) * b / x_abs - a;
                    a = temp;
                }
            } else {
                var j: i32 = @intCast(nm1);
                while (j > 0) : (j -= 1) {
                    const temp = b;
                    b = 2.0 * @as(f32, @floatFromInt(j)) * b / x_abs - a;
                    a = temp;
                    if (b > 0x1p60) {
                        a /= b;
                        t /= b;
                        b = 1.0;
                    }
                }
            }
            const z_val = j0f_(x_abs);
            const w_val = j1f_(x_abs);
            if (@abs(z_val) >= @abs(w_val)) {
                b = t * z_val / b;
            } else {
                b = t * w_val / a;
            }
        }
    }
    return if (sign != 0) -b else b;
}

pub export fn ynf_(n: c_int, x: f32) callconv(.c) f32 {
    var ix = @as(u32, @bitCast(x));
    const sign_bit = ix >> 31;
    ix &= 0x7fffffff;
    
    if (ix > 0x7f800000)
        return x;
    if (sign_bit != 0 and ix != 0)
        return math.nan(f32);
    if (ix == 0x7f800000)
        return 0.0;
    
    var nm1: u32 = undefined;
    var sign: u32 = undefined;
    if (n == 0)
        return y0f_(x);
    if (n < 0) {
        nm1 = @intCast(-(n + 1));
        sign = @intCast(n & 1);
    } else {
        nm1 = @intCast(n - 1);
        sign = 0;
    }
    if (nm1 == 0)
        return if (sign != 0) -y1f_(x) else y1f_(x);
    
    var a = y0f_(x);
    var b = y1f_(x);
    var ib = @as(u32, @bitCast(b));
    var i: u32 = 0;
    while (i < nm1 and ib != 0xff800000) : (i += 1) {
        const temp = b;
        b = (2.0 * @as(f32, @floatFromInt(i + 1)) / x) * b - a;
        ib = @as(u32, @bitCast(b));
        a = temp;
    }
    return if (sign != 0) -b else b;
}
