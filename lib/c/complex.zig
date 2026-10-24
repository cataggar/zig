const builtin = @import("builtin");
const std = @import("std");
const mc = std.math.complex;
const symbol = @import("../c.zig").symbol;

const CF64 = extern struct { re: f64, im: f64 };
const CF32 = extern struct { re: f32, im: f32 };
const long_double = c_longdouble;
const math_ld = f64; // Complex math uses f64 since std.math.complex does not support c_longdouble or f128
const CFLD = extern struct { re: long_double, im: long_double };

fn toZ64(c: CF64) mc.Complex(f64) {
    return .{ .re = @floatCast(c.re), .im = @floatCast(c.im) };
}
fn fromZ64(c: mc.Complex(f64)) CF64 {
    return .{ .re = @floatCast(c.re), .im = @floatCast(c.im) };
}
fn toZ32(c: CF32) mc.Complex(f32) {
    return .{ .re = @floatCast(c.re), .im = @floatCast(c.im) };
}
fn fromZ32(c: mc.Complex(f32)) CF32 {
    return .{ .re = @floatCast(c.re), .im = @floatCast(c.im) };
}
fn toZLD(c: CFLD) mc.Complex(math_ld) {
    // c_longdouble -> f64 conversion
    return .{ .re = @floatCast(c.re), .im = @floatCast(c.im) };
}
fn fromZLD(c: mc.Complex(math_ld)) CFLD {
    return .{ .re = @floatCast(c.re), .im = @floatCast(c.im) };
}

// --- Field accessors (musl-only) ---

fn crealC(z: CF64) callconv(.c) f64 {
    return z.re;
}
fn crealfC(z: CF32) callconv(.c) f32 {
    return z.re;
}
fn creallC(z: CFLD) callconv(.c) long_double {
    return z.re;
}
fn cimagC(z: CF64) callconv(.c) f64 {
    return z.im;
}
fn cimagfC(z: CF32) callconv(.c) f32 {
    return z.im;
}
fn cimaglC(z: CFLD) callconv(.c) long_double {
    return z.im;
}

// --- Conjugate ---

fn conjC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.conj(toZ64(z)));
}
fn conjfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.conj(toZ32(z)));
}
fn conjlC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.conj(toZLD(z)));
}

// --- Absolute value ---

fn cabsC(z: CF64) callconv(.c) f64 {
    return mc.abs(toZ64(z));
}
fn cabsfC(z: CF32) callconv(.c) f32 {
    return mc.abs(toZ32(z));
}
fn cabslC(z: CFLD) callconv(.c) long_double {
    return mc.abs(toZLD(z));
}

// --- Argument/phase ---

fn cargC(z: CF64) callconv(.c) f64 {
    return mc.arg(toZ64(z));
}
fn cargfC(z: CF32) callconv(.c) f32 {
    return mc.arg(toZ32(z));
}
fn carglC(z: CFLD) callconv(.c) long_double {
    return mc.arg(toZLD(z));
}

// --- Projection ---

fn cprojC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.proj(toZ64(z)));
}
fn cprojfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.proj(toZ32(z)));
}
fn cprojlC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.proj(toZLD(z)));
}

// --- Exponential ---

fn frexp_exp64(x: f64, expt: *c_int) f64 {
    const k = 1799;
    const kln2 = 1246.97177782734161156;
    const exp_x = @exp(x - kln2);
    const fx: u64 = @bitCast(exp_x);
    const hx: u32 = @intCast(fx >> 32);
    const lx: u32 = @truncate(fx);
    expt.* = @as(c_int, @intCast(hx >> 20)) - (0x3ff + 1023) + k;
    const high_word = (hx & 0xfffff) | ((0x3ff + 1023) << 20);
    return @bitCast((@as(u64, high_word) << 32) | lx);
}

fn ldexp_cexpC(z: CF64, expt: c_int) callconv(.c) CF64 {
    var ex_expt: c_int = undefined;
    const exp_x = frexp_exp64(z.re, &ex_expt);
    const exptf: i64 = @as(i64, expt) + ex_expt;
    const half_expt1 = @divTrunc(exptf, 2);
    const scale1: f64 = @bitCast(@as(u64, @bitCast(0x3ff + half_expt1)) << 52);
    const half_expt2 = exptf - half_expt1;
    const scale2: f64 = @bitCast(@as(u64, @bitCast(0x3ff + half_expt2)) << 52);
    return .{
        .re = @cos(z.im) * exp_x * scale1 * scale2,
        .im = @sin(z.im) * exp_x * scale1 * scale2,
    };
}

fn frexp_exp32(x: f32, expt: *c_int) f32 {
    const k = 235;
    const kln2 = 162.88958740;
    const exp_x = @exp(x - kln2);
    const hx: u32 = @bitCast(exp_x);
    expt.* = @as(c_int, @intCast(hx >> 23)) - (0x7f + 127) + k;
    return @bitCast((hx & 0x7fffff) | ((0x7f + 127) << 23));
}

fn ldexp_cexpfC(z: CF32, expt: c_int) callconv(.c) CF32 {
    var ex_expt: c_int = undefined;
    const exp_x = frexp_exp32(z.re, &ex_expt);
    const exptf: i32 = expt + ex_expt;
    const half_expt1 = @divTrunc(exptf, 2);
    const scale1: f32 = @bitCast(@as(u32, @bitCast(0x7f + half_expt1)) << 23);
    const half_expt2 = exptf - half_expt1;
    const scale2: f32 = @bitCast(@as(u32, @bitCast(0x7f + half_expt2)) << 23);
    return .{
        .re = @cos(z.im) * exp_x * scale1 * scale2,
        .im = @sin(z.im) * exp_x * scale1 * scale2,
    };
}

fn cexpC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.exp(toZ64(z)));
}
fn cexpfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.exp(toZ32(z)));
}
fn cexplC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.exp(toZLD(z)));
}

// --- Logarithm ---

fn clogC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.log(toZ64(z)));
}
fn clogfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.log(toZ32(z)));
}
fn cloglC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.log(toZLD(z)));
}

// --- Power ---

fn cpowC(z: CF64, s: CF64) callconv(.c) CF64 {
    return fromZ64(mc.pow(toZ64(z), toZ64(s)));
}
fn cpowfC(z: CF32, s: CF32) callconv(.c) CF32 {
    return fromZ32(mc.pow(toZ32(z), toZ32(s)));
}
fn cpowlC(z: CFLD, s: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.pow(toZLD(z), toZLD(s)));
}

// --- Square root ---

fn csqrtC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.sqrt(toZ64(z)));
}
fn csqrtfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.sqrt(toZ32(z)));
}
fn csqrtlC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.sqrt(toZLD(z)));
}

// --- Trigonometric ---

fn ccosC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.cos(toZ64(z)));
}
fn ccosfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.cos(toZ32(z)));
}
fn ccoslC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.cos(toZLD(z)));
}

fn csinC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.sin(toZ64(z)));
}
fn csinfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.sin(toZ32(z)));
}
fn csinlC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.sin(toZLD(z)));
}

fn ctanC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.tan(toZ64(z)));
}
fn ctanfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.tan(toZ32(z)));
}
fn ctanlC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.tan(toZLD(z)));
}

// --- Hyperbolic ---

fn ccoshC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.cosh(toZ64(z)));
}
fn ccoshfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.cosh(toZ32(z)));
}
fn ccoshlC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.cosh(toZLD(z)));
}

fn csinhC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.sinh(toZ64(z)));
}
fn csinhfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.sinh(toZ32(z)));
}
fn csinhlC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.sinh(toZLD(z)));
}

fn ctanhC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.tanh(toZ64(z)));
}
fn ctanhfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.tanh(toZ32(z)));
}
fn ctanhlC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.tanh(toZLD(z)));
}

// --- Inverse trigonometric ---

fn cacosC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.acos(toZ64(z)));
}
fn cacosfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.acos(toZ32(z)));
}
fn cacoslC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.acos(toZLD(z)));
}

fn casinC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.asin(toZ64(z)));
}
fn casinfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.asin(toZ32(z)));
}
fn casinlC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.asin(toZLD(z)));
}

fn catanC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.atan(toZ64(z)));
}
fn catanfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.atan(toZ32(z)));
}
fn catanlC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.atan(toZLD(z)));
}

// --- Inverse hyperbolic ---

fn cacoshC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.acosh(toZ64(z)));
}
fn cacoshfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.acosh(toZ32(z)));
}
fn cacoshlC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.acosh(toZLD(z)));
}

fn casinhC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.asinh(toZ64(z)));
}
fn casinhfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.asinh(toZ32(z)));
}
fn casinhlC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.asinh(toZLD(z)));
}

fn catanhC(z: CF64) callconv(.c) CF64 {
    return fromZ64(mc.atanh(toZ64(z)));
}
fn catanhfC(z: CF32) callconv(.c) CF32 {
    return fromZ32(mc.atanh(toZ32(z)));
}
fn catanhlC(z: CFLD) callconv(.c) CFLD {
    return fromZLD(mc.atanh(toZLD(z)));
}

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        // abs
        symbol(&cabsC, "cabs");
        symbol(&cabsfC, "cabsf");
        symbol(&cabslC, "cabsl");
        // arg
        symbol(&cargC, "carg");
        symbol(&cargfC, "cargf");
        symbol(&carglC, "cargl");
        // conj
        symbol(&conjC, "conj");
        symbol(&conjfC, "conjf");
        symbol(&conjlC, "conjl");
        // proj
        symbol(&cprojC, "cproj");
        symbol(&cprojfC, "cprojf");
        symbol(&cprojlC, "cprojl");
        // exp
        symbol(&cexpC, "cexp");
        symbol(&cexpfC, "cexpf");
        symbol(&cexplC, "cexpl");
        // log
        symbol(&clogC, "clog");
        symbol(&clogfC, "clogf");
        symbol(&cloglC, "clogl");
        // pow
        symbol(&cpowC, "cpow");
        symbol(&cpowfC, "cpowf");
        symbol(&cpowlC, "cpowl");
        // sqrt
        symbol(&csqrtC, "csqrt");
        symbol(&csqrtfC, "csqrtf");
        symbol(&csqrtlC, "csqrtl");
        // cos
        symbol(&ccosC, "ccos");
        symbol(&ccosfC, "ccosf");
        symbol(&ccoslC, "ccosl");
        // sin
        symbol(&csinC, "csin");
        symbol(&csinfC, "csinf");
        symbol(&csinlC, "csinl");
        // tan
        symbol(&ctanC, "ctan");
        symbol(&ctanfC, "ctanf");
        symbol(&ctanlC, "ctanl");
        // cosh
        symbol(&ccoshC, "ccosh");
        symbol(&ccoshfC, "ccoshf");
        symbol(&ccoshlC, "ccoshl");
        // sinh
        symbol(&csinhC, "csinh");
        symbol(&csinhfC, "csinhf");
        symbol(&csinhlC, "csinhl");
        // tanh
        symbol(&ctanhC, "ctanh");
        symbol(&ctanhfC, "ctanhf");
        symbol(&ctanhlC, "ctanhl");
        // acos
        symbol(&cacosC, "cacos");
        symbol(&cacosfC, "cacosf");
        symbol(&cacoslC, "cacosl");
        // asin
        symbol(&casinC, "casin");
        symbol(&casinfC, "casinf");
        symbol(&casinlC, "casinl");
        // atan
        symbol(&catanC, "catan");
        symbol(&catanfC, "catanf");
        symbol(&catanlC, "catanl");
        // acosh
        symbol(&cacoshC, "cacosh");
        symbol(&cacoshfC, "cacoshf");
        symbol(&cacoshlC, "cacoshl");
        // asinh
        symbol(&casinhC, "casinh");
        symbol(&casinhfC, "casinhf");
        symbol(&casinhlC, "casinhl");
        // atanh
        symbol(&catanhC, "catanh");
        symbol(&catanhfC, "catanhf");
        symbol(&catanhlC, "catanhl");
    }
    if (builtin.target.isMuslLibC()) {
        symbol(&crealC, "creal");
        symbol(&crealfC, "crealf");
        symbol(&creallC, "creall");
        symbol(&cimagC, "cimag");
        symbol(&cimagfC, "cimagf");
        symbol(&cimaglC, "cimagl");
    }
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&ldexp_cexpC, "__ldexp_cexp");
        symbol(&ldexp_cexpfC, "__ldexp_cexpf");
    }
}
