const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

extern "c" fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) callconv(.c) c_int;
extern "c" fn execvp(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) callconv(.c) c_int;
extern "c" var __environ: [*:null]?[*:0]u8;

const MAX_ARGS = 256;

comptime {
    if (builtin.link_libc) {
        symbol(&execlImpl, "execl");
        symbol(&execleImpl, "execle");
        symbol(&execlpImpl, "execlp");
    }
}

fn execlImpl(path: [*:0]const u8, argv0: ?[*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    var argv_buf: [MAX_ARGS + 1]?[*:0]const u8 = undefined;
    argv_buf[0] = argv0;
    var argc: usize = 1;
    while (argc < MAX_ARGS) : (argc += 1) {
        argv_buf[argc] = @cVaArg(&ap, ?[*:0]const u8);
        if (argv_buf[argc] == null) break;
    }
    argv_buf[argc] = null;

    return execve(path, @ptrCast(&argv_buf), @ptrCast(&__environ));
}

fn execleImpl(path: [*:0]const u8, argv0: ?[*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    var argv_buf: [MAX_ARGS + 1]?[*:0]const u8 = undefined;
    argv_buf[0] = argv0;
    var argc: usize = 1;
    while (argc < MAX_ARGS) : (argc += 1) {
        argv_buf[argc] = @cVaArg(&ap, ?[*:0]const u8);
        if (argv_buf[argc] == null) break;
    }
    argv_buf[argc] = null;
    // envp follows the null terminator
    const envp = @cVaArg(&ap, [*:null]const ?[*:0]const u8);

    return execve(path, @ptrCast(&argv_buf), envp);
}

fn execlpImpl(file: [*:0]const u8, argv0: ?[*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    var argv_buf: [MAX_ARGS + 1]?[*:0]const u8 = undefined;
    argv_buf[0] = argv0;
    var argc: usize = 1;
    while (argc < MAX_ARGS) : (argc += 1) {
        argv_buf[argc] = @cVaArg(&ap, ?[*:0]const u8);
        if (argv_buf[argc] == null) break;
    }
    argv_buf[argc] = null;

    return execvp(file, @ptrCast(&argv_buf));
}
