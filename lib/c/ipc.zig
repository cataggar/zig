const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;
const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;
const syscallArg = @import("../c.zig").syscallArg;

const IPC_64: linux.syscall_arg_t = 0x100;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&ftokLinux, "ftok");
        symbol(&msgctlLinux, "msgctl");
        symbol(&msggetLinux, "msgget");
        symbol(&msgrcvLinux, "msgrcv");
        symbol(&msgsndLinux, "msgsnd");
        symbol(&semgetLinux, "semget");
        symbol(&semopLinux, "semop");
        symbol(&semtimedopLinux, "semtimedop");
        symbol(&shmatLinux, "shmat");
        symbol(&shmctlLinux, "shmctl");
        symbol(&shmdtLinux, "shmdt");
        symbol(&shmgetLinux, "shmget");
    }
}

fn ftokLinux(path: [*:0]const u8, id: c_int) callconv(.c) c_int {
    var stx: linux.Statx = undefined;
    const rc = linux.statx(linux.AT.FDCWD, path, 0, linux.STATX.BASIC_STATS, &stx);
    const signed: isize = @bitCast(rc);
    if (signed < 0) {
        @branchHint(.unlikely);
        std.c._errno().* = @intCast(-signed);
        return -1;
    }
    const ino: c_uint = @truncate(stx.ino);
    const dev: c_uint = stx.dev_minor;
    const proj: c_uint = @bitCast(id);
    return @bitCast((ino & 0xffff) | ((dev & 0xff) << 16) | ((proj & 0xff) << 24));
}

fn msgctlLinux(q: c_int, cmd: c_int, buf: ?*anyopaque) callconv(.c) c_int {
    return errno(linux.syscall3(
        .msgctl,
        syscallArg(q),
        syscallArg(cmd) | IPC_64,
        if (buf) |b| @intFromPtr(b) else 0,
    ));
}

fn msggetLinux(key: c_int, flag: c_int) callconv(.c) c_int {
    return errno(linux.syscall2(
        .msgget,
        syscallArg(key),
        syscallArg(flag),
    ));
}

fn msgrcvLinux(q: c_int, m: *anyopaque, len: usize, typ: c_long, flag: c_int) callconv(.c) isize {
    const rc: isize = @bitCast(linux.syscall5(
        .msgrcv,
        syscallArg(q),
        @intFromPtr(m),
        len,
        syscallArg(typ),
        syscallArg(flag),
    ));
    if (rc < 0) {
        @branchHint(.unlikely);
        std.c._errno().* = @intCast(-rc);
        return -1;
    }
    return rc;
}

fn msgsndLinux(q: c_int, m: *const anyopaque, len: usize, flag: c_int) callconv(.c) c_int {
    return errno(linux.syscall4(
        .msgsnd,
        syscallArg(q),
        @intFromPtr(m),
        len,
        syscallArg(flag),
    ));
}

fn semctlLinux(id: c_int, num: c_int, cmd: c_int, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    const arg = @cVaArg(&ap, usize);
    return errno(linux.syscall4(
        .semctl,
        syscallArg(id),
        syscallArg(num),
        syscallArg(cmd) | IPC_64,
        arg,
    ));
}

fn semgetLinux(key: c_int, n: c_int, fl: c_int) callconv(.c) c_int {
    if (n > std.math.maxInt(c_ushort)) {
        std.c._errno().* = @intCast(@intFromEnum(linux.E.INVAL));
        return -1;
    }
    return errno(linux.syscall3(
        .semget,
        syscallArg(key),
        syscallArg(n),
        syscallArg(fl),
    ));
}

fn semopLinux(id: c_int, buf: *anyopaque, n: usize) callconv(.c) c_int {
    // Some 0.17 targets (e.g. x86, s390x) have no direct `semop` syscall; like
    // musl, implement semop as semtimedop with a null timeout.
    if (@hasField(linux.SYS, "semop")) {
        return errno(linux.syscall3(
            .semop,
            syscallArg(id),
            @intFromPtr(buf),
            n,
        ));
    }
    return semtimedopLinux(id, buf, n, null);
}

fn semtimedopLinux(id: c_int, buf: *anyopaque, n: usize, ts: ?*const anyopaque) callconv(.c) c_int {
    return errno(linux.syscall4(
        if (@hasField(linux.SYS, "semtimedop_time64")) .semtimedop_time64 else .semtimedop,
        syscallArg(id),
        @intFromPtr(buf),
        n,
        if (ts) |t| @intFromPtr(t) else 0,
    ));
}

fn shmatLinux(id: c_int, addr: ?*const anyopaque, flag: c_int) callconv(.c) ?*anyopaque {
    const rc = linux.syscall3(
        .shmat,
        syscallArg(id),
        if (addr) |a| @intFromPtr(a) else 0,
        syscallArg(flag),
    );
    const signed: isize = @bitCast(rc);
    if (signed > -4096 and signed < 0) {
        @branchHint(.unlikely);
        std.c._errno().* = @intCast(-signed);
        return @ptrFromInt(std.math.maxInt(usize));
    }
    if (rc == 0) return null;
    return @ptrFromInt(rc);
}

fn shmctlLinux(id: c_int, cmd: c_int, buf: ?*anyopaque) callconv(.c) c_int {
    return errno(linux.syscall3(
        .shmctl,
        syscallArg(id),
        syscallArg(cmd) | IPC_64,
        if (buf) |b| @intFromPtr(b) else 0,
    ));
}

fn shmdtLinux(addr: *const anyopaque) callconv(.c) c_int {
    return errno(linux.syscall1(
        .shmdt,
        @intFromPtr(addr),
    ));
}

fn shmgetLinux(key: c_int, size: usize, flag: c_int) callconv(.c) c_int {
    const sz = if (size > std.math.maxInt(isize)) std.math.maxInt(usize) else size;
    return errno(linux.syscall3(
        .shmget,
        syscallArg(key),
        sz,
        syscallArg(flag),
    ));
}
