const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;
const symbol = @import("../c.zig").symbol;
fn _ExitImpl(code: c_int) callconv(.c) noreturn {
    std.os.linux.exit_group(@intCast(code));
}
extern "c" fn __stdio_exit() void;
fn _finiStub() callconv(.c) void {}
extern const __fini_array_start: *const fn () callconv(.c) void;
extern const __fini_array_end: *const fn () callconv(.c) void;
// Internal musl lock functions (provided by the thread subsystem).
extern "c" fn __lock(lock: *c_int) void;
extern "c" fn __unlock(lock: *c_int) void;
// C library functions used by atexit.
extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;
const COUNT = 32;
var qe_funcs: [COUNT]?*const fn () callconv(.c) void = .{null} ** COUNT;
var qe_count: c_int = 0;
var qe_lock: c_int = 0;
const FuncList = extern struct {
    next: ?*FuncList,
    f: [COUNT]?*const fn (?*anyopaque) callconv(.c) void,
    a: [COUNT]?*anyopaque,
};
var ae_builtin: FuncList = std.mem.zeroes(FuncList);
var ae_head: ?*FuncList = null;
var ae_slot: c_int = 0;
var ae_lock: c_int = 0;
extern "c" fn raise(sig: c_int) c_int;
extern "c" fn __block_all_sigs(set: ?*anyopaque) void;
extern "c" var __abort_lock: c_int;

comptime {
    if (builtin.target.isMuslLibC()) {
    }
    if (builtin.link_libc) {
        symbol(&quick_exit, "quick_exit");
        symbol(&__funcs_on_quick_exit, "__funcs_on_quick_exit");
        symbol(&at_quick_exit, "at_quick_exit");
        symbol(&__funcs_on_exit, "__funcs_on_exit");
        symbol(&__cxa_finalize, "__cxa_finalize");
        symbol(&__cxa_atexit, "__cxa_atexit");
        symbol(&atexit, "atexit");
        symbol(&qe_lock, "__at_quick_exit_lockptr");
        symbol(&ae_lock, "__atexit_lockptr");
        symbol(&abortImpl, "abort");
        symbol(&dummy, "__stdio_exit");
        symbol(&libc_exit_fini, "__libc_exit_fini");
        symbol(&exitImpl, "exit");
    }
}

fn _ExitLinux(exit_code: c_int) callconv(.c) noreturn {
    linux.exit_group(exit_code);
}

fn quick_exit(code: c_int) callconv(.c) noreturn {
    __funcs_on_quick_exit();
    _Exit(code);
}

fn __funcs_on_quick_exit() callconv(.c) void {
    __lock(&qe_lock);
    while (qe_count > 0) {
        qe_count -= 1;
        const func = qe_funcs[@intCast(qe_count)].?;
        __unlock(&qe_lock);
        func();
        __lock(&qe_lock);
    }
    __unlock(&qe_lock);
}

fn at_quick_exit(func: ?*const fn () callconv(.c) void) callconv(.c) c_int {
    __lock(&qe_lock);
    defer __unlock(&qe_lock);
    if (qe_count == COUNT) return -1;
    qe_funcs[@intCast(qe_count)] = func;
    qe_count += 1;
    return 0;
}

fn __funcs_on_exit() callconv(.c) void {
    __lock(&ae_lock);
    var head = ae_head;
    var slot = ae_slot;
    while (head) |h| {
        while (slot > 0) {
            slot -= 1;
            const func = h.f[@intCast(slot)].?;
            const arg = h.a[@intCast(slot)];
            __unlock(&ae_lock);
            func(arg);
            __lock(&ae_lock);
        }
        head = h.next;
        slot = COUNT;
    }
    __unlock(&ae_lock);
}

fn __cxa_finalize(_: ?*anyopaque) callconv(.c) void {}

fn __cxa_atexit(
    func: ?*const fn (?*anyopaque) callconv(.c) void,
    arg: ?*anyopaque,
    _: ?*anyopaque,
) callconv(.c) c_int {
    __lock(&ae_lock);
    defer __unlock(&ae_lock);

    // Defer initialization of head so it can be in BSS.
    if (ae_head == null) ae_head = &ae_builtin;

    // If the current function list is full, add a new one.
    if (ae_slot == COUNT) {
        const new_fl: ?*FuncList = @ptrCast(@alignCast(calloc(@sizeOf(FuncList), 1)));
        if (new_fl == null) return -1;
        new_fl.?.next = ae_head;
        ae_head = new_fl;
        ae_slot = 0;
    }

    ae_head.?.f[@intCast(ae_slot)] = func;
    ae_head.?.a[@intCast(ae_slot)] = arg;
    ae_slot += 1;
    return 0;
}

fn call(p: ?*anyopaque) callconv(.c) void {
    const func: *const fn () callconv(.c) void = @ptrCast(@alignCast(p));
    func();
}

fn atexit(func: ?*const fn () callconv(.c) void) callconv(.c) c_int {
    return __cxa_atexit(call, @ptrCast(@constCast(func)), null);
}

fn abortImpl() callconv(.c) noreturn {
    _ = raise(@intFromEnum(linux.SIG.ABRT));

    // If we get here, SIGABRT was caught/blocked/ignored.
    // Block all signals, lock to prevent new handlers, reset SIGABRT to default,
    // then re-raise.
    __block_all_sigs(null);
    __lock(&__abort_lock);

    // Reset SIGABRT handler to SIG_DFL via rt_sigaction.
    const SIG_DFL: usize = 0;
    var sa: [4]usize = .{ SIG_DFL, 0, 0, 0 };
    _ = linux.syscall4(
        .rt_sigaction,
        @intFromEnum(linux.SIG.ABRT),
        @intFromPtr(&sa),
        0,
        linux.NSIG / 8,
    );

    // Send SIGABRT to this thread.
    _ = linux.tkill(linux.gettid(), linux.SIG.ABRT);

    // Unblock SIGABRT.
    const sigabrt_bit: usize = @as(usize, 1) << (@intFromEnum(linux.SIG.ABRT) - 1);
    const SIG_UNBLOCK: usize = 1;
    _ = linux.syscall4(
        .rt_sigprocmask,
        SIG_UNBLOCK,
        @intFromPtr(&sigabrt_bit),
        0,
        linux.NSIG / 8,
    );

    // Should be unreachable. Crash hard.
    _ = raise(@intFromEnum(linux.SIG.KILL));
    _Exit(127);
}

fn dummy() callconv(.c) void {}

fn libc_exit_fini() callconv(.c) void {
    const start: usize = @intFromPtr(&__fini_array_start);
    const end: usize = @intFromPtr(&__fini_array_end);
    const ptr_size = @sizeOf(*const fn () callconv(.c) void);
    var a: usize = end;
    while (a > start) {
        a -= ptr_size;
        const func: *const *const fn () callconv(.c) void = @ptrFromInt(a);
        func.*();
    }
    _finiStub();
}

fn exitImpl(code: c_int) callconv(.c) noreturn {
    __funcs_on_exit();
    libc_exit_fini();
    __stdio_exit();
    _Exit(code);
}

comptime { if (builtin.target.isMuslLibC()) symbol(&_finiStub, "_fini"); }
