const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.link_libc) {
        symbol(&realpath, "realpath");
    }
}

extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8;
extern "c" fn readlink(path: [*:0]const u8, buf: [*]u8, bufsiz: usize) isize;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn __strchrnul(s: [*:0]const u8, c: c_int) [*:0]const u8;
extern "c" fn strnlen(s: [*]const u8, maxlen: usize) usize;
extern "c" fn memcpy(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;
extern "c" fn memmove(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;
extern "c" fn strlen(s: [*:0]const u8) usize;

const PATH_MAX = 4096;
const SYMLOOP_MAX = 40;

fn slash_len(s: []const u8) usize {
    var n: usize = 0;
    while (n < s.len and s[n] == '/') : (n += 1) {}
    return n;
}

fn realpath(filename: ?[*:0]const u8, resolved: ?[*]u8) callconv(.c) ?[*:0]u8 {
    const fname = filename orelse {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return null;
    };
    const l = strnlen(@ptrCast(fname), PATH_MAX + 1);
    if (l == 0) {
        std.c._errno().* = @intFromEnum(linux.E.NOENT);
        return null;
    }
    if (l >= PATH_MAX) {
        std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
        return null;
    }

    var stack: [PATH_MAX + 1]u8 = undefined;
    var output: [PATH_MAX]u8 = undefined;
    var cnt: usize = 0;
    var nup: usize = 0;
    var check_dir: bool = false;

    var p: usize = PATH_MAX + 1 - l - 1;
    var q: usize = 0;
    _ = memcpy(@ptrCast(&stack[p]), @as(*const anyopaque, @ptrCast(fname)), l + 1);

    restart: while (true) {
        while (true) {
            p += slash_len(stack[p..]);
            if (stack[p] == '/') {
                check_dir = false;
                nup = 0;
                q = 0;
                output[q] = '/';
                q += 1;
                p += 1;
                if (stack[p] == '/' and stack[p + 1] != '/') {
                    output[q] = '/';
                    q += 1;
                }
                continue;
            }

            const z = @intFromPtr(__strchrnul(@ptrCast(stack[p..].ptr), '/')) - @intFromPtr(&stack[p]);
            const l0 = z;
            var comp_l = z;

            if (comp_l == 0 and !check_dir) break;

            if (comp_l == 1 and stack[p] == '.') {
                p += comp_l;
                continue;
            }

            if (q > 0 and output[q - 1] != '/') {
                if (p == 0) {
                    std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
                    return null;
                }
                p -= 1;
                stack[p] = '/';
                comp_l += 1;
            }
            if (q + comp_l >= PATH_MAX) {
                std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
                return null;
            }
            _ = memcpy(@ptrCast(&output[q]), @as(*const anyopaque, @ptrCast(&stack[p])), comp_l);
            output[q + comp_l] = 0;
            p += comp_l;

            var up = false;
            if (l0 == 2 and stack[p - 2] == '.' and stack[p - 1] == '.') {
                up = true;
                if (q <= 3 * nup) {
                    nup += 1;
                    q += comp_l;
                    continue;
                }
                if (!check_dir) {
                    // skip_readlink path
                    check_dir = false;
                    while (q > 0 and output[q - 1] != '/') q -= 1;
                    if (q > 1 and (q > 2 or output[0] != '/')) q -= 1;
                    continue;
                }
            }
            const k = readlink(@ptrCast(output[0..q + comp_l :0]), &stack, p);
            if (k == @as(isize, @intCast(p))) {
                std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
                return null;
            }
            if (k == 0) {
                std.c._errno().* = @intFromEnum(linux.E.NOENT);
                return null;
            }
            if (k < 0) {
                if (std.c._errno().* != @intFromEnum(linux.E.INVAL)) return null;
                // Not a symlink — skip_readlink
                check_dir = false;
                if (up) {
                    while (q > 0 and output[q - 1] != '/') q -= 1;
                    if (q > 1 and (q > 2 or output[0] != '/')) q -= 1;
                    continue;
                }
                if (l0 != 0) q += comp_l;
                check_dir = stack[p] != 0;
                continue;
            }
            cnt += 1;
            if (cnt == SYMLOOP_MAX) {
                std.c._errno().* = @intFromEnum(linux.E.LOOP);
                return null;
            }
            const uk: usize = @intCast(k);
            if (stack[uk - 1] == '/') {
                while (stack[p] == '/') p += 1;
            }
            p -= uk;
            _ = memmove(@ptrCast(&stack[p]), @as(*const anyopaque, @ptrCast(&stack[0])), uk);
            continue :restart;
        }
        break;
    }

    output[q] = 0;

    if (output[0] != '/') {
        if (getcwd(&stack, stack.len) == null) return null;
        var gl: usize = strlen(@ptrCast(&stack));
        p = 0;
        while (nup > 0) : (nup -= 1) {
            while (gl > 1 and stack[gl - 1] != '/') gl -= 1;
            if (gl > 1) gl -= 1;
            p += 2;
            if (p < q) p += 1;
        }
        if (q - p > 0 and stack[gl - 1] != '/') {
            stack[gl] = '/';
            gl += 1;
        }
        if (gl + (q - p) + 1 >= PATH_MAX) {
            std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
            return null;
        }
        _ = memmove(@ptrCast(&output[gl]), @as(*const anyopaque, @ptrCast(&output[p])), q - p + 1);
        _ = memcpy(@ptrCast(&output), @as(*const anyopaque, @ptrCast(&stack)), gl);
        q = gl + q - p;
    }

    if (resolved) |r| {
        _ = memcpy(r, @as(*const anyopaque, @ptrCast(&output)), q + 1);
        return @ptrCast(r);
    } else {
        return strdup(@ptrCast(output[0..q :0]));
    }
}
