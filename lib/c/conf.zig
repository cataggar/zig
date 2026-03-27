const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&fpathconf, "fpathconf");
        symbol(&pathconf, "pathconf");
    }
    if (builtin.target.isWasiLibC()) {
        symbol(&fpathconf, "fpathconf");
        symbol(&pathconf, "pathconf");
    }
}

// POSIX limit values
const _POSIX_LINK_MAX = 8;
const _POSIX_MAX_CANON = 255;
const _POSIX_MAX_INPUT = 255;
const NAME_MAX = 255;
const PATH_MAX = 4096;
const PIPE_BUF = 4096;
const FILESIZEBITS = 64;

// _PC_ index values (from POSIX / musl unistd.h)
const values = [21]c_short{
    _POSIX_LINK_MAX, // _PC_LINK_MAX = 0
    _POSIX_MAX_CANON, // _PC_MAX_CANON = 1
    _POSIX_MAX_INPUT, // _PC_MAX_INPUT = 2
    NAME_MAX, // _PC_NAME_MAX = 3
    PATH_MAX, // _PC_PATH_MAX = 4
    PIPE_BUF, // _PC_PIPE_BUF = 5
    1, // _PC_CHOWN_RESTRICTED = 6
    1, // _PC_NO_TRUNC = 7
    0, // _PC_VDISABLE = 8
    1, // _PC_SYNC_IO = 9
    -1, // _PC_ASYNC_IO = 10
    -1, // _PC_PRIO_IO = 11
    -1, // _PC_SOCK_MAXBUF = 12
    FILESIZEBITS, // _PC_FILESIZEBITS = 13
    4096, // _PC_REC_INCR_XFER_SIZE = 14
    4096, // _PC_REC_MAX_XFER_SIZE = 15
    4096, // _PC_REC_MIN_XFER_SIZE = 16
    4096, // _PC_REC_XFER_ALIGN = 17
    4096, // _PC_ALLOC_SIZE_MIN = 18
    -1, // _PC_SYMLINK_MAX = 19
    1, // _PC_2_SYMLINKS = 20
};

fn fpathconf(_: c_int, name: c_int) callconv(.c) c_long {
    if (name < 0 or name >= values.len) {
        if (builtin.os.tag == .linux) {
            std.c._errno().* = @intFromEnum(linux.E.INVAL);
        }
        return -1;
    }
    return values[@intCast(name)];
}

fn pathconf(_: ?[*:0]const u8, name: c_int) callconv(.c) c_long {
    return fpathconf(-1, name);
}
