const builtin = @import("builtin");
const std = @import("std");

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.link_libc) {
        symbol(&vwarn, "vwarn");
        symbol(&vwarnx, "vwarnx");
        symbol(&verr, "verr");
        symbol(&verrx, "verrx");
        symbol(&warn_fn, "warn");
        symbol(&warnx_fn, "warnx");
        symbol(&err_fn, "err");
        symbol(&errx_fn, "errx");
    }
}

const VaList = std.builtin.VaList;

extern "c" var stderr: *anyopaque;
extern "c" var __progname: [*:0]const u8;
extern "c" fn fprintf(stream: *anyopaque, fmt: [*:0]const u8, ...) c_int;
extern "c" fn vfprintf(stream: *anyopaque, fmt: [*:0]const u8, ap: VaList) c_int;
extern "c" fn fputs(s: [*:0]const u8, stream: *anyopaque) c_int;
extern "c" fn putc(c: c_int, stream: *anyopaque) c_int;
extern "c" fn perror(s: ?[*:0]const u8) void;
extern "c" fn exit(status: c_int) noreturn;

fn vwarn(fmt: ?[*:0]const u8, ap: VaList) callconv(.c) void {
    _ = fprintf(stderr, "%s: ", __progname);
    if (fmt) |f| {
        _ = vfprintf(stderr, f, ap);
        _ = fputs(": ", stderr);
    }
    perror(null);
}

fn vwarnx(fmt: ?[*:0]const u8, ap: VaList) callconv(.c) void {
    _ = fprintf(stderr, "%s: ", __progname);
    if (fmt) |f| _ = vfprintf(stderr, f, ap);
    _ = putc('\n', stderr);
}

fn verr(status: c_int, fmt: ?[*:0]const u8, ap: VaList) callconv(.c) noreturn {
    vwarn(fmt, ap);
    exit(status);
}

fn verrx(status: c_int, fmt: ?[*:0]const u8, ap: VaList) callconv(.c) noreturn {
    vwarnx(fmt, ap);
    exit(status);
}

fn warn_fn(fmt: ?[*:0]const u8, ...) callconv(.c) void {
    const ap = @cVaStart();
    vwarn(fmt, @as(VaList, @bitCast(ap)));
}

fn warnx_fn(fmt: ?[*:0]const u8, ...) callconv(.c) void {
    const ap = @cVaStart();
    vwarnx(fmt, @as(VaList, @bitCast(ap)));
}

fn err_fn(status: c_int, fmt: ?[*:0]const u8, ...) callconv(.c) noreturn {
    const ap = @cVaStart();
    verr(status, fmt, @as(VaList, @bitCast(ap)));
}

fn errx_fn(status: c_int, fmt: ?[*:0]const u8, ...) callconv(.c) noreturn {
    const ap = @cVaStart();
    verrx(status, fmt, @as(VaList, @bitCast(ap)));
}
