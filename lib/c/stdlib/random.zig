/// BSD random() — lagged Fibonacci generator.
/// Ported from musl libc src/prng/random.c
const builtin = @import("builtin");
const symbol = @import("../../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&srandom, "srandom");
        symbol(&initstate, "initstate");
        symbol(&setstate, "setstate");
        symbol(&random, "random");
    }
}

var init_data = [_]u32{
    0x00000000, 0x5851f42d, 0xc0b18ccf, 0xcbb5f646,
    0xc7033129, 0x30705b04, 0x20fd5db4, 0x9a8b7f78,
    0x502959d8, 0xab894868, 0x6c0356a7, 0x88cdb7ff,
    0xb477d43f, 0x70a3a52b, 0xa8e4baf1, 0xfd8341fc,
    0x8ae16fd9, 0x742d2f7a, 0x0d1f0796, 0x76035e09,
    0x40f7702c, 0x6fa72ca5, 0xaaa84157, 0x58a0df74,
    0xc74a0364, 0xae533cc4, 0x04185faf, 0x6de3b115,
    0x0cab8628, 0xf043bfa4, 0x398150e9, 0x37521657,
};

// State: x_base[0] holds metadata (n<<16 | fi<<8 | fj), x_base[1..n+1] holds the generator state.
var n: usize = 31;
var fi: usize = 3;
var fj: usize = 0;
var x_base: [*]u32 = &init_data;

fn lcg31(x: u32) u32 {
    return (1103515245 *% x +% 12345) & 0x7fffffff;
}

fn lcg64(x: u64) u64 {
    return 6364136223846793005 *% x +% 1;
}

fn savestate() [*]u32 {
    x_base[0] = @intCast(n << 16 | fi << 8 | fj);
    return x_base;
}

fn loadstate(state: [*]u32) void {
    x_base = state;
    n = state[0] >> 16;
    fi = (state[0] >> 8) & 0xff;
    fj = state[0] & 0xff;
}

fn doSrandom(seed: c_uint) void {
    var s: u64 = seed;
    if (n == 0) {
        x_base[1] = @truncate(s);
        return;
    }
    fi = if (n == 31 or n == 7) 3 else 1;
    fj = 0;
    for (0..n) |k| {
        s = lcg64(s);
        x_base[k + 1] = @truncate(s >> 32);
    }
    x_base[1] |= 1;
}

fn srandom(seed: c_uint) callconv(.c) void {
    doSrandom(seed);
}

fn initstate(seed: c_uint, state_buf: [*]u8, size: usize) callconv(.c) ?[*]u8 {
    if (size < 8) return null;
    const old: [*]u8 = @ptrCast(savestate());
    if (size < 32) {
        n = 0;
    } else if (size < 64) {
        n = 7;
    } else if (size < 128) {
        n = 15;
    } else if (size < 256) {
        n = 31;
    } else {
        n = 63;
    }
    x_base = @ptrCast(@alignCast(state_buf));
    doSrandom(seed);
    _ = savestate();
    return old;
}

fn setstate(new_state: [*]u8) callconv(.c) ?[*]u8 {
    const old: [*]u8 = @ptrCast(savestate());
    loadstate(@ptrCast(@alignCast(new_state)));
    return old;
}

fn random() callconv(.c) c_long {
    if (n == 0) {
        const k = lcg31(x_base[1]);
        x_base[1] = k;
        return @intCast(k);
    }
    x_base[fi + 1] +%= x_base[fj + 1];
    const k = x_base[fi + 1] >> 1;
    fi += 1;
    if (fi == n) fi = 0;
    fj += 1;
    if (fj == n) fj = 0;
    return @intCast(k);
}
