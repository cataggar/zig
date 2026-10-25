const std = @import("std");
const builtin = @import("builtin");

extern fn __wasm_call_ctors() callconv(.c) void;

var initialized: c_int = 0;

export fn _initialize() callconv(.c) void {
    const prev: *volatile c_int = &initialized;
    if (prev.* != 0) {
        @trap();
    }
    prev.* = 1;

    __wasm_call_ctors();
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
        @export(&cabiRealloc, .{ .name = "cabi_realloc" });
    }
}
