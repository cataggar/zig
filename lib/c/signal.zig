const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

const NSIG = linux.NSIG;
const sigset_t = linux.sigset_t;
const SigsetElement = @typeInfo(sigset_t).array.child;
const bits_per_elem = @bitSizeOf(SigsetElement);

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
const errno = @import("../c.zig").errno;

const NSIG = linux.NSIG;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&killLinux, "kill");
        symbol(&killpgLinux, "killpg");
        symbol(&sigpendingLinux, "sigpending");
    }
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

fn sigpendingLinux(set: *linux.sigset_t) callconv(.c) c_int {
    return errno(linux.syscall2(.rt_sigpending, @intFromPtr(set), NSIG / 8));
const errno = @import("../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&sigaltstackLinux, "sigaltstack");
    }
}

fn sigaltstackLinux(ss: ?*const linux.stack_t, old: ?*linux.stack_t) callconv(.c) c_int {
    if (ss) |s| {
        if (s.flags & linux.SS.DISABLE == 0 and s.size < linux.MINSIGSTKSZ) {
            std.c._errno().* = @intFromEnum(linux.E.NOMEM);
            return -1;
        }
        if (s.flags & linux.SS.ONSTACK != 0) {
            std.c._errno().* = @intFromEnum(linux.E.INVAL);
            return -1;
        }
    }
    return errno(linux.sigaltstack(ss, old));
        symbol(&sigprocmaskLinux, "sigprocmask");
        symbol(&sigsuspendLinux, "sigsuspend");
    }
}

fn sigprocmaskLinux(how: c_int, noalias set: ?*const linux.sigset_t, noalias old: ?*linux.sigset_t) callconv(.c) c_int {
    const rc = linux.sigprocmask(@bitCast(@as(u32, @bitCast(how))), set, old);
    const signed: isize = @bitCast(rc);
    if (signed < 0) {
        std.c._errno().* = @intCast(-signed);
        return -1;
    }
    return 0;
}

fn sigsuspendLinux(mask: *const linux.sigset_t) callconv(.c) c_int {
    return errno(linux.syscall2(.rt_sigsuspend, @intFromPtr(mask), linux.NSIG / 8));
        // block.c helpers
        symbol(&__block_all_sigs, "__block_all_sigs");
        symbol(&__block_app_sigs, "__block_app_sigs");
        symbol(&__restore_sigs, "__restore_sigs");
        // sighold/sigrelse/sigpause
        symbol(&sigholdLinux, "sighold");
        symbol(&sigrelseLinux, "sigrelse");
        symbol(&sigpauseLinux, "sigpause");
    }
}

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

fn __block_all_sigs(set: ?*sigset_t) callconv(.c) void {
    _ = linux.sigprocmask(linux.SIG.BLOCK, &all_mask, set);
}

fn __block_app_sigs(set: ?*sigset_t) callconv(.c) void {
    _ = linux.sigprocmask(linux.SIG.BLOCK, &app_mask, set);
}

fn __restore_sigs(set: *const sigset_t) callconv(.c) void {
    _ = linux.sigprocmask(linux.SIG.SETMASK, set, null);
}

fn sigholdLinux(sig: c_int) callconv(.c) c_int {
    var mask: sigset_t = @splat(0);
    const s: u32 = @bitCast(sig -% 1);
    if (s >= NSIG - 1 or @as(u32, @bitCast(sig -% 32)) < 3) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    mask[s / bits_per_elem] |= @as(SigsetElement, 1) << @intCast(s % bits_per_elem);
    return errno(linux.sigprocmask(linux.SIG.BLOCK, &mask, null));
}

fn sigrelseLinux(sig: c_int) callconv(.c) c_int {
    var mask: sigset_t = @splat(0);
    const s: u32 = @bitCast(sig -% 1);
    if (s >= NSIG - 1 or @as(u32, @bitCast(sig -% 32)) < 3) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    mask[s / bits_per_elem] |= @as(SigsetElement, 1) << @intCast(s % bits_per_elem);
    return errno(linux.sigprocmask(linux.SIG.UNBLOCK, &mask, null));
}

fn sigpauseLinux(sig: c_int) callconv(.c) c_int {
    var mask: sigset_t = undefined;
    _ = linux.sigprocmask(0, null, &mask);
    const s: u32 = @bitCast(sig -% 1);
    if (s < NSIG - 1) {
        mask[s / bits_per_elem] &= ~(@as(SigsetElement, 1) << @intCast(s % bits_per_elem));
    }
    return errno(linux.syscall2(.rt_sigsuspend, @intFromPtr(&mask), NSIG / 8));
}
