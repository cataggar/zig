const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC()) {
        // Self-contained stubs (no C library dependencies).
        symbol(&dladdr, "dladdr");
        symbol(&__tlsdesc_static, "__tlsdesc_static");
        symbol(&__tlsdesc_static, "__tlsdesc_dynamic");

        // Functions with C library dependencies (dlerror.c provides
        // __dl_seterr and __dl_invalid_handle).
        if (builtin.link_libc) {
            symbol(&dlclose, "dlclose");
            symbol(&dlinfo, "dlinfo");
            symbol(&dlopen, "dlopen");
            symbol(&dlsym, "dlsym");
            symbol(&__dlsym_stub, "__dlsym");
            if (@sizeOf(c_long) < 8) {
                symbol(&__dlsym_stub, "__dlsym_redir_time64");
            }
        }
    }
}

const RTLD_DI_LINKMAP = 2;

// Self-contained stubs that return stub values. The dynamic linker
// overrides these with real implementations when present.

fn dladdr(addr: ?*const anyopaque, info: ?*anyopaque) callconv(.c) c_int {
    _ = addr;
    _ = info;
    return 0;
}

fn __tlsdesc_static() callconv(.c) isize {
    return 0;
}

// Functions depending on C library symbols from dlerror.c.

extern fn __dl_seterr([*:0]const u8, ...) callconv(.c) void;
extern fn __dl_invalid_handle(?*anyopaque) callconv(.c) c_int;

fn dlclose(p: ?*anyopaque) callconv(.c) c_int {
    return __dl_invalid_handle(p);
}

fn dlinfo(dso: ?*anyopaque, req: c_int, res: ?*anyopaque) callconv(.c) c_int {
    if (__dl_invalid_handle(dso) != 0) return -1;
    if (req != RTLD_DI_LINKMAP) {
        __dl_seterr("Unsupported request %d", req);
        return -1;
    }
    const ptr: *?*anyopaque = @ptrCast(@alignCast(res));
    ptr.* = dso;
    return 0;
}

fn dlopen(file: ?[*:0]const u8, mode: c_int) callconv(.c) ?*anyopaque {
    _ = file;
    _ = mode;
    __dl_seterr("Dynamic loading not supported");
    return null;
}

fn dlsym(p: ?*anyopaque, s: ?[*:0]const u8) callconv(.c) ?*anyopaque {
    return __dlsym_stub(p, s, null);
}

fn __dlsym_stub(p: ?*anyopaque, s: ?[*:0]const u8, ra: ?*anyopaque) callconv(.c) ?*anyopaque {
    _ = p;
    _ = ra;
    __dl_seterr("Symbol not found: %s", s);
    return null;
}
