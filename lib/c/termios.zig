const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

const native_arch = builtin.cpu.arch;
const is_ppc = native_arch.isPowerPC();

const T = linux.T;

/// Baud rate bitmask for c_cflag.
/// PPC uses 0xFF (8-bit, contiguous values), all others use 0x100F (4-bit + CBAUDEX).
const CBAUD: linux.tcflag_t = if (is_ppc) 0xff else 0x100f;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&cfgetospeed, "cfgetospeed");
        symbol(&cfsetospeed, "cfsetospeed");
        symbol(&cfsetispeedImpl, "cfsetispeed");
        symbol(&cfmakeraw, "cfmakeraw");
        symbol(&tcgetattrLinux, "tcgetattr");
        symbol(&tcsetattrLinux, "tcsetattr");
        symbol(&tcdrainLinux, "tcdrain");
        symbol(&tcflowLinux, "tcflow");
        symbol(&tcflushLinux, "tcflush");
        symbol(&tcsendbreakLinux, "tcsendbreak");
        symbol(&tcgetsidLinux, "tcgetsid");
        symbol(&tcgetwinsizeLinux, "tcgetwinsize");
        symbol(&tcsetwinsizeLinux, "tcsetwinsize");
    }
}

fn cfgetospeed(tio: *const linux.termios) callconv(.c) linux.tcflag_t {
    const cflag: linux.tcflag_t = @bitCast(tio.cflag);
    return cflag & CBAUD;
}

fn cfsetospeed(tio: *linux.termios, speed: linux.tcflag_t) callconv(.c) c_int {
    if (speed & ~CBAUD != 0) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    var cflag: linux.tcflag_t = @bitCast(tio.cflag);
    cflag &= ~CBAUD;
    cflag |= speed;
    tio.cflag = @bitCast(cflag);
    return 0;
}

fn cfsetispeedImpl(tio: *linux.termios, speed: linux.tcflag_t) callconv(.c) c_int {
    return if (speed != 0) cfsetospeed(tio, speed) else 0;
}

fn cfmakeraw(t: *linux.termios) callconv(.c) void {
    t.iflag.IGNBRK = false;
    t.iflag.BRKINT = false;
    t.iflag.PARMRK = false;
    t.iflag.ISTRIP = false;
    t.iflag.INLCR = false;
    t.iflag.IGNCR = false;
    t.iflag.ICRNL = false;
    t.iflag.IXON = false;
    t.oflag.OPOST = false;
    t.lflag.ECHO = false;
    t.lflag.ECHONL = false;
    t.lflag.ICANON = false;
    t.lflag.ISIG = false;
    t.lflag.IEXTEN = false;
    t.cflag.CSIZE = .CS8;
    t.cflag.PARENB = false;
    t.cc[@intFromEnum(linux.V.MIN)] = 1;
    t.cc[@intFromEnum(linux.V.TIME)] = 0;
}

fn tcgetattrLinux(fd: c_int, tio: *linux.termios) callconv(.c) c_int {
    const rc = errno(linux.ioctl(fd, T.CGETS, @intFromPtr(tio)));
    if (rc < 0) return -1;
    return 0;
}

fn tcsetattrLinux(fd: c_int, act: c_int, tio: *const linux.termios) callconv(.c) c_int {
    if (act < 0 or act > 2) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    return errno(linux.ioctl(fd, T.CSETS + @as(u32, @intCast(act)), @intFromPtr(tio)));
}

fn tcdrainLinux(fd: c_int) callconv(.c) c_int {
    return errno(linux.ioctl(fd, T.CSBRK, 1));
}

fn tcflowLinux(fd: c_int, action: c_int) callconv(.c) c_int {
    return errno(linux.ioctl(fd, T.CXONC, @as(usize, @bitCast(@as(isize, action)))));
}

fn tcflushLinux(fd: c_int, queue: c_int) callconv(.c) c_int {
    return errno(linux.ioctl(fd, T.CFLSH, @as(usize, @bitCast(@as(isize, queue)))));
}

fn tcsendbreakLinux(fd: c_int, dur: c_int) callconv(.c) c_int {
    _ = dur;
    return errno(linux.ioctl(fd, T.CSBRK, 0));
}

fn tcgetsidLinux(fd: c_int) callconv(.c) c_int {
    var sid: c_int = undefined;
    const rc = errno(linux.ioctl(fd, T.IOCGSID, @intFromPtr(&sid)));
    if (rc < 0) return -1;
    return sid;
}

fn tcgetwinsizeLinux(fd: c_int, wsz: *std.posix.winsize) callconv(.c) c_int {
    return errno(linux.ioctl(fd, T.IOCGWINSZ, @intFromPtr(wsz)));
}

fn tcsetwinsizeLinux(fd: c_int, wsz: *const std.posix.winsize) callconv(.c) c_int {
    return errno(linux.ioctl(fd, T.IOCSWINSZ, @intFromPtr(wsz)));
}
