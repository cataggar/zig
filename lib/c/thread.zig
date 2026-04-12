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
const linux = std.os.linux;
const E = linux.E;
const arch = builtin.target.cpu.arch;

comptime {
    if (builtin.target.isMuslLibC()) {
        // Thread identity
        symbol(&pthread_self_fn, "pthread_self");
        symbol(&pthread_self_fn, "thrd_current");

        // Thread-specific data
        symbol(&pthread_getspecific_fn, "pthread_getspecific");
        symbol(&pthread_getspecific_fn, "tss_get");
        symbol(&pthread_setspecific_fn, "pthread_setspecific");

        // Cancellation
        symbol(&pthread_setcancelstate_fn, "__pthread_setcancelstate");
        symbol(&pthread_setcancelstate_fn, "pthread_setcancelstate");
        symbol(&pthread_setcanceltype_fn, "pthread_setcanceltype");
        symbol(&pthread_testcancel_fn, "__pthread_testcancel");
        symbol(&pthread_testcancel_fn, "pthread_testcancel");

        // Semaphore operations
        symbol(&sem_trywait_fn, "sem_trywait");
        symbol(&sem_post_fn, "sem_post");

        // Functions that depend on other musl C symbols via @extern
        if (builtin.link_libc) {
            symbol(&pthread_detach_fn, "pthread_detach");
            symbol(&pthread_detach_fn, "thrd_detach");
            symbol(&sem_wait_fn, "sem_wait");
            symbol(&sem_unlink_fn, "sem_unlink");
        if (builtin.link_libc) {
            // Cleanup handler management
            symbol(&do_cleanup_push_default, "__do_cleanup_push");
            symbol(&do_cleanup_pop_default, "__do_cleanup_pop");
            symbol(&_pthread_cleanup_push_fn, "_pthread_cleanup_push");
            symbol(&_pthread_cleanup_pop_fn, "_pthread_cleanup_pop");

            // Scheduling parameters
            symbol(&pthread_getschedparam_fn, "pthread_getschedparam");
            symbol(&pthread_setschedparam_fn, "pthread_setschedparam");

            // Thread name (GNU extensions)
            symbol(&pthread_getname_np_fn, "pthread_getname_np");
            symbol(&pthread_setname_np_fn, "pthread_setname_np");

            // Timed semaphore wait
            symbol(&sem_timedwait_fn, "sem_timedwait");
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
// --- Musl struct pthread field offsets ---
// Computed from the musl struct pthread layout in pthread_impl.h.
// The layout varies by architecture based on TLS model and pointer size.
// --- Musl struct pthread field offsets ---
// Computed from the musl struct pthread layout in pthread_impl.h.

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
const ptr_size = @sizeOf(usize);
const part1_size: usize = if (tls_above_tp) 4 * ptr_size else 6 * ptr_size;
const map_base_off: usize = if (ptr_size == 8) 24 else 20;

const off_tid = part1_size;
const off_killlock = part1_size + map_base_off + 11 * ptr_size + 8 + ptr_size;

const SEM_VALUE_MAX: c_int = 0x7fffffff;
const CLOCK_REALTIME: c_int = 0;

const sem_val_len = 4 * @sizeOf(c_long) / @sizeOf(c_int);
const sem_impl = extern struct {
    __val: [sem_val_len]c_int,
};

/// Convert a Linux errno enum to a positive c_int for POSIX thread functions.
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

// --- Thread identity ---

fn pthread_self_fn() callconv(.c) std.c.pthread_t {
    return @ptrFromInt(pthread_self_ptr());
}

// --- Thread-specific data ---

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
// --- Cancellation ---

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

// --- Thread detach ---

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

// --- Semaphore operations ---

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

// --- Futex helper ---

fn futex_wake(addr: *const c_int, cnt: c_int, priv: c_int) void {
    const FUTEX_WAKE: usize = 1;
    const FUTEX_PRIVATE: usize = 128;
    const p: usize = if (priv != 0) FUTEX_PRIVATE else 0;
    const max_int: c_int = std.math.maxInt(c_int);
    const c: usize = @intCast(if (cnt < 0) max_int else cnt);
    const rc: isize = @bitCast(std.os.linux.syscall4(.futex, @intFromPtr(addr), FUTEX_WAKE | p, c, 0));
    if (rc == -@as(isize, @intFromEnum(E.NOSYS))) {
        _ = std.os.linux.syscall4(.futex, @intFromPtr(addr), FUTEX_WAKE, c, 0);
    }
/// Musl's struct __ptcb from pthread.h.
const PtCb = extern struct {
    f: ?*const fn (?*anyopaque) callconv(.c) void,
    x: ?*anyopaque,
    next: ?*PtCb,
};

fn eint(e: E) c_int {
    return @intCast(@intFromEnum(e));
}

// --- Cleanup handler management (pthread_cleanup_push.c) ---

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

// --- Scheduling parameters (pthread_getschedparam.c / pthread_setschedparam.c) ---

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

// --- Thread name (pthread_getname_np.c / pthread_setname_np.c) ---

const PR_SET_NAME: usize = 15;
const PR_GET_NAME: usize = 16;
const AT_FDCWD: usize = @bitCast(@as(isize, -100));
const O_CLOEXEC: usize = 0o2000000;

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

// --- Timed semaphore wait (sem_timedwait.c) ---

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
