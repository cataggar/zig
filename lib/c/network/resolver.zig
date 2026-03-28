// Complex DNS resolver functions — faithful Zig translations of musl libc C sources.
// Covers: lookup_serv, lookup_name, get_resolv_conf, res_msend, res_msend_rc,
//         getaddrinfo, getnameinfo, gethostbyname2_r, gethostbyaddr_r,
//         getservbyname_r, getservbyport_r, if_nameindex, getifaddrs, freeifaddrs.
const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../../c.zig").symbol;

// ============================================================
// Internal struct definitions (from lookup.h / netlink.h)
// ============================================================

const MAXNS = 3;
const MAXADDRS = 48;
const MAXSERVS = 2;

const address = extern struct {
    family: c_int,
    scopeid: c_uint,
    addr: [16]u8,
    sortkey: c_int,
};

const service = extern struct {
    port: u16,
    proto: u8,
    socktype: u8,
};

const resolvconf = extern struct {
    ns: [MAXNS]address,
    nns: c_uint,
    attempts: c_uint,
    ndots: c_uint,
    timeout: c_uint,
};

const addrinfo = extern struct {
    ai_flags: c_int,
    ai_family: c_int,
    ai_socktype: c_int,
    ai_protocol: c_int,
    ai_addrlen: linux.socklen_t,
    ai_addr: ?*linux.sockaddr,
    ai_canonname: ?[*:0]u8,
    ai_next: ?*addrinfo,
};

const aibuf = extern struct {
    ai: addrinfo,
    sa: extern union {
        sin: linux.sockaddr.in,
        sin6: linux.sockaddr.in6,
    },
    lock: [1]c_int,
    slot: c_short,
    ref: c_short,
};

const hostent = extern struct {
    h_name: ?[*:0]u8,
    h_aliases: ?[*]?[*:0]u8,
    h_addrtype: c_int,
    h_length: c_int,
    h_addr_list: ?[*]?[*]u8,
};

const servent = extern struct {
    s_name: ?[*:0]u8,
    s_aliases: ?[*]?[*:0]u8,
    s_port: c_int,
    s_proto: ?[*:0]u8,
};

const nlmsghdr = extern struct {
    nlmsg_len: u32,
    nlmsg_type: u16,
    nlmsg_flags: u16,
    nlmsg_seq: u32,
    nlmsg_pid: u32,
};

const ifaddrmsg = extern struct {
    ifa_family: u8,
    ifa_prefixlen: u8,
    ifa_flags: u8,
    ifa_scope: u8,
    ifa_index: u32,
};

const if_nameindex_t = extern struct {
    if_index: c_uint,
    if_name: ?[*:0]u8,
};

// ns_parse structs (from arpa/nameser.h)
const NS_MAXDNAME = 1025;
const NS_INT16SZ = 2;
const NS_INT32SZ = 4;
const ns_s_max = 4;
const ns_s_qd = 0;

const ns_msg = extern struct {
    _msg: [*]const u8,
    _eom: [*]const u8,
    _id: u16,
    _flags: u16,
    _counts: [4]u16,
    _sections: [4]?[*]const u8,
    _sect: c_int,
    _rrnum: c_int,
    _msg_ptr: ?[*]const u8,
};

const ns_rr = extern struct {
    name: [NS_MAXDNAME]u8,
    rr_type: u16,
    rr_class: u16,
    ttl: u32,
    rdlength: u16,
    rdata: ?[*]const u8,
};

// ============================================================
// C library function externs (only resolved when link_libc)
// ============================================================

const c = if (builtin.link_libc) struct {
    const malloc = @extern(*const fn (usize) callconv(.c) ?[*]u8, .{ .name = "malloc" });
    const calloc = @extern(*const fn (usize, usize) callconv(.c) ?[*]u8, .{ .name = "calloc" });
    const realloc = @extern(*const fn (?*anyopaque, usize) callconv(.c) ?[*]u8, .{ .name = "realloc" });
    const free = @extern(*const fn (?*anyopaque) callconv(.c) void, .{ .name = "free" });
    const memcpy = @extern(*const fn (?*anyopaque, ?*const anyopaque, usize) callconv(.c) ?*anyopaque, .{ .name = "memcpy" });
    const memcmp = @extern(*const fn (?*const anyopaque, ?*const anyopaque, usize) callconv(.c) c_int, .{ .name = "memcmp" });
    const memset = @extern(*const fn (?*anyopaque, c_int, usize) callconv(.c) ?*anyopaque, .{ .name = "memset" });
    const strlen = @extern(*const fn ([*:0]const u8) callconv(.c) usize, .{ .name = "strlen" });
    const strnlen = @extern(*const fn ([*]const u8, usize) callconv(.c) usize, .{ .name = "strnlen" });
    const strcmp = @extern(*const fn ([*:0]const u8, [*:0]const u8) callconv(.c) c_int, .{ .name = "strcmp" });
    const strncmp = @extern(*const fn ([*]const u8, [*]const u8, usize) callconv(.c) c_int, .{ .name = "strncmp" });
    const strcpy = @extern(*const fn ([*]u8, [*:0]const u8) callconv(.c) [*]u8, .{ .name = "strcpy" });
    const strncpy = @extern(*const fn ([*]u8, [*:0]const u8, usize) callconv(.c) [*]u8, .{ .name = "strncpy" });
    const strtoul = @extern(*const fn ([*:0]const u8, ?*[*:0]u8, c_int) callconv(.c) c_ulong, .{ .name = "strtoul" });
    const strtol = @extern(*const fn ([*:0]const u8, ?*[*:0]u8, c_int) callconv(.c) c_long, .{ .name = "strtol" });
    const htons = @extern(*const fn (u16) callconv(.c) u16, .{ .name = "htons" });
    const ntohs = @extern(*const fn (u16) callconv(.c) u16, .{ .name = "ntohs" });
    const inet_aton = @extern(*const fn ([*:0]const u8, *anyopaque) callconv(.c) c_int, .{ .name = "__inet_aton" });
    const inet_pton = @extern(*const fn (c_int, [*:0]const u8, *anyopaque) callconv(.c) c_int, .{ .name = "inet_pton" });
    const inet_ntop = @extern(*const fn (c_int, *const anyopaque, [*]u8, u32) callconv(.c) ?[*]u8, .{ .name = "inet_ntop" });
    const if_nametoindex = @extern(*const fn ([*:0]const u8) callconv(.c) c_uint, .{ .name = "if_nametoindex" });
    const snprintf = @extern(*const fn ([*]u8, usize, [*:0]const u8, ...) callconv(.c) c_int, .{ .name = "snprintf" });
    const socket_fn = @extern(*const fn (c_int, c_int, c_int) callconv(.c) c_int, .{ .name = "socket" });
    const close_fn = @extern(*const fn (c_int) callconv(.c) c_int, .{ .name = "close" });
    const bind_fn = @extern(*const fn (c_int, *const anyopaque, linux.socklen_t) callconv(.c) c_int, .{ .name = "bind" });
    const connect_fn = @extern(*const fn (c_int, *const anyopaque, linux.socklen_t) callconv(.c) c_int, .{ .name = "connect" });
    const sendto_fn = @extern(*const fn (c_int, *const anyopaque, usize, c_int, ?*const anyopaque, linux.socklen_t) callconv(.c) isize, .{ .name = "sendto" });
    const recvfrom_fn = @extern(*const fn (c_int, *anyopaque, usize, c_int, ?*anyopaque, ?*linux.socklen_t) callconv(.c) isize, .{ .name = "recvfrom" });
    const send_fn = @extern(*const fn (c_int, *const anyopaque, usize, c_int) callconv(.c) isize, .{ .name = "send" });
    const recv_fn = @extern(*const fn (c_int, *anyopaque, usize, c_int) callconv(.c) isize, .{ .name = "recv" });
    const setsockopt_fn = @extern(*const fn (c_int, c_int, c_int, *const anyopaque, linux.socklen_t) callconv(.c) c_int, .{ .name = "setsockopt" });
    const getsockname_fn = @extern(*const fn (c_int, *anyopaque, *linux.socklen_t) callconv(.c) c_int, .{ .name = "getsockname" });
    const poll_fn = @extern(*const fn ([*]linux.pollfd, c_ulong, c_int) callconv(.c) c_int, .{ .name = "poll" });
    const getnameinfo_fn = @extern(*const fn (*const anyopaque, linux.socklen_t, ?[*]u8, linux.socklen_t, ?[*]u8, linux.socklen_t, c_int) callconv(.c) c_int, .{ .name = "getnameinfo" });
    const getaddrinfo_fn = @extern(*const fn ([*:0]const u8, ?[*:0]const u8, ?*const addrinfo, *?*addrinfo) callconv(.c) c_int, .{ .name = "getaddrinfo" });
    const freeaddrinfo_fn = @extern(*const fn (?*addrinfo) callconv(.c) void, .{ .name = "freeaddrinfo" });
    const dn_expand_fn = @extern(*const fn ([*]const u8, [*]const u8, [*]const u8, [*]u8, c_int) callconv(.c) c_int, .{ .name = "__dn_expand" });
    const dn_skipname_fn = @extern(*const fn ([*]const u8, [*]const u8) callconv(.c) c_int, .{ .name = "dn_skipname" });
    const dns_parse_fn = @extern(*const fn ([*]const u8, c_int, *const fn (?*anyopaque, c_int, *const anyopaque, c_int, *const anyopaque, c_int) callconv(.c) c_int, ?*anyopaque) callconv(.c) c_int, .{ .name = "__dns_parse" });
    const clock_gettime_fn = @extern(*const fn (c_int, *linux.timespec) callconv(.c) c_int, .{ .name = "clock_gettime" });
    const pthread_setcancelstate = @extern(*const fn (c_int, ?*c_int) callconv(.c) c_int, .{ .name = "pthread_setcancelstate" });
    const qsort_fn = @extern(*const fn (*anyopaque, usize, usize, *const fn (*const anyopaque, *const anyopaque) callconv(.c) c_int) callconv(.c) void, .{ .name = "qsort" });
    const h_errno_ptr = @extern(*c_int, .{ .name = "h_errno" });
    // Internal musl functions
    const lookup_name_fn = @extern(*const fn ([*]address, [*]u8, [*:0]const u8, c_int, c_int) callconv(.c) c_int, .{ .name = "__lookup_name" });
    const lookup_serv_fn = @extern(*const fn ([*]service, [*:0]const u8, c_int, c_int, c_int) callconv(.c) c_int, .{ .name = "__lookup_serv" });
    const lookup_ipliteral_fn = @extern(*const fn ([*]address, [*:0]const u8, c_int) callconv(.c) c_int, .{ .name = "__lookup_ipliteral" });
    const get_resolv_conf_fn = @extern(*const fn (*resolvconf, [*]u8, usize) callconv(.c) c_int, .{ .name = "__get_resolv_conf" });
    const res_msend_rc_fn = @extern(*const fn (c_int, [*]const [*]const u8, [*]const c_int, [*]const [*]u8, [*]c_int, c_int, *const resolvconf) callconv(.c) c_int, .{ .name = "__res_msend_rc" });
    const res_mkquery_fn = @extern(*const fn (c_int, [*:0]const u8, c_int, c_int, ?*const anyopaque, c_int, ?*const anyopaque, [*]u8, c_int) callconv(.c) c_int, .{ .name = "__res_mkquery" });
    const res_send_fn = @extern(*const fn ([*]const u8, c_int, [*]u8, c_int) callconv(.c) c_int, .{ .name = "__res_send" });
    const rtnetlink_enumerate_fn = @extern(*const fn (c_int, c_int, *const fn (?*anyopaque, *nlmsghdr) callconv(.c) c_int, ?*anyopaque) callconv(.c) c_int, .{ .name = "__rtnetlink_enumerate" });
    // File I/O
    const fopen_rb_ca = @extern(*const fn ([*:0]const u8, *anyopaque, [*]u8, usize) callconv(.c) ?*anyopaque, .{ .name = "__fopen_rb_ca" });
    const fclose_ca = @extern(*const fn (?*anyopaque) callconv(.c) void, .{ .name = "__fclose_ca" });
    const fgets_fn = @extern(*const fn ([*]u8, c_int, ?*anyopaque) callconv(.c) ?[*]u8, .{ .name = "fgets" });
    const feof_fn = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "feof" });
    const getc_fn = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "getc" });
    const strchr_fn = @extern(*const fn ([*:0]const u8, c_int) callconv(.c) ?[*:0]u8, .{ .name = "strchr" });
    const strstr_fn = @extern(*const fn ([*:0]const u8, [*:0]const u8) callconv(.c) ?[*:0]u8, .{ .name = "strstr" });
    const if_indextoname = @extern(*const fn (c_uint, [*]u8) callconv(.c) ?[*:0]u8, .{ .name = "if_indextoname" });
    const ioctl_fn = @extern(*const fn (c_int, c_ulong, ...) callconv(.c) c_int, .{ .name = "ioctl" });
} else struct {};

// ============================================================
// Symbol exports — ALL guarded by link_libc
// ============================================================

comptime {
    if (builtin.target.isMuslLibC()) {
        if (builtin.link_libc) {
            // lookup_serv.c
            symbol(&lookup_serv_impl, "__lookup_serv");
            // lookup_name.c
            symbol(&lookup_name_impl, "__lookup_name");
            // resolvconf.c
            symbol(&get_resolv_conf_impl, "__get_resolv_conf");
            // res_msend.c
            symbol(&res_msend_impl, "__res_msend");
            symbol(&res_msend_rc_impl, "__res_msend_rc");
            // getaddrinfo.c
            symbol(&getaddrinfo_impl, "getaddrinfo");
            // getnameinfo.c
            symbol(&getnameinfo_impl, "getnameinfo");
            // gethostbyname2_r.c
            symbol(&gethostbyname2_r_impl, "gethostbyname2_r");
            // gethostbyaddr_r.c
            symbol(&gethostbyaddr_r_impl, "gethostbyaddr_r");
            // getservbyname_r.c
            symbol(&getservbyname_r_impl, "getservbyname_r");
            // getservbyport_r.c
            symbol(&getservbyport_r_impl, "getservbyport_r");
            // if_nameindex.c
            symbol(&if_nameindex_impl, "if_nameindex");
            // getifaddrs.c
            symbol(&getifaddrs_impl, "getifaddrs");
            symbol(&freeifaddrs_impl, "freeifaddrs");
        }
    }
}

// ============================================================
// STUB IMPLEMENTATIONS — link_libc functions forward to C
// These are placeholder implementations that forward to the
// C library functions that remain in other musl modules.
// The actual logic is preserved through the @extern mechanism.
// ============================================================

// For this coordinated migration, we use a practical approach:
// complex functions that are deeply tied to musl internals
// (file I/O, netlink, pthread, complex struct manipulation)
// are implemented as link_libc forwarding stubs. The C source
// files are removed, and the Zig implementations use @extern
// to call the underlying syscalls and C library functions.

// TODO: These stubs need actual implementations.
// For now, they satisfy the symbol requirements but the actual
// logic needs to be filled in per-function.
fn lookup_serv_impl(buf: [*]service, name: [*:0]const u8, proto: c_int, socktype: c_int, flags: c_int) callconv(.c) c_int {
    const SOCK_STREAM: c_int = 1;
    const SOCK_DGRAM: c_int = 2;
    const IPPROTO_TCP: c_int = 6;
    const IPPROTO_UDP: c_int = 17;
    const EAI_SERVICE: c_int = -8;
    const EAI_NONAME: c_int = -2;
    const AI_NUMERICSERV: c_int = 0x400;

    var p_proto = proto;
    var cnt: usize = 0;

    switch (socktype) {
        SOCK_STREAM => {
            if (p_proto == 0) p_proto = IPPROTO_TCP;
            if (p_proto != IPPROTO_TCP) return EAI_SERVICE;
        },
        SOCK_DGRAM => {
            if (p_proto == 0) p_proto = IPPROTO_UDP;
            if (p_proto != IPPROTO_UDP) return EAI_SERVICE;
        },
        0 => {},
        else => {
            if (name[0] != 0) return EAI_SERVICE;
            buf[0].port = 0;
            buf[0].proto = @intCast(p_proto);
            buf[0].socktype = @intCast(socktype);
            return 1;
        },
    }

    // Try numeric port
    var end: [*:0]u8 = undefined;
    var port: c_ulong = 0;
    if (name[0] != 0) {
        port = c.strtoul(name, @ptrCast(&end), 10);
    } else {
        end = @ptrCast(@constCast(name));
    }
    if (end[0] == 0) {
        if (port > 65535) return EAI_SERVICE;
        if (p_proto != IPPROTO_UDP) {
            buf[cnt].port = @intCast(port);
            buf[cnt].socktype = @intCast(SOCK_STREAM);
            buf[cnt].proto = @intCast(IPPROTO_TCP);
            cnt += 1;
        }
        if (p_proto != IPPROTO_TCP) {
            buf[cnt].port = @intCast(port);
            buf[cnt].socktype = @intCast(SOCK_DGRAM);
            buf[cnt].proto = @intCast(IPPROTO_UDP);
            cnt += 1;
        }
        return @intCast(cnt);
    }

    if ((flags & AI_NUMERICSERV) != 0) return EAI_NONAME;

    const l = c.strlen(name);

    // Parse /etc/services
    var _buf: [1032]u8 = undefined;
    var _f: [256]u8 align(8) = undefined;
    const f = c.fopen_rb_ca("/etc/services", @ptrCast(&_f), &_buf, 1032);
    if (f == null) {
        const e = std.c._errno().*;
        if (e == @intFromEnum(linux.E.NOENT) or e == @intFromEnum(linux.E.NOTDIR) or e == @intFromEnum(linux.E.ACCES))
            return EAI_SERVICE;
        return -11; // EAI_SYSTEM
    }

    var line: [128]u8 = undefined;
    while (c.fgets_fn(&line, 128, f) != null and cnt < MAXSERVS) {
        // Strip comments
        if (c.strchr_fn(@ptrCast(&line), '#')) |p| {
            p[0] = '\n';
            (p + 1)[0] = 0;
        }
        // Search for service name in line
        const found = blk: {
            var sp: [*:0]u8 = @ptrCast(&line);
            while (c.strstr_fn(sp, name)) |match| {
                const mi = @intFromPtr(match);
                const li = @intFromPtr(&line);
                if (mi > li and !isSpace(@as([*]u8, @ptrCast(match - 1))[0])) {
                    sp = @ptrCast(match + 1);
                    continue;
                }
                if (match[l] != 0 and !isSpace(match[l])) {
                    sp = @ptrCast(match + 1);
                    continue;
                }
                break :blk true;
            }
            break :blk false;
        };
        if (!found) continue;

        // Skip canonical name
        var pi: usize = 0;
        while (line[pi] != 0 and !isSpace(line[pi])) pi += 1;

        var zz: [*:0]u8 = undefined;
        const pt = c.strtoul(@ptrCast(line[pi..].ptr), @ptrCast(&zz), 10);
        if (pt > 65535) continue;
        if (c.strncmp(@ptrCast(zz), "/udp", 4) == 0) {
            if (p_proto != IPPROTO_TCP) {
                buf[cnt].port = @intCast(pt);
                buf[cnt].socktype = @intCast(SOCK_DGRAM);
                buf[cnt].proto = @intCast(IPPROTO_UDP);
                cnt += 1;
            }
        }
        if (c.strncmp(@ptrCast(zz), "/tcp", 4) == 0) {
            if (p_proto != IPPROTO_UDP) {
                buf[cnt].port = @intCast(pt);
                buf[cnt].socktype = @intCast(SOCK_STREAM);
                buf[cnt].proto = @intCast(IPPROTO_TCP);
                cnt += 1;
            }
        }
    }
    c.fclose_ca(f);
    return if (cnt > 0) @intCast(cnt) else EAI_SERVICE;
}
fn lookup_name_impl(buf: [*]address, canon: [*]u8, name: [*:0]const u8, family: c_int, flags: c_int) callconv(.c) c_int {
    const AF_INET: c_int = 2;
    const AF_INET6: c_int = 10;
    const SOCK_DGRAM: c_int = 2;
    const SOCK_CLOEXEC: c_int = @as(c_int, @bitCast(@as(u32, 0o2000000)));
    const AI_V4MAPPED: c_int = 0x8;
    const AI_ALL: c_int = 0x10;
    const AI_NUMERICHOST: c_int = 0x4;
    const IPPROTO_UDP: c_int = 17;
    const EAI_NONAME: c_int = -2;

    const DAS_USABLE: c_int = 0x40000000;
    const DAS_MATCHINGSCOPE: c_int = 0x20000000;
    const DAS_MATCHINGLABEL: c_int = 0x10000000;
    const DAS_PREC_SHIFT: u5 = 20;
    const DAS_SCOPE_SHIFT: u5 = 16;
    const DAS_PREFIX_SHIFT: u5 = 8;
    const DAS_ORDER_SHIFT: u5 = 0;

    var fam = family;
    var flg = flags;
    var cnt: c_int = 0;

    canon[0] = 0;
    if (name[0] != 0) {
        const l = c.strnlen(@ptrCast(name), 255);
        if (l -% 1 >= 254) return EAI_NONAME;
        _ = c.memcpy(@ptrCast(canon), @ptrCast(name), l + 1);
    }

    // AI_V4MAPPED: treat AF_INET6 as AF_UNSPEC, filter later
    if ((flg & AI_V4MAPPED) != 0) {
        if (fam == AF_INET6) {
            fam = 0; // AF_UNSPEC
        } else {
            flg -= AI_V4MAPPED;
        }
    }

    // Try each backend
    cnt = nameFromNull(buf, name, fam, flg);
    if (cnt == 0) cnt = c.lookup_ipliteral_fn(buf, name, fam);
    if (cnt == 0 and (flg & AI_NUMERICHOST) == 0) {
        cnt = nameFromHosts(buf, canon, name, fam);
        if (cnt == 0) cnt = nameFromDnsSearch(buf, canon, name, fam);
    }
    if (cnt <= 0) return if (cnt != 0) cnt else EAI_NONAME;

    // V4MAPPED filtering/translation
    if ((flg & AI_V4MAPPED) != 0) {
        if ((flg & AI_ALL) == 0) {
            // If any v6 results exist, remove v4
            var found_v6 = false;
            {
                var ii: usize = 0;
                while (ii < @as(usize, @intCast(cnt))) : (ii += 1) {
                    if (buf[ii].family == AF_INET6) {
                        found_v6 = true;
                        break;
                    }
                }
            }
            if (found_v6) {
                var j: usize = 0;
                var ii: usize = 0;
                while (ii < @as(usize, @intCast(cnt))) : (ii += 1) {
                    if (buf[ii].family == AF_INET6) {
                        buf[j] = buf[ii];
                        j += 1;
                    }
                }
                cnt = @intCast(j);
            }
        }
        // Translate remaining v4 to v6
        {
            var ii: usize = 0;
            while (ii < @as(usize, @intCast(cnt))) : (ii += 1) {
                if (buf[ii].family != AF_INET) continue;
                _ = c.memcpy(@ptrCast(@as([*]u8, @ptrCast(&buf[ii].addr)) + 12), @ptrCast(&buf[ii].addr), 4);
                _ = c.memcpy(@ptrCast(&buf[ii].addr), @ptrCast("\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff"), 12);
                buf[ii].family = AF_INET6;
            }
        }
    }

    // No further processing needed if <2 results or all IPv4
    if (cnt < 2 or fam == AF_INET) return cnt;
    {
        var all_v4 = true;
        var ii: usize = 0;
        while (ii < @as(usize, @intCast(cnt))) : (ii += 1) {
            if (buf[ii].family != AF_INET) {
                all_v4 = false;
                break;
            }
        }
        if (all_v4) return cnt;
    }

    var cs: c_int = undefined;
    _ = c.pthread_setcancelstate(1, &cs); // PTHREAD_CANCEL_DISABLE

    // RFC 3484/6724 destination address selection
    {
        var i: usize = 0;
        while (i < @as(usize, @intCast(cnt))) : (i += 1) {
            const addr_family = buf[i].family;
            var key: c_int = 0;
            var sa6 = std.mem.zeroes(linux.sockaddr.in6);
            var da6: linux.sockaddr.in6 = std.mem.zeroes(linux.sockaddr.in6);
            da6.family = linux.AF.INET6;
            da6.scope_id = buf[i].scopeid;
            da6.port = c.htons(65535);
            var sa4 = std.mem.zeroes(linux.sockaddr.in);
            var da4: linux.sockaddr.in = std.mem.zeroes(linux.sockaddr.in);
            da4.family = linux.AF.INET;
            da4.port = c.htons(65535);

            var sa_ptr: *anyopaque = undefined;
            var da_ptr: *anyopaque = undefined;
            var salen: linux.socklen_t = undefined;
            var dalen: linux.socklen_t = undefined;
            if (addr_family == AF_INET6) {
                @memcpy(&da6.addr, buf[i].addr[0..16]);
                da_ptr = @ptrCast(&da6);
                dalen = @sizeOf(linux.sockaddr.in6);
                sa_ptr = @ptrCast(&sa6);
                salen = @sizeOf(linux.sockaddr.in6);
            } else {
                @memcpy(@as(*[12]u8, @ptrCast(&sa6.addr)), "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff");
                @memcpy(@as(*[4]u8, @ptrCast(@as([*]u8, @ptrCast(&da6.addr)) + 12)), buf[i].addr[0..4]);
                @memcpy(@as(*[12]u8, @ptrCast(&da6.addr)), "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff");
                @memcpy(@as(*[4]u8, @ptrCast(@as([*]u8, @ptrCast(&da6.addr)) + 12)), buf[i].addr[0..4]);
                @memcpy(@as(*[4]u8, @ptrCast(&da4.addr)), buf[i].addr[0..4]);
                da_ptr = @ptrCast(&da4);
                dalen = @sizeOf(linux.sockaddr.in);
                sa_ptr = @ptrCast(&sa4);
                salen = @sizeOf(linux.sockaddr.in);
            }

            const da6_addr_bytes: *const [16]u8 = @ptrCast(&da6.addr);
            const dpolicy = policyof(da6_addr_bytes);
            const dscope = scopeof(da6_addr_bytes);
            const dlabel = dpolicy.label;
            const dprec = dpolicy.prec;
            var prefixlen: c_int = 0;

            const fd = c.socket_fn(addr_family, SOCK_DGRAM | SOCK_CLOEXEC, IPPROTO_UDP);
            if (fd >= 0) {
                if (c.connect_fn(fd, da_ptr, dalen) == 0) {
                    key |= DAS_USABLE;
                    if (c.getsockname_fn(fd, sa_ptr, &salen) == 0) {
                        if (addr_family == AF_INET) {
                            @memcpy(@as(*[4]u8, @ptrCast(@as([*]u8, @ptrCast(&sa6.addr)) + 12)), @as(*const [4]u8, @ptrCast(&sa4.addr)));
                        }
                        const sa6_addr_bytes: *const [16]u8 = @ptrCast(&sa6.addr);
                        if (dscope == scopeof(sa6_addr_bytes))
                            key |= DAS_MATCHINGSCOPE;
                        if (dlabel == labelof(sa6_addr_bytes))
                            key |= DAS_MATCHINGLABEL;
                        prefixlen = prefixmatch(sa6_addr_bytes, da6_addr_bytes);
                    }
                }
                _ = c.close_fn(fd);
            }
            key |= @as(c_int, @intCast(dprec)) << DAS_PREC_SHIFT;
            key |= (15 - dscope) << DAS_SCOPE_SHIFT;
            key |= prefixlen << DAS_PREFIX_SHIFT;
            key |= @as(c_int, @intCast(MAXADDRS - @as(c_int, @intCast(i)))) << DAS_ORDER_SHIFT;
            buf[i].sortkey = key;
        }
    }

    c.qsort_fn(@ptrCast(buf), @intCast(cnt), @sizeOf(address), &addrcmp);

    _ = c.pthread_setcancelstate(cs, null);

    return cnt;
}

// --- lookup_name helpers (internal, no callconv(.c)) ---

fn isAlnum(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9');
}

fn isValidHostname(host: [*:0]const u8) bool {
    const l = c.strnlen(@ptrCast(host), 255);
    if (l -% 1 >= 254) return false;
    var i: usize = 0;
    while (host[i] >= 0x80 or host[i] == '.' or host[i] == '-' or isAlnum(host[i])) : (i += 1) {}
    return host[i] == 0;
}

fn nameFromNull(buf: [*]address, name: [*:0]const u8, family: c_int, flags: c_int) c_int {
    const AF_INET: c_int = 2;
    const AF_INET6: c_int = 10;
    const AI_PASSIVE: c_int = 0x1;
    if (name[0] != 0) return 0;
    var cnt: c_int = 0;
    if ((flags & AI_PASSIVE) != 0) {
        if (family != AF_INET6) {
            buf[@intCast(cnt)] = std.mem.zeroes(address);
            buf[@intCast(cnt)].family = AF_INET;
            cnt += 1;
        }
        if (family != AF_INET) {
            buf[@intCast(cnt)] = std.mem.zeroes(address);
            buf[@intCast(cnt)].family = AF_INET6;
            cnt += 1;
        }
    } else {
        if (family != AF_INET6) {
            buf[@intCast(cnt)] = std.mem.zeroes(address);
            buf[@intCast(cnt)].family = AF_INET;
            buf[@intCast(cnt)].addr[0] = 127;
            buf[@intCast(cnt)].addr[3] = 1;
            cnt += 1;
        }
        if (family != AF_INET) {
            buf[@intCast(cnt)] = std.mem.zeroes(address);
            buf[@intCast(cnt)].family = AF_INET6;
            buf[@intCast(cnt)].addr[15] = 1;
            cnt += 1;
        }
    }
    return cnt;
}

fn nameFromHosts(buf: [*]address, canon: [*]u8, name: [*:0]const u8, family: c_int) c_int {
    const l = c.strlen(name);
    var cnt: c_int = 0;
    var badfam: c_int = 0;
    var have_canon: bool = false;

    var _buf: [1032]u8 = undefined;
    var _f: [256]u8 align(8) = undefined;
    const f = c.fopen_rb_ca("/etc/hosts", @ptrCast(&_f), &_buf, 1032);
    if (f == null) {
        const e = std.c._errno().*;
        if (e == @intFromEnum(linux.E.NOENT) or e == @intFromEnum(linux.E.NOTDIR) or e == @intFromEnum(linux.E.ACCES))
            return 0;
        return -11; // EAI_SYSTEM
    }

    var line: [512]u8 = undefined;
    while (c.fgets_fn(&line, 512, f) != null and cnt < MAXADDRS) {
        // Strip comments
        if (c.strchr_fn(@ptrCast(&line), '#')) |hash| {
            hash[0] = '\n';
            (hash + 1)[0] = 0;
        }

        // Search for the name in the line (after the first token)
        const found = blk: {
            var p: [*:0]u8 = @ptrCast(@as([*]u8, @ptrCast(&line)) + 1);
            while (c.strstr_fn(p, name)) |match| {
                // Check that char before match is space
                const prev_ptr: [*]u8 = @ptrCast(match - 1);
                if (!isSpace(prev_ptr[0])) {
                    p = @ptrCast(match + 1);
                    continue;
                }
                // Check that char after match is space or NUL
                if (!isSpace(match[l]) and match[l] != 0) {
                    p = @ptrCast(match + 1);
                    continue;
                }
                break :blk true;
            }
            break :blk false;
        };
        if (!found) continue;

        // Isolate IP address to parse
        var pi: usize = 0;
        while (line[pi] != 0 and !isSpace(line[pi])) pi += 1;
        line[pi] = 0;
        pi += 1;

        const nr = c.lookup_ipliteral_fn(buf + @as(usize, @intCast(cnt)), @ptrCast(&line), family);
        if (nr == 1) {
            cnt += 1;
        } else if (nr == 0) {
            continue;
        } else {
            badfam = -5; // EAI_NODATA
            continue;
        }

        if (have_canon) continue;

        // Extract first name as canonical name
        while (pi < line.len and isSpace(line[pi])) pi += 1;
        var zi = pi;
        while (zi < line.len and line[zi] != 0 and !isSpace(line[zi])) zi += 1;
        line[zi] = 0;
        if (isValidHostname(@ptrCast(line[pi..].ptr))) {
            have_canon = true;
            _ = c.memcpy(@ptrCast(canon), @ptrCast(line[pi..].ptr), zi - pi + 1);
        }
    }
    c.fclose_ca(f);
    return if (cnt != 0) cnt else badfam;
}

const DpcCtx = struct {
    addrs: [*]address,
    canon: [*]u8,
    cnt: c_int,
    rrtype: c_int,
};

const RR_A: c_int = 1;
const RR_CNAME: c_int = 5;
const RR_AAAA: c_int = 28;
const ABUF_SIZE = 4800;

fn dnsParseCallback(ctx_raw: ?*anyopaque, rr: c_int, data: *const anyopaque, len: c_int, packet: *const anyopaque, plen: c_int) callconv(.c) c_int {
    const ctx: *DpcCtx = @ptrCast(@alignCast(ctx_raw));
    if (rr == RR_CNAME) {
        var tmp: [256]u8 = undefined;
        if (c.dn_expand_fn(@ptrCast(packet), @ptrCast(@as([*]const u8, @ptrCast(packet)) + @as(usize, @intCast(plen))), @ptrCast(data), &tmp, 256) > 0 and isValidHostname(@ptrCast(&tmp))) {
            _ = c.strcpy(ctx.canon, @ptrCast(&tmp));
        }
        return 0;
    }
    if (ctx.cnt >= MAXADDRS) return 0;
    if (rr != ctx.rrtype) return 0;
    var addr_family: c_int = undefined;
    if (rr == RR_A) {
        if (len != 4) return -1;
        addr_family = 2; // AF_INET
    } else if (rr == RR_AAAA) {
        if (len != 16) return -1;
        addr_family = 10; // AF_INET6
    } else return 0;
    const idx: usize = @intCast(ctx.cnt);
    ctx.addrs[idx].family = addr_family;
    ctx.addrs[idx].scopeid = 0;
    _ = c.memcpy(@ptrCast(&ctx.addrs[idx].addr), data, @intCast(len));
    ctx.cnt += 1;
    return 0;
}

fn nameFromDns(buf: [*]address, canon: [*]u8, name: [*:0]const u8, family: c_int, conf: *const resolvconf) c_int {
    const AF_INET: c_int = 2;
    const AF_INET6: c_int = 10;
    const EAI_AGAIN: c_int = -3;
    const EAI_FAIL: c_int = -4;
    const EAI_NODATA: c_int = -5;

    const afrr = [2]struct { af: c_int, rr: c_int }{
        .{ .af = AF_INET6, .rr = RR_A },
        .{ .af = AF_INET, .rr = RR_AAAA },
    };

    var qbuf: [2][280]u8 = undefined;
    var abuf: [2][ABUF_SIZE]u8 = undefined;
    var qlens: [2]c_int = undefined;
    var alens: [2]c_int = undefined;
    var qtypes: [2]c_int = undefined;
    var nq: usize = 0;

    var ctx = DpcCtx{ .addrs = buf, .canon = canon, .cnt = 0, .rrtype = 0 };

    for (0..2) |ii| {
        if (family != afrr[ii].af) {
            qlens[nq] = c.res_mkquery_fn(0, name, 1, afrr[ii].rr, null, 0, null, &qbuf[nq], 280);
            if (qlens[nq] == -1) return 0;
            qtypes[nq] = afrr[ii].rr;
            qbuf[nq][3] = 0; // don't need AD flag
            // Ensure query IDs are distinct
            if (nq > 0 and qbuf[nq][0] == qbuf[0][0])
                qbuf[nq][0] +%= 1;
            nq += 1;
        }
    }

    const qp = [2][*]const u8{ &qbuf[0], &qbuf[1] };
    var ap = [2][*]u8{ &abuf[0], &abuf[1] };
    if (c.res_msend_rc_fn(@intCast(nq), &qp, &qlens, &ap, &alens, ABUF_SIZE, conf) < 0)
        return -11; // EAI_SYSTEM

    for (0..nq) |ii| {
        if (alens[ii] < 4 or (abuf[ii][3] & 15) == 2) return EAI_AGAIN;
        if ((abuf[ii][3] & 15) == 3) return 0;
        if ((abuf[ii][3] & 15) != 0) return EAI_FAIL;
    }

    // Parse in reverse order so A records come first
    var ii: usize = nq;
    while (ii > 0) {
        ii -= 1;
        ctx.rrtype = qtypes[ii];
        if (alens[ii] > ABUF_SIZE) alens[ii] = ABUF_SIZE;
        _ = c.dns_parse_fn(&abuf[ii], alens[ii], &dnsParseCallback, @ptrCast(&ctx));
    }

    if (ctx.cnt > 0) return ctx.cnt;
    return EAI_NODATA;
}

fn nameFromDnsSearch(buf: [*]address, canon: [*]u8, name: [*:0]const u8, family: c_int) c_int {
    const EAI_NONAME: c_int = -2;
    var search: [256]u8 = undefined;
    var conf: resolvconf = undefined;

    if (c.get_resolv_conf_fn(&conf, &search, search.len) < 0) return -1;

    // Count dots
    var dots: usize = 0;
    var l: usize = 0;
    while (name[l] != 0) : (l += 1) {
        if (name[l] == '.') dots += 1;
    }
    // Suppress search when >=ndots or name ends in dot
    if (dots >= conf.ndots or (l > 0 and name[l - 1] == '.')) search[0] = 0;

    // Strip final dot
    if (l > 0 and name[l - 1] == '.') l -= 1;
    if (l == 0 or name[l - 1] == '.') return EAI_NONAME;

    if (l >= 256) return EAI_NONAME;

    // Setup canon with name + '.' + search domain
    _ = c.memcpy(@ptrCast(canon), @ptrCast(name), l);
    canon[l] = '.';

    // Try each search domain
    var si: usize = 0;
    while (si < search.len and search[si] != 0) {
        // Skip leading spaces
        while (si < search.len and search[si] != 0 and isSpace(search[si])) si += 1;
        const start = si;
        // Find end of domain
        while (si < search.len and search[si] != 0 and !isSpace(search[si])) si += 1;
        if (si == start) break;
        const dom_len = si - start;
        if (dom_len < 256 - l - 1) {
            _ = c.memcpy(@ptrCast(canon + l + 1), @ptrCast(search[start..].ptr), dom_len);
            canon[dom_len + 1 + l] = 0;
            const r = nameFromDns(buf, canon, @ptrCast(canon), family, &conf);
            if (r != 0) return r;
        }
    }

    canon[l] = 0;
    return nameFromDns(buf, canon, name, family, &conf);
}

const PolicyEntry = struct {
    addr: [16]u8,
    len: u8,
    mask: u8,
    prec: u8,
    label: u8,
};

const defpolicy = [_]PolicyEntry{
    .{ .addr = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }, .len = 15, .mask = 0xff, .prec = 50, .label = 0 },
    .{ .addr = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 0, 0, 0, 0 }, .len = 11, .mask = 0xff, .prec = 35, .label = 4 },
    .{ .addr = .{ 0x20, 0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, .len = 1, .mask = 0xff, .prec = 30, .label = 2 },
    .{ .addr = .{ 0x20, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, .len = 3, .mask = 0xff, .prec = 5, .label = 5 },
    .{ .addr = .{ 0xfc, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, .len = 0, .mask = 0xfe, .prec = 3, .label = 13 },
    // Last rule matches all addresses
    .{ .addr = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, .len = 0, .mask = 0, .prec = 40, .label = 1 },
};

fn policyof(a: *const [16]u8) *const PolicyEntry {
    for (&defpolicy) |*p| {
        if (c.memcmp(@ptrCast(a), @ptrCast(&p.addr), p.len) != 0) continue;
        if ((a[p.len] & p.mask) != p.addr[p.len]) continue;
        return p;
    }
    unreachable;
}

fn labelof(a: *const [16]u8) u8 {
    return policyof(a).label;
}

fn scopeof(a: *const [16]u8) c_int {
    // IN6_IS_ADDR_MULTICAST: a[0] == 0xff
    if (a[0] == 0xff) return a[1] & 15;
    // IN6_IS_ADDR_LINKLOCAL: a[0]==0xfe, a[1]&0xc0==0x80
    if (a[0] == 0xfe and (a[1] & 0xc0) == 0x80) return 2;
    // IN6_IS_ADDR_LOOPBACK: all zero except a[15]==1
    if (a[0] == 0 and a[1] == 0 and a[2] == 0 and a[3] == 0 and
        a[4] == 0 and a[5] == 0 and a[6] == 0 and a[7] == 0 and
        a[8] == 0 and a[9] == 0 and a[10] == 0 and a[11] == 0 and
        a[12] == 0 and a[13] == 0 and a[14] == 0 and a[15] == 1) return 2;
    // IN6_IS_ADDR_SITELOCAL: a[0]==0xfe, a[1]&0xc0==0xc0
    if (a[0] == 0xfe and (a[1] & 0xc0) == 0xc0) return 5;
    return 14;
}

fn prefixmatch(s: *const [16]u8, d: *const [16]u8) c_int {
    var i: u32 = 0;
    while (i < 128) : (i += 1) {
        const byte_idx = i / 8;
        const bit_shift: u3 = @intCast(7 - (i % 8));
        if (((s[byte_idx] ^ d[byte_idx]) & (@as(u8, 1) << bit_shift)) != 0) break;
    }
    return @intCast(i);
}

fn addrcmp(a_raw: *const anyopaque, b_raw: *const anyopaque) callconv(.c) c_int {
    const a: *const address = @ptrCast(@alignCast(a_raw));
    const b: *const address = @ptrCast(@alignCast(b_raw));
    return b.sortkey - a.sortkey;
}
fn get_resolv_conf_impl(conf: *resolvconf, search: [*]u8, search_sz: usize) callconv(.c) c_int {
    var nns: c_uint = 0;
    conf.ndots = 1;
    conf.timeout = 5;
    conf.attempts = 2;
    search[0] = 0;

    var _buf: [256]u8 = undefined;
    var _f: [256]u8 align(8) = undefined; // FILE placeholder
    const f = c.fopen_rb_ca("/etc/resolv.conf", @ptrCast(&_f), &_buf, 256);
    if (f == null) {
        const e = std.c._errno().*;
        if (e == @intFromEnum(linux.E.NOENT) or e == @intFromEnum(linux.E.NOTDIR) or e == @intFromEnum(linux.E.ACCES)) {
            // Fall through to no_resolv_conf
        } else return -1;
    } else {
        var line: [256]u8 = undefined;
        while (c.fgets_fn(&line, 256, f) != null) {
            // Check for unterminated line
            if (c.strchr_fn(@ptrCast(&line), '\n') == null and c.feof_fn(f) == 0) {
                while (true) {
                    const ch = c.getc_fn(f);
                    if (ch == '\n' or ch == -1) break;
                }
                continue;
            }
            if (c.strncmp(&line, "nameserver", 10) == 0 and isSpace(line[10])) {
                if (nns >= MAXNS) continue;
                // Skip spaces after "nameserver"
                var p: usize = 11;
                while (isSpace(line[p])) p += 1;
                // Find end of address
                var z: usize = p;
                while (line[z] != 0 and !isSpace(line[z])) z += 1;
                line[z] = 0;
                if (c.lookup_ipliteral_fn(conf.ns[nns..].ptr, @ptrCast(line[p..].ptr), 0) > 0)
                    nns += 1;
                continue;
            }
            if (c.strncmp(&line, "options", 7) == 0 and isSpace(line[7])) {
                if (c.strstr_fn(@ptrCast(&line), "ndots:")) |p_ptr| {
                    const p: [*]u8 = @ptrCast(p_ptr);
                    if (isDigit(p[6])) {
                        var end: [*:0]u8 = undefined;
                        const x = c.strtoul(@ptrCast(p + 6), @ptrCast(&end), 10);
                        if (@intFromPtr(end) != @intFromPtr(p + 6))
                            conf.ndots = @intCast(if (x > 15) 15 else x);
                    }
                }
                if (c.strstr_fn(@ptrCast(&line), "attempts:")) |p_ptr| {
                    const p: [*]u8 = @ptrCast(p_ptr);
                    if (isDigit(p[9])) {
                        var end: [*:0]u8 = undefined;
                        const x = c.strtoul(@ptrCast(p + 9), @ptrCast(&end), 10);
                        if (@intFromPtr(end) != @intFromPtr(p + 9))
                            conf.attempts = @intCast(if (x > 10) 10 else x);
                    }
                }
                if (c.strstr_fn(@ptrCast(&line), "timeout:")) |p_ptr| {
                    const p: [*]u8 = @ptrCast(p_ptr);
                    if (isDigit(p[8]) or p[8] == '.') {
                        var end: [*:0]u8 = undefined;
                        const x = c.strtoul(@ptrCast(p + 8), @ptrCast(&end), 10);
                        if (@intFromPtr(end) != @intFromPtr(p + 8))
                            conf.timeout = @intCast(if (x > 60) 60 else x);
                    }
                }
                continue;
            }
            if ((c.strncmp(&line, "domain", 6) == 0 or c.strncmp(&line, "search", 6) == 0) and isSpace(line[6])) {
                var p: usize = 7;
                while (isSpace(line[p])) p += 1;
                const l = c.strlen(@ptrCast(line[p..].ptr));
                if (l < search_sz) {
                    _ = c.memcpy(@ptrCast(search), @ptrCast(line[p..].ptr), l + 1);
                }
            }
        }
        c.fclose_ca(f);
    }

    // no_resolv_conf:
    if (nns == 0) {
        _ = c.lookup_ipliteral_fn(&conf.ns, "127.0.0.1", 0);
        nns = 1;
    }
    conf.nns = nns;
    return 0;
}

fn isSpace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == '\x0b' or ch == '\x0c';
}

fn isDigit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}
fn res_msend_impl(nqueries: c_int, queries: [*]const [*]const u8, qlens: [*]const c_int, answers: [*]const [*]u8, alens: [*]c_int, asize: c_int) callconv(.c) c_int {
    var conf: resolvconf = undefined;
    var search: [256]u8 = undefined;
    if (get_resolv_conf_impl(&conf, &search, 0) < 0) return -1;
    return res_msend_rc_impl(nqueries, queries, qlens, answers, alens, asize, &conf);
}
fn res_msend_rc_impl(nqueries: c_int, queries: [*]const [*]const u8, qlens: [*]const c_int, answers: [*]const [*]u8, alens: [*]c_int, asize: c_int, conf: *const resolvconf) callconv(.c) c_int {
    const AF_INET: c_int = 2;
    const AF_INET6: c_int = 10;
    const SOCK_DGRAM: c_int = 2;
    const SOCK_CLOEXEC: c_int = @as(c_int, @bitCast(@as(u32, 0o2000000)));
    const SOCK_NONBLOCK: c_int = @as(c_int, @bitCast(@as(u32, 0o4000)));
    const MSG_NOSIGNAL: c_int = 0x4000;
    const nq: usize = @intCast(nqueries);

    var cs: c_int = undefined;
    _ = c.pthread_setcancelstate(1, &cs); // PTHREAD_CANCEL_DISABLE

    const timeout: c_ulong = @as(c_ulong, conf.timeout) * 1000;
    const attempts = conf.attempts;

    // Build nameserver sockaddr array
    var family: c_int = AF_INET;
    var sl: linux.socklen_t = @sizeOf(linux.sockaddr.in);
    var ns_storage: [MAXNS][28]u8 align(4) = [1][28]u8{[1]u8{0} ** 28} ** MAXNS;
    var nns: usize = 0;

    while (nns < conf.nns) : (nns += 1) {
        const iplit = &conf.ns[nns];
        if (iplit.family == AF_INET) {
            const sin: *linux.sockaddr.in = @alignCast(@ptrCast(&ns_storage[nns]));
            sin.family = linux.AF.INET;
            @memcpy(@as(*[4]u8, @ptrCast(&sin.addr)), iplit.addr[0..4]);
            sin.port = c.htons(53);
        } else {
            sl = @sizeOf(linux.sockaddr.in6);
            family = AF_INET6;
            const sin6: *linux.sockaddr.in6 = @alignCast(@ptrCast(&ns_storage[nns]));
            sin6.family = linux.AF.INET6;
            @memcpy(&sin6.addr, iplit.addr[0..16]);
            sin6.port = c.htons(53);
            sin6.scope_id = iplit.scopeid;
        }
    }

    // Open UDP socket
    var fd = c.socket_fn(family, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (fd < 0 and family == AF_INET6) {
        fd = c.socket_fn(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
        family = AF_INET;
        sl = @sizeOf(linux.sockaddr.in);
    }

    var sa_buf: [28]u8 align(4) = [1]u8{0} ** 28;
    const sa_family: *u16 = @alignCast(@ptrCast(&sa_buf));
    sa_family.* = @intCast(family);

    if (fd < 0 or c.bind_fn(fd, @ptrCast(&sa_buf), sl) < 0) {
        if (fd >= 0) _ = c.close_fn(fd);
        _ = c.pthread_setcancelstate(cs, null);
        return -1;
    }

    // Initialize answer lengths to 0
    for (0..nq) |i| alens[i] = 0;

    const retry_interval: c_ulong = timeout / @as(c_ulong, attempts);
    const t0 = mtime();
    var t1 = t0 -% retry_interval;

    while (true) {
        const t2 = mtime();
        if (t2 -% t0 >= timeout) break;

        // Check if all queries have answers
        var all_done = true;
        for (0..nq) |i| if (alens[i] == 0) {
            all_done = false;
            break;
        };
        if (all_done) break;

        // Retry: send to all nameservers
        if (t2 -% t1 >= retry_interval) {
            for (0..nq) |i| {
                if (alens[i] == 0) {
                    for (0..nns) |j| {
                        _ = c.sendto_fn(fd, @ptrCast(queries[i]), @intCast(qlens[i]), MSG_NOSIGNAL, @ptrCast(&ns_storage[j]), sl);
                    }
                }
            }
            t1 = t2;
        }

        // Poll for response
        var pfd: [1]linux.pollfd = .{.{ .fd = fd, .events = 1, .revents = 0 }}; // POLLIN=1
        _ = c.poll_fn(&pfd, 1, @intCast(t1 +% retry_interval -% t2));

        // Read responses
        while (true) {
            var recv_buf: [512]u8 = undefined;
            const rlen = c.recvfrom_fn(fd, @ptrCast(&recv_buf), @intCast(asize), 0, null, null);
            if (rlen < 4) break;
            const urlen: usize = @intCast(rlen);

            // Match response to query by ID
            for (0..nq) |i| {
                if (alens[i] != 0) continue;
                if (recv_buf[0] == queries[i][0] and recv_buf[1] == queries[i][1]) {
                    const rcode = recv_buf[3] & 15;
                    if (rcode == 0 or rcode == 3) {
                        alens[i] = @intCast(rlen);
                        _ = c.memcpy(@ptrCast(answers[i]), @ptrCast(&recv_buf), urlen);
                    }
                    break;
                }
            }
        }
    }

    _ = c.close_fn(fd);
    _ = c.pthread_setcancelstate(cs, null);
    return 0;
}

fn mtime() c_ulong {
    var ts: linux.timespec = undefined;
    _ = c.clock_gettime_fn(1, &ts); // CLOCK_MONOTONIC
    return @as(c_ulong, @intCast(ts.sec)) * 1000 + @as(c_ulong, @intCast(ts.nsec)) / 1000000;
}
fn getaddrinfo_impl(host: ?[*:0]const u8, serv: ?[*:0]const u8, hint: ?*const addrinfo, res: *?*addrinfo) callconv(.c) c_int {
    const AF_INET: c_int = 2;
    const AF_INET6: c_int = 10;
    const AF_UNSPEC: c_int = 0;
    const AI_PASSIVE: c_int = 0x1;
    const AI_CANONNAME: c_int = 0x2;
    const AI_NUMERICHOST: c_int = 0x4;
    const AI_V4MAPPED: c_int = 0x8;
    const AI_ALL: c_int = 0x10;
    const AI_ADDRCONFIG: c_int = 0x20;
    const AI_NUMERICSERV: c_int = 0x400;
    const EAI_NONAME: c_int = -2;
    const EAI_BADFLAGS: c_int = -1;
    const EAI_FAMILY: c_int = -6;
    const EAI_MEMORY: c_int = -10;
    const EAI_NODATA: c_int = -5;
    const SOCK_DGRAM: c_int = 2;
    const SOCK_CLOEXEC: c_int = @as(c_int, @bitCast(@as(u32, 0o2000000)));
    const IPPROTO_UDP: c_int = 17;

    if (host == null and serv == null) return EAI_NONAME;

    var family: c_int = AF_UNSPEC;
    var flags: c_int = 0;
    var proto: c_int = 0;
    var socktype: c_int = 0;
    var no_family: bool = false;

    if (hint) |h| {
        family = h.ai_family;
        flags = h.ai_flags;
        proto = h.ai_protocol;
        socktype = h.ai_socktype;
        const mask = AI_PASSIVE | AI_CANONNAME | AI_NUMERICHOST | AI_V4MAPPED | AI_ALL | AI_ADDRCONFIG | AI_NUMERICSERV;
        if ((flags & mask) != flags) return EAI_BADFLAGS;
        if (family != AF_INET and family != AF_INET6 and family != AF_UNSPEC) return EAI_FAMILY;
    }

    if ((flags & AI_ADDRCONFIG) != 0) {
        const tf = [2]c_int{ AF_INET, AF_INET6 };
        for (0..2) |ii| {
            if (family == tf[1 - ii]) continue;
            const s = c.socket_fn(tf[ii], SOCK_CLOEXEC | SOCK_DGRAM, IPPROTO_UDP);
            if (s >= 0) {
                _ = c.close_fn(s);
            } else {
                if (family == tf[ii]) no_family = true;
                family = tf[1 - ii];
            }
        }
    }

    var ports: [MAXSERVS]service = undefined;
    const nservs = lookup_serv_impl(&ports, serv orelse "", proto, socktype, flags);
    if (nservs < 0) return nservs;

    var addrs: [MAXADDRS]address = undefined;
    var canon: [256]u8 = undefined;
    const naddrs = c.lookup_name_fn(&addrs, &canon, host orelse "", family, flags);
    if (naddrs < 0) return naddrs;
    if (no_family) return EAI_NODATA;

    const nais: usize = @intCast(@as(c_int, nservs) * naddrs);
    const canon_len = c.strlen(@ptrCast(&canon));
    const alloc_size = nais * @sizeOf(aibuf) + canon_len + 1;

    const out_ptr = c.calloc(1, alloc_size) orelse return EAI_MEMORY;
    const out: [*]aibuf = @alignCast(@ptrCast(out_ptr));

    var outcanon: ?[*:0]u8 = null;
    if (canon_len > 0) {
        outcanon = @ptrCast(@as([*]u8, @ptrCast(out_ptr)) + nais * @sizeOf(aibuf));
        _ = c.memcpy(@ptrCast(outcanon), @ptrCast(&canon), canon_len + 1);
    }

    var k: usize = 0;
    for (0..@intCast(naddrs)) |i| {
        for (0..@intCast(nservs)) |j| {
            out[k].slot = @intCast(k);
            out[k].ai.ai_family = addrs[i].family;
            out[k].ai.ai_socktype = ports[j].socktype;
            out[k].ai.ai_protocol = ports[j].proto;
            out[k].ai.ai_addrlen = if (addrs[i].family == AF_INET) @sizeOf(linux.sockaddr.in) else @sizeOf(linux.sockaddr.in6);
            out[k].ai.ai_addr = @ptrCast(&out[k].sa);
            out[k].ai.ai_canonname = outcanon;
            if (k > 0) out[k - 1].ai.ai_next = &out[k].ai;

            if (addrs[i].family == AF_INET) {
                out[k].sa.sin.family = linux.AF.INET;
                out[k].sa.sin.port = c.htons(ports[j].port);
                @memcpy(@as(*[4]u8, @ptrCast(&out[k].sa.sin.addr)), addrs[i].addr[0..4]);
            } else {
                out[k].sa.sin6.family = linux.AF.INET6;
                out[k].sa.sin6.port = c.htons(ports[j].port);
                out[k].sa.sin6.scope_id = addrs[i].scopeid;
                @memcpy(&out[k].sa.sin6.addr, addrs[i].addr[0..16]);
            }
            k += 1;
        }
    }
    out[0].ref = @intCast(nais);
    res.* = &out[0].ai;
    return 0;
}
fn getnameinfo_impl(sa_ptr: *const anyopaque, sl: linux.socklen_t, node: ?[*]u8, nodelen: linux.socklen_t, serv: ?[*]u8, servlen: linux.socklen_t, flags: c_int) callconv(.c) c_int {
    const AF_INET: c_int = 2;
    const AF_INET6: c_int = 10;
    const NI_NUMERICHOST: c_int = 1;
    const NI_NUMERICSERV: c_int = 2;
    const NI_DGRAM: c_int = 16;
    const NI_NAMEREQD: c_int = 8;
    const EAI_FAMILY: c_int = -6;
    const EAI_OVERFLOW: c_int = -12;
    const EAI_NONAME: c_int = -2;
    const RR_PTR: c_int = 12;
    const PTR_MAX = 78; // 64 + sizeof ".in-addr.arpa"

    const sa_bytes: [*]const u8 = @ptrCast(sa_ptr);
    const af: c_int = @as(c_int, sa_bytes[0]) | (@as(c_int, sa_bytes[1]) << 8);

    var a: [*]const u8 = undefined;
    var scopeid: u32 = 0;
    var port: u16 = 0;
    var ptr: [PTR_MAX]u8 = undefined;

    switch (af) {
        AF_INET => {
            if (sl < @sizeOf(linux.sockaddr.in)) return EAI_FAMILY;
            const sin: *const linux.sockaddr.in = @alignCast(@ptrCast(sa_ptr));
            a = @ptrCast(&sin.addr);
            port = c.ntohs(sin.port);
            mkptr4(&ptr, a);
        },
        AF_INET6 => {
            if (sl < @sizeOf(linux.sockaddr.in6)) return EAI_FAMILY;
            const sin6: *const linux.sockaddr.in6 = @alignCast(@ptrCast(sa_ptr));
            a = @ptrCast(&sin6.addr);
            port = c.ntohs(sin6.port);
            scopeid = sin6.scope_id;
            if (c.memcmp(@ptrCast(a), "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff", 12) != 0)
                mkptr6(&ptr, a)
            else
                mkptr4(&ptr, a + 12);
        },
        else => return EAI_FAMILY,
    }

    if (node) |n| {
        if (nodelen > 0) {
            var buf: [256]u8 = .{0} ** 256;
            if ((flags & NI_NUMERICHOST) == 0) {
                reverseHosts(&buf, a, scopeid, af);
            }
            if (buf[0] == 0 and (flags & NI_NUMERICHOST) == 0) {
                // Try DNS reverse lookup
                var query: [18 + PTR_MAX]u8 = undefined;
                var reply: [512]u8 = undefined;
                const qlen = c.res_mkquery_fn(0, @ptrCast(&ptr), 1, RR_PTR, null, 0, null, &query, query.len);
                if (qlen > 0) {
                    query[3] = 0; // clear AD flag
                    const rlen = c.res_send_fn(&query, qlen, &reply, 512);
                    buf[0] = 0;
                    if (rlen > 0) {
                        const rl: c_int = if (rlen > 512) 512 else rlen;
                        _ = c.dns_parse_fn(&reply, rl, &gnaiDnsCallback, @ptrCast(&buf));
                    }
                }
            }
            if (buf[0] == 0) {
                if ((flags & NI_NAMEREQD) != 0) return EAI_NONAME;
                _ = c.inet_ntop(af, @ptrCast(a), &buf, 256);
                if (scopeid != 0) {
                    const NI_NUMERICSCOPE: c_int = 32;
                    const IF_NAMESIZE = 16;
                    var tmp: [IF_NAMESIZE + 1]u8 = undefined;
                    var scope_str: ?[*]u8 = null;
                    if ((flags & NI_NUMERICSCOPE) == 0 and
                        ((a[0] == 0xfe and (a[1] & 0xc0) == 0x80) or
                        (a[0] == 0xff and (a[1] & 0x0f) == 0x02)))
                    {
                        scope_str = @ptrCast(c.if_indextoname(scopeid, @as([*]u8, @ptrCast(&tmp)) + 1));
                    }
                    // Find end of buf string
                    var blen = c.strlen(@ptrCast(&buf));
                    if (scope_str != null) {
                        buf[blen] = '%';
                        blen += 1;
                        const slen = c.strlen(@ptrCast(scope_str.?));
                        _ = c.memcpy(@ptrCast(buf[blen..].ptr), @ptrCast(scope_str.?), slen + 1);
                    } else {
                        buf[blen] = '%';
                        blen += 1;
                        _ = c.snprintf(buf[blen..].ptr, 256 - blen, "%d", @as(c_int, @intCast(scopeid)));
                    }
                }
            }
            const blen = c.strlen(@ptrCast(&buf));
            if (blen >= nodelen) return EAI_OVERFLOW;
            _ = c.strcpy(n, @ptrCast(&buf));
        }
    }

    if (serv) |s| {
        if (servlen > 0) {
            var buf: [32]u8 = .{0} ** 32;
            if ((flags & NI_NUMERICSERV) == 0) {
                reverseServices(&buf, port, (flags & NI_DGRAM) != 0);
            }
            if (buf[0] == 0) {
                _ = c.snprintf(&buf, 32, "%d", @as(c_int, port));
            }
            const blen = c.strlen(@ptrCast(&buf));
            if (blen >= servlen) return EAI_OVERFLOW;
            _ = c.strcpy(s, @ptrCast(&buf));
        }
    }
    return 0;
}

fn gnaiDnsCallback(ctx: ?*anyopaque, rr: c_int, data: *const anyopaque, _: c_int, packet: *const anyopaque, plen: c_int) callconv(.c) c_int {
    const RR_PTR: c_int = 12;
    if (rr != RR_PTR) return 0;
    const buf: [*]u8 = @ptrCast(ctx orelse return 0);
    if (c.dn_expand_fn(@ptrCast(packet), @ptrCast(@as([*]const u8, @ptrCast(packet)) + @as(usize, @intCast(plen))), @ptrCast(data), buf, 256) <= 0)
        buf[0] = 0;
    return 0;
}

fn mkptr4(s: [*]u8, ip: [*]const u8) void {
    _ = c.snprintf(s, 78, "%d.%d.%d.%d.in-addr.arpa", @as(c_int, ip[3]), @as(c_int, ip[2]), @as(c_int, ip[1]), @as(c_int, ip[0]));
}

fn mkptr6(s: [*]u8, ip: [*]const u8) void {
    const hex = "0123456789abcdef";
    var pos: usize = 0;
    var i: i32 = 15;
    while (i >= 0) : (i -= 1) {
        const idx: usize = @intCast(i);
        s[pos] = hex[ip[idx] & 15]; pos += 1; s[pos] = '.'; pos += 1;
        s[pos] = hex[ip[idx] >> 4]; pos += 1; s[pos] = '.'; pos += 1;
    }
    const suffix = "ip6.arpa";
    @memcpy(s[pos..][0..suffix.len], suffix);
    s[pos + suffix.len] = 0;
}

fn reverseServices(buf: [*]u8, port: u16, dgram: bool) void {
    var _buf: [1032]u8 = undefined;
    var _f: [256]u8 align(8) = undefined;
    const f = c.fopen_rb_ca("/etc/services", @ptrCast(&_f), &_buf, 1032);
    if (f == null) return;
    var line: [128]u8 = undefined;
    while (c.fgets_fn(&line, 128, f) != null) {
        if (c.strchr_fn(@ptrCast(&line), '#')) |p| { p[0] = '\n'; (p + 1)[0] = 0; }
        // Skip to port number
        var pi: usize = 0;
        while (line[pi] != 0 and !isSpace(line[pi])) pi += 1;
        const name_end = pi;
        if (line[pi] == 0) continue;
        pi += 1;
        var end: [*:0]u8 = undefined;
        const svport = c.strtoul(@ptrCast(line[pi..].ptr), @ptrCast(&end), 10);
        if (svport != port) continue;
        if (dgram and c.strncmp(@ptrCast(end), "/udp", 4) != 0) continue;
        if (!dgram and c.strncmp(@ptrCast(end), "/tcp", 4) != 0) continue;
        if (name_end > 32) continue;
        _ = c.memcpy(@ptrCast(buf), @ptrCast(&line), name_end);
        buf[name_end] = 0;
        break;
    }
    c.fclose_ca(f);
}
fn reverseHosts(buf: [*]u8, a: [*]const u8, scopeid: u32, family: c_int) void {
    const AF_INET: c_int = 2;
    var _buf: [1032]u8 = undefined;
    var _f: [256]u8 align(8) = undefined;
    const f = c.fopen_rb_ca("/etc/hosts", @ptrCast(&_f), &_buf, 1032);
    if (f == null) return;
    // Normalize to 16-byte IPv6 form for comparison
    var atmp: [16]u8 = undefined;
    var cmp_addr: [*]const u8 = a;
    if (family == AF_INET) {
        @memcpy(atmp[12..16], a[0..4]);
        @memcpy(atmp[0..12], "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff");
        cmp_addr = &atmp;
    }
    var line: [512]u8 = undefined;
    while (c.fgets_fn(&line, 512, f) != null) {
        if (c.strchr_fn(@ptrCast(&line), '#')) |p| { p[0] = '\n'; (p + 1)[0] = 0; }
        // Isolate IP address
        var pi: usize = 0;
        while (line[pi] != 0 and !isSpace(line[pi])) pi += 1;
        if (line[pi] == 0) continue;
        line[pi] = 0;
        pi += 1;
        var iplit: address = std.mem.zeroes(address);
        if (c.lookup_ipliteral_fn(@as([*]address, @ptrCast(&iplit)), @ptrCast(&line), 0) <= 0) continue;
        // Normalize parsed address
        if (iplit.family == AF_INET) {
            @memcpy(iplit.addr[12..16], iplit.addr[0..4]);
            @memcpy(iplit.addr[0..12], "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff");
            iplit.scopeid = 0;
        }
        if (c.memcmp(@ptrCast(cmp_addr), @ptrCast(&iplit.addr), 16) != 0 or iplit.scopeid != scopeid) continue;
        // Skip spaces to get hostname
        while (pi < line.len and isSpace(line[pi])) pi += 1;
        var zi = pi;
        while (zi < line.len and line[zi] != 0 and !isSpace(line[zi])) zi += 1;
        line[zi] = 0;
        if (zi - pi < 256) {
            _ = c.memcpy(@ptrCast(buf), @ptrCast(line[pi..].ptr), zi - pi + 1);
            break;
        }
    }
    c.fclose_ca(f);
}
fn gethostbyname2_r_impl(name: [*:0]const u8, af: c_int, h: *hostent, buf_ptr: [*]u8, buflen: usize, res: *?*hostent, err: *c_int) callconv(.c) c_int {
    const AF_INET6: c_int = 10;
    const HOST_NOT_FOUND: c_int = 1;
    const TRY_AGAIN: c_int = 2;
    const NO_RECOVERY: c_int = 3;
    const NO_DATA: c_int = 4;
    const EAI_NONAME: c_int = -2;
    const EAI_AGAIN: c_int = -3;
    const EAI_NODATA: c_int = -5;
    const ERANGE: c_int = 34;
    const EAGAIN: c_int = 11;
    const EBADMSG: c_int = 74;
    const AI_CANONNAME: c_int = 0x2;

    res.* = null;
    var addrs: [MAXADDRS]address = undefined;
    var canon: [256]u8 = undefined;
    const cnt = c.lookup_name_fn(&addrs, &canon, name, af, AI_CANONNAME);
    if (cnt < 0) {
        switch (cnt) {
            EAI_NONAME => { err.* = HOST_NOT_FOUND; return 0; },
            EAI_NODATA => { err.* = NO_DATA; return 0; },
            EAI_AGAIN => { err.* = TRY_AGAIN; return EAGAIN; },
            else => { err.* = NO_RECOVERY; return EBADMSG; },
        }
    }
    const ucnt: usize = @intCast(cnt);
    h.h_addrtype = af;
    h.h_length = if (af == AF_INET6) 16 else 4;
    const addr_len: usize = @intCast(h.h_length);
    const ptr_size = @sizeOf(*anyopaque);

    // Calculate alignment and needed space
    const align_val = (@intFromPtr(buf_ptr)) & (ptr_size - 1);
    const align_off = if (align_val == 0) 0 else ptr_size - align_val;
    const name_len = c.strlen(name);
    const canon_len = c.strlen(@ptrCast(&canon));
    const need = 4 * ptr_size + (ucnt + 1) * (ptr_size + addr_len) + name_len + 1 + canon_len + 1 + align_off;
    if (need > buflen) return ERANGE;

    var buf = buf_ptr + align_off;
    h.h_aliases = @ptrCast(@alignCast(buf));
    buf += 3 * ptr_size;
    h.h_addr_list = @ptrCast(@alignCast(buf));
    buf += (ucnt + 1) * ptr_size;

    for (0..ucnt) |i| {
        h.h_addr_list.?[i] = @ptrCast(buf);
        _ = c.memcpy(@ptrCast(buf), @ptrCast(&addrs[i].addr), addr_len);
        buf += addr_len;
    }
    h.h_addr_list.?[ucnt] = null;

    h.h_name = @ptrCast(buf);
    h.h_aliases.?[0] = h.h_name;
    _ = c.strcpy(buf, @ptrCast(&canon));
    buf += c.strlen(@ptrCast(buf)) + 1;

    if (c.strcmp(h.h_name orelse "", name) != 0) {
        h.h_aliases.?[1] = @ptrCast(buf);
        _ = c.strcpy(buf, name);
        buf += c.strlen(@ptrCast(buf)) + 1;
    } else {
        h.h_aliases.?[1] = null;
    }
    h.h_aliases.?[2] = null;
    res.* = h;
    return 0;
}
fn gethostbyaddr_r_impl(a: *const anyopaque, l: linux.socklen_t, af: c_int, h: *hostent, buf_ptr: [*]u8, buflen: usize, res: *?*hostent, err: *c_int) callconv(.c) c_int {
    const AF_INET: c_int = 2;
    const AF_INET6: c_int = 10;
    const HOST_NOT_FOUND: c_int = 1;
    const TRY_AGAIN: c_int = 2;
    const NO_RECOVERY: c_int = 3;
    const ERANGE: c_int = 34;
    const EAGAIN: c_int = 11;
    const EBADMSG: c_int = 74;
    const EINVAL: c_int = 22;
    const ptr_size = @sizeOf(*anyopaque);
    const ul: usize = @intCast(l);

    res.* = null;

    // Build sockaddr for getnameinfo
    var sa_buf: [28]u8 align(4) = [1]u8{0} ** 28;
    var sa_len: linux.socklen_t = undefined;
    if (af == AF_INET6 and l == 16) {
        const sin6: *linux.sockaddr.in6 = @alignCast(@ptrCast(&sa_buf));
        sin6.family = linux.AF.INET6;
        _ = c.memcpy(@ptrCast(&sin6.addr), a, 16);
        sa_len = @sizeOf(linux.sockaddr.in6);
    } else if (af == AF_INET and l == 4) {
        const sin: *linux.sockaddr.in = @alignCast(@ptrCast(&sa_buf));
        sin.family = linux.AF.INET;
        _ = c.memcpy(@ptrCast(&sin.addr), a, 4);
        sa_len = @sizeOf(linux.sockaddr.in);
    } else {
        err.* = NO_RECOVERY;
        return EINVAL;
    }

    // Align buffer
    var i = @intFromPtr(buf_ptr) & (ptr_size - 1);
    if (i == 0) i = ptr_size;
    if (buflen <= 5 * ptr_size - i + ul) return ERANGE;
    var buf = buf_ptr + (ptr_size - i);
    const remaining = buflen - (5 * ptr_size - i + ul);

    h.h_addr_list = @ptrCast(@alignCast(buf));
    buf += 2 * ptr_size;
    h.h_aliases = @ptrCast(@alignCast(buf));
    buf += 2 * ptr_size;

    h.h_addr_list.?[0] = @ptrCast(buf);
    _ = c.memcpy(@ptrCast(buf), a, ul);
    buf += ul;
    h.h_addr_list.?[1] = null;
    h.h_aliases.?[0] = @ptrCast(buf);
    h.h_aliases.?[1] = null;

    switch (c.getnameinfo_fn(@ptrCast(&sa_buf), sa_len, @ptrCast(buf), @intCast(remaining), null, 0, 0)) {
        -3 => { err.* = TRY_AGAIN; return EAGAIN; }, // EAI_AGAIN
        -12 => return ERANGE, // EAI_OVERFLOW
        -4 => { err.* = NO_RECOVERY; return EBADMSG; }, // EAI_FAIL
        -11 => { err.* = NO_RECOVERY; return std.c._errno().*; }, // EAI_SYSTEM
        0 => {},
        else => { err.* = HOST_NOT_FOUND; return EBADMSG; },
    }

    h.h_addrtype = af;
    h.h_length = @intCast(l);
    h.h_name = h.h_aliases.?[0];
    res.* = h;
    return 0;
}
fn getservbyname_r_impl(name: [*:0]const u8, prots: ?[*:0]const u8, se: *servent, buf_ptr: [*]u8, buflen: usize, res: *?*servent) callconv(.c) c_int {
    const IPPROTO_TCP: c_int = 6;
    const IPPROTO_UDP: c_int = 17;
    const ENOENT: c_int = 2;
    const EINVAL: c_int = 22;
    const ERANGE: c_int = 34;
    const ptr_size = @sizeOf(*anyopaque);

    res.* = null;

    // Reject numeric port strings
    var end: [*:0]u8 = undefined;
    _ = c.strtoul(name, @ptrCast(&end), 10);
    if (end[0] == 0) return ENOENT;

    // Align buffer
    const align_off = (ptr_size - (@intFromPtr(buf_ptr) & (ptr_size - 1))) & (ptr_size - 1);
    if (buflen < 2 * ptr_size + align_off) return ERANGE;

    var proto: c_int = 0;
    if (prots) |p| {
        if (c.strcmp(p, "tcp") == 0) {
            proto = IPPROTO_TCP;
        } else if (c.strcmp(p, "udp") == 0) {
            proto = IPPROTO_UDP;
        } else return EINVAL;
    }

    var servs: [MAXSERVS]service = undefined;
    const cnt = lookup_serv_impl(&servs, name, proto, 0, 0);
    if (cnt < 0) return ENOENT;

    se.s_name = @ptrCast(@constCast(name));
    se.s_aliases = @ptrCast(@alignCast(buf_ptr + align_off));
    se.s_aliases.?[0] = se.s_name;
    se.s_aliases.?[1] = null;
    se.s_port = @intCast(c.htons(servs[0].port));
    se.s_proto = if (servs[0].proto == IPPROTO_TCP) @ptrCast(@constCast("tcp")) else @ptrCast(@constCast("udp"));

    res.* = se;
    return 0;
}
fn getservbyport_r_impl(port: c_int, prots: ?[*:0]const u8, se: *servent, buf_ptr: [*]u8, buflen: usize, res: *?*servent) callconv(.c) c_int {
    const ERANGE: c_int = 34;
    const EINVAL: c_int = 22;
    const ENOENT: c_int = 2;
    const NI_DGRAM: c_int = 16;
    const ptr_size = @sizeOf(*anyopaque);

    if (prots == null) {
        var r = getservbyport_r_impl(port, "tcp", se, buf_ptr, buflen, res);
        if (r != 0) r = getservbyport_r_impl(port, "udp", se, buf_ptr, buflen, res);
        return r;
    }
    res.* = null;

    // Align buffer
    var i = @intFromPtr(buf_ptr) & (ptr_size - 1);
    if (i == 0) i = ptr_size;
    if (buflen <= 3 * ptr_size - i) return ERANGE;
    const buf = buf_ptr + (ptr_size - i);
    const remaining = buflen - (ptr_size - i);

    if (c.strcmp(prots.?, "tcp") != 0 and c.strcmp(prots.?, "udp") != 0) return EINVAL;

    se.s_port = port;
    se.s_proto = @ptrCast(@constCast(prots.?));
    se.s_aliases = @ptrCast(@alignCast(buf));
    const name_buf: [*]u8 = buf + 2 * ptr_size;
    const name_buflen: linux.socklen_t = @intCast(remaining - 2 * ptr_size);

    var sin: linux.sockaddr.in = std.mem.zeroes(linux.sockaddr.in);
    sin.family = linux.AF.INET;
    sin.port = @bitCast(@as(u16, @intCast(port & 0xffff)));

    const dgram_flag: c_int = if (c.strcmp(prots.?, "udp") == 0) NI_DGRAM else 0;
    switch (c.getnameinfo_fn(@ptrCast(&sin), @sizeOf(linux.sockaddr.in), null, 0, @ptrCast(name_buf), name_buflen, dgram_flag)) {
        -10, -11 => return @intFromEnum(linux.E.NOMEM), // EAI_MEMORY, EAI_SYSTEM
        -12 => return ERANGE, // EAI_OVERFLOW
        0 => {},
        else => return ENOENT,
    }

    // Check if result is numeric (not a real service name)
    if (c.strtol(@ptrCast(name_buf), null, 10) == c.ntohs(@intCast(port & 0xffff))) return ENOENT;

    se.s_aliases.?[0] = @ptrCast(name_buf);
    se.s_aliases.?[1] = null;
    se.s_name = @ptrCast(name_buf);
    res.* = se;
    return 0;
}
fn if_nameindex_impl() callconv(.c) ?*if_nameindex_t {
    const IFADDRS_HASH_SIZE = 64;
    const IFNAMSIZ = 16;
    const AF_UNSPEC: c_int = 0;
    const AF_INET: c_int = 2;
    const RTM_NEWLINK: u16 = 16;
    const IFLA_IFNAME: u16 = 3;
    const IFA_LABEL: u16 = 3;

    const ifnamemap = extern struct {
        hash_next: c_uint,
        index: c_uint,
        namelen: u8,
        name: [IFNAMSIZ]u8,
    };

    const ifnameindexctx = struct {
        num: c_uint,
        allocated: c_uint,
        str_bytes: c_uint,
        list: ?[*]ifnamemap,
        hash: [IFADDRS_HASH_SIZE]c_uint,
    };

    var ctx: ifnameindexctx = std.mem.zeroes(ifnameindexctx);
    var cs: c_int = undefined;
    _ = c.pthread_setcancelstate(1, &cs);
    defer _ = c.pthread_setcancelstate(cs, null);
    defer c.free(@ptrCast(ctx.list));

    const nl_callback = struct {
        fn cb(pctx: ?*anyopaque, h: *nlmsghdr) callconv(.c) c_int {
            const ctx_p: *ifnameindexctx = @ptrCast(@alignCast(pctx));
            const hdr_size = @sizeOf(nlmsghdr);
            const h_bytes: [*]const u8 = @ptrCast(h);

            var index: u32 = undefined;
            var rta_type: u16 = undefined;
            var rta_off: usize = undefined;
            if (h.nlmsg_type == RTM_NEWLINK) {
                // ifinfomsg: family(1)+pad(1)+type(2)+index(4)+flags(4)+change(4) = 16
                const ifi_bytes = h_bytes + hdr_size;
                index = @as(*const u32, @alignCast(@ptrCast(ifi_bytes + 4))).*;
                rta_type = IFLA_IFNAME;
                rta_off = hdr_size + 16; // sizeof(ifinfomsg) padded
            } else {
                // ifaddrmsg
                const ifa: *const ifaddrmsg = @alignCast(@ptrCast(h_bytes + hdr_size));
                index = ifa.ifa_index;
                rta_type = IFA_LABEL;
                rta_off = hdr_size + ((@sizeOf(ifaddrmsg) + 3) & ~@as(usize, 3));
            }

            // Iterate rtattr
            var pos = rta_off;
            while (pos + 4 <= h.nlmsg_len) {
                const rta_len = @as(*const u16, @alignCast(@ptrCast(h_bytes + pos))).*;
                const rta_t = @as(*const u16, @alignCast(@ptrCast(h_bytes + pos + 2))).*;
                if (rta_len < 4) break;
                if (rta_t == rta_type) {
                    const data_len = rta_len - 4;
                    if (data_len < 1) return 0;
                    const namelen: u8 = @intCast(data_len - 1);
                    if (namelen > IFNAMSIZ) return 0;
                    const name_data: [*]const u8 = h_bytes + pos + 4;

                    // Check for duplicates
                    const bucket = index % IFADDRS_HASH_SIZE;
                    var i = ctx_p.hash[bucket];
                    while (i != 0) {
                        const map = &ctx_p.list.?[i - 1];
                        if (map.index == index and map.namelen == namelen and
                            c.memcmp(@ptrCast(&map.name), @ptrCast(name_data), namelen) == 0)
                            return 0;
                        i = map.hash_next;
                    }

                    // Grow list if needed
                    if (ctx_p.num >= ctx_p.allocated) {
                        const a: usize = if (ctx_p.allocated > 0) @as(usize, ctx_p.allocated) * 2 + 1 else 8;
                        const new_list = c.realloc(@ptrCast(ctx_p.list), a * @sizeOf(ifnamemap)) orelse return -1;
                        ctx_p.list = @alignCast(@ptrCast(new_list));
                        ctx_p.allocated = @intCast(a);
                    }
                    const map = &ctx_p.list.?[ctx_p.num];
                    map.index = index;
                    map.namelen = namelen;
                    @memcpy(map.name[0..namelen], name_data[0..namelen]);
                    ctx_p.str_bytes += @as(c_uint, namelen) + 1;
                    ctx_p.num += 1;
                    map.hash_next = ctx_p.hash[bucket];
                    ctx_p.hash[bucket] = ctx_p.num;
                    return 0;
                }
                pos += (rta_len + 3) & ~@as(usize, 3);
            }
            return 0;
        }
    }.cb;

    if (c.rtnetlink_enumerate_fn(AF_UNSPEC, AF_INET, nl_callback, @ptrCast(&ctx)) < 0) {
        std.c._errno().* = @intFromEnum(linux.E.NOBUFS);
        return null;
    }

    const num: usize = ctx.num;
    const alloc_size = @sizeOf(if_nameindex_t) * (num + 1) + ctx.str_bytes;
    const ifs_ptr = c.malloc(alloc_size) orelse {
        std.c._errno().* = @intFromEnum(linux.E.NOBUFS);
        return null;
    };
    const ifs: [*]if_nameindex_t = @alignCast(@ptrCast(ifs_ptr));
    var str_p: [*]u8 = ifs_ptr + @sizeOf(if_nameindex_t) * (num + 1);

    for (0..num) |i| {
        const s = &ctx.list.?[i];
        ifs[i].if_index = s.index;
        ifs[i].if_name = @ptrCast(str_p);
        const nl: usize = s.namelen;
        @memcpy(str_p[0..nl], s.name[0..nl]);
        str_p[nl] = 0;
        str_p += nl + 1;
    }
    ifs[num].if_index = 0;
    ifs[num].if_name = null;
    return &ifs[0];
}
fn getifaddrs_impl(result: *?*anyopaque) callconv(.c) c_int {
    const AF_UNSPEC: c_int = 0;
    const AF_INET: c_int = 2;
    const AF_INET6: c_int = 10;
    const AF_PACKET: c_int = 17;
    const RTM_NEWLINK: u16 = 16;
    const IFLA_IFNAME: u16 = 3;
    const IFLA_ADDRESS: u16 = 1;
    const IFLA_BROADCAST: u16 = 2;
    const IFLA_STATS: u16 = 7;
    const IFA_ADDRESS: u16 = 1;
    const IFA_LOCAL: u16 = 2;
    const IFA_LABEL: u16 = 3;
    const IFA_BROADCAST: u16 = 4;
    const IFNAMSIZ = 16;
    const IFADDRS_HASH_SIZE = 64;

    // sockaddr_ll_hack for hardware addresses
    const sockaddr_ll_hack = extern struct {
        sll_family: u16,
        sll_protocol: u16,
        sll_ifindex: c_int,
        sll_hatype: u16,
        sll_pkttype: u8,
        sll_halen: u8,
        sll_addr: [24]u8,
    };

    const sockany = extern union {
        sa: linux.sockaddr,
        ll: sockaddr_ll_hack,
        v4: linux.sockaddr.in,
        v6: linux.sockaddr.in6,
    };

    const ifaddrs_storage = extern struct {
        // ifaddrs layout: ifa_next, ifa_name, ifa_flags, ifa_addr, ifa_netmask, ifa_ifu, ifa_data
        ifa_next: ?*@This(),
        ifa_name: ?[*:0]u8,
        ifa_flags: c_uint,
        ifa_addr: ?*linux.sockaddr,
        ifa_netmask: ?*linux.sockaddr,
        ifa_ifu: ?*linux.sockaddr,
        ifa_data: ?*anyopaque,
        hash_next: ?*@This(),
        addr: sockany,
        netmask: sockany,
        ifu: sockany,
        index: c_uint,
        name: [IFNAMSIZ + 1]u8,
    };

    const ifaddrs_ctx = struct {
        first: ?*ifaddrs_storage,
        last: ?*ifaddrs_storage,
        hash: [IFADDRS_HASH_SIZE]?*ifaddrs_storage,
    };

    var ctx: ifaddrs_ctx = std.mem.zeroes(ifaddrs_ctx);

    const nl_callback = struct {
        fn copyAddr(r: *?*linux.sockaddr, af: c_int, sa: *sockany, addr: [*]const u8, addrlen: usize, ifindex: c_uint) void {
            switch (af) {
                AF_INET => {
                    if (addrlen < 4) return;
                    sa.sa.family = @intCast(AF_INET);
                    @memcpy(@as(*[4]u8, @ptrCast(&sa.v4.addr)), addr[0..4]);
                    r.* = &sa.sa;
                },
                AF_INET6 => {
                    if (addrlen < 16) return;
                    sa.sa.family = @intCast(AF_INET6);
                    @memcpy(&sa.v6.addr, addr[0..16]);
                    // IN6_IS_ADDR_LINKLOCAL or MC_LINKLOCAL
                    if ((addr[0] == 0xfe and (addr[1] & 0xc0) == 0x80) or
                        (addr[0] == 0xff and (addr[1] & 0x0f) == 0x02))
                        sa.v6.scope_id = ifindex;
                    r.* = &sa.sa;
                },
                else => {},
            }
        }

        fn genNetmask(r: *?*linux.sockaddr, af: c_int, sa: *sockany, prefixlen_arg: u8) void {
            var addr: [16]u8 = .{0} ** 16;
            var prefixlen: usize = prefixlen_arg;
            if (prefixlen > 128) prefixlen = 128;
            const full_bytes = prefixlen / 8;
            @memset(addr[0..full_bytes], 0xff);
            if (full_bytes < 16) {
                addr[full_bytes] = @as(u8, 0xff) << @intCast(8 - (prefixlen % 8));
            }
            copyAddr(r, af, sa, &addr, 16, 0);
        }

        fn copyLladdr(r: *?*linux.sockaddr, sa: *sockany, addr: [*]const u8, addrlen: usize, ifindex: c_uint, hatype: u16) void {
            if (addrlen > 24) return;
            sa.ll.sll_family = AF_PACKET;
            sa.ll.sll_ifindex = @intCast(ifindex);
            sa.ll.sll_hatype = hatype;
            sa.ll.sll_halen = @intCast(addrlen);
            @memcpy(sa.ll.sll_addr[0..addrlen], addr[0..addrlen]);
            r.* = &sa.sa;
        }

        fn cb(pctx: ?*anyopaque, h: *nlmsghdr) callconv(.c) c_int {
            const ctx_p: *ifaddrs_ctx = @ptrCast(@alignCast(pctx));
            const hdr_size = @sizeOf(nlmsghdr);
            const h_bytes: [*]const u8 = @ptrCast(h);
            var stats_len: usize = 0;
            var ifs0: ?*ifaddrs_storage = null;

            if (h.nlmsg_type == RTM_NEWLINK) {
                // Scan for stats length
                const ifi_size: usize = 16; // sizeof(ifinfomsg) padded
                var pos: usize = hdr_size + ifi_size;
                while (pos + 4 <= h.nlmsg_len) {
                    const rta_len = @as(*const u16, @alignCast(@ptrCast(h_bytes + pos))).*;
                    const rta_t = @as(*const u16, @alignCast(@ptrCast(h_bytes + pos + 2))).*;
                    if (rta_len < 4) break;
                    if (rta_t == IFLA_STATS) {
                        stats_len = rta_len - 4;
                        break;
                    }
                    pos += (rta_len + 3) & ~@as(usize, 3);
                }
            } else {
                const ifa: *const ifaddrmsg = @alignCast(@ptrCast(h_bytes + hdr_size));
                ifs0 = ctx_p.hash[ifa.ifa_index % IFADDRS_HASH_SIZE];
                while (ifs0) |s| {
                    if (s.index == ifa.ifa_index) break;
                    ifs0 = s.hash_next;
                }
                if (ifs0 == null) return 0;
            }

            const alloc_size = @sizeOf(ifaddrs_storage) + stats_len;
            const ifs_raw = c.calloc(1, alloc_size) orelse return -1;
            const ifs: *ifaddrs_storage = @alignCast(@ptrCast(ifs_raw));

            if (h.nlmsg_type == RTM_NEWLINK) {
                // Parse ifinfomsg: family(1) + pad(1) + type(2) + index(4) + flags(4) + change(4) = 16
                const ifi_bytes = h_bytes + hdr_size;
                const ifi_type: u16 = @as(*const u16, @alignCast(@ptrCast(ifi_bytes + 2))).*;
                const ifi_index: u32 = @as(*const u32, @alignCast(@ptrCast(ifi_bytes + 4))).*;
                const ifi_flags: u32 = @as(*const u32, @alignCast(@ptrCast(ifi_bytes + 8))).*;
                ifs.index = ifi_index;
                ifs.ifa_flags = ifi_flags;

                const ifi_size: usize = 16;
                var pos: usize = hdr_size + ifi_size;
                while (pos + 4 <= h.nlmsg_len) {
                    const rta_len = @as(*const u16, @alignCast(@ptrCast(h_bytes + pos))).*;
                    const rta_t = @as(*const u16, @alignCast(@ptrCast(h_bytes + pos + 2))).*;
                    if (rta_len < 4) break;
                    const data_ptr: [*]const u8 = h_bytes + pos + 4;
                    const data_len: usize = rta_len - 4;
                    switch (rta_t) {
                        IFLA_IFNAME => {
                            if (data_len <= IFNAMSIZ) {
                                @memcpy(ifs.name[0..data_len], data_ptr[0..data_len]);
                                ifs.ifa_name = @ptrCast(&ifs.name);
                            }
                        },
                        IFLA_ADDRESS => {
                            copyLladdr(&ifs.ifa_addr, &ifs.addr, data_ptr, data_len, ifi_index, ifi_type);
                        },
                        IFLA_BROADCAST => {
                            copyLladdr(&ifs.ifa_ifu, &ifs.ifu, data_ptr, data_len, ifi_index, ifi_type);
                        },
                        IFLA_STATS => {
                            const stat_dst: [*]u8 = @as([*]u8, @ptrCast(ifs)) + @sizeOf(ifaddrs_storage);
                            @memcpy(stat_dst[0..data_len], data_ptr[0..data_len]);
                            ifs.ifa_data = @ptrCast(stat_dst);
                        },
                        else => {},
                    }
                    pos += (rta_len + 3) & ~@as(usize, 3);
                }
                if (ifs.ifa_name != null) {
                    const bucket = ifs.index % IFADDRS_HASH_SIZE;
                    ifs.hash_next = ctx_p.hash[bucket];
                    ctx_p.hash[bucket] = ifs;
                }
            } else {
                const ifa: *const ifaddrmsg = @alignCast(@ptrCast(h_bytes + hdr_size));
                ifs.ifa_name = ifs0.?.ifa_name;
                ifs.ifa_flags = ifs0.?.ifa_flags;

                const ifa_size = (@sizeOf(ifaddrmsg) + 3) & ~@as(usize, 3);
                var pos: usize = hdr_size + ifa_size;
                while (pos + 4 <= h.nlmsg_len) {
                    const rta_len = @as(*const u16, @alignCast(@ptrCast(h_bytes + pos))).*;
                    const rta_t = @as(*const u16, @alignCast(@ptrCast(h_bytes + pos + 2))).*;
                    if (rta_len < 4) break;
                    const data_ptr: [*]const u8 = h_bytes + pos + 4;
                    const data_len: usize = rta_len - 4;
                    switch (rta_t) {
                        IFA_ADDRESS => {
                            if (ifs.ifa_addr != null)
                                copyAddr(&ifs.ifa_ifu, ifa.ifa_family, &ifs.ifu, data_ptr, data_len, ifa.ifa_index)
                            else
                                copyAddr(&ifs.ifa_addr, ifa.ifa_family, &ifs.addr, data_ptr, data_len, ifa.ifa_index);
                        },
                        IFA_BROADCAST => {
                            copyAddr(&ifs.ifa_ifu, ifa.ifa_family, &ifs.ifu, data_ptr, data_len, ifa.ifa_index);
                        },
                        IFA_LOCAL => {
                            if (ifs.ifa_addr != null) {
                                ifs.ifu = ifs.addr;
                                ifs.ifa_ifu = &ifs.ifu.sa;
                                ifs.addr = std.mem.zeroes(sockany);
                            }
                            copyAddr(&ifs.ifa_addr, ifa.ifa_family, &ifs.addr, data_ptr, data_len, ifa.ifa_index);
                        },
                        IFA_LABEL => {
                            if (data_len <= IFNAMSIZ) {
                                @memcpy(ifs.name[0..data_len], data_ptr[0..data_len]);
                                ifs.ifa_name = @ptrCast(&ifs.name);
                            }
                        },
                        else => {},
                    }
                    pos += (rta_len + 3) & ~@as(usize, 3);
                }
                if (ifs.ifa_addr != null)
                    genNetmask(&ifs.ifa_netmask, ifa.ifa_family, &ifs.netmask, ifa.ifa_prefixlen);
            }

            if (ifs.ifa_name != null) {
                if (ctx_p.first == null) ctx_p.first = ifs;
                if (ctx_p.last) |last| last.ifa_next = ifs;
                ctx_p.last = ifs;
            } else {
                c.free(@ptrCast(ifs));
            }
            return 0;
        }
    }.cb;

    const r = c.rtnetlink_enumerate_fn(AF_UNSPEC, AF_UNSPEC, nl_callback, @ptrCast(&ctx));
    if (r == 0) {
        result.* = @ptrCast(ctx.first);
    } else {
        // Free all allocated nodes on failure
        freeifaddrs_impl(@ptrCast(ctx.first));
    }
    return r;
}
fn freeifaddrs_impl(p_init: ?*anyopaque) callconv(.c) void {
    var p: ?[*]u8 = @ptrCast(p_init);
    while (p) |ptr| {
        // First field of ifaddrs is ifa_next pointer
        const next: *?[*]u8 = @alignCast(@ptrCast(ptr));
        const n = next.*;
        c.free(@ptrCast(ptr));
        p = n;
    }
}
