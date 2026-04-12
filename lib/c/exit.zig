const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

var abort_lock: c_int = 0;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&abort_lock, "__abort_lock");
    }
}
