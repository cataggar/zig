const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC() and !builtin.os.tag.isWasi()) {
        symbol(&__errno_location, "__errno_location");
        symbol(&__errno_location, "___errno_location");
    }
    if ((builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) and builtin.link_libc) {
        symbol(&strerror, "strerror");
        symbol(&__strerror_l, "__strerror_l");
        symbol(&__strerror_l, "strerror_l");
    }
}

// ── __errno_location ───────────────────────────────────────────────────

const env = @import("env.zig");

fn __errno_location() callconv(.c) *c_int {
    return &env.pthread_self_ptr().errno_val;
}

// ── strerror ───────────────────────────────────────────────────────────

// Error message table indexed by errno value.
// Max errno on Linux is ~133 (1133 on MIPS for EDQUOT).
const MAX_ERRNO = if (builtin.target.isWasiLibC()) 77 else if (builtin.cpu.arch.isMIPS()) 1134 else 134;

const errmsg = blk: {
    @setEvalBranchQuota(5000);
    var table: [MAX_ERRNO][*:0]const u8 = undefined;
    for (&table) |*entry| entry.* = "No error information";
    const E = if (builtin.target.isWasiLibC()) std.os.wasi.errno_t else linux.E;
    table[@backingInt(E.ILSEQ)] = "Illegal byte sequence";
    table[@backingInt(E.DOM)] = "Domain error";
    table[@backingInt(E.RANGE)] = "Result not representable";
    table[@backingInt(E.NOTTY)] = "Not a tty";
    table[@backingInt(E.ACCES)] = "Permission denied";
    table[@backingInt(E.PERM)] = "Operation not permitted";
    table[@backingInt(E.NOENT)] = "No such file or directory";
    table[@backingInt(E.SRCH)] = "No such process";
    table[@backingInt(E.EXIST)] = "File exists";
    table[@backingInt(E.OVERFLOW)] = "Value too large for data type";
    table[@backingInt(E.NOSPC)] = "No space left on device";
    table[@backingInt(E.NOMEM)] = "Out of memory";
    table[@backingInt(E.BUSY)] = "Resource busy";
    table[@backingInt(E.INTR)] = "Interrupted system call";
    table[@backingInt(E.AGAIN)] = "Resource temporarily unavailable";
    table[@backingInt(E.SPIPE)] = "Invalid seek";
    table[@backingInt(E.XDEV)] = "Cross-device link";
    table[@backingInt(E.ROFS)] = "Read-only file system";
    table[@backingInt(E.NOTEMPTY)] = "Directory not empty";
    table[@backingInt(E.CONNRESET)] = "Connection reset by peer";
    table[@backingInt(E.TIMEDOUT)] = "Operation timed out";
    table[@backingInt(E.CONNREFUSED)] = "Connection refused";
    table[@backingInt(E.HOSTUNREACH)] = "Host is unreachable";
    table[@backingInt(E.ADDRINUSE)] = "Address in use";
    table[@backingInt(E.PIPE)] = "Broken pipe";
    table[@backingInt(E.IO)] = "I/O error";
    table[@backingInt(E.NXIO)] = "No such device or address";
    table[@backingInt(E.NODEV)] = "No such device";
    table[@backingInt(E.NOTDIR)] = "Not a directory";
    table[@backingInt(E.ISDIR)] = "Is a directory";
    table[@backingInt(E.TXTBSY)] = "Text file busy";
    table[@backingInt(E.NOEXEC)] = "Exec format error";
    table[@backingInt(E.INVAL)] = "Invalid argument";
    table[@backingInt(E.@"2BIG")] = "Argument list too long";
    table[@backingInt(E.LOOP)] = "Symbolic link loop";
    table[@backingInt(E.NAMETOOLONG)] = "Filename too long";
    table[@backingInt(E.NFILE)] = "Too many open files in system";
    table[@backingInt(E.MFILE)] = "No file descriptors available";
    table[@backingInt(E.BADF)] = "Bad file descriptor";
    table[@backingInt(E.CHILD)] = "No child process";
    table[@backingInt(E.FAULT)] = "Bad address";
    table[@backingInt(E.FBIG)] = "File too large";
    table[@backingInt(E.MLINK)] = "Too many links";
    table[@backingInt(E.NOLCK)] = "No locks available";
    table[@backingInt(E.DEADLK)] = "Resource deadlock would occur";
    table[@backingInt(E.NOTRECOVERABLE)] = "State not recoverable";
    table[@backingInt(E.OWNERDEAD)] = "Previous owner died";
    table[@backingInt(E.CANCELED)] = "Operation canceled";
    table[@backingInt(E.NOSYS)] = "Function not implemented";
    table[@backingInt(E.NOMSG)] = "No message of desired type";
    table[@backingInt(E.IDRM)] = "Identifier removed";
    table[@backingInt(E.NOLINK)] = "Link has been severed";
    table[@backingInt(E.PROTO)] = "Protocol error";
    table[@backingInt(E.BADMSG)] = "Bad message";
    table[@backingInt(E.NOTSOCK)] = "Not a socket";
    table[@backingInt(E.DESTADDRREQ)] = "Destination address required";
    table[@backingInt(E.MSGSIZE)] = "Message too large";
    table[@backingInt(E.PROTOTYPE)] = "Protocol wrong type for socket";
    table[@backingInt(E.NOPROTOOPT)] = "Protocol not available";
    table[@backingInt(E.PROTONOSUPPORT)] = "Protocol not supported";
    table[@backingInt(E.OPNOTSUPP)] = "Not supported";
    table[@backingInt(E.AFNOSUPPORT)] = "Address family not supported by protocol";
    table[@backingInt(E.ADDRNOTAVAIL)] = "Address not available";
    table[@backingInt(E.NETDOWN)] = "Network is down";
    table[@backingInt(E.NETUNREACH)] = "Network unreachable";
    table[@backingInt(E.NETRESET)] = "Connection reset by network";
    table[@backingInt(E.CONNABORTED)] = "Connection aborted";
    table[@backingInt(E.NOBUFS)] = "No buffer space available";
    table[@backingInt(E.ISCONN)] = "Socket is connected";
    table[@backingInt(E.NOTCONN)] = "Socket not connected";
    table[@backingInt(E.ALREADY)] = "Operation already in progress";
    table[@backingInt(E.INPROGRESS)] = "Operation in progress";
    table[@backingInt(E.STALE)] = "Stale file handle";
    table[@backingInt(E.DQUOT)] = "Quota exceeded";
    table[@backingInt(E.MULTIHOP)] = "Multihop attempted";
    if (builtin.target.isWasiLibC()) {
        table[@backingInt(E.NOTCAPABLE)] = "Capabilities insufficient";
    } else {
        table[@backingInt(E.NOTBLK)] = "Block device required";
        table[@backingInt(E.NOSTR)] = "Device not a stream";
        table[@backingInt(E.NODATA)] = "No data available";
        table[@backingInt(E.TIME)] = "Device timeout";
        table[@backingInt(E.NOSR)] = "Out of streams resources";
        table[@backingInt(E.SOCKTNOSUPPORT)] = "Socket type not supported";
        table[@backingInt(E.PFNOSUPPORT)] = "Protocol family not supported";
        table[@backingInt(E.SHUTDOWN)] = "Cannot send after socket shutdown";
        table[@backingInt(E.REMOTEIO)] = "Remote I/O error";
        table[@backingInt(E.NOMEDIUM)] = "No medium found";
        table[@backingInt(E.MEDIUMTYPE)] = "Wrong medium type";
        table[@backingInt(E.NOKEY)] = "Required key not available";
        table[@backingInt(E.KEYEXPIRED)] = "Key has expired";
        table[@backingInt(E.KEYREVOKED)] = "Key has been revoked";
        table[@backingInt(E.KEYREJECTED)] = "Key was rejected by service";
    }
    break :blk table;
};

fn strerror(e: c_int) callconv(.c) [*:0]const u8 {
    const idx: usize = if (e >= 0 and e < MAX_ERRNO) @intCast(e) else 0;
    return errmsg[idx];
}

fn __strerror_l(e: c_int, _: ?*anyopaque) callconv(.c) [*:0]const u8 {
    return strerror(e);
}
