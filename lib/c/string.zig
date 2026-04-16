const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;
const wchar_t = std.c.wchar_t;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        // memcpy implemented in compiler_rt
        // memmove implemented in compiler_rt
        // memset implemented in compiler_rt
        // memcmp implemented in compiler_rt
        symbol(&memchr, "memchr");
        symbol(&strcpy, "strcpy");
        symbol(&strncpy, "strncpy");
        symbol(&strcat, "strcat");
        symbol(&strncat, "strncat");
        symbol(&strcmp, "strcmp");
        symbol(&strncmp, "strncmp");
        symbol(&strcoll, "strcoll");
        symbol(&strxfrm, "strxfrm");
        symbol(&strchr, "strchr");
        symbol(&strrchr, "strrchr");
        symbol(&strcspn, "strcspn");
        symbol(&strspn, "strspn");
        symbol(&strpbrk, "strpbrk");
        symbol(&strstr, "strstr");
        symbol(&strtok, "strtok");
        // strlen is in compiler_rt

        symbol(&strtok_r, "strtok_r");
        symbol(&stpcpy, "stpcpy");
        symbol(&stpncpy, "stpncpy");
        symbol(&strnlen, "strnlen");
        symbol(&memmem, "memmem");

        symbol(&memccpy, "memccpy");

        symbol(&strsep, "strsep");
        symbol(&strlcat, "strlcat");
        symbol(&strlcpy, "strlcpy");
        symbol(&explicit_bzero, "explicit_bzero");

        symbol(&strchrnul, "strchrnul");
        symbol(&strcasestr, "strcasestr");
        symbol(&memrchr, "memrchr");
        symbol(&mempcpy, "mempcpy");

        symbol(&__strcoll_l, "__strcoll_l");
        symbol(&__strxfrm_l, "strxfrm_l");
        symbol(&__strcoll_l, "strcoll_l");
        symbol(&__strxfrm_l, "__strxfrm_l");
        symbol(&strchrnul, "__strchrnul");

        symbol(&strverscmp_fn, "strverscmp");

        symbol(&wcscasecmp_fn, "wcscasecmp");
        symbol(&wcsncasecmp_fn, "wcsncasecmp");
        symbol(&wcscasecmp_l_fn, "wcscasecmp_l");
        symbol(&wcsncasecmp_l_fn, "wcsncasecmp_l");

        if (builtin.link_libc) {
            symbol(&strdup_fn, "strdup");
            symbol(&strndup_fn, "strndup");
            symbol(&wcsdup_fn, "wcsdup");
            symbol(&strerror_r_fn, "strerror_r");
            symbol(&strsignal_fn, "strsignal");
        }

        // These symbols are not in the public ABI of musl/wasi. However they depend on these exports internally.
    }

    if (builtin.target.isMinGW()) {
    }
}

fn memchr(ptr: *const anyopaque, value: c_int, len: usize) callconv(.c) ?*anyopaque {
    const bytes: [*]const u8 = @ptrCast(ptr);
    return @constCast(bytes[std.mem.findScalar(u8, bytes[0..len], @truncate(@as(c_uint, @bitCast(value)))) orelse return null ..]);
}

fn strcpy(noalias dst: [*]c_char, noalias src: [*:0]const c_char) callconv(.c) [*]c_char {
    _ = stpcpy(dst, src);
    return dst;
}

fn strncpy(noalias dst: [*]c_char, noalias src: [*:0]const c_char, max: usize) callconv(.c) [*]c_char {
    _ = stpncpy(dst, src, max);
    return dst;
}

fn strcat(noalias dst: [*:0]c_char, noalias src: [*:0]const c_char) callconv(.c) [*:0]c_char {
    return strncat(dst, src, std.math.maxInt(usize));
}

fn strncat(noalias dst: [*:0]c_char, noalias src: [*:0]const c_char, max: usize) callconv(.c) [*:0]c_char {
    const dst_len = std.mem.len(@as([*:0]u8, @ptrCast(dst)));
    const src_len = strnlen(src, max);

    @memcpy(dst[dst_len..][0..src_len], src[0..src_len]);
    dst[dst_len + src_len] = 0;
    return dst[0..(dst_len + src_len) :0].ptr;
}

fn strcmp(a: [*:0]const c_char, b: [*:0]const c_char) callconv(.c) c_int {
    return strncmp(a, b, std.math.maxInt(usize));
}

fn strncmp(a: [*:0]const c_char, b: [*:0]const c_char, max: usize) callconv(.c) c_int {
    return switch (std.mem.boundedOrderZ(u8, @ptrCast(a), @ptrCast(b), max)) {
        .eq => 0,
        .gt => 1,
        .lt => -1,
    };
}

fn strcoll(a: [*:0]const c_char, b: [*:0]const c_char) callconv(.c) c_int {
    return strcmp(a, b);
}

fn __strcoll_l(a: [*:0]const c_char, b: [*:0]const c_char, locale: *anyopaque) callconv(.c) c_int {
    _ = locale;
    return strcoll(a, b);
}

// NOTE: If 'max' is 0, 'dst' is allowed to be a null pointer
fn strxfrm(noalias dst: ?[*]c_char, noalias src: [*:0]const c_char, max: usize) callconv(.c) usize {
    const src_len = std.mem.len(@as([*:0]const u8, @ptrCast(src)));
    if (src_len < max) @memcpy(dst.?[0 .. src_len + 1], src[0 .. src_len + 1]);
    return src_len;
}

fn __strxfrm_l(noalias dst: ?[*]c_char, noalias src: [*:0]const c_char, max: usize, locale: *anyopaque) callconv(.c) usize {
    _ = locale;
    return strxfrm(dst, src, max);
}

fn strchr(str: [*:0]const c_char, value: c_int) callconv(.c) ?[*:0]c_char {
    const str_u8: [*:0]const u8 = @ptrCast(str);
    const len = std.mem.len(str_u8);

    if (value == 0) return @constCast(str + len);
    return @constCast(str[std.mem.findScalar(u8, str_u8[0..len], @truncate(@as(c_uint, @bitCast(value)))) orelse return null ..]);
}

fn strrchr(str: [*:0]const c_char, value: c_int) callconv(.c) ?[*:0]c_char {
    const str_u8: [*:0]const u8 = @ptrCast(str);
    // std.mem.len(str) + 1 to not special case '\0'
    return @constCast(str[std.mem.findScalarLast(u8, str_u8[0 .. std.mem.len(str_u8) + 1], @truncate(@as(c_uint, @bitCast(value)))) orelse return null ..]);
}

fn strcspn(dst: [*:0]const c_char, values: [*:0]const c_char) callconv(.c) usize {
    const dst_slice = std.mem.span(@as([*:0]const u8, @ptrCast(dst)));
    return std.mem.findAny(u8, dst_slice, std.mem.span(@as([*:0]const u8, @ptrCast(values)))) orelse dst_slice.len;
}

fn strspn(dst: [*:0]const c_char, values: [*:0]const c_char) callconv(.c) usize {
    const dst_slice = std.mem.span(@as([*:0]const u8, @ptrCast(dst)));
    return std.mem.findNone(u8, dst_slice, std.mem.span(@as([*:0]const u8, @ptrCast(values)))) orelse dst_slice.len;
}

fn strpbrk(haystack: [*:0]const c_char, needle: [*:0]const c_char) callconv(.c) ?[*:0]c_char {
    return @constCast(haystack[std.mem.findAny(u8, std.mem.span(@as([*:0]const u8, @ptrCast(haystack))), std.mem.span(@as([*:0]const u8, @ptrCast(needle)))) orelse return null ..]);
}

fn strstr(haystack: [*:0]const c_char, needle: [*:0]const c_char) callconv(.c) ?[*:0]c_char {
    return @constCast(haystack[std.mem.find(u8, std.mem.span(@as([*:0]const u8, @ptrCast(haystack))), std.mem.span(@as([*:0]const u8, @ptrCast(needle)))) orelse return null ..]);
}

fn strtok(noalias maybe_str: ?[*:0]c_char, noalias values: [*:0]const c_char) callconv(.c) ?[*:0]c_char {
    const state = struct {
        var str: ?[*:0]c_char = null;
    };

    return strtok_r(maybe_str, values, &state.str);
}

// strlen is in compiler_rt

fn strtok_r(noalias maybe_str: ?[*:0]c_char, noalias values: [*:0]const c_char, noalias state: *?[*:0]c_char) callconv(.c) ?[*:0]c_char {
    const str = if (maybe_str) |str|
        str
    else if (state.*) |state_str|
        state_str
    else
        return null;

    const str_bytes = std.mem.span(@as([*:0]u8, @ptrCast(str)));
    const values_bytes = std.mem.span(@as([*:0]const u8, @ptrCast(values)));
    const tok_start = std.mem.findNone(u8, str_bytes, values_bytes) orelse return null;

    if (std.mem.findAnyPos(u8, str_bytes, tok_start, values_bytes)) |tok_end| {
        str[tok_end] = 0;
        state.* = str[tok_end + 1 ..];
    } else {
        state.* = str[str_bytes.len..];
    }

    return str[tok_start..];
}

fn stpcpy(noalias dst: [*]c_char, noalias src: [*:0]const c_char) callconv(.c) [*]c_char {
    const src_len = std.mem.len(@as([*:0]const u8, @ptrCast(src)));
    @memcpy(dst[0 .. src_len + 1], src[0 .. src_len + 1]);
    return dst + src_len;
}

fn stpncpy(noalias dst: [*]c_char, noalias src: [*:0]const c_char, max: usize) callconv(.c) [*]c_char {
    const src_len = strnlen(src, max);
    const copying_len = @min(max, src_len);
    @memcpy(dst[0..copying_len], src[0..copying_len]);
    @memset(dst[copying_len..][0 .. max - copying_len], 0x00);
    return dst + copying_len;
}

fn strnlen(str: [*:0]const c_char, max: usize) callconv(.c) usize {
    return std.mem.findScalar(u8, @ptrCast(str[0..max]), 0) orelse max;
}

fn memmem(haystack: *const anyopaque, haystack_len: usize, needle: *const anyopaque, needle_len: usize) callconv(.c) ?*anyopaque {
    const haystack_bytes: [*:0]const u8 = @ptrCast(haystack);
    const needle_bytes: [*:0]const u8 = @ptrCast(needle);

    return @constCast(haystack_bytes[std.mem.find(u8, haystack_bytes[0..haystack_len], needle_bytes[0..needle_len]) orelse return null ..]);
}

fn strsep(maybe_str: *?[*:0]c_char, values: [*:0]const c_char) callconv(.c) ?[*]c_char {
    if (maybe_str.*) |str| {
        const values_bytes = std.mem.span(@as([*:0]const u8, @ptrCast(values)));
        const str_bytes = std.mem.span(@as([*:0]u8, @ptrCast(str)));
        const found = std.mem.findAny(u8, str_bytes, values_bytes) orelse {
            maybe_str.* = null;
            return str;
        };

        str[found] = 0;
        maybe_str.* = str[found + 1 ..];
        return str;
    }

    return null;
}

fn strlcat(dst: [*:0]c_char, src: [*:0]const c_char, dst_total_len: usize) callconv(.c) usize {
    const dst_len = strnlen(dst, dst_total_len);
    const src_bytes = std.mem.span(@as([*:0]const u8, @ptrCast(src)));

    if (dst_total_len == dst_len) return dst_len + src_bytes.len;

    const copying_len = @min(dst_total_len - (dst_len + 1), src_bytes.len);

    @memcpy(dst[dst_len..][0..copying_len], src[0..copying_len]);
    dst[dst_len + copying_len] = 0;
    return dst_len + src_bytes.len;
}

fn strlcpy(dst: [*]c_char, src: [*:0]const c_char, dst_total_len: usize) callconv(.c) usize {
    const src_bytes = std.mem.span(@as([*:0]const u8, @ptrCast(src)));
    if (dst_total_len != 0) {
        const copying_len = @min(src_bytes.len, dst_total_len - 1);
        @memcpy(dst[0..copying_len], src[0..copying_len]);
        dst[copying_len] = 0;
    }
    return src_bytes.len;
}

fn memccpy(noalias dst: *anyopaque, noalias src: *const anyopaque, value: c_int, len: usize) callconv(.c) *anyopaque {
    const dst_bytes: [*]u8 = @ptrCast(dst);
    const src_bytes: [*]const u8 = @ptrCast(src);
    const value_u8: u8 = @truncate(@as(c_uint, @bitCast(value)));
    const copying_len = std.mem.findScalar(u8, src_bytes[0..len], value_u8) orelse len;
    @memcpy(dst_bytes[0..copying_len], src_bytes[0..copying_len]);
    return dst_bytes + copying_len;
}

fn explicit_bzero(ptr: *anyopaque, len: usize) callconv(.c) void {
    const bytes: [*]u8 = @ptrCast(ptr);
    std.crypto.secureZero(u8, bytes[0..len]);
}

fn strchrnul(str: [*:0]const c_char, value: c_int) callconv(.c) [*:0]c_char {
    const str_u8: [*:0]const u8 = @ptrCast(str);
    const len = std.mem.len(str_u8);

    if (value == 0) return @constCast(str + len);
    return @constCast(str[std.mem.findScalar(u8, str_u8[0..len], @truncate(@as(c_uint, @bitCast(value)))) orelse len ..]);
}

fn strcasestr(haystack: [*:0]const c_char, needle: [*:0]const c_char) callconv(.c) ?[*:0]c_char {
    return @constCast(haystack[std.ascii.findIgnoreCase(std.mem.span(@as([*:0]const u8, @ptrCast(haystack))), std.mem.span(@as([*:0]const u8, @ptrCast(needle)))) orelse return null ..]);
}

fn memrchr(ptr: *const anyopaque, value: c_int, len: usize) callconv(.c) ?*anyopaque {
    const bytes: [*]const u8 = @ptrCast(ptr);
    return @constCast(bytes[std.mem.findScalarLast(u8, bytes[0..len], @truncate(@as(c_uint, @bitCast(value)))) orelse return null ..]);
}

fn mempcpy(noalias dst: *anyopaque, noalias src: *const anyopaque, len: usize) callconv(.c) *anyopaque {
    const dst_bytes: [*]u8 = @ptrCast(dst);
    const src_bytes: [*]const u8 = @ptrCast(src);
    @memcpy(dst_bytes[0..len], src_bytes[0..len]);
    return dst_bytes + len;
}

fn strdup_fn(s: [*:0]const u8) callconv(.c) ?[*:0]u8 {
    const l = std.mem.len(s);
    const d: [*]u8 = @ptrCast(std.c.malloc(l + 1) orelse return null);
    @memcpy(d[0 .. l + 1], s[0 .. l + 1]);
    return d[0 .. l + 1 :0].ptr;
}

fn strndup_fn(s: [*:0]const u8, n: usize) callconv(.c) ?[*:0]u8 {
    const l = strnlen(@ptrCast(s), n);
    const d: [*]u8 = @ptrCast(std.c.malloc(l + 1) orelse return null);
    @memcpy(d[0..l], s[0..l]);
    d[l] = 0;
    return d[0 .. l + 1 :0].ptr;
}

fn wcsdup_fn(s: [*:0]const wchar_t) callconv(.c) ?[*:0]wchar_t {
    const l = std.mem.len(s);
    const byte_len = (l + 1) * @sizeOf(wchar_t);
    const d: [*]wchar_t = @ptrCast(@alignCast(@as([*]u8, @ptrCast(std.c.malloc(byte_len) orelse return null))));
    @memcpy(d[0 .. l + 1], s[0 .. l + 1]);
    return d[0 .. l + 1 :0].ptr;
}

const strerror_c = @extern(*const fn (c_int) callconv(.c) [*:0]u8, .{ .name = "strerror" });

fn strerror_r_fn(err: c_int, buf: ?[*]u8, buflen: usize) callconv(.c) c_int {
    const msg: [*:0]const u8 = strerror_c(err);
    const l = std.mem.len(msg);
    if (l >= buflen) {
        if (buflen != 0) {
            @memcpy(buf.?[0 .. buflen - 1], msg[0 .. buflen - 1]);
            buf.?[buflen - 1] = 0;
        }
        return @intFromEnum(std.c.E.RANGE);
    }
    @memcpy(buf.?[0 .. l + 1], msg[0 .. l + 1]);
    return 0;
}

const signal_descriptions = blk: {
    @setEvalBranchQuota(10000);
    const base = [_][*:0]const u8{
        "Unknown signal",
        "Hangup",
        "Interrupt",
        "Quit",
        "Illegal instruction",
        "Trace/breakpoint trap",
        "Aborted",
        "Bus error",
        "Arithmetic exception",
        "Killed",
        "User defined signal 1",
        "Segmentation fault",
        "User defined signal 2",
        "Broken pipe",
        "Alarm clock",
        "Terminated",
        "Stack fault",
        "Child process status",
        "Continued",
        "Stopped (signal)",
        "Stopped",
        "Stopped (tty input)",
        "Stopped (tty output)",
        "Urgent I/O condition",
        "CPU time limit exceeded",
        "File size limit exceeded",
        "Virtual timer expired",
        "Profiling timer expired",
        "Window changed",
        "I/O possible",
        "Power failure",
        "Bad system call",
    };

    const nsig: usize = if (builtin.cpu.arch.isMIPS()) 128 else 65;
    var desc: [nsig][*:0]const u8 = undefined;

    for (0..nsig) |i| {
        desc[i] = "Unknown signal";
    }

    if (builtin.cpu.arch.isMIPS() or builtin.cpu.arch.isSPARC()) {
        const linux = std.os.linux;
        const SIG = linux.SIG;
        desc[@intFromEnum(SIG.HUP)] = base[1];
        desc[@intFromEnum(SIG.INT)] = base[2];
        desc[@intFromEnum(SIG.QUIT)] = base[3];
        desc[@intFromEnum(SIG.ILL)] = base[4];
        desc[@intFromEnum(SIG.TRAP)] = base[5];
        desc[@intFromEnum(SIG.ABRT)] = base[6];
        desc[@intFromEnum(SIG.EMT)] = "Emulator trap";
        desc[@intFromEnum(SIG.FPE)] = base[8];
        desc[@intFromEnum(SIG.KILL)] = base[9];
        desc[@intFromEnum(SIG.BUS)] = base[7];
        desc[@intFromEnum(SIG.SEGV)] = base[11];
        desc[@intFromEnum(SIG.SYS)] = base[31];
        desc[@intFromEnum(SIG.PIPE)] = base[13];
        desc[@intFromEnum(SIG.ALRM)] = base[14];
        desc[@intFromEnum(SIG.TERM)] = base[15];
        desc[@intFromEnum(SIG.USR1)] = base[10];
        desc[@intFromEnum(SIG.USR2)] = base[12];
        desc[@intFromEnum(SIG.CHLD)] = base[17];
        desc[@intFromEnum(SIG.WINCH)] = base[28];
        desc[@intFromEnum(SIG.URG)] = base[23];
        desc[@intFromEnum(SIG.IO)] = base[29];
        desc[@intFromEnum(SIG.STOP)] = base[19];
        desc[@intFromEnum(SIG.TSTP)] = base[20];
        desc[@intFromEnum(SIG.CONT)] = base[18];
        desc[@intFromEnum(SIG.TTIN)] = base[21];
        desc[@intFromEnum(SIG.TTOU)] = base[22];
        desc[@intFromEnum(SIG.VTALRM)] = base[26];
        desc[@intFromEnum(SIG.PROF)] = base[27];
        desc[@intFromEnum(SIG.XCPU)] = base[24];
        if (builtin.cpu.arch.isMIPS()) {
            desc[@intFromEnum(SIG.XFZ)] = base[25];
            desc[@intFromEnum(SIG.PWR)] = base[30];
        } else {
            desc[@intFromEnum(SIG.XFSZ)] = base[25];
            // SPARC: PWR is alias for LOST
            desc[@intFromEnum(SIG.LOST)] = base[30];
        }
    } else {
        for (0..base.len) |i| {
            desc[i] = base[i];
        }
    }

    for (32..nsig) |i| {
        desc[i] = std.fmt.comptimePrint("RT{d}", .{i});
    }

    break :blk desc;
};

fn strsignal_fn(sig_arg: c_int) callconv(.c) [*:0]const u8 {
    const nsig: c_uint = if (builtin.cpu.arch.isMIPS()) 128 else 65;
    const sig: c_uint = @bitCast(sig_arg);
    if (sig -% 1 >= nsig - 1) return signal_descriptions[0];
    return signal_descriptions[sig];
}

fn strverscmp_fn(l0: [*:0]const u8, r0: [*:0]const u8) callconv(.c) c_int {
    var i: usize = 0;
    var dp: usize = 0;
    var z: bool = true;

    while (l0[i] == r0[i]) {
        const c = l0[i];
        if (c == 0) return 0;
        if (!std.ascii.isDigit(c)) {
            dp = i + 1;
            z = true;
        } else if (c != '0') {
            z = false;
        }
        i += 1;
    }

    if (l0[dp] -% '1' < 9 and r0[dp] -% '1' < 9) {
        var j = i;
        while (std.ascii.isDigit(l0[j])) {
            if (!std.ascii.isDigit(r0[j])) return 1;
            j += 1;
        }
        if (std.ascii.isDigit(r0[j])) return -1;
    } else if (z and dp < i and (std.ascii.isDigit(l0[i]) or std.ascii.isDigit(r0[i]))) {
        return @as(c_int, l0[i]) - @as(c_int, '0') - (@as(c_int, r0[i]) - @as(c_int, '0'));
    }

    return @as(c_int, l0[i]) - @as(c_int, r0[i]);
}

const towlower_ext = @extern(*const fn (c_uint) callconv(.c) c_uint, .{ .name = "towlower" });

fn wcsncasecmp_fn(l: [*:0]const wchar_t, r: [*:0]const wchar_t, n_arg: usize) callconv(.c) c_int {
    var n = n_arg;
    if (n == 0) return 0;
    n -= 1;
    var li: usize = 0;
    while (l[li] != 0 and r[li] != 0 and n > 0 and
        (l[li] == r[li] or towlower_ext(@as(c_uint, @bitCast(l[li]))) == towlower_ext(@as(c_uint, @bitCast(r[li])))))
    {
        li += 1;
        n -= 1;
    }
    return @as(c_int, @bitCast(towlower_ext(@as(c_uint, @bitCast(l[li]))))) -
        @as(c_int, @bitCast(towlower_ext(@as(c_uint, @bitCast(r[li])))));
}

fn wcscasecmp_fn(l: [*:0]const wchar_t, r: [*:0]const wchar_t) callconv(.c) c_int {
    return wcsncasecmp_fn(l, r, std.math.maxInt(usize));
}

fn wcscasecmp_l_fn(l: [*:0]const wchar_t, r: [*:0]const wchar_t, locale: *anyopaque) callconv(.c) c_int {
    _ = locale;
    return wcscasecmp_fn(l, r);
}

fn wcsncasecmp_l_fn(l: [*:0]const wchar_t, r: [*:0]const wchar_t, n: usize, locale: *anyopaque) callconv(.c) c_int {
    _ = locale;
    return wcsncasecmp_fn(l, r, n);
}

test strncmp {
    try std.testing.expect(strncmp(@ptrCast("a"), @ptrCast("b"), 1) < 0);
    try std.testing.expect(strncmp(@ptrCast("a"), @ptrCast("c"), 1) < 0);
    try std.testing.expect(strncmp(@ptrCast("b"), @ptrCast("a"), 1) > 0);
    try std.testing.expect(strncmp(@ptrCast("\xff"), @ptrCast("\x02"), 1) > 0);
}
