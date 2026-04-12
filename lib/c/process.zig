const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

const itimerval = extern struct {
    it_interval: linux.timeval,
    it_value: linux.timeval,

const musl_sigset_t = [128 / @sizeOf(c_ulong)]c_ulong;

const posix_spawnattr_t = extern struct {
    __flags: c_int,
    __pgrp: linux.pid_t,
    __def: musl_sigset_t,
    __mask: musl_sigset_t,
    __prio: c_int,
    __pol: c_int,
    __fn: ?*anyopaque,
    __pad: [64 - @sizeOf(?*anyopaque)]u8,
};

const posix_spawn_file_actions_t = extern struct {
    __pad0: [2]c_int,
    __actions: ?*anyopaque,
    __pad: [16]c_int,
};

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&getitimerLinux, "getitimer");
        symbol(&setitimerLinux, "setitimer");
        // vfork fallback (weak: arch-specific .s files take priority)
        symbol(&vforkLinux, "vfork");
    }
}

fn getitimerLinux(which: c_int, old: *itimerval) callconv(.c) c_int {
    return errno(linux.syscall2(.getitimer, @as(usize, @bitCast(@as(isize, which))), @intFromPtr(old)));
}

fn setitimerLinux(which: c_int, new: *const itimerval, old: ?*itimerval) callconv(.c) c_int {
    return errno(linux.syscall3(.setitimer, @as(usize, @bitCast(@as(isize, which))), @intFromPtr(new), @intFromPtr(old)));
}

fn vforkLinux() callconv(.c) linux.pid_t {
    // Fallback: vfork cannot be correctly implemented in C/Zig.
    // Architecture-specific .s files provide real vfork where available.
    const r: isize = @bitCast(linux.fork());
    if (r < 0) {
        @branchHint(.unlikely);
        std.c._errno().* = @intCast(-r);
        return -1;
    }
    return @intCast(r);
        symbol(&posix_spawnattr_init, "posix_spawnattr_init");
        symbol(&posix_spawnattr_getflags, "posix_spawnattr_getflags");
        symbol(&posix_spawnattr_setflags, "posix_spawnattr_setflags");
        symbol(&posix_spawnattr_getpgroup, "posix_spawnattr_getpgroup");
        symbol(&posix_spawnattr_setpgroup, "posix_spawnattr_setpgroup");
        symbol(&posix_spawnattr_getsigdefault, "posix_spawnattr_getsigdefault");
        symbol(&posix_spawnattr_setsigdefault, "posix_spawnattr_setsigdefault");
        symbol(&posix_spawnattr_getsigmask, "posix_spawnattr_getsigmask");
        symbol(&posix_spawnattr_setsigmask, "posix_spawnattr_setsigmask");
        symbol(&posix_spawn_file_actions_init, "posix_spawn_file_actions_init");
    }
}

fn posix_spawnattr_init(attr: *posix_spawnattr_t) callconv(.c) c_int {
    @memset(std.mem.asBytes(attr), 0);
    return 0;
}

fn posix_spawnattr_getflags(attr: *const posix_spawnattr_t, flags: *c_short) callconv(.c) c_int {
    flags.* = @intCast(attr.__flags);
    return 0;
}

fn posix_spawnattr_setflags(attr: *posix_spawnattr_t, flags: c_short) callconv(.c) c_int {
    const all_flags: c_uint = 0x1 | 0x2 | 0x4 | 0x8 | 0x10 | 0x20 | 0x40 | 0x80;
    if (@as(c_uint, @bitCast(@as(c_int, flags))) & ~all_flags != 0)
        return @intFromEnum(linux.E.INVAL);
    attr.__flags = flags;
    return 0;
}

fn posix_spawnattr_getpgroup(attr: *const posix_spawnattr_t, pgrp: *linux.pid_t) callconv(.c) c_int {
    pgrp.* = attr.__pgrp;
    return 0;
}

fn posix_spawnattr_setpgroup(attr: *posix_spawnattr_t, pgrp: linux.pid_t) callconv(.c) c_int {
    attr.__pgrp = pgrp;
    return 0;
}

fn posix_spawnattr_getsigdefault(attr: *const posix_spawnattr_t, def: *musl_sigset_t) callconv(.c) c_int {
    def.* = attr.__def;
    return 0;
}

fn posix_spawnattr_setsigdefault(attr: *posix_spawnattr_t, def: *const musl_sigset_t) callconv(.c) c_int {
    attr.__def = def.*;
    return 0;
}

fn posix_spawnattr_getsigmask(attr: *const posix_spawnattr_t, mask: *musl_sigset_t) callconv(.c) c_int {
    mask.* = attr.__mask;
    return 0;
}

fn posix_spawnattr_setsigmask(attr: *posix_spawnattr_t, mask: *const musl_sigset_t) callconv(.c) c_int {
    attr.__mask = mask.*;
    return 0;
}

fn posix_spawn_file_actions_init(fa: *posix_spawn_file_actions_t) callconv(.c) c_int {
    fa.__actions = null;
    return 0;
}
