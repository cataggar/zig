const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;

const tls_module_t = opaque {};
const LibC = extern struct {
    can_do_threads: u8,
    threaded: u8,
    secure: u8,
    need_locks: i8,
    threads_minus_1: c_int,
    auxv: ?[*]usize,
    tls_head: ?*tls_module_t,
    tls_size: usize,
    tls_align: usize,
    tls_cnt: usize,
    page_size: usize,
};
extern var __libc: LibC;
const E = std.os.linux.E;
/// `typedef struct { unsigned __attr; } pthread_mutexattr_t;`
const pthread_mutexattr_t = extern struct { __attr: c_uint = 0 };
/// `typedef struct { unsigned __attr; } pthread_condattr_t;`
const pthread_condattr_t = extern struct { __attr: c_uint = 0 };
/// `typedef struct { unsigned __attr; } pthread_barrierattr_t;`
const pthread_barrierattr_t = extern struct { __attr: c_uint = 0 };
/// `typedef struct { unsigned __attr[2]; } pthread_rwlockattr_t;`
const pthread_rwlockattr_t = extern struct { __attr: [2]c_uint = .{ 0, 0 } };
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
const mutex_size = if (@sizeOf(c_ulong) == 8) @as(usize, 40) else 24;
const pthread_mutex_impl = extern struct {
    _m_type: c_int = 0,
    _m_lock: c_int = 0,
    _padding: [mutex_size - 2 * @sizeOf(c_int)]u8 = [_]u8{0} ** (mutex_size - 2 * @sizeOf(c_int)),
};
const rwlock_size = if (@sizeOf(c_ulong) == 8) @as(usize, 56) else 32;
const pthread_rwlock_impl = extern struct {
    _rw_lock: c_int = 0,
    _rw_waiters: c_int = 0,
    _rw_shared: c_int = 0,
    _padding: [rwlock_size - 3 * @sizeOf(c_int)]u8 = [_]u8{0} ** (rwlock_size - 3 * @sizeOf(c_int)),
};
const pthread_cond_impl = extern struct {
    _c_shared: usize = 0,
    _pad1: [16 - @sizeOf(usize)]u8 = [_]u8{0} ** (16 - @sizeOf(usize)),
    _c_clock: c_int = 0,
    _pad2: [48 - 16 - @sizeOf(c_int)]u8 = [_]u8{0} ** (48 - 16 - @sizeOf(c_int)),
};
const barrier_size = if (@sizeOf(c_ulong) == 8) @as(usize, 32) else 20;
const pthread_barrier_impl = extern struct {
    _b_lock: c_int = 0,
    _b_waiters: c_int = 0,
    _b_limit: c_int = 0,
    _padding: [barrier_size - 3 * @sizeOf(c_int)]u8 = [_]u8{0} ** (barrier_size - 3 * @sizeOf(c_int)),
};
// Comptime errno constants for use in switch cases.
const c_EBUSY: c_int = @intCast(@intFromEnum(E.BUSY));
const c_ETIMEDOUT: c_int = @intCast(@intFromEnum(E.TIMEDOUT));
const sem_val_len = 4 * @sizeOf(c_long) / @sizeOf(c_int);
const sem_impl = extern struct {
    __val: [sem_val_len]c_int = [_]c_int{0} ** sem_val_len,
};
const arch = builtin.target.cpu.arch;
const tls_above_tp = switch (arch) {
    .aarch64, .aarch64_be, .arm, .armeb, .thumb, .thumbeb,
    .riscv64, .riscv32, .mips, .mipsel, .mips64, .mips64el,
    .powerpc, .powerpcle, .powerpc64, .powerpc64le,
    .loongarch64, .m68k => true,
    else => false,
};
/// TP_OFFSET from musl per-arch pthread_arch.h (defaults to 0).
const tp_offset: usize = switch (arch) {
    .mips, .mipsel, .mips64, .mips64el,
    .powerpc, .powerpcle, .powerpc64, .powerpc64le,
    .m68k => 0x7000,
    else => 0,
};
const ptr_size = @sizeOf(usize);
/// Part 1 of struct pthread: ABI fields whose presence depends on TLS model.
/// Non-TLS_ABOVE_TP: self, dtv, prev, next, sysinfo, canary = 6 pointers.
/// TLS_ABOVE_TP: self, prev, next, sysinfo = 4 pointers.
const part1_size: usize = if (tls_above_tp) 4 * ptr_size else 6 * ptr_size;
/// Total sizeof(struct pthread): 200 on 64-bit, 112 on 32-bit.
const sizeof_pthread: usize = if (ptr_size == 8) 200 else 112;
/// Padding from Part 2 byte 19 to next pointer-aligned boundary.
const map_base_off: usize = if (ptr_size == 8) 24 else 20;
// Field offsets from struct pthread base.
const off_detach_state = part1_size + 8;
const off_canceldisable = part1_size + 16;
const off_cancelasync = part1_size + 17;
const off_tsd_flags = part1_size + 18;
const off_tsd = part1_size + map_base_off + 7 * ptr_size;
/// Musl detach state enum values from pthread_impl.h.
const DT_JOINABLE: c_int = 2;
const DT_DETACHED: c_int = 3;
const SEM_VALUE_MAX: c_int = 0x7fffffff;
const linux = std.os.linux;
const off_tid = part1_size;
const off_killlock = part1_size + map_base_off + 11 * ptr_size + 8 + ptr_size;
const CLOCK_REALTIME: c_int = 0;
/// Musl's struct __ptcb from pthread.h.
const PtCb = extern struct {
    f: ?*const fn (?*anyopaque) callconv(.c) void,
    x: ?*anyopaque,
    next: ?*PtCb,
};
const PR_SET_NAME: usize = 15;
const PR_GET_NAME: usize = 16;
const AT_FDCWD: usize = @bitCast(@as(isize, -100));
const O_CLOEXEC: usize = 0o2000000;
const thrd_success: c_int = 0;
const thrd_error: c_int = 2;
const thrd_nomem: c_int = 3;
const _NSIG: c_uint = 129;
var check_pi_result: c_int = -1;
var check_robust_result: c_int = -1;
const rwlock_int_count: usize = if (@sizeOf(c_long) == 8) 14 else 8;
var ptc_lock: [rwlock_int_count]c_int = [_]c_int{0} ** rwlock_int_count;
const FUTEX_WAIT: usize = 0;
const FUTEX_WAKE: usize = 1;
const FUTEX_PRIVATE: usize = 128;
var vmlock: [2]c_int = .{ 0, 0 };
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
const rwlock_ints = if (@sizeOf(c_long) == 8) 14 else 8;
var ptc_rwlock: [rwlock_ints]c_int = .{0} ** rwlock_ints;
const PTHREAD_BARRIER_SERIAL_THREAD: c_int = -1;
const barrier_int_count: usize = if (@sizeOf(usize) == 8) 8 else 5;
const BarrierInstance = extern struct {
    count: c_int = 0,
    last: c_int = 0,
    waiters: c_int = 0,
    finished: c_int = 0,
};
const cond_int_count: usize = if (@sizeOf(usize) == 8) 12 else 8;
const FUTEX_LOCK_PI: usize = 6;
const FUTEX_UNLOCK_PI: usize = 7;
// Pthread struct offsets for robust_list (relative to self pointer)
const off_after_bitfields: usize = off_tid + 19; // tid(4)+errno_val(4)+detach_state(4)+cancel(4)+canceldisable(1)+cancelasync(1)+bitfield_byte(1)
const off_map_base: usize = std.mem.alignForward(usize, off_after_bitfields, ptr_size);
const off_robust_head: usize = off_map_base + 8 * ptr_size; // skip: map_base, map_size, stack, stack_size, guard_size, result, cancelbuf, tsd
const off_robust_off: usize = off_robust_head + ptr_size;
const off_robust_pending: usize = off_robust_head + 2 * ptr_size;
// __SU = sizeof(size_t) / sizeof(int)
const SU: usize = @sizeOf(usize) / @sizeOf(c_int);
// pthread_attr_t field indices:
//   __s[0..2]  = stacksize, guardsize, stackaddr (usize-indexed)
//   __i[3*SU+0..3] = detach, sched, policy, prio (c_int-indexed)
const attr_i_detach: usize = 3 * SU;
const attr_i_sched: usize = 3 * SU + 1;
const attr_i_policy: usize = 3 * SU + 2;
const attr_i_prio: usize = 3 * SU + 3;
const SIZE_MAX: usize = std.math.maxInt(usize);
const PTHREAD_SCOPE_SYSTEM: c_int = 0;
const PTHREAD_SCOPE_PROCESS: c_int = 1;
const DEFAULT_STACK_MAX: c_uint = 8 << 20;
const DEFAULT_GUARD_MAX: c_uint = 1 << 20;
const thrd_busy: c_int = 1;
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
const off_cancel: usize = off_tid + 12;
// DT_* enum values
const DT_EXITED: c_int = 0;
var vmlock_storage: [2]c_int = .{ 0, 0 };
const SIG_BLOCK: c_int = 0;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&pthread_attr_destroy, "pthread_attr_destroy");
        symbol(&pthread_mutexattr_destroy, "pthread_mutexattr_destroy");
        symbol(&pthread_condattr_destroy, "pthread_condattr_destroy");
        symbol(&pthread_rwlockattr_destroy, "pthread_rwlockattr_destroy");
        symbol(&pthread_barrierattr_destroy, "pthread_barrierattr_destroy");
        symbol(&pthread_spin_destroy, "pthread_spin_destroy");
        symbol(&pthread_rwlock_destroy, "pthread_rwlock_destroy");
        symbol(&sem_destroy, "sem_destroy");
        symbol(&pthread_getconcurrency, "pthread_getconcurrency");
        symbol(&pthread_setconcurrency, "pthread_setconcurrency");
        symbol(&pthread_mutex_getprioceiling, "pthread_mutex_getprioceiling");
        symbol(&cnd_destroy, "cnd_destroy");
        symbol(&mtx_destroy, "mtx_destroy");
        symbol(&pthread_equal, "pthread_equal");
        symbol(&pthread_mutexattr_init, "pthread_mutexattr_init");
        symbol(&pthread_condattr_init, "pthread_condattr_init");
        symbol(&pthread_rwlockattr_init, "pthread_rwlockattr_init");
        symbol(&pthread_barrierattr_init, "pthread_barrierattr_init");
        symbol(&pthread_spin_init, "pthread_spin_init");
        symbol(&pthread_mutexattr_settype, "pthread_mutexattr_settype");
        symbol(&pthread_mutexattr_setpshared, "pthread_mutexattr_setpshared");
        symbol(&pthread_condattr_setclock, "pthread_condattr_setclock");
        symbol(&pthread_condattr_setpshared, "pthread_condattr_setpshared");
        symbol(&pthread_rwlockattr_setpshared, "pthread_rwlockattr_setpshared");
        symbol(&pthread_barrierattr_setpshared, "pthread_barrierattr_setpshared");
        symbol(&pthread_attr_setscope, "pthread_attr_setscope");
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
        symbol(&pthread_attr_setdetachstate, "pthread_attr_setdetachstate");
        symbol(&pthread_attr_setguardsize, "pthread_attr_setguardsize");
        symbol(&pthread_attr_setinheritsched, "pthread_attr_setinheritsched");
        symbol(&pthread_attr_setschedparam, "pthread_attr_setschedparam");
        symbol(&pthread_attr_setschedpolicy, "pthread_attr_setschedpolicy");
        symbol(&pthread_attr_setstack, "pthread_attr_setstack");
        symbol(&pthread_attr_setstacksize, "pthread_attr_setstacksize");
        symbol(&pthread_spin_lock, "pthread_spin_lock");
        symbol(&pthread_spin_trylock, "pthread_spin_trylock");
        symbol(&pthread_spin_unlock, "pthread_spin_unlock");
        symbol(&pthread_mutex_init, "pthread_mutex_init");
        symbol(&pthread_rwlock_init, "pthread_rwlock_init");
        symbol(&pthread_cond_init, "pthread_cond_init");
        symbol(&pthread_barrier_init, "pthread_barrier_init");
        symbol(&pthread_mutex_setprioceiling, "pthread_mutex_setprioceiling");
        symbol(&sem_init, "sem_init");
        symbol(&sem_getvalue, "sem_getvalue");
        symbol(&cnd_init, "cnd_init");
        symbol(&mtx_init, "mtx_init");
        symbol(&thrd_yield, "thrd_yield");
        symbol(&pthread_self_fn, "pthread_self");
        symbol(&pthread_getspecific_fn, "pthread_getspecific");
        symbol(&pthread_setspecific_fn, "pthread_setspecific");
        symbol(&pthread_setcancelstate_fn, "__pthread_setcancelstate");
        symbol(&pthread_testcancel_fn, "pthread_testcancel");
        symbol(&pthread_setcancelstate_fn, "pthread_setcancelstate");
        symbol(&pthread_setcanceltype_fn, "pthread_setcanceltype");
        symbol(&pthread_testcancel_fn, "__pthread_testcancel");
        symbol(&sem_trywait_fn, "sem_trywait");
        symbol(&sem_post_fn, "sem_post");
        symbol(&__clone_fn, "__clone");
        symbol(&__default_stacksize, "__default_stacksize");
        symbol(&__default_guardsize, "__default_guardsize");
    }
    if (builtin.target.isMuslLibC()) {
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
            symbol(&pthread_detach_fn, "pthread_detach");
            symbol(&sem_wait_fn, "sem_wait");
            symbol(&sem_unlink_fn, "sem_unlink");
            symbol(&do_cleanup_push_default, "__do_cleanup_push");
            symbol(&do_cleanup_pop_default, "__do_cleanup_pop");
            symbol(&_pthread_cleanup_push_fn, "_pthread_cleanup_push");
            symbol(&_pthread_cleanup_pop_fn, "_pthread_cleanup_pop");
            symbol(&pthread_getschedparam_fn, "pthread_getschedparam");
            symbol(&pthread_setschedparam_fn, "pthread_setschedparam");
            symbol(&pthread_getname_np_fn, "pthread_getname_np");
            symbol(&pthread_setname_np_fn, "pthread_setname_np");
            symbol(&sem_timedwait_fn, "sem_timedwait");
            symbol(&thrd_create_fn, "thrd_create");
            symbol(&thrd_exit_fn, "thrd_exit");
            symbol(&thrd_join_fn, "thrd_join");
            symbol(&thrd_sleep_fn, "thrd_sleep");
            symbol(&pthread_getcpuclockid_fn, "pthread_getcpuclockid");
            symbol(&pthread_kill_fn, "pthread_kill");
            symbol(&pthread_setschedprio_fn, "pthread_setschedprio");
            symbol(&pthread_sigmask_fn, "pthread_sigmask");
            symbol(&pthread_mutexattr_setprotocol_fn, "pthread_mutexattr_setprotocol");
            symbol(&pthread_mutexattr_setrobust_fn, "pthread_mutexattr_setrobust");
            symbol(&pthread_mutex_destroy_fn, "pthread_mutex_destroy");
            symbol(&inhibit_ptc_fn, "__inhibit_ptc");
            symbol(&acquire_ptc_fn, "__acquire_ptc");
            symbol(&release_ptc_fn, "__release_ptc");
            symbol(&__pthread_once_fn, "__pthread_once");
            symbol(&__wait_fn, "__wait");
            symbol(&vm_wait_fn, "__vm_wait");
            symbol(&vm_lock_fn, "__vm_lock");
            symbol(&vm_unlock_fn, "__vm_unlock");
            symbol(&__lock_fn, "__lock");
            symbol(&__unlock_fn, "__unlock");
            symbol(&rwlock_tryrdlock_fn, "__pthread_rwlock_tryrdlock");
            symbol(&rwlock_trywrlock_fn, "__pthread_rwlock_trywrlock");
            symbol(&rwlock_unlock_fn, "__pthread_rwlock_unlock");
            symbol(&rwlock_timedrdlock_fn, "__pthread_rwlock_timedrdlock");
            symbol(&rwlock_timedwrlock_fn, "__pthread_rwlock_timedwrlock");
            symbol(&rwlock_rdlock_fn, "__pthread_rwlock_rdlock");
            symbol(&rwlock_wrlock_fn, "__pthread_rwlock_wrlock");
            symbol(&barrier_destroy_fn, "pthread_barrier_destroy");
            symbol(&barrier_wait_fn, "pthread_barrier_wait");
            symbol(&cond_destroy_fn, "pthread_cond_destroy");
            symbol(&cond_signal_fn, "pthread_cond_signal");
            symbol(&cond_broadcast_fn, "pthread_cond_broadcast");
            symbol(&cond_wait_fn, "pthread_cond_wait");
            symbol(&mutex_lock_fn, "__pthread_mutex_lock");
            symbol(&mutex_consistent_fn, "pthread_mutex_consistent");
            symbol(&mutex_trylock_owner_fn, "__pthread_mutex_trylock_owner");
            symbol(&mutex_trylock_fn, "__pthread_mutex_trylock");
            symbol(&mutex_timedlock_fn, "__pthread_mutex_timedlock");
            symbol(&mutex_unlock_fn, "__pthread_mutex_unlock");
            symbol(&attr_init_fn, "pthread_attr_init");
            symbol(&tss_set_fn, "tss_set");
            symbol(&setattr_default_np_fn, "pthread_setattr_default_np");
            symbol(&getattr_default_np_fn, "pthread_getattr_default_np");
            symbol(&syscall_cp_fn, "__syscall_cp");
            symbol(&testcancel_fn, "__testcancel");
        }
    }
    @export(&vmlock, .{ .name = "__vmlock_lockptr" });
}

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

fn pthread_getconcurrency() callconv(.c) c_int {
    return 0;
}

fn pthread_setconcurrency(val: c_int) callconv(.c) c_int {
    if (val < 0) return eint(.INVAL);
    if (val > 0) return eint(.AGAIN);
    return 0;
}

fn pthread_mutex_getprioceiling(m: ?*const anyopaque, ceiling: ?*c_int) callconv(.c) c_int {
    _ = m;
    _ = ceiling;
    return eint(.INVAL);
}

fn cnd_destroy(c: ?*anyopaque) callconv(.c) void {
    _ = c;
}

fn mtx_destroy(mtx: ?*anyopaque) callconv(.c) void {
    _ = mtx;
}

fn pthread_equal(a: std.c.pthread_t, b: std.c.pthread_t) callconv(.c) c_int {
    return @intCast(@intFromBool(a == b));
}

/// Convert a Linux errno enum value to a positive c_int for direct return
/// from POSIX thread functions (which return error numbers, not -1).
fn eint(e: E) c_int {
    return @intCast(@intFromEnum(e));
}

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

fn pthread_mutex_init(m: *pthread_mutex_impl, a: ?*const pthread_mutexattr_t) callconv(.c) c_int {
    m.* = .{};
    if (a) |attr| m._m_type = @bitCast(attr.__attr);
    return 0;
}

fn pthread_rwlock_init(rw: *pthread_rwlock_impl, a: ?*const pthread_rwlockattr_t) callconv(.c) c_int {
    rw.* = .{};
    if (a) |attr| rw._rw_shared = @bitCast(attr.__attr[0] * @as(c_uint, 128));
    return 0;
}

fn pthread_cond_init(c: *pthread_cond_impl, a: ?*const pthread_condattr_t) callconv(.c) c_int {
    c.* = .{};
    if (a) |attr| {
        c._c_clock = @bitCast(attr.__attr & 0x7fffffff);
        if (attr.__attr >> 31 != 0) c._c_shared = std.math.maxInt(usize);
    }
    return 0;
}

fn pthread_barrier_init(b: *pthread_barrier_impl, a: ?*const pthread_barrierattr_t, count: c_uint) callconv(.c) c_int {
    if (count -% 1 > 0x7FFFFFFE) return eint(.INVAL);
    b.* = .{};
    b._b_limit = @bitCast((count -% 1) | if (a) |attr| attr.__attr else 0);
    return 0;
}

fn pthread_mutex_setprioceiling(m: ?*anyopaque, ceiling: c_int, old: ?*c_int) callconv(.c) c_int {
    _ = m;
    _ = ceiling;
    _ = old;
    return eint(.INVAL);
}

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

/// Read the architecture-specific thread pointer register.
fn get_tp() usize {
    return switch (arch) {
        .x86_64 => asm ("mov %%fs:0, %[ret]"
            : [ret] "=r" (-> usize),
        ),
        .x86 => asm ("movl %%gs:0, %[ret]"
            : [ret] "=r" (-> usize),
        ),
        .aarch64, .aarch64_be => asm ("mrs %[ret], tpidr_el0"
            : [ret] "=r" (-> usize),
        ),
        .arm, .armeb, .thumb, .thumbeb => asm ("mrc p15, 0, %[ret], c13, c0, 3"
            : [ret] "=r" (-> usize),
        ),
        .riscv64, .riscv32 => asm ("mv %[ret], tp"
            : [ret] "=r" (-> usize),
        ),
        .s390x => asm (
            \\ear  %[ret], %%a0
            \\sllg %[ret], %[ret], 32
            \\ear  %[ret], %%a1
            : [ret] "=r" (-> usize),
        ),
        .mips, .mipsel => asm (
            \\.set push
            \\.set mips32r2
            \\rdhwr %[ret], $29
            \\.set pop
            : [ret] "=r" (-> usize),
        ),
        .mips64, .mips64el => asm (
            \\rdhwr %[ret], $29
            : [ret] "=r" (-> usize),
        ),
        .powerpc, .powerpcle => asm ("mr %[ret], 2"
            : [ret] "=r" (-> usize),
        ),
        .powerpc64, .powerpc64le => asm ("mr %[ret], 13"
            : [ret] "=r" (-> usize),
        ),
        .loongarch64 => asm ("move %[ret], $tp"
            : [ret] "=r" (-> usize),
        ),
        .m68k => std.os.linux.syscall0(.get_thread_area),
        else => @compileError("unsupported architecture for __pthread_self"),
    };
}

/// Equivalent to musl's __pthread_self() macro: returns the struct pthread address.
fn pthread_self_ptr() usize {
    const tp = get_tp();
    return if (tls_above_tp) tp - sizeof_pthread - tp_offset else tp;
}

fn pthread_self_fn() callconv(.c) std.c.pthread_t {
    return @ptrFromInt(pthread_self_ptr());
}

fn pthread_getspecific_fn(k: c_uint) callconv(.c) ?*anyopaque {
    const self = pthread_self_ptr();
    const tsd: *[*]?*anyopaque = @ptrFromInt(self + off_tsd);
    return tsd.*[k];
}

fn pthread_setspecific_fn(k: c_uint, x: ?*const anyopaque) callconv(.c) c_int {
    const self = pthread_self_ptr();
    const tsd: *[*]?*anyopaque = @ptrFromInt(self + off_tsd);
    const val: ?*anyopaque = @constCast(x);
    if (tsd.*[k] != val) {
        tsd.*[k] = val;
        const flags: *u8 = @ptrFromInt(self + off_tsd_flags);
        // C bitfield tsd_used:1 — bit 0 on LE, bit 7 on BE
        const tsd_used_bit: u8 = if (arch.endian() == .big) 0x80 else 1;
        flags.* |= tsd_used_bit;
    }
    return 0;
}

fn pthread_setcancelstate_fn(new: c_int, old: ?*c_int) callconv(.c) c_int {
    if (@as(c_uint, @bitCast(new)) > 2) return eint(.INVAL);
    const self = pthread_self_ptr();
    const cd: *u8 = @ptrFromInt(self + off_canceldisable);
    if (old) |o| o.* = cd.*;
    cd.* = @intCast(@as(c_uint, @bitCast(new)));
    return 0;
}

fn pthread_setcanceltype_fn(new: c_int, old: ?*c_int) callconv(.c) c_int {
    const self = pthread_self_ptr();
    if (@as(c_uint, @bitCast(new)) > 1) return eint(.INVAL);
    const ca: *u8 = @ptrFromInt(self + off_cancelasync);
    if (old) |o| o.* = ca.*;
    ca.* = @intCast(@as(c_uint, @bitCast(new)));
    if (new != 0) pthread_testcancel_fn();
    return 0;
}

fn pthread_testcancel_fn() callconv(.c) void {
    if (builtin.link_libc) {
        const __testcancel = @extern(*const fn () callconv(.c) void, .{ .name = "__testcancel" });
        __testcancel();
    }
}

fn pthread_detach_fn(t: std.c.pthread_t) callconv(.c) c_int {
    const t_addr = @intFromPtr(t);
    const ds: *c_int = @ptrFromInt(t_addr + off_detach_state);
    if (@cmpxchgStrong(c_int, ds, DT_JOINABLE, DT_DETACHED, .seq_cst, .seq_cst) != null) {
        var cs: c_int = undefined;
        _ = pthread_setcancelstate_fn(1, &cs);
        const __pthread_join = @extern(*const fn (std.c.pthread_t, ?*?*anyopaque) callconv(.c) c_int, .{ .name = "__pthread_join" });
        _ = __pthread_join(t, null);
        _ = pthread_setcancelstate_fn(cs, null);
    }
    return 0;
}

fn sem_trywait_fn(sem: *sem_impl) callconv(.c) c_int {
    while (true) {
        const val = @atomicLoad(c_int, &sem.__val[0], .monotonic);
        if ((val & SEM_VALUE_MAX) == 0) break;
        if (@cmpxchgStrong(c_int, &sem.__val[0], val, val - 1, .seq_cst, .seq_cst) == null) return 0;
    }
    std.c._errno().* = eint(.AGAIN);
    return -1;
}

fn sem_post_fn(sem: *sem_impl) callconv(.c) c_int {
    const priv = sem.__val[2];
    while (true) {
        const val = @atomicLoad(c_int, &sem.__val[0], .monotonic);
        const waiters = @atomicLoad(c_int, &sem.__val[1], .monotonic);
        if ((val & SEM_VALUE_MAX) == SEM_VALUE_MAX) {
            std.c._errno().* = eint(.OVERFLOW);
            return -1;
        }
        var new_val = val + 1;
        if (waiters <= 1) new_val &= SEM_VALUE_MAX;
        if (@cmpxchgStrong(c_int, &sem.__val[0], val, new_val, .seq_cst, .seq_cst) == null) {
            if (val < 0) futex_wake(&sem.__val[0], if (waiters > 1) @as(c_int, 1) else -1, priv);
            return 0;
        }
    }
}

fn sem_wait_fn(sem: *sem_impl) callconv(.c) c_int {
    const ext = @extern(*const fn (*sem_impl, ?*const anyopaque) callconv(.c) c_int, .{ .name = "sem_timedwait" });
    return ext(sem, null);
}

fn sem_unlink_fn(name: [*:0]const u8) callconv(.c) c_int {
    const shm_unlink = @extern(*const fn ([*:0]const u8) callconv(.c) c_int, .{ .name = "shm_unlink" });
    return shm_unlink(name);
}

fn futex_wake(addr: *const c_int, cnt: c_int, priv: c_int) void {
    const p: usize = if (priv != 0) FUTEX_PRIVATE else 0;
    const max_int: c_int = std.math.maxInt(c_int);
    const c: usize = @intCast(if (cnt < 0) max_int else cnt);
    const rc: isize = @bitCast(std.os.linux.syscall4(.futex, @intFromPtr(addr), FUTEX_WAKE | p, c, 0));
    if (rc == -@as(isize, @intFromEnum(E.NOSYS))) {
        _ = std.os.linux.syscall4(.futex, @intFromPtr(addr), FUTEX_WAKE, c, 0);
    }
}

fn do_cleanup_push_default(cb: *PtCb) callconv(.c) void {
    _ = cb;
}

fn do_cleanup_pop_default(cb: *PtCb) callconv(.c) void {
    _ = cb;
}

fn _pthread_cleanup_push_fn(cb: *PtCb, f: *const fn (?*anyopaque) callconv(.c) void, x: ?*anyopaque) callconv(.c) void {
    cb.f = f;
    cb.x = x;
    const __do_cleanup_push = @extern(*const fn (*PtCb) callconv(.c) void, .{ .name = "__do_cleanup_push" });
    __do_cleanup_push(cb);
}

fn _pthread_cleanup_pop_fn(cb: *PtCb, run: c_int) callconv(.c) void {
    const __do_cleanup_pop = @extern(*const fn (*PtCb) callconv(.c) void, .{ .name = "__do_cleanup_pop" });
    __do_cleanup_pop(cb);
    if (run != 0) {
        if (cb.f) |f| f(cb.x);
    }
}

fn pthread_getschedparam_fn(t: std.c.pthread_t, policy: *c_int, param: *sched_param) callconv(.c) c_int {
    const __block_app_sigs = @extern(*const fn (*anyopaque) callconv(.c) void, .{ .name = "__block_app_sigs" });
    const __restore_sigs = @extern(*const fn (*anyopaque) callconv(.c) void, .{ .name = "__restore_sigs" });
    const __lock = @extern(*const fn (*c_int) callconv(.c) void, .{ .name = "__lock" });
    const __unlock = @extern(*const fn (*c_int) callconv(.c) void, .{ .name = "__unlock" });

    var r: c_int = undefined;
    var set: [128]u8 = undefined;
    __block_app_sigs(@ptrCast(&set));

    const t_addr = @intFromPtr(t);
    const killlock: *c_int = @ptrFromInt(t_addr + off_killlock);
    __lock(killlock);

    const tid: c_int = (@as(*const c_int, @ptrFromInt(t_addr + off_tid))).*;
    if (tid == 0) {
        r = eint(.SRCH);
    } else {
        const rc: isize = @bitCast(linux.syscall2(.sched_getparam, @as(usize, @intCast(tid)), @intFromPtr(param)));
        r = @intCast(-rc);
        if (r == 0) {
            const sched_rc: isize = @bitCast(linux.syscall1(.sched_getscheduler, @as(usize, @intCast(tid))));
            policy.* = @intCast(sched_rc);
        }
    }

    __unlock(killlock);
    __restore_sigs(@ptrCast(&set));
    return r;
}

fn pthread_setschedparam_fn(t: std.c.pthread_t, policy: c_int, param: *const sched_param) callconv(.c) c_int {
    const __block_app_sigs = @extern(*const fn (*anyopaque) callconv(.c) void, .{ .name = "__block_app_sigs" });
    const __restore_sigs = @extern(*const fn (*anyopaque) callconv(.c) void, .{ .name = "__restore_sigs" });
    const __lock = @extern(*const fn (*c_int) callconv(.c) void, .{ .name = "__lock" });
    const __unlock = @extern(*const fn (*c_int) callconv(.c) void, .{ .name = "__unlock" });

    var set: [128]u8 = undefined;
    __block_app_sigs(@ptrCast(&set));

    const t_addr = @intFromPtr(t);
    const killlock: *c_int = @ptrFromInt(t_addr + off_killlock);
    __lock(killlock);

    const tid: c_int = (@as(*const c_int, @ptrFromInt(t_addr + off_tid))).*;
    const r: c_int = if (tid == 0)
        eint(.SRCH)
    else blk: {
        const rc: isize = @bitCast(linux.syscall3(.sched_setscheduler, @as(usize, @intCast(tid)), @as(usize, @bitCast(@as(isize, policy))), @intFromPtr(param)));
        break :blk @intCast(-rc);
    };

    __unlock(killlock);
    __restore_sigs(@ptrCast(&set));
    return r;
}

fn pthread_getname_np_fn(thread: std.c.pthread_t, name: [*]u8, len: usize) callconv(.c) c_int {
    if (len < 16) return eint(.RANGE);

    const pthread_self_ext = @extern(*const fn () callconv(.c) std.c.pthread_t, .{ .name = "pthread_self" });
    if (thread == pthread_self_ext()) {
        const rc: isize = @bitCast(linux.syscall5(.prctl, PR_GET_NAME, @intFromPtr(name), 0, 0, 0));
        return if (rc < 0) @intCast(-rc) else 0;
    }

    const tid: c_int = (@as(*const c_int, @ptrFromInt(@intFromPtr(thread) + off_tid))).*;
    var path_buf: [40]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "/proc/self/task/{d}/comm", .{tid}) catch unreachable;

    const pthread_setcancelstate_ext = @extern(*const fn (c_int, ?*c_int) callconv(.c) c_int, .{ .name = "pthread_setcancelstate" });
    var cs: c_int = undefined;
    _ = pthread_setcancelstate_ext(1, &cs); // PTHREAD_CANCEL_DISABLE

    var status: c_int = 0;
    const fd_raw: isize = @bitCast(linux.syscall4(.openat, AT_FDCWD, @intFromPtr(path.ptr), O_CLOEXEC, 0));
    if (fd_raw < 0) {
        status = @intCast(-fd_raw);
    } else {
        const fd: usize = @intCast(fd_raw);
        const n_raw: isize = @bitCast(linux.syscall3(.read, fd, @intFromPtr(name), len));
        if (n_raw < 0) {
            status = @intCast(-n_raw);
        } else {
            // Remove trailing newline
            name[@as(usize, @intCast(n_raw)) - 1] = 0;
        }
        _ = linux.syscall1(.close, fd);
    }

    _ = pthread_setcancelstate_ext(cs, null);
    return status;
}

fn pthread_setname_np_fn(thread: std.c.pthread_t, name: [*:0]const u8) callconv(.c) c_int {
    // strnlen(name, 16)
    var name_len: usize = 0;
    while (name_len < 16 and name[name_len] != 0) : (name_len += 1) {}
    if (name_len > 15) return eint(.RANGE);

    const pthread_self_ext = @extern(*const fn () callconv(.c) std.c.pthread_t, .{ .name = "pthread_self" });
    if (thread == pthread_self_ext()) {
        const rc: isize = @bitCast(linux.syscall5(.prctl, PR_SET_NAME, @intFromPtr(name), 0, 0, 0));
        return if (rc < 0) @intCast(-rc) else 0;
    }

    const tid: c_int = (@as(*const c_int, @ptrFromInt(@intFromPtr(thread) + off_tid))).*;
    var path_buf: [40]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "/proc/self/task/{d}/comm", .{tid}) catch unreachable;

    const pthread_setcancelstate_ext = @extern(*const fn (c_int, ?*c_int) callconv(.c) c_int, .{ .name = "pthread_setcancelstate" });
    var cs: c_int = undefined;
    _ = pthread_setcancelstate_ext(1, &cs); // PTHREAD_CANCEL_DISABLE

    var status: c_int = 0;
    const fd_raw: isize = @bitCast(linux.syscall4(.openat, AT_FDCWD, @intFromPtr(path.ptr), O_CLOEXEC | 1, 0)); // O_WRONLY=1
    if (fd_raw < 0) {
        status = @intCast(-fd_raw);
    } else {
        const fd: usize = @intCast(fd_raw);
        const n_raw: isize = @bitCast(linux.syscall3(.write, fd, @intFromPtr(name), name_len));
        if (n_raw < 0) {
            status = @intCast(-n_raw);
        }
        _ = linux.syscall1(.close, fd);
    }

    _ = pthread_setcancelstate_ext(cs, null);
    return status;
}

fn sem_timedwait_cleanup(p: ?*anyopaque) callconv(.c) void {
    const ptr: *c_int = @ptrCast(@alignCast(p));
    _ = @atomicRmw(c_int, ptr, .Sub, 1, .seq_cst);
}

fn sem_timedwait_fn(sem: *sem_impl, at: ?*const anyopaque) callconv(.c) c_int {
    const pthread_testcancel_ext = @extern(*const fn () callconv(.c) void, .{ .name = "pthread_testcancel" });
    const sem_trywait_ext = @extern(*const fn (*sem_impl) callconv(.c) c_int, .{ .name = "sem_trywait" });
    const __timedwait_cp = @extern(*const fn (*c_int, c_int, c_int, ?*const anyopaque, c_int) callconv(.c) c_int, .{ .name = "__timedwait_cp" });

    pthread_testcancel_ext();
    if (sem_trywait_ext(sem) == 0) return 0;

    // Spin briefly before blocking
    var spins: c_int = 100;
    while (spins > 0) : (spins -= 1) {
        if ((@atomicLoad(c_int, &sem.__val[0], .monotonic) & SEM_VALUE_MAX) != 0) break;
        if (@atomicLoad(c_int, &sem.__val[1], .monotonic) != 0) break;
        std.atomic.spinLoopHint();
    }

    while (sem_trywait_ext(sem) != 0) {
        const priv = sem.__val[2];
        _ = @atomicRmw(c_int, &sem.__val[1], .Add, 1, .seq_cst);
        const WAITER_FLAG: c_int = @bitCast(@as(c_uint, 0x80000000));
        _ = @cmpxchgStrong(c_int, &sem.__val[0], 0, WAITER_FLAG, .seq_cst, .seq_cst);

        var cb: PtCb = undefined;
        _pthread_cleanup_push_fn(&cb, sem_timedwait_cleanup, @ptrCast(&sem.__val[1]));
        const r = __timedwait_cp(&sem.__val[0], WAITER_FLAG, CLOCK_REALTIME, at, priv);
        _pthread_cleanup_pop_fn(&cb, 1);

        if (r != 0) {
            std.c._errno().* = r;
            return -1;
        }
    }
    return 0;
}

fn thrd_create_fn(thr: *anyopaque, func: ?*const anyopaque, arg: ?*anyopaque) callconv(.c) c_int {
    // __ATTRP_C11_THREAD sentinel: (void*)(uintptr_t)-1
    const ATTRP_C11_THREAD: ?*const anyopaque = @ptrFromInt(std.math.maxInt(usize));
    const __pthread_create = @extern(*const fn (*anyopaque, ?*const anyopaque, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int, .{ .name = "__pthread_create" });
    const ret = __pthread_create(thr, ATTRP_C11_THREAD, func, arg);
    if (ret == 0) return thrd_success;
    if (ret == eint(.AGAIN)) return thrd_nomem;
    return thrd_error;
}

fn thrd_exit_fn(result: c_int) callconv(.c) noreturn {
    const __pthread_exit = @extern(*const fn (?*anyopaque) callconv(.c) noreturn, .{ .name = "__pthread_exit" });
    // (void*)(intptr_t)result — sign-extend int to pointer
    __pthread_exit(@ptrFromInt(@as(usize, @bitCast(@as(isize, result)))));
}

fn thrd_join_fn(t: std.c.pthread_t, res: ?*c_int) callconv(.c) c_int {
    var pthread_res: usize = 0;
    const __pthread_join = @extern(*const fn (std.c.pthread_t, *usize) callconv(.c) c_int, .{ .name = "__pthread_join" });
    _ = __pthread_join(t, &pthread_res);
    if (res) |r| {
        // (int)(intptr_t)pthread_res — truncate pointer to int
        r.* = @as(c_int, @truncate(@as(isize, @bitCast(pthread_res))));
    }
    return thrd_success;
}

fn thrd_sleep_fn(req: ?*const anyopaque, rem: ?*anyopaque) callconv(.c) c_int {
    const __clock_nanosleep = @extern(*const fn (c_int, c_int, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int, .{ .name = "__clock_nanosleep" });
    const ret: c_int = 0 -% __clock_nanosleep(CLOCK_REALTIME, 0, req, rem);
    if (ret == 0) return 0;
    if (ret == 0 -% eint(.INTR)) return -1;
    return -2;
}

// pthread_getcpuclockid.c
fn pthread_getcpuclockid_fn(t: std.c.pthread_t, clockid: *c_int) callconv(.c) c_int {
    const tid: c_int = (@as(*const c_int, @ptrFromInt(@intFromPtr(t) + off_tid))).*;
    // (-t->tid - 1) * 8U + 6
    const neg_tid_m1: c_uint = @bitCast((0 -% tid) -% @as(c_int, 1));
    clockid.* = @bitCast(neg_tid_m1 *% 8 +% 6);
    return 0;
}

// pthread_kill.c
fn pthread_kill_fn(t: std.c.pthread_t, sig: c_int) callconv(.c) c_int {
    const __block_all_sigs = @extern(*const fn (*anyopaque) callconv(.c) void, .{ .name = "__block_all_sigs" });
    const __restore_sigs = @extern(*const fn (*anyopaque) callconv(.c) void, .{ .name = "__restore_sigs" });
    const __lock = @extern(*const fn (*c_int) callconv(.c) void, .{ .name = "__lock" });
    const __unlock = @extern(*const fn (*c_int) callconv(.c) void, .{ .name = "__unlock" });

    var set: [128]u8 = undefined;
    __block_all_sigs(@ptrCast(&set));

    const t_addr = @intFromPtr(t);
    const killlock: *c_int = @ptrFromInt(t_addr + off_killlock);
    __lock(killlock);

    const tid: c_int = (@as(*const c_int, @ptrFromInt(t_addr + off_tid))).*;
    const r: c_int = if (tid != 0) blk: {
        const rc: isize = @bitCast(linux.syscall2(.tkill, @as(usize, @intCast(tid)), @as(usize, @bitCast(@as(isize, sig)))));
        break :blk @as(c_int, @intCast(-rc));
    } else if (@as(c_uint, @bitCast(sig)) >= _NSIG) eint(.INVAL) else 0;

    __unlock(killlock);
    __restore_sigs(@ptrCast(&set));
    return r;
}

// pthread_setschedprio.c
fn pthread_setschedprio_fn(t: std.c.pthread_t, prio: c_int) callconv(.c) c_int {
    const __block_app_sigs = @extern(*const fn (*anyopaque) callconv(.c) void, .{ .name = "__block_app_sigs" });
    const __restore_sigs = @extern(*const fn (*anyopaque) callconv(.c) void, .{ .name = "__restore_sigs" });
    const __lock = @extern(*const fn (*c_int) callconv(.c) void, .{ .name = "__lock" });
    const __unlock = @extern(*const fn (*c_int) callconv(.c) void, .{ .name = "__unlock" });

    var set: [128]u8 = undefined;
    __block_app_sigs(@ptrCast(&set));

    const t_addr = @intFromPtr(t);
    const killlock: *c_int = @ptrFromInt(t_addr + off_killlock);
    __lock(killlock);

    const tid: c_int = (@as(*const c_int, @ptrFromInt(t_addr + off_tid))).*;
    var prio_val = prio;
    const r: c_int = if (tid == 0)
        eint(.SRCH)
    else blk: {
        const rc: isize = @bitCast(linux.syscall2(.sched_setparam, @as(usize, @intCast(tid)), @intFromPtr(&prio_val)));
        break :blk @as(c_int, @intCast(-rc));
    };

    __unlock(killlock);
    __restore_sigs(@ptrCast(&set));
    return r;
}

// pthread_sigmask.c
fn pthread_sigmask_fn(how: c_int, set: ?*const anyopaque, old: ?*anyopaque) callconv(.c) c_int {
    if (set != null and @as(c_uint, @bitCast(how)) > 2) return eint(.INVAL);
    const sig_set_size: usize = linux.NSIG / 8;
    const set_addr: usize = if (set) |s| @intFromPtr(s) else 0;
    const old_addr: usize = if (old) |o| @intFromPtr(o) else 0;
    const ret: c_int = blk: {
        const rc: isize = @bitCast(linux.syscall4(.rt_sigprocmask, @as(usize, @bitCast(@as(isize, how))), set_addr, old_addr, sig_set_size));
        break :blk @as(c_int, @intCast(-rc));
    };
    if (ret == 0) {
        if (old) |o| {
            // Clear internal signal bits (SIGTIMER=32, SIGCANCEL=33, SIGSYNCCALL=34)
            if (@sizeOf(c_ulong) == 8) {
                const p: *u64 = @ptrCast(@alignCast(o));
                p.* &= ~@as(u64, 0x380000000);
            } else {
                const p: [*]u32 = @ptrCast(@alignCast(o));
                p[0] &= ~@as(u32, 0x80000000);
                p[1] &= ~@as(u32, 0x3);
            }
        }
    }
    return ret;
}

fn wake(addr: *anyopaque, cnt: c_int, priv_val: c_int) void {
    const p: usize = if (priv_val != 0) FUTEX_PRIVATE else 0;
    const n: usize = if (cnt < 0) @as(usize, @intCast(std.math.maxInt(c_int))) else @as(usize, @intCast(cnt));
    _ = linux.syscall3(.futex, @intFromPtr(addr), FUTEX_WAKE | p, n);
}

fn pthread_mutexattr_setprotocol_fn(a: *c_uint, protocol: c_int) callconv(.c) c_int {
    if (protocol == 0) { // PTHREAD_PRIO_NONE
        a.* &= ~@as(c_uint, 8);
        return 0;
    } else if (protocol == 1) { // PTHREAD_PRIO_INHERIT
        var r = @atomicLoad(c_int, &check_pi_result, .monotonic);
        if (r < 0) {
            var lk: c_int = 0;
            const rc: isize = @bitCast(linux.syscall4(.futex, @intFromPtr(&lk), FUTEX_LOCK_PI, 0, 0));
            r = @as(c_int, @intCast(-rc));
            @atomicStore(c_int, &check_pi_result, r, .release);
        }
        if (r != 0) return r;
        a.* |= 8;
        return 0;
    } else if (protocol == 2) { // PTHREAD_PRIO_PROTECT
        return eint(.OPNOTSUPP);
    } else {
        return eint(.INVAL);
    }
}

fn pthread_mutexattr_setrobust_fn(a: *c_uint, robust: c_int) callconv(.c) c_int {
    if (@as(c_uint, @bitCast(robust)) > 1) return eint(.INVAL);
    if (robust != 0) {
        var r = @atomicLoad(c_int, &check_robust_result, .monotonic);
        if (r < 0) {
            var p: usize = undefined;
            var l: usize = undefined;
            const rc: isize = @bitCast(linux.syscall3(.get_robust_list, 0, @intFromPtr(&p), @intFromPtr(&l)));
            r = @as(c_int, @intCast(-rc));
            @atomicStore(c_int, &check_robust_result, r, .release);
        }
        if (r != 0) return r;
        a.* |= 4;
        return 0;
    }
    a.* &= ~@as(c_uint, 4);
    return 0;
}

fn pthread_mutex_destroy_fn(mutex: *anyopaque) callconv(.c) c_int {
    // _m_type is the first int in pthread_mutex_t
    const m_type: c_int = @as(*const c_int, @ptrCast(@alignCast(mutex))).*;
    if (m_type > 128) {
        const __vm_wait = @extern(*const fn () callconv(.c) void, .{ .name = "__vm_wait" });
        __vm_wait();
    }
    return 0;
}

fn inhibit_ptc_fn() callconv(.c) void {
    const f = @extern(*const fn (*anyopaque) callconv(.c) c_int, .{ .name = "pthread_rwlock_wrlock" });
    _ = f(@ptrCast(&ptc_lock));
}

fn acquire_ptc_fn() callconv(.c) void {
    const f = @extern(*const fn (*anyopaque) callconv(.c) c_int, .{ .name = "pthread_rwlock_rdlock" });
    _ = f(@ptrCast(&ptc_lock));
}

fn release_ptc_fn() callconv(.c) void {
    const f = @extern(*const fn (*anyopaque) callconv(.c) c_int, .{ .name = "pthread_rwlock_unlock" });
    _ = f(@ptrCast(&ptc_lock));
}

fn undo_once(control: ?*anyopaque) callconv(.c) void {
    const ptr: *c_int = @ptrCast(@alignCast(control));
    if (@atomicRmw(c_int, ptr, .Xchg, 0, .seq_cst) == 3)
        wake(@ptrCast(ptr), -1, 1);
}

fn __pthread_once_fn(control: *c_int, init: *const fn () callconv(.c) void) callconv(.c) c_int {
    if (@atomicLoad(c_int, control, .acquire) == 2) return 0;
    return pthread_once_full(control, init);
}

fn pthread_once_full(control: *c_int, init: *const fn () callconv(.c) void) c_int {
    const __wait_ext = @extern(*const fn (*anyopaque, ?*anyopaque, c_int, c_int) callconv(.c) void, .{ .name = "__wait" });
    const _pthread_cleanup_push = @extern(*const fn (*PtCb, *const fn (?*anyopaque) callconv(.c) void, ?*anyopaque) callconv(.c) void, .{ .name = "_pthread_cleanup_push" });
    const _pthread_cleanup_pop = @extern(*const fn (*PtCb, c_int) callconv(.c) void, .{ .name = "_pthread_cleanup_pop" });

    while (true) {
        const result = @cmpxchgStrong(c_int, control, 0, 1, .seq_cst, .seq_cst);
        if (result) |prev| {
            switch (prev) {
                1 => {
                    // Another thread is initializing; set waiter flag and wait
                    _ = @cmpxchgStrong(c_int, control, 1, 3, .seq_cst, .seq_cst);
                    __wait_ext(@ptrCast(control), null, 3, 1);
                },
                3 => {
                    __wait_ext(@ptrCast(control), null, 3, 1);
                },
                2 => return 0,
                else => unreachable,
            }
        } else {
            // CAS succeeded (was 0, now 1): run the init function
            var cb: PtCb = undefined;
            _pthread_cleanup_push(&cb, undo_once, @ptrCast(control));
            init();
            _pthread_cleanup_pop(&cb, 0);
            if (@atomicRmw(c_int, control, .Xchg, 2, .seq_cst) == 3)
                wake(@ptrCast(control), -1, 1);
            return 0;
        }
    }
}

fn __wait_fn(addr: *anyopaque, waiters_opt: ?*anyopaque, val: c_int, priv_arg: c_int) callconv(.c) void {
    const priv: usize = if (priv_arg != 0) FUTEX_PRIVATE else 0;
    const addr_ptr: *c_int = @ptrCast(@alignCast(addr));
    const waiters_ptr: ?*c_int = if (waiters_opt) |w| @as(*c_int, @ptrCast(@alignCast(w))) else null;

    // Spin phase: spin briefly before blocking
    var spins: c_int = 100;
    while (spins > 0) : (spins -= 1) {
        if (waiters_ptr) |w| {
            if (@atomicLoad(c_int, w, .monotonic) != 0) break;
        }
        if (@atomicLoad(c_int, addr_ptr, .monotonic) == val) {
            std.atomic.spinLoopHint();
        } else {
            return;
        }
    }

    // Register as waiter
    if (waiters_ptr) |w| {
        _ = @atomicRmw(c_int, w, .Add, 1, .seq_cst);
    }

    // Futex wait loop
    while (@atomicLoad(c_int, addr_ptr, .monotonic) == val) {
        const val_u: usize = @as(usize, @bitCast(@as(isize, val)));
        const rc: isize = @bitCast(linux.syscall4(.futex, @intFromPtr(addr), FUTEX_WAIT | priv, val_u, 0));
        // Fall back to shared futex if private not supported
        if (rc == -@as(isize, @intCast(@intFromEnum(E.NOSYS)))) {
            _ = linux.syscall4(.futex, @intFromPtr(addr), FUTEX_WAIT, val_u, 0);
        }
    }

    // Deregister as waiter
    if (waiters_ptr) |w| {
        _ = @atomicRmw(c_int, w, .Add, -1, .seq_cst);
    }
}

fn vm_wait_fn() callconv(.c) void {
    while (true) {
        const tmp = @atomicLoad(c_int, &vmlock[0], .monotonic);
        if (tmp == 0) break;
        __wait_fn(@ptrCast(&vmlock[0]), @ptrCast(&vmlock[1]), tmp, 1);
    }
}

fn vm_lock_fn() callconv(.c) void {
    _ = @atomicRmw(c_int, &vmlock[0], .Add, 1, .seq_cst);
}

fn vm_unlock_fn() callconv(.c) void {
    if (@atomicRmw(c_int, &vmlock[0], .Add, -1, .seq_cst) == 1 and
        @atomicLoad(c_int, &vmlock[1], .monotonic) != 0)
    {
        wake(@ptrCast(&vmlock[0]), -1, 1);
    }
}

fn __clone_fn(_: ?*const fn (?*anyopaque) callconv(.c) c_int, _: ?*anyopaque, _: c_int, _: ?*anyopaque) callconv(.c) c_int {
    return -@as(c_int, @intCast(@intFromEnum(E.NOSYS)));
}

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

fn __inhibit_ptc_fn() callconv(.c) void {
    _ = rwlock_wrlock_fn(@ptrCast(&ptc_rwlock));
}

fn __acquire_ptc_fn() callconv(.c) void {
    _ = rwlock_rdlock_fn(@ptrCast(&ptc_rwlock));
}

fn __release_ptc_fn() callconv(.c) void {
    _ = rwlock_unlock_fn(@ptrCast(&ptc_rwlock));
}

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

fn mutexPtrs(m: *anyopaque) [*]usize {
    return @ptrCast(@alignCast(m));
}

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

// --- pthread_mutexattr_destroy.c ---
fn mutexattr_destroy_fn(_: *anyopaque) callconv(.c) c_int {
    return 0;
}

// --- pthread_mutexattr_init.c ---
fn mutexattr_init_fn(a: *c_uint) callconv(.c) c_int {
    a.* = 0;
    return 0;
}

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

fn wait_fn(addr: *volatile c_int, waiters: ?*volatile c_int, val: c_int, priv_arg: c_int) callconv(.c) void {
    var spins: c_int = 100;
    const priv: usize = if (priv_arg != 0) FUTEX_PRIVATE else 0;
    while (spins > 0) : (spins -= 1) {
        if (waiters) |w| {
            if (w.* != 0) break;
        }
        if (addr.* == val) {
            std.atomic.spinLoopHint();
        } else {
            return;
        }
    }
    if (waiters) |w| {
        _ = @atomicRmw(c_int, @constCast(@volatileCast(w)), .Add, 1, .seq_cst);
    }
    while (addr.* == val) {
        const val_u: usize = @bitCast(@as(isize, val));
        const rc: isize = @bitCast(linux.syscall4(.futex, @intFromPtr(addr), FUTEX_WAIT | priv, val_u, 0));
        if (rc == -@as(isize, @intCast(@intFromEnum(E.NOSYS)))) {
            _ = linux.syscall4(.futex, @intFromPtr(addr), FUTEX_WAIT, val_u, 0);
        }
    }
    if (waiters) |w| {
        _ = @atomicRmw(c_int, @constCast(@volatileCast(w)), .Add, -1, .seq_cst);
    }
}

fn vm_lock_fn2() callconv(.c) void {
    _ = @atomicRmw(c_int, &vmlock_storage[0], .Add, 1, .seq_cst);
}

fn vm_unlock_fn2() callconv(.c) void {
    if (@atomicRmw(c_int, &vmlock_storage[0], .Add, -1, .seq_cst) == 1 and vmlock_storage[1] != 0)
        wake(@ptrCast(&vmlock_storage[0]), -1, 1);
}

fn set_thread_area_fn(p: usize) callconv(.c) c_int {
    if (@hasField(linux.SYS, "set_thread_area")) {
        return @truncate(-@as(isize, @bitCast(linux.syscall1(.set_thread_area, p))));
    } else {
        return -eint(.NOSYS);
    }
}

// The real cancellation-point logic is in arch-specific .s files
// (via __syscall_cp_asm). This is the C fallback: just a regular syscall.
fn syscall_cp_fn(nr: usize, u: usize, v: usize, w: usize, x: usize, y: usize, z: usize) callconv(.c) isize {
    const __syscall_cp_c_ext = @extern(*const fn (usize, usize, usize, usize, usize, usize, usize) callconv(.c) isize, .{ .name = "__syscall_cp_c" });
    return __syscall_cp_c_ext(nr, u, v, w, x, y, z);
}

// __testcancel is a weak symbol: if cancellation is not linked, it's a no-op.
// The real implementation is in pthread_cancel.c.
fn testcancel_fn() callconv(.c) void {}

fn do_cleanup_push_fn(_: *anyopaque) callconv(.c) void {}

fn do_cleanup_pop_fn(_: *anyopaque) callconv(.c) void {}

fn cleanup_push_fn(cb: *anyopaque, f: ?*const anyopaque, x: ?*anyopaque) callconv(.c) void {
    const cb_p: [*]usize = @ptrCast(@alignCast(cb));
    cb_p[0] = @intFromPtr(f); // __f
    cb_p[1] = @intFromPtr(x); // __x
    do_cleanup_push_fn(cb);
}

fn cleanup_pop_fn(cb: *anyopaque, run: c_int) callconv(.c) void {
    do_cleanup_pop_fn(cb);
    if (run != 0) {
        const cb_p: [*]usize = @ptrCast(@alignCast(cb));
        const f: *const fn (?*anyopaque) callconv(.c) void = @ptrFromInt(cb_p[0]);
        f(@ptrFromInt(cb_p[1]));
    }
}

fn pthread_once_fn(control: *volatile c_int, init: *const fn () callconv(.c) void) callconv(.c) c_int {
    if (control.* == 2) {
        _ = @atomicLoad(c_int, control, .seq_cst);
        return 0;
    }
    return pthread_once_full(@constCast(@volatileCast(control)), init);
}
