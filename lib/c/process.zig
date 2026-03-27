const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&posix_spawnattr_destroy, "posix_spawnattr_destroy");
        symbol(&posix_spawnattr_getschedparam, "posix_spawnattr_getschedparam");
        symbol(&posix_spawnattr_setschedparam, "posix_spawnattr_setschedparam");
        symbol(&posix_spawnattr_getschedpolicy, "posix_spawnattr_getschedpolicy");
        symbol(&posix_spawnattr_setschedpolicy, "posix_spawnattr_setschedpolicy");
    }
}

fn posix_spawnattr_destroy(_: *anyopaque) callconv(.c) c_int {
    return 0;
}

fn posix_spawnattr_getschedparam(_: *const anyopaque, _: *anyopaque) callconv(.c) c_int {
    return @intFromEnum(linux.E.NOSYS);
}

fn posix_spawnattr_setschedparam(_: *anyopaque, _: *const anyopaque) callconv(.c) c_int {
    return @intFromEnum(linux.E.NOSYS);
}

fn posix_spawnattr_getschedpolicy(_: *const anyopaque, _: *c_int) callconv(.c) c_int {
    return @intFromEnum(linux.E.NOSYS);
}

fn posix_spawnattr_setschedpolicy(_: *anyopaque, _: c_int) callconv(.c) c_int {
    return @intFromEnum(linux.E.NOSYS);
}
