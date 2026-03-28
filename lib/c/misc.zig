const builtin = @import("builtin");
const std = @import("std");

const symbol = @import("../c.zig").symbol;

const VaList = std.builtin.VaList;

extern "c" fn __lock(lock: *c_int) void;
extern "c" fn __unlock(lock: *c_int) void;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn socket(domain: c_int, sock_type: c_int, protocol: c_int) c_int;
extern "c" fn connect(fd: c_int, addr: *const anyopaque, len: c_uint) c_int;
extern "c" fn send(fd: c_int, buf: *const anyopaque, len: usize, flags: c_int) isize;
extern "c" fn time(tloc: ?*i64) i64;
extern "c" fn gmtime_r(timep: *const i64, result: *anyopaque) ?*anyopaque;
extern "c" fn strftime(s: [*]u8, max: usize, fmt: [*:0]const u8, tm: *const anyopaque) usize;
extern "c" fn getpid() c_int;
extern "c" fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern "c" fn vsnprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ap: VaList) c_int;
extern "c" fn dprintf(fd: c_int, fmt: [*:0]const u8, ...) c_int;
extern "c" fn strnlen(s: [*]const u8, maxlen: usize) usize;
extern "c" fn memcpy(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;

const AF_UNIX = 1;
const SOCK_DGRAM = 2;
const SOCK_CLOEXEC = 0o2000000;
const O_WRONLY = 1;
const O_NOCTTY = 0o400;
const O_CLOEXEC = 0o2000000;
const LOG_USER = 1 << 3;
const LOG_FACMASK = 0x3f8;
const LOG_PID = 0x01;
const LOG_CONS = 0x02;
const LOG_NDELAY = 0x08;
const LOG_PERROR = 0x20;
const LOG_MASK_FN = struct {
    fn mask(p: c_int) c_int {
        return @as(c_int, 1) << @intCast(p);
    }
};

const log_addr = extern struct {
    sun_family: c_short,
    sun_path: [9]u8,
}{ .sun_family = AF_UNIX, .sun_path = "/dev/log\x00".* };

var sl_lock: c_int = 0;
var log_ident: [32]u8 = .{0} ** 32;
var log_opt: c_int = 0;
var log_facility: c_int = LOG_USER;
var log_mask_val: c_int = 0xff;
var log_fd: c_int = -1;

fn openlog_internal() void {
    log_fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (log_fd >= 0) _ = connect(log_fd, &log_addr, @sizeOf(@TypeOf(log_addr)));
}

fn is_lost_conn(e: c_int) bool {
    return e == 111 or e == 104 or e == 107 or e == 32; // ECONNREFUSED, ECONNRESET, ENOTCONN, EPIPE
}

fn _vsyslog(priority: c_int, message: [*:0]const u8, ap: VaList) void {
    var timebuf: [16]u8 = undefined;
    var buf: [1024]u8 = undefined;
    const errno_save = std.c._errno().*;

    if (log_fd < 0) openlog_internal();
    var prio = priority;
    if (prio & LOG_FACMASK == 0) prio |= log_facility;

    var now: i64 = time(null);
    var tm_buf: [64]u8 = undefined;
    _ = gmtime_r(&now, &tm_buf);
    _ = strftime(&timebuf, timebuf.len, "%b %e %T", &tm_buf);

    const pid: c_int = if (log_opt & LOG_PID != 0) getpid() else 0;
    var hlen: c_int = 0;
    const l_raw = snprintf(&buf, buf.len, "<%d>%s %n%s%s%.0d%s: ",
        prio, &timebuf, &hlen,
        &log_ident,
        if (pid != 0) @as([*:0]const u8, "[") else @as([*:0]const u8, ""),
        pid,
        if (pid != 0) @as([*:0]const u8, "]") else @as([*:0]const u8, ""));
    var l: usize = if (l_raw >= 0) @intCast(l_raw) else return;

    std.c._errno().* = errno_save;
    const l2 = vsnprintf(buf[l..].ptr, buf.len - l, message, ap);
    if (l2 >= 0) {
        if (@as(usize, @intCast(l2)) >= buf.len - l) {
            l = buf.len - 1;
        } else {
            l += @intCast(l2);
        }
        if (buf[l - 1] != '\n') {
            buf[l] = '\n';
            l += 1;
        }
        if (send(log_fd, &buf, l, 0) < 0 and
            (!is_lost_conn(std.c._errno().*) or
            connect(log_fd, &log_addr, @sizeOf(@TypeOf(log_addr))) < 0 or
            send(log_fd, &buf, l, 0) < 0) and
            (log_opt & LOG_CONS != 0))
        {
            const fd = open("/dev/console", O_WRONLY | O_NOCTTY | O_CLOEXEC);
            if (fd >= 0) {
                _ = dprintf(fd, "%.*s", @as(c_int, @intCast(l)) - hlen, buf[@intCast(hlen)..].ptr);
                _ = close(fd);
            }
        }
        if (log_opt & LOG_PERROR != 0)
            _ = dprintf(2, "%.*s", @as(c_int, @intCast(l)) - hlen, buf[@intCast(hlen)..].ptr);
    }
}

fn setlogmask(maskpri: c_int) callconv(.c) c_int {
    __lock(&sl_lock);
    const ret = log_mask_val;
    if (maskpri != 0) log_mask_val = maskpri;
    __unlock(&sl_lock);
    return ret;
}

fn closelog() callconv(.c) void {
    __lock(&sl_lock);
    _ = close(log_fd);
    log_fd = -1;
    __unlock(&sl_lock);
}

fn openlog(ident: ?[*:0]const u8, opt: c_int, facility: c_int) callconv(.c) void {
    __lock(&sl_lock);
    if (ident) |id| {
        const n = strnlen(@ptrCast(id), log_ident.len - 1);
        _ = memcpy(&log_ident, id, n);
        log_ident[n] = 0;
    } else {
        log_ident[0] = 0;
    }
    log_opt = opt;
    log_facility = facility;
    if (opt & LOG_NDELAY != 0 and log_fd < 0) openlog_internal();
    __unlock(&sl_lock);
}

fn __vsyslog(priority: c_int, message: [*:0]const u8, ap: VaList) callconv(.c) void {
    if (log_mask_val & LOG_MASK_FN.mask(priority & 7) == 0 or priority & ~@as(c_int, 0x3ff) != 0) return;
    __lock(&sl_lock);
    _vsyslog(priority, message, ap);
    __unlock(&sl_lock);
}

fn syslog(priority: c_int, message: [*:0]const u8, ...) callconv(.c) void {
    const ap = @cVaStart();
    __vsyslog(priority, message, @as(VaList, @bitCast(ap)));
}

comptime {
    if (builtin.link_libc) {
        symbol(&setlogmask, "setlogmask");
        symbol(&closelog, "closelog");
        symbol(&openlog, "openlog");
        symbol(&__vsyslog, "vsyslog");
        symbol(&__vsyslog, "__vsyslog");
        symbol(&syslog, "syslog");
        symbol(&sl_lock, "__syslog_lockptr");
    }
}
