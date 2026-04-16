const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../../c.zig").symbol;
const errno = @import("../../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&madviseLinux, "madvise");

        symbol(&mincoreLinux, "mincore");

        symbol(&mlockLinux, "mlock");
        symbol(&mlockallLinux, "mlockall");

        symbol(&mmapLinux, "mmap");

        symbol(&mprotectLinux, "mprotect");

        symbol(&msyncLinux, "msync");

        symbol(&munlockLinux, "munlock");
        symbol(&munlockallLinux, "munlockall");

        symbol(&munmapLinux, "munmap");
        symbol(&mprotectLinux, "__mprotect");
        symbol(&munmapLinux, "__munmap");
        symbol(&mmapLinux, "__mmap");

        symbol(&posix_madviseLinux, "posix_madvise");

        symbol(&shm_openLinux, "shm_open");
        symbol(&shm_unlinkLinux, "shm_unlink");
    }
}

fn madviseLinux(addr: *anyopaque, len: usize, advice: c_int) callconv(.c) c_int {
    return errno(std.os.linux.madvise(@ptrCast(addr), len, @bitCast(advice)));
}

fn mincoreLinux(addr: *anyopaque, len: usize, vec: [*]u8) callconv(.c) c_int {
    return errno(std.os.linux.mincore(@ptrCast(addr), len, vec));
}

fn mlockLinux(addr: *const anyopaque, len: usize) callconv(.c) c_int {
    return errno(std.os.linux.mlock(@ptrCast(addr), len));
}

fn mlockallLinux(flags: c_int) callconv(.c) c_int {
    return errno(std.os.linux.mlockall(@bitCast(flags)));
}

fn mprotectLinux(addr: *anyopaque, len: usize, prot: c_int) callconv(.c) c_int {
    const page_size = std.heap.pageSize();
    const start = std.mem.alignBackward(usize, @intFromPtr(addr), page_size);
    const aligned_len = std.mem.alignForward(usize, len, page_size);
    return errno(std.os.linux.mprotect(@ptrFromInt(start), aligned_len, @bitCast(prot)));
}

fn msyncLinux(addr: *anyopaque, len: usize, flags: c_int) callconv(.c) c_int {
    return errno(std.os.linux.msync(@ptrCast(addr), len, flags));
}

fn munlockLinux(addr: *const anyopaque, len: usize) callconv(.c) c_int {
    return errno(std.os.linux.munlock(@ptrCast(addr), len));
}

fn munlockallLinux() callconv(.c) c_int {
    return errno(std.os.linux.munlockall());
}

fn munmapLinux(addr: *anyopaque, len: usize) callconv(.c) c_int {
    return errno(std.os.linux.munmap(@ptrCast(addr), len));
}

fn posix_madviseLinux(addr: *anyopaque, len: usize, advice: c_int) callconv(.c) c_int {
    if (advice == std.os.linux.MADV.DONTNEED) return 0;
    return @intCast(-@as(isize, @bitCast(std.os.linux.madvise(@ptrCast(addr), len, @bitCast(advice)))));
}


fn shm_openLinux(name: [*:0]const u8, flag: c_int, mode: linux.mode_t) callconv(.c) c_int {
    // Validate and construct /dev/shm/<name> path
    var ptr = name;
    while (ptr[0] == '/') ptr += 1;
    if (ptr[0] == 0) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    // Check for embedded '/' or "." / ".."
    var len: usize = 0;
    while (ptr[len] != 0) : (len += 1) {
        if (ptr[len] == '/') {
            std.c._errno().* = @intFromEnum(linux.E.INVAL);
            return -1;
        }
    }
    if (len <= 2 and ptr[0] == '.' and (len == 1 or ptr[1] == '.')) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    if (len > 255) {
        std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
        return -1;
    }
    var buf: [255 + 10]u8 = undefined;
    @memcpy(buf[0..9], "/dev/shm/");
    @memcpy(buf[9..][0..len], ptr[0..len]);
    buf[9 + len] = 0;
    const path: [*:0]const u8 = buf[0 .. 9 + len :0];

    // Open with O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
    const extra_flags: linux.O = .{ .NOFOLLOW = true, .CLOEXEC = true, .NONBLOCK = true };
    const combined: linux.O = @bitCast(@as(u32, @bitCast(extra_flags)) | @as(u32, @bitCast(flag)));
    return errno(linux.openat(linux.AT.FDCWD, path, combined, mode));
}

fn shm_unlinkLinux(name: [*:0]const u8) callconv(.c) c_int {
    var ptr = name;
    while (ptr[0] == '/') ptr += 1;
    if (ptr[0] == 0) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    var len: usize = 0;
    while (ptr[len] != 0) : (len += 1) {
        if (ptr[len] == '/') {
            std.c._errno().* = @intFromEnum(linux.E.INVAL);
            return -1;
        }
    }
    if (len <= 2 and ptr[0] == '.' and (len == 1 or ptr[1] == '.')) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    if (len > 255) {
        std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
        return -1;
    }
    var buf: [255 + 10]u8 = undefined;
    @memcpy(buf[0..9], "/dev/shm/");
    @memcpy(buf[9..][0..len], ptr[0..len]);
    buf[9 + len] = 0;
    const path: [*:0]const u8 = buf[0 .. 9 + len :0];

    return errno(linux.unlink(path));
}

const MAP_FAILED: ?*anyopaque = @ptrFromInt(std.math.maxInt(usize));

fn mmapLinux(addr: ?*anyopaque, len: usize, prot: c_int, flags: c_int, fd: c_int, off: i64) callconv(.c) ?*anyopaque {
    // Reject mappings that would overflow ptrdiff_t
    if (len >= @as(usize, @intCast(std.math.maxInt(isize)))) {
        std.c._errno().* = @intFromEnum(linux.E.NOMEM);
        return MAP_FAILED;
    }
    const ret = linux.mmap(@ptrCast(addr), len, @bitCast(@as(u32, @bitCast(prot))), @bitCast(@as(u32, @bitCast(flags))), fd, off);
    const signed: isize = @bitCast(ret);
    if (signed < 0 and signed >= -4095) {
        @branchHint(.unlikely);
        var e: c_int = @intCast(-signed);
        // Fixup incorrect EPERM from kernel for anonymous mappings
        if (e == @intFromEnum(linux.E.PERM) and addr == null) {
            const f: linux.MAP = @bitCast(@as(u32, @bitCast(flags)));
            if (f.ANONYMOUS and !f.FIXED) e = @intFromEnum(linux.E.NOMEM);
        }
        std.c._errno().* = e;
        return MAP_FAILED;
    }
    return @ptrFromInt(ret);
}


