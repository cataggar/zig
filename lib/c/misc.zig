const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&posix_openptLinux, "posix_openpt");
        symbol(&grantpt, "grantpt");
        symbol(&unlockptLinux, "unlockpt");
        symbol(&__ptsname_rLinux, "__ptsname_r");
        symbol(&__ptsname_rLinux, "ptsname_r");
    }
}

fn posix_openptLinux(flags: c_int) callconv(.c) c_int {
    const rc: isize = @bitCast(linux.open("/dev/ptmx", @bitCast(@as(u32, @bitCast(flags))), 0));
    if (rc < 0) {
        @branchHint(.unlikely);
        const e: u16 = @intCast(-rc);
        // Map ENOSPC to EAGAIN per POSIX.
        if (e == @intFromEnum(linux.E.NOSPC)) {
            std.c._errno().* = @intFromEnum(linux.E.AGAIN);
        } else {
            std.c._errno().* = @intCast(e);
        }
        return -1;
    }
    return @intCast(rc);
}

fn grantpt(_: c_int) callconv(.c) c_int {
    return 0;
}

fn unlockptLinux(fd: c_int) callconv(.c) c_int {
    var unlock: c_int = 0;
    return errno(linux.ioctl(@intCast(fd), linux.T.IOCSPTLCK, @intFromPtr(&unlock)));
}

fn __ptsname_rLinux(fd: c_int, buf: ?[*]u8, len: usize) callconv(.c) c_int {
    var pty: c_uint = undefined;
    const rc: isize = @bitCast(linux.ioctl(@intCast(fd), linux.T.IOCGPTN, @intFromPtr(&pty)));
    if (rc < 0) return @intCast(-rc);

    const b = buf orelse return @intFromEnum(linux.E.RANGE);

    const prefix = "/dev/pts/";
    if (len < prefix.len + 1) return @intFromEnum(linux.E.RANGE);
    @memcpy(b[0..prefix.len], prefix);

    // Format the pty number into the buffer after the prefix.
    var num_buf: [10]u8 = undefined;
    var num_len: usize = 0;
    var n: c_uint = pty;
    if (n == 0) {
        num_buf[0] = '0';
        num_len = 1;
    } else {
        while (n > 0) : (num_len += 1) {
            num_buf[num_len] = @intCast('0' + n % 10);
            n /= 10;
        }
        // Reverse.
        var lo: usize = 0;
        var hi: usize = num_len - 1;
        while (lo < hi) {
            const tmp = num_buf[lo];
            num_buf[lo] = num_buf[hi];
            num_buf[hi] = tmp;
            lo += 1;
            hi -= 1;
        }
    }

    if (prefix.len + num_len >= len) return @intFromEnum(linux.E.RANGE);
    @memcpy(b[prefix.len .. prefix.len + num_len], num_buf[0..num_len]);
    b[prefix.len + num_len] = 0;
    return 0;
}
