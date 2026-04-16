//! WASI thread stubs for single-threaded WASI targets.
//! Minimal pthread implementations that return no-op/error codes or trap
//! when actual threading would be required.

const std = @import("std");
const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

comptime {
    if (!builtin.target.isWasiLibC()) @compileError("wasi_thread_stub is only for WASI");
}

// musl pthread types represented as int arrays matching the union layout in
// pthread_impl.h: struct { union { int __i[N]; volatile int __vi[N]; ... } __u; }
const PthreadMutex = extern struct { __i: [if (@sizeOf(c_long) == 8) 10 else 6]c_int };
const PthreadRwlock = extern struct { __i: [if (@sizeOf(c_long) == 8) 14 else 8]c_int };
const PthreadBarrier = extern struct { __i: [if (@sizeOf(c_long) == 8) 8 else 5]c_int };
const PthreadAttr = extern struct { __i: [if (@sizeOf(c_long) == 8) 14 else 9]c_int };

// musl field index: _a_detach = __u.__i[3*__SU+0] where __SU = sizeof(size_t)/sizeof(int)
const a_detach_idx = 3 * (@sizeOf(usize) / @sizeOf(c_int));

// WASI errno values (from __errno_values.h)
const EAGAIN: c_int = 6;
const EBUSY: c_int = 10;
const EDEADLK: c_int = 16;
const EINVAL: c_int = 28;
const EPERM: c_int = 63;
const ETIMEDOUT: c_int = 73;
const EINTR: c_int = 27;

const PTHREAD_MUTEX_RECURSIVE: c_int = 1;
const PTHREAD_BARRIER_SERIAL_THREAD: c_int = -1;
const PTHREAD_CREATE_DETACHED: c_int = 1;

const CLOCK_REALTIME: c_int = 0;
const TIMER_ABSTIME: c_int = 1;

const INT_MAX: c_uint = @bitCast(std.math.maxInt(c_int));

extern "c" fn clock_nanosleep(clock_id: c_int, flags: c_int, request: *const anyopaque, remain: ?*anyopaque) c_int;

// --- Barrier ---

fn pthread_barrier_destroy(b: ?*anyopaque) callconv(.c) c_int {
    _ = b;
    return 0;
}

fn pthread_barrier_init(b: *PthreadBarrier, a: ?*const anyopaque, count: c_uint) callconv(.c) c_int {
    _ = a;
    if (count -% 1 > INT_MAX - 1) return EINVAL;
    b.* = std.mem.zeroes(PthreadBarrier);
    b.__i[2] = @intCast(count -% 1); // _b_limit
    return 0;
}

fn pthread_barrier_wait(b: *PthreadBarrier) callconv(.c) c_int {
    if (b.__i[2] == 0) return PTHREAD_BARRIER_SERIAL_THREAD; // _b_limit
    @trap();
}

// --- Condition variable ---

fn pthread_cond_broadcast(cv: ?*anyopaque) callconv(.c) c_int {
    _ = cv;
    return 0;
}

fn pthread_cond_destroy(cv: ?*anyopaque) callconv(.c) c_int {
    _ = cv;
    return 0;
}

fn pthread_cond_init(cv: ?*anyopaque, a: ?*const anyopaque) callconv(.c) c_int {
    _ = .{ cv, a };
    return 0;
}

fn pthread_cond_signal(cv: ?*anyopaque) callconv(.c) c_int {
    _ = cv;
    return 0;
}

fn pthread_cond_timedwait(cv: ?*anyopaque, m: *PthreadMutex, ts: *const anyopaque) callconv(.c) c_int {
    _ = cv;
    if (m.__i[5] == 0) return EPERM; // _m_count
    const ret = clock_nanosleep(CLOCK_REALTIME, TIMER_ABSTIME, ts, null);
    if (ret == 0) return ETIMEDOUT;
    if (ret != EINTR) return ret;
    return 0;
}

fn pthread_cond_wait(cv: ?*anyopaque, m: ?*anyopaque) callconv(.c) c_int {
    // No other thread can signal, so this is an immediate deadlock.
    _ = .{ cv, m };
    @trap();
}

// --- Thread lifecycle ---

fn dummy() callconv(.c) void {}

fn pthread_create(res: ?*anyopaque, attrp: ?*const anyopaque, entry: ?*const anyopaque, arg: ?*anyopaque) callconv(.c) c_int {
    _ = .{ res, attrp, entry, arg };
    return EAGAIN;
}

fn pthread_detach(t: ?*anyopaque) callconv(.c) c_int {
    _ = t;
    return 0;
}

fn pthread_getattr_np(t: ?*anyopaque, a: *PthreadAttr) callconv(.c) c_int {
    _ = t;
    a.* = std.mem.zeroes(PthreadAttr);
    a.__i[a_detach_idx] = PTHREAD_CREATE_DETACHED;
    return 0;
}

fn pthread_tryjoin_np(t: ?*anyopaque, res: ?*?*anyopaque) callconv(.c) c_int {
    _ = .{ t, res };
    return 0;
}

fn pthread_timedjoin_np(t: ?*anyopaque, res: ?*?*anyopaque, at: ?*const anyopaque) callconv(.c) c_int {
    _ = .{ t, res, at };
    return 0;
}

fn pthread_join(t: ?*anyopaque, res: ?*?*anyopaque) callconv(.c) c_int {
    _ = .{ t, res };
    return 0;
}

// --- Mutex ---

fn pthread_mutex_consistent(m: ?*anyopaque) callconv(.c) c_int {
    _ = m;
    return EINVAL;
}

fn pthread_mutex_getprioceiling(m: ?*const anyopaque, ceiling: ?*c_int) callconv(.c) c_int {
    _ = .{ m, ceiling };
    return EINVAL;
}

fn pthread_mutex_lock(m: *PthreadMutex) callconv(.c) c_int {
    if (m.__i[0] & 3 != PTHREAD_MUTEX_RECURSIVE) { // _m_type
        if (m.__i[5] != 0) return EDEADLK; // _m_count
        m.__i[5] = 1;
    } else {
        if (@as(c_uint, @bitCast(m.__i[5])) >= INT_MAX) return EAGAIN;
        m.__i[5] += 1;
    }
    return 0;
}

fn pthread_mutex_timedlock(m: *PthreadMutex, at: ?*const anyopaque) callconv(.c) c_int {
    _ = at;
    return pthread_mutex_lock(m);
}

fn pthread_mutex_trylock(m: *PthreadMutex) callconv(.c) c_int {
    if (m.__i[0] & 3 != PTHREAD_MUTEX_RECURSIVE) { // _m_type
        if (m.__i[5] != 0) return EBUSY; // _m_count
        m.__i[5] = 1;
    } else {
        if (@as(c_uint, @bitCast(m.__i[5])) >= INT_MAX) return EAGAIN;
        m.__i[5] += 1;
    }
    return 0;
}

fn pthread_mutex_unlock(m: *PthreadMutex) callconv(.c) c_int {
    if (m.__i[5] == 0) return EPERM; // _m_count
    m.__i[5] -= 1;
    return 0;
}

// --- Once ---

fn pthread_once(control: *c_int, init: *const fn () callconv(.c) void) callconv(.c) c_int {
    if (control.* == 0) {
        init();
        control.* = 1;
    }
    return 0;
}

// --- Read-write lock ---

fn pthread_rwlock_rdlock(rw: *PthreadRwlock) callconv(.c) c_int {
    if (rw.__i[0] == 0x7fffffff) return EDEADLK; // _rw_lock
    if (rw.__i[0] == 0x7ffffffe) return EAGAIN;
    rw.__i[0] += 1;
    return 0;
}

fn pthread_rwlock_timedrdlock(rw: *PthreadRwlock, at: ?*const anyopaque) callconv(.c) c_int {
    _ = at;
    return pthread_rwlock_rdlock(rw);
}

fn pthread_rwlock_timedwrlock(rw: *PthreadRwlock, at: ?*const anyopaque) callconv(.c) c_int {
    _ = at;
    return pthread_rwlock_wrlock(rw);
}

fn pthread_rwlock_tryrdlock(rw: *PthreadRwlock) callconv(.c) c_int {
    if (rw.__i[0] == 0x7fffffff) return EBUSY; // _rw_lock
    if (rw.__i[0] == 0x7ffffffe) return EAGAIN;
    rw.__i[0] += 1;
    return 0;
}

fn pthread_rwlock_trywrlock(rw: *PthreadRwlock) callconv(.c) c_int {
    if (rw.__i[0] != 0) return EBUSY; // _rw_lock
    rw.__i[0] = 0x7fffffff;
    return 0;
}

fn pthread_rwlock_unlock(rw: *PthreadRwlock) callconv(.c) c_int {
    if (rw.__i[0] == 0x7fffffff) { // _rw_lock
        rw.__i[0] = 0;
    } else {
        rw.__i[0] -= 1;
    }
    return 0;
}

fn pthread_rwlock_wrlock(rw: *PthreadRwlock) callconv(.c) c_int {
    if (rw.__i[0] != 0) return EDEADLK; // _rw_lock
    rw.__i[0] = 0x7fffffff;
    return 0;
}

// --- Spinlock ---

fn pthread_spin_lock(s: *c_int) callconv(.c) c_int {
    if (s.* != 0) return EDEADLK;
    s.* = 1;
    return 0;
}

fn pthread_spin_trylock(s: *c_int) callconv(.c) c_int {
    if (s.* != 0) return EBUSY;
    s.* = 1;
    return 0;
}

fn pthread_spin_unlock(s: *c_int) callconv(.c) c_int {
    s.* = 0;
    return 0;
}

// --- Symbol exports ---

comptime {
    // Barrier
    symbol(&pthread_barrier_destroy, "pthread_barrier_destroy");
    symbol(&pthread_barrier_init, "pthread_barrier_init");
    symbol(&pthread_barrier_wait, "pthread_barrier_wait");

    // Condition variable
    symbol(&pthread_cond_broadcast, "pthread_cond_broadcast");
    symbol(&pthread_cond_destroy, "pthread_cond_destroy");
    symbol(&pthread_cond_init, "pthread_cond_init");
    symbol(&pthread_cond_signal, "pthread_cond_signal");
    symbol(&pthread_cond_timedwait, "__pthread_cond_timedwait");
    symbol(&pthread_cond_wait, "pthread_cond_wait");

    // Thread lifecycle
    symbol(&dummy, "__acquire_ptc");
    symbol(&pthread_create, "__pthread_create");
    symbol(&pthread_detach, "__pthread_detach");
    symbol(&pthread_getattr_np, "pthread_getattr_np");
    symbol(&pthread_tryjoin_np, "__pthread_tryjoin_np");
    symbol(&pthread_timedjoin_np, "__pthread_timedjoin_np");
    symbol(&pthread_join, "__pthread_join");

    // Mutex
    symbol(&pthread_mutex_consistent, "pthread_mutex_consistent");
    symbol(&pthread_mutex_getprioceiling, "pthread_mutex_getprioceiling");
    symbol(&pthread_mutex_lock, "__pthread_mutex_lock");
    symbol(&pthread_mutex_timedlock, "__pthread_mutex_timedlock");
    symbol(&pthread_mutex_trylock, "__pthread_mutex_trylock");
    symbol(&pthread_mutex_unlock, "__pthread_mutex_unlock");

    // Once
    symbol(&pthread_once, "__pthread_once");

    // Read-write lock
    symbol(&pthread_rwlock_rdlock, "__pthread_rwlock_rdlock");
    symbol(&pthread_rwlock_timedrdlock, "__pthread_rwlock_timedrdlock");
    symbol(&pthread_rwlock_timedwrlock, "__pthread_rwlock_timedwrlock");
    symbol(&pthread_rwlock_tryrdlock, "__pthread_rwlock_tryrdlock");
    symbol(&pthread_rwlock_trywrlock, "__pthread_rwlock_trywrlock");
    symbol(&pthread_rwlock_unlock, "__pthread_rwlock_unlock");
    symbol(&pthread_rwlock_wrlock, "__pthread_rwlock_wrlock");

    // Spinlock
    symbol(&pthread_spin_lock, "pthread_spin_lock");
    symbol(&pthread_spin_trylock, "pthread_spin_trylock");
    symbol(&pthread_spin_unlock, "pthread_spin_unlock");
}
