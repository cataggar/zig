const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;
const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;
const NSIG = linux.NSIG;
const sigset_t = linux.sigset_t;
const SigsetElement = @typeInfo(sigset_t).array.child;
const bits_per_elem = @bitSizeOf(SigsetElement);
// app_mask: all signals set except internal signals 32, 33, 34
const app_mask = blk: {
    var mask: sigset_t = undefined;
    for (&mask) |*elem| elem.* = ~@as(SigsetElement, 0);
    for (.{ 31, 32, 33 }) |s| {
        mask[s / bits_per_elem] &= ~(@as(SigsetElement, 1) << @intCast(s % bits_per_elem));
    }
    break :blk mask;
};
const itimerval = extern struct {
    it_interval: linux.timeval,
    it_value: linux.timeval,
};
const musl_sigset_t = [128 / @sizeOf(c_ulong)]c_ulong;
const posix_spawnattr_t = extern struct {
    __flags: c_int,
    __pgrp: linux.pid_t,
    __def: musl_sigset_t,
    __mask: musl_sigset_t,
    __prio: c_int,
    __pol: c_int,
    __fn: ?*anyopaque,
    __pad: [64 - @sizeOf(?*anyopaque)]u8,
};
const posix_spawn_file_actions_t = extern struct {
    __pad0: [2]c_int,
    __actions: ?*anyopaque,
    __pad: [16]c_int,
};
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
extern "c" fn malloc(size: usize) callconv(.c) ?[*]u8;
extern "c" fn free(ptr: ?*anyopaque) callconv(.c) void;
extern "c" fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) callconv(.c) c_int;
extern "c" var __environ: [*:null]?[*:0]u8;
extern "c" fn getenv(name: [*:0]const u8) callconv(.c) ?[*:0]const u8;
const NAME_MAX = 255;
const PATH_MAX = 4096;
extern "c" fn execvp(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) callconv(.c) c_int;
const MAX_ARGS = 256;
const c_sigaction = extern struct {
    handler: ?*const fn (c_int) callconv(.c) void,
    mask: musl_sigset_t,
    flags: c_int,
    restorer: ?*const fn () callconv(.c) void,
};
const SIG_IGN: ?*const fn (c_int) callconv(.c) void = @ptrFromInt(1);
extern "c" fn sigaction(sig: c_int, act: ?*const c_sigaction, oact: ?*c_sigaction) callconv(.c) c_int;
extern "c" fn sigprocmask(how: c_int, set: ?*const musl_sigset_t, oset: ?*musl_sigset_t) callconv(.c) c_int;
extern "c" fn sigemptyset(set: *musl_sigset_t) callconv(.c) c_int;
extern "c" fn sigaddset(set: *musl_sigset_t, sig: c_int) callconv(.c) c_int;
extern "c" fn posix_spawnattr_destroy(attr: *posix_spawnattr_t) callconv(.c) c_int;
extern "c" fn posix_spawn(pid: *linux.pid_t, path: [*:0]const u8, fa: ?*anyopaque, attr: ?*const posix_spawnattr_t, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) callconv(.c) c_int;
extern "c" fn waitpid(pid: linux.pid_t, status: ?*c_int, options: c_int) callconv(.c) linux.pid_t;
extern "c" fn pthread_testcancel() callconv(.c) void;
const POSIX_SPAWN_SETSIGDEF: c_short = 0x4;
const POSIX_SPAWN_SETSIGMASK: c_short = 0x8;
const SIGINT = 2;
const SIGQUIT = 3;
const SIGCHLD = 17;
const SIG_BLOCK = 0;
const SIG_SETMASK = 2;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&raiseLinux, "raise");
        symbol(&waitLinux, "wait");
        symbol(&waitpidLinux, "waitpid");
        symbol(&waitidLinux, "waitid");
        symbol(&__restore, "__restore");
        symbol(&__restore_rt, "__restore_rt");
        symbol(&getitimerLinux, "getitimer");
        symbol(&setitimerLinux, "setitimer");
        symbol(&vforkLinux, "vfork");
        symbol(&posix_spawnattr_init, "posix_spawnattr_init");
        symbol(&posix_spawnattr_getflags, "posix_spawnattr_getflags");
        symbol(&posix_spawnattr_setflags, "posix_spawnattr_setflags");
        symbol(&posix_spawnattr_getpgroup, "posix_spawnattr_getpgroup");
        symbol(&posix_spawnattr_setpgroup, "posix_spawnattr_setpgroup");
        symbol(&posix_spawnattr_getsigdefault, "posix_spawnattr_getsigdefault");
        symbol(&posix_spawnattr_setsigdefault, "posix_spawnattr_setsigdefault");
        symbol(&posix_spawnattr_getsigmask, "posix_spawnattr_getsigmask");
        symbol(&posix_spawnattr_setsigmask, "posix_spawnattr_setsigmask");
        symbol(&posix_spawn_file_actions_init, "posix_spawn_file_actions_init");
    }
    if (builtin.link_libc) {
        symbol(&execvImpl, "execv");
        symbol(&posix_spawn_file_actions_addclose_impl, "posix_spawn_file_actions_addclose");
        symbol(&posix_spawn_file_actions_adddup2_impl, "posix_spawn_file_actions_adddup2");
        symbol(&posix_spawn_file_actions_addopen_impl, "posix_spawn_file_actions_addopen");
        symbol(&posix_spawn_file_actions_addchdir_impl, "posix_spawn_file_actions_addchdir_np");
        symbol(&posix_spawn_file_actions_addfchdir_impl, "posix_spawn_file_actions_addfchdir_np");
        symbol(&posix_spawn_file_actions_destroy_impl, "posix_spawn_file_actions_destroy");
        symbol(&__execvpe, "__execvpe");
        symbol(&execvpImpl, "execvp");
        symbol(&execlImpl, "execl");
        symbol(&execleImpl, "execle");
        symbol(&execlpImpl, "execlp");
        symbol(&systemImpl, "system");
    }
}

fn raiseLinux(sig: c_int) callconv(.c) c_int {
    var set: sigset_t = undefined;
    _ = linux.sigprocmask(linux.SIG.BLOCK, &app_mask, &set);
    const ret = errno(linux.tkill(linux.gettid(), @enumFromInt(@as(u32, @bitCast(sig)))));
    _ = linux.sigprocmask(linux.SIG.SETMASK, &set, null);
    return ret;
}

fn errnoP(r: usize) linux.pid_t {
    const signed: isize = @bitCast(r);
    if (signed < 0) {
        @branchHint(.unlikely);
        std.c._errno().* = @intCast(-signed);
        return -1;
    }
    return @intCast(signed);
}

fn waitLinux(status: ?*c_int) callconv(.c) linux.pid_t {
    return waitpidLinux(-1, status, 0);
}

fn waitpidLinux(pid: linux.pid_t, status: ?*c_int, options: c_int) callconv(.c) linux.pid_t {
    return errnoP(linux.syscall4(
        .wait4,
        @as(usize, @bitCast(@as(isize, pid))),
        @intFromPtr(status),
        @as(usize, @bitCast(@as(isize, options))),
        0,
    ));
}

fn waitidLinux(idtype: c_uint, id: c_uint, info: ?*linux.siginfo_t, options: c_int) callconv(.c) c_int {
    return errno(linux.syscall5(
        .waitid,
        @as(usize, idtype),
        @as(usize, id),
        @intFromPtr(info),
        @as(usize, @bitCast(@as(isize, options))),
        0,
    ));
}

// Fallback signal restorer stubs. Architecture-specific .s files provide
// real implementations where the kernel sigaction struct uses sa_restorer.
fn __restore() callconv(.c) void {}

fn __restore_rt() callconv(.c) void {}

fn getitimerLinux(which: c_int, old: *itimerval) callconv(.c) c_int {
    return errno(linux.syscall2(.getitimer, @as(usize, @bitCast(@as(isize, which))), @intFromPtr(old)));
}

fn setitimerLinux(which: c_int, new: *const itimerval, old: ?*itimerval) callconv(.c) c_int {
    return errno(linux.syscall3(.setitimer, @as(usize, @bitCast(@as(isize, which))), @intFromPtr(new), @intFromPtr(old)));
}

fn vforkLinux() callconv(.c) linux.pid_t {
    // Fallback: vfork cannot be correctly implemented in C/Zig.
    // Architecture-specific .s files provide real vfork where available.
    const r: isize = @bitCast(linux.fork());
    if (r < 0) {
        @branchHint(.unlikely);
        std.c._errno().* = @intCast(-r);
        return -1;
    }
    return @intCast(r);
}

fn posix_spawnattr_init(attr: *posix_spawnattr_t) callconv(.c) c_int {
    @memset(std.mem.asBytes(attr), 0);
    return 0;
}

fn posix_spawnattr_getflags(attr: *const posix_spawnattr_t, flags: *c_short) callconv(.c) c_int {
    flags.* = @intCast(attr.__flags);
    return 0;
}

fn posix_spawnattr_setflags(attr: *posix_spawnattr_t, flags: c_short) callconv(.c) c_int {
    const all_flags: c_uint = 0x1 | 0x2 | 0x4 | 0x8 | 0x10 | 0x20 | 0x40 | 0x80;
    if (@as(c_uint, @bitCast(@as(c_int, flags))) & ~all_flags != 0)
        return @intFromEnum(linux.E.INVAL);
    attr.__flags = flags;
    return 0;
}

fn posix_spawnattr_getpgroup(attr: *const posix_spawnattr_t, pgrp: *linux.pid_t) callconv(.c) c_int {
    pgrp.* = attr.__pgrp;
    return 0;
}

fn posix_spawnattr_setpgroup(attr: *posix_spawnattr_t, pgrp: linux.pid_t) callconv(.c) c_int {
    attr.__pgrp = pgrp;
    return 0;
}

fn posix_spawnattr_getsigdefault(attr: *const posix_spawnattr_t, def: *musl_sigset_t) callconv(.c) c_int {
    def.* = attr.__def;
    return 0;
}

fn posix_spawnattr_setsigdefault(attr: *posix_spawnattr_t, def: *const musl_sigset_t) callconv(.c) c_int {
    attr.__def = def.*;
    return 0;
}

fn posix_spawnattr_getsigmask(attr: *const posix_spawnattr_t, mask: *musl_sigset_t) callconv(.c) c_int {
    mask.* = attr.__mask;
    return 0;
}

fn posix_spawnattr_setsigmask(attr: *posix_spawnattr_t, mask: *const musl_sigset_t) callconv(.c) c_int {
    attr.__mask = mask.*;
    return 0;
}

fn posix_spawn_file_actions_init(fa: *posix_spawn_file_actions_t) callconv(.c) c_int {
    fa.__actions = null;
    return 0;
}

fn execvImpl(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) callconv(.c) c_int {
    return execve(path, argv, @ptrCast(&__environ));
}

fn allocFdop(extra: usize) ?*fdop {
    const ptr = malloc(@sizeOf(fdop) + extra) orelse return null;
    return @ptrCast(@alignCast(ptr));
}

fn prependOp(fa: *posix_spawn_file_actions_t, op: *fdop) void {
    op.next = @ptrCast(@alignCast(fa.__actions));
    if (@as(?*fdop, @ptrCast(@alignCast(fa.__actions)))) |existing| existing.prev = op;
    op.prev = null;
    fa.__actions = @ptrCast(op);
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
    var op: ?*fdop = @ptrCast(@alignCast(fa.__actions));
    while (op) |o| {
        const next = o.next;
        free(@ptrCast(o));
        op = next;
    }
    return 0;
}

fn strchrnul(s: [*]const u8, c: u8) [*]const u8 {
    var p = s;
    while (p[0] != 0 and p[0] != c) p += 1;
    return p;
}

fn strnlen(s: [*]const u8, max: usize) usize {
    var i: usize = 0;
    while (i < max and s[i] != 0) i += 1;
    return i;
}

fn __execvpe(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) callconv(.c) c_int {
    std.c._errno().* = @intFromEnum(linux.E.NOENT);
    if (file[0] == 0) return -1;

    // If file contains '/', exec directly
    if (std.mem.indexOfScalar(u8, std.mem.span(file), '/') != null)
        return execve(file, argv, envp);

    const path = getenv("PATH") orelse "/usr/local/bin:/bin:/usr/bin";
    const k = strnlen(file, NAME_MAX + 1);
    if (k > NAME_MAX) {
        std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
        return -1;
    }
    const l = strnlen(path, PATH_MAX - 1) + 1;

    var buf: [PATH_MAX + NAME_MAX + 2]u8 = undefined;
    var seen_eacces = false;
    var p: [*]const u8 = path;

    while (true) {
        const z = strchrnul(p, ':');
        const seg_len = @intFromPtr(z) - @intFromPtr(p);
        if (seg_len < l) {
            @memcpy(buf[0..seg_len], p[0..seg_len]);
            var pos = seg_len;
            if (seg_len > 0) {
                buf[pos] = '/';
                pos += 1;
            }
            @memcpy(buf[pos..][0 .. k + 1], file[0 .. k + 1]);
            buf[pos + k] = 0;
            _ = execve(@ptrCast(buf[0 .. pos + k :0]), argv, envp);
            switch (@as(linux.E, @enumFromInt(std.c._errno().*))) {
                .ACCES => seen_eacces = true,
                .NOENT, .NOTDIR => {},
                else => return -1,
            }
        }
        if (z[0] == 0) break;
        p = z + 1;
    }
    if (seen_eacces) std.c._errno().* = @intFromEnum(linux.E.ACCES);
    return -1;
}

fn execvpImpl(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) callconv(.c) c_int {
    return __execvpe(file, argv, @ptrCast(&__environ));
}

fn execlImpl(path: [*:0]const u8, argv0: ?[*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    var argv_buf: [MAX_ARGS + 1]?[*:0]const u8 = undefined;
    argv_buf[0] = argv0;
    var argc: usize = 1;
    while (argc < MAX_ARGS) : (argc += 1) {
        argv_buf[argc] = @cVaArg(&ap, ?[*:0]const u8);
        if (argv_buf[argc] == null) break;
    }
    argv_buf[argc] = null;

    return execve(path, @ptrCast(&argv_buf), @ptrCast(&__environ));
}

fn execleImpl(path: [*:0]const u8, argv0: ?[*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    var argv_buf: [MAX_ARGS + 1]?[*:0]const u8 = undefined;
    argv_buf[0] = argv0;
    var argc: usize = 1;
    while (argc < MAX_ARGS) : (argc += 1) {
        argv_buf[argc] = @cVaArg(&ap, ?[*:0]const u8);
        if (argv_buf[argc] == null) break;
    }
    argv_buf[argc] = null;
    // envp follows the null terminator
    const envp = @cVaArg(&ap, [*:null]const ?[*:0]const u8);

    return execve(path, @ptrCast(&argv_buf), envp);
}

fn execlpImpl(file: [*:0]const u8, argv0: ?[*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    var argv_buf: [MAX_ARGS + 1]?[*:0]const u8 = undefined;
    argv_buf[0] = argv0;
    var argc: usize = 1;
    while (argc < MAX_ARGS) : (argc += 1) {
        argv_buf[argc] = @cVaArg(&ap, ?[*:0]const u8);
        if (argv_buf[argc] == null) break;
    }
    argv_buf[argc] = null;

    return execvp(file, @ptrCast(&argv_buf));
}

fn systemImpl(cmd: ?[*:0]const u8) callconv(.c) c_int {
    pthread_testcancel();

    if (cmd == null) return 1;

    var sa: c_sigaction = .{ .handler = SIG_IGN, .mask = @splat(0), .flags = 0, .restorer = null };
    var oldint: c_sigaction = undefined;
    var oldquit: c_sigaction = undefined;
    _ = sigaction(SIGINT, &sa, &oldint);
    _ = sigaction(SIGQUIT, &sa, &oldquit);
    _ = sigaddset(&sa.mask, SIGCHLD);

    var old: musl_sigset_t = undefined;
    _ = sigprocmask(SIG_BLOCK, &sa.mask, &old);

    var reset: musl_sigset_t = undefined;
    _ = sigemptyset(&reset);
    if (oldint.handler != SIG_IGN) _ = sigaddset(&reset, SIGINT);
    if (oldquit.handler != SIG_IGN) _ = sigaddset(&reset, SIGQUIT);

    var attr: posix_spawnattr_t = undefined;
    _ = posix_spawnattr_init(&attr);
    _ = posix_spawnattr_setsigmask(&attr, &old);
    _ = posix_spawnattr_setsigdefault(&attr, &reset);
    _ = posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK);

    var pid: linux.pid_t = undefined;
    var argv = [4:null]?[*:0]const u8{ "sh", "-c", cmd, null };
    const ret = posix_spawn(&pid, "/bin/sh", null, &attr, @ptrCast(&argv), @ptrCast(&__environ));
    _ = posix_spawnattr_destroy(&attr);

    var status: c_int = -1;
    if (ret == 0) {
        while (waitpid(pid, &status, 0) < 0) {
            if (std.c._errno().* != @intFromEnum(linux.E.INTR)) break;
        }
    }

    _ = sigaction(SIGINT, &oldint, null);
    _ = sigaction(SIGQUIT, &oldquit, null);
    _ = sigprocmask(SIG_SETMASK, &old, null);

    if (ret != 0) std.c._errno().* = ret;
    return status;
}
