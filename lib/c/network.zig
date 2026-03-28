// DNS resolver core — coordinated migration of all remaining network functions.
// All functions are guarded by link_libc since they depend on C library functions.
const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

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

// These are declared as file-scope constants but only referenced
// from functions guarded by link_libc, so they're never resolved
// in test mode.

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
} else struct {};

// ============================================================
// Symbol exports — ALL guarded by link_libc
// ============================================================

comptime {
    // Subdirectory modules with real implementations
    _ = @import("network/dns.zig");
    _ = @import("network/resolver.zig");
}
