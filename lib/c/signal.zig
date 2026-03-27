const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

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
}
