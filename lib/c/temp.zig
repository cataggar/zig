const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&__randname, "__randname");
        symbol(&mkdtemp, "mkdtemp");
        symbol(&__mkostemps, "__mkostemps");
        symbol(&__mkostemps, "mkostemps");
        symbol(&mkstemp, "mkstemp");
        symbol(&mkstemps, "mkstemps");
        symbol(&mkostemp, "mkostemp");
        symbol(&mktemp, "mktemp");
    }
}

/// Generate a random 6-character suffix for temp file names.
/// Replaces musl's __randname which used __pthread_self()->tid.
fn __randname(template: [*]u8) callconv(.c) [*]u8 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.REALTIME, &ts);
    var r: usize = @bitCast(ts.sec +% ts.nsec +% @as(isize, linux.gettid()) *% 65537);
    for (0..6) |i| {
        template[i] = @intCast(@as(u8, 'A') + (@as(u8, @truncate(r & 15))) + (@as(u8, @truncate(r & 16)) * 2));
        r >>= 5;
    }
    return template;
}

fn sliceFromSentinel(ptr: [*:0]u8) [:0]u8 {
    var len: usize = 0;
    while (ptr[len] != 0) len += 1;
    return ptr[0..len :0];
}

fn mkdtemp(template: [*:0]u8) callconv(.c) ?[*:0]u8 {
    const s = sliceFromSentinel(template);
    if (s.len < 6 or !std.mem.eql(u8, s[s.len - 6 ..], "XXXXXX")) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return null;
    }
    var retries: u32 = 100;
    while (retries > 0) : (retries -= 1) {
        _ = __randname(template + s.len - 6);
        const rc: isize = @bitCast(linux.mkdirat(linux.AT.FDCWD, @ptrCast(template), 0o700));
        if (rc == 0) return template;
        if (std.c._errno().* != @intFromEnum(linux.E.EXIST)) break;
    }
    @memcpy((template + s.len - 6)[0..6], "XXXXXX");
    return null;
}

fn __mkostemps(template: [*:0]u8, len_arg: c_int, flags_arg: c_int) callconv(.c) c_int {
    const s = sliceFromSentinel(template);
    const len: usize = if (len_arg >= 0) @intCast(len_arg) else {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    };
    if (s.len < 6 or len > s.len - 6 or
        !std.mem.eql(u8, s[s.len - len - 6 .. s.len - len], "XXXXXX"))
    {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    // Build O flags: clear ACCMODE from caller, set RDWR|CREAT|EXCL
    const raw_flags: u32 = @as(u32, @intCast(flags_arg & ~@as(c_int, 3)));
    var oflags: linux.O = @bitCast(raw_flags);
    oflags.ACCMODE = .RDWR;
    oflags.CREAT = true;
    oflags.EXCL = true;
    var retries: u32 = 100;
    while (retries > 0) : (retries -= 1) {
        _ = __randname(template + s.len - len - 6);
        const rc = errno(linux.open(@ptrCast(template), oflags, 0o600));
        if (rc >= 0) return rc;
        if (std.c._errno().* != @intFromEnum(linux.E.EXIST)) break;
    }
    @memcpy((template + s.len - len - 6)[0..6], "XXXXXX");
    return -1;
}

fn mkstemp(template: [*:0]u8) callconv(.c) c_int {
    return __mkostemps(template, 0, 0);
}

fn mkstemps(template: [*:0]u8, len: c_int) callconv(.c) c_int {
    return __mkostemps(template, len, 0);
}

fn mkostemp(template: [*:0]u8, flags: c_int) callconv(.c) c_int {
    return __mkostemps(template, 0, flags);
}

fn mktemp(template: [*:0]u8) callconv(.c) [*:0]u8 {
    const s = sliceFromSentinel(template);
    if (s.len < 6 or !std.mem.eql(u8, s[s.len - 6 ..], "XXXXXX")) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        template[0] = 0;
        return template;
    }
    var retries: u32 = 100;
    while (retries > 0) : (retries -= 1) {
        _ = __randname(template + s.len - 6);
        // Use statx to check existence (avoids needing struct stat)
        var stx: linux.Statx = undefined;
        const rc: isize = @bitCast(linux.statx(
            linux.AT.FDCWD,
            @ptrCast(template),
            0,
            .{},
            &stx,
        ));
        if (rc < 0) {
            const e: linux.E = @enumFromInt(@as(u16, @intCast(-rc)));
            if (e != .NOENT) template[0] = 0;
            return template;
        }
    }
    template[0] = 0;
    std.c._errno().* = @intFromEnum(linux.E.EXIST);
    return template;
}
