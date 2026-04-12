const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

var environ_var: ?[*:null]?[*:0]u8 = null;

comptime {
    if (builtin.target.isMuslLibC()) {
        @export(&environ_var, .{ .name = "__environ", .linkage = .weak, .visibility = .hidden });
        @export(&environ_var, .{ .name = "___environ", .linkage = .weak, .visibility = .hidden });
        @export(&environ_var, .{ .name = "_environ", .linkage = .weak, .visibility = .hidden });
        @export(&environ_var, .{ .name = "environ", .linkage = .weak, .visibility = .hidden });
    }
}
