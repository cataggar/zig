const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const c = @import("../c.zig");

/// Musl libc sigset_t: 1024-bit signal set, matching the C ABI.
const sigset_t = std.c.sigset_t;

/// Matches the musl `posix_spawnattr_t` layout from spawn.h.
const posix_spawnattr_t = extern struct {
    __flags: c_int,
    __pgrp: c_int,
    __def: sigset_t,
    __mask: sigset_t,
    __prio: c_int,
    __pol: c_int,
    __fn: ?*anyopaque,
    __pad: [64 - @sizeOf(?*anyopaque)]u8,
};

comptime {
    if (builtin.target.isMuslLibC()) {
        c.symbol(&posix_spawnattr_destroy, "posix_spawnattr_destroy");
        c.symbol(&posix_spawnattr_getschedparam, "posix_spawnattr_getschedparam");
        c.symbol(&posix_spawnattr_setschedparam, "posix_spawnattr_setschedparam");
        c.symbol(&posix_spawnattr_getschedpolicy, "posix_spawnattr_getschedpolicy");
        c.symbol(&posix_spawnattr_setschedpolicy, "posix_spawnattr_setschedpolicy");
    }
}

fn posix_spawnattr_init(attr: *posix_spawnattr_t) callconv(.c) c_int {
    attr.* = std.mem.zeroes(posix_spawnattr_t);
    return 0;
}

fn posix_spawnattr_destroy(_: *posix_spawnattr_t) callconv(.c) c_int {
    return 0;
}

fn posix_spawnattr_getflags(attr: *const posix_spawnattr_t, flags: *c_short) callconv(.c) c_int {
    flags.* = @intCast(attr.__flags);
    return 0;
}

fn posix_spawnattr_setflags(attr: *posix_spawnattr_t, flags: c_short) callconv(.c) c_int {
    const all_flags: c_uint = 0x1 | 0x2 | 0x4 | 0x8 | 0x10 | 0x20 | 0x40 | 0x80;
    if (@as(c_uint, @bitCast(@as(c_int, flags))) & ~all_flags != 0) {
        return @intFromEnum(linux.E.INVAL);
    }
    attr.__flags = flags;
    return 0;
}

fn posix_spawnattr_getpgroup(attr: *const posix_spawnattr_t, pgrp: *c_int) callconv(.c) c_int {
    pgrp.* = attr.__pgrp;
    return 0;
}

fn posix_spawnattr_setpgroup(attr: *posix_spawnattr_t, pgrp: c_int) callconv(.c) c_int {
    attr.__pgrp = pgrp;
    return 0;
}

fn posix_spawnattr_getsigdefault(attr: *const posix_spawnattr_t, def: *sigset_t) callconv(.c) c_int {
    def.* = attr.__def;
    return 0;
}

fn posix_spawnattr_setsigdefault(attr: *posix_spawnattr_t, def: *const sigset_t) callconv(.c) c_int {
    attr.__def = def.*;
    return 0;
}

fn posix_spawnattr_getsigmask(attr: *const posix_spawnattr_t, mask: *sigset_t) callconv(.c) c_int {
    mask.* = attr.__mask;
    return 0;
}

fn posix_spawnattr_setsigmask(attr: *posix_spawnattr_t, mask: *const sigset_t) callconv(.c) c_int {
    attr.__mask = mask.*;
    return 0;
}

fn posix_spawnattr_getschedparam(_: *const posix_spawnattr_t, _: *anyopaque) callconv(.c) c_int {
    return @intFromEnum(linux.E.NOSYS);
}

fn posix_spawnattr_setschedparam(_: *posix_spawnattr_t, _: *const anyopaque) callconv(.c) c_int {
    return @intFromEnum(linux.E.NOSYS);
}

fn posix_spawnattr_getschedpolicy(_: *const posix_spawnattr_t, _: *c_int) callconv(.c) c_int {
    return @intFromEnum(linux.E.NOSYS);
}

fn posix_spawnattr_setschedpolicy(_: *posix_spawnattr_t, _: c_int) callconv(.c) c_int {
    return @intFromEnum(linux.E.NOSYS);
}
