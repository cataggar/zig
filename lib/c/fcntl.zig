const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;
const off_t = linux.off_t;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&creatLinux, "creat");
        symbol(&creatLinux, "creat64");
        symbol(&fcntlLinux, "fcntl");
        symbol(&fcntlLinux, "fcntl64");
        symbol(&openLinux, "open");
        symbol(&openLinux, "open64");
        symbol(&openatLinux, "openat");
        symbol(&openatLinux, "openat64");

        symbol(&fallocateLinux, "fallocate");
        symbol(&posix_fadviseLinux, "posix_fadvise");
        symbol(&posix_fallocateLinux, "posix_fallocate");
    }
}

fn creatLinux(path: [*:0]const c_char, mode: linux.mode_t) callconv(.c) c_int {
    return openLinux(path, @bitCast(@as(u32, @bitCast(std.c.O{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }))), mode);
}

fn fcntlLinux(fd: c_int, cmd: c_int, arg: c_ulong) callconv(.c) c_int {
    var a = arg;
    // F_SETFL must include O_LARGEFILE (musl always uses 64-bit offsets)
    if (cmd == std.c.F.SETFL) a |= @as(c_ulong, @bitCast(@as(c_long, @bitCast(std.c.O{ .LARGEFILE = true }))));
    return errno(linux.fcntl(fd, cmd, a));
}

fn openLinux(path: [*:0]const c_char, flags: c_int, mode: linux.mode_t) callconv(.c) c_int {
    return errno(linux.openat(linux.AT.FDCWD, @ptrCast(path), @bitCast(flags), mode));
}

fn openatLinux(fd: c_int, path: [*:0]const c_char, flags: c_int, mode: linux.mode_t) callconv(.c) c_int {
    return errno(linux.openat(fd, @ptrCast(path), @bitCast(flags), mode));
}
fn fallocateLinux(fd: c_int, mode: c_int, offset: off_t, len: off_t) callconv(.c) c_int {
    return errno(linux.fallocate(fd, mode, offset, len));
}

fn posix_fadviseLinux(fd: c_int, offset: off_t, len: off_t, advice: c_int) callconv(.c) c_int {
    return errno(linux.fadvise(fd, offset, len, @intCast(advice)));
}

fn posix_fallocateLinux(fd: c_int, offset: off_t, len: off_t) callconv(.c) c_int {
    return errno(linux.fallocate(fd, 0, offset, len));
}
