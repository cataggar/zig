const std = @import("std");
const builtin = @import("builtin");

extern fn __wasm_call_ctors() callconv(.c) void;
extern fn __main_void() callconv(.c) c_int;
extern fn __wasm_call_dtors() callconv(.c) void;
extern "[task-return]wasi:cli/run@0.3.0#run" fn @"task-return"(result: i32) callconv(.c) void;

var started: c_int = 0;

fn runMain() c_int {
    const prev: *volatile c_int = &started;
    if (prev.* != 0) {
        @trap();
    }
    prev.* = 1;

    __wasm_call_ctors();

    const r = __main_void();

    __wasm_call_dtors();

    return r;
}

export fn _start() callconv(.c) void {
    const r = runMain();
    if (r != 0) {
        std.os.wasi.proc_exit(@bitCast(r));
    }
}

fn startWasip3Command() callconv(.c) void {
    const r = runMain();
    @"task-return"(if (r == 0) 0 else 1);
}

fn cabiRealloc(old_ptr: ?[*]u8, old_len: usize, alignment: usize, new_len: usize) callconv(.c) ?[*]u8 {
    if (alignment == 0 or (alignment & (alignment - 1)) != 0) return null;
    const log2_align: std.mem.Alignment = .fromByteUnits(alignment);
    if (new_len == 0) {
        if (old_ptr) |p| {
            if (old_len != 0) {
                std.heap.wasm_allocator.rawFree(p[0..old_len], log2_align, @returnAddress());
            }
        }
        return @ptrFromInt(alignment);
    }
    if (old_ptr) |p| {
        if (old_len != 0) {
            if (std.heap.wasm_allocator.rawResize(p[0..old_len], log2_align, new_len, @returnAddress())) {
                return p;
            }
            const new_p = std.heap.wasm_allocator.rawAlloc(new_len, log2_align, @returnAddress()) orelse return null;
            const copy_len = @min(old_len, new_len);
            @memcpy(new_p[0..copy_len], p[0..copy_len]);
            std.heap.wasm_allocator.rawFree(p[0..old_len], log2_align, @returnAddress());
            return new_p;
        }
    }
    return std.heap.wasm_allocator.rawAlloc(new_len, log2_align, @returnAddress());
}

comptime {
    if (builtin.os.tag == .wasip3) {
        @export(&startWasip3Command, .{ .name = "wasi:cli/run@0.3.0#run" });
        @export(&cabiRealloc, .{ .name = "cabi_realloc" });
    }
}
