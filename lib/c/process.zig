const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

extern "c" fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) callconv(.c) c_int;
extern "c" fn getenv(name: [*:0]const u8) callconv(.c) ?[*:0]const u8;
extern "c" var __environ: [*:null]?[*:0]u8;

comptime {
    if (builtin.link_libc) {
        symbol(&__execvpe, "__execvpe");
        symbol(&__execvpe, "execvpe");
        symbol(&execvpImpl, "execvp");
    }
}

const NAME_MAX = 255;
const PATH_MAX = 4096;

fn strchrnul(s: [*]const u8, c: u8) [*]const u8 {
    var p = s;
    while (p[0] != 0 and p[0] != c) p += 1;
    return p;
}

fn strnlen(s: [*]const u8, max: usize) usize {
    var i: usize = 0;
    while (i < max and s[i] != 0) i += 1;
    return i;
}

fn __execvpe(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) callconv(.c) c_int {
    std.c._errno().* = @intFromEnum(linux.E.NOENT);
    if (file[0] == 0) return -1;

    // If file contains '/', exec directly
    if (std.mem.indexOfScalar(u8, std.mem.span(file), '/') != null)
        return execve(file, argv, envp);

    const path = getenv("PATH") orelse "/usr/local/bin:/bin:/usr/bin";
    const k = strnlen(file, NAME_MAX + 1);
    if (k > NAME_MAX) {
        std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
        return -1;
    }
    const l = strnlen(path, PATH_MAX - 1) + 1;

    var buf: [PATH_MAX + NAME_MAX + 2]u8 = undefined;
    var seen_eacces = false;
    var p: [*]const u8 = path;

    while (true) {
        const z = strchrnul(p, ':');
        const seg_len = @intFromPtr(z) - @intFromPtr(p);
        if (seg_len < l) {
            @memcpy(buf[0..seg_len], p[0..seg_len]);
            var pos = seg_len;
            if (seg_len > 0) {
                buf[pos] = '/';
                pos += 1;
            }
            @memcpy(buf[pos..][0 .. k + 1], file[0 .. k + 1]);
            buf[pos + k] = 0;
            _ = execve(@ptrCast(buf[0 .. pos + k :0]), argv, envp);
            switch (@as(linux.E, @enumFromInt(std.c._errno().*))) {
                .ACCES => seen_eacces = true,
                .NOENT, .NOTDIR => {},
                else => return -1,
            }
        }
        if (z[0] == 0) break;
        p = z + 1;
    }
    if (seen_eacces) std.c._errno().* = @intFromEnum(linux.E.ACCES);
    return -1;
}

fn execvpImpl(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) callconv(.c) c_int {
    return __execvpe(file, argv, @ptrCast(&__environ));
}
