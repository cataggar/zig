/// WASI CloudLibc syscall wrappers migrated from C to Zig.
///
/// These functions were originally in lib/libc/wasi/libc-bottom-half/cloudlibc/src/libc/.
/// They wrap WASI preview1 syscalls to provide POSIX-compatible C library functions.
const builtin = @import("builtin");
const std = @import("std");
const wasi = std.os.wasi;
const symbol = @import("../c.zig").symbol;
const E = std.c.E;
/// In WASI libc, clockid_t is `const struct __clockid *` (a pointer to a struct
/// containing the raw WASI clock ID). This differs from Zig's std.c.clockid_t.
const CClockId = extern struct { id: wasi.clockid_t };
const NSEC_PER_SEC: u64 = 1_000_000_000;
const timeval = extern struct {
    sec: i64,
    usec: i64,
};
const sym = @import("../c.zig").symbol;
extern "c" fn c_close(fd: c_int) c_int;
extern "c" fn c_malloc(size: usize) ?[*]align(@alignOf(usize)) u8;
extern "c" fn c_free(ptr: ?*anyopaque) void;
extern "c" fn c_realloc(ptr: ?*anyopaque, size: usize) ?[*]align(@alignOf(usize)) u8;
extern "c" fn c_qsort(
    base: ?*anyopaque,
    nmemb: usize,
    size: usize,
    compar: *const fn (*const anyopaque, *const anyopaque) callconv(.c) c_int,
) void;
extern "c" fn c_openat_nomode(dir: c_int, path: [*:0]const u8, flags: c_int) c_int;
const DIRENT_DEFAULT_BUFFER_SIZE: usize = 4096;
/// Internal DIR structure matching cloudlibc dirent_impl.h
const DIR = extern struct {
    fd: c_int,
    cookie: wasi.dircookie_t,
    buffer: ?[*]u8,
    buffer_processed: usize,
    buffer_size: usize,
    buffer_used: usize,
    dirent_ptr: ?[*]u8,
    dirent_size: usize,
};
/// Layout helper to compute offsetof(struct dirent, d_name).
const DirentLayout = extern struct {
    d_ino: u64,
    d_type: u8,
    d_name: [1]u8,
};
const DIRENT_D_NAME_OFFSET = @offsetOf(DirentLayout, "d_name");
const PollFd = extern struct {
    fd: c_int,
    events: c_short,
    revents: c_short,
};
const FD_SETSIZE = 1024;
const FdSet = extern struct {
    __nfds: usize,
    __fds: [FD_SETSIZE]c_int,
};
const ClockId = extern struct {
    id: wasi.clockid_t,
};
const Timespec = extern struct {
    tv_sec: c_longlong,
    tv_nsec: c_long,
};
const Timeval = extern struct {
    tv_sec: c_longlong,
    tv_usec: c_longlong,
};
// Poll event flags (from __header_poll.h)
const POLLRDNORM: c_short = 0x1;
const POLLWRNORM: c_short = 0x2;
const POLLERR: c_short = 0x1000;
const POLLHUP: c_short = 0x2000;
const POLLNVAL: c_short = 0x4000;
// ioctl requests (from __header_sys_ioctl.h)
const FIONREAD: c_int = 1;
const FIONBIO: c_int = 2;
// O_* flags for WASI (from __header_fcntl.h)
const O_NONBLOCK: c_int = 4; // __WASI_FDFLAGS_NONBLOCK
const O_DIRECTORY: c_int = 2 << 12; // __WASI_OFLAGS_DIRECTORY << 12
const O_RDONLY: c_int = 0x04000000;
const clock_monotonic = ClockId{ .id = .MONOTONIC };
const clock_realtime = ClockId{ .id = .REALTIME };
threadlocal var wasi_errno: c_int = 0;

comptime {
    if (builtin.target.isWasiLibC()) {
        symbol(&readWasi, "read");
        symbol(&writeWasi, "write");
        symbol(&lseekWasi, "__lseek");
        symbol(&lseekWasi, "lseek");
        symbol(&fdatasyncWasi, "fdatasync");
        symbol(&fsyncWasi, "fsync");
        symbol(&ftruncateWasi, "ftruncate");
        symbol(&preadWasi, "pread");
        symbol(&pwriteWasi, "pwrite");
        symbol(&readlinkatWasi, "__wasilibc_nocwd_readlinkat");
        symbol(&linkatWasi, "__wasilibc_nocwd_linkat");
        symbol(&symlinkatWasi, "__wasilibc_nocwd_symlinkat");
        symbol(&faccessatWasi, "__wasilibc_nocwd_faccessat");
        symbol(&unlinkatWasi, "unlinkat");
        symbol(&sleepWasi, "sleep");
        symbol(&usleepWasi, "usleep");
        symbol(&fcntlWasi, "fcntl");
        symbol(&openatWasi, "__wasilibc_nocwd_openat_nomode");
        symbol(&posixFadviseWasi, "posix_fadvise");
        symbol(&posixFallocateWasi, "posix_fallocate");
        symbol(&readvWasi, "readv");
        symbol(&writevWasi, "writev");
        symbol(&preadvWasi, "preadv");
        symbol(&pwritevWasi, "pwritev");
        symbol(&fstatWasi, "fstat");
        symbol(&fstatatWasi, "__wasilibc_nocwd_fstatat");
        symbol(&futimensWasi, "futimens");
        symbol(&mkdiratWasi, "__wasilibc_nocwd_mkdirat_nomode");
        symbol(&utimensatWasi, "__wasilibc_nocwd_utimensat");
        symbol(&recvWasi, "recv");
        symbol(&sendWasi, "send");
        symbol(&shutdownWasi, "shutdown");
        symbol(&getsockoptWasi, "getsockopt");
        symbol(&clockGetresWasi, "clock_getres");
        symbol(&clockGettimeWasi, "__clock_gettime");
        symbol(&clockGettimeWasi, "clock_gettime");
        symbol(&clockNanosleepWasi, "clock_nanosleep");
        symbol(&clockNanosleepWasi, "__clock_nanosleep");
        symbol(&nanosleepWasi, "nanosleep");
        symbol(&timeWasi, "time");
        symbol(&gettimeofdayWasi, "gettimeofday");
        symbol(&schedYieldWasi, "sched_yield");
        symbol(&renameatWasi, "__wasilibc_nocwd_renameat");
        @export(&clock_monotonic, .{ .name = "_CLOCK_MONOTONIC", .linkage = .weak, .visibility = .hidden });
        @export(&clock_realtime, .{ .name = "_CLOCK_REALTIME", .linkage = .weak, .visibility = .hidden });
        @export(&wasi_errno, .{ .name = "errno", .linkage = .weak, .visibility = .hidden });
    }
    @export(&c_close, .{ .name = "close" });
    @export(&c_malloc, .{ .name = "malloc" });
    @export(&c_free, .{ .name = "free" });
    @export(&c_realloc, .{ .name = "realloc" });
    @export(&c_qsort, .{ .name = "qsort" });
    @export(&c_openat_nomode, .{ .name = "__wasilibc_nocwd_openat_nomode" });
}

fn setErrno(e: E) void {
    std.c._errno().* = @intFromEnum(e);
}

fn readWasi(fd: c_int, buf: [*]u8, nbyte: usize) callconv(.c) isize {
    var nread: usize = 0;
    const iov = wasi.iovec_t{ .buf = buf, .buf_len = nbyte };
    switch (wasi.fd_read(@intCast(fd), @ptrCast(&iov), 1, &nread)) {
        .SUCCESS => return @intCast(nread),
        .NOTCAPABLE => {
            setErrno(.BADF);
            return -1;
        },
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn writeWasi(fd: c_int, buf: [*]const u8, nbyte: usize) callconv(.c) isize {
    var nwritten: usize = 0;
    const iov = wasi.ciovec_t{ .buf = buf, .buf_len = nbyte };
    switch (wasi.fd_write(@intCast(fd), @ptrCast(&iov), 1, &nwritten)) {
        .SUCCESS => return @intCast(nwritten),
        .NOTCAPABLE => {
            setErrno(.BADF);
            return -1;
        },
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn lseekWasi(fd: c_int, offset: i64, whence: c_int) callconv(.c) i64 {
    var new_offset: wasi.filesize_t = 0;
    switch (wasi.fd_seek(@intCast(fd), offset, @enumFromInt(@as(u8, @intCast(whence))), &new_offset)) {
        .SUCCESS => return @intCast(new_offset),
        .NOTCAPABLE => {
            setErrno(.SPIPE);
            return -1;
        },
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn fdatasyncWasi(fd: c_int) callconv(.c) c_int {
    switch (wasi.fd_datasync(@intCast(fd))) {
        .SUCCESS => return 0,
        .NOTCAPABLE => {
            setErrno(.BADF);
            return -1;
        },
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn fsyncWasi(fd: c_int) callconv(.c) c_int {
    switch (wasi.fd_sync(@intCast(fd))) {
        .SUCCESS => return 0,
        .NOTCAPABLE => {
            setErrno(.INVAL);
            return -1;
        },
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn ftruncateWasi(fd: c_int, length: i64) callconv(.c) c_int {
    if (length < 0) {
        setErrno(.INVAL);
        return -1;
    }
    switch (wasi.fd_filestat_set_size(@intCast(fd), @intCast(length))) {
        .SUCCESS => return 0,
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn preadWasi(fd: c_int, buf: [*]u8, nbyte: usize, offset: i64) callconv(.c) isize {
    if (offset < 0) {
        setErrno(.INVAL);
        return -1;
    }
    var nread: usize = 0;
    const iov = wasi.iovec_t{ .buf = buf, .buf_len = nbyte };
    switch (wasi.fd_pread(@intCast(fd), @ptrCast(&iov), 1, @intCast(offset), &nread)) {
        .SUCCESS => return @intCast(nread),
        .NOTCAPABLE => {
            var fds: wasi.fdstat_t = undefined;
            if (wasi.fd_fdstat_get(@intCast(fd), &fds) == .SUCCESS) {
                if (!fds.fs_rights_base.FD_READ)
                    setErrno(.BADF)
                else
                    setErrno(.SPIPE);
            } else {
                setErrno(.NOTCAPABLE);
            }
            return -1;
        },
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn pwriteWasi(fd: c_int, buf: [*]const u8, nbyte: usize, offset: i64) callconv(.c) isize {
    if (offset < 0) {
        setErrno(.INVAL);
        return -1;
    }
    var nwritten: usize = 0;
    const iov = wasi.ciovec_t{ .buf = buf, .buf_len = nbyte };
    switch (wasi.fd_pwrite(@intCast(fd), @ptrCast(&iov), 1, @intCast(offset), &nwritten)) {
        .SUCCESS => return @intCast(nwritten),
        .NOTCAPABLE => {
            var fds: wasi.fdstat_t = undefined;
            if (wasi.fd_fdstat_get(@intCast(fd), &fds) == .SUCCESS) {
                if (!fds.fs_rights_base.FD_WRITE)
                    setErrno(.BADF)
                else
                    setErrno(.SPIPE);
            } else {
                setErrno(.NOTCAPABLE);
            }
            return -1;
        },
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn readlinkatWasi(fd: c_int, path: [*]const u8, buf: [*]u8, bufsize: usize) callconv(.c) isize {
    const path_len = std.mem.len(path);
    var bufused: usize = 0;
    switch (wasi.path_readlink(@intCast(fd), path, path_len, buf, bufsize, &bufused)) {
        .SUCCESS => return @intCast(bufused),
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn linkatWasi(fd1: c_int, path1: [*]const u8, fd2: c_int, path2: [*]const u8, flag: c_int) callconv(.c) c_int {
    const AT_SYMLINK_FOLLOW = 0x400;
    const path1_len = std.mem.len(path1);
    const path2_len = std.mem.len(path2);
    var lookup_flags = wasi.lookupflags_t{};
    if ((flag & AT_SYMLINK_FOLLOW) != 0)
        lookup_flags.SYMLINK_FOLLOW = true;
    switch (wasi.path_link(@intCast(fd1), lookup_flags, path1, path1_len, @intCast(fd2), path2, path2_len)) {
        .SUCCESS => return 0,
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn symlinkatWasi(path1: [*]const u8, fd: c_int, path2: [*]const u8) callconv(.c) c_int {
    const path1_len = std.mem.len(path1);
    const path2_len = std.mem.len(path2);
    switch (wasi.path_symlink(path1, path1_len, @intCast(fd), path2, path2_len)) {
        .SUCCESS => return 0,
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn faccessatWasi(fd: c_int, path: [*]const u8, amode: c_int, flag: c_int) callconv(.c) c_int {
    const F_OK = 0;
    const R_OK = 4;
    const W_OK = 2;
    const X_OK = 1;
    const AT_EACCESS = 0x200;

    if ((amode & ~@as(c_int, F_OK | R_OK | W_OK | X_OK)) != 0 or
        (flag & ~@as(c_int, AT_EACCESS)) != 0)
    {
        setErrno(.INVAL);
        return -1;
    }

    const path_len = std.mem.len(path);
    const lookup_flags = wasi.lookupflags_t{ .SYMLINK_FOLLOW = true };
    var file: wasi.filestat_t = undefined;
    switch (wasi.path_filestat_get(@intCast(fd), lookup_flags, path, path_len, &file)) {
        .SUCCESS => {},
        else => |e| {
            setErrno(e);
            return -1;
        },
    }

    if (amode != 0) {
        var directory: wasi.fdstat_t = undefined;
        switch (wasi.fd_fdstat_get(@intCast(fd), &directory)) {
            .SUCCESS => {},
            else => |e| {
                setErrno(e);
                return -1;
            },
        }

        var min = wasi.rights_t{};
        if ((amode & R_OK) != 0) {
            if (file.filetype == .DIRECTORY)
                min.FD_READDIR = true
            else
                min.FD_READ = true;
        }
        if ((amode & W_OK) != 0)
            min.FD_WRITE = true;

        const min_int: u64 = @bitCast(min);
        const inheriting_int: u64 = @bitCast(directory.fs_rights_inheriting);
        if ((min_int & inheriting_int) != min_int) {
            setErrno(.ACCES);
            return -1;
        }
    }
    return 0;
}

fn unlinkatWasi(fd: c_int, path: [*:0]const u8, flag: c_int) callconv(.c) c_int {
    const AT_REMOVEDIR = 0x200;
    if ((flag & AT_REMOVEDIR) != 0)
        return __wasilibc_rmdirat(fd, path);
    return __wasilibc_unlinkat(fd, path);
}

fn sleepWasi(seconds: c_uint) callconv(.c) c_uint {
    const ts = std.c.timespec{ .sec = @intCast(seconds), .nsec = 0 };
    if (clockNanosleepImpl(.REALTIME, 0, &ts) != 0)
        return seconds;
    return 0;
}

fn usleepWasi(useconds: c_uint) callconv(.c) c_int {
    const ts = std.c.timespec{
        .sec = @intCast(useconds / 1_000_000),
        .nsec = @intCast(@as(u64, useconds % 1_000_000) * 1000),
    };
    const err = clockNanosleepImpl(.REALTIME, 0, &ts);
    if (err != 0) {
        setErrno(@enumFromInt(err));
        return -1;
    }
    return 0;
}

fn fcntlWasi(fd: c_int, cmd: c_int, ...) callconv(.c) c_int {
    const F_GETFD = 1;
    const F_SETFD = 2;
    const F_GETFL = 3;
    const F_SETFL = 4;
    const FD_CLOEXEC = 1;
    const O_RDONLY = 0x04000000;
    const O_WRONLY = 0x10000000;
    const O_RDWR = 0x14000000;
    const O_SEARCH = 0x08000000;

    switch (cmd) {
        F_GETFD => return FD_CLOEXEC,
        F_SETFD => return 0,
        F_GETFL => {
            var fds: wasi.fdstat_t = undefined;
            switch (wasi.fd_fdstat_get(@intCast(fd), &fds)) {
                .SUCCESS => {},
                else => |e| {
                    setErrno(e);
                    return -1;
                },
            }

            var oflags: c_int = @as(c_int, @bitCast(@as(u32, @bitCast(fds.fs_flags)) & 0xffff));
            if (fds.fs_rights_base.FD_READ or fds.fs_rights_base.FD_READDIR) {
                if (fds.fs_rights_base.FD_WRITE)
                    oflags |= O_RDWR
                else
                    oflags |= O_RDONLY;
            } else if (fds.fs_rights_base.FD_WRITE) {
                oflags |= O_WRONLY;
            } else {
                oflags |= O_SEARCH;
            }
            return oflags;
        },
        F_SETFL => {
            var ap = @cVaStart();
            const flags_arg = @cVaArg(&ap, c_int);
            @cVaEnd(&ap);
            const fs_flags: wasi.fdflags_t = @bitCast(@as(u16, @truncate(@as(u32, @bitCast(flags_arg)) & 0xfff)));
            switch (wasi.fd_fdstat_set_flags(@intCast(fd), fs_flags)) {
                .SUCCESS => return 0,
                else => |e| {
                    setErrno(e);
                    return -1;
                },
            }
        },
        else => {
            setErrno(.INVAL);
            return -1;
        },
    }
}

fn openatWasi(fd: c_int, path: [*]const u8, oflag: c_int) callconv(.c) c_int {
    const O_ACCMODE = 0x1c000000;
    const O_RDONLY = 0x04000000;
    const O_WRONLY = 0x10000000;
    const O_RDWR = 0x14000000;
    const O_EXEC = 0x02000000;
    const O_SEARCH = 0x08000000;
    const O_NOFOLLOW = 0x01000000;

    // Compute rights. Start with all rights except access-mode-specific ones.
    var max = wasi.rights_t{
        .FD_SEEK = true,
        .FD_FDSTAT_SET_FLAGS = true,
        .FD_SYNC = true,
        .FD_TELL = true,
        .FD_ADVISE = true,
        .PATH_CREATE_DIRECTORY = true,
        .PATH_CREATE_FILE = true,
        .PATH_LINK_SOURCE = true,
        .PATH_LINK_TARGET = true,
        .PATH_OPEN = true,
        .PATH_READLINK = true,
        .PATH_RENAME_SOURCE = true,
        .PATH_RENAME_TARGET = true,
        .PATH_FILESTAT_GET = true,
        .PATH_FILESTAT_SET_SIZE = true,
        .PATH_FILESTAT_SET_TIMES = true,
        .FD_FILESTAT_GET = true,
        .FD_FILESTAT_SET_TIMES = true,
        .PATH_SYMLINK = true,
        .PATH_REMOVE_DIRECTORY = true,
        .PATH_UNLINK_FILE = true,
        .POLL_FD_READWRITE = true,
        .SOCK_SHUTDOWN = true,
        .SOCK_ACCEPT = true,
    };

    switch (oflag & O_ACCMODE) {
        O_RDONLY, O_RDWR, O_WRONLY => {
            if ((oflag & O_RDONLY) != 0) {
                max.FD_READ = true;
                max.FD_READDIR = true;
            }
            if ((oflag & O_WRONLY) != 0) {
                max.FD_DATASYNC = true;
                max.FD_WRITE = true;
                max.FD_ALLOCATE = true;
                max.FD_FILESTAT_SET_SIZE = true;
            }
        },
        O_EXEC, O_SEARCH => {},
        else => {
            setErrno(.INVAL);
            return -1;
        },
    }

    var fsb_cur: wasi.fdstat_t = undefined;
    switch (wasi.fd_fdstat_get(@intCast(fd), &fsb_cur)) {
        .SUCCESS => {},
        else => |e| {
            setErrno(e);
            return -1;
        },
    }

    const path_len = std.mem.len(path);
    var lookup_flags = wasi.lookupflags_t{};
    if ((oflag & O_NOFOLLOW) == 0)
        lookup_flags.SYMLINK_FOLLOW = true;

    const fs_flags: wasi.fdflags_t = @bitCast(@as(u16, @truncate(@as(u32, @bitCast(oflag)) & 0xfff)));
    const max_int: u64 = @bitCast(max);
    const inheriting_int: u64 = @bitCast(fsb_cur.fs_rights_inheriting);
    const fs_rights_base: wasi.rights_t = @bitCast(max_int & inheriting_int);
    const oflags: wasi.oflags_t = @bitCast(@as(u16, @truncate((@as(u32, @bitCast(oflag)) >> 12) & 0xfff)));

    var newfd: wasi.fd_t = 0;
    switch (wasi.path_open(@intCast(fd), lookup_flags, path, path_len, oflags, fs_rights_base, fsb_cur.fs_rights_inheriting, fs_flags, &newfd)) {
        .SUCCESS => return @intCast(newfd),
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn posixFadviseWasi(fd: c_int, offset: i64, len: i64, advice: c_int) callconv(.c) c_int {
    if (offset < 0 or len < 0) return @intFromEnum(E.INVAL);
    return @intFromEnum(wasi.fd_advise(@intCast(fd), @intCast(offset), @intCast(len), @enumFromInt(@as(u8, @intCast(advice)))));
}

fn posixFallocateWasi(fd: c_int, offset: i64, len: i64) callconv(.c) c_int {
    if (offset < 0 or len < 0) return @intFromEnum(E.INVAL);
    return @intFromEnum(wasi.fd_allocate(@intCast(fd), @intCast(offset), @intCast(len)));
}

fn readvWasi(fd: c_int, iov: [*]const wasi.iovec_t, iovcnt: c_int) callconv(.c) isize {
    if (iovcnt < 0) {
        setErrno(.INVAL);
        return -1;
    }
    var nread: usize = 0;
    switch (wasi.fd_read(@intCast(fd), iov, @intCast(iovcnt), &nread)) {
        .SUCCESS => return @intCast(nread),
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn writevWasi(fd: c_int, iov: [*]const wasi.ciovec_t, iovcnt: c_int) callconv(.c) isize {
    if (iovcnt < 0) {
        setErrno(.INVAL);
        return -1;
    }
    var nwritten: usize = 0;
    switch (wasi.fd_write(@intCast(fd), iov, @intCast(iovcnt), &nwritten)) {
        .SUCCESS => return @intCast(nwritten),
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn preadvWasi(fd: c_int, iov: [*]const wasi.iovec_t, iovcnt: c_int, offset: i64) callconv(.c) isize {
    if (iovcnt < 0 or offset < 0) {
        setErrno(.INVAL);
        return -1;
    }
    var nread: usize = 0;
    switch (wasi.fd_pread(@intCast(fd), iov, @intCast(iovcnt), @intCast(offset), &nread)) {
        .SUCCESS => return @intCast(nread),
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn pwritevWasi(fd: c_int, iov: [*]const wasi.ciovec_t, iovcnt: c_int, offset: i64) callconv(.c) isize {
    if (iovcnt < 0 or offset < 0) {
        setErrno(.INVAL);
        return -1;
    }
    var nwritten: usize = 0;
    switch (wasi.fd_pwrite(@intCast(fd), iov, @intCast(iovcnt), @intCast(offset), &nwritten)) {
        .SUCCESS => return @intCast(nwritten),
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn fstatWasi(fd: c_int, buf: *std.c.Stat) callconv(.c) c_int {
    var internal_stat: wasi.filestat_t = undefined;
    switch (wasi.fd_filestat_get(@intCast(fd), &internal_stat)) {
        .SUCCESS => {
            buf.* = std.c.Stat.fromFilestat(internal_stat);
            return 0;
        },
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn fstatatWasi(fd: c_int, path: [*]const u8, buf: *std.c.Stat, flag: c_int) callconv(.c) c_int {
    const AT_SYMLINK_NOFOLLOW = 0x100;
    const path_len = std.mem.len(path);
    var lookup_flags = wasi.lookupflags_t{};
    if ((flag & AT_SYMLINK_NOFOLLOW) == 0)
        lookup_flags.SYMLINK_FOLLOW = true;

    var internal_stat: wasi.filestat_t = undefined;
    switch (wasi.path_filestat_get(@intCast(fd), lookup_flags, path, path_len, &internal_stat)) {
        .SUCCESS => {
            buf.* = std.c.Stat.fromFilestat(internal_stat);
            return 0;
        },
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn futimensWasi(fd: c_int, times: ?[*]const std.c.timespec) callconv(.c) c_int {
    var st_atim: wasi.timestamp_t = 0;
    var st_mtim: wasi.timestamp_t = 0;
    var flags = wasi.fstflags_t{};

    if (times) |ts| {
        if (!utimensGetTimestamps(ts, &st_atim, &st_mtim, &flags)) {
            setErrno(.INVAL);
            return -1;
        }
    } else {
        flags = .{ .ATIM_NOW = true, .MTIM_NOW = true };
    }

    switch (wasi.fd_filestat_set_times(@intCast(fd), st_atim, st_mtim, flags)) {
        .SUCCESS => return 0,
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn mkdiratWasi(fd: c_int, path: [*]const u8) callconv(.c) c_int {
    const path_len = std.mem.len(path);
    switch (wasi.path_create_directory(@intCast(fd), path, path_len)) {
        .SUCCESS => return 0,
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn utimensatWasi(fd: c_int, path: [*]const u8, times: ?[*]const std.c.timespec, flag: c_int) callconv(.c) c_int {
    var st_atim: wasi.timestamp_t = 0;
    var st_mtim: wasi.timestamp_t = 0;
    var flags = wasi.fstflags_t{};

    if (times) |ts| {
        if (!utimensGetTimestamps(ts, &st_atim, &st_mtim, &flags)) {
            setErrno(.INVAL);
            return -1;
        }
    } else {
        flags = .{ .ATIM_NOW = true, .MTIM_NOW = true };
    }

    const AT_SYMLINK_NOFOLLOW = 0x100;
    const path_len = std.mem.len(path);
    var lookup_flags = wasi.lookupflags_t{};
    if ((flag & AT_SYMLINK_NOFOLLOW) == 0)
        lookup_flags.SYMLINK_FOLLOW = true;

    switch (wasi.path_filestat_set_times(@intCast(fd), lookup_flags, path, path_len, st_atim, st_mtim, flags)) {
        .SUCCESS => return 0,
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn recvWasi(socket: c_int, buffer: [*]u8, length: usize, flags_arg: c_int) callconv(.c) isize {
    const MSG_PEEK = 0x2;
    const MSG_WAITALL = 0x100;
    if ((flags_arg & ~@as(c_int, MSG_PEEK | MSG_WAITALL)) != 0) {
        setErrno(.OPNOTSUPP);
        return -1;
    }

    const iov = wasi.iovec_t{ .buf = buffer, .buf_len = length };
    var ro_datalen: usize = 0;
    var ro_flags: wasi.roflags_t = 0;
    switch (wasi.sock_recv(@intCast(socket), @ptrCast(&iov), 1, @intCast(flags_arg), &ro_datalen, &ro_flags)) {
        .SUCCESS => return @intCast(ro_datalen),
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn sendWasi(socket: c_int, buffer: [*]const u8, length: usize, flags_arg: c_int) callconv(.c) isize {
    if (flags_arg != 0) {
        setErrno(.OPNOTSUPP);
        return -1;
    }

    const iov = wasi.ciovec_t{ .buf = buffer, .buf_len = length };
    var so_datalen: usize = 0;
    switch (wasi.sock_send(@intCast(socket), @ptrCast(&iov), 1, 0, &so_datalen)) {
        .SUCCESS => return @intCast(so_datalen),
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn shutdownWasi(socket: c_int, how: c_int) callconv(.c) c_int {
    const SHUT_RD = 1;
    const SHUT_WR = 2;
    const SHUT_RDWR = 3;
    if (how != SHUT_RD and how != SHUT_WR and how != SHUT_RDWR) {
        setErrno(.INVAL);
        return -1;
    }

    switch (wasi.sock_shutdown(@intCast(socket), @bitCast(@as(u8, @intCast(how))))) {
        .SUCCESS => return 0,
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn getsockoptWasi(socket: c_int, level: c_int, option_name: c_int, option_value: ?[*]u8, option_len: ?*u32) callconv(.c) c_int {
    const SOL_SOCKET = 1;
    const SO_TYPE = 3;

    if (level != SOL_SOCKET) {
        setErrno(.NOPROTOOPT);
        return -1;
    }

    var value: c_int = 0;
    switch (option_name) {
        SO_TYPE => {
            var fsb: wasi.fdstat_t = undefined;
            if (wasi.fd_fdstat_get(@intCast(socket), &fsb) != .SUCCESS) {
                setErrno(.BADF);
                return -1;
            }
            if (fsb.fs_filetype != .SOCKET_DGRAM and fsb.fs_filetype != .SOCKET_STREAM) {
                setErrno(.NOTSOCK);
                return -1;
            }
            value = @intFromEnum(fsb.fs_filetype);
        },
        else => {
            setErrno(.NOPROTOOPT);
            return -1;
        },
    }

    if (option_value) |ov| {
        if (option_len) |ol| {
            const copy_len = if (ol.* < @sizeOf(c_int)) ol.* else @sizeOf(c_int);
            const src: [*]const u8 = @ptrCast(&value);
            @memcpy(ov[0..copy_len], src[0..copy_len]);
            ol.* = @sizeOf(c_int);
        }
    }
    return 0;
}

fn clockGetresWasi(clock_id_ptr: *const CClockId, res: *std.c.timespec) callconv(.c) c_int {
    var ts: wasi.timestamp_t = 0;
    switch (wasi.clock_res_get(clock_id_ptr.id, &ts)) {
        .SUCCESS => {
            res.* = std.c.timespec.fromTimestamp(ts);
            return 0;
        },
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn clockGettimeWasi(clock_id_ptr: *const CClockId, tp: *std.c.timespec) callconv(.c) c_int {
    var ts: wasi.timestamp_t = 0;
    switch (wasi.clock_time_get(clock_id_ptr.id, 1, &ts)) {
        .SUCCESS => {
            tp.* = std.c.timespec.fromTimestamp(ts);
            return 0;
        },
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

/// Internal implementation that takes a raw clock ID (not the C pointer type).
fn clockNanosleepImpl(clock_id: wasi.clockid_t, flags_arg: c_int, rqtp: *const std.c.timespec) c_int {
    const TIMER_ABSTIME = 1;
    if ((flags_arg & ~@as(c_int, TIMER_ABSTIME)) != 0)
        return @intFromEnum(E.INVAL);

    const timeout = timespecToTimestampClamp(rqtp) orelse return @intFromEnum(E.INVAL);

    var sub = std.mem.zeroes(wasi.subscription_t);
    sub.u.tag = .CLOCK;
    sub.u.u.clock.id = clock_id;
    sub.u.u.clock.timeout = timeout;
    sub.u.u.clock.flags = @intCast(flags_arg);

    var nevents: usize = 0;
    var ev: wasi.event_t = undefined;
    const rc = wasi.poll_oneoff(&sub, &ev, 1, &nevents);
    if (rc == .SUCCESS and ev.@"error" == .SUCCESS) return 0;
    return @intFromEnum(E.NOTSUP);
}

/// C ABI wrapper that accepts the C clockid_t pointer.
fn clockNanosleepWasi(clock_id_ptr: *const CClockId, flags_arg: c_int, rqtp: *const std.c.timespec, _: ?*std.c.timespec) callconv(.c) c_int {
    return clockNanosleepImpl(clock_id_ptr.id, flags_arg, rqtp);
}

fn nanosleepWasi(rqtp: *const std.c.timespec, rmtp: ?*std.c.timespec) callconv(.c) c_int {
    _ = rmtp;
    const err = clockNanosleepImpl(.REALTIME, 0, rqtp);
    if (err != 0) {
        setErrno(@enumFromInt(err));
        return -1;
    }
    return 0;
}

fn timeWasi(tloc: ?*i64) callconv(.c) i64 {
    var ts: wasi.timestamp_t = 0;
    _ = wasi.clock_time_get(.REALTIME, NSEC_PER_SEC, &ts);
    const result: i64 = @intCast(ts / NSEC_PER_SEC);
    if (tloc) |p| p.* = result;
    return result;
}

fn gettimeofdayWasi(tp: ?*timeval, _: ?*anyopaque) callconv(.c) c_int {
    if (tp) |p| {
        var ts: wasi.timestamp_t = 0;
        _ = wasi.clock_time_get(.REALTIME, 1000, &ts);
        p.sec = @intCast(ts / NSEC_PER_SEC);
        p.usec = @intCast((ts % NSEC_PER_SEC) / 1000);
    }
    return 0;
}

fn schedYieldWasi() callconv(.c) c_int {
    switch (wasi.sched_yield()) {
        .SUCCESS => return 0,
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn renameatWasi(oldfd: c_int, old: [*]const u8, newfd: c_int, new: [*]const u8) callconv(.c) c_int {
    const old_len = std.mem.len(old);
    const new_len = std.mem.len(new);
    switch (wasi.path_rename(@intCast(oldfd), old, old_len, @intCast(newfd), new, new_len)) {
        .SUCCESS => return 0,
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

fn timespecToTimestampClamp(ts: *const std.c.timespec) ?wasi.timestamp_t {
    if (ts.nsec < 0 or ts.nsec >= @as(isize, @intCast(NSEC_PER_SEC)))
        return null;
    if (ts.sec < 0)
        return 0;
    const sec_ns = std.math.mul(u64, @intCast(ts.sec), NSEC_PER_SEC) catch return std.math.maxInt(u64);
    return std.math.add(u64, sec_ns, @intCast(ts.nsec)) catch std.math.maxInt(u64);
}

fn timespecToTimestampExact(ts: *const std.c.timespec) ?wasi.timestamp_t {
    if (ts.nsec < 0 or ts.nsec >= @as(isize, @intCast(NSEC_PER_SEC)))
        return null;
    if (ts.sec < 0)
        return null;
    const sec_ns = std.math.mul(u64, @intCast(ts.sec), NSEC_PER_SEC) catch return null;
    return std.math.add(u64, sec_ns, @intCast(ts.nsec)) catch null;
}

fn utimensGetTimestamps(
    times: [*]const std.c.timespec,
    st_atim: *wasi.timestamp_t,
    st_mtim: *wasi.timestamp_t,
    flags: *wasi.fstflags_t,
) bool {
    const UTIME_NOW: isize = -1;
    const UTIME_OMIT: isize = -2;

    flags.* = .{};

    switch (times[0].nsec) {
        UTIME_NOW => {
            flags.ATIM_NOW = true;
            st_atim.* = 0;
        },
        UTIME_OMIT => {
            st_atim.* = 0;
        },
        else => {
            flags.ATIM = true;
            st_atim.* = timespecToTimestampExact(&times[0]) orelse return false;
        },
    }

    switch (times[1].nsec) {
        UTIME_NOW => {
            flags.MTIM_NOW = true;
            st_mtim.* = 0;
        },
        UTIME_OMIT => {
            st_mtim.* = 0;
        },
        else => {
            flags.MTIM = true;
            st_mtim.* = timespecToTimestampExact(&times[1]) orelse return false;
        },
    }

    return true;
}

/// Grow a buffer (via realloc) to at least `target_size`.
/// Returns null on allocation failure.
fn grow(buf: ?[*]u8, buf_size: *usize, target_size: usize) ?[*]u8 {
    if (buf_size.* >= target_size) return buf;
    var new_size = buf_size.*;
    while (new_size < target_size) new_size *= 2;
    const new_buf = c_realloc(@ptrCast(buf), new_size) orelse return null;
    buf_size.* = new_size;
    return new_buf;
}

fn exitWasi(status: c_int) callconv(.c) noreturn {
    wasi.proc_exit(@bitCast(status));
}

fn dirfdWasi(dirp: *DIR) callconv(.c) c_int {
    return dirp.fd;
}

fn telldirWasi(dirp: *DIR) callconv(.c) c_long {
    return @bitCast(@as(c_ulong, @truncate(dirp.cookie)));
}

fn seekdirWasi(dirp: *DIR, loc: c_long) callconv(.c) void {
    dirp.cookie = @as(c_ulong, @bitCast(loc));
    dirp.buffer_used = dirp.buffer_size;
    dirp.buffer_processed = dirp.buffer_size;
}

fn rewinddirWasi(dirp: *DIR) callconv(.c) void {
    dirp.cookie = wasi.DIRCOOKIE_START;
    dirp.buffer_used = dirp.buffer_size;
    dirp.buffer_processed = dirp.buffer_size;
}

fn fdclosedirWasi(dirp: *DIR) callconv(.c) c_int {
    const fd = dirp.fd;
    c_free(@ptrCast(dirp.buffer));
    c_free(@ptrCast(dirp.dirent_ptr));
    c_free(@ptrCast(dirp));
    return fd;
}

fn closedirWasi(dirp: *DIR) callconv(.c) c_int {
    return c_close(fdclosedirWasi(dirp));
}

fn fdopendirWasi(fd: c_int) callconv(.c) ?*DIR {
    const dirp: *DIR = @ptrCast(@alignCast(c_malloc(@sizeOf(DIR)) orelse return null));
    dirp.buffer = c_malloc(DIRENT_DEFAULT_BUFFER_SIZE) orelse {
        c_free(@ptrCast(dirp));
        return null;
    };

    // Load the first chunk to verify this is a directory.
    switch (wasi.fd_readdir(fd, dirp.buffer.?, DIRENT_DEFAULT_BUFFER_SIZE, wasi.DIRCOOKIE_START, &dirp.buffer_used)) {
        .SUCCESS => {},
        else => |err| {
            c_free(@ptrCast(dirp.buffer));
            c_free(@ptrCast(dirp));
            setErrno(err);
            return null;
        },
    }

    dirp.fd = fd;
    dirp.cookie = wasi.DIRCOOKIE_START;
    dirp.buffer_processed = 0;
    dirp.buffer_size = DIRENT_DEFAULT_BUFFER_SIZE;
    dirp.dirent_ptr = null;
    dirp.dirent_size = 1;
    return dirp;
}

fn opendiratWasi(dir: c_int, dirname: [*:0]const u8) callconv(.c) ?*DIR {
    const fd = c_openat_nomode(dir, dirname, O_RDONLY | O_NONBLOCK | O_DIRECTORY);
    if (fd == -1) return null;

    const result = fdopendirWasi(fd);
    if (result == null) _ = c_close(fd);
    return result;
}

fn readdirWasi(dirp: *DIR) callconv(.c) ?*anyopaque {
    while (true) {
        const buffer_left = dirp.buffer_used - dirp.buffer_processed;
        if (buffer_left < @sizeOf(wasi.dirent_t)) {
            if (dirp.buffer_used < dirp.buffer_size) return null;
            readEntries(dirp) orelse return null;
            continue;
        }

        // Extract the dirent header.
        var entry: wasi.dirent_t = undefined;
        const entry_bytes: [*]const u8 = @ptrCast(&entry);
        const src = dirp.buffer.?[dirp.buffer_processed..][0..@sizeOf(wasi.dirent_t)];
        @memcpy(@constCast(entry_bytes[0..@sizeOf(wasi.dirent_t)]), src);

        const entry_size = @sizeOf(wasi.dirent_t) + entry.namlen;
        if (entry.namlen == 0) {
            dirp.buffer_processed += entry_size;
            continue;
        }

        // Ensure the full entry is in the buffer.
        if (buffer_left < entry_size) {
            dirp.buffer = grow(dirp.buffer, &dirp.buffer_size, entry_size) orelse return null;
            readEntries(dirp) orelse return null;
            continue;
        }

        // Skip entries with null bytes in the filename.
        const name = dirp.buffer.?[dirp.buffer_processed + @sizeOf(wasi.dirent_t) ..][0..entry.namlen];
        if (std.mem.indexOfScalar(u8, name, 0) != null) {
            dirp.buffer_processed += entry_size;
            continue;
        }

        // Ensure the dirent buffer is large enough for the filename.
        const needed = DIRENT_D_NAME_OFFSET + entry.namlen + 1;
        dirp.dirent_ptr = grow(dirp.dirent_ptr, &dirp.dirent_size, needed) orelse return null;
        const dirent_bytes = dirp.dirent_ptr.?;

        // Write d_type.
        dirent_bytes[8] = @intFromEnum(entry.type);
        // Write d_name.
        @memcpy(dirent_bytes[DIRENT_D_NAME_OFFSET..][0..entry.namlen], name);
        dirent_bytes[DIRENT_D_NAME_OFFSET + entry.namlen] = 0;

        // Resolve inode number if unknown.
        var d_ino: u64 = entry.ino;
        var d_type: u8 = @intFromEnum(entry.type);
        if (d_ino == 0) {
            // Check if this is ".." which we can't stat.
            const d_name_slice = dirent_bytes[DIRENT_D_NAME_OFFSET..][0..entry.namlen];
            if (!std.mem.eql(u8, d_name_slice, "..")) {
                var filestat: wasi.filestat_t = undefined;
                switch (wasi.path_filestat_get(dirp.fd, .{}, name.ptr, name.len, &filestat)) {
                    .SUCCESS => {
                        d_ino = filestat.ino;
                        d_type = @intFromEnum(filestat.filetype);
                    },
                    .NOENT => {
                        // File disappeared, skip it.
                        dirp.buffer_processed += entry_size;
                        continue;
                    },
                    else => return null,
                }
            }
        }

        // Write d_ino (u64, offset 0).
        @as(*align(1) u64, @ptrCast(dirent_bytes)).* = d_ino;
        // Update d_type in case it was resolved via stat.
        dirent_bytes[8] = d_type;

        dirp.cookie = entry.next;
        dirp.buffer_processed += entry_size;
        return @ptrCast(dirent_bytes);
    }
}

fn readEntries(dirp: *DIR) ?void {
    dirp.buffer_used = dirp.buffer_size;
    dirp.buffer_processed = dirp.buffer_size;
    switch (wasi.fd_readdir(dirp.fd, dirp.buffer.?, dirp.buffer_size, dirp.cookie, &dirp.buffer_used)) {
        .SUCCESS => {
            dirp.buffer_processed = 0;
        },
        else => |err| {
            setErrno(err);
            return null;
        },
    }
}

fn scandiratWasi(
    dirfd: c_int,
    dir: [*:0]const u8,
    namelist: *?[*]*anyopaque,
    sel: ?*const fn (*const anyopaque) callconv(.c) c_int,
    compar: *const fn (*const anyopaque, *const anyopaque) callconv(.c) c_int,
) callconv(.c) c_int {
    const fd = c_openat_nomode(dirfd, dir, O_RDONLY | O_NONBLOCK | O_DIRECTORY);
    if (fd == -1) return -1;

    var buffer_size: usize = DIRENT_DEFAULT_BUFFER_SIZE;
    var buffer: ?[*]u8 = @ptrCast(c_malloc(buffer_size));
    if (buffer == null) {
        _ = c_close(fd);
        return -1;
    }
    var buffer_processed: usize = buffer_size;
    var buffer_used: usize = buffer_size;

    var dirents: ?[*]*anyopaque = null;
    var dirents_size: usize = 0;
    var dirents_used: usize = 0;

    var cookie: wasi.dircookie_t = wasi.DIRCOOKIE_START;
    var done = false;
    while (!done) {
        const buffer_left = buffer_used - buffer_processed;
        if (buffer_left < @sizeOf(wasi.dirent_t)) {
            if (buffer_used < buffer_size) {
                done = true;
                continue;
            }
            // Read more entries.
            switch (wasi.fd_readdir(fd, buffer.?, buffer_size, cookie, &buffer_used)) {
                .SUCCESS => buffer_processed = 0,
                else => |err| {
                    setErrno(err);
                    scandiratFree(dirents, dirents_used);
                    c_free(@ptrCast(buffer));
                    _ = c_close(fd);
                    return -1;
                },
            }
            continue;
        }

        var entry: wasi.dirent_t = undefined;
        const entry_ptr: [*]u8 = @ptrCast(&entry);
        @memcpy(entry_ptr[0..@sizeOf(wasi.dirent_t)], buffer.?[buffer_processed..][0..@sizeOf(wasi.dirent_t)]);

        const entry_size = @sizeOf(wasi.dirent_t) + entry.namlen;
        if (entry.namlen == 0) {
            buffer_processed += entry_size;
            continue;
        }

        if (buffer_left < entry_size) {
            while (buffer_size < entry_size) buffer_size *= 2;
            buffer = @ptrCast(c_realloc(@ptrCast(buffer), buffer_size) orelse {
                scandiratFree(dirents, dirents_used);
                c_free(@ptrCast(buffer));
                _ = c_close(fd);
                return -1;
            });
            // Read entries again with larger buffer.
            switch (wasi.fd_readdir(fd, buffer.?, buffer_size, cookie, &buffer_used)) {
                .SUCCESS => buffer_processed = 0,
                else => |err| {
                    setErrno(err);
                    scandiratFree(dirents, dirents_used);
                    c_free(@ptrCast(buffer));
                    _ = c_close(fd);
                    return -1;
                },
            }
            continue;
        }

        const name = buffer.?[buffer_processed + @sizeOf(wasi.dirent_t) ..][0..entry.namlen];
        buffer_processed += entry_size;

        // Skip entries with null bytes in the filename.
        if (std.mem.indexOfScalar(u8, name, 0) != null) continue;

        // Allocate a new dirent.
        const alloc_size = DIRENT_D_NAME_OFFSET + entry.namlen + 1;
        const dirent_bytes: [*]u8 = @ptrCast(c_malloc(alloc_size) orelse {
            scandiratFree(dirents, dirents_used);
            c_free(@ptrCast(buffer));
            _ = c_close(fd);
            return -1;
        });

        dirent_bytes[8] = @intFromEnum(entry.type);
        @memcpy(dirent_bytes[DIRENT_D_NAME_OFFSET..][0..entry.namlen], name);
        dirent_bytes[DIRENT_D_NAME_OFFSET + entry.namlen] = 0;

        // Resolve inode if unknown.
        var d_ino: u64 = entry.ino;
        var d_type: u8 = @intFromEnum(entry.type);
        if (d_ino == 0) {
            var filestat: wasi.filestat_t = undefined;
            switch (wasi.path_filestat_get(fd, .{}, name.ptr, name.len, &filestat)) {
                .SUCCESS => {
                    d_ino = filestat.ino;
                    d_type = @intFromEnum(filestat.filetype);
                },
                else => {
                    c_free(@ptrCast(dirent_bytes));
                    scandiratFree(dirents, dirents_used);
                    c_free(@ptrCast(buffer));
                    _ = c_close(fd);
                    return -1;
                },
            }
        }
        @as(*align(1) u64, @ptrCast(dirent_bytes)).* = d_ino;
        dirent_bytes[8] = d_type;

        cookie = entry.next;

        // Apply selection filter.
        const selected = if (sel) |sel_fn| sel_fn(@ptrCast(dirent_bytes)) != 0 else true;
        if (selected) {
            // Grow dirents array if needed.
            if (dirents_used == dirents_size) {
                dirents_size = if (dirents_size < 8) 8 else dirents_size * 2;
                const new_dirents: ?[*]*anyopaque = @ptrCast(@alignCast(c_realloc(
                    @ptrCast(dirents),
                    dirents_size * @sizeOf(*anyopaque),
                )));
                if (new_dirents == null) {
                    c_free(@ptrCast(dirent_bytes));
                    scandiratFree(dirents, dirents_used);
                    c_free(@ptrCast(buffer));
                    _ = c_close(fd);
                    return -1;
                }
                dirents = new_dirents;
            }
            dirents.?[dirents_used] = @ptrCast(dirent_bytes);
            dirents_used += 1;
        } else {
            c_free(@ptrCast(dirent_bytes));
        }
    }

    // Sort and return results.
    c_free(@ptrCast(buffer));
    _ = c_close(fd);
    c_qsort(@ptrCast(dirents), dirents_used, @sizeOf(*anyopaque), compar);
    namelist.* = dirents;
    return @intCast(dirents_used);
}

fn scandiratFree(dirents: ?[*]*anyopaque, count: usize) void {
    if (dirents) |d| {
        for (d[0..count]) |entry| c_free(entry);
        c_free(@ptrCast(d));
    }
}

fn pollWasi(fds: ?[*]PollFd, nfds: usize, timeout: c_int) callconv(.c) c_int {
    return pollWasiP1(fds, nfds, timeout);
}

fn pollWasiP1(fds: ?[*]PollFd, nfds: usize, timeout: c_int) c_int {
    const max_subs = 2 * nfds + 1;
    if (max_subs == 0) {
        setErrno(.NOTSUP);
        return -1;
    }

    // Allocate subscription and event arrays.
    const subs_bytes = max_subs * @sizeOf(wasi.subscription_t);
    const subs_mem: [*]align(@alignOf(wasi.subscription_t)) u8 = @alignCast(c_malloc(subs_bytes) orelse {
        setErrno(.NOMEM);
        return -1;
    });
    const subs: [*]wasi.subscription_t = @ptrCast(subs_mem);
    defer c_free(@ptrCast(subs_mem));

    var nsubs: usize = 0;

    if (fds) |fds_ptr| {
        for (fds_ptr[0..nfds]) |*pollfd| {
            if (pollfd.fd < 0) continue;
            var created = false;
            if (pollfd.events & POLLRDNORM != 0) {
                subs[nsubs] = std.mem.zeroes(wasi.subscription_t);
                subs[nsubs].userdata = @intFromPtr(pollfd);
                subs[nsubs].u.tag = .FD_READ;
                subs[nsubs].u.u.fd_read.fd = pollfd.fd;
                nsubs += 1;
                created = true;
            }
            if (pollfd.events & POLLWRNORM != 0) {
                subs[nsubs] = std.mem.zeroes(wasi.subscription_t);
                subs[nsubs].userdata = @intFromPtr(pollfd);
                subs[nsubs].u.tag = .FD_WRITE;
                subs[nsubs].u.u.fd_write.fd = pollfd.fd;
                nsubs += 1;
                created = true;
            }
            if (!created) {
                setErrno(.NOSYS);
                return -1;
            }
        }
    }

    // Create timeout subscription if applicable.
    if (timeout >= 0) {
        subs[nsubs] = std.mem.zeroes(wasi.subscription_t);
        subs[nsubs].u.tag = .CLOCK;
        subs[nsubs].u.u.clock.id = .REALTIME;
        subs[nsubs].u.u.clock.timeout = @as(wasi.timestamp_t, @intCast(timeout)) * 1_000_000;
        nsubs += 1;
    }

    if (nsubs == 0) {
        setErrno(.NOTSUP);
        return -1;
    }

    // Allocate events array.
    const events_mem: [*]align(@alignOf(wasi.event_t)) u8 = @alignCast(c_malloc(nsubs * @sizeOf(wasi.event_t)) orelse {
        setErrno(.NOMEM);
        return -1;
    });
    const events: [*]wasi.event_t = @ptrCast(events_mem);
    defer c_free(@ptrCast(events_mem));

    var nevents: usize = 0;
    switch (wasi.poll_oneoff(&subs[0], &events[0], nsubs, &nevents)) {
        .SUCCESS => {},
        else => |err| {
            if (nsubs == 0)
                setErrno(.NOTSUP)
            else
                setErrno(err);
            return -1;
        },
    }

    // Clear revents.
    if (fds) |fds_ptr| {
        for (fds_ptr[0..nfds]) |*pollfd| pollfd.revents = 0;
    }

    // Set revents from events.
    for (events[0..nevents]) |*event| {
        if (event.type == .FD_READ or event.type == .FD_WRITE) {
            const pollfd: *PollFd = @ptrFromInt(event.userdata);
            if (event.@"error" == .BADF) {
                pollfd.revents |= POLLNVAL;
            } else if (event.@"error" == .PIPE) {
                pollfd.revents |= POLLHUP;
            } else if (event.@"error" != .SUCCESS) {
                pollfd.revents |= POLLERR;
            } else {
                if (event.type == .FD_READ) {
                    pollfd.revents |= POLLRDNORM;
                    if (event.fd_readwrite.flags & wasi.EVENT_FD_READWRITE_HANGUP != 0)
                        pollfd.revents |= POLLHUP;
                } else if (event.type == .FD_WRITE) {
                    pollfd.revents |= POLLWRNORM;
                    if (event.fd_readwrite.flags & wasi.EVENT_FD_READWRITE_HANGUP != 0)
                        pollfd.revents |= POLLHUP;
                }
            }
        }
    }

    // Count fds with non-zero revents.
    var retval: c_int = 0;
    if (fds) |fds_ptr| {
        for (fds_ptr[0..nfds]) |*pollfd| {
            if (pollfd.revents & POLLHUP != 0)
                pollfd.revents &= ~POLLWRNORM;
            if (pollfd.revents != 0)
                retval += 1;
        }
    }
    return retval;
}

fn pselectWasi(
    nfds: c_int,
    readfds: ?*FdSet,
    writefds: ?*FdSet,
    errorfds: ?*const FdSet,
    timeout: ?*const Timespec,
    _: ?*const u8, // sigset_t, unused on WASI
) callconv(.c) c_int {
    if (nfds < 0) {
        setErrno(.INVAL);
        return -1;
    }

    if (errorfds) |ef| {
        if (ef.__nfds > 0) {
            setErrno(.NOSYS);
            return -1;
        }
    }

    // Use empty sets for null pointers.
    var empty1 = std.mem.zeroes(FdSet);
    var empty2 = std.mem.zeroes(FdSet);
    const rds = readfds orelse &empty1;
    const wrs = writefds orelse &empty2;

    const poll_nfds_max = rds.__nfds + wrs.__nfds;
    const poll_fds_mem: ?[*]align(@alignOf(PollFd)) u8 = if (poll_nfds_max > 0)
        @alignCast(c_malloc(poll_nfds_max * @sizeOf(PollFd)) orelse {
            setErrno(.NOMEM);
            return -1;
        })
    else
        null;
    defer if (poll_fds_mem) |m| c_free(@ptrCast(m));

    const poll_fds: [*]PollFd = if (poll_fds_mem) |m| @ptrCast(m) else @as([*]PollFd, undefined);
    var poll_nfds: usize = 0;

    for (rds.__fds[0..rds.__nfds]) |fd| {
        if (fd < nfds) {
            poll_fds[poll_nfds] = PollFd{ .fd = fd, .events = POLLRDNORM, .revents = 0 };
            poll_nfds += 1;
        }
    }
    for (wrs.__fds[0..wrs.__nfds]) |fd| {
        if (fd < nfds) {
            poll_fds[poll_nfds] = PollFd{ .fd = fd, .events = POLLWRNORM, .revents = 0 };
            poll_nfds += 1;
        }
    }

    var poll_timeout: c_int = undefined;
    if (timeout) |ts| {
        if (ts.tv_nsec < 0 or ts.tv_nsec >= @as(c_long, @intCast(NSEC_PER_SEC))) {
            setErrno(.INVAL);
            return -1;
        }
        if (ts.tv_sec < 0) {
            poll_timeout = 0;
        } else {
            // Convert to milliseconds with clamping.
            const sec: u64 = @intCast(ts.tv_sec);
            const mul_result = @mulWithOverflow(sec, NSEC_PER_SEC);
            if (mul_result[1] != 0) {
                poll_timeout = std.math.maxInt(c_int);
            } else {
                const add_result = @addWithOverflow(mul_result[0], @as(u64, @intCast(ts.tv_nsec)));
                if (add_result[1] != 0) {
                    poll_timeout = std.math.maxInt(c_int);
                } else {
                    const ms = add_result[0] / 1_000_000;
                    poll_timeout = if (ms > @as(u64, @intCast(std.math.maxInt(c_int))))
                        std.math.maxInt(c_int)
                    else
                        @intCast(ms);
                }
            }
        }
    } else {
        poll_timeout = -1;
    }

    if (pollWasi(if (poll_nfds > 0) poll_fds else null, poll_nfds, poll_timeout) < 0)
        return -1;

    // Clear and rebuild fd sets.
    rds.__nfds = 0;
    wrs.__nfds = 0;
    for (0..poll_nfds) |i| {
        if (poll_fds[i].revents & POLLRDNORM != 0) {
            rds.__fds[rds.__nfds] = poll_fds[i].fd;
            rds.__nfds += 1;
        }
        if (poll_fds[i].revents & POLLWRNORM != 0) {
            wrs.__fds[wrs.__nfds] = poll_fds[i].fd;
            wrs.__nfds += 1;
        }
    }

    return @intCast(rds.__nfds + wrs.__nfds);
}

fn selectWasi(
    nfds: c_int,
    readfds: ?*FdSet,
    writefds: ?*FdSet,
    errorfds: ?*const FdSet,
    timeout: ?*Timeval,
) callconv(.c) c_int {
    if (timeout) |tv| {
        if (tv.tv_usec < 0 or tv.tv_usec >= 1_000_000) {
            setErrno(.INVAL);
            return -1;
        }
        const ts = Timespec{
            .tv_sec = tv.tv_sec,
            .tv_nsec = @intCast(tv.tv_usec * 1000),
        };
        return pselectWasi(nfds, readfds, writefds, errorfds, &ts, null);
    } else {
        return pselectWasi(nfds, readfds, writefds, errorfds, null, null);
    }
}

fn ioctlWasi(fildes: c_int, request: c_int, ...) callconv(.c) c_int {
    switch (request) {
        FIONREAD => {
            // Poll to determine bytes available for reading.
            var subs = [2]wasi.subscription_t{
                std.mem.zeroes(wasi.subscription_t),
                std.mem.zeroes(wasi.subscription_t),
            };
            subs[0].u.tag = .FD_READ;
            subs[0].u.u.fd_read.fd = fildes;
            subs[1].u.tag = .CLOCK;
            subs[1].u.u.clock.id = .MONOTONIC;

            var events: [2]wasi.event_t = undefined;
            var nevents: usize = 0;
            switch (wasi.poll_oneoff(&subs[0], &events[0], 2, &nevents)) {
                .SUCCESS => {},
                else => |err| {
                    setErrno(err);
                    return -1;
                },
            }

            var ap = @cVaStart();
            defer @cVaEnd(&ap);
            const result: *c_int = @cVaArg(&ap, *c_int);

            for (events[0..nevents]) |*event| {
                if (event.@"error" != .SUCCESS) {
                    setErrno(event.@"error");
                    return -1;
                }
                if (event.type == .FD_READ) {
                    result.* = @intCast(event.fd_readwrite.nbytes);
                    return 0;
                }
            }
            result.* = 0;
            return 0;
        },
        FIONBIO => {
            var fds: wasi.fdstat_t = undefined;
            switch (wasi.fd_fdstat_get(fildes, &fds)) {
                .SUCCESS => {},
                else => |err| {
                    setErrno(err);
                    return -1;
                },
            }

            var ap = @cVaStart();
            defer @cVaEnd(&ap);
            const val: *const c_int = @cVaArg(&ap, *const c_int);

            if (val.* != 0)
                fds.fs_flags.NONBLOCK = true
            else
                fds.fs_flags.NONBLOCK = false;

            switch (wasi.fd_fdstat_set_flags(fildes, fds.fs_flags)) {
                .SUCCESS => return 0,
                else => |err| {
                    setErrno(err);
                    return -1;
                },
            }
        },
        else => {
            setErrno(.INVAL);
            return -1;
        },
    }
}
