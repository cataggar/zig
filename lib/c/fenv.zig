const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

/// fexcept_t type matching musl's arch-specific bits/fenv.h definitions.
const fexcept_t = switch (builtin.cpu.arch) {
    .x86_64, .x86, .mips, .mipsel, .mips64, .mips64el => c_ushort,
    .aarch64, .aarch64_be, .riscv32, .riscv64, .loongarch64,
    .m68k, .powerpc, .powerpcle, .powerpc64, .powerpc64le, .s390x,
    => c_uint,
    else => c_ulong,
};

const FE_TONEAREST: c_int = 0;

const FE_ALL_EXCEPT: c_int = switch (builtin.cpu.arch) {
    .x86_64, .x86, .hexagon => 0x3f,
    .aarch64, .aarch64_be, .arm, .armeb, .thumb, .thumbeb,
    .riscv32, .riscv64,
    => 0x1f,
    .loongarch64 => 0x1f0000,
    .m68k => 0xf8,
    .mips, .mipsel, .mips64, .mips64el => 0x7c,
    .powerpc, .powerpcle, .powerpc64, .powerpc64le => 0x3e000000,
    .s390x => 0xf80000,
    else => 0,
};

const FE_TOWARDZERO: ?c_int = switch (builtin.cpu.arch) {
    .x86_64, .x86 => 0xc00,
    .aarch64, .aarch64_be, .arm, .armeb, .thumb, .thumbeb => @as(c_int, 0xc00000),
    .riscv32, .riscv64, .mips, .mipsel, .mips64, .mips64el,
    .powerpc, .powerpcle, .powerpc64, .powerpc64le, .s390x,
    => 1,
    .hexagon => 0x01,
    .loongarch64 => 0x100,
    .m68k => 16,
    else => null,
};

const FE_UPWARD: ?c_int = switch (builtin.cpu.arch) {
    .x86_64, .x86 => 0x800,
    .aarch64, .aarch64_be, .arm, .armeb, .thumb, .thumbeb => 0x400000,
    .riscv32, .riscv64 => 3,
    .mips, .mipsel, .mips64, .mips64el, .powerpc, .powerpcle,
    .powerpc64, .powerpc64le, .s390x,
    => 2,
    .hexagon => 0x03,
    .loongarch64 => 0x200,
    .m68k => 48,
    else => null,
};

const FE_DOWNWARD: ?c_int = switch (builtin.cpu.arch) {
    .x86_64, .x86 => 0x400,
    .aarch64, .aarch64_be, .arm, .armeb, .thumb, .thumbeb => @as(c_int, 0x800000),
    .riscv32, .riscv64 => 2,
    .mips, .mipsel, .mips64, .mips64el, .powerpc, .powerpcle,
    .powerpc64, .powerpc64le, .s390x,
    => 3,
    .hexagon => 0x02,
    .loongarch64 => 0x300,
    .m68k => 32,
    else => null,
};

comptime {
    if (builtin.link_libc) {
        // Weak generic fallbacks (from fenv.c).
        // Overridden by arch-specific implementations at link time.
        symbol(&feclearexcept, "feclearexcept");
        symbol(&feraiseexcept, "feraiseexcept");
        symbol(&fetestexcept, "fetestexcept");
        symbol(&fegetround, "fegetround");
        symbol(&__fesetround, "__fesetround");
        symbol(&fegetenv, "fegetenv");
        symbol(&fesetenv, "fesetenv");

        // Generic callers (no arch-specific overrides for these).
        symbol(&__flt_rounds, "__flt_rounds");
        symbol(&fegetexceptflag, "fegetexceptflag");
        symbol(&feholdexcept, "feholdexcept");
        symbol(&fesetexceptflag, "fesetexceptflag");
        symbol(&fesetround, "fesetround");
        symbol(&feupdateenv, "feupdateenv");
    }
}

// Weak generic fallbacks for archs without arch-specific fenv.
// On archs with FPU support, the arch-specific assembly provides
// strong definitions that override these at link time.

fn feclearexcept(mask: c_int) callconv(.c) c_int {
    _ = mask;
    return 0;
}

fn feraiseexcept(mask: c_int) callconv(.c) c_int {
    _ = mask;
    return 0;
}

fn fetestexcept(mask: c_int) callconv(.c) c_int {
    _ = mask;
    return 0;
}

fn fegetround() callconv(.c) c_int {
    return FE_TONEAREST;
}

fn __fesetround(r: c_int) callconv(.c) c_int {
    _ = r;
    return 0;
}

fn fegetenv(envp: *anyopaque) callconv(.c) c_int {
    _ = envp;
    return 0;
}

fn fesetenv(envp: *const anyopaque) callconv(.c) c_int {
    _ = envp;
    return 0;
}

// Generic callers: these call the fenv functions above (or their
// arch-specific overrides) and are always compiled for all architectures.

fn __flt_rounds() callconv(.c) c_int {
    const round = fegetround();
    if (FE_TOWARDZERO) |v| {
        if (round == v) return 0;
    }
    if (round == FE_TONEAREST) return 1;
    if (FE_UPWARD) |v| {
        if (round == v) return 2;
    }
    if (FE_DOWNWARD) |v| {
        if (round == v) return 3;
    }
    return -1;
}

fn fegetexceptflag(fp: *fexcept_t, mask: c_int) callconv(.c) c_int {
    fp.* = @intCast(@as(c_uint, @bitCast(fetestexcept(mask))));
    return 0;
}

fn feholdexcept(envp: *anyopaque) callconv(.c) c_int {
    _ = fegetenv(envp);
    _ = feclearexcept(FE_ALL_EXCEPT);
    return 0;
}

fn fesetexceptflag(fp: *const fexcept_t, mask: c_int) callconv(.c) c_int {
    const fp_int: c_int = @intCast(fp.*);
    _ = feclearexcept(~fp_int & mask);
    _ = feraiseexcept(fp_int & mask);
    return 0;
}

fn fesetround(r: c_int) callconv(.c) c_int {
    if (r == FE_TONEAREST) return __fesetround(r);
    if (FE_DOWNWARD) |v| {
        if (r == v) return __fesetround(r);
    }
    if (FE_UPWARD) |v| {
        if (r == v) return __fesetround(r);
    }
    if (FE_TOWARDZERO) |v| {
        if (r == v) return __fesetround(r);
    }
    return -1;
}

fn feupdateenv(envp: *const anyopaque) callconv(.c) c_int {
    const ex = fetestexcept(FE_ALL_EXCEPT);
    _ = fesetenv(envp);
    _ = feraiseexcept(ex);
    return 0;
}
