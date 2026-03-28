const builtin = @import("builtin");
const std = @import("std");

const symbol = @import("../c.zig").symbol;

// ── __stack_chk_fail / __stack_chk_guard / __init_ssp ──────────────────

var __stack_chk_guard: usize = 0;

fn __init_ssp(entropy: ?*const anyopaque) callconv(.c) void {
    if (entropy) |ent| {
        __stack_chk_guard = @as(*const usize, @ptrCast(@alignCast(ent))).*;
    } else {
        __stack_chk_guard = @intFromPtr(&__stack_chk_guard) *% 1103515245;
    }
    // On 64-bit, zero out the second byte to prevent string-based leaks.
    if (@sizeOf(usize) >= 8) {
        const bytes: *[8]u8 = @ptrCast(&__stack_chk_guard);
        bytes[1] = 0;
    }
}

fn __stack_chk_fail() callconv(.c) noreturn {
    @trap();
}

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&__stack_chk_guard, "__stack_chk_guard");
        symbol(&__init_ssp, "__init_ssp");
        symbol(&__stack_chk_fail, "__stack_chk_fail");
        symbol(&__stack_chk_fail, "__stack_chk_fail_local");
    }
}
