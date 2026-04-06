const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&mkdirLinux, "mkdir");
        symbol(&mkdiratLinux, "mkdirat");
        symbol(&mknodLinux, "mknod");
        symbol(&mknodatLinux, "mknodat");
        symbol(&mkfifoLinux, "mkfifo");
        symbol(&mkfifoatLinux, "mkfifoat");
        symbol(&umaskLinux, "umask");
        symbol(&chmodLinux, "chmod");
        symbol(&fchmodatLinux, "fchmodat");
        symbol(&statfsLinux, "statfs");
        symbol(&statfsLinux, "__statfs");
        symbol(&fstatfsLinux, "fstatfs");
        symbol(&fstatfsLinux, "__fstatfs");
        symbol(&statvfsLinux, "statvfs");
        symbol(&fstatvfsLinux, "fstatvfs");
        symbol(&fchmodLinux, "fchmod");
        if (builtin.link_libc) {
            symbol(&fstatatImpl, "fstatat");
            symbol(&fstatatImpl, "__fstatat");
            symbol(&statLinux, "stat");
            symbol(&lstatLinux, "lstat");
            symbol(&fstatLinux, "__fstat");
            symbol(&fstatLinux, "fstat");
            symbol(&futimensLinux, "futimens");
            symbol(&lchmodLinux, "lchmod");
            symbol(&__futimesat, "__futimesat");
            symbol(&__futimesat, "futimesat");
            symbol(&utimensatLinux, "utimensat");
            symbol(&__fxstat, "__fxstat");
            symbol(&__fxstatat, "__fxstatat");
            symbol(&__lxstat, "__lxstat");
            symbol(&__xstat_fn, "__xstat");
            symbol(&__xmknod, "__xmknod");
            symbol(&__xmknodat, "__xmknodat");
        }
    }
}

// --- Direct syscall wrappers ---

fn mkdirLinux(path: [*:0]const u8, mode: linux.mode_t) callconv(.c) c_int {
    return errno(linux.mkdirat(linux.AT.FDCWD, path, mode));
}
fn mkdiratLinux(fd: c_int, path: [*:0]const u8, mode: linux.mode_t) callconv(.c) c_int {
    return errno(linux.mkdirat(fd, path, mode));
}
fn mknodLinux(path: [*:0]const u8, mode: linux.mode_t, dev: linux.dev_t) callconv(.c) c_int {
    return errno(linux.mknodat(linux.AT.FDCWD, path, mode, @truncate(dev)));
}
fn mknodatLinux(fd: c_int, path: [*:0]const u8, mode: linux.mode_t, dev: linux.dev_t) callconv(.c) c_int {
    return errno(linux.mknodat(fd, path, mode, @truncate(dev)));
}
fn mkfifoLinux(path: [*:0]const u8, mode: linux.mode_t) callconv(.c) c_int {
    return errno(linux.mknodat(linux.AT.FDCWD, path, mode | linux.S.IFIFO, 0));
}
fn mkfifoatLinux(fd: c_int, path: [*:0]const u8, mode: linux.mode_t) callconv(.c) c_int {
    return errno(linux.mknodat(fd, path, mode | linux.S.IFIFO, 0));
}
fn umaskLinux(mode: linux.mode_t) callconv(.c) linux.mode_t {
    return @truncate(linux.syscall1(.umask, mode));
}
fn chmodLinux(path: [*:0]const u8, mode: linux.mode_t) callconv(.c) c_int {
    return errno(linux.fchmodat(linux.AT.FDCWD, path, mode));
}

/// fchmod with /proc/self/fd fallback for O_PATH fds.
fn fchmodLinux(fd: c_int, mode: linux.mode_t) callconv(.c) c_int {
    const ret: isize = @bitCast(linux.fchmod(fd, mode));
    if (ret != -@as(isize, @intFromEnum(linux.E.BADF)) or
        @as(isize, @bitCast(linux.fcntl(fd, linux.F.GETFD, 0))) < 0)
    {
        if (ret >= 0) return 0;
        std.c._errno().* = @intCast(-ret);
        return -1;
    }
    // Fall back to /proc/self/fd/N path
    var buf: [32]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "/proc/self/fd/{d}\x00", .{@as(u32, @intCast(fd))}) catch return -1;
    return errno(linux.fchmodat(linux.AT.FDCWD, @ptrCast(path.ptr), mode));
}

fn utimensatLinux(fd: c_int, path: ?[*:0]const u8, times: ?*const [2]linux.timespec, flags: c_int) callconv(.c) c_int {
    return errno(linux.utimensat(fd, if (path) |p| @ptrCast(p) else null, if (times) |t| t else null, @bitCast(flags)));
}

// --- fstatat implementation (replaces musl/src/stat/fstatat.c) ---

fn makedev(major: u32, minor: u32) u64 {
    const x: u64 = major;
    const y: u64 = minor;
    return ((x & 0xfffff000) << 32) | ((x & 0x00000fff) << 8) |
        ((y & 0xffffff00) << 12) | (y & 0x000000ff);
}

/// Musl-ABI time64 timespec, matching the C struct layout for all arches.
const Ts = if (@sizeOf(isize) >= 8)
    extern struct { sec: i64, nsec: i64 }
else if (builtin.cpu.arch.endian() == .little)
    extern struct { sec: i64, nsec: i32, _p: u32 = 0 }
else
    extern struct { sec: i64, _p: u32 = 0, nsec: i32 };

/// Time32 timespec for old 32-bit stat layouts.
const Ts32 = extern struct { sec: i32, nsec: i32 };

/// Returns true for arches where kernel kstat matches musl stat (direct fstatat64 works).
fn kstatMatchesStat() bool {
    const abi = builtin.target.abi;
    if (abi == .muslx32) return true;
    return switch (builtin.cpu.arch) {
        .x86_64, .aarch64, .aarch64_be, .riscv64, .loongarch64,
        .powerpc64, .powerpc64le, .s390x => true,
        else => false,
    };
}

/// Musl-ABI struct stat, architecture-specific layout.
const MuStat = muStatType();

fn muStatType() type {
    // 64-bit arches where kstat matches stat use direct syscall, no struct needed.
    // But mips64 (and n32 ABI) needs statx, so define structs for those.
    const arch = builtin.cpu.arch;
    const abi = builtin.target.abi;
    if (abi == .muslabin32) return MuStatMipsN32; // mipsn32
    return switch (arch) {
        // Generic layout: aarch64, hexagon, loongarch64, riscv32, riscv64
        .aarch64, .aarch64_be, .hexagon, .loongarch64, .riscv32, .riscv64 => extern struct {
            dev: u64, ino: u64, mode: u32, nlink: u32, uid: u32, gid: u32,
            rdev: u64, __pad: u64 = 0, size: i64, blksize: i32, __pad2: i32 = 0,
            blocks: i64, atim: Ts, mtim: Ts, ctim: Ts, __unused: [2]u32 = .{ 0, 0 },
        },
        .x86_64 => extern struct {
            dev: u64, ino: u64, nlink: u64, mode: u32, uid: u32, gid: u32,
            __pad0: u32 = 0, rdev: u64, size: i64, blksize: i64, blocks: i64,
            atim: Ts, mtim: Ts, ctim: Ts, __unused: [3]i64 = .{ 0, 0, 0 },
        },
        .powerpc64, .powerpc64le => extern struct {
            dev: u64, ino: u64, nlink: u64, mode: u32, uid: u32, gid: u32,
            __pad0: u32 = 0, rdev: u64, size: i64, blksize: i64, blocks: i64,
            atim: Ts, mtim: Ts, ctim: Ts, __unused: [3]u64 = .{ 0, 0, 0 },
        },
        .s390x => extern struct {
            dev: u64, ino: u64, nlink: u64, mode: u32, uid: u32, gid: u32,
            __pad0: u32 = 0, rdev: u64, size: i64,
            atim: Ts, mtim: Ts, ctim: Ts,
            blksize: i64, blocks: i64, __unused: [3]u64 = .{ 0, 0, 0 },
        },
        .mips64, .mips64el => extern struct {
            dev: u64, __pad1: [3]i32 = .{ 0, 0, 0 },
            ino: u64, mode: u32, nlink: u32, uid: u32, gid: u32,
            rdev: u64, __pad2: [2]u32 = .{ 0, 0 }, size: i64, __pad3: i32 = 0,
            atim: Ts, mtim: Ts, ctim: Ts,
            blksize: i64, __pad4: u32 = 0, blocks: i64, __pad5: [14]i32 = .{0} ** 14,
        },
        .arm, .armeb, .thumb, .thumbeb, .x86 => extern struct {
            dev: u64, __dev_pad: i32 = 0, ino_truncated: i32 = 0,
            mode: u32, nlink: u32, uid: u32, gid: u32,
            rdev: u64, __rdev_pad: i32 = 0,
            size: i64, blksize: i32, blocks: i64,
            atim32: Ts32 = .{ .sec = 0, .nsec = 0 },
            mtim32: Ts32 = .{ .sec = 0, .nsec = 0 },
            ctim32: Ts32 = .{ .sec = 0, .nsec = 0 },
            ino: u64, atim: Ts, mtim: Ts, ctim: Ts,
        },
        .m68k => extern struct {
            dev: u64, __dev_pad: i16 = 0, ino_truncated: i32 = 0,
            mode: u32, nlink: u32, uid: u32, gid: u32,
            rdev: u64, __rdev_pad: i16 = 0,
            size: i64, blksize: i32, blocks: i64,
            atim32: Ts32 = .{ .sec = 0, .nsec = 0 },
            mtim32: Ts32 = .{ .sec = 0, .nsec = 0 },
            ctim32: Ts32 = .{ .sec = 0, .nsec = 0 },
            ino: u64, atim: Ts, mtim: Ts, ctim: Ts,
        },
        .mips, .mipsel => extern struct {
            dev: u64, __pad1: [2]i32 = .{ 0, 0 },
            ino: u64, mode: u32, nlink: u32, uid: u32, gid: u32,
            rdev: u64, __pad2: [2]i32 = .{ 0, 0 }, size: i64,
            atim32: Ts32 = .{ .sec = 0, .nsec = 0 },
            mtim32: Ts32 = .{ .sec = 0, .nsec = 0 },
            ctim32: Ts32 = .{ .sec = 0, .nsec = 0 },
            blksize: i32, __pad3: i32 = 0, blocks: i64,
            atim: Ts, mtim: Ts, ctim: Ts, __pad4: [2]i32 = .{ 0, 0 },
        },
        .powerpc, .powerpcle => extern struct {
            dev: u64, ino: u64, mode: u32, nlink: u32, uid: u32, gid: u32,
            rdev: u64, __rdev_pad: i16 = 0,
            size: i64, blksize: i32, blocks: i64,
            atim32: Ts32 = .{ .sec = 0, .nsec = 0 },
            mtim32: Ts32 = .{ .sec = 0, .nsec = 0 },
            ctim32: Ts32 = .{ .sec = 0, .nsec = 0 },
            __unused: [2]u32 = .{ 0, 0 },
            atim: Ts, mtim: Ts, ctim: Ts,
        },
        else => @compileError("unsupported architecture for musl stat"),
    };
}

/// mipsn32: mips64 arch with .muslabin32 ABI (32-bit address, 64-bit regs)
const MuStatMipsN32 = extern struct {
    dev: u64, __pad1: [2]i32 = .{ 0, 0 },
    ino: u64, mode: u32, nlink: u32, uid: u32, gid: u32,
    rdev: u64, __pad2: [2]i32 = .{ 0, 0 }, size: i64,
    atim32: Ts32 = .{ .sec = 0, .nsec = 0 },
    mtim32: Ts32 = .{ .sec = 0, .nsec = 0 },
    ctim32: Ts32 = .{ .sec = 0, .nsec = 0 },
    blksize: i32, __pad3: i32 = 0, blocks: i64,
    atim: Ts, mtim: Ts, ctim: Ts, __pad4: [2]i32 = .{ 0, 0 },
};

fn fstatatImpl(fd: c_int, path: [*:0]const u8, buf: *anyopaque, flag: c_int) callconv(.c) c_int {
    if (comptime kstatMatchesStat()) {
        // Kernel stat struct matches musl stat — pass buffer directly.
        return errno(linux.syscall4(
            .fstatat64,
            @as(usize, @bitCast(@as(isize, fd))),
            @intFromPtr(path),
            @intFromPtr(buf),
            @as(usize, @bitCast(@as(isize, flag))),
        ));
    }
    // Use statx and convert to the arch-specific musl stat struct.
    var stx: linux.Statx = undefined;
    const stx_rc: isize = @bitCast(linux.statx(
        fd, path,
        @as(u32, @bitCast(flag)) | linux.AT.NO_AUTOMOUNT,
        linux.STATX.BASIC_STATS, &stx,
    ));
    if (stx_rc < 0) {
        std.c._errno().* = @intCast(-stx_rc);
        return -1;
    }
    const st: *MuStat = @ptrCast(@alignCast(buf));
    st.* = std.mem.zeroes(MuStat);
    st.dev = makedev(stx.dev_major, stx.dev_minor);
    st.ino = stx.ino;
    st.mode = @intCast(stx.mode);
    st.nlink = @intCast(stx.nlink);
    st.uid = stx.uid;
    st.gid = stx.gid;
    st.rdev = makedev(stx.rdev_major, stx.rdev_minor);
    st.size = @intCast(stx.size);
    st.blksize = @intCast(stx.blksize);
    st.blocks = @intCast(stx.blocks);
    st.atim = .{ .sec = stx.atime.sec, .nsec = @intCast(stx.atime.nsec) };
    st.mtim = .{ .sec = stx.mtime.sec, .nsec = @intCast(stx.mtime.nsec) };
    st.ctim = .{ .sec = stx.ctime.sec, .nsec = @intCast(stx.ctime.nsec) };
    if (@hasField(MuStat, "atim32")) {
        st.atim32 = .{ .sec = @truncate(stx.atime.sec), .nsec = @intCast(stx.atime.nsec) };
        st.mtim32 = .{ .sec = @truncate(stx.mtime.sec), .nsec = @intCast(stx.mtime.nsec) };
        st.ctim32 = .{ .sec = @truncate(stx.ctime.sec), .nsec = @intCast(stx.ctime.nsec) };
    }
    if (@hasField(MuStat, "ino_truncated")) {
        st.ino_truncated = @truncate(stx.ino);
    }
    return 0;
}

fn fstatat(fd: c_int, path: [*:0]const u8, buf: *anyopaque, flag: c_int) c_int {
    return fstatatImpl(fd, path, buf, flag);
}

fn statLinux(noalias path: [*:0]const u8, noalias buf: *anyopaque) callconv(.c) c_int {
    return fstatat(linux.AT.FDCWD, path, buf, 0);
}
fn lstatLinux(noalias path: [*:0]const u8, noalias buf: *anyopaque) callconv(.c) c_int {
    return fstatat(linux.AT.FDCWD, path, buf, linux.AT.SYMLINK_NOFOLLOW);
}
fn fstatLinux(fd: c_int, buf: *anyopaque) callconv(.c) c_int {
    if (fd < 0) { std.c._errno().* = @intFromEnum(linux.E.BADF); return -1; }
    return fstatat(fd, "", buf, linux.AT.EMPTY_PATH);
}
fn futimensLinux(fd: c_int, times: ?*const [2]linux.timespec) callconv(.c) c_int {
    return utimensatLinux(fd, null, times, 0);
}
fn lchmodLinux(path: [*:0]const u8, mode: linux.mode_t) callconv(.c) c_int {
    return fchmodatLinux(linux.AT.FDCWD, path, mode, linux.AT.SYMLINK_NOFOLLOW);
}

const timeval = extern struct { tv_sec: isize, tv_usec: isize };

fn __futimesat(dirfd: c_int, pathname: ?[*:0]const u8, times: ?*const [2]timeval) callconv(.c) c_int {
    if (times) |tv| {
        if (tv[0].tv_usec >= 1000000 or tv[1].tv_usec >= 1000000) {
            std.c._errno().* = @intFromEnum(linux.E.INVAL); return -1;
        }
        const ts = [2]linux.timespec{
            .{ .sec = tv[0].tv_sec, .nsec = tv[0].tv_usec * 1000 },
            .{ .sec = tv[1].tv_sec, .nsec = tv[1].tv_usec * 1000 },
        };
        return utimensatLinux(dirfd, pathname, &ts, 0);
    }
    return utimensatLinux(dirfd, pathname, null, 0);
}

// --- __xstat compat ---

fn __fxstat(ver: c_int, fd: c_int, buf: *anyopaque) callconv(.c) c_int {
    _ = ver;
    if (fd < 0) { std.c._errno().* = @intFromEnum(linux.E.BADF); return -1; }
    return fstatat(fd, "", buf, linux.AT.EMPTY_PATH);
}
fn __fxstatat(ver: c_int, fd: c_int, path: [*:0]const u8, buf: *anyopaque, flag: c_int) callconv(.c) c_int {
    _ = ver; return fstatat(fd, path, buf, flag);
}
fn __lxstat(ver: c_int, path: [*:0]const u8, buf: *anyopaque) callconv(.c) c_int {
    _ = ver; return fstatat(linux.AT.FDCWD, path, buf, linux.AT.SYMLINK_NOFOLLOW);
}
fn __xstat_fn(ver: c_int, path: [*:0]const u8, buf: *anyopaque) callconv(.c) c_int {
    _ = ver; return fstatat(linux.AT.FDCWD, path, buf, 0);
}
fn __xmknod(ver: c_int, path: [*:0]const u8, mode: linux.mode_t, dev: *const linux.dev_t) callconv(.c) c_int {
    _ = ver; return mknodLinux(path, mode, dev.*);
}
fn __xmknodat(ver: c_int, fd: c_int, path: [*:0]const u8, mode: linux.mode_t, dev: *const linux.dev_t) callconv(.c) c_int {
    _ = ver; return mknodatLinux(fd, path, mode, dev.*);
}

// --- fchmodat with AT_SYMLINK_NOFOLLOW fallback ---

fn fchmodatLinux(fd: c_int, path: [*:0]const u8, mode: linux.mode_t, flag: c_int) callconv(.c) c_int {
    if (flag == 0) return errno(linux.fchmodat(fd, path, mode));

    // Try fchmodat2 (kernel >= 6.6)
    const ret: isize = @bitCast(linux.fchmodat2(fd, path, mode, @as(u32, @intCast(flag))));
    if (ret != -@as(isize, @intFromEnum(linux.E.NOSYS))) {
        if (ret >= 0) return 0;
        std.c._errno().* = @intCast(-ret);
        return -1;
    }

    if (flag != linux.AT.SYMLINK_NOFOLLOW) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }

    // Check if target is a symlink using statx
    var stx: linux.Statx = undefined;
    const stx_rc: isize = @bitCast(linux.statx(
        fd, path, linux.AT.SYMLINK_NOFOLLOW | linux.AT.NO_AUTOMOUNT,
        .{ .MODE = true }, &stx,
    ));
    if (stx_rc < 0) { std.c._errno().* = @intCast(-stx_rc); return -1; }
    if (linux.S.ISLNK(@as(linux.mode_t, stx.mode))) {
        std.c._errno().* = @intFromEnum(linux.E.OPNOTSUPP);
        return -1;
    }

    // Open with O_PATH|O_NOFOLLOW, chmod via /proc/self/fd/N
    const fd2: isize = @bitCast(linux.openat(fd, path, .{
        .ACCMODE = .RDONLY, .PATH = true, .NOFOLLOW = true, .NOCTTY = true, .CLOEXEC = true,
    }, 0));
    if (fd2 < 0) {
        std.c._errno().* = @intCast(if (fd2 == -@as(isize, @intFromEnum(linux.E.LOOP)))
            @intFromEnum(linux.E.OPNOTSUPP) else -fd2);
        return -1;
    }

    var buf: [32]u8 = undefined;
    const proc = std.fmt.bufPrint(&buf, "/proc/self/fd/{d}\x00", .{@as(u32, @intCast(fd2))}) catch {
        _ = linux.close(@intCast(fd2));
        return -1;
    };

    // Verify not a symlink via statx on proc path, then chmod
    var stx2: linux.Statx = undefined;
    const stx2_rc: isize = @bitCast(linux.statx(
        linux.AT.FDCWD, @ptrCast(proc.ptr), linux.AT.NO_AUTOMOUNT, .{ .MODE = true }, &stx2,
    ));
    const result: c_int = if (stx2_rc < 0) blk: {
        std.c._errno().* = @intCast(-stx2_rc);
        break :blk -1;
    } else if (linux.S.ISLNK(@as(linux.mode_t, stx2.mode))) blk: {
        std.c._errno().* = @intFromEnum(linux.E.OPNOTSUPP);
        break :blk -1;
    } else errno(linux.fchmodat(linux.AT.FDCWD, @ptrCast(proc.ptr), mode));

    _ = linux.close(@intCast(fd2));
    return result;
}

// --- statvfs/fstatvfs (define kernel statfs struct) ---

const Statfs = extern struct {
    f_type: usize,
    f_bsize: usize,
    f_blocks: usize,
    f_bfree: usize,
    f_bavail: usize,
    f_files: usize,
    f_ffree: usize,
    f_fsid: extern struct { val: [2]c_int },
    f_namelen: usize,
    f_frsize: usize,
    f_flags: usize,
    f_spare: [4]usize,
};

const Statvfs = extern struct {
    f_bsize: c_ulong,
    f_frsize: c_ulong,
    f_blocks: u64,
    f_bfree: u64,
    f_bavail: u64,
    f_files: u64,
    f_ffree: u64,
    f_favail: u64,
    f_fsid: c_ulong,
    f_flag: c_ulong,
    f_namemax: c_ulong,
    f_type: c_int,
    __reserved: [5]c_int,
};

fn statfsLinux(path: [*:0]const u8, buf: *Statfs) callconv(.c) c_int {
    buf.* = std.mem.zeroes(Statfs);
    return errno(linux.syscall2(.statfs, @intFromPtr(path), @intFromPtr(buf)));
}

fn fstatfsLinux(fd: c_int, buf: *Statfs) callconv(.c) c_int {
    buf.* = std.mem.zeroes(Statfs);
    return errno(linux.syscall2(.fstatfs, @as(usize, @bitCast(@as(isize, fd))), @intFromPtr(buf)));
}

fn fixup(out: *Statvfs, in_buf: *const Statfs) void {
    out.* = std.mem.zeroes(Statvfs);
    out.f_bsize = in_buf.f_bsize;
    out.f_frsize = if (in_buf.f_frsize != 0) in_buf.f_frsize else in_buf.f_bsize;
    out.f_blocks = in_buf.f_blocks;
    out.f_bfree = in_buf.f_bfree;
    out.f_bavail = in_buf.f_bavail;
    out.f_files = in_buf.f_files;
    out.f_ffree = in_buf.f_ffree;
    out.f_favail = in_buf.f_ffree;
    out.f_fsid = @intCast(in_buf.f_fsid.val[0]);
    out.f_flag = in_buf.f_flags;
    out.f_namemax = in_buf.f_namelen;
    out.f_type = @intCast(in_buf.f_type);
}

fn statvfsLinux(path: [*:0]const u8, buf: *Statvfs) callconv(.c) c_int {
    var kbuf: Statfs = undefined;
    if (statfsLinux(path, &kbuf) < 0) return -1;
    fixup(buf, &kbuf);
    return 0;
}

fn fstatvfsLinux(fd: c_int, buf: *Statvfs) callconv(.c) c_int {
    var kbuf: Statfs = undefined;
    if (fstatfsLinux(fd, &kbuf) < 0) return -1;
    fixup(buf, &kbuf);
    return 0;
}