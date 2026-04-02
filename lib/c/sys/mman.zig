const builtin = @import("builtin");

const std = @import("std");

const symbol = @import("../../c.zig").symbol;
const errno = @import("../../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&madviseLinux, "madvise");
        symbol(&madviseLinux, "__madvise");

        symbol(&mincoreLinux, "mincore");

        symbol(&mlockLinux, "mlock");
        symbol(&mlockallLinux, "mlockall");

        symbol(&mmapLinux, "mmap");
        symbol(&mmapLinux, "__mmap");
        symbol(&mmapLinux, "mmap64");

        symbol(&mprotectLinux, "mprotect");
        symbol(&mprotectLinux, "__mprotect");

        symbol(&msyncLinux, "msync");

        symbol(&munlockLinux, "munlock");
        symbol(&munlockallLinux, "munlockall");

        symbol(&munmapLinux, "munmap");
        symbol(&munmapLinux, "__munmap");

        symbol(&posix_madviseLinux, "posix_madvise");
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

fn munlockLinux(addr: *const anyopaque, len: usize) callconv(.c) c_int {
    return errno(std.os.linux.munlock(@ptrCast(addr), len));
}

fn munlockallLinux() callconv(.c) c_int {
    return errno(std.os.linux.munlockall());
}

fn posix_madviseLinux(addr: *anyopaque, len: usize, advice: c_int) callconv(.c) c_int {
    if (advice == std.os.linux.MADV.DONTNEED) return 0;
    return @intCast(-@as(isize, @bitCast(std.os.linux.madvise(@ptrCast(addr), len, @bitCast(advice)))));
}

const linux = std.os.linux;

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

fn msyncLinux(addr: *anyopaque, len: usize, flags: c_int) callconv(.c) c_int {
    return errno(linux.msync(@ptrCast(addr), len, flags));
}

fn munmapLinux(addr: *anyopaque, len: usize) callconv(.c) c_int {
    return errno(linux.munmap(@ptrCast(addr), len));
}
