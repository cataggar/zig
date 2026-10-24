const std = @import("std");
const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

const wchar_t = c_int;
const nl_item = c_int;
const nl_catd = ?*anyopaque;
const iconv_t = ?*anyopaque;

const LC_CTYPE: c_int = 0;
const LC_NUMERIC: c_int = 1;
const LC_TIME: c_int = 2;
const LC_COLLATE: c_int = 3;
const LC_MONETARY: c_int = 4;
const LC_MESSAGES: c_int = 5;
const LC_ALL: c_int = 6;

const LOCALE_NAME_MAX = 23;
const NAME_MAX = 255;
const PATH_MAX = 4096;

const LocaleMap = extern struct {
    map: ?*const anyopaque,
    map_size: usize,
    name: [LOCALE_NAME_MAX + 1]u8,
    next: ?*const LocaleMap,
};

const LocaleStruct = extern struct {
    cat: [6]?*const LocaleMap,
};

const locale_t = ?*align(1) LocaleStruct;
const LC_GLOBAL_LOCALE: locale_t = @ptrFromInt(std.math.maxInt(usize));

const LibC = extern struct {
    can_do_threads: u8,
    threaded: u8,
    secure: u8,
    need_locks: i8,
    threads_minus_1: c_int,
    auxv: ?[*]usize,
    tls_head: ?*anyopaque,
    tls_size: usize,
    tls_align: usize,
    tls_cnt: usize,
    page_size: usize,
    global_locale: LocaleStruct,
};

extern var __libc: LibC;
extern "c" fn __lock(lock: *volatile c_int) callconv(.c) void;
extern "c" fn __unlock(lock: *volatile c_int) callconv(.c) void;
extern "c" fn pthread_self() callconv(.c) *anyopaque;
extern "c" fn __map_file(pathname: [*:0]const u8, size: *usize) callconv(.c) ?[*]const u8;
extern "c" fn munmap(addr: *anyopaque, len: usize) callconv(.c) c_int;
extern "c" fn getenv(name: [*:0]const u8) callconv(.c) ?[*:0]u8;
extern "c" fn strcmp(s1: [*:0]const u8, s2: [*:0]const u8) callconv(.c) c_int;
extern "c" fn strncmp(s1: [*]const u8, s2: [*]const u8, n: usize) callconv(.c) c_int;
extern "c" fn strlen(s: [*:0]const u8) callconv(.c) usize;
extern "c" fn strnlen(s: [*]const u8, maxlen: usize) callconv(.c) usize;
extern "c" fn strchr(s: [*:0]const u8, c: c_int) callconv(.c) ?[*:0]u8;
extern "c" fn __strchrnul(s: [*:0]const u8, c: c_int) callconv(.c) [*:0]u8;
extern "c" fn strcspn(s: [*:0]const u8, reject: [*:0]const u8) callconv(.c) usize;
extern "c" fn strcasecmp(s1: [*:0]const u8, s2: [*:0]const u8) callconv(.c) c_int;
extern "c" fn strtoul(nptr: [*:0]const u8, endptr: ?*[*:0]u8, base: c_int) callconv(.c) c_ulong;
extern "c" fn snprintf(str: [*]u8, size: usize, format: [*:0]const u8, ...) callconv(.c) c_int;
extern "c" fn bsearch(key: *const anyopaque, base: *const anyopaque, nmemb: usize, size: usize, compar: *const fn (*const anyopaque, *const anyopaque) callconv(.c) c_int) callconv(.c) ?*anyopaque;
extern "c" fn strtof(nptr: [*:0]const u8, endptr: ?*[*:0]u8) callconv(.c) f32;
extern "c" fn strtod(nptr: [*:0]const u8, endptr: ?*[*:0]u8) callconv(.c) f64;
extern "c" fn strtold(nptr: [*:0]const u8, endptr: ?*[*:0]u8) callconv(.c) c_longdouble;
extern "c" fn wcscmp(s1: [*:0]const wchar_t, s2: [*:0]const wchar_t) callconv(.c) c_int;
extern "c" fn wcslen(s: [*:0]const wchar_t) callconv(.c) usize;
extern "c" fn wmemcpy(d: [*]wchar_t, s: [*]const wchar_t, n: usize) callconv(.c) [*]wchar_t;

const arch = builtin.target.cpu.arch;
const ptr_size = @sizeOf(usize);
const tls_above_tp = switch (arch) {
    .aarch64, .aarch64_be, .arm, .armeb, .thumb, .thumbeb, .riscv64, .riscv32, .mips, .mipsel, .mips64, .mips64el, .powerpc, .powerpcle, .powerpc64, .powerpc64le, .loongarch64, .m68k => true,
    else => false,
};
const part1_size: usize = if (tls_above_tp) 4 * ptr_size else 6 * ptr_size;
const map_base_off: usize = if (ptr_size == 8) 24 else 20;
const off_locale = part1_size + map_base_off + 11 * ptr_size + 8;

inline fn currentLocaleSlot() **LocaleStruct {
    const self = @intFromPtr(pthread_self());
    return @ptrFromInt(self + off_locale);
}

inline fn currentLocale() *LocaleStruct {
    return currentLocaleSlot().*;
}

// ============================================================================
// c_locale.c
// ============================================================================

const empty_mo = [_]u32{ 0x950412de, 0, 0xffffffff, 0xffffffff, 0xffffffff };

const __c_dot_utf8: LocaleMap = .{
    .map = @ptrCast(&empty_mo),
    .map_size = @sizeOf(@TypeOf(empty_mo)),
    .name = "C.UTF-8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*,
    .next = null,
};

const __c_locale: LocaleStruct = .{
    .cat = .{ null, null, null, null, null, null },
};

const __c_dot_utf8_locale: LocaleStruct = .{
    .cat = .{ &__c_dot_utf8, null, null, null, null, null },
};

// ============================================================================
// __mo_lookup.c
// ============================================================================

inline fn swapc(x: u32, c: bool) u32 {
    return if (c) @byteSwap(x) else x;
}

fn __mo_lookup(p: *const anyopaque, size: usize, s: [*:0]const u8) callconv(.c) ?[*:0]const u8 {
    if (size < 20) return null;
    const mo: [*]const u32 = @ptrCast(@alignCast(p));
    const bytes: [*]const u8 = @ptrCast(p);
    const sw = mo[0] != 0x950412de;
    var b: u32 = 0;
    var n: u32 = swapc(mo[2], sw);
    var o: u32 = swapc(mo[3], sw);
    var t: u32 = swapc(mo[4], sw);
    if (n >= size / 4 or o >= size - 4 * @as(usize, n) or t >= size - 4 * @as(usize, n) or ((o | t) % 4) != 0)
        return null;
    o /= 4;
    t /= 4;
    while (true) {
        const idx = b + n / 2;
        const ol = swapc(mo[o + 2 * idx], sw);
        const os = swapc(mo[o + 2 * idx + 1], sw);
        if (os >= size or ol >= size - os or bytes[os + ol] != 0)
            return null;
        const sign = strcmp(s, @ptrCast(bytes + os));
        if (sign == 0) {
            const tl = swapc(mo[t + 2 * idx], sw);
            const ts = swapc(mo[t + 2 * idx + 1], sw);
            if (ts >= size or tl >= size - ts or bytes[ts + tl] != 0)
                return null;
            return @ptrCast(bytes + ts);
        } else if (n == 1) {
            return null;
        } else if (sign < 0) {
            n /= 2;
        } else {
            b += n / 2;
            n -= n / 2;
        }
    }
}

// ============================================================================
// locale_map.c & __lctrans.c
// ============================================================================

var __locale_lock: c_int = 0;

const envvars = [6][12:0]u8{
    "LC_CTYPE\x00\x00\x00\x00".*,
    "LC_NUMERIC\x00\x00".*,
    "LC_TIME\x00\x00\x00\x00\x00".*,
    "LC_COLLATE\x00\x00".*,
    "LC_MONETARY\x00".*,
    "LC_MESSAGES\x00".*,
};

fn __lctrans_impl(msg: [*:0]const u8, lm: ?*const LocaleMap) callconv(.c) [*:0]const u8 {
    var trans: ?[*:0]const u8 = null;
    if (lm) |m| {
        if (m.map) |map| {
            trans = __mo_lookup(map, m.map_size, msg);
        }
    }
    return trans orelse msg;
}

fn __lctrans(msg: [*:0]const u8, lm: ?*const LocaleMap) callconv(.c) [*:0]const u8 {
    return __lctrans_impl(msg, lm);
}

fn __lctrans_cur(msg: [*:0]const u8) callconv(.c) [*:0]const u8 {
    return __lctrans_impl(msg, currentLocale().cat[@intCast(LC_MESSAGES)]);
}

var loc_head: ?*const LocaleMap = null;

const LOC_MAP_FAILED: ?*align(1) const LocaleMap = @ptrFromInt(std.math.maxInt(usize));

fn __get_locale(cat: c_int, val_in: [*:0]const u8) callconv(.c) ?*align(1) const LocaleMap {
    var val = val_in;
    var p: ?*const LocaleMap = null;
    var new: ?*LocaleMap = null;
    var path: ?[*:0]const u8 = null;
    var z: [*:0]const u8 = undefined;
    var buf: [256]u8 = undefined;
    var l: usize = 0;
    var n: usize = 0;

    if (val[0] == 0) {
        if (getenv("LC_ALL")) |v| if (v[0] != 0) {
            val = v;
        };
        if (val[0] == 0) {
            if (getenv(&envvars[@intCast(cat)])) |v| if (v[0] != 0) {
                val = v;
            };
        }
        if (val[0] == 0) {
            if (getenv("LANG")) |v| if (v[0] != 0) {
                val = v;
            };
        }
        if (val[0] == 0) val = "C.UTF-8";
    }

    n = 0;
    while (n < LOCALE_NAME_MAX and val[n] != 0 and val[n] != '/') : (n += 1) {}
    if (val[0] == '.' or val[n] != 0) val = "C.UTF-8";
    const builtin_c = (val[0] == 'C' and val[1] == 0) or
        strcmp(val, "C.UTF-8") == 0 or
        strcmp(val, "POSIX") == 0;

    if (builtin_c) {
        if (cat == LC_CTYPE and val[1] == '.')
            return &__c_dot_utf8;
        return null;
    }

    p = loc_head;
    while (p) |cur| : (p = cur.next) {
        if (strcmp(@ptrCast(&cur.name), val) == 0) return cur;
    }

    if (__libc.secure == 0) path = getenv("MUSL_LOCPATH");

    if (path) |path_start| {
        var cur_path: [*:0]const u8 = path_start;
        while (cur_path[0] != 0) : (cur_path = z + @intFromBool(z[0] != 0)) {
            z = __strchrnul(cur_path, ':');
            l = @intFromPtr(z) - @intFromPtr(cur_path);
            if (l >= @sizeOf(@TypeOf(buf)) - n - 2) continue;
            @memcpy(buf[0..l], cur_path[0..l]);
            buf[l] = '/';
            @memcpy(buf[l + 1 ..][0..n], val[0..n]);
            buf[l + 1 + n] = 0;
            var map_size: usize = 0;
            if (__map_file(@ptrCast(&buf), &map_size)) |map| {
                new = @ptrCast(@alignCast(std.c.malloc(@sizeOf(LocaleMap))));
                if (new == null) {
                    _ = munmap(@ptrCast(@constCast(map)), map_size);
                    break;
                }
                new.?.map = @ptrCast(map);
                new.?.map_size = map_size;
                @memcpy(new.?.name[0..n], val[0..n]);
                new.?.name[n] = 0;
                new.?.next = loc_head;
                loc_head = new;
                break;
            }
        }
    }

    if (new == null and (new_blk: {
        new = @ptrCast(@alignCast(std.c.malloc(@sizeOf(LocaleMap))));
        break :new_blk new != null;
    })) {
        new.?.map = __c_dot_utf8.map;
        new.?.map_size = __c_dot_utf8.map_size;
        @memcpy(new.?.name[0..n], val[0..n]);
        new.?.name[n] = 0;
        new.?.next = loc_head;
        loc_head = new;
    }

    if (new == null and cat == LC_CTYPE) return &__c_dot_utf8;

    return new;
}

// ============================================================================
// setlocale.c
// ============================================================================

var setlocale_buf: [6 * (LOCALE_NAME_MAX + 1)]u8 = undefined;

fn setlocaleImpl(cat: c_int, name: ?[*:0]const u8) callconv(.c) ?[*:0]u8 {
    if (@as(c_uint, @bitCast(cat)) > @as(c_uint, LC_ALL)) return null;

    __lock(&__locale_lock);

    if (cat == LC_ALL) {
        if (name) |nm| {
            var tmp_locale: LocaleStruct = undefined;
            var part: [LOCALE_NAME_MAX + 1]u8 = "C.UTF-8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*;
            var p: [*:0]const u8 = nm;
            for (0..6) |i| {
                const z = __strchrnul(p, ';');
                const len = @intFromPtr(z) - @intFromPtr(p);
                if (len <= LOCALE_NAME_MAX) {
                    @memcpy(part[0..len], p[0..len]);
                    part[len] = 0;
                    if (z[0] != 0) p = z + 1;
                }
                const lm = __get_locale(@intCast(i), @ptrCast(&part));
                if (lm == LOC_MAP_FAILED) {
                    __unlock(&__locale_lock);
                    return null;
                }
                tmp_locale.cat[i] = if (lm) |m| @alignCast(m) else null;
            }
            __libc.global_locale = tmp_locale;
        }
        var s: [*]u8 = &setlocale_buf;
        var part: [*:0]const u8 = "C";
        var same: usize = 0;
        for (0..6) |i| {
            const lm = __libc.global_locale.cat[i];
            if (lm == __libc.global_locale.cat[0]) same += 1;
            part = if (lm) |m| @ptrCast(&m.name) else "C";
            const l = strlen(part);
            @memcpy(s[0..l], part[0..l]);
            s[l] = ';';
            s += l + 1;
        }
        (s - 1)[0] = 0;
        __unlock(&__locale_lock);
        return if (same == 6) @constCast(part) else @ptrCast(&setlocale_buf);
    }

    var lm: ?*const LocaleMap = null;
    if (name) |nm| {
        const raw_lm = __get_locale(cat, nm);
        if (raw_lm == LOC_MAP_FAILED) {
            __unlock(&__locale_lock);
            return null;
        }
        lm = if (raw_lm) |m| @alignCast(m) else null;
        __libc.global_locale.cat[@intCast(cat)] = lm;
    } else {
        lm = __libc.global_locale.cat[@intCast(cat)];
    }
    const ret: [*:0]u8 = if (lm) |m| @ptrCast(@constCast(&m.name)) else @constCast("C");

    __unlock(&__locale_lock);
    return ret;
}

// ============================================================================
// newlocale.c, duplocale.c, freelocale.c, uselocale.c
// ============================================================================

var default_locale_init_done: c_int = 0;
var default_locale: LocaleStruct = undefined;
var default_ctype_locale: LocaleStruct = undefined;

fn __loc_is_allocated(loc: locale_t) bool {
    return loc != null and loc != LC_GLOBAL_LOCALE and
        loc != @as(locale_t, @constCast(&__c_locale)) and
        loc != @as(locale_t, @constCast(&__c_dot_utf8_locale)) and
        loc != @as(locale_t, &default_locale) and
        loc != @as(locale_t, &default_ctype_locale);
}

fn do_newlocale(mask: c_int, name: [*:0]const u8, loc_in: locale_t) locale_t {
    var tmp: LocaleStruct = undefined;

    for (0..6) |i| {
        const bit = @as(c_int, 1) << @intCast(i);
        if ((mask & bit) == 0 and loc_in != null) {
            tmp.cat[i] = @as(*const LocaleStruct, @alignCast(loc_in.?)).cat[i];
        } else {
            const raw_lm = __get_locale(@intCast(i), if ((mask & bit) != 0) name else "");
            if (raw_lm == LOC_MAP_FAILED) return null;
            tmp.cat[i] = if (raw_lm) |m| @alignCast(m) else null;
        }
    }

    if (__loc_is_allocated(loc_in)) {
        const loc_aligned: *LocaleStruct = @alignCast(loc_in.?);
        loc_aligned.* = tmp;
        return loc_aligned;
    }

    if (std.mem.eql(u8, std.mem.asBytes(&tmp), std.mem.asBytes(&__c_locale)))
        return @constCast(&__c_locale);
    if (std.mem.eql(u8, std.mem.asBytes(&tmp), std.mem.asBytes(&__c_dot_utf8_locale)))
        return @constCast(&__c_dot_utf8_locale);

    if (default_locale_init_done == 0) {
        for (0..6) |i| {
            const raw_lm = __get_locale(@intCast(i), "");
            default_locale.cat[i] = if (raw_lm != null and raw_lm != LOC_MAP_FAILED) @alignCast(raw_lm.?) else null;
        }
        default_ctype_locale.cat = .{ default_locale.cat[0], null, null, null, null, null };
        default_locale_init_done = 1;
    }
    if (std.mem.eql(u8, std.mem.asBytes(&tmp), std.mem.asBytes(&default_locale)))
        return &default_locale;
    if (std.mem.eql(u8, std.mem.asBytes(&tmp), std.mem.asBytes(&default_ctype_locale)))
        return &default_ctype_locale;

    const allocated = @as(?*LocaleStruct, @ptrCast(@alignCast(std.c.malloc(@sizeOf(LocaleStruct))))) orelse return null;
    allocated.* = tmp;
    return allocated;
}

fn __newlocale(mask: c_int, name: ?[*:0]const u8, loc_in: locale_t) callconv(.c) locale_t {
    const nm = name orelse return null;
    __lock(&__locale_lock);
    const ret = do_newlocale(mask, nm, loc_in);
    __unlock(&__locale_lock);
    return ret;
}

fn __duplocale(old: locale_t) callconv(.c) locale_t {
    const new = @as(?*LocaleStruct, @ptrCast(@alignCast(std.c.malloc(@sizeOf(LocaleStruct))))) orelse return null;
    if (old == LC_GLOBAL_LOCALE) {
        new.* = __libc.global_locale;
    } else if (old) |o| {
        new.* = @as(*const LocaleStruct, @alignCast(o)).*;
    } else {
        new.* = std.mem.zeroes(LocaleStruct);
    }
    return new;
}

fn __freelocale(l: locale_t) callconv(.c) void {
    if (__loc_is_allocated(l)) std.c.free(@ptrCast(l));
}

fn __uselocale(new: locale_t) callconv(.c) locale_t {
    const loc_slot = currentLocaleSlot();
    const old = loc_slot.*;
    const global = &__libc.global_locale;
    if (new) |n| {
        loc_slot.* = if (n == LC_GLOBAL_LOCALE) global else @alignCast(n);
    }
    return if (old == global) LC_GLOBAL_LOCALE else old;
}

// ============================================================================
// langinfo.c
// ============================================================================

const c_time = "Sun\x00Mon\x00Tue\x00Wed\x00Thu\x00Fri\x00Sat\x00" ++
    "Sunday\x00Monday\x00Tuesday\x00Wednesday\x00" ++
    "Thursday\x00Friday\x00Saturday\x00" ++
    "Jan\x00Feb\x00Mar\x00Apr\x00May\x00Jun\x00" ++
    "Jul\x00Aug\x00Sep\x00Oct\x00Nov\x00Dec\x00" ++
    "January\x00February\x00March\x00April\x00" ++
    "May\x00June\x00July\x00August\x00" ++
    "September\x00October\x00November\x00December\x00" ++
    "AM\x00PM\x00" ++
    "%a %b %e %T %Y\x00" ++
    "%m/%d/%y\x00" ++
    "%H:%M:%S\x00" ++
    "%I:%M:%S %p\x00" ++
    "\x00" ++
    "\x00" ++
    "%m/%d/%y\x00" ++
    "0123456789\x00" ++
    "%a %b %e %T %Y\x00" ++
    "%H:%M:%S";

const c_messages = "^[yY]\x00^[nN]\x00yes\x00no";
const c_numeric = ".\x00";

fn __nl_langinfo_l(item: nl_item, loc: locale_t) callconv(.c) [*:0]u8 {
    const uitem: c_uint = @bitCast(item);
    const cat: c_int = @intCast(uitem >> 16);
    var idx: c_uint = uitem & 65535;
    var str: [*:0]const u8 = undefined;

    if (item == 14) { // CODESET
        const lm = if (loc) |l| l.cat[0] else null;
        return if (lm != null) @constCast("UTF-8") else @constCast("ASCII");
    }

    if (idx == 65535 and @as(c_uint, @bitCast(cat)) < @as(c_uint, LC_ALL)) {
        const lm = if (loc) |l| l.cat[@intCast(cat)] else null;
        return if (lm) |m| @ptrCast(@constCast(&m.name)) else @constCast("C");
    }

    switch (cat) {
        LC_NUMERIC => {
            if (idx > 1) return @constCast("");
            str = c_numeric;
        },
        LC_TIME => {
            if (idx > 0x31) return @constCast("");
            str = c_time;
        },
        LC_MONETARY => {
            if (idx > 0) return @constCast("");
            str = "";
        },
        LC_MESSAGES => {
            if (idx > 3) return @constCast("");
            str = c_messages;
        },
        else => return @constCast(""),
    }

    while (idx > 0) : (idx -= 1) {
        while (str[0] != 0) : (str += 1) {}
        str += 1;
    }
    if (cat != LC_NUMERIC and str[0] != 0) {
        const lm = if (loc) |l| l.cat[@intCast(cat)] else null;
        str = __lctrans(str, lm);
    }
    return @constCast(str);
}

fn __nl_langinfo(item: nl_item) callconv(.c) [*:0]u8 {
    return __nl_langinfo_l(item, currentLocale());
}

// ============================================================================
// localeconv.c
// ============================================================================

const Lconv = extern struct {
    decimal_point: [*:0]const u8,
    thousands_sep: [*:0]const u8,
    grouping: [*:0]const u8,
    int_curr_symbol: [*:0]const u8,
    currency_symbol: [*:0]const u8,
    mon_decimal_point: [*:0]const u8,
    mon_thousands_sep: [*:0]const u8,
    mon_grouping: [*:0]const u8,
    positive_sign: [*:0]const u8,
    negative_sign: [*:0]const u8,
    int_frac_digits: u8,
    frac_digits: u8,
    p_cs_precedes: u8,
    p_sep_by_space: u8,
    n_cs_precedes: u8,
    n_sep_by_space: u8,
    p_sign_posn: u8,
    n_sign_posn: u8,
    int_p_cs_precedes: u8,
    int_p_sep_by_space: u8,
    int_n_cs_precedes: u8,
    int_n_sep_by_space: u8,
    int_p_sign_posn: u8,
    int_n_sign_posn: u8,
};

const posix_lconv: Lconv = .{
    .decimal_point = ".",
    .thousands_sep = "",
    .grouping = "",
    .int_curr_symbol = "",
    .currency_symbol = "",
    .mon_decimal_point = "",
    .mon_thousands_sep = "",
    .mon_grouping = "",
    .positive_sign = "",
    .negative_sign = "",
    .int_frac_digits = 127,
    .frac_digits = 127,
    .p_cs_precedes = 127,
    .p_sep_by_space = 127,
    .n_cs_precedes = 127,
    .n_sep_by_space = 127,
    .p_sign_posn = 127,
    .n_sign_posn = 127,
    .int_p_cs_precedes = 127,
    .int_p_sep_by_space = 127,
    .int_n_cs_precedes = 127,
    .int_n_sep_by_space = 127,
    .int_p_sign_posn = 127,
    .int_n_sign_posn = 127,
};

fn localeconvImpl() callconv(.c) *const Lconv {
    return &posix_lconv;
}

// ============================================================================
// strtod_l.c, wcscoll.c, wcsxfrm.c, iconv_close.c
// ============================================================================

fn strtof_l(s: [*:0]const u8, p: ?*[*:0]u8, _: locale_t) callconv(.c) f32 {
    return strtof(s, p);
}

fn strtod_l(s: [*:0]const u8, p: ?*[*:0]u8, _: locale_t) callconv(.c) f64 {
    return strtod(s, p);
}

fn strtold_l(s: [*:0]const u8, p: ?*[*:0]u8, _: locale_t) callconv(.c) c_longdouble {
    return strtold(s, p);
}

fn __wcscoll_l(l: [*:0]const wchar_t, r: [*:0]const wchar_t, _: locale_t) callconv(.c) c_int {
    return wcscmp(l, r);
}

fn wcscollImpl(l: [*:0]const wchar_t, r: [*:0]const wchar_t) callconv(.c) c_int {
    return __wcscoll_l(l, r, currentLocale());
}

fn __wcsxfrm_l(dest: ?[*]wchar_t, src: [*:0]const wchar_t, n: usize, _: locale_t) callconv(.c) usize {
    const l = wcslen(src);
    if (l < n) {
        if (dest) |d| _ = wmemcpy(d, src, l + 1);
    } else if (n != 0) {
        if (dest) |d| {
            _ = wmemcpy(d, src, n - 1);
            d[n - 1] = 0;
        }
    }
    return l;
}

fn wcsxfrmImpl(dest: ?[*]wchar_t, src: [*:0]const wchar_t, n: usize) callconv(.c) usize {
    return __wcsxfrm_l(dest, src, n, currentLocale());
}

fn iconv_closeImpl(cd: iconv_t) callconv(.c) c_int {
    if ((@intFromPtr(cd) & 1) == 0) std.c.free(cd);
    return 0;
}

// ============================================================================
// pleval.c
// ============================================================================

const PlevalSt = struct {
    r: c_ulong = 0,
    n: c_ulong = 0,
    op: c_int = 0,
};

fn skipspace(s_in: [*:0]const u8) [*:0]const u8 {
    var s = s_in;
    while (std.ascii.isWhitespace(s[0])) : (s += 1) {}
    return s;
}

fn evalprim(st: *PlevalSt, s_in: [*:0]const u8, d_in: c_int) [*:0]const u8 {
    const d = d_in - 1;
    if (d < 0) return "";
    var s = skipspace(s_in);
    if (std.ascii.isDigit(s[0])) {
        var e: [*:0]u8 = undefined;
        st.r = strtoul(s, &e, 10);
        if (@intFromPtr(e) == @intFromPtr(s) or st.r == std.math.maxInt(c_ulong)) return "";
        return skipspace(e);
    }
    if (s[0] == 'n') {
        st.r = st.n;
        return skipspace(s + 1);
    }
    if (s[0] == '(') {
        s = evalexpr(st, s + 1, d);
        if (s[0] != ')') return "";
        return skipspace(s + 1);
    }
    if (s[0] == '!') {
        s = evalprim(st, s + 1, d);
        st.r = @intFromBool(st.r == 0);
        return s;
    }
    return "";
}

fn binop(st: *PlevalSt, op: c_int, left: c_ulong) bool {
    const a = left;
    const b = st.r;
    switch (op) {
        0 => {
            st.r = @intFromBool(a != 0 or b != 0);
            return false;
        },
        1 => {
            st.r = @intFromBool(a != 0 and b != 0);
            return false;
        },
        2 => {
            st.r = @intFromBool(a == b);
            return false;
        },
        3 => {
            st.r = @intFromBool(a != b);
            return false;
        },
        4 => {
            st.r = @intFromBool(a >= b);
            return false;
        },
        5 => {
            st.r = @intFromBool(a <= b);
            return false;
        },
        6 => {
            st.r = @intFromBool(a > b);
            return false;
        },
        7 => {
            st.r = @intFromBool(a < b);
            return false;
        },
        8 => {
            st.r = a +% b;
            return false;
        },
        9 => {
            st.r = a -% b;
            return false;
        },
        10 => {
            st.r = a *% b;
            return false;
        },
        11 => {
            if (b != 0) {
                st.r = a % b;
                return false;
            }
            return true;
        },
        12 => {
            if (b != 0) {
                st.r = a / b;
                return false;
            }
            return true;
        },
        else => return true,
    }
}

fn parseop(st: *PlevalSt, s: [*:0]const u8) [*:0]const u8 {
    const opch = "|&=!><+-*%/";
    const opch2 = "|&====";
    for (0..11) |i| {
        if (s[0] == opch[i]) {
            if (i < 6 and s[1] == opch2[i]) {
                st.op = @intCast(i);
                return s + 2;
            }
            if (i >= 4) {
                st.op = @intCast(i + 2);
                return s + 1;
            }
            break;
        }
    }
    st.op = 13;
    return s;
}

fn evalbinop(st: *PlevalSt, s_in: [*:0]const u8, minprec: c_int, d_in: c_int) [*:0]const u8 {
    const prec = [14]c_int{ 1, 2, 3, 3, 4, 4, 4, 4, 5, 5, 6, 6, 6, 0 };
    const d = d_in - 1;
    var s = evalprim(st, s_in, d);
    s = parseop(st, s);
    while (true) {
        const op = st.op;
        if (prec[@intCast(op)] <= minprec) return s;
        const left = st.r;
        s = evalbinop(st, s, prec[@intCast(op)], d);
        if (binop(st, op, left)) return "";
    }
}

fn evalexpr(st: *PlevalSt, s_in: [*:0]const u8, d_in: c_int) [*:0]const u8 {
    const d = d_in - 1;
    if (d < 0) return "";
    var s = evalbinop(st, s_in, 0, d);
    if (s[0] != '?') return s;
    const a = st.r;
    s = evalexpr(st, s + 1, d);
    if (s[0] != ':') return "";
    const b = st.r;
    s = evalexpr(st, s + 1, d);
    st.r = if (a != 0) b else st.r;
    return s;
}

fn __pleval(s_in: [*:0]const u8, n: c_ulong) callconv(.c) c_ulong {
    var st = PlevalSt{ .n = n };
    const s = evalexpr(&st, s_in, 100);
    return if (s[0] == ';') st.r else std.math.maxInt(c_ulong);
}

// ============================================================================
// bind_textdomain_codeset.c, textdomain.c, dcngettext.c
// ============================================================================

fn bind_textdomain_codesetImpl(_: ?[*:0]const u8, codeset: ?[*:0]const u8) callconv(.c) ?[*:0]u8 {
    if (codeset) |cs| {
        if (strcasecmp(cs, "UTF-8") != 0) {
            std.c._errno().* = @backingInt(std.posix.E.INVAL);
        }
    }
    return null;
}

var current_domain: ?[*:0]u8 = null;

fn __gettextdomain() callconv(.c) [*:0]u8 {
    return current_domain orelse @constCast("messages");
}

fn textdomainImpl(domainname: ?[*:0]const u8) callconv(.c) ?[*:0]u8 {
    const dn = domainname orelse return __gettextdomain();
    const domlen = strlen(dn);
    if (domlen > NAME_MAX) {
        std.c._errno().* = @backingInt(std.posix.E.INVAL);
        return null;
    }
    if (current_domain == null) {
        current_domain = @ptrCast(std.c.malloc(NAME_MAX + 1) orelse return null);
    }
    const dst: [*]u8 = @ptrCast(current_domain.?);
    @memcpy(dst[0 .. domlen + 1], dn[0 .. domlen + 1]);
    return current_domain;
}

const Binding = struct {
    next: ?*Binding,
    dirlen: c_int,
    active: c_int,
    domainname: [*:0]u8,
    dirname: [*:0]u8,
};

var bindings: ?*Binding = null;
var gettext_lock: c_int = 0;

fn gettextdir(domainname: [*:0]const u8, dirlen: *usize) ?[*:0]u8 {
    var p = @atomicLoad(?*Binding, &bindings, .seq_cst);
    while (p) |cur| : (p = cur.next) {
        if (strcmp(cur.domainname, domainname) == 0 and @atomicLoad(c_int, &cur.active, .seq_cst) != 0) {
            dirlen.* = @intCast(cur.dirlen);
            return cur.dirname;
        }
    }
    return null;
}

fn bindtextdomainImpl(domainname_in: ?[*:0]const u8, dirname_in: ?[*:0]const u8) callconv(.c) ?[*:0]u8 {
    const domainname = domainname_in orelse return null;
    var unused_len: usize = 0;
    const dirname = dirname_in orelse return gettextdir(domainname, &unused_len);

    const domlen = strnlen(domainname, NAME_MAX + 1);
    const dirlen = strnlen(dirname, PATH_MAX);
    if (domlen > NAME_MAX or dirlen >= PATH_MAX) {
        std.c._errno().* = @backingInt(std.posix.E.INVAL);
        return null;
    }

    __lock(&gettext_lock);

    var p = bindings;
    while (p) |cur| : (p = cur.next) {
        if (strcmp(cur.domainname, domainname) == 0 and strcmp(cur.dirname, dirname) == 0) {
            break;
        }
    }

    if (p == null) {
        const total = @sizeOf(Binding) + domlen + dirlen + 2;
        const raw_opt = std.c.malloc(total);
        if (raw_opt == null) {
            __unlock(&gettext_lock);
            return null;
        }
        const raw: [*]u8 = @ptrCast(raw_opt.?);
        @memset(raw[0..total], 0);
        const new_b: *Binding = @ptrCast(@alignCast(raw));
        new_b.next = bindings;
        new_b.dirlen = @intCast(dirlen);
        const buf = raw + @sizeOf(Binding);
        @memcpy(buf[0 .. domlen + 1], domainname[0 .. domlen + 1]);
        @memcpy((buf + domlen + 1)[0 .. dirlen + 1], dirname[0 .. dirlen + 1]);
        new_b.domainname = @ptrCast(buf);
        new_b.dirname = @ptrCast(buf + domlen + 1);
        @atomicStore(?*Binding, &bindings, new_b, .seq_cst);
        p = new_b;
    }

    @atomicStore(c_int, &p.?.active, 1, .seq_cst);

    var q = bindings;
    while (q) |cur| : (q = cur.next) {
        if (strcmp(cur.domainname, domainname) == 0 and cur != p.?) {
            @atomicStore(c_int, &cur.active, 0, .seq_cst);
        }
    }

    __unlock(&gettext_lock);
    return p.?.dirname;
}

const catnames = [6][12:0]u8{
    "LC_CTYPE\x00\x00\x00\x00".*,
    "LC_NUMERIC\x00\x00".*,
    "LC_TIME\x00\x00\x00\x00\x00".*,
    "LC_COLLATE\x00\x00".*,
    "LC_MONETARY\x00".*,
    "LC_MESSAGES\x00".*,
};

const MsgCat = struct {
    next: ?*MsgCat,
    map: *const anyopaque,
    map_size: usize,
    plural_rule: [*:0]const u8,
    nplurals: c_ulong,
    binding: *Binding,
    lm: *const LocaleMap,
    cat: c_int,
};

var cats: ?*MsgCat = null;

fn memchrSlice(ptr: [*]const u8, ch: u8, len: usize) ?[*]const u8 {
    for (0..len) |i| {
        if (ptr[i] == ch) return ptr + i;
    }
    return null;
}

fn dcngettextImpl(
    domainname_in: ?[*:0]const u8,
    msgid1_in: ?[*:0]const u8,
    msgid2_in: ?[*:0]const u8,
    n: c_ulong,
    category: c_int,
) callconv(.c) ?[*:0]u8 {
    const old_errno = std.c._errno().*;
    const msgid1 = msgid1_in orelse {
        std.c._errno().* = old_errno;
        return if (n == 1) null else @constCast(msgid2_in);
    };

    if (@as(c_uint, @bitCast(category)) >= @as(c_uint, LC_ALL)) {
        std.c._errno().* = old_errno;
        return @constCast(if (n == 1) msgid1 else (msgid2_in orelse msgid1));
    }

    const domainname: [*:0]const u8 = domainname_in orelse __gettextdomain();
    const domlen = strnlen(domainname, NAME_MAX + 1);
    if (domlen > NAME_MAX) {
        std.c._errno().* = old_errno;
        return @constCast(if (n == 1) msgid1 else (msgid2_in orelse msgid1));
    }

    var q = @atomicLoad(?*Binding, &bindings, .seq_cst);
    while (q) |cur| : (q = cur.next) {
        if (strcmp(cur.domainname, domainname) == 0 and @atomicLoad(c_int, &cur.active, .seq_cst) != 0)
            break;
    }
    const binding = q orelse {
        std.c._errno().* = old_errno;
        return @constCast(if (n == 1) msgid1 else (msgid2_in orelse msgid1));
    };

    const loc = currentLocale();
    const lm = loc.cat[@intCast(category)] orelse {
        std.c._errno().* = old_errno;
        return @constCast(if (n == 1) msgid1 else (msgid2_in orelse msgid1));
    };

    var p = @atomicLoad(?*MsgCat, &cats, .seq_cst);
    while (p) |cur| : (p = cur.next) {
        if (cur.binding == binding and cur.lm == lm and cur.cat == category)
            break;
    }

    if (p == null) {
        const dirname = binding.dirname;
        const locname: [*:0]const u8 = @ptrCast(&lm.name);
        const catname: [*:0]const u8 = &catnames[@intCast(category)];
        var loclen: usize = strlen(locname);

        const modname: [*]const u8 = memchrSlice(locname, '@', loclen) orelse (locname + loclen);
        const modlen: usize = loclen - (@intFromPtr(modname) - @intFromPtr(locname));
        var alt_modlen: usize = modlen;
        loclen = @intFromPtr(modname) - @intFromPtr(locname);

        if (memchrSlice(locname, '.', loclen)) |csp| {
            loclen = @intFromPtr(csp) - @intFromPtr(locname);
        }

        var name_buf: [PATH_MAX + NAME_MAX + 64]u8 = undefined;
        var map_opt: ?[*]const u8 = null;
        var map_size: usize = 0;

        while (true) {
            _ = snprintf(
                &name_buf,
                @sizeOf(@TypeOf(name_buf)),
                "%s/%.*s%.*s/%s/%s.mo",
                dirname,
                @as(c_int, @intCast(loclen)),
                locname,
                @as(c_int, @intCast(alt_modlen)),
                modname,
                catname,
                domainname,
            );
            map_opt = __map_file(@ptrCast(&name_buf), &map_size);
            if (map_opt != null) break;

            if (alt_modlen != 0) {
                alt_modlen = 0;
            } else if (memchrSlice(locname, '_', loclen)) |locp| {
                loclen = @intFromPtr(locp) - @intFromPtr(locname);
                alt_modlen = modlen;
            } else {
                break;
            }
        }
        const map = map_opt orelse {
            std.c._errno().* = old_errno;
            return @constCast(if (n == 1) msgid1 else (msgid2_in orelse msgid1));
        };

        const raw_mc = std.c.malloc(@sizeOf(MsgCat)) orelse {
            _ = munmap(@ptrCast(@constCast(map)), map_size);
            std.c._errno().* = old_errno;
            return @constCast(if (n == 1) msgid1 else (msgid2_in orelse msgid1));
        };
        const new_mc: *MsgCat = @ptrCast(@alignCast(raw_mc));
        new_mc.cat = category;
        new_mc.binding = binding;
        new_mc.lm = lm;
        new_mc.map = @ptrCast(map);
        new_mc.map_size = map_size;

        var rule: [*:0]const u8 = "n!=1;";
        var np: c_ulong = 2;
        var r_opt = __mo_lookup(new_mc.map, new_mc.map_size, "");
        while (r_opt) |r| {
            if (strncmp(r, "Plural-Forms:", 13) == 0) break;
            if (strchr(r, '\n')) |z| {
                r_opt = z + 1;
            } else {
                r_opt = null;
            }
        }
        if (r_opt) |r_start| {
            var r = r_start + 13;
            while (std.ascii.isWhitespace(r[0])) : (r += 1) {}
            if (strncmp(r, "nplurals=", 9) == 0) {
                var z: [*:0]u8 = undefined;
                np = strtoul(r + 9, &z, 10);
                r = z;
            }
            while (r[0] != 0 and r[0] != ';') : (r += 1) {}
            if (r[0] != 0) {
                r += 1;
                while (std.ascii.isWhitespace(r[0])) : (r += 1) {}
                if (strncmp(r, "plural=", 7) == 0) {
                    rule = r + 7;
                }
            }
        }
        new_mc.nplurals = np;
        new_mc.plural_rule = rule;

        while (true) {
            const old_cats = @atomicLoad(?*MsgCat, &cats, .seq_cst);
            new_mc.next = old_cats;
            if (@cmpxchgWeak(?*MsgCat, &cats, old_cats, new_mc, .seq_cst, .seq_cst) == null) break;
        }
        p = new_mc;
    }

    const mc = p.?;
    var trans = __mo_lookup(mc.map, mc.map_size, msgid1) orelse {
        std.c._errno().* = old_errno;
        return @constCast(if (n == 1) msgid1 else (msgid2_in orelse msgid1));
    };

    if (msgid2_in != null and mc.nplurals != 0) {
        var plural = __pleval(mc.plural_rule, n);
        if (plural > mc.nplurals) {
            std.c._errno().* = old_errno;
            return @constCast(if (n == 1) msgid1 else (msgid2_in orelse msgid1));
        }
        while (plural > 0) : (plural -= 1) {
            const rem = mc.map_size - (@intFromPtr(trans) - @intFromPtr(mc.map));
            const l = strnlen(trans, rem);
            if (l + 1 >= rem) {
                std.c._errno().* = old_errno;
                return @constCast(if (n == 1) msgid1 else (msgid2_in orelse msgid1));
            }
            trans += l + 1;
        }
    }

    std.c._errno().* = old_errno;
    return @constCast(trans);
}

fn dcgettextImpl(domainname: ?[*:0]const u8, msgid: ?[*:0]const u8, category: c_int) callconv(.c) ?[*:0]u8 {
    return dcngettextImpl(domainname, msgid, null, 1, category);
}

fn dngettextImpl(domainname: ?[*:0]const u8, msgid1: ?[*:0]const u8, msgid2: ?[*:0]const u8, n: c_ulong) callconv(.c) ?[*:0]u8 {
    return dcngettextImpl(domainname, msgid1, msgid2, n, LC_MESSAGES);
}

fn dgettextImpl(domainname: ?[*:0]const u8, msgid: ?[*:0]const u8) callconv(.c) ?[*:0]u8 {
    return dcngettextImpl(domainname, msgid, null, 1, LC_MESSAGES);
}

fn gettextImpl(msgid: ?[*:0]const u8) callconv(.c) ?[*:0]u8 {
    return dgettextImpl(null, msgid);
}

fn ngettextImpl(msgid1: ?[*:0]const u8, msgid2: ?[*:0]const u8, n: c_ulong) callconv(.c) ?[*:0]u8 {
    return dngettextImpl(null, msgid1, msgid2, n);
}

// ============================================================================
// catopen.c, catgets.c, catclose.c
// ============================================================================

inline fn readBe32(p: [*]const u8) u32 {
    return std.mem.readInt(u32, p[0..4], .big);
}

fn do_catopen(name: [*:0]const u8) nl_catd {
    var size: usize = 0;
    const map = __map_file(name, &size) orelse {
        std.c._errno().* = @backingInt(std.posix.E.NOENT);
        return @ptrFromInt(std.math.maxInt(usize));
    };
    if (size < 20 or readBe32(map) != 0xff88ff89 or 20 + @as(usize, readBe32(map + 8)) != size) {
        _ = munmap(@ptrCast(@constCast(map)), size);
        std.c._errno().* = @backingInt(std.posix.E.NOENT);
        return @ptrFromInt(std.math.maxInt(usize));
    }
    return @ptrCast(@constCast(map));
}

fn catopenImpl(name: [*:0]const u8, oflag: c_int) callconv(.c) nl_catd {
    const invalid: nl_catd = @ptrFromInt(std.math.maxInt(usize));
    if (strchr(name, '/') != null) return do_catopen(name);

    var buf: [PATH_MAX]u8 = undefined;
    if (__libc.secure != 0) {
        std.c._errno().* = @backingInt(std.posix.E.NOENT);
        return invalid;
    }
    const path = getenv("NLSPATH") orelse {
        std.c._errno().* = @backingInt(std.posix.E.NOENT);
        return invalid;
    };
    const lang: [*:0]const u8 = (if (oflag != 0)
        __nl_langinfo((LC_MESSAGES << 16) | 65535)
    else
        getenv("LANG")) orelse "";

    var p: [*:0]const u8 = path;
    var z: [*:0]const u8 = undefined;
    while (p[0] != 0) : (p = z) {
        var i: usize = 0;
        z = __strchrnul(p, ':');
        while (@intFromPtr(p) < @intFromPtr(z)) : (p += 1) {
            var v: ?[*]const u8 = null;
            var l: usize = 0;
            if (p[0] != '%') {
                v = p;
                l = 1;
            } else {
                p += 1;
                switch (p[0]) {
                    'N' => {
                        v = name;
                        l = strlen(name);
                    },
                    'L' => {
                        v = lang;
                        l = strlen(lang);
                    },
                    'l' => {
                        v = lang;
                        l = strcspn(lang, "_.@");
                    },
                    't' => {
                        var tv = __strchrnul(lang, '_');
                        if (tv[0] != 0) tv += 1;
                        v = tv;
                        l = strcspn(tv, ".@");
                    },
                    'c' => {
                        v = "UTF-8";
                        l = 5;
                    },
                    '%' => {
                        v = "%";
                        l = 1;
                    },
                    else => {
                        v = null;
                    },
                }
            }
            if (v == null or l >= @sizeOf(@TypeOf(buf)) - i) {
                break;
            }
            @memcpy(buf[i..][0..l], v.?[0..l]);
            i += l;
        }
        if (z[0] == 0 and (@intFromPtr(p) < @intFromPtr(z) or i == 0)) break;
        if (@intFromPtr(p) < @intFromPtr(z)) continue;
        if (z[0] != 0) z += 1;
        buf[i] = 0;
        const catd = do_catopen(if (i != 0) @ptrCast(&buf) else name);
        if (catd != invalid) return catd;
    }
    std.c._errno().* = @backingInt(std.posix.E.NOENT);
    return invalid;
}

fn catCmp(a: *const anyopaque, b: *const anyopaque) callconv(.c) c_int {
    const x = readBe32(@ptrCast(a));
    const y = readBe32(@ptrCast(b));
    return if (x < y) -1 else if (x > y) 1 else 0;
}

fn catgetsImpl(catd: nl_catd, set_id: c_int, msg_id: c_int, s: [*:0]const u8) callconv(.c) [*:0]u8 {
    if (catd == null or catd == @as(nl_catd, @ptrFromInt(std.math.maxInt(usize)))) {
        std.c._errno().* = @backingInt(std.posix.E.BADF);
        return @constCast(s);
    }
    const map: [*]const u8 = @ptrCast(catd.?);
    const nsets = readBe32(map + 4);
    const sets = map + 20;
    var msgs = map + 20 + readBe32(map + 12);
    const strings = map + 20 + readBe32(map + 16);
    var set_id_be: [4]u8 = undefined;
    var msg_id_be: [4]u8 = undefined;
    std.mem.writeInt(u32, &set_id_be, @bitCast(set_id), .big);
    std.mem.writeInt(u32, &msg_id_be, @bitCast(msg_id), .big);

    const set_ptr = bsearch(&set_id_be, sets, nsets, 12, &catCmp) orelse {
        std.c._errno().* = @backingInt(std.posix.E.NOMSG);
        return @constCast(s);
    };
    const set_bytes: [*]const u8 = @ptrCast(set_ptr);
    const nmsgs = readBe32(set_bytes + 4);
    msgs += 12 * @as(usize, readBe32(set_bytes + 8));
    const msg_ptr = bsearch(&msg_id_be, msgs, nmsgs, 12, &catCmp) orelse {
        std.c._errno().* = @backingInt(std.posix.E.NOMSG);
        return @constCast(s);
    };
    const msg_bytes: [*]const u8 = @ptrCast(msg_ptr);
    return @ptrCast(@constCast(strings + readBe32(msg_bytes + 8)));
}

fn catcloseImpl(catd: nl_catd) callconv(.c) c_int {
    if (catd == null or catd == @as(nl_catd, @ptrFromInt(std.math.maxInt(usize)))) {
        std.c._errno().* = @backingInt(std.posix.E.BADF);
        return -1;
    }
    const map: [*]u8 = @ptrCast(catd.?);
    _ = munmap(@ptrCast(map), @as(usize, readBe32(map + 8)) + 20);
    return 0;
}

comptime {
    if (builtin.target.isMuslLibC() and builtin.link_libc) {
        symbol(&__c_dot_utf8, "__c_dot_utf8");
        symbol(&__c_locale, "__c_locale");
        symbol(&__c_dot_utf8_locale, "__c_dot_utf8_locale");

        symbol(&__mo_lookup, "__mo_lookup");
        symbol(&__lctrans_impl, "__lctrans_impl");
        symbol(&__lctrans, "__lctrans");
        symbol(&__lctrans_cur, "__lctrans_cur");
        symbol(&__get_locale, "__get_locale");

        symbol(&setlocaleImpl, "setlocale");
        symbol(&__newlocale, "__newlocale");
        symbol(&__newlocale, "newlocale");
        symbol(&__duplocale, "__duplocale");
        symbol(&__duplocale, "duplocale");
        symbol(&__freelocale, "__freelocale");
        symbol(&__freelocale, "freelocale");
        symbol(&__uselocale, "__uselocale");
        symbol(&__uselocale, "uselocale");

        symbol(&__nl_langinfo, "__nl_langinfo");
        symbol(&__nl_langinfo, "nl_langinfo");
        symbol(&__nl_langinfo_l, "__nl_langinfo_l");
        symbol(&__nl_langinfo_l, "nl_langinfo_l");

        symbol(&localeconvImpl, "localeconv");

        symbol(&strtof_l, "strtof_l");
        symbol(&strtof_l, "__strtof_l");
        symbol(&strtod_l, "strtod_l");
        symbol(&strtod_l, "__strtod_l");
        symbol(&strtold_l, "strtold_l");
        symbol(&strtold_l, "__strtold_l");

        symbol(&wcscollImpl, "wcscoll");
        symbol(&__wcscoll_l, "__wcscoll_l");
        symbol(&__wcscoll_l, "wcscoll_l");
        symbol(&wcsxfrmImpl, "wcsxfrm");
        symbol(&__wcsxfrm_l, "__wcsxfrm_l");
        symbol(&__wcsxfrm_l, "wcsxfrm_l");

        symbol(&iconv_closeImpl, "iconv_close");

        symbol(&__pleval, "__pleval");
        symbol(&bind_textdomain_codesetImpl, "bind_textdomain_codeset");
        symbol(&__gettextdomain, "__gettextdomain");
        symbol(&textdomainImpl, "textdomain");
        symbol(&bindtextdomainImpl, "bindtextdomain");
        symbol(&dcngettextImpl, "dcngettext");
        symbol(&dcgettextImpl, "dcgettext");
        symbol(&dngettextImpl, "dngettext");
        symbol(&dgettextImpl, "dgettext");
        symbol(&gettextImpl, "gettext");
        symbol(&ngettextImpl, "ngettext");

        symbol(&catopenImpl, "catopen");
        symbol(&catgetsImpl, "catgets");
        symbol(&catcloseImpl, "catclose");
    }
}
