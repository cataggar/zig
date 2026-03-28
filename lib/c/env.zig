const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

const TLS_ABOVE_TP = switch (builtin.cpu.arch) {
    .aarch64, .aarch64_be, .riscv32, .riscv64, .mips, .mipsel, .mips64, .mips64el, .loongarch64 => true,
    else => false,
};

const GAP_ABOVE_TP: usize = switch (builtin.cpu.arch) {
    .aarch64, .aarch64_be => 16,
    .arm, .armeb, .thumb, .thumbeb => 8,
    else => 0,
};

const DTP_OFFSET: usize = if (builtin.cpu.arch.isMIPS() or builtin.cpu.arch == .m68k or builtin.cpu.arch.isPowerPC())
    0x8000
else if (builtin.cpu.arch.isRISCV())
    0x800
else
    0;

const TP_OFFSET: usize = 0;

// ── Musl internal types ────────────────────────────────────────────────

const tls_module = extern struct {
    next: ?*tls_module,
    image: ?*anyopaque,
    len: usize,
    size: usize,
    @"align": usize,
    offset: usize,
};

const robust_list_t = extern struct {
    head: ?*volatile ?*anyopaque,
    off: isize,
    pending: ?*volatile ?*anyopaque,
};

// Minimal pthread struct matching musl layout for the fields we access.
const pthread = if (!TLS_ABOVE_TP) extern struct {
    self: ?*@This(),
    dtv: ?[*]usize,
    prev: ?*@This(),
    next: ?*@This(),
    sysinfo: usize,
    canary: usize,
    // Part 2
    tid: c_int,
    errno_val: c_int,
    detach_state: c_int,
    cancel: c_int,
    canceldisable: u8,
    cancelasync: u8,
    _bitfields: u8,
    _pad1: u8,
    _pad2: u32,
    map_base: ?*u8,
    map_size: usize,
    stack: ?*anyopaque,
    stack_size: usize,
    guard_size: usize,
    result: ?*anyopaque,
    cancelbuf: ?*anyopaque,
    tsd: ?*?*anyopaque,
    robust_list: robust_list_t,
    h_errno_val: c_int,
    timer_id: c_int,
    locale: ?*anyopaque,
} else extern struct {
    self: ?*@This(),
    prev: ?*@This(),
    next: ?*@This(),
    sysinfo: usize,
    // Part 2
    tid: c_int,
    errno_val: c_int,
    detach_state: c_int,
    cancel: c_int,
    canceldisable: u8,
    cancelasync: u8,
    _bitfields: u8,
    _pad1: u8,
    _pad2: u32,
    map_base: ?*u8,
    map_size: usize,
    stack: ?*anyopaque,
    stack_size: usize,
    guard_size: usize,
    result: ?*anyopaque,
    cancelbuf: ?*anyopaque,
    tsd: ?*?*anyopaque,
    robust_list: robust_list_t,
    h_errno_val: c_int,
    timer_id: c_int,
    locale: ?*anyopaque,
    killlock: c_int,
    _pad3: u32,
    dlerror_buf: ?*u8,
    stdio_locks: ?*anyopaque,
    canary: usize,
    dtv: ?[*]usize,
};

const DT_JOINABLE = 0;

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
    // global_locale follows but we access it by pointer from libc base
};

extern var __libc: LibC;
extern var __sysinfo: usize;
extern var __thread_list_lock_ext: c_int;
extern var __default_stacksize: c_uint;
extern "c" fn __set_thread_area(tp: *anyopaque) c_int;
extern "c" fn memcpy(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;

const AT_PHDR = 3;
const AT_PHENT = 4;
const AT_PHNUM = 5;
const PT_PHDR = 6;
const PT_DYNAMIC = 2;
const PT_TLS = 7;
const PT_GNU_STACK = 0x6474e551;
const PROT_READ = 1;
const PROT_WRITE = 2;
const MAP_ANONYMOUS = 0x20;
const MAP_PRIVATE = 0x02;
const DEFAULT_STACK_MAX: c_uint = 8 << 20;

var thread_list_lock: c_int = 0;

// ── Phdr type ──────────────────────────────────────────────────────────

const Phdr = if (@sizeOf(usize) == 4) std.elf.Elf32_Phdr else std.elf.Elf64_Phdr;

// ── Static data ────────────────────────────────────────────────────────

const builtin_tls_size = @sizeOf(pthread) + 16 * @sizeOf(?*anyopaque) + @alignOf(pthread);
var builtin_tls: [builtin_tls_size]u8 align(@alignOf(pthread)) = undefined;
const MIN_TLS_ALIGN = @alignOf(pthread);

var main_tls: tls_module = std.mem.zeroes(tls_module);

// ── __init_tp ──────────────────────────────────────────────────────────

fn __init_tp(p: *anyopaque) callconv(.c) c_int {
    const td: *pthread = @ptrCast(@alignCast(p));
    td.self = td;
    const tp_adj: *anyopaque = if (TLS_ABOVE_TP)
        @ptrFromInt(@intFromPtr(p) + @sizeOf(pthread) + TP_OFFSET)
    else
        p;
    const r = __set_thread_area(tp_adj);
    if (r < 0) return -1;
    if (r == 0) __libc.can_do_threads = 1;
    td.detach_state = DT_JOINABLE;
    td.tid = @intCast(@as(isize, @bitCast(linux.syscall1(.set_tid_address, @intFromPtr(&thread_list_lock)))));
    // locale points to global_locale which is right after page_size in LibC
    td.locale = @ptrFromInt(@intFromPtr(&__libc) + @offsetOf(LibC, "page_size") + @sizeOf(usize));
    td.robust_list.head = @ptrCast(&td.robust_list.head);
    td.sysinfo = __sysinfo;
    td.next = td;
    td.prev = td;
    return 0;
}

// ── __copy_tls ─────────────────────────────────────────────────────────

fn __copy_tls(mem_arg: [*]u8) callconv(.c) *anyopaque {
    var mem = mem_arg;
    var td: *pthread = undefined;
    var dtv: [*]usize = undefined;

    if (TLS_ABOVE_TP) {
        dtv = @ptrCast(@alignCast(mem + __libc.tls_size - (__libc.tls_cnt + 1) * @sizeOf(usize)));
        const adj = (~@intFromPtr(mem) +% 1 +% @sizeOf(pthread)) & (__libc.tls_align -% 1);
        mem = @ptrFromInt(@intFromPtr(mem) +% adj);
        td = @ptrCast(@alignCast(mem));
        mem += @sizeOf(pthread);
        var i: usize = 1;
        var p = __libc.tls_head;
        while (p) |mod| : ({
            i += 1;
            p = mod.next;
        }) {
            dtv[i] = @intFromPtr(mem + mod.offset) +% DTP_OFFSET;
            if (mod.image) |img| _ = memcpy(mem + mod.offset, img, mod.len);
        }
    } else {
        dtv = @ptrCast(@alignCast(mem));
        mem += __libc.tls_size - @sizeOf(pthread);
        mem = @ptrFromInt(@intFromPtr(mem) & ~(__libc.tls_align -% 1));
        td = @ptrCast(@alignCast(mem));
        var i: usize = 1;
        var p = __libc.tls_head;
        while (p) |mod| : ({
            i += 1;
            p = mod.next;
        }) {
            dtv[i] = (@intFromPtr(mem) -% mod.offset) +% DTP_OFFSET;
            if (mod.image) |img| _ = memcpy(@ptrFromInt(@intFromPtr(mem) -% mod.offset), img, mod.len);
        }
    }
    dtv[0] = __libc.tls_cnt;
    td.dtv = dtv;
    return td;
}

// ── static_init_tls ────────────────────────────────────────────────────

fn static_init_tls(aux: [*]usize) callconv(.c) void {
    var tls_phdr: ?*const Phdr = null;
    var base: usize = 0;

    var p_raw: [*]const u8 = @ptrFromInt(aux[AT_PHDR]);
    var n: usize = aux[AT_PHNUM];
    while (n > 0) : ({
        n -= 1;
        p_raw += aux[AT_PHENT];
    }) {
        const phdr: *const Phdr = @ptrCast(@alignCast(p_raw));
        if (phdr.p_type == PT_PHDR) base = aux[AT_PHDR] -% phdr.p_vaddr;
        if (phdr.p_type == PT_TLS) tls_phdr = phdr;
        if (phdr.p_type == PT_GNU_STACK and phdr.p_memsz > __default_stacksize)
            __default_stacksize = if (phdr.p_memsz < DEFAULT_STACK_MAX) @intCast(phdr.p_memsz) else DEFAULT_STACK_MAX;
    }

    if (tls_phdr) |tp| {
        main_tls.image = @ptrFromInt(base +% tp.p_vaddr);
        main_tls.len = tp.p_filesz;
        main_tls.size = tp.p_memsz;
        main_tls.@"align" = tp.p_align;
        __libc.tls_cnt = 1;
        __libc.tls_head = &main_tls;
    }

    main_tls.size +%= (-%main_tls.size -% @intFromPtr(main_tls.image)) & (main_tls.@"align" -% 1);

    if (TLS_ABOVE_TP) {
        main_tls.offset = GAP_ABOVE_TP;
        main_tls.offset +%= (-%GAP_ABOVE_TP +% @intFromPtr(main_tls.image)) & (main_tls.@"align" -% 1);
    } else {
        main_tls.offset = main_tls.size;
    }
    if (main_tls.@"align" < MIN_TLS_ALIGN) main_tls.@"align" = MIN_TLS_ALIGN;

    __libc.tls_align = main_tls.@"align";
    var tls_sz = 2 * @sizeOf(*anyopaque) + @sizeOf(pthread);
    if (TLS_ABOVE_TP) tls_sz += main_tls.offset;
    tls_sz += main_tls.size + main_tls.@"align";
    tls_sz = (tls_sz + MIN_TLS_ALIGN - 1) & ~(MIN_TLS_ALIGN - 1);
    __libc.tls_size = tls_sz;

    var mem: [*]u8 = undefined;
    if (__libc.tls_size > builtin_tls.len) {
        mem = @ptrFromInt(linux.syscall6(
            if (@hasField(linux.SYS, "mmap2")) .mmap2 else .mmap,
            0,
            __libc.tls_size,
            PROT_READ | PROT_WRITE,
            MAP_ANONYMOUS | MAP_PRIVATE,
            @bitCast(@as(isize, -1)),
            0,
        ));
    } else {
        mem = &builtin_tls;
    }

    if (__init_tp(__copy_tls(mem)) < 0) @trap();
}

comptime {
    if (builtin.link_libc) {
        symbol(&thread_list_lock, "__thread_list_lock");
        symbol(&__init_tp, "__init_tp");
        symbol(&__copy_tls, "__copy_tls");
        symbol(&static_init_tls, "__init_tls");
    }
}
