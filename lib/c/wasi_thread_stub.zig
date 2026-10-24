//! WASI thread stubs for single-threaded WASI targets.
//! Minimal pthread implementations that return no-op/error codes or trap
//! when actual threading would be required.

const std = @import("std");
const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

comptime {
    if (!builtin.target.isWasiLibC()) @compileError("wasi_thread_stub is only for WASI");
}

// musl pthread types matching pthread_impl.h and bits/alltypes.h
const PthreadMutex = extern struct { __i: [if (@sizeOf(c_long) == 8) 10 else 6]c_int };
const PthreadRwlock = extern struct { __i: [if (@sizeOf(c_long) == 8) 14 else 8]c_int };
const PthreadBarrier = extern struct { __i: [if (@sizeOf(c_long) == 8) 8 else 5]c_int };

const PthreadAttr = extern struct {
    _a_stacksize: usize = 0,
    _a_guardsize: usize = 0,
    _a_stackaddr: usize = 0,
    _a_detach: c_int = 0,
    _a_sched: c_int = 0,
    _a_policy: c_int = 0,
    _a_prio: c_int = 0,
    _padding: [attr_padding]u8 = @splat(0),

    const attr_total = if (@sizeOf(c_long) == 8) @as(usize, 56) else 36;
    const attr_padding = attr_total - 3 * @sizeOf(usize) - 4 * @sizeOf(c_int);
};

const PthreadMutexattr = extern struct { __attr: c_uint = 0 };
const PthreadCondattr = extern struct { __attr: c_uint = 0 };
const PthreadBarrierattr = extern struct { __attr: c_uint = 0 };
const PthreadRwlockattr = extern struct { __attr: [2]c_uint = .{ 0, 0 } };
const SchedParam = extern struct { sched_priority: c_int };

const Ptcb = extern struct {
    __f: ?*const fn (?*anyopaque) callconv(.c) void,
    __x: ?*anyopaque,
    __next: ?*Ptcb,
};

/// WASI `struct __pthread` layout from `wasi/libc-top-half/musl/src/internal/pthread_impl.h`.
const Pthread = extern struct {
    self: ?*Pthread = null,
    prev: ?*Pthread = null,
    next: ?*Pthread = null,
    sysinfo: usize = 0,
    canary: usize = 0,

    tid: c_int = 0,
    errno_val: c_int = 0,
    detach_state: c_int = 0,
    cancel: c_int = 0,
    canceldisable: u8 = 0,
    cancelasync: u8 = 0,
    flags: u8 = 0, // bit 0: tsd_used, bit 1: dlerror_flag
    map_base: ?[*]u8 = null,
    map_size: usize = 0,
    stack: ?*anyopaque = null,
    stack_size: usize = 0,
    guard_size: usize = 0,
    result: ?*anyopaque = null,
    cancelbuf: ?*Ptcb = null,
    tsd: ?[*]?*anyopaque = null,
    robust_list_head: ?*anyopaque = null,
    robust_list_off: c_long = 0,
    robust_list_pending: ?*anyopaque = null,
    h_errno_val: c_int = 0,
    timer_id: c_int = 0,
    locale: ?*anyopaque = null,
    killlock: [1]c_int = .{0},
    dlerror_buf: ?[*]u8 = null,
    stdio_locks: ?*anyopaque = null,
};

const ClockId = extern struct {
    id: u32,
};

// WASI errno values (from __errno_values.h)
const EAGAIN: c_int = 6;
const EBUSY: c_int = 10;
const EDEADLK: c_int = 16;
const EINTR: c_int = 27;
const EINVAL: c_int = 28;
const ENOTSUP: c_int = 58;
const EPERM: c_int = 63;
const ETIMEDOUT: c_int = 73;

const PTHREAD_MUTEX_RECURSIVE: c_int = 1;
const PTHREAD_BARRIER_SERIAL_THREAD: c_int = -1;
const PTHREAD_CREATE_DETACHED: c_int = 1;
const PTHREAD_PRIO_NONE: c_int = 0;
const PTHREAD_PRIO_INHERIT: c_int = 1;
const PTHREAD_PRIO_PROTECT: c_int = 2;
const PTHREAD_SCOPE_SYSTEM: c_int = 0;

const PTHREAD_KEYS_MAX: usize = 128;
const PTHREAD_DESTRUCTOR_ITERATIONS: usize = 4;
const PTHREAD_STACK_MIN: usize = 2048;
const DEFAULT_STACK_SIZE: c_uint = 131072;
const DEFAULT_GUARD_SIZE: c_uint = 0;

const TIMER_ABSTIME: c_int = 1;

const INT_MAX: c_uint = @bitCast(@as(c_int, std.math.maxInt(c_int)));
const INT_MIN_UINT: c_uint = @bitCast(@as(c_int, std.math.minInt(c_int)));

extern const _CLOCK_REALTIME: ClockId;
extern const _CLOCK_MONOTONIC: ClockId;
extern "c" fn clock_nanosleep(clock_id: *const ClockId, flags: c_int, request: ?*const anyopaque, remain: ?*anyopaque) c_int;

// --- Global state ---

var __default_stacksize: c_uint = DEFAULT_STACK_SIZE;
var __default_guardsize: c_uint = DEFAULT_GUARD_SIZE;

var __pthread_tsd_size: usize = @sizeOf(?*anyopaque) * PTHREAD_KEYS_MAX;
var __pthread_tsd_main: [PTHREAD_KEYS_MAX]?*anyopaque = @splat(null);
var __wasilibc_pthread_self: Pthread = .{};

const DtorFn = *const fn (?*anyopaque) callconv(.c) void;
var keys: [PTHREAD_KEYS_MAX]?DtorFn = @splat(null);
var key_lock: PthreadRwlock = std.mem.zeroes(PthreadRwlock);
var next_key: c_uint = 0;

fn nodtor(arg: ?*anyopaque) callconv(.c) void {
    _ = arg;
}

// --- Attributes (pthread_attr_*) ---

fn pthread_attr_init(a: *PthreadAttr) callconv(.c) c_int {
    a.* = .{
        ._a_stacksize = __default_stacksize,
        ._a_guardsize = __default_guardsize,
    };
    return 0;
}

fn pthread_attr_destroy(a: ?*PthreadAttr) callconv(.c) c_int {
    _ = a;
    return 0;
}

fn pthread_attr_getdetachstate(a: *const PthreadAttr, state: *c_int) callconv(.c) c_int {
    state.* = a._a_detach;
    return 0;
}

fn pthread_attr_setdetachstate(a: *PthreadAttr, state: c_int) callconv(.c) c_int {
    if (@as(c_uint, @bitCast(state)) > 1) return EINVAL;
    a._a_detach = state;
    return 0;
}

fn pthread_attr_getguardsize(a: *const PthreadAttr, size: *usize) callconv(.c) c_int {
    size.* = a._a_guardsize;
    return 0;
}

fn pthread_attr_setguardsize(a: *PthreadAttr, size: usize) callconv(.c) c_int {
    // WASI doesn't have memory protection required for stack guards.
    if (size > 0) return EINVAL;
    a._a_guardsize = size;
    return 0;
}

fn pthread_attr_getinheritsched(a: *const PthreadAttr, inherit: *c_int) callconv(.c) c_int {
    inherit.* = a._a_sched;
    return 0;
}

fn pthread_attr_getschedparam(a: *const PthreadAttr, param: *SchedParam) callconv(.c) c_int {
    _ = a;
    param.sched_priority = 0;
    return 0;
}

fn pthread_attr_setschedparam(a: *PthreadAttr, param: *const SchedParam) callconv(.c) c_int {
    _ = a;
    if (param.sched_priority != 0) return ENOTSUP;
    return 0;
}

fn pthread_attr_getschedpolicy(a: *const PthreadAttr, policy: *c_int) callconv(.c) c_int {
    policy.* = a._a_policy;
    return 0;
}

fn pthread_attr_getscope(a: *const PthreadAttr, scope: *c_int) callconv(.c) c_int {
    _ = a;
    scope.* = PTHREAD_SCOPE_SYSTEM;
    return 0;
}

fn pthread_attr_getstack(a: *const PthreadAttr, addr: *?*anyopaque, size: *usize) callconv(.c) c_int {
    if (a._a_stackaddr == 0) return EINVAL;
    size.* = a._a_stacksize;
    addr.* = @ptrFromInt(a._a_stackaddr -% size.*);
    return 0;
}

fn pthread_attr_setstack(a: *PthreadAttr, addr: ?*anyopaque, size: usize) callconv(.c) c_int {
    if (size -% PTHREAD_STACK_MIN > std.math.maxInt(usize) / 4) return EINVAL;
    a._a_stackaddr = @intFromPtr(addr) +% size;
    a._a_stacksize = size;
    return 0;
}

fn pthread_attr_getstacksize(a: *const PthreadAttr, size: *usize) callconv(.c) c_int {
    size.* = a._a_stacksize;
    return 0;
}

fn pthread_attr_setstacksize(a: *PthreadAttr, size: usize) callconv(.c) c_int {
    if (size -% PTHREAD_STACK_MIN > std.math.maxInt(usize) / 4) return EINVAL;
    a._a_stackaddr = 0;
    a._a_stacksize = size;
    return 0;
}

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

fn pthread_barrierattr_init(a: *PthreadBarrierattr) callconv(.c) c_int {
    a.* = .{};
    return 0;
}

fn pthread_barrierattr_destroy(a: ?*PthreadBarrierattr) callconv(.c) c_int {
    _ = a;
    return 0;
}

fn pthread_barrierattr_getpshared(a: *const PthreadBarrierattr, pshared: *c_int) callconv(.c) c_int {
    pshared.* = @intFromBool(a.__attr != 0);
    return 0;
}

fn pthread_barrierattr_setpshared(a: *PthreadBarrierattr, pshared: c_int) callconv(.c) c_int {
    if (@as(c_uint, @bitCast(pshared)) > 1) return EINVAL;
    a.__attr = if (pshared != 0) INT_MIN_UINT else 0;
    return 0;
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
    const ret = clock_nanosleep(&_CLOCK_REALTIME, TIMER_ABSTIME, ts, null);
    if (ret == 0) return ETIMEDOUT;
    if (ret != EINTR) return ret;
    return 0;
}

fn pthread_cond_wait(cv: ?*anyopaque, m: ?*anyopaque) callconv(.c) c_int {
    // No other thread can signal, so this is an immediate deadlock.
    _ = .{ cv, m };
    @trap();
}

fn pthread_condattr_init(a: *PthreadCondattr) callconv(.c) c_int {
    a.* = .{};
    return 0;
}

fn pthread_condattr_destroy(a: ?*PthreadCondattr) callconv(.c) c_int {
    _ = a;
    return 0;
}

fn pthread_condattr_getclock(a: *const PthreadCondattr, clk: **const ClockId) callconv(.c) c_int {
    if ((a.__attr & 0x7fffffff) == 0) clk.* = &_CLOCK_REALTIME;
    if ((a.__attr & 0x7fffffff) == 1) clk.* = &_CLOCK_MONOTONIC;
    return 0;
}

fn pthread_condattr_setclock(a: *PthreadCondattr, clk: *const ClockId) callconv(.c) c_int {
    if (clk.id -% 2 < 2) return EINVAL;
    a.__attr &= 0x80000000;
    a.__attr |= clk.id;
    return 0;
}

fn pthread_condattr_getpshared(a: *const PthreadCondattr, pshared: *c_int) callconv(.c) c_int {
    pshared.* = @intCast(a.__attr >> 31);
    return 0;
}

fn pthread_condattr_setpshared(a: *PthreadCondattr, pshared: c_int) callconv(.c) c_int {
    const pshared_u: c_uint = @bitCast(pshared);
    if (pshared_u > 1) return EINVAL;
    a.__attr &= 0x7fffffff;
    a.__attr |= pshared_u << 31;
    return 0;
}

// --- Thread lifecycle & cancellation ---

fn dummy() callconv(.c) void {}

fn dummyPtcb(cb: ?*Ptcb) callconv(.c) void {
    _ = cb;
}

fn _pthread_cleanup_push(cb: *Ptcb, f: ?*const fn (?*anyopaque) callconv(.c) void, x: ?*anyopaque) callconv(.c) void {
    cb.__f = f;
    cb.__x = x;
}

fn _pthread_cleanup_pop(cb: *Ptcb, run: c_int) callconv(.c) void {
    if (run != 0) {
        if (cb.__f) |f| f(cb.__x);
    }
}

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
    a.* = .{
        ._a_detach = PTHREAD_CREATE_DETACHED,
        ._a_guardsize = 0,
    };
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

fn pthread_self() callconv(.c) *Pthread {
    return &__wasilibc_pthread_self;
}

fn __init_tp(p: ?*anyopaque) callconv(.c) c_int {
    _ = p;
    return 0;
}

fn pthread_equal(a: ?*anyopaque, b: ?*anyopaque) callconv(.c) c_int {
    return @intFromBool(a == b);
}

fn pthread_setcancelstate(new: c_int, old: ?*c_int) callconv(.c) c_int {
    if (@as(c_uint, @bitCast(new)) > 2) return EINVAL;
    const self = &__wasilibc_pthread_self;
    if (old) |o| o.* = self.canceldisable;
    self.canceldisable = @intCast(@as(c_uint, @bitCast(new)));
    return 0;
}

fn pthread_setcanceltype(new: c_int, old: ?*c_int) callconv(.c) c_int {
    const self = &__wasilibc_pthread_self;
    if (@as(c_uint, @bitCast(new)) > 1) return EINVAL;
    if (old) |o| o.* = self.cancelasync;
    self.cancelasync = @intCast(@as(c_uint, @bitCast(new)));
    return 0;
}

fn pthread_cancel(t: ?*anyopaque) callconv(.c) c_int {
    _ = t;
    return ENOTSUP;
}

fn thrd_sleep(req: ?*const anyopaque, rem: ?*anyopaque) callconv(.c) c_int {
    const ret = -clock_nanosleep(&_CLOCK_REALTIME, 0, req, rem);
    return switch (ret) {
        0 => 0,
        -EINTR => -1, // value specified by C11
        else => -2,
    };
}

// --- Thread-specific data (TSD) ---

fn __pthread_key_create(k: *c_uint, dtor_arg: ?DtorFn) callconv(.c) c_int {
    const self = &__wasilibc_pthread_self;
    if (self.tsd == null) self.tsd = &__pthread_tsd_main;

    const dtor: DtorFn = dtor_arg orelse &nodtor;

    _ = pthread_rwlock_wrlock(&key_lock);
    var j: c_uint = next_key;
    while (true) {
        if (keys[j] == null) {
            next_key = j;
            k.* = j;
            keys[j] = dtor;
            _ = pthread_rwlock_unlock(&key_lock);
            return 0;
        }
        j = (j + 1) % @as(c_uint, PTHREAD_KEYS_MAX);
        if (j == next_key) break;
    }
    _ = pthread_rwlock_unlock(&key_lock);
    return EAGAIN;
}

fn __pthread_key_delete(k: c_uint) callconv(.c) c_int {
    const self = &__wasilibc_pthread_self;
    _ = pthread_rwlock_wrlock(&key_lock);

    var td: ?*Pthread = self;
    while (td) |cur| {
        if (cur.tsd) |tsd| tsd[k] = null;
        if (cur.next == null or cur.next == self) break;
        td = cur.next;
    }

    keys[k] = null;
    _ = pthread_rwlock_unlock(&key_lock);
    return 0;
}

fn __pthread_tsd_run_dtors() callconv(.c) void {
    const self = &__wasilibc_pthread_self;
    var j: usize = 0;
    while ((self.flags & 1) != 0 and j < PTHREAD_DESTRUCTOR_ITERATIONS) : (j += 1) {
        _ = pthread_rwlock_rdlock(&key_lock);
        self.flags &= ~@as(u8, 1);
        for (0..PTHREAD_KEYS_MAX) |i| {
            const tsd = self.tsd orelse break;
            const val = tsd[i];
            const dtor = keys[i];
            tsd[i] = null;
            if (val != null and dtor != null and dtor != @as(?DtorFn, &nodtor)) {
                _ = pthread_rwlock_unlock(&key_lock);
                dtor.?(val);
                _ = pthread_rwlock_rdlock(&key_lock);
            }
        }
        _ = pthread_rwlock_unlock(&key_lock);
    }
}

fn pthread_getspecific(k: c_uint) callconv(.c) ?*anyopaque {
    const self = &__wasilibc_pthread_self;
    const tsd = self.tsd orelse return null;
    return tsd[k];
}

fn pthread_setspecific(k: c_uint, x: ?*const anyopaque) callconv(.c) c_int {
    const self = &__wasilibc_pthread_self;
    const tsd = self.tsd orelse blk: {
        self.tsd = &__pthread_tsd_main;
        break :blk @as([*]?*anyopaque, &__pthread_tsd_main);
    };
    const mut_x: ?*anyopaque = @constCast(x);
    if (tsd[k] != mut_x) {
        tsd[k] = mut_x;
        self.flags |= 1; // tsd_used = 1
    }
    return 0;
}

// --- Mutex ---

fn pthread_mutex_init(m: *PthreadMutex, a: ?*const PthreadMutexattr) callconv(.c) c_int {
    m.* = std.mem.zeroes(PthreadMutex);
    if (a) |attr| m.__i[0] = @bitCast(attr.__attr); // _m_type
    return 0;
}

fn pthread_mutex_destroy(m: *PthreadMutex) callconv(.c) c_int {
    if (m.__i[0] > 128) return EINVAL; // _m_type
    return 0;
}

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

fn pthread_mutexattr_init(a: *PthreadMutexattr) callconv(.c) c_int {
    a.* = .{};
    return 0;
}

fn pthread_mutexattr_destroy(a: ?*PthreadMutexattr) callconv(.c) c_int {
    _ = a;
    return 0;
}

fn pthread_mutexattr_getprotocol(a: *const PthreadMutexattr, protocol: *c_int) callconv(.c) c_int {
    protocol.* = @intCast((a.__attr / 8) % 2);
    return 0;
}

fn pthread_mutexattr_setprotocol(a: *PthreadMutexattr, protocol: c_int) callconv(.c) c_int {
    return switch (protocol) {
        PTHREAD_PRIO_NONE => {
            a.__attr &= ~@as(c_uint, 8);
            return 0;
        },
        PTHREAD_PRIO_INHERIT, PTHREAD_PRIO_PROTECT => ENOTSUP,
        else => EINVAL,
    };
}

fn pthread_mutexattr_getpshared(a: *const PthreadMutexattr, pshared: *c_int) callconv(.c) c_int {
    pshared.* = @intCast((a.__attr / 128) % 2);
    return 0;
}

fn pthread_mutexattr_setpshared(a: *PthreadMutexattr, pshared: c_int) callconv(.c) c_int {
    const pshared_u: c_uint = @bitCast(pshared);
    if (pshared_u > 1) return EINVAL;
    a.__attr &= ~@as(c_uint, 128);
    a.__attr |= pshared_u << 7;
    return 0;
}

fn pthread_mutexattr_getrobust(a: *const PthreadMutexattr, robust: *c_int) callconv(.c) c_int {
    robust.* = @intCast((a.__attr / 4) % 2);
    return 0;
}

fn pthread_mutexattr_setrobust(a: *PthreadMutexattr, robust: c_int) callconv(.c) c_int {
    _ = a;
    if (robust != 0) return EINVAL;
    return 0;
}

fn pthread_mutexattr_gettype(a: *const PthreadMutexattr, @"type": *c_int) callconv(.c) c_int {
    @"type".* = @intCast(a.__attr & 3);
    return 0;
}

fn pthread_mutexattr_settype(a: *PthreadMutexattr, @"type": c_int) callconv(.c) c_int {
    const type_u: c_uint = @bitCast(@"type");
    if (type_u > 2) return EINVAL;
    a.__attr = (a.__attr & ~@as(c_uint, 3)) | type_u;
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

fn pthread_rwlock_init(rw: *PthreadRwlock, a: ?*const PthreadRwlockattr) callconv(.c) c_int {
    rw.* = std.mem.zeroes(PthreadRwlock);
    if (a) |attr| rw.__i[2] = @bitCast(attr.__attr[0] *% 128); // _rw_shared
    return 0;
}

fn pthread_rwlock_destroy(rw: ?*PthreadRwlock) callconv(.c) c_int {
    _ = rw;
    return 0;
}

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

fn pthread_rwlockattr_init(a: *PthreadRwlockattr) callconv(.c) c_int {
    a.* = .{};
    return 0;
}

fn pthread_rwlockattr_destroy(a: ?*PthreadRwlockattr) callconv(.c) c_int {
    _ = a;
    return 0;
}

fn pthread_rwlockattr_getpshared(a: *const PthreadRwlockattr, pshared: *c_int) callconv(.c) c_int {
    pshared.* = @bitCast(a.__attr[0]);
    return 0;
}

fn pthread_rwlockattr_setpshared(a: *PthreadRwlockattr, pshared: c_int) callconv(.c) c_int {
    const pshared_u: c_uint = @bitCast(pshared);
    if (pshared_u > 1) return EINVAL;
    a.__attr[0] = pshared_u;
    return 0;
}

// --- Symbol exports ---

comptime {
    // Global variables
    symbol(&__default_stacksize, "__default_stacksize");
    symbol(&__default_guardsize, "__default_guardsize");
    symbol(&__pthread_tsd_size, "__pthread_tsd_size");
    symbol(&__pthread_tsd_main, "__pthread_tsd_main");
    symbol(&__wasilibc_pthread_self, "__wasilibc_pthread_self");

    // Attributes
    symbol(&pthread_attr_init, "pthread_attr_init");
    symbol(&pthread_attr_destroy, "pthread_attr_destroy");
    symbol(&pthread_attr_getdetachstate, "pthread_attr_getdetachstate");
    symbol(&pthread_attr_setdetachstate, "pthread_attr_setdetachstate");
    symbol(&pthread_attr_getguardsize, "pthread_attr_getguardsize");
    symbol(&pthread_attr_setguardsize, "pthread_attr_setguardsize");
    symbol(&pthread_attr_getinheritsched, "pthread_attr_getinheritsched");
    symbol(&pthread_attr_getschedparam, "pthread_attr_getschedparam");
    symbol(&pthread_attr_setschedparam, "pthread_attr_setschedparam");
    symbol(&pthread_attr_getschedpolicy, "pthread_attr_getschedpolicy");
    symbol(&pthread_attr_getscope, "pthread_attr_getscope");
    symbol(&pthread_attr_getstack, "pthread_attr_getstack");
    symbol(&pthread_attr_setstack, "pthread_attr_setstack");
    symbol(&pthread_attr_getstacksize, "pthread_attr_getstacksize");
    symbol(&pthread_attr_setstacksize, "pthread_attr_setstacksize");

    // Barrier
    symbol(&pthread_barrier_destroy, "pthread_barrier_destroy");
    symbol(&pthread_barrier_init, "pthread_barrier_init");
    symbol(&pthread_barrier_wait, "pthread_barrier_wait");
    symbol(&pthread_barrierattr_init, "pthread_barrierattr_init");
    symbol(&pthread_barrierattr_destroy, "pthread_barrierattr_destroy");
    symbol(&pthread_barrierattr_getpshared, "pthread_barrierattr_getpshared");
    symbol(&pthread_barrierattr_setpshared, "pthread_barrierattr_setpshared");

    // Condition variable
    symbol(&pthread_cond_broadcast, "pthread_cond_broadcast");
    symbol(&pthread_cond_destroy, "pthread_cond_destroy");
    symbol(&pthread_cond_init, "pthread_cond_init");
    symbol(&pthread_cond_signal, "pthread_cond_signal");
    symbol(&pthread_cond_timedwait, "__pthread_cond_timedwait");
    symbol(&pthread_cond_timedwait, "pthread_cond_timedwait");
    symbol(&pthread_cond_wait, "pthread_cond_wait");
    symbol(&pthread_condattr_init, "pthread_condattr_init");
    symbol(&pthread_condattr_destroy, "pthread_condattr_destroy");
    symbol(&pthread_condattr_getclock, "pthread_condattr_getclock");
    symbol(&pthread_condattr_setclock, "pthread_condattr_setclock");
    symbol(&pthread_condattr_getpshared, "pthread_condattr_getpshared");
    symbol(&pthread_condattr_setpshared, "pthread_condattr_setpshared");

    // Thread lifecycle & cancellation
    symbol(&dummy, "__acquire_ptc");
    symbol(&dummy, "__release_ptc");
    symbol(&dummy, "__tl_lock");
    symbol(&dummy, "__tl_unlock");
    symbol(&dummyPtcb, "__do_cleanup_push");
    symbol(&dummyPtcb, "__do_cleanup_pop");
    symbol(&_pthread_cleanup_push, "_pthread_cleanup_push");
    symbol(&_pthread_cleanup_pop, "_pthread_cleanup_pop");
    symbol(&pthread_create, "__pthread_create");
    symbol(&pthread_create, "pthread_create");
    symbol(&pthread_detach, "__pthread_detach");
    symbol(&pthread_detach, "pthread_detach");
    symbol(&pthread_detach, "thrd_detach");
    symbol(&pthread_getattr_np, "pthread_getattr_np");
    symbol(&pthread_tryjoin_np, "__pthread_tryjoin_np");
    symbol(&pthread_tryjoin_np, "pthread_tryjoin_np");
    symbol(&pthread_timedjoin_np, "__pthread_timedjoin_np");
    symbol(&pthread_timedjoin_np, "pthread_timedjoin_np");
    symbol(&pthread_join, "__pthread_join");
    symbol(&pthread_join, "pthread_join");
    symbol(&pthread_self, "__pthread_self");
    symbol(&pthread_self, "pthread_self");
    symbol(&pthread_self, "thrd_current");
    symbol(&__init_tp, "__init_tp");
    symbol(&pthread_equal, "pthread_equal");
    symbol(&pthread_equal, "thrd_equal");
    symbol(&pthread_setcancelstate, "__pthread_setcancelstate");
    symbol(&pthread_setcancelstate, "pthread_setcancelstate");
    symbol(&pthread_setcanceltype, "pthread_setcanceltype");
    symbol(&dummy, "__testcancel");
    symbol(&dummy, "__pthread_testcancel");
    symbol(&dummy, "pthread_testcancel");
    symbol(&dummy, "_pthread_testcancel");
    symbol(&pthread_cancel, "pthread_cancel");
    symbol(&thrd_sleep, "thrd_sleep");

    // Thread-specific data
    symbol(&__pthread_key_create, "__pthread_key_create");
    symbol(&__pthread_key_create, "pthread_key_create");
    symbol(&__pthread_key_delete, "__pthread_key_delete");
    symbol(&__pthread_key_delete, "pthread_key_delete");
    symbol(&__pthread_tsd_run_dtors, "__pthread_tsd_run_dtors");
    symbol(&pthread_getspecific, "pthread_getspecific");
    symbol(&pthread_getspecific, "tss_get");
    symbol(&pthread_setspecific, "pthread_setspecific");
    symbol(&pthread_setspecific, "tss_set");

    // Mutex
    symbol(&pthread_mutex_init, "pthread_mutex_init");
    symbol(&pthread_mutex_destroy, "pthread_mutex_destroy");
    symbol(&pthread_mutex_consistent, "pthread_mutex_consistent");
    symbol(&pthread_mutex_getprioceiling, "pthread_mutex_getprioceiling");
    symbol(&pthread_mutex_lock, "__pthread_mutex_lock");
    symbol(&pthread_mutex_lock, "pthread_mutex_lock");
    symbol(&pthread_mutex_timedlock, "__pthread_mutex_timedlock");
    symbol(&pthread_mutex_timedlock, "pthread_mutex_timedlock");
    symbol(&pthread_mutex_trylock, "__pthread_mutex_trylock");
    symbol(&pthread_mutex_trylock, "pthread_mutex_trylock");
    symbol(&pthread_mutex_unlock, "__pthread_mutex_unlock");
    symbol(&pthread_mutex_unlock, "pthread_mutex_unlock");
    symbol(&pthread_mutexattr_init, "pthread_mutexattr_init");
    symbol(&pthread_mutexattr_destroy, "pthread_mutexattr_destroy");
    symbol(&pthread_mutexattr_getprotocol, "pthread_mutexattr_getprotocol");
    symbol(&pthread_mutexattr_setprotocol, "pthread_mutexattr_setprotocol");
    symbol(&pthread_mutexattr_getpshared, "pthread_mutexattr_getpshared");
    symbol(&pthread_mutexattr_setpshared, "pthread_mutexattr_setpshared");
    symbol(&pthread_mutexattr_getrobust, "pthread_mutexattr_getrobust");
    symbol(&pthread_mutexattr_setrobust, "pthread_mutexattr_setrobust");
    symbol(&pthread_mutexattr_gettype, "pthread_mutexattr_gettype");
    symbol(&pthread_mutexattr_settype, "pthread_mutexattr_settype");

    // Once
    symbol(&pthread_once, "__pthread_once");
    symbol(&pthread_once, "pthread_once");

    // Read-write lock
    symbol(&pthread_rwlock_init, "pthread_rwlock_init");
    symbol(&pthread_rwlock_destroy, "pthread_rwlock_destroy");
    symbol(&pthread_rwlock_rdlock, "__pthread_rwlock_rdlock");
    symbol(&pthread_rwlock_rdlock, "pthread_rwlock_rdlock");
    symbol(&pthread_rwlock_timedrdlock, "__pthread_rwlock_timedrdlock");
    symbol(&pthread_rwlock_timedrdlock, "pthread_rwlock_timedrdlock");
    symbol(&pthread_rwlock_timedwrlock, "__pthread_rwlock_timedwrlock");
    symbol(&pthread_rwlock_timedwrlock, "pthread_rwlock_timedwrlock");
    symbol(&pthread_rwlock_tryrdlock, "__pthread_rwlock_tryrdlock");
    symbol(&pthread_rwlock_tryrdlock, "pthread_rwlock_tryrdlock");
    symbol(&pthread_rwlock_trywrlock, "__pthread_rwlock_trywrlock");
    symbol(&pthread_rwlock_trywrlock, "pthread_rwlock_trywrlock");
    symbol(&pthread_rwlock_unlock, "__pthread_rwlock_unlock");
    symbol(&pthread_rwlock_unlock, "pthread_rwlock_unlock");
    symbol(&pthread_rwlock_wrlock, "__pthread_rwlock_wrlock");
    symbol(&pthread_rwlock_wrlock, "pthread_rwlock_wrlock");
    symbol(&pthread_rwlockattr_init, "pthread_rwlockattr_init");
    symbol(&pthread_rwlockattr_destroy, "pthread_rwlockattr_destroy");
    symbol(&pthread_rwlockattr_getpshared, "pthread_rwlockattr_getpshared");
    symbol(&pthread_rwlockattr_setpshared, "pthread_rwlockattr_setpshared");
}
