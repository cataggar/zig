const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;

const AF_INET: c_int = if (builtin.target.isWasiLibC()) 1 else 2;
const AF_INET6: c_int = if (builtin.target.isWasiLibC()) 2 else 10;

const In6Addr = extern struct {
    s6_addr: [16]u8 align(4),
};

const in6addr_any_val = In6Addr{ .s6_addr = @splat(0) };
const in6addr_loopback_val = In6Addr{ .s6_addr = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 } };

extern "c" fn strtoul(nptr: [*:0]const u8, endptr: *?[*:0]u8, base: c_int) c_ulong;
extern "c" fn snprintf(str: [*]u8, size: usize, format: [*:0]const u8, ...) c_int;
extern "c" fn memcmp(s1: *const anyopaque, s2: *const anyopaque, n: usize) c_int;
extern "c" fn memmove(dest: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;
extern "c" fn strspn(s: [*:0]const u8, accept: [*:0]const u8) usize;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn strcpy(dest: [*]u8, src: [*:0]const u8) [*]u8;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&htonl, "htonl");
        symbol(&htons, "htons");
        symbol(&ntohl, "ntohl");
        symbol(&ntohs, "ntohs");
        symbol(&in6addr_any_val, "in6addr_any");
        symbol(&in6addr_loopback_val, "in6addr_loopback");
        if (builtin.link_libc) {
            symbol(&__inet_aton, "__inet_aton");
            symbol(&__inet_aton, "inet_aton");
            symbol(&inet_ntop, "inet_ntop");
            symbol(&inet_pton, "inet_pton");
        }
    }
}

fn htonl(n: u32) callconv(.c) u32 {
    return if (builtin.cpu.arch.endian() == .little) @byteSwap(n) else n;
}

fn htons(n: u16) callconv(.c) u16 {
    return if (builtin.cpu.arch.endian() == .little) @byteSwap(n) else n;
}

fn ntohl(n: u32) callconv(.c) u32 {
    return if (builtin.cpu.arch.endian() == .little) @byteSwap(n) else n;
}

fn ntohs(n: u16) callconv(.c) u16 {
    return if (builtin.cpu.arch.endian() == .little) @byteSwap(n) else n;
}

fn __inet_aton(s0: [*:0]const u8, dest: *anyopaque) callconv(.c) c_int {
    var s: [*:0]const u8 = s0;
    const d: [*]u8 = @ptrCast(dest);
    var a: [4]c_ulong = .{ 0, 0, 0, 0 };
    var z: ?[*:0]u8 = null;
    var i: usize = 0;

    while (i < 4) : (i += 1) {
        a[i] = strtoul(s, &z, 0);
        const zp = z orelse return 0;
        if (@intFromPtr(zp) == @intFromPtr(s) or (zp[0] != 0 and zp[0] != '.') or !std.ascii.isDigit(s[0]))
            return 0;
        if (zp[0] == 0) break;
        s = @ptrCast(zp + 1);
    }
    if (i == 4) return 0;
    if (i <= 0) {
        a[1] = a[0] & 0xffffff;
        a[0] >>= 24;
    }
    if (i <= 1) {
        a[2] = a[1] & 0xffff;
        a[1] >>= 16;
    }
    if (i <= 2) {
        a[3] = a[2] & 0xff;
        a[2] >>= 8;
    }
    for (0..4) |idx| {
        if (a[idx] > 255) return 0;
        d[idx] = @intCast(a[idx]);
    }
    return 1;
}

fn inet_ntop(af: c_int, a0: *const anyopaque, s: [*]u8, l: u32) callconv(.c) ?[*:0]const u8 {
    const a: [*]const u8 = @ptrCast(a0);
    var buf: [100]u8 = undefined;

    switch (af) {
        AF_INET => {
            const ret = snprintf(
                s,
                l,
                "%d.%d.%d.%d",
                @as(c_int, a[0]),
                @as(c_int, a[1]),
                @as(c_int, a[2]),
                @as(c_int, a[3]),
            );
            if (ret >= 0 and @as(u32, @intCast(ret)) < l)
                return @ptrCast(s);
        },
        AF_INET6 => {
            if (memcmp(a, "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff", 12) != 0) {
                _ = snprintf(
                    &buf,
                    buf.len,
                    "%x:%x:%x:%x:%x:%x:%x:%x",
                    256 * @as(c_int, a[0]) + @as(c_int, a[1]),
                    256 * @as(c_int, a[2]) + @as(c_int, a[3]),
                    256 * @as(c_int, a[4]) + @as(c_int, a[5]),
                    256 * @as(c_int, a[6]) + @as(c_int, a[7]),
                    256 * @as(c_int, a[8]) + @as(c_int, a[9]),
                    256 * @as(c_int, a[10]) + @as(c_int, a[11]),
                    256 * @as(c_int, a[12]) + @as(c_int, a[13]),
                    256 * @as(c_int, a[14]) + @as(c_int, a[15]),
                );
            } else {
                _ = snprintf(
                    &buf,
                    buf.len,
                    "%x:%x:%x:%x:%x:%x:%d.%d.%d.%d",
                    256 * @as(c_int, a[0]) + @as(c_int, a[1]),
                    256 * @as(c_int, a[2]) + @as(c_int, a[3]),
                    256 * @as(c_int, a[4]) + @as(c_int, a[5]),
                    256 * @as(c_int, a[6]) + @as(c_int, a[7]),
                    256 * @as(c_int, a[8]) + @as(c_int, a[9]),
                    256 * @as(c_int, a[10]) + @as(c_int, a[11]),
                    @as(c_int, a[12]),
                    @as(c_int, a[13]),
                    @as(c_int, a[14]),
                    @as(c_int, a[15]),
                );
            }
            var i: usize = 0;
            var best: usize = 0;
            var max: usize = 2;
            while (buf[i] != 0) : (i += 1) {
                if (i != 0 and buf[i] != ':') continue;
                const j = strspn(@ptrCast(buf[i..].ptr), ":0");
                if (j > max + @intFromBool(best == 0)) {
                    best = i;
                    max = j;
                }
            }
            if (max > 3) {
                buf[best] = ':';
                buf[best + 1] = ':';
                _ = memmove(@ptrCast(buf[best + 2 ..].ptr), @ptrCast(buf[best + max ..].ptr), i - best - max + 1);
            }
            if (strlen(@ptrCast(&buf)) < l) {
                _ = strcpy(s, @ptrCast(&buf));
                return @ptrCast(s);
            }
        },
        else => {
            std.c._errno().* = @backingInt(std.c.E.AFNOSUPPORT);
            return null;
        },
    }
    std.c._errno().* = @backingInt(std.c.E.NOSPC);
    return null;
}

fn hexval(c_arg: u8) c_int {
    if (c_arg -% '0' < 10) return @intCast(c_arg - '0');
    const c = c_arg | 32;
    if (c -% 'a' < 6) return @intCast(c - 'a' + 10);
    return -1;
}

fn inet_pton(af: c_int, s_arg: [*:0]const u8, a0: *anyopaque) callconv(.c) c_int {
    var ip: [8]u16 = undefined;
    const a: [*]u8 = @ptrCast(a0);
    var s: [*:0]const u8 = s_arg;
    var brk: c_int = -1;
    var need_v4: bool = false;

    if (af == AF_INET) {
        var i: usize = 0;
        while (i < 4) : (i += 1) {
            var v: c_int = 0;
            var j: usize = 0;
            while (j < 3 and s[j] != 0 and std.ascii.isDigit(s[j])) : (j += 1) {
                v = 10 * v + @as(c_int, s[j] - '0');
            }
            if (j == 0 or (j > 1 and s[0] == '0') or v > 255) return 0;
            a[i] = @intCast(v);
            if (s[j] == 0 and i == 3) return 1;
            if (s[j] != '.') return 0;
            s += j + 1;
        }
        return 0;
    } else if (af != AF_INET6) {
        std.c._errno().* = @backingInt(std.c.E.AFNOSUPPORT);
        return -1;
    }

    if (s[0] == ':') {
        s += 1;
        if (s[0] != ':') return 0;
    }

    var i: c_int = 0;
    while (true) : (i += 1) {
        if (s[0] == ':' and brk < 0) {
            brk = i;
            ip[@intCast(i & 7)] = 0;
            s += 1;
            if (s[0] == 0) break;
            if (i == 7) return 0;
            continue;
        }
        var v: c_int = 0;
        var j: usize = 0;
        while (j < 4) : (j += 1) {
            const d = hexval(s[j]);
            if (d < 0) break;
            v = 16 * v + d;
        }
        if (j == 0) return 0;
        ip[@intCast(i & 7)] = @intCast(v);
        if (s[j] == 0 and (brk >= 0 or i == 7)) break;
        if (i == 7) return 0;
        if (s[j] != ':') {
            if (s[j] != '.' or (i < 6 and brk < 0)) return 0;
            need_v4 = true;
            i += 1;
            break;
        }
        s += j + 1;
    }
    if (brk >= 0) {
        const u_brk: usize = @intCast(brk);
        const u_i: usize = @intCast(i);
        _ = memmove(
            @ptrCast(ip[u_brk + 7 - u_i ..].ptr),
            @ptrCast(ip[u_brk..].ptr),
            2 * (u_i + 1 - u_brk),
        );
        var j: usize = 0;
        while (j < 7 - u_i) : (j += 1) {
            ip[u_brk + j] = 0;
        }
    }
    for (0..8) |j| {
        a[2 * j] = @intCast(ip[j] >> 8);
        a[2 * j + 1] = @truncate(ip[j]);
    }
    if (need_v4 and inet_pton(AF_INET, s, @ptrCast(a + 12)) <= 0) return 0;
    return 1;
}
