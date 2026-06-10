const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;
const symbol = @import("../c.zig").symbol;

const E = linux.E;
const SYS_futex = if (@hasField(linux.SYS, "futex")) linux.SYS.futex else linux.SYS.futex_time64;
const FUTEX_WAIT: usize = 0;
const FUTEX_WAKE: usize = 1;
const FUTEX_PRIVATE: usize = 128;
const SEM_VALUE_MAX: c_int = 0x7fffffff;
const INT_MAX: c_int = std.math.maxInt(c_int);

const thrd_success: c_int = 0;
const thrd_busy: c_int = 1;
const thrd_error: c_int = 2;
const thrd_timedout: c_int = 4;
const mtx_recursive: c_int = 1;
const PTHREAD_MUTEX_NORMAL: c_int = 0;
const PTHREAD_MUTEX_RECURSIVE: c_int = 1;

const pthread_mutexattr_t = extern struct { __attr: c_uint = 0 };
const pthread_condattr_t = extern struct { __attr: c_uint = 0 };
const pthread_barrierattr_t = extern struct { __attr: c_uint = 0 };
const pthread_rwlockattr_t = extern struct { __attr: [2]c_uint = .{ 0, 0 } };
const sched_param = extern struct { sched_priority: c_int };

const pthread_attr_t = extern struct {
    _a_stacksize: usize = 0,
    _a_guardsize: usize = 0,
    _a_stackaddr: usize = 0,
    _a_detach: c_int = 0,
    _a_sched: c_int = 0,
    _a_policy: c_int = 0,
    _a_prio: c_int = 0,
    _padding: [attr_padding]u8 = @splat(0),

    const attr_total = if (@sizeOf(c_ulong) == 8) @as(usize, 56) else 36;
    const attr_padding = attr_total - 3 * @sizeOf(usize) - 4 * @sizeOf(c_int);
};

const mutex_size = if (@sizeOf(c_ulong) == 8) @as(usize, 40) else 24;
const pthread_mutex_impl = extern struct {
    _m_type: c_int = 0,
    _m_lock: c_int = 0,
    _padding: [mutex_size - 2 * @sizeOf(c_int)]u8 = @splat(0),
};

const sem_val_len = 4 * @sizeOf(c_long) / @sizeOf(c_int);
const sem_impl = extern struct { __val: [sem_val_len]c_int = @splat(0) };

const rwlock_int_count: usize = if (@sizeOf(c_long) == 8) 14 else 8;
var ptc_lock: [rwlock_int_count]c_int = @splat(0);
var vmlock: [2]c_int = .{ 0, 0 };
var vmlock_lockptr: *c_int = &vmlock[0];

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&pthread_attr_destroy, "pthread_attr_destroy");
        symbol(&pthread_attr_getdetachstate, "pthread_attr_getdetachstate");
        symbol(&pthread_attr_getguardsize, "pthread_attr_getguardsize");
        symbol(&pthread_attr_getinheritsched, "pthread_attr_getinheritsched");
        symbol(&pthread_attr_getschedparam, "pthread_attr_getschedparam");
        symbol(&pthread_attr_getschedpolicy, "pthread_attr_getschedpolicy");
        symbol(&pthread_attr_getscope, "pthread_attr_getscope");
        symbol(&pthread_attr_getstack, "pthread_attr_getstack");
        symbol(&pthread_attr_getstacksize, "pthread_attr_getstacksize");
        symbol(&pthread_barrierattr_getpshared, "pthread_barrierattr_getpshared");
        symbol(&pthread_condattr_getclock, "pthread_condattr_getclock");
        symbol(&pthread_condattr_getpshared, "pthread_condattr_getpshared");
        symbol(&pthread_mutexattr_getprotocol, "pthread_mutexattr_getprotocol");
        symbol(&pthread_mutexattr_getpshared, "pthread_mutexattr_getpshared");
        symbol(&pthread_mutexattr_getrobust, "pthread_mutexattr_getrobust");
        symbol(&pthread_mutexattr_gettype, "pthread_mutexattr_gettype");
        symbol(&pthread_rwlockattr_getpshared, "pthread_rwlockattr_getpshared");

        symbol(&mtx_destroy, "mtx_destroy");
        symbol(&mtx_init, "mtx_init");
        symbol(&mtx_lock, "mtx_lock");
        symbol(&mtx_timedlock, "mtx_timedlock");
        symbol(&mtx_trylock, "mtx_trylock");
        symbol(&mtx_unlock, "mtx_unlock");

        symbol(&sem_destroy, "sem_destroy");
        symbol(&sem_getvalue, "sem_getvalue");
        symbol(&sem_init, "sem_init");

        symbol(&tss_create, "tss_create");
        symbol(&tss_delete, "tss_delete");

        symbol(&inhibit_ptc, "__inhibit_ptc");
        symbol(&acquire_ptc, "__acquire_ptc");
        symbol(&release_ptc, "__release_ptc");
        symbol(&wait, "__wait");
        symbol(&vm_wait, "__vm_wait");
        symbol(&vm_lock, "__vm_lock");
        symbol(&vm_unlock, "__vm_unlock");
        @export(&vmlock_lockptr, .{ .name = "__vmlock_lockptr", .linkage = .weak, .visibility = .hidden });
    }
}

fn eint(e: E) c_int {
    return @intCast(@intFromEnum(e));
}

fn pthread_attr_destroy(_: ?*anyopaque) callconv(.c) c_int {
    return 0;
}

fn pthread_attr_getdetachstate(a: *const pthread_attr_t, state: *c_int) callconv(.c) c_int {
    state.* = a._a_detach;
    return 0;
}

fn pthread_attr_getguardsize(a: *const pthread_attr_t, size: *usize) callconv(.c) c_int {
    size.* = a._a_guardsize;
    return 0;
}

fn pthread_attr_getinheritsched(a: *const pthread_attr_t, inherit: *c_int) callconv(.c) c_int {
    inherit.* = a._a_sched;
    return 0;
}

fn pthread_attr_getschedparam(a: *const pthread_attr_t, param: *sched_param) callconv(.c) c_int {
    param.sched_priority = a._a_prio;
    return 0;
}

fn pthread_attr_getschedpolicy(a: *const pthread_attr_t, policy: *c_int) callconv(.c) c_int {
    policy.* = a._a_policy;
    return 0;
}

fn pthread_attr_getscope(_: *const pthread_attr_t, scope: *c_int) callconv(.c) c_int {
    scope.* = 0;
    return 0;
}

fn pthread_attr_getstack(a: *const pthread_attr_t, addr: *?*anyopaque, size: *usize) callconv(.c) c_int {
    if (a._a_stackaddr == 0) return eint(.INVAL);
    size.* = a._a_stacksize;
    addr.* = @ptrFromInt(a._a_stackaddr - size.*);
    return 0;
}

fn pthread_attr_getstacksize(a: *const pthread_attr_t, size: *usize) callconv(.c) c_int {
    size.* = a._a_stacksize;
    return 0;
}

fn pthread_barrierattr_getpshared(a: *const pthread_barrierattr_t, pshared: *c_int) callconv(.c) c_int {
    pshared.* = @intFromBool(a.__attr != 0);
    return 0;
}

fn pthread_condattr_getclock(a: *const pthread_condattr_t, clk: *c_int) callconv(.c) c_int {
    clk.* = @bitCast(a.__attr & 0x7fffffff);
    return 0;
}

fn pthread_condattr_getpshared(a: *const pthread_condattr_t, pshared: *c_int) callconv(.c) c_int {
    pshared.* = @intCast(a.__attr >> 31);
    return 0;
}

fn pthread_mutexattr_getprotocol(a: *const pthread_mutexattr_t, protocol: *c_int) callconv(.c) c_int {
    protocol.* = @intCast((a.__attr / 8) % 2);
    return 0;
}

fn pthread_mutexattr_getpshared(a: *const pthread_mutexattr_t, pshared: *c_int) callconv(.c) c_int {
    pshared.* = @intCast((a.__attr / 128) % 2);
    return 0;
}

fn pthread_mutexattr_getrobust(a: *const pthread_mutexattr_t, robust: *c_int) callconv(.c) c_int {
    robust.* = @intCast((a.__attr / 4) % 2);
    return 0;
}

fn pthread_mutexattr_gettype(a: *const pthread_mutexattr_t, t: *c_int) callconv(.c) c_int {
    t.* = @intCast(a.__attr & 3);
    return 0;
}

fn pthread_rwlockattr_getpshared(a: *const pthread_rwlockattr_t, pshared: *c_int) callconv(.c) c_int {
    pshared.* = @bitCast(a.__attr[0]);
    return 0;
}

fn mtx_destroy(_: ?*anyopaque) callconv(.c) void {}

fn mtx_init(m: *pthread_mutex_impl, t: c_int) callconv(.c) c_int {
    m.* = .{};
    m._m_type = if ((t & mtx_recursive) != 0) PTHREAD_MUTEX_RECURSIVE else PTHREAD_MUTEX_NORMAL;
    return thrd_success;
}

fn mtx_lock(m: *pthread_mutex_impl) callconv(.c) c_int {
    if (m._m_type == PTHREAD_MUTEX_NORMAL and @cmpxchgStrong(c_int, &m._m_lock, 0, eint(.BUSY), .seq_cst, .seq_cst) == null)
        return thrd_success;
    return mtx_timedlock(@ptrCast(m), null);
}

fn mtx_timedlock(m: *anyopaque, ts: ?*const anyopaque) callconv(.c) c_int {
    const __pthread_mutex_timedlock = @extern(*const fn (*anyopaque, ?*const anyopaque) callconv(.c) c_int, .{ .name = "__pthread_mutex_timedlock" });
    return switch (__pthread_mutex_timedlock(m, ts)) {
        0 => thrd_success,
        @as(c_int, @intCast(@intFromEnum(E.TIMEDOUT))) => thrd_timedout,
        else => thrd_error,
    };
}

fn mtx_trylock(m: *pthread_mutex_impl) callconv(.c) c_int {
    if (m._m_type == PTHREAD_MUTEX_NORMAL) {
        return if (@cmpxchgStrong(c_int, &m._m_lock, 0, eint(.BUSY), .seq_cst, .seq_cst) == null)
            thrd_success
        else
            thrd_busy;
    }
    const __pthread_mutex_trylock = @extern(*const fn (*anyopaque) callconv(.c) c_int, .{ .name = "__pthread_mutex_trylock" });
    return switch (__pthread_mutex_trylock(@ptrCast(m))) {
        0 => thrd_success,
        @as(c_int, @intCast(@intFromEnum(E.BUSY))) => thrd_busy,
        else => thrd_error,
    };
}

fn mtx_unlock(m: *anyopaque) callconv(.c) c_int {
    const __pthread_mutex_unlock = @extern(*const fn (*anyopaque) callconv(.c) c_int, .{ .name = "__pthread_mutex_unlock" });
    return __pthread_mutex_unlock(m);
}

fn sem_destroy(_: ?*anyopaque) callconv(.c) c_int {
    return 0;
}

fn sem_getvalue(sem: *const sem_impl, valp: *c_int) callconv(.c) c_int {
    valp.* = sem.__val[0] & SEM_VALUE_MAX;
    return 0;
}

fn sem_init(sem: *sem_impl, pshared: c_int, value: c_uint) callconv(.c) c_int {
    if (value > SEM_VALUE_MAX) {
        std.c._errno().* = eint(.INVAL);
        return -1;
    }
    sem.__val[0] = @bitCast(value);
    sem.__val[1] = 0;
    sem.__val[2] = if (pshared != 0) 0 else 128;
    return 0;
}

fn tss_create(tss: *c_uint, dtor: ?*const fn (?*anyopaque) callconv(.c) void) callconv(.c) c_int {
    const __pthread_key_create = @extern(*const fn (*c_uint, ?*const fn (?*anyopaque) callconv(.c) void) callconv(.c) c_int, .{ .name = "__pthread_key_create" });
    return if (__pthread_key_create(tss, dtor) != 0) thrd_error else thrd_success;
}

fn tss_delete(key: c_uint) callconv(.c) void {
    const __pthread_key_delete = @extern(*const fn (c_uint) callconv(.c) c_int, .{ .name = "__pthread_key_delete" });
    _ = __pthread_key_delete(key);
}

fn inhibit_ptc() callconv(.c) void {
    const pthread_rwlock_wrlock = @extern(*const fn (*anyopaque) callconv(.c) c_int, .{ .name = "pthread_rwlock_wrlock" });
    _ = pthread_rwlock_wrlock(@ptrCast(&ptc_lock));
}

fn acquire_ptc() callconv(.c) void {
    const pthread_rwlock_rdlock = @extern(*const fn (*anyopaque) callconv(.c) c_int, .{ .name = "pthread_rwlock_rdlock" });
    _ = pthread_rwlock_rdlock(@ptrCast(&ptc_lock));
}

fn release_ptc() callconv(.c) void {
    const pthread_rwlock_unlock = @extern(*const fn (*anyopaque) callconv(.c) c_int, .{ .name = "pthread_rwlock_unlock" });
    _ = pthread_rwlock_unlock(@ptrCast(&ptc_lock));
}

fn futexWake(addr: *c_int, count: c_int, private: bool) void {
    const priv: usize = if (private) FUTEX_PRIVATE else 0;
    const n: usize = if (count < 0) @intCast(INT_MAX) else @intCast(count);
    const rc: isize = @bitCast(linux.syscall3(SYS_futex, @intFromPtr(addr), FUTEX_WAKE | priv, n));
    if (rc == -@as(isize, @intCast(@intFromEnum(E.NOSYS)))) {
        _ = linux.syscall3(SYS_futex, @intFromPtr(addr), FUTEX_WAKE, n);
    }
}

fn wait(addr: *c_int, waiters: ?*c_int, val: c_int, priv_arg: c_int) callconv(.c) void {
    var spins: c_int = 100;
    const private = priv_arg != 0;
    while (spins > 0) : (spins -= 1) {
        if (waiters) |w| if (@atomicLoad(c_int, w, .monotonic) != 0) break;
        if (@atomicLoad(c_int, addr, .monotonic) == val) {
            std.atomic.spinLoopHint();
        } else return;
    }
    if (waiters) |w| _ = @atomicRmw(c_int, w, .Add, 1, .seq_cst);
    while (@atomicLoad(c_int, addr, .monotonic) == val) {
        const priv: usize = if (private) FUTEX_PRIVATE else 0;
        const val_u: usize = @bitCast(@as(isize, val));
        const rc: isize = @bitCast(linux.syscall4(SYS_futex, @intFromPtr(addr), FUTEX_WAIT | priv, val_u, 0));
        if (rc == -@as(isize, @intCast(@intFromEnum(E.NOSYS)))) {
            _ = linux.syscall4(SYS_futex, @intFromPtr(addr), FUTEX_WAIT, val_u, 0);
        }
    }
    if (waiters) |w| _ = @atomicRmw(c_int, w, .Add, -1, .seq_cst);
}

fn vm_wait() callconv(.c) void {
    while (true) {
        const tmp = @atomicLoad(c_int, &vmlock[0], .monotonic);
        if (tmp == 0) break;
        wait(&vmlock[0], &vmlock[1], tmp, 1);
    }
}

fn vm_lock() callconv(.c) void {
    _ = @atomicRmw(c_int, &vmlock[0], .Add, 1, .seq_cst);
}

fn vm_unlock() callconv(.c) void {
    if (@atomicRmw(c_int, &vmlock[0], .Add, -1, .seq_cst) == 1 and
        @atomicLoad(c_int, &vmlock[1], .monotonic) != 0)
    {
        futexWake(&vmlock[0], -1, true);
    }
}
