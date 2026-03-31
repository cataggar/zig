const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;

const E = std.os.linux.E;

comptime {
    if (builtin.target.isMuslLibC()) {
        // Destroy functions (all return 0, releasing no resources)
        symbol(&pthread_attr_destroy, "pthread_attr_destroy");
        symbol(&pthread_mutexattr_destroy, "pthread_mutexattr_destroy");
        symbol(&pthread_condattr_destroy, "pthread_condattr_destroy");
        symbol(&pthread_rwlockattr_destroy, "pthread_rwlockattr_destroy");
        symbol(&pthread_barrierattr_destroy, "pthread_barrierattr_destroy");
        symbol(&pthread_spin_destroy, "pthread_spin_destroy");
        symbol(&pthread_rwlock_destroy, "pthread_rwlock_destroy");
        symbol(&sem_destroy, "sem_destroy");

        // Concurrency stubs (no-ops on Linux, which always uses 1:1 threading)
        symbol(&pthread_getconcurrency, "pthread_getconcurrency");
        symbol(&pthread_setconcurrency, "pthread_setconcurrency");

        // Priority ceiling not supported by musl
        symbol(&pthread_mutex_getprioceiling, "pthread_mutex_getprioceiling");

        // C11 thread destroy stubs (no-ops for private objects)
        symbol(&cnd_destroy, "cnd_destroy");
        symbol(&mtx_destroy, "mtx_destroy");

        // Thread comparison
        symbol(&pthread_equal, "pthread_equal");
        symbol(&pthread_equal, "thrd_equal");

        // Attribute init functions (zero-initialize)
        symbol(&pthread_mutexattr_init, "pthread_mutexattr_init");
        symbol(&pthread_condattr_init, "pthread_condattr_init");
        symbol(&pthread_rwlockattr_init, "pthread_rwlockattr_init");
        symbol(&pthread_barrierattr_init, "pthread_barrierattr_init");
        symbol(&pthread_spin_init, "pthread_spin_init");

        // Attribute set functions
        symbol(&pthread_mutexattr_settype, "pthread_mutexattr_settype");
        symbol(&pthread_mutexattr_setpshared, "pthread_mutexattr_setpshared");
        symbol(&pthread_condattr_setclock, "pthread_condattr_setclock");
        symbol(&pthread_condattr_setpshared, "pthread_condattr_setpshared");
        symbol(&pthread_rwlockattr_setpshared, "pthread_rwlockattr_setpshared");
        symbol(&pthread_barrierattr_setpshared, "pthread_barrierattr_setpshared");
        symbol(&pthread_attr_setscope, "pthread_attr_setscope");

        // Attribute getters (all from pthread_attr_get.c)
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

        // pthread_attr_t setters
        symbol(&pthread_attr_setdetachstate, "pthread_attr_setdetachstate");
        symbol(&pthread_attr_setguardsize, "pthread_attr_setguardsize");
        symbol(&pthread_attr_setinheritsched, "pthread_attr_setinheritsched");
        symbol(&pthread_attr_setschedparam, "pthread_attr_setschedparam");
        symbol(&pthread_attr_setschedpolicy, "pthread_attr_setschedpolicy");
        symbol(&pthread_attr_setstack, "pthread_attr_setstack");
        symbol(&pthread_attr_setstacksize, "pthread_attr_setstacksize");

        // Spin lock operations (atomics)
        symbol(&pthread_spin_lock, "pthread_spin_lock");
        symbol(&pthread_spin_trylock, "pthread_spin_trylock");
        symbol(&pthread_spin_unlock, "pthread_spin_unlock");

        // Mutex, rwlock, cond, barrier init
        symbol(&pthread_mutex_init, "pthread_mutex_init");
        symbol(&pthread_rwlock_init, "pthread_rwlock_init");
        symbol(&pthread_cond_init, "pthread_cond_init");
        symbol(&pthread_barrier_init, "pthread_barrier_init");

        // Prioceiling set (not supported)
        symbol(&pthread_mutex_setprioceiling, "pthread_mutex_setprioceiling");

        // Semaphore init/getvalue
        symbol(&sem_init, "sem_init");
        symbol(&sem_getvalue, "sem_getvalue");

        // C11 thread init and yield
        symbol(&cnd_init, "cnd_init");
        symbol(&mtx_init, "mtx_init");
        symbol(&thrd_yield, "thrd_yield");

        // C11 thread wrappers (depend on musl internal functions)
        if (builtin.link_libc) {
            symbol(&call_once, "call_once");
            symbol(&tss_create, "tss_create");
            symbol(&tss_delete, "tss_delete");
            symbol(&cnd_signal, "cnd_signal");
            symbol(&cnd_broadcast, "cnd_broadcast");
            symbol(&cnd_timedwait, "cnd_timedwait");
            symbol(&cnd_wait, "cnd_wait");
            symbol(&mtx_lock, "mtx_lock");
            symbol(&mtx_timedlock, "mtx_timedlock");
            symbol(&mtx_trylock, "mtx_trylock");
            symbol(&mtx_unlock, "mtx_unlock");
        }
    }
}

// All pthread/semaphore destroy functions return 0 because musl's
// implementations hold no dynamically-allocated resources.

fn pthread_attr_destroy(a: ?*anyopaque) callconv(.c) c_int {
    _ = a;
    return 0;
}

fn pthread_mutexattr_destroy(a: ?*anyopaque) callconv(.c) c_int {
    _ = a;
    return 0;
}

fn pthread_condattr_destroy(a: ?*anyopaque) callconv(.c) c_int {
    _ = a;
    return 0;
}

fn pthread_rwlockattr_destroy(a: ?*anyopaque) callconv(.c) c_int {
    _ = a;
    return 0;
}

fn pthread_barrierattr_destroy(a: ?*anyopaque) callconv(.c) c_int {
    _ = a;
    return 0;
}

fn pthread_spin_destroy(s: ?*anyopaque) callconv(.c) c_int {
    _ = s;
    return 0;
}

fn pthread_rwlock_destroy(rw: ?*anyopaque) callconv(.c) c_int {
    _ = rw;
    return 0;
}

fn sem_destroy(sem: ?*anyopaque) callconv(.c) c_int {
    _ = sem;
    return 0;
}

// Linux always uses 1:1 threading; concurrency hints are no-ops.

fn pthread_getconcurrency() callconv(.c) c_int {
    return 0;
}

fn pthread_setconcurrency(val: c_int) callconv(.c) c_int {
    if (val < 0) return eint(.INVAL);
    if (val > 0) return eint(.AGAIN);
    return 0;
}

// Priority ceiling is not supported by musl.

fn pthread_mutex_getprioceiling(m: ?*const anyopaque, ceiling: ?*c_int) callconv(.c) c_int {
    _ = m;
    _ = ceiling;
    return eint(.INVAL);
}

// C11 thread destroy stubs.

fn cnd_destroy(c: ?*anyopaque) callconv(.c) void {
    _ = c;
}

fn mtx_destroy(mtx: ?*anyopaque) callconv(.c) void {
    _ = mtx;
}

// Thread identity comparison.

fn pthread_equal(a: std.c.pthread_t, b: std.c.pthread_t) callconv(.c) c_int {
    return @intCast(@intFromBool(a == b));
}

/// Convert a Linux errno enum value to a positive c_int for direct return
/// from POSIX thread functions (which return error numbers, not -1).
fn eint(e: E) c_int {
    return @intCast(@intFromEnum(e));
}

// Comptime errno constants for use in switch cases.
const c_EBUSY: c_int = @intCast(@intFromEnum(E.BUSY));
const c_ETIMEDOUT: c_int = @intCast(@intFromEnum(E.TIMEDOUT));

// --- Musl internal type definitions ---
// These match the musl libc type layouts exactly.

/// `typedef struct { unsigned __attr; } pthread_mutexattr_t;`
const pthread_mutexattr_t = extern struct { __attr: c_uint = 0 };

/// `typedef struct { unsigned __attr; } pthread_condattr_t;`
const pthread_condattr_t = extern struct { __attr: c_uint = 0 };

/// `typedef struct { unsigned __attr; } pthread_barrierattr_t;`
const pthread_barrierattr_t = extern struct { __attr: c_uint = 0 };

/// `typedef struct { unsigned __attr[2]; } pthread_rwlockattr_t;`
const pthread_rwlockattr_t = extern struct { __attr: [2]c_uint = .{ 0, 0 } };

// --- Attribute init functions ---

fn pthread_mutexattr_init(a: *pthread_mutexattr_t) callconv(.c) c_int {
    a.* = .{};
    return 0;
}

fn pthread_condattr_init(a: *pthread_condattr_t) callconv(.c) c_int {
    a.* = .{};
    return 0;
}

fn pthread_rwlockattr_init(a: *pthread_rwlockattr_t) callconv(.c) c_int {
    a.* = .{};
    return 0;
}

fn pthread_barrierattr_init(a: *pthread_barrierattr_t) callconv(.c) c_int {
    a.* = .{};
    return 0;
}

fn pthread_spin_init(s: *c_int, shared: c_int) callconv(.c) c_int {
    _ = shared;
    s.* = 0;
    return 0;
}

// --- Attribute set functions ---

fn pthread_mutexattr_settype(a: *pthread_mutexattr_t, @"type": c_int) callconv(.c) c_int {
    const t: c_uint = @bitCast(@"type");
    if (t > 2) return eint(.INVAL);
    a.__attr = (a.__attr & ~@as(c_uint, 3)) | t;
    return 0;
}

fn pthread_mutexattr_setpshared(a: *pthread_mutexattr_t, pshared: c_int) callconv(.c) c_int {
    const ps: c_uint = @bitCast(pshared);
    if (ps > 1) return eint(.INVAL);
    a.__attr &= ~@as(c_uint, 128);
    a.__attr |= ps << 7;
    return 0;
}

fn pthread_condattr_setclock(a: *pthread_condattr_t, clk: c_int) callconv(.c) c_int {
    if (clk < 0) return eint(.INVAL);
    const clk_u: c_uint = @intCast(clk);
    if (clk_u -% 2 < 2) return eint(.INVAL);
    a.__attr &= 0x80000000;
    a.__attr |= clk_u;
    return 0;
}

fn pthread_condattr_setpshared(a: *pthread_condattr_t, pshared: c_int) callconv(.c) c_int {
    const ps: c_uint = @bitCast(pshared);
    if (ps > 1) return eint(.INVAL);
    a.__attr &= 0x7fffffff;
    a.__attr |= ps << 31;
    return 0;
}

fn pthread_rwlockattr_setpshared(a: *pthread_rwlockattr_t, pshared: c_int) callconv(.c) c_int {
    const ps: c_uint = @bitCast(pshared);
    if (ps > 1) return eint(.INVAL);
    a.__attr[0] = ps;
    return 0;
}

fn pthread_barrierattr_setpshared(a: *pthread_barrierattr_t, pshared: c_int) callconv(.c) c_int {
    const ps: c_uint = @bitCast(pshared);
    if (ps > 1) return eint(.INVAL);
    a.__attr = if (pshared != 0) 0x80000000 else 0;
    return 0;
}

fn pthread_attr_setscope(a: ?*anyopaque, scope: c_int) callconv(.c) c_int {
    _ = a;
    return switch (scope) {
        0 => 0, // PTHREAD_SCOPE_SYSTEM
        1 => eint(.OPNOTSUPP), // PTHREAD_SCOPE_PROCESS
        else => eint(.INVAL),
    };
}

// --- pthread_attr_t layout ---
// Matches musl's union-based layout: three size_t fields followed by int fields.
// See musl/src/internal/pthread_impl.h for the _a_* accessor macros.

const pthread_attr_t = extern struct {
    _a_stacksize: usize = 0,
    _a_guardsize: usize = 0,
    _a_stackaddr: usize = 0,
    _a_detach: c_int = 0,
    _a_sched: c_int = 0,
    _a_policy: c_int = 0,
    _a_prio: c_int = 0,
    _padding: [attr_padding]u8 = [_]u8{0} ** attr_padding,

    const attr_total = if (@sizeOf(c_ulong) == 8) @as(usize, 56) else 36;
    const attr_padding = attr_total - 3 * @sizeOf(usize) - 4 * @sizeOf(c_int);
};

/// Only the first field is accessed; remaining musl sched_param fields are padding.
const sched_param = extern struct {
    sched_priority: c_int,
};

const PTHREAD_STACK_MIN: usize = 2048;

// --- Attribute getters (all from pthread_attr_get.c) ---

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

fn pthread_attr_getscope(a: *const pthread_attr_t, scope: *c_int) callconv(.c) c_int {
    _ = a;
    scope.* = 0; // PTHREAD_SCOPE_SYSTEM
    return 0;
}

fn pthread_attr_getstack(a: *const pthread_attr_t, addr: *usize, size: *usize) callconv(.c) c_int {
    if (a._a_stackaddr == 0) return eint(.INVAL);
    size.* = a._a_stacksize;
    addr.* = a._a_stackaddr -% size.*;
    return 0;
}

fn pthread_attr_getstacksize(a: *const pthread_attr_t, size: *usize) callconv(.c) c_int {
    size.* = a._a_stacksize;
    return 0;
}

fn pthread_barrierattr_getpshared(a: *const pthread_barrierattr_t, pshared: *c_int) callconv(.c) c_int {
    pshared.* = @intCast(@intFromBool(a.__attr != 0));
    return 0;
}

fn pthread_condattr_getclock(a: *const pthread_condattr_t, clk: *c_int) callconv(.c) c_int {
    clk.* = @bitCast(a.__attr & 0x7fffffff);
    return 0;
}

fn pthread_condattr_getpshared(a: *const pthread_condattr_t, pshared: *c_int) callconv(.c) c_int {
    pshared.* = @bitCast(a.__attr >> 31);
    return 0;
}

fn pthread_mutexattr_getprotocol(a: *const pthread_mutexattr_t, protocol: *c_int) callconv(.c) c_int {
    protocol.* = @bitCast(a.__attr / 8 % 2);
    return 0;
}

fn pthread_mutexattr_getpshared(a: *const pthread_mutexattr_t, pshared: *c_int) callconv(.c) c_int {
    pshared.* = @bitCast(a.__attr / 128 % 2);
    return 0;
}

fn pthread_mutexattr_getrobust(a: *const pthread_mutexattr_t, robust: *c_int) callconv(.c) c_int {
    robust.* = @bitCast(a.__attr / 4 % 2);
    return 0;
}

fn pthread_mutexattr_gettype(a: *const pthread_mutexattr_t, @"type": *c_int) callconv(.c) c_int {
    @"type".* = @bitCast(a.__attr & 3);
    return 0;
}

fn pthread_rwlockattr_getpshared(a: *const pthread_rwlockattr_t, pshared: *c_int) callconv(.c) c_int {
    pshared.* = @bitCast(a.__attr[0]);
    return 0;
}

// --- pthread_attr_t setters ---

fn pthread_attr_setdetachstate(a: *pthread_attr_t, state: c_int) callconv(.c) c_int {
    const s: c_uint = @bitCast(state);
    if (s > 1) return eint(.INVAL);
    a._a_detach = state;
    return 0;
}

fn pthread_attr_setguardsize(a: *pthread_attr_t, size: usize) callconv(.c) c_int {
    if (size > std.math.maxInt(usize) / 8) return eint(.INVAL);
    a._a_guardsize = size;
    return 0;
}

fn pthread_attr_setinheritsched(a: *pthread_attr_t, inherit: c_int) callconv(.c) c_int {
    const i: c_uint = @bitCast(inherit);
    if (i > 1) return eint(.INVAL);
    a._a_sched = inherit;
    return 0;
}

fn pthread_attr_setschedparam(a: *pthread_attr_t, param: *const sched_param) callconv(.c) c_int {
    a._a_prio = param.sched_priority;
    return 0;
}

fn pthread_attr_setschedpolicy(a: *pthread_attr_t, policy: c_int) callconv(.c) c_int {
    a._a_policy = policy;
    return 0;
}

fn pthread_attr_setstack(a: *pthread_attr_t, addr: usize, size: usize) callconv(.c) c_int {
    if (size -% PTHREAD_STACK_MIN > std.math.maxInt(usize) / 4) return eint(.INVAL);
    a._a_stackaddr = addr +% size;
    a._a_stacksize = size;
    return 0;
}

fn pthread_attr_setstacksize(a: *pthread_attr_t, size: usize) callconv(.c) c_int {
    if (size -% PTHREAD_STACK_MIN > std.math.maxInt(usize) / 4) return eint(.INVAL);
    a._a_stackaddr = 0;
    a._a_stacksize = size;
    return 0;
}

// --- Spin lock operations ---

fn pthread_spin_lock(s: *c_int) callconv(.c) c_int {
    while (@atomicLoad(c_int, s, .monotonic) != 0 or
        @cmpxchgWeak(c_int, s, 0, eint(.BUSY), .seq_cst, .seq_cst) != null)
    {
        std.atomic.spinLoopHint();
    }
    return 0;
}

fn pthread_spin_trylock(s: *c_int) callconv(.c) c_int {
    return @cmpxchgStrong(c_int, s, 0, eint(.BUSY), .seq_cst, .seq_cst) orelse 0;
}

fn pthread_spin_unlock(s: *c_int) callconv(.c) c_int {
    @atomicStore(c_int, s, 0, .seq_cst);
    return 0;
}

// --- Synchronization object init ---

const mutex_size = if (@sizeOf(c_ulong) == 8) @as(usize, 40) else 24;
const pthread_mutex_impl = extern struct {
    _m_type: c_int = 0,
    _m_lock: c_int = 0,
    _padding: [mutex_size - 2 * @sizeOf(c_int)]u8 = [_]u8{0} ** (mutex_size - 2 * @sizeOf(c_int)),
};

fn pthread_mutex_init(m: *pthread_mutex_impl, a: ?*const pthread_mutexattr_t) callconv(.c) c_int {
    m.* = .{};
    if (a) |attr| m._m_type = @bitCast(attr.__attr);
    return 0;
}

const rwlock_size = if (@sizeOf(c_ulong) == 8) @as(usize, 56) else 32;
const pthread_rwlock_impl = extern struct {
    _rw_lock: c_int = 0,
    _rw_waiters: c_int = 0,
    _rw_shared: c_int = 0,
    _padding: [rwlock_size - 3 * @sizeOf(c_int)]u8 = [_]u8{0} ** (rwlock_size - 3 * @sizeOf(c_int)),
};

fn pthread_rwlock_init(rw: *pthread_rwlock_impl, a: ?*const pthread_rwlockattr_t) callconv(.c) c_int {
    rw.* = .{};
    if (a) |attr| rw._rw_shared = @bitCast(attr.__attr[0] * @as(c_uint, 128));
    return 0;
}

const pthread_cond_impl = extern struct {
    _c_shared: usize = 0,
    _pad1: [16 - @sizeOf(usize)]u8 = [_]u8{0} ** (16 - @sizeOf(usize)),
    _c_clock: c_int = 0,
    _pad2: [48 - 16 - @sizeOf(c_int)]u8 = [_]u8{0} ** (48 - 16 - @sizeOf(c_int)),
};

fn pthread_cond_init(c: *pthread_cond_impl, a: ?*const pthread_condattr_t) callconv(.c) c_int {
    c.* = .{};
    if (a) |attr| {
        c._c_clock = @bitCast(attr.__attr & 0x7fffffff);
        if (attr.__attr >> 31 != 0) c._c_shared = std.math.maxInt(usize);
    }
    return 0;
}

const barrier_size = if (@sizeOf(c_ulong) == 8) @as(usize, 32) else 20;
const pthread_barrier_impl = extern struct {
    _b_lock: c_int = 0,
    _b_waiters: c_int = 0,
    _b_limit: c_int = 0,
    _padding: [barrier_size - 3 * @sizeOf(c_int)]u8 = [_]u8{0} ** (barrier_size - 3 * @sizeOf(c_int)),
};

fn pthread_barrier_init(b: *pthread_barrier_impl, a: ?*const pthread_barrierattr_t, count: c_uint) callconv(.c) c_int {
    if (count -% 1 > 0x7FFFFFFE) return eint(.INVAL);
    b.* = .{};
    b._b_limit = @bitCast((count -% 1) | if (a) |attr| attr.__attr else 0);
    return 0;
}

// Priority ceiling set is not supported by musl (same as get).

fn pthread_mutex_setprioceiling(m: ?*anyopaque, ceiling: c_int, old: ?*c_int) callconv(.c) c_int {
    _ = m;
    _ = ceiling;
    _ = old;
    return eint(.INVAL);
}

// --- Semaphore init/getvalue ---

const sem_val_len = 4 * @sizeOf(c_long) / @sizeOf(c_int);
const sem_impl = extern struct {
    __val: [sem_val_len]c_int = [_]c_int{0} ** sem_val_len,
};

fn sem_init(sem: *sem_impl, pshared: c_int, value: c_uint) callconv(.c) c_int {
    if (value > 0x7fffffff) {
        std.c._errno().* = @intCast(@intFromEnum(E.INVAL));
        return -1;
    }
    sem.__val[0] = @bitCast(value);
    sem.__val[1] = 0;
    sem.__val[2] = if (pshared != 0) 0 else 128;
    return 0;
}

fn sem_getvalue(sem: *const sem_impl, valp: *c_int) callconv(.c) c_int {
    valp.* = sem.__val[0] & 0x7fffffff;
    return 0;
}

// --- C11 thread functions ---

fn cnd_init(c: *pthread_cond_impl) callconv(.c) c_int {
    c.* = .{};
    return 0; // thrd_success
}

fn mtx_init(m: *pthread_mutex_impl, @"type": c_int) callconv(.c) c_int {
    m.* = .{};
    // mtx_recursive (1) maps to PTHREAD_MUTEX_RECURSIVE (1)
    m._m_type = if (@"type" & 1 != 0) 1 else 0;
    return 0; // thrd_success
}

fn thrd_yield() callconv(.c) void {
    _ = std.os.linux.syscall0(.sched_yield);
}

// C11 thread wrappers that delegate to musl internal pthread functions.
// Gated behind builtin.link_libc since they depend on C-provided symbols.

fn call_once(flag: *c_int, func: *const fn () callconv(.c) void) callconv(.c) void {
    const __pthread_once = @extern(*const fn (*c_int, *const fn () callconv(.c) void) callconv(.c) c_int, .{ .name = "__pthread_once" });
    _ = __pthread_once(flag, func);
}

fn tss_create(tss: *c_uint, dtor: ?*const fn (?*anyopaque) callconv(.c) void) callconv(.c) c_int {
    const __pthread_key_create = @extern(*const fn (*c_uint, ?*const fn (?*anyopaque) callconv(.c) void) callconv(.c) c_int, .{ .name = "__pthread_key_create" });
    return if (__pthread_key_create(tss, dtor) != 0) 1 else 0; // thrd_error : thrd_success
}

fn tss_delete(key: c_uint) callconv(.c) void {
    const __pthread_key_delete = @extern(*const fn (c_uint) callconv(.c) c_int, .{ .name = "__pthread_key_delete" });
    _ = __pthread_key_delete(key);
}

fn cnd_signal(c: ?*anyopaque) callconv(.c) c_int {
    const __private_cond_signal = @extern(*const fn (?*anyopaque, c_int) callconv(.c) c_int, .{ .name = "__private_cond_signal" });
    return __private_cond_signal(c, 1);
}

fn cnd_broadcast(c: ?*anyopaque) callconv(.c) c_int {
    const __private_cond_signal = @extern(*const fn (?*anyopaque, c_int) callconv(.c) c_int, .{ .name = "__private_cond_signal" });
    return __private_cond_signal(c, -1);
}

fn cnd_timedwait(c: ?*anyopaque, m: ?*anyopaque, ts: ?*const anyopaque) callconv(.c) c_int {
    const __pthread_cond_timedwait = @extern(*const fn (?*anyopaque, ?*anyopaque, ?*const anyopaque) callconv(.c) c_int, .{ .name = "__pthread_cond_timedwait" });
    const ret = __pthread_cond_timedwait(c, m, ts);
    return switch (ret) {
        0 => 0, // thrd_success
        c_ETIMEDOUT => 3, // thrd_timedout
        else => 1, // thrd_error
    };
}

fn cnd_wait(c: ?*anyopaque, m: ?*anyopaque) callconv(.c) c_int {
    return cnd_timedwait(c, m, null);
}

fn mtx_lock(m: *pthread_mutex_impl) callconv(.c) c_int {
    if (m._m_type == 0 and @cmpxchgWeak(c_int, &m._m_lock, 0, c_EBUSY, .seq_cst, .seq_cst) == null) {
        return 0; // thrd_success - fast path for PTHREAD_MUTEX_NORMAL
    }
    return mtx_timedlock(@ptrCast(m), null);
}

fn mtx_timedlock(m: ?*anyopaque, ts: ?*const anyopaque) callconv(.c) c_int {
    const __pthread_mutex_timedlock = @extern(*const fn (?*anyopaque, ?*const anyopaque) callconv(.c) c_int, .{ .name = "__pthread_mutex_timedlock" });
    const ret = __pthread_mutex_timedlock(m, ts);
    return switch (ret) {
        0 => 0, // thrd_success
        c_ETIMEDOUT => 3, // thrd_timedout
        else => 1, // thrd_error
    };
}

fn mtx_trylock(m: *pthread_mutex_impl) callconv(.c) c_int {
    if (m._m_type == 0) {
        return if (@cmpxchgStrong(c_int, &m._m_lock, 0, c_EBUSY, .seq_cst, .seq_cst) != null) 4 else 0;
    }
    const __pthread_mutex_trylock = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "__pthread_mutex_trylock" });
    const ret = __pthread_mutex_trylock(@ptrCast(m));
    return switch (ret) {
        0 => 0, // thrd_success
        c_EBUSY => 4, // thrd_busy
        else => 1, // thrd_error
    };
}

fn mtx_unlock(mtx: ?*anyopaque) callconv(.c) c_int {
    const __pthread_mutex_unlock = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "__pthread_mutex_unlock" });
    return __pthread_mutex_unlock(mtx);
}

