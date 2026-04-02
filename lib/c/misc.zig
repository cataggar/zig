const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const c = @import("../c.zig");

comptime {
    if (builtin.target.isMuslLibC()) {
        c.symbol(&getresuidLinux, "getresuid");
        c.symbol(&getresgidLinux, "getresgid");

        c.symbol(&getentropyLinux, "getentropy");

        c.symbol(&getpriorityLinux, "getpriority");
        c.symbol(&setpriorityLinux, "setpriority");

        c.symbol(&setdomainnameLinux, "setdomainname");

        c.symbol(&getrlimitLinux, "getrlimit");
        c.symbol(&getrlimitLinux, "getrlimit64");

        c.symbol(&getrusageLinux, "getrusage");
    }
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        c.symbol(&gethostidImpl, "gethostid");

        c.symbol(&a64l, "a64l");
        c.symbol(&l64a, "l64a");

        c.symbol(&basenameImpl, "basename");
        c.symbol(&basenameImpl, "__xpg_basename");

        c.symbol(&dirnameImpl, "dirname");
    }
}

fn getresuidLinux(ruid: *linux.uid_t, euid: *linux.uid_t, suid: *linux.uid_t) callconv(.c) c_int {
    return c.errno(linux.getresuid(ruid, euid, suid));
}

fn getresgidLinux(rgid: *linux.gid_t, egid: *linux.gid_t, sgid: *linux.gid_t) callconv(.c) c_int {
    return c.errno(linux.getresgid(rgid, egid, sgid));
}

fn getentropyLinux(buffer: [*]u8, len: usize) callconv(.c) c_int {
    if (len > 256) {
        std.c._errno().* = @intFromEnum(linux.E.IO);
        return -1;
    }
    var pos = buffer;
    var remaining = len;
    while (remaining > 0) {
        const ret: isize = @bitCast(linux.getrandom(pos, remaining, 0));
        if (ret < 0) {
            if (-ret == @intFromEnum(linux.E.INTR)) continue;
            std.c._errno().* = @intCast(@as(usize, @bitCast(-ret)));
            return -1;
        }
        const n: usize = @intCast(ret);
        pos += n;
        remaining -= n;
    }
    return 0;
}

fn gethostidImpl() callconv(.c) c_long {
    return 0;
}

fn getpriorityLinux(which: c_int, who: c_uint) callconv(.c) c_int {
    const ret = linux.syscall2(.getpriority, @as(usize, @bitCast(@as(isize, which))), @as(usize, who));
    const signed: isize = @bitCast(ret);
    if (signed < 0) {
        @branchHint(.unlikely);
        std.c._errno().* = @intCast(-signed);
        return -1;
    }
    return 20 - @as(c_int, @intCast(signed));
}

fn setpriorityLinux(which: c_int, who: c_uint, prio: c_int) callconv(.c) c_int {
    return c.errno(linux.syscall3(.setpriority, @as(usize, @bitCast(@as(isize, which))), @as(usize, who), @as(usize, @bitCast(@as(isize, prio)))));
}

fn setdomainnameLinux(name: [*]const u8, len: usize) callconv(.c) c_int {
    return c.errno(linux.syscall2(.setdomainname, @intFromPtr(name), len));
}

fn getrlimitLinux(resource: c_int, rlim: *linux.rlimit) callconv(.c) c_int {
    return c.errno(linux.prlimit(@as(linux.pid_t, 0), @enumFromInt(@as(u7, @intCast(@as(u32, @bitCast(resource))))), null, rlim));
}

fn getrusageLinux(who: c_int, ru: *linux.rusage) callconv(.c) c_int {
    return c.errno(linux.getrusage(who, ru));
}

const digits = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

fn a64l(s: [*:0]const u8) callconv(.c) c_long {
    var x: u32 = 0;
    var ptr = s;
    var e: u6 = 0;
    while (e < 36 and ptr[0] != 0) : ({
        e += 6;
        ptr += 1;
    }) {
        const ch = ptr[0];
        const d = std.mem.indexOfScalar(u8, digits, ch) orelse break;
        x |= @as(u32, @intCast(d)) << @as(u5, @intCast(e));
    }
    return @as(c_long, @as(i32, @bitCast(x)));
}

fn l64a(x0: c_long) callconv(.c) [*:0]u8 {
    const buf = struct {
        var s: [7]u8 = undefined;
    };
    var x: u32 = @truncate(@as(u64, @bitCast(@as(i64, x0))));
    var i: usize = 0;
    while (x != 0) : (i += 1) {
        buf.s[i] = digits[x & 63];
        x >>= 6;
    }
    buf.s[i] = 0;
    return buf.s[0..i :0].ptr;
}

fn basenameImpl(s: ?[*:0]u8) callconv(.c) [*:0]u8 {
    const dot: *const [2:0]u8 = ".";

    const str = s orelse return @constCast(@ptrCast(dot));
    if (str[0] == 0) return @constCast(@ptrCast(dot));

    var i = std.mem.len(str) - 1;

    // Strip trailing slashes
    while (i > 0 and str[i] == '/') {
        str[i] = 0;
        i -= 1;
    }

    // Find last component
    while (i > 0 and str[i - 1] != '/') {
        i -= 1;
    }

    return str + i;
}

fn dirnameImpl(s: ?[*:0]u8) callconv(.c) [*:0]u8 {
    const dot: *const [2:0]u8 = ".";
    const slash: *const [2:0]u8 = "/";

    const str = s orelse return @constCast(@ptrCast(dot));
    if (str[0] == 0) return @constCast(@ptrCast(dot));

    var i = std.mem.len(str) - 1;

    // Strip trailing slashes
    while (str[i] == '/') {
        if (i == 0) return @constCast(@ptrCast(slash));
        i -= 1;
    }

    // Skip non-slash component
    while (str[i] != '/') {
        if (i == 0) return @constCast(@ptrCast(dot));
        i -= 1;
    }

    // Strip trailing slashes from directory part
    while (str[i] == '/') {
        if (i == 0) return @constCast(@ptrCast(slash));
        i -= 1;
    }

    str[i + 1] = 0;
    return str;
}
