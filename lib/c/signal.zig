const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

const NSIG = linux.NSIG;
const sigset_t = linux.sigset_t;
const SigsetElement = @typeInfo(sigset_t).array.child;
const bits_per_elem = @bitSizeOf(SigsetElement);

// Musl's struct sigaction (different from kernel's k_sigaction)
const c_sigaction = extern struct {
    handler: ?*const fn (c_int) callconv(.c) void,
    mask: [128 / @sizeOf(c_ulong)]c_ulong,
    flags: c_int,
    restorer: ?*const fn () callconv(.c) void,
};

// Functions provided by the C library (sigaction.c remains as C)
extern "c" fn sigaction(sig: c_int, act: ?*const c_sigaction, oact: ?*c_sigaction) callconv(.c) c_int;
extern "c" fn __sigaction(sig: c_int, act: ?*const c_sigaction, oact: ?*c_sigaction) callconv(.c) c_int;

comptime {
    if (builtin.link_libc) {
        symbol(&signalImpl, "signal");
        symbol(&signalImpl, "bsd_signal");
        symbol(&signalImpl, "__sysv_signal");
        symbol(&siginterruptImpl, "siginterrupt");
        symbol(&sigignoreImpl, "sigignore");
        symbol(&psiginfo, "psiginfo");
    }
}

const SA_RESTART = 0x10000000;

fn signalImpl(sig: c_int, func: ?*const fn (c_int) callconv(.c) void) callconv(.c) ?*const fn (c_int) callconv(.c) void {
    const SIG_ERR: ?*const fn (c_int) callconv(.c) void = @ptrFromInt(std.math.maxInt(usize));
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
    const SIG_IGN: ?*const fn (c_int) callconv(.c) void = @ptrFromInt(1);
    var sa: c_sigaction = .{
        .handler = SIG_IGN,
        .mask = @splat(0),
        .flags = 0,
        .restorer = null,
    };
    return sigaction(sig, &sa, null);
}

extern "c" fn psignal(sig: c_int, msg: ?[*:0]const u8) callconv(.c) void;

fn psiginfo(si: *const linux.siginfo_t, msg: ?[*:0]const u8) callconv(.c) void {
    psignal(@intCast(@intFromEnum(si.signo)), msg);
}
