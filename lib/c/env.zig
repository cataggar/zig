const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

var environ_var: ?[*:null]?[*:0]u8 = null;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&environ_var, "__environ");
        symbol(&environ_var, "___environ");
        symbol(&environ_var, "_environ");
        symbol(&environ_var, "environ");
    }
}
