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

const VaList = std.builtin.VaList;

inline fn cVaArg(ap: *VaList, comptime T: type) T {
    if ((builtin.cpu.arch == .aarch64 or builtin.cpu.arch == .aarch64_be) and
        builtin.os.tag != .macos and builtin.os.tag != .ios and
        builtin.os.tag != .tvos and builtin.os.tag != .watchos and
        builtin.os.tag != .visionos and builtin.os.tag != .windows)
    {
        const is_be = builtin.cpu.arch == .aarch64_be;
        const align_bytes: usize = @max(@alignOf(T), 8);
        const size_bytes: usize = @sizeOf(T);
        const offs = ap.__gr_offs;
        if (offs < 0) {
            const aligned_offs: c_int = if (align_bytes > 8)
                (offs + @as(c_int, @intCast(align_bytes - 1))) & -@as(c_int, @intCast(align_bytes))
            else
                offs;
            const reg_size: c_int = @intCast((size_bytes + 7) & ~@as(usize, 7));
            const new_offs = aligned_offs + reg_size;
            ap.__gr_offs = new_offs;
            if (new_offs <= 0) {
                const top: usize = @intFromPtr(ap.__gr_top);
                const base_addr: usize = @bitCast(@as(isize, @bitCast(top)) + @as(isize, aligned_offs));
                const be_delta: usize = if (is_be and size_bytes < 8) 8 - size_bytes else 0;
                return @as(*align(1) const T, @ptrFromInt(base_addr + be_delta)).*;
            }
        }
        const stack_addr: usize = @intFromPtr(ap.__stack);
        const aligned_stack: usize = (stack_addr + (align_bytes - 1)) & ~(align_bytes - 1);
        const stack_size: usize = (size_bytes + 7) & ~@as(usize, 7);
        ap.__stack = @ptrFromInt(aligned_stack + stack_size);
        const be_delta: usize = if (is_be and size_bytes < 8) 8 - size_bytes else 0;
        return @as(*align(1) const T, @ptrFromInt(aligned_stack + be_delta)).*;
    }
    if (builtin.cpu.arch == .s390x) {
        const padded_size: usize = 8;
        const padding: usize = padded_size - @sizeOf(T);
        const addr: usize = if (ap.__gpr < 5) blk: {
            const count: usize = @intCast(ap.__gpr);
            ap.__gpr += 1;
            break :blk @intFromPtr(ap.__reg_save_area) + (2 + count) * padded_size + padding;
        } else blk: {
            const ovf: usize = @intFromPtr(ap.__overflow_arg_area);
            ap.__overflow_arg_area = @ptrFromInt(ovf + padded_size);
            break :blk ovf + padding;
        };
        return @as(*align(1) const T, @ptrFromInt(addr)).*;
    }
    if (builtin.cpu.arch == .x86_64 and (builtin.os.tag == .windows or builtin.os.tag == .uefi)) {
        const cur: usize = @intFromPtr(ap.*);
        ap.* = @ptrFromInt(cur + 8);
        return @as(*align(1) const T, @ptrFromInt(cur)).*;
    }
    return @cVaArg(ap, T);
}

fn fcntlLinux(fd: c_int, cmd: c_int, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    const arg = cVaArg(&ap, c_ulong);
    @cVaEnd(&ap);
    var a: usize = arg;
    // F_SETFL must include O_LARGEFILE (musl always uses 64-bit offsets)
    if (cmd == std.c.F.SETFL) a |= 0o100000; // O_LARGEFILE
    if (cmd == linux.F.GETOWN) {
        const F_GETOWN_EX: i32 = 16;
        const F_OWNER_PGRP: c_int = 2;
        const FOwnerEx = extern struct {
            type: c_int,
            pid: c_int,
        };
        var ex: FOwnerEx = undefined;
        const ret = linux.fcntl(fd, F_GETOWN_EX, @intFromPtr(&ex));
        if (@as(isize, @bitCast(ret)) == -@as(isize, @backingInt(linux.E.INVAL))) {
            return @intCast(@as(isize, @bitCast(linux.fcntl(fd, cmd, a))));
        }
        if (errno(ret) != 0) return -1;
        return if (ex.type == F_OWNER_PGRP) -ex.pid else ex.pid;
    }
    if (cmd == linux.F.DUPFD_CLOEXEC) {
        var ret = linux.fcntl(fd, linux.F.DUPFD_CLOEXEC, a);
        var signed: isize = @bitCast(ret);
        if (signed != -@as(isize, @backingInt(linux.E.INVAL))) {
            if (signed >= 0) _ = linux.fcntl(@intCast(signed), linux.F.SETFD, linux.FD_CLOEXEC);
            return errno(ret);
        }
        ret = linux.fcntl(fd, linux.F.DUPFD_CLOEXEC, 0);
        signed = @bitCast(ret);
        if (signed != -@as(isize, @backingInt(linux.E.INVAL))) {
            if (signed >= 0) _ = linux.close(@intCast(signed));
            std.c._errno().* = @intCast(@backingInt(linux.E.INVAL));
            return -1;
        }
        ret = linux.fcntl(fd, linux.F.DUPFD, a);
        signed = @bitCast(ret);
        if (signed >= 0) _ = linux.fcntl(@intCast(signed), linux.F.SETFD, linux.FD_CLOEXEC);
        return errno(ret);
    }
    return errno(linux.fcntl(fd, cmd, a));
}

fn openLinux(path: [*:0]const c_char, flags: c_int, mode: linux.mode_t) callconv(.c) c_int {
    return errno(linux.openat(linux.AT.FDCWD, @ptrCast(path), @bitCast(flags), mode));
}

fn openatLinux(fd: c_int, path: [*:0]const c_char, flags: c_int, mode: linux.mode_t) callconv(.c) c_int {
    return errno(linux.openat(fd, @ptrCast(path), @bitCast(flags), mode));
}
fn fallocateLinux(fd: c_int, mode: c_int, offset: off_t, len: off_t) callconv(.c) c_int {
    return errno(linux.fallocate(fd, @bitCast(mode), offset, len));
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
