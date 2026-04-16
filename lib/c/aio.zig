//! POSIX Asynchronous I/O — thread-pool based implementation.
//!
//! Ported from musl libc's src/aio/ (aio.c, aio_suspend.c, lio_listio.c).
//! Each aio_read/aio_write/aio_fsync call spawns a detached worker thread
//! that performs the I/O, then notifies waiters via atomics and futex.

const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;
const c_lib = @import("../c.zig");

/// O_SYNC and O_DSYNC as integer constants for the C ABI.
const O_DSYNC: c_int = @bitCast(@as(linux.O, .{ .DSYNC = true }));
const O_SYNC: c_int = @bitCast(@as(linux.O, .{ .SYNC = true, .DSYNC = true }));

/// Wrapper for pthread_sigmask that discards the old mask (passes a dummy instead of null).
fn sigmaskRestore(origmask: *const std.c.sigset_t) void {
    var discard: std.c.sigset_t = undefined;
    _ = std.c.pthread_sigmask(linux.SIG.SETMASK, origmask, &discard);
}

// ─── Constants ───────────────────────────────────────────────────────

const AIO_CANCELED: c_int = 0;
const AIO_NOTCANCELED: c_int = 1;
const AIO_ALLDONE: c_int = 2;

const LIO_READ: c_int = 0;
const LIO_WRITE: c_int = 1;
const LIO_WAIT: c_int = 0;

const SIGEV_SIGNAL: c_int = 0;
const SIGEV_NONE: c_int = 1;
const SIGEV_THREAD: c_int = 2;

const SI_ASYNCIO: c_int = -4;

const MINSIGSTKSZ: usize = switch (builtin.cpu.arch) {
    .aarch64, .aarch64_be => 5120,
    else => 2048,
};
const AT_MINSIGSTKSZ: c_ulong = 51;

const PTHREAD_CREATE_DETACHED: c_int = 1;

// ─── Types ───────────────────────────────────────────────────────────

const sigval_t = extern union {
    int: c_int,
    ptr: ?*anyopaque,
};

const sigevent_t = extern struct {
    sigev_value: sigval_t,
    sigev_signo: c_int,
    sigev_notify: c_int,
    __sev_fields: extern union {
        __pad: [64 - 2 * @sizeOf(c_int) - @sizeOf(sigval_t)]u8,
        __sev_thread: extern struct {
            sigev_notify_function: ?*const fn (sigval_t) callconv(.c) void,
            sigev_notify_attributes: ?*std.c.pthread_attr_t,
        },
    },
};

const aiocb = extern struct {
    aio_fildes: c_int,
    aio_lio_opcode: c_int,
    aio_reqprio: c_int,
    aio_buf: ?*anyopaque,
    aio_nbytes: usize,
    aio_sigevent: sigevent_t,
    __td: ?*anyopaque,
    __lock: [2]c_int,
    __err: c_int,
    __ret: isize,
    aio_offset: std.c.off_t,
    __next: ?*anyopaque,
    __prev: ?*anyopaque,
    __dummy4: [32 - 2 * @sizeOf(?*anyopaque)]u8,
};

const PtCb = extern struct {
    __f: ?*const fn (?*anyopaque) callconv(.c) void,
    __x: ?*anyopaque,
    __next: ?*PtCb,
};

// ─── Internal structures ────────────────────────────────────────────

const AioThread = struct {
    td: std.c.pthread_t = undefined,
    cb: *aiocb = undefined,
    next: ?*AioThread = null,
    prev: ?*AioThread = null,
    q: *AioQueue = undefined,
    running: c_int = 0,
    err: c_int = 0,
    op: c_int = 0,
    ret: isize = 0,
};

const AioQueue = struct {
    fd: c_int = 0,
    seekable: c_int = 0,
    append: c_int = 0,
    ref: c_int = 0,
    init: c_int = 0,
    lock: std.c.pthread_mutex_t = std.c.PTHREAD_MUTEX_INITIALIZER,
    cond: std.c.pthread_cond_t = std.c.PTHREAD_COND_INITIALIZER,
    head: ?*AioThread = null,
};

const AioArgs = struct {
    cb: *aiocb,
    op: c_int,
    q: *AioQueue,
    sem: std.c.sem_t = undefined,
};

const LioState = struct {
    sev: ?*sigevent_t,
    cnt: c_int,
    // cbs is a flexible array following this struct in the allocation
};

// ─── Extern C functions ─────────────────────────────────────────────

extern "c" fn pthread_mutex_init(mutex: *std.c.pthread_mutex_t, attr: ?*const anyopaque) c_int;
extern "c" fn pthread_cond_init(cond: *std.c.pthread_cond_t, attr: ?*const anyopaque) c_int;
extern "c" fn pthread_rwlock_init(rwlock: *std.c.pthread_rwlock_t, attr: ?*const anyopaque) c_int;
extern "c" fn pthread_attr_setdetachstate(attr: *std.c.pthread_attr_t, state: c_int) c_int;
extern "c" fn pthread_testcancel() void;
extern "c" fn _pthread_cleanup_push(cb: *PtCb, f: *const fn (?*anyopaque) callconv(.c) void, x: ?*anyopaque) void;
extern "c" fn _pthread_cleanup_pop(cb: *PtCb, execute: c_int) void;
extern "c" fn read(fd: c_int, buf: ?*anyopaque, count: usize) isize;
extern "c" fn write(fd: c_int, buf: ?*const anyopaque, count: usize) isize;
extern "c" fn pread(fd: c_int, buf: ?*anyopaque, count: usize, offset: std.c.off_t) isize;
extern "c" fn pwrite(fd: c_int, buf: ?*const anyopaque, count: usize, offset: std.c.off_t) isize;
extern "c" fn fsync(fd: c_int) c_int;
extern "c" fn fdatasync(fd: c_int) c_int;
extern "c" fn lseek(fd: c_int, offset: std.c.off_t, whence: c_int) std.c.off_t;
extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;
extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn memcpy(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque;
extern "c" fn getauxval(tag: c_ulong) c_ulong;

// ─── Global state ───────────────────────────────────────────────────

var maplock: std.c.pthread_rwlock_t = .{};

// 4-level radix tree mapping fd → AioQueue.
// Levels: [128][256][256][256], indexed by fd octets.
var map: ?[*]?[*]?[*]?[*]?*AioQueue = null;
var aio_fd_cnt: c_int = 0;
var aio_fut: c_int = 0;

var io_thread_stack_size: usize = 0;

// ─── Atomic helpers ─────────────────────────────────────────────────

inline fn atomicLoad(ptr: *c_int) c_int {
    return @atomicLoad(c_int, ptr, .seq_cst);
}

inline fn atomicStore(ptr: *c_int, val: c_int) void {
    @atomicStore(c_int, ptr, val, .seq_cst);
}

inline fn atomicCas(ptr: *c_int, expected: c_int, desired: c_int) ?c_int {
    return @cmpxchgStrong(c_int, ptr, expected, desired, .seq_cst, .seq_cst);
}

inline fn atomicSwap(ptr: *c_int, val: c_int) c_int {
    return @atomicRmw(c_int, ptr, .Xchg, val, .seq_cst);
}

inline fn atomicInc(ptr: *c_int) void {
    _ = @atomicRmw(c_int, ptr, .Add, 1, .seq_cst);
}

inline fn atomicDec(ptr: *c_int) void {
    _ = @atomicRmw(c_int, ptr, .Sub, 1, .seq_cst);
}

// ─── Futex helpers ──────────────────────────────────────────────────

fn futexWake(ptr: *c_int, cnt: c_int) void {
    const actual_cnt: u32 = if (cnt < 0) std.math.maxInt(u32) else @intCast(cnt);
    _ = linux.futex(@ptrCast(ptr), .{ .cmd = .WAKE, .private = true }, actual_cnt, .{ .timeout = null }, null, 0);
}

fn futexWait(ptr: *c_int, val: c_int) void {
    _ = linux.futex(@ptrCast(ptr), .{ .cmd = .WAIT, .private = true }, @bitCast(val), .{ .timeout = null }, null, 0);
}

fn futexTimedWait(ptr: *c_int, val: c_int, clk: std.c.clockid_t, ts: ?*const std.c.timespec) c_int {
    const op: linux.FUTEX_OP = .{
        .cmd = .WAIT_BITSET,
        .private = true,
        .realtime = (clk == std.c.CLOCK.MONOTONIC),
    };
    const rc = linux.futex(@ptrCast(ptr), op, @bitCast(val), .{ .timeout = if (ts) |t| @ptrCast(t) else null }, null, std.math.maxInt(u32) // FUTEX_BITSET_MATCH_ANY
    );
    const signed: isize = @bitCast(rc);
    if (signed < 0) return @truncate(-signed);
    return 0;
}

// ─── Queue management ───────────────────────────────────────────────

fn getQueue(fd: c_int, need: c_int) ?*AioQueue {
    if (fd < 0) {
        std.c._errno().* = @intFromEnum(linux.E.BADF);
        return null;
    }
    const ufd: u31 = @intCast(fd);
    const a: u7 = @intCast(ufd >> 24);
    const b: u8 = @truncate(ufd >> 16);
    const c: u8 = @truncate(ufd >> 8);
    const d: u8 = @truncate(ufd);

    var masked = false;
    var origmask: std.c.sigset_t = undefined;

    _ = std.c.pthread_rwlock_rdlock(&maplock);
    var q: ?*AioQueue = null;
    if (map) |m| {
        if (m[a]) |ma| {
            if (ma[b]) |mab| {
                if (mab[c]) |mabc| {
                    q = mabc[d];
                }
            }
        }
    }

    if (q == null and need != 0) {
        _ = std.c.pthread_rwlock_unlock(&maplock);
        if (fcntl(fd, linux.F.GETFD) < 0) return null;
        var allmask: std.c.sigset_t = undefined;
        _ = std.c.sigfillset(&allmask);
        masked = true;
        _ = std.c.pthread_sigmask(linux.SIG.BLOCK, &allmask, &origmask);
        _ = std.c.pthread_rwlock_wrlock(&maplock);
        if (io_thread_stack_size == 0) {
            const val = getauxval(AT_MINSIGSTKSZ);
            io_thread_stack_size = @max(MINSIGSTKSZ + 2048, val + 512);
        }
        if (map == null) {
            map = @ptrCast(@alignCast(calloc(128, @sizeOf(?[*]?[*]?[*]?*AioQueue)) orelse {
                _ = std.c.pthread_rwlock_unlock(&maplock);
                if (masked) sigmaskRestore(&origmask);
                return null;
            }));
        }
        const m = map.?;
        if (m[a] == null) {
            m[a] = @ptrCast(@alignCast(calloc(256, @sizeOf(?[*]?[*]?*AioQueue)) orelse {
                _ = std.c.pthread_rwlock_unlock(&maplock);
                if (masked) sigmaskRestore(&origmask);
                return null;
            }));
        }
        if (m[a] == null) {
            _ = std.c.pthread_rwlock_unlock(&maplock);
            if (masked) sigmaskRestore(&origmask);
            return null;
        }
        const ma = m[a].?;
        if (ma[b] == null) {
            ma[b] = @ptrCast(@alignCast(calloc(256, @sizeOf(?[*]?*AioQueue)) orelse {
                _ = std.c.pthread_rwlock_unlock(&maplock);
                if (masked) sigmaskRestore(&origmask);
                return null;
            }));
        }
        if (ma[b] == null) {
            _ = std.c.pthread_rwlock_unlock(&maplock);
            if (masked) sigmaskRestore(&origmask);
            return null;
        }
        const mab = ma[b].?;
        if (mab[c] == null) {
            mab[c] = @ptrCast(@alignCast(calloc(256, @sizeOf(?*AioQueue)) orelse {
                _ = std.c.pthread_rwlock_unlock(&maplock);
                if (masked) sigmaskRestore(&origmask);
                return null;
            }));
        }
        if (mab[c] == null) {
            _ = std.c.pthread_rwlock_unlock(&maplock);
            if (masked) sigmaskRestore(&origmask);
            return null;
        }
        const mabc = mab[c].?;
        if (mabc[d] == null) {
            const new_q: ?*AioQueue = @ptrCast(@alignCast(calloc(1, @sizeOf(AioQueue))));
            if (new_q) |nq| {
                nq.* = .{
                    .fd = fd,
                    .lock = std.c.PTHREAD_MUTEX_INITIALIZER,
                    .cond = std.c.PTHREAD_COND_INITIALIZER,
                };
                _ = pthread_mutex_init(&nq.lock, null);
                _ = pthread_cond_init(&nq.cond, null);
                atomicInc(&aio_fd_cnt);
            }
            mabc[d] = new_q;
        }
        q = mabc[d];
    }
    if (q) |queue| _ = std.c.pthread_mutex_lock(&queue.lock);
    _ = std.c.pthread_rwlock_unlock(&maplock);
    if (masked) sigmaskRestore(&origmask);
    return q;
}

fn unrefQueue(q: *AioQueue) void {
    if (q.ref > 1) {
        q.ref -= 1;
        _ = std.c.pthread_mutex_unlock(&q.lock);
        return;
    }

    _ = std.c.pthread_mutex_unlock(&q.lock);
    _ = std.c.pthread_rwlock_wrlock(&maplock);
    _ = std.c.pthread_mutex_lock(&q.lock);
    if (q.ref == 1) {
        const fd = q.fd;
        const ufd: u31 = @intCast(fd);
        const a: u7 = @intCast(ufd >> 24);
        const b: u8 = @truncate(ufd >> 16);
        const c: u8 = @truncate(ufd >> 8);
        const d: u8 = @truncate(ufd);
        map.?[a].?[b].?[c].?[d] = null;
        atomicDec(&aio_fd_cnt);
        _ = std.c.pthread_rwlock_unlock(&maplock);
        _ = std.c.pthread_mutex_unlock(&q.lock);
        free(@ptrCast(q));
    } else {
        q.ref -= 1;
        _ = std.c.pthread_rwlock_unlock(&maplock);
        _ = std.c.pthread_mutex_unlock(&q.lock);
    }
}

// ─── Signal notification helper ─────────────────────────────────────

fn notifySignal(signo: c_int, val: sigval_t) void {
    const pid: c_int = @bitCast(linux.getuid());
    // Use rt_sigqueueinfo syscall with a minimal siginfo_t layout.
    // The kernel expects 128 bytes; we zero-initialize and set the fields.
    var si = std.mem.zeroes(linux.siginfo_t);
    si.signo = @enumFromInt(signo);
    si.code = SI_ASYNCIO;
    si.fields = .{
        .common = .{
            .first = .{
                .piduid = .{
                    .pid = linux.getpid(),
                    .uid = @bitCast(pid),
                },
            },
            .second = .{
                .value = .{ .int = val.int },
            },
        },
    };
    _ = linux.syscall3(
        .rt_sigqueueinfo,
        @bitCast(@as(isize, linux.getpid())),
        @bitCast(@as(isize, signo)),
        @intFromPtr(&si),
    );
}

// ─── Cleanup handler ────────────────────────────────────────────────

fn cleanup(ctx: ?*anyopaque) callconv(.c) void {
    const at: *AioThread = @ptrCast(@alignCast(ctx));
    const q = at.q;
    const cb = at.cb;
    const sev = cb.aio_sigevent;

    cb.__ret = at.ret;
    if (atomicSwap(&at.running, 0) < 0)
        futexWake(&at.running, -1);
    if (atomicSwap(&cb.__err, at.err) != @intFromEnum(linux.E.INPROGRESS))
        futexWake(&cb.__err, -1);
    if (atomicSwap(&aio_fut, 0) != 0)
        futexWake(&aio_fut, -1);

    _ = std.c.pthread_mutex_lock(&q.lock);

    if (at.next) |next| next.prev = at.prev;
    if (at.prev) |prev| {
        prev.next = at.next;
    } else {
        q.head = at.next;
    }

    _ = std.c.pthread_cond_broadcast(&q.cond);

    unrefQueue(q);

    if (sev.sigev_notify == SIGEV_SIGNAL) {
        notifySignal(sev.sigev_signo, sev.sigev_value);
    }
    if (sev.sigev_notify == SIGEV_THREAD) {
        // Disable cancellation before calling the notification function.
        _ = std.c.pthread_setcancelstate(.DISABLE, null);
        if (sev.__sev_fields.__sev_thread.sigev_notify_function) |func| {
            func(sev.sigev_value);
        }
    }
}

// ─── Worker thread ──────────────────────────────────────────────────

fn ioThreadFunc(ctx: ?*anyopaque) callconv(.c) ?*anyopaque {
    var at: AioThread = .{};

    const args: *AioArgs = @ptrCast(@alignCast(ctx));
    const cb = args.cb;
    const fd = cb.aio_fildes;
    const op = args.op;
    const buf = cb.aio_buf;
    const len = cb.aio_nbytes;
    const off = cb.aio_offset;

    const q = args.q;

    _ = std.c.pthread_mutex_lock(&q.lock);
    _ = std.c.sem_post(&args.sem);

    at.op = op;
    at.running = 1;
    at.ret = -1;
    at.err = @intFromEnum(linux.E.CANCELED);
    at.q = q;
    at.td = std.c.pthread_self();
    at.cb = cb;
    at.prev = null;
    at.next = q.head;
    if (q.head) |head| head.prev = &at;
    q.head = &at;

    if (q.init == 0) {
        const seek_result = lseek(fd, 0, linux.SEEK.CUR);
        const seekable: c_int = if (seek_result >= 0) 1 else 0;
        q.seekable = seekable;
        q.append = if (seekable == 0) 1 else blk: {
            const fl: linux.O = @bitCast(@as(u32, @intCast(@as(c_uint, @bitCast(fcntl(fd, linux.F.GETFL))))));
            break :blk if (fl.APPEND) @as(c_int, 1) else @as(c_int, 0);
        };
        q.init = 1;
    }

    // Push cleanup handler.
    var ptcb: PtCb = undefined;
    _pthread_cleanup_push(&ptcb, &cleanup, @ptrCast(&at));

    // Wait for sequenced operations (writes on append-mode fds must be ordered).
    if (op != LIO_READ and (op != LIO_WRITE or q.append != 0)) {
        while (true) {
            var p = at.next;
            while (p) |pp| {
                if (pp.op == LIO_WRITE) break;
                p = pp.next;
            } else break; // no writer found
            if (p != null) {
                _ = std.c.pthread_cond_wait(&q.cond, &q.lock);
            }
        }
    }

    _ = std.c.pthread_mutex_unlock(&q.lock);

    const ret: isize = switch (op) {
        LIO_WRITE => if (q.append != 0)
            write(fd, buf, len)
        else
            pwrite(fd, buf, len, off),
        LIO_READ => if (q.seekable == 0)
            read(fd, buf, len)
        else
            pread(fd, buf, len, off),
        O_SYNC => @as(isize, fsync(fd)),
        O_DSYNC => @as(isize, fdatasync(fd)),
        else => -1,
    };
    at.ret = ret;
    at.err = if (ret < 0) std.c._errno().* else 0;

    // Pop and execute cleanup handler.
    _pthread_cleanup_pop(&ptcb, 1);

    return null;
}

// ─── Submit ─────────────────────────────────────────────────────────

fn submit(cb: *aiocb, op: c_int) c_int {
    var ret: c_int = 0;
    var a: std.c.pthread_attr_t = undefined;
    var origmask: std.c.sigset_t = undefined;
    var td: std.c.pthread_t = undefined;
    const q = getQueue(cb.aio_fildes, 1) orelse {
        if (std.c._errno().* != @intFromEnum(linux.E.BADF))
            std.c._errno().* = @intFromEnum(linux.E.AGAIN);
        cb.__ret = -1;
        cb.__err = std.c._errno().*;
        return -1;
    };
    var args: AioArgs = .{ .cb = cb, .op = op, .q = q };
    _ = std.c.sem_init(&args.sem, 0, 0);

    q.ref += 1;
    _ = std.c.pthread_mutex_unlock(&q.lock);

    if (cb.aio_sigevent.sigev_notify == SIGEV_THREAD) {
        if (cb.aio_sigevent.__sev_fields.__sev_thread.sigev_notify_attributes) |attr| {
            a = attr.*;
        } else {
            _ = std.c.pthread_attr_init(&a);
        }
    } else {
        _ = std.c.pthread_attr_init(&a);
        _ = std.c.pthread_attr_setstacksize(&a, io_thread_stack_size);
        _ = std.c.pthread_attr_setguardsize(&a, 0);
    }
    _ = pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
    var allmask: std.c.sigset_t = undefined;
    _ = std.c.sigfillset(&allmask);
    _ = std.c.pthread_sigmask(linux.SIG.BLOCK, &allmask, &origmask);
    cb.__err = @intFromEnum(linux.E.INPROGRESS);
    if (std.c.pthread_create(&td, &a, &ioThreadFunc, @ptrCast(&args)) != .SUCCESS) {
        _ = std.c.pthread_mutex_lock(&q.lock);
        unrefQueue(q);
        std.c._errno().* = @intFromEnum(linux.E.AGAIN);
        cb.__err = @intFromEnum(linux.E.AGAIN);
        cb.__ret = -1;
        ret = -1;
    }
    sigmaskRestore(&origmask);

    if (ret == 0) {
        while (std.c.sem_wait(&args.sem) != 0) {}
    }

    return ret;
}

// ─── Public API ─────────────────────────────────────────────────────

fn aio_read_impl(cb: *aiocb) callconv(.c) c_int {
    return submit(cb, LIO_READ);
}

fn aio_write_impl(cb: *aiocb) callconv(.c) c_int {
    return submit(cb, LIO_WRITE);
}

fn aio_fsync_impl(op: c_int, cb: *aiocb) callconv(.c) c_int {
    if (op != O_SYNC and op != O_DSYNC) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    return submit(cb, op);
}

fn aio_return_impl(cb: *aiocb) callconv(.c) isize {
    return cb.__ret;
}

fn aio_error_impl(cb: *const aiocb) callconv(.c) c_int {
    return atomicLoad(@constCast(&cb.__err)) & 0x7fffffff;
}

fn aio_cancel_impl(fd: c_int, cb: ?*aiocb) callconv(.c) c_int {
    var origmask: std.c.sigset_t = undefined;
    var ret: c_int = AIO_ALLDONE;

    if (cb) |cb_ptr| {
        if (fd != cb_ptr.aio_fildes) {
            std.c._errno().* = @intFromEnum(linux.E.INVAL);
            return -1;
        }
    }

    var allmask: std.c.sigset_t = undefined;
    _ = std.c.sigfillset(&allmask);
    _ = std.c.pthread_sigmask(linux.SIG.BLOCK, &allmask, &origmask);

    std.c._errno().* = @intFromEnum(linux.E.NOENT);
    const q = getQueue(fd, 0) orelse {
        if (std.c._errno().* == @intFromEnum(linux.E.BADF)) {
            ret = -1;
        }
        sigmaskRestore(&origmask);
        return ret;
    };

    var p = q.head;
    while (p) |pp| {
        if (cb != null and cb != @as(?*aiocb, pp.cb)) {
            p = pp.next;
            continue;
        }
        // Transition from running(1) to running-with-waiters(-1).
        if (atomicCas(&pp.running, 1, -1) == null) {
            _ = std.c.pthread_cancel(pp.td);
            // Wait for the thread to finish.
            while (atomicLoad(&pp.running) == -1) {
                futexWait(&pp.running, -1);
            }
            if (pp.err == @intFromEnum(linux.E.CANCELED)) ret = AIO_CANCELED;
        }
        p = pp.next;
    }

    _ = std.c.pthread_mutex_unlock(&q.lock);
    sigmaskRestore(&origmask);
    return ret;
}

// ─── aio_suspend ────────────────────────────────────────────────────

fn aio_suspend_impl(cbs: [*]const ?*const aiocb, cnt: c_int, ts: ?*const std.c.timespec) callconv(.c) c_int {
    pthread_testcancel();

    if (cnt < 0) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }

    const ucnt: usize = @intCast(cnt);
    var nzcnt: c_int = 0;
    var last_cb: ?*const aiocb = null;

    for (0..ucnt) |i| {
        if (cbs[i]) |cb_ptr| {
            if (aio_error_impl(cb_ptr) != @intFromEnum(linux.E.INPROGRESS)) return 0;
            nzcnt += 1;
            last_cb = cb_ptr;
        }
    }

    var at: std.c.timespec = undefined;
    if (ts) |timeout| {
        _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &at);
        at.sec += timeout.sec;
        at.nsec += timeout.nsec;
        if (at.nsec >= 1_000_000_000) {
            at.nsec -= 1_000_000_000;
            at.sec += 1;
        }
    }

    var tid: c_int = 0;

    while (true) {
        for (0..ucnt) |i| {
            if (cbs[i]) |cb_ptr| {
                if (aio_error_impl(cb_ptr) != @intFromEnum(linux.E.INPROGRESS)) return 0;
            }
        }

        var pfut: *c_int = undefined;
        var expect: c_int = 0;

        switch (nzcnt) {
            0 => {
                var dummy_fut: c_int = 0;
                pfut = &dummy_fut;
            },
            1 => {
                pfut = @constCast(&last_cb.?.__err);
                expect = @intFromEnum(linux.E.INPROGRESS) | @as(c_int, @bitCast(@as(u32, 0x80000000)));
                _ = atomicCas(pfut, @intFromEnum(linux.E.INPROGRESS), expect);
            },
            else => {
                pfut = &aio_fut;
                if (tid == 0) tid = linux.gettid();
                const cas_result = atomicCas(pfut, 0, tid);
                if (cas_result) |old_val| {
                    expect = old_val;
                } else {
                    expect = tid;
                }
                // Recheck before waiting.
                for (0..ucnt) |i| {
                    if (cbs[i]) |cb_ptr| {
                        if (aio_error_impl(cb_ptr) != @intFromEnum(linux.E.INPROGRESS)) return 0;
                    }
                }
            },
        }

        const wait_ts: ?*const std.c.timespec = if (ts != null) &at else null;
        const wait_ret = futexTimedWait(pfut, expect, std.c.CLOCK.MONOTONIC, wait_ts);

        switch (wait_ret) {
            @intFromEnum(linux.E.TIMEDOUT) => {
                std.c._errno().* = @intFromEnum(linux.E.AGAIN);
                return -1;
            },
            @intFromEnum(linux.E.CANCELED) => {
                std.c._errno().* = @intFromEnum(linux.E.CANCELED);
                return -1;
            },
            @intFromEnum(linux.E.INTR) => {
                std.c._errno().* = @intFromEnum(linux.E.INTR);
                return -1;
            },
            else => {},
        }
    }
}

// ─── lio_listio ─────────────────────────────────────────────────────

fn lioWait(st_ptr: *anyopaque) c_int {
    const st: *LioState = @ptrCast(@alignCast(st_ptr));
    const cnt: usize = @intCast(st.cnt);
    const cbs_base: [*]?*aiocb = @ptrCast(@alignCast(@as([*]u8, @ptrCast(st)) + @sizeOf(LioState)));
    var got_err: bool = false;

    while (true) {
        var all_done = true;
        for (0..cnt) |i| {
            if (cbs_base[i]) |cb_ptr| {
                const err = aio_error_impl(@ptrCast(cb_ptr));
                if (err == @intFromEnum(linux.E.INPROGRESS)) {
                    all_done = false;
                    break;
                }
                if (err != 0) got_err = true;
                cbs_base[i] = null;
            }
        }
        if (all_done) {
            if (got_err) {
                std.c._errno().* = @intFromEnum(linux.E.IO);
                return -1;
            }
            return 0;
        }
        // Cast cbs_base to the type aio_suspend expects.
        if (aio_suspend_impl(@ptrCast(cbs_base), st.cnt, null) != 0)
            return -1;
    }
}

fn waitThread(ctx: ?*anyopaque) callconv(.c) ?*anyopaque {
    const st: *LioState = @ptrCast(@alignCast(ctx));
    const sev = st.sev;
    _ = lioWait(@ptrCast(st));
    const sev_copy = sev;
    free(@ptrCast(st));
    if (sev_copy) |s| {
        switch (s.sigev_notify) {
            SIGEV_SIGNAL => notifySignal(s.sigev_signo, s.sigev_value),
            SIGEV_THREAD => {
                if (s.__sev_fields.__sev_thread.sigev_notify_function) |func| {
                    func(s.sigev_value);
                }
            },
            else => {},
        }
    }
    return null;
}

fn lio_listio_impl(mode: c_int, cbs: [*]const ?*aiocb, cnt: c_int, sev: ?*sigevent_t) callconv(.c) c_int {
    if (cnt < 0) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }

    const ucnt: usize = @intCast(cnt);

    // Allocate LioState + flexible array of aiocb pointers.
    var st: ?*LioState = null;
    if (mode == LIO_WAIT or (sev != null and sev.?.sigev_notify != SIGEV_NONE)) {
        const alloc_size = @sizeOf(LioState) + ucnt * @sizeOf(?*aiocb);
        st = @ptrCast(@alignCast(malloc(alloc_size) orelse {
            std.c._errno().* = @intFromEnum(linux.E.AGAIN);
            return -1;
        }));
        st.?.cnt = cnt;
        st.?.sev = sev;
        // Copy the cbs array into the flexible array portion.
        const dst: [*]u8 = @ptrCast(st.?);
        _ = memcpy(@ptrCast(dst + @sizeOf(LioState)), @ptrCast(cbs), ucnt * @sizeOf(?*aiocb));
    }

    for (0..ucnt) |i| {
        if (cbs[i]) |cb_ptr| {
            const opcode = cb_ptr.aio_lio_opcode;
            const sub_ret: c_int = switch (opcode) {
                LIO_READ => aio_read_impl(@constCast(cb_ptr)),
                LIO_WRITE => aio_write_impl(@constCast(cb_ptr)),
                else => continue,
            };
            if (sub_ret != 0) {
                if (st) |s| free(@ptrCast(s));
                std.c._errno().* = @intFromEnum(linux.E.AGAIN);
                return -1;
            }
        }
    }

    if (mode == LIO_WAIT) {
        const ret = lioWait(@ptrCast(st.?));
        free(@ptrCast(st.?));
        return ret;
    }

    if (st) |s| {
        var a: std.c.pthread_attr_t = undefined;
        var set_old: std.c.sigset_t = undefined;
        var td: std.c.pthread_t = undefined;

        if (sev.?.sigev_notify == SIGEV_THREAD) {
            if (sev.?.__sev_fields.__sev_thread.sigev_notify_attributes) |attr| {
                a = attr.*;
            } else {
                _ = std.c.pthread_attr_init(&a);
            }
        } else {
            _ = std.c.pthread_attr_init(&a);
            _ = std.c.pthread_attr_setstacksize(&a, std.heap.page_size_min);
            _ = std.c.pthread_attr_setguardsize(&a, 0);
        }
        _ = pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
        var set: std.c.sigset_t = undefined;
        _ = std.c.sigfillset(&set);
        _ = std.c.pthread_sigmask(linux.SIG.BLOCK, &set, &set_old);
        if (std.c.pthread_create(&td, &a, &waitThread, @ptrCast(s)) != .SUCCESS) {
            free(@ptrCast(s));
            std.c._errno().* = @intFromEnum(linux.E.AGAIN);
            return -1;
        }
        sigmaskRestore(&set_old);
    }

    return 0;
}

// ─── Internal API ───────────────────────────────────────────────────

fn aio_close_impl(fd: c_int) callconv(.c) c_int {
    if (atomicLoad(&aio_fd_cnt) != 0) _ = aio_cancel_impl(fd, null);
    return fd;
}

fn aio_atfork_impl(who: c_int) callconv(.c) void {
    if (who < 0) {
        _ = std.c.pthread_rwlock_rdlock(&maplock);
        return;
    } else if (who == 0) {
        _ = std.c.pthread_rwlock_unlock(&maplock);
        return;
    }
    atomicStore(&aio_fd_cnt, 0);
    if (std.c.pthread_rwlock_tryrdlock(&maplock) != .SUCCESS) {
        map = null;
        return;
    }
    if (map) |m| {
        for (0..128) |a| {
            if (m[a]) |ma| {
                for (0..256) |b| {
                    if (ma[b]) |mab| {
                        for (0..256) |cc| {
                            if (mab[cc]) |mabc| {
                                for (0..256) |d| {
                                    mabc[d] = null;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    _ = pthread_rwlock_init(&maplock, null);
}

// ─── Symbol exports ─────────────────────────────────────────────────

comptime {
    if (builtin.link_libc) {
        c_lib.symbol(&aio_read_impl, "aio_read");
        c_lib.symbol(&aio_write_impl, "aio_write");
        c_lib.symbol(&aio_fsync_impl, "aio_fsync");
        c_lib.symbol(&aio_return_impl, "aio_return");
        c_lib.symbol(&aio_error_impl, "aio_error");
        c_lib.symbol(&aio_cancel_impl, "aio_cancel");
        c_lib.symbol(&aio_suspend_impl, "aio_suspend");
        c_lib.symbol(&lio_listio_impl, "lio_listio");
        c_lib.symbol(&aio_close_impl, "__aio_close");
        c_lib.symbol(&aio_atfork_impl, "__aio_atfork");

        @export(&aio_fut, .{ .name = "__aio_fut", .linkage = .weak, .visibility = .hidden });
    }
}
