const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;

const FILE = opaque {};
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

        // Word I/O (getw.c, putw.c)
        symbol(&getw, "getw");
        symbol(&putw, "putw");
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

// Extern references to musl C functions that are still compiled from C sources.
const setvbuf_fn = @extern(*const fn (?*FILE, ?[*]u8, c_int, usize) callconv(.c) c_int, .{ .name = "setvbuf" });
const getdelim_fn = @extern(*const fn (?*[*]u8, ?*usize, c_int, ?*FILE) callconv(.c) ssize_t, .{ .name = "getdelim" });
const fgetwc_fn = @extern(*const fn (?*FILE) callconv(.c) wint_t, .{ .name = "fgetwc" });
const fputwc_fn = @extern(*const fn (wchar_t, ?*FILE) callconv(.c) wint_t, .{ .name = "fputwc" });
const fread_fn = @extern(*const fn (*anyopaque, usize, usize, ?*FILE) callconv(.c) usize, .{ .name = "fread" });
const fwrite_fn = @extern(*const fn (*const anyopaque, usize, usize, ?*FILE) callconv(.c) usize, .{ .name = "fwrite" });
const stdin_ext = @extern(*const ?*FILE, .{ .name = "stdin" });
const stdout_ext = @extern(*const ?*FILE, .{ .name = "stdout" });
