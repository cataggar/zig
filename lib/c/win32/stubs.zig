//! Windows (Win32) ENOSYS stubs for Linux-only POSIX APIs that are
//! declared in std.c but have no analog in mingw-w64 / ucrt and are
//! not worth semantic-porting on the current iteration.
//!
//! Issue #248 Phase 7. Purpose is link resolution + clean POSIX
//! errno for callers. All exports are weak (`symbol()`) so any real
//! implementation (from mingw, winpthreads, or a future libzigc
//! phase) overrides.
//!
//! Covered:
//!   * POSIX shared memory (`shm_open`/`shm_unlink`) — Windows uses
//!     named file mappings; a real shim would go in a future phase.
//!   * Socket extensions not in WinSock2: `accept4`, `socketpair`,
//!     `sendmmsg`.
//!   * `sendfile` (Linux-only syscall — there's `TransmitFile` on
//!     Windows but it's socket-specific and not a drop-in).
//!
//! Not covered here (handled elsewhere or left to mingw):
//!   * Core socket APIs (`socket`/`bind`/`listen`/...) — callers on
//!     Windows link `-lws2_32`; ws2_32 exports them with matching
//!     names + cdecl.
//!   * `sem_*` — provided by libwinpthread today; will be replaced
//!     when Phase 3 lands.
//!   * `mq_*`, `msgget`/`shmget`/`semget` — not declared in std.c.

const std = @import("std");
const symbol = @import("../../c.zig").symbol;

fn setErrno(e: std.posix.E) c_int {
    std.c._errno().* = @intFromEnum(e);
    return -1;
}

// ---------- POSIX shared memory ----------

fn shm_openStub(_: [*:0]const u8, _: c_int, _: c_uint) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn shm_unlinkStub(_: [*:0]const u8) callconv(.c) c_int {
    return setErrno(.NOSYS);
}

// ---------- socket extensions ----------

fn accept4Stub(_: c_int, _: ?*anyopaque, _: ?*anyopaque, _: c_uint) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn socketpairStub(_: c_uint, _: c_uint, _: c_uint, _: *[2]c_int) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn sendmmsgStub(_: c_int, _: ?*anyopaque, _: c_uint, _: u32) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn recvmmsgStub(_: c_int, _: ?*anyopaque, _: c_uint, _: u32, _: ?*anyopaque) callconv(.c) c_int {
    return setErrno(.NOSYS);
}

// ---------- linux-only file ops ----------

fn sendfileStub(_: c_int, _: c_int, _: ?*anyopaque, _: usize) callconv(.c) isize {
    _ = setErrno(.NOSYS);
    return -1;
}
fn sendfile64Stub(_: c_int, _: c_int, _: ?*anyopaque, _: usize) callconv(.c) isize {
    _ = setErrno(.NOSYS);
    return -1;
}
fn copy_file_rangeStub(_: c_int, _: ?*anyopaque, _: c_int, _: ?*anyopaque, _: usize, _: c_uint) callconv(.c) isize {
    _ = setErrno(.NOSYS);
    return -1;
}

comptime {
    symbol(&shm_openStub, "shm_open");
    symbol(&shm_unlinkStub, "shm_unlink");

    symbol(&accept4Stub, "accept4");
    symbol(&socketpairStub, "socketpair");
    symbol(&sendmmsgStub, "sendmmsg");
    symbol(&recvmmsgStub, "recvmmsg");

    symbol(&sendfileStub, "sendfile");
    symbol(&sendfile64Stub, "sendfile64");
    symbol(&copy_file_rangeStub, "copy_file_range");
}
