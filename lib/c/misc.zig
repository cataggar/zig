const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&syscall_fn, "syscall");
    }
}

fn syscall_fn(n: c_long, ...) callconv(.c) c_long {
    var ap = @cVaStart();
    const a = @cVaArg(&ap, usize);
    const b = @cVaArg(&ap, usize);
    const c = @cVaArg(&ap, usize);
    const d = @cVaArg(&ap, usize);
    const e = @cVaArg(&ap, usize);
    const f = @cVaArg(&ap, usize);
    @cVaEnd(&ap);

    const rc = linux.syscall6(
        @enumFromInt(@as(usize, @bitCast(@as(isize, n)))),
        a,
        b,
        c,
        d,
        e,
        f,
    );

    const signed: isize = @bitCast(rc);
    if (signed < 0 and signed > -4096) {
        std.c._errno().* = @intCast(-signed);
        return -1;
    }
    return @intCast(signed);
}
