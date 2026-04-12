const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

var abort_lock: c_int = 0;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&abort_lock, "__abort_lock");
    }
}
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&_ExitLinux, "_Exit");
    }
}

fn _ExitLinux(exit_code: c_int) callconv(.c) noreturn {
    linux.exit_group(exit_code);
comptime {
    if (builtin.link_libc) {
        symbol(&quick_exit, "quick_exit");
    }
}

extern "c" fn __funcs_on_quick_exit() void;
extern "c" fn _Exit(code: c_int) noreturn;

fn quick_exit(code: c_int) callconv(.c) noreturn {
    __funcs_on_quick_exit();
    _Exit(code);
}
