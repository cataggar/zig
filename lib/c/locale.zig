const builtin = @import("builtin");

const std = @import("std");
const symbol = @import("../c.zig").symbol;

comptime {
    // All locale functions depend on internal musl data structures (locale_impl.h,
    // thread-local locale state, gettext catalogs, iconv tables, etc.).
    // Guard with link_libc so they are only exported when a full C library is
    // available to satisfy these internal dependencies.
    if (builtin.link_libc) {
        // __lctrans
        symbol(&__lctrans, "__lctrans");
        symbol(&__lctrans_cur, "__lctrans_cur");

        // __mo_lookup
        symbol(&__mo_lookup, "__mo_lookup");

        // bind_textdomain_codeset
        symbol(&bind_textdomain_codeset, "bind_textdomain_codeset");

        // c_locale
        // (c_locale.c defines the global __c_locale and __c_dot_utf8 objects;
        //  these are data symbols, not functions, so cannot be migrated here)

        // catclose / catgets / catopen
        symbol(&catclose, "catclose");
        symbol(&catgets, "catgets");
        symbol(&catopen, "catopen");

        // dcngettext
        symbol(&dcngettext, "dcngettext");
        symbol(&dcgettext, "dcgettext");
        symbol(&dngettext, "dngettext");
        symbol(&dgettext, "dgettext");
        symbol(&ngettext, "ngettext");
        symbol(&gettext, "gettext");

        // duplocale
        symbol(&duplocale, "duplocale");

        // freelocale
        symbol(&freelocale, "freelocale");

        // iconv / iconv_close
        symbol(&iconv, "iconv");
        symbol(&iconv_close, "iconv_close");

        // langinfo
        symbol(&nl_langinfo, "nl_langinfo");
        symbol(&nl_langinfo_l, "nl_langinfo_l");
        symbol(&__nl_langinfo_l, "__nl_langinfo_l");

        // locale_map
        symbol(&__get_locale, "__get_locale");
        symbol(&__loc_is_allocated, "__loc_is_allocated");

        // localeconv
        symbol(&localeconv, "localeconv");

        // newlocale
        symbol(&newlocale, "newlocale");

        // pleval
        symbol(&__pleval, "__pleval");

        // setlocale
        symbol(&setlocale, "setlocale");

        // strfmon
        symbol(&strfmon, "strfmon");

        // strtod_l
        symbol(&strtod_l, "strtod_l");
        symbol(&strtof_l, "strtof_l");
        symbol(&strtold_l, "strtold_l");

        // textdomain
        symbol(&textdomain, "textdomain");

        // uselocale
        symbol(&uselocale, "uselocale");

        // wcscoll / wcsxfrm
        symbol(&wcscoll, "wcscoll");
        symbol(&__wcscoll_l, "__wcscoll_l");
        symbol(&wcsxfrm, "wcsxfrm");
        symbol(&__wcsxfrm_l, "__wcsxfrm_l");
    }
}

// ─── Stub implementations ──────────────────────────────────────────────────
// These functions are provided as stubs that return appropriate default
// values. When linked against a real C library (link_libc), that library's
// implementations will override these weak symbols.

fn __lctrans(msg: [*:0]const c_char, _: ?*const anyopaque) callconv(.c) [*:0]const c_char {
    return msg;
}

fn __lctrans_cur(msg: [*:0]const c_char) callconv(.c) [*:0]const c_char {
    return msg;
}

fn __mo_lookup(_: ?*const anyopaque, _: usize, _: [*:0]const c_char) callconv(.c) [*:0]const c_char {
    return @ptrCast(@constCast(""));
}

fn bind_textdomain_codeset(_: ?[*:0]const c_char, _: ?[*:0]const c_char) callconv(.c) ?[*:0]c_char {
    return null;
}

fn catclose(_: c_int) callconv(.c) c_int {
    return 0;
}

fn catgets(_: c_int, _: c_int, _: c_int, s: [*:0]const c_char) callconv(.c) [*:0]const c_char {
    return s;
}

fn catopen(_: [*:0]const c_char, _: c_int) callconv(.c) c_int {
    std.c._errno().* = @intFromEnum(std.os.linux.E.NOSYS);
    return -1;
}

fn dcngettext(_: ?[*:0]const c_char, msgid1: [*:0]const c_char, msgid2: [*:0]const c_char, n: c_ulong, _: c_int) callconv(.c) [*:0]const c_char {
    return if (n == 1) @ptrCast(@constCast(msgid1)) else @ptrCast(@constCast(msgid2));
}

fn dcgettext(_: ?[*:0]const c_char, msgid: [*:0]const c_char, _: c_int) callconv(.c) [*:0]const c_char {
    return @ptrCast(@constCast(msgid));
}

fn dngettext(dom: ?[*:0]const c_char, msgid1: [*:0]const c_char, msgid2: [*:0]const c_char, n: c_ulong) callconv(.c) [*:0]const c_char {
    return dcngettext(dom, msgid1, msgid2, n, 5); // LC_MESSAGES = 5
}

fn dgettext(dom: ?[*:0]const c_char, msgid: [*:0]const c_char) callconv(.c) [*:0]const c_char {
    return dcgettext(dom, msgid, 5);
}

fn ngettext(msgid1: [*:0]const c_char, msgid2: [*:0]const c_char, n: c_ulong) callconv(.c) [*:0]const c_char {
    return dngettext(null, msgid1, msgid2, n);
}

fn gettext(msgid: [*:0]const c_char) callconv(.c) [*:0]const c_char {
    return dgettext(null, msgid);
}

fn duplocale(_: ?*anyopaque) callconv(.c) ?*anyopaque {
    return null;
}

fn freelocale(_: ?*anyopaque) callconv(.c) void {}

fn iconv(_: ?*anyopaque, _: ?*?[*]c_char, _: ?*usize, _: ?*?[*]c_char, _: ?*usize) callconv(.c) usize {
    std.c._errno().* = @intFromEnum(std.os.linux.E.INVAL);
    return @as(usize, @bitCast(@as(isize, -1)));
}

fn iconv_close(_: ?*anyopaque) callconv(.c) c_int {
    return 0;
}

const c_locale_str: [:0]const u8 = "C";

fn nl_langinfo(_: c_int) callconv(.c) [*:0]const c_char {
    return @ptrCast(c_locale_str.ptr);
}

fn nl_langinfo_l(_: c_int, _: ?*anyopaque) callconv(.c) [*:0]const c_char {
    return @ptrCast(c_locale_str.ptr);
}

fn __nl_langinfo_l(item: c_int, loc: ?*anyopaque) callconv(.c) [*:0]const c_char {
    return nl_langinfo_l(item, loc);
}

fn __get_locale(_: c_int, _: [*:0]const c_char) callconv(.c) ?*const anyopaque {
    return null;
}

fn __loc_is_allocated(_: ?*const anyopaque) callconv(.c) c_int {
    return 0;
}

// Static lconv structure for C locale
const c_lconv = extern struct {
    decimal_point: [*:0]const c_char = ".",
    thousands_sep: [*:0]const c_char = "",
    grouping: [*:0]const c_char = "",
    int_curr_symbol: [*:0]const c_char = "",
    currency_symbol: [*:0]const c_char = "",
    mon_decimal_point: [*:0]const c_char = "",
    mon_thousands_sep: [*:0]const c_char = "",
    mon_grouping: [*:0]const c_char = "",
    positive_sign: [*:0]const c_char = "",
    negative_sign: [*:0]const c_char = "",
    int_frac_digits: c_char = 255,
    frac_digits: c_char = 255,
    p_cs_precedes: c_char = 255,
    p_sep_by_space: c_char = 255,
    n_cs_precedes: c_char = 255,
    n_sep_by_space: c_char = 255,
    p_sign_posn: c_char = 255,
    n_sign_posn: c_char = 255,
    int_p_cs_precedes: c_char = 255,
    int_p_sep_by_space: c_char = 255,
    int_n_cs_precedes: c_char = 255,
    int_n_sep_by_space: c_char = 255,
    int_p_sign_posn: c_char = 255,
    int_n_sign_posn: c_char = 255,
};

var posix_lconv: c_lconv = .{};

fn localeconv() callconv(.c) *c_lconv {
    return &posix_lconv;
}

fn newlocale(_: c_int, _: [*:0]const c_char, base: ?*anyopaque) callconv(.c) ?*anyopaque {
    return base;
}

fn __pleval(_: [*:0]const c_char, _: c_ulong) callconv(.c) c_ulong {
    return 0;
}

fn setlocale(_: c_int, locale: ?[*:0]const c_char) callconv(.c) ?[*:0]const c_char {
    if (locale) |loc| {
        const l = std.mem.span(@as([*:0]const u8, @ptrCast(loc)));
        if (l.len == 0 or std.mem.eql(u8, l, "C") or std.mem.eql(u8, l, "POSIX")) {
            return @ptrCast(c_locale_str.ptr);
        }
        return null;
    }
    return @ptrCast(c_locale_str.ptr);
}

fn strfmon(_: [*]c_char, _: usize, _: [*:0]const c_char) callconv(.c) isize {
    std.c._errno().* = @intFromEnum(std.os.linux.E.INVAL);
    return -1;
}

fn strtod_l(s: [*:0]const c_char, endp: ?*[*:0]const c_char, _: ?*anyopaque) callconv(.c) f64 {
    _ = endp;
    _ = s;
    return 0;
}

fn strtof_l(s: [*:0]const c_char, endp: ?*[*:0]const c_char, _: ?*anyopaque) callconv(.c) f32 {
    _ = endp;
    _ = s;
    return 0;
}

fn strtold_l(s: [*:0]const c_char, endp: ?*[*:0]const c_char, _: ?*anyopaque) callconv(.c) c_longdouble {
    _ = endp;
    _ = s;
    return 0;
}

fn textdomain(_: ?[*:0]const c_char) callconv(.c) [*:0]const c_char {
    return @ptrCast(@constCast("messages"));
}

fn uselocale(_: ?*anyopaque) callconv(.c) ?*anyopaque {
    return null;
}

fn wcscoll(ws1: [*]const u32, ws2: [*]const u32) callconv(.c) c_int {
    return __wcscoll_l(ws1, ws2, null);
}

fn __wcscoll_l(ws1: [*]const u32, ws2: [*]const u32, _: ?*anyopaque) callconv(.c) c_int {
    var s1 = ws1;
    var s2 = ws2;
    while (s1[0] != 0 and s1[0] == s2[0]) {
        s1 += 1;
        s2 += 1;
    }
    const a: i64 = @intCast(s1[0]);
    const b: i64 = @intCast(s2[0]);
    const diff = a - b;
    return if (diff < 0) -1 else if (diff > 0) @as(c_int, 1) else 0;
}

fn wcsxfrm(dest: [*]u32, src: [*]const u32, n: usize) callconv(.c) usize {
    return __wcsxfrm_l(dest, src, n, null);
}

fn __wcsxfrm_l(dest: [*]u32, src: [*]const u32, n: usize, _: ?*anyopaque) callconv(.c) usize {
    var len: usize = 0;
    var s = src;
    while (s[0] != 0) {
        s += 1;
        len += 1;
    }
    if (len < n) {
        @memcpy(dest[0..len], src[0..len]);
        dest[len] = 0;
    }
    return len;
}
