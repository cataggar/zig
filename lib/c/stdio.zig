const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;

/// Musl internal FILE struct layout (struct _IO_FILE from stdio_impl.h).
/// Field order MUST match musl's struct _IO_FILE exactly.
const FILE = extern struct {
    flags: c_uint,
    rpos: ?[*]u8,
    rend: ?[*]u8,
    close_fn: ?*const fn (*FILE) callconv(.c) c_int,
    wend: ?[*]u8,
    wpos: ?[*]u8,
    mustbezero_1: ?[*]u8,
    wbase: ?[*]u8,
    read_fn: ?*const fn (*FILE, [*]u8, usize) callconv(.c) usize,
    write_fn: ?*const fn (*FILE, [*]const u8, usize) callconv(.c) usize,
    seek_fn: ?*const fn (*FILE, i64, c_int) callconv(.c) i64,
    buf: ?[*]u8,
    buf_size: usize,
    prev: ?*FILE,
    next: ?*FILE,
    fd: c_int,
    pipe_pid: c_int,
    lockcount: c_long,
    mode: c_int,
    lock: c_int,
    lbf: c_int,
    cookie: ?*anyopaque,
    off: i64,
    getln_buf: ?[*]u8,
    mustbezero_2: ?*anyopaque,
    shend: ?[*]u8,
    shlim: i64,
    shcnt: i64,
    prev_locked: ?*FILE,
    next_locked: ?*FILE,
    locale: ?*anyopaque,
};
const wchar_t = std.c.wchar_t;
const wint_t = std.c.wint_t;
const ssize_t = isize;
/// C constants
const _IOFBF = 0;
const _IOLBF = 1;
const _IONBF = 2;
const BUFSIZ = 1024;
const EOF = -1;
// Extern references to musl C functions that are still compiled from C sources.
const setvbuf_fn = @extern(*const fn (?*FILE, ?[*]u8, c_int, usize) callconv(.c) c_int, .{ .name = "setvbuf" });
const getdelim_fn = @extern(*const fn (?*[*]u8, ?*usize, c_int, ?*FILE) callconv(.c) ssize_t, .{ .name = "getdelim" });
const fgetwc_fn = @extern(*const fn (?*FILE) callconv(.c) wint_t, .{ .name = "fgetwc" });
const fputwc_fn = @extern(*const fn (wchar_t, ?*FILE) callconv(.c) wint_t, .{ .name = "fputwc" });
const fread_fn = @extern(*const fn (*anyopaque, usize, usize, ?*FILE) callconv(.c) usize, .{ .name = "fread" });
const fwrite_fn = @extern(*const fn (*const anyopaque, usize, usize, ?*FILE) callconv(.c) usize, .{ .name = "fwrite" });
const stdin_ext = @extern(*const ?*FILE, .{ .name = "stdin" });
const stdout_ext = @extern(*const ?*FILE, .{ .name = "stdout" });
const fgetc_fn = @extern(*const fn (?*FILE) callconv(.c) c_int, .{ .name = "fgetc" });
const fputc_fn = @extern(*const fn (c_int, ?*FILE) callconv(.c) c_int, .{ .name = "fputc" });
const getc_unlocked_fn = @extern(*const fn (?*FILE) callconv(.c) c_int, .{ .name = "getc_unlocked" });
const putc_unlocked_fn = @extern(*const fn (c_int, ?*FILE) callconv(.c) c_int, .{ .name = "putc_unlocked" });
/// Musl FILE flag constants (from stdio_impl.h)
const F_EOF: c_uint = 16;
const F_ERR: c_uint = 32;
const fseeko_unlocked_fn = @extern(*const fn (*FILE, i64, c_int) callconv(.c) c_int, .{ .name = "__fseeko_unlocked" });
const fseeko_fn = @extern(*const fn (*FILE, i64, c_int) callconv(.c) c_int, .{ .name = "__fseeko" });
const ftello_fn = @extern(*const fn (*FILE) callconv(.c) i64, .{ .name = "__ftello" });
/// Musl UNGET constant (from stdio_impl.h)
const UNGET = 8;
const toread_fn = @extern(*const fn (*FILE) callconv(.c) c_int, .{ .name = "__toread" });
/// Musl FILE flag constant (from stdio_impl.h)
const F_SVB: c_uint = 64;
const F_APP: c_uint = 128;
const F_NORD: c_uint = 4;
const F_NOWR: c_uint = 8;
const SEEK_SET: c_int = 0;
const SEEK_CUR: c_int = 1;
const SEEK_END: c_int = 2;
const towrite_fn = @extern(*const fn (*FILE) callconv(.c) c_int, .{ .name = "__towrite" });
const linux = std.os.linux;
const c_errno = @import("../c.zig").errno;
const fflush_fn = @extern(*const fn (?*FILE) callconv(.c) c_int, .{ .name = "fflush" });
const uflow_fn = @extern(*const fn (*FILE) callconv(.c) c_int, .{ .name = "__uflow" });
const overflow_fn = @extern(*const fn (*FILE, c_int) callconv(.c) c_int, .{ .name = "__overflow" });
const VaList = std.builtin.VaList;
const CVaList = switch (builtin.cpu.arch) {
    .x86_64 => switch (builtin.os.tag) {
        .uefi, .windows => VaList,
        else => *VaList,
    },
    .powerpc, .powerpcle, .s390x => *VaList,
    else => VaList,
};

inline fn passVaList(ap: *VaList) CVaList {
    return if (CVaList == *VaList) ap else ap.*;
}

inline fn unpackVaList(ap: CVaList) VaList {
    return if (CVaList == *VaList) ap.* else ap;
}

inline fn cVaArg(ap: *VaList, comptime T: type) T {
    if ((builtin.cpu.arch == .aarch64 or builtin.cpu.arch == .aarch64_be) and
        builtin.os.tag != .macos and builtin.os.tag != .ios and
        builtin.os.tag != .tvos and builtin.os.tag != .watchos and
        builtin.os.tag != .visionos and builtin.os.tag != .windows)
    {
        const is_be = builtin.cpu.arch == .aarch64_be;
        const align_bytes: usize = @max(@alignOf(T), 8);
        const size_bytes: usize = @sizeOf(T);
        if (@typeInfo(T) == .float) {
            const offs = ap.__vr_offs;
            if (offs < 0) {
                const new_offs = offs + 16;
                ap.__vr_offs = new_offs;
                if (new_offs <= 0) {
                    const top: usize = @intFromPtr(ap.__vr_top);
                    const addr: usize = @bitCast(@as(isize, @bitCast(top)) + @as(isize, offs));
                    const be_delta: usize = if (is_be and size_bytes < 16) 16 - size_bytes else 0;
                    return @as(*align(1) const T, @ptrFromInt(addr + be_delta)).*;
                }
            }
            const stack_addr: usize = @intFromPtr(ap.__stack);
            const aligned_stack: usize = (stack_addr + (align_bytes - 1)) & ~(align_bytes - 1);
            const stack_size: usize = (size_bytes + 7) & ~@as(usize, 7);
            ap.__stack = @ptrFromInt(aligned_stack + stack_size);
            const be_delta: usize = if (is_be and size_bytes < 8) 8 - size_bytes else 0;
            return @as(*align(1) const T, @ptrFromInt(aligned_stack + be_delta)).*;
        } else {
            const offs = ap.__gr_offs;
            if (offs < 0) {
                const aligned_offs: c_int = if (align_bytes > 8)
                    (offs + @as(c_int, @intCast(align_bytes - 1))) & -@as(c_int, @intCast(align_bytes))
                else
                    offs;
                const reg_size: c_int = @intCast((size_bytes + 7) & ~@as(usize, 7));
                const new_offs = aligned_offs + reg_size;
                ap.__gr_offs = new_offs;
                if (new_offs <= 0) {
                    const top: usize = @intFromPtr(ap.__gr_top);
                    const base_addr: usize = @bitCast(@as(isize, @bitCast(top)) + @as(isize, aligned_offs));
                    const be_delta: usize = if (is_be and size_bytes < 8) 8 - size_bytes else 0;
                    return @as(*align(1) const T, @ptrFromInt(base_addr + be_delta)).*;
                }
            }
            const stack_addr: usize = @intFromPtr(ap.__stack);
            const aligned_stack: usize = (stack_addr + (align_bytes - 1)) & ~(align_bytes - 1);
            const stack_size: usize = (size_bytes + 7) & ~@as(usize, 7);
            ap.__stack = @ptrFromInt(aligned_stack + stack_size);
            const be_delta: usize = if (is_be and size_bytes < 8) 8 - size_bytes else 0;
            return @as(*align(1) const T, @ptrFromInt(aligned_stack + be_delta)).*;
        }
    }
    if (builtin.cpu.arch == .s390x) {
        const padded_size: usize = 8;
        if (@typeInfo(T) == .float and @sizeOf(T) <= 8) {
            const padding: usize = padded_size - @sizeOf(T);
            const addr: usize = if (ap.__fpr < 4) blk: {
                const count: usize = @intCast(ap.__fpr);
                ap.__fpr += 1;
                break :blk @intFromPtr(ap.__reg_save_area) + (16 + count) * padded_size + padding;
            } else blk: {
                const ovf: usize = @intFromPtr(ap.__overflow_arg_area);
                ap.__overflow_arg_area = @ptrFromInt(ovf + padded_size);
                break :blk ovf + padding;
            };
            return @as(*align(1) const T, @ptrFromInt(addr)).*;
        } else if (@sizeOf(T) > 8) {
            const ptr_addr: usize = if (ap.__gpr < 5) blk: {
                const count: usize = @intCast(ap.__gpr);
                ap.__gpr += 1;
                break :blk @intFromPtr(ap.__reg_save_area) + (2 + count) * padded_size;
            } else blk: {
                const ovf: usize = @intFromPtr(ap.__overflow_arg_area);
                ap.__overflow_arg_area = @ptrFromInt(ovf + padded_size);
                break :blk ovf;
            };
            const indirect_ptr = @as(*align(1) const *align(1) const T, @ptrFromInt(ptr_addr)).*;
            return indirect_ptr.*;
        } else {
            const padding: usize = padded_size - @sizeOf(T);
            const addr: usize = if (ap.__gpr < 5) blk: {
                const count: usize = @intCast(ap.__gpr);
                ap.__gpr += 1;
                break :blk @intFromPtr(ap.__reg_save_area) + (2 + count) * padded_size + padding;
            } else blk: {
                const ovf: usize = @intFromPtr(ap.__overflow_arg_area);
                ap.__overflow_arg_area = @ptrFromInt(ovf + padded_size);
                break :blk ovf + padding;
            };
            return @as(*align(1) const T, @ptrFromInt(addr)).*;
        }
    }
    if (builtin.cpu.arch == .x86_64 and (builtin.os.tag == .windows or builtin.os.tag == .uefi)) {
        const cur: usize = @intFromPtr(ap.*);
        ap.* = @ptrFromInt(cur + 8);
        if (@sizeOf(T) > 8 or (@sizeOf(T) & (@sizeOf(T) - 1)) != 0) {
            const indirect_ptr = @as(*align(1) const *align(1) const T, @ptrFromInt(cur)).*;
            return indirect_ptr.*;
        }
        return @as(*align(1) const T, @ptrFromInt(cur)).*;
    }
    if (builtin.cpu.arch == .x86_64 and T == c_longdouble) {
        const va: *std.builtin.VaListX86_64 = ap;
        const raw = @intFromPtr(va.overflow_arg_area);
        const aligned = std.mem.alignForward(usize, raw, 16);
        const v = @as(*align(1) const c_longdouble, @ptrFromInt(aligned)).*;
        va.overflow_arg_area = @ptrFromInt(aligned + 16);
        return v;
    }
    if (builtin.cpu.arch == .riscv32 and @sizeOf(T) > 8) {
        return @cVaArg(ap, *align(1) const T).*;
    }
    return @cVaArg(ap, T);
}

const MB_LEN_MAX = 4;
const SnCookie = extern struct {
    s: [*]u8,
    n: usize,
};
const SwCookie = extern struct {
    ws: [*]wchar_t,
    l: usize,
};
const stderr_ext = @extern(*const ?*FILE, .{ .name = "stderr" });
const strerror_fn = @extern(*const fn (c_int) callconv(.c) [*:0]const u8, .{ .name = "strerror" });
const btowc_fn = @extern(*const fn (c_int) callconv(.c) wint_t, .{ .name = "btowc" });
const wcsnlen_fn = @extern(*const fn ([*:0]const wchar_t, usize) callconv(.c) usize, .{ .name = "wcsnlen" });
const memchr_fn = @extern(*const fn (?[*]const u8, c_int, usize) callconv(.c) ?[*]u8, .{ .name = "memchr" });
const lseek_fn = @extern(*const fn (c_int, i64, c_int) callconv(.c) i64, .{ .name = "__lseek" });
const malloc_fn = @extern(*const fn (usize) callconv(.c) ?*anyopaque, .{ .name = "malloc" });
const realloc_fn = @extern(*const fn (?*anyopaque, usize) callconv(.c) ?*anyopaque, .{ .name = "realloc" });
const aio_close_fn = @extern(*const fn (c_int) callconv(.c) c_int, .{ .name = "__aio_close" });
const mbtowc_fn = @extern(*const fn (?*wchar_t, ?[*]const u8, usize) callconv(.c) c_int, .{ .name = "mbtowc" });
const wcsrtombs_fn = @extern(*const fn (?[*]u8, *?[*:0]const wchar_t, usize, ?*anyopaque) callconv(.c) usize, .{ .name = "wcsrtombs" });
const shlim_fn = @extern(*const fn (*FILE, i64) callconv(.c) void, .{ .name = "__shlim" });
const shgetc_fn = @extern(*const fn (*FILE) callconv(.c) c_int, .{ .name = "__shgetc" });
const intscan_fn = @extern(*const fn (*FILE, c_uint, c_int, c_ulonglong) callconv(.c) c_ulonglong, .{ .name = "__intscan" });
const floatscan_fn = @extern(*const fn (*FILE, c_int, c_int) callconv(.c) c_longdouble, .{ .name = "__floatscan" });
const mbrtowc_fn = @extern(*const fn (?*wchar_t, ?[*]const u8, usize, ?*mbstate_t) callconv(.c) usize, .{ .name = "mbrtowc" });
const mbsinit_fn = @extern(*const fn (?*const mbstate_t) callconv(.c) c_int, .{ .name = "mbsinit" });
const wctomb_fn = @extern(*const fn (?[*]u8, wchar_t) callconv(.c) c_int, .{ .name = "wctomb" });
const ungetwc_fn = @extern(*const fn (wint_t, ?*FILE) callconv(.c) wint_t, .{ .name = "ungetwc" });

comptime {
    if (builtin.link_libc and (builtin.target.isMuslLibC() or builtin.target.isWasiLibC())) {
        symbol(&setbuf, "setbuf");
        symbol(&setbuffer, "setbuffer");
        symbol(&setlinebuf, "setlinebuf");
        symbol(&getline, "getline");
        symbol(&getwchar, "getwchar");
        symbol(&getwchar, "getwchar_unlocked");
        symbol(&putwchar, "putwchar");
        symbol(&putwchar, "putwchar_unlocked");
        symbol(&getwc, "getwc");
        symbol(&putwc, "putwc");
        symbol(&getw, "getw");
        symbol(&putw, "putw");
        symbol(&getchar, "getchar");
        symbol(&putchar, "putchar");
        symbol(&getchar_unlocked, "getchar_unlocked");
        symbol(&putchar_unlocked, "putchar_unlocked");
        symbol(&feof_fn, "feof");
        symbol(&feof_fn, "feof_unlocked");
        symbol(&feof_fn, "_IO_feof_unlocked");
        symbol(&__fseeko, "fseeko");
        symbol(&__fseeko, "fseeko64");
        symbol(&__ftello, "ftello");
        symbol(&__ftello, "ftello64");
        symbol(&ferror_fn, "ferror");
        symbol(&ferror_fn, "ferror_unlocked");
        symbol(&ferror_fn, "_IO_ferror_unlocked");
        symbol(&clearerr, "clearerr");
        symbol(&clearerr, "clearerr_unlocked");
        symbol(&fileno, "fileno");
        symbol(&fileno, "fileno_unlocked");
        symbol(&rewind, "rewind");
        symbol(&fgetpos, "fgetpos");
        symbol(&fgetpos, "fgetpos64");
        symbol(&fsetpos, "fsetpos");
        symbol(&fsetpos, "fsetpos64");
        symbol(&fputs, "fputs");
        symbol(&fputs, "fputs_unlocked");
        symbol(&puts, "puts");
        symbol(&ungetc, "ungetc");
        symbol(&setvbuf, "setvbuf");
        symbol(&__fseeko_unlocked, "__fseeko_unlocked");
        symbol(&__fseeko, "__fseeko");
        symbol(&fseek, "fseek");
        symbol(&__ftello_unlocked, "__ftello_unlocked");
        symbol(&__ftello, "__ftello");
        symbol(&ftell, "ftell");
        symbol(&__fwritex, "__fwritex");
        symbol(&fwrite, "fwrite");
        symbol(&fwrite, "fwrite_unlocked");
        symbol(&fread, "fread");
        symbol(&fread, "fread_unlocked");
        symbol(&fgets, "fgets");
        symbol(&fgets, "fgets_unlocked");
        symbol(&_flushlbf, "_flushlbf");
        symbol(&__fsetlocking, "__fsetlocking");
        symbol(&__fwriting, "__fwriting");
        symbol(&__freading, "__freading");
        symbol(&__freadable, "__freadable");
        symbol(&__fwritable, "__fwritable");
        symbol(&__flbf, "__flbf");
        symbol(&__fbufsize, "__fbufsize");
        symbol(&__fpending, "__fpending");
        symbol(&__fpurge, "__fpurge");
        symbol(&__fpurge, "fpurge");
        symbol(&__freadahead, "__freadahead");
        symbol(&__freadptr, "__freadptr");
        symbol(&__freadptrinc, "__freadptrinc");
        symbol(&__fseterr, "__fseterr");
        symbol(&getc_unlocked_impl, "getc_unlocked");
        symbol(&getc_unlocked_impl, "fgetc_unlocked");
        symbol(&getc_unlocked_impl, "_IO_getc_unlocked");
        symbol(&putc_unlocked_impl, "putc_unlocked");
        symbol(&putc_unlocked_impl, "fputc_unlocked");
        symbol(&putc_unlocked_impl, "_IO_putc_unlocked");
        symbol(&fgetc_impl, "fgetc");
        symbol(&fgetc_impl, "getc");
        symbol(&fgetc_impl, "_IO_getc");
        symbol(&fputc_impl, "fputc");
        symbol(&fputc_impl, "putc");
        symbol(&fputc_impl, "_IO_putc");
        symbol(&toread_impl, "__toread");
        symbol(&towrite_impl, "__towrite");
        symbol(&uflow_impl, "__uflow");
        symbol(&overflow_impl, "__overflow");
        symbol(&perror_impl, "perror");
        // Internal helpers (__fmodeflags.c, __fclose_ca.c, __fopen_rb_ca.c)
        symbol(&fmodeflags_impl, "__fmodeflags");
        symbol(&fclose_ca_impl, "__fclose_ca");
        symbol(&fopen_rb_ca_impl, "__fopen_rb_ca");
        symbol(&fgetln_impl, "fgetln");
        symbol(&stdio_seek_impl, "__stdio_seek");

        // Internal I/O (__stdio_close.c, __stdio_read.c, __stdio_write.c, __stdout_write.c)
        symbol(&stdio_close_impl, "__stdio_close");
        symbol(&stdio_read_impl, "__stdio_read");
        symbol(&stdio_write_impl, "__stdio_write");
        symbol(&stdout_write_impl, "__stdout_write");

        // getdelim.c
        symbol(&getdelim_impl, "getdelim");
        symbol(&getdelim_impl, "__getdelim");

        // v* printf/scanf family
        symbol(&vfprintf_impl, "vfprintf");
        symbol(&vprintf_impl, "vprintf");
        symbol(&vdprintf_impl, "vdprintf");
        symbol(&vsprintf_impl, "vsprintf");
        symbol(&vsnprintf_impl, "vsnprintf");
        symbol(&vasprintf_impl, "vasprintf");
        symbol(&vfscanf_impl, "vfscanf");
        symbol(&vfscanf_impl, "__isoc99_vfscanf");
        symbol(&vscanf_impl, "vscanf");
        symbol(&vscanf_impl, "__isoc99_vscanf");
        symbol(&vsscanf_impl, "vsscanf");
        symbol(&vsscanf_impl, "__isoc99_vsscanf");
        symbol(&vfwprintf_impl, "vfwprintf");
        symbol(&vwprintf_impl, "vwprintf");
        symbol(&vswprintf_impl, "vswprintf");
        symbol(&vfwscanf_impl, "vfwscanf");
        symbol(&vfwscanf_impl, "__isoc99_vfwscanf");
        symbol(&vwscanf_impl, "vwscanf");
        symbol(&vwscanf_impl, "__isoc99_vwscanf");
        symbol(&vswscanf_impl, "vswscanf");
        symbol(&vswscanf_impl, "__isoc99_vswscanf");

        // Memory stream functions (fmemopen.c, open_memstream.c, open_wmemstream.c, fopencookie.c)
        symbol(&fmemopen_impl, "fmemopen");
        symbol(&open_memstream_impl, "open_memstream");
        symbol(&open_wmemstream_impl, "open_wmemstream");
        symbol(&fopencookie_impl, "fopencookie");

        if (builtin.target.isMuslLibC()) {
            symbol(&gets, "gets");
            symbol(&remove_fn, "remove");
            symbol(&rename_fn, "rename");

            // Locking (__lockfile.c, flockfile.c, funlockfile.c, ftrylockfile.c)
            symbol(&flockfile_impl, "flockfile");
            symbol(&ftrylockfile_impl, "ftrylockfile");
            symbol(&funlockfile_impl, "funlockfile");
            symbol(&lockfile_impl, "__lockfile");
            symbol(&unlockfile_impl, "__unlockfile");
            symbol(&do_orphaned_stdio_locks_impl, "__do_orphaned_stdio_locks");
            symbol(&unlist_locked_file_impl, "__unlist_locked_file");
            symbol(&register_locked_file_impl, "__register_locked_file");
        }

        if (builtin.target.isWasiLibC()) {
            // Internal scanners (shgetc.c, intscan.c, floatscan.c)
            symbol(&shlim_impl, "__shlim");
            symbol(&shgetc_impl, "__shgetc");
            symbol(&intscan_impl, "__intscan");
            symbol(&floatscan_impl, "__floatscan");

            // Open file list (ofl.c, ofl_add.c)
            symbol(&ofl_lock_impl, "__ofl_lock");
            symbol(&ofl_unlock_impl, "__ofl_unlock");
            symbol(&ofl_add_impl, "__ofl_add");

            // Standard streams (stdin.c, stdout.c, stderr.c, __stdio_exit.c)
            symbol(&__stdin_FILE, "__stdin_FILE");
            symbol(@ptrCast(&stdin_var), "stdin");
            symbol(@ptrCast(&stdin_var), "__stdin_used");
            symbol(&__stdout_FILE, "__stdout_FILE");
            symbol(@ptrCast(&stdout_var), "stdout");
            symbol(@ptrCast(&stdout_var), "__stdout_used");
            symbol(&__stderr_FILE, "__stderr_FILE");
            symbol(@ptrCast(&stderr_var), "stderr");
            symbol(@ptrCast(&stderr_var), "__stderr_used");
            symbol(&stdio_exit_impl, "__stdio_exit");
            symbol(&stdio_exit_impl, "__stdio_exit_needed");

            // Stream lifecycle (fflush.c, fclose.c, __fdopen.c, fopen.c, freopen.c)
            symbol(&fflush_impl, "fflush");
            symbol(&fflush_impl, "fflush_unlocked");
            symbol(&fclose_impl, "fclose");
            symbol(&fclose_dummy, "__unlist_locked_file");
            symbol(&fdopen_impl, "__fdopen");
            symbol(&fdopen_impl, "fdopen");
            symbol(&fopen_impl, "fopen");
            symbol(&fopen_impl, "fopen64");
            symbol(&freopen_impl, "freopen");
            symbol(&freopen_impl, "freopen64");

            // Wide character I/O (fwide.c, fgetwc.c, fgetws.c, fputwc.c, fputws.c, ungetwc.c)
            symbol(&fwide_impl, "fwide");
            symbol(&fgetwc_unlocked_impl, "__fgetwc_unlocked");
            symbol(&fgetwc_unlocked_impl, "fgetwc_unlocked");
            symbol(&fgetwc_unlocked_impl, "getwc_unlocked");
            symbol(&fgetwc_impl, "fgetwc");
            symbol(&fgetws_impl, "fgetws");
            symbol(&fgetws_impl, "fgetws_unlocked");
            symbol(&fputwc_unlocked_impl, "__fputwc_unlocked");
            symbol(&fputwc_unlocked_impl, "fputwc_unlocked");
            symbol(&fputwc_unlocked_impl, "putwc_unlocked");
            symbol(&fputwc_impl, "fputwc");
            symbol(&fputws_impl, "fputws");
            symbol(&fputws_impl, "fputws_unlocked");
            symbol(&ungetwc_impl, "ungetwc");

            // Variadic printf/scanf wrappers
            symbol(&printf_impl, "printf");
            symbol(&printf_impl, "iprintf");
            symbol(&printf_impl, "__small_printf");
            symbol(&fprintf_impl, "fprintf");
            symbol(&sprintf_impl, "sprintf");
            symbol(&snprintf_impl, "snprintf");
            symbol(&asprintf_impl, "asprintf");
            symbol(&dprintf_impl, "dprintf");
            symbol(&scanf_impl, "scanf");
            symbol(&scanf_impl, "__isoc99_scanf");
            symbol(&fscanf_impl, "fscanf");
            symbol(&fscanf_impl, "__isoc99_fscanf");
            symbol(&sscanf_impl, "sscanf");
            symbol(&sscanf_impl, "__isoc99_sscanf");
            symbol(&wprintf_impl, "wprintf");
            symbol(&fwprintf_impl, "fwprintf");
            symbol(&swprintf_impl, "swprintf");
            symbol(&wscanf_impl, "wscanf");
            symbol(&wscanf_impl, "__isoc99_wscanf");
            symbol(&fwscanf_impl, "fwscanf");
            symbol(&fwscanf_impl, "__isoc99_fwscanf");
            symbol(&swscanf_impl, "swscanf");
            symbol(&swscanf_impl, "__isoc99_swscanf");
        }
    }
}

/// setbuf.c: void setbuf(FILE *restrict f, char *restrict buf)
fn setbuf(f: ?*FILE, buf: ?[*]u8) callconv(.c) void {
    _ = setvbuf_fn(f, buf, if (buf != null) _IOFBF else _IONBF, BUFSIZ);
}

/// setbuffer.c: void setbuffer(FILE *f, char *buf, size_t size)
fn setbuffer(f: ?*FILE, buf: ?[*]u8, size: usize) callconv(.c) void {
    _ = setvbuf_fn(f, buf, if (buf != null) _IOFBF else _IONBF, size);
}

/// setlinebuf.c: void setlinebuf(FILE *f)
fn setlinebuf(f: ?*FILE) callconv(.c) void {
    _ = setvbuf_fn(f, null, _IOLBF, 0);
}

/// getline.c: ssize_t getline(char **s, size_t *n, FILE *f)
fn getline(s: ?*[*]u8, n: ?*usize, f: ?*FILE) callconv(.c) ssize_t {
    return getdelim_fn(s, n, '\n', f);
}

/// getwchar.c: wint_t getwchar(void)
fn getwchar() callconv(.c) wint_t {
    return fgetwc_fn(stdin_ext.*);
}

/// putwchar.c: wint_t putwchar(wchar_t c)
fn putwchar(c: wchar_t) callconv(.c) wint_t {
    return fputwc_fn(c, stdout_ext.*);
}

/// getwc.c: wint_t getwc(FILE *f)
fn getwc(f: ?*FILE) callconv(.c) wint_t {
    return fgetwc_fn(f);
}

/// putwc.c: wint_t putwc(wchar_t c, FILE *f)
fn putwc(c: wchar_t, f: ?*FILE) callconv(.c) wint_t {
    return fputwc_fn(c, f);
}

/// getw.c: int getw(FILE *f)
fn getw(f: ?*FILE) callconv(.c) c_int {
    var x: c_int = undefined;
    return if (fread_fn(&x, @sizeOf(c_int), 1, f) != 0) x else EOF;
}

/// putw.c: int putw(int x, FILE *f)
fn putw(x: c_int, f: ?*FILE) callconv(.c) c_int {
    var val = x;
    return @as(c_int, @intCast(fwrite_fn(&val, @sizeOf(c_int), 1, f))) - 1;
}

/// getchar.c: int getchar(void)
fn getchar() callconv(.c) c_int {
    return fgetc_fn(stdin_ext.*);
}

/// putchar.c: int putchar(int c)
fn putchar(c: c_int) callconv(.c) c_int {
    return fputc_fn(c, stdout_ext.*);
}

/// getchar_unlocked.c: int getchar_unlocked(void)
fn getchar_unlocked() callconv(.c) c_int {
    return getc_unlocked_fn(stdin_ext.*);
}

/// putchar_unlocked.c: int putchar_unlocked(int c)
fn putchar_unlocked(c: c_int) callconv(.c) c_int {
    return putc_unlocked_fn(c, stdout_ext.*);
}

/// Implements musl FLOCK(f) macro: ((f)->lock>=0 ? __lockfile((f)) : 0)
inline fn flock(f: *FILE) c_int {
    if (builtin.target.isWasiLibC()) return 0;
    return if (f.lock >= 0) lockfile_impl(f) else 0;
}

/// Implements musl FUNLOCK(f) macro
inline fn funlock(f: *FILE, need_unlock: c_int) void {
    if (builtin.target.isWasiLibC()) return;
    if (need_unlock != 0) unlockfile_impl(f);
}

/// feof.c: int feof(FILE *f)
fn feof_fn(f: *FILE) callconv(.c) c_int {
    const need_unlock = flock(f);
    const ret: c_int = @intFromBool(f.flags & F_EOF != 0);
    funlock(f, need_unlock);
    return ret;
}

/// ferror.c: int ferror(FILE *f)
fn ferror_fn(f: *FILE) callconv(.c) c_int {
    const need_unlock = flock(f);
    const ret: c_int = @intFromBool(f.flags & F_ERR != 0);
    funlock(f, need_unlock);
    return ret;
}

/// clearerr.c: void clearerr(FILE *f)
fn clearerr(f: *FILE) callconv(.c) void {
    const need_unlock = flock(f);
    f.flags &= ~(F_EOF | F_ERR);
    funlock(f, need_unlock);
}

/// fileno.c: int fileno(FILE *f)
fn fileno(f: *FILE) callconv(.c) c_int {
    const need_unlock = flock(f);
    const fd = f.fd;
    funlock(f, need_unlock);
    if (fd < 0) {
        std.c._errno().* = @backingInt(std.c.E.BADF);
        return -1;
    }
    return fd;
}

/// rewind.c: void rewind(FILE *f)
fn rewind(f: *FILE) callconv(.c) void {
    const need_unlock = flock(f);
    _ = fseeko_unlocked_fn(f, 0, 0); // SEEK_SET = 0
    f.flags &= ~F_ERR;
    funlock(f, need_unlock);
}

/// fgetpos.c: int fgetpos(FILE *f, fpos_t *pos)
fn fgetpos(f: *FILE, pos: *i64) callconv(.c) c_int {
    const off = ftello_fn(f);
    if (off < 0) return -1;
    pos.* = off;
    return 0;
}

/// fsetpos.c: int fsetpos(FILE *f, const fpos_t *pos)
fn fsetpos(f: *FILE, pos: *const i64) callconv(.c) c_int {
    return fseeko_fn(f, pos.*, 0); // SEEK_SET = 0
}

/// fputs.c: int fputs(const char *restrict s, FILE *restrict f)
fn fputs(s: [*:0]const u8, f: *FILE) callconv(.c) c_int {
    const l = std.mem.len(s);
    return @as(c_int, @intCast(@intFromBool(fwrite_fn(s, 1, l, f) == l))) - 1;
}

/// puts.c: int puts(const char *s)
fn puts(s: [*:0]const u8) callconv(.c) c_int {
    const stdout_ptr: *FILE = @ptrCast(stdout_ext.*);
    const need_unlock = flock(stdout_ptr);
    const r: c_int = -@as(c_int, @intFromBool(fputs(s, stdout_ptr) < 0 or putc_unlocked_fn('\n', stdout_ext.*) < 0));
    funlock(stdout_ptr, need_unlock);
    return r;
}

/// gets.c: char *gets(char *s)
fn gets(s: [*]u8) callconv(.c) ?[*]u8 {
    var i: usize = 0;
    const stdin_ptr: *FILE = @ptrCast(stdin_ext.*);
    const need_unlock = flock(stdin_ptr);
    while (true) {
        const c = getc_unlocked_fn(stdin_ext.*);
        if (c == EOF or c == '\n') {
            s[i] = 0;
            if (c != '\n' and (stdin_ptr.flags & F_EOF == 0 or i == 0)) {
                funlock(stdin_ptr, need_unlock);
                return null;
            }
            break;
        }
        s[i] = @intCast(@as(c_uint, @bitCast(c)));
        i += 1;
    }
    funlock(stdin_ptr, need_unlock);
    return s;
}

/// ungetc.c: int ungetc(int c, FILE *f)
fn ungetc(c: c_int, f: *FILE) callconv(.c) c_int {
    if (c == EOF) return c;

    const need_unlock = flock(f);

    if (f.rpos == null) _ = toread_fn(f);
    if (f.rpos == null) {
        funlock(f, need_unlock);
        return EOF;
    }
    // Check: f->rpos <= f->buf - UNGET
    const buf_addr = @intFromPtr(f.buf.?);
    const rpos_addr = @intFromPtr(f.rpos.?);
    if (rpos_addr <= buf_addr -% UNGET) {
        funlock(f, need_unlock);
        return EOF;
    }

    const rpos = f.rpos.?;
    f.rpos = rpos - 1;
    (rpos - 1)[0] = @intCast(@as(c_uint, @bitCast(c)));
    f.flags &= ~F_EOF;

    funlock(f, need_unlock);
    return @as(c_int, @intCast(@as(c_uint, @bitCast(c)) & 0xff));
}

/// setvbuf.c
fn setvbuf(f: *FILE, buf: ?[*]u8, @"type": c_int, size: usize) callconv(.c) c_int {
    f.lbf = EOF;

    if (@"type" == _IONBF) {
        f.buf_size = 0;
    } else if (@"type" == _IOLBF or @"type" == _IOFBF) {
        if (buf != null and size >= UNGET) {
            f.buf = buf.? + UNGET;
            f.buf_size = size - UNGET;
        }
        if (@"type" == _IOLBF and f.buf_size != 0)
            f.lbf = '\n';
    } else {
        return -1;
    }

    f.flags |= F_SVB;
    return 0;
}

/// __fseeko_unlocked from fseek.c
fn __fseeko_unlocked(f: *FILE, off_arg: i64, whence: c_int) callconv(.c) c_int {
    var off = off_arg;

    // Fail immediately for invalid whence argument.
    if (whence != SEEK_CUR and whence != SEEK_SET and whence != SEEK_END) {
        std.c._errno().* = @backingInt(std.c.E.INVAL);
        return -1;
    }

    // Adjust relative offset for unread data in buffer, if any.
    if (whence == SEEK_CUR and f.rend != null) {
        off -= @as(i64, @intCast(@intFromPtr(f.rend.?) - @intFromPtr(f.rpos.?)));
    }

    // Flush write buffer, and report error on failure.
    if (f.wpos != f.wbase) {
        _ = f.write_fn.?(f, @ptrCast(&[0]u8{}), 0);
        if (f.wpos == null) return -1;
    }

    // Leave writing mode
    f.wpos = null;
    f.wbase = null;
    f.wend = null;

    // Perform the underlying seek.
    if (f.seek_fn.?(f, off, whence) < 0) return -1;

    // If seek succeeded, file is seekable and we discard read buffer.
    f.rpos = null;
    f.rend = null;
    f.flags &= ~F_EOF;

    return 0;
}

/// __fseeko from fseek.c
fn __fseeko(f: *FILE, off: i64, whence: c_int) callconv(.c) c_int {
    const need_unlock = flock(f);
    const result = __fseeko_unlocked(f, off, whence);
    funlock(f, need_unlock);
    return result;
}

/// fseek from fseek.c
fn fseek(f: *FILE, off: c_long, whence: c_int) callconv(.c) c_int {
    return __fseeko(f, @intCast(off), whence);
}

/// __ftello_unlocked from ftell.c
fn __ftello_unlocked(f: *FILE) callconv(.c) i64 {
    const pos = f.seek_fn.?(f, 0, if (f.flags & F_APP != 0 and f.wpos != f.wbase) SEEK_END else SEEK_CUR);
    if (pos < 0) return pos;

    // Adjust for data in buffer.
    if (f.rend != null) {
        return pos + @as(i64, @intCast(@as(isize, @intCast(@intFromPtr(f.rpos.?))) - @as(isize, @intCast(@intFromPtr(f.rend.?)))));
    } else if (f.wbase != null) {
        return pos + @as(i64, @intCast(@as(isize, @intCast(@intFromPtr(f.wpos.?))) - @as(isize, @intCast(@intFromPtr(f.wbase.?)))));
    }
    return pos;
}

/// __ftello from ftell.c
fn __ftello(f: *FILE) callconv(.c) i64 {
    const need_unlock = flock(f);
    const pos = __ftello_unlocked(f);
    funlock(f, need_unlock);
    return pos;
}

/// ftell from ftell.c
fn ftell(f: *FILE) callconv(.c) c_long {
    const pos = __ftello(f);
    if (pos > std.math.maxInt(c_long)) {
        std.c._errno().* = @backingInt(std.c.E.OVERFLOW);
        return -1;
    }
    return @intCast(pos);
}

/// __fwritex from fwrite.c - internal write helper
fn __fwritex(s: [*]const u8, l_arg: usize, f: *FILE) callconv(.c) usize {
    var l = l_arg;

    if (f.wend == null and towrite_fn(f) != 0) return 0;

    if (l > @intFromPtr(f.wend.?) - @intFromPtr(f.wpos.?)) return f.write_fn.?(f, s, l);

    if (f.lbf >= 0) {
        // Match /^(.*\n|)/
        var i = l;
        while (i > 0 and s[i - 1] != '\n') : (i -= 1) {}
        if (i > 0) {
            const n = f.write_fn.?(f, s, i);
            if (n < i) return n;
            const rest = s + i;
            l -= i;
            @memcpy(f.wpos.?[0..l], rest[0..l]);
            f.wpos = f.wpos.? + l;
            return l + i;
        }
    }

    @memcpy(f.wpos.?[0..l], s[0..l]);
    f.wpos = f.wpos.? + l;
    return l + 0; // +0 because no i prefix in this path
}

/// fwrite from fwrite.c
fn fwrite(src: [*]const u8, size: usize, nmemb: usize, f: *FILE) callconv(.c) usize {
    const l = size *% nmemb;
    if (size == 0) return 0;
    const need_unlock = flock(f);
    const k = __fwritex(src, l, f);
    funlock(f, need_unlock);
    return if (k == l) nmemb else k / size;
}

/// fread from fread.c
fn fread(destv: [*]u8, size: usize, nmemb: usize, f: *FILE) callconv(.c) usize {
    const len = size *% nmemb;
    var l = len;
    if (size == 0) return 0;

    const need_unlock = flock(f);

    f.mode |= @bitCast(@as(c_uint, @bitCast(f.mode)) -% 1);

    if (f.rpos != f.rend) {
        // First exhaust the buffer.
        const avail = @intFromPtr(f.rend.?) - @intFromPtr(f.rpos.?);
        const k = @min(avail, l);
        @memcpy(destv[0..k], f.rpos.?[0..k]);
        f.rpos = f.rpos.? + k;
        l -= k;
        if (l == 0) {
            funlock(f, need_unlock);
            return nmemb;
        }
    }

    // Read the remainder directly
    var dest = destv + (len - l);
    while (l > 0) {
        const k = if (toread_fn(f) != 0) @as(usize, 0) else f.read_fn.?(f, dest, l);
        if (k == 0) {
            funlock(f, need_unlock);
            return (len - l) / size;
        }
        l -= k;
        dest += k;
    }

    funlock(f, need_unlock);
    return nmemb;
}

/// fgets.c: char *fgets(char *restrict s, int n, FILE *restrict f)
fn fgets(s: [*]u8, n_arg: c_int, f: *FILE) callconv(.c) ?[*]u8 {
    var p = s;
    var n = n_arg;

    const need_unlock = flock(f);

    if (n <= 1) {
        f.mode |= @bitCast(@as(c_uint, @bitCast(f.mode)) -% 1);
        funlock(f, need_unlock);
        if (n < 1) return null;
        s[0] = 0;
        return s;
    }
    n -= 1;

    while (n > 0) {
        if (f.rpos != f.rend) {
            const rpos = f.rpos.?;
            const rend = f.rend.?;
            const avail = @intFromPtr(rend) - @intFromPtr(rpos);
            const z = std.mem.indexOfScalar(u8, rpos[0..avail], '\n');
            const k_raw = if (z) |idx| idx + 1 else avail;
            const k = @min(k_raw, @as(usize, @intCast(n)));
            @memcpy(p[0..k], rpos[0..k]);
            f.rpos = rpos + k;
            p += k;
            n -= @intCast(k);
            if (z != null or n == 0) break;
        }
        const c = getc_unlocked_fn(@ptrCast(f));
        if (c < 0) {
            if (p == s or f.flags & F_EOF == 0) {
                funlock(f, need_unlock);
                return null;
            }
            break;
        }
        n -= 1;
        p[0] = @intCast(@as(c_uint, @bitCast(c)));
        p += 1;
        if (@as(u8, @intCast(@as(c_uint, @bitCast(c)))) == '\n') break;
    }
    p[0] = 0;

    funlock(f, need_unlock);
    return s;
}

/// _flushlbf: flush all line-buffered streams
fn _flushlbf() callconv(.c) void {
    _ = fflush_fn(null);
}

/// __fsetlocking: set locking type (no-op in musl)
fn __fsetlocking(_: *FILE, _: c_int) callconv(.c) c_int {
    return 0;
}

/// __fwriting: check if stream is in write mode
fn __fwriting(f: *FILE) callconv(.c) c_int {
    return @intFromBool(f.flags & F_NORD != 0 or f.wend != null);
}

/// __freading: check if stream is in read mode
fn __freading(f: *FILE) callconv(.c) c_int {
    return @intFromBool(f.flags & F_NOWR != 0 or f.rend != null);
}

/// __freadable: check if stream is readable
fn __freadable(f: *FILE) callconv(.c) c_int {
    return @intFromBool(f.flags & F_NORD == 0);
}

/// __fwritable: check if stream is writable
fn __fwritable(f: *FILE) callconv(.c) c_int {
    return @intFromBool(f.flags & F_NOWR == 0);
}

/// __flbf: check if stream is line-buffered
fn __flbf(f: *FILE) callconv(.c) c_int {
    return @intFromBool(f.lbf >= 0);
}

/// __fbufsize: get stream buffer size
fn __fbufsize(f: *FILE) callconv(.c) usize {
    return f.buf_size;
}

/// __fpending: get pending write data size
fn __fpending(f: *FILE) callconv(.c) usize {
    return if (f.wend != null) @intFromPtr(f.wpos.?) - @intFromPtr(f.wbase.?) else 0;
}

/// __fpurge: discard all pending data
fn __fpurge(f: *FILE) callconv(.c) c_int {
    f.wpos = null;
    f.wbase = null;
    f.wend = null;
    f.rpos = null;
    f.rend = null;
    return 0;
}

/// __freadahead: bytes available for reading
fn __freadahead(f: *FILE) callconv(.c) usize {
    return if (f.rend != null) @intFromPtr(f.rend.?) - @intFromPtr(f.rpos.?) else 0;
}

/// __freadptr: get pointer to read buffer
fn __freadptr(f: *FILE, sizep: *usize) callconv(.c) ?[*]const u8 {
    if (f.rpos == f.rend) return null;
    sizep.* = @intFromPtr(f.rend.?) - @intFromPtr(f.rpos.?);
    return f.rpos;
}

/// __freadptrinc: advance read pointer
fn __freadptrinc(f: *FILE, inc: usize) callconv(.c) void {
    f.rpos = f.rpos.? + inc;
}

/// __fseterr: set error flag on stream
fn __fseterr(f: *FILE) callconv(.c) void {
    f.flags |= F_ERR;
}

/// remove.c: int remove(const char *path)
fn remove_fn(path: [*:0]const u8) callconv(.c) c_int {
    var r = linux.unlinkat(linux.AT.FDCWD, @ptrCast(path), 0);
    const signed: isize = @bitCast(r);
    if (signed == -@as(isize, @backingInt(linux.E.ISDIR))) {
        r = linux.unlinkat(linux.AT.FDCWD, @ptrCast(path), linux.AT.REMOVEDIR);
    }
    return c_errno(r);
}

/// rename.c: int rename(const char *old, const char *new)
fn rename_fn(old: [*:0]const u8, new: [*:0]const u8) callconv(.c) c_int {
    return c_errno(linux.renameat2(linux.AT.FDCWD, @ptrCast(old), linux.AT.FDCWD, @ptrCast(new), .{}));
}

/// getc_unlocked.c: int getc_unlocked(FILE *f)
/// Implements musl's getc_unlocked macro:
///   ((f)->rpos != (f)->rend) ? *(f)->rpos++ : __uflow((f))
fn getc_unlocked_impl(f: *FILE) callconv(.c) c_int {
    if (f.rpos != f.rend) {
        const c = f.rpos.?[0];
        f.rpos = f.rpos.? + 1;
        return c;
    }
    return uflow_fn(f);
}

/// putc_unlocked.c: int putc_unlocked(int c, FILE *f)
/// Implements musl's putc_unlocked macro:
///   ((unsigned char)(c)!=(f)->lbf && (f)->wpos!=(f)->wend)
///     ? *(f)->wpos++ = (unsigned char)(c) : __overflow((f),(unsigned char)(c))
fn putc_unlocked_impl(c: c_int, f: *FILE) callconv(.c) c_int {
    const uc: u8 = @truncate(@as(c_uint, @bitCast(c)));
    if (uc != @as(u8, @truncate(@as(c_uint, @bitCast(f.lbf)))) and f.wpos != f.wend) {
        f.wpos.?[0] = uc;
        f.wpos = f.wpos.? + 1;
        return uc;
    }
    return overflow_fn(f, uc);
}

/// fgetc.c / getc.c: int fgetc(FILE *f)
fn fgetc_impl(f: *FILE) callconv(.c) c_int {
    const need_unlock = flock(f);
    const c = getc_unlocked_impl(f);
    funlock(f, need_unlock);
    return c;
}

/// fputc.c / putc.c: int fputc(int c, FILE *f)
fn fputc_impl(c: c_int, f: *FILE) callconv(.c) c_int {
    const need_unlock = flock(f);
    const result = putc_unlocked_impl(c, f);
    funlock(f, need_unlock);
    return result;
}

/// __toread.c: int __toread(FILE *f)
/// Transition FILE from write mode to read mode.
fn toread_impl(f: *FILE) callconv(.c) c_int {
    f.mode |= @bitCast(@as(c_uint, @bitCast(f.mode)) -% 1);
    if (f.wpos != f.wbase) {
        _ = f.write_fn.?(f, @ptrCast(&[0]u8{}), 0);
    }
    f.wpos = null;
    f.wbase = null;
    f.wend = null;
    if (f.flags & F_NORD != 0) {
        f.flags |= F_ERR;
        return EOF;
    }
    const end = f.buf.? + f.buf_size;
    f.rpos = end;
    f.rend = end;
    return if (f.flags & F_EOF != 0) EOF else 0;
}

/// __towrite.c: int __towrite(FILE *f)
/// Transition FILE from read mode to write mode.
fn towrite_impl(f: *FILE) callconv(.c) c_int {
    f.mode |= @bitCast(@as(c_uint, @bitCast(f.mode)) -% 1);
    if (f.flags & F_NOWR != 0) {
        f.flags |= F_ERR;
        return EOF;
    }
    f.rpos = null;
    f.rend = null;
    f.wpos = f.buf;
    f.wbase = f.buf;
    f.wend = f.buf.? + f.buf_size;
    return 0;
}

/// __uflow.c: int __uflow(FILE *f)
/// Refill read buffer and return one byte, or EOF.
fn uflow_impl(f: *FILE) callconv(.c) c_int {
    var c: u8 = undefined;
    if (toread_impl(f) == 0 and f.read_fn.?(f, @as([*]u8, @ptrCast(&c)), 1) == 1) return c;
    return EOF;
}

/// __overflow.c: int __overflow(FILE *f, int _c)
/// Write one byte through the buffer, flushing if needed.
fn overflow_impl(f: *FILE, _c: c_int) callconv(.c) c_int {
    var c: u8 = @truncate(@as(c_uint, @bitCast(_c)));
    if (f.wend == null and towrite_impl(f) != 0) return EOF;
    if (f.wpos != f.wend and @as(c_int, c) != f.lbf) {
        f.wpos.?[0] = c;
        f.wpos = f.wpos.? + 1;
        return c;
    }
    if (f.write_fn.?(f, @as([*]const u8, @ptrCast(&c)), 1) != 1) return EOF;
    return c;
}

/// fprintf.c: int fprintf(FILE *restrict f, const char *restrict fmt, ...)
/// printf.c: int printf(const char *restrict fmt, ...)
/// snprintf.c: int snprintf(char *restrict s, size_t n, const char *restrict fmt, ...)
/// sprintf.c: int sprintf(char *restrict s, const char *restrict fmt, ...)
/// asprintf.c: int asprintf(char **s, const char *fmt, ...)
/// dprintf.c: int dprintf(int fd, const char *restrict fmt, ...)
/// scanf.c: int scanf(const char *restrict fmt, ...)
/// fscanf.c: int fscanf(FILE *restrict f, const char *restrict fmt, ...)
/// sscanf.c: int sscanf(const char *restrict s, const char *restrict fmt, ...)
/// perror.c: void perror(const char *msg)
fn perror_impl(msg: ?[*:0]const u8) callconv(.c) void {
    const f: *FILE = @ptrCast(stderr_ext.*);
    const errstr = strerror_fn(std.c._errno().*);
    const need_unlock = flock(f);
    // Save stderr's orientation and encoding rule, since perror is not
    // permitted to change them.
    const old_locale = f.locale;
    const old_mode = f.mode;
    if (msg) |m| {
        if (m[0] != 0) {
            _ = fwrite(m, std.mem.len(m), 1, f);
            _ = fputc_impl(':', f);
            _ = fputc_impl(' ', f);
        }
    }
    _ = fwrite(errstr, std.mem.len(errstr), 1, f);
    _ = fputc_impl('\n', f);
    f.mode = old_mode;
    f.locale = old_locale;
    funlock(f, need_unlock);
}

/// __fmodeflags.c: int __fmodeflags(const char *mode)
/// Parse fopen-style mode string to O_* flags.
fn fmodeflags_impl(mode: [*:0]const u8) callconv(.c) c_int {
    // Check for '+', 'x', 'e' anywhere in the mode string
    var has_plus = false;
    var has_x = false;
    var has_e = false;
    {
        var p = mode;
        while (p[0] != 0) : (p += 1) {
            switch (p[0]) {
                '+' => has_plus = true,
                'x' => has_x = true,
                'e' => has_e = true,
                else => {},
            }
        }
    }
    if (builtin.target.isWasiLibC()) {
        var o = std.c.O{};
        if (has_plus) {
            o.read = true;
            o.write = true;
        } else if (mode[0] == 'r') {
            o.read = true;
        } else {
            o.write = true;
        }
        if (has_x) o.EXCL = true;
        if (mode[0] != 'r') o.CREAT = true;
        if (mode[0] == 'w') o.TRUNC = true;
        if (mode[0] == 'a') o.APPEND = true;
        return @bitCast(@as(u32, @bitCast(o)));
    }
    const O = std.os.linux.O;
    var o = O{};
    if (has_plus)
        o.ACCMODE = .RDWR
    else if (mode[0] == 'r')
        o.ACCMODE = .RDONLY
    else
        o.ACCMODE = .WRONLY;
    if (has_x) o.EXCL = true;
    if (has_e) o.CLOEXEC = true;
    if (mode[0] != 'r') o.CREAT = true;
    if (mode[0] == 'w') o.TRUNC = true;
    if (mode[0] == 'a') o.APPEND = true;
    return @bitCast(@as(u32, @bitCast(o)));
}

/// __fclose_ca.c: int __fclose_ca(FILE *f)
fn fclose_ca_impl(f: *FILE) callconv(.c) c_int {
    return f.close_fn.?(f);
}

// --- Internal helper (__fopen_rb_ca.c) ---

const F_PERM: c_uint = 1;

/// __fopen_rb_ca.c: FILE *__fopen_rb_ca(const char *filename, FILE *f, unsigned char *buf, size_t len)
fn fopen_rb_ca_impl(filename: [*:0]const u8, f: *FILE, buf: [*]u8, len: usize) callconv(.c) ?*FILE {
    f.* = std.mem.zeroes(FILE);
    const fd: c_int = if (builtin.target.isWasiLibC()) blk: {
        const o_rdonly: c_int = @bitCast(@as(u32, @bitCast(std.c.O{ .read = true })));
        const fd_wasi = wasilibc_open_nomode_fn(filename, o_rdonly);
        if (fd_wasi < 0) return null;
        _ = fcntl_fn(fd_wasi, std.c.F.SETFD, @as(c_int, 1)); // FD_CLOEXEC = 1
        break :blk fd_wasi;
    } else blk: {
        const O = linux.O;
        var o = O{};
        o.ACCMODE = .RDONLY;
        o.CLOEXEC = true;
        const fd_raw: isize = @bitCast(linux.openat(linux.AT.FDCWD, @ptrCast(filename), o, 0));
        if (fd_raw < 0) return null;
        const fd_linux: c_int = @intCast(fd_raw);
        _ = linux.fcntl(fd_linux, linux.F.SETFD, @as(usize, linux.FD_CLOEXEC));
        break :blk fd_linux;
    };
    f.flags = F_NOWR | F_PERM;
    f.buf = buf + UNGET;
    f.buf_size = len - UNGET;
    f.read_fn = &stdio_read_impl;
    f.seek_fn = &stdio_seek_impl;
    f.close_fn = &stdio_close_impl;
    f.fd = fd;
    f.lock = -1;
    return f;
}

/// fgetln.c: char *fgetln(FILE *f, size_t *plen)
fn fgetln_impl(f_opaque: ?*FILE, plen: *usize) callconv(.c) ?[*]u8 {
    const f: *FILE = @ptrCast(f_opaque orelse return null);
    var ret: ?[*]u8 = null;
    const need_unlock = flock(f);
    // Push back one byte to ensure the read buffer is populated.
    _ = ungetc(getc_unlocked_impl(f), f);
    if (f.rend) |rend| {
        const rpos = f.rpos orelse rend;
        const len = @intFromPtr(rend) - @intFromPtr(rpos);
        if (memchr_fn(rpos, '\n', len)) |z| {
            ret = rpos;
            const z_next: [*]u8 = @ptrCast(z + 1);
            plen.* = @intFromPtr(z_next) - @intFromPtr(rpos);
            f.rpos = z_next;
        }
    }
    if (ret == null) {
        var tmp_n: usize = 0;
        const l = getdelim_impl(@ptrCast(&f.getln_buf), &tmp_n, '\n', f_opaque);
        if (l > 0) {
            plen.* = @intCast(l);
            ret = f.getln_buf;
        }
    }
    funlock(f, need_unlock);
    return ret;
}

/// __stdio_seek.c: off_t __stdio_seek(FILE *f, off_t off, int whence)
fn stdio_seek_impl(f: *FILE, off: i64, whence: c_int) callconv(.c) i64 {
    return lseek_fn(f.fd, off, whence);
}

// --- Internal I/O (__stdio_close.c) ---

/// __stdio_close.c: int __stdio_close(FILE *f)
fn stdio_close_impl(f: *FILE) callconv(.c) c_int {
    if (builtin.target.isWasiLibC()) {
        return posix_close_fn(f.fd);
    }
    const fd = aio_close_fn(f.fd);
    return c_errno(linux.close(@bitCast(fd)));
}

// --- Internal I/O (__stdio_read.c) ---

/// __stdio_read.c: size_t __stdio_read(FILE *f, unsigned char *buf, size_t len)
fn stdio_read_impl(f: *FILE, buf: [*]u8, len: usize) callconv(.c) usize {
    const has_buf: usize = @intFromBool(f.buf_size != 0);
    var iov = [2]std.posix.iovec{
        .{ .base = buf, .len = len -| has_buf },
        .{ .base = f.buf orelse buf, .len = f.buf_size },
    };
    const cnt: isize = if (builtin.target.isWasiLibC()) blk: {
        break :blk if (iov[0].len != 0)
            readv_fn(f.fd, &iov, 2)
        else
            posix_read_fn(f.fd, iov[1].base, iov[1].len);
    } else blk: {
        const cnt_raw = if (iov[0].len != 0)
            linux.readv(@bitCast(f.fd), &iov, 2)
        else
            linux.read(@bitCast(f.fd), iov[1].base, iov[1].len);
        break :blk @bitCast(cnt_raw);
    };
    if (cnt <= 0) {
        f.flags |= if (cnt != 0) F_ERR else F_EOF;
        return 0;
    }
    const ucnt: usize = @intCast(cnt);
    if (ucnt <= iov[0].len) return ucnt;
    const buf_cnt = ucnt - iov[0].len;
    f.rpos = f.buf;
    f.rend = f.buf.? + buf_cnt;
    if (f.buf_size != 0) {
        buf[len - 1] = f.rpos.?[0];
        f.rpos = f.rpos.? + 1;
    }
    return len;
}

// --- Internal I/O (__stdio_write.c) ---

/// __stdio_write.c: size_t __stdio_write(FILE *f, const unsigned char *buf, size_t len)
fn stdio_write_impl(f: *FILE, buf: [*]const u8, len: usize) callconv(.c) usize {
    const wbase = f.wbase orelse @as([*]u8, @ptrCast(@constCast(buf)));
    const wpos = f.wpos orelse wbase;
    var iovs = [2]std.posix.iovec_const{
        .{ .base = wbase, .len = @intFromPtr(wpos) - @intFromPtr(wbase) },
        .{ .base = buf, .len = len },
    };
    var iov_idx: usize = 0;
    var rem = iovs[0].len + iovs[1].len;
    while (true) {
        const iov_slice: [*]const std.posix.iovec_const = @ptrCast(&iovs[iov_idx]);
        const iovcnt: u32 = @intCast(2 - iov_idx);
        const cnt: isize = if (builtin.target.isWasiLibC())
            writev_fn(f.fd, iov_slice, @intCast(iovcnt))
        else
            @bitCast(linux.writev(@bitCast(f.fd), iov_slice, iovcnt));
        if (cnt == @as(isize, @intCast(rem))) {
            f.wend = f.buf.? + f.buf_size;
            f.wpos = f.buf;
            f.wbase = f.buf;
            return len;
        }
        if (cnt < 0) {
            f.wpos = null;
            f.wbase = null;
            f.wend = null;
            f.flags |= F_ERR;
            return if (iov_idx == 0) 0 else len - iovs[iov_idx].len;
        }
        const ucnt: usize = @intCast(cnt);
        rem -= ucnt;
        if (ucnt > iovs[iov_idx].len) {
            const skip = ucnt - iovs[iov_idx].len;
            iov_idx += 1;
            iovs[iov_idx].base += skip;
            iovs[iov_idx].len -= skip;
        } else {
            iovs[iov_idx].base += ucnt;
            iovs[iov_idx].len -= ucnt;
        }
    }
}

// --- Internal I/O (__stdout_write.c) ---

const TIOCGWINSZ: u32 = 0x5413;

/// __stdout_write.c: size_t __stdout_write(FILE *f, const unsigned char *buf, size_t len)
fn stdout_write_impl(f: *FILE, buf: [*]const u8, len: usize) callconv(.c) usize {
    f.write_fn = &stdio_write_impl;
    if (f.flags & F_SVB == 0) {
        if (builtin.target.isWasiLibC()) {
            if (isatty_fn(f.fd) == 0) f.lbf = -1;
        } else {
            var wsz: [4]u16 = undefined; // struct winsize placeholder
            const r: isize = @bitCast(linux.ioctl(@bitCast(f.fd), TIOCGWINSZ, @intFromPtr(&wsz)));
            if (r != 0) f.lbf = -1;
        }
    }
    return stdio_write_impl(f, buf, len);
}

/// vasprintf.c: int vasprintf(char **s, const char *fmt, va_list ap)
fn vasprintf_impl(s: *?[*]u8, fmt: [*:0]const u8, ap: CVaList) callconv(.c) c_int {
    var ap_src = unpackVaList(ap);
    var ap_copy = @cVaCopy(&ap_src);
    defer @cVaEnd(&ap_copy);
    var dummy: [1]u8 = undefined;
    const l = vsnprintf_impl(&dummy, 0, fmt, passVaList(&ap_copy));
    if (l < 0) return -1;
    const size: usize = @intCast(l);
    const ptr: ?*anyopaque = malloc_fn(size + 1) orelse return -1;
    s.* = @ptrCast(ptr);
    return vsnprintf_impl(s.*.?, size + 1, fmt, passVaList(&ap_src));
}

/// vdprintf.c: int vdprintf(int fd, const char *restrict fmt, va_list ap)
fn vdprintf_impl(fd: c_int, fmt: [*:0]const u8, ap: CVaList) callconv(.c) c_int {
    var f = std.mem.zeroes(FILE);
    f.fd = fd;
    f.lbf = EOF;
    f.write_fn = &stdio_write_impl;
    f.buf = @ptrCast(@constCast(fmt));
    f.buf_size = 0;
    f.lock = -1;
    return vfprintf_impl(@ptrCast(&f), fmt, ap);
}

/// getdelim.c: ssize_t getdelim(char **restrict s, size_t *restrict n, int delim, FILE *restrict f)
fn getdelim_impl(s_raw: ?*[*]u8, n_raw: ?*usize, delim: c_int, f_opaque: ?*FILE) callconv(.c) ssize_t {
    const f: *FILE = @ptrCast(f_opaque orelse return -1);
    const need_unlock = flock(f);

    const n = n_raw orelse {
        setModeErr(f);
        funlock(f, need_unlock);
        setErrno(.INVAL);
        return -1;
    };
    // Reinterpret as *?[*]u8 so we can handle null inner pointer.
    const s: *?[*]u8 = @ptrCast(s_raw orelse {
        setModeErr(f);
        funlock(f, need_unlock);
        setErrno(.INVAL);
        return -1;
    });

    if (s.* == null) n.* = 0;

    var i: usize = 0;
    while (true) {
        var z: ?[*]u8 = null;
        var k: usize = 0;

        if (f.rpos != f.rend) {
            const rpos = f.rpos.?;
            const buf_len = @intFromPtr(f.rend.?) - @intFromPtr(rpos);
            z = memchr_fn(rpos, delim, buf_len);
            k = if (z) |zp|
                @intFromPtr(zp) - @intFromPtr(rpos) + 1
            else
                buf_len;
        }

        if (i + k >= n.*) {
            var m = i + k + 2;
            if (z == null and m < std.math.maxInt(usize) / 4) m += m / 2;
            if (!getdelimRealloc(s, n, m)) {
                const m2 = i + k + 2;
                if (!getdelimRealloc(s, n, m2)) {
                    // Copy as much as fits and ensure no pushback remains.
                    const nk = n.* -| i;
                    if (nk > 0) {
                        @memcpy((s.*).?[i..][0..nk], f.rpos.?[0..nk]);
                        f.rpos = f.rpos.? + nk;
                    }
                    setModeErr(f);
                    funlock(f, need_unlock);
                    setErrno(.NOMEM);
                    return -1;
                }
            }
        }

        if (k > 0) {
            @memcpy((s.*).?[i..][0..k], f.rpos.?[0..k]);
            f.rpos = f.rpos.? + k;
            i += k;
        }

        if (z != null) break;

        const c = getc_unlocked_impl(f);
        if (c == EOF) {
            if (i == 0 or (f.flags & F_EOF == 0)) {
                funlock(f, need_unlock);
                return -1;
            }
            break;
        }

        if (i + 1 >= n.*) {
            // Push byte back for next iteration's realloc.
            f.rpos = f.rpos.? - 1;
            f.rpos.?[0] = @truncate(@as(c_uint, @bitCast(c)));
        } else {
            const uc: u8 = @truncate(@as(c_uint, @bitCast(c)));
            (s.*).?[i] = uc;
            i += 1;
            if (c == delim) break;
        }
    }
    (s.*).?[i] = 0;

    funlock(f, need_unlock);
    return @intCast(i);
}

fn getdelimRealloc(s: *?[*]u8, n: *usize, m: usize) bool {
    const old: ?*anyopaque = if (s.*) |p| @ptrCast(p) else null;
    const new_ptr = realloc_fn(old, m) orelse return false;
    s.* = @ptrCast(new_ptr);
    n.* = m;
    return true;
}

fn setModeErr(f: *FILE) void {
    f.mode |= @bitCast(@as(c_uint, @bitCast(f.mode)) -% 1);
    f.flags |= F_ERR;
}

fn setErrno(e: std.c.E) void {
    std.c._errno().* = @intCast(@backingInt(e));
}

// === vfprintf (from musl src/stdio/vfprintf.c) ===========================

/// Bit positions for modifier flags (all fall within 31 codepoints of space).
const ALT_FORM_BIT: c_uint = 1 << ('#' - ' ');
const ZERO_PAD_BIT: c_uint = 1 << ('0' - ' ');
const LEFT_ADJ_BIT: c_uint = 1 << ('-' - ' ');
const PAD_POS_BIT: c_uint = 1 << (' ' - ' ');
const MARK_POS_BIT: c_uint = 1 << ('+' - ' ');
const GROUPED_BIT: c_uint = 1 << ('\'' - ' ');
const FLAGMASK: c_uint = ALT_FORM_BIT | ZERO_PAD_BIT | LEFT_ADJ_BIT | PAD_POS_BIT | MARK_POS_BIT | GROUPED_BIT;

/// State machine type-classes used by the printf format-spec state table.
const PF_BARE: u8 = 0;
const PF_LPRE: u8 = 1;
const PF_LLPRE: u8 = 2;
const PF_HPRE: u8 = 3;
const PF_HHPRE: u8 = 4;
const PF_BIGLPRE: u8 = 5;
const PF_ZTPRE: u8 = 6;
const PF_JPRE: u8 = 7;
const PF_STOP: u8 = 8;
const PF_PTR: u8 = 9;
const PF_INT: u8 = 10;
const PF_UINT: u8 = 11;
const PF_ULLONG: u8 = 12;
const PF_LONG: u8 = 13;
const PF_ULONG: u8 = 14;
const PF_SHORT: u8 = 15;
const PF_USHORT: u8 = 16;
const PF_CHAR: u8 = 17;
const PF_UCHAR: u8 = 18;
const PF_LLONG: u8 = 19;
const PF_SIZET: u8 = 20;
const PF_IMAX: u8 = 21;
const PF_UMAX: u8 = 22;
const PF_PDIFF: u8 = 23;
const PF_UIPTR: u8 = 24;
const PF_DBL: u8 = 25;
const PF_LDBL: u8 = 26;
const PF_NOARG: u8 = 27;

const NL_ARGMAX: usize = 9;

const PrintfArg = extern union {
    i: c_ulonglong,
    f: c_longdouble,
    p: ?*anyopaque,
};

/// `LDBL_MANT_DIG`, `LDBL_MAX_EXP`, `LDBL_EPSILON` mirroring musl's
/// arch/*/bits/float.h values, derived from the c_longdouble bit width.
const LDBL_MANT_DIG: comptime_int = switch (@bitSizeOf(c_longdouble)) {
    64 => 53,
    80 => 64,
    128 => 113,
    else => @compileError("unsupported c_longdouble bit size"),
};
const LDBL_MAX_EXP: comptime_int = switch (@bitSizeOf(c_longdouble)) {
    64 => 1024,
    80, 128 => 16384,
    else => @compileError("unsupported c_longdouble bit size"),
};
const LDBL_EPSILON: c_longdouble = switch (@bitSizeOf(c_longdouble)) {
    64 => 2.22044604925031308085e-16,
    80 => 1.0842021724855044340e-19,
    128 => 1.92592994438723585305597794258492732e-34,
    else => @compileError("unsupported c_longdouble bit size"),
};

const PF_STATES_W: comptime_int = 'z' - 'A' + 1;

/// `states[][]` table from musl: maps (current state, next character) to
/// either the next prefix state or a terminal type-class.
const pf_states: [8][PF_STATES_W]u8 = blk: {
    @setEvalBranchQuota(50000);
    var t: [8][PF_STATES_W]u8 = @splat(@splat(0));
    // 0: bare
    t[0]['d' - 'A'] = PF_INT;
    t[0]['i' - 'A'] = PF_INT;
    t[0]['o' - 'A'] = PF_UINT;
    t[0]['u' - 'A'] = PF_UINT;
    t[0]['x' - 'A'] = PF_UINT;
    t[0]['X' - 'A'] = PF_UINT;
    t[0]['e' - 'A'] = PF_DBL;
    t[0]['f' - 'A'] = PF_DBL;
    t[0]['g' - 'A'] = PF_DBL;
    t[0]['a' - 'A'] = PF_DBL;
    t[0]['E' - 'A'] = PF_DBL;
    t[0]['F' - 'A'] = PF_DBL;
    t[0]['G' - 'A'] = PF_DBL;
    t[0]['A' - 'A'] = PF_DBL;
    t[0]['c' - 'A'] = PF_INT;
    t[0]['C' - 'A'] = PF_UINT;
    t[0]['s' - 'A'] = PF_PTR;
    t[0]['S' - 'A'] = PF_PTR;
    t[0]['p' - 'A'] = PF_UIPTR;
    t[0]['n' - 'A'] = PF_PTR;
    t[0]['m' - 'A'] = PF_NOARG;
    t[0]['l' - 'A'] = PF_LPRE;
    t[0]['h' - 'A'] = PF_HPRE;
    t[0]['L' - 'A'] = PF_BIGLPRE;
    t[0]['z' - 'A'] = PF_ZTPRE;
    t[0]['j' - 'A'] = PF_JPRE;
    t[0]['t' - 'A'] = PF_ZTPRE;
    // 1: l-prefixed
    t[1]['d' - 'A'] = PF_LONG;
    t[1]['i' - 'A'] = PF_LONG;
    t[1]['o' - 'A'] = PF_ULONG;
    t[1]['u' - 'A'] = PF_ULONG;
    t[1]['x' - 'A'] = PF_ULONG;
    t[1]['X' - 'A'] = PF_ULONG;
    t[1]['e' - 'A'] = PF_DBL;
    t[1]['f' - 'A'] = PF_DBL;
    t[1]['g' - 'A'] = PF_DBL;
    t[1]['a' - 'A'] = PF_DBL;
    t[1]['E' - 'A'] = PF_DBL;
    t[1]['F' - 'A'] = PF_DBL;
    t[1]['G' - 'A'] = PF_DBL;
    t[1]['A' - 'A'] = PF_DBL;
    t[1]['c' - 'A'] = PF_UINT;
    t[1]['s' - 'A'] = PF_PTR;
    t[1]['n' - 'A'] = PF_PTR;
    t[1]['l' - 'A'] = PF_LLPRE;
    // 2: ll-prefixed
    t[2]['d' - 'A'] = PF_LLONG;
    t[2]['i' - 'A'] = PF_LLONG;
    t[2]['o' - 'A'] = PF_ULLONG;
    t[2]['u' - 'A'] = PF_ULLONG;
    t[2]['x' - 'A'] = PF_ULLONG;
    t[2]['X' - 'A'] = PF_ULLONG;
    t[2]['n' - 'A'] = PF_PTR;
    // 3: h-prefixed
    t[3]['d' - 'A'] = PF_SHORT;
    t[3]['i' - 'A'] = PF_SHORT;
    t[3]['o' - 'A'] = PF_USHORT;
    t[3]['u' - 'A'] = PF_USHORT;
    t[3]['x' - 'A'] = PF_USHORT;
    t[3]['X' - 'A'] = PF_USHORT;
    t[3]['n' - 'A'] = PF_PTR;
    t[3]['h' - 'A'] = PF_HHPRE;
    // 4: hh-prefixed
    t[4]['d' - 'A'] = PF_CHAR;
    t[4]['i' - 'A'] = PF_CHAR;
    t[4]['o' - 'A'] = PF_UCHAR;
    t[4]['u' - 'A'] = PF_UCHAR;
    t[4]['x' - 'A'] = PF_UCHAR;
    t[4]['X' - 'A'] = PF_UCHAR;
    t[4]['n' - 'A'] = PF_PTR;
    // 5: L-prefixed
    t[5]['e' - 'A'] = PF_LDBL;
    t[5]['f' - 'A'] = PF_LDBL;
    t[5]['g' - 'A'] = PF_LDBL;
    t[5]['a' - 'A'] = PF_LDBL;
    t[5]['E' - 'A'] = PF_LDBL;
    t[5]['F' - 'A'] = PF_LDBL;
    t[5]['G' - 'A'] = PF_LDBL;
    t[5]['A' - 'A'] = PF_LDBL;
    t[5]['n' - 'A'] = PF_PTR;
    // 6: z- or t-prefixed
    t[6]['d' - 'A'] = PF_PDIFF;
    t[6]['i' - 'A'] = PF_PDIFF;
    t[6]['o' - 'A'] = PF_SIZET;
    t[6]['u' - 'A'] = PF_SIZET;
    t[6]['x' - 'A'] = PF_SIZET;
    t[6]['X' - 'A'] = PF_SIZET;
    t[6]['n' - 'A'] = PF_PTR;
    // 7: j-prefixed
    t[7]['d' - 'A'] = PF_IMAX;
    t[7]['i' - 'A'] = PF_IMAX;
    t[7]['o' - 'A'] = PF_UMAX;
    t[7]['u' - 'A'] = PF_UMAX;
    t[7]['x' - 'A'] = PF_UMAX;
    t[7]['X' - 'A'] = PF_UMAX;
    t[7]['n' - 'A'] = PF_PTR;
    break :blk t;
};

/// musl OOB(x): (unsigned)(x)-'A' > 'z'-'A'
inline fn pf_oob(c: u8) bool {
    return @as(c_uint, c) -% 'A' > 'z' - 'A';
}

fn pop_arg(arg: *PrintfArg, ty: u8, ap: *VaList) callconv(.c) void {
    switch (ty) {
        PF_PTR => arg.p = cVaArg(ap, ?*anyopaque),
        PF_INT => arg.i = @bitCast(@as(c_longlong, cVaArg(ap, c_int))),
        PF_UINT => arg.i = cVaArg(ap, c_uint),
        PF_LONG => arg.i = @bitCast(@as(c_longlong, cVaArg(ap, c_long))),
        PF_ULONG => arg.i = cVaArg(ap, c_ulong),
        PF_ULLONG => arg.i = cVaArg(ap, c_ulonglong),
        PF_SHORT => arg.i = @bitCast(@as(c_longlong, @as(c_short, @truncate(cVaArg(ap, c_int))))),
        PF_USHORT => arg.i = @as(c_ushort, @truncate(@as(c_uint, @bitCast(cVaArg(ap, c_int))))),
        PF_CHAR => arg.i = @bitCast(@as(c_longlong, @as(i8, @truncate(cVaArg(ap, c_int))))),
        PF_UCHAR => arg.i = @as(u8, @truncate(@as(c_uint, @bitCast(cVaArg(ap, c_int))))),
        PF_LLONG => arg.i = @bitCast(cVaArg(ap, c_longlong)),
        PF_SIZET => arg.i = cVaArg(ap, usize),
        PF_IMAX => arg.i = @bitCast(cVaArg(ap, c_longlong)),
        PF_UMAX => arg.i = cVaArg(ap, c_ulonglong),
        PF_PDIFF => arg.i = @bitCast(@as(c_longlong, cVaArg(ap, isize))),
        PF_UIPTR => arg.i = @intFromPtr(cVaArg(ap, ?*anyopaque)),
        PF_DBL => arg.f = @floatCast(cVaArg(ap, f64)),
        PF_LDBL => arg.f = cVaArg(ap, c_longdouble),
        else => {},
    }
}

/// musl `out`: write only when stream is not in error state.
inline fn pf_out(f: ?*FILE, s: [*]const u8, l: usize) void {
    if (f) |ff| {
        if (ff.flags & F_ERR == 0) _ = __fwritex(s, l, ff);
    }
}

/// musl `pad`: emit (w-l) copies of `c` unless LEFT_ADJ/ZERO_PAD set, or already wide enough.
fn pf_pad(f: ?*FILE, c: u8, w: c_int, l_in: c_int, fl: c_uint) void {
    var l = l_in;
    if ((fl & (LEFT_ADJ_BIT | ZERO_PAD_BIT)) != 0 or l >= w) return;
    l = w - l;
    var buf: [256]u8 = undefined;
    const fill: usize = @intCast(@min(l, @as(c_int, buf.len)));
    @memset(buf[0..fill], c);
    while (l >= buf.len) : (l -= buf.len) pf_out(f, &buf, buf.len);
    pf_out(f, &buf, @intCast(l));
}

const pf_xdigits: [16]u8 = "0123456789ABCDEF".*;

/// Write hex digits of x backwards into the buffer ending at `s_end`.
fn fmt_x(x: c_ulonglong, s_end: [*]u8, lower: c_int) [*]u8 {
    var s = s_end;
    var v = x;
    while (v != 0) : (v >>= 4) {
        s -= 1;
        s[0] = pf_xdigits[@as(usize, @intCast(v & 15))] | @as(u8, @intCast(lower));
    }
    return s;
}

fn fmt_o(x: c_ulonglong, s_end: [*]u8) [*]u8 {
    var s = s_end;
    var v = x;
    while (v != 0) : (v >>= 3) {
        s -= 1;
        s[0] = '0' + @as(u8, @intCast(v & 7));
    }
    return s;
}

fn fmt_u(x: c_ulonglong, s_end: [*]u8) [*]u8 {
    var s = s_end;
    var v = x;
    // Reduce above ULONG_MAX using c_ulonglong division.
    while (v > std.math.maxInt(c_ulong)) : (v /= 10) {
        s -= 1;
        s[0] = '0' + @as(u8, @intCast(v % 10));
    }
    var y: c_ulong = @intCast(v);
    while (y != 0) : (y /= 10) {
        s -= 1;
        s[0] = '0' + @as(u8, @intCast(y % 10));
    }
    return s;
}

/// Floating-point formatter (musl `fmt_fp`). Returns the printed length,
/// or -1 on overflow (errno is NOT set here; caller checks).
fn fmt_fp(f: ?*FILE, y_in: c_longdouble, w: c_int, p_in: c_int, fl_in: c_uint, t_in: c_int) c_int {
    var y = y_in;
    var p = p_in;
    const fl = fl_in;
    var t = t_in;

    // Mantissa expansion + exponent expansion words.
    const big_words: comptime_int = (LDBL_MANT_DIG + 28) / 29 + 1 + (LDBL_MAX_EXP + LDBL_MANT_DIG + 28 + 8) / 9;
    var big: [big_words]u32 = undefined;
    var a: [*]u32 = undefined;
    var d: [*]u32 = undefined;
    var r: [*]u32 = undefined;
    var z: [*]u32 = undefined;
    var e2: c_int = 0;
    var e: c_int = undefined;
    var i: c_int = undefined;
    var j: c_int = undefined;
    var l: c_int = undefined;
    var buf: [9 + LDBL_MANT_DIG / 4]u8 = undefined;
    var s: [*]u8 = undefined;
    var prefix: [*]const u8 = "-0X+0X 0X-0x+0x 0x";
    var pl: c_int = undefined;
    var ebuf0: [3 * @sizeOf(c_int)]u8 = undefined;
    const ebuf: [*]u8 = @as([*]u8, &ebuf0) + ebuf0.len;
    var estr: [*]u8 = undefined;

    pl = 1;
    if (std.math.signbit(y)) {
        y = -y;
    } else if ((fl & MARK_POS_BIT) != 0) {
        prefix += 3;
    } else if ((fl & PAD_POS_BIT) != 0) {
        prefix += 6;
    } else {
        prefix += 1;
        pl = 0;
    }

    const is_unnormal_f80 = @typeInfo(c_longdouble).float.bits == 80 and blk: {
        const ux: u80 = @bitCast(y);
        const exp: u16 = @truncate((ux >> 64) & 0x7fff);
        const msb: u1 = @truncate(ux >> 63);
        break :blk exp != 0 and msb == 0;
    };
    if (!std.math.isFinite(y) or is_unnormal_f80) {
        const lower_inf: [*]const u8 = "inf";
        const upper_inf: [*]const u8 = "INF";
        const lower_nan: [*]const u8 = "nan";
        const upper_nan: [*]const u8 = "NAN";
        var sptr: [*]const u8 = if ((t & 32) != 0) lower_inf else upper_inf;
        if (std.math.isNan(y) or is_unnormal_f80) sptr = if ((t & 32) != 0) lower_nan else upper_nan;
        pf_pad(f, ' ', w, 3 + pl, fl & ~ZERO_PAD_BIT);
        pf_out(f, prefix, @intCast(pl));
        pf_out(f, sptr, 3);
        pf_pad(f, ' ', w, 3 + pl, fl ^ LEFT_ADJ_BIT);
        return @max(w, 3 + pl);
    }

    {
        const fr = std.math.frexp(y);
        y = fr.significand * 2;
        e2 = fr.exponent;
    }
    if (y != 0) e2 -= 1;

    if ((t | 32) == 'a') {
        var round: c_longdouble = 8.0;
        var re: c_int = undefined;

        if ((t & 32) != 0) prefix += 9;
        pl += 2;

        if (p < 0 or p >= LDBL_MANT_DIG / 4 - 1) {
            re = 0;
        } else {
            re = LDBL_MANT_DIG / 4 - 1 - p;
        }

        if (re != 0) {
            round *= @as(c_longdouble, @floatFromInt(@as(c_int, 1) << (LDBL_MANT_DIG % 4)));
            while (re != 0) : (re -= 1) round *= 16;
            if (prefix[0] == '-') {
                y = -y;
                y -= round;
                y += round;
                y = -y;
            } else {
                y += round;
                y -= round;
            }
        }

        estr = fmt_u(@bitCast(@as(c_longlong, if (e2 < 0) -e2 else e2)), ebuf);
        if (estr == ebuf) {
            estr -= 1;
            estr[0] = '0';
        }
        estr -= 1;
        estr[0] = if (e2 < 0) '-' else '+';
        estr -= 1;
        estr[0] = @as(u8, @intCast(t)) + ('p' - 'a');

        s = &buf;
        while (true) {
            const ix: c_int = @intFromFloat(y);
            s[0] = pf_xdigits[@as(usize, @intCast(ix))] | @as(u8, @intCast(t & 32));
            s += 1;
            y = 16 * (y - @as(c_longdouble, @floatFromInt(ix)));
            if (@intFromPtr(s) - @intFromPtr(&buf) == 1 and (y != 0 or p > 0 or (fl & ALT_FORM_BIT) != 0)) {
                s[0] = '.';
                s += 1;
            }
            if (y == 0) break;
        }

        const ebuf_minus_estr: c_int = @intCast(@intFromPtr(ebuf) - @intFromPtr(estr));
        if (p > std.math.maxInt(c_int) - 2 - ebuf_minus_estr - pl) return -1;
        const sbuf_diff: c_int = @intCast(@intFromPtr(s) - @intFromPtr(&buf));
        if (p != 0 and sbuf_diff - 2 < p) {
            l = (p + 2) + ebuf_minus_estr;
        } else {
            l = sbuf_diff + ebuf_minus_estr;
        }

        pf_pad(f, ' ', w, pl + l, fl);
        pf_out(f, prefix, @intCast(pl));
        pf_pad(f, '0', w, pl + l, fl ^ ZERO_PAD_BIT);
        pf_out(f, &buf, @intCast(sbuf_diff));
        pf_pad(f, '0', l - ebuf_minus_estr - sbuf_diff, 0, 0);
        pf_out(f, estr, @intCast(ebuf_minus_estr));
        pf_pad(f, ' ', w, pl + l, fl ^ LEFT_ADJ_BIT);
        return @max(w, pl + l);
    }
    if (p < 0) p = 6;

    if (y != 0) {
        y *= 0x1p28;
        e2 -= 28;
    }

    if (e2 < 0) {
        a = &big;
        r = a;
        z = a;
    } else {
        const off: usize = big.len - LDBL_MANT_DIG - 1;
        a = @as([*]u32, &big) + off;
        r = a;
        z = a;
    }

    while (true) {
        z[0] = @intFromFloat(y);
        const zv: c_longdouble = @floatFromInt(z[0]);
        z += 1;
        y = 1000000000 * (y - zv);
        if (y == 0) break;
    }

    while (e2 > 0) {
        var carry: u32 = 0;
        const sh: c_int = @min(@as(c_int, 29), e2);
        d = z - 1;
        while (@intFromPtr(d) >= @intFromPtr(a)) : (d -= 1) {
            const x: u64 = (@as(u64, d[0]) << @intCast(sh)) + carry;
            d[0] = @intCast(x % 1000000000);
            carry = @intCast(x / 1000000000);
            if (d == a) break;
        }
        if (carry != 0) {
            a -= 1;
            a[0] = carry;
        }
        while (@intFromPtr(z) > @intFromPtr(a) and (z - 1)[0] == 0) z -= 1;
        e2 -= sh;
    }
    while (e2 < 0) {
        var carry: u32 = 0;
        const sh: c_int = @min(@as(c_int, 9), -e2);
        const need: c_int = 1 + @divFloor(p + @as(c_int, LDBL_MANT_DIG / 3) + 8, 9);
        d = a;
        while (@intFromPtr(d) < @intFromPtr(z)) : (d += 1) {
            const mask: u32 = (@as(u32, 1) << @intCast(sh)) - 1;
            const rm: u32 = d[0] & mask;
            d[0] = (d[0] >> @intCast(sh)) + carry;
            carry = (@as(u32, 1000000000) >> @intCast(sh)) * rm;
        }
        if (a[0] == 0) a += 1;
        if (carry != 0) {
            z[0] = carry;
            z += 1;
        }
        const b: [*]u32 = if ((t | 32) == 'f') r else a;
        const zb_diff: c_int = @intCast(@as(isize, @bitCast(@intFromPtr(z) -% @intFromPtr(b))) >> 2);
        if (zb_diff > need) z = b + @as(usize, @intCast(need));
        e2 += sh;
    }

    if (@intFromPtr(a) < @intFromPtr(z)) {
        i = 10;
        e = 9 * @as(c_int, @intCast(@as(isize, @bitCast(@intFromPtr(r) -% @intFromPtr(a))) >> 2));
        while (a[0] >= @as(u32, @intCast(i))) : ({
            i *= 10;
            e += 1;
        }) {}
    } else {
        e = 0;
    }

    // Perform rounding: j is precision after the radix (possibly negative).
    {
        const f_match: c_int = @intFromBool((t | 32) != 'f');
        const g_match: c_int = @intFromBool((t | 32) == 'g' and p != 0);
        j = p - f_match * e - g_match;
    }
    {
        const z_r_minus_one: c_int = @intCast(@as(isize, @bitCast(@intFromPtr(z) -% @intFromPtr(r))) >> 2);
        if (j < 9 * (z_r_minus_one - 1)) {
            const j_off: c_int = @divTrunc(j + 9 * @as(c_int, LDBL_MAX_EXP), 9) - @as(c_int, LDBL_MAX_EXP);
            const d_addr: isize = @as(isize, @bitCast(@intFromPtr(r))) +
                (@as(isize, 1) + @as(isize, j_off)) * @sizeOf(u32);
            d = @ptrFromInt(@as(usize, @bitCast(d_addr)));
            var jj: c_int = j + 9 * @as(c_int, LDBL_MAX_EXP);
            jj = @mod(jj, 9);
            i = 10;
            jj += 1;
            while (jj < 9) : ({
                i *= 10;
                jj += 1;
            }) {}
            const x: u32 = d[0] % @as(u32, @intCast(i));
            if (x != 0 or (d + 1) != z) {
                var round: c_longdouble = 2 / LDBL_EPSILON;
                var small: c_longdouble = undefined;
                if (((d[0] / @as(u32, @intCast(i))) & 1) != 0 or
                    (i == 1000000000 and @intFromPtr(d) > @intFromPtr(a) and ((d - 1)[0] & 1) != 0))
                {
                    round += 2;
                }
                if (x < @as(u32, @intCast(i)) / 2) {
                    small = 0x0.8p0;
                } else if (x == @as(u32, @intCast(i)) / 2 and (d + 1) == z) {
                    small = 0x1.0p0;
                } else {
                    small = 0x1.8p0;
                }
                if (pl != 0 and prefix[0] == '-') {
                    round *= -1;
                    small *= -1;
                }
                d[0] -= x;
                if (round + small != round) {
                    d[0] = d[0] + @as(u32, @intCast(i));
                    while (d[0] > 999999999) {
                        d[0] = 0;
                        d -= 1;
                        if (@intFromPtr(d) < @intFromPtr(a)) {
                            a -= 1;
                            a[0] = 0;
                            d = a;
                        }
                        d[0] += 1;
                    }
                    i = 10;
                    e = 9 * @as(c_int, @intCast(@as(isize, @bitCast(@intFromPtr(r) -% @intFromPtr(a))) >> 2));
                    while (a[0] >= @as(u32, @intCast(i))) : ({
                        i *= 10;
                        e += 1;
                    }) {}
                }
            }
            if (@intFromPtr(z) > @intFromPtr(d + 1)) z = d + 1;
        }
    }
    while (@intFromPtr(z) > @intFromPtr(a) and (z - 1)[0] == 0) z -= 1;

    if ((t | 32) == 'g') {
        if (p == 0) p += 1;
        if (p > e and e >= -4) {
            t -= 1;
            p -= e + 1;
        } else {
            t -= 2;
            p -= 1;
        }
        if ((fl & ALT_FORM_BIT) == 0) {
            const z_r_minus_one: c_int = @intCast(@as(isize, @bitCast(@intFromPtr(z) -% @intFromPtr(r))) >> 2);
            if (@intFromPtr(z) > @intFromPtr(a) and (z - 1)[0] != 0) {
                i = 10;
                j = 0;
                while ((z - 1)[0] % @as(u32, @intCast(i)) == 0) : ({
                    i *= 10;
                    j += 1;
                }) {}
            } else {
                j = 9;
            }
            if ((t | 32) == 'f') {
                p = @min(p, @max(@as(c_int, 0), 9 * (z_r_minus_one - 1) - j));
            } else {
                p = @min(p, @max(@as(c_int, 0), 9 * (z_r_minus_one - 1) + e - j));
            }
        }
    }
    {
        const extra: c_int = @intFromBool(p != 0 or (fl & ALT_FORM_BIT) != 0);
        if (p > std.math.maxInt(c_int) - 1 - extra) return -1;
        l = 1 + p + extra;
    }
    if ((t | 32) == 'f') {
        if (e > std.math.maxInt(c_int) - l) return -1;
        if (e > 0) l += e;
    } else {
        estr = fmt_u(@bitCast(@as(c_longlong, if (e < 0) -e else e)), ebuf);
        while (@intFromPtr(ebuf) - @intFromPtr(estr) < 2) {
            estr -= 1;
            estr[0] = '0';
        }
        estr -= 1;
        estr[0] = if (e < 0) '-' else '+';
        estr -= 1;
        estr[0] = @intCast(t);
        const eb_diff: c_int = @intCast(@intFromPtr(ebuf) - @intFromPtr(estr));
        if (eb_diff > std.math.maxInt(c_int) - l) return -1;
        l += eb_diff;
    }

    if (l > std.math.maxInt(c_int) - pl) return -1;
    pf_pad(f, ' ', w, pl + l, fl);
    pf_out(f, prefix, @intCast(pl));
    pf_pad(f, '0', w, pl + l, fl ^ ZERO_PAD_BIT);

    if ((t | 32) == 'f') {
        if (@intFromPtr(a) > @intFromPtr(r)) a = r;
        d = a;
        while (@intFromPtr(d) <= @intFromPtr(r)) : (d += 1) {
            var sp: [*]u8 = fmt_u(d[0], @as([*]u8, &buf) + 9);
            if (d != a) {
                while (@intFromPtr(sp) > @intFromPtr(&buf)) {
                    sp -= 1;
                    sp[0] = '0';
                }
            } else if (sp == @as([*]u8, &buf) + 9) {
                sp -= 1;
                sp[0] = '0';
            }
            pf_out(f, sp, @intFromPtr(&buf) + 9 - @intFromPtr(sp));
        }
        if (p != 0 or (fl & ALT_FORM_BIT) != 0) pf_out(f, ".", 1);
        while (@intFromPtr(d) < @intFromPtr(z) and p > 0) : ({
            d += 1;
            p -= 9;
        }) {
            var sp: [*]u8 = fmt_u(d[0], @as([*]u8, &buf) + 9);
            while (@intFromPtr(sp) > @intFromPtr(&buf)) {
                sp -= 1;
                sp[0] = '0';
            }
            pf_out(f, sp, @intCast(@min(@as(c_int, 9), p)));
        }
        pf_pad(f, '0', p + 9, 9, 0);
    } else {
        if (@intFromPtr(z) <= @intFromPtr(a)) z = a + 1;
        d = a;
        while (@intFromPtr(d) < @intFromPtr(z) and p >= 0) : (d += 1) {
            var sp: [*]u8 = fmt_u(d[0], @as([*]u8, &buf) + 9);
            if (sp == @as([*]u8, &buf) + 9) {
                sp -= 1;
                sp[0] = '0';
            }
            if (d != a) {
                while (@intFromPtr(sp) > @intFromPtr(&buf)) {
                    sp -= 1;
                    sp[0] = '0';
                }
            } else {
                pf_out(f, sp, 1);
                sp += 1;
                if (p > 0 or (fl & ALT_FORM_BIT) != 0) pf_out(f, ".", 1);
            }
            const remain: usize = @intFromPtr(&buf) + 9 - @intFromPtr(sp);
            const emit: usize = @min(remain, @as(usize, @intCast(@max(@as(c_int, 0), p))));
            pf_out(f, sp, emit);
            p -= @intCast(remain);
        }
        pf_pad(f, '0', p + 18, 18, 0);
        const eb_diff: usize = @intFromPtr(ebuf) - @intFromPtr(estr);
        pf_out(f, estr, eb_diff);
    }

    pf_pad(f, ' ', w, pl + l, fl ^ LEFT_ADJ_BIT);
    return @max(w, pl + l);
}

fn pf_getint(sp: *[*]const u8) c_int {
    var i: c_int = 0;
    while (true) {
        const c = sp.*[0];
        if (c < '0' or c > '9') break;
        const digit: c_int = @as(c_int, c) - '0';
        if (@as(c_uint, @bitCast(i)) > std.math.maxInt(c_int) / 10 or
            digit > std.math.maxInt(c_int) - 10 * i)
        {
            i = -1;
        } else {
            i = 10 * i + digit;
        }
        sp.* += 1;
    }
    return i;
}

/// musl printf_core: walks the format string, either counting positional
/// arg classes (when `f == null`) or emitting formatted output to `f`.
fn printf_core(
    f: ?*FILE,
    fmt_arg: [*:0]const u8,
    ap: *VaList,
    nl_arg: *[NL_ARGMAX + 1]PrintfArg,
    nl_type: *[NL_ARGMAX + 1]c_int,
) callconv(.c) c_int {
    var s: [*]const u8 = fmt_arg;
    var l10n: c_uint = 0;
    var fl: c_uint = undefined;
    var w: c_int = undefined;
    var p: c_int = undefined;
    var xp: c_int = undefined;
    var arg: PrintfArg = std.mem.zeroes(PrintfArg);
    var argpos: c_int = undefined;
    var st: u8 = undefined;
    var ps: u8 = undefined;
    var cnt: c_int = 0;
    var l: c_int = 0;
    var i: usize = undefined;
    var buf: [@sizeOf(c_ulonglong) * 3]u8 = undefined;
    var prefix: [*]const u8 = undefined;
    var t: c_int = undefined;
    var pl: c_int = undefined;
    var wc: [2]wchar_t = undefined;
    var ws: [*]const wchar_t = undefined;
    var mb: [4]u8 = undefined;
    var a: [*]u8 = undefined;
    var zp: [*]u8 = undefined;

    while (true) {
        if (l > std.math.maxInt(c_int) - cnt) {
            setErrno(.OVERFLOW);
            return -1;
        }

        cnt += l;
        if (s[0] == 0) break;

        const a_lit = s;
        while (s[0] != 0 and s[0] != '%') s += 1;
        var z_lit = s;
        while (s[0] == '%' and s[1] == '%') {
            z_lit += 1;
            s += 2;
        }
        const lit_len: isize = @intCast(@intFromPtr(z_lit) - @intFromPtr(a_lit));
        if (lit_len > std.math.maxInt(c_int) - cnt) {
            setErrno(.OVERFLOW);
            return -1;
        }
        l = @intCast(lit_len);
        if (f != null) pf_out(f, a_lit, @intCast(l));
        if (l != 0) continue;

        if (s[1] >= '0' and s[1] <= '9' and s[2] == '$') {
            l10n = 1;
            argpos = @as(c_int, s[1]) - '0';
            s += 3;
        } else {
            argpos = -1;
            s += 1;
        }

        fl = 0;
        while (true) {
            const c = s[0];
            const bit: c_uint = @as(c_uint, c) -% ' ';
            if (bit >= 32) break;
            if ((FLAGMASK & (@as(c_uint, 1) << @as(u5, @intCast(bit)))) == 0) break;
            fl |= @as(c_uint, 1) << @as(u5, @intCast(bit));
            s += 1;
        }

        if (s[0] == '*') {
            if (s[1] >= '0' and s[1] <= '9' and s[2] == '$') {
                l10n = 1;
                if (f == null) {
                    nl_type[s[1] - '0'] = PF_INT;
                    w = 0;
                } else {
                    w = @intCast(nl_arg[s[1] - '0'].i);
                }
                s += 3;
            } else if (l10n == 0) {
                w = if (f != null) cVaArg(ap, c_int) else 0;
                s += 1;
            } else {
                setErrno(.INVAL);
                return -1;
            }
            if (w < 0) {
                fl |= LEFT_ADJ_BIT;
                w = -w;
            }
        } else {
            w = pf_getint(&s);
            if (w < 0) {
                setErrno(.OVERFLOW);
                return -1;
            }
        }

        if (s[0] == '.' and s[1] == '*') {
            if (s[2] >= '0' and s[2] <= '9' and s[3] == '$') {
                if (f == null) {
                    nl_type[s[2] - '0'] = PF_INT;
                    p = 0;
                } else {
                    p = @intCast(nl_arg[s[2] - '0'].i);
                }
                s += 4;
            } else if (l10n == 0) {
                p = if (f != null) cVaArg(ap, c_int) else 0;
                s += 2;
            } else {
                setErrno(.INVAL);
                return -1;
            }
            xp = @intFromBool(p >= 0);
        } else if (s[0] == '.') {
            s += 1;
            p = pf_getint(&s);
            xp = 1;
        } else {
            p = -1;
            xp = 0;
        }

        st = 0;
        while (true) {
            if (pf_oob(s[0])) {
                setErrno(.INVAL);
                return -1;
            }
            ps = st;
            const idx: usize = @as(usize, s[0]) - 'A';
            s += 1;
            st = pf_states[st][idx];
            if (st - 1 >= PF_STOP) break;
        }
        if (st == 0) {
            setErrno(.INVAL);
            return -1;
        }

        if (st == PF_NOARG) {
            if (argpos >= 0) {
                setErrno(.INVAL);
                return -1;
            }
        } else {
            if (argpos >= 0) {
                if (f == null) {
                    nl_type[@as(usize, @intCast(argpos))] = st;
                } else {
                    arg = nl_arg[@as(usize, @intCast(argpos))];
                }
            } else if (f != null) {
                pop_arg(&arg, st, ap);
            } else {
                return 0;
            }
        }

        if (f == null) continue;
        const ff = f.?;

        if (ff.flags & F_ERR != 0) return -1;

        zp = @as([*]u8, &buf) + buf.len;
        prefix = "-+   0X0x";
        pl = 0;
        t = @as(c_int, (s - 1)[0]);

        if (ps != 0 and (t & 15) == 3) t &= ~@as(c_int, 32);

        if ((fl & LEFT_ADJ_BIT) != 0) fl &= ~ZERO_PAD_BIT;

        var skip_common: bool = false;
        sw: {
            if (t == 'n') {
                const p_dest: ?*anyopaque = arg.p;
                if (p_dest) |pd| {
                    switch (ps) {
                        PF_BARE => @as(*c_int, @ptrCast(@alignCast(pd))).* = cnt,
                        PF_LPRE => @as(*c_long, @ptrCast(@alignCast(pd))).* = cnt,
                        PF_LLPRE => @as(*c_longlong, @ptrCast(@alignCast(pd))).* = cnt,
                        PF_HPRE => @as(*c_ushort, @ptrCast(@alignCast(pd))).* = @truncate(@as(c_uint, @bitCast(cnt))),
                        PF_HHPRE => @as(*u8, @ptrCast(@alignCast(pd))).* = @truncate(@as(c_uint, @bitCast(cnt))),
                        PF_ZTPRE => @as(*usize, @ptrCast(@alignCast(pd))).* = @intCast(cnt),
                        PF_JPRE => @as(*c_ulonglong, @ptrCast(@alignCast(pd))).* = @intCast(cnt),
                        else => {},
                    }
                }
                skip_common = true;
                break :sw;
            }
            if (t == 'p') {
                p = @max(p, 2 * @as(c_int, @sizeOf(usize)));
                t = 'x';
                fl |= ALT_FORM_BIT;
            }
            if (t == 'x' or t == 'X') {
                a = fmt_x(arg.i, zp, t & 32);
                if (arg.i != 0 and (fl & ALT_FORM_BIT) != 0) {
                    prefix += @as(usize, @intCast(@as(c_uint, @bitCast(t)) >> 4));
                    pl = 2;
                }
            } else if (t == 'o') {
                a = fmt_o(arg.i, zp);
                const a_len: c_int = @intCast(@intFromPtr(zp) - @intFromPtr(a));
                if ((fl & ALT_FORM_BIT) != 0 and p < a_len + 1) p = a_len + 1;
            } else if (t == 'd' or t == 'i') {
                pl = 1;
                if (arg.i > @as(c_ulonglong, std.math.maxInt(c_longlong))) {
                    arg.i = 0 -% arg.i;
                } else if ((fl & MARK_POS_BIT) != 0) {
                    prefix += 1;
                } else if ((fl & PAD_POS_BIT) != 0) {
                    prefix += 2;
                } else {
                    pl = 0;
                }
                a = fmt_u(arg.i, zp);
            } else if (t == 'u') {
                a = fmt_u(arg.i, zp);
            } else if (t == 'c' or t == 'C') {
                if (t == 'C' and arg.i != 0) {
                    wc[0] = @intCast(arg.i);
                    wc[1] = 0;
                    arg.p = @ptrCast(&wc);
                    p = -1;
                }
                if (t == 'c' or arg.i == 0) {
                    p = 1;
                    a = zp - 1;
                    a[0] = @truncate(arg.i);
                    fl &= ~ZERO_PAD_BIT;
                } else {
                    ws = @ptrCast(@alignCast(arg.p));
                    i = 0;
                    l = 0;
                    while (true) {
                        if (i >= @as(usize, @intCast(@max(@as(c_int, 0), p))) and p >= 0) break;
                        if (ws[0] == 0) break;
                        const wl: c_int = wctomb_fn(&mb, ws[0]);
                        ws += 1;
                        if (wl < 0) {
                            l = wl;
                            break;
                        }
                        if (p >= 0 and wl > p - @as(c_int, @intCast(i))) break;
                        l = wl;
                        i += @as(usize, @intCast(wl));
                    }
                    if (l < 0) return -1;
                    if (i > std.math.maxInt(c_int)) {
                        setErrno(.OVERFLOW);
                        return -1;
                    }
                    p = @intCast(i);
                    pf_pad(f, ' ', w, p, fl);
                    ws = @ptrCast(@alignCast(arg.p));
                    i = 0;
                    while (i < @as(usize, @intCast(p)) and ws[0] != 0) {
                        const wl: c_int = wctomb_fn(&mb, ws[0]);
                        ws += 1;
                        if (i + @as(usize, @intCast(wl)) > @as(usize, @intCast(p))) break;
                        pf_out(f, &mb, @intCast(wl));
                        i += @as(usize, @intCast(wl));
                    }
                    pf_pad(f, ' ', w, p, fl ^ LEFT_ADJ_BIT);
                    l = if (w > p) w else p;
                    skip_common = true;
                    break :sw;
                }
            } else if (t == 's' or t == 'm') {
                a = if (t == 'm')
                    @constCast(strerror_fn(std.c._errno().*))
                else if (arg.p != null)
                    @ptrCast(@alignCast(arg.p))
                else
                    @ptrCast(@constCast(@as([*]const u8, "(null)")));
                const limit: usize = if (p < 0) std.math.maxInt(c_int) else @as(usize, @intCast(p));
                const nlen = strnlen(a, limit);
                const z_ptr: [*]u8 = a + nlen;
                if (p < 0 and z_ptr[0] != 0) {
                    setErrno(.OVERFLOW);
                    return -1;
                }
                p = @intCast(@intFromPtr(z_ptr) - @intFromPtr(a));
                zp = z_ptr;
                fl &= ~ZERO_PAD_BIT;
            } else if (t == 'S') {
                ws = @ptrCast(@alignCast(arg.p));
                i = 0;
                l = 0;
                while (true) {
                    if (p >= 0 and i >= @as(usize, @intCast(p))) break;
                    if (ws[0] == 0) break;
                    const wl: c_int = wctomb_fn(&mb, ws[0]);
                    ws += 1;
                    if (wl < 0) {
                        l = wl;
                        break;
                    }
                    if (p >= 0 and wl > p - @as(c_int, @intCast(i))) break;
                    l = wl;
                    i += @as(usize, @intCast(wl));
                }
                if (l < 0) return -1;
                if (i > std.math.maxInt(c_int)) {
                    setErrno(.OVERFLOW);
                    return -1;
                }
                p = @intCast(i);
                pf_pad(f, ' ', w, p, fl);
                ws = @ptrCast(@alignCast(arg.p));
                i = 0;
                while (i < @as(usize, @intCast(p)) and ws[0] != 0) {
                    const wl: c_int = wctomb_fn(&mb, ws[0]);
                    ws += 1;
                    if (i + @as(usize, @intCast(wl)) > @as(usize, @intCast(p))) break;
                    pf_out(f, &mb, @intCast(wl));
                    i += @as(usize, @intCast(wl));
                }
                pf_pad(f, ' ', w, p, fl ^ LEFT_ADJ_BIT);
                l = if (w > p) w else p;
                skip_common = true;
                break :sw;
            } else switch (t) {
                'e', 'f', 'g', 'a', 'E', 'F', 'G', 'A' => {
                    if (xp != 0 and p < 0) {
                        setErrno(.OVERFLOW);
                        return -1;
                    }
                    l = fmt_fp(f, arg.f, w, p, fl, t);
                    if (l < 0) {
                        setErrno(.OVERFLOW);
                        return -1;
                    }
                    skip_common = true;
                    break :sw;
                },
                else => {},
            }

            if (t == 'x' or t == 'X' or t == 'o' or t == 'd' or t == 'i' or t == 'u') {
                if (xp != 0 and p < 0) {
                    setErrno(.OVERFLOW);
                    return -1;
                }
                if (xp != 0) fl &= ~ZERO_PAD_BIT;
                if (arg.i == 0 and p == 0) {
                    a = zp;
                } else {
                    const az_diff: c_int = @intCast(@intFromPtr(zp) - @intFromPtr(a));
                    const bump: c_int = @intFromBool(arg.i == 0);
                    p = @max(p, az_diff + bump);
                }
            }
        }

        if (skip_common) continue;

        const a_len: c_int = @intCast(@intFromPtr(zp) - @intFromPtr(a));
        if (p < a_len) p = a_len;
        if (p > std.math.maxInt(c_int) - pl) {
            setErrno(.OVERFLOW);
            return -1;
        }
        if (w < pl + p) w = pl + p;
        if (w > std.math.maxInt(c_int) - cnt) {
            setErrno(.OVERFLOW);
            return -1;
        }

        pf_pad(f, ' ', w, pl + p, fl);
        pf_out(f, prefix, @intCast(pl));
        pf_pad(f, '0', w, pl + p, fl ^ ZERO_PAD_BIT);
        pf_pad(f, '0', p, a_len, 0);
        pf_out(f, a, @intCast(a_len));
        pf_pad(f, ' ', w, pl + p, fl ^ LEFT_ADJ_BIT);

        l = w;
    }

    if (f != null) return cnt;
    if (l10n == 0) return 0;

    var k: usize = 1;
    while (k <= NL_ARGMAX and nl_type[k] != 0) : (k += 1) {
        pop_arg(&nl_arg[k], @intCast(nl_type[k]), ap);
    }
    while (k <= NL_ARGMAX and nl_type[k] == 0) : (k += 1) {}
    if (k <= NL_ARGMAX) {
        setErrno(.INVAL);
        return -1;
    }
    return 1;
}

inline fn strnlen(s: [*]const u8, n: usize) usize {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (s[i] == 0) break;
    }
    return i;
}

/// vfprintf.c: int vfprintf(FILE *restrict f, const char *restrict fmt, va_list ap)
fn vfprintf_impl(f_opt: ?*FILE, fmt: [*:0]const u8, ap: CVaList) callconv(.c) c_int {
    const f = f_opt.?;
    var ap_src = unpackVaList(ap);
    var ap2 = @cVaCopy(&ap_src);
    var nl_type: [NL_ARGMAX + 1]c_int = @splat(0);
    var nl_arg: [NL_ARGMAX + 1]PrintfArg = undefined;
    var internal_buf: [80]u8 = undefined;
    var saved_buf: ?[*]u8 = null;
    var ret: c_int = undefined;

    if (printf_core(null, fmt, &ap2, &nl_arg, &nl_type) < 0) {
        @cVaEnd(&ap2);
        return -1;
    }

    const need_unlock = flock(f);
    const olderr: c_uint = f.flags & F_ERR;
    f.flags &= ~F_ERR;
    if (f.buf_size == 0) {
        saved_buf = f.buf;
        f.buf = &internal_buf;
        f.buf_size = internal_buf.len;
        f.wpos = null;
        f.wbase = null;
        f.wend = null;
    }
    if (f.wend == null and towrite_impl(f) != 0) {
        ret = -1;
    } else {
        ret = printf_core(f, fmt, &ap2, &nl_arg, &nl_type);
    }
    if (saved_buf) |sb| {
        _ = f.write_fn.?(f, @ptrCast(fmt), 0);
        if (f.wpos == null) ret = -1;
        f.buf = sb;
        f.buf_size = 0;
        f.wpos = null;
        f.wbase = null;
        f.wend = null;
    }
    if (f.flags & F_ERR != 0) ret = -1;
    f.flags |= olderr;
    funlock(f, need_unlock);
    @cVaEnd(&ap2);
    return ret;
}

fn fprintf_impl(f: ?*FILE, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vfprintf_impl(f, fmt, passVaList(&ap));
}

// === vfwprintf (from musl src/stdio/vfwprintf.c) ========================

const wfp_sizeprefix: [25]u8 = blk: {
    var t: [25]u8 = @splat(0);
    t['a' - 'a'] = 'L';
    t['e' - 'a'] = 'L';
    t['f' - 'a'] = 'L';
    t['g' - 'a'] = 'L';
    t['d' - 'a'] = 'j';
    t['i' - 'a'] = 'j';
    t['o' - 'a'] = 'j';
    t['u' - 'a'] = 'j';
    t['x' - 'a'] = 'j';
    t['p' - 'a'] = 'j';
    break :blk t;
};

inline fn wfp_out(f: *FILE, s: [*]const wchar_t, l: usize) void {
    var i: usize = 0;
    while (i < l and f.flags & F_ERR == 0) : (i += 1) {
        _ = fputwc_fn(s[i], f);
    }
}

fn wfp_pad(f: *FILE, n: c_int, fl: c_uint) void {
    if ((fl & LEFT_ADJ_BIT) != 0 or n <= 0 or f.flags & F_ERR != 0) return;
    _ = fprintf_impl(f, "%*s", n, @as([*:0]const u8, ""));
}

fn wfp_getint(sp: *[*]const wchar_t) c_int {
    var i: c_int = 0;
    while (iswdigit_local(sp.*[0])) : (sp.* += 1) {
        const d: c_int = @intCast(wcharAsU32(sp.*[0]) - '0');
        if (i > @as(c_int, std.math.maxInt(c_int) / 10) or d > std.math.maxInt(c_int) - 10 * i) {
            i = -1;
        } else {
            i = 10 * i + d;
        }
    }
    return i;
}

fn wprintf_core(
    f_opt: ?*FILE,
    fmt: [*:0]const wchar_t,
    ap: *VaList,
    nl_arg: *[NL_ARGMAX + 1]PrintfArg,
    nl_type: *[NL_ARGMAX + 1]c_int,
) callconv(.c) c_int {
    var s: [*:0]const wchar_t = fmt;
    var l10n: c_uint = 0;
    var fl: c_uint = undefined;
    var w: c_int = undefined;
    var p: c_int = undefined;
    var xp: c_int = undefined;
    var arg: PrintfArg = std.mem.zeroes(PrintfArg);
    var argpos: c_int = undefined;
    var st: u8 = undefined;
    var ps: u8 = undefined;
    var cnt: c_int = 0;
    var l: c_int = 0;
    var i: c_int = undefined;
    var t: c_int = undefined;
    var bs: [*]const u8 = undefined;
    var charfmt: [16]u8 = undefined;
    var wc: wchar_t = undefined;
    var single_wc: [1]wchar_t = undefined;

    while (true) {
        if (l > std.math.maxInt(c_int) - cnt) {
            setErrno(.OVERFLOW);
            return -1;
        }
        cnt += l;
        if (s[0] == 0) break;

        const a_lit = s;
        while (s[0] != 0 and wcharAsU32(s[0]) != '%') s += 1;
        var z_lit = s;
        while (wcharAsU32(s[0]) == '%' and wcharAsU32(s[1]) == '%') {
            z_lit += 1;
            s += 2;
        }
        const lit_bytes: isize = @intCast(@intFromPtr(z_lit) - @intFromPtr(a_lit));
        const lit_wchars: isize = @divExact(lit_bytes, @sizeOf(wchar_t));
        if (lit_wchars > std.math.maxInt(c_int) - cnt) {
            setErrno(.OVERFLOW);
            return -1;
        }
        l = @intCast(lit_wchars);
        if (f_opt) |ff| wfp_out(ff, a_lit, @intCast(l));
        if (l != 0) continue;

        if (iswdigit_local(s[1]) and wcharAsU32(s[2]) == '$') {
            l10n = 1;
            argpos = @intCast(wcharAsU32(s[1]) - '0');
            s += 3;
        } else {
            argpos = -1;
            s += 1;
        }

        fl = 0;
        while (true) {
            const c: u32 = wcharAsU32(s[0]);
            const bit: c_uint = @as(c_uint, @intCast(c)) -% ' ';
            if (bit >= 32) break;
            if ((FLAGMASK & (@as(c_uint, 1) << @as(u5, @intCast(bit)))) == 0) break;
            fl |= @as(c_uint, 1) << @as(u5, @intCast(bit));
            s += 1;
        }

        if (wcharAsU32(s[0]) == '*') {
            if (iswdigit_local(s[1]) and wcharAsU32(s[2]) == '$') {
                l10n = 1;
                nl_type[@as(usize, @intCast(wcharAsU32(s[1]) - '0'))] = PF_INT;
                w = @intCast(nl_arg[@as(usize, @intCast(wcharAsU32(s[1]) - '0'))].i);
                s += 3;
            } else if (l10n == 0) {
                w = if (f_opt != null) cVaArg(ap, c_int) else 0;
                s += 1;
            } else {
                setErrno(.INVAL);
                return -1;
            }
            if (w < 0) {
                fl |= LEFT_ADJ_BIT;
                w = -w;
            }
        } else {
            w = wfp_getint(@ptrCast(&s));
            if (w < 0) {
                setErrno(.OVERFLOW);
                return -1;
            }
        }

        if (wcharAsU32(s[0]) == '.' and wcharAsU32(s[1]) == '*') {
            if (iswdigit_local(s[2]) and wcharAsU32(s[3]) == '$') {
                nl_type[@as(usize, @intCast(wcharAsU32(s[2]) - '0'))] = PF_INT;
                p = @intCast(nl_arg[@as(usize, @intCast(wcharAsU32(s[2]) - '0'))].i);
                s += 4;
            } else if (l10n == 0) {
                p = if (f_opt != null) cVaArg(ap, c_int) else 0;
                s += 2;
            } else {
                setErrno(.INVAL);
                return -1;
            }
            xp = @intFromBool(p >= 0);
        } else if (wcharAsU32(s[0]) == '.') {
            s += 1;
            p = wfp_getint(@ptrCast(&s));
            xp = 1;
        } else {
            p = -1;
            xp = 0;
        }

        st = 0;
        while (true) {
            const sc: u32 = wcharAsU32(s[0]);
            if (sc > 127 or pf_oob(@intCast(sc))) {
                setErrno(.INVAL);
                return -1;
            }
            ps = st;
            const idx: usize = @as(usize, @intCast(sc)) - 'A';
            s += 1;
            st = pf_states[st][idx];
            if (st - 1 >= PF_STOP) break;
        }
        if (st == 0) {
            setErrno(.INVAL);
            return -1;
        }

        if (st == PF_NOARG) {
            if (argpos >= 0) {
                setErrno(.INVAL);
                return -1;
            }
        } else {
            if (argpos >= 0) {
                nl_type[@as(usize, @intCast(argpos))] = st;
                arg = nl_arg[@as(usize, @intCast(argpos))];
            } else if (f_opt != null) {
                pop_arg(&arg, st, ap);
            } else {
                return 0;
            }
        }

        if (f_opt == null) continue;
        const ff = f_opt.?;

        if (ff.flags & F_ERR != 0) return -1;

        t = @intCast(wcharAsU32((s - 1)[0]));

        if (ps != 0 and (t & 15) == 3) t &= ~@as(c_int, 32);

        switch (t) {
            'n' => {
                const p_dest: ?*anyopaque = arg.p;
                if (p_dest) |pd| {
                    switch (ps) {
                        PF_BARE => @as(*c_int, @ptrCast(@alignCast(pd))).* = cnt,
                        PF_LPRE => @as(*c_long, @ptrCast(@alignCast(pd))).* = cnt,
                        PF_LLPRE => @as(*c_longlong, @ptrCast(@alignCast(pd))).* = cnt,
                        PF_HPRE => @as(*c_ushort, @ptrCast(@alignCast(pd))).* = @truncate(@as(c_uint, @bitCast(cnt))),
                        PF_HHPRE => @as(*u8, @ptrCast(@alignCast(pd))).* = @truncate(@as(c_uint, @bitCast(cnt))),
                        PF_ZTPRE => @as(*usize, @ptrCast(@alignCast(pd))).* = @intCast(cnt),
                        PF_JPRE => @as(*c_ulonglong, @ptrCast(@alignCast(pd))).* = @intCast(cnt),
                        else => {},
                    }
                }
                continue;
            },
            'c', 'C' => {
                if (w < 1) w = 1;
                wfp_pad(ff, w - 1, fl);
                const ch_u32: u32 = if (t == 'C')
                    @intCast(arg.i & 0xFFFFFFFF)
                else
                    @as(u32, @intCast(wintAsU32(@bitCast(btowc_fn(@as(c_int, @intCast(arg.i & 0xFF)))))));
                single_wc[0] = @bitCast(ch_u32);
                wfp_out(ff, &single_wc, 1);
                wfp_pad(ff, w - 1, fl ^ LEFT_ADJ_BIT);
                l = w;
                continue;
            },
            'S' => {
                const ws: [*:0]const wchar_t = @ptrCast(@alignCast(arg.p));
                const limit: usize = if (p < 0) std.math.maxInt(c_int) else @as(usize, @intCast(p));
                const wlen: usize = wcsnlen_fn(ws, limit);
                if (p < 0 and ws[wlen] != 0) {
                    setErrno(.OVERFLOW);
                    return -1;
                }
                if (wlen > std.math.maxInt(c_int)) {
                    setErrno(.OVERFLOW);
                    return -1;
                }
                p = @intCast(wlen);
                if (w < p) w = p;
                wfp_pad(ff, w - p, fl);
                wfp_out(ff, ws, @intCast(p));
                wfp_pad(ff, w - p, fl ^ LEFT_ADJ_BIT);
                l = w;
                continue;
            },
            'm', 's' => {
                if (t == 'm') arg.p = @ptrCast(@constCast(strerror_fn(std.c._errno().*)));
                if (arg.p == null) arg.p = @ptrCast(@constCast(@as([*]const u8, "(null)")));
                bs = @ptrCast(@alignCast(arg.p));
                i = 0;
                l = 0;
                const cap: c_int = if (p < 0) std.math.maxInt(c_int) else p;
                while (l < cap) {
                    i = mbtowc_fn(&wc, bs, MB_LEN_MAX);
                    if (i <= 0) break;
                    bs += @as(usize, @intCast(i));
                    l += 1;
                }
                if (i < 0) return -1;
                if (p < 0 and bs[0] != 0) {
                    setErrno(.OVERFLOW);
                    return -1;
                }
                p = l;
                if (w < p) w = p;
                wfp_pad(ff, w - p, fl);
                bs = @ptrCast(@alignCast(arg.p.?));
                while (l != 0) : (l -= 1) {
                    i = mbtowc_fn(&wc, bs, MB_LEN_MAX);
                    bs += @as(usize, @intCast(i));
                    single_wc[0] = wc;
                    wfp_out(ff, &single_wc, 1);
                }
                wfp_pad(ff, w - p, fl ^ LEFT_ADJ_BIT);
                l = w;
                continue;
            },
            else => {},
        }

        if (xp != 0 and p < 0) {
            setErrno(.OVERFLOW);
            return -1;
        }

        {
            var ci: usize = 0;
            charfmt[ci] = '%';
            ci += 1;
            if ((fl & ALT_FORM_BIT) != 0) {
                charfmt[ci] = '#';
                ci += 1;
            }
            if ((fl & MARK_POS_BIT) != 0) {
                charfmt[ci] = '+';
                ci += 1;
            }
            if ((fl & LEFT_ADJ_BIT) != 0) {
                charfmt[ci] = '-';
                ci += 1;
            }
            if ((fl & PAD_POS_BIT) != 0) {
                charfmt[ci] = ' ';
                ci += 1;
            }
            if ((fl & ZERO_PAD_BIT) != 0) {
                charfmt[ci] = '0';
                ci += 1;
            }
            charfmt[ci] = '*';
            ci += 1;
            charfmt[ci] = '.';
            ci += 1;
            charfmt[ci] = '*';
            ci += 1;
            const sp_idx: c_int = (t | 32) - 'a';
            if (sp_idx >= 0 and sp_idx < @as(c_int, wfp_sizeprefix.len)) {
                const sp_ch: u8 = wfp_sizeprefix[@as(usize, @intCast(sp_idx))];
                if (sp_ch != 0) {
                    charfmt[ci] = sp_ch;
                    ci += 1;
                }
            }
            charfmt[ci] = @intCast(t);
            ci += 1;
            charfmt[ci] = 0;
        }

        switch (t | 32) {
            'a', 'e', 'f', 'g' => {
                l = fprintf_impl(ff, @ptrCast(&charfmt), w, p, arg.f);
            },
            'd', 'i', 'o', 'u', 'x', 'p' => {
                l = fprintf_impl(ff, @ptrCast(&charfmt), w, p, arg.i);
            },
            else => {},
        }
    }

    if (f_opt != null) return cnt;
    if (l10n == 0) return 0;

    var ii: usize = 1;
    while (ii <= NL_ARGMAX and nl_type[ii] != 0) : (ii += 1) {
        pop_arg(&nl_arg[ii], @intCast(nl_type[ii]), ap);
    }
    while (ii <= NL_ARGMAX and nl_type[ii] == 0) : (ii += 1) {}
    if (ii <= NL_ARGMAX) {
        setErrno(.INVAL);
        return -1;
    }
    return 1;
}

fn vfwprintf_impl(f_opt: ?*FILE, fmt: [*:0]const wchar_t, ap: CVaList) callconv(.c) c_int {
    const f = f_opt.?;
    var ap_src = unpackVaList(ap);
    var ap2 = @cVaCopy(&ap_src);
    var nl_type: [NL_ARGMAX + 1]c_int = @splat(0);
    var nl_arg: [NL_ARGMAX + 1]PrintfArg = undefined;
    var ret: c_int = undefined;

    if (wprintf_core(null, fmt, &ap2, &nl_arg, &nl_type) < 0) {
        @cVaEnd(&ap2);
        return -1;
    }

    const need_unlock = flock(f);
    _ = fwide_fn(f, 1);
    const olderr: c_uint = f.flags & F_ERR;
    f.flags &= ~F_ERR;
    ret = wprintf_core(f, fmt, &ap2, &nl_arg, &nl_type);
    if (f.flags & F_ERR != 0) ret = -1;
    f.flags |= olderr;
    funlock(f, need_unlock);
    @cVaEnd(&ap2);
    return ret;
}

fn sn_write(f: *FILE, s: [*]const u8, l: usize) callconv(.c) usize {
    const c: *SnCookie = @ptrCast(@alignCast(f.cookie.?));
    const wbase = f.wbase orelse @as([*]u8, @ptrCast(@constCast(s)));
    const wpos = f.wpos orelse wbase;
    const len2 = @intFromPtr(wpos) - @intFromPtr(wbase);
    const k1 = @min(c.n, len2);
    if (k1 > 0) {
        @memcpy(c.s[0..k1], @as([*]const u8, @ptrCast(wbase))[0..k1]);
        c.s += k1;
        c.n -= k1;
    }
    const k2 = @min(c.n, l);
    if (k2 > 0) {
        @memcpy(c.s[0..k2], s[0..k2]);
        c.s += k2;
        c.n -= k2;
    }
    c.s[0] = 0;
    f.wpos = f.buf;
    f.wbase = f.buf;
    return l;
}

/// vsnprintf.c: int vsnprintf(char *restrict s, size_t n, const char *restrict fmt, va_list ap)
fn vsnprintf_impl(s: [*]u8, n: usize, fmt: [*:0]const u8, ap: CVaList) callconv(.c) c_int {
    var buf: [1]u8 = undefined;
    var dummy: [1]u8 = undefined;
    var c = SnCookie{
        .s = if (n != 0) s else &dummy,
        .n = if (n != 0) n - 1 else 0,
    };
    var f = std.mem.zeroes(FILE);
    f.lbf = EOF;
    f.write_fn = &sn_write;
    f.lock = -1;
    f.buf = &buf;
    f.cookie = @ptrCast(&c);
    c.s[0] = 0;
    return vfprintf_impl(@ptrCast(&f), fmt, ap);
}

/// vsprintf.c: int vsprintf(char *restrict s, const char *restrict fmt, va_list ap)
fn vsprintf_impl(s: [*]u8, fmt: [*:0]const u8, ap: CVaList) callconv(.c) c_int {
    return vsnprintf_impl(s, std.math.maxInt(c_int), fmt, ap);
}

fn string_read(f: *FILE, buf: [*]u8, len: usize) callconv(.c) usize {
    const src: [*]const u8 = @ptrCast(@alignCast(f.cookie.?));
    const k_limit = len +| 256;
    const k = if (memchr_fn(src, 0, k_limit)) |end|
        @intFromPtr(end) - @intFromPtr(src)
    else
        k_limit;
    const actual = @min(len, k);
    @memcpy(buf[0..actual], src[0..actual]);
    f.rpos = @ptrCast(@constCast(src + actual));
    f.rend = @ptrCast(@constCast(src + k));
    f.cookie = @ptrCast(@constCast(src + k));
    return actual;
}

const SIZE_hh: c_int = -2;
const SIZE_h: c_int = -1;
const SIZE_def: c_int = 0;
const SIZE_l: c_int = 1;
const SIZE_L: c_int = 2;
const SIZE_ll: c_int = 3;

inline fn is_space(c: c_int) bool {
    return switch (c) {
        ' ', '\t', '\n', '\r', 11, 12 => true,
        else => false,
    };
}

inline fn is_digit(c: c_int) bool {
    return c >= '0' and c <= '9';
}

inline fn shcnt(f: *FILE) i64 {
    return f.shcnt + @as(i64, @intCast(@intFromPtr(f.rpos.?) - @intFromPtr(f.buf.?)));
}

inline fn shlim(f: *FILE, lim: i64) void {
    shlim_fn(f, lim);
}

inline fn shgetc(f: *FILE) c_int {
    if (f.rpos != f.shend) {
        const c = f.rpos.?[0];
        f.rpos = f.rpos.? + 1;
        return c;
    }
    return shgetc_fn(f);
}

inline fn shunget(f: *FILE) void {
    if (f.shlim >= 0) f.rpos = f.rpos.? - 1;
}

fn store_int(dest: ?*anyopaque, size: c_int, i: c_ulonglong) void {
    const p = dest orelse return;
    switch (size) {
        SIZE_hh => @as(*u8, @ptrCast(@alignCast(p))).* = @truncate(i),
        SIZE_h => @as(*c_short, @ptrCast(@alignCast(p))).* = @bitCast(@as(c_ushort, @truncate(i))),
        SIZE_def => @as(*c_int, @ptrCast(@alignCast(p))).* = @bitCast(@as(c_uint, @truncate(i))),
        SIZE_l => @as(*c_long, @ptrCast(@alignCast(p))).* = @bitCast(@as(c_ulong, @truncate(i))),
        SIZE_ll => @as(*c_longlong, @ptrCast(@alignCast(p))).* = @bitCast(@as(c_ulonglong, i)),
        else => {},
    }
}

fn arg_n(ap: VaList, n: c_uint) callconv(.c) ?*anyopaque {
    var ap_src = ap;
    var ap2 = @cVaCopy(&ap_src);
    defer @cVaEnd(&ap2);
    var n_remaining = n;
    while (n_remaining > 1) : (n_remaining -= 1) _ = cVaArg(&ap2, ?*anyopaque);
    return cVaArg(&ap2, ?*anyopaque);
}

fn fail_with_alloc(result: c_int, alloc: bool, s: ?[*]u8, wcs: ?[*]wchar_t) c_int {
    if (alloc) {
        free_fn(s);
        free_fn(wcs);
    }
    return result;
}

fn input_fail_result(matches: c_int) c_int {
    return if (matches == 0) -1 else matches;
}

/// vfscanf.c: int vfscanf(FILE *restrict f, const char *restrict fmt, va_list ap)
fn vfscanf_impl(f_arg: ?*FILE, fmt: [*:0]const u8, ap: CVaList) callconv(.c) c_int {
    const f = f_arg.?;
    var ap_src = unpackVaList(ap);
    var width: c_int = undefined;
    var size: c_int = undefined;
    var alloc: bool = false;
    var base: c_uint = undefined;
    var p: [*]const u8 = fmt;
    var c: c_int = undefined;
    var t: c_int = undefined;
    var s: ?[*]u8 = null;
    var wcs: ?[*]wchar_t = null;
    var st: mbstate_t = undefined;
    var dest: ?*anyopaque = null;
    var invert: c_int = 0;
    var matches: c_int = 0;
    var x: c_ulonglong = undefined;
    var y: c_longdouble = undefined;
    var pos: i64 = 0;
    var scanset: [257]u8 = undefined;
    var i: usize = undefined;
    var k: usize = undefined;
    var wc: wchar_t = undefined;

    const need_unlock = flock(f);
    defer funlock(f, need_unlock);

    if (f.rpos == null) _ = toread_fn(f);
    if (f.rpos == null) return input_fail_result(matches);

    while (p[0] != 0) : (p += 1) {
        alloc = false;

        if (is_space(p[0])) {
            while (is_space(p[1])) p += 1;
            shlim(f, 0);
            while (true) {
                c = shgetc(f);
                if (!is_space(c)) break;
            }
            shunget(f);
            pos += shcnt(f);
            continue;
        }

        if (p[0] != '%' or p[1] == '%') {
            shlim(f, 0);
            if (p[0] == '%') {
                p += 1;
                while (true) {
                    c = shgetc(f);
                    if (!is_space(c)) break;
                }
            } else {
                c = shgetc(f);
            }
            if (c != p[0]) {
                shunget(f);
                if (c < 0) return input_fail_result(matches);
                return matches;
            }
            pos += shcnt(f);
            continue;
        }

        p += 1;
        if (p[0] == '*') {
            dest = null;
            p += 1;
        } else if (is_digit(p[0]) and p[1] == '$') {
            dest = arg_n(ap_src, p[0] - '0');
            p += 2;
        } else {
            dest = cVaArg(&ap_src, ?*anyopaque);
        }

        width = 0;
        while (is_digit(p[0])) : (p += 1) {
            width = 10 * width + @as(c_int, p[0]) - '0';
        }

        if (p[0] == 'm') {
            wcs = null;
            s = null;
            alloc = dest != null;
            p += 1;
        } else {
            alloc = false;
        }

        size = SIZE_def;
        const size_ch = p[0];
        p += 1;
        switch (size_ch) {
            'h' => {
                if (p[0] == 'h') {
                    p += 1;
                    size = SIZE_hh;
                } else size = SIZE_h;
            },
            'l' => {
                if (p[0] == 'l') {
                    p += 1;
                    size = SIZE_ll;
                } else size = SIZE_l;
            },
            'j' => size = SIZE_ll,
            'z', 't' => size = SIZE_l,
            'L' => size = SIZE_L,
            'd', 'i', 'o', 'u', 'x', 'a', 'e', 'f', 'g', 'A', 'E', 'F', 'G', 'X', 's', 'c', '[', 'S', 'C', 'p', 'n' => p -= 1,
            else => return fail_with_alloc(matches, alloc, s, wcs),
        }

        t = p[0];

        if ((t & 0x2f) == 3) {
            t |= 32;
            size = SIZE_l;
        }

        switch (t) {
            'c' => {
                if (width < 1) width = 1;
            },
            '[' => {},
            'n' => {
                store_int(dest, size, @intCast(pos));
                continue;
            },
            else => {
                shlim(f, 0);
                while (true) {
                    c = shgetc(f);
                    if (!is_space(c)) break;
                }
                shunget(f);
                pos += shcnt(f);
            },
        }

        shlim(f, width);
        if (shgetc(f) < 0) return fail_with_alloc(input_fail_result(matches), alloc, s, wcs);
        shunget(f);

        switch (t) {
            's', 'c', '[' => {
                if (t == 'c' or t == 's') {
                    @memset(&scanset, 0xff);
                    scanset[0] = 0;
                    if (t == 's') {
                        scanset[1 + '\t'] = 0;
                        scanset[1 + '\n'] = 0;
                        scanset[1 + 11] = 0;
                        scanset[1 + 12] = 0;
                        scanset[1 + '\r'] = 0;
                        scanset[1 + ' '] = 0;
                    }
                } else {
                    p += 1;
                    if (p[0] == '^') {
                        p += 1;
                        invert = 1;
                    } else invert = 0;
                    @memset(&scanset, @as(u8, @intCast(invert)));
                    scanset[0] = 0;
                    if (p[0] == '-') {
                        p += 1;
                        scanset[1 + '-'] = @intCast(1 - invert);
                    } else if (p[0] == ']') {
                        p += 1;
                        scanset[1 + ']'] = @intCast(1 - invert);
                    }
                    while (p[0] != ']') : (p += 1) {
                        if (p[0] == 0) return fail_with_alloc(matches, alloc, s, wcs);
                        if (p[0] == '-' and p[1] != 0 and p[1] != ']') {
                            const start = (p - 1)[0];
                            p += 1;
                            var rc: c_int = start;
                            while (rc < p[0]) : (rc += 1) scanset[@as(usize, @intCast(1 + rc))] = @intCast(1 - invert);
                        }
                        scanset[1 + p[0]] = @intCast(1 - invert);
                    }
                }

                wcs = null;
                s = null;
                i = 0;
                k = if (t == 'c') @as(usize, @intCast(width)) + 1 else 31;
                if (size == SIZE_l) {
                    if (alloc) {
                        wcs = @ptrCast(@alignCast(malloc_fn(k * @sizeOf(wchar_t)) orelse return fail_with_alloc(input_fail_result(matches), alloc, s, wcs)));
                    } else if (dest) |d| {
                        wcs = @ptrCast(@alignCast(d));
                    }
                    st = std.mem.zeroes(mbstate_t);
                    while (true) {
                        c = shgetc(f);
                        if (scanset[@as(usize, @intCast(c + 1))] == 0) break;
                        var ch: u8 = @truncate(@as(c_uint, @bitCast(c)));
                        switch (mbrtowc_fn(&wc, @ptrCast(&ch), 1, &st)) {
                            @as(usize, @bitCast(@as(isize, -1))) => return fail_with_alloc(input_fail_result(matches), alloc, s, wcs),
                            @as(usize, @bitCast(@as(isize, -2))) => continue,
                            else => {},
                        }
                        if (wcs) |buf| buf[i] = wc;
                        i += 1;
                        if (alloc and i == k) {
                            k += k + 1;
                            wcs = @ptrCast(@alignCast(realloc_fn(wcs, k * @sizeOf(wchar_t)) orelse return fail_with_alloc(input_fail_result(matches), alloc, s, wcs)));
                        }
                    }
                    if (mbsinit_fn(&st) == 0) return fail_with_alloc(input_fail_result(matches), alloc, s, wcs);
                } else if (alloc) {
                    s = @ptrCast(@alignCast(malloc_fn(k) orelse return fail_with_alloc(input_fail_result(matches), alloc, s, wcs)));
                    while (true) {
                        c = shgetc(f);
                        if (scanset[@as(usize, @intCast(c + 1))] == 0) break;
                        s.?[i] = @truncate(@as(c_uint, @bitCast(c)));
                        i += 1;
                        if (i == k) {
                            k += k + 1;
                            s = @ptrCast(@alignCast(realloc_fn(s, k) orelse return fail_with_alloc(input_fail_result(matches), alloc, s, wcs)));
                        }
                    }
                } else if (dest) |d| {
                    s = @ptrCast(@alignCast(d));
                    while (true) {
                        c = shgetc(f);
                        if (scanset[@as(usize, @intCast(c + 1))] == 0) break;
                        s.?[i] = @truncate(@as(c_uint, @bitCast(c)));
                        i += 1;
                    }
                } else {
                    while (true) {
                        c = shgetc(f);
                        if (scanset[@as(usize, @intCast(c + 1))] == 0) break;
                    }
                }
                shunget(f);
                const cnt = shcnt(f);
                if (cnt == 0) return fail_with_alloc(matches, alloc, s, wcs);
                if (t == 'c' and cnt != width) return fail_with_alloc(matches, alloc, s, wcs);
                if (alloc) {
                    if (size == SIZE_l) @as(*?[*]wchar_t, @ptrCast(@alignCast(dest.?))).* = wcs else @as(*?[*]u8, @ptrCast(@alignCast(dest.?))).* = s;
                }
                if (t != 'c') {
                    if (wcs) |buf| buf[i] = 0;
                    if (s) |buf| buf[i] = 0;
                }
            },
            'p', 'X', 'x' => {
                base = 16;
                x = intscan_fn(f, base, 0, std.math.maxInt(c_ulonglong));
                if (shcnt(f) == 0) return matches;
                if (t == 'p') {
                    if (dest) |d| @as(*?*anyopaque, @ptrCast(@alignCast(d))).* = @ptrFromInt(@as(usize, @intCast(x)));
                } else store_int(dest, size, x);
            },
            'o' => {
                base = 8;
                x = intscan_fn(f, base, 0, std.math.maxInt(c_ulonglong));
                if (shcnt(f) == 0) return matches;
                store_int(dest, size, x);
            },
            'd', 'u' => {
                base = 10;
                x = intscan_fn(f, base, 0, std.math.maxInt(c_ulonglong));
                if (shcnt(f) == 0) return matches;
                store_int(dest, size, x);
            },
            'i' => {
                base = 0;
                x = intscan_fn(f, base, 0, std.math.maxInt(c_ulonglong));
                if (shcnt(f) == 0) return matches;
                store_int(dest, size, x);
            },
            'a', 'A', 'e', 'E', 'f', 'F', 'g', 'G' => {
                y = floatscan_fn(f, size, 0);
                if (shcnt(f) == 0) return matches;
                if (dest) |d| switch (size) {
                    SIZE_def => @as(*f32, @ptrCast(@alignCast(d))).* = @floatCast(y),
                    SIZE_l => @as(*f64, @ptrCast(@alignCast(d))).* = @floatCast(y),
                    SIZE_L => @as(*c_longdouble, @ptrCast(@alignCast(d))).* = y,
                    else => {},
                };
            },
            else => return fail_with_alloc(matches, alloc, s, wcs),
        }

        pos += shcnt(f);
        if (dest != null) matches += 1;
    }
    return matches;
}

fn fscanf_impl(f: ?*FILE, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vfscanf_impl(f, fmt, passVaList(&ap));
}

/// vsscanf.c: int vsscanf(const char *restrict s, const char *restrict fmt, va_list ap)
fn vsscanf_impl(s: [*:0]const u8, fmt: [*:0]const u8, ap: CVaList) callconv(.c) c_int {
    var f = std.mem.zeroes(FILE);
    f.buf = @ptrCast(@constCast(s));
    f.cookie = @ptrCast(@constCast(s));
    f.read_fn = &string_read;
    f.lock = -1;
    return vfscanf_impl(@ptrCast(&f), fmt, ap);
}

fn sw_write(f: *FILE, s: [*]const u8, l: usize) callconv(.c) usize {
    const l0 = l;
    var i: c_int = 0;
    const c: *SwCookie = @ptrCast(@alignCast(f.cookie.?));
    if (f.wbase) |wbase| {
        if (@intFromPtr(s) != @intFromPtr(wbase)) {
            const wpos = f.wpos orelse @as([*]u8, wbase);
            const base_len = @intFromPtr(wpos) - @intFromPtr(wbase);
            if (sw_write(f, @ptrCast(wbase), base_len) == @as(usize, @bitCast(@as(isize, -1)))) {
                return @bitCast(@as(isize, -1));
            }
        }
    }
    var src = s;
    var remain = l;
    while (c.l > 0 and remain > 0) {
        i = mbtowc_fn(@ptrCast(c.ws), @ptrCast(src), remain);
        if (i < 0) break;
        const step: usize = if (i == 0) 1 else @intCast(i);
        src += step;
        remain -= step;
        c.l -= 1;
        c.ws += 1;
    }
    c.ws[0] = 0;
    if (i < 0) {
        f.wpos = null;
        f.wbase = null;
        f.wend = null;
        f.flags |= F_ERR;
        return @bitCast(@as(isize, @intCast(i)));
    }
    f.wend = f.buf.? + f.buf_size;
    f.wpos = f.buf;
    f.wbase = f.buf;
    return l0;
}

/// vswprintf.c: int vswprintf(wchar_t *restrict s, size_t n, const wchar_t *restrict fmt, va_list ap)
fn vswprintf_impl(s: [*]wchar_t, n: usize, fmt: [*:0]const wchar_t, ap: CVaList) callconv(.c) c_int {
    var buf: [256]u8 = undefined;
    var c = SwCookie{ .ws = s, .l = n -| 1 };
    var f = std.mem.zeroes(FILE);
    f.lbf = EOF;
    f.write_fn = &sw_write;
    f.lock = -1;
    f.buf = &buf;
    f.buf_size = buf.len;
    f.cookie = @ptrCast(&c);
    if (n == 0) return -1;
    const r = vfwprintf_impl(@ptrCast(&f), fmt, ap);
    _ = sw_write(&f, @ptrCast(&f), 0);
    return if (r >= @as(c_int, @intCast(n))) @as(c_int, -1) else r;
}

fn wstring_read(f: *FILE, buf: [*]u8, len: usize) callconv(.c) usize {
    var src: ?[*:0]const wchar_t = @ptrCast(@alignCast(f.cookie orelse return 0));
    const k = wcsrtombs_fn(@ptrCast(f.buf), &src, f.buf_size, null);
    if (k == @as(usize, @bitCast(@as(isize, -1)))) {
        f.rpos = null;
        f.rend = null;
        return 0;
    }
    f.rpos = f.buf;
    f.rend = f.buf.? + k;
    f.cookie = @ptrCast(@constCast(src));
    if (len == 0 or k == 0) return 0;
    buf[0] = f.rpos.?[0];
    f.rpos = f.rpos.? + 1;
    return 1;
}

/// vswscanf.c: int vswscanf(const wchar_t *restrict s, const wchar_t *restrict fmt, va_list ap)
fn vswscanf_impl(s: [*:0]const wchar_t, fmt: [*:0]const wchar_t, ap: CVaList) callconv(.c) c_int {
    var buf: [256]u8 = undefined;
    var f = std.mem.zeroes(FILE);
    f.buf = &buf;
    f.buf_size = buf.len;
    f.cookie = @ptrCast(@constCast(s));
    f.read_fn = &wstring_read;
    f.lock = -1;
    return vfwscanf_impl(@ptrCast(&f), fmt, ap);
}

const VfwscanfSize = enum(i32) {
    hh = -2,
    h = -1,
    def = 0,
    l = 1,
    L = 2,
    ll = 3,
};

inline fn wcharAsU32(c: wchar_t) u32 {
    return @as(u32, @bitCast(c));
}

inline fn wintAsU32(c: wint_t) u32 {
    return @as(u32, @bitCast(c));
}

inline fn iswspace_local(c: u32) bool {
    const spaces = [_]u32{
        ' ',    '\t',   '\n',   '\r',   11,     12,     0x0085,
        0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006,
        0x2008, 0x2009, 0x200a, 0x2028, 0x2029, 0x205f, 0x3000,
    };
    if (c == 0) return false;
    for (spaces) |space| {
        if (c == space) return true;
    }
    return false;
}

inline fn iswdigit_local(c: wchar_t) bool {
    const wc = wcharAsU32(c);
    return wc >= '0' and wc <= '9';
}

inline fn vfwscanfGetwc(f: *FILE) wint_t {
    if (f.rpos != f.rend and f.rpos.?[0] < 128) {
        const c = f.rpos.?[0];
        f.rpos = f.rpos.? + 1;
        return c;
    }
    return fgetwc_fn(f);
}

inline fn vfwscanfUngetwc(c: wint_t, f: *FILE) void {
    if (f.rend != null and wintAsU32(c) < 128) {
        f.rpos = f.rpos.? - 1;
        f.rpos.?[0] = @intCast(wintAsU32(c));
    } else {
        _ = ungetwc_fn(c, f);
    }
}

fn vfwscanfStoreInt(dest: ?*anyopaque, size: VfwscanfSize, i: c_ulonglong) void {
    const d = dest orelse return;
    switch (size) {
        .hh => @as(*c_char, @ptrCast(@alignCast(d))).* = @bitCast(@as(u8, @truncate(i))),
        .h => @as(*c_short, @ptrCast(@alignCast(d))).* = @bitCast(@as(c_ushort, @truncate(i))),
        .def => @as(*c_int, @ptrCast(@alignCast(d))).* = @bitCast(@as(c_uint, @truncate(i))),
        .l => @as(*c_long, @ptrCast(@alignCast(d))).* = @bitCast(@as(c_ulong, @truncate(i))),
        .ll => @as(*c_longlong, @ptrCast(@alignCast(d))).* = @bitCast(i),
        .L => {},
    }
}

fn vfwscanfArgN(ap: VaList, n: c_uint) callconv(.c) ?*anyopaque {
    var ap_src = ap;
    var ap2 = @cVaCopy(&ap_src);
    defer @cVaEnd(&ap2);
    var i = n;
    while (i > 1) : (i -= 1) {
        _ = cVaArg(&ap2, ?*anyopaque);
    }
    return cVaArg(&ap2, ?*anyopaque);
}

fn vfwscanfInSet(set: [*:0]const wchar_t, c: wint_t) bool {
    var p = set;
    const wc = wintAsU32(c);
    if (wcharAsU32(p[0]) == '-') {
        if (wc == '-') return true;
        p += 1;
    } else if (wcharAsU32(p[0]) == ']') {
        if (wc == ']') return true;
        p += 1;
    }
    while (p[0] != 0 and wcharAsU32(p[0]) != ']') : (p += 1) {
        if (wcharAsU32(p[0]) == '-' and p[1] != 0 and wcharAsU32(p[1]) != ']') {
            const start = wcharAsU32((p - 1)[0]);
            p += 1;
            var j = start;
            while (j < wcharAsU32(p[0])) : (j += 1) {
                if (wc == j) return true;
            }
        }
        if (wc == wcharAsU32(p[0])) return true;
    }
    return false;
}

const vfwscanf_spaces = [_:0]wchar_t{
    ' ',    '\t',   '\n',   '\r',   11,     12,     0x0085,
    0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006,
    0x2008, 0x2009, 0x200a, 0x2028, 0x2029, 0x205f, 0x3000,
};

fn vfwscanfFail(f: *FILE, need_unlock: c_int, matches_in: c_int, alloc: bool, s: ?[*]u8, wcs: ?[*]wchar_t, input_failure: bool) c_int {
    var matches = matches_in;
    if (input_failure and matches == 0) matches -= 1;
    if (alloc) {
        free_fn(@ptrCast(s));
        free_fn(@ptrCast(wcs));
    }
    funlock(f, need_unlock);
    return matches;
}

/// vfwscanf.c: int vfwscanf(FILE *restrict f, const wchar_t *restrict fmt, va_list ap)
fn vfwscanf_impl(f_raw: ?*FILE, fmt: [*:0]const wchar_t, ap: CVaList) callconv(.c) c_int {
    const f = f_raw orelse return -1;
    var p = fmt;
    var dest: ?*anyopaque = null;
    var matches: c_int = 0;
    var pos: i64 = 0;
    const size_pfx = [_][]const u8{ "hh", "h", "", "l", "L", "ll" };
    var tmp: [3 * @sizeOf(c_int) + 10:0]u8 = undefined;

    const need_unlock = flock(f);
    _ = fwide_fn(f, 1);

    var ap_src = unpackVaList(ap);

    while (p[0] != 0) : (p += 1) {
        var alloc = false;

        if (iswspace_local(wcharAsU32(p[0]))) {
            while (iswspace_local(wcharAsU32(p[1]))) p += 1;
            while (true) {
                const c = vfwscanfGetwc(f);
                if (!iswspace_local(wintAsU32(c))) {
                    vfwscanfUngetwc(c, f);
                    break;
                }
                pos += 1;
            }
            continue;
        }
        if (wcharAsU32(p[0]) != '%' or wcharAsU32(p[1]) == '%') {
            var c: wint_t = undefined;
            if (wcharAsU32(p[0]) == '%') {
                p += 1;
                while (true) {
                    c = vfwscanfGetwc(f);
                    if (!iswspace_local(wintAsU32(c))) break;
                    pos += 1;
                }
            } else {
                c = vfwscanfGetwc(f);
            }
            if (wintAsU32(c) != wcharAsU32(p[0])) {
                vfwscanfUngetwc(c, f);
                if (c < 0) return vfwscanfFail(f, need_unlock, matches, alloc, null, null, true);
                return vfwscanfFail(f, need_unlock, matches, alloc, null, null, false);
            }
            pos += 1;
            continue;
        }

        p += 1;
        if (wcharAsU32(p[0]) == '*') {
            dest = null;
            p += 1;
        } else if (iswdigit_local(p[0]) and wcharAsU32(p[1]) == '$') {
            dest = vfwscanfArgN(ap_src, wcharAsU32(p[0]) - '0');
            p += 2;
        } else {
            dest = cVaArg(&ap_src, ?*anyopaque);
        }

        var width: c_int = 0;
        while (iswdigit_local(p[0])) : (p += 1) {
            width = 10 * width + @as(c_int, @intCast(wcharAsU32(p[0]) - '0'));
        }

        var s: ?[*]u8 = null;
        var wcs: ?[*]wchar_t = null;
        if (wcharAsU32(p[0]) == 'm') {
            alloc = dest != null;
            p += 1;
        }

        var size: VfwscanfSize = .def;
        const size_ch = wcharAsU32(p[0]);
        p += 1;
        switch (size_ch) {
            'h' => if (wcharAsU32(p[0]) == 'h') {
                p += 1;
                size = .hh;
            } else {
                size = .h;
            },
            'l' => if (wcharAsU32(p[0]) == 'l') {
                p += 1;
                size = .ll;
            } else {
                size = .l;
            },
            'j' => size = .ll,
            'z', 't' => size = .l,
            'L' => size = .L,
            'd', 'i', 'o', 'u', 'x', 'a', 'e', 'f', 'g', 'A', 'E', 'F', 'G', 'X', 's', 'c', '[', 'S', 'C', 'p', 'n' => p -= 1,
            else => return vfwscanfFail(f, need_unlock, matches, alloc, s, wcs, true),
        }

        var t = wcharAsU32(p[0]);
        if ((t & 0x2f) == 3) {
            size = .l;
            t |= 32;
        }

        if (t != 'n') {
            var c: wint_t = undefined;
            if (t != '[' and (t | 32) != 'c') {
                while (true) {
                    c = vfwscanfGetwc(f);
                    if (!iswspace_local(wintAsU32(c))) break;
                    pos += 1;
                }
            } else {
                c = vfwscanfGetwc(f);
            }
            if (c < 0) return vfwscanfFail(f, need_unlock, matches, alloc, s, wcs, true);
            vfwscanfUngetwc(c, f);
        }

        switch (t) {
            'n' => {
                vfwscanfStoreInt(dest, size, @intCast(pos));
                continue;
            },
            's', 'c', '[' => {
                var invert: c_int = undefined;
                var set: [*:0]const wchar_t = undefined;
                if (t == 'c') {
                    if (width < 1) width = 1;
                    invert = 1;
                    set = @ptrCast(&[_:0]wchar_t{});
                } else if (t == 's') {
                    invert = 1;
                    set = @ptrCast(&vfwscanf_spaces);
                } else {
                    p += 1;
                    if (wcharAsU32(p[0]) == '^') {
                        p += 1;
                        invert = 1;
                    } else {
                        invert = 0;
                    }
                    set = p;
                    if (wcharAsU32(p[0]) == ']') p += 1;
                    while (wcharAsU32(p[0]) != ']') : (p += 1) {
                        if (p[0] == 0) return vfwscanfFail(f, need_unlock, matches, alloc, s, wcs, true);
                    }
                }

                if (size == .def) s = @ptrCast(dest);
                if (size == .l) wcs = @ptrCast(@alignCast(dest));
                var gotmatch = false;
                if (width < 1) width = -1;
                var i: usize = 0;
                var k: usize = undefined;
                if (alloc) {
                    k = if (t == 'c') @as(usize, @intCast(width)) + 1 else 31;
                    if (size == .l) {
                        wcs = @ptrCast(@alignCast(malloc_fn(k * @sizeOf(wchar_t)) orelse return vfwscanfFail(f, need_unlock, matches, alloc, s, wcs, true)));
                    } else {
                        s = @ptrCast(malloc_fn(k) orelse return vfwscanfFail(f, need_unlock, matches, alloc, s, wcs, true));
                    }
                }
                while (width != 0) {
                    const c = vfwscanfGetwc(f);
                    if (c < 0) break;
                    if (@intFromBool(vfwscanfInSet(set, c)) == invert) {
                        vfwscanfUngetwc(c, f);
                        if (t == 'c' or !gotmatch) return vfwscanfFail(f, need_unlock, matches, alloc, s, wcs, false);
                        break;
                    }
                    if (wcs) |wcs_ptr| {
                        wcs_ptr[i] = @bitCast(wintAsU32(c));
                        i += 1;
                        if (alloc and i == k) {
                            k += k + 1;
                            wcs = @ptrCast(@alignCast(realloc_fn(@ptrCast(wcs_ptr), k * @sizeOf(wchar_t)) orelse return vfwscanfFail(f, need_unlock, matches, alloc, s, wcs, true)));
                        }
                    } else if (size != .l) {
                        const out = if (s) |s_ptr| s_ptr + i else @as([*]u8, @ptrCast(&tmp));
                        const l = wctomb_fn(out, @bitCast(wintAsU32(c)));
                        if (l < 0) return vfwscanfFail(f, need_unlock, matches, alloc, s, wcs, true);
                        i += @intCast(l);
                        if (alloc and i > k - 4) {
                            k += k + 1;
                            s = @ptrCast(realloc_fn(@ptrCast(s.?), k) orelse return vfwscanfFail(f, need_unlock, matches, alloc, s, wcs, true));
                        }
                    }
                    pos += 1;
                    width -= @intFromBool(width > 0);
                    gotmatch = true;
                }

                if (alloc) {
                    if (size == .l) {
                        @as(*?[*]wchar_t, @ptrCast(@alignCast(dest.?))).* = wcs;
                    } else {
                        @as(*?[*]u8, @ptrCast(@alignCast(dest.?))).* = s;
                    }
                }
                if (t != 'c') {
                    if (wcs) |wcs_ptr| wcs_ptr[i] = 0;
                    if (s) |s_ptr| s_ptr[i] = 0;
                }
            },
            'd', 'i', 'o', 'u', 'x', 'a', 'e', 'f', 'g', 'A', 'E', 'F', 'G', 'X', 'p' => {
                if (width < 1) width = 0;
                const prefix = size_pfx[@intCast(@backingInt(size) + 2)];
                const written = std.fmt.bufPrintSentinel(&tmp, "{s}{d}{s}{c}%lln", .{
                    if (dest == null) "%*" else "%",
                    width,
                    prefix,
                    @as(u8, @intCast(t)),
                }, 0) catch return vfwscanfFail(f, need_unlock, matches, alloc, s, wcs, true);
                var cnt: c_longlong = 0;
                const scan_result = if (dest) |d|
                    fscanf_impl(f, written, d, &cnt)
                else
                    fscanf_impl(f, written, &cnt, &cnt);
                if (scan_result == -1) return vfwscanfFail(f, need_unlock, matches, alloc, s, wcs, true);
                if (cnt == 0) return vfwscanfFail(f, need_unlock, matches, alloc, s, wcs, false);
                pos += cnt;
            },
            else => return vfwscanfFail(f, need_unlock, matches, alloc, s, wcs, true),
        }

        if (dest != null) matches += 1;
    }
    funlock(f, need_unlock);
    return matches;
}

/// vwprintf.c: int vwprintf(const wchar_t *restrict fmt, va_list ap)
fn vwprintf_impl(fmt: [*:0]const wchar_t, ap: CVaList) callconv(.c) c_int {
    return vfwprintf_impl(stdout_ext.*, fmt, ap);
}

/// vwscanf.c: int vwscanf(const wchar_t *restrict fmt, va_list ap)
fn vwscanf_impl(fmt: [*:0]const wchar_t, ap: CVaList) callconv(.c) c_int {
    return vfwscanf_impl(stdin_ext.*, fmt, ap);
}

/// vprintf.c: int vprintf(const char *restrict fmt, va_list ap)
fn vprintf_impl(fmt: [*:0]const u8, ap: CVaList) callconv(.c) c_int {
    return vfprintf_impl(stdout_ext.*, fmt, ap);
}

/// vscanf.c: int vscanf(const char *restrict fmt, va_list ap)
fn vscanf_impl(fmt: [*:0]const u8, ap: CVaList) callconv(.c) c_int {
    return vfscanf_impl(stdin_ext.*, fmt, ap);
}

// --- Locking (__lockfile.c, flockfile.c, funlockfile.c, ftrylockfile.c) ---

const MAYBE_WAITERS: c_int = 0x40000000;

/// Minimal model of musl's `struct __pthread` so that the `tid` and
/// `stdio_locks` fields land at their correct ABI offsets. Part 1
/// (architecture-dependent TLS header) is opaque padding; Part 2
/// (uniform across all targets) is represented by `tid`, a gap, then
/// `stdio_locks`.
const PThread = extern struct {
    _header: [header_size]u8,
    tid: c_int,
    _p2: [p2_size]u8,
    stdio_locks: ?*FILE,

    /// Architectures where musl defines TLS_ABOVE_TP.
    const tls_above_tp: bool = switch (builtin.cpu.arch) {
        .aarch64,
        .aarch64_be,
        .arm,
        .armeb,
        .thumb,
        .thumbeb,
        .loongarch64,
        .m68k,
        .mips,
        .mipsel,
        .mips64,
        .mips64el,
        .powerpc,
        .powerpcle,
        .powerpc64,
        .powerpc64le,
        .riscv32,
        .riscv64,
        => true,
        else => false,
    };

    /// musl/arch/x32 is the only architecture that defines CANARY_PAD.
    const has_canary_pad: bool = !tls_above_tp and builtin.cpu.arch == .x86_64 and @sizeOf(usize) == 4;

    /// Part 1 field count: self[, dtv], prev, next, sysinfo[, canary_pad][, canary].
    const part1_fields: usize = if (tls_above_tp) 4 else if (has_canary_pad) 7 else 6;
    const header_size: usize = part1_fields * @sizeOf(usize);

    /// Byte gap between end-of-tid and start-of-stdio_locks inside Part 2.
    /// Covers errno_val through dlerror_buf (see pthread_impl.h lines 36-59).
    const p2_size: usize = if (@sizeOf(usize) == 8) 140 else 80;
};

const pthread_self_fn = @extern(*const fn () callconv(.c) *PThread, .{ .name = "pthread_self" });

/// __lockfile.c: int __lockfile(FILE *f)
fn lockfile_impl(f: *FILE) callconv(.c) c_int {
    const tid = pthread_self_fn().tid;
    if ((f.lock & ~MAYBE_WAITERS) == tid)
        return 0;
    if (@cmpxchgStrong(c_int, &f.lock, 0, tid, .seq_cst, .seq_cst) == null)
        return 1;
    while (@cmpxchgStrong(c_int, &f.lock, 0, tid | MAYBE_WAITERS, .seq_cst, .seq_cst)) |owner| {
        if ((owner & MAYBE_WAITERS) != 0 or
            @cmpxchgStrong(c_int, &f.lock, owner, owner | MAYBE_WAITERS, .seq_cst, .seq_cst) == null)
        {
            futex_wait(&f.lock, owner | MAYBE_WAITERS);
        }
    }
    return 1;
}

/// __lockfile.c: void __unlockfile(FILE *f)
fn unlockfile_impl(f: *FILE) callconv(.c) void {
    if ((@atomicRmw(c_int, &f.lock, .Xchg, 0, .seq_cst) & MAYBE_WAITERS) != 0) {
        futex_wake(&f.lock, 1);
    }
}

/// flockfile.c: void flockfile(FILE *f)
fn flockfile_impl(f: *FILE) callconv(.c) void {
    if (ftrylockfile_impl(f) == 0) return;
    _ = lockfile_impl(f);
    register_locked_file_impl(f, pthread_self_fn());
}

/// funlockfile.c: void funlockfile(FILE *f)
fn funlockfile_impl(f: *FILE) callconv(.c) void {
    if (f.lockcount == 1) {
        unlist_locked_file_impl(f);
        f.lockcount = 0;
        unlockfile_impl(f);
    } else {
        f.lockcount -= 1;
    }
}

/// ftrylockfile.c: void __do_orphaned_stdio_locks(void)
fn do_orphaned_stdio_locks_impl() callconv(.c) void {
    var f = pthread_self_fn().stdio_locks;
    while (f) |file| : (f = file.next_locked) {
        @atomicStore(c_int, &file.lock, MAYBE_WAITERS, .seq_cst);
    }
}

/// ftrylockfile.c: void __unlist_locked_file(FILE *f)
fn unlist_locked_file_impl(f: *FILE) callconv(.c) void {
    if (f.lockcount != 0) {
        if (f.next_locked) |next| {
            next.prev_locked = f.prev_locked;
        }
        if (f.prev_locked) |prev| {
            prev.next_locked = f.next_locked;
        } else {
            pthread_self_fn().stdio_locks = f.next_locked;
        }
    }
}

/// ftrylockfile.c: void __register_locked_file(FILE *f, pthread_t self)
fn register_locked_file_impl(f: *FILE, self: *PThread) callconv(.c) void {
    f.lockcount = 1;
    f.prev_locked = null;
    f.next_locked = self.stdio_locks;
    if (f.next_locked) |next| {
        next.prev_locked = f;
    }
    self.stdio_locks = f;
}

/// ftrylockfile.c: int ftrylockfile(FILE *f)
fn ftrylockfile_impl(f: *FILE) callconv(.c) c_int {
    const self = pthread_self_fn();
    const tid = self.tid;
    var owner = f.lock;
    if ((owner & ~MAYBE_WAITERS) == tid) {
        if (f.lockcount == std.math.maxInt(c_long))
            return -1;
        f.lockcount += 1;
        return 0;
    }
    if (owner < 0) {
        f.lock = 0;
        owner = 0;
    }
    if (owner != 0 or @cmpxchgStrong(c_int, &f.lock, 0, tid, .seq_cst, .seq_cst) != null)
        return -1;
    register_locked_file_impl(f, self);
    return 0;
}

fn futex_wait(ptr: *const c_int, expected: c_int) void {
    _ = linux.futex_4arg(@ptrCast(ptr), .{ .cmd = .WAIT, .private = true }, @bitCast(expected), null);
}

fn futex_wake(ptr: *const c_int, count: u32) void {
    _ = linux.futex_3arg(@ptrCast(ptr), .{ .cmd = .WAKE, .private = true }, count);
}

// --- Memory stream functions (fmemopen.c, open_memstream.c, open_wmemstream.c, fopencookie.c) ---

// Minimal view of musl's struct __libc, enough to read the `threaded` field.
const Libc = extern struct {
    can_do_threads: u8,
    threaded: u8,
};

// musl mbstate_t: struct { unsigned __opaque1, __opaque2; }
const mbstate_t = extern struct {
    __opaque1: c_uint = 0,
    __opaque2: c_uint = 0,
};

// --- fmemopen.c ---

const FmemCookie = extern struct {
    pos: usize,
    len: usize,
    size: usize,
    buf: ?[*]u8,
    mode: c_int,
};

const MemFILE = extern struct {
    f: FILE,
    c: FmemCookie,
    buf: [UNGET + BUFSIZ]u8,
    // Flexible array member buf2[] is allocated past this struct.
};

fn mseek_impl(f: *FILE, off: i64, whence: c_int) callconv(.c) i64 {
    const c: *FmemCookie = @ptrCast(@alignCast(f.cookie.?));
    const w: usize = @intCast(@as(c_uint, @bitCast(whence)));
    if (w > 2) {
        setErrno(.INVAL);
        return -1;
    }
    const base: isize = @intCast(([3]usize{ 0, c.pos, c.len })[w]);
    if (off < -@as(i64, base) or off > @as(i64, @as(isize, @intCast(c.size))) - @as(i64, base)) {
        setErrno(.INVAL);
        return -1;
    }
    const new_pos: usize = @intCast(@as(i64, base) + off);
    c.pos = new_pos;
    return @intCast(new_pos);
}

fn mread_impl(f: *FILE, buf: [*]u8, len_arg: usize) callconv(.c) usize {
    const c: *FmemCookie = @ptrCast(@alignCast(f.cookie.?));
    var rem: usize = if (c.pos > c.len) 0 else c.len - c.pos;
    var len = len_arg;
    if (len > rem) {
        len = rem;
        f.flags |= F_EOF;
    }
    if (len > 0) @memcpy(buf[0..len], c.buf.?[c.pos..][0..len]);
    c.pos += len;
    rem -= len;
    if (rem > f.buf_size) rem = f.buf_size;
    f.rpos = f.buf;
    if (f.buf) |b| {
        f.rend = b + rem;
        if (rem > 0) @memcpy(b[0..rem], c.buf.?[c.pos..][0..rem]);
    }
    c.pos += rem;
    return len;
}

fn mwrite_impl(f: *FILE, buf: [*]const u8, len_arg: usize) callconv(.c) usize {
    const c: *FmemCookie = @ptrCast(@alignCast(f.cookie.?));
    const len2: usize = if (f.wpos != null and f.wbase != null)
        @intFromPtr(f.wpos.?) - @intFromPtr(f.wbase.?)
    else
        0;
    if (len2 != 0) {
        f.wpos = f.wbase;
        if (mwrite_impl(f, @ptrCast(f.wpos.?), len2) < len2) return 0;
    }
    if (c.mode == 'a') c.pos = c.len;
    const rem = c.size - c.pos;
    var len = len_arg;
    if (len > rem) len = rem;
    if (len > 0) @memcpy(c.buf.?[c.pos..][0..len], buf[0..len]);
    c.pos += len;
    if (c.pos > c.len) {
        c.len = c.pos;
        if (c.len < c.size)
            c.buf.?[c.len] = 0
        else if (f.flags & F_NORD != 0 and c.size != 0)
            c.buf.?[c.size - 1] = 0;
    }
    return len;
}

fn mclose_impl(_: *FILE) callconv(.c) c_int {
    return 0;
}

/// fmemopen.c: FILE *fmemopen(void *restrict buf, size_t size, const char *restrict mode)
fn fmemopen_impl(user_buf: ?[*]u8, size: usize, mode: [*:0]const u8) callconv(.c) ?*FILE {
    const mode_char = mode[0];
    if (mode_char != 'r' and mode_char != 'w' and mode_char != 'a') {
        setErrno(.INVAL);
        return null;
    }
    if (user_buf == null and size > @as(usize, @intCast(std.math.maxInt(isize)))) {
        setErrno(.NOMEM);
        return null;
    }
    const has_plus = std.mem.indexOfScalar(u8, std.mem.span(mode), '+') != null;
    const extra: usize = if (user_buf != null) 0 else size;
    const alloc_size = @sizeOf(MemFILE) + extra;
    const raw_ptr: *anyopaque = malloc_fn(alloc_size) orelse return null;
    const mf: *MemFILE = @ptrCast(@alignCast(raw_ptr));

    // Zero FILE and cookie (but not the I/O buffer), matching C offsetof(struct mem_FILE, buf).
    @memset(@as([*]u8, @ptrCast(mf))[0..@offsetOf(MemFILE, "buf")], 0);

    mf.f.cookie = @ptrCast(&mf.c);
    mf.f.fd = -1;
    mf.f.lbf = EOF;
    const buf_start: [*]u8 = @ptrCast(&mf.buf);
    mf.f.buf = buf_start + UNGET;
    mf.f.buf_size = (UNGET + BUFSIZ) - UNGET;

    var buf_ptr: [*]u8 = undefined;
    if (user_buf) |ub| {
        buf_ptr = ub;
    } else {
        buf_ptr = @as([*]u8, @ptrCast(mf)) + @sizeOf(MemFILE);
        @memset(buf_ptr[0..size], 0);
    }

    mf.c.buf = buf_ptr;
    mf.c.size = size;
    mf.c.mode = @intCast(mode_char);

    if (!has_plus) mf.f.flags = if (mode_char == 'r') F_NOWR else F_NORD;
    if (mode_char == 'r') {
        mf.c.len = size;
    } else if (mode_char == 'a') {
        const slen = std.mem.indexOfScalar(u8, buf_ptr[0..size], 0) orelse size;
        mf.c.len = slen;
        mf.c.pos = slen;
    } else if (has_plus) {
        buf_ptr[0] = 0;
    }

    mf.f.read_fn = &mread_impl;
    mf.f.write_fn = &mwrite_impl;
    mf.f.seek_fn = &mseek_impl;
    mf.f.close_fn = &mclose_impl;

    if (builtin.target.isWasiLibC() or libc_ptr.threaded == 0) mf.f.lock = -1;

    return ofl_add_fn(&mf.f);
}

// --- open_memstream.c ---

const MsCookie = extern struct {
    bufp: *?[*]u8,
    sizep: *usize,
    pos: usize,
    buf: ?[*]u8,
    len: usize,
    space: usize,
};

const MsFILE = extern struct {
    f: FILE,
    c: MsCookie,
    buf: [BUFSIZ]u8,
};

fn ms_seek_impl(f: *FILE, off: i64, whence: c_int) callconv(.c) i64 {
    const c: *MsCookie = @ptrCast(@alignCast(f.cookie.?));
    const w: usize = @intCast(@as(c_uint, @bitCast(whence)));
    if (w > 2) {
        setErrno(.INVAL);
        return -1;
    }
    const base: isize = @intCast(([3]usize{ 0, c.pos, c.len })[w]);
    const ssize_max: i64 = std.math.maxInt(isize);
    if (off < -@as(i64, base) or off > ssize_max - @as(i64, base)) {
        setErrno(.INVAL);
        return -1;
    }
    const new_pos: usize = @intCast(@as(i64, base) + off);
    c.pos = new_pos;
    return @intCast(new_pos);
}

fn ms_write_impl(f: *FILE, buf: [*]const u8, len: usize) callconv(.c) usize {
    const c: *MsCookie = @ptrCast(@alignCast(f.cookie.?));
    const len2: usize = if (f.wpos != null and f.wbase != null)
        @intFromPtr(f.wpos.?) - @intFromPtr(f.wbase.?)
    else
        0;
    if (len2 != 0) {
        f.wpos = f.wbase;
        if (ms_write_impl(f, @ptrCast(f.wbase.?), len2) < len2) return 0;
    }
    if (len + c.pos >= c.space) {
        const new_space = (2 * c.space + 1) | (c.pos + len + 1);
        const newbuf = realloc_fn(@ptrCast(c.buf), new_space) orelse return 0;
        const new_ptr: [*]u8 = @ptrCast(newbuf);
        c.bufp.* = new_ptr;
        c.buf = new_ptr;
        @memset(new_ptr[c.space..new_space], 0);
        c.space = new_space;
    }
    if (len > 0) @memcpy(c.buf.?[c.pos..][0..len], buf[0..len]);
    c.pos += len;
    if (c.pos >= c.len) c.len = c.pos;
    c.sizep.* = c.pos;
    return len;
}

fn ms_close_impl(_: *FILE) callconv(.c) c_int {
    return 0;
}

/// open_memstream.c: FILE *open_memstream(char **bufp, size_t *sizep)
fn open_memstream_impl(bufp: *?[*]u8, sizep: *usize) callconv(.c) ?*FILE {
    const raw: *anyopaque = malloc_fn(@sizeOf(MsFILE)) orelse return null;
    const ms: *MsFILE = @ptrCast(@alignCast(raw));
    const buf_raw: *anyopaque = malloc_fn(1) orelse {
        free_fn(raw);
        return null;
    };
    const initial_buf: [*]u8 = @ptrCast(buf_raw);

    ms.f = std.mem.zeroes(FILE);
    ms.c = MsCookie{
        .bufp = bufp,
        .sizep = sizep,
        .pos = 0,
        .buf = initial_buf,
        .len = 0,
        .space = 0,
    };
    sizep.* = 0;
    bufp.* = initial_buf;
    initial_buf[0] = 0;

    ms.f.cookie = @ptrCast(&ms.c);
    ms.f.flags = F_NORD;
    ms.f.fd = -1;
    const ms_buf_start: [*]u8 = @ptrCast(&ms.buf);
    ms.f.buf = ms_buf_start;
    ms.f.buf_size = BUFSIZ;
    ms.f.lbf = EOF;
    ms.f.write_fn = &ms_write_impl;
    ms.f.seek_fn = &ms_seek_impl;
    ms.f.close_fn = &ms_close_impl;
    ms.f.mode = -1;

    if (builtin.target.isWasiLibC() or libc_ptr.threaded == 0) ms.f.lock = -1;

    return ofl_add_fn(&ms.f);
}

// --- open_wmemstream.c ---

const WmsCookie = extern struct {
    bufp: *?[*]wchar_t,
    sizep: *usize,
    pos: usize,
    buf: ?[*]wchar_t,
    len: usize,
    space: usize,
    mbs: mbstate_t,
};

const WmsFILE = extern struct {
    f: FILE,
    c: WmsCookie,
    buf: [1]u8,
};

fn wms_seek_impl(f: *FILE, off: i64, whence: c_int) callconv(.c) i64 {
    const c: *WmsCookie = @ptrCast(@alignCast(f.cookie.?));
    const w: usize = @intCast(@as(c_uint, @bitCast(whence)));
    if (w > 2) {
        setErrno(.INVAL);
        return -1;
    }
    const base: isize = @intCast(([3]usize{ 0, c.pos, c.len })[w]);
    const ssize_max_div4: i64 = @divFloor(std.math.maxInt(isize), 4);
    if (off < -@as(i64, base) or off > ssize_max_div4 - @as(i64, base)) {
        setErrno(.INVAL);
        return -1;
    }
    c.mbs = std.mem.zeroes(mbstate_t);
    const new_pos: usize = @intCast(@as(i64, base) + off);
    c.pos = new_pos;
    return @intCast(new_pos);
}

fn wms_write_impl(f: *FILE, buf: [*]const u8, len: usize) callconv(.c) usize {
    const c: *WmsCookie = @ptrCast(@alignCast(f.cookie.?));
    const len2_init: usize = if (f.wpos != null and f.wbase != null)
        @intFromPtr(f.wpos.?) - @intFromPtr(f.wbase.?)
    else
        0;
    if (len2_init != 0) {
        f.wpos = f.wbase;
        if (wms_write_impl(f, @ptrCast(f.wbase.?), len2_init) < len2_init) return 0;
    }
    if (len + c.pos >= c.space) {
        const new_space = (2 * c.space + 1) | (c.pos + len + 1);
        const ssize_max_div4: usize = @intCast(@divFloor(std.math.maxInt(isize), 4));
        if (new_space > ssize_max_div4) return 0;
        const newbuf_raw = realloc_fn(@ptrCast(c.buf), new_space * @sizeOf(wchar_t)) orelse return 0;
        const newbuf: [*]wchar_t = @ptrCast(@alignCast(newbuf_raw));
        c.bufp.* = newbuf;
        c.buf = newbuf;
        const start_bytes: [*]u8 = @ptrCast(c.buf.? + c.space);
        @memset(start_bytes[0 .. @sizeOf(wchar_t) * (new_space - c.space)], 0);
        c.space = new_space;
    }
    var src_ptr: ?[*]const u8 = buf;
    const result = mbsnrtowcs_fn(c.buf.? + c.pos, &src_ptr, len, c.space - c.pos, &c.mbs);
    if (result == @as(usize, @bitCast(@as(isize, -1)))) return 0;
    c.pos += result;
    if (c.pos >= c.len) c.len = c.pos;
    c.sizep.* = c.pos;
    return len;
}

fn wms_close_impl(_: *FILE) callconv(.c) c_int {
    return 0;
}

/// open_wmemstream.c: FILE *open_wmemstream(wchar_t **bufp, size_t *sizep)
fn open_wmemstream_impl(bufp: *?[*]wchar_t, sizep: *usize) callconv(.c) ?*FILE {
    const raw: *anyopaque = malloc_fn(@sizeOf(WmsFILE)) orelse return null;
    const wms: *WmsFILE = @ptrCast(@alignCast(raw));
    const buf_raw: *anyopaque = malloc_fn(@sizeOf(wchar_t)) orelse {
        free_fn(raw);
        return null;
    };
    const initial_buf: [*]wchar_t = @ptrCast(@alignCast(buf_raw));

    wms.f = std.mem.zeroes(FILE);
    wms.c = WmsCookie{
        .bufp = bufp,
        .sizep = sizep,
        .pos = 0,
        .buf = initial_buf,
        .len = 0,
        .space = 0,
        .mbs = std.mem.zeroes(mbstate_t),
    };
    sizep.* = 0;
    bufp.* = initial_buf;
    initial_buf[0] = 0;

    wms.f.cookie = @ptrCast(&wms.c);
    wms.f.flags = F_NORD;
    wms.f.fd = -1;
    const wms_buf_start: [*]u8 = @ptrCast(&wms.buf);
    wms.f.buf = wms_buf_start;
    wms.f.buf_size = 0;
    wms.f.lbf = EOF;
    wms.f.write_fn = &wms_write_impl;
    wms.f.seek_fn = &wms_seek_impl;
    wms.f.close_fn = &wms_close_impl;

    if (builtin.target.isWasiLibC() or libc_ptr.threaded == 0) wms.f.lock = -1;

    _ = fwide_fn(&wms.f, 1);

    return ofl_add_fn(&wms.f);
}

// --- fopencookie.c ---

const CookieReadFn = *const fn (?*anyopaque, [*]u8, usize) callconv(.c) isize;
const CookieWriteFn = *const fn (?*anyopaque, [*]const u8, usize) callconv(.c) isize;
const CookieSeekFn = *const fn (?*anyopaque, *i64, c_int) callconv(.c) c_int;
const CookieCloseFn = *const fn (?*anyopaque) callconv(.c) c_int;

const CookieIoFunctions = extern struct {
    read: ?CookieReadFn,
    write: ?CookieWriteFn,
    seek: ?CookieSeekFn,
    close: ?CookieCloseFn,
};

const FCookie = extern struct {
    cookie: ?*anyopaque,
    iofuncs: CookieIoFunctions,
};

const CookieFILE = extern struct {
    f: FILE,
    fc: FCookie,
    buf: [UNGET + BUFSIZ]u8,
};

fn cookieread_impl(f: *FILE, buf: [*]u8, len: usize) callconv(.c) usize {
    const fc: *FCookie = @ptrCast(@alignCast(f.cookie.?));
    var ret: isize = -1;
    var remain = len;
    var readlen: usize = 0;
    const has_buf: usize = @intFromBool(f.buf_size != 0);
    const len2 = len - has_buf;

    const read_fn = fc.iofuncs.read orelse {
        f.flags |= F_ERR;
        f.rpos = f.buf;
        f.rend = f.buf;
        return 0;
    };

    if (len2 != 0) {
        ret = read_fn(fc.cookie, buf, len2);
        if (ret <= 0) {
            f.flags |= if (ret == 0) F_EOF else F_ERR;
            f.rpos = f.buf;
            f.rend = f.buf;
            return readlen;
        }
        const ret_u: usize = @intCast(ret);
        readlen += ret_u;
        remain -= ret_u;
    }

    if (f.buf_size == 0 or remain > has_buf) return readlen;

    f.rpos = f.buf;
    ret = read_fn(fc.cookie, @ptrCast(f.rpos.?), f.buf_size);
    if (ret <= 0) {
        f.flags |= if (ret == 0) F_EOF else F_ERR;
        f.rpos = f.buf;
        f.rend = f.buf;
        return readlen;
    }
    f.rend = f.rpos.? + @as(usize, @intCast(ret));

    buf[readlen] = f.rpos.?[0];
    f.rpos = f.rpos.? + 1;
    readlen += 1;

    return readlen;
}

fn cookiewrite_impl(f: *FILE, buf: [*]const u8, len: usize) callconv(.c) usize {
    const fc: *FCookie = @ptrCast(@alignCast(f.cookie.?));
    const len2: usize = if (f.wpos != null and f.wbase != null)
        @intFromPtr(f.wpos.?) - @intFromPtr(f.wbase.?)
    else
        0;
    const write_fn = fc.iofuncs.write orelse return len;
    if (len2 != 0) {
        f.wpos = f.wbase;
        if (cookiewrite_impl(f, @ptrCast(f.wpos.?), len2) < len2) return 0;
    }
    const ret = write_fn(fc.cookie, buf, len);
    if (ret < 0) {
        f.wpos = null;
        f.wbase = null;
        f.wend = null;
        f.flags |= F_ERR;
        return 0;
    }
    return @intCast(ret);
}

fn cookieseek_impl(f: *FILE, off: i64, whence: c_int) callconv(.c) i64 {
    const fc: *FCookie = @ptrCast(@alignCast(f.cookie.?));
    const w: c_uint = @bitCast(whence);
    if (w > 2) {
        setErrno(.INVAL);
        return -1;
    }
    const seek_fn = fc.iofuncs.seek orelse {
        setErrno(.OPNOTSUPP);
        return -1;
    };
    var off_mut = off;
    const res = seek_fn(fc.cookie, &off_mut, whence);
    if (res < 0) return @intCast(res);
    return off_mut;
}

fn cookieclose_impl(f: *FILE) callconv(.c) c_int {
    const fc: *FCookie = @ptrCast(@alignCast(f.cookie.?));
    if (fc.iofuncs.close) |close_fn| return close_fn(fc.cookie);
    return 0;
}

/// fopencookie.c: FILE *fopencookie(void *cookie, const char *mode, cookie_io_functions_t iofuncs)
fn fopencookie_impl(cookie: ?*anyopaque, mode: [*:0]const u8, iofuncs: CookieIoFunctions) callconv(.c) ?*FILE {
    const mode_char = mode[0];
    if (mode_char != 'r' and mode_char != 'w' and mode_char != 'a') {
        setErrno(.INVAL);
        return null;
    }
    const raw: *anyopaque = malloc_fn(@sizeOf(CookieFILE)) orelse return null;
    const cf: *CookieFILE = @ptrCast(@alignCast(raw));

    cf.f = std.mem.zeroes(FILE);

    if (std.mem.indexOfScalar(u8, std.mem.span(mode), '+') == null)
        cf.f.flags = if (mode_char == 'r') F_NOWR else F_NORD;

    cf.fc = FCookie{
        .cookie = cookie,
        .iofuncs = iofuncs,
    };

    cf.f.fd = -1;
    cf.f.cookie = @ptrCast(&cf.fc);
    const cf_buf_start: [*]u8 = @ptrCast(&cf.buf);
    cf.f.buf = cf_buf_start + UNGET;
    cf.f.buf_size = (UNGET + BUFSIZ) - UNGET;
    cf.f.lbf = EOF;

    cf.f.read_fn = &cookieread_impl;
    cf.f.write_fn = &cookiewrite_impl;
    cf.f.seek_fn = &cookieseek_impl;
    cf.f.close_fn = &cookieclose_impl;

    return ofl_add_fn(&cf.f);
}

// Extern references to musl C functions that are still compiled from C sources.
const free_fn = @extern(*const fn (?*anyopaque) callconv(.c) void, .{ .name = "free" });
const ofl_add_fn = @extern(*const fn (*FILE) callconv(.c) ?*FILE, .{ .name = "__ofl_add" });
const libc_ptr = @extern(*const Libc, .{ .name = "__libc" });
const fwide_fn = @extern(*const fn (*FILE, c_int) callconv(.c) c_int, .{ .name = "fwide" });
const mbsnrtowcs_fn = @extern(*const fn (?[*]wchar_t, *?[*]const u8, usize, usize, *mbstate_t) callconv(.c) usize, .{ .name = "mbsnrtowcs" });
const fcntl_fn = @extern(*const fn (c_int, c_int, ...) callconv(.c) c_int, .{ .name = "fcntl" });
const posix_close_fn = @extern(*const fn (c_int) callconv(.c) c_int, .{ .name = "close" });
const posix_read_fn = @extern(*const fn (c_int, [*]u8, usize) callconv(.c) isize, .{ .name = "read" });
const readv_fn = @extern(*const fn (c_int, [*]const std.posix.iovec, c_int) callconv(.c) isize, .{ .name = "readv" });
const writev_fn = @extern(*const fn (c_int, [*]const std.posix.iovec_const, c_int) callconv(.c) isize, .{ .name = "writev" });
const isatty_fn = @extern(*const fn (c_int) callconv(.c) c_int, .{ .name = "__isatty" });
const wasilibc_open_nomode_fn = @extern(*const fn ([*:0]const u8, c_int) callconv(.c) c_int, .{ .name = "__wasilibc_open_nomode" });
const wasilibc_fd_renumber_fn = @extern(*const fn (c_int, c_int) callconv(.c) c_int, .{ .name = "__wasilibc_fd_renumber" });

// ===========================================================================
// Internal scanners: shgetc.c, intscan.c, floatscan.c
// ===========================================================================

inline fn shcnt_fn(f: *FILE) i64 {
    return f.shcnt + @as(i64, @as(isize, @bitCast(@intFromPtr(f.rpos) -% @intFromPtr(f.buf))));
}

inline fn shgetc_macro(f: *FILE) c_int {
    if (@intFromPtr(f.rpos) != @intFromPtr(f.shend)) {
        const rpos = f.rpos.?;
        const c = rpos[0];
        f.rpos = rpos + 1;
        return c;
    }
    return shgetc_impl(f);
}

inline fn shunget_macro(f: *FILE) void {
    if (f.shlim >= 0) {
        f.rpos = f.rpos.? - 1;
    }
}

/// shgetc.c: void __shlim(FILE *f, off_t lim)
fn shlim_impl(f: *FILE, lim: i64) callconv(.c) void {
    f.shlim = lim;
    f.shcnt = @as(i64, @as(isize, @bitCast(@intFromPtr(f.buf) -% @intFromPtr(f.rpos))));
    if (lim != 0 and @as(i64, @as(isize, @bitCast(@intFromPtr(f.rend) -% @intFromPtr(f.rpos)))) > lim) {
        f.shend = f.rpos.? + @as(usize, @intCast(lim));
    } else {
        f.shend = f.rend;
    }
}

/// shgetc.c: int __shgetc(FILE *f)
fn shgetc_impl(f: *FILE) callconv(.c) c_int {
    var cnt: i64 = shcnt_fn(f);
    var c: c_int = undefined;
    if ((f.shlim != 0 and cnt >= f.shlim) or blk: {
        c = uflow_fn(f);
        break :blk c < 0;
    }) {
        f.shcnt = @as(i64, @as(isize, @bitCast(@intFromPtr(f.buf) -% @intFromPtr(f.rpos)))) + cnt;
        f.shend = f.rpos;
        f.shlim = -1;
        return EOF;
    }
    cnt += 1;
    if (f.shlim != 0 and @as(i64, @as(isize, @bitCast(@intFromPtr(f.rend) -% @intFromPtr(f.rpos)))) > f.shlim - cnt) {
        f.shend = f.rpos.? + @as(usize, @intCast(f.shlim - cnt));
    } else {
        f.shend = f.rend;
    }
    f.shcnt = @as(i64, @as(isize, @bitCast(@intFromPtr(f.buf) -% @intFromPtr(f.rpos)))) + cnt;
    if (@intFromPtr(f.rpos) <= @intFromPtr(f.buf)) {
        (f.rpos.? - 1)[0] = @truncate(@as(c_uint, @bitCast(c)));
    }
    return c;
}

const intscan_table = [257]u8{
    255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    0,   1,   2,   3,   4,   5,   6,   7,   8,   9,   255, 255, 255, 255, 255, 255,
    255, 10,  11,  12,  13,  14,  15,  16,  17,  18,  19,  20,  21,  22,  23,  24,
    25,  26,  27,  28,  29,  30,  31,  32,  33,  34,  35,  255, 255, 255, 255, 255,
    255, 10,  11,  12,  13,  14,  15,  16,  17,  18,  19,  20,  21,  22,  23,  24,
    25,  26,  27,  28,  29,  30,  31,  32,  33,  34,  35,  255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
};

inline fn intscanVal(c: c_int) u8 {
    return intscan_table[@intCast(c + 1)];
}

fn intscanDone(f: *FILE, y: c_ulonglong, neg: c_int, lim: c_ulonglong) c_ulonglong {
    shunget_macro(f);
    if (y >= lim) {
        if ((lim & 1) == 0 and neg == 0) {
            setErrno(.RANGE);
            return lim -% 1;
        } else if (y > lim) {
            setErrno(.RANGE);
            return lim;
        }
    }
    const neg_mask: c_ulonglong = @bitCast(@as(c_longlong, neg));
    return (y ^ neg_mask) -% neg_mask;
}

/// intscan.c: unsigned long long __intscan(FILE *f, unsigned base, int pok, unsigned long long lim)
fn intscan_impl(f: *FILE, base_arg: c_uint, pok: c_int, lim: c_ulonglong) callconv(.c) c_ulonglong {
    var base = base_arg;
    var c: c_int = shgetc_macro(f);
    var neg: c_int = 0;
    var x: usize = 0;
    var y: c_ulonglong = undefined;
    if (base > 36 or base == 1) {
        setErrno(.INVAL);
        return 0;
    }
    while (c >= 0 and std.ascii.isWhitespace(@truncate(@as(c_uint, @bitCast(c))))) {
        c = shgetc_macro(f);
    }
    if (c == '+' or c == '-') {
        neg = -@as(c_int, @intFromBool(c == '-'));
        c = shgetc_macro(f);
    }
    if ((base == 0 or base == 16) and c == '0') {
        c = shgetc_macro(f);
        if ((c | 32) == 'x') {
            c = shgetc_macro(f);
            if (intscanVal(c) >= 16) {
                shunget_macro(f);
                if (pok != 0) {
                    shunget_macro(f);
                } else {
                    shlim_impl(f, 0);
                }
                return 0;
            }
            base = 16;
        } else if (base == 0) {
            base = 8;
        }
    } else {
        if (base == 0) base = 10;
        if (intscanVal(c) >= base) {
            shunget_macro(f);
            shlim_impl(f, 0);
            setErrno(.INVAL);
            return 0;
        }
    }
    if (base == 10) {
        while (intscanVal(c) < 10 and x <= std.math.maxInt(usize) / 10 - 1) : (c = shgetc_macro(f)) {
            x = x * 10 + intscanVal(c);
        }
        y = x;
        while (intscanVal(c) < 10 and y <= std.math.maxInt(c_ulonglong) / 10 and 10 * y <= @as(c_ulonglong, std.math.maxInt(c_ulonglong)) - intscanVal(c)) : (c = shgetc_macro(f)) {
            y = y * 10 + intscanVal(c);
        }
        if (intscanVal(c) >= 10) return intscanDone(f, y, neg, lim);
    } else if ((base & (base - 1)) == 0) {
        const bs: std.math.Log2Int(c_ulonglong) = @intCast(("\x00\x01\x02\x04\x07\x03\x06\x05")[(@as(usize, 0x17 *% base) >> 5) & 7]);
        const bs_usize: std.math.Log2Int(usize) = @intCast(bs);
        while (intscanVal(c) < base and x <= (@as(usize, std.math.maxInt(usize)) >> bs_usize)) : (c = shgetc_macro(f)) {
            x = (x << bs_usize) | intscanVal(c);
        }
        y = x;
        while (intscanVal(c) < base and y <= (@as(c_ulonglong, std.math.maxInt(c_ulonglong)) >> bs)) : (c = shgetc_macro(f)) {
            y = (y << bs) | intscanVal(c);
        }
        if (intscanVal(c) >= base) return intscanDone(f, y, neg, lim);
    } else {
        while (intscanVal(c) < base and x <= @as(usize, std.math.maxInt(usize)) / base - 1) : (c = shgetc_macro(f)) {
            x = x * base + intscanVal(c);
        }
        y = x;
        while (intscanVal(c) < base and y <= @as(c_ulonglong, std.math.maxInt(c_ulonglong)) / base and base * y <= @as(c_ulonglong, std.math.maxInt(c_ulonglong)) - intscanVal(c)) : (c = shgetc_macro(f)) {
            y = y * base + intscanVal(c);
        }
        if (intscanVal(c) >= base) return intscanDone(f, y, neg, lim);
    }
    while (intscanVal(c) < base) : (c = shgetc_macro(f)) {}
    setErrno(.RANGE);
    y = lim;
    if ((lim & 1) != 0) neg = 0;
    return intscanDone(f, y, neg, lim);
}

const FS_LDBL_MANT_DIG: c_int = switch (@bitSizeOf(c_longdouble)) {
    64 => 53,
    80 => 64,
    128 => 113,
    else => @compileError("unsupported c_longdouble bit size"),
};
const FS_LDBL_MAX_EXP: c_int = switch (FS_LDBL_MANT_DIG) {
    53 => 1024,
    64, 113 => 16384,
    else => unreachable,
};
const FS_LDBL_MIN_EXP: c_int = 2 - FS_LDBL_MAX_EXP;
const FS_LD_B1B_DIG: usize = switch (FS_LDBL_MANT_DIG) {
    53 => 2,
    64 => 3,
    113 => 4,
    else => unreachable,
};
const FS_LD_B1B_MAX: [FS_LD_B1B_DIG]u32 = switch (FS_LDBL_MANT_DIG) {
    53 => .{ 9007199, 254740991 },
    64 => .{ 18, 446744073, 709551615 },
    113 => .{ 10384593, 717069655, 257060992, 658440191 },
    else => unreachable,
};
const FS_KMAX: usize = switch (FS_LDBL_MANT_DIG) {
    53 => 128,
    64, 113 => 2048,
    else => unreachable,
};
const FS_MASK: usize = FS_KMAX - 1;

fn scanexp(f: *FILE, pok: c_int) c_longlong {
    var c: c_int = shgetc_macro(f);
    var x: u32 = 0;
    var y: c_longlong = 0;
    var neg: c_int = 0;

    if (c == '+' or c == '-') {
        neg = @intFromBool(c == '-');
        c = shgetc_macro(f);
        if (@as(c_uint, @bitCast(c)) -% '0' >= 10 and pok != 0) shunget_macro(f);
    }
    if (@as(c_uint, @bitCast(c)) -% '0' >= 10) {
        shunget_macro(f);
        return std.math.minInt(c_longlong);
    }
    while (@as(c_uint, @bitCast(c)) -% '0' < 10 and x < std.math.maxInt(u32) / 10) : (c = shgetc_macro(f)) {
        x = 10 * x + (@as(u32, @bitCast(c)) - '0');
    }
    y = x;
    while (@as(c_uint, @bitCast(c)) -% '0' < 10 and y < @divTrunc(std.math.maxInt(c_longlong), 100)) : (c = shgetc_macro(f)) {
        y = 10 * y + (@as(c_longlong, c) - '0');
    }
    while (@as(c_uint, @bitCast(c)) -% '0' < 10) : (c = shgetc_macro(f)) {}
    shunget_macro(f);
    return if (neg != 0) -y else y;
}

fn decfloat(f: *FILE, c_arg: c_int, bits_arg: c_int, emin: c_int, sign: c_int, pok: c_int) c_longdouble {
    var x: [FS_KMAX]u32 = undefined;
    const th = FS_LD_B1B_MAX;
    var c: c_int = c_arg;
    var bits: c_int = bits_arg;
    var j: usize = 0;
    var k: usize = 0;
    var a: usize = 0;
    var z: usize = 0;
    var lrp: c_longlong = 0;
    var dc: c_longlong = 0;
    var e10: c_longlong = 0;
    var lnz: c_longlong = 0;
    var gotdig: bool = false;
    var gotrad: bool = false;
    var rp: c_int = 0;
    var e2: c_int = 0;
    const emax: c_int = -emin - bits + 3;
    var denormal: bool = false;
    var y: c_longdouble = 0;
    var frac: c_longdouble = 0;
    var bias: c_longdouble = 0;
    const sign_ld: c_longdouble = @floatFromInt(sign);
    const p10s = [8]u32{ 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000 };

    while (c == '0') : (c = shgetc_macro(f)) {
        gotdig = true;
    }
    if (c == '.') {
        gotrad = true;
        c = shgetc_macro(f);
        while (c == '0') : (c = shgetc_macro(f)) {
            gotdig = true;
            lrp -= 1;
        }
    }

    x[0] = 0;
    while (@as(c_uint, @bitCast(c)) -% '0' < 10 or c == '.') : (c = shgetc_macro(f)) {
        if (c == '.') {
            if (gotrad) break;
            gotrad = true;
            lrp = dc;
        } else if (k < FS_KMAX - 3) {
            dc += 1;
            if (c != '0') lnz = dc;
            const d: u32 = @intCast(c - '0');
            if (j != 0) {
                x[k] = x[k] * 10 + d;
            } else {
                x[k] = d;
            }
            j += 1;
            if (j == 9) {
                k += 1;
                j = 0;
            }
            gotdig = true;
        } else {
            dc += 1;
            if (c != '0') {
                lnz = @intCast((FS_KMAX - 4) * 9);
                x[FS_KMAX - 4] |= 1;
            }
        }
    }
    if (!gotrad) lrp = dc;

    if (gotdig and (c | 32) == 'e') {
        e10 = scanexp(f, pok);
        if (e10 == std.math.minInt(c_longlong)) {
            if (pok != 0) {
                shunget_macro(f);
            } else {
                shlim_impl(f, 0);
                return 0;
            }
            e10 = 0;
        }
        lrp += e10;
    } else if (c >= 0) {
        shunget_macro(f);
    }
    if (!gotdig) {
        setErrno(.INVAL);
        shlim_impl(f, 0);
        return 0;
    }

    if (x[0] == 0) return sign_ld * 0.0;

    if (lrp == dc and dc < 10 and (bits > 30 or (x[0] >> @intCast(bits)) == 0)) {
        return sign_ld * @as(c_longdouble, @floatFromInt(x[0]));
    }
    if (lrp > @divTrunc(-emin, 2)) {
        setErrno(.RANGE);
        return sign_ld * std.math.floatMax(c_longdouble) * std.math.floatMax(c_longdouble);
    }
    if (lrp < emin - 2 * FS_LDBL_MANT_DIG) {
        setErrno(.RANGE);
        return sign_ld * std.math.floatMin(c_longdouble) * std.math.floatMin(c_longdouble);
    }

    if (j != 0) {
        while (j < 9) : (j += 1) {
            x[k] *= 10;
        }
        k += 1;
        j = 0;
    }

    a = 0;
    z = k;
    e2 = 0;
    rp = @intCast(lrp);

    if (lnz < 9 and lnz <= rp and rp < 18) {
        if (rp == 9) return sign_ld * @as(c_longdouble, @floatFromInt(x[0]));
        if (rp < 9) return sign_ld * @as(c_longdouble, @floatFromInt(x[0])) / @as(c_longdouble, @floatFromInt(p10s[@intCast(8 - rp)]));
        const bitlim: c_int = bits - 3 * (rp - 9);
        if (bitlim > 30 or (x[0] >> @intCast(bitlim)) == 0) {
            return sign_ld * @as(c_longdouble, @floatFromInt(x[0])) * @as(c_longdouble, @floatFromInt(p10s[@intCast(rp - 10)]));
        }
    }

    while (x[z - 1] == 0) : (z -= 1) {}

    if (@rem(rp, 9) != 0) {
        const rpm9: c_int = if (rp >= 0) @rem(rp, 9) else @rem(rp, 9) + 9;
        const p10: u32 = p10s[@intCast(8 - rpm9)];
        var carry: u32 = 0;
        k = a;
        while (k != z) : (k += 1) {
            const tmp: u32 = x[k] % p10;
            x[k] = x[k] / p10 + carry;
            carry = (1000000000 / p10) * tmp;
            if (k == a and x[k] == 0) {
                a = (a + 1) & FS_MASK;
                rp -= 9;
            }
        }
        if (carry != 0) {
            x[z] = carry;
            z += 1;
        }
        rp += 9 - rpm9;
    }

    const target_rp: c_int = @intCast(9 * FS_LD_B1B_DIG);
    while (rp < target_rp or (rp == target_rp and x[a] < th[0])) {
        var carry: u32 = 0;
        e2 -= 29;
        k = (z -% 1) & FS_MASK;
        while (true) : (k = (k -% 1) & FS_MASK) {
            const tmp: u64 = (@as(u64, x[k]) << 29) + carry;
            if (tmp > 1000000000) {
                carry = @intCast(tmp / 1000000000);
                x[k] = @intCast(tmp % 1000000000);
            } else {
                carry = 0;
                x[k] = @intCast(tmp);
            }
            if (k == ((z -% 1) & FS_MASK) and k != a and x[k] == 0) z = k;
            if (k == a) break;
        }
        if (carry != 0) {
            rp += 9;
            a = (a -% 1) & FS_MASK;
            if (a == z) {
                z = (z -% 1) & FS_MASK;
                x[(z -% 1) & FS_MASK] |= x[z];
            }
            x[a] = carry;
        }
    }

    var i: usize = 0;
    while (true) {
        var carry: u32 = 0;
        var sh: u5 = 1;
        i = 0;
        while (i < FS_LD_B1B_DIG) : (i += 1) {
            k = (a + i) & FS_MASK;
            if (k == z or x[k] < th[i]) {
                i = FS_LD_B1B_DIG;
                break;
            }
            if (x[(a + i) & FS_MASK] > th[i]) break;
        }
        if (i == FS_LD_B1B_DIG and rp == target_rp) break;
        if (rp > 9 + target_rp) sh = 9;
        e2 += sh;
        k = a;
        while (k != z) : (k = (k + 1) & FS_MASK) {
            const mask_sh: u32 = (@as(u32, 1) << sh) - 1;
            const tmp: u32 = x[k] & mask_sh;
            x[k] = (x[k] >> sh) + carry;
            carry = (@as(u32, 1000000000) >> sh) * tmp;
            if (k == a and x[k] == 0) {
                a = (a + 1) & FS_MASK;
                i -%= 1;
                rp -= 9;
            }
        }
        if (carry != 0) {
            if (((z + 1) & FS_MASK) != a) {
                x[z] = carry;
                z = (z + 1) & FS_MASK;
            } else {
                x[(z -% 1) & FS_MASK] |= 1;
            }
        }
    }

    y = 0;
    i = 0;
    while (i < FS_LD_B1B_DIG) : (i += 1) {
        if (((a + i) & FS_MASK) == z) {
            const old_z = z;
            z = (z + 1) & FS_MASK;
            x[old_z] = 0;
        }
        y = 1000000000.0 * y + @as(c_longdouble, @floatFromInt(x[(a + i) & FS_MASK]));
    }

    y *= sign_ld;

    if (bits > FS_LDBL_MANT_DIG + e2 - emin) {
        bits = FS_LDBL_MANT_DIG + e2 - emin;
        if (bits < 0) bits = 0;
        denormal = true;
    }

    if (bits < FS_LDBL_MANT_DIG) {
        bias = std.math.copysign(std.math.scalbn(@as(c_longdouble, 1.0), 2 * FS_LDBL_MANT_DIG - bits - 1), y);
        frac = @rem(y, std.math.scalbn(@as(c_longdouble, 1.0), FS_LDBL_MANT_DIG - bits));
        y -= frac;
        y += bias;
    }

    if (((a + i) & FS_MASK) != z) {
        const t: u32 = x[(a + i) & FS_MASK];
        if (t < 500000000 and (t != 0 or ((a + i + 1) & FS_MASK) != z)) {
            frac += 0.25 * sign_ld;
        } else if (t > 500000000) {
            frac += 0.75 * sign_ld;
        } else if (t == 500000000) {
            if (((a + i + 1) & FS_MASK) == z) {
                frac += 0.5 * sign_ld;
            } else {
                frac += 0.75 * sign_ld;
            }
        }
        if (FS_LDBL_MANT_DIG - bits >= 2 and @rem(frac, 1.0) == 0.0) {
            frac += 1.0;
        }
    }

    y += frac;
    y -= bias;

    if (((e2 + FS_LDBL_MANT_DIG) & std.math.maxInt(c_int)) > emax - 5) {
        if (@abs(y) >= 2.0 / std.math.floatEps(c_longdouble)) {
            if (denormal and bits == FS_LDBL_MANT_DIG + e2 - emin) {
                denormal = false;
            }
            y *= 0.5;
            e2 += 1;
        }
        if (e2 + FS_LDBL_MANT_DIG > emax or (denormal and frac != 0.0)) {
            setErrno(.RANGE);
        }
    }

    return std.math.scalbn(y, e2);
}

fn hexfloat(f: *FILE, bits_arg: c_int, emin: c_int, sign: c_int, pok: c_int) c_longdouble {
    var x: u32 = 0;
    var y: c_longdouble = 0;
    var scale: c_longdouble = 1;
    var bias: c_longdouble = 0;
    var gottail: bool = false;
    var gotrad: bool = false;
    var gotdig: bool = false;
    var rp: c_longlong = 0;
    var dc: c_longlong = 0;
    var e2: c_longlong = 0;
    var bits: c_int = bits_arg;
    const sign_ld: c_longdouble = @floatFromInt(sign);

    var c: c_int = shgetc_macro(f);

    while (c == '0') : (c = shgetc_macro(f)) {
        gotdig = true;
    }

    if (c == '.') {
        gotrad = true;
        c = shgetc_macro(f);
        rp = 0;
        while (c == '0') : ({
            c = shgetc_macro(f);
            rp -= 1;
        }) {
            gotdig = true;
        }
    }

    while (@as(c_uint, @bitCast(c)) -% '0' < 10 or (@as(c_uint, @bitCast(c | 32)) -% 'a') < 6 or c == '.') : (c = shgetc_macro(f)) {
        if (c == '.') {
            if (gotrad) break;
            rp = dc;
            gotrad = true;
        } else {
            gotdig = true;
            const d: u32 = if (c > '9') @intCast((c | 32) + 10 - 'a') else @intCast(c - '0');
            if (dc < 8) {
                x = x * 16 + d;
            } else if (dc < @divTrunc(FS_LDBL_MANT_DIG + 3, 4) + 1) {
                scale /= 16.0;
                y += @as(c_longdouble, @floatFromInt(d)) * scale;
            } else if (d != 0 and !gottail) {
                y += 0.5 * scale;
                gottail = true;
            }
            dc += 1;
        }
    }
    if (!gotdig) {
        shunget_macro(f);
        if (pok != 0) {
            shunget_macro(f);
            if (gotrad) shunget_macro(f);
        } else {
            shlim_impl(f, 0);
        }
        return sign_ld * 0.0;
    }
    if (!gotrad) rp = dc;
    while (dc < 8) : (dc += 1) {
        x *= 16;
    }
    if ((c | 32) == 'p') {
        e2 = scanexp(f, pok);
        if (e2 == std.math.minInt(c_longlong)) {
            if (pok != 0) {
                shunget_macro(f);
            } else {
                shlim_impl(f, 0);
                return 0;
            }
            e2 = 0;
        }
    } else {
        shunget_macro(f);
    }
    e2 += 4 * rp - 32;

    if (x == 0) return sign_ld * 0.0;
    if (e2 > -emin) {
        setErrno(.RANGE);
        return sign_ld * std.math.floatMax(c_longdouble) * std.math.floatMax(c_longdouble);
    }
    if (e2 < emin - 2 * FS_LDBL_MANT_DIG) {
        setErrno(.RANGE);
        return sign_ld * std.math.floatMin(c_longdouble) * std.math.floatMin(c_longdouble);
    }

    while (x < 0x80000000) {
        if (y >= 0.5) {
            x = x + x + 1;
            y = y + y - 1.0;
        } else {
            x = x + x;
            y = y + y;
        }
        e2 -= 1;
    }

    const e2_i32: c_int = @intCast(e2);
    if (bits > 32 + e2_i32 - emin) {
        bits = 32 + e2_i32 - emin;
        if (bits < 0) bits = 0;
    }

    if (bits < FS_LDBL_MANT_DIG) {
        bias = std.math.copysign(std.math.scalbn(@as(c_longdouble, 1.0), 32 + FS_LDBL_MANT_DIG - bits - 1), sign_ld);
    }

    if (bits < 32 and y != 0.0 and (x & 1) == 0) {
        x += 1;
        y = 0.0;
    }

    y = bias + sign_ld * @as(c_longdouble, @floatFromInt(x)) + sign_ld * y;
    y -= bias;

    if (y == 0.0) setErrno(.RANGE);

    return std.math.scalbn(y, e2_i32);
}

/// floatscan.c: long double __floatscan(FILE *f, int prec, int pok)
fn floatscan_impl(f: *FILE, prec: c_int, pok: c_int) callconv(.c) c_longdouble {
    var sign: c_int = 1;
    var i: usize = 0;
    var bits: c_int = undefined;
    var emin: c_int = undefined;
    var c: c_int = undefined;

    switch (prec) {
        0 => {
            bits = 24; // FLT_MANT_DIG
            emin = -125 - bits; // FLT_MIN_EXP - bits
        },
        1 => {
            bits = 53; // DBL_MANT_DIG
            emin = -1021 - bits; // DBL_MIN_EXP - bits
        },
        2 => {
            bits = FS_LDBL_MANT_DIG;
            emin = FS_LDBL_MIN_EXP - bits;
        },
        else => return 0,
    }

    c = shgetc_macro(f);
    while (c >= 0 and std.ascii.isWhitespace(@truncate(@as(c_uint, @bitCast(c))))) {
        c = shgetc_macro(f);
    }

    if (c == '+' or c == '-') {
        sign -= 2 * @as(c_int, @intFromBool(c == '-'));
        c = shgetc_macro(f);
    }

    const inf_str = "infinity";
    i = 0;
    while (i < 8 and (c | 32) == inf_str[i]) : (i += 1) {
        if (i < 7) c = shgetc_macro(f);
    }
    if (i == 3 or i == 8 or (i > 3 and pok != 0)) {
        if (i != 8) {
            shunget_macro(f);
            if (pok != 0) {
                while (i > 3) : (i -= 1) shunget_macro(f);
            }
        }
        return @as(c_longdouble, @floatFromInt(sign)) * std.math.inf(c_longdouble);
    }
    if (i == 0) {
        const nan_str = "nan";
        while (i < 3 and (c | 32) == nan_str[i]) : (i += 1) {
            if (i < 2) c = shgetc_macro(f);
        }
    }
    if (i == 3) {
        if (shgetc_macro(f) != '(') {
            shunget_macro(f);
            return std.math.nan(c_longdouble);
        }
        i = 1;
        while (true) : (i += 1) {
            c = shgetc_macro(f);
            const cu: c_uint = @bitCast(c);
            if (cu -% '0' < 10 or cu -% 'A' < 26 or cu -% 'a' < 26 or c == '_')
                continue;
            if (c == ')') return std.math.nan(c_longdouble);
            shunget_macro(f);
            if (pok == 0) {
                setErrno(.INVAL);
                shlim_impl(f, 0);
                return 0;
            }
            while (i > 0) : (i -= 1) shunget_macro(f);
            return std.math.nan(c_longdouble);
        }
    }

    if (i != 0) {
        shunget_macro(f);
        setErrno(.INVAL);
        shlim_impl(f, 0);
        return 0;
    }

    if (c == '0') {
        c = shgetc_macro(f);
        if ((c | 32) == 'x') {
            return hexfloat(f, bits, emin, sign, pok);
        }
        shunget_macro(f);
        c = '0';
    }

    return decfloat(f, c, bits, emin, sign, pok);
}

// ===========================================================================
// Open file list, standard streams, stream lifecycle, wide I/O, variadic I/O
// ===========================================================================

var ofl_head: ?*FILE = null;

fn ofl_lock_impl() callconv(.c) *?*FILE {
    return &ofl_head;
}

fn ofl_unlock_impl() callconv(.c) void {}

fn ofl_add_impl(f: *FILE) callconv(.c) ?*FILE {
    const head = ofl_lock_impl();
    f.next = head.*;
    if (head.*) |h| h.prev = f;
    head.* = f;
    ofl_unlock_impl();
    return f;
}

var stdin_buf: [BUFSIZ + UNGET]u8 = undefined;
var __stdin_FILE: FILE = .{
    .flags = F_PERM | F_NOWR,
    .rpos = null,
    .rend = null,
    .close_fn = &stdio_close_impl,
    .wend = null,
    .wpos = null,
    .mustbezero_1 = null,
    .wbase = null,
    .read_fn = &stdio_read_impl,
    .write_fn = null,
    .seek_fn = &stdio_seek_impl,
    .buf = stdin_buf[UNGET..].ptr,
    .buf_size = BUFSIZ,
    .prev = null,
    .next = null,
    .fd = 0,
    .pipe_pid = 0,
    .lockcount = 0,
    .mode = 0,
    .lock = -1,
    .lbf = EOF,
    .cookie = null,
    .off = 0,
    .getln_buf = null,
    .mustbezero_2 = null,
    .shend = null,
    .shlim = 0,
    .shcnt = 0,
    .prev_locked = null,
    .next_locked = null,
    .locale = null,
};
var stdin_var: ?*FILE = &__stdin_FILE;

var stdout_buf: [BUFSIZ + UNGET]u8 = undefined;
var __stdout_FILE: FILE = .{
    .flags = F_PERM | F_NORD,
    .rpos = null,
    .rend = null,
    .close_fn = &stdio_close_impl,
    .wend = null,
    .wpos = null,
    .mustbezero_1 = null,
    .wbase = null,
    .read_fn = null,
    .write_fn = &stdout_write_impl,
    .seek_fn = &stdio_seek_impl,
    .buf = stdout_buf[UNGET..].ptr,
    .buf_size = BUFSIZ,
    .prev = null,
    .next = null,
    .fd = 1,
    .pipe_pid = 0,
    .lockcount = 0,
    .mode = 0,
    .lock = -1,
    .lbf = '\n',
    .cookie = null,
    .off = 0,
    .getln_buf = null,
    .mustbezero_2 = null,
    .shend = null,
    .shlim = 0,
    .shcnt = 0,
    .prev_locked = null,
    .next_locked = null,
    .locale = null,
};
var stdout_var: ?*FILE = &__stdout_FILE;

var stderr_buf: [UNGET]u8 = undefined;
var __stderr_FILE: FILE = .{
    .flags = F_PERM | F_NORD,
    .rpos = null,
    .rend = null,
    .close_fn = &stdio_close_impl,
    .wend = null,
    .wpos = null,
    .mustbezero_1 = null,
    .wbase = null,
    .read_fn = null,
    .write_fn = &stdio_write_impl,
    .seek_fn = &stdio_seek_impl,
    .buf = stderr_buf[UNGET..].ptr,
    .buf_size = 0,
    .prev = null,
    .next = null,
    .fd = 2,
    .pipe_pid = 0,
    .lockcount = 0,
    .mode = 0,
    .lock = -1,
    .lbf = -1,
    .cookie = null,
    .off = 0,
    .getln_buf = null,
    .mustbezero_2 = null,
    .shend = null,
    .shlim = 0,
    .shcnt = 0,
    .prev_locked = null,
    .next_locked = null,
    .locale = null,
};
var stderr_var: ?*FILE = &__stderr_FILE;

fn close_file(f_opt: ?*FILE) void {
    const f = f_opt orelse return;
    _ = flock(f);
    if (f.wpos != f.wbase) _ = f.write_fn.?(f, @ptrCast(&[0]u8{}), 0);
    if (f.rpos != f.rend) _ = f.seek_fn.?(f, @as(i64, @as(isize, @bitCast(@intFromPtr(f.rpos) -% @intFromPtr(f.rend)))), SEEK_CUR);
}

/// __stdio_exit.c: void __stdio_exit(void)
fn stdio_exit_impl() callconv(.c) void {
    var f = ofl_lock_impl().*;
    while (f) |cur| : (f = cur.next) {
        close_file(cur);
    }
    close_file(stdin_ext.*);
    close_file(stdout_ext.*);
    close_file(stderr_ext.*);
}

/// fflush.c: int fflush(FILE *f)
fn fflush_impl(f_opt: ?*FILE) callconv(.c) c_int {
    if (f_opt == null) {
        var r: c_int = 0;
        if (stdout_ext.*) |out| r |= fflush_impl(out);
        if (stderr_ext.*) |err| r |= fflush_impl(err);
        var f = ofl_lock_impl().*;
        while (f) |cur| : (f = cur.next) {
            const need_unlock = flock(cur);
            if (cur.wpos != cur.wbase) r |= fflush_impl(cur);
            funlock(cur, need_unlock);
        }
        ofl_unlock_impl();
        return r;
    }
    const f = f_opt.?;
    const need_unlock = flock(f);
    if (f.wpos != f.wbase) {
        _ = f.write_fn.?(f, @ptrCast(&[0]u8{}), 0);
        if (f.wpos == null) {
            funlock(f, need_unlock);
            return EOF;
        }
    }
    if (f.rpos != f.rend) {
        _ = f.seek_fn.?(f, @as(i64, @as(isize, @bitCast(@intFromPtr(f.rpos) -% @intFromPtr(f.rend)))), SEEK_CUR);
    }
    f.wpos = null;
    f.wbase = null;
    f.wend = null;
    f.rpos = null;
    f.rend = null;
    funlock(f, need_unlock);
    return 0;
}

fn fclose_dummy(_: *FILE) callconv(.c) void {}

/// fclose.c: int fclose(FILE *f)
fn fclose_impl(f: *FILE) callconv(.c) c_int {
    _ = flock(f);
    var r = fflush_fn(f);
    r |= f.close_fn.?(f);
    const head = ofl_lock_impl();
    if (f.prev) |prev| prev.next = f.next;
    if (f.next) |next| next.prev = f.prev;
    if (head.* == f) head.* = f.next;
    ofl_unlock_impl();
    free_fn(f.getln_buf);
    free_fn(f);
    return r;
}

/// __fdopen.c: FILE *__fdopen(int fd, const char *mode)
fn fdopen_impl(fd: c_int, mode: [*:0]const u8) callconv(.c) ?*FILE {
    if (mode[0] != 'r' and mode[0] != 'w' and mode[0] != 'a') {
        setErrno(.INVAL);
        return null;
    }
    const raw = malloc_fn(@sizeOf(FILE) + UNGET + BUFSIZ) orelse return null;
    const f: *FILE = @ptrCast(@alignCast(raw));
    f.* = std.mem.zeroes(FILE);

    const mode_span = std.mem.span(mode);
    if (std.mem.indexOfScalar(u8, mode_span, '+') == null) {
        f.flags = if (mode[0] == 'r') F_NOWR else F_NORD;
    }
    if (std.mem.indexOfScalar(u8, mode_span, 'e') != null) {
        _ = fcntl_fn(fd, std.c.F.SETFD, @as(c_int, 1));
    }
    if (mode[0] == 'a') {
        const flags = fcntl_fn(fd, std.c.F.GETFL);
        const o_append: c_int = @bitCast(@as(u32, @bitCast(std.c.O{ .APPEND = true })));
        if ((flags & o_append) == 0) {
            _ = fcntl_fn(fd, std.c.F.SETFL, flags | o_append);
        }
        f.flags |= F_APP;
    }
    f.fd = fd;
    f.buf = @as([*]u8, @ptrCast(raw)) + @sizeOf(FILE) + UNGET;
    f.buf_size = BUFSIZ;
    f.lbf = EOF;
    if ((f.flags & F_NOWR) == 0 and isatty_fn(fd) != 0) {
        f.lbf = '\n';
    }
    f.read_fn = &stdio_read_impl;
    f.write_fn = &stdio_write_impl;
    f.seek_fn = &stdio_seek_impl;
    f.close_fn = &stdio_close_impl;
    f.lock = -1;
    return ofl_add_fn(f);
}

/// fopen.c: FILE *fopen(const char *restrict filename, const char *restrict mode)
fn fopen_impl(filename: [*:0]const u8, mode: [*:0]const u8) callconv(.c) ?*FILE {
    if (mode[0] != 'r' and mode[0] != 'w' and mode[0] != 'a') {
        setErrno(.INVAL);
        return null;
    }
    const flags = fmodeflags_impl(mode);
    const fd = wasilibc_open_nomode_fn(filename, flags);
    if (fd < 0) return null;
    if (fdopen_impl(fd, mode)) |f| return f;
    _ = posix_close_fn(fd);
    return null;
}

/// freopen.c: FILE *freopen(const char *restrict filename, const char *restrict mode, FILE *restrict f)
fn freopen_impl(filename_opt: ?[*:0]const u8, mode: [*:0]const u8, f: *FILE) callconv(.c) ?*FILE {
    var fl = fmodeflags_impl(mode);
    const need_unlock = flock(f);
    _ = fflush_fn(f);
    if (filename_opt == null) {
        fl &= ~@as(c_int, @bitCast(@as(u32, @bitCast(std.c.O{ .CREAT = true, .TRUNC = true, .EXCL = true }))));
        if (fcntl_fn(f.fd, std.c.F.SETFL, fl) < 0) {
            funlock(f, need_unlock);
            _ = fclose_impl(f);
            return null;
        }
    } else {
        const filename = filename_opt.?;
        const f2 = fopen_impl(filename, mode) orelse {
            funlock(f, need_unlock);
            _ = fclose_impl(f);
            return null;
        };
        if (f2.fd == f.fd) {
            f2.fd = -1;
        } else if (wasilibc_fd_renumber_fn(f2.fd, f.fd) < 0) {
            _ = fclose_impl(f2);
            funlock(f, need_unlock);
            _ = fclose_impl(f);
            return null;
        }
        f.flags = (f.flags & F_PERM) | f2.flags;
        f.read_fn = f2.read_fn;
        f.write_fn = f2.write_fn;
        f.seek_fn = f2.seek_fn;
        f.close_fn = f2.close_fn;
        f2.fd = -1;
        _ = fclose_impl(f2);
    }
    f.mode = 0;
    f.locale = null;
    funlock(f, need_unlock);
    return f;
}

/// fwide.c: int fwide(FILE *f, int mode)
fn fwide_impl(f: *FILE, mode: c_int) callconv(.c) c_int {
    const need_unlock = flock(f);
    if (mode != 0) {
        if (f.mode == 0) f.mode = if (mode > 0) 1 else -1;
    }
    const ret = f.mode;
    funlock(f, need_unlock);
    return ret;
}

const WEOF: wint_t = @bitCast(@as(c_int, -1));

fn fgetwc_unlocked_internal(f: *FILE) wint_t {
    var wc: wchar_t = undefined;
    var st: mbstate_t = std.mem.zeroes(mbstate_t);
    var c: u8 = undefined;
    var l: usize = @bitCast(@as(isize, -2));
    var first: bool = true;
    while (l == @as(usize, @bitCast(@as(isize, -2)))) {
        if (f.rpos != f.rend) {
            const rpos = f.rpos.?;
            const avail = @intFromPtr(f.rend.?) - @intFromPtr(rpos);
            l = mbrtowc_fn(&wc, rpos, avail, &st);
            if (l +% 2 >= 2) {
                f.rpos = rpos + (l + @intFromBool(l == 0));
                return @bitCast(wc);
            }
            if (l == @as(usize, @bitCast(@as(isize, -1)))) {
                f.rpos = rpos + 1;
                return WEOF;
            }
            f.rpos = f.rend;
        } else {
            const b = getc_unlocked_impl(f);
            if (b < 0) {
                if (!first) {
                    f.flags |= F_ERR;
                    setErrno(.ILSEQ);
                }
                return WEOF;
            }
            c = @truncate(@as(c_uint, @bitCast(b)));
            l = mbrtowc_fn(&wc, @ptrCast(&c), 1, &st);
            if (l == @as(usize, @bitCast(@as(isize, -1)))) {
                return WEOF;
            }
        }
        first = false;
    }
    return @bitCast(wc);
}

/// fgetwc.c: wint_t __fgetwc_unlocked(FILE *f)
fn fgetwc_unlocked_impl(f: *FILE) callconv(.c) wint_t {
    if (f.mode <= 0) _ = fwide_fn(f, 1);
    if (f.rpos != f.rend) {
        const rpos = f.rpos.?;
        const b = rpos[0];
        if (b < 128) {
            f.rpos = rpos + 1;
            return b;
        }
    }
    return fgetwc_unlocked_internal(f);
}

/// fgetwc.c: wint_t fgetwc(FILE *f)
fn fgetwc_impl(f: *FILE) callconv(.c) wint_t {
    const need_unlock = flock(f);
    const c = fgetwc_unlocked_impl(f);
    funlock(f, need_unlock);
    return c;
}

/// fgetws.c: wchar_t *fgetws(wchar_t *restrict s, int n, FILE *restrict f)
fn fgetws_impl(s_arg: [*]wchar_t, n_arg: c_int, f: *FILE) callconv(.c) ?[*]wchar_t {
    var p = s_arg;
    var n = n_arg;
    if (n == 0) return s_arg;
    const need_unlock = flock(f);
    const prev_errno = std.c._errno().*;
    std.c._errno().* = 0;
    while (true) {
        n -= 1;
        if (n == 0) break;
        const c = fgetwc_unlocked_impl(f);
        if (c == WEOF) break;
        p[0] = @bitCast(c);
        p += 1;
        if (c == '\n') break;
    }
    p[0] = 0;
    if ((f.flags & F_ERR) != 0 or std.c._errno().* == @backingInt(std.c.E.ILSEQ)) {
        p = s_arg;
    } else {
        std.c._errno().* = prev_errno;
    }
    funlock(f, need_unlock);
    return if (p == s_arg) null else s_arg;
}

inline fn isascii_wchar(c: wchar_t) bool {
    return (@as(u32, @bitCast(c)) & ~@as(u32, 0x7f)) == 0;
}

/// fputwc.c: wint_t __fputwc_unlocked(wchar_t c, FILE *f)
fn fputwc_unlocked_impl(c: wchar_t, f: *FILE) callconv(.c) wint_t {
    var mbc: [MB_LEN_MAX]u8 = undefined;
    var l: c_int = undefined;
    if (f.mode <= 0) _ = fwide_fn(f, 1);
    if (isascii_wchar(c)) {
        return @bitCast(putc_unlocked_impl(@bitCast(c), f));
    } else if (f.wpos != null and f.wend != null and @intFromPtr(f.wpos.?) + MB_LEN_MAX < @intFromPtr(f.wend.?)) {
        l = wctomb_fn(f.wpos, c);
        if (l < 0) return WEOF;
        f.wpos = f.wpos.? + @as(usize, @intCast(l));
    } else {
        l = wctomb_fn(&mbc, c);
        if (l < 0 or __fwritex(&mbc, @intCast(l), f) < @as(usize, @intCast(l))) return WEOF;
    }
    if (c == '\n' and f.lbf >= 0) _ = f.write_fn.?(f, @ptrCast(&[0]u8{}), 0);
    return @bitCast(c);
}

/// fputwc.c: wint_t fputwc(wchar_t c, FILE *f)
fn fputwc_impl(c: wchar_t, f: *FILE) callconv(.c) wint_t {
    const need_unlock = flock(f);
    const r = fputwc_unlocked_impl(c, f);
    funlock(f, need_unlock);
    return r;
}

/// fputws.c: int fputws(const wchar_t *restrict ws, FILE *restrict f)
fn fputws_impl(ws_arg: [*:0]const wchar_t, f: *FILE) callconv(.c) c_int {
    var ws: ?[*:0]const wchar_t = ws_arg;
    var buf: [BUFSIZ]u8 = undefined;
    var l: usize = 0;
    const need_unlock = flock(f);
    _ = fwide_fn(f, 1);
    while (ws != null) {
        l = wcsrtombs_fn(&buf, &ws, buf.len, null);
        if (l +% 1 == 0) break;
        if (__fwritex(&buf, l, f) < l) {
            funlock(f, need_unlock);
            return -1;
        }
    }
    funlock(f, need_unlock);
    return @intCast(@as(isize, @bitCast(l)));
}

/// ungetwc.c: wint_t ungetwc(wint_t c, FILE *f)
fn ungetwc_impl(c: wint_t, f: *FILE) callconv(.c) wint_t {
    var mbc: [MB_LEN_MAX]u8 = undefined;
    var l: c_int = 1;
    const need_unlock = flock(f);
    if (f.mode <= 0) _ = fwide_fn(f, 1);
    if (c == WEOF) {
        funlock(f, need_unlock);
        return WEOF;
    }
    if (!isascii_wchar(@bitCast(c))) {
        l = wctomb_fn(&mbc, @bitCast(c));
        if (l < 0) {
            funlock(f, need_unlock);
            return WEOF;
        }
    } else {
        mbc[0] = @truncate(@as(u32, @bitCast(c)));
    }
    if (f.rpos == null) _ = toread_fn(f);
    if (f.rpos == null or @intFromPtr(f.rpos.?) < @intFromPtr(f.buf.?) -% UNGET + @as(usize, @intCast(l))) {
        funlock(f, need_unlock);
        return WEOF;
    }
    const ul: usize = @intCast(l);
    const new_rpos = f.rpos.? - ul;
    f.rpos = new_rpos;
    @memcpy(new_rpos[0..ul], mbc[0..ul]);
    f.flags &= ~F_EOF;
    funlock(f, need_unlock);
    return c;
}

/// printf.c: int printf(const char *restrict fmt, ...)
fn printf_impl(fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vfprintf_impl(stdout_ext.*.?, fmt, passVaList(&ap));
}

/// sprintf.c: int sprintf(char *restrict s, const char *restrict fmt, ...)
fn sprintf_impl(s: [*]u8, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vsprintf_impl(s, fmt, passVaList(&ap));
}

/// snprintf.c: int snprintf(char *restrict s, size_t n, const char *restrict fmt, ...)
fn snprintf_impl(s: [*]u8, n: usize, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vsnprintf_impl(s, n, fmt, passVaList(&ap));
}

/// asprintf.c: int asprintf(char **s, const char *fmt, ...)
fn asprintf_impl(s: *?[*]u8, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vasprintf_impl(s, fmt, passVaList(&ap));
}

/// dprintf.c: int dprintf(int fd, const char *restrict fmt, ...)
fn dprintf_impl(fd: c_int, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vdprintf_impl(fd, fmt, passVaList(&ap));
}

/// scanf.c: int scanf(const char *restrict fmt, ...)
fn scanf_impl(fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vscanf_impl(fmt, passVaList(&ap));
}

/// sscanf.c: int sscanf(const char *restrict s, const char *restrict fmt, ...)
fn sscanf_impl(s: [*:0]const u8, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vsscanf_impl(s, fmt, passVaList(&ap));
}

/// wprintf.c: int wprintf(const wchar_t *restrict fmt, ...)
fn wprintf_impl(fmt: [*:0]const wchar_t, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vwprintf_impl(fmt, passVaList(&ap));
}

/// fwprintf.c: int fwprintf(FILE *restrict f, const wchar_t *restrict fmt, ...)
fn fwprintf_impl(f: *FILE, fmt: [*:0]const wchar_t, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vfwprintf_impl(f, fmt, passVaList(&ap));
}

/// swprintf.c: int swprintf(wchar_t *restrict s, size_t n, const wchar_t *restrict fmt, ...)
fn swprintf_impl(s: [*]wchar_t, n: usize, fmt: [*:0]const wchar_t, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vswprintf_impl(s, n, fmt, passVaList(&ap));
}

/// wscanf.c: int wscanf(const wchar_t *restrict fmt, ...)
fn wscanf_impl(fmt: [*:0]const wchar_t, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vwscanf_impl(fmt, passVaList(&ap));
}

/// fwscanf.c: int fwscanf(FILE *restrict f, const wchar_t *restrict fmt, ...)
fn fwscanf_impl(f: *FILE, fmt: [*:0]const wchar_t, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vfwscanf_impl(f, fmt, passVaList(&ap));
}

/// swscanf.c: int swscanf(const wchar_t *restrict s, const wchar_t *restrict fmt, ...)
fn swscanf_impl(s: [*:0]const wchar_t, fmt: [*:0]const wchar_t, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vswscanf_impl(s, fmt, passVaList(&ap));
}
