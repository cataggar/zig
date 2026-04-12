const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

// ── Musl internal types ────────────────────────────────────────────────

const tls_module = extern struct {
    next: ?*tls_module,
    image: ?*anyopaque,
    len: usize,
    size: usize,
    @"align": usize,
    offset: usize,
};

// Partial __libc struct — only the fields we access.
// After page_size, there's global_locale which we don't touch.
const LibC = extern struct {
    can_do_threads: u8,
    threaded: u8,
    secure: u8,
    need_locks: i8,
    threads_minus_1: c_int,
    auxv: ?[*]usize,
    tls_head: ?*tls_module,
    tls_size: usize,
    tls_align: usize,
    tls_cnt: usize,
    page_size: usize,
};

extern var __libc: LibC;
extern var __environ: ?[*:null]?[*:0]u8;
extern var __hwcap: usize;
extern var __sysinfo: usize;
extern var __progname: ?[*:0]u8;
extern var __progname_full: ?[*:0]u8;
extern var __default_stacksize: c_uint;
extern var __thread_list_lock: c_int;

extern "c" fn __init_tls(aux: [*]usize) void;
extern "c" fn __init_ssp(entropy: ?*const anyopaque) void;
extern "c" fn __set_thread_area(tp: *anyopaque) c_int;
extern "c" fn memcpy(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;
extern "c" fn memset(dst: *anyopaque, c: c_int, n: usize) *anyopaque;
extern "c" fn _init() void;
extern "c" fn exit(code: c_int) noreturn;
extern "c" fn __libc_start_init() void;

const AT_PHDR = 3;
const AT_PHENT = 4;
const AT_PHNUM = 5;
const AT_PAGESZ = 6;
const AT_UID = 11;
const AT_EUID = 12;
const AT_GID = 13;
const AT_EGID = 14;
const AT_SECURE = 23;
const AT_RANDOM = 25;
const AT_HWCAP = 16;
const AT_SYSINFO = 32;
const AT_EXECFN = 31;
const AUX_CNT = 38;

const PT_PHDR = 6;
const PT_DYNAMIC = 2;
const PT_TLS = 7;
const PT_GNU_STACK = 0x6474e551;
const PROT_READ = 1;
const PROT_WRITE = 2;
const MAP_ANONYMOUS = 0x20;
const MAP_PRIVATE = 0x02;
const O_RDWR = 2;
const O_LARGEFILE = if (@sizeOf(usize) == 4) 0o100000 else 0;
const POLLNVAL: c_short = 0x020;
const DEFAULT_STACK_MAX: c_uint = 8 << 20;

// ── __reset_tls ────────────────────────────────────────────────────────

// DTP_OFFSET is arch-specific.
const DTP_OFFSET: usize = if (builtin.cpu.arch.isMIPS() or builtin.cpu.arch == .m68k or builtin.cpu.arch.isPowerPC())
    0x8000
else if (builtin.cpu.arch.isRISCV())
    0x800
else
    0;

// __pthread_self() for the current arch.
inline fn get_tp() usize {
    return switch (builtin.cpu.arch) {
        .x86_64 => asm volatile ("mov %%fs:0, %[ret]"
            : [ret] "=r" (-> usize),
        ),
        .x86 => asm volatile ("movl %%gs:0, %[ret]"
            : [ret] "=r" (-> usize),
        ),
        .aarch64, .aarch64_be => asm volatile ("mrs %[ret], tpidr_el0"
            : [ret] "=r" (-> usize),
        ),
        .arm, .armeb, .thumb, .thumbeb => asm volatile ("mrc p15,0,%[ret],c13,c0,3"
            : [ret] "=r" (-> usize),
        ),
        .riscv32, .riscv64 => asm volatile ("mv %[ret], tp"
            : [ret] "=r" (-> usize),
        ),
        .powerpc, .powerpc64, .powerpc64le => asm volatile (""
            : [ret] "={r13}" (-> usize),
        ),
        .s390x => asm volatile (
            \\ear  %[ret], %%a0
            \\sllg %[ret], %[ret], 32
            \\ear  %[ret], %%a1
            : [ret] "=r" (-> usize),
        ),
        .loongarch64 => asm volatile (""
            : [ret] "={$r2}" (-> usize),
        ),
        else => @compileError("unsupported arch for get_tp"),
    };
}

// Offsets into struct pthread for dtv field (arch-specific).
// On x86_64 (TLS below TP): self(8), dtv(8) at offset 8.
// On aarch64 (TLS_ABOVE_TP): dtv is at end of struct after canary.
const DTV_OFFSET: usize = @sizeOf(usize); // offset of dtv in struct pthread (after self ptr)

fn __reset_tls_fn() callconv(.c) void {
    const tp = get_tp();
    // On non-TLS_ABOVE_TP (x86_64), pthread_self = tp, dtv at offset 8.
    const dtv: [*]usize = @ptrFromInt(@as(*const usize, @ptrFromInt(tp + DTV_OFFSET)).*);
    const n = dtv[0];
    if (n == 0) return;
    var p = __libc.tls_head;
    var i: usize = 1;
    while (i <= n and p != null) : ({
        i += 1;
        p = p.?.next;
    }) {
        const mem: [*]u8 = @ptrFromInt(dtv[i] -% DTP_OFFSET);
        if (p) |mod| {
            _ = memcpy(mem, mod.image orelse continue, mod.len);
            _ = memset(mem + mod.len, 0, mod.size - mod.len);
        }
    }
}

// ── __libc_start_main ──────────────────────────────────────────────────

fn dummy() callconv(.c) void {}

extern const __init_array_start: *const fn () callconv(.c) void;
extern const __init_array_end: *const fn () callconv(.c) void;

fn libc_start_init_fn() callconv(.c) void {
    _init();
    const start: usize = @intFromPtr(&__init_array_start);
    const end: usize = @intFromPtr(&__init_array_end);
    const ptr_size = @sizeOf(*const fn () callconv(.c) void);
    var a = start;
    while (a < end) : (a += ptr_size) {
        const func: *const *const fn () callconv(.c) void = @ptrFromInt(a);
        func.*();
    }
}

fn __init_libc_fn(envp: [*:null]?[*:0]u8, pn: ?[*:0]u8) callconv(.c) void {
    __environ = envp;

    // Count env entries to find auxv.
    var env_count: usize = 0;
    while (envp[env_count] != null) : (env_count += 1) {}
    const auxv_ptr: [*]usize = @ptrCast(@alignCast(@as([*]?[*:0]u8, @ptrCast(envp)) + env_count + 1));
    __libc.auxv = auxv_ptr;

    var aux: [AUX_CNT]usize = .{0} ** AUX_CNT;
    var idx: usize = 0;
    while (auxv_ptr[idx] != 0) : (idx += 2) {
        if (auxv_ptr[idx] < AUX_CNT) aux[auxv_ptr[idx]] = auxv_ptr[idx + 1];
    }

    __hwcap = aux[AT_HWCAP];
    if (aux[AT_SYSINFO] != 0) __sysinfo = aux[AT_SYSINFO];
    __libc.page_size = aux[AT_PAGESZ];

    var progname = pn;
    if (progname == null) progname = @ptrFromInt(aux[AT_EXECFN]);
    if (progname == null) progname = @ptrCast(@constCast(""));
    __progname = progname;
    __progname_full = progname;
    if (progname) |p| {
        var i: usize = 0;
        while (p[i] != 0) : (i += 1) {
            if (p[i] == '/') __progname = @ptrCast(@as([*]u8, @ptrCast(p)) + i + 1);
        }
    }

    __init_tls(&aux);
    __init_ssp(@ptrFromInt(aux[AT_RANDOM]));

    if (aux[AT_UID] == aux[AT_EUID] and aux[AT_GID] == aux[AT_EGID] and aux[AT_SECURE] == 0) return;

    // Check for closed stdin/stdout/stderr and open /dev/null if needed.
    const SYS_ppoll = linux.SYS.ppoll;
    var pfd: [3]extern struct { fd: c_int, events: c_short, revents: c_short } = .{
        .{ .fd = 0, .events = 0, .revents = 0 },
        .{ .fd = 1, .events = 0, .revents = 0 },
        .{ .fd = 2, .events = 0, .revents = 0 },
    };
    const r: isize = @bitCast(linux.syscall4(
        SYS_ppoll,
        @intFromPtr(&pfd),
        3,
        @intFromPtr(&linux.timespec{ .sec = 0, .nsec = 0 }),
        0,
    ));
    if (r < 0) @trap();
    for (&pfd) |*p2| {
        if (p2.revents & POLLNVAL != 0) {
            const orc: isize = @bitCast(linux.open("/dev/null", .{ .ACCMODE = .RDWR }, 0));
            if (orc < 0) @trap();
        }
    }
    __libc.secure = 1;
}

fn __libc_start_main_fn(
    main_fn: *const fn (c_int, [*]?[*:0]u8, [*:null]?[*:0]u8) callconv(.c) c_int,
    argc: c_int,
    argv: [*]?[*:0]u8,
    _: ?*anyopaque, // init_dummy
    _: ?*anyopaque, // fini_dummy
    _: ?*anyopaque, // ldso_dummy
) callconv(.c) c_int {
    const envp: [*:null]?[*:0]u8 = @ptrCast(argv + @as(usize, @intCast(argc)) + 1);
    __init_libc_fn(envp, argv[0]);

    __libc_start_init();
    const envp2: [*:null]?[*:0]u8 = @ptrCast(argv + @as(usize, @intCast(argc)) + 1);
    exit(main_fn(argc, argv, envp2));
}

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&__reset_tls_fn, "__reset_tls");
        symbol(&dummy, "_init");
        symbol(&dummy, "__funcs_on_exit");
        symbol(&dummy, "__stdio_exit");
        symbol(&dummy, "_fini");
        symbol(&libc_start_init_fn, "__libc_start_init");
        symbol(&__init_libc_fn, "__init_libc");
        symbol(&__libc_start_main_fn, "__libc_start_main");
    }
}
