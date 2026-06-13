const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;
const c = @import("../c.zig");
const symbol = c.symbol;
const NSIG = linux.NSIG;
const sigset_t = [128 / @sizeOf(c_ulong)]c_ulong;
const SigsetElement = @typeInfo(sigset_t).array.child;
const bits_per_elem = @bitSizeOf(SigsetElement);
const errno = c.errno;
const MINSIGSTKSZ = switch (builtin.cpu.arch) {
    .aarch64, .aarch64_be => 6144,
    .loongarch64, .powerpc, .powerpcle, .powerpc64, .powerpc64le, .s390x => 4096,
    else => 2048,
};
const all_mask = blk: {
    var mask: sigset_t = undefined;
    for (&mask) |*elem| elem.* = ~@as(SigsetElement, 0);
    break :blk mask;
};
const app_mask = blk: {
    var mask = all_mask;
    // Clear bits for internal signals 32, 33, 34 (bits 31, 32, 33)
    for (.{ 31, 32, 33 }) |s| {
        mask[s / bits_per_elem] &= ~(@as(SigsetElement, 1) << @intCast(s % bits_per_elem));
    }
    break :blk mask;
};
const sighandler_t = ?*align(1) const fn (c_int) callconv(.c) void;

const c_sigaction = extern struct {
    handler: sighandler_t,
    mask: sigset_t,
    flags: c_int,
    restorer: ?*const fn () callconv(.c) void,
};

const FILE = extern struct {
    flags: c_uint,
    rpos: ?[*]u8,
    rend: ?[*]u8,
    close_fn: ?*const fn (?*FILE) callconv(.c) c_int,
    wend: ?[*]u8,
    wpos: ?[*]u8,
    mustbezero_1: ?[*]u8,
    wbase: ?[*]u8,
    read_fn: ?*const fn (?*FILE, [*]u8, usize) callconv(.c) usize,
    write_fn: ?*const fn (?*FILE, [*]const u8, usize) callconv(.c) usize,
    seek_fn: ?*const fn (?*FILE, i64, c_int) callconv(.c) i64,
    buf: ?[*]u8,
    buf_size: usize,
    prev: ?*FILE,
    next: ?*FILE,
    fd: c_int,
    pipe_pid: c_int,
    lockcount: c_long,
    mode: c_int,
    lock: c_int,
    lbf: c_int,
    cookie: ?*anyopaque,
    off: i64,
    getln_buf: ?[*]u8,
    mustbezero_2: ?*anyopaque,
    shend: ?[*]u8,
    shlim: i64,
    shcnt: i64,
    prev_locked: ?*FILE,
    next_locked: ?*FILE,
    locale: ?*anyopaque,
};

const LibC = extern struct {
    can_do_threads: u8,
    threaded: u8,
    secure: u8,
    need_locks: i8,
};

extern var __libc: LibC;
extern var __abort_lock: c_int;
extern "c" fn __lock(lock: *volatile c_int) callconv(.c) void;
extern "c" fn __unlock(lock: *volatile c_int) callconv(.c) void;
const stderr_ext = @extern(*const ?*FILE, .{ .name = "stderr" });
const strsignal_fn = @extern(*const fn (c_int) callconv(.c) [*:0]const u8, .{ .name = "strsignal" });
const fwrite_fn = @extern(*const fn (?*const anyopaque, usize, usize, ?*FILE) callconv(.c) usize, .{ .name = "fwrite" });
const fputc_fn = @extern(*const fn (c_int, ?*FILE) callconv(.c) c_int, .{ .name = "fputc" });
const flockfile_fn = @extern(*const fn (?*FILE) callconv(.c) void, .{ .name = "flockfile" });
const funlockfile_fn = @extern(*const fn (?*FILE) callconv(.c) void, .{ .name = "funlockfile" });

const SA_RESTART = 0x10000000;
const SIG_HOLD: sighandler_t = @ptrFromInt(2);
const SIG_ERR: sighandler_t = @ptrFromInt(std.math.maxInt(usize));
const SIGABRT = 6;
const SI_QUEUE = -1;
const handler_set_len = @max(@as(usize, 1), NSIG / bits_per_elem);
var unmask_done: c_int = 0;
var handler_set: [handler_set_len]SigsetElement = @splat(0);
var __eintr_valid_flag: c_int = 0;

const pthread_mask = blk: {
    var mask: sigset_t = @splat(0);
    for (.{ 32, 33 }) |s| {
        mask[s / bits_per_elem] |= @as(SigsetElement, 1) << @intCast(s % bits_per_elem);
    }
    break :blk mask;
};

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&sigaddsetLinux, "sigaddset");
        symbol(&sigandsetLinux, "sigandset");
        symbol(&sigdelsetLinux, "sigdelset");
        symbol(&sigemptysetLinux, "sigemptyset");
        symbol(&sigfillsetLinux, "sigfillset");
        symbol(&sigisemptysetLinux, "sigisemptyset");
        symbol(&sigismemberLinux, "sigismember");
        symbol(&sigorsetLinux, "sigorset");
        symbol(&__libc_current_sigrtmin, "__libc_current_sigrtmin");
        symbol(&__libc_current_sigrtmax, "__libc_current_sigrtmax");
        symbol(&killLinux, "kill");
        symbol(&killpgLinux, "killpg");
        symbol(&sigpendingLinux, "sigpending");
        symbol(&sigaltstackLinux, "sigaltstack");
        symbol(&sigprocmaskLinux, "sigprocmask");
        symbol(&__get_handler_set, "__get_handler_set");
        symbol(&__libc_sigaction, "__libc_sigaction");
        symbol(&__sigaction, "__sigaction");
        symbol(&sigaction, "sigaction");
        @export(&__eintr_valid_flag, .{ .name = "__eintr_valid_flag", .linkage = .weak, .visibility = .hidden });
        if (@hasDecl(linux.SA, "RESTORER")) {
            @export(&linux.restore, .{ .name = "__restore", .linkage = .weak, .visibility = .hidden });
            @export(&linux.restore_rt, .{ .name = "__restore_rt", .linkage = .weak, .visibility = .hidden });
        } else {
            symbol(&__restore, "__restore");
            symbol(&__restore_rt, "__restore_rt");
        }
        symbol(&__block_all_sigs, "__block_all_sigs");
        symbol(&__block_app_sigs, "__block_app_sigs");
        symbol(&__restore_sigs, "__restore_sigs");
        symbol(&sigholdLinux, "sighold");
        symbol(&sigrelseLinux, "sigrelse");
    }
    if (builtin.link_libc and builtin.os.tag == .linux) {
        symbol(&signalImpl, "signal");
        symbol(&siginterruptImpl, "siginterrupt");
        symbol(&sigignoreImpl, "sigignore");
        symbol(&psiginfo, "psiginfo");
        symbol(&psignal, "psignal");
        symbol(&sigsetImpl, "sigset");
        symbol(&sigqueueImpl, "sigqueue");
    }
}

fn sigaddsetLinux(set: *sigset_t, sig: c_int) callconv(.c) c_int {
    const s: u32 = @bitCast(sig -% 1);
    if (s >= NSIG - 1 or @as(u32, @bitCast(sig -% 32)) < 3) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    (set.*)[s / bits_per_elem] |= @as(SigsetElement, 1) << @intCast(s % bits_per_elem);
    return 0;
}

fn sigandsetLinux(dest: *sigset_t, left: *const sigset_t, right: *const sigset_t) callconv(.c) c_int {
    for (dest, left, right) |*d, l, r| d.* = l & r;
    return 0;
}

fn sigdelsetLinux(set: *sigset_t, sig: c_int) callconv(.c) c_int {
    const s: u32 = @bitCast(sig -% 1);
    if (s >= NSIG - 1 or @as(u32, @bitCast(sig -% 32)) < 3) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    (set.*)[s / bits_per_elem] &= ~(@as(SigsetElement, 1) << @intCast(s % bits_per_elem));
    return 0;
}

fn sigemptysetLinux(set: *sigset_t) callconv(.c) c_int {
    @memset(std.mem.asBytes(set), 0);
    return 0;
}

fn sigfillsetLinux(set: *sigset_t) callconv(.c) c_int {
    @memset(std.mem.asBytes(set), 0xff);
    // Clear bits for internal signals 32, 33, 34 (bits 31, 32, 33)
    inline for (.{ 31, 32, 33 }) |s| {
        (set.*)[s / bits_per_elem] &= ~(@as(SigsetElement, 1) << @intCast(s % bits_per_elem));
    }
    return 0;
}

fn sigisemptysetLinux(set: *const sigset_t) callconv(.c) c_int {
    for (set) |elem| {
        if (elem != 0) return 0;
    }
    return 1;
}

fn sigismemberLinux(set: *const sigset_t, sig: c_int) callconv(.c) c_int {
    const s: u32 = @bitCast(sig -% 1);
    if (s >= NSIG - 1) return 0;
    return @intFromBool((set.*)[s / bits_per_elem] & (@as(SigsetElement, 1) << @intCast(s % bits_per_elem)) != 0);
}

fn sigorsetLinux(dest: *sigset_t, left: *const sigset_t, right: *const sigset_t) callconv(.c) c_int {
    for (dest, left, right) |*d, l, r| d.* = l | r;
    return 0;
}

fn __libc_current_sigrtmin() callconv(.c) c_int {
    return 35;
}

fn __libc_current_sigrtmax() callconv(.c) c_int {
    return NSIG - 1;
}

fn killLinux(pid: linux.pid_t, sig: c_int) callconv(.c) c_int {
    return errno(linux.kill(pid, @enumFromInt(@as(u32, @bitCast(sig)))));
}

fn killpgLinux(pgid: linux.pid_t, sig: c_int) callconv(.c) c_int {
    if (pgid < 0) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    return killLinux(-pgid, sig);
}

fn sigpendingLinux(set: *sigset_t) callconv(.c) c_int {
    return errno(linux.syscall2(.rt_sigpending, @intFromPtr(set), NSIG / 8));
}

fn sigaltstackLinux(ss: ?*const linux.stack_t, old: ?*linux.stack_t) callconv(.c) c_int {
    if (ss) |s| {
        if (s.flags & linux.SS.DISABLE == 0 and s.size < MINSIGSTKSZ) {
            std.c._errno().* = @intFromEnum(linux.E.NOMEM);
            return -1;
        }
        if (s.flags & linux.SS.ONSTACK != 0) {
            std.c._errno().* = @intFromEnum(linux.E.INVAL);
            return -1;
        }
    }
    return errno(linux.sigaltstack(ss, old));
}

fn handlerValue(handler: sighandler_t) usize {
    return if (handler) |h| @intFromPtr(h) else 0;
}

fn copyLibcMaskToKernel(src: *const sigset_t) linux.sigset_t {
    var dst: linux.sigset_t = @splat(0);
    @memcpy(std.mem.asBytes(&dst), std.mem.asBytes(src)[0..@sizeOf(linux.sigset_t)]);
    return dst;
}

fn copyKernelMaskToLibc(dst: *sigset_t, src: *const linux.sigset_t) void {
    @memcpy(std.mem.asBytes(dst)[0..@sizeOf(linux.sigset_t)], std.mem.asBytes(src));
}

fn castFlags(comptime T: type, flags: c_int) T {
    const U = @Int(.unsigned, @bitSizeOf(T));
    const bits: U = @intCast(@as(c_uint, @bitCast(flags)));
    return switch (@typeInfo(T).int.signedness) {
        .signed => @bitCast(bits),
        .unsigned => bits,
    };
}

fn fillKernelSigaction(ksa: *linux.k_sigaction, sa: *const c_sigaction) void {
    ksa.handler = @ptrCast(sa.handler);
    ksa.flags = castFlags(@TypeOf(ksa.flags), sa.flags);
    ksa.mask = copyLibcMaskToKernel(&sa.mask);
    if (@hasField(linux.k_sigaction, "restorer")) {
        ksa.flags |= linux.SA.RESTORER;
        const restorer_fn = if ((sa.flags & linux.SA.SIGINFO) != 0) &linux.restore_rt else &linux.restore;
        ksa.restorer = @ptrCast(restorer_fn);
    }
}

fn __get_handler_set(set: *sigset_t) callconv(.c) void {
    @memcpy(std.mem.asBytes(set)[0..@sizeOf(@TypeOf(handler_set))], std.mem.asBytes(&handler_set));
}

fn __libc_sigaction(sig: c_int, sa: ?*const c_sigaction, old: ?*c_sigaction) callconv(.c) c_int {
    var ksa: linux.k_sigaction = undefined;
    var ksa_old: linux.k_sigaction = undefined;

    if (sa) |act| {
        if (handlerValue(act.handler) > 1 and sig > 0 and @as(c_uint, @intCast(sig)) < NSIG) {
            const s: usize = @intCast(sig - 1);
            _ = @atomicRmw(SigsetElement, &handler_set[s / bits_per_elem], .Or, @as(SigsetElement, 1) << @intCast(s % bits_per_elem), .seq_cst);

            if (__libc.threaded == 0 and unmask_done == 0) {
                _ = linux.syscall4(.rt_sigprocmask, linux.SIG.UNBLOCK, @intFromPtr(&pthread_mask), 0, NSIG / 8);
                unmask_done = 1;
            }

            if ((act.flags & SA_RESTART) == 0) {
                @atomicStore(c_int, &__eintr_valid_flag, 1, .seq_cst);
            }
        }
        fillKernelSigaction(&ksa, act);
    }

    const ksa_arg = if (sa != null) @intFromPtr(&ksa) else 0;
    const old_arg = if (old != null) @intFromPtr(&ksa_old) else 0;
    const rc = linux.syscall4(.rt_sigaction, c.syscallArg(sig), ksa_arg, old_arg, NSIG / 8);
    const ret = errno(rc);
    if (ret == 0) {
        if (old) |o| {
            o.handler = @ptrCast(ksa_old.handler);
            o.flags = @bitCast(@as(c_uint, @truncate(ksa_old.flags)));
            copyKernelMaskToLibc(&o.mask, &ksa_old.mask);
        }
    }
    return ret;
}

fn __sigaction(sig: c_int, sa: ?*const c_sigaction, old: ?*c_sigaction) callconv(.c) c_int {
    const sig_u: c_uint = @bitCast(sig);
    if (sig_u -% 32 < 3 or sig_u -% 1 >= NSIG - 1) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }

    if (sig == SIGABRT) {
        var set: sigset_t = undefined;
        __block_all_sigs(&set);
        __lock(&__abort_lock);
        const ret = __libc_sigaction(sig, sa, old);
        __unlock(&__abort_lock);
        __restore_sigs(&set);
        return ret;
    }
    return __libc_sigaction(sig, sa, old);
}

fn sigaction(sig: c_int, sa: ?*const c_sigaction, old: ?*c_sigaction) callconv(.c) c_int {
    return __sigaction(sig, sa, old);
}

fn __restore() callconv(.c) void {}
fn __restore_rt() callconv(.c) void {}

fn clearInternalSignals(set: *sigset_t) void {
    inline for (.{ 31, 32, 33 }) |s| {
        (set.*)[s / bits_per_elem] &= ~(@as(SigsetElement, 1) << @intCast(s % bits_per_elem));
    }
}

fn sigprocmaskLinux(how: c_int, noalias set: ?*const sigset_t, noalias old: ?*sigset_t) callconv(.c) c_int {
    if (set != null and how != linux.SIG.BLOCK and how != linux.SIG.UNBLOCK and how != linux.SIG.SETMASK) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }

    var filtered: sigset_t = undefined;
    var set_arg = set;
    if (set) |src| {
        if (how == linux.SIG.BLOCK or how == linux.SIG.SETMASK) {
            filtered = src.*;
            clearInternalSignals(&filtered);
            set_arg = &filtered;
        }
    }

    const rc = linux.syscall4(.rt_sigprocmask, @as(u32, @bitCast(how)), @intFromPtr(set_arg), @intFromPtr(old), NSIG / 8);
    const signed: isize = @bitCast(rc);
    if (signed < 0) {
        std.c._errno().* = @intCast(-signed);
        return -1;
    }
    if (old) |old_set| clearInternalSignals(old_set);
    return 0;
}

fn __block_all_sigs(set: ?*sigset_t) callconv(.c) void {
    _ = linux.syscall4(.rt_sigprocmask, linux.SIG.BLOCK, @intFromPtr(&all_mask), @intFromPtr(set), NSIG / 8);
}

fn __block_app_sigs(set: ?*sigset_t) callconv(.c) void {
    _ = linux.syscall4(.rt_sigprocmask, linux.SIG.BLOCK, @intFromPtr(&app_mask), @intFromPtr(set), NSIG / 8);
}

fn __restore_sigs(set: *const sigset_t) callconv(.c) void {
    _ = linux.syscall4(.rt_sigprocmask, linux.SIG.SETMASK, @intFromPtr(set), 0, NSIG / 8);
}

fn sigholdLinux(sig: c_int) callconv(.c) c_int {
    var mask: sigset_t = @splat(0);
    const s: u32 = @bitCast(sig -% 1);
    if (s >= NSIG - 1 or @as(u32, @bitCast(sig -% 32)) < 3) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    mask[s / bits_per_elem] |= @as(SigsetElement, 1) << @intCast(s % bits_per_elem);
    return sigprocmaskLinux(linux.SIG.BLOCK, &mask, null);
}

fn sigrelseLinux(sig: c_int) callconv(.c) c_int {
    var mask: sigset_t = @splat(0);
    const s: u32 = @bitCast(sig -% 1);
    if (s >= NSIG - 1 or @as(u32, @bitCast(sig -% 32)) < 3) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    mask[s / bits_per_elem] |= @as(SigsetElement, 1) << @intCast(s % bits_per_elem);
    return sigprocmaskLinux(linux.SIG.UNBLOCK, &mask, null);
}

fn signalImpl(sig: c_int, func: sighandler_t) callconv(.c) sighandler_t {
    var sa_old: c_sigaction = undefined;
    var sa: c_sigaction = .{
        .handler = func,
        .mask = @splat(0),
        .flags = SA_RESTART,
        .restorer = null,
    };
    if (__sigaction(sig, &sa, &sa_old) < 0) return SIG_ERR;
    return sa_old.handler;
}

fn siginterruptImpl(sig: c_int, flag: c_int) callconv(.c) c_int {
    var sa: c_sigaction = undefined;
    _ = sigaction(sig, null, &sa);
    if (flag != 0) {
        sa.flags &= ~@as(c_int, SA_RESTART);
    } else {
        sa.flags |= SA_RESTART;
    }
    return sigaction(sig, &sa, null);
}

fn sigignoreImpl(sig: c_int) callconv(.c) c_int {
    const SIG_IGN: sighandler_t = @ptrFromInt(1);
    var sa: c_sigaction = .{
        .handler = SIG_IGN,
        .mask = @splat(0),
        .flags = 0,
        .restorer = null,
    };
    return sigaction(sig, &sa, null);
}

fn psignal(sig: c_int, msg: ?[*:0]const u8) callconv(.c) void {
    const f = stderr_ext.*.?;
    const s = strsignal_fn(sig);
    flockfile_fn(f);

    const old_locale = f.locale;
    const old_mode = f.mode;
    const old_errno = std.c._errno().*;
    var ok = true;

    if (msg) |m| {
        const msg_len = std.mem.len(m);
        if (msg_len != 0 and fwrite_fn(m, msg_len, 1, f) != 1) ok = false;
        if (fwrite_fn(": ", 2, 1, f) != 1) ok = false;
    }
    const str_len = std.mem.len(s);
    if (str_len != 0 and fwrite_fn(s, str_len, 1, f) != 1) ok = false;
    if (fputc_fn('\n', f) < 0) ok = false;

    if (ok) std.c._errno().* = old_errno;
    f.mode = old_mode;
    f.locale = old_locale;

    funlockfile_fn(f);
}

fn psiginfo(si: *const linux.siginfo_t, msg: ?[*:0]const u8) callconv(.c) void {
    psignal(@intCast(@intFromEnum(si.signo)), msg);
}

fn sigsetImpl(sig: c_int, handler: sighandler_t) callconv(.c) sighandler_t {
    var sa: c_sigaction = undefined;
    var sa_old: c_sigaction = undefined;
    var mask: sigset_t = @splat(0);
    var mask_old: sigset_t = undefined;

    const s: u32 = @bitCast(sig -% 1);
    if (s >= NSIG - 1 or @as(u32, @bitCast(sig -% 32)) < 3) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return SIG_ERR;
    }
    mask[s / bits_per_elem] |= @as(SigsetElement, 1) << @intCast(s % bits_per_elem);

    if (handler == SIG_HOLD) {
        if (sigaction(sig, null, &sa_old) < 0) return SIG_ERR;
        if (sigprocmaskLinux(linux.SIG.BLOCK, &mask, &mask_old) < 0) return SIG_ERR;
    } else {
        sa = .{ .handler = handler, .mask = @splat(0), .flags = 0, .restorer = null };
        if (sigaction(sig, &sa, &sa_old) < 0) return SIG_ERR;
        if (sigprocmaskLinux(linux.SIG.UNBLOCK, &mask, &mask_old) < 0) return SIG_ERR;
    }
    return if (mask_old[s / bits_per_elem] & (@as(SigsetElement, 1) << @intCast(s % bits_per_elem)) != 0) SIG_HOLD else sa_old.handler;
}

fn sigqueueImpl(pid: linux.pid_t, sig: c_int, value: usize) callconv(.c) c_int {
    // siginfo_t needs to be zeroed and then filled in
    var si: linux.siginfo_t = std.mem.zeroes(linux.siginfo_t);
    si.signo = @enumFromInt(@as(u32, @bitCast(sig)));
    si.code = SI_QUEUE;
    si.fields.common.first.piduid = .{
        .pid = linux.getpid(),
        .uid = linux.getuid(),
    };
    si.fields.common.second.value = @bitCast(value);

    var set: sigset_t = undefined;
    _ = linux.syscall4(.rt_sigprocmask, linux.SIG.BLOCK, @intFromPtr(&app_mask), @intFromPtr(&set), NSIG / 8);
    const ret = errno(linux.syscall3(.rt_sigqueueinfo, @as(usize, @bitCast(@as(isize, pid))), @as(usize, @bitCast(@as(isize, sig))), @intFromPtr(&si)));
    _ = linux.syscall4(.rt_sigprocmask, linux.SIG.SETMASK, @intFromPtr(&set), 0, NSIG / 8);
    return ret;
}
