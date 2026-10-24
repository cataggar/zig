const builtin = @import("builtin");
const std = @import("std");
const c = @import("../c.zig");

// syscall_ret.c — syscall return value to errno conversion
fn syscall_retLinux(r: c_ulong) callconv(.c) c_long {
    const signed_r: c_long = @bitCast(r);
    if (signed_r >= -4095 and signed_r < 0) {
        std.c._errno().* = @intCast(-signed_r);
        return -1;
    }
    return signed_r;
}

// procfdname.c — /proc/self/fd/N path builder
fn procfdnameLinux(buf: [*]u8, fd: c_uint) callconv(.c) void {
    const prefix = "/proc/self/fd/";
    @memcpy(buf[0..prefix.len], prefix);
    var i: usize = prefix.len;
    if (fd == 0) {
        buf[i] = '0';
        buf[i + 1] = 0;
        return;
    }
    var j: c_uint = fd;
    while (j != 0) : (j /= 10) {
        i += 1;
    }
    buf[i] = 0;
    var remaining: c_uint = fd;
    while (remaining != 0) : (remaining /= 10) {
        i -= 1;
        buf[i] = '0' + @as(u8, @intCast(remaining % 10));
    }
}

// version.c — musl version string
const libc_version: [5:0]u8 = "1.2.5".*;

// defsysinfo.c — vDSO pointer
var sysinfo: usize = 0;

// libc.c — libc struct initialization and globals
const LibcStruct = extern struct {
    can_do_threads: u8,
    threaded: u8,
    secure: u8,
    need_locks: i8,
    threads_minus_1: c_int,
    auxv: ?[*]usize,
    tls_head: ?*anyopaque,
    tls_size: usize,
    tls_align: usize,
    tls_cnt: usize,
    page_size: usize,
    global_locale: extern struct {
        cat: [6]?*const anyopaque,
    },
};

var libc_struct: LibcStruct = std.mem.zeroes(LibcStruct);
var hwcap: usize = 0;
var progname: ?[*]u8 = null;
var progname_full: ?[*]u8 = null;

comptime {
    if (builtin.target.isMuslLibC()) {
        c.symbol(&syscall_retLinux, "__syscall_ret");
        c.symbol(&procfdnameLinux, "__procfdname");

        @export(&libc_version, .{ .name = "__libc_version", .linkage = .weak, .visibility = .hidden });
        @export(&sysinfo, .{ .name = "__sysinfo", .linkage = .weak, .visibility = .hidden });

        @export(&libc_struct, .{ .name = "__libc", .linkage = .weak, .visibility = .hidden });
        @export(&hwcap, .{ .name = "__hwcap", .linkage = .weak, .visibility = .hidden });
        @export(&progname, .{ .name = "__progname", .linkage = .weak, .visibility = .default });
        @export(&progname_full, .{ .name = "__progname_full", .linkage = .weak, .visibility = .default });
        @export(&progname, .{ .name = "program_invocation_short_name", .linkage = .weak, .visibility = .default });
        @export(&progname_full, .{ .name = "program_invocation_name", .linkage = .weak, .visibility = .default });
    }
}

test procfdnameLinux {
    var buf: [32]u8 = undefined;

    procfdnameLinux(&buf, 0);
    try std.testing.expectEqualStrings("/proc/self/fd/0", std.mem.sliceTo(&buf, 0));

    procfdnameLinux(&buf, 1);
    try std.testing.expectEqualStrings("/proc/self/fd/1", std.mem.sliceTo(&buf, 0));

    procfdnameLinux(&buf, 42);
    try std.testing.expectEqualStrings("/proc/self/fd/42", std.mem.sliceTo(&buf, 0));

    procfdnameLinux(&buf, 12345);
    try std.testing.expectEqualStrings("/proc/self/fd/12345", std.mem.sliceTo(&buf, 0));

    procfdnameLinux(&buf, 999999999);
    try std.testing.expectEqualStrings("/proc/self/fd/999999999", std.mem.sliceTo(&buf, 0));
}
