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
