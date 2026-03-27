const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&getrusageLinux, "getrusage");
        symbol(&getentropyLinux, "getentropy");
    }
}

fn getrusageLinux(who: c_int, usage: *linux.rusage) callconv(.c) c_int {
    return errno(linux.getrusage(who, usage));
}

fn getentropyLinux(buffer: [*]u8, len: usize) callconv(.c) c_int {
    if (len > 256) {
        std.c._errno().* = @intFromEnum(linux.E.IO);
        return -1;
    }
    var pos: usize = 0;
    while (pos < len) {
        const rc: isize = @bitCast(linux.getrandom(buffer + pos, len - pos, 0));
        if (rc < 0) {
            @branchHint(.unlikely);
            if (-rc == @intFromEnum(linux.E.INTR)) continue;
            std.c._errno().* = @intCast(-rc);
            return -1;
        }
        pos += @intCast(rc);
    }
    return 0;
}
