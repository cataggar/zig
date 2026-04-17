const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;
const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;
const digits = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
var l64a_buf: [7]u8 = undefined;
const NGROUPS_MAX = 32;
extern "c" fn getgrouplist(user: [*:0]const u8, group: linux.gid_t, groups: [*]linux.gid_t, ngroups: *c_int) c_int;
extern "c" fn setgroups(size: usize, list: [*]const linux.gid_t) c_int;
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
extern "c" fn __ptsname_r(fd: c_int, buf: [*]u8, len: usize) c_int;
var ptsname_buf: [9 + @sizeOf(c_int) * 3 + 1]u8 = undefined;
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
extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8;
extern "c" fn dprintf(fd: c_int, fmt: [*:0]const u8, ...) c_int;
extern "c" fn strchr(s: [*:0]u8, c: c_int) ?[*:0]u8;
const O_WRONLY = 1;
const MM_CONSOLE: c_long = 512;
const MM_PRINT: c_long = 256;
const MM_HALT: c_int = 1;
const MM_ERROR: c_int = 2;
const MM_WARNING: c_int = 3;
const MM_INFO: c_int = 4;
const MM_NOCON = 4;
const MM_NOMSG = 1;
const MM_NOTOK = -1;
const empty: [*:0]const u8 = "";
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn getcwd(buf: ?[*]u8, size: usize) ?[*:0]u8;
// Use opaque stat buffers and compare dev+ino fields.
const STAT_BUF_SIZE = 256;
extern "c" fn stat(path: [*:0]const u8, buf: *[STAT_BUF_SIZE]u8) c_int;
const FILE = anyopaque;
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE;
extern "c" fn fclose(f: *FILE) c_int;
extern "c" fn fgets(buf: [*]u8, size: c_int, f: *FILE) ?[*]u8;
extern "c" fn feof(f: *FILE) c_int;
extern "c" fn ferror(f: *FILE) c_int;
extern "c" fn fscanf(f: *FILE, fmt: [*:0]const u8, ...) c_int;
extern "c" fn sscanf(s: [*]const u8, fmt: [*:0]const u8, ...) c_int;
extern "c" fn fprintf(f: *FILE, fmt: [*:0]const u8, ...) c_int;
extern "c" fn fseek(f: *FILE, offset: c_long, whence: c_int) c_int;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn strstr(haystack: [*:0]const u8, needle: [*:0]const u8) ?[*:0]const u8;
extern "c" fn getline(lineptr: *?[*:0]u8, n: *usize, f: *FILE) isize;
const SEEK_END = 2;
const mntent = extern struct {
    mnt_fsname: ?[*:0]u8,
    mnt_dir: ?[*:0]u8,
    mnt_type: ?[*:0]u8,
    mnt_opts: ?[*:0]u8,
    mnt_freq: c_int,
    mnt_passno: c_int,
};
var internal_buf: ?[*:0]u8 = null;
var internal_bufsize: usize = 0;
var static_mnt: mntent = undefined;
const SENTINEL: [*]u8 = @ptrCast(&internal_buf);
extern "c" fn readlink(path: [*:0]const u8, buf: [*]u8, bufsiz: usize) isize;
extern "c" fn __strchrnul(s: [*:0]const u8, c: c_int) [*:0]const u8;
extern "c" fn strnlen(s: [*]const u8, maxlen: usize) usize;
extern "c" fn memcpy(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;
extern "c" fn memmove(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;
const PATH_MAX = 4096;
const SYMLOOP_MAX = 40;
// C library dependencies.
extern "c" fn mbtowc(pwc: ?*c_uint, s: [*]const u8, n: usize) c_int;
extern "c" fn fputs(s: [*:0]const u8, f: *anyopaque) c_int;
extern "c" fn fwrite(ptr: *const anyopaque, size: usize, nmemb: usize, f: *anyopaque) usize;
extern "c" fn putc(c: c_int, f: *anyopaque) c_int;
extern "c" fn flockfile(f: *anyopaque) void;
extern "c" fn funlockfile(f: *anyopaque) void;
extern "c" var stderr: *anyopaque;
const MB_LEN_MAX = 4;
var optarg_val: ?[*:0]u8 = null;
var optind_val: c_int = 1;
var opterr_val: c_int = 1;
var optopt_val: c_int = 0;
var optpos_val: c_int = 0;
var optreset_val: c_int = 0;
const VaList = std.builtin.VaList;
extern "c" fn __lock(lock: *c_int) void;
extern "c" fn __unlock(lock: *c_int) void;
extern "c" fn socket(domain: c_int, sock_type: c_int, protocol: c_int) c_int;
extern "c" fn connect(fd: c_int, addr: *const anyopaque, len: c_uint) c_int;
extern "c" fn send(fd: c_int, buf: *const anyopaque, len: usize, flags: c_int) isize;
extern "c" fn time(tloc: ?*i64) i64;
extern "c" fn gmtime_r(timep: *const i64, result: *anyopaque) ?*anyopaque;
extern "c" fn strftime(s: [*]u8, max: usize, fmt: [*:0]const u8, tm: *const anyopaque) usize;
extern "c" fn vsnprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ap: VaList) c_int;
const AF_UNIX = 1;
const SOCK_DGRAM = 2;
const SOCK_CLOEXEC = 0o2000000;
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
const Option = extern struct {
    name: ?[*:0]const u8,
    has_arg: c_int,
    flag: ?*c_int,
    val: c_int,
};
const required_argument: c_int = 1;
extern "c" var optarg: ?[*:0]u8;
extern "c" var optind: c_int;
extern "c" var opterr: c_int;
extern "c" var optopt: c_int;
extern "c" var __optpos: c_int;
extern "c" var __optreset: c_int;
extern "c" fn getopt(argc: c_int, argv: [*]const ?[*:0]u8, optstring: [*:0]const u8) c_int;
extern "c" fn mblen(s: [*]const u8, n: usize) c_int;
const sigset_t = [128 / @sizeOf(c_ulong)]c_ulong;
const wordexp_t = extern struct {
    we_wordc: usize,
    we_wordv: ?[*]?[*:0]u8,
    we_offs: usize,
};
const WRDE_DOOFFS: c_int = 1;
const WRDE_APPEND: c_int = 2;
const WRDE_NOCMD: c_int = 4;
const WRDE_REUSE: c_int = 8;
const WRDE_SHOWERR: c_int = 16;
const WRDE_NOSPACE: c_int = 1;
const WRDE_BADCHAR: c_int = 2;
const WRDE_CMDSUB: c_int = 4;
const WRDE_SYNTAX: c_int = 5;
const F_SETFD: c_int = 2;
const SIGKILL: c_int = 9;
extern "c" fn dup2(old: c_int, new: c_int) c_int;
extern "c" fn execl(path: [*:0]const u8, arg0: [*:0]const u8, ...) c_int;
extern "c" fn kill(pid: c_int, sig: c_int) c_int;
extern "c" fn fdopen(fd: c_int, mode: [*:0]const u8) ?*FILE;
extern "c" fn getdelim(lineptr: *?[*:0]u8, n: *usize, delim: c_int, f: *FILE) isize;
extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?[*]u8;
extern "c" fn calloc(nmemb: usize, size: usize) ?[*]u8;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn __block_all_sigs(set: ?*sigset_t) void;
extern "c" fn __restore_sigs(set: *const sigset_t) void;
extern "c" fn pthread_setcancelstate(state: c_int, oldstate: ?*c_int) c_int;
const PTHREAD_CANCEL_DISABLE: c_int = 1;
const DIR = anyopaque;
const stat_buf = [256]u8;
const FTW_F: c_int = 1;
const FTW_D: c_int = 2;
const FTW_DNR: c_int = 3;
const FTW_NS: c_int = 4;
const FTW_SL: c_int = 5;
const FTW_DP: c_int = 6;
const FTW_SLN: c_int = 7;
const FTW_PHYS: c_int = 1;
const FTW_MOUNT: c_int = 2;
const FTW_DEPTH: c_int = 8;
const FTW = extern struct { base: c_int, level: c_int };
const nftw_fn_t = *const fn ([*:0]const u8, *const stat_buf, c_int, *FTW) callconv(.c) c_int;
extern "c" fn lstat(path: [*:0]const u8, buf: *stat_buf) c_int;
extern "c" fn fdopendir(fd: c_int) ?*DIR;
extern "c" fn readdir(d: *DIR) ?*anyopaque; // returns struct dirent*
extern "c" fn closedir(d: *DIR) c_int;
extern "c" fn strcpy(dst: [*]u8, src: [*:0]const u8) [*]u8;
const O_RDONLY = 0;
const S_IFMT: u32 = 0o170000;
const S_IFDIR: u32 = 0o040000;
const S_IFLNK: u32 = 0o120000;
// Offsets for st_dev, st_ino, st_mode in struct stat (Linux 64-bit musl)
const ST_DEV_OFF = 0;
const ST_INO_OFF = 8;
const ST_MODE_OFF = 24; // after dev(8) + ino(8) + nlink(8)

fn get_dev(st: *const stat_buf) u64 {
    return @as(*const u64, @ptrCast(@alignCast(&st.*[ST_DEV_OFF]))).*;
}
fn get_ino(st: *const stat_buf) u64 {
    return @as(*const u64, @ptrCast(@alignCast(&st.*[ST_INO_OFF]))).*;
}
fn get_mode(st: *const stat_buf) u32 {
    return @as(*const u32, @ptrCast(@alignCast(&st.*[ST_MODE_OFF]))).*;
}

// dirent d_name offset: after d_ino(8) + d_off(8) + d_reclen(2) + d_type(1) = 19
const DIRENT_DNAME_OFF = 19;
const History = struct {
    chain: ?*const History,
    dev: u64,
    ino: u64,
    level: c_int,
    base: usize,
};

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&getpriorityLinux, "getpriority");
        symbol(&setpriorityLinux, "setpriority");
        symbol(&getresuidLinux, "getresuid");
        symbol(&getresgidLinux, "getresgid");
        symbol(&setdomainnameLinux, "setdomainname");
        symbol(&gethostid, "gethostid");
        symbol(&getdomainnameLinux, "getdomainname");
        symbol(&getrlimitLinux, "getrlimit");
        symbol(&setrlimitLinux, "setrlimit");
        symbol(&getrusageLinux, "getrusage");
        symbol(&getentropyLinux, "getentropy");
        symbol(&login_ttyLinux, "login_tty");
        symbol(&posix_openptLinux, "posix_openpt");
        symbol(&grantpt, "grantpt");
        symbol(&unlockptLinux, "unlockpt");
        symbol(&__ptsname_rLinux, "__ptsname_r");
        symbol(&ioctlImpl, "ioctl");
        symbol(&syscall_fn, "syscall");
    }
    if (builtin.target.isWasiLibC()) {
    }
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&basename, "basename");
        symbol(&dirname, "dirname");
        symbol(&a64l, "a64l");
        symbol(&l64a, "l64a");
        symbol(&getsubopt, "getsubopt");
    }
    if (builtin.link_libc) {
        symbol(&initgroups, "initgroups");
        symbol(&lockf, "lockf");
        symbol(&ptsname, "ptsname");
        symbol(&openpty, "openpty");
        symbol(&forkpty, "forkpty");
        symbol(&fmtmsg, "fmtmsg");
        symbol(&get_current_dir_name, "get_current_dir_name");
        symbol(&setmntent, "setmntent");
        symbol(&endmntent, "endmntent");
        symbol(&getmntent, "getmntent");
        symbol(&getmntent_r, "getmntent_r");
        symbol(&addmntent, "addmntent");
        symbol(&hasmntopt, "hasmntopt");
        symbol(&realpath, "realpath");
        @export(&optarg_val, .{ .name = "optarg" });
        symbol(&optind_val, "optind");
        symbol(&opterr_val, "opterr");
        symbol(&optopt_val, "optopt");
        symbol(&optpos_val, "__optpos");
        symbol(&optreset_val, "__optreset");
        symbol(&__getopt_msg, "__getopt_msg");
        symbol(&getopt_fn, "getopt");
        symbol(&setlogmask, "setlogmask");
        symbol(&closelog, "closelog");
        symbol(&openlog, "openlog");
        symbol(&__vsyslog, "vsyslog");
        symbol(&syslog, "syslog");
        symbol(&sl_lock, "__syslog_lockptr");
        symbol(&getopt_long_fn, "getopt_long");
        symbol(&getopt_long_only_fn, "getopt_long_only");
        symbol(&wordexp_fn, "wordexp");
        symbol(&wordfree_fn, "wordfree");
        symbol(&nftw_fn, "nftw");
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
}

fn gethostid() callconv(.c) c_long {
    return 0;
}

fn getdomainnameLinux(name: [*]u8, len: usize) callconv(.c) c_int {
    var uts: linux.utsname = undefined;
    const rc: isize = @bitCast(linux.uname(&uts));
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
}

fn login_ttyLinux(fd: c_int) callconv(.c) c_int {
    _ = linux.setsid();
    const rc: isize = @bitCast(linux.ioctl(@intCast(fd), linux.T.IOCSCTTY, 0));
    if (rc < 0) {
        @branchHint(.unlikely);
        std.c._errno().* = @intCast(-rc);
        return -1;
    }
    _ = linux.dup2(fd, 0);
    _ = linux.dup2(fd, 1);
    _ = linux.dup2(fd, 2);
    if (fd > 2) _ = linux.close(fd);
    return 0;
}

fn initgroups(user: [*:0]const u8, gid: linux.gid_t) callconv(.c) c_int {
    var groups: [NGROUPS_MAX]linux.gid_t = undefined;
    var count: c_int = NGROUPS_MAX;
    if (getgrouplist(user, gid, &groups, &count) < 0) return -1;
    return setgroups(@intCast(count), &groups);
}

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
}

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

fn strcolcmp(lstr: [*:0]const u8, bstr: [*:0]const u8) bool {
    var i: usize = 0;
    while (lstr[i] != 0 and bstr[i] != 0 and bstr[i] == lstr[i]) : (i += 1) {}
    return lstr[i] == 0 and (bstr[i] == 0 or bstr[i] == ':');
}

fn fmtmsg(
    classification: c_long,
    label: ?[*:0]const u8,
    severity: c_int,
    text: ?[*:0]const u8,
    action: ?[*:0]const u8,
    tag: ?[*:0]const u8,
) callconv(.c) c_int {
    var ret: c_int = 0;

    const errstring: [*:0]const u8 = switch (severity) {
        MM_HALT => "HALT: ",
        MM_ERROR => "ERROR: ",
        MM_WARNING => "WARNING: ",
        MM_INFO => "INFO: ",
        else => empty,
    };

    if (classification & MM_CONSOLE != 0) {
        const consolefd = open("/dev/console", O_WRONLY);
        if (consolefd < 0) {
            ret = MM_NOCON;
        } else {
            if (dprintf(consolefd, "%s%s%s%s%s%s%s%s\n",
                if (label) |l| l else empty, if (label != null) @as([*:0]const u8, ": ") else empty,
                if (severity != 0) errstring else empty, if (text) |t| t else empty,
                if (action != null) @as([*:0]const u8, "\nTO FIX: ") else empty,
                if (action) |a| a else empty, if (action != null) @as([*:0]const u8, " ") else empty,
                if (tag) |t| t else empty) < 1)
                ret = MM_NOCON;
            _ = close(consolefd);
        }
    }

    if (classification & MM_PRINT != 0) {
        var verb: c_int = 0;
        var cmsg: ?[*:0]u8 = getenv("MSGVERB");
        const msgs = [_][*:0]const u8{ "label", "severity", "text", "action", "tag" };

        while (cmsg) |cm| {
            if (cm[0] == 0) break;
            var found = false;
            for (msgs, 0..) |m, i| {
                if (strcolcmp(m, cm)) {
                    verb |= @as(c_int, 1) << @intCast(i);
                    found = true;
                    break;
                }
            }
            if (!found) { verb = 0xFF; break; }
            cmsg = if (strchr(cm, ':')) |p| @ptrCast(@as([*]u8, @ptrCast(p)) + 1) else null;
        }
        if (verb == 0) verb = 0xFF;

        if (dprintf(2, "%s%s%s%s%s%s%s%s\n",
            if (verb & 1 != 0 and label != null) label.? else empty,
            if (verb & 1 != 0 and label != null) @as([*:0]const u8, ": ") else empty,
            if (verb & 2 != 0 and severity != 0) errstring else empty,
            if (verb & 4 != 0 and text != null) text.? else empty,
            if (verb & 8 != 0 and action != null) @as([*:0]const u8, "\nTO FIX: ") else empty,
            if (verb & 8 != 0 and action != null) action.? else empty,
            if (verb & 8 != 0 and action != null) @as([*:0]const u8, " ") else empty,
            if (verb & 16 != 0 and tag != null) tag.? else empty) < 1)
            ret |= MM_NOMSG;
    }

    if (ret & (MM_NOCON | MM_NOMSG) == (MM_NOCON | MM_NOMSG))
        ret = MM_NOTOK;

    return ret;
}

fn get_current_dir_name() callconv(.c) ?[*:0]u8 {
    const res = getenv("PWD") orelse return getcwd(null, 0);
    if (res[0] == 0) return getcwd(null, 0);
    var a: [STAT_BUF_SIZE]u8 = undefined;
    var b: [STAT_BUF_SIZE]u8 = undefined;
    if (stat(res, &a) != 0 or stat(".", &b) != 0) return getcwd(null, 0);
    // Compare st_dev (first field) and st_ino (second field on most archs).
    // Both are typically 8 bytes each, starting at offset 0.
    if (@as(*const u64, @ptrCast(@alignCast(&a[0]))).* == @as(*const u64, @ptrCast(@alignCast(&b[0]))).* and
        @as(*const u64, @ptrCast(@alignCast(&a[8]))).* == @as(*const u64, @ptrCast(@alignCast(&b[8]))).*) {
        return strdup(res);
    }
    return getcwd(null, 0);
}

fn setmntent(name: [*:0]const u8, mode: [*:0]const u8) callconv(.c) ?*FILE {
    return fopen(name, mode);
}

fn endmntent(f: ?*FILE) callconv(.c) c_int {
    if (f) |stream| _ = fclose(stream);
    return 1;
}

fn unescape_ent(beg: [*:0]u8) [*:0]u8 {
    var dest: [*]u8 = @ptrCast(beg);
    var src: [*]const u8 = @ptrCast(beg);
    while (src[0] != 0) {
        if (src[0] != '\\') {
            dest[0] = src[0];
            dest += 1;
            src += 1;
            continue;
        }
        if (src[1] == '\\') {
            src += 1;
            dest[0] = src[0];
            dest += 1;
            src += 1;
            continue;
        }
        var cval: u8 = 0;
        var val: [*]const u8 = src + 1;
        for (0..3) |_| {
            if (val[0] >= '0' and val[0] <= '7') {
                cval = (cval << 3) + (val[0] - '0');
                val += 1;
            } else break;
        }
        if (cval != 0) {
            dest[0] = cval;
            dest += 1;
            src = val;
        } else {
            dest[0] = src[0];
            dest += 1;
            src += 1;
        }
    }
    dest[0] = 0;
    return beg;
}

fn getmntent_r(f: *FILE, mnt_out: *mntent, linebuf_arg: [*]u8, buflen: c_int) callconv(.c) ?*mntent {
    const use_internal = (linebuf_arg == SENTINEL);
    var n: [8]c_int = undefined;

    mnt_out.mnt_freq = 0;
    mnt_out.mnt_passno = 0;

    while (true) {
        var linebuf: [*:0]u8 = undefined;
        if (use_internal) {
            _ = getline(&internal_buf, &internal_bufsize, f);
            linebuf = internal_buf orelse return null;
        } else {
            if (fgets(linebuf_arg, buflen, f) == null) return null;
            linebuf = @ptrCast(linebuf_arg);
        }
        if (feof(f) != 0 or ferror(f) != 0) return null;

        const len: c_int = @intCast(strlen(linebuf));
        for (&n) |*p| p.* = len;
        _ = sscanf(linebuf, " %n%*[^ \t]%n %n%*[^ \t]%n %n%*[^ \t]%n %n%*[^ \t]%n %d %d",
            &n[0], &n[1], &n[2], &n[3], &n[4], &n[5], &n[6], &n[7],
            &mnt_out.mnt_freq, &mnt_out.mnt_passno);

        const lb: [*]u8 = @ptrCast(linebuf);
        if (lb[@intCast(n[0])] == '#' or n[1] == len) continue;

        lb[@intCast(n[1])] = 0;
        lb[@intCast(n[3])] = 0;
        lb[@intCast(n[5])] = 0;
        lb[@intCast(n[7])] = 0;

        mnt_out.mnt_fsname = unescape_ent(@ptrCast(lb + @as(usize, @intCast(n[0]))));
        mnt_out.mnt_dir = unescape_ent(@ptrCast(lb + @as(usize, @intCast(n[2]))));
        mnt_out.mnt_type = unescape_ent(@ptrCast(lb + @as(usize, @intCast(n[4]))));
        mnt_out.mnt_opts = unescape_ent(@ptrCast(lb + @as(usize, @intCast(n[6]))));

        return mnt_out;
    }
}

fn getmntent(f: *FILE) callconv(.c) ?*mntent {
    return getmntent_r(f, &static_mnt, SENTINEL, 0);
}

fn addmntent(f: *FILE, mnt_in: *const mntent) callconv(.c) c_int {
    if (fseek(f, 0, SEEK_END) != 0) return 1;
    return if (fprintf(f, "%s\t%s\t%s\t%s\t%d\t%d\n",
        mnt_in.mnt_fsname, mnt_in.mnt_dir, mnt_in.mnt_type, mnt_in.mnt_opts,
        mnt_in.mnt_freq, mnt_in.mnt_passno) < 0) @as(c_int, 1) else 0;
}

fn hasmntopt(mnt_in: *const mntent, opt: [*:0]const u8) callconv(.c) ?[*:0]const u8 {
    return strstr(mnt_in.mnt_opts orelse return null, opt);
}

fn slash_len(s: []const u8) usize {
    var n: usize = 0;
    while (n < s.len and s[n] == '/') : (n += 1) {}
    return n;
}

fn realpath(filename: ?[*:0]const u8, resolved: ?[*]u8) callconv(.c) ?[*:0]u8 {
    const fname = filename orelse {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return null;
    };
    const l = strnlen(@ptrCast(fname), PATH_MAX + 1);
    if (l == 0) {
        std.c._errno().* = @intFromEnum(linux.E.NOENT);
        return null;
    }
    if (l >= PATH_MAX) {
        std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
        return null;
    }

    var stack: [PATH_MAX + 1]u8 = undefined;
    var output: [PATH_MAX]u8 = undefined;
    var cnt: usize = 0;
    var nup: usize = 0;
    var check_dir: bool = false;

    var p: usize = PATH_MAX + 1 - l - 1;
    var q: usize = 0;
    _ = memcpy(@ptrCast(&stack[p]), @as(*const anyopaque, @ptrCast(fname)), l + 1);

    restart: while (true) {
        while (true) {
            p += slash_len(stack[p..]);
            if (stack[p] == '/') {
                check_dir = false;
                nup = 0;
                q = 0;
                output[q] = '/';
                q += 1;
                p += 1;
                if (stack[p] == '/' and stack[p + 1] != '/') {
                    output[q] = '/';
                    q += 1;
                }
                continue;
            }

            const z = @intFromPtr(__strchrnul(@ptrCast(stack[p..].ptr), '/')) - @intFromPtr(&stack[p]);
            const l0 = z;
            var comp_l = z;

            if (comp_l == 0 and !check_dir) break;

            if (comp_l == 1 and stack[p] == '.') {
                p += comp_l;
                continue;
            }

            if (q > 0 and output[q - 1] != '/') {
                if (p == 0) {
                    std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
                    return null;
                }
                p -= 1;
                stack[p] = '/';
                comp_l += 1;
            }
            if (q + comp_l >= PATH_MAX) {
                std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
                return null;
            }
            _ = memcpy(@ptrCast(&output[q]), @as(*const anyopaque, @ptrCast(&stack[p])), comp_l);
            output[q + comp_l] = 0;
            p += comp_l;

            var up = false;
            if (l0 == 2 and stack[p - 2] == '.' and stack[p - 1] == '.') {
                up = true;
                if (q <= 3 * nup) {
                    nup += 1;
                    q += comp_l;
                    continue;
                }
                if (!check_dir) {
                    // skip_readlink path
                    check_dir = false;
                    while (q > 0 and output[q - 1] != '/') q -= 1;
                    if (q > 1 and (q > 2 or output[0] != '/')) q -= 1;
                    continue;
                }
            }
            const k = readlink(@ptrCast(output[0..q + comp_l :0]), &stack, p);
            if (k == @as(isize, @intCast(p))) {
                std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
                return null;
            }
            if (k == 0) {
                std.c._errno().* = @intFromEnum(linux.E.NOENT);
                return null;
            }
            if (k < 0) {
                if (std.c._errno().* != @intFromEnum(linux.E.INVAL)) return null;
                // Not a symlink — skip_readlink
                check_dir = false;
                if (up) {
                    while (q > 0 and output[q - 1] != '/') q -= 1;
                    if (q > 1 and (q > 2 or output[0] != '/')) q -= 1;
                    continue;
                }
                if (l0 != 0) q += comp_l;
                check_dir = stack[p] != 0;
                continue;
            }
            cnt += 1;
            if (cnt == SYMLOOP_MAX) {
                std.c._errno().* = @intFromEnum(linux.E.LOOP);
                return null;
            }
            const uk: usize = @intCast(k);
            if (stack[uk - 1] == '/') {
                while (stack[p] == '/') p += 1;
            }
            p -= uk;
            _ = memmove(@ptrCast(&stack[p]), @as(*const anyopaque, @ptrCast(&stack[0])), uk);
            continue :restart;
        }
        break;
    }

    output[q] = 0;

    if (output[0] != '/') {
        if (getcwd(&stack, stack.len) == null) return null;
        var gl: usize = strlen(@ptrCast(&stack));
        p = 0;
        while (nup > 0) : (nup -= 1) {
            while (gl > 1 and stack[gl - 1] != '/') gl -= 1;
            if (gl > 1) gl -= 1;
            p += 2;
            if (p < q) p += 1;
        }
        if (q - p > 0 and stack[gl - 1] != '/') {
            stack[gl] = '/';
            gl += 1;
        }
        if (gl + (q - p) + 1 >= PATH_MAX) {
            std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
            return null;
        }
        _ = memmove(@ptrCast(&output[gl]), @as(*const anyopaque, @ptrCast(&output[p])), q - p + 1);
        _ = memcpy(@ptrCast(&output), @as(*const anyopaque, @ptrCast(&stack)), gl);
        q = gl + q - p;
    }

    if (resolved) |r| {
        _ = memcpy(r, @as(*const anyopaque, @ptrCast(&output)), q + 1);
        return @ptrCast(r);
    } else {
        return strdup(@ptrCast(output[0..q :0]));
    }
}

fn __getopt_msg(a: [*:0]const u8, b: [*:0]const u8, c_ptr: [*]const u8, l: usize) callconv(.c) void {
    const f = stderr;
    flockfile(f);
    _ = fputs(a, f);
    _ = fwrite(b, strlen(b), 1, f);
    _ = fwrite(c_ptr, 1, l, f);
    _ = putc('\n', f);
    funlockfile(f);
}

fn getopt_fn(
    argc: c_int,
    argv: [*]const ?[*:0]u8,
    optstring_arg: [*:0]const u8,
) callconv(.c) c_int {
    if (optind_val == 0 or optreset_val != 0) {
        optreset_val = 0;
        optpos_val = 0;
        optind_val = 1;
    }

    if (optind_val >= argc) return -1;
    const cur = argv[@intCast(optind_val)] orelse return -1;
    if (cur[0] != '-') {
        if (optstring_arg[0] == '-') {
            optarg_val = @constCast(cur);
            optind_val += 1;
            return 1;
        }
        return -1;
    }
    if (cur[1] == 0) return -1;
    if (cur[1] == '-' and cur[2] == 0) {
        optind_val += 1;
        return -1;
    }

    if (optpos_val == 0) optpos_val = 1;

    var c: c_uint = undefined;
    const cur_bytes: [*]const u8 = @ptrCast(cur);
    var k = mbtowc(&c, cur_bytes + @as(usize, @intCast(optpos_val)), MB_LEN_MAX);
    if (k < 0) {
        k = 1;
        c = 0xfffd;
    }
    const optchar: [*]const u8 = cur_bytes + @as(usize, @intCast(optpos_val));
    optpos_val += k;

    if (cur[@intCast(optpos_val)] == 0) {
        optind_val += 1;
        optpos_val = 0;
    }

    var optstring = optstring_arg;
    if (optstring[0] == '-' or optstring[0] == '+') optstring = @ptrCast(@as([*]const u8, @ptrCast(optstring)) + 1);

    var i: usize = 0;
    var d: c_uint = 0;
    while (true) {
        const os_bytes: [*]const u8 = @ptrCast(optstring);
        const l = mbtowc(&d, os_bytes + i, MB_LEN_MAX);
        if (l > 0) {
            i += @intCast(l);
        } else {
            i += 1;
        }
        if (l == 0 or d == c) break;
    }

    if (d != c or c == ':') {
        optopt_val = @intCast(c);
        if (optstring_arg[0] != ':' and opterr_val != 0)
            __getopt_msg(@ptrCast(argv[0].?), ": unrecognized option: ", optchar, @intCast(k));
        return '?';
    }

    const os_bytes: [*]const u8 = @ptrCast(optstring);
    if (os_bytes[i] == ':') {
        optarg_val = null;
        if (os_bytes[i + 1] != ':' or optpos_val != 0) {
            if (optind_val >= argc) {
                optopt_val = @intCast(c);
                if (optstring_arg[0] == ':') return ':';
                if (opterr_val != 0)
                    __getopt_msg(@ptrCast(argv[0].?), ": option requires an argument: ", optchar, @intCast(k));
                return '?';
            }
            const next = argv[@intCast(optind_val)] orelse null;
            optind_val += 1;
            if (optpos_val != 0) {
                if (next) |n| {
                    optarg_val = @ptrCast(@constCast(@as([*]const u8, @ptrCast(n)) + @as(usize, @intCast(optpos_val))));
                }
            } else {
                optarg_val = @constCast(next);
            }
            optpos_val = 0;
        }
    }
    return @intCast(c);
}

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
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    __vsyslog(priority, message, ap);
}

fn permute(argv: [*]const ?[*:0]u8, dest: c_int, src: c_int) void {
    const av: [*]?[*:0]u8 = @constCast(argv);
    const tmp = av[@intCast(src)];
    var i = src;
    while (i > dest) : (i -= 1) {
        av[@intCast(i)] = av[@intCast(i - 1)];
    }
    av[@intCast(dest)] = tmp;
}

fn getopt_long_core(
    argc: c_int,
    argv: [*]const ?[*:0]u8,
    optstring: [*:0]const u8,
    longopts: ?[*]const Option,
    idx: ?*c_int,
    longonly: c_int,
) c_int {
    optarg = null;
    const cur = argv[@intCast(optind)] orelse return getopt(argc, argv, optstring);
    const cur_b: [*]const u8 = @ptrCast(cur);

    if (longopts != null and cur[0] == '-' and
        ((longonly != 0 and cur[1] != 0 and cur[1] != '-') or
        (cur[1] == '-' and cur[2] != 0)))
    {
        const opts = longopts.?;
        const os_b: [*]const u8 = @ptrCast(optstring);
        const colon: bool = os_b[if (os_b[0] == '+' or os_b[0] == '-') @as(usize, 1) else 0] == ':';

        const start: [*]const u8 = cur_b + 1;
        var cnt: c_int = 0;
        var match: usize = 0;
        var match_arg: [*]const u8 = start;
        var i: usize = 0;
        while (opts[i].name) |name_ptr| : (i += 1) {
            const name_b: [*]const u8 = @ptrCast(name_ptr);
            var opt: [*]const u8 = start;
            if (opt[0] == '-') opt += 1;
            var n: [*]const u8 = name_b;
            while (opt[0] != 0 and opt[0] != '=' and opt[0] == n[0]) {
                n += 1;
                opt += 1;
            }
            if (opt[0] != 0 and opt[0] != '=') continue;
            match_arg = opt;
            match = i;
            if (n[0] == 0) {
                cnt = 1;
                break;
            }
            cnt += 1;
        }

        if (cnt == 1 and longonly != 0) {
            const arg_len = @intFromPtr(match_arg) - @intFromPtr(start);
            if (arg_len == @as(usize, @intCast(mblen(start, MB_LEN_MAX)))) {
                const l: usize = arg_len;
                var j_outer: usize = 0;
                while (os_b[j_outer] != 0) : (j_outer += 1) {
                    var k: usize = 0;
                    while (k < l and start[k] == os_b[j_outer + k]) : (k += 1) {}
                    if (k == l) {
                        cnt += 1;
                        break;
                    }
                }
            }
        }

        if (cnt == 1) {
            i = match;
            const opt = match_arg;
            optind += 1;
            if (opt[0] == '=') {
                if (opts[i].has_arg == 0) {
                    optopt = opts[i].val;
                    if (colon or opterr == 0) return '?';
                    __getopt_msg(@ptrCast(argv[0].?), ": option does not take an argument: ", @ptrCast(opts[i].name.?), strlen(opts[i].name.?));
                    return '?';
                }
                optarg = @ptrCast(@constCast(opt + 1));
            } else if (opts[i].has_arg == required_argument) {
                optarg = @constCast(argv[@intCast(optind)]);
                if (optarg == null) {
                    optopt = opts[i].val;
                    if (colon) return ':';
                    if (opterr == 0) return '?';
                    __getopt_msg(@ptrCast(argv[0].?), ": option requires an argument: ", @ptrCast(opts[i].name.?), strlen(opts[i].name.?));
                    return '?';
                }
                optind += 1;
            }
            if (idx) |p| p.* = @intCast(i);
            if (opts[i].flag) |flag| {
                flag.* = opts[i].val;
                return 0;
            }
            return opts[i].val;
        }

        if (cur[1] == '-') {
            optopt = 0;
            if (!colon and opterr != 0) {
                __getopt_msg(@ptrCast(argv[0].?), if (cnt != 0) ": option is ambiguous: " else ": unrecognized option: ", cur_b + 2, strlen(@ptrCast(cur_b + 2)));
            }
            optind += 1;
            return '?';
        }
    }
    return getopt(argc, argv, optstring);
}

fn getopt_long_impl(
    argc: c_int,
    argv: [*]const ?[*:0]u8,
    optstring: [*:0]const u8,
    longopts: ?[*]const Option,
    idx: ?*c_int,
    longonly: c_int,
) c_int {
    if (optind == 0 or __optreset != 0) {
        __optreset = 0;
        __optpos = 0;
        optind = 1;
    }
    if (optind >= argc or argv[@intCast(optind)] == null) return -1;
    const skipped = optind;
    const os_b: [*]const u8 = @ptrCast(optstring);
    if (os_b[0] != '+' and os_b[0] != '-') {
        var ii = optind;
        while (true) : (ii += 1) {
            if (ii >= argc or argv[@intCast(ii)] == null) return -1;
            const a = argv[@intCast(ii)].?;
            if (a[0] == '-' and a[1] != 0) break;
        }
        optind = ii;
    }
    const resumed = optind;
    const ret = getopt_long_core(argc, argv, optstring, longopts, idx, longonly);
    if (resumed > skipped) {
        const cnt = optind - resumed;
        var j: c_int = 0;
        while (j < cnt) : (j += 1) {
            permute(argv, skipped, optind - 1);
        }
        optind = skipped + cnt;
    }
    return ret;
}

fn getopt_long_fn(argc: c_int, argv: [*]const ?[*:0]u8, optstring: [*:0]const u8, longopts: ?[*]const Option, idx: ?*c_int) callconv(.c) c_int {
    return getopt_long_impl(argc, argv, optstring, longopts, idx, 0);
}

fn getopt_long_only_fn(argc: c_int, argv: [*]const ?[*:0]u8, optstring: [*:0]const u8, longopts: ?[*]const Option, idx: ?*c_int) callconv(.c) c_int {
    return getopt_long_impl(argc, argv, optstring, longopts, idx, 1);
}

fn ioctlImpl(fd: c_int, req: c_int, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    const arg = @cVaArg(&ap, usize);
    @cVaEnd(&ap);

    const rc: isize = @bitCast(linux.ioctl(@intCast(fd), @bitCast(@as(c_uint, @bitCast(req))), arg));
    if (rc >= 0) return @intCast(rc);

    // On 64-bit, time_t == long, so no ioctl compat conversion is needed.
    // On 32-bit with time64, the compat table would handle SIOCGSTAMP etc.
    // but that path is only active when SIOCGSTAMP != SIOCGSTAMP_OLD,
    // which requires the full conversion table from the C implementation.
    // For now, just return the error.
    std.c._errno().* = @intCast(-rc);
    return -1;
}

fn reap(pid: c_int) void {
    var status: c_int = undefined;
    while (waitpid(pid, &status, 0) < 0 and std.c._errno().* == @intFromEnum(std.os.linux.E.INTR)) {}
}

fn getword(f: *FILE) ?[*:0]u8 {
    var s: ?[*:0]u8 = null;
    var n: usize = 0;
    return if (getdelim(&s, &n, 0, f) < 0) null else s;
}

fn do_wordexp(s: [*:0]const u8, we: *wordexp_t, flags: c_int) c_int {
    if (flags & WRDE_REUSE != 0) wordfree_fn(we);

    if (flags & WRDE_NOCMD != 0) {
        var sq = false;
        var dq = false;
        var np: usize = 0;
        var idx: usize = 0;
        while (s[idx] != 0) : (idx += 1) {
            const c = s[idx];
            if (c == '\\') {
                if (!sq) {
                    idx += 1;
                    if (s[idx] == 0) return WRDE_SYNTAX;
                }
            } else if (c == '\'') {
                if (!dq) sq = !sq;
            } else if (c == '"') {
                if (!sq) dq = !dq;
            } else if (c == '(') {
                if (np > 0) np += 1;
            } else if (c == ')') {
                if (np > 0) np -= 1;
            } else if (c == '\n' or c == '|' or c == '&' or c == ';' or c == '<' or c == '>' or c == '{' or c == '}') {
                if (!(sq or dq or np > 0)) return WRDE_BADCHAR;
            } else if (c == '$') {
                if (!sq and s[idx + 1] == '(' and s[idx + 2] == '(') {
                    idx += 2;
                    np += 2;
                } else if (!sq and s[idx + 1] == '(') {
                    return WRDE_CMDSUB;
                }
            } else if (c == '`') {
                if (!sq) return WRDE_CMDSUB;
            }
        }
    }

    var wc: usize = 0;
    var wv: ?[*]?[*:0]u8 = null;
    if (flags & WRDE_APPEND != 0) {
        wc = we.we_wordc;
        wv = we.we_wordv;
    }

    var i: usize = wc;
    if (flags & WRDE_DOOFFS != 0) {
        if (we.we_offs > std.math.maxInt(usize) / @sizeOf(?*anyopaque) / 4)
            return nospace(we, flags);
        i += we.we_offs;
    } else {
        we.we_offs = 0;
    }

    var p: [2]c_int = undefined;
    if (pipe2(&p, O_CLOEXEC) < 0) return nospace(we, flags);
    var set: sigset_t = undefined;
    __block_all_sigs(&set);
    const pid = fork();
    __restore_sigs(&set);
    if (pid < 0) {
        _ = close(p[0]);
        _ = close(p[1]);
        return nospace(we, flags);
    }
    if (pid == 0) {
        if (p[1] == 1) _ = fcntl(1, F_SETFD, @as(c_int, 0)) else _ = dup2(p[1], 1);
        const redir: [*:0]const u8 = if (flags & WRDE_SHOWERR != 0) "" else "2>/dev/null";
        _ = execl("/bin/sh", "sh", "-c", "eval \"printf %s\\\\\\\\0 x $1 $2\"", "sh", s, redir, @as(?[*:0]const u8, null));
        _exit(1);
    }
    _ = close(p[1]);

    const f: *FILE = fdopen(p[0], "r") orelse {
        _ = close(p[0]);
        _ = kill(pid, SIGKILL);
        reap(pid);
        return nospace(we, flags);
    };

    var l: usize = if (wv != null) i + 1 else 0;

    free(getword(f));
    if (feof(f) != 0) {
        _ = fclose(f);
        reap(pid);
        return WRDE_SYNTAX;
    }

    var err: c_int = 0;
    while (getword(f)) |w| {
        if (i + 1 >= l) {
            l += l / 2 + 10;
            const tmp: ?[*]?[*:0]u8 = @ptrCast(@alignCast(realloc(@ptrCast(wv), l * @sizeOf(?[*:0]u8))));
            if (tmp == null) break;
            wv = tmp;
        }
        wv.?[i] = w;
        i += 1;
        wv.?[i] = null;
    }
    if (feof(f) == 0) err = WRDE_NOSPACE;
    _ = fclose(f);
    reap(pid);

    if (wv == null) wv = @ptrCast(@alignCast(calloc(i + 1, @sizeOf(?[*:0]u8))));

    we.we_wordv = wv;
    we.we_wordc = i;

    if (flags & WRDE_DOOFFS != 0) {
        if (wv) |v| {
            var j = we.we_offs;
            while (j > 0) : (j -= 1) v[j - 1] = null;
        }
        we.we_wordc -= we.we_offs;
    }
    return err;
}

fn nospace(we: *wordexp_t, flags: c_int) c_int {
    if (flags & WRDE_APPEND == 0) {
        we.we_wordc = 0;
        we.we_wordv = null;
    }
    return WRDE_NOSPACE;
}

fn wordexp_fn(s: [*:0]const u8, we: *wordexp_t, flags: c_int) callconv(.c) c_int {
    var cs: c_int = undefined;
    _ = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cs);
    const r = do_wordexp(s, we, flags);
    _ = pthread_setcancelstate(cs, null);
    return r;
}

fn wordfree_fn(we: *wordexp_t) callconv(.c) void {
    const wv = we.we_wordv orelse return;
    for (0..we.we_wordc) |j| free(wv[we.we_offs + j]);
    free(@ptrCast(wv));
    we.we_wordv = null;
    we.we_wordc = 0;
}

fn syscall_fn(n: c_long, ...) callconv(.c) c_long {
    var ap = @cVaStart();
    const a = @cVaArg(&ap, usize);
    const b = @cVaArg(&ap, usize);
    const c = @cVaArg(&ap, usize);
    const d = @cVaArg(&ap, usize);
    const e = @cVaArg(&ap, usize);
    const f = @cVaArg(&ap, usize);
    @cVaEnd(&ap);

    const rc = linux.syscall6(
        @enumFromInt(@as(usize, @bitCast(@as(isize, n)))),
        a,
        b,
        c,
        d,
        e,
        f,
    );

    const signed: isize = @bitCast(rc);
    if (signed < 0 and signed > -4096) {
        std.c._errno().* = @intCast(-signed);
        return -1;
    }
    return @intCast(signed);
}

fn d_name(de: *anyopaque) [*:0]const u8 {
    return @ptrCast(@as([*]const u8, @ptrCast(de)) + DIRENT_DNAME_OFF);
}

fn do_nftw(path: [*:0]u8, func: nftw_fn_t, fd_limit: c_int, flags: c_int, h: ?*const History) c_int {
    const l = strlen(path);
    const j: usize = if (l > 0 and path[l - 1] == '/') l - 1 else l;
    var st: stat_buf = std.mem.zeroes(stat_buf);
    var ftw_type: c_int = undefined;
    var dfd: c_int = -1;
    var err: c_int = 0;

    const stat_rc = if (flags & FTW_PHYS != 0) lstat(path, &st) else @"stat"(path, &st);
    if (stat_rc < 0) {
        const e = std.c._errno().*;
        if (flags & FTW_PHYS == 0 and e == @intFromEnum(linux.E.NOENT) and lstat(path, &st) == 0)
            ftw_type = FTW_SLN
        else if (e != @intFromEnum(linux.E.ACCES))
            return -1
        else
            ftw_type = FTW_NS;
    } else {
        const mode = get_mode(&st) & S_IFMT;
        if (mode == S_IFDIR)
            ftw_type = if (flags & FTW_DEPTH != 0) FTW_DP else FTW_D
        else if (mode == S_IFLNK)
            ftw_type = if (flags & FTW_PHYS != 0) FTW_SL else FTW_SLN
        else
            ftw_type = FTW_F;
    }

    if (flags & FTW_MOUNT != 0 and h != null and ftw_type != FTW_NS and get_dev(&st) != h.?.dev)
        return 0;

    const new_h = History{
        .chain = h,
        .dev = get_dev(&st),
        .ino = get_ino(&st),
        .level = if (h) |hh| hh.level + 1 else 0,
        .base = j + 1,
    };

    var lev = FTW{
        .level = new_h.level,
        .base = @intCast(if (h) |hh| hh.base else blk: {
            var k = j;
            while (k > 0 and path[k] == '/') : (k -= 1) {}
            while (k > 0 and path[k - 1] != '/') : (k -= 1) {}
            break :blk k;
        }),
    };

    if (ftw_type == FTW_D or ftw_type == FTW_DP) {
        dfd = @"open"(path, O_RDONLY);
        err = std.c._errno().*;
        if (dfd < 0 and err == @intFromEnum(linux.E.ACCES)) ftw_type = FTW_DNR;
        if (fd_limit == 0) _ = close(dfd);
    }

    if (flags & FTW_DEPTH == 0) {
        const r = func(path, &st, ftw_type, &lev);
        if (r != 0) return r;
    }

    // Check for cycles
    var hh = h;
    while (hh) |cur| : (hh = cur.chain) {
        if (cur.dev == get_dev(&st) and cur.ino == get_ino(&st)) return 0;
    }

    if ((ftw_type == FTW_D or ftw_type == FTW_DP) and fd_limit > 0) {
        if (dfd < 0) {
            std.c._errno().* = err;
            return -1;
        }
        const d = fdopendir(dfd) orelse {
            _ = close(dfd);
            return -1;
        };
        while (readdir(d)) |de| {
            const name = d_name(de);
            if (name[0] == '.' and (name[1] == 0 or (name[1] == '.' and name[2] == 0))) continue;
            if (strlen(name) >= PATH_MAX - l) {
                std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
                _ = closedir(d);
                return -1;
            }
            @as([*]u8, @ptrCast(path))[j] = '/';
            _ = strcpy(@as([*]u8, @ptrCast(path)) + j + 1, name);
            const r = do_nftw(path, func, fd_limit - 1, flags, &new_h);
            if (r != 0) {
                _ = closedir(d);
                return r;
            }
        }
        _ = closedir(d);
    }

    @as([*]u8, @ptrCast(path))[l] = 0;
    if (flags & FTW_DEPTH != 0) {
        const r = func(path, &st, ftw_type, &lev);
        if (r != 0) return r;
    }
    return 0;
}

fn nftw_fn(path: [*:0]const u8, func: nftw_fn_t, fd_limit: c_int, flags: c_int) callconv(.c) c_int {
    if (fd_limit <= 0) return 0;
    const l = strlen(path);
    if (l > PATH_MAX) {
        std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
        return -1;
    }
    var pathbuf: [PATH_MAX + 1]u8 = undefined;
    _ = memcpy(&pathbuf, path, l + 1);
    var cs: c_int = undefined;
    _ = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cs);
    const r = do_nftw(@ptrCast(pathbuf[0..l :0]), func, fd_limit, flags, null);
    _ = pthread_setcancelstate(cs, null);
    return r;
}
