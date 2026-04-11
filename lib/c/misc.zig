const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

comptime {
    if (builtin.link_libc) {
        symbol(&openpty, "openpty");
        symbol(&forkpty, "forkpty");
    }
}

extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn ioctl(fd: c_int, req: c_int, ...) c_int;
extern "c" fn login_tty(fd: c_int) c_int;
extern "c" fn fork() c_int;
extern "c" fn write(fd: c_int, buf: *const anyopaque, count: usize) isize;
extern "c" fn read(fd: c_int, buf: *anyopaque, count: usize) isize;
extern "c" fn _exit(code: c_int) noreturn;
extern "c" fn waitpid(pid: c_int, status: ?*c_int, options: c_int) c_int;
extern "c" fn pipe2(fds: *[2]c_int, flags: c_int) c_int;
extern "c" fn tcsetattr(fd: c_int, action: c_int, termios_p: *const anyopaque) c_int;
extern "c" fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;

const O_RDWR = 2;
const O_NOCTTY = 0o400;
const O_CLOEXEC = 0o2000000;
const TCSANOW = 0;

fn openpty(
    pm: *c_int,
    ps: *c_int,
    name: ?[*]u8,
    tio: ?*const anyopaque,
    ws: ?*const anyopaque,
) callconv(.c) c_int {
    var n: c_int = 0;
    var buf: [20]u8 = undefined;

    const m = open("/dev/ptmx", O_RDWR | O_NOCTTY);
    if (m < 0) return -1;

    if (ioctl(m, @as(c_int, @bitCast(@as(c_uint, linux.T.IOCSPTLCK))), &n) != 0 or
        ioctl(m, @as(c_int, @bitCast(@as(c_uint, linux.T.IOCGPTN))), &n) != 0)
    {
        _ = close(m);
        return -1;
    }

    const namebuf: [*]u8 = name orelse &buf;
    _ = snprintf(namebuf, 20, "/dev/pts/%d", n);

    const s = open(@ptrCast(namebuf), O_RDWR | O_NOCTTY);
    if (s < 0) {
        _ = close(m);
        return -1;
    }

    if (tio) |t| _ = tcsetattr(s, TCSANOW, t);
    if (ws) |w| _ = ioctl(s, @as(c_int, @bitCast(@as(c_uint, linux.T.IOCSWINSZ))), w);

    pm.* = m;
    ps.* = s;
    return 0;
}

fn forkpty(
    pm: *c_int,
    name: ?[*]u8,
    tio: ?*const anyopaque,
    ws: ?*const anyopaque,
) callconv(.c) c_int {
    var m: c_int = undefined;
    var s: c_int = undefined;
    var p: [2]c_int = undefined;

    if (openpty(&m, &s, name, tio, ws) < 0) return -1;

    if (pipe2(&p, O_CLOEXEC) != 0) {
        _ = close(s);
        _ = close(m);
        return -1;
    }

    const pid = fork();
    if (pid == 0) {
        // Child.
        _ = close(m);
        _ = close(p[0]);
        if (login_tty(s) != 0) {
            const e = std.c._errno().*;
            _ = write(p[1], &e, @sizeOf(c_int));
            _exit(127);
        }
        _ = close(p[1]);
        return 0;
    }

    // Parent.
    _ = close(s);
    _ = close(p[1]);

    if (pid < 0) {
        _ = close(p[0]);
        _ = close(m);
        return -1;
    }

    var ec: c_int = undefined;
    if (read(p[0], &ec, @sizeOf(c_int)) > 0) {
        var status: c_int = undefined;
        _ = waitpid(pid, &status, 0);
        _ = close(p[0]);
        _ = close(m);
        std.c._errno().* = ec;
        return -1;
    }
    _ = close(p[0]);

    pm.* = m;
    return pid;
}
