const std = @import("std");
const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

const arch = builtin.cpu.arch;

const is_x86 = arch == .x86;
const is_x86_64 = arch == .x86_64;
const is_x86_family = is_x86 or is_x86_64;
const is_aarch64 = arch == .aarch64 or arch == .aarch64_be;
const is_arm = arch == .arm or arch == .armeb or arch == .thumb or arch == .thumbeb;
const is_riscv = arch == .riscv32 or arch == .riscv64;
const is_mips = arch == .mips or arch == .mipsel or arch == .mips64 or arch == .mips64el;
const is_powerpc = arch == .powerpc or arch == .powerpcle or arch == .powerpc64 or arch == .powerpc64le;
const is_loongarch = arch == .loongarch64;
const is_hexagon = arch == .hexagon;

const is_arm_hard_float = switch (builtin.abi) {
    .eabihf, .gnueabihf, .musleabihf => is_arm,
    else => false,
};

const riscv_has_f = is_riscv and std.Target.riscv.featureSetHas(builtin.cpu.features, .f);
const loongarch_has_f = is_loongarch and builtin.abi != .muslsf and
    std.Target.loongarch.featureSetHas(builtin.cpu.features, .f);
const mips_soft_float = is_mips and std.Target.mips.featureSetHas(builtin.cpu.features, .soft_float);
const mips_hard_float = is_mips and !mips_soft_float;

const m68k_hard_float = arch == .m68k and
    std.Target.m68k.featureSetHasAny(builtin.cpu.features, .{ .isa_68881, .isa_68882 });

const powerpc_soft_float = switch (builtin.abi) {
    .eabi, .gnueabi, .musleabi => arch == .powerpc or arch == .powerpcle,
    else => false,
};
const powerpc_hard_float = is_powerpc and !powerpc_soft_float;

const fexcept_t = switch (arch) {
    .x86_64, .x86, .mips, .mipsel, .mips64, .mips64el => c_ushort,
    .aarch64,
    .aarch64_be,
    .riscv32,
    .riscv64,
    .loongarch64,
    .m68k,
    .powerpc,
    .powerpcle,
    .powerpc64,
    .powerpc64le,
    .s390x,
    => c_uint,
    else => c_ulong,
};

const FE_TONEAREST: c_int = 0;

const FE_ALL_EXCEPT: c_int = switch (arch) {
    .x86_64, .x86, .hexagon => 0x3f,
    .aarch64, .aarch64_be => 0x1f,
    .arm, .armeb, .thumb, .thumbeb => if (is_arm_hard_float) 0x1f else 0,
    .riscv32, .riscv64 => 0x1f,
    .loongarch64 => 0x1f0000,
    .m68k => if (m68k_hard_float) 0xf8 else 0,
    .mips, .mipsel, .mips64, .mips64el => if (mips_hard_float) 0x7c else 0,
    .powerpc, .powerpcle, .powerpc64, .powerpc64le => if (powerpc_hard_float) 0x3e000000 else 0,
    .s390x => 0xf80000,
    else => 0,
};

const FE_TOWARDZERO: ?c_int = switch (arch) {
    .x86_64, .x86 => 0xc00,
    .aarch64, .aarch64_be => 0xc00000,
    .arm, .armeb, .thumb, .thumbeb => if (is_arm_hard_float) 0xc00000 else null,
    .riscv32, .riscv64 => 1,
    .mips, .mipsel, .mips64, .mips64el => if (mips_hard_float) 1 else null,
    .powerpc, .powerpcle, .powerpc64, .powerpc64le => if (powerpc_hard_float) 1 else null,
    .s390x => 1,
    .hexagon => 0x01,
    .loongarch64 => 0x100,
    .m68k => if (m68k_hard_float) 16 else null,
    else => null,
};

const FE_UPWARD: ?c_int = switch (arch) {
    .x86_64, .x86 => 0x800,
    .aarch64, .aarch64_be => 0x400000,
    .arm, .armeb, .thumb, .thumbeb => if (is_arm_hard_float) 0x400000 else null,
    .riscv32, .riscv64 => 3,
    .mips, .mipsel, .mips64, .mips64el => if (mips_hard_float) 2 else null,
    .powerpc, .powerpcle, .powerpc64, .powerpc64le => if (powerpc_hard_float) 2 else null,
    .s390x => 2,
    .hexagon => 0x03,
    .loongarch64 => 0x200,
    .m68k => if (m68k_hard_float) 48 else null,
    else => null,
};

const FE_DOWNWARD: ?c_int = switch (arch) {
    .x86_64, .x86 => 0x400,
    .aarch64, .aarch64_be => 0x800000,
    .arm, .armeb, .thumb, .thumbeb => if (is_arm_hard_float) 0x800000 else null,
    .riscv32, .riscv64 => 2,
    .mips, .mipsel, .mips64, .mips64el => if (mips_hard_float) 3 else null,
    .powerpc, .powerpcle, .powerpc64, .powerpc64le => if (powerpc_hard_float) 3 else null,
    .s390x => 3,
    .hexagon => 0x02,
    .loongarch64 => 0x300,
    .m68k => if (m68k_hard_float) 32 else null,
    else => null,
};

const FE_DFL_ENV = @as(usize, std.math.maxInt(usize));

const X87Env = extern struct { bytes: [28]u8 };
const X86SseEnv = extern struct {
    x87: X87Env,
    mxcsr: c_uint,
};
const X86Mode = extern struct {
    control_word: c_ushort,
    reserved: c_ushort,
    mxcsr: c_uint,
};
const Aarch64Env = extern struct {
    fpcr: c_uint,
    fpsr: c_uint,
};
const ArmEnv = extern struct { cw: c_ulong };
const M68kEnv = extern struct {
    control_register: c_uint,
    status_register: c_uint,
    instruction_address: c_uint,
};

comptime {
    if (builtin.link_libc) {
        if (!is_x86_family) {
            symbol(&feclearexcept, "feclearexcept");
            symbol(&feraiseexcept, "feraiseexcept");
            symbol(&fetestexcept, "fetestexcept");
            symbol(&fegetround, "fegetround");
            symbol(&__fesetround, "__fesetround");
            symbol(&fegetenv, "fegetenv");
            symbol(&fesetenv, "fesetenv");
        }
        symbol(&__flt_rounds, "__flt_rounds");
        symbol(&fegetexceptflag, "fegetexceptflag");
        symbol(&feholdexcept, "feholdexcept");
        symbol(&fesetexceptflag, "fesetexceptflag");
        symbol(&fesetround, "fesetround");
        symbol(&feupdateenv, "feupdateenv");
        symbol(&fegetmode, "fegetmode");
        symbol(&fesetmode, "fesetmode");
    }
}

fn defaultX87Env() X87Env {
    var env: X87Env = std.mem.zeroes(X87Env);
    env.bytes[0] = 0x7f;
    env.bytes[1] = 0x03;
    env.bytes[8] = 0xff;
    env.bytes[9] = 0xff;
    return env;
}

fn x86Fnstsw() u16 {
    var sw: u16 = undefined;
    if (comptime is_x86_64) {
        asm volatile ("fnstsw (%%rax)"
            :
            : [sw] "{rax}" (&sw),
            : .{ .memory = true });
    } else {
        asm volatile ("fnstsw (%%eax)"
            :
            : [sw] "{eax}" (&sw),
            : .{ .memory = true });
    }
    return sw;
}

fn x86Fnclex() void {
    asm volatile ("fnclex");
}

fn x86Fnstcw() u16 {
    var cw: u16 = undefined;
    if (comptime is_x86_64) {
        asm volatile ("fnstcw (%%rax)"
            :
            : [cw] "{rax}" (&cw),
            : .{ .memory = true });
    } else {
        asm volatile ("fnstcw (%%eax)"
            :
            : [cw] "{eax}" (&cw),
            : .{ .memory = true });
    }
    return cw;
}

fn x86Fldcw(cw: u16) void {
    const tmp = cw;
    if (comptime is_x86_64) {
        asm volatile ("fldcw (%%rax)"
            :
            : [cw] "{rax}" (&tmp),
            : .{ .memory = true });
    } else {
        asm volatile ("fldcw (%%eax)"
            :
            : [cw] "{eax}" (&tmp),
            : .{ .memory = true });
    }
}

fn x86FnstenvTo(env: *X87Env) void {
    if (comptime is_x86_64) {
        asm volatile ("fnstenv (%%rax)"
            :
            : [env] "{rax}" (env),
            : .{ .memory = true });
    } else {
        asm volatile ("fnstenv (%%eax)"
            :
            : [env] "{eax}" (env),
            : .{ .memory = true });
    }
}

fn x86FldenvFrom(env: *const X87Env) void {
    if (comptime is_x86_64) {
        asm volatile ("fldenv (%%rax)"
            :
            : [env] "{rax}" (env),
            : .{ .memory = true });
    } else {
        asm volatile ("fldenv (%%eax)"
            :
            : [env] "{eax}" (env),
            : .{ .memory = true });
    }
}

fn x86Stmxcsr() u32 {
    var mxcsr: u32 = undefined;
    if (comptime is_x86_64) {
        asm volatile ("stmxcsr (%%rax)"
            :
            : [mxcsr] "{rax}" (&mxcsr),
            : .{ .memory = true });
    } else {
        asm volatile ("stmxcsr (%%eax)"
            :
            : [mxcsr] "{eax}" (&mxcsr),
            : .{ .memory = true });
    }
    return mxcsr;
}

fn x86Ldmxcsr(mxcsr: u32) void {
    const tmp = mxcsr;
    if (comptime is_x86_64) {
        asm volatile ("ldmxcsr (%%rax)"
            :
            : [mxcsr] "{rax}" (&tmp),
            : .{ .memory = true });
    } else {
        asm volatile ("ldmxcsr (%%eax)"
            :
            : [mxcsr] "{eax}" (&tmp),
            : .{ .memory = true });
    }
}

extern var __hwcap: usize;

fn x86HasSse() bool {
    if (comptime is_x86_64) return true;
    return (__hwcap & 0x02000000) != 0;
}

fn x86Feclearexcept(mask_arg: c_int) c_int {
    const mask = @as(u32, @bitCast(mask_arg)) & 0x3f;
    const sw = x86Fnstsw();
    if (x86HasSse()) {
        if ((@as(u32, sw) & mask) != 0) x86Fnclex();
        var mxcsr = x86Stmxcsr();
        mxcsr |= @as(u32, sw) & 0x3f;
        if ((mxcsr & mask) != 0) {
            mxcsr &= ~mask;
            x86Ldmxcsr(mxcsr);
        }
    } else if ((@as(u32, sw) & mask) != 0) {
        const new_sw = @as(u32, sw) & ~mask;
        if ((new_sw & 0x3f) == 0) {
            x86Fnclex();
        } else {
            var env: X87Env = undefined;
            x86FnstenvTo(&env);
            env.bytes[4] = @truncate(new_sw);
            x86FldenvFrom(&env);
        }
    }
    return 0;
}

fn x86Feraiseexcept(mask_arg: c_int) c_int {
    const mask = @as(u32, @bitCast(mask_arg)) & 0x3f;
    if (comptime is_x86_64) {
        x86Ldmxcsr(x86Stmxcsr() | mask);
    } else {
        var env: X87Env = undefined;
        x86FnstenvTo(&env);
        env.bytes[4] |= @truncate(mask);
        x86FldenvFrom(&env);
    }
    return 0;
}

fn x86Fetestexcept(mask_arg: c_int) c_int {
    const mask = @as(u32, @bitCast(mask_arg)) & 0x3f;
    var flags = @as(u32, x86Fnstsw());
    if (x86HasSse()) flags |= x86Stmxcsr();
    return @intCast(flags & mask);
}

fn x86Fegetround() c_int {
    if (comptime is_x86_64) return @intCast((x86Stmxcsr() >> 3) & 0xc00);
    return @intCast(x86Fnstcw() & 0xc00);
}

fn x86Fesetround(r_arg: c_int) c_int {
    const r = @as(u32, @bitCast(r_arg)) & 0xc00;
    x86Fldcw((x86Fnstcw() & ~@as(u16, 0xc00)) | @as(u16, @intCast(r)));
    if (x86HasSse()) {
        var mxcsr = x86Stmxcsr();
        mxcsr &= ~@as(u32, 0x6000);
        mxcsr |= r << 3;
        x86Ldmxcsr(mxcsr);
    }
    return 0;
}

fn x86Fegetenv(envp: *anyopaque) c_int {
    if (comptime is_x86_64) {
        const envp_typed: *X86SseEnv = @ptrCast(@alignCast(envp));
        x86FnstenvTo(&envp_typed.x87);
        envp_typed.mxcsr = x86Stmxcsr();
    } else {
        const envp_typed: *X87Env = @ptrCast(@alignCast(envp));
        x86FnstenvTo(envp_typed);
        if (x86HasSse()) envp_typed.bytes[4] |= @truncate(x86Stmxcsr() & 0x3f);
    }
    return 0;
}

fn x86Fesetenv(envp: *const anyopaque) c_int {
    if (comptime is_x86_64) {
        if (@intFromPtr(envp) == FE_DFL_ENV) {
            var env = X86SseEnv{ .x87 = defaultX87Env(), .mxcsr = 0x1f80 };
            x86FldenvFrom(&env.x87);
            x86Ldmxcsr(env.mxcsr);
        } else {
            const env: *const X86SseEnv = @ptrCast(@alignCast(envp));
            x86FldenvFrom(&env.x87);
            x86Ldmxcsr(env.mxcsr);
        }
    } else {
        var default_env: X87Env = undefined;
        const env: *const X87Env = if (@intFromPtr(envp) == FE_DFL_ENV) blk: {
            default_env = defaultX87Env();
            break :blk &default_env;
        } else @ptrCast(@alignCast(envp));
        x86FldenvFrom(env);
        if (x86HasSse()) {
            const cw = if (@intFromPtr(envp) == FE_DFL_ENV)
                @as(u32, 0)
            else
                @as(u32, env.bytes[0]) | (@as(u32, env.bytes[1]) << 8);
            const mxcsr = ((cw & 0xc00) << 3) | 0x1f80;
            x86Ldmxcsr(mxcsr);
        }
    }
    return 0;
}

fn aarch64GetFpcr() u64 {
    return asm volatile ("mrs %[fpcr], fpcr"
        : [fpcr] "=r" (-> u64),
    );
}

fn aarch64SetFpcr(fpcr: u64) void {
    asm volatile ("msr fpcr, %[fpcr]"
        :
        : [fpcr] "r" (fpcr),
    );
}

fn aarch64GetFpsr() u64 {
    return asm volatile ("mrs %[fpsr], fpsr"
        : [fpsr] "=r" (-> u64),
    );
}

fn aarch64SetFpsr(fpsr: u64) void {
    asm volatile ("msr fpsr, %[fpsr]"
        :
        : [fpsr] "r" (fpsr),
    );
}

fn aarch64Feclearexcept(mask_arg: c_int) c_int {
    const mask = @as(u64, @as(c_uint, @bitCast(mask_arg)) & 0x1f);
    aarch64SetFpsr(aarch64GetFpsr() & ~mask);
    return 0;
}

fn aarch64Feraiseexcept(mask_arg: c_int) c_int {
    const mask = @as(u64, @as(c_uint, @bitCast(mask_arg)) & 0x1f);
    aarch64SetFpsr(aarch64GetFpsr() | mask);
    return 0;
}

fn aarch64Fetestexcept(mask_arg: c_int) c_int {
    const mask = @as(u64, @as(c_uint, @bitCast(mask_arg)) & 0x1f);
    return @intCast(aarch64GetFpsr() & mask);
}

fn aarch64Fegetround() c_int {
    return @intCast(aarch64GetFpcr() & 0xc00000);
}

fn aarch64Fesetround(r_arg: c_int) c_int {
    const r = @as(u64, @as(c_uint, @bitCast(r_arg)) & 0xc00000);
    aarch64SetFpcr((aarch64GetFpcr() & ~@as(u64, 0xc00000)) | r);
    return 0;
}

fn aarch64Fegetenv(envp: *Aarch64Env) c_int {
    envp.fpcr = @truncate(aarch64GetFpcr());
    envp.fpsr = @truncate(aarch64GetFpsr());
    return 0;
}

fn aarch64Fesetenv(envp_arg: *const Aarch64Env) c_int {
    const env = if (@intFromPtr(envp_arg) == FE_DFL_ENV)
        Aarch64Env{ .fpcr = 0, .fpsr = 0 }
    else
        envp_arg.*;
    aarch64SetFpcr(env.fpcr);
    aarch64SetFpsr(env.fpsr);
    return 0;
}

fn armGetFpscr() c_uint {
    return asm volatile ("vmrs %[fpscr], fpscr"
        : [fpscr] "=r" (-> c_uint),
    );
}

fn armSetFpscr(fpscr: c_uint) void {
    asm volatile ("vmsr fpscr, %[fpscr]"
        :
        : [fpscr] "r" (fpscr),
    );
}

fn armFeclearexcept(mask_arg: c_int) c_int {
    const mask = @as(c_uint, @bitCast(mask_arg)) & 0x1f;
    armSetFpscr(armGetFpscr() & ~mask);
    return 0;
}

fn armFeraiseexcept(mask_arg: c_int) c_int {
    const mask = @as(c_uint, @bitCast(mask_arg)) & 0x1f;
    armSetFpscr(armGetFpscr() | mask);
    return 0;
}

fn armFetestexcept(mask_arg: c_int) c_int {
    const mask = @as(c_uint, @bitCast(mask_arg)) & 0x1f;
    return @intCast(armGetFpscr() & mask);
}

fn armFegetround() c_int {
    return @intCast(armGetFpscr() & 0xc00000);
}

fn armFesetround(r_arg: c_int) c_int {
    const r = @as(c_uint, @bitCast(r_arg)) & 0xc00000;
    armSetFpscr((armGetFpscr() & ~@as(c_uint, 0xc00000)) | r);
    return 0;
}

fn armFegetenv(envp: *ArmEnv) c_int {
    envp.cw = armGetFpscr();
    return 0;
}

fn armFesetenv(envp_arg: *const ArmEnv) c_int {
    armSetFpscr(if (@intFromPtr(envp_arg) == FE_DFL_ENV) 0 else @intCast(envp_arg.cw));
    return 0;
}

fn riscvFrflags() c_uint {
    return asm volatile ("frflags %[flags]"
        : [flags] "=r" (-> c_uint),
    );
}

fn riscvFsflags(flags: c_uint) void {
    asm volatile ("fsflags %[flags]"
        :
        : [flags] "r" (flags),
    );
}

fn riscvFrrm() c_uint {
    return asm volatile ("frrm %[round]"
        : [round] "=r" (-> c_uint),
    );
}

fn riscvFsrm(round: c_uint) void {
    asm volatile ("fsrm %[round]"
        :
        : [round] "r" (round),
    );
}

fn riscvFrcsr() c_uint {
    return asm volatile ("frcsr %[csr]"
        : [csr] "=r" (-> c_uint),
    );
}

fn riscvFscsr(csr: c_uint) void {
    asm volatile ("fscsr %[csr]"
        :
        : [csr] "r" (csr),
    );
}

fn riscvFeclearexcept(mask_arg: c_int) c_int {
    riscvFsflags(riscvFrflags() & ~(@as(c_uint, @bitCast(mask_arg)) & 0x1f));
    return 0;
}

fn riscvFeraiseexcept(mask_arg: c_int) c_int {
    riscvFsflags(riscvFrflags() | (@as(c_uint, @bitCast(mask_arg)) & 0x1f));
    return 0;
}

fn riscvFetestexcept(mask_arg: c_int) c_int {
    return @intCast(riscvFrflags() & (@as(c_uint, @bitCast(mask_arg)) & 0x1f));
}

fn riscvFegetround() c_int {
    return @intCast(riscvFrrm());
}

fn riscvFesetround(r_arg: c_int) c_int {
    riscvFsrm(@as(c_uint, @bitCast(r_arg)) & 0x7);
    return 0;
}

fn riscvFegetenv(envp: *c_uint) c_int {
    envp.* = riscvFrcsr();
    return 0;
}

fn riscvFesetenv(envp: *const c_uint) c_int {
    riscvFscsr(if (@intFromPtr(envp) == FE_DFL_ENV) 0 else envp.*);
    return 0;
}

fn mipsGetFcsr() c_uint {
    return asm volatile ("cfc1 %[fcsr], $31"
        : [fcsr] "=r" (-> c_uint),
    );
}

fn mipsSetFcsr(fcsr: c_uint) void {
    asm volatile ("ctc1 %[fcsr], $31"
        :
        : [fcsr] "r" (fcsr),
    );
}

fn mipsFeclearexcept(mask_arg: c_int) c_int {
    const mask = @as(c_uint, @bitCast(mask_arg)) & 0x7c;
    mipsSetFcsr(mipsGetFcsr() & ~mask);
    return 0;
}

fn mipsFeraiseexcept(mask_arg: c_int) c_int {
    const mask = @as(c_uint, @bitCast(mask_arg)) & 0x7c;
    mipsSetFcsr(mipsGetFcsr() | mask);
    return 0;
}

fn mipsFetestexcept(mask_arg: c_int) c_int {
    const mask = @as(c_uint, @bitCast(mask_arg)) & 0x7c;
    return @intCast(mipsGetFcsr() & mask);
}

fn mipsFegetround() c_int {
    return @intCast(mipsGetFcsr() & 3);
}

fn mipsFesetround(r_arg: c_int) c_int {
    const r = @as(c_uint, @bitCast(r_arg)) & 3;
    mipsSetFcsr((mipsGetFcsr() & ~@as(c_uint, 3)) | r);
    return 0;
}

fn mipsFegetenv(envp: *c_uint) c_int {
    envp.* = mipsGetFcsr();
    return 0;
}

fn mipsFesetenv(envp: *const c_uint) c_int {
    mipsSetFcsr(if (@intFromPtr(envp) == FE_DFL_ENV) 0 else envp.*);
    return 0;
}

fn loongarchGetFcsr() c_uint {
    return asm volatile ("movfcsr2gr %[fcsr], $fcsr0"
        : [fcsr] "=r" (-> c_uint),
    );
}

fn loongarchSetFcsr(fcsr: c_uint) void {
    asm volatile ("movgr2fcsr $fcsr0, %[fcsr]"
        :
        : [fcsr] "r" (fcsr),
    );
}

fn loongarchFeclearexcept(mask_arg: c_int) c_int {
    const mask = @as(c_uint, @bitCast(mask_arg)) & 0x1f0000;
    loongarchSetFcsr(loongarchGetFcsr() & ~mask);
    return 0;
}

fn loongarchFeraiseexcept(mask_arg: c_int) c_int {
    const mask = @as(c_uint, @bitCast(mask_arg)) & 0x1f0000;
    loongarchSetFcsr(loongarchGetFcsr() | mask);
    return 0;
}

fn loongarchFetestexcept(mask_arg: c_int) c_int {
    const mask = @as(c_uint, @bitCast(mask_arg)) & 0x1f0000;
    return @intCast(loongarchGetFcsr() & mask);
}

fn loongarchFegetround() c_int {
    return @intCast(loongarchGetFcsr() & 0x300);
}

fn loongarchFesetround(r_arg: c_int) c_int {
    const r = @as(c_uint, @bitCast(r_arg)) & 0x300;
    loongarchSetFcsr((loongarchGetFcsr() & ~@as(c_uint, 0x300)) | r);
    return 0;
}

fn loongarchFegetenv(envp: *c_uint) c_int {
    envp.* = loongarchGetFcsr();
    return 0;
}

fn loongarchFesetenv(envp: *const c_uint) c_int {
    loongarchSetFcsr(if (@intFromPtr(envp) == FE_DFL_ENV) 0 else envp.*);
    return 0;
}

fn s390xGetFpc() c_uint {
    return asm volatile ("efpc %[fpc]"
        : [fpc] "=r" (-> c_uint),
    );
}

fn s390xSetFpc(fpc: c_uint) void {
    asm volatile ("sfpc %[fpc]"
        :
        : [fpc] "r" (fpc),
    );
}

fn s390xFeclearexcept(mask_arg: c_int) c_int {
    const mask = @as(c_uint, @bitCast(mask_arg)) & 0xf80000;
    s390xSetFpc(s390xGetFpc() & ~mask);
    return 0;
}

fn s390xFeraiseexcept(mask_arg: c_int) c_int {
    const mask = @as(c_uint, @bitCast(mask_arg)) & 0xf80000;
    s390xSetFpc(s390xGetFpc() | mask);
    return 0;
}

fn s390xFetestexcept(mask_arg: c_int) c_int {
    const mask = @as(c_uint, @bitCast(mask_arg)) & 0xf80000;
    return @intCast(s390xGetFpc() & mask);
}

fn s390xFegetround() c_int {
    return @intCast(s390xGetFpc() & 3);
}

fn s390xFesetround(r_arg: c_int) c_int {
    const r = @as(c_uint, @bitCast(r_arg)) & 3;
    s390xSetFpc((s390xGetFpc() & ~@as(c_uint, 3)) | r);
    return 0;
}

fn s390xFegetenv(envp: *c_uint) c_int {
    envp.* = s390xGetFpc();
    return 0;
}

fn s390xFesetenv(envp: *const c_uint) c_int {
    s390xSetFpc(if (@intFromPtr(envp) == FE_DFL_ENV) 0 else envp.*);
    return 0;
}

const POWERPC_FE_INVALID: u64 = 0x20000000;
const POWERPC_FE_ALL_INVALID: u64 = 0x01f80700;
const POWERPC_FE_INVALID_SOFTWARE: u64 = 0x00000400;

fn powerpcGetFpscrF() f64 {
    var fpscr: f64 = undefined;
    asm volatile ("mffs %[fpscr]"
        : [fpscr] "=d" (fpscr),
    );
    return fpscr;
}

fn powerpcSetFpscrF(fpscr: f64) void {
    asm volatile ("mtfsf 255, %[fpscr]"
        :
        : [fpscr] "d" (fpscr),
    );
}

fn powerpcGetFpscr() u64 {
    return @bitCast(powerpcGetFpscrF());
}

fn powerpcSetFpscr(fpscr: u64) void {
    powerpcSetFpscrF(@bitCast(fpscr));
}

fn powerpcFeclearexcept(mask_arg: c_int) c_int {
    var mask = @as(u64, @as(c_uint, @bitCast(mask_arg))) & 0x3e000000;
    if (mask & POWERPC_FE_INVALID != 0) mask |= POWERPC_FE_ALL_INVALID;
    powerpcSetFpscr(powerpcGetFpscr() & ~mask);
    return 0;
}

fn powerpcFeraiseexcept(mask_arg: c_int) c_int {
    var mask = @as(u64, @as(c_uint, @bitCast(mask_arg))) & 0x3e000000;
    if (mask & POWERPC_FE_INVALID != 0) mask |= POWERPC_FE_INVALID_SOFTWARE;
    powerpcSetFpscr(powerpcGetFpscr() | mask);
    return 0;
}

fn powerpcFetestexcept(mask_arg: c_int) c_int {
    const mask = @as(u64, @as(c_uint, @bitCast(mask_arg))) & 0x3e000000;
    return @intCast(powerpcGetFpscr() & mask);
}

fn powerpcFegetround() c_int {
    return @intCast(powerpcGetFpscr() & 3);
}

fn powerpcFesetround(r_arg: c_int) c_int {
    const r = @as(u64, @as(c_uint, @bitCast(r_arg)) & 3);
    powerpcSetFpscr((powerpcGetFpscr() & ~@as(u64, 3)) | r);
    return 0;
}

fn powerpcFegetenv(envp: *f64) c_int {
    envp.* = powerpcGetFpscrF();
    return 0;
}

fn powerpcFesetenv(envp: *const f64) c_int {
    powerpcSetFpscrF(if (@intFromPtr(envp) == FE_DFL_ENV) 0 else envp.*);
    return 0;
}

fn m68kGetsr() c_uint {
    return asm volatile ("fmove.l %%fpsr,%[sr]"
        : [sr] "=dm" (-> c_uint),
    );
}

fn m68kSetsr(v: c_uint) void {
    asm volatile ("fmove.l %[sr],%%fpsr"
        :
        : [sr] "dm" (v),
    );
}

fn m68kGetcr() c_uint {
    return asm volatile ("fmove.l %%fpcr,%[cr]"
        : [cr] "=dm" (-> c_uint),
    );
}

fn m68kSetcr(v: c_uint) void {
    asm volatile ("fmove.l %[cr],%%fpcr"
        :
        : [cr] "dm" (v),
    );
}

fn m68kGetpiar() c_uint {
    return asm volatile ("fmove.l %%fpiar,%[piar]"
        : [piar] "=dm" (-> c_uint),
    );
}

fn m68kSetpiar(v: c_uint) void {
    asm volatile ("fmove.l %[piar],%%fpiar"
        :
        : [piar] "dm" (v),
    );
}

fn m68kFeclearexcept(mask_arg: c_int) c_int {
    if (mask_arg & ~FE_ALL_EXCEPT != 0) return -1;
    m68kSetsr(m68kGetsr() & ~@as(c_uint, @bitCast(mask_arg)));
    return 0;
}

fn m68kFeraiseexcept(mask_arg: c_int) c_int {
    if (mask_arg & ~FE_ALL_EXCEPT != 0) return -1;
    m68kSetsr(m68kGetsr() | @as(c_uint, @bitCast(mask_arg)));
    return 0;
}

fn m68kFetestexcept(mask_arg: c_int) c_int {
    return @intCast(m68kGetsr() & @as(c_uint, @bitCast(mask_arg)));
}

fn m68kFegetround() c_int {
    return @intCast(m68kGetcr() & @as(c_uint, @intCast(FE_UPWARD.?)));
}

fn m68kFesetround(r_arg: c_int) c_int {
    const round_mask: c_uint = @intCast(FE_UPWARD.?);
    m68kSetcr((m68kGetcr() & ~round_mask) | @as(c_uint, @bitCast(r_arg)));
    return 0;
}

fn m68kFegetenv(envp: *M68kEnv) c_int {
    envp.control_register = m68kGetcr();
    envp.status_register = m68kGetsr();
    envp.instruction_address = m68kGetpiar();
    return 0;
}

fn m68kFesetenv(envp_arg: *const M68kEnv) c_int {
    const env = if (@intFromPtr(envp_arg) == FE_DFL_ENV)
        M68kEnv{ .control_register = 0, .status_register = 0, .instruction_address = 0 }
    else
        envp_arg.*;
    m68kSetcr(env.control_register);
    m68kSetsr(env.status_register);
    m68kSetpiar(env.instruction_address);
    return 0;
}

const HEXAGON_USR_FE_MASK: c_uint = 0x3fc0003f;
const HEXAGON_RND_MASK: c_uint = 0x00c00000;

fn hexagonGetUsr() c_uint {
    return asm volatile ("%[usr] = usr"
        : [usr] "=r" (-> c_uint),
    );
}

fn hexagonSetUsr(usr: c_uint) void {
    asm volatile ("usr = %[usr]"
        :
        : [usr] "r" (usr),
    );
}

fn hexagonFeclearexcept(mask_arg: c_int) c_int {
    const mask = @as(c_uint, @bitCast(mask_arg)) & 0x3f;
    hexagonSetUsr(hexagonGetUsr() & ~mask);
    return 0;
}

fn hexagonFeraiseexcept(mask_arg: c_int) c_int {
    const mask = @as(c_uint, @bitCast(mask_arg)) & 0x3f;
    hexagonSetUsr(hexagonGetUsr() | mask);
    return 0;
}

fn hexagonFetestexcept(mask_arg: c_int) c_int {
    const mask = @as(c_uint, @bitCast(mask_arg)) & 0x3f;
    return @intCast(hexagonGetUsr() & mask);
}

fn hexagonFegetround() c_int {
    return @intCast((hexagonGetUsr() & HEXAGON_RND_MASK) >> 22);
}

fn hexagonFesetround(r_arg: c_int) c_int {
    const r = (@as(c_uint, @bitCast(r_arg)) & 3) << 22;
    hexagonSetUsr((hexagonGetUsr() & ~HEXAGON_RND_MASK) | r);
    return 0;
}

fn hexagonFegetenv(envp: *c_uint) c_int {
    envp.* = hexagonGetUsr();
    return 0;
}

fn hexagonFesetenv(envp: *const c_uint) c_int {
    const new_bits = (if (@intFromPtr(envp) == FE_DFL_ENV) 0 else envp.*) & HEXAGON_USR_FE_MASK;
    hexagonSetUsr((hexagonGetUsr() & ~HEXAGON_USR_FE_MASK) | new_bits);
    return 0;
}

fn feclearexcept(mask: c_int) callconv(.c) c_int {
    if (comptime is_x86_family) return x86Feclearexcept(mask);
    if (comptime is_aarch64) return aarch64Feclearexcept(mask);
    if (comptime is_arm_hard_float) return armFeclearexcept(mask);
    if (comptime riscv_has_f) return riscvFeclearexcept(mask);
    if (comptime mips_hard_float) return mipsFeclearexcept(mask);
    if (comptime loongarch_has_f) return loongarchFeclearexcept(mask);
    if (comptime arch == .s390x) return s390xFeclearexcept(mask);
    if (comptime powerpc_hard_float) return powerpcFeclearexcept(mask);
    if (comptime m68k_hard_float) return m68kFeclearexcept(mask);
    if (comptime is_hexagon) return hexagonFeclearexcept(mask);
    return 0;
}

fn feraiseexcept(mask: c_int) callconv(.c) c_int {
    if (comptime is_x86_family) return x86Feraiseexcept(mask);
    if (comptime is_aarch64) return aarch64Feraiseexcept(mask);
    if (comptime is_arm_hard_float) return armFeraiseexcept(mask);
    if (comptime riscv_has_f) return riscvFeraiseexcept(mask);
    if (comptime mips_hard_float) return mipsFeraiseexcept(mask);
    if (comptime loongarch_has_f) return loongarchFeraiseexcept(mask);
    if (comptime arch == .s390x) return s390xFeraiseexcept(mask);
    if (comptime powerpc_hard_float) return powerpcFeraiseexcept(mask);
    if (comptime m68k_hard_float) return m68kFeraiseexcept(mask);
    if (comptime is_hexagon) return hexagonFeraiseexcept(mask);
    return 0;
}

fn fetestexcept(mask: c_int) callconv(.c) c_int {
    if (comptime is_x86_family) return x86Fetestexcept(mask);
    if (comptime is_aarch64) return aarch64Fetestexcept(mask);
    if (comptime is_arm_hard_float) return armFetestexcept(mask);
    if (comptime riscv_has_f) return riscvFetestexcept(mask);
    if (comptime mips_hard_float) return mipsFetestexcept(mask);
    if (comptime loongarch_has_f) return loongarchFetestexcept(mask);
    if (comptime arch == .s390x) return s390xFetestexcept(mask);
    if (comptime powerpc_hard_float) return powerpcFetestexcept(mask);
    if (comptime m68k_hard_float) return m68kFetestexcept(mask);
    if (comptime is_hexagon) return hexagonFetestexcept(mask);
    return 0;
}

fn fegetround() callconv(.c) c_int {
    if (comptime is_x86_family) return x86Fegetround();
    if (comptime is_aarch64) return aarch64Fegetround();
    if (comptime is_arm_hard_float) return armFegetround();
    if (comptime riscv_has_f) return riscvFegetround();
    if (comptime mips_hard_float) return mipsFegetround();
    if (comptime loongarch_has_f) return loongarchFegetround();
    if (comptime arch == .s390x) return s390xFegetround();
    if (comptime powerpc_hard_float) return powerpcFegetround();
    if (comptime m68k_hard_float) return m68kFegetround();
    if (comptime is_hexagon) return hexagonFegetround();
    return FE_TONEAREST;
}

fn __fesetround(r: c_int) callconv(.c) c_int {
    if (comptime is_x86_family) return x86Fesetround(r);
    if (comptime is_aarch64) return aarch64Fesetround(r);
    if (comptime is_arm_hard_float) return armFesetround(r);
    if (comptime riscv_has_f) return riscvFesetround(r);
    if (comptime mips_hard_float) return mipsFesetround(r);
    if (comptime loongarch_has_f) return loongarchFesetround(r);
    if (comptime arch == .s390x) return s390xFesetround(r);
    if (comptime powerpc_hard_float) return powerpcFesetround(r);
    if (comptime m68k_hard_float) return m68kFesetround(r);
    if (comptime is_hexagon) return hexagonFesetround(r);
    return 0;
}

fn fegetenv(envp: *anyopaque) callconv(.c) c_int {
    if (comptime is_x86_family) return x86Fegetenv(envp);
    if (comptime is_aarch64) return aarch64Fegetenv(@ptrCast(@alignCast(envp)));
    if (comptime is_arm_hard_float) return armFegetenv(@ptrCast(@alignCast(envp)));
    if (comptime riscv_has_f) return riscvFegetenv(@ptrCast(@alignCast(envp)));
    if (comptime mips_hard_float) return mipsFegetenv(@ptrCast(@alignCast(envp)));
    if (comptime loongarch_has_f) return loongarchFegetenv(@ptrCast(@alignCast(envp)));
    if (comptime arch == .s390x) return s390xFegetenv(@ptrCast(@alignCast(envp)));
    if (comptime powerpc_hard_float) return powerpcFegetenv(@ptrCast(@alignCast(envp)));
    if (comptime m68k_hard_float) return m68kFegetenv(@ptrCast(@alignCast(envp)));
    if (comptime is_hexagon) return hexagonFegetenv(@ptrCast(@alignCast(envp)));
    return 0;
}

fn fesetenv(envp: *const anyopaque) callconv(.c) c_int {
    if (comptime is_x86_family) return x86Fesetenv(envp);
    if (comptime is_aarch64) {
        const default_env = Aarch64Env{ .fpcr = 0, .fpsr = 0 };
        const typed = if (@intFromPtr(envp) == FE_DFL_ENV) &default_env else @as(*const Aarch64Env, @ptrCast(@alignCast(envp)));
        return aarch64Fesetenv(typed);
    }
    if (comptime is_arm_hard_float) {
        const default_env = ArmEnv{ .cw = 0 };
        const typed = if (@intFromPtr(envp) == FE_DFL_ENV) &default_env else @as(*const ArmEnv, @ptrCast(@alignCast(envp)));
        return armFesetenv(typed);
    }
    if (comptime riscv_has_f) {
        const default_env: c_uint = 0;
        const typed = if (@intFromPtr(envp) == FE_DFL_ENV) &default_env else @as(*const c_uint, @ptrCast(@alignCast(envp)));
        return riscvFesetenv(typed);
    }
    if (comptime mips_hard_float) {
        const default_env: c_uint = 0;
        const typed = if (@intFromPtr(envp) == FE_DFL_ENV) &default_env else @as(*const c_uint, @ptrCast(@alignCast(envp)));
        return mipsFesetenv(typed);
    }
    if (comptime loongarch_has_f) {
        const default_env: c_uint = 0;
        const typed = if (@intFromPtr(envp) == FE_DFL_ENV) &default_env else @as(*const c_uint, @ptrCast(@alignCast(envp)));
        return loongarchFesetenv(typed);
    }
    if (comptime arch == .s390x) {
        const default_env: c_uint = 0;
        const typed = if (@intFromPtr(envp) == FE_DFL_ENV) &default_env else @as(*const c_uint, @ptrCast(@alignCast(envp)));
        return s390xFesetenv(typed);
    }
    if (comptime powerpc_hard_float) {
        const default_env: f64 = 0;
        const typed = if (@intFromPtr(envp) == FE_DFL_ENV) &default_env else @as(*const f64, @ptrCast(@alignCast(envp)));
        return powerpcFesetenv(typed);
    }
    if (comptime m68k_hard_float) {
        const default_env = M68kEnv{ .control_register = 0, .status_register = 0, .instruction_address = 0 };
        const typed = if (@intFromPtr(envp) == FE_DFL_ENV) &default_env else @as(*const M68kEnv, @ptrCast(@alignCast(envp)));
        return m68kFesetenv(typed);
    }
    if (comptime is_hexagon) {
        const default_env: c_uint = 0;
        const typed = if (@intFromPtr(envp) == FE_DFL_ENV) &default_env else @as(*const c_uint, @ptrCast(@alignCast(envp)));
        return hexagonFesetenv(typed);
    }
    return 0;
}

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

fn fegetmode(modep: *anyopaque) callconv(.c) c_int {
    if (comptime is_x86_family) {
        const mode: *X86Mode = @ptrCast(@alignCast(modep));
        mode.control_word = x86Fnstcw();
        mode.reserved = 0;
        mode.mxcsr = x86Stmxcsr() & ~@as(c_uint, 0x3f);
        return 0;
    }
    if (comptime is_aarch64) {
        (@as(*c_uint, @ptrCast(@alignCast(modep)))).* = @truncate(aarch64GetFpcr());
        return 0;
    }
    if (comptime is_arm_hard_float) {
        (@as(*c_uint, @ptrCast(@alignCast(modep)))).* = armGetFpscr() & ~@as(c_uint, 0x1f);
        return 0;
    }
    if (comptime riscv_has_f) {
        (@as(*c_uint, @ptrCast(@alignCast(modep)))).* = riscvFrcsr() & ~@as(c_uint, 0x1f);
        return 0;
    }
    if (comptime mips_hard_float) {
        (@as(*c_uint, @ptrCast(@alignCast(modep)))).* = mipsGetFcsr() & ~@as(c_uint, 0x7c);
        return 0;
    }
    if (comptime loongarch_has_f) {
        (@as(*c_uint, @ptrCast(@alignCast(modep)))).* = loongarchGetFcsr() & ~@as(c_uint, 0x1f0000);
        return 0;
    }
    if (comptime arch == .s390x) {
        (@as(*c_uint, @ptrCast(@alignCast(modep)))).* = s390xGetFpc() & ~@as(c_uint, 0xf80000);
        return 0;
    }
    if (comptime powerpc_hard_float) {
        (@as(*f64, @ptrCast(@alignCast(modep)))).* = @bitCast(powerpcGetFpscr() & ~@as(u64, 0x3e000000));
        return 0;
    }
    if (comptime m68k_hard_float) {
        (@as(*c_uint, @ptrCast(@alignCast(modep)))).* = m68kGetcr();
        return 0;
    }
    if (comptime is_hexagon) {
        (@as(*c_uint, @ptrCast(@alignCast(modep)))).* = hexagonGetUsr() & HEXAGON_RND_MASK;
        return 0;
    }
    return 0;
}

fn fesetmode(modep: *const anyopaque) callconv(.c) c_int {
    if (comptime is_x86_family) {
        const default_mode = X86Mode{ .control_word = 0x037f, .reserved = 0, .mxcsr = 0x1f80 };
        const mode = if (@intFromPtr(modep) == FE_DFL_ENV)
            default_mode
        else
            (@as(*const X86Mode, @ptrCast(@alignCast(modep)))).*;
        x86Fldcw(mode.control_word);
        if (x86HasSse()) x86Ldmxcsr((x86Stmxcsr() & 0x3f) | (mode.mxcsr & ~@as(c_uint, 0x3f)));
        return 0;
    }
    if (comptime is_aarch64) {
        const mode: c_uint = if (@intFromPtr(modep) == FE_DFL_ENV) 0 else (@as(*const c_uint, @ptrCast(@alignCast(modep)))).*;
        aarch64SetFpcr(mode);
        return 0;
    }
    if (comptime is_arm_hard_float) {
        const mode: c_uint = if (@intFromPtr(modep) == FE_DFL_ENV) 0 else (@as(*const c_uint, @ptrCast(@alignCast(modep)))).*;
        armSetFpscr((armGetFpscr() & 0x1f) | (mode & ~@as(c_uint, 0x1f)));
        return 0;
    }
    if (comptime riscv_has_f) {
        const mode: c_uint = if (@intFromPtr(modep) == FE_DFL_ENV) 0 else (@as(*const c_uint, @ptrCast(@alignCast(modep)))).*;
        riscvFscsr((riscvFrcsr() & 0x1f) | (mode & ~@as(c_uint, 0x1f)));
        return 0;
    }
    if (comptime mips_hard_float) {
        const mode: c_uint = if (@intFromPtr(modep) == FE_DFL_ENV) 0 else (@as(*const c_uint, @ptrCast(@alignCast(modep)))).*;
        mipsSetFcsr((mipsGetFcsr() & 0x7c) | (mode & ~@as(c_uint, 0x7c)));
        return 0;
    }
    if (comptime loongarch_has_f) {
        const mode: c_uint = if (@intFromPtr(modep) == FE_DFL_ENV) 0 else (@as(*const c_uint, @ptrCast(@alignCast(modep)))).*;
        loongarchSetFcsr((loongarchGetFcsr() & 0x1f0000) | (mode & ~@as(c_uint, 0x1f0000)));
        return 0;
    }
    if (comptime arch == .s390x) {
        const mode: c_uint = if (@intFromPtr(modep) == FE_DFL_ENV) 0 else (@as(*const c_uint, @ptrCast(@alignCast(modep)))).*;
        s390xSetFpc((s390xGetFpc() & 0xf80000) | (mode & ~@as(c_uint, 0xf80000)));
        return 0;
    }
    if (comptime powerpc_hard_float) {
        const mode_bits: u64 = if (@intFromPtr(modep) == FE_DFL_ENV) 0 else @bitCast((@as(*const f64, @ptrCast(@alignCast(modep)))).*);
        powerpcSetFpscr((powerpcGetFpscr() & 0x3e000000) | (mode_bits & ~@as(u64, 0x3e000000)));
        return 0;
    }
    if (comptime m68k_hard_float) {
        const mode: c_uint = if (@intFromPtr(modep) == FE_DFL_ENV) 0 else (@as(*const c_uint, @ptrCast(@alignCast(modep)))).*;
        m68kSetcr(mode);
        return 0;
    }
    if (comptime is_hexagon) {
        const mode: c_uint = if (@intFromPtr(modep) == FE_DFL_ENV) 0 else (@as(*const c_uint, @ptrCast(@alignCast(modep)))).*;
        hexagonSetUsr((hexagonGetUsr() & ~HEXAGON_RND_MASK) | (mode & HEXAGON_RND_MASK));
        return 0;
    }
    return 0;
}
