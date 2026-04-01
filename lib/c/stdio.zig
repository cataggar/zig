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
    return if (f.lock >= 0) lockfile_fn(f) else 0;
}

/// Implements musl FUNLOCK(f) macro
inline fn funlock(f: *FILE, need_unlock: c_int) void {
    if (need_unlock != 0) unlockfile_fn(f);
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
        f.write_fn.?(f, @ptrCast(&[0]u8{}), 0);
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
    return c_errno(linux.renameat2(linux.AT.FDCWD, @ptrCast(old), linux.AT.FDCWD, @ptrCast(new), 0));
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
    return vsnprintf_fn(s, n, fmt, ap);
}

/// sprintf.c: int sprintf(char *restrict s, const char *restrict fmt, ...)
fn sprintf_impl(s: [*]u8, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vsprintf_fn(s, fmt, ap);
}

/// asprintf.c: int asprintf(char **s, const char *fmt, ...)
fn asprintf_impl(s: *?[*]u8, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vasprintf_fn(s, fmt, ap);
}

/// dprintf.c: int dprintf(int fd, const char *restrict fmt, ...)
fn dprintf_impl(fd: c_int, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vdprintf_fn(fd, fmt, ap);
}

// --- Scanning wrappers (scanf.c, fscanf.c, sscanf.c) ---

/// scanf.c: int scanf(const char *restrict fmt, ...)
fn scanf_impl(fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vscanf_fn(fmt, ap);
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
    return vsscanf_fn(s, fmt, ap);
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
    const l = vsnprintf_fn(&dummy, 0, fmt, ap_copy);
    @cVaEnd(&ap_copy);
    if (l < 0) return -1;
    const size: usize = @intCast(l);
    const ptr: ?*anyopaque = malloc_fn(size + 1) orelse return -1;
    s.* = @ptrCast(ptr);
    return vsnprintf_fn(s.*.?, size + 1, fmt, ap_src);
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
    return vswprintf_fn(s, n, fmt, ap);
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
    return vswscanf_fn(s, fmt, ap);
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

// Extern references to musl C functions that are still compiled from C sources.
const fgetwc_fn = @extern(*const fn (?*FILE) callconv(.c) wint_t, .{ .name = "fgetwc" });
const fputwc_fn = @extern(*const fn (wchar_t, ?*FILE) callconv(.c) wint_t, .{ .name = "fputwc" });
const stdin_ext = @extern(*const ?*FILE, .{ .name = "stdin" });
const stdout_ext = @extern(*const ?*FILE, .{ .name = "stdout" });
const stderr_ext = @extern(*const ?*FILE, .{ .name = "stderr" });
const lockfile_fn = @extern(*const fn (*FILE) callconv(.c) c_int, .{ .name = "__lockfile" });
const unlockfile_fn = @extern(*const fn (*FILE) callconv(.c) void, .{ .name = "__unlockfile" });
const fflush_fn = @extern(*const fn (?*FILE) callconv(.c) c_int, .{ .name = "fflush" });
const strerror_fn = @extern(*const fn (c_int) callconv(.c) [*:0]const u8, .{ .name = "strerror" });
const vfprintf_fn = @extern(*const fn (?*FILE, [*:0]const u8, VaList) callconv(.c) c_int, .{ .name = "vfprintf" });
const vsnprintf_fn = @extern(*const fn ([*]u8, usize, [*:0]const u8, VaList) callconv(.c) c_int, .{ .name = "vsnprintf" });
const vsprintf_fn = @extern(*const fn ([*]u8, [*:0]const u8, VaList) callconv(.c) c_int, .{ .name = "vsprintf" });
const vasprintf_fn = @extern(*const fn (*?[*]u8, [*:0]const u8, VaList) callconv(.c) c_int, .{ .name = "vasprintf" });
const vdprintf_fn = @extern(*const fn (c_int, [*:0]const u8, VaList) callconv(.c) c_int, .{ .name = "vdprintf" });
const vscanf_fn = @extern(*const fn ([*:0]const u8, VaList) callconv(.c) c_int, .{ .name = "vscanf" });
const vfscanf_fn = @extern(*const fn (?*FILE, [*:0]const u8, VaList) callconv(.c) c_int, .{ .name = "vfscanf" });
const vsscanf_fn = @extern(*const fn ([*:0]const u8, [*:0]const u8, VaList) callconv(.c) c_int, .{ .name = "vsscanf" });
const vfwprintf_fn = @extern(*const fn (?*FILE, [*:0]const wchar_t, VaList) callconv(.c) c_int, .{ .name = "vfwprintf" });
const vfwscanf_fn = @extern(*const fn (?*FILE, [*:0]const wchar_t, VaList) callconv(.c) c_int, .{ .name = "vfwscanf" });
const vswprintf_fn = @extern(*const fn ([*]wchar_t, usize, [*:0]const wchar_t, VaList) callconv(.c) c_int, .{ .name = "vswprintf" });
const vswscanf_fn = @extern(*const fn ([*:0]const wchar_t, [*:0]const wchar_t, VaList) callconv(.c) c_int, .{ .name = "vswscanf" });
const memchr_fn = @extern(*const fn (?[*]const u8, c_int, usize) callconv(.c) ?[*]u8, .{ .name = "memchr" });
const lseek_fn = @extern(*const fn (c_int, i64, c_int) callconv(.c) i64, .{ .name = "__lseek" });
const malloc_fn = @extern(*const fn (usize) callconv(.c) ?*anyopaque, .{ .name = "malloc" });
const realloc_fn = @extern(*const fn (?*anyopaque, usize) callconv(.c) ?*anyopaque, .{ .name = "realloc" });
const stdio_write_ext = @extern(*const fn (*FILE, [*]const u8, usize) callconv(.c) usize, .{ .name = "__stdio_write" });
