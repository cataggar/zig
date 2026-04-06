const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno_fn = @import("../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&fpathconf, "fpathconf");
        symbol(&pathconf, "pathconf");
        symbol(&confstr, "confstr");
        symbol(&sysconf, "sysconf");
        if (builtin.link_libc) {
            symbol(&get_nprocs_conf, "get_nprocs_conf");
            symbol(&get_nprocs, "get_nprocs");
            symbol(&get_phys_pages, "get_phys_pages");
            symbol(&get_avphys_pages, "get_avphys_pages");
        }
    }
}

// --- fpathconf / pathconf ---

const pc_values = [21]c_short{ 8, 255, 255, 255, 4096, 4096, 1, 1, 0, 1, -1, -1, -1, 64, 4096, 4096, 4096, 4096, 4096, -1, 1 };

fn fpathconf(fd: c_int, name: c_int) callconv(.c) c_long {
    _ = fd;
    if (name < 0 or name >= pc_values.len) { std.c._errno().* = @intFromEnum(linux.E.INVAL); return -1; }
    return pc_values[@intCast(name)];
}

fn pathconf(path: [*:0]const u8, name: c_int) callconv(.c) c_long {
    _ = path;
    return fpathconf(-1, name);
}

// --- confstr ---

fn confstr(name: c_int, buf: ?[*]u8, len: usize) callconv(.c) usize {
    const s: [*:0]const u8 = blk: {
        if (name == 0) break :blk "/bin:/usr/bin";
        if ((name & ~@as(c_int, 4)) == 1) break :blk "";
        if (name >= 1116 and name - 1116 <= 35) break :blk "";
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return 0;
    };
    var slen: usize = 0;
    while (s[slen] != 0) slen += 1;
    if (buf) |b| {
        if (len > 0) { const c = @min(slen, len - 1); @memcpy(b[0..c], s[0..c]); b[c] = 0; }
    }
    return slen + 1;
}

// --- sysconf ---

// Value encoding: direct (>= -1), RLIM (< -32768), jump table (-256..-2)
const VER: c_short = -255; // JT(1)
const JT_ARG_MAX: c_short = -254;
const JT_MQ_PRIO_MAX: c_short = -253;
const JT_PAGE_SIZE: c_short = -252;
const JT_SEM_VALUE_MAX: c_short = -251;
const JT_NPROCS_CONF: c_short = -250;
const JT_NPROCS_ONLN: c_short = -249;
const JT_PHYS_PAGES: c_short = -248;
const JT_AVPHYS_PAGES: c_short = -247;
const JT_ZERO: c_short = -246;
const JT_DELAYTIMER_MAX: c_short = -245;
const JT_MINSIGSTKSZ: c_short = -244;
const JT_SIGSTKSZ: c_short = -243;

const RLIM_NPROC: c_short = -32768 | 6;
const RLIM_NOFILE: c_short = -32768 | 7;

const POSIX_VERSION: c_long = 200809;
const NSIG: c_short = if (builtin.cpu.arch.isMIPS()) 128 else 65;

// Lookup table: sc_values[_SC_xxx] = encoded value
const sc_values = blk: {
    var t: [251]c_short = .{0} ** 251;
    t[0] = JT_ARG_MAX; // ARG_MAX
    t[1] = RLIM_NPROC; // CHILD_MAX
    t[2] = 100; // CLK_TCK
    t[3] = 32; // NGROUPS_MAX
    t[4] = RLIM_NOFILE; // OPEN_MAX
    t[5] = -1; // STREAM_MAX
    t[6] = 6; // TZNAME_MAX
    t[7] = 1; // JOB_CONTROL
    t[8] = 1; // SAVED_IDS
    t[9] = VER; // REALTIME_SIGNALS
    t[10] = -1; // PRIORITY_SCHEDULING
    t[11] = VER; // TIMERS
    t[12] = VER; // ASYNCHRONOUS_IO
    t[13] = -1; // PRIORITIZED_IO
    t[14] = -1; // SYNCHRONIZED_IO
    t[15] = VER; // FSYNC
    t[16] = VER; // MAPPED_FILES
    t[17] = VER; // MEMLOCK
    t[18] = VER; // MEMLOCK_RANGE
    t[19] = VER; // MEMORY_PROTECTION
    t[20] = VER; // MESSAGE_PASSING
    t[21] = VER; // SEMAPHORES
    t[22] = VER; // SHARED_MEMORY_OBJECTS
    t[23] = -1; // AIO_LISTIO_MAX
    t[24] = -1; // AIO_MAX
    t[25] = JT_ZERO; // AIO_PRIO_DELTA_MAX
    t[26] = JT_DELAYTIMER_MAX;
    t[27] = -1; // MQ_OPEN_MAX
    t[28] = JT_MQ_PRIO_MAX;
    t[29] = VER; // VERSION
    t[30] = JT_PAGE_SIZE;
    t[31] = NSIG - 1 - 31 - 3; // RTSIG_MAX
    t[32] = 256; // SEM_NSEMS_MAX
    t[33] = JT_SEM_VALUE_MAX;
    t[34] = -1; // SIGQUEUE_MAX
    t[35] = -1; // TIMER_MAX
    t[36] = 99; // BC_BASE_MAX
    t[37] = 2048; // BC_DIM_MAX
    t[38] = 99; // BC_SCALE_MAX
    t[39] = 1000; // BC_STRING_MAX
    t[40] = 2; // COLL_WEIGHTS_MAX
    t[42] = -1; // EXPR_NEST_MAX
    t[43] = -1; // LINE_MAX
    t[44] = 255; // RE_DUP_MAX
    t[46] = VER; // 2_VERSION
    t[47] = VER; // 2_C_BIND
    t[48] = -1; t[49] = -1; t[50] = -1; t[51] = -1; t[52] = -1;
    t[60] = 1024; // IOV_MAX
    t[67] = VER; // THREADS
    t[68] = VER; // THREAD_SAFE_FUNCTIONS
    t[69] = -1; t[70] = -1;
    t[71] = 256; // LOGIN_NAME_MAX
    t[72] = 32; // TTY_NAME_MAX
    t[73] = 4; // THREAD_DESTRUCTOR_ITERATIONS
    t[74] = 128; // THREAD_KEYS_MAX
    t[75] = 2048; // THREAD_STACK_MIN
    t[76] = -1; // THREAD_THREADS_MAX
    t[77] = VER; // THREAD_ATTR_STACKADDR
    t[78] = VER; // THREAD_ATTR_STACKSIZE
    t[79] = VER; // THREAD_PRIORITY_SCHEDULING
    t[80] = -1; t[81] = -1;
    t[82] = VER; // THREAD_PROCESS_SHARED
    t[83] = JT_NPROCS_CONF;
    t[84] = JT_NPROCS_ONLN;
    t[85] = JT_PHYS_PAGES;
    t[86] = JT_AVPHYS_PAGES;
    t[87] = -1; t[88] = -1;
    t[89] = 700; // XOPEN_VERSION
    t[90] = 700; // XOPEN_XCU_VERSION
    t[91] = 1; // XOPEN_UNIX
    t[92] = -1; // XOPEN_CRYPT
    t[93] = 1; // XOPEN_ENH_I18N
    t[94] = 1; // XOPEN_SHM
    t[96] = -1; t[97] = -1; t[98] = -1; t[99] = -1; t[100] = -1;
    t[109] = 20; // NZERO
    t[125] = -1; // XBS5_ILP32_OFF32
    t[126] = if (@sizeOf(c_long) == 4) 1 else -1;
    t[127] = if (@sizeOf(c_long) == 8) 1 else -1;
    t[128] = -1;
    t[129] = -1; t[130] = -1; t[131] = -1;
    t[132] = VER; // ADVISORY_INFO
    t[133] = VER; // BARRIERS
    t[137] = VER; // CLOCK_SELECTION
    t[138] = VER; // CPUTIME
    t[139] = VER; // THREAD_CPUTIME
    t[149] = VER; // MONOTONIC_CLOCK
    t[153] = VER; // READER_WRITER_LOCKS
    t[154] = VER; // SPIN_LOCKS
    t[155] = 1; // REGEXP
    t[157] = 1; // SHELL
    t[159] = VER; // SPAWN
    t[160] = -1; t[161] = -1;
    t[164] = VER; // TIMEOUTS
    t[165] = -1;
    t[168] = -1; t[169] = -1; t[170] = -1; t[171] = -1; t[172] = -1;
    t[173] = 40; // SYMLOOP_MAX
    t[174] = JT_ZERO; // STREAMS
    t[175] = -1;
    t[176] = -1;
    t[177] = if (@sizeOf(c_long) == 4) 1 else -1;
    t[178] = if (@sizeOf(c_long) == 8) 1 else -1;
    t[179] = -1;
    t[180] = 255; // HOST_NAME_MAX
    t[181] = -1; t[182] = -1; t[183] = -1; t[184] = -1;
    t[235] = VER; // IPV6
    t[236] = VER; // RAW_SOCKETS
    t[237] = -1;
    t[238] = if (@sizeOf(c_long) == 4) 1 else -1;
    t[239] = if (@sizeOf(c_long) == 8) 1 else -1;
    t[240] = -1; t[241] = -1; t[242] = -1; t[243] = -1; t[244] = -1;
    t[245] = -1;
    t[246] = JT_ZERO; // XOPEN_STREAMS
    t[247] = -1; t[248] = -1;
    t[249] = JT_MINSIGSTKSZ;
    t[250] = JT_SIGSTKSZ;
    break :blk t;
};

extern "c" fn getrlimit(resource: c_int, rlim: *linux.rlimit) c_int;
extern "c" fn getauxval(at_type: c_ulong) c_ulong;

fn sysconf(name: c_int) callconv(.c) c_long {
    if (name < 0 or name >= sc_values.len or sc_values[@intCast(name)] == 0) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    const v = sc_values[@intCast(name)];
    if (v >= -1) return v;

    // RLIMIT case
    if (v < -256) {
        var rl: linux.rlimit = undefined;
        _ = getrlimit(v & 16383, &rl);
        if (rl.cur == std.math.maxInt(usize)) return -1;
        return if (rl.cur > std.math.maxInt(c_long)) std.math.maxInt(c_long) else @intCast(rl.cur);
    }

    // Jump table cases
    const code: u8 = @truncate(@as(u16, @bitCast(v)));
    return switch (code) {
        @as(u8, @truncate(@as(u16, @bitCast(VER)))) => POSIX_VERSION,
        @as(u8, @truncate(@as(u16, @bitCast(JT_ARG_MAX)))) => 131072,
        @as(u8, @truncate(@as(u16, @bitCast(JT_MQ_PRIO_MAX)))) => 32768,
        @as(u8, @truncate(@as(u16, @bitCast(JT_PAGE_SIZE)))) => @intCast(getauxval(6)), // AT_PAGESZ=6
        @as(u8, @truncate(@as(u16, @bitCast(JT_SEM_VALUE_MAX)))) => 0x7fffffff,
        @as(u8, @truncate(@as(u16, @bitCast(JT_DELAYTIMER_MAX)))) => 0x7fffffff,
        @as(u8, @truncate(@as(u16, @bitCast(JT_NPROCS_CONF)))),
        @as(u8, @truncate(@as(u16, @bitCast(JT_NPROCS_ONLN)))) => blk: {
            var set: [128]u8 = .{1} ++ (.{0} ** 127);
            _ = linux.syscall3(.sched_getaffinity, 0, set.len, @intFromPtr(&set));
            var cnt: c_long = 0;
            for (set) |b| cnt += @intCast(@popCount(b));
            break :blk cnt;
        },
        @as(u8, @truncate(@as(u16, @bitCast(JT_PHYS_PAGES)))),
        @as(u8, @truncate(@as(u16, @bitCast(JT_AVPHYS_PAGES)))) => blk: {
            var si: linux.Sysinfo = undefined;
            _ = linux.sysinfo(&si);
            const unit: u64 = if (si.mem_unit == 0) 1 else si.mem_unit;
            const mem: u64 = if (code == @as(u8, @truncate(@as(u16, @bitCast(JT_PHYS_PAGES)))))
                @as(u64, si.totalram) * unit
            else
                (@as(u64, si.freeram) + @as(u64, si.bufferram)) * unit;
            const page_size = getauxval(6);
            const pages = mem / page_size;
            break :blk if (pages > std.math.maxInt(c_long)) std.math.maxInt(c_long) else @intCast(pages);
        },
        @as(u8, @truncate(@as(u16, @bitCast(JT_MINSIGSTKSZ)))),
        @as(u8, @truncate(@as(u16, @bitCast(JT_SIGSTKSZ)))) => blk: {
            var val: c_long = @intCast(getauxval(51)); // AT_MINSIGSTKSZ=51
            if (val < 2048) val = 2048; // MINSIGSTKSZ
            if (code == @as(u8, @truncate(@as(u16, @bitCast(JT_SIGSTKSZ)))))
                val += 8192 - 2048; // SIGSTKSZ - MINSIGSTKSZ
            break :blk val;
        },
        @as(u8, @truncate(@as(u16, @bitCast(JT_ZERO)))) => 0,
        else => v,
    };
}

// --- conf/legacy.c ---

extern "c" fn sysconf_c(name: c_int) c_long;

fn get_nprocs_conf() callconv(.c) c_int { return @intCast(sysconf(83)); }
fn get_nprocs() callconv(.c) c_int { return @intCast(sysconf(84)); }
fn get_phys_pages() callconv(.c) c_long { return sysconf(85); }
fn get_avphys_pages() callconv(.c) c_long { return sysconf(86); }
