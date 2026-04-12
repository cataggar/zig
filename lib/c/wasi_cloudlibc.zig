/// WASI CloudLibc syscall wrappers migrated from C to Zig.
///
/// These functions were originally in lib/libc/wasi/libc-bottom-half/cloudlibc/src/libc/.
/// They wrap WASI preview1 syscalls to provide POSIX-compatible C library functions.
const builtin = @import("builtin");
const std = @import("std");
const wasi = std.os.wasi;

const symbol = @import("../c.zig").symbol;

const E = std.c.E;

fn setErrno(e: E) void {
    std.c._errno().* = @intFromEnum(e);
}

/// In WASI libc, clockid_t is `const struct __clockid *` (a pointer to a struct
/// containing the raw WASI clock ID). This differs from Zig's std.c.clockid_t.
const CClockId = extern struct { id: wasi.clockid_t };

// ═══════════════════════════════════════════════════════════════════════
// unistd
// ═══════════════════════════════════════════════════════════════════════

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

extern fn __wasilibc_rmdirat(fd: c_int, path: [*:0]const u8) c_int;
extern fn __wasilibc_unlinkat(fd: c_int, path: [*:0]const u8) c_int;

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

// ═══════════════════════════════════════════════════════════════════════
// fcntl
// ═══════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════
// sys/uio
// ═══════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════
// sys/stat
// ═══════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════
// sys/socket
// ═══════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════
// time
// ═══════════════════════════════════════════════════════════════════════

const NSEC_PER_SEC: u64 = 1_000_000_000;

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

// ═══════════════════════════════════════════════════════════════════════
// sys/time
// ═══════════════════════════════════════════════════════════════════════

const timeval = extern struct {
    sec: i64,
    usec: i64,
};

fn gettimeofdayWasi(tp: ?*timeval, _: ?*anyopaque) callconv(.c) c_int {
    if (tp) |p| {
        var ts: wasi.timestamp_t = 0;
        _ = wasi.clock_time_get(.REALTIME, 1000, &ts);
        p.sec = @intCast(ts / NSEC_PER_SEC);
        p.usec = @intCast((ts % NSEC_PER_SEC) / 1000);
    }
    return 0;
}

// ═══════════════════════════════════════════════════════════════════════
// sched
// ═══════════════════════════════════════════════════════════════════════

fn schedYieldWasi() callconv(.c) c_int {
    switch (wasi.sched_yield()) {
        .SUCCESS => return 0,
        else => |e| {
            setErrno(e);
            return -1;
        },
    }
}

// ═══════════════════════════════════════════════════════════════════════
// stdio
// ═══════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════
// Symbol exports
// ═══════════════════════════════════════════════════════════════════════

comptime {
    if (builtin.target.isWasiLibC()) {
        // unistd
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

        // fcntl
        symbol(&fcntlWasi, "fcntl");
        symbol(&openatWasi, "__wasilibc_nocwd_openat_nomode");
        symbol(&posixFadviseWasi, "posix_fadvise");
        symbol(&posixFallocateWasi, "posix_fallocate");

        // sys/uio
        symbol(&readvWasi, "readv");
        symbol(&writevWasi, "writev");
        symbol(&preadvWasi, "preadv");
        symbol(&pwritevWasi, "pwritev");

        // sys/stat
        symbol(&fstatWasi, "fstat");
        symbol(&fstatatWasi, "__wasilibc_nocwd_fstatat");
        symbol(&futimensWasi, "futimens");
        symbol(&mkdiratWasi, "__wasilibc_nocwd_mkdirat_nomode");
        symbol(&utimensatWasi, "__wasilibc_nocwd_utimensat");

        // sys/socket
        symbol(&recvWasi, "recv");
        symbol(&sendWasi, "send");
        symbol(&shutdownWasi, "shutdown");
        symbol(&getsockoptWasi, "getsockopt");

        // time
        symbol(&clockGetresWasi, "clock_getres");
        symbol(&clockGettimeWasi, "__clock_gettime");
        symbol(&clockGettimeWasi, "clock_gettime");
        symbol(&clockNanosleepWasi, "clock_nanosleep");
        symbol(&clockNanosleepWasi, "__clock_nanosleep");
        symbol(&nanosleepWasi, "nanosleep");
        symbol(&timeWasi, "time");

        // sys/time
        symbol(&gettimeofdayWasi, "gettimeofday");

        // sched
        symbol(&schedYieldWasi, "sched_yield");

        // stdio
        symbol(&renameatWasi, "__wasilibc_nocwd_renameat");
    }
}
