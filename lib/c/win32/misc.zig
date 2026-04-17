//! Windows (Win32) implementations / stubs for the remaining Linux-
//! flavoured APIs declared by std.c: dynamic loading, passwd/group,
//! and login identity.
//!
//! Issue #248 Phase 8. Weak symbol() exports throughout.
//!
//! Real implementations:
//!   * dlopen/dlsym/dlclose: LoadLibraryA / GetProcAddress /
//!     FreeLibrary. mingw-w64 does not ship a libdl emulation, so
//!     these are the canonical providers.
//!   * dlerror: returns a thread-local string filled by the last
//!     failed dlopen/dlsym/dlclose.
//!
//! Stubs:
//!   * passwd/group lookups: `std.c.passwd` / `std.c.group` are
//!     `void` on Windows, so we cannot populate fields; all lookup
//!     functions return null. `_r` variants return ENOSYS.
//!   * getlogin/getlogin_r: GetUserNameA via advapi32 when
//!     available; best-effort.
//!
//! Deferred to a later phase:
//!   * locale / multibyte: ucrt provides these; vendoring musl's
//!     port would conflict with ucrt's locale id space.
//!   * mq_*, msgsnd, etc.: not declared in std.c.

const std = @import("std");
const windows = std.os.windows;
const symbol = @import("../../c.zig").symbol;

fn setErrno(e: std.posix.E) c_int {
    std.c._errno().* = @intFromEnum(e);
    return -1;
}

// ---------- dynamic loading ----------

extern "kernel32" fn LoadLibraryA(lpLibFileName: [*:0]const u8) callconv(.winapi) ?windows.HMODULE;
extern "kernel32" fn GetModuleHandleA(lpModuleName: ?[*:0]const u8) callconv(.winapi) ?windows.HMODULE;
extern "kernel32" fn GetProcAddress(hModule: windows.HMODULE, lpProcName: [*:0]const u8) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn FreeLibrary(hLibModule: windows.HMODULE) callconv(.winapi) windows.BOOL;
extern "kernel32" fn GetLastError() callconv(.winapi) windows.DWORD;
extern "kernel32" fn FormatMessageA(
    dwFlags: windows.DWORD,
    lpSource: ?*const anyopaque,
    dwMessageId: windows.DWORD,
    dwLanguageId: windows.DWORD,
    lpBuffer: [*]u8,
    nSize: windows.DWORD,
    Arguments: ?*anyopaque,
) callconv(.winapi) windows.DWORD;

const FORMAT_MESSAGE_FROM_SYSTEM: windows.DWORD = 0x00001000;
const FORMAT_MESSAGE_IGNORE_INSERTS: windows.DWORD = 0x00000200;

// Thread-local error buffer for dlerror().
threadlocal var dlerror_buf: [256]u8 = undefined;
threadlocal var dlerror_set: bool = false;

fn setDlerror(prefix: []const u8) void {
    const err = GetLastError();
    var tail: [128]u8 = undefined;
    const n = FormatMessageA(
        FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        null,
        err,
        0,
        &tail,
        tail.len,
        null,
    );
    const tail_slice: []const u8 = if (n > 0) tail[0..n] else "unknown error";
    const fmt = std.fmt.bufPrint(&dlerror_buf, "{s}: {s}\x00", .{ prefix, tail_slice }) catch
        std.fmt.bufPrint(&dlerror_buf, "{s}\x00", .{prefix}) catch blk: {
            dlerror_buf[0] = 0;
            break :blk dlerror_buf[0..0];
        };
    _ = fmt;
    dlerror_set = true;
}

fn dlopenImpl(path: ?[*:0]const u8, _: c_int) callconv(.c) ?*anyopaque {
    const h: ?windows.HMODULE = if (path) |p| LoadLibraryA(p) else GetModuleHandleA(null);
    if (h == null) {
        setDlerror("dlopen");
        return null;
    }
    return @ptrCast(h);
}

fn dlsymImpl(handle: ?*anyopaque, sym: [*:0]const u8) callconv(.c) ?*anyopaque {
    const h: windows.HMODULE = if (handle) |p| @ptrCast(p) else (GetModuleHandleA(null) orelse {
        setDlerror("dlsym");
        return null;
    });
    const addr = GetProcAddress(h, sym);
    if (addr == null) setDlerror("dlsym");
    return addr;
}

fn dlcloseImpl(handle: *anyopaque) callconv(.c) c_int {
    const h: windows.HMODULE = @ptrCast(handle);
    if (FreeLibrary(h) == .FALSE) {
        setDlerror("dlclose");
        return -1;
    }
    return 0;
}

fn dlerrorImpl() callconv(.c) ?[*:0]u8 {
    if (!dlerror_set) return null;
    dlerror_set = false;
    return @ptrCast(&dlerror_buf);
}

// ---------- passwd / group (null on Windows) ----------

fn getpwuidStub(_: u32) callconv(.c) ?*anyopaque {
    return null;
}
fn getpwnamStub(_: [*:0]const u8) callconv(.c) ?*anyopaque {
    return null;
}
fn getpwentStub() callconv(.c) ?*anyopaque {
    return null;
}
fn setpwentStub() callconv(.c) void {}
fn endpwentStub() callconv(.c) void {}
fn getpwuid_rStub(_: u32, _: ?*anyopaque, _: [*]u8, _: usize, result: *?*anyopaque) callconv(.c) c_int {
    result.* = null;
    return 0; // POSIX: not-found is not an error for _r variants.
}
fn getpwnam_rStub(_: [*:0]const u8, _: ?*anyopaque, _: [*]u8, _: usize, result: *?*anyopaque) callconv(.c) c_int {
    result.* = null;
    return 0;
}

fn getgrgidStub(_: u32) callconv(.c) ?*anyopaque {
    return null;
}
fn getgrnamStub(_: [*:0]const u8) callconv(.c) ?*anyopaque {
    return null;
}
fn getgrentStub() callconv(.c) ?*anyopaque {
    return null;
}
fn setgrentStub() callconv(.c) void {}
fn endgrentStub() callconv(.c) void {}
fn getgrgid_rStub(_: u32, _: ?*anyopaque, _: [*]u8, _: usize, result: *?*anyopaque) callconv(.c) c_int {
    result.* = null;
    return 0;
}
fn getgrnam_rStub(_: [*:0]const u8, _: ?*anyopaque, _: [*]u8, _: usize, result: *?*anyopaque) callconv(.c) c_int {
    result.* = null;
    return 0;
}
fn getgroupsStub(_: c_int, _: ?*anyopaque) callconv(.c) c_int {
    return 0;
}
fn initgroupsStub(_: [*:0]const u8, _: u32) callconv(.c) c_int {
    return setErrno(.NOSYS);
}

// ---------- login identity ----------

extern "advapi32" fn GetUserNameA(lpBuffer: [*]u8, pcbBuffer: *windows.DWORD) callconv(.winapi) windows.BOOL;

threadlocal var login_buf: [256]u8 = undefined;

fn getloginImpl() callconv(.c) ?[*:0]u8 {
    var size: windows.DWORD = login_buf.len;
    if (GetUserNameA(&login_buf, &size) == .FALSE) return null;
    return @ptrCast(&login_buf);
}

fn getlogin_rImpl(buf: [*]u8, buflen: usize) callconv(.c) c_int {
    if (buflen == 0) return @intFromEnum(std.posix.E.INVAL);
    var size: windows.DWORD = @intCast(@min(buflen, std.math.maxInt(windows.DWORD)));
    if (GetUserNameA(buf, &size) == .FALSE) return @intFromEnum(std.posix.E.RANGE);
    return 0;
}

comptime {
    // dynamic loading (real impls)
    symbol(&dlopenImpl, "dlopen");
    symbol(&dlsymImpl, "dlsym");
    symbol(&dlcloseImpl, "dlclose");
    symbol(&dlerrorImpl, "dlerror");

    // passwd
    symbol(&getpwuidStub, "getpwuid");
    symbol(&getpwnamStub, "getpwnam");
    symbol(&getpwentStub, "getpwent");
    symbol(&setpwentStub, "setpwent");
    symbol(&endpwentStub, "endpwent");
    symbol(&getpwuid_rStub, "getpwuid_r");
    symbol(&getpwnam_rStub, "getpwnam_r");

    // group
    symbol(&getgrgidStub, "getgrgid");
    symbol(&getgrnamStub, "getgrnam");
    symbol(&getgrentStub, "getgrent");
    symbol(&setgrentStub, "setgrent");
    symbol(&endgrentStub, "endgrent");
    symbol(&getgrgid_rStub, "getgrgid_r");
    symbol(&getgrnam_rStub, "getgrnam_r");
    symbol(&getgroupsStub, "getgrouplist");
    symbol(&initgroupsStub, "initgroups");

    // login
    symbol(&getloginImpl, "getlogin");
    symbol(&getlogin_rImpl, "getlogin_r");
}
