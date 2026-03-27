const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

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
