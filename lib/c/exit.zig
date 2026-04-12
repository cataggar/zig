const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

var abort_lock: c_int = 0;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&abort_lock, "__abort_lock");
    }
}
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&_ExitLinux, "_Exit");
    }
}

fn _ExitLinux(exit_code: c_int) callconv(.c) noreturn {
    linux.exit_group(exit_code);
comptime {
    if (builtin.link_libc) {
        symbol(&quick_exit, "quick_exit");
    }
}

extern "c" fn __funcs_on_quick_exit() void;
extern "c" fn _Exit(code: c_int) noreturn;

fn quick_exit(code: c_int) callconv(.c) noreturn {
    __funcs_on_quick_exit();
    _Exit(code);
}
const std = @import("std");

const symbol = @import("../c.zig").symbol;

// Internal musl lock functions (provided by the thread subsystem).
extern "c" fn __lock(lock: *c_int) void;
extern "c" fn __unlock(lock: *c_int) void;

// C library functions used by atexit.
extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;

const COUNT = 32;

// ── at_quick_exit ──────────────────────────────────────────────────────

var qe_funcs: [COUNT]?*const fn () callconv(.c) void = .{null} ** COUNT;
var qe_count: c_int = 0;
var qe_lock: c_int = 0;

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

// ── atexit ─────────────────────────────────────────────────────────────

const FuncList = extern struct {
    next: ?*FuncList,
    f: [COUNT]?*const fn (?*anyopaque) callconv(.c) void,
    a: [COUNT]?*anyopaque,
};

var ae_builtin: FuncList = std.mem.zeroes(FuncList);
var ae_head: ?*FuncList = null;
var ae_slot: c_int = 0;
var ae_lock: c_int = 0;

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

comptime {
    if (builtin.link_libc) {
        symbol(&__funcs_on_quick_exit, "__funcs_on_quick_exit");
        symbol(&at_quick_exit, "at_quick_exit");
        symbol(&__funcs_on_exit, "__funcs_on_exit");
        symbol(&__cxa_finalize, "__cxa_finalize");
        symbol(&__cxa_atexit, "__cxa_atexit");
        symbol(&atexit, "atexit");
        symbol(&qe_lock, "__at_quick_exit_lockptr");
        symbol(&ae_lock, "__atexit_lockptr");
    }
}
