//! Windows (Win32) stubs for POSIX signal APIs that are declared by
//! `std.c` but have no provider in mingw-w64 (they are POSIX-only and
//! mingw deliberately omits them — `pthread_signal.h` even defines
//! `pthread_sigmask` as a no-op macro rather than a symbol).
//!
//! Issue #248 Phase 4. Goal: make every `std.c.sig*` / `kill` /
//! `pthread_sigmask` declaration link-resolvable on x86_64-windows-gnu
//! with sensible no-op or ENOSYS behaviour. Real Win32-backed signal
//! delivery (SetConsoleCtrlHandler / structured-exception mapping) is
//! intentionally out of scope — when POSIX callers rely on it they
//! get a clean ENOSYS rather than a link error or silent UB.
//!
//! `signal`, `raise`, and `abort` are intentionally left to ucrt.
//!
//! On Windows `std.c.sigset_t = u0` (zero-size), so set-manipulation
//! primitives have nothing to manipulate and always succeed.

const std = @import("std");
const builtin = @import("builtin");
const symbol = @import("../../c.zig").symbol;

fn setErrno(e: std.posix.E) c_int {
    std.c._errno().* = @intFromEnum(e);
    return -1;
}

// ---------- sigset manipulation (sigset_t is u0 on Windows) ----------

fn sigemptysetImpl(_: ?*anyopaque) callconv(.c) c_int {
    return 0;
}
fn sigfillsetImpl(_: ?*anyopaque) callconv(.c) c_int {
    return 0;
}
fn sigaddsetImpl(_: ?*anyopaque, _: c_int) callconv(.c) c_int {
    return 0;
}
fn sigdelsetImpl(_: ?*anyopaque, _: c_int) callconv(.c) c_int {
    return 0;
}
fn sigismemberImpl(_: ?*const anyopaque, _: c_int) callconv(.c) c_int {
    // sigset_t is empty on Windows; no signal is ever a member.
    return 0;
}
fn sigisemptysetImpl(_: ?*const anyopaque) callconv(.c) c_int {
    return 1;
}
fn sigandsetImpl(_: ?*anyopaque, _: ?*const anyopaque, _: ?*const anyopaque) callconv(.c) c_int {
    return 0;
}
fn sigorsetImpl(_: ?*anyopaque, _: ?*const anyopaque, _: ?*const anyopaque) callconv(.c) c_int {
    return 0;
}

// ---------- mask manipulation (no-ops; no signal delivery) ----------

fn sigprocmaskImpl(_: c_int, _: ?*const anyopaque, _: ?*anyopaque) callconv(.c) c_int {
    // oldset points to a u0; nothing to zero. Return success for legacy
    // POSIX code paths that only care about side-effect completion.
    return 0;
}
fn pthread_sigmaskImpl(_: c_int, _: ?*const anyopaque, _: ?*anyopaque) callconv(.c) c_int {
    // Matches mingw-w64 `pthread_signal.h` macro semantics.
    return 0;
}
fn sigpendingImpl(_: ?*anyopaque) callconv(.c) c_int {
    return 0;
}

// ---------- delivery / handler APIs (ENOSYS) ----------

fn sigactionStub(_: c_int, _: ?*const anyopaque, _: ?*anyopaque) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn sigaltstackStub(_: ?*const anyopaque, _: ?*anyopaque) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn sigsuspendStub(_: ?*const anyopaque) callconv(.c) c_int {
    // POSIX sigsuspend always returns -1 with errno=EINTR.
    return setErrno(.INTR);
}
fn sigwaitStub(_: ?*const anyopaque, sig: ?*c_int) callconv(.c) c_int {
    if (sig) |p| p.* = 0;
    // sigwait returns the errno value directly (not via errno).
    return @intFromEnum(std.posix.E.NOSYS);
}
fn sigtimedwaitStub(_: ?*const anyopaque, _: ?*anyopaque, _: ?*const anyopaque) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn sigwaitinfoStub(_: ?*const anyopaque, _: ?*anyopaque) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn sigqueueStub(_: c_int, _: c_int, _: usize) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn killStub(_: c_int, _: c_int) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn killpgStub(_: c_int, _: c_int) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn siginterruptImpl(_: c_int, _: c_int) callconv(.c) c_int {
    return 0;
}
fn sigholdStub(_: c_int) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn sigrelseStub(_: c_int) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn sigignoreStub(_: c_int) callconv(.c) c_int {
    return setErrno(.NOSYS);
}
fn sigpauseStub(_: c_int) callconv(.c) c_int {
    return setErrno(.INTR);
}
fn sigsetStub(_: c_int, _: ?*const anyopaque) callconv(.c) ?*const anyopaque {
    // SIG_ERR = (void*)-1
    return @ptrFromInt(std.math.maxInt(usize));
}

// ---------- signal descriptions ----------

fn strsignalImpl(sig: c_int) callconv(.c) [*:0]const u8 {
    return switch (sig) {
        1 => "Hangup",
        2 => "Interrupt",
        3 => "Quit",
        4 => "Illegal instruction",
        5 => "Trace/breakpoint trap",
        6 => "Aborted",
        7 => "Bus error",
        8 => "Floating point exception",
        9 => "Killed",
        10 => "User defined signal 1",
        11 => "Segmentation fault",
        12 => "User defined signal 2",
        13 => "Broken pipe",
        14 => "Alarm clock",
        15 => "Terminated",
        else => "Unknown signal",
    };
}
fn psignalImpl(_: c_int, _: ?[*:0]const u8) callconv(.c) void {
    // No-op: writing to stderr from a stub would pull in FILE*/fprintf
    // machinery for a rarely-used POSIX convenience. Callers that need
    // the message text can use strsignal() directly.
}
fn psiginfoImpl(_: ?*const anyopaque, _: ?[*:0]const u8) callconv(.c) void {}

comptime {
    // sigset manipulation
    symbol(&sigemptysetImpl, "sigemptyset");
    symbol(&sigfillsetImpl, "sigfillset");
    symbol(&sigaddsetImpl, "sigaddset");
    symbol(&sigdelsetImpl, "sigdelset");
    symbol(&sigismemberImpl, "sigismember");
    symbol(&sigisemptysetImpl, "sigisemptyset");
    symbol(&sigandsetImpl, "sigandset");
    symbol(&sigorsetImpl, "sigorset");

    // mask manipulation (no-ops)
    symbol(&sigprocmaskImpl, "sigprocmask");
    symbol(&pthread_sigmaskImpl, "pthread_sigmask");
    symbol(&sigpendingImpl, "sigpending");

    // delivery / handler (ENOSYS)
    symbol(&sigactionStub, "sigaction");
    symbol(&sigaltstackStub, "sigaltstack");
    symbol(&sigsuspendStub, "sigsuspend");
    symbol(&sigwaitStub, "sigwait");
    symbol(&sigtimedwaitStub, "sigtimedwait");
    symbol(&sigwaitinfoStub, "sigwaitinfo");
    symbol(&sigqueueStub, "sigqueue");
    symbol(&killStub, "kill");
    symbol(&killpgStub, "killpg");
    symbol(&siginterruptImpl, "siginterrupt");
    symbol(&sigholdStub, "sighold");
    symbol(&sigrelseStub, "sigrelse");
    symbol(&sigignoreStub, "sigignore");
    symbol(&sigpauseStub, "sigpause");
    symbol(&sigsetStub, "sigset");

    // descriptions
    symbol(&strsignalImpl, "strsignal");
    symbol(&psignalImpl, "psignal");
    symbol(&psiginfoImpl, "psiginfo");
}
