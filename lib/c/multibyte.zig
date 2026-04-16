const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&btowc, "btowc");
        symbol(&c16rtomb, "c16rtomb");
        symbol(&c32rtomb, "c32rtomb");
        symbol(&mblen, "mblen");
        symbol(&mbrlen, "mbrlen");
        symbol(&mbrtoc16, "mbrtoc16");
        symbol(&mbrtoc32, "mbrtoc32");
        symbol(&mbrtowc, "mbrtowc");
        symbol(&mbsinit, "mbsinit");
        symbol(&mbsnrtowcs, "mbsnrtowcs");
        symbol(&mbsrtowcs, "mbsrtowcs");
        symbol(&mbstowcs, "mbstowcs");
        symbol(&mbtowc, "mbtowc");
        symbol(&wcrtomb, "wcrtomb");
        symbol(&wcsnrtombs, "wcsnrtombs");
        symbol(&wcsrtombs, "wcsrtombs");
        symbol(&wcstombs, "wcstombs");
        symbol(&wctob, "wctob");
        symbol(&wctomb, "wctomb");
    }
}

const EILSEQ: c_int = 84;
const WEOF: c_uint = 0xFFFFFFFF;
const MB_LEN_MAX = 4;

const SA: u8 = 0xc2;
const SB: u8 = 0xf4;

extern "c" fn setlocale(category: c_int, locale: ?[*:0]const u8) ?[*:0]const u8;

/// Check if the current locale uses UTF-8 encoding (MB_CUR_MAX > 1).
/// In the C locale (default), MB_CUR_MAX is 1 and bytes 0x80-0xFF are
/// valid single-byte characters.
fn currentUtf8() bool {
    const loc = setlocale(0, null) orelse return false; // LC_CTYPE = 0
    // C locale returns "C", POSIX returns "POSIX" — both are single-byte
    if (loc[0] == 'C' and loc[1] == 0) return false;
    if (loc[0] == 'P') return false; // "POSIX"
    return true;
}

/// Interval [a,b). Either a must be 0x80 or b must be 0xc0, lower 3 bits clear.
fn R(comptime a: u32, comptime b: u32) u32 {
    return if (a == 0x80) (0x40 -% b) << 23 else (0 -% a) << 23;
}

const FAILSTATE: u32 = R(0x80, 0x80);

fn C(comptime x: u32) u32 {
    return if (x < 2) @bitCast(@as(i32, -1)) else R(0x80, 0xc0) | x;
}

fn D(comptime x: u32) u32 {
    return C(x + 16);
}

fn E(comptime x: u32) u32 {
    return (if (x == 0) R(0xa0, 0xc0) else if (x == 0xd) R(0x80, 0xa0) else R(0x80, 0xc0)) |
        (R(0x80, 0xc0) >> 6) | x;
}

fn F(comptime x: u32) u32 {
    return (if (x >= 5) @as(u32, 0) else if (x == 0) R(0x90, 0xc0) else if (x == 4) R(0x80, 0x90) else R(0x80, 0xc0)) |
        (R(0x80, 0xc0) >> 6) | (R(0x80, 0xc0) >> 12) | x;
}

const bittab = [_]u32{
    C(0x2),  C(0x3),  C(0x4),  C(0x5),  C(0x6),  C(0x7),
    C(0x8),  C(0x9),  C(0xa),  C(0xb),  C(0xc),  C(0xd),  C(0xe),  C(0xf),
    D(0x0),  D(0x1),  D(0x2),  D(0x3),  D(0x4),  D(0x5),  D(0x6),  D(0x7),
    D(0x8),  D(0x9),  D(0xa),  D(0xb),  D(0xc),  D(0xd),  D(0xe),  D(0xf),
    E(0x0),  E(0x1),  E(0x2),  E(0x3),  E(0x4),  E(0x5),  E(0x6),  E(0x7),
    E(0x8),  E(0x9),  E(0xa),  E(0xb),  E(0xc),  E(0xd),  E(0xe),  E(0xf),
    F(0x0),  F(0x1),  F(0x2),  F(0x3),  F(0x4),
};

/// `OOB(c,b)` — out-of-bounds check for continuation bytes.
/// Uses wrapping arithmetic matching the C:
/// `(((((b)>>3)-0x10)|(((b)>>3)+((int32_t)(c)>>26))) & ~7)`
fn OOB(c_val: u32, b: u8) bool {
    const b_shifted: u32 = @as(u32, b) >> 3;
    const c_signed: i32 = @bitCast(c_val);
    const c_shifted: u32 = @bitCast(c_signed >> 26);
    return ((b_shifted -% 0x10) | (b_shifted +% c_shifted)) & ~@as(u32, 7) != 0;
}

/// `CODEUNIT(c)` — sign-extend u8 to i8 then to i32, mask with 0xdfff.
fn CODEUNIT(c: u8) u32 {
    const signed: i32 = @as(i8, @bitCast(c));
    return @as(u32, @bitCast(signed)) & 0xdfff;
}

/// `IS_CODEUNIT(c)` — check if c is a code unit encoding.
fn IS_CODEUNIT(c: u32) bool {
    return c -% 0xdf80 < 0x80;
}

fn setErrno() void {
    std.c._errno().* = EILSEQ;
}

const size_t_minus1: usize = @bitCast(@as(isize, -1));
const size_t_minus2: usize = @bitCast(@as(isize, -2));
const size_t_minus3: usize = @bitCast(@as(isize, -3));

var mbrtowc_internal_state: c_uint = 0;
var mbrlen_internal_state: c_uint = 0;
var mbrtoc16_internal_state: c_uint = 0;
var mbrtoc32_internal_state: c_uint = 0;
var c16rtomb_internal_state: c_uint = 0;

// ---------------------------------------------------------------------------
// btowc
// ---------------------------------------------------------------------------

fn btowc(c: c_int) callconv(.c) c_uint {
    const b: u8 = @truncate(@as(c_uint, @bitCast(c)));
    if (b < 128) return b;
    if (!currentUtf8()) return CODEUNIT(b);
    return WEOF;
}

// ---------------------------------------------------------------------------
// wctob
// ---------------------------------------------------------------------------

fn wctob(c: c_uint) callconv(.c) c_int {
    if (c < 128) return @intCast(c);
    if (!currentUtf8() and IS_CODEUNIT(c)) return @as(c_int, @as(u8, @truncate(c)));
    return -1; // EOF
}

// ---------------------------------------------------------------------------
// mbsinit
// ---------------------------------------------------------------------------

fn mbsinit(st: ?*const c_uint) callconv(.c) c_int {
    if (st) |s| {
        return if (s.* == 0) @as(c_int, 1) else @as(c_int, 0);
    }
    return 1;
}

// ---------------------------------------------------------------------------
// mbrtowc — CORE: UTF-8 decode with state machine
// ---------------------------------------------------------------------------

fn mbrtowc(wc_ptr: ?*u32, src_ptr: ?[*]const u8, n_arg: usize, st_ptr: ?*c_uint) callconv(.c) usize {
    const st: *c_uint = st_ptr orelse &mbrtowc_internal_state;
    var c: u32 = st.*;

    const s_init = src_ptr orelse {
        // src is NULL
        if (c != 0) {
            st.* = 0;
            setErrno();
            return size_t_minus1;
        }
        return 0;
    };

    var s = s_init;
    const N = n_arg;
    var n = n_arg;

    if (n == 0) return size_t_minus2;

    if (c == 0) {
        if (s[0] < 0x80) {
            const val: u32 = s[0];
            if (wc_ptr) |wc| wc.* = val;
            return if (val != 0) 1 else 0;
        }
        if (!currentUtf8()) {
            if (wc_ptr) |wc| wc.* = CODEUNIT(s[0]);
            return 1;
        }
        if (s[0] -% SA > SB - SA) {
            st.* = 0;
            setErrno();
            return size_t_minus1;
        }
        c = bittab[s[0] - SA];
        s = s + 1;
        n -= 1;
    }

    if (n != 0) {
        if (OOB(c, s[0])) {
            st.* = 0;
            setErrno();
            return size_t_minus1;
        }
        // loop
        while (true) {
            c = (c << 6) | (@as(u32, s[0]) -% 0x80);
            s = s + 1;
            n -= 1;
            if (c & (1 << 31) == 0) {
                st.* = 0;
                if (wc_ptr) |wc| wc.* = c;
                return N - n;
            }
            if (n == 0) break;
            if (@as(u32, s[0]) -% 0x80 >= 0x40) {
                st.* = 0;
                setErrno();
                return size_t_minus1;
            }
        }
    }

    st.* = c;
    return size_t_minus2;
}

// ---------------------------------------------------------------------------
// wcrtomb — CORE: wchar_t to UTF-8 encode
// ---------------------------------------------------------------------------

fn wcrtomb(s: ?[*]u8, wc_arg: u32, st: ?*c_uint) callconv(.c) usize {
    _ = st;
    const p = s orelse return 1;
    const wc: u32 = wc_arg;

    if (wc < 0x80) {
        p[0] = @truncate(wc);
        return 1;
    } else if (!currentUtf8()) {
        if (!IS_CODEUNIT(wc)) {
            setErrno();
            return size_t_minus1;
        }
        p[0] = @truncate(wc);
        return 1;
    } else if (wc < 0x800) {
        p[0] = @truncate(0xc0 | (wc >> 6));
        p[1] = @truncate(0x80 | (wc & 0x3f));
        return 2;
    } else if (wc < 0xd800 or (wc -% 0xe000 < 0x2000)) {
        p[0] = @truncate(0xe0 | (wc >> 12));
        p[1] = @truncate(0x80 | ((wc >> 6) & 0x3f));
        p[2] = @truncate(0x80 | (wc & 0x3f));
        return 3;
    } else if (wc -% 0x10000 < 0x100000) {
        p[0] = @truncate(0xf0 | (wc >> 18));
        p[1] = @truncate(0x80 | ((wc >> 12) & 0x3f));
        p[2] = @truncate(0x80 | ((wc >> 6) & 0x3f));
        p[3] = @truncate(0x80 | (wc & 0x3f));
        return 4;
    }
    setErrno();
    return size_t_minus1;
}

// ---------------------------------------------------------------------------
// mbtowc
// ---------------------------------------------------------------------------

fn mbtowc(wc_ptr: ?*u32, src_ptr: ?[*]const u8, n: usize) callconv(.c) c_int {
    const s = src_ptr orelse return 0;
    if (n == 0) {
        setErrno();
        return -1;
    }

    if (s[0] < 0x80) {
        if (wc_ptr) |wc| wc.* = s[0];
        return if (s[0] != 0) @as(c_int, 1) else @as(c_int, 0);
    }
    if (!currentUtf8()) {
        if (wc_ptr) |wc| wc.* = CODEUNIT(s[0]);
        return 1;
    }
    if (s[0] -% SA > SB - SA) {
        setErrno();
        return -1;
    }
    var c: u32 = bittab[s[0] - SA];

    // If shifting the state n-1 times does not clear the high bit,
    // then the value of n is insufficient to read a character.
    if (n < 4 and ((c << @intCast(6 * n - 6)) & (1 << 31) != 0)) {
        setErrno();
        return -1;
    }

    if (OOB(c, s[1])) {
        setErrno();
        return -1;
    }
    c = (c << 6) | (@as(u32, s[1]) -% 0x80);
    if (c & (1 << 31) == 0) {
        if (wc_ptr) |wc| wc.* = c;
        return 2;
    }

    if (@as(u32, s[2]) -% 0x80 >= 0x40) {
        setErrno();
        return -1;
    }
    c = (c << 6) | (@as(u32, s[2]) -% 0x80);
    if (c & (1 << 31) == 0) {
        if (wc_ptr) |wc| wc.* = c;
        return 3;
    }

    if (@as(u32, s[3]) -% 0x80 >= 0x40) {
        setErrno();
        return -1;
    }
    if (wc_ptr) |wc| wc.* = (c << 6) | (@as(u32, s[3]) -% 0x80);
    return 4;
}

// ---------------------------------------------------------------------------
// mblen
// ---------------------------------------------------------------------------

fn mblen(s: ?[*]const u8, n: usize) callconv(.c) c_int {
    return mbtowc(null, s, n);
}

// ---------------------------------------------------------------------------
// mbrlen
// ---------------------------------------------------------------------------

fn mbrlen(s: ?[*]const u8, n: usize, st: ?*c_uint) callconv(.c) usize {
    return mbrtowc(null, s, n, st orelse &mbrlen_internal_state);
}

// ---------------------------------------------------------------------------
// wctomb
// ---------------------------------------------------------------------------

fn wctomb(s: ?[*]u8, wc: u32) callconv(.c) c_int {
    if (s == null) return 0;
    const ret = wcrtomb(s, wc, null);
    if (ret == size_t_minus1) return -1;
    return @intCast(ret);
}

// ---------------------------------------------------------------------------
// mbstowcs
// ---------------------------------------------------------------------------

fn mbstowcs(ws: ?[*]u32, s_ptr: ?[*]const u8, wn: usize) callconv(.c) usize {
    // mbsrtowcs expects a pointer to the source pointer.
    // We create a local copy on the stack.
    var s = s_ptr;
    return mbsrtowcs(ws, &s, wn, null);
}

// ---------------------------------------------------------------------------
// wcstombs
// ---------------------------------------------------------------------------

fn wcstombs(s: ?[*]u8, ws_ptr: ?[*]const u32, n: usize) callconv(.c) usize {
    var ws = ws_ptr;
    return wcsrtombs(s, &ws, n, null);
}

// ---------------------------------------------------------------------------
// mbsrtowcs — batch UTF-8 to wchar_t
// ---------------------------------------------------------------------------

fn mbsrtowcs(ws: ?[*]u32, src: *?[*]const u8, wn_arg: usize, st_ptr: ?*c_uint) callconv(.c) usize {
    var s: [*]const u8 = src.* orelse return 0;
    var wn = wn_arg;
    const wn0 = wn;
    var c: u32 = 0;

    if (st_ptr) |st| {
        c = st.*;
        if (c != 0) {
            st.* = 0;
            if (ws != null) {
                return mbsrtowcs_ws_resume(ws.?, src, wn0, &wn, &c, &s);
            } else {
                return mbsrtowcs_count_resume(src, wn0, &wn, &c, &s);
            }
        }
    }

    // C locale fast path: single-byte encoding
    if (!currentUtf8()) {
        if (ws) |w| {
            var wp = w;
            while (wn > 0) {
                if (s[0] == 0) {
                    wp[0] = 0;
                    src.* = null;
                    return wn0 - wn;
                }
                wp[0] = CODEUNIT(s[0]);
                wp += 1;
                s += 1;
                wn -= 1;
            }
            src.* = s;
            return wn0;
        } else {
            return std.mem.len(@as([*:0]const u8, @ptrCast(s)));
        }
    }

    if (ws) |ws_nonnull| {
        return mbsrtowcs_ws(ws_nonnull, src, wn0, &wn, &c, &s);
    } else {
        return mbsrtowcs_count(src, wn0, &wn, &c, &s);
    }
}

fn mbsrtowcs_count(src: *?[*]const u8, wn0: usize, wn: *usize, c: *u32, s: *[*]const u8) usize {
    return mbsrtowcs_count_inner(src, wn0, wn, c, s, false);
}

fn mbsrtowcs_count_resume(src: *?[*]const u8, wn0: usize, wn: *usize, c: *u32, s: *[*]const u8) usize {
    return mbsrtowcs_count_inner(src, wn0, wn, c, s, true);
}

fn mbsrtowcs_count_inner(_: *?[*]const u8, wn0: usize, wn: *usize, c: *u32, s: *[*]const u8, resume_first: bool) usize {
    var first = resume_first;
    while (true) {
        if (first) {
            first = false;
            // resume0: validate continuation bytes
            if (OOB(c.*, s.*[0])) {
                s.* -= 1;
                break;
            }
            s.* += 1;
            if (c.* & (1 << 25) != 0) {
                if (@as(u32, s.*[0]) -% 0x80 >= 0x40) {
                    s.* -= 2;
                    break;
                }
                s.* += 1;
                if (c.* & (1 << 19) != 0) {
                    if (@as(u32, s.*[0]) -% 0x80 >= 0x40) {
                        s.* -= 3;
                        break;
                    }
                    s.* += 1;
                }
            }
            wn.* -= 1;
            c.* = 0;
            continue;
        }

        if (s.*[0] -% 1 < 0x7f) {
            s.* += 1;
            wn.* -= 1;
            continue;
        }
        if (s.*[0] -% SA > SB - SA) break;
        c.* = bittab[s.*[0] - SA];
        s.* += 1;
        // resume0 logic inline
        if (OOB(c.*, s.*[0])) {
            s.* -= 1;
            break;
        }
        s.* += 1;
        if (c.* & (1 << 25) != 0) {
            if (@as(u32, s.*[0]) -% 0x80 >= 0x40) {
                s.* -= 2;
                break;
            }
            s.* += 1;
            if (c.* & (1 << 19) != 0) {
                if (@as(u32, s.*[0]) -% 0x80 >= 0x40) {
                    s.* -= 3;
                    break;
                }
                s.* += 1;
            }
        }
        wn.* -= 1;
        c.* = 0;
    }

    if (c.* == 0 and s.*[0] == 0) {
        return wn0 - wn.*;
    }
    setErrno();
    return size_t_minus1;
}

fn mbsrtowcs_ws(ws_nonnull: [*]u32, src: *?[*]const u8, wn0: usize, wn: *usize, c: *u32, s: *[*]const u8) usize {
    return mbsrtowcs_ws_inner(ws_nonnull, src, wn0, wn, c, s, false);
}

fn mbsrtowcs_ws_resume(ws_nonnull: [*]u32, src: *?[*]const u8, wn0: usize, wn: *usize, c: *u32, s: *[*]const u8) usize {
    return mbsrtowcs_ws_inner(ws_nonnull, src, wn0, wn, c, s, true);
}

fn mbsrtowcs_ws_inner(ws_base: [*]u32, src: *?[*]const u8, wn0: usize, wn: *usize, c: *u32, s: *[*]const u8, resume_first: bool) usize {
    var ws = ws_base + (wn0 - wn.*);
    var first = resume_first;

    while (true) {
        if (first) {
            first = false;
            // resume: decode continuation bytes
            if (OOB(c.*, s.*[0])) {
                s.* -= 1;
                break;
            }
            c.* = (c.* << 6) | (@as(u32, s.*[0]) -% 0x80);
            s.* += 1;
            if (c.* & (1 << 31) != 0) {
                if (@as(u32, s.*[0]) -% 0x80 >= 0x40) {
                    s.* -= 2;
                    break;
                }
                c.* = (c.* << 6) | (@as(u32, s.*[0]) -% 0x80);
                s.* += 1;
                if (c.* & (1 << 31) != 0) {
                    if (@as(u32, s.*[0]) -% 0x80 >= 0x40) {
                        s.* -= 3;
                        break;
                    }
                    c.* = (c.* << 6) | (@as(u32, s.*[0]) -% 0x80);
                    s.* += 1;
                }
            }
            ws[0] = c.*;
            ws += 1;
            wn.* -= 1;
            c.* = 0;
            continue;
        }

        if (wn.* == 0) {
            src.* = s.*;
            return wn0;
        }
        if (s.*[0] -% 1 < 0x7f) {
            ws[0] = s.*[0];
            ws += 1;
            s.* += 1;
            wn.* -= 1;
            continue;
        }
        if (s.*[0] -% SA > SB - SA) break;
        c.* = bittab[s.*[0] - SA];
        s.* += 1;
        // resume: decode continuation bytes
        if (OOB(c.*, s.*[0])) {
            s.* -= 1;
            break;
        }
        c.* = (c.* << 6) | (@as(u32, s.*[0]) -% 0x80);
        s.* += 1;
        if (c.* & (1 << 31) != 0) {
            if (@as(u32, s.*[0]) -% 0x80 >= 0x40) {
                s.* -= 2;
                break;
            }
            c.* = (c.* << 6) | (@as(u32, s.*[0]) -% 0x80);
            s.* += 1;
            if (c.* & (1 << 31) != 0) {
                if (@as(u32, s.*[0]) -% 0x80 >= 0x40) {
                    s.* -= 3;
                    break;
                }
                c.* = (c.* << 6) | (@as(u32, s.*[0]) -% 0x80);
                s.* += 1;
            }
        }
        ws[0] = c.*;
        ws += 1;
        wn.* -= 1;
        c.* = 0;
    }

    if (c.* == 0 and s.*[0] == 0) {
        ws[0] = 0;
        src.* = null;
        return wn0 - wn.*;
    }
    setErrno();
    src.* = s.*;
    return size_t_minus1;
}

// ---------------------------------------------------------------------------
// wcsrtombs — batch wchar_t to UTF-8
// ---------------------------------------------------------------------------

fn wcsrtombs(s: ?[*]u8, ws: *?[*]const u32, n_arg: usize, st: ?*c_uint) callconv(.c) usize {
    _ = st;
    const ws_start: [*]const u32 = ws.* orelse return 0;
    var ws2 = ws_start;
    var buf: [4]u8 = undefined;

    if (s == null) {
        var count: usize = 0;
        while (ws2[0] != 0) {
            if (ws2[0] < 0x80) {
                count += 1;
            } else {
                const l = wcrtomb(&buf, ws2[0], null);
                if (l == size_t_minus1) return size_t_minus1;
                count += l;
            }
            ws2 += 1;
        }
        return count;
    }

    var dst = s.?;
    var n = n_arg;
    const N = n;

    while (n >= 4) {
        if (ws2[0] -% 1 >= 0x7f) {
            if (ws2[0] == 0) {
                dst[0] = 0;
                ws.* = null;
                return N - n;
            }
            const l = wcrtomb(dst, ws2[0], null);
            if (l == size_t_minus1) return size_t_minus1;
            dst += l;
            n -= l;
        } else {
            dst[0] = @truncate(ws2[0]);
            dst += 1;
            n -= 1;
        }
        ws2 += 1;
    }
    while (n != 0) {
        if (ws2[0] -% 1 >= 0x7f) {
            if (ws2[0] == 0) {
                dst[0] = 0;
                ws.* = null;
                return N - n;
            }
            const l = wcrtomb(&buf, ws2[0], null);
            if (l == size_t_minus1) return size_t_minus1;
            if (l > n) return N - n;
            _ = wcrtomb(dst, ws2[0], null);
            dst += l;
            n -= l;
        } else {
            dst[0] = @truncate(ws2[0]);
            dst += 1;
            n -= 1;
        }
        ws2 += 1;
    }
    ws.* = ws2;
    return N;
}

// ---------------------------------------------------------------------------
// mbrtoc16 — UTF-8 to UTF-16 with surrogate handling
// ---------------------------------------------------------------------------

fn mbrtoc16(pc16: ?*u16, s: ?[*]const u8, n: usize, ps: ?*c_uint) callconv(.c) usize {
    const pending: *c_uint = ps orelse &mbrtoc16_internal_state;

    if (s == null) return mbrtoc16(null, @as([*]const u8, @ptrCast("")), 1, pending);

    // Nonzero states without high bit are pending surrogates.
    const pending_signed: i32 = @bitCast(pending.*);
    if (pending_signed > 0) {
        if (pc16) |p| p.* = @truncate(pending.*);
        pending.* = 0;
        return size_t_minus3;
    }

    var wc: u32 = 0;
    const ret = mbrtowc(&wc, s, n, pending);
    if (ret <= 4) {
        if (wc >= 0x10000) {
            pending.* = (wc & 0x3ff) + 0xdc00;
            wc = 0xd7c0 + (wc >> 10);
        }
        if (pc16) |p| p.* = @truncate(wc);
    }
    return ret;
}

// ---------------------------------------------------------------------------
// c16rtomb — UTF-16 to UTF-8 with surrogate handling
// ---------------------------------------------------------------------------

fn c16rtomb(s: ?[*]u8, c16: u16, ps: ?*c_uint) callconv(.c) usize {
    const x: *c_uint = ps orelse &c16rtomb_internal_state;

    if (s == null) {
        if (x.* != 0) {
            x.* = 0;
            setErrno();
            return size_t_minus1;
        }
        return 1;
    }

    const c16_u32: u32 = c16;
    if (x.* == 0 and c16_u32 -% 0xd800 < 0x400) {
        x.* = (c16_u32 - 0xd7c0) << 10;
        return 0;
    }

    var wc: u32 = undefined;
    if (x.* != 0) {
        if (c16_u32 -% 0xdc00 >= 0x400) {
            x.* = 0;
            setErrno();
            return size_t_minus1;
        }
        wc = x.* + c16_u32 - 0xdc00;
        x.* = 0;
    } else {
        wc = c16_u32;
    }
    return wcrtomb(s, wc, null);
}

// ---------------------------------------------------------------------------
// mbrtoc32 — UTF-8 to UTF-32 wrapper
// ---------------------------------------------------------------------------

fn mbrtoc32(pc32: ?*u32, s: ?[*]const u8, n: usize, ps: ?*c_uint) callconv(.c) usize {
    const st: *c_uint = ps orelse &mbrtoc32_internal_state;
    if (s == null) return mbrtoc32(null, @as([*]const u8, @ptrCast("")), 1, st);
    var wc: u32 = 0;
    const ret = mbrtowc(&wc, s, n, st);
    if (ret <= 4) {
        if (pc32) |p| p.* = wc;
    }
    return ret;
}

// ---------------------------------------------------------------------------
// c32rtomb — UTF-32 to UTF-8 wrapper
// ---------------------------------------------------------------------------

fn c32rtomb(s: ?[*]u8, c32: u32, ps: ?*c_uint) callconv(.c) usize {
    return wcrtomb(s, c32, ps);
}

// ---------------------------------------------------------------------------
// mbsnrtowcs — batch UTF-8 to wchar_t with byte limit
// ---------------------------------------------------------------------------

fn mbsnrtowcs(wcs: ?[*]u32, src: *?[*]const u8, n_arg: usize, wn_arg: usize, st: ?*c_uint) callconv(.c) usize {
    var wbuf: [256]u32 = undefined;
    var cnt: usize = 0;
    var s: [*]const u8 = src.* orelse return 0;
    var n = n_arg;
    var wn = wn_arg;

    var ws: [*]u32 = undefined;
    if (wcs == null) {
        ws = &wbuf;
        wn = wbuf.len;
    } else {
        ws = wcs.?;
    }

    // Use mbsrtowcs in chunks where n/4 >= wn or n/4 > 32
    while (n != 0 and wn != 0) {
        const n2 = n / 4;
        if (n2 < wn and n2 <= 32) break;
        const use_n2 = if (n2 >= wn) wn else n2;
        var tmp_s: ?[*]const u8 = s;
        const l = mbsrtowcs(ws, &tmp_s, use_n2, st);
        if (l == size_t_minus1) {
            cnt = l;
            wn = 0;
            break;
        }
        if (wcs != null) {
            ws += l;
            wn -= l;
        }
        if (tmp_s) |new_s| {
            const advanced = @intFromPtr(new_s) - @intFromPtr(s);
            n -= advanced;
            s = new_s;
        } else {
            n = 0;
        }
        cnt += l;
    }

    if (n != 0) {
        var s_opt: ?[*]const u8 = s;
        while (wn != 0 and n != 0) {
            const l = mbrtowc(@ptrCast(ws), s_opt, n, st);
            if (l +% 2 <= 2) {
                if (l == size_t_minus1) {
                    cnt = l;
                    break;
                }
                if (l == 0) {
                    s_opt = null;
                    break;
                }
                // l == (size_t)-2: partial character, roll back
                if (st) |stp| stp.* = 0;
                break;
            }
            s = s_opt.? + l;
            s_opt = s;
            n -= l;
            ws += 1;
            wn -= 1;
            cnt += 1;
        }
        if (wcs != null) {
            src.* = s_opt;
        }
    } else {
        if (wcs != null) {
            src.* = null;
        }
    }
    return cnt;
}

// ---------------------------------------------------------------------------
// wcsnrtombs — batch wchar_t to UTF-8 with wchar_t limit
// ---------------------------------------------------------------------------

fn wcsnrtombs(dst: ?[*]u8, wcs: *?[*]const u32, wn_arg: usize, n_arg: usize, st: ?*c_uint) callconv(.c) usize {
    _ = st;
    var ws: [*]const u32 = wcs.* orelse return 0;
    var cnt: usize = 0;
    var n = n_arg;
    var wn = wn_arg;
    var d = dst;

    if (d == null) n = 0;

    while (wn != 0) {
        var tmp: [MB_LEN_MAX]u8 = undefined;
        const write_dst = if (n < MB_LEN_MAX) @as([*]u8, &tmp) else d.?;
        const l = wcrtomb(write_dst, ws[0], null);
        if (l == size_t_minus1) {
            cnt = size_t_minus1;
            break;
        }
        if (d != null) {
            if (n < MB_LEN_MAX) {
                if (l > n) break;
                @memcpy(d.?[0..l], tmp[0..l]);
            }
            d = d.? + l;
            n -= l;
        }
        if (ws[0] == 0) {
            ws = undefined;
            break;
        }
        ws += 1;
        wn -= 1;
        cnt += l;
    }
    if (dst != null) wcs.* = ws;
    return cnt;
}
