const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const c = @import("../c.zig");

/// Musl libc sigset_t: 1024-bit signal set, matching the C ABI.
const sigset_t = std.c.sigset_t;

/// Matches the musl `posix_spawnattr_t` layout from spawn.h.
const posix_spawnattr_t = extern struct {
    __flags: c_int,
    __pgrp: c_int,
    __def: sigset_t,
    __mask: sigset_t,
    __prio: c_int,
    __pol: c_int,
    __fn: ?*anyopaque,
    __pad: [64 - @sizeOf(?*anyopaque)]u8,
};

comptime {
    if (builtin.target.isMuslLibC()) {
        c.symbol(&posix_spawnattr_destroy, "posix_spawnattr_destroy");
        c.symbol(&posix_spawnattr_getschedparam, "posix_spawnattr_getschedparam");
        c.symbol(&posix_spawnattr_setschedparam, "posix_spawnattr_setschedparam");
        c.symbol(&posix_spawnattr_getschedpolicy, "posix_spawnattr_getschedpolicy");
        c.symbol(&posix_spawnattr_setschedpolicy, "posix_spawnattr_setschedpolicy");
        c.symbol(&posix_spawn_impl, "posix_spawn");
        c.symbol(&posix_spawnp_impl, "posix_spawnp");
    }
}

fn posix_spawnattr_init(attr: *posix_spawnattr_t) callconv(.c) c_int {
    attr.* = std.mem.zeroes(posix_spawnattr_t);
    return 0;
}

fn posix_spawnattr_destroy(_: *posix_spawnattr_t) callconv(.c) c_int {
    return 0;
}

fn posix_spawnattr_getflags(attr: *const posix_spawnattr_t, flags: *c_short) callconv(.c) c_int {
    flags.* = @intCast(attr.__flags);
    return 0;
}

fn posix_spawnattr_setflags(attr: *posix_spawnattr_t, flags: c_short) callconv(.c) c_int {
    const all_flags: c_uint = 0x1 | 0x2 | 0x4 | 0x8 | 0x10 | 0x20 | 0x40 | 0x80;
    if (@as(c_uint, @bitCast(@as(c_int, flags))) & ~all_flags != 0) {
        return @intFromEnum(linux.E.INVAL);
    }
    attr.__flags = flags;
    return 0;
}

fn posix_spawnattr_getpgroup(attr: *const posix_spawnattr_t, pgrp: *c_int) callconv(.c) c_int {
    pgrp.* = attr.__pgrp;
    return 0;
}

fn posix_spawnattr_setpgroup(attr: *posix_spawnattr_t, pgrp: c_int) callconv(.c) c_int {
    attr.__pgrp = pgrp;
    return 0;
}

fn posix_spawnattr_getsigdefault(attr: *const posix_spawnattr_t, def: *sigset_t) callconv(.c) c_int {
    def.* = attr.__def;
    return 0;
}

fn posix_spawnattr_setsigdefault(attr: *posix_spawnattr_t, def: *const sigset_t) callconv(.c) c_int {
    attr.__def = def.*;
    return 0;
}

fn posix_spawnattr_getsigmask(attr: *const posix_spawnattr_t, mask: *sigset_t) callconv(.c) c_int {
    mask.* = attr.__mask;
    return 0;
}

fn posix_spawnattr_setsigmask(attr: *posix_spawnattr_t, mask: *const sigset_t) callconv(.c) c_int {
    attr.__mask = mask.*;
    return 0;
}

fn posix_spawnattr_getschedparam(_: *const posix_spawnattr_t, _: *anyopaque) callconv(.c) c_int {
    return @intFromEnum(linux.E.NOSYS);
}

fn posix_spawnattr_setschedparam(_: *posix_spawnattr_t, _: *const anyopaque) callconv(.c) c_int {
    return @intFromEnum(linux.E.NOSYS);
}

fn posix_spawnattr_getschedpolicy(_: *const posix_spawnattr_t, _: *c_int) callconv(.c) c_int {
    return @intFromEnum(linux.E.NOSYS);
}

fn posix_spawnattr_setschedpolicy(_: *posix_spawnattr_t, _: c_int) callconv(.c) c_int {
    return @intFromEnum(linux.E.NOSYS);
}

// posix_spawn implementation (ported from musl src/process/posix_spawn.c).
// posix_spawnp is the trivial PATH-search wrapper from src/process/posix_spawnp.c.
// File-action layout (`fdop` + `posix_spawn_file_actions_t`) and the FDOP_*
// command discriminators mirror musl's fdop.h verbatim so the existing
// add{close,dup2,open,chdir,fchdir} family living in lib/c/process.zig can
// continue to construct the list without any binary changes.

const fdop = extern struct {
    next: ?*fdop,
    prev: ?*fdop,
    cmd: c_int,
    fd: c_int,
    srcfd: c_int,
    oflag: c_int,
    mode: linux.mode_t,
    // flexible array member follows: path[] for FDOP_OPEN/FDOP_CHDIR.
};

const posix_spawn_file_actions_t = extern struct {
    __pad0: [2]c_int,
    __actions: ?*anyopaque,
    __pad: [16]c_int,
};

const FDOP_CLOSE: c_int = 1;
const FDOP_DUP2: c_int = 2;
const FDOP_OPEN: c_int = 3;
const FDOP_CHDIR: c_int = 4;
const FDOP_FCHDIR: c_int = 5;

const POSIX_SPAWN_RESETIDS: c_int = 0x1;
const POSIX_SPAWN_SETPGROUP: c_int = 0x2;
const POSIX_SPAWN_SETSIGDEF: c_int = 0x4;
const POSIX_SPAWN_SETSIGMASK: c_int = 0x8;
const POSIX_SPAWN_SETSID: c_int = 0x80;

const PTHREAD_CANCEL_DISABLE: c_int = 1;

const SIG_BLOCK: c_int = 0;
const SIG_SETMASK: c_int = 2;
const F_GETFD: c_int = linux.F.GETFD;
const F_SETFD: c_int = linux.F.SETFD;
const FD_CLOEXEC: c_int = linux.FD_CLOEXEC;

// O_CLOEXEC value for the live target's `O` flag union, used when calling
// libc `pipe2`.
const O_CLOEXEC: c_int = blk: {
    const o = linux.O{ .CLOEXEC = true };
    break :blk @bitCast(@as(u32, @bitCast(o)));
};

// LARGEFILE bit (where the arch's `O` defines it), ORed into the flags we
// pass to the open/openat syscalls, matching musl's `__sys_open` macro.
const O_LARGEFILE: u32 = blk: {
    if (@hasField(linux.O, "LARGEFILE")) {
        const o = linux.O{ .LARGEFILE = true };
        break :blk @bitCast(o);
    }
    break :blk 0;
};

// Musl's `struct sigaction` (kept binary-compatible with lib/c/signal.zig's
// definition so we can call `__libc_sigaction` here).
const c_sigaction = extern struct {
    handler: ?*align(1) const fn (c_int) callconv(.c) void,
    mask: [128 / @sizeOf(c_ulong)]c_ulong,
    flags: c_int,
    restorer: ?*const fn () callconv(.c) void,
};
const SIG_DFL: ?*align(1) const fn (c_int) callconv(.c) void = @ptrFromInt(0);
const SIG_IGN: ?*align(1) const fn (c_int) callconv(.c) void = @ptrFromInt(1);

// musl-internal helpers and libc entry points used by the child path.
extern var __abort_lock: c_int;
extern "c" fn __lock(lock: *c_int) void;
extern "c" fn __unlock(lock: *c_int) void;
extern "c" fn __get_handler_set(set: *sigset_t) void;
extern "c" fn __libc_sigaction(sig: c_int, sa: ?*const c_sigaction, old: ?*c_sigaction) callconv(.c) c_int;
extern "c" fn __execvpe(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) callconv(.c) c_int;
extern "c" fn pthread_setcancelstate(state: c_int, oldstate: ?*c_int) callconv(.c) c_int;
extern "c" fn pthread_sigmask(how: c_int, set: ?*const sigset_t, oldset: ?*sigset_t) callconv(.c) c_int;
extern "c" fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) callconv(.c) c_int;
extern "c" fn sigismember(set: *const sigset_t, sig: c_int) callconv(.c) c_int;
extern "c" fn pipe2(fds: *[2]c_int, flags: c_int) callconv(.c) c_int;
extern "c" fn close(fd: c_int) callconv(.c) c_int;
extern "c" fn read(fd: c_int, buf: *anyopaque, count: usize) callconv(.c) isize;
extern "c" fn waitpid(pid: linux.pid_t, status: ?*c_int, options: c_int) callconv(.c) linux.pid_t;

const execFn = *const fn ([*:0]const u8, [*:null]const ?[*:0]const u8, [*:null]const ?[*:0]const u8) callconv(.c) c_int;

const Args = extern struct {
    p: [2]c_int,
    oldmask: sigset_t,
    path: [*:0]const u8,
    fa: ?*const posix_spawn_file_actions_t,
    attr: *const posix_spawnattr_t,
    argv: [*:null]const ?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
};

const have_sys_dup2 = @hasField(linux.SYS, "dup2");
const have_sys_open = @hasField(linux.SYS, "open");

fn sysDup2(old: c_int, new: c_int) isize {
    if (have_sys_dup2) {
        return @bitCast(linux.syscall2(
            .dup2,
            c.syscallArg(old),
            c.syscallArg(new),
        ));
    } else {
        return @bitCast(linux.syscall3(
            .dup3,
            c.syscallArg(old),
            c.syscallArg(new),
            0,
        ));
    }
}

fn sysOpen(path: [*:0]const u8, flags: c_int, mode: linux.mode_t) isize {
    const fl: u32 = @as(u32, @bitCast(flags)) | O_LARGEFILE;
    if (have_sys_open) {
        return @bitCast(linux.syscall3(
            .open,
            @intFromPtr(path),
            fl,
            mode,
        ));
    } else {
        return @bitCast(linux.syscall4(
            .openat,
            c.syscallArg(@as(isize, linux.AT.FDCWD)),
            @intFromPtr(path),
            fl,
            mode,
        ));
    }
}

fn sysClose(fd: c_int) isize {
    return @bitCast(linux.syscall1(.close, c.syscallArg(fd)));
}

fn sysWrite(fd: c_int, buf: *const anyopaque, count: usize) isize {
    return @bitCast(linux.syscall3(
        .write,
        c.syscallArg(fd),
        @intFromPtr(buf),
        count,
    ));
}

fn sysFcntl(fd: c_int, cmd: c_int, arg: usize) isize {
    // RiscV32 (and other time-bits-32 archs) lack SYS_fcntl; use SYS_fcntl64.
    const SYS_fcntl_compat = if (@hasField(linux.SYS, "fcntl")) linux.SYS.fcntl else linux.SYS.fcntl64;
    return @bitCast(linux.syscall3(
        SYS_fcntl_compat,
        c.syscallArg(fd),
        c.syscallArg(cmd),
        arg,
    ));
}

fn sysDup(fd: c_int) isize {
    return @bitCast(linux.syscall1(.dup, c.syscallArg(fd)));
}

// The child function runs on the parent's stack via CLONE_VM|CLONE_VFORK,
// so until it execs or _exits we must keep memory access strictly to the
// shared args/file_actions and our own stack frame. Library calls that
// might allocate or touch the parent's mutable state (malloc, stdio, the
// non-`__libc_` sigaction wrapper) are not safe here.
fn childImpl(args: *Args) noreturn {
    var sa: c_sigaction = std.mem.zeroes(c_sigaction);
    var ret: isize = 0;
    var p: c_int = args.p[1];
    const attr = args.attr;
    const fa = args.fa;

    _ = sysClose(args.p[0]);

    // All signal dispositions must be either SIG_DFL or SIG_IGN before
    // unblocking, otherwise a parent handler could run in the child while
    // we still share memory.
    var hset: sigset_t = undefined;
    __get_handler_set(&hset);
    var i: c_int = 1;
    while (i < linux.NSIG) : (i += 1) {
        const want_def = (attr.__flags & POSIX_SPAWN_SETSIGDEF) != 0 and
            sigismember(&attr.__def, i) != 0;
        if (want_def) {
            sa.handler = SIG_DFL;
        } else if (sigismember(&hset, i) != 0) {
            if (@as(c_uint, @bitCast(i - 32)) < 3) {
                sa.handler = SIG_IGN;
            } else {
                _ = __libc_sigaction(i, null, &sa);
                if (sa.handler == SIG_IGN) continue;
                sa.handler = SIG_DFL;
            }
        } else {
            continue;
        }
        _ = __libc_sigaction(i, &sa, null);
    }

    if ((attr.__flags & POSIX_SPAWN_SETSID) != 0) {
        ret = @bitCast(linux.syscall0(.setsid));
        if (ret < 0) {
            failExit(p, ret);
        }
    }

    if ((attr.__flags & POSIX_SPAWN_SETPGROUP) != 0) {
        ret = @bitCast(linux.syscall2(
            .setpgid,
            0,
            c.syscallArg(attr.__pgrp),
        ));
        if (ret != 0) {
            failExit(p, ret);
        }
    }

    // Use syscalls directly: the library setuid/setgid wrappers attempt a
    // multi-threaded synchronised id change that would trash parent state.
    if ((attr.__flags & POSIX_SPAWN_RESETIDS) != 0) {
        const gid_ret: isize = @bitCast(linux.syscall0(.getgid));
        ret = @bitCast(linux.syscall1(.setgid, c.syscallArg(gid_ret)));
        if (ret == 0) {
            const uid_ret: isize = @bitCast(linux.syscall0(.getuid));
            ret = @bitCast(linux.syscall1(.setuid, c.syscallArg(uid_ret)));
        }
        if (ret != 0) {
            failExit(p, ret);
        }
    }

    if (fa) |actions_ref| {
        if (actions_ref.__actions) |actions_head_anyopaque| {
            var op: ?*fdop = @ptrCast(@alignCast(actions_head_anyopaque));
            // Walk to the tail of the list...
            while (op.?.next) |next| op = next;
            // ...then replay LIFO (oldest add* call first).
            while (op) |o| : (op = o.prev) {
                // A file operation could clobber the synchronisation pipe;
                // dup it onto an unoccupied fd in that case.
                if (o.fd == p) {
                    const dup_ret = sysDup(p);
                    if (dup_ret < 0) {
                        ret = dup_ret;
                        failExit(p, ret);
                    }
                    _ = sysClose(p);
                    p = @intCast(dup_ret);
                }
                switch (o.cmd) {
                    FDOP_CLOSE => {
                        _ = sysClose(o.fd);
                    },
                    FDOP_DUP2 => {
                        const src = o.srcfd;
                        if (src == p) {
                            ret = -@as(isize, @intFromEnum(linux.E.BADF));
                            failExit(p, ret);
                        }
                        if (src != o.fd) {
                            ret = sysDup2(src, o.fd);
                            if (ret < 0) failExit(p, ret);
                        } else {
                            ret = sysFcntl(src, F_GETFD, 0);
                            if (ret >= 0) {
                                const new_flags: usize = @as(usize, @bitCast(ret)) & ~@as(usize, @intCast(FD_CLOEXEC));
                                ret = sysFcntl(src, F_SETFD, new_flags);
                            }
                            if (ret < 0) failExit(p, ret);
                        }
                    },
                    FDOP_OPEN => {
                        const path_ptr: [*:0]const u8 = @ptrCast(@as([*]const u8, @ptrCast(o)) + @sizeOf(fdop));
                        const open_ret = sysOpen(path_ptr, o.oflag, o.mode);
                        if (open_ret < 0) {
                            ret = open_ret;
                            failExit(p, ret);
                        }
                        const fd: c_int = @intCast(open_ret);
                        if (fd != o.fd) {
                            ret = sysDup2(fd, o.fd);
                            if (ret < 0) failExit(p, ret);
                            _ = sysClose(fd);
                        }
                    },
                    FDOP_CHDIR => {
                        const path_ptr: [*:0]const u8 = @ptrCast(@as([*]const u8, @ptrCast(o)) + @sizeOf(fdop));
                        ret = @bitCast(linux.syscall1(.chdir, @intFromPtr(path_ptr)));
                        if (ret < 0) failExit(p, ret);
                    },
                    FDOP_FCHDIR => {
                        ret = @bitCast(linux.syscall1(
                            .fchdir,
                            c.syscallArg(o.fd),
                        ));
                        if (ret < 0) failExit(p, ret);
                    },
                    else => {},
                }
            }
        }
    }

    // The close-on-exec flag may have been lost if we dup'd the pipe to a
    // different fd above. We don't use F_DUPFD_CLOEXEC there because it
    // would fail on older kernels and atomicity is unnecessary in a child
    // with no threads or signal handlers.
    _ = sysFcntl(p, F_SETFD, FD_CLOEXEC);

    const mask_to_restore: *const sigset_t = if ((attr.__flags & POSIX_SPAWN_SETSIGMASK) != 0)
        &attr.__mask
    else
        &args.oldmask;
    _ = pthread_sigmask(SIG_SETMASK, mask_to_restore, null);

    const exec_fn: execFn = if (attr.__fn) |fnptr|
        @ptrCast(@alignCast(fnptr))
    else
        &execve;

    _ = exec_fn(args.path, args.argv, args.envp);
    // execve only returns on failure; report errno to the parent and exit 127.
    ret = -@as(isize, std.c._errno().*);
    failExit(p, ret);
}

fn failExit(p: c_int, ret_in: isize) noreturn {
    const ret: isize = -ret_in;
    if (ret != 0) {
        // sizeof(int) < PIPE_BUF, so this write is atomic.
        var ec: c_int = @intCast(ret);
        while (true) {
            const r = sysWrite(p, &ec, @sizeOf(c_int));
            if (r >= 0) break;
            if (r == -@as(isize, @intFromEnum(linux.E.PIPE))) break;
        }
    }
    while (true) _ = linux.syscall1(.exit_group, 127);
}

fn childTrampoline(args_addr: usize) callconv(.c) u8 {
    childImpl(@ptrFromInt(args_addr));
}

fn posix_spawn_impl(
    res: ?*linux.pid_t,
    path: [*:0]const u8,
    fa: ?*const posix_spawn_file_actions_t,
    attr: ?*const posix_spawnattr_t,
    argv: [*:null]const ?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
) callconv(.c) c_int {
    var stack: [1024 + linux.PATH_MAX]u8 align(16) = undefined;
    var ec: c_int = 0;
    var cs: c_int = 0;
    var args: Args = undefined;
    const zero_attr: posix_spawnattr_t = std.mem.zeroes(posix_spawnattr_t);

    _ = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cs);

    args.path = path;
    args.fa = fa;
    args.attr = if (attr) |a| a else &zero_attr;
    args.argv = argv;
    args.envp = envp;

    // SIGALL_SET: all-ones sigset_t, used to block every signal while we
    // spawn so a handler can't run in the (shared-VM) child.
    var all_set: sigset_t = undefined;
    @memset(std.mem.asBytes(&all_set), 0xff);
    _ = pthread_sigmask(SIG_BLOCK, &all_set, &args.oldmask);

    // The lock guards both against seeing a SIGABRT disposition change by
    // abort() and against leaking the pipe fd to a forked-without-exec
    // child.
    __lock(&__abort_lock);

    var pid: linux.pid_t = -1;
    if (pipe2(&args.p, O_CLOEXEC) != 0) {
        __unlock(&__abort_lock);
        ec = std.c._errno().*;
    } else {
        const flags: u32 = linux.CLONE.VM | linux.CLONE.VFORK | @intFromEnum(linux.SIG.CHLD);
        const pid_raw = linux.clone(
            &childTrampoline,
            @intFromPtr(&stack) + stack.len,
            flags,
            @intFromPtr(&args),
            null,
            0,
            null,
        );
        _ = close(args.p[1]);
        __unlock(&__abort_lock);

        const pid_signed: isize = @bitCast(pid_raw);
        if (pid_signed > 0) {
            pid = @intCast(pid_signed);
            const n = read(args.p[0], &ec, @sizeOf(c_int));
            if (n != @sizeOf(c_int)) {
                ec = 0;
            } else {
                var status: c_int = 0;
                _ = waitpid(pid, &status, 0);
            }
        } else {
            ec = @intCast(-pid_signed);
        }

        _ = close(args.p[0]);

        if (ec == 0) {
            if (res) |r| r.* = pid;
        }
    }

    _ = pthread_sigmask(SIG_SETMASK, &args.oldmask, null);
    _ = pthread_setcancelstate(cs, null);

    return ec;
}

fn posix_spawnp_impl(
    res: ?*linux.pid_t,
    file: [*:0]const u8,
    fa: ?*const posix_spawn_file_actions_t,
    attr: ?*const posix_spawnattr_t,
    argv: [*:null]const ?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
) callconv(.c) c_int {
    var spawnp_attr: posix_spawnattr_t = std.mem.zeroes(posix_spawnattr_t);
    if (attr) |a| spawnp_attr = a.*;
    spawnp_attr.__fn = @as(*anyopaque, @ptrCast(@constCast(&__execvpe)));
    return posix_spawn_impl(res, file, fa, &spawnp_attr, argv, envp);
}
