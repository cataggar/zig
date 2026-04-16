const builtin = @import("builtin");
var environ_var: ?[*:null]?[*:0]u8 = null;
const std = @import("std");
const linux = std.os.linux;
const symbol = @import("../c.zig").symbol;
// C library dependencies.
extern "c" fn strncmp(a: [*:0]const u8, b: [*:0]const u8, n: usize) c_int;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn malloc(size: usize) ?[*]u8;
extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?[*]u8;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn memcpy(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;
extern "c" fn __strchrnul(s: [*:0]const u8, c: c_int) [*:0]const u8;
fn issetugidImpl() callconv(.c) c_int {
    return 0; // Linux does not have issetugid; always return 0
}
extern "c" var __environ: ?[*:null]?[*:0]u8;
var env_alloced: ?[*]?[*:0]u8 = null;
var env_alloced_n: usize = 0;
var oldenv: ?[*:null]?[*:0]u8 = null;
var __stack_chk_guard: usize = 0;
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
extern "c" fn __set_thread_area(tp: *anyopaque) c_int;
extern "c" fn memset(dst: *anyopaque, c: c_int, n: usize) *anyopaque;
extern "c" fn _init() void;
extern "c" fn exit(code: c_int) noreturn;
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
// DTP_OFFSET is arch-specific.
const DTP_OFFSET: usize = if (builtin.cpu.arch.isMIPS() or builtin.cpu.arch == .m68k or builtin.cpu.arch.isPowerPC())
    0x8000
else if (builtin.cpu.arch.isRISCV())
    0x800
else
    0;
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

extern var __libc: LibC;
extern var __hwcap: usize;
extern var __sysinfo: usize;
extern var __progname: ?[*:0]u8;
extern var __progname_full: ?[*:0]u8;
extern "c" fn __libc_start_init() void;
extern var __default_stacksize: c_uint;
extern var __thread_list_lock: c_int;
extern "c" fn __init_tls(aux: [*]usize) void;

comptime {
    if (builtin.target.isMuslLibC()) {
        @export(&environ_var, .{ .name = "__environ", .linkage = .weak, .visibility = .hidden });
        @export(&environ_var, .{ .name = "___environ", .linkage = .weak, .visibility = .hidden });
        @export(&environ_var, .{ .name = "_environ", .linkage = .weak, .visibility = .hidden });
        @export(&environ_var, .{ .name = "environ", .linkage = .weak, .visibility = .hidden });
        symbol(&__stack_chk_guard, "__stack_chk_guard");
        symbol(&__init_ssp, "__init_ssp");
        symbol(&__stack_chk_fail, "__stack_chk_fail");
        symbol(&issetugidImpl, "issetugid");
        symbol(&__reset_tls_fn, "__reset_tls");
        symbol(&dummy, "_init");
        symbol(&libc_start_init_fn, "__libc_start_init");
        symbol(&__init_libc_fn, "__init_libc");
        symbol(&__libc_start_main_fn, "__libc_start_main");
    }
    if (builtin.link_libc) {
        symbol(&__env_rm_add, "__env_rm_add");
        symbol(&__putenv, "__putenv");
        symbol(&getenv, "getenv");
        symbol(&setenv, "setenv");
        symbol(&putenv, "putenv");
        symbol(&unsetenv, "unsetenv");
        symbol(&clearenv, "clearenv");
        symbol(&secure_getenv, "secure_getenv");
    }
}

fn __env_rm_add(old: ?[*:0]u8, new_val: ?[*:0]u8) callconv(.c) void {
    var new = new_val;
    for (0..env_alloced_n) |i| {
        if (env_alloced.?[i] == old) {
            env_alloced.?[i] = new;
            free(old);
            return;
        } else if (env_alloced.?[i] == null and new != null) {
            env_alloced.?[i] = new;
            new = null;
        }
    }
    if (new == null) return;
    const t: ?[*]?[*:0]u8 = @ptrCast(@alignCast(realloc(@ptrCast(env_alloced), @sizeOf(?[*:0]u8) * (env_alloced_n + 1))));
    if (t == null) return;
    env_alloced = t;
    t.?[env_alloced_n] = new;
    env_alloced_n += 1;
}

fn __putenv(s: [*:0]u8, l: usize, r: ?[*:0]u8) callconv(.c) c_int {
    var i: usize = 0;
    if (__environ) |env| {
        var e = env;
        while (e[0]) |entry| : ({
            e = @ptrCast(@as([*]?[*:0]u8, @ptrCast(e)) + 1);
            i += 1;
        }) {
            if (strncmp(s, entry, l + 1) == 0) {
                const tmp = entry;
                e[0] = s;
                __env_rm_add(tmp, r);
                return 0;
            }
        }
    }
    const ptr_size = @sizeOf(?[*:0]u8);
    var newenv: ?[*:null]?[*:0]u8 = undefined;
    if (__environ == oldenv) {
        newenv = @ptrCast(@alignCast(realloc(@ptrCast(oldenv), ptr_size * (i + 2))));
        if (newenv == null) {
            free(r);
            return -1;
        }
    } else {
        newenv = @ptrCast(@alignCast(malloc(ptr_size * (i + 2))));
        if (newenv == null) {
            free(r);
            return -1;
        }
        if (i > 0) _ = memcpy(@ptrCast(newenv.?), @as(*const anyopaque, @ptrCast(__environ.?)), ptr_size * i);
        free(@ptrCast(oldenv));
    }
    const nv = newenv.?;
    @as([*]?[*:0]u8, @ptrCast(nv))[i] = s;
    @as([*]?[*:0]u8, @ptrCast(nv))[i + 1] = null;
    __environ = nv;
    oldenv = nv;
    if (r) |rv| __env_rm_add(null, rv);
    return 0;
}

fn getenv(name: [*:0]const u8) callconv(.c) ?[*:0]u8 {
    const l = @intFromPtr(__strchrnul(name, '=')) - @intFromPtr(name);
    if (l != 0 and name[l] == 0) {
        if (__environ) |env| {
            var e: [*]?[*:0]u8 = @ptrCast(env);
            while (e[0]) |entry| : (e += 1) {
                if (strncmp(name, entry, l) == 0 and entry[l] == '=')
                    return @ptrCast(@as([*]u8, @ptrCast(entry)) + l + 1);
            }
        }
    }
    return null;
}

fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) callconv(.c) c_int {
    const l1 = @intFromPtr(__strchrnul(name, '=')) - @intFromPtr(name);
    if (l1 == 0 or name[l1] != 0) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    if (overwrite == 0 and getenv(name) != null) return 0;

    const l2 = strlen(value);
    const s: ?[*]u8 = malloc(l1 + l2 + 2);
    if (s == null) return -1;
    _ = memcpy(s.?, @as(*const anyopaque, @ptrCast(name)), l1);
    s.?[l1] = '=';
    _ = memcpy(@ptrCast(s.? + l1 + 1), @as(*const anyopaque, @ptrCast(value)), l2 + 1);
    return __putenv(@ptrCast(s.?), l1, @ptrCast(s.?));
}

fn putenv(s: [*:0]u8) callconv(.c) c_int {
    const l = @intFromPtr(__strchrnul(s, '=')) - @intFromPtr(s);
    if (l == 0 or s[l] == 0) return unsetenv(s);
    return __putenv(s, l, null);
}

fn unsetenv(name: [*:0]const u8) callconv(.c) c_int {
    const l = @intFromPtr(__strchrnul(name, '=')) - @intFromPtr(name);
    if (l == 0 or name[l] != 0) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    if (__environ) |env| {
        var e: [*]?[*:0]u8 = @ptrCast(env);
        var eo: [*]?[*:0]u8 = e;
        while (e[0]) |entry| : (e += 1) {
            if (strncmp(name, entry, l) == 0 and entry[l] == '=') {
                __env_rm_add(entry, null);
            } else {
                if (eo != e) eo[0] = entry;
                eo += 1;
            }
        }
        if (eo != e) eo[0] = null;
    }
    return 0;
}

fn clearenv() callconv(.c) c_int {
    if (__environ) |env| {
        var e: [*]?[*:0]u8 = @ptrCast(env);
        __environ = null;
        while (e[0]) |entry| : (e += 1) {
            __env_rm_add(entry, null);
        }
    } else {
        __environ = null;
    }
    return 0;
}

fn secure_getenv(name: [*:0]const u8) callconv(.c) ?[*:0]u8 {
    if (issetugidImpl() != 0) return null;
    return getenv(name);
}

fn __init_ssp(entropy: ?*const anyopaque) callconv(.c) void {
    if (entropy) |ent| {
        __stack_chk_guard = @as(*const usize, @ptrCast(@alignCast(ent))).*;
    } else {
        __stack_chk_guard = @intFromPtr(&__stack_chk_guard) *% 1103515245;
    }
    // On 64-bit, zero out the second byte to prevent string-based leaks.
    if (@sizeOf(usize) >= 8) {
        const bytes: *[8]u8 = @ptrCast(&__stack_chk_guard);
        bytes[1] = 0;
    }
}

fn __stack_chk_fail() callconv(.c) noreturn {
    @trap();
}

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
