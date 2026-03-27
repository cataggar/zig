const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

const FDOP_CLOSE = 1;
const FDOP_DUP2 = 2;
const FDOP_OPEN = 3;
const FDOP_CHDIR = 4;
const FDOP_FCHDIR = 5;

const fdop = extern struct {
    next: ?*fdop,
    prev: ?*fdop,
    cmd: c_int,
    fd: c_int,
    srcfd: c_int,
    oflag: c_int,
    mode: linux.mode_t,
    // flexible array member follows; for alloc sizing only
};

const posix_spawn_file_actions_t = extern struct {
    __pad0: [2]c_int,
    __actions: ?*fdop,
    __pad: [16]c_int,
};

extern "c" fn malloc(size: usize) callconv(.c) ?[*]u8;
extern "c" fn free(ptr: ?*anyopaque) callconv(.c) void;
extern "c" fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) callconv(.c) c_int;
extern "c" var __environ: [*:null]?[*:0]u8;

comptime {
    if (builtin.link_libc) {
        symbol(&execvImpl, "execv");
        symbol(&posix_spawn_file_actions_addclose_impl, "posix_spawn_file_actions_addclose");
        symbol(&posix_spawn_file_actions_adddup2_impl, "posix_spawn_file_actions_adddup2");
        symbol(&posix_spawn_file_actions_addopen_impl, "posix_spawn_file_actions_addopen");
        symbol(&posix_spawn_file_actions_addchdir_impl, "posix_spawn_file_actions_addchdir_np");
        symbol(&posix_spawn_file_actions_addfchdir_impl, "posix_spawn_file_actions_addfchdir_np");
        symbol(&posix_spawn_file_actions_destroy_impl, "posix_spawn_file_actions_destroy");
    }
}

fn execvImpl(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) callconv(.c) c_int {
    return execve(path, argv, @ptrCast(&__environ));
}

fn allocFdop(extra: usize) ?*fdop {
    const ptr = malloc(@sizeOf(fdop) + extra) orelse return null;
    return @ptrCast(@alignCast(ptr));
}

fn prependOp(fa: *posix_spawn_file_actions_t, op: *fdop) void {
    op.next = fa.__actions;
    if (fa.__actions) |existing| existing.prev = op;
    op.prev = null;
    fa.__actions = op;
}

fn posix_spawn_file_actions_addclose_impl(fa: *posix_spawn_file_actions_t, fd: c_int) callconv(.c) c_int {
    if (fd < 0) return @intFromEnum(linux.E.BADF);
    const op = allocFdop(0) orelse return @intFromEnum(linux.E.NOMEM);
    op.cmd = FDOP_CLOSE;
    op.fd = fd;
    prependOp(fa, op);
    return 0;
}

fn posix_spawn_file_actions_adddup2_impl(fa: *posix_spawn_file_actions_t, srcfd: c_int, fd: c_int) callconv(.c) c_int {
    if (srcfd < 0 or fd < 0) return @intFromEnum(linux.E.BADF);
    const op = allocFdop(0) orelse return @intFromEnum(linux.E.NOMEM);
    op.cmd = FDOP_DUP2;
    op.srcfd = srcfd;
    op.fd = fd;
    prependOp(fa, op);
    return 0;
}

fn posix_spawn_file_actions_addopen_impl(fa: *posix_spawn_file_actions_t, fd: c_int, path: [*:0]const u8, flags: c_int, mode: linux.mode_t) callconv(.c) c_int {
    if (fd < 0) return @intFromEnum(linux.E.BADF);
    const pathlen = std.mem.len(path) + 1;
    const op = allocFdop(pathlen) orelse return @intFromEnum(linux.E.NOMEM);
    op.cmd = FDOP_OPEN;
    op.fd = fd;
    op.oflag = flags;
    op.mode = mode;
    const dest: [*]u8 = @as([*]u8, @ptrCast(op)) + @sizeOf(fdop);
    @memcpy(dest[0..pathlen], path[0..pathlen]);
    prependOp(fa, op);
    return 0;
}

fn posix_spawn_file_actions_addchdir_impl(fa: *posix_spawn_file_actions_t, path: [*:0]const u8) callconv(.c) c_int {
    const pathlen = std.mem.len(path) + 1;
    const op = allocFdop(pathlen) orelse return @intFromEnum(linux.E.NOMEM);
    op.cmd = FDOP_CHDIR;
    op.fd = -1;
    const dest: [*]u8 = @as([*]u8, @ptrCast(op)) + @sizeOf(fdop);
    @memcpy(dest[0..pathlen], path[0..pathlen]);
    prependOp(fa, op);
    return 0;
}

fn posix_spawn_file_actions_addfchdir_impl(fa: *posix_spawn_file_actions_t, fd: c_int) callconv(.c) c_int {
    if (fd < 0) return @intFromEnum(linux.E.BADF);
    const op = allocFdop(0) orelse return @intFromEnum(linux.E.NOMEM);
    op.cmd = FDOP_FCHDIR;
    op.fd = fd;
    prependOp(fa, op);
    return 0;
}

fn posix_spawn_file_actions_destroy_impl(fa: *posix_spawn_file_actions_t) callconv(.c) c_int {
    var op = fa.__actions;
    while (op) |o| {
        const next = o.next;
        free(o);
        op = next;
    }
    return 0;
}
