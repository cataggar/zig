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
