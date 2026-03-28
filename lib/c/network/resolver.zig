// DNS resolver core — complex function implementations.
// These are only active when link_libc is true.
const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;
const symbol = @import("../../c.zig").symbol;

// ============================================================
// Constants
// ============================================================

const MAXNS = 3;
const MAXADDRS = 48;
const MAXSERVS = 2;

const AF_INET: c_int = 2;
const AF_INET6: c_int = 10;
const AF_UNSPEC: c_int = 0;
const PF_NETLINK: c_int = 16;

const SOCK_STREAM: c_int = 1;
const SOCK_DGRAM: c_int = 2;
const SOCK_RAW: c_int = 3;
const SOCK_CLOEXEC: c_int = @as(c_int, @bitCast(@as(c_uint, 0o2000000)));
const SOCK_NONBLOCK: c_int = @as(c_int, @bitCast(@as(c_uint, 0o4000)));

const IPPROTO_TCP: c_int = 6;
const IPPROTO_UDP: c_int = 17;
const IPPROTO_IPV6: c_int = 41;

const MSG_NOSIGNAL: c_int = 0x4000;
const MSG_DONTWAIT: c_int = 0x40;
const MSG_TRUNC: c_int = 0x20;
const MSG_FASTOPEN: c_int = 0x20000000;

const POLLIN: i16 = 1;
const POLLOUT: i16 = 4;

const NETLINK_ROUTE: c_int = 0;
const NLM_F_REQUEST: u16 = 1;
const NLM_F_DUMP: u16 = 0x100 | 0x200;
const NLMSG_DONE: u16 = 3;
const NLMSG_ERROR: u16 = 2;
const RTM_GETLINK: u16 = 18;
const RTM_GETADDR: u16 = 22;
const RTM_NEWLINK: u16 = 16;

const IFLA_IFNAME: u16 = 3;
const IFLA_ADDRESS: u16 = 1;
const IFLA_BROADCAST: u16 = 2;
const IFLA_STATS: u16 = 7;
const IFA_ADDRESS: u16 = 1;
const IFA_LOCAL: u16 = 2;
const IFA_LABEL: u16 = 3;
const IFA_BROADCAST: u16 = 4;

const EAI_BADFLAGS: c_int = -1;
const EAI_NONAME: c_int = -2;
const EAI_AGAIN: c_int = -3;
const EAI_FAIL: c_int = -4;
const EAI_NODATA: c_int = -5;
const EAI_FAMILY: c_int = -6;
const EAI_SERVICE: c_int = -8;
const EAI_MEMORY: c_int = -10;
const EAI_SYSTEM: c_int = -11;
const EAI_OVERFLOW: c_int = -12;

const AI_PASSIVE: c_int = 0x01;
const AI_CANONNAME: c_int = 0x02;
const AI_NUMERICHOST: c_int = 0x04;
const AI_V4MAPPED: c_int = 0x08;
const AI_ALL: c_int = 0x10;
const AI_ADDRCONFIG: c_int = 0x20;
const AI_NUMERICSERV: c_int = 0x0400;

const NI_NUMERICHOST: c_int = 0x01;
const NI_NUMERICSERV: c_int = 0x02;
const NI_NAMEREQD: c_int = 0x08;
const NI_DGRAM: c_int = 0x10;
const NI_NUMERICSCOPE: c_int = 0x100;

const HOST_NOT_FOUND: c_int = 1;
const TRY_AGAIN: c_int = 2;
const NO_RECOVERY: c_int = 3;
const NO_DATA: c_int = 4;

const EAGAIN: c_int = 11;
const ERANGE: c_int = 34;
const ENOENT: c_int = 2;
const ENOTDIR: c_int = 20;
const EACCES: c_int = 13;
const EINVAL: c_int = 22;
const EBADMSG: c_int = 74;
const ENOMEM: c_int = 12;
const EAFNOSUPPORT: c_int = 97;
const EADDRNOTAVAIL: c_int = 99;
const EHOSTUNREACH: c_int = 113;
const ENETDOWN: c_int = 100;
const ENETUNREACH: c_int = 101;
const EINPROGRESS: c_int = 115;
const ENOBUFS: c_int = 105;

const TCP_FASTOPEN_CONNECT: c_int = 30;
const IPV6_V6ONLY: c_int = 26;
const PTHREAD_CANCEL_DISABLE: c_int = 1;
const CLOCK_REALTIME: c_int = 0;
const CLOCK_MONOTONIC: c_int = 1;
const IFNAMSIZ = 16;
const IF_NAMESIZE = 16;
const IFADDRS_HASH_SIZE = 64;

const DAS_USABLE: c_int = 0x40000000;
const DAS_MATCHINGSCOPE: c_int = 0x20000000;
const DAS_MATCHINGLABEL: c_int = 0x10000000;
const DAS_PREC_SHIFT: u5 = 20;
const DAS_SCOPE_SHIFT: u5 = 16;
const DAS_PREFIX_SHIFT: u5 = 8;
const DAS_ORDER_SHIFT: u5 = 0;

const ABUF_SIZE = 4800;
const RR_A: c_int = 1;
const RR_CNAME: c_int = 5;
const RR_PTR: c_int = 12;
const RR_AAAA: c_int = 28;
const PTR_MAX = 64 + 14; // sizeof ".in-addr.arpa" = 14
const MAX_NQ = 8;
const EOF: c_int = -1;
const FILE_BUF_SIZE = 256;

// ============================================================
// Type definitions
// ============================================================

const address = extern struct {
    family: c_int = 0,
    scopeid: c_uint = 0,
    addr: [16]u8 = [1]u8{0} ** 16,
    sortkey: c_int = 0,
};

const service = extern struct {
    port: u16 = 0,
    proto: u8 = 0,
    socktype: u8 = 0,
};

const resolvconf = extern struct {
    ns: [MAXNS]address = [1]address{.{}} ** MAXNS,
    nns: c_uint = 0,
    attempts: c_uint = 0,
    ndots: c_uint = 0,
    timeout: c_uint = 0,
};

const addrinfo = extern struct {
    ai_flags: c_int = 0,
    ai_family: c_int = 0,
    ai_socktype: c_int = 0,
    ai_protocol: c_int = 0,
    ai_addrlen: linux.socklen_t = 0,
    ai_addr: ?*linux.sockaddr = null,
    ai_canonname: ?[*:0]u8 = null,
    ai_next: ?*addrinfo = null,
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
    h_name: ?[*:0]u8 = null,
    h_aliases: ?[*]?[*:0]u8 = null,
    h_addrtype: c_int = 0,
    h_length: c_int = 0,
    h_addr_list: ?[*]?[*]u8 = null,
};

const servent = extern struct {
    s_name: ?[*:0]u8 = null,
    s_aliases: ?[*]?[*:0]u8 = null,
    s_port: c_int = 0,
    s_proto: ?[*:0]u8 = null,
};

const nlmsghdr = extern struct {
    nlmsg_len: u32 = 0,
    nlmsg_type: u16 = 0,
    nlmsg_flags: u16 = 0,
    nlmsg_seq: u32 = 0,
    nlmsg_pid: u32 = 0,
};

const ifaddrmsg = extern struct {
    ifa_family: u8 = 0,
    ifa_prefixlen: u8 = 0,
    ifa_flags: u8 = 0,
    ifa_scope: u8 = 0,
    ifa_index: u32 = 0,
};

const if_nameindex_t = extern struct {
    if_index: c_uint = 0,
    if_name: ?[*:0]u8 = null,
};

const rtgenmsg = extern struct {
    rtgen_family: u8 = 0,
};

const ifinfomsg = extern struct {
    ifi_family: u8 = 0,
    __ifi_pad: u8 = 0,
    ifi_type: c_ushort = 0,
    ifi_index: c_int = 0,
    ifi_flags: c_uint = 0,
    ifi_change: c_uint = 0,
};

const rtattr = extern struct {
    rta_len: c_ushort = 0,
    rta_type: c_ushort = 0,
};

const msghdr_t = extern struct {
    msg_name: ?*anyopaque = null,
    msg_namelen: linux.socklen_t = 0,
    msg_iov: ?[*]iovec_t = null,
    msg_iovlen: usize = 0,
    msg_control: ?*anyopaque = null,
    msg_controllen: usize = 0,
    msg_flags: c_int = 0,
};

const iovec_t = extern struct {
    iov_base: ?*anyopaque = null,
    iov_len: usize = 0,
};

const sockaddr_ll_hack = extern struct {
    sll_family: c_ushort = 0,
    sll_protocol: c_ushort = 0,
    sll_ifindex: c_int = 0,
    sll_hatype: c_ushort = 0,
    sll_pkttype: u8 = 0,
    sll_halen: u8 = 0,
    sll_addr: [24]u8 = [1]u8{0} ** 24,
};

const sockany = extern union {
    sa: linux.sockaddr,
    ll: sockaddr_ll_hack,
    v4: linux.sockaddr.in,
    v6: linux.sockaddr.in6,
};

const ifaddrs_t = extern struct {
    ifa_next: ?*ifaddrs_t = null,
    ifa_name: ?[*:0]u8 = null,
    ifa_flags: c_uint = 0,
    ifa_addr: ?*linux.sockaddr = null,
    ifa_netmask: ?*linux.sockaddr = null,
    ifa_ifu: ?*linux.sockaddr = null,
    ifa_data: ?*anyopaque = null,
};

const ifaddrs_storage = extern struct {
    ifa: ifaddrs_t = .{},
    hash_next: ?*ifaddrs_storage = null,
    addr_sa: sockany = undefined,
    netmask_sa: sockany = undefined,
    ifu_sa: sockany = undefined,
    index: c_uint = 0,
    name: [IFNAMSIZ + 1]u8 = [1]u8{0} ** (IFNAMSIZ + 1),
};

const ifaddrs_ctx = struct {
    first: ?*ifaddrs_t = null,
    last: ?*ifaddrs_t = null,
    hash: [IFADDRS_HASH_SIZE]?*ifaddrs_storage = [1]?*ifaddrs_storage{null} ** IFADDRS_HASH_SIZE,
};

const policy = struct {
    addr_data: [16]u8,
    len: u8,
    mask: u8,
    prec: u8,
    label: u8,
};

const defpolicy = [_]policy{
    .{ .addr_data = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }, .len = 15, .mask = 0xff, .prec = 50, .label = 0 },
    .{ .addr_data = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 0, 0, 0, 0 }, .len = 11, .mask = 0xff, .prec = 35, .label = 4 },
    .{ .addr_data = .{ 0x20, 0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, .len = 1, .mask = 0xff, .prec = 30, .label = 2 },
    .{ .addr_data = .{ 0x20, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, .len = 3, .mask = 0xff, .prec = 5, .label = 5 },
    .{ .addr_data = .{ 0xfc, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, .len = 0, .mask = 0xfe, .prec = 3, .label = 13 },
    .{ .addr_data = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, .len = 0, .mask = 0, .prec = 40, .label = 1 },
};

const ifnamemap = struct {
    hash_next: c_uint = 0,
    index: c_uint = 0,
    namelen: u8 = 0,
    name: [IFNAMSIZ]u8 = [1]u8{0} ** IFNAMSIZ,
};

const ifnameindexctx = struct {
    num: c_uint = 0,
    allocated: c_uint = 0,
    str_bytes: c_uint = 0,
    list: ?[*]ifnamemap = null,
    hash: [IFADDRS_HASH_SIZE]c_uint = [1]c_uint{0} ** IFADDRS_HASH_SIZE,
};

const dpc_ctx = struct {
    addrs: [*]address,
    canon: [*]u8,
    cnt: c_int,
    rrtype: c_int,
};

// ============================================================
// C library function externs (only resolved when link_libc)
// ============================================================

const c = if (builtin.link_libc) struct {
    // Memory
    const malloc = @extern(*const fn (usize) callconv(.c) ?[*]u8, .{ .name = "malloc" });
    const calloc = @extern(*const fn (usize, usize) callconv(.c) ?[*]u8, .{ .name = "calloc" });
    const realloc = @extern(*const fn (?*anyopaque, usize) callconv(.c) ?[*]u8, .{ .name = "realloc" });
    const free = @extern(*const fn (?*anyopaque) callconv(.c) void, .{ .name = "free" });
    // String/memory ops
    const memcpy = @extern(*const fn (?*anyopaque, ?*const anyopaque, usize) callconv(.c) ?*anyopaque, .{ .name = "memcpy" });
    const memcmp = @extern(*const fn (?*const anyopaque, ?*const anyopaque, usize) callconv(.c) c_int, .{ .name = "memcmp" });
    const memset = @extern(*const fn (?*anyopaque, c_int, usize) callconv(.c) ?*anyopaque, .{ .name = "memset" });
    const strlen = @extern(*const fn ([*:0]const u8) callconv(.c) usize, .{ .name = "strlen" });
    const strnlen = @extern(*const fn ([*]const u8, usize) callconv(.c) usize, .{ .name = "strnlen" });
    const strcmp = @extern(*const fn ([*:0]const u8, [*:0]const u8) callconv(.c) c_int, .{ .name = "strcmp" });
    const strncmp = @extern(*const fn ([*]const u8, [*]const u8, usize) callconv(.c) c_int, .{ .name = "strncmp" });
    const strcpy = @extern(*const fn ([*]u8, [*:0]const u8) callconv(.c) [*]u8, .{ .name = "strcpy" });
    const strcat_fn = @extern(*const fn ([*:0]u8, [*:0]const u8) callconv(.c) [*:0]u8, .{ .name = "strcat" });
    const strchr_fn = @extern(*const fn ([*]const u8, c_int) callconv(.c) ?[*]u8, .{ .name = "strchr" });
    const strstr_fn = @extern(*const fn ([*]const u8, [*:0]const u8) callconv(.c) ?[*]u8, .{ .name = "strstr" });
    const strtoul = @extern(*const fn ([*:0]const u8, ?*[*:0]u8, c_int) callconv(.c) c_ulong, .{ .name = "strtoul" });
    const strtol = @extern(*const fn ([*:0]const u8, ?*[*:0]u8, c_int) callconv(.c) c_long, .{ .name = "strtol" });
    // Network
    const htons = @extern(*const fn (u16) callconv(.c) u16, .{ .name = "htons" });
    const ntohs = @extern(*const fn (u16) callconv(.c) u16, .{ .name = "ntohs" });
    const inet_ntop = @extern(*const fn (c_int, *const anyopaque, [*]u8, u32) callconv(.c) ?[*]u8, .{ .name = "inet_ntop" });
    const if_indextoname_fn = @extern(*const fn (c_uint, [*]u8) callconv(.c) ?[*:0]u8, .{ .name = "if_indextoname" });
    const sprintf_fn = @extern(*const fn ([*]u8, [*:0]const u8, ...) callconv(.c) c_int, .{ .name = "sprintf" });
    // Socket
    const socket_fn = @extern(*const fn (c_int, c_int, c_int) callconv(.c) c_int, .{ .name = "socket" });
    const close_fn = @extern(*const fn (c_int) callconv(.c) c_int, .{ .name = "close" });
    const bind_fn = @extern(*const fn (c_int, *const anyopaque, linux.socklen_t) callconv(.c) c_int, .{ .name = "bind" });
    const connect_fn = @extern(*const fn (c_int, *const anyopaque, linux.socklen_t) callconv(.c) c_int, .{ .name = "connect" });
    const sendto_fn = @extern(*const fn (c_int, *const anyopaque, usize, c_int, ?*const anyopaque, linux.socklen_t) callconv(.c) isize, .{ .name = "sendto" });
    const send_fn = @extern(*const fn (c_int, *const anyopaque, usize, c_int) callconv(.c) isize, .{ .name = "send" });
    const recv_fn = @extern(*const fn (c_int, *anyopaque, usize, c_int) callconv(.c) isize, .{ .name = "recv" });
    const recvmsg_fn = @extern(*const fn (c_int, *msghdr_t, c_int) callconv(.c) isize, .{ .name = "recvmsg" });
    const sendmsg_fn = @extern(*const fn (c_int, *const msghdr_t, c_int) callconv(.c) isize, .{ .name = "sendmsg" });
    const setsockopt_fn = @extern(*const fn (c_int, c_int, c_int, *const anyopaque, linux.socklen_t) callconv(.c) c_int, .{ .name = "setsockopt" });
    const getsockname_fn = @extern(*const fn (c_int, *anyopaque, *linux.socklen_t) callconv(.c) c_int, .{ .name = "getsockname" });
    const poll_fn = @extern(*const fn ([*]linux.pollfd, c_ulong, c_int) callconv(.c) c_int, .{ .name = "poll" });
    // File I/O
    const fopen_rb_ca = @extern(*const fn ([*:0]const u8, *anyopaque, [*]u8, usize) callconv(.c) ?*anyopaque, .{ .name = "__fopen_rb_ca" });
    const fclose_ca = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "__fclose_ca" });
    const fgets_fn = @extern(*const fn ([*]u8, c_int, *anyopaque) callconv(.c) ?[*]u8, .{ .name = "fgets" });
    const feof_fn = @extern(*const fn (*anyopaque) callconv(.c) c_int, .{ .name = "feof" });
    const getc_fn = @extern(*const fn (*anyopaque) callconv(.c) c_int, .{ .name = "getc" });
    // Thread
    const pthread_setcancelstate = @extern(*const fn (c_int, ?*c_int) callconv(.c) c_int, .{ .name = "pthread_setcancelstate" });
    // Time
    const clock_gettime_fn = @extern(*const fn (c_int, *linux.timespec) callconv(.c) c_int, .{ .name = "clock_gettime" });
    // DNS internals
    const res_mkquery_fn = @extern(*const fn (c_int, [*:0]const u8, c_int, c_int, ?*const anyopaque, c_int, ?*const anyopaque, [*]u8, c_int) callconv(.c) c_int, .{ .name = "__res_mkquery" });
    const res_send_fn = @extern(*const fn ([*]const u8, c_int, [*]u8, c_int) callconv(.c) c_int, .{ .name = "__res_send" });
    const dns_parse_fn = @extern(*const fn ([*]const u8, c_int, *const fn (?*anyopaque, c_int, *const anyopaque, c_int, *const anyopaque, c_int) callconv(.c) c_int, ?*anyopaque) callconv(.c) c_int, .{ .name = "__dns_parse" });
    const dn_expand_fn = @extern(*const fn ([*]const u8, [*]const u8, [*]const u8, [*]u8, c_int) callconv(.c) c_int, .{ .name = "__dn_expand" });
    const lookup_ipliteral_fn = @extern(*const fn ([*]address, [*:0]const u8, c_int) callconv(.c) c_int, .{ .name = "__lookup_ipliteral" });
    // Sorting
    const qsort_fn = @extern(*const fn (*anyopaque, usize, usize, *const fn (*const anyopaque, *const anyopaque) callconv(.c) c_int) callconv(.c) void, .{ .name = "qsort" });
    // Lock
    const lock_fn = @extern(*const fn ([*]c_int) callconv(.c) void, .{ .name = "__lock" });
    const unlock_fn = @extern(*const fn ([*]c_int) callconv(.c) void, .{ .name = "__unlock" });
    // errno
    const errno_location = @extern(*const fn () callconv(.c) *c_int, .{ .name = "__errno_location" });
    // Multibyte
    const mbstowcs_fn = @extern(*const fn (?[*]u32, [*:0]const u8, usize) callconv(.c) usize, .{ .name = "mbstowcs" });
    // h_errno
    const h_errno_ptr = @extern(*c_int, .{ .name = "h_errno" });
} else struct {};

// ============================================================
// Helper functions
// ============================================================

fn isspace_ch(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == 0x0b or ch == 0x0c;
}

fn isdigit_ch(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

fn isalnum_ch(ch: u8) bool {
    return (ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z');
}

fn in6_is_addr_linklocal(a: [*]const u8) bool {
    return a[0] == 0xfe and (a[1] & 0xc0) == 0x80;
}

fn in6_is_addr_mc_linklocal(a: [*]const u8) bool {
    return a[0] == 0xff and (a[1] & 0x0f) == 2;
}

fn in6_is_addr_multicast(a: [*]const u8) bool {
    return a[0] == 0xff;
}

fn in6_is_addr_loopback(a: [*]const u8) bool {
    inline for (0..15) |i| {
        if (a[i] != 0) return false;
    }
    return a[15] == 1;
}

fn in6_is_addr_sitelocal(a: [*]const u8) bool {
    return a[0] == 0xfe and (a[1] & 0xc0) == 0xc0;
}

fn nlmsg_align(len: u32) u32 {
    return (len + 3) & ~@as(u32, 3);
}

fn nlmsg_hdrlen() u32 {
    return nlmsg_align(@sizeOf(nlmsghdr));
}

fn nlmsg_space(len: u32) u32 {
    return nlmsg_align(nlmsg_hdrlen() + len);
}

fn nlmsg_data(nlh: *nlmsghdr) *anyopaque {
    return @ptrFromInt(@intFromPtr(nlh) + nlmsg_hdrlen());
}

fn nlmsg_ok(nlh: *nlmsghdr, end: usize) bool {
    const h_addr = @intFromPtr(nlh);
    return (end >= h_addr + @sizeOf(nlmsghdr) and
        nlh.nlmsg_len >= @sizeOf(nlmsghdr) and
        h_addr + nlh.nlmsg_len <= end);
}

fn nlmsg_next(nlh: *nlmsghdr) *nlmsghdr {
    return @ptrFromInt(@intFromPtr(nlh) + nlmsg_align(nlh.nlmsg_len));
}

fn rta_align(len: c_ushort) u32 {
    return (@as(u32, len) + 3) & ~@as(u32, 3);
}

fn rta_hdrlen() u32 {
    return rta_align(@sizeOf(rtattr));
}

fn rta_data(r: *rtattr) *anyopaque {
    return @ptrFromInt(@intFromPtr(r) + rta_hdrlen());
}

fn rta_datalen(r: *rtattr) u32 {
    return @as(u32, r.rta_len) - rta_hdrlen();
}

fn rta_next(r: *rtattr) *rtattr {
    return @ptrFromInt(@intFromPtr(r) + rta_align(r.rta_len));
}

fn rta_ok(r: *rtattr, h: *nlmsghdr) bool {
    const r_addr = @intFromPtr(r);
    const h_end = @intFromPtr(h) + h.nlmsg_len;
    return (r_addr + @sizeOf(rtattr) <= h_end and
        r.rta_len >= @sizeOf(rtattr) and
        r_addr + r.rta_len <= h_end);
}

fn nlmsg_rta(h: *nlmsghdr, payload_len: u32) *rtattr {
    return @ptrFromInt(@intFromPtr(h) + nlmsg_space(payload_len));
}

fn getErrno() c_int {
    return c.errno_location().*;
}

fn setErrno(val: c_int) void {
    c.errno_location().* = val;
}

// ============================================================
// Symbol exports
// ============================================================

comptime {
    if (builtin.target.isMuslLibC()) {
        if (builtin.link_libc) {
            symbol(&freeaddrinfo_impl, "freeaddrinfo");
            symbol(&get_resolv_conf_impl, "__get_resolv_conf");
            symbol(&res_msend_impl, "__res_msend");
            symbol(&res_msend_rc_impl, "__res_msend_rc");
            symbol(&lookup_serv_impl, "__lookup_serv");
            symbol(&lookup_name_impl, "__lookup_name");
            symbol(&getaddrinfo_impl, "getaddrinfo");
            symbol(&getnameinfo_impl, "getnameinfo");
            symbol(&gethostbyname2_r_impl, "gethostbyname2_r");
            symbol(&gethostbyaddr_r_impl, "gethostbyaddr_r");
            symbol(&getservbyname_r_impl, "getservbyname_r");
            symbol(&getservbyport_r_impl, "getservbyport_r");
            symbol(&rtnetlink_enumerate_impl, "__rtnetlink_enumerate");
            symbol(&if_nameindex_impl, "if_nameindex");
            symbol(&getifaddrs_impl, "getifaddrs");
            symbol(&freeifaddrs_impl, "freeifaddrs");
            symbol(&dn_comp_impl, "dn_comp");
        }
    }
}