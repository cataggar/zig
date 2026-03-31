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
    return if (fread(@ptrCast(&x), @sizeOf(c_int), 1, @ptrCast(f)) != 0) x else EOF;
}

/// putw.c: int putw(int x, FILE *f)
fn putw(x: c_int, f: ?*FILE) callconv(.c) c_int {
    var val = x;
    return @as(c_int, @intCast(fwrite(@ptrCast(&val), @sizeOf(c_int), 1, @ptrCast(f)))) - 1;
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

// --- Unget functions ---

/// Musl UNGET constant (from stdio_impl.h)
const UNGET = 8;

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

// Extern references to musl C functions that are still compiled from C sources.
const getdelim_fn = @extern(*const fn (?*[*]u8, ?*usize, c_int, ?*FILE) callconv(.c) ssize_t, .{ .name = "getdelim" });
const fgetwc_fn = @extern(*const fn (?*FILE) callconv(.c) wint_t, .{ .name = "fgetwc" });
const fputwc_fn = @extern(*const fn (wchar_t, ?*FILE) callconv(.c) wint_t, .{ .name = "fputwc" });
const fgetc_fn = @extern(*const fn (?*FILE) callconv(.c) c_int, .{ .name = "fgetc" });
const fputc_fn = @extern(*const fn (c_int, ?*FILE) callconv(.c) c_int, .{ .name = "fputc" });
const getc_unlocked_fn = @extern(*const fn (?*FILE) callconv(.c) c_int, .{ .name = "getc_unlocked" });
const putc_unlocked_fn = @extern(*const fn (c_int, ?*FILE) callconv(.c) c_int, .{ .name = "putc_unlocked" });
const stdin_ext = @extern(*const ?*FILE, .{ .name = "stdin" });
const stdout_ext = @extern(*const ?*FILE, .{ .name = "stdout" });
const lockfile_fn = @extern(*const fn (*FILE) callconv(.c) c_int, .{ .name = "__lockfile" });
const unlockfile_fn = @extern(*const fn (*FILE) callconv(.c) void, .{ .name = "__unlockfile" });
const toread_fn = @extern(*const fn (*FILE) callconv(.c) c_int, .{ .name = "__toread" });
const towrite_fn = @extern(*const fn (*FILE) callconv(.c) c_int, .{ .name = "__towrite" });
