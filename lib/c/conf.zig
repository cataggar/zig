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
const RLIM_NPROC: c_int = -32768 | 6; // RLIMIT_NPROC
const RLIM_NOFILE: c_int = -32768 | 7; // RLIMIT_NOFILE
const sz_long: c_int = @sizeOf(c_long);
const ARG_MAX: c_long = 131072;
const TZNAME_MAX: c_long = 6;
const SEM_NSEMS_MAX: c_long = 256;
const IOV_MAX: c_long = 1024;
const TTY_NAME_MAX: c_long = 32;
const PTHREAD_DESTRUCTOR_ITERATIONS: c_long = 4;
const PTHREAD_KEYS_MAX: c_long = 128;
const PTHREAD_STACK_MIN: c_long = 2048;
const XOPEN_VERSION: c_long = 700;
const NZERO: c_long = 20;
const SYMLOOP_MAX: c_long = 40;
const HOST_NAME_MAX: c_long = 255;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&fpathconf, "fpathconf");
        symbol(&pathconf, "pathconf");
    }
    if (builtin.target.isWasiLibC()) {}
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
    } else "";

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

fn sysconfValue(name: c_int) c_int {
    return switch (name) {
        0 => JT_ARG_MAX,
        1 => RLIM_NPROC,
        2 => 100,
        3 => 32,
        4 => RLIM_NOFILE,
        5, 10, 13, 14, 23, 24, 27, 34, 35, 42, 43, 48, 49, 50, 51, 52, 76, 80, 81, 87, 88, 92, 95, 97, 98, 99, 100, 125, 128, 129, 130, 131, 160, 161, 165, 168, 169, 170, 171, 172, 175, 176, 179, 181, 182, 183, 184, 237, 240, 241, 242, 243, 244, 245, 247, 248 => -1,
        6 => TZNAME_MAX,
        7, 8, 91, 93, 94, 155, 157 => 1,
        9, 11, 12, 15, 16, 17, 18, 19, 20, 21, 22, 29, 46, 47, 67, 68, 77, 78, 79, 82, 132, 133, 137, 138, 139, 149, 153, 154, 159, 164, 235, 236 => VER,
        25, 174, 246 => JT_ZERO,
        26 => JT_DELAYTIMER_MAX,
        28 => JT_MQ_PRIO_MAX,
        30 => JT_PAGE_SIZE,
        31 => linux.NSIG - 1 - 31 - 3,
        32 => SEM_NSEMS_MAX,
        33 => JT_SEM_VALUE_MAX,
        36 => 99,
        37 => 2048,
        38 => 99,
        39 => 1000,
        40 => 2,
        44 => 255,
        60 => IOV_MAX,
        69, 70 => -1,
        71 => 256,
        72 => TTY_NAME_MAX,
        73 => PTHREAD_DESTRUCTOR_ITERATIONS,
        74 => PTHREAD_KEYS_MAX,
        75 => PTHREAD_STACK_MIN,
        83 => JT_NPROCESSORS,
        84 => JT_NPROCESSORS,
        85 => JT_PHYS_PAGES,
        86 => JT_AVPHYS_PAGES,
        89, 90 => XOPEN_VERSION,
        109 => NZERO,
        126, 177, 238 => if (sz_long == 4) 1 else -1,
        127, 178, 239 => if (sz_long == 8) 1 else -1,
        173 => SYMLOOP_MAX,
        180 => HOST_NAME_MAX,
        249 => JT_MINSIGSTKSZ,
        250 => JT_SIGSTKSZ,
        else => 0,
    };
}

fn sysconf(name: c_int) callconv(.c) c_long {
    const v = sysconfValue(name);
    if (v == 0) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    if (v >= -1) return v;

    if (v < -256) {
        var rl: linux.rlimit = undefined;
        _ = linux.getrlimit(@enumFromInt(v & 0x3FFF), &rl);
        if (rl.cur == std.math.maxInt(u64)) return -1;
        return if (rl.cur > LONG_MAX) LONG_MAX else @intCast(rl.cur);
    }

    const code: u8 = @truncate(@as(c_uint, @bitCast(v)));
    return switch (code) {
        1 => _POSIX_VERSION,
        2 => ARG_MAX,
        3 => 32768,
        4 => @intCast(std.heap.page_size_min),
        5 => 2147483647,
        6, 7 => blk: {
            var set: [128]u8 = @splat(0);
            set[0] = 1;
            _ = linux.syscall3(.sched_getaffinity, 0, set.len, @intFromPtr(&set));
            var cnt: c_long = 0;
            for (&set) |*byte| {
                var b = byte.*;
                while (b != 0) : (b &= b - 1) cnt += 1;
            }
            break :blk cnt;
        },
        8, 9 => blk: {
            var si: linux.Sysinfo = undefined;
            _ = linux.sysinfo(&si);
            const mem_unit: u64 = if (si.mem_unit == 0) 1 else si.mem_unit;
            const mem = if (code == 8) si.totalram else si.freeram +% si.bufferram;
            const result = (mem *% mem_unit) / std.heap.page_size_min;
            break :blk if (result > LONG_MAX) LONG_MAX else @intCast(result);
        },
        10 => 0,
        11 => 2147483647,
        12, 13 => blk: {
            var val: c_long = @intCast(linux.getauxval(std.elf.AT_MINSIGSTKSZ));
            if (val < linux.MINSIGSTKSZ) val = linux.MINSIGSTKSZ;
            if (code == 13) val += linux.SIGSTKSZ - linux.MINSIGSTKSZ;
            break :blk val;
        },
        else => v,
    };
}
