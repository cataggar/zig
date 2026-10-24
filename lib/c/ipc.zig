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
        symbol(&semctlLinux, "semctl");
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

fn semctlLinux(id: c_int, num: c_int, cmd: c_int, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    const arg = cVaArg(&ap, usize);
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
        std.c._errno().* = @intCast(@backingInt(linux.E.INVAL));
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
