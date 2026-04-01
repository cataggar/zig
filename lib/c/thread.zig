const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;

const linux = std.os.linux;
const E = linux.E;
const arch = builtin.target.cpu.arch;

comptime {
    if (builtin.target.isMuslLibC()) {
        // Generic clone stub (returns ENOSYS; arch-specific .s files override this)
        symbol(&__clone_fn, "__clone");

        // Default thread stack/guard size attributes
        symbol(&__default_stacksize, "__default_stacksize");
        symbol(&__default_guardsize, "__default_guardsize");

        if (builtin.link_libc) {
            // Futex-based internal lock (__lock.c)
            symbol(&__lock_fn, "__lock");
            symbol(&__unlock_fn, "__unlock");

            // PTC (pthread_create) rwlock wrappers (lock_ptc.c)
            symbol(&__inhibit_ptc_fn, "__inhibit_ptc");
            symbol(&__acquire_ptc_fn, "__acquire_ptc");
            symbol(&__release_ptc_fn, "__release_ptc");

            // RWLock operations
            symbol(&rwlock_init_fn, "pthread_rwlock_init");
            symbol(&rwlock_destroy_fn, "pthread_rwlock_destroy");
            symbol(&rwlock_tryrdlock_fn, "__pthread_rwlock_tryrdlock");
            symbol(&rwlock_tryrdlock_fn, "pthread_rwlock_tryrdlock");
            symbol(&rwlock_trywrlock_fn, "__pthread_rwlock_trywrlock");
            symbol(&rwlock_trywrlock_fn, "pthread_rwlock_trywrlock");
            symbol(&rwlock_unlock_fn, "__pthread_rwlock_unlock");
            symbol(&rwlock_unlock_fn, "pthread_rwlock_unlock");
            symbol(&rwlock_timedrdlock_fn, "__pthread_rwlock_timedrdlock");
            symbol(&rwlock_timedrdlock_fn, "pthread_rwlock_timedrdlock");
            symbol(&rwlock_timedwrlock_fn, "__pthread_rwlock_timedwrlock");
            symbol(&rwlock_timedwrlock_fn, "pthread_rwlock_timedwrlock");
            symbol(&rwlock_rdlock_fn, "__pthread_rwlock_rdlock");
            symbol(&rwlock_rdlock_fn, "pthread_rwlock_rdlock");
            symbol(&rwlock_wrlock_fn, "__pthread_rwlock_wrlock");
            symbol(&rwlock_wrlock_fn, "pthread_rwlock_wrlock");

            // Barrier operations
            symbol(&barrier_init_fn, "pthread_barrier_init");
            symbol(&barrier_destroy_fn, "pthread_barrier_destroy");
            symbol(&barrier_wait_fn, "pthread_barrier_wait");

            // Condvar operations
            symbol(&cond_init_fn, "pthread_cond_init");
            symbol(&cond_destroy_fn, "pthread_cond_destroy");
            symbol(&cond_signal_fn, "pthread_cond_signal");
            symbol(&cond_broadcast_fn, "pthread_cond_broadcast");
            symbol(&cond_wait_fn, "pthread_cond_wait");

            // Mutex operations
            symbol(&mutex_lock_fn, "__pthread_mutex_lock");
            symbol(&mutex_lock_fn, "pthread_mutex_lock");
            symbol(&mutex_consistent_fn, "pthread_mutex_consistent");

            // Spinlock operations
            symbol(&spin_init_fn, "pthread_spin_init");
            symbol(&spin_destroy_fn, "pthread_spin_destroy");
            symbol(&spin_lock_fn, "pthread_spin_lock");
            symbol(&spin_trylock_fn, "pthread_spin_trylock");
            symbol(&spin_unlock_fn, "pthread_spin_unlock");

            // Mutex trylock/timedlock/unlock
            symbol(&mutex_trylock_owner_fn, "__pthread_mutex_trylock_owner");
            symbol(&mutex_trylock_fn, "__pthread_mutex_trylock");
            symbol(&mutex_trylock_fn, "pthread_mutex_trylock");
            symbol(&mutex_timedlock_fn, "__pthread_mutex_timedlock");
            symbol(&mutex_timedlock_fn, "pthread_mutex_timedlock");
            symbol(&mutex_unlock_fn, "__pthread_mutex_unlock");
            symbol(&mutex_unlock_fn, "pthread_mutex_unlock");

            // Simple pthread stubs
            symbol(&pthread_getconcurrency_fn, "pthread_getconcurrency");
            symbol(&pthread_setconcurrency_fn, "pthread_setconcurrency");
            symbol(&pthread_equal_fn, "pthread_equal");
            symbol(&pthread_equal_fn, "thrd_equal");

            // C11 thread helpers
            symbol(&thrd_yield_fn, "thrd_yield");

            // Attribute operations (pthread_attr_*)
            symbol(&attr_destroy_fn, "pthread_attr_destroy");
            symbol(&attr_init_fn, "pthread_attr_init");
            symbol(&attr_setdetachstate_fn, "pthread_attr_setdetachstate");
            symbol(&attr_setguardsize_fn, "pthread_attr_setguardsize");
            symbol(&attr_setinheritsched_fn, "pthread_attr_setinheritsched");
            symbol(&attr_setschedparam_fn, "pthread_attr_setschedparam");
            symbol(&attr_setschedpolicy_fn, "pthread_attr_setschedpolicy");
            symbol(&attr_setscope_fn, "pthread_attr_setscope");
            symbol(&attr_setstack_fn, "pthread_attr_setstack");
            symbol(&attr_setstacksize_fn, "pthread_attr_setstacksize");

            // Attribute getters (pthread_attr_get.c)
            symbol(&attr_getdetachstate_fn, "pthread_attr_getdetachstate");
            symbol(&attr_getguardsize_fn, "pthread_attr_getguardsize");
            symbol(&attr_getinheritsched_fn, "pthread_attr_getinheritsched");
            symbol(&attr_getschedparam_fn, "pthread_attr_getschedparam");
            symbol(&attr_getschedpolicy_fn, "pthread_attr_getschedpolicy");
            symbol(&attr_getscope_fn, "pthread_attr_getscope");
            symbol(&attr_getstack_fn, "pthread_attr_getstack");
            symbol(&attr_getstacksize_fn, "pthread_attr_getstacksize");

            // Barrier attr operations
            symbol(&barrierattr_destroy_fn, "pthread_barrierattr_destroy");
            symbol(&barrierattr_init_fn, "pthread_barrierattr_init");
            symbol(&barrierattr_setpshared_fn, "pthread_barrierattr_setpshared");
            symbol(&barrierattr_getpshared_fn, "pthread_barrierattr_getpshared");

            // Condvar attr operations
            symbol(&condattr_destroy_fn, "pthread_condattr_destroy");
            symbol(&condattr_init_fn, "pthread_condattr_init");
            symbol(&condattr_setclock_fn, "pthread_condattr_setclock");
            symbol(&condattr_setpshared_fn, "pthread_condattr_setpshared");
            symbol(&condattr_getclock_fn, "pthread_condattr_getclock");
            symbol(&condattr_getpshared_fn, "pthread_condattr_getpshared");

            // Mutex attr operations
            symbol(&mutexattr_destroy_fn, "pthread_mutexattr_destroy");
            symbol(&mutexattr_init_fn, "pthread_mutexattr_init");
            symbol(&mutexattr_setprotocol_fn, "pthread_mutexattr_setprotocol");
            symbol(&mutexattr_setpshared_fn, "pthread_mutexattr_setpshared");
            symbol(&mutexattr_setrobust_fn, "pthread_mutexattr_setrobust");
            symbol(&mutexattr_settype_fn, "pthread_mutexattr_settype");
            symbol(&mutexattr_getprotocol_fn, "pthread_mutexattr_getprotocol");
            symbol(&mutexattr_getpshared_fn, "pthread_mutexattr_getpshared");
            symbol(&mutexattr_getrobust_fn, "pthread_mutexattr_getrobust");
            symbol(&mutexattr_gettype_fn, "pthread_mutexattr_gettype");

            // RWLock attr operations
            symbol(&rwlockattr_destroy_fn, "pthread_rwlockattr_destroy");
            symbol(&rwlockattr_init_fn, "pthread_rwlockattr_init");
            symbol(&rwlockattr_setpshared_fn, "pthread_rwlockattr_setpshared");
            symbol(&rwlockattr_getpshared_fn, "pthread_rwlockattr_getpshared");

            // Mutex init/destroy/prioceiling
            symbol(&mutex_destroy_fn, "pthread_mutex_destroy");
            symbol(&mutex_init_fn, "pthread_mutex_init");
            symbol(&mutex_getprioceiling_fn, "pthread_mutex_getprioceiling");
            symbol(&mutex_setprioceiling_fn, "pthread_mutex_setprioceiling");

            // Semaphore simple operations
            symbol(&sem_destroy_fn, "sem_destroy");
            symbol(&sem_getvalue_fn, "sem_getvalue");
            symbol(&sem_init_fn, "sem_init");
            symbol(&sem_unlink_fn, "sem_unlink");
            symbol(&sem_wait_fn, "sem_wait");

            // C11 cnd_* wrappers
            symbol(&call_once_fn, "call_once");
            symbol(&cnd_broadcast_fn2, "cnd_broadcast");
            symbol(&cnd_destroy_fn2, "cnd_destroy");
            symbol(&cnd_init_fn2, "cnd_init");
            symbol(&cnd_signal_fn2, "cnd_signal");
            symbol(&cnd_timedwait_fn, "cnd_timedwait");
            symbol(&cnd_wait_fn2, "cnd_wait");

            // C11 mtx_* wrappers
            symbol(&mtx_destroy_fn, "mtx_destroy");
            symbol(&mtx_init_fn, "mtx_init");
            symbol(&mtx_lock_fn, "mtx_lock");
            symbol(&mtx_timedlock_fn, "mtx_timedlock");
            symbol(&mtx_trylock_fn, "mtx_trylock");
            symbol(&mtx_unlock_fn, "mtx_unlock");

            // C11 thrd_* wrappers
            symbol(&thrd_create_fn, "thrd_create");
            symbol(&thrd_exit_fn, "thrd_exit");
            symbol(&thrd_join_fn, "thrd_join");
            symbol(&thrd_sleep_fn, "thrd_sleep");

            // C11 tss_* wrappers
            symbol(&tss_create_fn, "tss_create");
            symbol(&tss_delete_fn, "tss_delete");
            symbol(&tss_set_fn, "tss_set");

            // pthread_setattr_default_np / pthread_getattr_default_np
            symbol(&setattr_default_np_fn, "pthread_setattr_default_np");
            symbol(&getattr_default_np_fn, "pthread_getattr_default_np");
        }
    }
}

// --- clone.c ---
// Generic fallback: real implementations are arch-specific .s files.

fn __clone_fn(_: ?*const fn (?*anyopaque) callconv(.c) c_int, _: ?*anyopaque, _: c_int, _: ?*anyopaque) callconv(.c) c_int {
    return -@as(c_int, @intCast(@intFromEnum(E.NOSYS)));
}

// --- default_attr.c ---

var __default_stacksize: c_uint = 131072; // DEFAULT_STACK_SIZE
var __default_guardsize: c_uint = 8192; // DEFAULT_GUARD_SIZE

// --- __lock.c ---
// Futex-based lock combining a flag (sign bit) and congestion count.
// States: 0 = unlocked/empty, < 0 = locked, > 0 = unlocked with waiters.

const INT_MIN = std.math.minInt(c_int);

/// Partial layout of musl's internal `struct __libc` (from libc.h).
/// Only the initial fields needed to access `need_locks` are declared.
const MuslLibc = extern struct {
    can_do_threads: i8,
    threaded: i8,
    secure: i8,
    need_locks: i8, // volatile signed char
};

extern var __libc: MuslLibc;

fn futexWait(addr: *volatile c_int, val: c_int, priv_flag: bool) void {
    const priv: usize = if (priv_flag) FUTEX_PRIVATE else 0;
    const val_u: usize = @bitCast(@as(isize, val));
    const rc: isize = @bitCast(linux.syscall4(.futex, @intFromPtr(addr), FUTEX_WAIT | priv, val_u, 0));
    if (rc == -@as(isize, @intCast(@intFromEnum(E.NOSYS)))) {
        _ = linux.syscall4(.futex, @intFromPtr(addr), FUTEX_WAIT, val_u, 0);
    }
}

fn futexWake(addr: *volatile c_int, cnt: c_int, priv_flag: bool) void {
    const priv: usize = if (priv_flag) FUTEX_PRIVATE else 0;
    const n: usize = if (cnt < 0) @intCast(std.math.maxInt(c_int)) else @intCast(cnt);
    const rc: isize = @bitCast(linux.syscall3(.futex, @intFromPtr(addr), FUTEX_WAKE | priv, n));
    if (rc == -@as(isize, @intCast(@intFromEnum(E.NOSYS)))) {
        _ = linux.syscall3(.futex, @intFromPtr(addr), FUTEX_WAKE, n);
    }
}

const FUTEX_WAIT: usize = 0;
const FUTEX_WAKE: usize = 1;
const FUTEX_PRIVATE: usize = 128;

fn cas(ptr: *volatile c_int, expected: c_int, desired: c_int) c_int {
    // a_cas: returns old value. On success old==expected, on failure old!=expected.
    const p: *c_int = @constCast(@volatileCast(ptr));
    return @cmpxchgStrong(c_int, p, expected, desired, .seq_cst, .seq_cst) orelse expected;
}

fn fetchAdd(ptr: *volatile c_int, val: c_int) c_int {
    const p: *c_int = @constCast(@volatileCast(ptr));
    return @atomicRmw(c_int, p, .Add, val, .seq_cst);
}

fn __lock_fn(l: *volatile c_int) callconv(.c) void {
    const nl: *volatile i8 = @ptrCast(&__libc.need_locks);
    const need_locks: i8 = nl.*;
    if (need_locks == 0) return;

    // Fast path: INT_MIN for the lock, +1 for the congestion
    var current = cas(l, 0, INT_MIN + 1);
    if (need_locks < 0) nl.* = 0;
    if (current == 0) return;

    // First spin loop for medium congestion
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        if (current < 0) current -%= INT_MIN + 1;
        const val = cas(l, current, INT_MIN +% (current +% 1));
        if (val == current) return;
        current = val;
    }

    // Mark ourselves as being inside the critical section
    current = fetchAdd(l, 1) +% 1;

    // Main lock acquisition loop for heavy congestion
    while (true) {
        if (current < 0) {
            futexWait(l, current, true);
            current -%= INT_MIN + 1;
        }
        const val = cas(l, current, INT_MIN +% current);
        if (val == current) return;
        current = val;
    }
}

fn __unlock_fn(l: *volatile c_int) callconv(.c) void {
    if (l.* < 0) {
        if (fetchAdd(l, -(INT_MIN + 1)) != (INT_MIN + 1)) {
            futexWake(l, 1, true);
        }
    }
}

// --- lock_ptc.c ---
// PTC (pthread_create/TLS-change) rwlock wrappers.
// Uses a pthread_rwlock_t initialized to all zeros (PTHREAD_RWLOCK_INITIALIZER).

const rwlock_ints = if (@sizeOf(c_long) == 8) 14 else 8;
var ptc_rwlock: [rwlock_ints]c_int = .{0} ** rwlock_ints;

fn __inhibit_ptc_fn() callconv(.c) void {
    _ = rwlock_wrlock_fn(@ptrCast(&ptc_rwlock));
}

fn __acquire_ptc_fn() callconv(.c) void {
    _ = rwlock_rdlock_fn(@ptrCast(&ptc_rwlock));
}

fn __release_ptc_fn() callconv(.c) void {
    _ = rwlock_unlock_fn(@ptrCast(&ptc_rwlock));
}

// --- Helpers ---

fn eint(e: E) c_int {
    return @intCast(@intFromEnum(e));
}

/// musl's static inline __wake (pthread_impl.h)
fn wake(addr: *anyopaque, cnt: c_int, priv_val: c_int) void {
    const p: usize = if (priv_val != 0) FUTEX_PRIVATE else 0;
    const n: usize = if (cnt < 0) @intCast(std.math.maxInt(c_int)) else @intCast(cnt);
    _ = linux.syscall3(.futex, @intFromPtr(addr), FUTEX_WAKE | p, n);
}

// musl struct field offsets (from pthread_impl.h macros over the __u union)
//
// pthread_rwlock_t: _rw_lock=vi[0], _rw_waiters=vi[1], _rw_shared=i[2]
// pthread_barrier_t: _b_lock=vi[0], _b_waiters=vi[1], _b_limit=i[2],
//                    _b_count=vi[3], _b_waiters2=vi[4], _b_inst=p[3]
// pthread_cond_t: _c_shared=p[0], _c_seq=vi[2], _c_waiters=vi[3],
//                 _c_clock=i[4]
// pthread_mutex_t: _m_type=i[0], _m_lock=vi[1]

// Thread descriptor tid offset (musl struct __pthread layout)
const tls_above_tp = switch (arch) {
    .aarch64, .aarch64_be, .arm, .armeb, .thumb, .thumbeb,
    .riscv64, .riscv32, .mips, .mipsel, .mips64, .mips64el,
    .powerpc, .powerpcle, .powerpc64, .powerpc64le,
    .loongarch64, .m68k => true,
    else => false,
};
const ptr_size = @sizeOf(usize);
const off_tid: usize = if (tls_above_tp) 4 * ptr_size else 6 * ptr_size;

const PTHREAD_BARRIER_SERIAL_THREAD: c_int = -1;

// ============================================================
// RWLock operations
// ============================================================

// --- pthread_rwlock_init.c ---
fn rwlock_init_fn(rw: *anyopaque, a: ?*const anyopaque) callconv(.c) c_int {
    const bytes: [*]u8 = @ptrCast(rw);
    @memset(bytes[0 .. rwlock_ints * @sizeOf(c_int)], 0);
    if (a) |attr| {
        const rw_i: [*]c_int = @ptrCast(@alignCast(rw));
        const attr_i: *const c_int = @ptrCast(@alignCast(attr));
        rw_i[2] = attr_i.* * 128; // _rw_shared = a->__attr[0]*128
    }
    return 0;
}

// --- pthread_rwlock_destroy.c ---
fn rwlock_destroy_fn(_: *anyopaque) callconv(.c) c_int {
    return 0;
}

// --- pthread_rwlock_tryrdlock.c ---
fn rwlock_tryrdlock_fn(rw: *anyopaque) callconv(.c) c_int {
    const rw_i: [*]c_int = @ptrCast(@alignCast(rw));
    while (true) {
        const val = @atomicLoad(c_int, &rw_i[0], .seq_cst);
        const cnt = val & 0x7fffffff;
        if (cnt == 0x7fffffff) return eint(.BUSY);
        if (cnt == 0x7ffffffe) return eint(.AGAIN);
        if (@cmpxchgStrong(c_int, &rw_i[0], val, val +% 1, .seq_cst, .seq_cst) == null)
            return 0;
    }
}

// --- pthread_rwlock_trywrlock.c ---
fn rwlock_trywrlock_fn(rw: *anyopaque) callconv(.c) c_int {
    const rw_i: [*]c_int = @ptrCast(@alignCast(rw));
    if (@cmpxchgStrong(c_int, &rw_i[0], 0, 0x7fffffff, .seq_cst, .seq_cst) != null)
        return eint(.BUSY);
    return 0;
}

// --- pthread_rwlock_unlock.c ---
fn rwlock_unlock_fn(rw: *anyopaque) callconv(.c) c_int {
    const rw_i: [*]c_int = @ptrCast(@alignCast(rw));
    const priv = rw_i[2] ^ 128; // _rw_shared^128

    while (true) {
        const val = @atomicLoad(c_int, &rw_i[0], .seq_cst);
        const cnt = val & 0x7fffffff;
        const waiters = @atomicLoad(c_int, &rw_i[1], .seq_cst);
        const new: c_int = if (cnt == 0x7fffffff or cnt == 1) 0 else val -% 1;
        if (@cmpxchgStrong(c_int, &rw_i[0], val, new, .seq_cst, .seq_cst) == null) {
            if (new == 0 and (waiters != 0 or val < 0))
                wake(@ptrCast(&rw_i[0]), @intCast(cnt), priv);
            return 0;
        }
    }
}

// --- pthread_rwlock_timedrdlock.c ---
fn rwlock_timedrdlock_fn(rw: *anyopaque, at: ?*const anyopaque) callconv(.c) c_int {
    const rw_i: [*]c_int = @ptrCast(@alignCast(rw));
    const __timedwait = @extern(*const fn (*anyopaque, c_int, c_int, ?*const anyopaque, c_int) callconv(.c) c_int, .{ .name = "__timedwait" });

    var r = rwlock_tryrdlock_fn(rw);
    if (r != eint(.BUSY)) return r;

    // Spin phase
    var spins: c_int = 100;
    while (spins > 0) : (spins -= 1) {
        if (@atomicLoad(c_int, &rw_i[0], .monotonic) == 0) break;
        if (@atomicLoad(c_int, &rw_i[1], .monotonic) != 0) break;
        std.atomic.spinLoopHint();
    }

    while (true) {
        r = rwlock_tryrdlock_fn(rw);
        if (r != eint(.BUSY)) return r;

        const lock_val = @atomicLoad(c_int, &rw_i[0], .monotonic);
        // Only wait if write-locked (lower 31 bits == 0x7fffffff)
        if (lock_val == 0 or (lock_val & 0x7fffffff) != 0x7fffffff) continue;

        const t = lock_val | @as(c_int, @bitCast(@as(c_uint, 0x80000000)));
        _ = @atomicRmw(c_int, &rw_i[1], .Add, 1, .seq_cst);
        _ = @cmpxchgStrong(c_int, &rw_i[0], lock_val, t, .seq_cst, .seq_cst);
        r = __timedwait(@ptrCast(&rw_i[0]), t, 0, at, rw_i[2] ^ 128);
        _ = @atomicRmw(c_int, &rw_i[1], .Add, -1, .seq_cst);
        if (r != 0 and r != eint(.INTR)) return r;
    }
}

// --- pthread_rwlock_timedwrlock.c ---
fn rwlock_timedwrlock_fn(rw: *anyopaque, at: ?*const anyopaque) callconv(.c) c_int {
    const rw_i: [*]c_int = @ptrCast(@alignCast(rw));
    const __timedwait = @extern(*const fn (*anyopaque, c_int, c_int, ?*const anyopaque, c_int) callconv(.c) c_int, .{ .name = "__timedwait" });

    var r = rwlock_trywrlock_fn(rw);
    if (r != eint(.BUSY)) return r;

    var spins: c_int = 100;
    while (spins > 0) : (spins -= 1) {
        if (@atomicLoad(c_int, &rw_i[0], .monotonic) == 0) break;
        if (@atomicLoad(c_int, &rw_i[1], .monotonic) != 0) break;
        std.atomic.spinLoopHint();
    }

    while (true) {
        r = rwlock_trywrlock_fn(rw);
        if (r != eint(.BUSY)) return r;

        const lock_val = @atomicLoad(c_int, &rw_i[0], .monotonic);
        if (lock_val == 0) continue;

        const t = lock_val | @as(c_int, @bitCast(@as(c_uint, 0x80000000)));
        _ = @atomicRmw(c_int, &rw_i[1], .Add, 1, .seq_cst);
        _ = @cmpxchgStrong(c_int, &rw_i[0], lock_val, t, .seq_cst, .seq_cst);
        r = __timedwait(@ptrCast(&rw_i[0]), t, 0, at, rw_i[2] ^ 128);
        _ = @atomicRmw(c_int, &rw_i[1], .Add, -1, .seq_cst);
        if (r != 0 and r != eint(.INTR)) return r;
    }
}

// --- pthread_rwlock_rdlock.c ---
fn rwlock_rdlock_fn(rw: *anyopaque) callconv(.c) c_int {
    return rwlock_timedrdlock_fn(rw, null);
}

// --- pthread_rwlock_wrlock.c ---
fn rwlock_wrlock_fn(rw: *anyopaque) callconv(.c) c_int {
    return rwlock_timedwrlock_fn(rw, null);
}

// ============================================================
// Barrier operations
// ============================================================

const barrier_int_count: usize = if (@sizeOf(usize) == 8) 8 else 5;

const BarrierInstance = extern struct {
    count: c_int = 0,
    last: c_int = 0,
    waiters: c_int = 0,
    finished: c_int = 0,
};

// --- pthread_barrier_init.c ---
fn barrier_init_fn(b: *anyopaque, a: ?*const anyopaque, count: c_uint) callconv(.c) c_int {
    if (count -% 1 > @as(c_uint, 0x7ffffffe)) return eint(.INVAL);

    const bytes: [*]u8 = @ptrCast(b);
    @memset(bytes[0 .. barrier_int_count * @sizeOf(c_int)], 0);

    const b_i: [*]c_int = @ptrCast(@alignCast(b));
    const attr_val: c_uint = if (a) |attr_ptr|
        (@as(*const c_uint, @ptrCast(@alignCast(attr_ptr))).*)
    else
        0;
    b_i[2] = @bitCast((count -% 1) | attr_val); // _b_limit
    return 0;
}

// --- pthread_barrier_destroy.c ---
fn barrier_destroy_fn(b: *anyopaque) callconv(.c) c_int {
    const b_i: [*]c_int = @ptrCast(@alignCast(b));
    if (b_i[2] < 0) { // _b_limit < 0 → process-shared
        if (@atomicLoad(c_int, &b_i[0], .monotonic) != 0) {
            _ = @atomicRmw(c_int, &b_i[0], .Or, INT_MIN, .seq_cst);
            while (true) {
                const v = @atomicLoad(c_int, &b_i[0], .monotonic);
                if ((v & std.math.maxInt(c_int)) == 0) break;
                const __wait_ext = @extern(*const fn (*anyopaque, ?*anyopaque, c_int, c_int) callconv(.c) void, .{ .name = "__wait" });
                __wait_ext(@ptrCast(&b_i[0]), null, v, 0);
            }
        }
        const __vm_wait = @extern(*const fn () callconv(.c) void, .{ .name = "__vm_wait" });
        __vm_wait();
    }
    return 0;
}

// --- pthread_barrier_wait.c (process-shared path) ---
fn pshared_barrier_wait(b: *anyopaque) c_int {
    const b_i: [*]c_int = @ptrCast(@alignCast(b));
    const __wait_ext = @extern(*const fn (*anyopaque, ?*anyopaque, c_int, c_int) callconv(.c) void, .{ .name = "__wait" });
    const __vm_lock = @extern(*const fn () callconv(.c) void, .{ .name = "__vm_lock" });
    const __vm_unlock = @extern(*const fn () callconv(.c) void, .{ .name = "__vm_unlock" });

    const limit: c_int = (b_i[2] & std.math.maxInt(c_int)) +% 1;
    var ret: c_int = 0;

    if (limit == 1) return PTHREAD_BARRIER_SERIAL_THREAD;

    // Acquire lock: CAS _b_lock from 0 to limit
    while (true) {
        if (@cmpxchgStrong(c_int, &b_i[0], 0, limit, .seq_cst, .seq_cst)) |v| {
            __wait_ext(@ptrCast(&b_i[0]), @ptrCast(&b_i[1]), v, 0);
        } else break;
    }

    // Wait for <limit> threads to reach the barrier
    b_i[3] +%= 1; // ++_b_count
    if (b_i[3] == limit) {
        @atomicStore(c_int, &b_i[3], 0, .seq_cst);
        ret = PTHREAD_BARRIER_SERIAL_THREAD;
        if (@atomicLoad(c_int, &b_i[4], .monotonic) != 0)
            wake(@ptrCast(&b_i[3]), -1, 0);
    } else {
        @atomicStore(c_int, &b_i[0], 0, .seq_cst);
        if (@atomicLoad(c_int, &b_i[1], .monotonic) != 0)
            wake(@ptrCast(&b_i[0]), 1, 0);
        while (true) {
            const v = @atomicLoad(c_int, &b_i[3], .monotonic);
            if (v <= 0) break;
            __wait_ext(@ptrCast(&b_i[3]), @ptrCast(&b_i[4]), v, 0);
        }
    }

    __vm_lock();

    // Ensure all threads have a vm lock before proceeding
    if (@atomicRmw(c_int, &b_i[3], .Add, -1, .seq_cst) == 1 -% limit) {
        @atomicStore(c_int, &b_i[3], 0, .seq_cst);
        if (@atomicLoad(c_int, &b_i[4], .monotonic) != 0)
            wake(@ptrCast(&b_i[3]), -1, 0);
    } else {
        while (true) {
            const v = @atomicLoad(c_int, &b_i[3], .monotonic);
            if (v == 0) break;
            __wait_ext(@ptrCast(&b_i[3]), @ptrCast(&b_i[4]), v, 0);
        }
    }

    // Recursive unlock suitable for self-sync'd destruction
    var v: c_int = undefined;
    var w: c_int = undefined;
    while (true) {
        v = @atomicLoad(c_int, &b_i[0], .monotonic);
        w = @atomicLoad(c_int, &b_i[1], .monotonic);
        const new_val: c_int = if (v == INT_MIN +% 1) 0 else v -% 1;
        if (@cmpxchgStrong(c_int, &b_i[0], v, new_val, .seq_cst, .seq_cst) == null)
            break;
    }

    if (v == INT_MIN +% 1 or (v == 1 and w != 0))
        wake(@ptrCast(&b_i[0]), 1, 0);

    __vm_unlock();

    return ret;
}

// --- pthread_barrier_wait.c (main, non-shared path) ---
fn barrier_wait_fn(b: *anyopaque) callconv(.c) c_int {
    const b_i: [*]c_int = @ptrCast(@alignCast(b));
    const __wait_ext = @extern(*const fn (*anyopaque, ?*anyopaque, c_int, c_int) callconv(.c) void, .{ .name = "__wait" });

    const limit = b_i[2]; // _b_limit

    // Trivial case: count was set at 1
    if (limit == 0) return PTHREAD_BARRIER_SERIAL_THREAD;

    // Process-shared barriers require a separate, inefficient wait
    if (limit < 0) return pshared_barrier_wait(b);

    // Acquire the barrier lock
    while (@atomicRmw(c_int, &b_i[0], .Xchg, 1, .seq_cst) != 0)
        __wait_ext(@ptrCast(&b_i[0]), @ptrCast(&b_i[1]), 1, 1);

    // Read _b_inst pointer
    const b_ptrs: [*]usize = @ptrCast(@alignCast(b));
    const inst_val = b_ptrs[3]; // __p[3]

    if (inst_val == 0) {
        // First thread to enter: become the instance owner
        var new_inst = BarrierInstance{};
        b_ptrs[3] = @intFromPtr(&new_inst);

        @atomicStore(c_int, &b_i[0], 0, .seq_cst);
        if (@atomicLoad(c_int, &b_i[1], .monotonic) != 0)
            wake(@ptrCast(&b_i[0]), 1, 1);

        // Spin waiting for other threads
        var spins: c_int = 200;
        while (spins > 0) : (spins -= 1) {
            if (@atomicLoad(c_int, &new_inst.finished, .monotonic) != 0) break;
            std.atomic.spinLoopHint();
        }

        // Signal that we're done spinning
        _ = @atomicRmw(c_int, &new_inst.finished, .Add, 1, .seq_cst);

        // Wait until woken by last exiting thread
        while (@atomicLoad(c_int, &new_inst.finished, .seq_cst) == 1) {
            const rc: isize = @bitCast(linux.syscall4(
                .futex,
                @intFromPtr(&new_inst.finished),
                FUTEX_WAIT | FUTEX_PRIVATE,
                1,
                0,
            ));
            if (rc == -@as(isize, @intCast(@intFromEnum(E.NOSYS)))) {
                _ = linux.syscall4(
                    .futex,
                    @intFromPtr(&new_inst.finished),
                    FUTEX_WAIT,
                    1,
                    0,
                );
            }
        }
        return PTHREAD_BARRIER_SERIAL_THREAD;
    }

    const inst: *BarrierInstance = @ptrFromInt(inst_val);

    // Last thread to enter wakes all non-instance-owners
    inst.count +%= 1;
    if (inst.count == limit) {
        b_ptrs[3] = 0; // b->_b_inst = 0
        @atomicStore(c_int, &b_i[0], 0, .seq_cst);
        if (@atomicLoad(c_int, &b_i[1], .monotonic) != 0)
            wake(@ptrCast(&b_i[0]), 1, 1);
        @atomicStore(c_int, &inst.last, 1, .seq_cst);
        if (@atomicLoad(c_int, &inst.waiters, .monotonic) != 0)
            wake(@ptrCast(&inst.last), -1, 1);
    } else {
        @atomicStore(c_int, &b_i[0], 0, .seq_cst);
        if (@atomicLoad(c_int, &b_i[1], .monotonic) != 0)
            wake(@ptrCast(&b_i[0]), 1, 1);
        __wait_ext(@ptrCast(&inst.last), @ptrCast(&inst.waiters), 0, 1);
    }

    // Last thread to exit wakes the instance owner
    if (@atomicRmw(c_int, &inst.count, .Add, -1, .seq_cst) == 1 and
        @atomicRmw(c_int, &inst.finished, .Add, 1, .seq_cst) != 0)
    {
        wake(@ptrCast(&inst.finished), 1, 1);
    }

    return 0;
}

// ============================================================
// Condvar operations
// ============================================================

const cond_int_count: usize = if (@sizeOf(usize) == 8) 12 else 8;

// --- pthread_cond_init.c ---
fn cond_init_fn(c: *anyopaque, a: ?*const anyopaque) callconv(.c) c_int {
    const bytes: [*]u8 = @ptrCast(c);
    @memset(bytes[0 .. cond_int_count * @sizeOf(c_int)], 0);
    if (a) |attr_ptr| {
        const attr: c_uint = @as(*const c_uint, @ptrCast(@alignCast(attr_ptr))).*;
        const c_i: [*]c_int = @ptrCast(@alignCast(c));
        c_i[4] = @intCast(attr & 0x7fffffff); // _c_clock
        if (attr >> 31 != 0) {
            // _c_shared = (void*)-1 → set p[0] to all-ones
            const c_ptrs: [*]usize = @ptrCast(@alignCast(c));
            c_ptrs[0] = @bitCast(@as(isize, -1));
        }
    }
    return 0;
}

// --- pthread_cond_destroy.c ---
fn cond_destroy_fn(c: *anyopaque) callconv(.c) c_int {
    const c_ptrs: [*]usize = @ptrCast(@alignCast(c));
    const c_i: [*]c_int = @ptrCast(@alignCast(c));
    if (c_ptrs[0] != 0 and @atomicLoad(c_int, &c_i[3], .monotonic) != 0) {
        _ = @atomicRmw(c_int, &c_i[3], .Or, INT_MIN, .seq_cst); // _c_waiters |= 0x80000000
        _ = @atomicRmw(c_int, &c_i[2], .Add, 1, .seq_cst); // a_inc(&_c_seq)
        wake(@ptrCast(&c_i[2]), -1, 0);
        const __wait_ext = @extern(*const fn (*anyopaque, ?*anyopaque, c_int, c_int) callconv(.c) void, .{ .name = "__wait" });
        while (true) {
            const cnt = @atomicLoad(c_int, &c_i[3], .monotonic);
            if ((cnt & 0x7fffffff) == 0) break;
            __wait_ext(@ptrCast(&c_i[3]), null, cnt, 0);
        }
    }
    return 0;
}

// --- pthread_cond_signal.c ---
fn cond_signal_fn(c: *anyopaque) callconv(.c) c_int {
    const c_ptrs: [*]usize = @ptrCast(@alignCast(c));
    const c_i: [*]c_int = @ptrCast(@alignCast(c));
    if (c_ptrs[0] == 0) { // !_c_shared → private
        const __priv_cond_sig = @extern(*const fn (*anyopaque, c_int) callconv(.c) c_int, .{ .name = "__private_cond_signal" });
        return __priv_cond_sig(c, 1);
    }
    if (@atomicLoad(c_int, &c_i[3], .monotonic) == 0) return 0;
    _ = @atomicRmw(c_int, &c_i[2], .Add, 1, .seq_cst);
    wake(@ptrCast(&c_i[2]), 1, 0);
    return 0;
}

// --- pthread_cond_broadcast.c ---
fn cond_broadcast_fn(c: *anyopaque) callconv(.c) c_int {
    const c_ptrs: [*]usize = @ptrCast(@alignCast(c));
    const c_i: [*]c_int = @ptrCast(@alignCast(c));
    if (c_ptrs[0] == 0) { // !_c_shared → private
        const __priv_cond_sig = @extern(*const fn (*anyopaque, c_int) callconv(.c) c_int, .{ .name = "__private_cond_signal" });
        return __priv_cond_sig(c, -1);
    }
    if (@atomicLoad(c_int, &c_i[3], .monotonic) == 0) return 0;
    _ = @atomicRmw(c_int, &c_i[2], .Add, 1, .seq_cst);
    wake(@ptrCast(&c_i[2]), -1, 0);
    return 0;
}

// --- pthread_cond_wait.c ---
fn cond_wait_fn(c: *anyopaque, m: *anyopaque) callconv(.c) c_int {
    const __pthread_cond_timedwait_ext = @extern(*const fn (*anyopaque, *anyopaque, ?*const anyopaque) callconv(.c) c_int, .{ .name = "pthread_cond_timedwait" });
    return __pthread_cond_timedwait_ext(c, m, null);
}

// ============================================================
// Mutex operations
// ============================================================

// --- pthread_mutex_lock.c ---
fn mutex_lock_fn(m: *anyopaque) callconv(.c) c_int {
    const m_i: [*]c_int = @ptrCast(@alignCast(m));
    // Fast path for PTHREAD_MUTEX_NORMAL (type == 0)
    if ((m_i[0] & 15) == 0) {
        if (@cmpxchgStrong(c_int, &m_i[1], 0, eint(.BUSY), .seq_cst, .seq_cst) == null)
            return 0;
    }
    const __pthread_mutex_timedlock_ext = @extern(*const fn (*anyopaque, ?*const anyopaque) callconv(.c) c_int, .{ .name = "__pthread_mutex_timedlock" });
    return __pthread_mutex_timedlock_ext(m, null);
}

// --- pthread_mutex_consistent.c ---
fn mutex_consistent_fn(m: *anyopaque) callconv(.c) c_int {
    const m_i: [*]c_int = @ptrCast(@alignCast(m));
    const old = @atomicLoad(c_int, &m_i[1], .monotonic); // _m_lock
    const own = old & 0x3fffffff;
    if ((m_i[0] & 4) == 0 or own == 0 or (old & 0x40000000) == 0)
        return eint(.INVAL);
    const pthread_self_ext = @extern(*const fn () callconv(.c) usize, .{ .name = "pthread_self" });
    const self_addr = pthread_self_ext();
    const tid: c_int = @as(*const c_int, @ptrFromInt(self_addr + off_tid)).*;
    if (own != tid)
        return eint(.PERM);
    _ = @atomicRmw(c_int, &m_i[1], .And, ~@as(c_int, 0x40000000), .seq_cst);
    return 0;
}

// ============================================================
// Spinlock operations
// ============================================================

// --- pthread_spin_init.c ---
fn spin_init_fn(s: *c_int, _: c_int) callconv(.c) c_int {
    s.* = 0;
    return 0;
}

// --- pthread_spin_destroy.c ---
fn spin_destroy_fn(_: *c_int) callconv(.c) c_int {
    return 0;
}

// --- pthread_spin_lock.c ---
fn spin_lock_fn(s: *c_int) callconv(.c) c_int {
    while (@as(*volatile c_int, s).* != 0 or
        (@cmpxchgStrong(c_int, s, 0, eint(.BUSY), .seq_cst, .seq_cst) != null))
    {
        std.atomic.spinLoopHint();
    }
    return 0;
}

// --- pthread_spin_trylock.c ---
fn spin_trylock_fn(s: *c_int) callconv(.c) c_int {
    return @cmpxchgStrong(c_int, s, 0, eint(.BUSY), .seq_cst, .seq_cst) orelse 0;
}

// --- pthread_spin_unlock.c ---
fn spin_unlock_fn(s: *c_int) callconv(.c) c_int {
    @atomicStore(c_int, s, 0, .seq_cst);
    return 0;
}

// ============================================================
// Mutex trylock / timedlock / unlock
// ============================================================

const FUTEX_LOCK_PI: usize = 6;
const FUTEX_UNLOCK_PI: usize = 7;

// Mutex field indices (matching musl's __u union layout in pthread_impl.h)
// _m_type = __i[0], _m_lock = __vi[1], _m_waiters = __vi[2]
// _m_prev = __p[3], _m_next = __p[4], _m_count = __i[5]

fn mutexPtrs(m: *anyopaque) [*]usize {
    return @ptrCast(@alignCast(m));
}

// Pthread struct offsets for robust_list (relative to self pointer)
const off_after_bitfields: usize = off_tid + 19; // tid(4)+errno_val(4)+detach_state(4)+cancel(4)+canceldisable(1)+cancelasync(1)+bitfield_byte(1)
const off_map_base: usize = std.mem.alignForward(usize, off_after_bitfields, ptr_size);
const off_robust_head: usize = off_map_base + 8 * ptr_size; // skip: map_base, map_size, stack, stack_size, guard_size, result, cancelbuf, tsd
const off_robust_off: usize = off_robust_head + ptr_size;
const off_robust_pending: usize = off_robust_head + 2 * ptr_size;

fn selfTid() c_int {
    const pthread_self_ext = @extern(*const fn () callconv(.c) usize, .{ .name = "pthread_self" });
    const self_addr = pthread_self_ext();
    return @as(*const c_int, @ptrFromInt(self_addr + off_tid)).*;
}

fn selfAddr() usize {
    const pthread_self_ext = @extern(*const fn () callconv(.c) usize, .{ .name = "pthread_self" });
    return pthread_self_ext();
}

fn robustHead(self_addr: usize) *volatile usize {
    return @ptrFromInt(self_addr + off_robust_head);
}

fn robustOff(self_addr: usize) *isize {
    return @ptrFromInt(self_addr + off_robust_off);
}

fn robustPending(self_addr: usize) *volatile usize {
    return @ptrFromInt(self_addr + off_robust_pending);
}

// --- pthread_mutex_trylock.c ---
fn mutex_trylock_owner_fn(m: *anyopaque) callconv(.c) c_int {
    const m_i: [*]c_int = @ptrCast(@alignCast(m));
    const m_p = mutexPtrs(m);

    const @"type" = m_i[0]; // _m_type
    const self_a = selfAddr();
    const tid = @as(*const c_int, @ptrFromInt(self_a + off_tid)).*;

    var old = @atomicLoad(c_int, &m_i[1], .monotonic); // _m_lock
    const own = old & 0x3fffffff;
    if (own == tid) {
        if ((@"type" & 8) != 0 and m_i[5] < 0) { // PI + _m_count < 0
            old &= 0x40000000;
            m_i[5] = 0; // _m_count = 0
            // fall through to success
        } else if ((@"type" & 3) == 1) { // PTHREAD_MUTEX_RECURSIVE
            if (@as(c_uint, @bitCast(m_i[5])) >= @as(c_uint, @bitCast(@as(c_int, std.math.maxInt(c_int)))))
                return eint(.AGAIN);
            m_i[5] += 1; // _m_count++
            return 0;
        } else {
            // Not recursive - can't re-lock
            return eint(.BUSY);
        }
    } else {
        if (own == 0x3fffffff) return eint(.NOTRECOVERABLE);
        if (own != 0 or (old != 0 and (@"type" & 4) == 0)) return eint(.BUSY);
    }

    if ((@"type" & 128) != 0) {
        if (robustOff(self_a).* == 0) {
            // Set up robust list offset: &m->_m_lock - &m->_m_next
            // _m_lock is at byte offset 4 (i[1]), _m_next is at p[4]
            const m_lock_addr = @intFromPtr(&m_i[1]);
            const m_next_addr = @intFromPtr(&m_p[4]);
            robustOff(self_a).* = @as(isize, @intCast(m_lock_addr)) - @as(isize, @intCast(m_next_addr));
            _ = linux.syscall2(.set_robust_list, self_a + off_robust_head, 3 * ptr_size);
        }
        if (m_i[2] != 0) { // _m_waiters
            var tid_u: c_uint = @bitCast(tid);
            tid_u |= 0x80000000;
            _ = @as(c_int, @bitCast(tid_u)); // tid |= 0x80000000
        }
        robustPending(self_a).* = @intFromPtr(&m_p[4]); // pending = &_m_next
    }

    var new_tid = tid | (old & 0x40000000);
    if ((@"type" & 128) != 0 and m_i[2] != 0) // robust + waiters
        new_tid |= @as(c_int, @bitCast(@as(c_uint, 0x80000000)));

    if (@cmpxchgStrong(c_int, &m_i[1], old, new_tid, .seq_cst, .seq_cst) != null) {
        robustPending(self_a).* = 0;
        if ((@"type" & 12) == 12 and m_i[2] != 0) return eint(.NOTRECOVERABLE);
        return eint(.BUSY);
    }

    // success path
    if ((@"type" & 8) != 0 and m_i[2] != 0) { // PI + waiters
        const priv: usize = (@as(usize, @intCast(@"type" & 128)) ^ 128);
        _ = linux.syscall2(.futex, @intFromPtr(&m_i[1]), FUTEX_UNLOCK_PI | priv);
        robustPending(self_a).* = 0;
        return if ((@"type" & 4) != 0) eint(.NOTRECOVERABLE) else eint(.BUSY);
    }

    // Link mutex into robust list
    const head = robustHead(self_a);
    const next_val = head.*;
    m_p[4] = next_val; // _m_next = head
    m_p[3] = @intFromPtr(head); // _m_prev = &head
    if (next_val != @intFromPtr(head)) {
        // *(void**)(next - sizeof(void*)) = &m->_m_next
        const prev_ptr: *usize = @ptrFromInt(next_val - ptr_size);
        prev_ptr.* = @intFromPtr(&m_p[4]);
    }
    head.* = @intFromPtr(&m_p[4]);
    robustPending(self_a).* = 0;

    if (old != 0) {
        m_i[5] = 0; // _m_count = 0
        return eint(.OWNERDEAD);
    }
    return 0;
}

fn mutex_trylock_fn(m: *anyopaque) callconv(.c) c_int {
    const m_i: [*]c_int = @ptrCast(@alignCast(m));
    if ((m_i[0] & 15) == 0) { // PTHREAD_MUTEX_NORMAL
        return @cmpxchgStrong(c_int, &m_i[1], 0, eint(.BUSY), .seq_cst, .seq_cst) orelse 0;
    }
    return mutex_trylock_owner_fn(m);
}

// --- pthread_mutex_timedlock.c ---

fn mutex_timedlock_pi(m: *anyopaque, at: ?*const anyopaque) c_int {
    const m_i: [*]c_int = @ptrCast(@alignCast(m));
    const @"type" = m_i[0];
    const priv: usize = (@as(usize, @intCast(@"type" & 128)) ^ 128);
    const self_a = selfAddr();

    if (priv == 0) robustPending(self_a).* = @intFromPtr(&mutexPtrs(m)[4]);

    var e: c_int = undefined;
    while (true) {
        const at_addr: usize = if (at) |p| @intFromPtr(p) else 0;
        const rc: isize = @bitCast(linux.syscall4(.futex, @intFromPtr(&m_i[1]), FUTEX_LOCK_PI | priv, 0, at_addr));
        e = -@as(c_int, @intCast(@as(i32, @truncate(rc))));
        if (e != eint(.INTR)) break;
    }
    if (e != 0) {
        robustPending(self_a).* = 0;
    }

    switch (e) {
        0 => {
            // Catch spurious success for non-robust mutexes
            if ((@"type" & 4) == 0 and ((@atomicLoad(c_int, &m_i[1], .monotonic) & 0x40000000) != 0 or m_i[2] != 0)) {
                @atomicStore(c_int, &m_i[2], -1, .seq_cst);
                _ = linux.syscall2(.futex, @intFromPtr(&m_i[1]), FUTEX_UNLOCK_PI | priv);
                robustPending(self_a).* = 0;
            } else {
                m_i[5] = -1; // _m_count = -1
                return mutex_trylock_owner_fn(m);
            }
        },
        eint(.TIMEDOUT) => return e,
        eint(.DEADLK) => {
            if ((@"type" & 3) == 2) return e; // PTHREAD_MUTEX_ERRORCHECK
        },
        else => {},
    }
    // Fall through: wait until timeout
    const __timedwait_ext = @extern(*const fn (*anyopaque, c_int, c_int, ?*const anyopaque, c_int) callconv(.c) c_int, .{ .name = "__timedwait" });
    while (true) {
        var zero: c_int = 0;
        e = __timedwait_ext(@ptrCast(&zero), 0, 0, at, 1); // CLOCK_REALTIME=0
        if (e == eint(.TIMEDOUT)) return e;
    }
}

fn mutex_timedlock_fn(m: *anyopaque, at: ?*const anyopaque) callconv(.c) c_int {
    const m_i: [*]c_int = @ptrCast(@alignCast(m));
    const __timedwait_ext = @extern(*const fn (*anyopaque, c_int, c_int, ?*const anyopaque, c_int) callconv(.c) c_int, .{ .name = "__timedwait" });

    if ((m_i[0] & 15) == 0 and @cmpxchgStrong(c_int, &m_i[1], 0, eint(.BUSY), .seq_cst, .seq_cst) == null)
        return 0;

    const @"type" = m_i[0];
    const priv: c_int = (@"type" & 128) ^ 128;

    var r = mutex_trylock_fn(m);
    if (r != eint(.BUSY)) return r;

    if ((@"type" & 8) != 0) return mutex_timedlock_pi(m, at);

    var spins: c_int = 100;
    while (spins > 0 and @atomicLoad(c_int, &m_i[1], .monotonic) != 0 and m_i[2] == 0) : (spins -= 1) {
        std.atomic.spinLoopHint();
    }

    while (true) {
        r = mutex_trylock_fn(m);
        if (r != eint(.BUSY)) return r;

        const lock_val = @atomicLoad(c_int, &m_i[1], .monotonic);
        const own = lock_val & 0x3fffffff;
        if (own == 0 and (lock_val == 0 or (@"type" & 4) != 0))
            continue;
        if ((@"type" & 3) == 2 and own == selfTid()) // ERRORCHECK
            return eint(.DEADLK);

        _ = @atomicRmw(c_int, &m_i[2], .Add, 1, .seq_cst); // _m_waiters++
        const t = lock_val | @as(c_int, @bitCast(@as(c_uint, 0x80000000)));
        _ = @cmpxchgStrong(c_int, &m_i[1], lock_val, t, .seq_cst, .seq_cst);
        r = __timedwait_ext(@ptrCast(&m_i[1]), t, 0, at, priv); // CLOCK_REALTIME=0
        _ = @atomicRmw(c_int, &m_i[2], .Add, -1, .seq_cst); // _m_waiters--
        if (r != 0 and r != eint(.INTR)) break;
    }
    return r;
}

// --- pthread_mutex_unlock.c ---
fn mutex_unlock_fn(m: *anyopaque) callconv(.c) c_int {
    const m_i: [*]c_int = @ptrCast(@alignCast(m));
    const m_p = mutexPtrs(m);
    const waiters = m_i[2]; // _m_waiters
    var cont: c_int = undefined;
    const @"type" = m_i[0] & 15;
    const priv: usize = (@as(usize, @intCast(m_i[0] & 128)) ^ 128);
    var new: c_int = 0;
    var old: c_int = undefined;

    if (@"type" != 0) { // not PTHREAD_MUTEX_NORMAL
        const self_a = selfAddr();
        old = @atomicLoad(c_int, &m_i[1], .monotonic);
        const own = old & 0x3fffffff;
        const tid = @as(*const c_int, @ptrFromInt(self_a + off_tid)).*;
        if (own != tid) return eint(.PERM);
        if ((m_i[0] & 3) == 1 and m_i[5] != 0) { // RECURSIVE + _m_count
            m_i[5] -= 1;
            return 0;
        }
        if ((m_i[0] & 4) != 0 and (old & 0x40000000) != 0)
            new = 0x7fffffff;
        if (priv == 0) { // robust (non-private)
            robustPending(self_a).* = @intFromPtr(&m_p[4]);
            const __vm_lock_ext = @extern(*const fn () callconv(.c) void, .{ .name = "__vm_lock" });
            __vm_lock_ext();
        }
        // Unlink from robust list: prev->next = next; next->prev = prev
        const prev_val = m_p[3]; // _m_prev
        const next_val = m_p[4]; // _m_next
        const prev_p: *volatile usize = @ptrFromInt(prev_val);
        prev_p.* = next_val;
        if (next_val != @intFromPtr(robustHead(self_a))) {
            const next_prev_p: *volatile usize = @ptrFromInt(next_val - ptr_size);
            next_prev_p.* = prev_val;
        }
    }
    if ((m_i[0] & 8) != 0) { // PI mutex
        if (old < 0 or @cmpxchgStrong(c_int, &m_i[1], old, new, .seq_cst, .seq_cst) != null) {
            if (new != 0) @atomicStore(c_int, &m_i[2], -1, .seq_cst);
            _ = linux.syscall2(.futex, @intFromPtr(&m_i[1]), FUTEX_UNLOCK_PI | priv);
        }
        cont = 0;
    } else {
        cont = @atomicRmw(c_int, &m_i[1], .Xchg, new, .seq_cst);
    }
    if (@"type" != 0 and priv == 0) {
        const self_a = selfAddr();
        robustPending(self_a).* = 0;
        const __vm_unlock_ext = @extern(*const fn () callconv(.c) void, .{ .name = "__vm_unlock" });
        __vm_unlock_ext();
    }
    if (waiters != 0 or cont < 0)
        wake(@ptrCast(&m_i[1]), 1, @intCast(priv));
    return 0;
}

// ============================================================
// Simple pthread stubs
// ============================================================

// --- pthread_getconcurrency.c ---
fn pthread_getconcurrency_fn() callconv(.c) c_int {
    return 0;
}

// --- pthread_setconcurrency.c ---
fn pthread_setconcurrency_fn(val: c_int) callconv(.c) c_int {
    if (val < 0) return eint(.INVAL);
    if (val > 0) return eint(.AGAIN);
    return 0;
}

// --- pthread_equal.c ---
fn pthread_equal_fn(a: usize, b: usize) callconv(.c) c_int {
    return @intFromBool(a == b);
}

// --- thrd_yield.c ---
fn thrd_yield_fn() callconv(.c) void {
    _ = linux.syscall0(.sched_yield);
}

// ============================================================
// Attribute struct field offsets
// ============================================================

// __SU = sizeof(size_t) / sizeof(int)
const SU: usize = @sizeOf(usize) / @sizeOf(c_int);

// pthread_attr_t field indices:
//   __s[0..2]  = stacksize, guardsize, stackaddr (usize-indexed)
//   __i[3*SU+0..3] = detach, sched, policy, prio (c_int-indexed)
const attr_i_detach: usize = 3 * SU;
const attr_i_sched: usize = 3 * SU + 1;
const attr_i_policy: usize = 3 * SU + 2;
const attr_i_prio: usize = 3 * SU + 3;

const PTHREAD_STACK_MIN: usize = 2048;
const SIZE_MAX: usize = std.math.maxInt(usize);
const PTHREAD_SCOPE_SYSTEM: c_int = 0;
const PTHREAD_SCOPE_PROCESS: c_int = 1;
const DEFAULT_STACK_MAX: c_uint = 8 << 20;
const DEFAULT_GUARD_MAX: c_uint = 1 << 20;
const SEM_VALUE_MAX: c_int = 0x7fffffff;

// C11 thread return codes
const thrd_success: c_int = 0;
const thrd_busy: c_int = 1;
const thrd_error: c_int = 2;
const thrd_nomem: c_int = 3;
const thrd_timedout: c_int = 4;

// C11 mutex type flags
const mtx_recursive: c_int = 1;

// POSIX mutex types
const PTHREAD_MUTEX_NORMAL: c_int = 0;
const PTHREAD_MUTEX_RECURSIVE: c_int = 1;

// POSIX cancellation constants
const PTHREAD_CANCEL_DISABLE: c_int = 1;

// POSIX priority protocol
const PTHREAD_PRIO_NONE: c_int = 0;
const PTHREAD_PRIO_INHERIT: c_int = 1;
const PTHREAD_PRIO_PROTECT: c_int = 2;

// ============================================================
// pthread_attr_t operations
// ============================================================

// --- pthread_attr_destroy.c ---
fn attr_destroy_fn(_: *anyopaque) callconv(.c) c_int {
    return 0;
}

// --- pthread_attr_init.c ---
fn attr_init_fn(a: *anyopaque) callconv(.c) c_int {
    const a_s: [*]usize = @ptrCast(@alignCast(a));
    const a_i: [*]c_int = @ptrCast(@alignCast(a));
    const n = if (@sizeOf(usize) == 8) 14 else 9;
    @memset(@as([*]u8, @ptrCast(a))[0 .. n * @sizeOf(c_int)], 0);
    const __acquire_ptc_ext = @extern(*const fn () callconv(.c) void, .{ .name = "__acquire_ptc" });
    const __release_ptc_ext = @extern(*const fn () callconv(.c) void, .{ .name = "__release_ptc" });
    __acquire_ptc_ext();
    a_s[0] = @as(*const usize, @ptrCast(@alignCast(&__default_stacksize))).*;
    a_s[1] = @as(*const usize, @ptrCast(@alignCast(&__default_guardsize))).*;
    _ = a_i; // suppress unused
    __release_ptc_ext();
    return 0;
}

// --- pthread_attr_setdetachstate.c ---
fn attr_setdetachstate_fn(a: *anyopaque, state: c_int) callconv(.c) c_int {
    if (@as(c_uint, @bitCast(state)) > 1) return eint(.INVAL);
    const a_i: [*]c_int = @ptrCast(@alignCast(a));
    a_i[attr_i_detach] = state;
    return 0;
}

// --- pthread_attr_setguardsize.c ---
fn attr_setguardsize_fn(a: *anyopaque, size: usize) callconv(.c) c_int {
    if (size > SIZE_MAX / 8) return eint(.INVAL);
    const a_s: [*]usize = @ptrCast(@alignCast(a));
    a_s[1] = size;
    return 0;
}

// --- pthread_attr_setinheritsched.c ---
fn attr_setinheritsched_fn(a: *anyopaque, inherit: c_int) callconv(.c) c_int {
    if (@as(c_uint, @bitCast(inherit)) > 1) return eint(.INVAL);
    const a_i: [*]c_int = @ptrCast(@alignCast(a));
    a_i[attr_i_sched] = inherit;
    return 0;
}

// --- pthread_attr_setschedparam.c ---
// sched_param has sched_priority as first (and only) int field
fn attr_setschedparam_fn(a: *anyopaque, param: *const c_int) callconv(.c) c_int {
    const a_i: [*]c_int = @ptrCast(@alignCast(a));
    a_i[attr_i_prio] = param.*;
    return 0;
}

// --- pthread_attr_setschedpolicy.c ---
fn attr_setschedpolicy_fn(a: *anyopaque, policy: c_int) callconv(.c) c_int {
    const a_i: [*]c_int = @ptrCast(@alignCast(a));
    a_i[attr_i_policy] = policy;
    return 0;
}

// --- pthread_attr_setscope.c ---
fn attr_setscope_fn(_: *anyopaque, scope: c_int) callconv(.c) c_int {
    return switch (scope) {
        PTHREAD_SCOPE_SYSTEM => 0,
        PTHREAD_SCOPE_PROCESS => eint(.OPNOTSUPP),
        else => eint(.INVAL),
    };
}

// --- pthread_attr_setstack.c ---
fn attr_setstack_fn(a: *anyopaque, addr: usize, size: usize) callconv(.c) c_int {
    if (size -% PTHREAD_STACK_MIN > SIZE_MAX / 4) return eint(.INVAL);
    const a_s: [*]usize = @ptrCast(@alignCast(a));
    a_s[2] = addr + size; // _a_stackaddr
    a_s[0] = size; // _a_stacksize
    return 0;
}

// --- pthread_attr_setstacksize.c ---
fn attr_setstacksize_fn(a: *anyopaque, size: usize) callconv(.c) c_int {
    if (size -% PTHREAD_STACK_MIN > SIZE_MAX / 4) return eint(.INVAL);
    const a_s: [*]usize = @ptrCast(@alignCast(a));
    a_s[2] = 0; // _a_stackaddr = 0
    a_s[0] = size; // _a_stacksize
    return 0;
}

// --- pthread_attr_get.c (getters) ---

fn attr_getdetachstate_fn(a: *const anyopaque, state: *c_int) callconv(.c) c_int {
    const a_i: [*]const c_int = @ptrCast(@alignCast(a));
    state.* = a_i[attr_i_detach];
    return 0;
}

fn attr_getguardsize_fn(a: *const anyopaque, size: *usize) callconv(.c) c_int {
    const a_s: [*]const usize = @ptrCast(@alignCast(a));
    size.* = a_s[1];
    return 0;
}

fn attr_getinheritsched_fn(a: *const anyopaque, inherit: *c_int) callconv(.c) c_int {
    const a_i: [*]const c_int = @ptrCast(@alignCast(a));
    inherit.* = a_i[attr_i_sched];
    return 0;
}

fn attr_getschedparam_fn(a: *const anyopaque, param: *c_int) callconv(.c) c_int {
    const a_i: [*]const c_int = @ptrCast(@alignCast(a));
    param.* = a_i[attr_i_prio];
    return 0;
}

fn attr_getschedpolicy_fn(a: *const anyopaque, policy: *c_int) callconv(.c) c_int {
    const a_i: [*]const c_int = @ptrCast(@alignCast(a));
    policy.* = a_i[attr_i_policy];
    return 0;
}

fn attr_getscope_fn(_: *const anyopaque, scope: *c_int) callconv(.c) c_int {
    scope.* = PTHREAD_SCOPE_SYSTEM;
    return 0;
}

fn attr_getstack_fn(a: *const anyopaque, addr: *usize, size: *usize) callconv(.c) c_int {
    const a_s: [*]const usize = @ptrCast(@alignCast(a));
    if (a_s[2] == 0) return eint(.INVAL); // no _a_stackaddr
    size.* = a_s[0];
    addr.* = a_s[2] - size.*;
    return 0;
}

fn attr_getstacksize_fn(a: *const anyopaque, size: *usize) callconv(.c) c_int {
    const a_s: [*]const usize = @ptrCast(@alignCast(a));
    size.* = a_s[0];
    return 0;
}

// ============================================================
// Barrier attr operations
// ============================================================

// --- pthread_barrierattr_destroy.c ---
fn barrierattr_destroy_fn(_: *anyopaque) callconv(.c) c_int {
    return 0;
}

// --- pthread_barrierattr_init.c ---
fn barrierattr_init_fn(a: *c_uint) callconv(.c) c_int {
    a.* = 0;
    return 0;
}

// --- pthread_barrierattr_setpshared.c ---
fn barrierattr_setpshared_fn(a: *c_int, pshared: c_int) callconv(.c) c_int {
    if (@as(c_uint, @bitCast(pshared)) > 1) return eint(.INVAL);
    a.* = if (pshared != 0) INT_MIN else 0;
    return 0;
}

// --- pthread_barrierattr_getpshared.c ---
fn barrierattr_getpshared_fn(a: *const c_uint, pshared: *c_int) callconv(.c) c_int {
    pshared.* = @intFromBool(a.* != 0);
    return 0;
}

// ============================================================
// Condvar attr operations
// ============================================================

// --- pthread_condattr_destroy.c ---
fn condattr_destroy_fn(_: *anyopaque) callconv(.c) c_int {
    return 0;
}

// --- pthread_condattr_init.c ---
fn condattr_init_fn(a: *c_int) callconv(.c) c_int {
    a.* = 0;
    return 0;
}

// --- pthread_condattr_setclock.c ---
fn condattr_setclock_fn(a: *c_int, clk: c_int) callconv(.c) c_int {
    if (clk < 0) return eint(.INVAL);
    // clk-2U < 2 catches clk==2 and clk==3 (CLOCK_MONOTONIC_RAW, etc.)
    if (@as(c_uint, @bitCast(clk)) -% 2 < 2) return eint(.INVAL);
    a.* = (a.* & @as(c_int, @bitCast(@as(c_uint, 0x80000000)))) | clk;
    return 0;
}

// --- pthread_condattr_setpshared.c ---
fn condattr_setpshared_fn(a: *c_uint, pshared: c_int) callconv(.c) c_int {
    if (@as(c_uint, @bitCast(pshared)) > 1) return eint(.INVAL);
    a.* = (a.* & 0x7fffffff) | (@as(c_uint, @bitCast(pshared)) << 31);
    return 0;
}

// --- pthread_condattr_getclock.c ---
fn condattr_getclock_fn(a: *const c_int, clk: *c_int) callconv(.c) c_int {
    clk.* = a.* & 0x7fffffff;
    return 0;
}

// --- pthread_condattr_getpshared.c ---
fn condattr_getpshared_fn(a: *const c_uint, pshared: *c_int) callconv(.c) c_int {
    pshared.* = @intCast(a.* >> 31);
    return 0;
}

// ============================================================
// Mutex attr operations
// ============================================================

// --- pthread_mutexattr_destroy.c ---
fn mutexattr_destroy_fn(_: *anyopaque) callconv(.c) c_int {
    return 0;
}

// --- pthread_mutexattr_init.c ---
fn mutexattr_init_fn(a: *c_uint) callconv(.c) c_int {
    a.* = 0;
    return 0;
}

// --- pthread_mutexattr_setprotocol.c ---
var check_pi_result: c_int = -1;
fn mutexattr_setprotocol_fn(a: *c_uint, protocol: c_int) callconv(.c) c_int {
    switch (protocol) {
        PTHREAD_PRIO_NONE => {
            a.* &= ~@as(c_uint, 8);
            return 0;
        },
        PTHREAD_PRIO_INHERIT => {
            var r = @atomicLoad(c_int, &check_pi_result, .seq_cst);
            if (r < 0) {
                var lk: c_int = 0;
                const rc: isize = @bitCast(linux.syscall4(.futex, @intFromPtr(&lk), 6, 0, 0)); // FUTEX_LOCK_PI=6
                r = -@as(c_int, @truncate(rc));
                @atomicStore(c_int, &check_pi_result, r, .seq_cst);
            }
            if (r != 0) return r;
            a.* |= 8;
            return 0;
        },
        PTHREAD_PRIO_PROTECT => return eint(.OPNOTSUPP),
        else => return eint(.INVAL),
    }
}

// --- pthread_mutexattr_setpshared.c ---
fn mutexattr_setpshared_fn(a: *c_uint, pshared: c_int) callconv(.c) c_int {
    if (@as(c_uint, @bitCast(pshared)) > 1) return eint(.INVAL);
    a.* = (a.* & ~@as(c_uint, 128)) | (@as(c_uint, @bitCast(pshared)) << 7);
    return 0;
}

// --- pthread_mutexattr_setrobust.c ---
var check_robust_result: c_int = -1;
fn mutexattr_setrobust_fn(a: *c_uint, robust: c_int) callconv(.c) c_int {
    if (@as(c_uint, @bitCast(robust)) > 1) return eint(.INVAL);
    if (robust != 0) {
        var r = @atomicLoad(c_int, &check_robust_result, .seq_cst);
        if (r < 0) {
            var p: usize = undefined;
            var l: usize = undefined;
            const rc: isize = @bitCast(linux.syscall3(.get_robust_list, 0, @intFromPtr(&p), @intFromPtr(&l)));
            r = -@as(c_int, @truncate(rc));
            @atomicStore(c_int, &check_robust_result, r, .seq_cst);
        }
        if (r != 0) return r;
        a.* |= 4;
        return 0;
    }
    a.* &= ~@as(c_uint, 4);
    return 0;
}

// --- pthread_mutexattr_settype.c ---
fn mutexattr_settype_fn(a: *c_uint, t: c_int) callconv(.c) c_int {
    if (@as(c_uint, @bitCast(t)) > 2) return eint(.INVAL);
    a.* = (a.* & ~@as(c_uint, 3)) | @as(c_uint, @bitCast(t));
    return 0;
}

// --- pthread_mutexattr_getprotocol.c ---
fn mutexattr_getprotocol_fn(a: *const c_uint, protocol: *c_int) callconv(.c) c_int {
    protocol.* = @intCast((a.* / 8) % 2);
    return 0;
}

// --- pthread_mutexattr_getpshared.c ---
fn mutexattr_getpshared_fn(a: *const c_uint, pshared: *c_int) callconv(.c) c_int {
    pshared.* = @intCast((a.* / 128) % 2);
    return 0;
}

// --- pthread_mutexattr_getrobust.c ---
fn mutexattr_getrobust_fn(a: *const c_uint, robust: *c_int) callconv(.c) c_int {
    robust.* = @intCast((a.* / 4) % 2);
    return 0;
}

// --- pthread_mutexattr_gettype.c ---
fn mutexattr_gettype_fn(a: *const c_uint, t: *c_int) callconv(.c) c_int {
    t.* = @intCast(a.* & 3);
    return 0;
}

// ============================================================
// RWLock attr operations
// ============================================================

// --- pthread_rwlockattr_destroy.c ---
fn rwlockattr_destroy_fn(_: *anyopaque) callconv(.c) c_int {
    return 0;
}

// --- pthread_rwlockattr_init.c ---
fn rwlockattr_init_fn(a: *anyopaque) callconv(.c) c_int {
    const a_i: [*]c_int = @ptrCast(@alignCast(a));
    a_i[0] = 0;
    a_i[1] = 0;
    return 0;
}

// --- pthread_rwlockattr_setpshared.c ---
fn rwlockattr_setpshared_fn(a: *c_int, pshared: c_int) callconv(.c) c_int {
    if (@as(c_uint, @bitCast(pshared)) > 1) return eint(.INVAL);
    a.* = pshared;
    return 0;
}

// --- pthread_rwlockattr_getpshared.c ---
fn rwlockattr_getpshared_fn(a: *const c_int, pshared: *c_int) callconv(.c) c_int {
    pshared.* = a.*;
    return 0;
}

// ============================================================
// Mutex init / destroy / prioceiling
// ============================================================

// --- pthread_mutex_destroy.c ---
fn mutex_destroy_fn(m: *anyopaque) callconv(.c) c_int {
    const m_i: [*]c_int = @ptrCast(@alignCast(m));
    if (m_i[0] > 128) { // _m_type > 128 → process-shared with nontrivial type
        const __vm_wait_ext = @extern(*const fn () callconv(.c) void, .{ .name = "__vm_wait" });
        __vm_wait_ext();
    }
    return 0;
}

// --- pthread_mutex_init.c ---
fn mutex_init_fn(m: *anyopaque, a: ?*const c_uint) callconv(.c) c_int {
    const size = if (@sizeOf(usize) == 8) 14 * @sizeOf(c_int) else 6 * @sizeOf(c_int);
    @memset(@as([*]u8, @ptrCast(m))[0..size], 0);
    if (a) |attr| {
        const m_i: [*]c_int = @ptrCast(@alignCast(m));
        m_i[0] = @bitCast(attr.*); // _m_type = a->__attr
    }
    return 0;
}

// --- pthread_mutex_getprioceiling.c ---
fn mutex_getprioceiling_fn(_: *const anyopaque, _: *c_int) callconv(.c) c_int {
    return eint(.INVAL);
}

// --- pthread_mutex_setprioceiling.c ---
fn mutex_setprioceiling_fn(_: *anyopaque, _: c_int, _: ?*c_int) callconv(.c) c_int {
    return eint(.INVAL);
}

// ============================================================
// Semaphore simple operations
// ============================================================

// --- sem_destroy.c ---
fn sem_destroy_fn(_: *anyopaque) callconv(.c) c_int {
    return 0;
}

// --- sem_getvalue.c ---
fn sem_getvalue_fn(sem: *anyopaque, valp: *c_int) callconv(.c) c_int {
    const s: [*]volatile c_int = @ptrCast(@alignCast(sem));
    valp.* = s[0] & SEM_VALUE_MAX;
    return 0;
}

// --- sem_init.c ---
fn sem_init_fn(sem: *anyopaque, pshared: c_int, value: c_uint) callconv(.c) c_int {
    if (@as(c_int, @bitCast(value)) < 0) { // value > SEM_VALUE_MAX
        // errno = EINVAL
        const __errno_location = @extern(*const fn () callconv(.c) *c_int, .{ .name = "__errno_location" });
        __errno_location().* = eint(.INVAL);
        return -1;
    }
    const s: [*]volatile c_int = @ptrCast(@alignCast(sem));
    s[0] = @bitCast(value);
    s[1] = 0;
    s[2] = if (pshared != 0) 0 else 128;
    return 0;
}

// --- sem_unlink.c ---
fn sem_unlink_fn(name: [*:0]const u8) callconv(.c) c_int {
    const shm_unlink_ext = @extern(*const fn ([*:0]const u8) callconv(.c) c_int, .{ .name = "shm_unlink" });
    return shm_unlink_ext(name);
}

// --- sem_wait.c ---
fn sem_wait_fn(sem: *anyopaque) callconv(.c) c_int {
    const sem_timedwait_ext = @extern(*const fn (*anyopaque, ?*const anyopaque) callconv(.c) c_int, .{ .name = "sem_timedwait" });
    return sem_timedwait_ext(sem, null);
}

// ============================================================
// C11 cnd_* wrappers
// ============================================================

// --- call_once.c ---
fn call_once_fn(flag: *c_int, func: *const fn () callconv(.c) void) callconv(.c) void {
    const __pthread_once_ext = @extern(*const fn (*c_int, *const fn () callconv(.c) void) callconv(.c) c_int, .{ .name = "__pthread_once" });
    _ = __pthread_once_ext(flag, func);
}

// --- cnd_broadcast.c ---
fn cnd_broadcast_fn2(c: *anyopaque) callconv(.c) c_int {
    const __priv_cond_sig = @extern(*const fn (*anyopaque, c_int) callconv(.c) c_int, .{ .name = "__private_cond_signal" });
    return __priv_cond_sig(c, -1);
}

// --- cnd_destroy.c ---
fn cnd_destroy_fn2(_: *anyopaque) callconv(.c) void {}

// --- cnd_init.c ---
fn cnd_init_fn2(c: *anyopaque) callconv(.c) c_int {
    const bytes: [*]u8 = @ptrCast(c);
    @memset(bytes[0 .. cond_int_count * @sizeOf(c_int)], 0);
    return thrd_success;
}

// --- cnd_signal.c ---
fn cnd_signal_fn2(c: *anyopaque) callconv(.c) c_int {
    const __priv_cond_sig = @extern(*const fn (*anyopaque, c_int) callconv(.c) c_int, .{ .name = "__private_cond_signal" });
    return __priv_cond_sig(c, 1);
}

// --- cnd_timedwait.c ---
fn cnd_timedwait_fn(c: *anyopaque, m: *anyopaque, ts: ?*const anyopaque) callconv(.c) c_int {
    const __pthread_cond_timedwait_ext = @extern(*const fn (*anyopaque, *anyopaque, ?*const anyopaque) callconv(.c) c_int, .{ .name = "__pthread_cond_timedwait" });
    const ret = __pthread_cond_timedwait_ext(c, m, ts);
    return switch (ret) {
        0 => thrd_success,
        @as(c_int, @intCast(@intFromEnum(E.TIMEDOUT))) => thrd_timedout,
        else => thrd_error,
    };
}

// --- cnd_wait.c ---
fn cnd_wait_fn2(c: *anyopaque, m: *anyopaque) callconv(.c) c_int {
    return cnd_timedwait_fn(c, m, null);
}

// ============================================================
// C11 mtx_* wrappers
// ============================================================

// --- mtx_destroy.c ---
fn mtx_destroy_fn(_: *anyopaque) callconv(.c) void {}

// --- mtx_init.c ---
fn mtx_init_fn(m: *anyopaque, t: c_int) callconv(.c) c_int {
    const m_i: [*]c_int = @ptrCast(@alignCast(m));
    const size = if (@sizeOf(usize) == 8) 14 * @sizeOf(c_int) else 6 * @sizeOf(c_int);
    @memset(@as([*]u8, @ptrCast(m))[0..size], 0);
    m_i[0] = if ((t & mtx_recursive) != 0) PTHREAD_MUTEX_RECURSIVE else PTHREAD_MUTEX_NORMAL;
    return thrd_success;
}

// --- mtx_lock.c ---
fn mtx_lock_fn(m: *anyopaque) callconv(.c) c_int {
    const m_i: [*]c_int = @ptrCast(@alignCast(m));
    if (m_i[0] == PTHREAD_MUTEX_NORMAL) {
        if (@cmpxchgStrong(c_int, &m_i[1], 0, eint(.BUSY), .seq_cst, .seq_cst) == null)
            return thrd_success;
    }
    return mtx_timedlock_fn(m, null);
}

// --- mtx_timedlock.c ---
fn mtx_timedlock_fn(m: *anyopaque, ts: ?*const anyopaque) callconv(.c) c_int {
    const __pthread_mutex_timedlock_ext = @extern(*const fn (*anyopaque, ?*const anyopaque) callconv(.c) c_int, .{ .name = "__pthread_mutex_timedlock" });
    const ret = __pthread_mutex_timedlock_ext(m, ts);
    return switch (ret) {
        0 => thrd_success,
        @as(c_int, @intCast(@intFromEnum(E.TIMEDOUT))) => thrd_timedout,
        else => thrd_error,
    };
}

// --- mtx_trylock.c ---
fn mtx_trylock_fn(m: *anyopaque) callconv(.c) c_int {
    const m_i: [*]c_int = @ptrCast(@alignCast(m));
    if (m_i[0] == PTHREAD_MUTEX_NORMAL) {
        return if ((@cmpxchgStrong(c_int, &m_i[1], 0, eint(.BUSY), .seq_cst, .seq_cst) orelse 0) & eint(.BUSY) != 0)
            thrd_busy
        else
            thrd_success;
    }
    const __pthread_mutex_trylock_ext = @extern(*const fn (*anyopaque) callconv(.c) c_int, .{ .name = "__pthread_mutex_trylock" });
    const ret = __pthread_mutex_trylock_ext(m);
    return switch (ret) {
        0 => thrd_success,
        eint(.BUSY) => thrd_busy,
        else => thrd_error,
    };
}

// --- mtx_unlock.c ---
fn mtx_unlock_fn(m: *anyopaque) callconv(.c) c_int {
    const __pthread_mutex_unlock_ext = @extern(*const fn (*anyopaque) callconv(.c) c_int, .{ .name = "__pthread_mutex_unlock" });
    return __pthread_mutex_unlock_ext(m);
}

// ============================================================
// C11 thrd_* wrappers
// ============================================================

// --- thrd_create.c ---
// __ATTRP_C11_THREAD is a sentinel value: (void*)(size_t)-1
fn thrd_create_fn(thr: *usize, func: *const anyopaque, arg: ?*anyopaque) callconv(.c) c_int {
    const __pthread_create_ext = @extern(*const fn (*usize, ?*const anyopaque, *const anyopaque, ?*anyopaque) callconv(.c) c_int, .{ .name = "__pthread_create" });
    const ATTRP_C11: usize = @bitCast(@as(isize, -1));
    const ret = __pthread_create_ext(thr, @ptrFromInt(ATTRP_C11), func, arg);
    return switch (ret) {
        0 => thrd_success,
        eint(.AGAIN) => thrd_nomem,
        else => thrd_error,
    };
}

// --- thrd_exit.c ---
fn thrd_exit_fn(result: c_int) callconv(.c) noreturn {
    const __pthread_exit_ext = @extern(*const fn (?*anyopaque) callconv(.c) noreturn, .{ .name = "__pthread_exit" });
    __pthread_exit_ext(@ptrFromInt(@as(usize, @bitCast(@as(isize, result)))));
}

// --- thrd_join.c ---
fn thrd_join_fn(t: usize, res: ?*c_int) callconv(.c) c_int {
    const __pthread_join_ext = @extern(*const fn (usize, *?*anyopaque) callconv(.c) c_int, .{ .name = "__pthread_join" });
    var pthread_res: ?*anyopaque = null;
    _ = __pthread_join_ext(t, &pthread_res);
    if (res) |r| {
        r.* = @truncate(@as(isize, @bitCast(@intFromPtr(pthread_res))));
    }
    return thrd_success;
}

// --- thrd_sleep.c ---
fn thrd_sleep_fn(req: *const anyopaque, rem: ?*anyopaque) callconv(.c) c_int {
    const __clock_nanosleep_ext = @extern(*const fn (c_int, c_int, *const anyopaque, ?*anyopaque) callconv(.c) c_int, .{ .name = "__clock_nanosleep" });
    const ret = -__clock_nanosleep_ext(0, 0, req, rem); // CLOCK_REALTIME = 0
    if (ret == 0) return 0;
    if (ret == -eint(.INTR)) return -1;
    return -2;
}

// ============================================================
// C11 tss_* wrappers
// ============================================================

// --- tss_create.c ---
fn tss_create_fn(tss: *c_uint, dtor: ?*const anyopaque) callconv(.c) c_int {
    const __pthread_key_create_ext = @extern(*const fn (*c_uint, ?*const anyopaque) callconv(.c) c_int, .{ .name = "__pthread_key_create" });
    return if (__pthread_key_create_ext(tss, dtor) != 0) thrd_error else thrd_success;
}

// --- tss_delete.c ---
fn tss_delete_fn(key: c_uint) callconv(.c) void {
    const __pthread_key_delete_ext = @extern(*const fn (c_uint) callconv(.c) c_int, .{ .name = "__pthread_key_delete" });
    _ = __pthread_key_delete_ext(key);
}

// --- tss_set.c ---
// Accesses self->tsd[k] - use struct pthread layout
fn tss_set_fn(k: c_uint, x: ?*anyopaque) callconv(.c) c_int {
    const self_addr = selfAddr();
    const off_tsd: usize = off_map_base + 7 * ptr_size;
    const tsd_pp: *[*]?*anyopaque = @ptrFromInt(self_addr + off_tsd);
    const tsd = tsd_pp.*;
    if (tsd[k] != x) {
        tsd[k] = x;
        // tsd_used is at off_tid+18 (1 byte, bitfield byte)
        const tsd_used: *u8 = @ptrFromInt(self_addr + off_tid + 18);
        tsd_used.* = 1;
    }
    return thrd_success;
}

// ============================================================
// pthread_setattr_default_np / pthread_getattr_default_np
// ============================================================

// --- pthread_setattr_default_np.c ---
fn setattr_default_np_fn(attrp: *const anyopaque) callconv(.c) c_int {
    // Reject anything except stack/guard size.
    // C code: copy attr, zero stacksize+guardsize, check rest is all-zero.
    const a_s: [*]const usize = @ptrCast(@alignCast(attrp));
    const n_ints: usize = if (@sizeOf(usize) == 8) 14 else 9;
    const bytes: [*]const u8 = @ptrCast(attrp);
    const total_bytes = n_ints * @sizeOf(c_int);
    const skip_bytes = 2 * @sizeOf(usize); // skip stacksize (__s[0]) and guardsize (__s[1])
    var j: usize = skip_bytes;
    while (j < total_bytes) : (j += 1) {
        if (bytes[j] != 0) return eint(.INVAL);
    }

    const stack_u: c_uint = @truncate(a_s[0]);
    const guard_u: c_uint = @truncate(a_s[1]);
    const stack = @min(stack_u, DEFAULT_STACK_MAX);
    const guard = @min(guard_u, DEFAULT_GUARD_MAX);

    const __inhibit_ptc_ext = @extern(*const fn () callconv(.c) void, .{ .name = "__inhibit_ptc" });
    const __release_ptc_ext = @extern(*const fn () callconv(.c) void, .{ .name = "__release_ptc" });
    __inhibit_ptc_ext();
    if (stack > __default_stacksize) __default_stacksize = stack;
    if (guard > __default_guardsize) __default_guardsize = guard;
    __release_ptc_ext();
    return 0;
}

// --- pthread_getattr_default_np (in same file) ---
fn getattr_default_np_fn(attrp: *anyopaque) callconv(.c) c_int {
    const a_s: [*]usize = @ptrCast(@alignCast(attrp));
    const n_ints: usize = if (@sizeOf(usize) == 8) 14 else 9;
    @memset(@as([*]u8, @ptrCast(attrp))[0 .. n_ints * @sizeOf(c_int)], 0);
    const __acquire_ptc_ext = @extern(*const fn () callconv(.c) void, .{ .name = "__acquire_ptc" });
    const __release_ptc_ext = @extern(*const fn () callconv(.c) void, .{ .name = "__release_ptc" });
    __acquire_ptc_ext();
    a_s[0] = __default_stacksize;
    a_s[1] = __default_guardsize;
    __release_ptc_ext();
    return 0;
}
