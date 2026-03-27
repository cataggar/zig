const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&getloadavgLinux, "getloadavg");
        symbol(&daemonLinux, "daemon");
    }
}

const SI_LOAD_SHIFT = 16;

fn getloadavgLinux(a: [*]f64, n: c_int) callconv(.c) c_int {
    if (n <= 0) return if (n != 0) -1 else 0;
    var si: linux.Sysinfo = undefined;
    _ = linux.sysinfo(&si);
    const count: usize = if (n > 3) 3 else @intCast(n);
    for (0..count) |i| {
        a[i] = @as(f64, @floatFromInt(si.loads[i])) / @as(f64, @floatFromInt(@as(u64, 1) << SI_LOAD_SHIFT));
    }
    return @intCast(count);
}

fn daemonLinux(nochdir: c_int, noclose: c_int) callconv(.c) c_int {
    if (nochdir == 0) {
        if (errno(linux.chdir("/")) < 0) return -1;
    }

    if (noclose == 0) {
        const rc: isize = @bitCast(linux.open("/dev/null", .{ .ACCMODE = .RDWR }, 0));
        if (rc < 0) {
            @branchHint(.unlikely);
            std.c._errno().* = @intCast(-rc);
            return -1;
        }
        const fd: i32 = @intCast(rc);
        var failed = false;
        if (@as(isize, @bitCast(linux.dup2(fd, 0))) < 0) failed = true;
        if (@as(isize, @bitCast(linux.dup2(fd, 1))) < 0) failed = true;
        if (@as(isize, @bitCast(linux.dup2(fd, 2))) < 0) failed = true;
        if (fd > 2) _ = linux.close(fd);
        if (failed) return -1;
    }

    // First fork.
    const f1: isize = @bitCast(linux.fork());
    if (f1 < 0) return -1;
    if (f1 > 0) linux.exit_group(0);

    if (@as(isize, @bitCast(linux.setsid())) < 0) return -1;

    // Second fork.
    const f2: isize = @bitCast(linux.fork());
    if (f2 < 0) return -1;
    if (f2 > 0) linux.exit_group(0);

    return 0;
}
