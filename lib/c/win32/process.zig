//! Windows (Win32) stubs for POSIX process/identity APIs that are
//! declared by `std.c` but have no provider in mingw-w64 / ucrt.
//!
//! Issue #248 Phase 6. Goal: make every Unix-only symbol that
//! `std.c` declares as `extern "c"` link-resolvable on
//! x86_64-windows-gnu with sensible no-op / single-user /
//! ENOSYS semantics.
//!
//! All exports are weak (`symbol()`), so mingw / ucrt wins when it
//! provides a real implementation (e.g. `getpid`, `getenv`, `link`-
//! like operations via msvcrt `_*` variants with mingwex aliases).
//! Our fallbacks only bind when the platform has nothing to offer.
//!
//! Windows has only one logical user from a POSIX perspective, so:
//!
//! * `getuid`/`geteuid`/`getgid`/`getegid`   -> 0
//! * `setuid`/`seteuid`/`setgid`/`setegid`   -> 0 (no-op success)
//!
//! Everything requiring multi-process Unix semantics (fork, wait,
//! sessions, process groups) returns ENOSYS so callers get a clean
//! POSIX-style error rather than UB.

const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const symbol = @import("../../c.zig").symbol;

fn setErrno(e: std.posix.E) c_int {
    std.c._errno().* = @intFromEnum(e);
    return -1;
}

// ---------- identity (single-user) ----------

fn getuidImpl() callconv(.c) u32 {
    return 0;
}
fn geteuidImpl() callconv(.c) u32 {
    return 0;
}
fn getgidImpl() callconv(.c) u32 {
    return 0;
}
fn getegidImpl() callconv(.c) u32 {
    return 0;
}
fn setuidImpl(_: u32) callconv(.c) c_int {
    return 0;
}
fn seteuidImpl(_: u32) callconv(.c) c_int {
    return 0;
}
fn setgidImpl(_: u32) callconv(.c) c_int {
    return 0;
}
fn setegidImpl(_: u32) callconv(.c) c_int {
    return 0;
}
fn getgroupsImpl(_: c_int, _: ?*anyopaque) callconv(.c) c_int {
    return 0;
}
fn setgroupsImpl(_: usize, _: ?*const anyopaque) callconv(.c) c_int {
    return 0;
}

// ---------- sessions / process groups (ENOSYS) ----------

fn getppidImpl() callconv(.c) c_int {
    return 0;
}
fn setsidImpl() callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn getsidImpl(_: c_int) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn setpgidImpl(_: c_int, _: c_int) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn getpgidImpl(_: c_int) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn getpgrpImpl() callconv(.c) c_int {
    return 0;
}
fn setpgrpImpl() callconv(.c) c_int {
    return setErrno(.NOSYS);
}

// ---------- fork / wait (ENOSYS) ----------

fn forkStub() callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn vforkStub() callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn waitStub(_: ?*c_int) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn waitpidStub(_: c_int, _: ?*c_int, _: c_int) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn wait3Stub(_: ?*c_int, _: c_int, _: ?*anyopaque) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn wait4Stub(_: c_int, _: ?*c_int, _: c_int, _: ?*anyopaque) callconv(.c) c_int {
    return setErrno(.NOSYS);
}

// ---------- hostname ----------

fn gethostnameImpl(name: ?[*]u8, len: usize) callconv(.c) c_int {
    if (name == null or len == 0) return setErrno(.INVAL);

    // GetComputerNameExA with ComputerNamePhysicalDnsHostname gives the
    // short hostname — closest analog to POSIX gethostname() which
    // returns the nodename (not the FQDN).
    var size: u32 = @intCast(@min(len, std.math.maxInt(u32)));
    const ok = GetComputerNameExA(
        COMPUTER_NAME_FORMAT.PhysicalDnsHostname,
        name.?,
        &size,
    );
    if (ok == .FALSE) return setErrno(.NAMETOOLONG);

    // Ensure NUL-termination inside the caller's buffer even if the OS
    // didn't include one (it does, but defence in depth).
    if (size < len) name.?[size] = 0 else name.?[len - 1] = 0;
    return 0;
}

fn sethostnameStub(_: ?*const anyopaque, _: usize) callconv(.c) c_int {
    return setErrno(.PERM);
}

const COMPUTER_NAME_FORMAT = enum(c_int) {
    NetBIOS = 0,
    DnsHostname = 1,
    DnsDomain = 2,
    DnsFullyQualified = 3,
    PhysicalNetBIOS = 4,
    PhysicalDnsHostname = 5,
    PhysicalDnsDomain = 6,
    PhysicalDnsFullyQualified = 7,
};

extern "kernel32" fn GetComputerNameExA(
    NameType: COMPUTER_NAME_FORMAT,
    lpBuffer: [*]u8,
    nSize: *u32,
) callconv(.winapi) windows.BOOL;

// ---------- symlink / hardlink (prefer mingw; fallback ENOSYS) ----------
//
// mingw-w64 libmingwex provides `symlink`, `readlink`, `link` via
// wrappers around `CreateSymbolicLinkW` / `DeviceIoControl` /
// `CreateHardLinkW`. Our weak exports are last-resort ENOSYS in case
// a particular mingw build omits them.

fn symlinkStub(_: [*:0]const u8, _: [*:0]const u8) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn readlinkStub(_: [*:0]const u8, _: [*]u8, _: usize) callconv(.c) isize {
    _ = setErrno(.NOSYS);
    return -1;
}
fn linkStub(_: [*:0]const u8, _: [*:0]const u8) callconv(.c) c_int {
    return setErrno(.NOSYS);
}

// ---------- misc (POSIX-only signals-adjacent) ----------

fn pauseStub() callconv(.c) c_int {
    return setErrno(.INTR);
}
fn nice_stub(_: c_int) callconv(.c) c_int {
    return setErrno(.NOSYS);
}

comptime {
    // identity
    symbol(&getuidImpl, "getuid");
    symbol(&geteuidImpl, "geteuid");
    symbol(&getgidImpl, "getgid");
    symbol(&getegidImpl, "getegid");
    symbol(&setuidImpl, "setuid");
    symbol(&seteuidImpl, "seteuid");
    symbol(&setgidImpl, "setgid");
    symbol(&setegidImpl, "setegid");
    symbol(&getgroupsImpl, "getgroups");
    symbol(&setgroupsImpl, "setgroups");

    // sessions / process groups
    symbol(&getppidImpl, "getppid");
    symbol(&setsidImpl, "setsid");
    symbol(&getsidImpl, "getsid");
    symbol(&setpgidImpl, "setpgid");
    symbol(&getpgidImpl, "getpgid");
    symbol(&getpgrpImpl, "getpgrp");
    symbol(&setpgrpImpl, "setpgrp");

    // fork / wait
    symbol(&forkStub, "fork");
    symbol(&vforkStub, "vfork");
    symbol(&waitStub, "wait");
    symbol(&waitpidStub, "waitpid");
    symbol(&wait3Stub, "wait3");
    symbol(&wait4Stub, "wait4");

    // hostname
    symbol(&gethostnameImpl, "gethostname");
    symbol(&sethostnameStub, "sethostname");

    // symlink / hardlink (fallbacks)
    symbol(&symlinkStub, "symlink");
    symbol(&readlinkStub, "readlink");
    symbol(&linkStub, "link");

    // misc
    symbol(&pauseStub, "pause");
    symbol(&nice_stub, "nice");
}
