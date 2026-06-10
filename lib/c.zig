//! Multi-target implementation of libc, providing ABI compatibility with
//! bundled libcs.
//!
//! mingw-w64 libc is not fully statically linked, so some symbols don't need
//! to be exported.

const builtin = @import("builtin");
const std = @import("std");

// Avoid dragging in the runtime safety mechanisms into this .o file, unless
// we're trying to test zigc.
pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    std.debug.no_panic;

/// It is possible that this libc is being linked into a different test
/// compilation, as opposed to being tested itself. In such case,
/// `builtin.link_libc` will be `true` along with `builtin.is_test`.
///
/// When we don't have a complete libc, `builtin.link_libc` will be `false` and
/// we will be missing externally provided symbols, such as `_errno` from
/// ucrtbase.dll. In such case, we must avoid analyzing otherwise exported
/// functions because it would cause undefined symbol usage.
///
/// Unfortunately such logic cannot be automatically done in this function body
/// since `func` will always be analyzed by the time we get here, so `comptime`
/// blocks will need to each check for `builtin.link_libc` and skip exports
/// when the exported functions have libc dependencies not provided by this
/// compilation unit.
pub inline fn symbol(comptime func: *const anyopaque, comptime name: []const u8) void {
    @export(func, .{
        .name = name,
        // Normally, libc goes into a static archive, making all symbols
        // overridable. However, Zig supports including the libc functions as part
        // of the Zig Compilation Unit, so to support this use case we make all
        // symbols weak.
        .linkage = .weak,
        // For WebAssembly, hidden visibility allows the symbol to be resolved to
        // other modules, but will not export it to the host runtime.
        .visibility = .hidden,
    });
}

/// Given a low-level syscall return value, sets errno and returns `-1`, or on
/// success returns the result.
pub fn errno(syscall_return_value: usize) c_int {
    return switch (builtin.os.tag) {
        .linux => {
            const signed: isize = @bitCast(syscall_return_value);
            const casted: c_int = @intCast(signed);
            if (casted < 0) {
                @branchHint(.unlikely);
                std.c._errno().* = -casted;
                return -1;
            }
            return casted;
        },
        else => comptime unreachable,
    };
}

/// Like `errno`, but for syscalls that return `ssize_t` (e.g. read, write).
pub fn errnoSize(syscall_return_value: usize) isize {
    return switch (builtin.os.tag) {
        .linux => {
            const signed: isize = @bitCast(syscall_return_value);
            if (signed < 0) {
                @branchHint(.unlikely);
                std.c._errno().* = @intCast(-signed);
                return -1;
            }
            return signed;
        },
        else => comptime unreachable,
    };
}

pub inline fn syscallArg(value: anytype) std.os.linux.syscall_arg_t {
    const Arg = std.os.linux.syscall_arg_t;
    return switch (@typeInfo(@TypeOf(value))) {
        .int => |int| if (int.signedness == .signed)
            @bitCast(@as(@Int(.signed, @bitSizeOf(Arg)), @intCast(value)))
        else
            @intCast(value),
        .@"enum" => @intCast(@intFromEnum(value)),
        else => @intCast(value),
    };
}

comptime {
    _ = @import("c/crypt.zig");
    _ = @import("c/ctype.zig");
    _ = @import("c/errno.zig");
    _ = @import("c/inttypes.zig");
    if (!builtin.target.isMinGW()) {
        _ = @import("c/malloc.zig");
    }
    _ = @import("c/math.zig");
    _ = @import("c/complex.zig");
    _ = @import("c/pthread.zig");
    _ = @import("c/stdlib.zig");
    _ = @import("c/string.zig");
    _ = @import("c/strings.zig");
    _ = @import("c/wchar.zig");

    if (builtin.os.tag == .linux) {
        _ = @import("c/dirent.zig");
        _ = @import("c/fcntl.zig");
        _ = @import("c/internal.zig");
        _ = @import("c/ipc.zig");
        _ = @import("c/linux.zig");
        _ = @import("c/misc.zig");
        _ = @import("c/sched.zig");
        _ = @import("c/search.zig");
        _ = @import("c/stat.zig");
        _ = @import("c/stdio.zig");
        _ = @import("c/stropts.zig");
        _ = @import("c/temp.zig");
        _ = @import("c/termios.zig");
        _ = @import("c/time.zig");
        _ = @import("c/unistd.zig");

        _ = @import("c/sys/capability.zig");
        _ = @import("c/sys/file.zig");
        _ = @import("c/sys/mman.zig");
        _ = @import("c/sys/reboot.zig");
        _ = @import("c/sys/select.zig");
        _ = @import("c/sys/utsname.zig");
    }
    if (builtin.target.isWasiLibC()) {
        _ = @import("c/search.zig");
        _ = @import("c/unistd.zig");
    }
}
