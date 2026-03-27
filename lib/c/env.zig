const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

// C library dependencies.
extern "c" fn strncmp(a: [*:0]const u8, b: [*:0]const u8, n: usize) c_int;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn malloc(size: usize) ?[*]u8;
extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?[*]u8;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn memcpy(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;
extern "c" fn __strchrnul(s: [*:0]const u8, c: c_int) [*:0]const u8;
extern "c" fn issetugid() c_int;
extern "c" var __environ: ?[*:null]?[*:0]u8;

// ── __env_rm_add ───────────────────────────────────────────────────────
// Tracks dynamically allocated env strings so they can be freed.

var env_alloced: ?[*]?[*:0]u8 = null;
var env_alloced_n: usize = 0;

fn __env_rm_add(old: ?[*:0]u8, new_val: ?[*:0]u8) callconv(.c) void {
    var new = new_val;
    for (0..env_alloced_n) |i| {
        if (env_alloced.?[i] == old) {
            env_alloced.?[i] = new;
            free(old);
            return;
        } else if (env_alloced.?[i] == null and new != null) {
            env_alloced.?[i] = new;
            new = null;
        }
    }
    if (new == null) return;
    const t: ?[*]?[*:0]u8 = @ptrCast(@alignCast(realloc(env_alloced, @sizeOf(?[*:0]u8) * (env_alloced_n + 1))));
    if (t == null) return;
    env_alloced = t;
    t.?[env_alloced_n] = new;
    env_alloced_n += 1;
}

// ── __putenv ───────────────────────────────────────────────────────────

var oldenv: ?[*:null]?[*:0]u8 = null;

fn __putenv(s: [*:0]u8, l: usize, r: ?[*:0]u8) callconv(.c) c_int {
    var i: usize = 0;
    if (__environ) |env| {
        var e = env;
        while (e[0]) |entry| : ({
            e = @ptrCast(@as([*]?[*:0]u8, @ptrCast(e)) + 1);
            i += 1;
        }) {
            if (strncmp(s, entry, l + 1) == 0) {
                const tmp = entry;
                e[0] = s;
                __env_rm_add(tmp, r);
                return 0;
            }
        }
    }
    const ptr_size = @sizeOf(?[*:0]u8);
    var newenv: ?[*:null]?[*:0]u8 = undefined;
    if (__environ == oldenv) {
        newenv = @ptrCast(@alignCast(realloc(oldenv, ptr_size * (i + 2))));
        if (newenv == null) {
            free(r);
            return -1;
        }
    } else {
        newenv = @ptrCast(@alignCast(malloc(ptr_size * (i + 2))));
        if (newenv == null) {
            free(r);
            return -1;
        }
        if (i > 0) _ = memcpy(newenv.?, @as(*const anyopaque, @ptrCast(__environ.?)), ptr_size * i);
        free(oldenv);
    }
    const nv = newenv.?;
    @as([*]?[*:0]u8, @ptrCast(nv))[i] = s;
    @as([*]?[*:0]u8, @ptrCast(nv))[i + 1] = null;
    __environ = nv;
    oldenv = nv;
    if (r) |rv| __env_rm_add(null, rv);
    return 0;
}

// ── Public functions ───────────────────────────────────────────────────

fn getenv(name: [*:0]const u8) callconv(.c) ?[*:0]u8 {
    const l = @intFromPtr(__strchrnul(name, '=')) - @intFromPtr(name);
    if (l != 0 and name[l] == 0) {
        if (__environ) |env| {
            var e: [*]?[*:0]u8 = @ptrCast(env);
            while (e[0]) |entry| : (e += 1) {
                if (strncmp(name, entry, l) == 0 and entry[l] == '=')
                    return @ptrCast(@as([*]u8, @ptrCast(entry)) + l + 1);
            }
        }
    }
    return null;
}

fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) callconv(.c) c_int {
    const l1 = @intFromPtr(__strchrnul(name, '=')) - @intFromPtr(name);
    if (l1 == 0 or name[l1] != 0) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    if (overwrite == 0 and getenv(name) != null) return 0;

    const l2 = strlen(value);
    const s: ?[*]u8 = malloc(l1 + l2 + 2);
    if (s == null) return -1;
    _ = memcpy(s.?, @as(*const anyopaque, @ptrCast(name)), l1);
    s.?[l1] = '=';
    _ = memcpy(@ptrCast(s.? + l1 + 1), @as(*const anyopaque, @ptrCast(value)), l2 + 1);
    return __putenv(@ptrCast(s.?), l1, @ptrCast(s.?));
}

fn putenv(s: [*:0]u8) callconv(.c) c_int {
    const l = @intFromPtr(__strchrnul(s, '=')) - @intFromPtr(s);
    if (l == 0 or s[l] == 0) return unsetenv(s);
    return __putenv(s, l, null);
}

fn unsetenv(name: [*:0]const u8) callconv(.c) c_int {
    const l = @intFromPtr(__strchrnul(name, '=')) - @intFromPtr(name);
    if (l == 0 or name[l] != 0) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    if (__environ) |env| {
        var e: [*]?[*:0]u8 = @ptrCast(env);
        var eo: [*]?[*:0]u8 = e;
        while (e[0]) |entry| : (e += 1) {
            if (strncmp(name, entry, l) == 0 and entry[l] == '=') {
                __env_rm_add(entry, null);
            } else {
                if (eo != e) eo[0] = entry;
                eo += 1;
            }
        }
        if (eo != e) eo[0] = null;
    }
    return 0;
}

fn clearenv() callconv(.c) c_int {
    if (__environ) |env| {
        var e: [*]?[*:0]u8 = @ptrCast(env);
        __environ = null;
        while (e[0]) |entry| : (e += 1) {
            __env_rm_add(entry, null);
        }
    } else {
        __environ = null;
    }
    return 0;
}

fn secure_getenv(name: [*:0]const u8) callconv(.c) ?[*:0]u8 {
    if (issetugid() != 0) return null;
    return getenv(name);
}

comptime {
    if (builtin.link_libc) {
        symbol(&__env_rm_add, "__env_rm_add");
        symbol(&__putenv, "__putenv");
        symbol(&getenv, "getenv");
        symbol(&setenv, "setenv");
        symbol(&putenv, "putenv");
        symbol(&unsetenv, "unsetenv");
        symbol(&clearenv, "clearenv");
        symbol(&secure_getenv, "secure_getenv");
    }
}
