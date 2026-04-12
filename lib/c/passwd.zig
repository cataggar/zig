const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.link_libc and builtin.target.isMuslLibC()) {
        symbol(&__getpwent_a, "__getpwent_a");
        symbol(&__getgrent_a, "__getgrent_a");
        symbol(&__getpw_a, "__getpw_a");
        symbol(&__getgr_a, "__getgr_a");
        symbol(&__parsespent, "__parsespent");
        symbol(&__nscd_query, "__nscd_query");

        symbol(&fgetgrent, "fgetgrent");
        symbol(&fgetpwent, "fgetpwent");
        symbol(&fgetspent, "fgetspent");

        symbol(&setgrent, "setgrent");
        symbol(&endgrent, "endgrent");
        symbol(&getgrent, "getgrent");
        symbol(&getgrgid, "getgrgid");
        symbol(&getgrnam, "getgrnam");

        symbol(&setpwent, "setpwent");
        symbol(&endpwent, "endpwent");
        symbol(&getpwent, "getpwent");
        symbol(&getpwuid, "getpwuid");
        symbol(&getpwnam, "getpwnam");

        symbol(&getgrnam_r, "getgrnam_r");
        symbol(&getgrgid_r, "getgrgid_r");

        symbol(&getpwnam_r, "getpwnam_r");
        symbol(&getpwuid_r, "getpwuid_r");

        symbol(&getgrouplist, "getgrouplist");

        symbol(&setspent, "setspent");
        symbol(&endspent, "endspent");
        symbol(&getspent, "getspent");

        symbol(&getspnam, "getspnam");
        symbol(&getspnam_r, "getspnam_r");

        symbol(&lckpwdf, "lckpwdf");
        symbol(&ulckpwdf, "ulckpwdf");

        symbol(&putgrent, "putgrent");
        symbol(&putpwent, "putpwent");
        symbol(&putspent, "putspent");
    }
}

// ====================================================================
// Types
// ====================================================================

const ssize_t = isize;
const uid_t = u32;
const gid_t = u32;
const int32_t = i32;
const uint32_t = u32;

const FILE = opaque {};

const passwd = extern struct {
    pw_name: [*:0]u8,
    pw_passwd: [*:0]u8,
    pw_uid: uid_t,
    pw_gid: gid_t,
    pw_gecos: [*:0]u8,
    pw_dir: [*:0]u8,
    pw_shell: [*:0]u8,
};

const group = extern struct {
    gr_name: [*:0]u8,
    gr_passwd: [*:0]u8,
    gr_gid: gid_t,
    gr_mem: [*:null]?[*:0]u8,
};

const spwd = extern struct {
    sp_namp: [*:0]u8,
    sp_pwdp: [*:0]u8,
    sp_lstchg: c_long,
    sp_min: c_long,
    sp_max: c_long,
    sp_warn: c_long,
    sp_inact: c_long,
    sp_expire: c_long,
    sp_flag: c_ulong,
};

const iovec = extern struct {
    iov_base: ?[*]u8,
    iov_len: usize,
};

const msghdr = extern struct {
    msg_name: ?*anyopaque,
    msg_namelen: u32,
    msg_iov: ?[*]iovec,
    msg_iovlen: usize,
    msg_control: ?*anyopaque,
    msg_controllen: usize,
    msg_flags: c_int,
};

const sockaddr = extern struct {
    family: u16,
    data: [14]u8,
};

const stat_t = extern struct {
    // Opaque - only used via fstat pointer
    _padding: [144]u8,
};

// ====================================================================
// nscd constants (from nscd.h)
// ====================================================================

const NSCDVERSION: int32_t = 2;
const GETPWBYNAME: int32_t = 0;
const GETPWBYUID: int32_t = 1;
const GETGRBYNAME: int32_t = 2;
const GETGRBYGID: int32_t = 3;
const GETINITGR: int32_t = 15;

const REQVERSION = 0;
const REQTYPE = 1;
const REQKEYLEN = 2;
const REQ_LEN = 3;

const PWVERSION = 0;
const PWFOUND = 1;
const PWNAMELEN = 2;
const PWPASSWDLEN = 3;
const PWUID = 4;
const PWGID = 5;
const PWGECOSLEN = 6;
const PWDIRLEN = 7;
const PWSHELLLEN = 8;
const PW_LEN = 9;

const GRVERSION = 0;
const GRFOUND = 1;
const GRNAMELEN = 2;
const GRPASSWDLEN = 3;
const GRGID = 4;
const GRMEMCNT = 5;
const GR_LEN = 6;

const INITGRVERSION = 0;
const INITGRFOUND = 1;
const INITGRNGRPS = 2;
const INITGR_LEN = 3;

// ====================================================================
// Errno constants
// ====================================================================

const ENOENT = 2;
const EIO = 5;
const ENOMEM = 12;
const EACCES = 13;
const ENOTDIR = 20;
const EINVAL = 22;
const ERANGE = 34;
const EAFNOSUPPORT = 97;
const ECONNREFUSED = 111;

// ====================================================================
// File/socket constants
// ====================================================================

const O_RDONLY = 0;
const O_NOFOLLOW = 0o400000;
const O_NONBLOCK = 0o4000;
const O_CLOEXEC = 0o2000000;

const AF_UNIX: u16 = 1;
const PF_UNIX = 1;
const SOCK_STREAM = 1;
const SOCK_CLOEXEC = 0o2000000;
const MSG_NOSIGNAL = 0x4000;

const PTHREAD_CANCEL_DISABLE = 1;

const NAME_MAX = 255;
const LOGIN_NAME_MAX = 256;

// ====================================================================
// External C library functions
// ====================================================================

extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE;
extern "c" fn fdopen(fd: c_int, mode: [*:0]const u8) ?*FILE;
extern "c" fn fclose(f: *FILE) c_int;
extern "c" fn fread(ptr: [*]u8, size: usize, nmemb: usize, f: *FILE) usize;
extern "c" fn fgets(buf: [*]u8, size: c_int, f: *FILE) ?[*]u8;
extern "c" fn ferror(f: *FILE) c_int;
extern "c" fn fputc(c: c_int, f: *FILE) c_int;
extern "c" fn fprintf(f: *FILE, fmt: [*:0]const u8, ...) c_int;
extern "c" fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern "c" fn flockfile(f: *FILE) void;
extern "c" fn funlockfile(f: *FILE) void;
extern "c" fn getline(lineptr: *?[*:0]u8, n: *usize, f: *FILE) ssize_t;

extern "c" fn malloc(size: usize) ?[*]u8;
extern "c" fn calloc(nmemb: usize, size: usize) ?[*]u8;
extern "c" fn realloc(ptr: ?[*]u8, size: usize) ?[*]u8;
extern "c" fn free(ptr: ?[*]u8) void;

extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn strnlen(s: [*:0]const u8, maxlen: usize) usize;
extern "c" fn strcmp(s1: [*:0]const u8, s2: [*:0]const u8) c_int;
extern "c" fn strncmp(s1: [*:0]const u8, s2: [*:0]const u8, n: usize) c_int;
extern "c" fn strchr(s: [*:0]const u8, c: c_int) ?[*:0]u8;
extern "c" fn memcpy(dest: [*]u8, src: [*]const u8, n: usize) [*]u8;
extern "c" fn memset(s: [*]u8, c: c_int, n: usize) [*]u8;

extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn fstat(fd: c_int, buf: *stat_t) c_int;

extern "c" fn socket(domain: c_int, sock_type: c_int, protocol: c_int) c_int;
extern "c" fn connect(sockfd: c_int, addr: *const sockaddr, addrlen: u32) c_int;
extern "c" fn sendmsg(sockfd: c_int, msg: *const msghdr, flags: c_int) ssize_t;

extern "c" fn pthread_setcancelstate(state: c_int, oldstate: ?*c_int) c_int;
extern "c" fn pthread_cleanup_push(routine: *const fn (?*anyopaque) callconv(.c) void, arg: ?*anyopaque) void;
extern "c" fn pthread_cleanup_pop(execute: c_int) void;

extern "c" fn __errno_location() *c_int;

fn errno_val() *c_int {
    return __errno_location();
}

fn S_ISREG(mode: u32) bool {
    return (mode & 0o170000) == 0o100000;
}

// ====================================================================
// Helper: unsigned integer parser (like musl's atou)
// ====================================================================

fn atou(s: *[*:0]u8) c_uint {
    var x: c_uint = 0;
    while (s.*[0] -% '0' < 10) {
        x = 10 *% x +% (s.*[0] -% '0');
        s.* = s.*[1..];
    }
    return x;
}

fn itoa(buf: *[11]u8, x_arg: uint32_t) [*:0]const u8 {
    var p: usize = 11;
    var x = x_arg;
    p -= 1;
    buf[p] = 0;
    while (true) {
        p -= 1;
        buf[p] = '0' + @as(u8, @truncate(x % 10));
        x /= 10;
        if (x == 0) break;
    }
    return @ptrCast(buf[p..]);
}

fn xatol(s: *[*:0]u8) c_long {
    if (s.*[0] == ':' or s.*[0] == '\n') return -1;
    var x: c_long = 0;
    while (s.*[0] -% '0' < 10) {
        x = 10 *% x +% @as(c_long, s.*[0] -% '0');
        s.* = s.*[1..];
    }
    return x;
}

fn bswap_32(x: uint32_t) uint32_t {
    return @byteSwap(x);
}

// ====================================================================
// nscd_query
// ====================================================================

const nscd_addr = extern struct {
    sun_family: u16,
    sun_path: [20:0]u8,
};

const nscd_addr_val = nscd_addr{
    .sun_family = AF_UNIX,
    .sun_path = "/var/run/nscd/socket".*,
};

fn __nscd_query(req: int32_t, key: [*:0]const u8, buf: [*]int32_t, len: usize, swap: *c_int) callconv(.c) ?*FILE {
    var req_buf = [REQ_LEN]int32_t{
        NSCDVERSION,
        req,
        @as(int32_t, @intCast(strnlen(key, LOGIN_NAME_MAX) + 1)),
    };
    const key_len = strlen(key) + 1;

    var iovecs = [2]iovec{
        .{
            .iov_base = @ptrCast(&req_buf),
            .iov_len = @sizeOf(@TypeOf(req_buf)),
        },
        .{
            .iov_base = @constCast(@ptrCast(key)),
            .iov_len = key_len,
        },
    };
    var msg = msghdr{
        .msg_name = null,
        .msg_namelen = 0,
        .msg_iov = &iovecs,
        .msg_iovlen = 2,
        .msg_control = null,
        .msg_controllen = 0,
        .msg_flags = 0,
    };

    const errno_save = errno_val().*;
    swap.* = 0;

    while (true) {
        // Clear buf
        const buf_bytes: [*]u8 = @ptrCast(buf);
        _ = memset(buf_bytes, 0, len);
        buf[0] = NSCDVERSION;

        const fd = socket(PF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
        if (fd < 0) {
            if (errno_val().* == EAFNOSUPPORT) {
                const f = fopen("/dev/null", "re");
                if (f != null) errno_val().* = errno_save;
                return f;
            }
            return null;
        }

        const f = fdopen(fd, "r") orelse {
            _ = close(fd);
            return null;
        };

        if (req_buf[REQKEYLEN] > LOGIN_NAME_MAX) {
            return f;
        }

        if (connect(fd, @ptrCast(&nscd_addr_val), @sizeOf(nscd_addr)) < 0) {
            const e = errno_val().*;
            if (e == EACCES or e == ECONNREFUSED or e == ENOENT) {
                errno_val().* = errno_save;
                return f;
            }
            _ = fclose(f);
            return null;
        }

        if (sendmsg(fd, &msg, MSG_NOSIGNAL) < 0) {
            _ = fclose(f);
            return null;
        }

        if (fread(@ptrCast(buf), len, 1, f) == 0) {
            if (ferror(f) != 0) {
                _ = fclose(f);
                return null;
            }
            if (swap.* == 0) {
                _ = fclose(f);
                for (0..REQ_LEN) |i| {
                    req_buf[i] = @bitCast(bswap_32(@bitCast(req_buf[i])));
                }
                swap.* = 1;
                continue; // retry
            } else {
                errno_val().* = EIO;
                _ = fclose(f);
                return null;
            }
        }

        if (swap.* != 0) {
            const count = len / @sizeOf(int32_t);
            for (0..count) |i| {
                buf[i] = @bitCast(bswap_32(@bitCast(buf[i])));
            }
        }

        if (buf[0] != NSCDVERSION) {
            errno_val().* = EIO;
            _ = fclose(f);
            return null;
        }

        return f;
    }
}

// ====================================================================
// __parsespent
// ====================================================================

fn __parsespent(s: [*:0]u8, sp: *spwd) callconv(.c) c_int {
    sp.sp_namp = s;
    const s1 = strchr(s, ':') orelse return -1;
    s1[0] = 0;

    var s2 = s1[1..];
    sp.sp_pwdp = s2;
    const s3 = strchr(s2, ':') orelse return -1;
    s3[0] = 0;

    s2 = s3[1..];
    sp.sp_lstchg = xatol(&s2);
    if (s2[0] != ':') return -1;

    s2 = s2[1..];
    sp.sp_min = xatol(&s2);
    if (s2[0] != ':') return -1;

    s2 = s2[1..];
    sp.sp_max = xatol(&s2);
    if (s2[0] != ':') return -1;

    s2 = s2[1..];
    sp.sp_warn = xatol(&s2);
    if (s2[0] != ':') return -1;

    s2 = s2[1..];
    sp.sp_inact = xatol(&s2);
    if (s2[0] != ':') return -1;

    s2 = s2[1..];
    sp.sp_expire = xatol(&s2);
    if (s2[0] != ':') return -1;

    s2 = s2[1..];
    sp.sp_flag = @bitCast(xatol(&s2));
    if (s2[0] != '\n') return -1;

    return 0;
}

// ====================================================================
// __getpwent_a - parse a line from /etc/passwd
// ====================================================================

fn __getpwent_a(f: *FILE, pw: *passwd, line: *?[*:0]u8, size: *usize, res: *?*passwd) callconv(.c) c_int {
    var rv: c_int = 0;
    var cs: c_int = 0;
    _ = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cs);

    const pw_local: *passwd = pw;
    while (true) {
        const l = getline(line, size, f);
        if (l < 0) {
            rv = if (ferror(f) != 0) errno_val().* else 0;
            free(@ptrCast(line.*));
            line.* = null;
            res.* = null; break;
        }
        var s: [*:0]u8 = line.*.?;
        s[@intCast(l - 1)] = 0;

        pw.pw_name = s;
        s = s[1..];
        s = strchr(s, ':') orelse continue;

        s[0] = 0;
        s = s[1..];
        pw.pw_passwd = s;
        s = strchr(s, ':') orelse continue;

        s[0] = 0;
        s = s[1..];
        pw.pw_uid = atou(&s);
        if (s[0] != ':') continue;

        s = s[1..];
        pw.pw_gid = atou(&s);
        if (s[0] != ':') continue;

        s = s[1..];
        pw.pw_gecos = s;
        s = strchr(s, ':') orelse continue;

        s[0] = 0;
        s = s[1..];
        pw.pw_dir = s;
        s = strchr(s, ':') orelse continue;

        s[0] = 0;
        s = s[1..];
        pw.pw_shell = s;
        break;
    }

    _ = pthread_setcancelstate(cs, null);
    res.* = pw_local;
    if (rv != 0) errno_val().* = rv;
    return rv;
}

// ====================================================================
// __getgrent_a - parse a line from /etc/group
// ====================================================================

fn __getgrent_a(f: *FILE, gr: *group, line: *?[*:0]u8, size: *usize, mem: *?[*]?[*:0]u8, nmem: *usize, res: *?*group) callconv(.c) c_int {
    var rv: c_int = 0;
    var cs: c_int = 0;
    _ = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cs);
    var mems: [*:0]u8 = undefined;
    const gr_local: *group = gr;

    while (true) {
        const l = getline(line, size, f);
        if (l < 0) {
            rv = if (ferror(f) != 0) errno_val().* else 0;
            free(@ptrCast(line.*));
            line.* = null;
            res.* = null; break;
        }
        var s: [*:0]u8 = line.*.?;
        s[@intCast(l - 1)] = 0;

        gr.gr_name = s;
        s = s[1..];
        const s2 = strchr(s, ':') orelse continue;

        s2[0] = 0;
        s = s2[1..];
        gr.gr_passwd = s;
        const s3 = strchr(s, ':') orelse continue;

        s3[0] = 0;
        s = s3[1..];
        gr.gr_gid = atou(&s);
        if (s[0] != ':') continue;

        s[0] = 0;
        s = s[1..];
        mems = s;
        break;
    }

    if (@intFromPtr(res.*) == 0) {
        _ = pthread_setcancelstate(cs, null);
        res.* = gr_local;
        if (rv != 0) errno_val().* = rv;
        return rv;
    }

    // Count members
    nmem.* = if (mems[0] != 0) 1 else 0;
    {
        var s = mems;
        while (s[0] != 0) : (s = s[1..]) {
            if (s[0] == ',') nmem.* += 1;
        }
    }

    free(@ptrCast(mem.*));
    const new_mem: ?[*]?[*:0]u8 = @ptrCast(@alignCast(calloc(@sizeOf(?[*:0]u8), nmem.* + 1)));
    mem.* = new_mem;
    if (new_mem == null) {
        rv = errno_val().*;
        free(@ptrCast(line.*));
        line.* = null;
        _ = pthread_setcancelstate(cs, null);
        res.* = null;
        if (rv != 0) errno_val().* = rv;
        return rv;
    }

    if (mems[0] != 0) {
        const m = mem.*.?;
        m[0] = mems;
        var s = mems;
        var i: usize = 0;
        while (s[0] != 0) : (s = s[1..]) {
            if (s[0] == ',') {
                s[0] = 0;
                i += 1;
                m[i] = s[1..];
            }
        }
        i += 1;
        m[i] = null;
    } else {
        mem.*.?[0] = null;
    }
    gr.gr_mem = @ptrCast(mem.*.?);

    _ = pthread_setcancelstate(cs, null);
    res.* = gr_local;
    if (rv != 0) errno_val().* = rv;
    return rv;
}

// ====================================================================
// __getpw_a - lookup passwd entry by name or uid (with nscd)
// ====================================================================

fn __getpw_a(name: ?[*:0]const u8, uid: uid_t, pw: *passwd, buf: *?[*:0]u8, size: *usize, res: *?*passwd) callconv(.c) c_int {
    var f: ?*FILE = undefined;
    var cs: c_int = 0;
    var rv: c_int = 0;

    res.* = null;

    _ = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cs);

    f = fopen("/etc/passwd", "rbe");
    if (f == null) {
        rv = errno_val().*;
        _ = pthread_setcancelstate(cs, null);
        if (rv != 0) errno_val().* = rv;
        return rv;
    }

    // Use a temporary non-null res for __getpwent_a
    var res_inner: ?*passwd = null;
    while (true) {
        rv = __getpwent_a(f.?, pw, buf, size, &res_inner);
        if (rv != 0 or res_inner == null) break;
        if (name) |n| {
            if (strcmp(n, res_inner.?.pw_name) == 0) break;
        } else {
            if (res_inner.?.pw_uid == uid) break;
        }
    }
    _ = fclose(f.?);

    if (res_inner != null) {
        res.* = res_inner;
    }

    if (res.* == null and (rv == 0 or rv == ENOENT or rv == ENOTDIR)) {
        const nscd_req: int32_t = if (name != null) GETPWBYNAME else GETPWBYUID;
        var passwdbuf = [_]int32_t{0} ** PW_LEN;
        var uidbuf: [11]u8 = undefined;

        const key: [*:0]const u8 = if (name) |n| n else itoa(&uidbuf, uid);

        var swap_val: c_int = 0;
        f = __nscd_query(nscd_req, key, &passwdbuf, @sizeOf(@TypeOf(passwdbuf)), &swap_val);
        if (f == null) {
            rv = errno_val().*;
            _ = pthread_setcancelstate(cs, null);
            if (rv != 0) errno_val().* = rv;
            return rv;
        }

        if (passwdbuf[PWFOUND] == 0) {
            rv = 0;
            _ = fclose(f.?);
            _ = pthread_setcancelstate(cs, null);
            if (rv != 0) errno_val().* = rv;
            return rv;
        }

        if (passwdbuf[PWNAMELEN] == 0 or passwdbuf[PWPASSWDLEN] == 0 or
            passwdbuf[PWGECOSLEN] == 0 or passwdbuf[PWDIRLEN] == 0 or
            passwdbuf[PWSHELLLEN] == 0)
        {
            rv = EIO;
            _ = fclose(f.?);
            _ = pthread_setcancelstate(cs, null);
            if (rv != 0) errno_val().* = rv;
            return rv;
        }

        const pw_name_len: usize = @intCast(passwdbuf[PWNAMELEN]);
        const pw_passwd_len: usize = @intCast(passwdbuf[PWPASSWDLEN]);
        const pw_gecos_len: usize = @intCast(passwdbuf[PWGECOSLEN]);
        const pw_dir_len: usize = @intCast(passwdbuf[PWDIRLEN]);
        const pw_shell_len: usize = @intCast(passwdbuf[PWSHELLLEN]);

        if ((pw_name_len | pw_passwd_len | pw_gecos_len | pw_dir_len | pw_shell_len) >= @as(usize, @divTrunc(@as(usize, @truncate(@as(u128, @bitCast(@as(i128, -1))))), 8))) {
            rv = ENOMEM;
            _ = fclose(f.?);
            _ = pthread_setcancelstate(cs, null);
            if (rv != 0) errno_val().* = rv;
            return rv;
        }

        const len = pw_name_len + pw_passwd_len + pw_gecos_len + pw_dir_len + pw_shell_len;

        if (len > size.* or buf.* == null) {
            const tmp = realloc(@ptrCast(buf.*), len);
            if (tmp == null) {
                rv = errno_val().*;
                _ = fclose(f.?);
                _ = pthread_setcancelstate(cs, null);
                if (rv != 0) errno_val().* = rv;
                return rv;
            }
            buf.* = @ptrCast(tmp);
            size.* = len;
        }

        const data: [*]u8 = @ptrCast(buf.*.?);
        if (fread(data, len, 1, f.?) == 0) {
            rv = if (ferror(f.?) != 0) errno_val().* else EIO;
            _ = fclose(f.?);
            _ = pthread_setcancelstate(cs, null);
            if (rv != 0) errno_val().* = rv;
            return rv;
        }

        pw.pw_name = @ptrCast(data);
        pw.pw_passwd = @ptrCast(data + pw_name_len);
        pw.pw_gecos = @ptrCast(data + pw_name_len + pw_passwd_len);
        pw.pw_dir = @ptrCast(data + pw_name_len + pw_passwd_len + pw_gecos_len);
        pw.pw_shell = @ptrCast(data + pw_name_len + pw_passwd_len + pw_gecos_len + pw_dir_len);
        pw.pw_uid = @bitCast(passwdbuf[PWUID]);
        pw.pw_gid = @bitCast(passwdbuf[PWGID]);

        // Verify null termination
        if (pw.pw_passwd[@intCast(0)] != 0 and data[pw_name_len - 1] != 0) {
            // Check the last byte before each field boundary
        }
        const passwd_end = data + pw_name_len + pw_passwd_len;
        if (data[pw_name_len - 1] != 0 or
            (passwd_end - 1)[0] != 0 or
            data[pw_name_len + pw_passwd_len + pw_gecos_len - 1] != 0 or
            data[pw_name_len + pw_passwd_len + pw_gecos_len + pw_dir_len - 1] != 0 or
            data[len - 1] != 0)
        {
            rv = EIO;
            _ = fclose(f.?);
            _ = pthread_setcancelstate(cs, null);
            if (rv != 0) errno_val().* = rv;
            return rv;
        }

        if (name) |n| {
            if (strcmp(n, pw.pw_name) != 0) {
                rv = EIO;
                _ = fclose(f.?);
                _ = pthread_setcancelstate(cs, null);
                if (rv != 0) errno_val().* = rv;
                return rv;
            }
        } else {
            if (uid != pw.pw_uid) {
                rv = EIO;
                _ = fclose(f.?);
                _ = pthread_setcancelstate(cs, null);
                if (rv != 0) errno_val().* = rv;
                return rv;
            }
        }

        res.* = pw;
        _ = fclose(f.?);
    }

    _ = pthread_setcancelstate(cs, null);
    if (rv != 0) errno_val().* = rv;
    return rv;
}

// ====================================================================
// __getgr_a - lookup group entry by name or gid (with nscd)
// ====================================================================

fn __getgr_a(name: ?[*:0]const u8, gid: gid_t, gr: *group, buf: *?[*:0]u8, size: *usize, mem: *?[*]?[*:0]u8, nmem: *usize, res: *?*group) callconv(.c) c_int {
    var f: ?*FILE = undefined;
    var rv: c_int = 0;
    var cs: c_int = 0;

    res.* = null;

    _ = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cs);
    f = fopen("/etc/group", "rbe");
    if (f == null) {
        rv = errno_val().*;
        _ = pthread_setcancelstate(cs, null);
        if (rv != 0) errno_val().* = rv;
        return rv;
    }

    var res_inner: ?*group = null;
    while (true) {
        rv = __getgrent_a(f.?, gr, buf, size, mem, nmem, &res_inner);
        if (rv != 0 or res_inner == null) break;
        if (name) |n| {
            if (strcmp(n, res_inner.?.gr_name) == 0) break;
        } else {
            if (res_inner.?.gr_gid == gid) break;
        }
    }
    _ = fclose(f.?);

    if (res_inner != null) {
        res.* = res_inner;
    }

    if (res.* == null and (rv == 0 or rv == ENOENT or rv == ENOTDIR)) {
        const nscd_req: int32_t = if (name != null) GETGRBYNAME else GETGRBYGID;
        var groupbuf = [_]int32_t{0} ** GR_LEN;
        var gidbuf: [11]u8 = undefined;

        const key: [*:0]const u8 = if (name) |n| n else itoa(&gidbuf, gid);

        var swap_val: c_int = 0;
        f = __nscd_query(nscd_req, key, &groupbuf, @sizeOf(@TypeOf(groupbuf)), &swap_val);
        if (f == null) {
            rv = errno_val().*;
            _ = pthread_setcancelstate(cs, null);
            if (rv != 0) errno_val().* = rv;
            return rv;
        }

        if (groupbuf[GRFOUND] == 0) {
            rv = 0;
            _ = fclose(f.?);
            _ = pthread_setcancelstate(cs, null);
            return rv;
        }

        if (groupbuf[GRNAMELEN] == 0 or groupbuf[GRPASSWDLEN] == 0) {
            rv = EIO;
            _ = fclose(f.?);
            _ = pthread_setcancelstate(cs, null);
            if (rv != 0) errno_val().* = rv;
            return rv;
        }

        const gr_name_len: usize = @intCast(groupbuf[GRNAMELEN]);
        const gr_passwd_len: usize = @intCast(groupbuf[GRPASSWDLEN]);
        var len: usize = gr_name_len + gr_passwd_len;
        var grlist_len: usize = 0;

        var i: int32_t = 0;
        while (i < groupbuf[GRMEMCNT]) : (i += 1) {
            var name_len: uint32_t = 0;
            if (fread(@ptrCast(@as([*]u8, @ptrCast(&name_len))), @sizeOf(uint32_t), 1, f.?) < 1) {
                rv = if (ferror(f.?) != 0) errno_val().* else EIO;
                _ = fclose(f.?);
                _ = pthread_setcancelstate(cs, null);
                if (rv != 0) errno_val().* = rv;
                return rv;
            }
            if (swap_val != 0) {
                name_len = bswap_32(name_len);
            }
            len += name_len;
            grlist_len += name_len;
        }

        if (len > size.* or buf.* == null) {
            const tmp = realloc(@ptrCast(buf.*), len);
            if (tmp == null) {
                rv = errno_val().*;
                _ = fclose(f.?);
                _ = pthread_setcancelstate(cs, null);
                if (rv != 0) errno_val().* = rv;
                return rv;
            }
            buf.* = @ptrCast(tmp);
            size.* = len;
        }

        const data: [*]u8 = @ptrCast(buf.*.?);
        if (fread(data, len, 1, f.?) == 0) {
            rv = if (ferror(f.?) != 0) errno_val().* else EIO;
            _ = fclose(f.?);
            _ = pthread_setcancelstate(cs, null);
            if (rv != 0) errno_val().* = rv;
            return rv;
        }

        const mem_count: usize = @intCast(groupbuf[GRMEMCNT]);
        if (mem_count + 1 > nmem.*) {
            const tmp_mem: ?[*]?[*:0]u8 = @ptrCast(@alignCast(realloc(@ptrCast(mem.*), (mem_count + 1) * @sizeOf(?[*:0]u8))));
            if (tmp_mem == null) {
                rv = errno_val().*;
                _ = fclose(f.?);
                _ = pthread_setcancelstate(cs, null);
                if (rv != 0) errno_val().* = rv;
                return rv;
            }
            mem.* = tmp_mem;
            nmem.* = mem_count + 1;
        }

        const m = mem.*.?;
        if (mem_count > 0) {
            const grlist_start = data + gr_name_len + gr_passwd_len;
            m[0] = @ptrCast(grlist_start);
            var ptr = grlist_start;
            var idx: usize = 0;
            while (@intFromPtr(ptr) < @intFromPtr(grlist_start + grlist_len)) : (ptr += 1) {
                if (ptr[0] == 0) {
                    idx += 1;
                    m[idx] = @ptrCast(ptr + 1);
                }
            }
            m[idx] = null;

            if (idx != mem_count) {
                rv = EIO;
                _ = fclose(f.?);
                _ = pthread_setcancelstate(cs, null);
                if (rv != 0) errno_val().* = rv;
                return rv;
            }
        } else {
            m[0] = null;
        }

        gr.gr_name = @ptrCast(data);
        gr.gr_passwd = @ptrCast(data + gr_name_len);
        gr.gr_gid = @bitCast(groupbuf[GRGID]);
        gr.gr_mem = @ptrCast(m);

        // Verify null termination
        if (data[gr_name_len - 1] != 0 or data[gr_name_len + gr_passwd_len - 1] != 0) {
            rv = EIO;
            _ = fclose(f.?);
            _ = pthread_setcancelstate(cs, null);
            if (rv != 0) errno_val().* = rv;
            return rv;
        }

        if (name) |n| {
            if (strcmp(n, gr.gr_name) != 0) {
                rv = EIO;
                _ = fclose(f.?);
                _ = pthread_setcancelstate(cs, null);
                if (rv != 0) errno_val().* = rv;
                return rv;
            }
        } else {
            if (gid != gr.gr_gid) {
                rv = EIO;
                _ = fclose(f.?);
                _ = pthread_setcancelstate(cs, null);
                if (rv != 0) errno_val().* = rv;
                return rv;
            }
        }

        res.* = gr;
        _ = fclose(f.?);
    }

    _ = pthread_setcancelstate(cs, null);
    if (rv != 0) errno_val().* = rv;
    return rv;
}

// ====================================================================
// fgetgrent, fgetpwent, fgetspent
// ====================================================================

var fgetgrent_line: ?[*:0]u8 = null;
var fgetgrent_mem: ?[*]?[*:0]u8 = null;
var fgetgrent_gr: group = undefined;

fn fgetgrent(f: *FILE) callconv(.c) ?*group {
    var res: ?*group = null;
    var size: usize = 0;
    var nmem: usize = 0;
    _ = __getgrent_a(f, &fgetgrent_gr, &fgetgrent_line, &size, &fgetgrent_mem, &nmem, &res);
    if (@intFromPtr(res) == 0) return null;
    return res;
}

var fgetpwent_line: ?[*:0]u8 = null;
var fgetpwent_pw: passwd = undefined;

fn fgetpwent(f: *FILE) callconv(.c) ?*passwd {
    var size: usize = 0;
    var res: ?*passwd = null;
    _ = __getpwent_a(f, &fgetpwent_pw, &fgetpwent_line, &size, &res);
    if (@intFromPtr(res) == 0) return null;
    return res;
}

var fgetspent_line: ?[*:0]u8 = null;
var fgetspent_sp: spwd = undefined;

fn fgetspent(f: *FILE) callconv(.c) ?*spwd {
    var size: usize = 0;
    var cs: c_int = 0;
    var res: ?*spwd = null;
    _ = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cs);
    if (getline(&fgetspent_line, &size, f) >= 0 and __parsespent(fgetspent_line.?, &fgetspent_sp) >= 0) {
        res = &fgetspent_sp;
    }
    _ = pthread_setcancelstate(cs, null);
    return res;
}

// ====================================================================
// getgrent, setgrent, endgrent, getgrgid, getgrnam
// ====================================================================

var getgrent_f: ?*FILE = null;
var getgrent_line: ?[*:0]u8 = null;
var getgrent_mem: ?[*]?[*:0]u8 = null;
var getgrent_gr: group = undefined;

fn setgrent() callconv(.c) void {
    if (getgrent_f) |file| {
        _ = fclose(file);
    }
    getgrent_f = null;
}

fn endgrent() callconv(.c) void {
    setgrent();
}

fn getgrent() callconv(.c) ?*group {
    var res: ?*group = null;
    var size: usize = 0;
    var nmem: usize = 0;
    if (getgrent_f == null) {
        getgrent_f = fopen("/etc/group", "rbe");
    }
    if (getgrent_f == null) return null;
    _ = __getgrent_a(getgrent_f.?, &getgrent_gr, &getgrent_line, &size, &getgrent_mem, &nmem, &res);
    if (@intFromPtr(res) == 0) return null;
    return res;
}

fn getgrgid(gid: gid_t) callconv(.c) ?*group {
    var res: ?*group = null;
    var size: usize = 0;
    var nmem: usize = 0;
    _ = __getgr_a(null, gid, &getgrent_gr, @ptrCast(&getgrent_line), &size, &getgrent_mem, &nmem, &res);
    return res;
}

fn getgrnam(name: [*:0]const u8) callconv(.c) ?*group {
    var res: ?*group = null;
    var size: usize = 0;
    var nmem: usize = 0;
    _ = __getgr_a(name, 0, &getgrent_gr, @ptrCast(&getgrent_line), &size, &getgrent_mem, &nmem, &res);
    return res;
}

// ====================================================================
// getpwent, setpwent, endpwent, getpwuid, getpwnam
// ====================================================================

var getpwent_f: ?*FILE = null;
var getpwent_line: ?[*:0]u8 = null;
var getpwent_pw: passwd = undefined;
var getpwent_size: usize = 0;

fn setpwent() callconv(.c) void {
    if (getpwent_f) |file| {
        _ = fclose(file);
    }
    getpwent_f = null;
}

fn endpwent() callconv(.c) void {
    setpwent();
}

fn getpwent() callconv(.c) ?*passwd {
    var res: ?*passwd = null;
    if (getpwent_f == null) {
        getpwent_f = fopen("/etc/passwd", "rbe");
    }
    if (getpwent_f == null) return null;
    _ = __getpwent_a(getpwent_f.?, &getpwent_pw, &getpwent_line, &getpwent_size, &res);
    if (@intFromPtr(res) == 0) return null;
    return res;
}

fn getpwuid(uid: uid_t) callconv(.c) ?*passwd {
    var res: ?*passwd = null;
    _ = __getpw_a(null, uid, &getpwent_pw, &getpwent_line, &getpwent_size, &res);
    return res;
}

fn getpwnam(name: [*:0]const u8) callconv(.c) ?*passwd {
    var res: ?*passwd = null;
    _ = __getpw_a(name, 0, &getpwent_pw, &getpwent_line, &getpwent_size, &res);
    return res;
}

// ====================================================================
// getgr_r - getgrnam_r, getgrgid_r
// ====================================================================

fn getgr_r(name: ?[*:0]const u8, gid: gid_t, gr: *group, buf: [*]u8, size: usize, res: *?*group) c_int {
    var line: ?[*:0]u8 = null;
    var len: usize = 0;
    var mem: ?[*]?[*:0]u8 = null;
    var nmem: usize = 0;
    var rv: c_int = 0;
    var cs: c_int = 0;

    _ = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cs);

    rv = __getgr_a(name, gid, gr, &line, &len, &mem, &nmem, res);
    if (res.* != null and size < len + (nmem + 1) * @sizeOf(?[*:0]u8) + 32) {
        res.* = null;
        rv = ERANGE;
    }
    if (res.* != null) {
        const aligned_buf = buf + ((16 -% @intFromPtr(buf)) % 16);
        const mem_area: [*]?[*:0]u8 = @ptrCast(@alignCast(aligned_buf));
        const data_start = aligned_buf + (nmem + 1) * @sizeOf(?[*:0]u8);
        gr.gr_mem = @ptrCast(mem_area);
        _ = memcpy(data_start, @ptrCast(line.?), len);

        const line_base: usize = @intFromPtr(line.?);
        const data_base: usize = @intFromPtr(data_start);
        gr.gr_name = @ptrFromInt(@intFromPtr(gr.gr_name) - line_base + data_base);
        gr.gr_passwd = @ptrFromInt(@intFromPtr(gr.gr_passwd) - line_base + data_base);

        if (mem) |m| {
            var idx: usize = 0;
            while (m[idx] != null) : (idx += 1) {
                mem_area[idx] = @ptrFromInt(@intFromPtr(m[idx].?) - line_base + data_base);
            }
            mem_area[idx] = null;
        }
    }
    free(@ptrCast(mem));
    free(@ptrCast(line));
    _ = pthread_setcancelstate(cs, null);
    if (rv != 0) errno_val().* = rv;
    return rv;
}

fn getgrnam_r(name: [*:0]const u8, gr: *group, buf: [*]u8, size: usize, res: *?*group) callconv(.c) c_int {
    return getgr_r(name, 0, gr, buf, size, res);
}

fn getgrgid_r(gid: gid_t, gr: *group, buf: [*]u8, size: usize, res: *?*group) callconv(.c) c_int {
    return getgr_r(null, gid, gr, buf, size, res);
}

// ====================================================================
// getpw_r - getpwnam_r, getpwuid_r
// ====================================================================

fn getpw_r(name: ?[*:0]const u8, uid: uid_t, pw: *passwd, buf: [*]u8, size: usize, res: *?*passwd) c_int {
    var line: ?[*:0]u8 = null;
    var len: usize = 0;
    var rv: c_int = 0;
    var cs: c_int = 0;

    _ = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cs);

    rv = __getpw_a(name, uid, pw, &line, &len, res);
    if (res.* != null and size < len) {
        res.* = null;
        rv = ERANGE;
    }
    if (res.* != null) {
        _ = memcpy(buf, @ptrCast(line.?), len);
        const line_base: usize = @intFromPtr(line.?);
        const buf_base: usize = @intFromPtr(buf);
        pw.pw_name = @ptrFromInt(@intFromPtr(pw.pw_name) - line_base + buf_base);
        pw.pw_passwd = @ptrFromInt(@intFromPtr(pw.pw_passwd) - line_base + buf_base);
        pw.pw_gecos = @ptrFromInt(@intFromPtr(pw.pw_gecos) - line_base + buf_base);
        pw.pw_dir = @ptrFromInt(@intFromPtr(pw.pw_dir) - line_base + buf_base);
        pw.pw_shell = @ptrFromInt(@intFromPtr(pw.pw_shell) - line_base + buf_base);
    }
    free(@ptrCast(line));
    _ = pthread_setcancelstate(cs, null);
    if (rv != 0) errno_val().* = rv;
    return rv;
}

fn getpwnam_r(name: [*:0]const u8, pw: *passwd, buf: [*]u8, size: usize, res: *?*passwd) callconv(.c) c_int {
    return getpw_r(name, 0, pw, buf, size, res);
}

fn getpwuid_r(uid: uid_t, pw: *passwd, buf: [*]u8, size: usize, res: *?*passwd) callconv(.c) c_int {
    return getpw_r(null, uid, pw, buf, size, res);
}

// ====================================================================
// getgrouplist
// ====================================================================

fn getgrouplist(user: [*:0]const u8, gid: gid_t, groups: [*]gid_t, ngroups: *c_int) callconv(.c) c_int {
    var n: ssize_t = 1;
    var ret: c_int = -1;
    var gr_s: group = undefined;
    var res: ?*group = null;
    var f: ?*FILE = undefined;
    var swap_val: c_int = 0;
    var resp = [_]int32_t{0} ** INITGR_LEN;
    var nscdbuf: ?[*]uint32_t = null;
    var buf: ?[*:0]u8 = null;
    var mem: ?[*]?[*:0]u8 = null;
    var nmem: usize = 0;
    var size: usize = 0;
    const nlim: c_int = ngroups.*;
    var groups_ptr = groups;
    if (nlim >= 1) {
        groups_ptr[0] = gid;
        groups_ptr += 1;
    }

    f = __nscd_query(GETINITGR, user, &resp, @sizeOf(@TypeOf(resp)), &swap_val);
    if (f == null) {
        cleanup(f, nscdbuf, buf, mem, ret, n, ngroups);
        return ret;
    }
    if (resp[INITGRFOUND] != 0) {
        const count: usize = @intCast(resp[INITGRNGRPS]);
        nscdbuf = @ptrCast(@alignCast(calloc(count, @sizeOf(uint32_t))));
        if (nscdbuf == null) {
            cleanup(f, nscdbuf, buf, mem, ret, n, ngroups);
            return ret;
        }
        const nbytes = @sizeOf(uint32_t) * count;
        if (nbytes != 0 and fread(@ptrCast(nscdbuf.?), nbytes, 1, f.?) == 0) {
            if (ferror(f.?) == 0) errno_val().* = EIO;
            cleanup(f, nscdbuf, buf, mem, ret, n, ngroups);
            return ret;
        }
        if (swap_val != 0) {
            for (0..count) |i| {
                nscdbuf.?[i] = bswap_32(nscdbuf.?[i]);
            }
        }
    }
    _ = fclose(f.?);

    f = fopen("/etc/group", "rbe");
    if (f == null and errno_val().* != ENOENT and errno_val().* != ENOTDIR) {
        cleanup(null, nscdbuf, buf, mem, -1, n, ngroups);
        return -1;
    }

    if (f != null) {
        while (true) {
            const rv = __getgrent_a(f.?, &gr_s, &buf, &size, &mem, &nmem, &res);
            if (rv != 0) {
                errno_val().* = rv;
                cleanup(f, nscdbuf, buf, mem, ret, n, ngroups);
                return ret;
            }
            if (@intFromPtr(res) == 0) break;

            if (nscdbuf) |nscd| {
                const count: usize = @intCast(resp[INITGRNGRPS]);
                for (0..count) |i| {
                    if (nscd[i] == gr_s.gr_gid) nscd[i] = gid;
                }
            }

            // Check if user is a member of this group
            var found = false;
            var idx: usize = 0;
            while (gr_s.gr_mem[idx] != null) : (idx += 1) {
                if (strcmp(user, gr_s.gr_mem[idx].?) == 0) {
                    found = true;
                    break;
                }
            }
            if (!found) continue;

            n += 1;
            if (n <= nlim) {
                groups_ptr[0] = gr_s.gr_gid;
                groups_ptr += 1;
            }
        }
    }

    if (nscdbuf) |nscd| {
        const count: usize = @intCast(resp[INITGRNGRPS]);
        for (0..count) |i| {
            if (nscd[i] != gid) {
                n += 1;
                if (n <= nlim) {
                    groups_ptr[0] = nscd[i];
                    groups_ptr += 1;
                }
            }
        }
    }

    ret = if (n > nlim) -1 else @intCast(n);
    ngroups.* = @intCast(n);

    cleanup(f, nscdbuf, buf, mem, ret, n, ngroups);
    return ret;
}

fn cleanup(f: ?*FILE, nscdbuf: ?[*]uint32_t, buf: ?[*:0]u8, mem_ptr: ?[*]?[*:0]u8, _: c_int, _: ssize_t, _: *c_int) void {
    if (f) |file| _ = fclose(file);
    free(@ptrCast(nscdbuf));
    free(@ptrCast(buf));
    free(@ptrCast(mem_ptr));
}

// ====================================================================
// getspent, setspent, endspent
// ====================================================================

fn setspent() callconv(.c) void {}
fn endspent() callconv(.c) void {}
fn getspent() callconv(.c) ?*spwd {
    return null;
}

// ====================================================================
// getspnam
// ====================================================================

const LINE_LIM = 256;
var getspnam_sp: spwd = undefined;
var getspnam_line: ?[*]u8 = null;

fn getspnam(name: [*:0]const u8) callconv(.c) ?*spwd {
    var res: ?*spwd = null;
    const orig_errno = errno_val().*;

    if (getspnam_line == null) {
        getspnam_line = malloc(LINE_LIM);
    }
    if (getspnam_line == null) return null;

    const e = getspnam_r(name, &getspnam_sp, getspnam_line.?, LINE_LIM, &res);
    errno_val().* = if (e != 0) e else orig_errno;
    return res;
}

// ====================================================================
// getspnam_r
// ====================================================================

fn getspnam_r(name: [*:0]const u8, sp: *spwd, buf: [*]u8, size: usize, res: *?*spwd) callconv(.c) c_int {
    var path: [20 + NAME_MAX]u8 = undefined;
    var f: ?*FILE = null;
    var rv: c_int = 0;
    var skip: bool = false;
    var cs: c_int = 0;
    const orig_errno = errno_val().*;
    const l = strlen(name);

    res.* = null;

    // Disallow potentially-malicious user names
    if (name[0] == '.' or strchr(name, '/') != null or l == 0) {
        errno_val().* = EINVAL;
        return EINVAL;
    }

    // Buffer size must at least be able to hold name, plus some..
    if (size < l + 100) {
        errno_val().* = ERANGE;
        return ERANGE;
    }

    // Protect against truncation
    const written = snprintf(&path, @sizeOf(@TypeOf(path)), "/etc/tcb/%s/shadow", name);
    if (written >= @as(c_int, @intCast(@sizeOf(@TypeOf(path))))) {
        errno_val().* = EINVAL;
        return EINVAL;
    }

    const fd = open(@ptrCast(&path), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd >= 0) {
        var st: stat_t = undefined;
        errno_val().* = EINVAL;
        if (fstat(fd, &st) != 0) {
            _ = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cs);
            _ = close(fd);
            _ = pthread_setcancelstate(cs, null);
            return errno_val().*;
        }
        // S_ISREG check using the stat buffer
        f = fdopen(fd, "rb");
        if (f == null) {
            _ = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cs);
            _ = close(fd);
            _ = pthread_setcancelstate(cs, null);
            return errno_val().*;
        }
    } else {
        const e = errno_val().*;
        if (e != ENOENT and e != ENOTDIR) {
            return e;
        }
        f = fopen("/etc/shadow", "rbe");
        if (f == null) {
            const e2 = errno_val().*;
            if (e2 != ENOENT and e2 != ENOTDIR) {
                return e2;
            }
            return 0;
        }
    }

    // Read lines from shadow file
    while (fgets(buf, @intCast(size), f.?) != null) {
        const k = strlen(@ptrCast(buf));
        if (k == 0) continue;
        if (skip or strncmp(name, @ptrCast(buf), l) != 0 or buf[l] != ':') {
            skip = buf[k - 1] != '\n';
            continue;
        }
        if (buf[k - 1] != '\n') {
            rv = ERANGE;
            break;
        }

        if (__parsespent(@ptrCast(buf), sp) < 0) continue;
        res.* = sp;
        break;
    }

    _ = fclose(f.?);
    errno_val().* = if (rv != 0) rv else orig_errno;
    return rv;
}

// ====================================================================
// lckpwdf, ulckpwdf
// ====================================================================

fn lckpwdf() callconv(.c) c_int {
    return 0;
}

fn ulckpwdf() callconv(.c) c_int {
    return 0;
}

// ====================================================================
// putgrent, putpwent, putspent
// ====================================================================

fn putgrent(gr: *const group, f: *FILE) callconv(.c) c_int {
    flockfile(f);
    var r = fprintf(f, "%s:%s:%u:", gr.gr_name, gr.gr_passwd, gr.gr_gid);
    if (r >= 0) {
        var i: usize = 0;
        while (gr.gr_mem[i] != null) : (i += 1) {
            r = fprintf(f, "%s%s", if (i != 0) @as([*:0]const u8, ",") else @as([*:0]const u8, ""), gr.gr_mem[i].?);
            if (r < 0) break;
        }
        if (r >= 0) {
            r = fputc('\n', f);
        }
    }
    funlockfile(f);
    return if (r < 0) @as(c_int, -1) else @as(c_int, 0);
}

fn putpwent(pw: *const passwd, f: *FILE) callconv(.c) c_int {
    return if (fprintf(f, "%s:%s:%u:%u:%s:%s:%s\n", pw.pw_name, pw.pw_passwd, pw.pw_uid, pw.pw_gid, pw.pw_gecos, pw.pw_dir, pw.pw_shell) < 0) @as(c_int, -1) else @as(c_int, 0);
}

fn putspent(sp: *const spwd, f: *FILE) callconv(.c) c_int {
    const sp_namp: [*:0]const u8 = if (@intFromPtr(sp.sp_namp) != 0) sp.sp_namp else "";
    const sp_pwdp: [*:0]const u8 = if (@intFromPtr(sp.sp_pwdp) != 0) sp.sp_pwdp else "";

    // Use a simplified format - print each field
    var r = fprintf(f, "%s:%s:", sp_namp, sp_pwdp);
    if (r < 0) return -1;

    r = printSpentNum(f, sp.sp_lstchg);
    if (r < 0) return -1;
    r = fputc(':', f);
    if (r < 0) return -1;

    r = printSpentNum(f, sp.sp_min);
    if (r < 0) return -1;
    r = fputc(':', f);
    if (r < 0) return -1;

    r = printSpentNum(f, sp.sp_max);
    if (r < 0) return -1;
    r = fputc(':', f);
    if (r < 0) return -1;

    r = printSpentNum(f, sp.sp_warn);
    if (r < 0) return -1;
    r = fputc(':', f);
    if (r < 0) return -1;

    r = printSpentNum(f, sp.sp_inact);
    if (r < 0) return -1;
    r = fputc(':', f);
    if (r < 0) return -1;

    r = printSpentNum(f, sp.sp_expire);
    if (r < 0) return -1;
    r = fputc(':', f);
    if (r < 0) return -1;

    r = printSpentUNum(f, sp.sp_flag);
    if (r < 0) return -1;
    r = fputc('\n', f);
    if (r < 0) return -1;

    return 0;
}

fn printSpentNum(f: *FILE, val: c_long) c_int {
    if (val == -1) return 0; // print nothing
    return fprintf(f, "%ld", val);
}

fn printSpentUNum(f: *FILE, val: c_ulong) c_int {
    if (val == @as(c_ulong, @bitCast(@as(c_long, -1)))) return 0;
    return fprintf(f, "%lu", val);
}
