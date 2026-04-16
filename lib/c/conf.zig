const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;
const symbol = @import("../c.zig").symbol;
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
const _SC_NPROCESSORS_CONF = 83;
const _SC_NPROCESSORS_ONLN = 84;
const _SC_PHYS_PAGES = 85;
const _SC_AVPHYS_PAGES = 86;
const _CS_POSIX_V6_ILP32_OFF32_CFLAGS = 1116;
const _POSIX_VERSION: c_long = 200809;
const LONG_MAX = std.math.maxInt(c_long);
// Encoded table values
const VER: c_int = -256 | 1;
const JT_ARG_MAX: c_int = -256 | 2;
const JT_MQ_PRIO_MAX: c_int = -256 | 3;
const JT_PAGE_SIZE: c_int = -256 | 4;
const JT_SEM_VALUE_MAX: c_int = -256 | 5;
const JT_NPROCESSORS: c_int = -256 | 6;
const JT_PHYS_PAGES: c_int = -256 | 8;
const JT_AVPHYS_PAGES: c_int = -256 | 9;
const JT_ZERO: c_int = -256 | 10;
const JT_DELAYTIMER_MAX: c_int = -256 | 11;
const JT_MINSIGSTKSZ: c_int = -256 | 12;
const JT_SIGSTKSZ: c_int = -256 | 13;
const RLIM_NPROC: c_int = @bitCast(@as(c_uint, 0x80000000 | 6)); // RLIMIT_NPROC
const RLIM_NOFILE: c_int = @bitCast(@as(c_uint, 0x80000000 | 7)); // RLIMIT_NOFILE
const sz_long: c_int = @sizeOf(c_long);
// Table size: _SC values go up to ~199 on Linux
const TABLE_SIZE = 200;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&fpathconf, "fpathconf");
        symbol(&pathconf, "pathconf");
    }
    if (builtin.target.isWasiLibC()) {
    }
    if (builtin.link_libc) {
        symbol(&get_nprocs_conf, "get_nprocs_conf");
        symbol(&get_nprocs, "get_nprocs");
        symbol(&get_phys_pages, "get_phys_pages");
        symbol(&get_avphys_pages, "get_avphys_pages");
        symbol(&sysconf, "sysconf");
    }
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&confstr, "confstr");
    }
}

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

fn get_nprocs_conf() callconv(.c) c_int {
    return @intCast(sysconf(_SC_NPROCESSORS_CONF));
}

fn get_nprocs() callconv(.c) c_int {
    return @intCast(sysconf(_SC_NPROCESSORS_ONLN));
}

fn get_phys_pages() callconv(.c) c_long {
    return sysconf(_SC_PHYS_PAGES);
}

fn get_avphys_pages() callconv(.c) c_long {
    return sysconf(_SC_AVPHYS_PAGES);
}

fn confstr(name: c_int, buf: ?[*]u8, len: usize) callconv(.c) usize {
    const s: [*:0]const u8 = if (name == 0)
        "/bin:/usr/bin"
    else if ((@as(c_uint, @bitCast(name)) & ~@as(c_uint, 4)) != 1 and
        @as(c_uint, @bitCast(name -% _CS_POSIX_V6_ILP32_OFF32_CFLAGS)) > 35)
    {
        if (builtin.os.tag == .linux)
            std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return 0;
    } else
        "";

    // Find length of s.
    var slen: usize = 0;
    while (s[slen] != 0) : (slen += 1) {}

    // Copy with truncation.
    if (buf) |b| {
        if (len > 0) {
            const copy_len = if (slen < len - 1) slen else len - 1;
            @memcpy(b[0..copy_len], s[0..copy_len]);
            b[copy_len] = 0;
        }
    }
    return slen + 1;
}

fn sysconf(name: c_int) callconv(.c) c_long {
    if (name < 0 or name >= TABLE_SIZE) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    const v = values[@intCast(name)];
    if (v == 0) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    if (v >= -1) return v;

    // RLIMIT query
    if (v < -256) {
        var rl: linux.rlimit = undefined;
        _ = linux.getrlimit(@enumFromInt(v & 0x3FFF), &rl);
        if (rl.cur == std.math.maxInt(u64)) return -1;
        return if (rl.cur > LONG_MAX) LONG_MAX else @intCast(rl.cur);
    }

    // Jump table entries
    const code: u8 = @truncate(@as(c_uint, @intCast(v)));
    return switch (code) {
        1 => _POSIX_VERSION, // VER
        2 => 2097152, // ARG_MAX
        3 => 32768, // MQ_PRIO_MAX
        4 => @intCast(std.heap.page_size_min), // PAGE_SIZE
        5 => 2147483647, // SEM_VALUE_MAX (INT_MAX)
        6, 7 => blk: { // NPROCESSORS_CONF, NPROCESSORS_ONLN
            var set: [128]u8 = .{1} ++ (.{0} ** 127);
            _ = linux.syscall3(.sched_getaffinity, 0, set.len, @intFromPtr(&set));
            var cnt: c_long = 0;
            for (&set) |*byte| {
                var b = byte.*;
                while (b != 0) : (b &= b - 1) cnt += 1;
            }
            break :blk cnt;
        },
        8, 9 => blk: { // PHYS_PAGES, AVPHYS_PAGES
            var si: linux.Sysinfo = undefined;
            _ = linux.sysinfo(&si);
            const mem_unit: u64 = if (si.mem_unit == 0) 1 else si.mem_unit;
            const mem = if (code == 8) si.totalram else si.freeram +% si.bufferram;
            const result = (mem *% mem_unit) / std.heap.page_size_min;
            break :blk if (result > LONG_MAX) LONG_MAX else @intCast(result);
        },
        10 => 0, // ZERO
        11 => 2147483647, // DELAYTIMER_MAX (INT_MAX)
        12, 13 => blk: { // MINSIGSTKSZ, SIGSTKSZ
            var val: c_long = @intCast(linux.getauxval(std.elf.AT_MINSIGSTKSZ));
            if (val < linux.MINSIGSTKSZ) val = linux.MINSIGSTKSZ;
            if (code == 13) val += linux.SIGSTKSZ - linux.MINSIGSTKSZ;
            break :blk val;
        },
        else => -1,
    };
}
