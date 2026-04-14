const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;
const off_t = linux.off_t;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&creatLinux, "creat");
        symbol(&fcntlLinux, "fcntl");
        symbol(&openLinux, "open");
        symbol(&openatLinux, "openat");

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
    if (cmd == std.c.F.SETFL) a |= 0o100000; // O_LARGEFILE
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
    // posix_fallocate returns error code directly (NOT -1 with errno)
    const r = linux.fallocate(fd, 0, offset, len);
    const signed: isize = @bitCast(r);
    if (signed < 0) return @intCast(-signed);
    return 0;
}
