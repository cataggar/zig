const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;
const c = @import("../c.zig");
const mq_timedsend_sys = if (@hasField(linux.SYS, "mq_timedsend")) linux.SYS.mq_timedsend else linux.SYS.mq_timedsend_time64;
const mq_timedreceive_sys = if (@hasField(linux.SYS, "mq_timedreceive")) linux.SYS.mq_timedreceive else linux.SYS.mq_timedreceive_time64;

comptime {
    if (builtin.target.isMuslLibC()) {
        c.symbol(&mq_closeLinux, "mq_close");
        c.symbol(&mq_getattrLinux, "mq_getattr");
        c.symbol(&mq_openLinux, "mq_open");
        c.symbol(&mq_receiveLinux, "mq_receive");
        c.symbol(&mq_sendLinux, "mq_send");
        c.symbol(&mq_setattrLinux, "mq_setattr");
        c.symbol(&mq_timedreceiveLinux, "mq_timedreceive");
        c.symbol(&mq_timedsendLinux, "mq_timedsend");
        c.symbol(&mq_unlinkLinux, "mq_unlink");
    }
    if (builtin.link_libc) {
        c.symbol(&mq_notifyLinux, "mq_notify");
    }
}

fn mq_closeLinux(mqdes: c_int) callconv(.c) c_int {
    return c.errno(linux.close(mqdes));
}

fn mq_getattrLinux(mqdes: c_int, attr: ?*anyopaque) callconv(.c) c_int {
    return mq_setattrLinux(mqdes, null, attr);
}

fn mq_setattrLinux(mqdes: c_int, new_attr: ?*const anyopaque, old_attr: ?*anyopaque) callconv(.c) c_int {
    return c.errno(linux.syscall3(
        .mq_getsetattr,
        iarg(mqdes),
        @intFromPtr(new_attr),
        @intFromPtr(old_attr),
    ));
}

fn mq_openLinux(raw_name: [*:0]const u8, flags: c_int, mode_arg: c_uint, attr_arg: ?*anyopaque) callconv(.c) c_int {
    const name = @intFromPtr(raw_name) + @as(usize, if (raw_name[0] == '/') 1 else 0);
    const has_create = (flags & 0o100) != 0; // O_CREAT
    const mode: usize = if (has_create) mode_arg else 0;
    const attr: usize = if (has_create) @intFromPtr(attr_arg) else 0;
    return c.errno(linux.syscall4(.mq_open, name, iarg(flags), mode, attr));
}

fn mq_sendLinux(mqdes: c_int, msg: [*]const u8, len: usize, prio: c_uint) callconv(.c) c_int {
    return mq_timedsendLinux(mqdes, msg, len, prio, null);
}

fn mq_receiveLinux(mqdes: c_int, msg: [*]u8, len: usize, prio: ?*c_uint) callconv(.c) isize {
    return mq_timedreceiveLinux(mqdes, msg, len, prio, null);
}

fn mq_timedsendLinux(mqdes: c_int, msg: [*]const u8, len: usize, prio: c_uint, at: ?*const linux.timespec) callconv(.c) c_int {
    return c.errno(linux.syscall5(
        mq_timedsend_sys,
        iarg(mqdes),
        @intFromPtr(msg),
        len,
        @as(usize, prio),
        @intFromPtr(at),
    ));
}

fn mq_timedreceiveLinux(mqdes: c_int, msg: [*]u8, len: usize, prio: ?*c_uint, at: ?*const linux.timespec) callconv(.c) isize {
    const ret = linux.syscall5(
        mq_timedreceive_sys,
        iarg(mqdes),
        @intFromPtr(msg),
        len,
        @intFromPtr(prio),
        @intFromPtr(at),
    );
    const signed: isize = @bitCast(ret);
    if (signed > -4096 and signed < 0) {
        @branchHint(.unlikely);
        std.c._errno().* = @intCast(-signed);
        return -1;
    }
    return signed;
}

fn mq_unlinkLinux(raw_name: [*:0]const u8) callconv(.c) c_int {
    const name = @intFromPtr(raw_name) + @as(usize, if (raw_name[0] == '/') 1 else 0);
    const ret: isize = @bitCast(linux.syscall1(.mq_unlink, name));
    if (ret < 0) {
        var err: c_int = @intCast(-ret);
        if (err == @intFromEnum(linux.E.PERM)) err = @intFromEnum(linux.E.ACCES);
        std.c._errno().* = err;
        return -1;
    }
    return @intCast(ret);
}

/// Convert a c_int (e.g. file descriptor) to usize for syscall arguments.
fn iarg(v: c_int) usize {
    return @bitCast(@as(isize, v));
}

// --- mq_notify with SIGEV_THREAD support ---

const SIGEV_THREAD: c_int = 2;
const PTHREAD_CANCEL_DISABLE: c_int = 1;

const pthread_t = *opaque {};
const pthread_attr_t = extern struct { data: [if (@sizeOf(c_ulong) == 8) 56 else 36]u8 = @splat(0) };
const sem_t = extern struct { __val: [4 * @sizeOf(c_long) / @sizeOf(c_int)]c_int = @splat(0) };

const sigval_t = extern union {
    int: c_int,
    ptr: ?*anyopaque,
};

const sigevent_t = extern struct {
    value: sigval_t,
    signo: c_int,
    notify: c_int,
    un: extern union {
        pad: [pad_size]c_int,
        tid: c_int,
        thread: extern struct {
            function: ?*const fn (sigval_t) callconv(.c) void,
            attribute: ?*anyopaque,
        },
    },

    const max_size = 64;
    const preamble_size = @sizeOf(c_int) * 2 + @sizeOf(sigval_t);
    const pad_size = (max_size - preamble_size) / @sizeOf(c_int);
};

const NotifyArgs = struct {
    sem: sem_t,
    sock: c_int,
    mqd: c_int,
    err: c_int,
    sev: *const sigevent_t,
};

var notify_zeros: [32]u8 = @splat(0);

fn notifyStartFn(p: ?*anyopaque) callconv(.c) ?*anyopaque {
    const args: *NotifyArgs = @ptrCast(@alignCast(p));
    var buf: [32]u8 = undefined;
    const s = args.sock;
    const func = args.sev.un.thread.function.?;
    const val = args.sev.value;

    // Register with kernel: SIGEV_THREAD with socket fd for notification delivery
    var sev2 = std.mem.zeroes(sigevent_t);
    sev2.notify = SIGEV_THREAD;
    sev2.signo = s;
    sev2.value.ptr = &notify_zeros;

    const r: isize = @bitCast(linux.syscall2(
        .mq_notify,
        iarg(args.mqd),
        @intFromPtr(&sev2),
    ));
    args.err = if (r < 0) @intCast(-r) else 0;
    _ = sem_post(&args.sem);
    if (r < 0) return null;

    _ = pthread_detach(pthread_self());
    const n: isize = @bitCast(linux.recvfrom(
        s,
        &buf,
        32,
        linux.MSG.NOSIGNAL | linux.MSG.WAITALL,
        null,
        null,
    ));
    _ = linux.close(s);
    if (n == 32 and buf[31] == 1) {
        func(val);
    }
    return null;
}

extern "c" fn pthread_attr_setdetachstate(attr: *pthread_attr_t, state: c_int) c_int;
extern "c" fn pthread_detach(thread: pthread_t) c_int;
extern "c" fn pthread_self() pthread_t;
extern "c" fn pthread_attr_init(attr: *pthread_attr_t) c_int;
extern "c" fn pthread_create(thread: *pthread_t, attr: ?*const pthread_attr_t, start_routine: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, arg: ?*anyopaque) c_int;
extern "c" fn pthread_setcancelstate(state: c_int, oldstate: ?*c_int) c_int;
extern "c" fn pthread_join(thread: pthread_t, retval: ?*?*anyopaque) c_int;
extern "c" fn sem_init(sem: *sem_t, pshared: c_int, value: c_uint) c_int;
extern "c" fn sem_post(sem: *sem_t) c_int;
extern "c" fn sem_wait(sem: *sem_t) c_int;
extern "c" fn sem_destroy(sem: *sem_t) c_int;

fn mq_notifyLinux(mqd: c_int, sev: ?*const sigevent_t) callconv(.c) c_int {
    if (sev == null or sev.?.notify != SIGEV_THREAD) {
        return c.errno(linux.syscall2(
            .mq_notify,
            iarg(mqd),
            @intFromPtr(sev),
        ));
    }

    const s_ret: isize = @bitCast(linux.socket(
        linux.AF.NETLINK,
        linux.SOCK.RAW | linux.SOCK.CLOEXEC,
        0,
    ));
    if (s_ret < 0) return -1;
    const s: c_int = @intCast(s_ret);

    var args = NotifyArgs{
        .sem = undefined,
        .sock = s,
        .mqd = mqd,
        .err = 0,
        .sev = sev.?,
    };

    var attr: pthread_attr_t = undefined;
    const maybe_user_attr: ?*const pthread_attr_t = @ptrCast(@alignCast(sev.?.un.thread.attribute));
    if (maybe_user_attr) |user_attr| {
        attr = user_attr.*;
    } else {
        _ = pthread_attr_init(&attr);
    }
    _ = pthread_attr_setdetachstate(&attr, 0); // PTHREAD_CREATE_JOINABLE

    _ = sem_init(&args.sem, 0, 0);

    // Block all signals during thread creation
    var allmask = linux.sigfillset();
    var origmask: linux.sigset_t = undefined;
    _ = linux.sigprocmask(0, &allmask, &origmask); // SIG_BLOCK = 0

    var td: pthread_t = undefined;
    if (pthread_create(&td, &attr, &notifyStartFn, @ptrCast(&args)) != 0) {
        _ = linux.close(s);
        _ = linux.sigprocmask(2, &origmask, null); // SIG_SETMASK = 2
        std.c._errno().* = @intCast(@intFromEnum(linux.E.AGAIN));
        return -1;
    }
    _ = linux.sigprocmask(2, &origmask, null); // SIG_SETMASK = 2

    var old_cs: c_int = undefined;
    _ = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &old_cs);
    _ = sem_wait(&args.sem);
    _ = sem_destroy(&args.sem);

    if (args.err != 0) {
        _ = linux.close(s);
        _ = pthread_join(td, null);
        _ = pthread_setcancelstate(old_cs, null);
        std.c._errno().* = args.err;
        return -1;
    }

    _ = pthread_setcancelstate(old_cs, null);
    return 0;
}
