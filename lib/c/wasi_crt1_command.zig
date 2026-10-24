const std = @import("std");

extern fn __wasm_call_ctors() callconv(.c) void;
extern fn __main_void() callconv(.c) c_int;
extern fn __wasm_call_dtors() callconv(.c) void;

var started: c_int = 0;

export fn _start() callconv(.c) void {
    const prev: *volatile c_int = &started;
    if (prev.* != 0) {
        @trap();
    }
    prev.* = 1;

    __wasm_call_ctors();

    const r = __main_void();

    __wasm_call_dtors();

    if (r != 0) {
        std.os.wasi.proc_exit(@bitCast(r));
    }
}
