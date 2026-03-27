const builtin = @import("builtin");
const std = @import("std");

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&basename, "basename");
        symbol(&basename, "__xpg_basename");
        symbol(&dirname, "dirname");
        symbol(&a64l, "a64l");
        symbol(&l64a, "l64a");
    }
}

fn basename(s: ?[*:0]u8) callconv(.c) [*:0]const u8 {
    const str = s orelse return ".";
    if (str[0] == 0) return ".";

    // Find end of string.
    var i: usize = 0;
    while (str[i] != 0) : (i += 1) {}
    i -= 1;

    // Strip trailing slashes.
    while (i > 0 and str[i] == '/') : (i -= 1) {
        str[i] = 0;
    }
    if (i == 0 and str[0] == '/') return str[0..1 :0];

    // Find last slash.
    while (i > 0 and str[i - 1] != '/') : (i -= 1) {}

    return @ptrCast(str + i);
}

fn dirname(s: ?[*:0]u8) callconv(.c) [*:0]const u8 {
    const str = s orelse return ".";
    if (str[0] == 0) return ".";

    // Find end of string.
    var i: usize = 0;
    while (str[i] != 0) : (i += 1) {}
    i -= 1;

    // Strip trailing slashes.
    while (str[i] == '/') {
        if (i == 0) return "/";
        i -= 1;
    }
    // Strip trailing component.
    while (str[i] != '/') {
        if (i == 0) return ".";
        i -= 1;
    }
    // Strip trailing slashes again.
    while (str[i] == '/') {
        if (i == 0) return "/";
        i -= 1;
    }

    str[i + 1] = 0;
    return @ptrCast(str);
}

const digits = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

fn a64l(str: [*:0]const u8) callconv(.c) c_long {
    var x: u32 = 0;
    var e: u5 = 0;
    var p = str;
    while (e < 36 and p[0] != 0) : ({
        e += 6;
        p += 1;
    }) {
        const c = p[0];
        const d: u32 = for (digits, 0..) |ch, idx| {
            if (ch == c) break @intCast(idx);
        } else break;
        x |= d << e;
    }
    return @as(c_long, @as(i32, @bitCast(x)));
}

var l64a_buf: [7]u8 = undefined;

fn l64a(x0: c_long) callconv(.c) [*:0]u8 {
    var x: u32 = @bitCast(@as(c_int, @intCast(x0)));
    var i: usize = 0;
    while (x != 0 and i < 6) : (i += 1) {
        l64a_buf[i] = digits[x & 63];
        x >>= 6;
    }
    l64a_buf[i] = 0;
    return l64a_buf[0..i :0];
}
