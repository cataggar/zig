const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;
const errnoSize = @import("../c.zig").errnoSize;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&_exit, "_exit");

        symbol(&accessLinux, "access");
        symbol(&acctLinux, "acct");
        symbol(&chdirLinux, "chdir");
        symbol(&chownLinux, "chown");
        symbol(&close, "close");
        symbol(&posix_close, "posix_close");
        symbol(&fchownatLinux, "fchownat");
        symbol(&lchownLinux, "lchown");
        symbol(&chrootLinux, "chroot");
        symbol(&ctermidLinux, "ctermid");
        symbol(&dupLinux, "dup");
        symbol(&dup2Linux, "dup2");
        symbol(&dup3Linux, "__dup3");

        symbol(&fchdirLinux, "fchdir");
        symbol(&fchownLinux, "fchown");
        symbol(&fdatasyncLinux, "fdatasync");
        symbol(&fsyncLinux, "fsync");
        symbol(&ftruncateLinux, "ftruncate");
        symbol(&isattyLinux, "isatty");
        symbol(&pipe2Linux, "pipe2");

        symbol(&getegidLinux, "getegid");
        symbol(&geteuidLinux, "geteuid");
        symbol(&getgidLinux, "getgid");
        symbol(&getgroupsLinux, "getgroups");
        symbol(&getpgidLinux, "getpgid");
        symbol(&getpgrpLinux, "getpgrp");
        symbol(&setpgidLinux, "setpgid");
        symbol(&setpgrpLinux, "setpgrp");
        symbol(&getsidLinux, "getsid");
        symbol(&getpidLinux, "getpid");
        symbol(&getppidLinux, "getppid");
        symbol(&getuidLinux, "getuid");

        symbol(&lseekLinux, "__lseek");

        symbol(&readLinux, "read");
        symbol(&readvLinux, "readv");
        symbol(&preadLinux, "pread");
        symbol(&preadvLinux, "preadv");

        symbol(&writeLinux, "write");
        symbol(&writevLinux, "writev");
        symbol(&pwriteLinux, "pwrite");
        symbol(&pwritevLinux, "pwritev");
        symbol(&lseekLinux, "lseek");
        symbol(&alarmLinux, "alarm");
        symbol(&setsidLinux, "setsid");
        symbol(&gethostnameLinux, "gethostname");
        symbol(&setregidLinux, "setregid");
        symbol(&setreuidLinux, "setreuid");
        symbol(&readlinkLinux, "readlink");
        symbol(&readlinkatLinux, "readlinkat");
        symbol(&faccessatLinux, "faccessat");
        symbol(&getcwdLinux, "getcwd");
        symbol(&ualarmLinux, "ualarm");

        symbol(&rmdirLinux, "rmdir");
        symbol(&linkLinux, "link");
        symbol(&linkatLinux, "linkat");
        symbol(&pipeLinux, "pipe");
        symbol(&renameatLinux, "renameat");
        symbol(&symlinkLinux, "symlink");
        symbol(&symlinkatLinux, "symlinkat");
        symbol(&syncLinux, "sync");
        symbol(&unlinkLinux, "unlink");
        symbol(&unlinkatLinux, "unlinkat");

        symbol(&execveLinux, "execve");
        symbol(&fexecveLinux, "fexecve");
    }
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&swab, "swab");
    }
    if (builtin.target.isWasiLibC()) {
    }
}

fn _exit(exit_code: c_int) callconv(.c) noreturn {
    std.c._Exit(exit_code);
}

fn accessLinux(path: [*:0]const c_char, amode: c_int) callconv(.c) c_int {
    return errno(linux.access(@ptrCast(path), @bitCast(amode)));
}

fn acctLinux(path: [*:0]const c_char) callconv(.c) c_int {
    return errno(linux.acct(@ptrCast(path)));
}

fn chdirLinux(path: [*:0]const c_char) callconv(.c) c_int {
    return errno(linux.chdir(@ptrCast(path)));
}

fn chownLinux(path: [*:0]const c_char, uid: linux.uid_t, gid: linux.gid_t) callconv(.c) c_int {
    return errno(linux.chown(@ptrCast(path), uid, gid));
}

fn fchownatLinux(fd: c_int, path: [*:0]const c_char, uid: linux.uid_t, gid: linux.gid_t, flags: c_int) callconv(.c) c_int {
    return errno(linux.fchownat(fd, @ptrCast(path), uid, gid, @bitCast(flags)));
}

fn lchownLinux(path: [*:0]const c_char, uid: linux.uid_t, gid: linux.gid_t) callconv(.c) c_int {
    return errno(linux.lchown(@ptrCast(path), uid, gid));
}

fn chrootLinux(path: [*:0]const c_char) callconv(.c) c_int {
    return errno(linux.chroot(@ptrCast(path)));
}

fn ctermidLinux(maybe_path: ?[*]c_char) callconv(.c) [*:0]c_char {
    const default_tty = "/dev/tty";

    return if (maybe_path) |path| blk: {
        path[0..(default_tty.len + 1)].* = @bitCast(default_tty.*);
        break :blk path[0..default_tty.len :0].ptr;
    } else @ptrCast(@constCast(default_tty));
}

fn dupLinux(fd: c_int) callconv(.c) c_int {
    return errno(linux.dup(fd));
}

fn getegidLinux() callconv(.c) linux.gid_t {
    return linux.getegid();
}

fn geteuidLinux() callconv(.c) linux.uid_t {
    return linux.geteuid();
}

fn getgidLinux() callconv(.c) linux.gid_t {
    return linux.getgid();
}

fn getgroupsLinux(size: c_int, list: ?[*]linux.gid_t) callconv(.c) c_int {
    return errno(linux.getgroups(@intCast(size), list));
}

fn getpgidLinux(pid: linux.pid_t) callconv(.c) linux.pid_t {
    return errno(linux.getpgid(pid));
}

fn getpgrpLinux() callconv(.c) linux.pid_t {
    return @intCast(linux.getpgid(0)); // @intCast as it cannot fail
}

fn setpgidLinux(pid: linux.pid_t, pgid: linux.pid_t) callconv(.c) c_int {
    return errno(linux.setpgid(pid, pgid));
}

fn setpgrpLinux() callconv(.c) linux.pid_t {
    return @intCast(linux.setpgid(0, 0)); // @intCast as it cannot fail
}

fn getpidLinux() callconv(.c) linux.pid_t {
    return linux.getpid();
}

fn getppidLinux() callconv(.c) linux.pid_t {
    return linux.getppid();
}

fn getsidLinux(pid: linux.pid_t) callconv(.c) linux.pid_t {
    return errno(linux.getsid(pid));
}

fn getuidLinux() callconv(.c) linux.uid_t {
    return linux.getuid();
}

fn linkLinux(old: [*:0]const c_char, new: [*:0]const c_char) callconv(.c) c_int {
    return errno(linux.link(@ptrCast(old), @ptrCast(new)));
}

fn linkatLinux(old_fd: c_int, old: [*:0]const c_char, new_fd: c_int, new: [*:0]const c_char, flags: c_int) callconv(.c) c_int {
    return errno(linux.linkat(old_fd, @ptrCast(old), new_fd, @ptrCast(new), @bitCast(flags)));
}

fn pipeLinux(fd: *[2]c_int) callconv(.c) c_int {
    return errno(linux.pipe(@ptrCast(fd)));
}

fn renameatLinux(old_fd: c_int, old: [*:0]const c_char, new_fd: c_int, new: [*:0]const c_char) callconv(.c) c_int {
    return errno(linux.renameat(old_fd, @ptrCast(old), new_fd, @ptrCast(new)));
}

fn rmdirLinux(path: [*:0]const c_char) callconv(.c) c_int {
    return errno(linux.rmdir(@ptrCast(path)));
}

fn symlinkLinux(existing: [*:0]const c_char, new: [*:0]const c_char) callconv(.c) c_int {
    return errno(linux.symlink(@ptrCast(existing), @ptrCast(new)));
}

fn symlinkatLinux(existing: [*:0]const c_char, fd: c_int, new: [*:0]const c_char) callconv(.c) c_int {
    return errno(linux.symlinkat(@ptrCast(existing), fd, @ptrCast(new)));
}

fn fdatasyncLinux(fd: c_int) callconv(.c) c_int {
    return errno(linux.fdatasync(fd));
}

fn fsyncLinux(fd: c_int) callconv(.c) c_int {
    return errno(linux.fsync(fd));
}

fn ftruncateLinux(fd: c_int, length: linux.off_t) callconv(.c) c_int {
    return errno(linux.ftruncate(fd, length));
}

fn syncLinux() callconv(.c) void {
    linux.sync();
}

fn unlinkLinux(path: [*:0]const c_char) callconv(.c) c_int {
    return errno(linux.unlink(@ptrCast(path)));
}

fn unlinkatLinux(fd: c_int, path: [*:0]const c_char, flags: c_int) callconv(.c) c_int {
    return errno(linux.unlinkat(fd, @ptrCast(path), @bitCast(flags)));
}

fn execveLinux(path: [*:0]const c_char, argv: [*:null]const ?[*:0]c_char, envp: [*:null]const ?[*:0]c_char) callconv(.c) c_int {
    return errno(linux.execve(@ptrCast(path), @ptrCast(argv), @ptrCast(envp)));
}

fn dup2Linux(old_fd: c_int, new_fd: c_int) callconv(.c) c_int {
    return errno(linux.dup2(old_fd, new_fd));
}

fn dup3Linux(old_fd: c_int, new_fd: c_int, flags: c_int) callconv(.c) c_int {
    return errno(linux.dup3(old_fd, new_fd, @bitCast(flags)));
}

fn fchdirLinux(fd: c_int) callconv(.c) c_int {
    return errno(linux.fchdir(fd));
}

fn fchownLinux(fd: c_int, owner: linux.uid_t, group: linux.gid_t) callconv(.c) c_int {
    return errno(linux.fchown(fd, owner, group));
}




fn isattyLinux(fd: c_int) callconv(.c) c_int {
    var wsz: std.posix.winsize = undefined;
    if (errno(linux.ioctl(fd, linux.T.IOCGWINSZ, @intFromPtr(&wsz))) == 0) return 1;
    if (std.c._errno().* != @intFromEnum(linux.E.BADF))
        std.c._errno().* = @intFromEnum(linux.E.NOTTY);
    return 0;
}

fn pipe2Linux(fd: *[2]c_int, flags: c_int) callconv(.c) c_int {
    return errno(linux.pipe2(@ptrCast(fd), @bitCast(flags)));
}

fn lseekLinux(fd: c_int, offset: linux.off_t, whence: c_int) callconv(.c) linux.off_t {
    const signed: isize = @bitCast(linux.lseek(fd, offset, @intCast(@as(c_uint, @bitCast(whence)))));
    if (signed < 0) {
        @branchHint(.unlikely);
        std.c._errno().* = @intCast(-signed);
        return -1;
    }
    return signed;
}

fn readLinux(fd: c_int, buf: [*]u8, count: usize) callconv(.c) isize {
    return errnoSize(linux.read(fd, buf, count));
}

fn readvLinux(fd: c_int, iov: [*]const std.posix.iovec, count: c_int) callconv(.c) isize {
    return errnoSize(linux.readv(fd, iov, @intCast(@as(c_uint, @bitCast(count)))));
}

fn preadLinux(fd: c_int, buf: [*]u8, count: usize, offset: linux.off_t) callconv(.c) isize {
    return errnoSize(linux.pread(fd, buf, count, offset));
}

fn preadvLinux(fd: c_int, iov: [*]const std.posix.iovec, count: c_int, offset: linux.off_t) callconv(.c) isize {
    return errnoSize(linux.preadv(fd, iov, @intCast(@as(c_uint, @bitCast(count))), offset));
}

fn writeLinux(fd: c_int, buf: [*]const u8, count: usize) callconv(.c) isize {
    return errnoSize(linux.write(fd, buf, count));
}

fn writevLinux(fd: c_int, iov: [*]const std.posix.iovec_const, count: c_int) callconv(.c) isize {
    return errnoSize(linux.writev(fd, iov, @intCast(@as(c_uint, @bitCast(count)))));
}

fn pwriteLinux(fd: c_int, buf: [*]const u8, count: usize, offset: linux.off_t) callconv(.c) isize {
    return errnoSize(linux.pwrite(fd, buf, count, offset));
}

fn pwritevLinux(fd: c_int, iov: [*]const std.posix.iovec_const, count: c_int, offset: linux.off_t) callconv(.c) isize {
    return errnoSize(linux.pwritev(fd, iov, @intCast(@as(c_uint, @bitCast(count))), offset));
}

fn alarmLinux(seconds: c_uint) callconv(.c) c_uint {
    // setitimer syscall uses itimerval (usec), but Zig wraps it with itimerspec.
    // The memory layout is identical, so nsec field holds microseconds at ABI level.
    const it = linux.itimerspec{
        .it_interval = .{ .sec = 0, .nsec = 0 },
        .it_value = .{ .sec = @intCast(seconds), .nsec = 0 },
    };
    var old: linux.itimerspec = undefined;
    _ = linux.setitimer(0, &it, &old); // ITIMER_REAL = 0
    return @intCast(@as(u64, @intCast(old.it_value.sec)) + @as(u64, if (old.it_value.nsec != 0) 1 else 0));
}

fn faccessatLinux(fd: c_int, path: [*:0]const c_char, mode: c_int, flags: c_int) callconv(.c) c_int {
    return errno(linux.faccessat(fd, @ptrCast(path), @bitCast(mode), @bitCast(flags)));
}

fn getcwdLinux(buf: ?[*]u8, size: usize) callconv(.c) ?[*]u8 {
    if (buf) |b| {
        if (size == 0) {
            std.c._errno().* = @intFromEnum(linux.E.INVAL);
            return null;
        }
        const rc: isize = @bitCast(linux.getcwd(b, size));
        if (rc < 0) {
            std.c._errno().* = @intCast(-rc);
            return null;
        }
        if (rc == 0 or b[0] != '/') {
            std.c._errno().* = @intFromEnum(linux.E.NOENT);
            return null;
        }
        return b;
    } else {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return null;
    }
}

fn gethostnameLinux(name: [*]u8, len: usize) callconv(.c) c_int {
    var uts: linux.utsname = undefined;
    const rc: isize = @bitCast(linux.uname(&uts));
    if (rc < 0) {
        std.c._errno().* = @intCast(-rc);
        return -1;
    }
    const nodename: [*]const u8 = &uts.nodename;
    const max_len = @min(len, @as(usize, 65));
    var i: usize = 0;
    while (i < max_len) : (i += 1) {
        name[i] = nodename[i];
        if (nodename[i] == 0) return 0;
    }
    if (i > 0) name[i - 1] = 0;
    return 0;
}

fn niceLinux(inc: c_int) callconv(.c) c_int {
    const NZERO: c_int = 20;
    var prio: c_int = inc;
    if (inc > -2 * NZERO and inc < 2 * NZERO) {
        // Kernel getpriority returns 20-nice (1..40), negative on error
        const gp: isize = @bitCast(linux.syscall2(.getpriority, 0, 0));
        if (gp < 0) {
            std.c._errno().* = @intCast(-gp);
            return -1;
        }
        prio += NZERO - @as(c_int, @intCast(gp));
    }
    if (prio > NZERO - 1) prio = NZERO - 1;
    if (prio < -NZERO) prio = -NZERO;
    const sp: isize = @bitCast(linux.syscall3(
        .setpriority,
        0,
        0,
        @as(usize, @bitCast(@as(isize, prio))),
    ));
    if (sp < 0) {
        const err: c_int = @intCast(-sp);
        std.c._errno().* = if (err == @intFromEnum(linux.E.ACCES)) @intFromEnum(linux.E.PERM) else err;
        return -1;
    }
    return prio;
}

fn pauseLinux() callconv(.c) c_int {
    return errno(linux.pause());
}

fn readlinkLinux(path: [*:0]const c_char, buf: [*]u8, bufsiz: usize) callconv(.c) isize {
    return errnoSize(linux.readlink(@ptrCast(path), buf, bufsiz));
}

fn readlinkatLinux(fd: c_int, path: [*:0]const c_char, buf: [*]u8, bufsiz: usize) callconv(.c) isize {
    return errnoSize(linux.readlinkat(fd, @ptrCast(path), buf, bufsiz));
}

fn sleepLinux(seconds: c_uint) callconv(.c) c_uint {
    var tv = linux.timespec{ .sec = @intCast(seconds), .nsec = 0 };
    const rc: isize = @bitCast(linux.nanosleep(&tv, &tv));
    if (rc != 0) return @intCast(@max(tv.sec, 0));
    return 0;
}

fn tcgetpgrpLinux(fd: c_int) callconv(.c) linux.pid_t {
    var pgrp: linux.pid_t = undefined;
    const rc = errno(linux.tcgetpgrp(fd, &pgrp));
    if (rc < 0) return rc;
    return pgrp;
}

fn tcsetpgrpLinux(fd: c_int, pgrp: linux.pid_t) callconv(.c) c_int {
    return errno(linux.tcsetpgrp(fd, &pgrp));
}

fn truncateLinux(path: [*:0]const c_char, length: linux.off_t) callconv(.c) c_int {
    return errno(linux.syscall2(.truncate, @intFromPtr(path), @as(usize, @bitCast(length))));
}

fn ualarmLinux(value: c_uint, interval: c_uint) callconv(.c) c_uint {
    const it = linux.itimerspec{
        .it_interval = .{ .sec = 0, .nsec = @intCast(interval) },
        .it_value = .{ .sec = 0, .nsec = @intCast(value) },
    };
    var old: linux.itimerspec = undefined;
    _ = linux.setitimer(0, &it, &old); // ITIMER_REAL = 0
    // nsec field holds microseconds at ABI level (kernel itimerval.usec)
    return @intCast(@as(u64, @intCast(old.it_value.sec)) * 1000000 + @as(u64, @intCast(old.it_value.nsec)));
}

fn usleepLinux(useconds: c_uint) callconv(.c) c_int {
    const tv = linux.timespec{
        .sec = @intCast(useconds / 1000000),
        .nsec = @intCast(@as(u64, useconds % 1000000) * 1000),
    };
    return errno(linux.nanosleep(&tv, null));
}
fn setuidLinux(uid: linux.uid_t) callconv(.c) c_int {
    return errno(linux.setuid(uid));
}

fn setgidLinux(gid: linux.gid_t) callconv(.c) c_int {
    return errno(linux.setgid(gid));
}

fn seteuidLinux(euid: linux.uid_t) callconv(.c) c_int {
    return errno(linux.seteuid(euid));
}

fn setegidLinux(egid: linux.gid_t) callconv(.c) c_int {
    return errno(linux.setegid(egid));
}

fn setreuidLinux(ruid: linux.uid_t, euid: linux.uid_t) callconv(.c) c_int {
    return errno(linux.setreuid(ruid, euid));
}

fn setregidLinux(rgid: linux.gid_t, egid: linux.gid_t) callconv(.c) c_int {
    return errno(linux.setregid(rgid, egid));
}

fn setresuidLinux(ruid: linux.uid_t, euid: linux.uid_t, suid: linux.uid_t) callconv(.c) c_int {
    return errno(linux.setresuid(ruid, euid, suid));
}

fn setresgidLinux(rgid: linux.gid_t, egid: linux.gid_t, sgid: linux.gid_t) callconv(.c) c_int {
    return errno(linux.setresgid(rgid, egid, sgid));
}

fn setsidLinux() callconv(.c) linux.pid_t {
    return errno(linux.setsid());
}
fn fexecveLinux(fd: c_int, argv: [*:null]const ?[*:0]c_char, envp: [*:null]const ?[*:0]c_char) callconv(.c) c_int {
    const r: isize = @bitCast(linux.execveat(fd, "", @ptrCast(argv), @ptrCast(envp), .{ .SYMLINK_NOFOLLOW = false, .EMPTY_PATH = true }));
    if (r != -@as(isize, @intFromEnum(linux.E.NOSYS))) {
        return errno(@bitCast(r));
    }
    // Fallback: construct /proc/self/fd/<fd> path and call execve.
    var buf: ["/proc/self/fd/".len + 11]u8 = undefined;
    const proc_path = std.fmt.bufPrintZ(&buf, "/proc/self/fd/{d}", .{@as(u32, @intCast(fd))}) catch unreachable;
    _ = errno(linux.execve(proc_path.ptr, @ptrCast(argv), @ptrCast(envp)));
    if (std.c._errno().* == @intFromEnum(linux.E.NOENT)) {
        std.c._errno().* = @intFromEnum(linux.E.BADF);
    }
    return -1;
}

/// The vfork syscall cannot be safely made from compiled code because the
/// parent and child share the same stack. This fallback uses fork instead,
/// matching the behavior of musl's C fallback (vfork.c).
fn vforkLinux() callconv(.c) c_int {
    return errno(linux.fork());
}

fn swab(noalias src_ptr: *const anyopaque, noalias dest_ptr: *anyopaque, n: isize) callconv(.c) void {
    var src: [*]const u8 = @ptrCast(src_ptr);
    var dest: [*]u8 = @ptrCast(dest_ptr);
    var i = n;

    while (i > 1) : (i -= 2) {
        dest[0] = src[1];
        dest[1] = src[0];
        dest += 2;
        src += 2;
    }
}

test swab {
    var a: [4]u8 = undefined;
    @memset(a[0..], '\x00');
    swab("abcd", &a, 4);
    try std.testing.expectEqualSlices(u8, "badc", &a);

    // Partial copy
    @memset(a[0..], '\x00');
    swab("abcd", &a, 2);
    try std.testing.expectEqualSlices(u8, "ba\x00\x00", &a);

    // n < 1
    @memset(a[0..], '\x00');
    swab("abcd", &a, 0);
    try std.testing.expectEqualSlices(u8, "\x00" ** 4, &a);
    swab("abcd", &a, -1);
    try std.testing.expectEqualSlices(u8, "\x00" ** 4, &a);

    // Odd n
    @memset(a[0..], '\x00');
    swab("abcd", &a, 1);
    try std.testing.expectEqualSlices(u8, "\x00" ** 4, &a);
    swab("abcd", &a, 3);
    try std.testing.expectEqualSlices(u8, "ba\x00\x00", &a);
}

fn close(fd: std.c.fd_t) callconv(.c) c_int {
    const signed: isize = @bitCast(linux.close(fd));
    if (signed < 0) {
        @branchHint(.unlikely);
        if (-signed == @intFromEnum(linux.E.INTR)) return 0;
        std.c._errno().* = @intCast(-signed);
        return -1;
    }
    return 0;
}

fn posix_close(fd: std.c.fd_t, _: c_int) callconv(.c) c_int {
    return close(fd);
}

fn closeWasi(fd: std.c.fd_t) callconv(.c) c_int {
    switch (std.os.wasi.fd_close(fd)) {
        .SUCCESS => return 0,
        else => |e| {
            std.c._errno().* = @intFromEnum(e);
            return -1;
        },
    }
}
