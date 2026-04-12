const builtin = @import("builtin");
const std = @import("std");

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&getsubopt, "getsubopt");
    }
}

fn getsubopt(opt: *[*:0]u8, keys: [*:null]const ?[*:0]const u8, val: *?[*:0]u8) callconv(.c) c_int {
    const s: [*:0]u8 = opt.*;
    val.* = null;

    // Find the comma or end of string.
    var end: usize = 0;
    while (s[end] != 0 and s[end] != ',') : (end += 1) {}

    if (s[end] == ',') {
        s[end] = 0;
        opt.* = @ptrCast(s + end + 1);
    } else {
        opt.* = @ptrCast(s + end);
    }

    // Search for matching key.
    var i: c_int = 0;
    while (keys[@intCast(i)]) |key| : (i += 1) {
        var l: usize = 0;
        while (key[l] != 0) : (l += 1) {}
        if (l == 0) continue;

        // Compare key with beginning of s.
        var match = true;
        for (0..l) |j| {
            if (s[j] != key[j]) {
                match = false;
                break;
            }
        }
        if (!match) continue;

        if (s[l] == '=') {
            val.* = @ptrCast(s + l + 1);
        } else if (s[l] != 0) {
            continue;
        }
        return i;
    }
    return -1;
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&getpriorityLinux, "getpriority");
        symbol(&setpriorityLinux, "setpriority");
        symbol(&getresuidLinux, "getresuid");
        symbol(&getresgidLinux, "getresgid");
        symbol(&setdomainnameLinux, "setdomainname");
    }
}

fn getpriorityLinux(which: c_int, who: c_uint) callconv(.c) c_int {
    const rc = errno(linux.syscall2(.getpriority, @as(usize, @bitCast(@as(isize, which))), @as(usize, who)));
    if (rc < 0) return rc;
    return 20 - rc;
}

fn setpriorityLinux(which: c_int, who: c_uint, prio: c_int) callconv(.c) c_int {
    return errno(linux.syscall3(.setpriority, @as(usize, @bitCast(@as(isize, which))), @as(usize, who), @as(usize, @bitCast(@as(isize, prio)))));
}

fn getresuidLinux(ruid: *linux.uid_t, euid: *linux.uid_t, suid: *linux.uid_t) callconv(.c) c_int {
    return errno(linux.getresuid(ruid, euid, suid));
}

fn getresgidLinux(rgid: *linux.gid_t, egid: *linux.gid_t, sgid: *linux.gid_t) callconv(.c) c_int {
    return errno(linux.getresgid(rgid, egid, sgid));
}

fn setdomainnameLinux(name: [*]const u8, len: usize) callconv(.c) c_int {
    return errno(linux.syscall2(.setdomainname, @intFromPtr(name), len));
        symbol(&gethostid, "gethostid");
        symbol(&getdomainnameLinux, "getdomainname");
        symbol(&getrlimitLinux, "getrlimit");
        symbol(&setrlimitLinux, "setrlimit");
    }
    if (builtin.target.isWasiLibC()) {
        symbol(&gethostid, "gethostid");
    }
}

fn gethostid() callconv(.c) c_long {
    return 0;
}

fn getdomainnameLinux(name: [*]u8, len: usize) callconv(.c) c_int {
    var uts: linux.utsname = undefined;
    const rc: isize = @bitCast(linux.uname(&uts));
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&login_ttyLinux, "login_tty");
    }
    if (builtin.link_libc) {
        symbol(&initgroups, "initgroups");
    }
}

fn login_ttyLinux(fd: c_int) callconv(.c) c_int {
    _ = linux.setsid();
    const rc: isize = @bitCast(linux.ioctl(@intCast(fd), linux.T.IOCSCTTY, 0));
    if (rc < 0) {
        @branchHint(.unlikely);
        std.c._errno().* = @intCast(-rc);
        return -1;
    }
    const domain = std.mem.sliceTo(&uts.domainname, 0);
    if (len == 0 or domain.len >= len) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    @memcpy(name[0..domain.len], domain);
    name[domain.len] = 0;
    return 0;
}

fn getrlimitLinux(resource: c_int, rlim: *linux.rlimit) callconv(.c) c_int {
    return errno(linux.getrlimit(@enumFromInt(resource), rlim));
}

fn setrlimitLinux(resource: c_int, rlim: *const linux.rlimit) callconv(.c) c_int {
    return errno(linux.setrlimit(@enumFromInt(resource), rlim));
        symbol(&basename, "basename");
        symbol(&basename, "__xpg_basename");
        symbol(&dirname, "dirname");
        symbol(&a64l, "a64l");
        symbol(&l64a, "l64a");
    }
}

fn basename(s: ?[*:0]u8) callconv(.c) [*:0]const u8 {
    const str = s orelse return ".";
    if (str[0] == 0) return ".";

    // Find end of string.
    var i: usize = 0;
    while (str[i] != 0) : (i += 1) {}
    i -= 1;

    // Strip trailing slashes.
    while (i > 0 and str[i] == '/') : (i -= 1) {
        str[i] = 0;
    }
    if (i == 0 and str[0] == '/') return str[0..1 :0];

    // Find last slash.
    while (i > 0 and str[i - 1] != '/') : (i -= 1) {}

    return @ptrCast(str + i);
}

fn dirname(s: ?[*:0]u8) callconv(.c) [*:0]const u8 {
    const str = s orelse return ".";
    if (str[0] == 0) return ".";

    // Find end of string.
    var i: usize = 0;
    while (str[i] != 0) : (i += 1) {}
    i -= 1;

    // Strip trailing slashes.
    while (str[i] == '/') {
        if (i == 0) return "/";
        i -= 1;
    }
    // Strip trailing component.
    while (str[i] != '/') {
        if (i == 0) return ".";
        i -= 1;
    }
    // Strip trailing slashes again.
    while (str[i] == '/') {
        if (i == 0) return "/";
        i -= 1;
    }

    str[i + 1] = 0;
    return @ptrCast(str);
}

const digits = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

fn a64l(str: [*:0]const u8) callconv(.c) c_long {
    var x: u32 = 0;
    var e: u5 = 0;
    var p = str;
    while (e < 36 and p[0] != 0) : ({
        e += 6;
        p += 1;
    }) {
        const c = p[0];
        const d: u32 = for (digits, 0..) |ch, idx| {
            if (ch == c) break @intCast(idx);
        } else break;
        x |= d << e;
    }
    return @as(c_long, @as(i32, @bitCast(x)));
}

var l64a_buf: [7]u8 = undefined;

fn l64a(x0: c_long) callconv(.c) [*:0]u8 {
    var x: u32 = @bitCast(@as(c_int, @intCast(x0)));
    var i: usize = 0;
    while (x != 0 and i < 6) : (i += 1) {
        l64a_buf[i] = digits[x & 63];
        x >>= 6;
    }
    l64a_buf[i] = 0;
    return l64a_buf[0..i :0];
}
        symbol(&getrusageLinux, "getrusage");
        symbol(&getentropyLinux, "getentropy");
    }
}

fn getrusageLinux(who: c_int, usage: *linux.rusage) callconv(.c) c_int {
    return errno(linux.getrusage(who, usage));
}

fn getentropyLinux(buffer: [*]u8, len: usize) callconv(.c) c_int {
    if (len > 256) {
        std.c._errno().* = @intFromEnum(linux.E.IO);
        return -1;
    }
    var pos: usize = 0;
    while (pos < len) {
        const rc: isize = @bitCast(linux.getrandom(buffer + pos, len - pos, 0));
        if (rc < 0) {
            @branchHint(.unlikely);
            if (-rc == @intFromEnum(linux.E.INTR)) continue;
            std.c._errno().* = @intCast(-rc);
            return -1;
        }
        pos += @intCast(rc);
    }
    return 0;
    _ = linux.dup2(fd, 0);
    _ = linux.dup2(fd, 1);
    _ = linux.dup2(fd, 2);
    if (fd > 2) _ = linux.close(fd);
    return 0;
}

const NGROUPS_MAX = 32;

extern "c" fn getgrouplist(user: [*:0]const u8, group: linux.gid_t, groups: [*]linux.gid_t, ngroups: *c_int) c_int;
extern "c" fn setgroups(size: usize, list: [*]const linux.gid_t) c_int;

fn initgroups(user: [*:0]const u8, gid: linux.gid_t) callconv(.c) c_int {
    var groups: [NGROUPS_MAX]linux.gid_t = undefined;
    var count: c_int = NGROUPS_MAX;
    if (getgrouplist(user, gid, &groups, &count) < 0) return -1;
    return setgroups(@intCast(count), &groups);
    if (builtin.link_libc) {
        symbol(&lockf, "lockf");
        symbol(&ptsname, "ptsname");
    }
}

// lockf command constants
const F_ULOCK = 0;
const F_LOCK = 1;
const F_TLOCK = 2;
const F_TEST = 3;

// fcntl commands
const F_GETLK = 5;
const F_SETLK = 6;
const F_SETLKW = 7;

// flock types
const F_RDLCK: c_short = 0;
const F_WRLCK: c_short = 1;
const F_UNLCK: c_short = 2;

const SEEK_CUR: c_short = 1;

const flock = extern struct {
    l_type: c_short,
    l_whence: c_short,
    l_start: i64,
    l_len: i64,
    l_pid: c_int,
};

extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
extern "c" fn getpid() c_int;

fn lockf(fd: c_int, op: c_int, size: i64) callconv(.c) c_int {
    var l = flock{
        .l_type = F_WRLCK,
        .l_whence = SEEK_CUR,
        .l_start = 0,
        .l_len = size,
        .l_pid = 0,
    };
    switch (op) {
        F_TEST => {
            l.l_type = F_RDLCK;
            if (fcntl(fd, F_GETLK, &l) < 0) return -1;
            if (l.l_type == F_UNLCK or l.l_pid == getpid()) return 0;
            std.c._errno().* = @intFromEnum(linux.E.ACCES);
            return -1;
        },
        F_ULOCK => {
            l.l_type = F_UNLCK;
            return fcntl(fd, F_SETLK, &l);
        },
        F_TLOCK => return fcntl(fd, F_SETLK, &l),
        F_LOCK => return fcntl(fd, F_SETLKW, &l),
        else => {
            std.c._errno().* = @intFromEnum(linux.E.INVAL);
            return -1;
        },
    }
}

extern "c" fn __ptsname_r(fd: c_int, buf: [*]u8, len: usize) c_int;

var ptsname_buf: [9 + @sizeOf(c_int) * 3 + 1]u8 = undefined;

fn ptsname(fd: c_int) callconv(.c) ?[*:0]u8 {
    const err = __ptsname_r(fd, &ptsname_buf, ptsname_buf.len);
    if (err != 0) {
        std.c._errno().* = err;
        return null;
    }
    // Find the null terminator to create a sentinel-terminated pointer.
    for (&ptsname_buf, 0..) |*c, i| {
        if (c.* == 0) return ptsname_buf[0..i :0];
    }
    return null;
        symbol(&posix_openptLinux, "posix_openpt");
        symbol(&grantpt, "grantpt");
        symbol(&unlockptLinux, "unlockpt");
        symbol(&__ptsname_rLinux, "__ptsname_r");
        symbol(&__ptsname_rLinux, "ptsname_r");
    }
}

fn posix_openptLinux(flags: c_int) callconv(.c) c_int {
    const rc: isize = @bitCast(linux.open("/dev/ptmx", @bitCast(@as(u32, @bitCast(flags))), 0));
    if (rc < 0) {
        @branchHint(.unlikely);
        const e: u16 = @intCast(-rc);
        // Map ENOSPC to EAGAIN per POSIX.
        if (e == @intFromEnum(linux.E.NOSPC)) {
            std.c._errno().* = @intFromEnum(linux.E.AGAIN);
        } else {
            std.c._errno().* = @intCast(e);
        }
        return -1;
    }
    return @intCast(rc);
}

fn grantpt(_: c_int) callconv(.c) c_int {
    return 0;
}

fn unlockptLinux(fd: c_int) callconv(.c) c_int {
    var unlock: c_int = 0;
    return errno(linux.ioctl(@intCast(fd), linux.T.IOCSPTLCK, @intFromPtr(&unlock)));
}

fn __ptsname_rLinux(fd: c_int, buf: ?[*]u8, len: usize) callconv(.c) c_int {
    var pty: c_uint = undefined;
    const rc: isize = @bitCast(linux.ioctl(@intCast(fd), linux.T.IOCGPTN, @intFromPtr(&pty)));
    if (rc < 0) return @intCast(-rc);

    const b = buf orelse return @intFromEnum(linux.E.RANGE);

    const prefix = "/dev/pts/";
    if (len < prefix.len + 1) return @intFromEnum(linux.E.RANGE);
    @memcpy(b[0..prefix.len], prefix);

    // Format the pty number into the buffer after the prefix.
    var num_buf: [10]u8 = undefined;
    var num_len: usize = 0;
    var n: c_uint = pty;
    if (n == 0) {
        num_buf[0] = '0';
        num_len = 1;
    } else {
        while (n > 0) : (num_len += 1) {
            num_buf[num_len] = @intCast('0' + n % 10);
            n /= 10;
        }
        // Reverse.
        var lo: usize = 0;
        var hi: usize = num_len - 1;
        while (lo < hi) {
            const tmp = num_buf[lo];
            num_buf[lo] = num_buf[hi];
            num_buf[hi] = tmp;
            lo += 1;
            hi -= 1;
        }
    }

    if (prefix.len + num_len >= len) return @intFromEnum(linux.E.RANGE);
    @memcpy(b[prefix.len .. prefix.len + num_len], num_buf[0..num_len]);
    b[prefix.len + num_len] = 0;
    return 0;
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
