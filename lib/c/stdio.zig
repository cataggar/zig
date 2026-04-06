const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;

/// Musl internal FILE struct layout (struct _IO_FILE from stdio_impl.h).
/// Only used when targeting musl libc.
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

comptime {
    if (builtin.link_libc and builtin.target.isMuslLibC()) {
        // Buffer control wrappers (setbuf.c, setbuffer.c, setlinebuf.c)
        symbol(&setbuf, "setbuf");
        symbol(&setbuffer, "setbuffer");
        symbol(&setlinebuf, "setlinebuf");

        // Line reading (getline.c)
        symbol(&getline, "getline");

        // Wide character I/O wrappers (getwchar.c, putwchar.c, getwc.c, putwc.c)
        symbol(&getwchar, "getwchar");
        symbol(&getwchar, "getwchar_unlocked");
        symbol(&putwchar, "putwchar");
        symbol(&putwchar, "putwchar_unlocked");
        symbol(&getwc, "getwc");
        symbol(&putwc, "putwc");

        // Character I/O (fgetc.c, fputc.c, getc.c, putc.c, getc_unlocked.c, putc_unlocked.c)
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

        // Internal buffer transitions (__toread.c, __towrite.c, __uflow.c, __overflow.c)
        symbol(&toread_impl, "__toread");
        symbol(&towrite_impl, "__towrite");
        symbol(&uflow_impl, "__uflow");
        symbol(&overflow_impl, "__overflow");

        // Character I/O wrappers (getchar.c, putchar.c, getchar_unlocked.c, putchar_unlocked.c)
        symbol(&getchar, "getchar");
        symbol(&putchar, "putchar");
        symbol(&getchar_unlocked, "getchar_unlocked");
        symbol(&putchar_unlocked, "putchar_unlocked");

        // Word I/O (getw.c, putw.c)
        symbol(&getw, "getw");
        symbol(&putw, "putw");

        // Stream status (feof.c, ferror.c, clearerr.c, fileno.c)
        symbol(&feof_fn, "feof");
        symbol(&feof_fn, "feof_unlocked");
        symbol(&feof_fn, "_IO_feof_unlocked");
        symbol(&ferror_fn, "ferror");
        symbol(&ferror_fn, "ferror_unlocked");
        symbol(&ferror_fn, "_IO_ferror_unlocked");
        symbol(&clearerr, "clearerr");
        symbol(&clearerr, "clearerr_unlocked");
        symbol(&fileno, "fileno");
        symbol(&fileno, "fileno_unlocked");

        // Positioning (rewind.c, fgetpos.c, fsetpos.c)
        symbol(&rewind, "rewind");
        symbol(&fgetpos, "fgetpos");
        symbol(&fsetpos, "fsetpos");

        // String I/O (fputs.c, puts.c, gets.c)
        symbol(&fputs, "fputs");
        symbol(&fputs, "fputs_unlocked");
        symbol(&puts, "puts");
        symbol(&gets, "gets");

        // Unget (ungetc.c)
        symbol(&ungetc, "ungetc");

        // Buffering (setvbuf.c)
        symbol(&setvbuf, "setvbuf");

        // Seeking & position (fseek.c, ftell.c)
        symbol(&__fseeko_unlocked, "__fseeko_unlocked");
        symbol(&__fseeko, "__fseeko");
        symbol(&fseek, "fseek");
        symbol(&__fseeko, "fseeko");
        symbol(&__ftello_unlocked, "__ftello_unlocked");
        symbol(&__ftello, "__ftello");
        symbol(&ftell, "ftell");
        symbol(&__ftello, "ftello");

        // Bulk I/O (fread.c, fwrite.c)
        symbol(&__fwritex, "__fwritex");
        symbol(&fwrite, "fwrite");
        symbol(&fwrite, "fwrite_unlocked");
        symbol(&fread, "fread");
        symbol(&fread, "fread_unlocked");

        // String read (fgets.c)
        symbol(&fgets, "fgets");
        symbol(&fgets, "fgets_unlocked");

        // GNU extensions (ext.c, ext2.c)
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

        // File operations (remove.c, rename.c)
        symbol(&remove_fn, "remove");
        symbol(&rename_fn, "rename");

        // Formatting wrappers (fprintf.c, printf.c, snprintf.c, sprintf.c, asprintf.c, dprintf.c)
        symbol(&fprintf_impl, "fprintf");
        symbol(&printf_impl, "printf");
        symbol(&snprintf_impl, "snprintf");
        symbol(&sprintf_impl, "sprintf");
        symbol(&asprintf_impl, "asprintf");
        symbol(&dprintf_impl, "dprintf");

        // Scanning wrappers (scanf.c, fscanf.c, sscanf.c)
        symbol(&scanf_impl, "scanf");
        symbol(&scanf_impl, "__isoc99_scanf");
        symbol(&fscanf_impl, "fscanf");
        symbol(&fscanf_impl, "__isoc99_fscanf");
        symbol(&sscanf_impl, "sscanf");
        symbol(&sscanf_impl, "__isoc99_sscanf");

        // Error output (perror.c)
        symbol(&perror_impl, "perror");

        // Wide formatting wrappers (wprintf.c, fwprintf.c, swprintf.c)
        symbol(&wprintf_impl, "wprintf");
        symbol(&fwprintf_impl, "fwprintf");
        symbol(&swprintf_impl, "swprintf");

        // Wide scanning wrappers (wscanf.c, fwscanf.c, swscanf.c)
        symbol(&wscanf_impl, "wscanf");
        symbol(&wscanf_impl, "__isoc99_wscanf");
        symbol(&fwscanf_impl, "fwscanf");
        symbol(&fwscanf_impl, "__isoc99_fwscanf");
        symbol(&swscanf_impl, "swscanf");
        symbol(&swscanf_impl, "__isoc99_swscanf");

        // Wide v* delegation (vwprintf.c, vwscanf.c)
        symbol(&vwprintf_impl, "vwprintf");
        symbol(&vwscanf_impl, "vwscanf");
        symbol(&vwscanf_impl, "__isoc99_vwscanf");

        // Narrow v* delegation (vprintf.c, vscanf.c)
        symbol(&vprintf_impl, "vprintf");
        symbol(&vscanf_impl, "vscanf");
        symbol(&vscanf_impl, "__isoc99_vscanf");

        // Narrow v*s... (vsnprintf.c, vsprintf.c, vsscanf.c)
        symbol(&vsnprintf_impl, "vsnprintf");
        symbol(&vsprintf_impl, "vsprintf");
        symbol(&vsscanf_impl, "vsscanf");
        symbol(&vsscanf_impl, "__isoc99_vsscanf");

        // Wide v*sw... (vswprintf.c, vswscanf.c)
        symbol(&vswprintf_impl, "vswprintf");
        symbol(&vswscanf_impl, "vswscanf");
        symbol(&vswscanf_impl, "__isoc99_vswscanf");

        // Internal helpers (__fmodeflags.c, __fclose_ca.c)
        symbol(&fmodeflags_impl, "__fmodeflags");
        symbol(&fclose_ca_impl, "__fclose_ca");

        // BSD extension (fgetln.c)
        symbol(&fgetln_impl, "fgetln");

        // Internal I/O (__stdio_seek.c)
        symbol(&stdio_seek_impl, "__stdio_seek");

        // Allocation formatting (vasprintf.c)
        symbol(&vasprintf_impl, "vasprintf");

        // FD formatting (vdprintf.c)
        symbol(&vdprintf_impl, "vdprintf");

        // Line reading (getdelim.c)
        symbol(&getdelim_impl, "getdelim");
        symbol(&getdelim_impl, "__getdelim");

        // Locking (__lockfile.c, flockfile.c, funlockfile.c, ftrylockfile.c)
        symbol(&lockfile_impl, "__lockfile");
        symbol(&unlockfile_impl, "__unlockfile");
        symbol(&flockfile_impl, "flockfile");
        symbol(&funlockfile_impl, "funlockfile");
        symbol(&ftrylockfile_impl, "ftrylockfile");
        symbol(&do_orphaned_stdio_locks_impl, "__do_orphaned_stdio_locks");
        symbol(&unlist_locked_file_impl, "__unlist_locked_file");
        symbol(&register_locked_file_impl, "__register_locked_file");

        // Memory stream functions (fmemopen.c, open_memstream.c, open_wmemstream.c, fopencookie.c)
        symbol(&fmemopen_impl, "fmemopen");
        symbol(&open_memstream_impl, "open_memstream");
        symbol(&open_wmemstream_impl, "open_wmemstream");
        symbol(&fopencookie_impl, "fopencookie");
    }
}

/// C constants
const _IOFBF = 0;
const _IOLBF = 1;
const _IONBF = 2;
const BUFSIZ = 1024;
const EOF = -1;

/// setbuf.c: void setbuf(FILE *restrict f, char *restrict buf)
fn setbuf(f: ?*FILE, buf: ?[*]u8) callconv(.c) void {
    _ = setvbuf(@ptrCast(f), buf, if (buf != null) _IOFBF else _IONBF, BUFSIZ);
}

/// setbuffer.c: void setbuffer(FILE *f, char *buf, size_t size)
fn setbuffer(f: ?*FILE, buf: ?[*]u8, size: usize) callconv(.c) void {
    _ = setvbuf(@ptrCast(f), buf, if (buf != null) _IOFBF else _IONBF, size);
}

/// setlinebuf.c: void setlinebuf(FILE *f)
fn setlinebuf(f: ?*FILE) callconv(.c) void {
    _ = setvbuf(@ptrCast(f), null, _IOLBF, 0);
}

/// getline.c: ssize_t getline(char **s, size_t *n, FILE *f)
fn getline(s: ?*[*]u8, n: ?*usize, f: ?*FILE) callconv(.c) ssize_t {
    return getdelim_impl(s, n, '\n', f);
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
    return if (fread(@ptrCast(&x), @sizeOf(c_int), 1, @ptrCast(f)) != 0) x else EOF;
}

/// putw.c: int putw(int x, FILE *f)
fn putw(x: c_int, f: ?*FILE) callconv(.c) c_int {
    var val = x;
    return @as(c_int, @intCast(fwrite(@ptrCast(&val), @sizeOf(c_int), 1, @ptrCast(f)))) - 1;
}

// --- Internal buffer transitions (__toread.c, __towrite.c, __uflow.c, __overflow.c) ---

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

// --- Character I/O (fgetc.c, fputc.c, getc.c, putc.c, getc_unlocked.c, putc_unlocked.c) ---

/// getc_unlocked.c: int getc_unlocked(FILE *f)
/// Implements musl's getc_unlocked macro:
///   ((f)->rpos != (f)->rend) ? *(f)->rpos++ : __uflow((f))
fn getc_unlocked_impl(f: *FILE) callconv(.c) c_int {
    if (f.rpos != f.rend) {
        const c = f.rpos.?[0];
        f.rpos = f.rpos.? + 1;
        return c;
    }
    return uflow_impl(f);
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
    return overflow_impl(f, uc);
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

/// getchar.c: int getchar(void)
fn getchar() callconv(.c) c_int {
    return fgetc_impl(@ptrCast(stdin_ext.*));
}

/// putchar.c: int putchar(int c)
fn putchar(c: c_int) callconv(.c) c_int {
    return fputc_impl(c, @ptrCast(stdout_ext.*));
}

/// getchar_unlocked.c: int getchar_unlocked(void)
fn getchar_unlocked() callconv(.c) c_int {
    return getc_unlocked_impl(@ptrCast(stdin_ext.*));
}

/// putchar_unlocked.c: int putchar_unlocked(int c)
fn putchar_unlocked(c: c_int) callconv(.c) c_int {
    return putc_unlocked_impl(c, @ptrCast(stdout_ext.*));
}

// --- Stream status functions ---

/// Musl FILE flag constants (from stdio_impl.h)
const F_EOF: c_uint = 16;
const F_ERR: c_uint = 32;

/// Implements musl FLOCK(f) macro: ((f)->lock>=0 ? __lockfile((f)) : 0)
inline fn flock(f: *FILE) c_int {
    return if (f.lock >= 0) lockfile_impl(f) else 0;
}

/// Implements musl FUNLOCK(f) macro
inline fn funlock(f: *FILE, need_unlock: c_int) void {
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
        std.c._errno().* = @intFromEnum(std.os.linux.E.BADF);
        return -1;
    }
    return fd;
}

/// rewind.c: void rewind(FILE *f)
fn rewind(f: *FILE) callconv(.c) void {
    const need_unlock = flock(f);
    _ = __fseeko_unlocked(f, 0, SEEK_SET);
    f.flags &= ~F_ERR;
    funlock(f, need_unlock);
}

/// fgetpos.c: int fgetpos(FILE *f, fpos_t *pos)
fn fgetpos(f: *FILE, pos: *i64) callconv(.c) c_int {
    const off = __ftello(f);
    if (off < 0) return -1;
    pos.* = off;
    return 0;
}

/// fsetpos.c: int fsetpos(FILE *f, const fpos_t *pos)
fn fsetpos(f: *FILE, pos: *const i64) callconv(.c) c_int {
    return __fseeko(f, pos.*, SEEK_SET);
}

// --- String I/O functions ---

/// fputs.c: int fputs(const char *restrict s, FILE *restrict f)
fn fputs(s: [*:0]const u8, f: *FILE) callconv(.c) c_int {
    const l = std.mem.len(s);
    return @as(c_int, @intCast(@intFromBool(fwrite(s, 1, l, f) == l))) - 1;
}

/// puts.c: int puts(const char *s)
fn puts(s: [*:0]const u8) callconv(.c) c_int {
    const stdout_ptr: *FILE = @ptrCast(stdout_ext.*);
    const need_unlock = flock(stdout_ptr);
    const r: c_int = -@as(c_int, @intFromBool(fputs(s, stdout_ptr) < 0 or putc_unlocked_impl('\n', stdout_ptr) < 0));
    funlock(stdout_ptr, need_unlock);
    return r;
}

/// gets.c: char *gets(char *s)
fn gets(s: [*]u8) callconv(.c) ?[*]u8 {
    var i: usize = 0;
    const stdin_ptr: *FILE = @ptrCast(stdin_ext.*);
    const need_unlock = flock(stdin_ptr);
    while (true) {
        const c = getc_unlocked_impl(stdin_ptr);
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

// --- Unget functions ---

/// Musl UNGET constant (from stdio_impl.h)
const UNGET = 8;

/// ungetc.c: int ungetc(int c, FILE *f)
fn ungetc(c: c_int, f: *FILE) callconv(.c) c_int {
    if (c == EOF) return c;

    const need_unlock = flock(f);

    if (f.rpos == null) _ = toread_impl(f);
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

// --- Buffering ---

/// Musl FILE flag constant (from stdio_impl.h)
const F_SVB: c_uint = 64;
const F_APP: c_uint = 128;
const F_NORD: c_uint = 4;
const F_NOWR: c_uint = 8;

const SEEK_SET: c_int = 0;
const SEEK_CUR: c_int = 1;
const SEEK_END: c_int = 2;

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

// --- Seeking & position (fseek.c, ftell.c) ---

/// __fseeko_unlocked from fseek.c
fn __fseeko_unlocked(f: *FILE, off_arg: i64, whence: c_int) callconv(.c) c_int {
    var off = off_arg;

    // Fail immediately for invalid whence argument.
    if (whence != SEEK_CUR and whence != SEEK_SET and whence != SEEK_END) {
        std.c._errno().* = @intFromEnum(std.os.linux.E.INVAL);
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
        std.c._errno().* = @intFromEnum(std.os.linux.E.OVERFLOW);
        return -1;
    }
    return @intCast(pos);
}

// --- Bulk I/O (fread.c, fwrite.c) ---

/// __fwritex from fwrite.c - internal write helper
fn __fwritex(s: [*]const u8, l_arg: usize, f: *FILE) callconv(.c) usize {
    var l = l_arg;

    if (f.wend == null and towrite_impl(f) != 0) return 0;

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
        const k = if (toread_impl(f) != 0) @as(usize, 0) else f.read_fn.?(f, dest, l);
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

// --- String read (fgets.c) ---

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
        const c = getc_unlocked_impl(@ptrCast(f));
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

// --- GNU extensions (ext.c) ---

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

// --- GNU extensions (ext2.c) ---

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

// --- File operations (remove.c, rename.c) ---

const linux = std.os.linux;
const c_errno = @import("../c.zig").errno;

/// remove.c: int remove(const char *path)
fn remove_fn(path: [*:0]const u8) callconv(.c) c_int {
    var r = linux.unlinkat(linux.AT.FDCWD, @ptrCast(path), 0);
    const signed: isize = @bitCast(r);
    if (signed == -@as(isize, @intFromEnum(linux.E.ISDIR))) {
        r = linux.unlinkat(linux.AT.FDCWD, @ptrCast(path), linux.AT.REMOVEDIR);
    }
    return c_errno(r);
}

/// rename.c: int rename(const char *old, const char *new)
fn rename_fn(old: [*:0]const u8, new: [*:0]const u8) callconv(.c) c_int {
    return c_errno(linux.renameat2(linux.AT.FDCWD, @ptrCast(old), linux.AT.FDCWD, @ptrCast(new), .{}));
}

// --- Formatting wrappers (fprintf.c, printf.c, snprintf.c, sprintf.c, asprintf.c, dprintf.c) ---

const VaList = std.builtin.VaList;

/// fprintf.c: int fprintf(FILE *restrict f, const char *restrict fmt, ...)
fn fprintf_impl(f: ?*FILE, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vfprintf_fn(f, fmt, ap);
}

/// printf.c: int printf(const char *restrict fmt, ...)
fn printf_impl(fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vfprintf_fn(stdout_ext.*, fmt, ap);
}

/// snprintf.c: int snprintf(char *restrict s, size_t n, const char *restrict fmt, ...)
fn snprintf_impl(s: [*]u8, n: usize, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vsnprintf_impl(s, n, fmt, ap);
}

/// sprintf.c: int sprintf(char *restrict s, const char *restrict fmt, ...)
fn sprintf_impl(s: [*]u8, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vsprintf_impl(s, fmt, ap);
}

/// asprintf.c: int asprintf(char **s, const char *fmt, ...)
fn asprintf_impl(s: *?[*]u8, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vasprintf_impl(s, fmt, ap);
}

/// dprintf.c: int dprintf(int fd, const char *restrict fmt, ...)
fn dprintf_impl(fd: c_int, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vdprintf_impl(fd, fmt, ap);
}

// --- Scanning wrappers (scanf.c, fscanf.c, sscanf.c) ---

/// scanf.c: int scanf(const char *restrict fmt, ...)
fn scanf_impl(fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vscanf_impl(fmt, ap);
}

/// fscanf.c: int fscanf(FILE *restrict f, const char *restrict fmt, ...)
fn fscanf_impl(f: ?*FILE, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vfscanf_fn(f, fmt, ap);
}

/// sscanf.c: int sscanf(const char *restrict s, const char *restrict fmt, ...)
fn sscanf_impl(s: [*:0]const u8, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vsscanf_impl(s, fmt, ap);
}

// --- Error output (perror.c) ---

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

// --- Internal helpers (__fmodeflags.c, __fclose_ca.c) ---

/// __fmodeflags.c: int __fmodeflags(const char *mode)
/// Parse fopen-style mode string to O_* flags.
fn fmodeflags_impl(mode: [*:0]const u8) callconv(.c) c_int {
    const O = std.os.linux.O;
    var o = O{};
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

// --- BSD extension (fgetln.c) ---

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

// --- Internal I/O (__stdio_seek.c) ---

/// __stdio_seek.c: off_t __stdio_seek(FILE *f, off_t off, int whence)
fn stdio_seek_impl(f: *FILE, off: i64, whence: c_int) callconv(.c) i64 {
    return lseek_fn(f.fd, off, whence);
}

// --- Allocation formatting (vasprintf.c) ---

/// vasprintf.c: int vasprintf(char **s, const char *fmt, va_list ap)
fn vasprintf_impl(s: *?[*]u8, fmt: [*:0]const u8, ap: VaList) callconv(.c) c_int {
    var ap_src = ap;
    var ap_copy = @cVaCopy(&ap_src);
    var dummy: [1]u8 = undefined;
    const l = vsnprintf_impl(&dummy, 0, fmt, ap_copy);
    @cVaEnd(&ap_copy);
    if (l < 0) return -1;
    const size: usize = @intCast(l);
    const ptr: ?*anyopaque = malloc_fn(size + 1) orelse return -1;
    s.* = @ptrCast(ptr);
    return vsnprintf_impl(s.*.?, size + 1, fmt, ap_src);
}

// --- FD formatting (vdprintf.c) ---

/// vdprintf.c: int vdprintf(int fd, const char *restrict fmt, va_list ap)
fn vdprintf_impl(fd: c_int, fmt: [*:0]const u8, ap: VaList) callconv(.c) c_int {
    var f = std.mem.zeroes(FILE);
    f.fd = fd;
    f.lbf = EOF;
    f.write_fn = stdio_write_ext;
    f.buf = @ptrCast(@constCast(fmt));
    f.buf_size = 0;
    f.lock = -1;
    return vfprintf_fn(@ptrCast(&f), fmt, ap);
}

// --- Line reading (getdelim.c) ---

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

fn setErrno(e: std.os.linux.E) void {
    std.c._errno().* = @intCast(@intFromEnum(e));
}

// --- vsnprintf.c ---

const SnCookie = extern struct {
    s: [*]u8,
    n: usize,
};

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
fn vsnprintf_impl(s: [*]u8, n: usize, fmt: [*:0]const u8, ap: VaList) callconv(.c) c_int {
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
    return vfprintf_fn(@ptrCast(&f), fmt, ap);
}

// --- vsprintf.c ---

/// vsprintf.c: int vsprintf(char *restrict s, const char *restrict fmt, va_list ap)
fn vsprintf_impl(s: [*]u8, fmt: [*:0]const u8, ap: VaList) callconv(.c) c_int {
    return vsnprintf_impl(s, std.math.maxInt(c_int), fmt, ap);
}

// --- vsscanf.c ---

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

/// vsscanf.c: int vsscanf(const char *restrict s, const char *restrict fmt, va_list ap)
fn vsscanf_impl(s: [*:0]const u8, fmt: [*:0]const u8, ap: VaList) callconv(.c) c_int {
    var f = std.mem.zeroes(FILE);
    f.buf = @ptrCast(@constCast(s));
    f.cookie = @ptrCast(@constCast(s));
    f.read_fn = &string_read;
    f.lock = -1;
    return vfscanf_fn(@ptrCast(&f), fmt, ap);
}

// --- vswprintf.c ---

fn sw_write(f: *FILE, s: [*]const u8, l: usize) callconv(.c) usize {
    const l0 = l;
    var i: c_int = 0;
    const c: *SwCookie = @ptrCast(@alignCast(f.cookie.?));
    // Flush pending buffered data if s is not the write base
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

const SwCookie = extern struct {
    ws: [*]wchar_t,
    l: usize,
};

/// vswprintf.c: int vswprintf(wchar_t *restrict s, size_t n, const wchar_t *restrict fmt, va_list ap)
fn vswprintf_impl(s: [*]wchar_t, n: usize, fmt: [*:0]const wchar_t, ap: VaList) callconv(.c) c_int {
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
    const r = vfwprintf_fn(@ptrCast(&f), fmt, ap);
    _ = sw_write(&f, @ptrCast(&f), 0);
    return if (r >= @as(c_int, @intCast(n))) @as(c_int, -1) else r;
}

// --- vswscanf.c ---

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
fn vswscanf_impl(s: [*:0]const wchar_t, fmt: [*:0]const wchar_t, ap: VaList) callconv(.c) c_int {
    var buf: [256]u8 = undefined;
    var f = std.mem.zeroes(FILE);
    f.buf = &buf;
    f.buf_size = buf.len;
    f.cookie = @ptrCast(@constCast(s));
    f.read_fn = &wstring_read;
    f.lock = -1;
    return vfwscanf_fn(@ptrCast(&f), fmt, ap);
}

// --- Wide formatting wrappers (wprintf.c, fwprintf.c, swprintf.c) ---

/// wprintf.c: int wprintf(const wchar_t *restrict fmt, ...)
fn wprintf_impl(fmt: [*:0]const wchar_t, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vfwprintf_fn(stdout_ext.*, fmt, ap);
}

/// fwprintf.c: int fwprintf(FILE *restrict f, const wchar_t *restrict fmt, ...)
fn fwprintf_impl(f: ?*FILE, fmt: [*:0]const wchar_t, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vfwprintf_fn(f, fmt, ap);
}

/// swprintf.c: int swprintf(wchar_t *restrict s, size_t n, const wchar_t *restrict fmt, ...)
fn swprintf_impl(s: [*]wchar_t, n: usize, fmt: [*:0]const wchar_t, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vswprintf_impl(s, n, fmt, ap);
}

// --- Wide scanning wrappers (wscanf.c, fwscanf.c, swscanf.c) ---

/// wscanf.c: int wscanf(const wchar_t *restrict fmt, ...)
fn wscanf_impl(fmt: [*:0]const wchar_t, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vfwscanf_fn(stdin_ext.*, fmt, ap);
}

/// fwscanf.c: int fwscanf(FILE *restrict f, const wchar_t *restrict fmt, ...)
fn fwscanf_impl(f: ?*FILE, fmt: [*:0]const wchar_t, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vfwscanf_fn(f, fmt, ap);
}

/// swscanf.c: int swscanf(const wchar_t *restrict s, const wchar_t *restrict fmt, ...)
fn swscanf_impl(s: [*:0]const wchar_t, fmt: [*:0]const wchar_t, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vswscanf_impl(s, fmt, ap);
}

// --- Wide v* delegation (vwprintf.c, vwscanf.c) ---

/// vwprintf.c: int vwprintf(const wchar_t *restrict fmt, va_list ap)
fn vwprintf_impl(fmt: [*:0]const wchar_t, ap: VaList) callconv(.c) c_int {
    return vfwprintf_fn(stdout_ext.*, fmt, ap);
}

/// vwscanf.c: int vwscanf(const wchar_t *restrict fmt, va_list ap)
fn vwscanf_impl(fmt: [*:0]const wchar_t, ap: VaList) callconv(.c) c_int {
    return vfwscanf_fn(stdin_ext.*, fmt, ap);
}

// --- Narrow v* delegation (vprintf.c, vscanf.c) ---

/// vprintf.c: int vprintf(const char *restrict fmt, va_list ap)
fn vprintf_impl(fmt: [*:0]const u8, ap: VaList) callconv(.c) c_int {
    return vfprintf_fn(stdout_ext.*, fmt, ap);
}

/// vscanf.c: int vscanf(const char *restrict fmt, va_list ap)
fn vscanf_impl(fmt: [*:0]const u8, ap: VaList) callconv(.c) c_int {
    return vfscanf_fn(stdin_ext.*, fmt, ap);
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
        .aarch64, .aarch64_be,
        .arm, .armeb, .thumb, .thumbeb,
        .loongarch64,
        .m68k,
        .mips, .mipsel, .mips64, .mips64el,
        .powerpc, .powerpcle, .powerpc64, .powerpc64le,
        .riscv32, .riscv64,
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

    if (libc_ptr.threaded == 0) mf.f.lock = -1;

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

    if (libc_ptr.threaded == 0) ms.f.lock = -1;

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

    if (libc_ptr.threaded == 0) wms.f.lock = -1;

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
const fgetwc_fn = @extern(*const fn (?*FILE) callconv(.c) wint_t, .{ .name = "fgetwc" });
const fputwc_fn = @extern(*const fn (wchar_t, ?*FILE) callconv(.c) wint_t, .{ .name = "fputwc" });
const stdin_ext = @extern(*const ?*FILE, .{ .name = "stdin" });
const stdout_ext = @extern(*const ?*FILE, .{ .name = "stdout" });
const stderr_ext = @extern(*const ?*FILE, .{ .name = "stderr" });
const fflush_fn = @extern(*const fn (?*FILE) callconv(.c) c_int, .{ .name = "fflush" });
const strerror_fn = @extern(*const fn (c_int) callconv(.c) [*:0]const u8, .{ .name = "strerror" });
const vfprintf_fn = @extern(*const fn (?*FILE, [*:0]const u8, VaList) callconv(.c) c_int, .{ .name = "vfprintf" });
const vfwprintf_fn = @extern(*const fn (?*FILE, [*:0]const wchar_t, VaList) callconv(.c) c_int, .{ .name = "vfwprintf" });
const vfscanf_fn = @extern(*const fn (?*FILE, [*:0]const u8, VaList) callconv(.c) c_int, .{ .name = "vfscanf" });
const vfwscanf_fn = @extern(*const fn (?*FILE, [*:0]const wchar_t, VaList) callconv(.c) c_int, .{ .name = "vfwscanf" });
const memchr_fn = @extern(*const fn (?[*]const u8, c_int, usize) callconv(.c) ?[*]u8, .{ .name = "memchr" });
const lseek_fn = @extern(*const fn (c_int, i64, c_int) callconv(.c) i64, .{ .name = "__lseek" });
const malloc_fn = @extern(*const fn (usize) callconv(.c) ?*anyopaque, .{ .name = "malloc" });
const realloc_fn = @extern(*const fn (?*anyopaque, usize) callconv(.c) ?*anyopaque, .{ .name = "realloc" });
const stdio_write_ext = @extern(*const fn (*FILE, [*]const u8, usize) callconv(.c) usize, .{ .name = "__stdio_write" });
const mbtowc_fn = @extern(*const fn (?*wchar_t, ?[*]const u8, usize) callconv(.c) c_int, .{ .name = "mbtowc" });
const wcsrtombs_fn = @extern(*const fn (?[*]u8, *?[*:0]const wchar_t, usize, ?*anyopaque) callconv(.c) usize, .{ .name = "wcsrtombs" });
const free_fn = @extern(*const fn (?*anyopaque) callconv(.c) void, .{ .name = "free" });
const ofl_add_fn = @extern(*const fn (*FILE) callconv(.c) ?*FILE, .{ .name = "__ofl_add" });
const libc_ptr = @extern(*const Libc, .{ .name = "__libc" });
const fwide_fn = @extern(*const fn (*FILE, c_int) callconv(.c) c_int, .{ .name = "fwide" });
const mbsnrtowcs_fn = @extern(*const fn (?[*]wchar_t, *?[*]const u8, usize, usize, *mbstate_t) callconv(.c) usize, .{ .name = "mbsnrtowcs" });
