const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;

const linux = std.os.linux;
const E = linux.E;

comptime {
    if (builtin.target.isMuslLibC()) {
        if (builtin.link_libc) {
            // Mutex attributes
            symbol(&pthread_mutexattr_setprotocol_fn, "pthread_mutexattr_setprotocol");
            symbol(&pthread_mutexattr_setrobust_fn, "pthread_mutexattr_setrobust");

            // Mutex destroy
            symbol(&pthread_mutex_destroy_fn, "pthread_mutex_destroy");

            // PTC lock (used by pthread_attr_init / pthread_setattr_default_np)
            symbol(&inhibit_ptc_fn, "__inhibit_ptc");
            symbol(&acquire_ptc_fn, "__acquire_ptc");
            symbol(&release_ptc_fn, "__release_ptc");

            // pthread_once
            symbol(&__pthread_once_fn, "__pthread_once");
            symbol(&__pthread_once_fn, "pthread_once");
        }
    }
}

fn eint(e: E) c_int {
    return @intCast(@intFromEnum(e));
}

// --- Futex helper (static inline __wake in musl) ---

fn wake(addr: *anyopaque, cnt: c_int, priv_val: c_int) void {
    const FUTEX_WAKE: usize = 1;
    const FUTEX_PRIVATE: usize = 128;
    const p: usize = if (priv_val != 0) FUTEX_PRIVATE else 0;
    const n: usize = if (cnt < 0) @as(usize, @intCast(std.math.maxInt(c_int))) else @as(usize, @intCast(cnt));
    _ = linux.syscall3(.futex, @intFromPtr(addr), FUTEX_WAKE | p, n);
}

// --- Cancellation cleanup struct (musl's struct __ptcb) ---

const PtCb = extern struct {
    f: ?*const fn (?*anyopaque) callconv(.c) void,
    x: ?*anyopaque,
    next: ?*PtCb,
};

// --- pthread_mutexattr_setprotocol (pthread_mutexattr_setprotocol.c) ---

var check_pi_result: c_int = -1;

fn pthread_mutexattr_setprotocol_fn(a: *c_uint, protocol: c_int) callconv(.c) c_int {
    const FUTEX_LOCK_PI: usize = 6;
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

// --- pthread_mutexattr_setrobust (pthread_mutexattr_setrobust.c) ---

var check_robust_result: c_int = -1;

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

// --- pthread_mutex_destroy (pthread_mutex_destroy.c) ---

fn pthread_mutex_destroy_fn(mutex: *anyopaque) callconv(.c) c_int {
    // _m_type is the first int in pthread_mutex_t
    const m_type: c_int = @as(*const c_int, @ptrCast(@alignCast(mutex))).*;
    if (m_type > 128) {
        const __vm_wait = @extern(*const fn () callconv(.c) void, .{ .name = "__vm_wait" });
        __vm_wait();
    }
    return 0;
}

// --- lock_ptc (lock_ptc.c) ---

const rwlock_int_count: usize = if (@sizeOf(c_long) == 8) 14 else 8;
var ptc_lock: [rwlock_int_count]c_int = [_]c_int{0} ** rwlock_int_count;

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

// --- pthread_once (pthread_once.c) ---

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
