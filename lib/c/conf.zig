const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.link_libc) {
        symbol(&sysconf, "sysconf");
    }
}

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

const values: [TABLE_SIZE]c_int = blk: {
    var t: [TABLE_SIZE]c_int = .{0} ** TABLE_SIZE;
    t[0] = JT_ARG_MAX; // _SC_ARG_MAX
    t[1] = RLIM_NPROC; // _SC_CHILD_MAX
    t[2] = 100; // _SC_CLK_TCK
    t[3] = 32; // _SC_NGROUPS_MAX
    t[4] = RLIM_NOFILE; // _SC_OPEN_MAX
    t[5] = -1; // _SC_STREAM_MAX
    t[6] = if (@sizeOf(c_long) == 8) 6 else 6; // _SC_TZNAME_MAX (TZNAME_MAX=6)
    t[7] = 1; // _SC_JOB_CONTROL
    t[8] = 1; // _SC_SAVED_IDS
    t[9] = VER; // _SC_REALTIME_SIGNALS
    t[10] = -1; // _SC_PRIORITY_SCHEDULING
    t[11] = VER; // _SC_TIMERS
    t[12] = VER; // _SC_ASYNCHRONOUS_IO
    t[13] = -1; // _SC_PRIORITIZED_IO
    t[14] = -1; // _SC_SYNCHRONIZED_IO
    t[15] = VER; // _SC_FSYNC
    t[16] = VER; // _SC_MAPPED_FILES
    t[17] = VER; // _SC_MEMLOCK
    t[18] = VER; // _SC_MEMLOCK_RANGE
    t[19] = VER; // _SC_MEMORY_PROTECTION
    t[20] = VER; // _SC_MESSAGE_PASSING
    t[21] = VER; // _SC_SEMAPHORES
    t[22] = VER; // _SC_SHARED_MEMORY_OBJECTS
    t[23] = -1; // _SC_AIO_LISTIO_MAX
    t[24] = -1; // _SC_AIO_MAX
    t[25] = JT_ZERO; // _SC_AIO_PRIO_DELTA_MAX
    t[26] = JT_DELAYTIMER_MAX; // _SC_DELAYTIMER_MAX
    t[27] = -1; // _SC_MQ_OPEN_MAX
    t[28] = JT_MQ_PRIO_MAX; // _SC_MQ_PRIO_MAX
    t[29] = VER; // _SC_VERSION
    t[30] = JT_PAGE_SIZE; // _SC_PAGE_SIZE
    t[31] = 31; // _SC_RTSIG_MAX (64-1-31-3 on most, simplified)
    t[32] = 256; // _SC_SEM_NSEMS_MAX
    t[33] = JT_SEM_VALUE_MAX; // _SC_SEM_VALUE_MAX
    t[34] = -1; // _SC_SIGQUEUE_MAX
    t[35] = -1; // _SC_TIMER_MAX
    t[36] = 99; // _SC_BC_BASE_MAX
    t[37] = 2048; // _SC_BC_DIM_MAX
    t[38] = 99; // _SC_BC_SCALE_MAX
    t[39] = 1000; // _SC_BC_STRING_MAX
    t[40] = 2; // _SC_COLL_WEIGHTS_MAX
    t[41] = -1; // _SC_EXPR_NEST_MAX
    t[42] = -1; // _SC_LINE_MAX
    t[43] = 255; // _SC_RE_DUP_MAX
    t[44] = VER; // _SC_2_VERSION
    t[45] = VER; // _SC_2_C_BIND
    t[46] = -1; // _SC_2_C_DEV
    t[47] = -1; // _SC_2_FORT_DEV
    t[48] = -1; // _SC_2_FORT_RUN
    t[49] = -1; // _SC_2_SW_DEV
    t[50] = -1; // _SC_2_LOCALEDEF
    t[51] = 1024; // _SC_IOV_MAX
    // 52..54 unused
    t[55] = VER; // _SC_THREADS
    t[56] = VER; // _SC_THREAD_SAFE_FUNCTIONS
    t[57] = -1; // _SC_GETGR_R_SIZE_MAX
    t[58] = -1; // _SC_GETPW_R_SIZE_MAX
    t[59] = 256; // _SC_LOGIN_NAME_MAX
    t[60] = 32; // _SC_TTY_NAME_MAX
    t[61] = 4; // _SC_THREAD_DESTRUCTOR_ITERATIONS
    t[62] = 128; // _SC_THREAD_KEYS_MAX
    t[63] = 131072; // _SC_THREAD_STACK_MIN
    t[64] = -1; // _SC_THREAD_THREADS_MAX
    t[65] = VER; // _SC_THREAD_ATTR_STACKADDR
    t[66] = VER; // _SC_THREAD_ATTR_STACKSIZE
    t[67] = VER; // _SC_THREAD_PRIORITY_SCHEDULING
    t[68] = -1; // _SC_THREAD_PRIO_INHERIT
    t[69] = -1; // _SC_THREAD_PRIO_PROTECT
    t[70] = VER; // _SC_THREAD_PROCESS_SHARED
    // 71..82 unused
    t[83] = JT_NPROCESSORS; // _SC_NPROCESSORS_CONF
    t[84] = JT_NPROCESSORS; // _SC_NPROCESSORS_ONLN
    t[85] = JT_PHYS_PAGES; // _SC_PHYS_PAGES
    t[86] = JT_AVPHYS_PAGES; // _SC_AVPHYS_PAGES
    t[87] = -1; // _SC_ATEXIT_MAX
    t[88] = -1; // _SC_PASS_MAX
    t[89] = 700; // _SC_XOPEN_VERSION
    t[90] = 700; // _SC_XOPEN_XCU_VERSION
    t[91] = 1; // _SC_XOPEN_UNIX
    t[92] = -1; // _SC_XOPEN_CRYPT
    t[93] = 1; // _SC_XOPEN_ENH_I18N
    t[94] = 1; // _SC_XOPEN_SHM
    t[95] = -1; // _SC_2_CHAR_TERM
    t[96] = -1; // _SC_2_UPE
    t[97] = -1; // _SC_XOPEN_XPG2
    t[98] = -1; // _SC_XOPEN_XPG3
    t[99] = -1; // _SC_XOPEN_XPG4
    t[100] = 20; // _SC_NZERO
    t[109] = -1; // _SC_XBS5_ILP32_OFF32
    t[110] = if (sz_long == 4) 1 else -1; // _SC_XBS5_ILP32_OFFBIG
    t[111] = if (sz_long == 8) 1 else -1; // _SC_XBS5_LP64_OFF64
    t[112] = -1; // _SC_XBS5_LPBIG_OFFBIG
    t[113] = -1; // _SC_XOPEN_LEGACY
    t[114] = -1; // _SC_XOPEN_REALTIME
    t[115] = -1; // _SC_XOPEN_REALTIME_THREADS
    t[132] = VER; // _SC_ADVISORY_INFO
    t[133] = VER; // _SC_BARRIERS
    t[134] = VER; // _SC_CLOCK_SELECTION
    t[135] = VER; // _SC_CPUTIME
    t[136] = VER; // _SC_THREAD_CPUTIME
    t[137] = VER; // _SC_MONOTONIC_CLOCK
    t[138] = VER; // _SC_READER_WRITER_LOCKS
    t[139] = VER; // _SC_SPIN_LOCKS
    t[140] = 1; // _SC_REGEXP
    t[141] = 1; // _SC_SHELL
    t[142] = VER; // _SC_SPAWN
    t[143] = -1; // _SC_SPORADIC_SERVER
    t[144] = -1; // _SC_THREAD_SPORADIC_SERVER
    t[145] = VER; // _SC_TIMEOUTS
    t[146] = -1; // _SC_TYPED_MEMORY_OBJECTS
    t[147] = -1; // _SC_2_PBS
    t[148] = -1; // _SC_2_PBS_ACCOUNTING
    t[149] = -1; // _SC_2_PBS_LOCATE
    t[150] = -1; // _SC_2_PBS_MESSAGE
    t[151] = -1; // _SC_2_PBS_TRACK
    t[152] = 40; // _SC_SYMLOOP_MAX
    t[153] = JT_ZERO; // _SC_STREAMS
    t[154] = -1; // _SC_2_PBS_CHECKPOINT
    t[155] = -1; // _SC_V6_ILP32_OFF32
    t[156] = if (sz_long == 4) 1 else -1; // _SC_V6_ILP32_OFFBIG
    t[157] = if (sz_long == 8) 1 else -1; // _SC_V6_LP64_OFF64
    t[158] = -1; // _SC_V6_LPBIG_OFFBIG
    t[159] = 64; // _SC_HOST_NAME_MAX
    t[160] = -1; // _SC_TRACE
    t[161] = -1; // _SC_TRACE_EVENT_FILTER
    t[162] = -1; // _SC_TRACE_INHERIT
    t[163] = -1; // _SC_TRACE_LOG
    t[164] = VER; // _SC_IPV6
    t[165] = VER; // _SC_RAW_SOCKETS
    t[166] = -1; // _SC_V7_ILP32_OFF32
    t[167] = if (sz_long == 4) 1 else -1; // _SC_V7_ILP32_OFFBIG
    t[168] = if (sz_long == 8) 1 else -1; // _SC_V7_LP64_OFF64
    t[169] = -1; // _SC_V7_LPBIG_OFFBIG
    t[170] = -1; // _SC_SS_REPL_MAX
    t[171] = -1; // _SC_TRACE_EVENT_NAME_MAX
    t[172] = -1; // _SC_TRACE_NAME_MAX
    t[173] = -1; // _SC_TRACE_SYS_MAX
    t[174] = -1; // _SC_TRACE_USER_EVENT_MAX
    t[175] = JT_ZERO; // _SC_XOPEN_STREAMS
    t[176] = -1; // _SC_THREAD_ROBUST_PRIO_INHERIT
    t[177] = -1; // _SC_THREAD_ROBUST_PRIO_PROTECT
    t[178] = JT_MINSIGSTKSZ; // _SC_MINSIGSTKSZ
    t[179] = JT_SIGSTKSZ; // _SC_SIGSTKSZ
    break :blk t;
};

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
    const code: u8 = @truncate(@as(c_uint, @bitCast(v)));
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
