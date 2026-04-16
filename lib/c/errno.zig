const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&__errno_location, "__errno_location");
        symbol(&__errno_location, "___errno_location");
    }
    if (builtin.link_libc) {
        symbol(&strerror, "strerror");
        symbol(&__strerror_l, "__strerror_l");
        symbol(&__strerror_l, "strerror_l");
    }
}

// ── __errno_location ───────────────────────────────────────────────────

threadlocal var errno_val: c_int = 0;

fn __errno_location() callconv(.c) *c_int {
    return &errno_val;
}

// ── strerror ───────────────────────────────────────────────────────────

// Error message table indexed by errno value.
// Max errno on Linux is ~133, allocate 134 entries.
const MAX_ERRNO = 134;

const errmsg = blk: {
    var table: [MAX_ERRNO][*:0]const u8 = .{"No error information"} ** MAX_ERRNO;
    const E = linux.E;
    table[@intFromEnum(E.ILSEQ)] = "Illegal byte sequence";
    table[@intFromEnum(E.DOM)] = "Domain error";
    table[@intFromEnum(E.RANGE)] = "Result not representable";
    table[@intFromEnum(E.NOTTY)] = "Not a tty";
    table[@intFromEnum(E.ACCES)] = "Permission denied";
    table[@intFromEnum(E.PERM)] = "Operation not permitted";
    table[@intFromEnum(E.NOENT)] = "No such file or directory";
    table[@intFromEnum(E.SRCH)] = "No such process";
    table[@intFromEnum(E.EXIST)] = "File exists";
    table[@intFromEnum(E.OVERFLOW)] = "Value too large for data type";
    table[@intFromEnum(E.NOSPC)] = "No space left on device";
    table[@intFromEnum(E.NOMEM)] = "Out of memory";
    table[@intFromEnum(E.BUSY)] = "Resource busy";
    table[@intFromEnum(E.INTR)] = "Interrupted system call";
    table[@intFromEnum(E.AGAIN)] = "Resource temporarily unavailable";
    table[@intFromEnum(E.SPIPE)] = "Invalid seek";
    table[@intFromEnum(E.XDEV)] = "Cross-device link";
    table[@intFromEnum(E.ROFS)] = "Read-only file system";
    table[@intFromEnum(E.NOTEMPTY)] = "Directory not empty";
    table[@intFromEnum(E.CONNRESET)] = "Connection reset by peer";
    table[@intFromEnum(E.TIMEDOUT)] = "Operation timed out";
    table[@intFromEnum(E.CONNREFUSED)] = "Connection refused";
    table[@intFromEnum(E.HOSTUNREACH)] = "Host is unreachable";
    table[@intFromEnum(E.ADDRINUSE)] = "Address in use";
    table[@intFromEnum(E.PIPE)] = "Broken pipe";
    table[@intFromEnum(E.IO)] = "I/O error";
    table[@intFromEnum(E.NXIO)] = "No such device or address";
    table[@intFromEnum(E.NOTBLK)] = "Block device required";
    table[@intFromEnum(E.NODEV)] = "No such device";
    table[@intFromEnum(E.NOTDIR)] = "Not a directory";
    table[@intFromEnum(E.ISDIR)] = "Is a directory";
    table[@intFromEnum(E.TXTBSY)] = "Text file busy";
    table[@intFromEnum(E.NOEXEC)] = "Exec format error";
    table[@intFromEnum(E.INVAL)] = "Invalid argument";
    table[@intFromEnum(E.@"2BIG")] = "Argument list too long";
    table[@intFromEnum(E.LOOP)] = "Symbolic link loop";
    table[@intFromEnum(E.NAMETOOLONG)] = "Filename too long";
    table[@intFromEnum(E.NFILE)] = "Too many open files in system";
    table[@intFromEnum(E.MFILE)] = "No file descriptors available";
    table[@intFromEnum(E.BADF)] = "Bad file descriptor";
    table[@intFromEnum(E.CHILD)] = "No child process";
    table[@intFromEnum(E.FAULT)] = "Bad address";
    table[@intFromEnum(E.FBIG)] = "File too large";
    table[@intFromEnum(E.MLINK)] = "Too many links";
    table[@intFromEnum(E.NOLCK)] = "No locks available";
    table[@intFromEnum(E.DEADLK)] = "Resource deadlock would occur";
    table[@intFromEnum(E.NOTRECOVERABLE)] = "State not recoverable";
    table[@intFromEnum(E.OWNERDEAD)] = "Previous owner died";
    table[@intFromEnum(E.CANCELED)] = "Operation canceled";
    table[@intFromEnum(E.NOSYS)] = "Function not implemented";
    table[@intFromEnum(E.NOMSG)] = "No message of desired type";
    table[@intFromEnum(E.IDRM)] = "Identifier removed";
    table[@intFromEnum(E.NOSTR)] = "Device not a stream";
    table[@intFromEnum(E.NODATA)] = "No data available";
    table[@intFromEnum(E.TIME)] = "Device timeout";
    table[@intFromEnum(E.NOSR)] = "Out of streams resources";
    table[@intFromEnum(E.NOLINK)] = "Link has been severed";
    table[@intFromEnum(E.PROTO)] = "Protocol error";
    table[@intFromEnum(E.BADMSG)] = "Bad message";
    table[@intFromEnum(E.NOTSOCK)] = "Not a socket";
    table[@intFromEnum(E.DESTADDRREQ)] = "Destination address required";
    table[@intFromEnum(E.MSGSIZE)] = "Message too large";
    table[@intFromEnum(E.PROTOTYPE)] = "Protocol wrong type for socket";
    table[@intFromEnum(E.NOPROTOOPT)] = "Protocol not available";
    table[@intFromEnum(E.PROTONOSUPPORT)] = "Protocol not supported";
    table[@intFromEnum(E.SOCKTNOSUPPORT)] = "Socket type not supported";
    table[@intFromEnum(E.OPNOTSUPP)] = "Not supported";
    table[@intFromEnum(E.PFNOSUPPORT)] = "Protocol family not supported";
    table[@intFromEnum(E.AFNOSUPPORT)] = "Address family not supported by protocol";
    table[@intFromEnum(E.ADDRNOTAVAIL)] = "Address not available";
    table[@intFromEnum(E.NETDOWN)] = "Network is down";
    table[@intFromEnum(E.NETUNREACH)] = "Network unreachable";
    table[@intFromEnum(E.NETRESET)] = "Connection reset by network";
    table[@intFromEnum(E.CONNABORTED)] = "Connection aborted";
    table[@intFromEnum(E.NOBUFS)] = "No buffer space available";
    table[@intFromEnum(E.ISCONN)] = "Socket is connected";
    table[@intFromEnum(E.NOTCONN)] = "Socket not connected";
    table[@intFromEnum(E.SHUTDOWN)] = "Cannot send after socket shutdown";
    table[@intFromEnum(E.ALREADY)] = "Operation already in progress";
    table[@intFromEnum(E.INPROGRESS)] = "Operation in progress";
    table[@intFromEnum(E.STALE)] = "Stale file handle";
    table[@intFromEnum(E.REMOTEIO)] = "Remote I/O error";
    table[@intFromEnum(E.DQUOT)] = "Quota exceeded";
    table[@intFromEnum(E.NOMEDIUM)] = "No medium found";
    table[@intFromEnum(E.MEDIUMTYPE)] = "Wrong medium type";
    table[@intFromEnum(E.MULTIHOP)] = "Multihop attempted";
    table[@intFromEnum(E.NOKEY)] = "Required key not available";
    table[@intFromEnum(E.KEYEXPIRED)] = "Key has expired";
    table[@intFromEnum(E.KEYREVOKED)] = "Key has been revoked";
    table[@intFromEnum(E.KEYREJECTED)] = "Key was rejected by service";
    break :blk table;
};

fn strerror(e: c_int) callconv(.c) [*:0]const u8 {
    const idx: usize = if (e >= 0 and e < MAX_ERRNO) @intCast(e) else 0;
    return errmsg[idx];
}

fn __strerror_l(e: c_int, _: ?*anyopaque) callconv(.c) [*:0]const u8 {
    return strerror(e);
}
