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
