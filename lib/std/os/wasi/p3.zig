//! WASI Preview 3 (0.3.0) Canonical ABI imports and Preview 1 compatibility wrappers.

const builtin = @import("builtin");
const std = @import("std");
const wasi = std.os.wasi;

// ============================================================================
// P3 Async Canonical Built-in Imports & Wire Constants
// ============================================================================

pub const BLOCKED: u32 = 0xffff_ffff;

pub const SubtaskState = enum(u4) {
    starting = 0,
    started = 1,
    returned = 2,
    _,
};

pub const ReturnStatus = enum(u4) {
    completed = 0,
    dropped = 1,
    cancelled = 2,
    _,
};

pub const EventCode = enum(i32) {
    none = 0,
    subtask = 1,
    stream_read = 2,
    stream_write = 3,
    future_read = 4,
    future_write = 5,
    _,
};

pub const waitable_set = struct {
    pub extern "[waitable-set]" fn new() i32;
    pub extern "[waitable-set]" fn wait(set: i32, payload_ptr: *[2]i32) i32;
    pub extern "[waitable-set]" fn poll(set: i32, payload_ptr: *[2]i32) i32;
    pub extern "[waitable-set]" fn drop(set: i32) void;
};

pub const waitable = struct {
    pub extern "[waitable]" fn join(waitable: i32, set: i32) void;
};

pub const subtask = struct {
    pub extern "[subtask]" fn drop(subtask: i32) void;
};

pub const stream_u8 = struct {
    pub extern "[stream]stream<u8>" fn new() u64;
    pub extern "[stream]stream<u8>" fn read(readable: i32, ptr: [*]u8, len: usize) usize;
    pub extern "[stream]stream<u8>" fn write(writable: i32, ptr: [*]const u8, len: usize) usize;
    pub extern "[stream]stream<u8>" fn @"drop-readable"(readable: i32) void;
    pub extern "[stream]stream<u8>" fn @"drop-writable"(writable: i32) void;
};

pub const stream_dir_entry = struct {
    pub extern "[stream]wasi:filesystem/types@0.3.0#[method]descriptor.read-directory#0" fn read(readable: i32, ptr: [*]CanonDirectoryEntry, len: usize) usize;
    pub extern "[stream]wasi:filesystem/types@0.3.0#[method]descriptor.read-directory#0" fn @"drop-readable"(readable: i32) void;
};

pub const future_stdin = struct {
    pub extern "[future]wasi:cli/stdin@0.3.0#read-via-stream#1" fn read(future: i32, ptr: *[2]u8) u32;
    pub extern "[future]wasi:cli/stdin@0.3.0#read-via-stream#1" fn @"drop-readable"(future: i32) void;
};

pub const future_stdout = struct {
    pub extern "[future]wasi:cli/stdout@0.3.0#write-via-stream#1" fn read(future: i32, ptr: *[2]u8) u32;
    pub extern "[future]wasi:cli/stdout@0.3.0#write-via-stream#1" fn @"drop-readable"(future: i32) void;
};

pub const future_stderr = struct {
    pub extern "[future]wasi:cli/stderr@0.3.0#write-via-stream#1" fn read(future: i32, ptr: *[2]u8) u32;
    pub extern "[future]wasi:cli/stderr@0.3.0#write-via-stream#1" fn @"drop-readable"(future: i32) void;
};

pub const future_fs_read = struct {
    pub extern "[future]wasi:filesystem/types@0.3.0#[method]descriptor.read-via-stream#1" fn read(future: i32, ptr: *[20]u8) u32;
    pub extern "[future]wasi:filesystem/types@0.3.0#[method]descriptor.read-via-stream#1" fn @"drop-readable"(future: i32) void;
};

pub const future_fs_write = struct {
    pub extern "[future]wasi:filesystem/types@0.3.0#[method]descriptor.write-via-stream#1" fn read(future: i32, ptr: *[20]u8) u32;
    pub extern "[future]wasi:filesystem/types@0.3.0#[method]descriptor.write-via-stream#1" fn @"drop-readable"(future: i32) void;
};

pub const future_fs_append = struct {
    pub extern "[future]wasi:filesystem/types@0.3.0#[method]descriptor.append-via-stream#1" fn read(future: i32, ptr: *[20]u8) u32;
    pub extern "[future]wasi:filesystem/types@0.3.0#[method]descriptor.append-via-stream#1" fn @"drop-readable"(future: i32) void;
};

pub const future_fs_readdir = struct {
    pub extern "[future]wasi:filesystem/types@0.3.0#[method]descriptor.read-directory#1" fn read(future: i32, ptr: *[20]u8) u32;
    pub extern "[future]wasi:filesystem/types@0.3.0#[method]descriptor.read-directory#1" fn @"drop-readable"(future: i32) void;
};

// ============================================================================
// Canonical ABI 0.3.0 Extern Declarations
// ============================================================================

// wasi:cli/exit@0.3.0
pub extern "wasi:cli/exit@0.3.0" fn exit(status: i32) noreturn;
pub extern "wasi:cli/exit@0.3.0" fn @"exit-with-code"(status_code: i32) noreturn;

// wasi:cli/environment@0.3.0
pub extern "wasi:cli/environment@0.3.0" fn @"get-arguments"(ret_area: *anyopaque) void;
pub extern "wasi:cli/environment@0.3.0" fn @"get-environment"(ret_area: *anyopaque) void;
pub extern "wasi:cli/environment@0.3.0" fn @"get-initial-cwd"(ret_area: *anyopaque) void;

// wasi:cli/stdin@0.3.0, wasi:cli/stdout@0.3.0, wasi:cli/stderr@0.3.0
pub const stdin_mod = struct {
    pub extern "wasi:cli/stdin@0.3.0" fn @"read-via-stream"(ret_area: *[2]i32) void;
};
pub const stdout_mod = struct {
    pub extern "wasi:cli/stdout@0.3.0" fn @"write-via-stream"(data: i32) i32;
};
pub const stderr_mod = struct {
    pub extern "wasi:cli/stderr@0.3.0" fn @"write-via-stream"(data: i32) i32;
};

// wasi:clocks/monotonic-clock@0.3.0
pub const monotonic_clock = struct {
    pub extern "wasi:clocks/monotonic-clock@0.3.0" fn now() u64;
    pub extern "wasi:clocks/monotonic-clock@0.3.0" fn @"get-resolution"() u64;
    pub extern "wasi:clocks/monotonic-clock@0.3.0" fn @"wait-until"(when: u64) i32;
    pub extern "wasi:clocks/monotonic-clock@0.3.0" fn @"wait-for"(how_long: u64) i32;
};
pub const @"wait-until" = monotonic_clock.@"wait-until";
pub const @"wait-for" = monotonic_clock.@"wait-for";

// wasi:clocks/system-clock@0.3.0
pub const system_clock = struct {
    pub extern "wasi:clocks/system-clock@0.3.0" fn now(ret_area: *anyopaque) void;
    pub extern "wasi:clocks/system-clock@0.3.0" fn @"get-resolution"() u64;
};

// wasi:random/random@0.3.0
pub extern "wasi:random/random@0.3.0" fn @"get-random-bytes"(max_len: u64, ret_area: *anyopaque) void;
pub extern "wasi:random/random@0.3.0" fn @"get-random-u64"() u64;

// wasi:filesystem/preopens@0.3.0
pub extern "wasi:filesystem/preopens@0.3.0" fn @"get-directories"(ret_area: *anyopaque) void;

// wasi:filesystem/types@0.3.0 — sync stream methods & resource drop
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.read-via-stream"(self: i32, offset: u64, ret_area: *[2]i32) void;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.write-via-stream"(self: i32, data: i32, offset: u64) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.append-via-stream"(self: i32, data: i32) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.read-directory"(self: i32, ret_area: *[2]i32) void;
pub extern "wasi:filesystem/types@0.3.0" fn @"[resource-drop]descriptor"(handle: i32) void;

// wasi:filesystem/types@0.3.0 — async methods with <= 4 flat params
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.advise"(self: i32, offset: u64, length: u64, advice: i32, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.sync-data"(self: i32, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.get-flags"(self: i32, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.get-type"(self: i32, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.set-size"(self: i32, size: u64, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.sync"(self: i32, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.create-directory-at"(self: i32, path_ptr: [*]const u8, path_len: usize, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.stat"(self: i32, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.stat-at"(self: i32, path_flags: u32, path_ptr: [*]const u8, path_len: usize, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.readlink-at"(self: i32, path_ptr: [*]const u8, path_len: usize, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.remove-directory-at"(self: i32, path_ptr: [*]const u8, path_len: usize, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.unlink-file-at"(self: i32, path_ptr: [*]const u8, path_len: usize, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.is-same-object"(self: i32, other: i32, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.metadata-hash"(self: i32, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.metadata-hash-at"(self: i32, path_flags: u32, path_ptr: [*]const u8, path_len: usize, ret_area: *anyopaque) i32;

// wasi:filesystem/types@0.3.0 — async methods with > 4 flat params (params spilled to pointer)
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.set-times"(params_ptr: *const anyopaque, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.set-times-at"(params_ptr: *const anyopaque, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.link-at"(params_ptr: *const anyopaque, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.open-at"(params_ptr: *const anyopaque, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.rename-at"(params_ptr: *const anyopaque, ret_area: *anyopaque) i32;
pub extern "wasi:filesystem/types@0.3.0" fn @"[method]descriptor.symlink-at"(params_ptr: *const anyopaque, ret_area: *anyopaque) i32;

// ============================================================================
// Canonical ABI Return Area Structures & Helpers
// ============================================================================

pub const CanonString = extern struct {
    ptr: u32 = 0,
    len: u32 = 0,

    pub inline fn ptrSlice(self: CanonString) [*]u8 {
        return @ptrFromInt(self.ptr);
    }
};

pub const CanonStringList = extern struct {
    ptr: u32 = 0,
    len: u32 = 0,

    pub inline fn ptrSlice(self: CanonStringList) [*]const CanonString {
        return @ptrFromInt(self.ptr);
    }
};

pub const CanonEnvPair = extern struct {
    k_ptr: u32 = 0,
    k_len: u32 = 0,
    v_ptr: u32 = 0,
    v_len: u32 = 0,

    pub inline fn kPtrSlice(self: CanonEnvPair) [*]u8 {
        return @ptrFromInt(self.k_ptr);
    }

    pub inline fn vPtrSlice(self: CanonEnvPair) [*]u8 {
        return @ptrFromInt(self.v_ptr);
    }
};

pub const CanonEnvList = extern struct {
    ptr: u32 = 0,
    len: u32 = 0,

    pub inline fn ptrSlice(self: CanonEnvList) [*]const CanonEnvPair {
        return @ptrFromInt(self.ptr);
    }
};

pub const CanonPreopenEntry = extern struct {
    handle: i32,
    name_ptr: u32 = 0,
    name_len: u32 = 0,

    pub inline fn namePtrSlice(self: CanonPreopenEntry) [*]const u8 {
        return @ptrFromInt(self.name_ptr);
    }
};

pub const CanonPreopenList = extern struct {
    ptr: u32 = 0,
    len: u32 = 0,

    pub inline fn ptrSlice(self: CanonPreopenList) [*]const CanonPreopenEntry {
        return @ptrFromInt(self.ptr);
    }
};

pub const CanonInstant = extern struct {
    seconds: i64,
    nanoseconds: u32,
    _pad: u32 = 0,
};

pub const CanonDirectoryEntry = extern struct {
    dtype_disc: u8,
    _pad: [3]u8 = .{ 0, 0, 0 },
    dtype_opt_tag: u8 = 0,
    _pad2: [3]u8 = .{ 0, 0, 0 },
    dtype_opt_ptr: u32 = 0,
    dtype_opt_len: u32 = 0,
    name_ptr: u32 = 0,
    name_len: u32 = 0,

    pub inline fn namePtrSlice(self: CanonDirectoryEntry) [*]u8 {
        return @ptrFromInt(self.name_ptr);
    }
};

fn waitReady(waitable_handle: i32) u32 {
    const ws = waitable_set.new();
    defer waitable_set.drop(ws);
    waitable.join(waitable_handle, ws);
    var payload: [2]i32 = .{ 0, 0 };
    _ = waitable_set.wait(ws, &payload);
    waitable.join(waitable_handle, 0);
    return @bitCast(payload[1]);
}

pub fn awaitAsyncCall(callstatus: i32) void {
    const ustatus: u32 = @bitCast(callstatus);
    const state = ustatus & 0xf;
    const subtask_handle: i32 = @intCast(ustatus >> 4);
    if (state != 2) { // 2 == RETURNED
        const ws = waitable_set.new();
        defer waitable_set.drop(ws);
        waitable.join(subtask_handle, ws);
        var payload: [2]i32 = .{ 0, 0 };
        while (true) {
            _ = waitable_set.wait(ws, &payload);
            if (payload[0] == subtask_handle and (@as(u32, @bitCast(payload[1])) & 0xf) == 2) break;
        }
        subtask.drop(subtask_handle);
    }
}

pub fn cliErrorCodeToErrno(code: u8) wasi.errno_t {
    return switch (code) {
        0 => .IO, // io
        1 => .ILSEQ, // illegal-byte-sequence
        2 => .PIPE, // pipe
        else => .IO,
    };
}

pub fn errorCodeToErrno(code: u32) wasi.errno_t {
    return switch (code) {
        0 => .ACCES, // access
        1 => .ALREADY, // already
        2 => .BADF, // bad-descriptor
        3 => .BUSY, // busy
        4 => .DEADLK, // deadlock
        5 => .DQUOT, // quota
        6 => .EXIST, // exist
        7 => .FBIG, // file-too-large
        8 => .ILSEQ, // illegal-byte-sequence
        9 => .INPROGRESS, // in-progress
        10 => .INTR, // interrupted
        11 => .INVAL, // invalid
        12 => .IO, // io
        13 => .ISDIR, // is-directory
        14 => .LOOP, // loop
        15 => .MLINK, // too-many-links
        16 => .MSGSIZE, // message-size
        17 => .NAMETOOLONG, // name-too-long
        18 => .NODEV, // no-device
        19 => .NOENT, // no-entry
        20 => .NOLCK, // no-lock
        21 => .NOMEM, // insufficient-memory
        22 => .NOSPC, // insufficient-space
        23 => .NOTDIR, // not-directory
        24 => .NOTEMPTY, // not-empty
        25 => .NOTRECOVERABLE, // not-recoverable
        26 => .OPNOTSUPP, // unsupported
        27 => .NOTTY, // no-tty
        28 => .NXIO, // no-such-device
        29 => .OVERFLOW, // overflow
        30 => .PERM, // not-permitted
        31 => .PIPE, // pipe
        32 => .ROFS, // read-only
        33 => .SPIPE, // invalid-seek
        34 => .TXTBSY, // text-file-busy
        35 => .XDEV, // cross-device
        36 => .IO, // other(option<string>)
        else => .IO,
    };
}

pub fn descriptorTypeToFiletype(dtype: u8) wasi.filetype_t {
    return switch (dtype) {
        0 => .BLOCK_DEVICE, // block-device
        1 => .CHARACTER_DEVICE, // character-device
        2 => .DIRECTORY, // directory
        3 => .UNKNOWN, // fifo
        4 => .SYMBOLIC_LINK, // symbolic-link
        5 => .REGULAR_FILE, // regular-file
        6 => .SOCKET_STREAM, // socket
        else => .UNKNOWN, // other(option<string>)
    };
}

fn freeErrorCodePayload(err_bytes: *const [16]u8) void {
    if (err_bytes[0] == 36 and err_bytes[4] != 0) {
        const ptr_addr: usize = std.mem.readInt(u32, err_bytes[8..12], .little);
        const len: usize = std.mem.readInt(u32, err_bytes[12..16], .little);
        if (len > 0) freeGuestSlice(@ptrFromInt(ptr_addr), len);
    }
}

fn freeDescriptorTypePayload(dtype_bytes: *const [16]u8) void {
    if (dtype_bytes[0] == 7 and dtype_bytes[4] != 0) {
        const ptr_addr: usize = std.mem.readInt(u32, dtype_bytes[8..12], .little);
        const len: usize = std.mem.readInt(u32, dtype_bytes[12..16], .little);
        if (len > 0) freeGuestSlice(@ptrFromInt(ptr_addr), len);
    }
}

pub fn descriptorResult20ToErrno(ret: *const [20]u8) wasi.errno_t {
    if (ret[0] == 0) return .SUCCESS;
    freeErrorCodePayload(ret[4..20]);
    return errorCodeToErrno(ret[4]);
}

pub fn descriptorStatResultToErrno(ret: *const [112]u8) wasi.errno_t {
    if (ret[0] == 0) return .SUCCESS;
    freeErrorCodePayload(ret[8..24]);
    return errorCodeToErrno(ret[8]);
}

fn optionInstantToTimestamp(opt: *const [24]u8) wasi.timestamp_t {
    if (opt[0] == 0) return 0;
    const sec_signed = std.mem.readInt(i64, opt[8..16], .little);
    if (sec_signed < 0) return 0;
    const sec: u64 = @intCast(sec_signed);
    const nsec = std.mem.readInt(u32, opt[16..20], .little);
    return sec *| std.time.ns_per_s +| nsec;
}

pub fn writeFilestatFromDescriptorStat(ret: *const [112]u8, buf: *wasi.filestat_t) void {
    freeDescriptorTypePayload(ret[8..24]);
    buf.* = .{
        .dev = 0,
        .ino = 0,
        .filetype = descriptorTypeToFiletype(ret[8]),
        .nlink = std.mem.readInt(u64, ret[24..32], .little),
        .size = std.mem.readInt(u64, ret[32..40], .little),
        .atim = optionInstantToTimestamp(ret[40..64]),
        .mtim = optionInstantToTimestamp(ret[64..88]),
        .ctim = optionInstantToTimestamp(ret[88..112]),
    };
}

pub fn translateLookupFlags(dirflags: wasi.lookupflags_t) u32 {
    return if (dirflags.SYMLINK_FOLLOW) 1 else 0;
}

pub fn translateOpenFlags(oflags: wasi.oflags_t) u32 {
    var open_flags: u32 = 0;
    if (oflags.CREAT) open_flags |= 1;
    if (oflags.DIRECTORY) open_flags |= 2;
    if (oflags.EXCL) open_flags |= 4;
    if (oflags.TRUNC) open_flags |= 8;
    return open_flags;
}

pub fn translateDescriptorFlags(
    fs_rights_base: wasi.rights_t,
    oflags: wasi.oflags_t,
    fs_flags: wasi.fdflags_t,
) u32 {
    var desc_flags: u32 = 0;
    if (fs_rights_base.FD_READ or fs_rights_base.FD_READDIR) desc_flags |= 1;
    if (fs_rights_base.FD_WRITE or fs_rights_base.FD_ALLOCATE or fs_rights_base.FD_FILESTAT_SET_SIZE or oflags.TRUNC) desc_flags |= 2;
    if (fs_flags.SYNC) desc_flags |= 4;
    if (fs_flags.DSYNC) desc_flags |= 8;
    if (fs_flags.RSYNC) desc_flags |= 16;
    const has_mutate_dir_rights =
        fs_rights_base.PATH_CREATE_DIRECTORY or
        fs_rights_base.PATH_CREATE_FILE or
        fs_rights_base.PATH_LINK_SOURCE or
        fs_rights_base.PATH_LINK_TARGET or
        fs_rights_base.PATH_RENAME_SOURCE or
        fs_rights_base.PATH_RENAME_TARGET or
        fs_rights_base.PATH_FILESTAT_SET_SIZE or
        fs_rights_base.PATH_FILESTAT_SET_TIMES or
        fs_rights_base.PATH_SYMLINK or
        fs_rights_base.PATH_REMOVE_DIRECTORY or
        fs_rights_base.PATH_UNLINK_FILE;
    if (!oflags.CREAT and !oflags.TRUNC and (oflags.DIRECTORY or has_mutate_dir_rights)) {
        desc_flags |= 32;
    }
    if (desc_flags == 0) desc_flags = 1;
    return desc_flags;
}

pub const NewTimestamp = struct {
    tag: u8,
    sec: i64,
    nsec: u32,
};

pub fn decodeFstTimestamps(
    st_atim: wasi.timestamp_t,
    st_mtim: wasi.timestamp_t,
    fstflags: wasi.fstflags_t,
) ?struct { atim: NewTimestamp, mtim: NewTimestamp } {
    if (fstflags.ATIM and fstflags.ATIM_NOW) return null;
    if (fstflags.MTIM and fstflags.MTIM_NOW) return null;

    const atim: NewTimestamp = if (fstflags.ATIM_NOW) .{
        .tag = 1,
        .sec = 0,
        .nsec = 0,
    } else if (fstflags.ATIM) .{
        .tag = 2,
        .sec = @intCast(@min(st_atim / std.time.ns_per_s, @as(u64, std.math.maxInt(i64)))),
        .nsec = @intCast(st_atim % std.time.ns_per_s),
    } else .{
        .tag = 0,
        .sec = 0,
        .nsec = 0,
    };

    const mtim: NewTimestamp = if (fstflags.MTIM_NOW) .{
        .tag = 1,
        .sec = 0,
        .nsec = 0,
    } else if (fstflags.MTIM) .{
        .tag = 2,
        .sec = @intCast(@min(st_mtim / std.time.ns_per_s, @as(u64, std.math.maxInt(i64)))),
        .nsec = @intCast(st_mtim % std.time.ns_per_s),
    } else .{
        .tag = 0,
        .sec = 0,
        .nsec = 0,
    };

    return .{ .atim = atim, .mtim = mtim };
}

pub fn packSetTimesParams(handle: i32, atim: NewTimestamp, mtim: NewTimestamp) [56]u8 {
    var params: [56]u8 = @splat(0);
    std.mem.writeInt(i32, params[0..4], handle, .little);
    params[8] = atim.tag;
    std.mem.writeInt(i64, params[16..24], atim.sec, .little);
    std.mem.writeInt(u32, params[24..28], atim.nsec, .little);
    params[32] = mtim.tag;
    std.mem.writeInt(i64, params[40..48], mtim.sec, .little);
    std.mem.writeInt(u32, params[48..52], mtim.nsec, .little);
    return params;
}

pub fn packSetTimesAtParams(
    handle: i32,
    path_flags: u32,
    path_ptr: usize,
    path_len: usize,
    atim: NewTimestamp,
    mtim: NewTimestamp,
) [64]u8 {
    var params: [64]u8 = @splat(0);
    std.mem.writeInt(i32, params[0..4], handle, .little);
    params[4] = @truncate(path_flags);
    std.mem.writeInt(u32, params[8..12], @intCast(path_ptr), .little);
    std.mem.writeInt(u32, params[12..16], @intCast(path_len), .little);
    params[16] = atim.tag;
    std.mem.writeInt(i64, params[24..32], atim.sec, .little);
    std.mem.writeInt(u32, params[32..36], atim.nsec, .little);
    params[40] = mtim.tag;
    std.mem.writeInt(i64, params[48..56], mtim.sec, .little);
    std.mem.writeInt(u32, params[56..60], mtim.nsec, .little);
    return params;
}

pub fn packLinkAtParams(
    old_handle: i32,
    old_path_flags: u32,
    old_path_ptr: usize,
    old_path_len: usize,
    new_handle: i32,
    new_path_ptr: usize,
    new_path_len: usize,
) [28]u8 {
    var params: [28]u8 = @splat(0);
    std.mem.writeInt(i32, params[0..4], old_handle, .little);
    params[4] = @truncate(old_path_flags);
    std.mem.writeInt(u32, params[8..12], @intCast(old_path_ptr), .little);
    std.mem.writeInt(u32, params[12..16], @intCast(old_path_len), .little);
    std.mem.writeInt(i32, params[16..20], new_handle, .little);
    std.mem.writeInt(u32, params[20..24], @intCast(new_path_ptr), .little);
    std.mem.writeInt(u32, params[24..28], @intCast(new_path_len), .little);
    return params;
}

pub fn packOpenAtParams(
    handle: i32,
    path_flags: u32,
    path_ptr: usize,
    path_len: usize,
    open_flags: u32,
    desc_flags: u32,
) [20]u8 {
    var params: [20]u8 = @splat(0);
    std.mem.writeInt(i32, params[0..4], handle, .little);
    params[4] = @truncate(path_flags);
    std.mem.writeInt(u32, params[8..12], @intCast(path_ptr), .little);
    std.mem.writeInt(u32, params[12..16], @intCast(path_len), .little);
    params[16] = @truncate(open_flags);
    params[17] = @truncate(desc_flags);
    return params;
}

pub fn packRenameAtParams(
    old_handle: i32,
    old_path_ptr: usize,
    old_path_len: usize,
    new_handle: i32,
    new_path_ptr: usize,
    new_path_len: usize,
) [24]u8 {
    var params: [24]u8 = @splat(0);
    std.mem.writeInt(i32, params[0..4], old_handle, .little);
    std.mem.writeInt(u32, params[4..8], @intCast(old_path_ptr), .little);
    std.mem.writeInt(u32, params[8..12], @intCast(old_path_len), .little);
    std.mem.writeInt(i32, params[12..16], new_handle, .little);
    std.mem.writeInt(u32, params[16..20], @intCast(new_path_ptr), .little);
    std.mem.writeInt(u32, params[20..24], @intCast(new_path_len), .little);
    return params;
}

pub fn packSymlinkAtParams(
    handle: i32,
    old_path_ptr: usize,
    old_path_len: usize,
    new_path_ptr: usize,
    new_path_len: usize,
) [20]u8 {
    var params: [20]u8 = @splat(0);
    std.mem.writeInt(i32, params[0..4], handle, .little);
    std.mem.writeInt(u32, params[4..8], @intCast(old_path_ptr), .little);
    std.mem.writeInt(u32, params[8..12], @intCast(old_path_len), .little);
    std.mem.writeInt(u32, params[12..16], @intCast(new_path_ptr), .little);
    std.mem.writeInt(u32, params[16..20], @intCast(new_path_len), .little);
    return params;
}

fn freeGuestSlice(ptr: [*]u8, len: usize) void {
    if (comptime builtin.cpu.arch.isWasm() and builtin.single_threaded) {
        if (len > 0) {
            std.heap.wasm_allocator.free(ptr[0..len]);
        }
    }
}

fn writeStreamU8Iovs(tx: i32, iovs: [*]const wasi.ciovec_t, iovs_len: usize) usize {
    var total: usize = 0;
    outer: for (0..iovs_len) |i| {
        const iov = iovs[i];
        var off: usize = 0;
        while (off < iov.len) {
            var rc = stream_u8.write(tx, iov.base + off, iov.len - off);
            if (@as(u32, @truncate(rc)) == BLOCKED) {
                rc = waitReady(tx);
            }
            const status = rc & 0xf;
            const count: usize = @intCast(rc >> 4);
            off += count;
            total += count;
            if (status == 1 or status == 2) {
                break :outer;
            }
        }
    }
    return total;
}

fn awaitCliFuture(comptime Fut: type, fut_handle: i32) wasi.errno_t {
    var fut_ret: [2]u8 align(4) = @splat(0);
    var frc = Fut.read(fut_handle, &fut_ret);
    if (frc == BLOCKED) {
        frc = waitReady(fut_handle);
    }
    Fut.@"drop-readable"(fut_handle);
    if (fut_ret[0] != 0) return cliErrorCodeToErrno(fut_ret[1]);
    return .SUCCESS;
}

fn awaitFsFuture(comptime Fut: type, fut_handle: i32) wasi.errno_t {
    var fut_ret: [20]u8 align(4) = @splat(0);
    var frc = Fut.read(fut_handle, &fut_ret);
    if (frc == BLOCKED) {
        frc = waitReady(fut_handle);
    }
    Fut.@"drop-readable"(fut_handle);
    return descriptorResult20ToErrno(&fut_ret);
}

// ============================================================================
// Descriptor Table State
// ============================================================================

const max_fds = 128;

const FdEntry = struct {
    in_use: bool = false,
    is_preopen: bool = false,
    append: bool = false,
    handle: i32 = -1,
    position: u64 = 0,
    preopen_name_ptr: [*]const u8 = undefined,
    preopen_name_len: usize = 0,
};

var fd_table: [max_fds]FdEntry = @splat(.{});
var preopens_initialized: bool = false;
var preopens_count: usize = 0;

var cached_args: CanonStringList = .{ .ptr = 0, .len = 0 };
var args_initialized: bool = false;

var cached_env: CanonEnvList = .{ .ptr = 0, .len = 0 };
var env_initialized: bool = false;

fn initPreopens() void {
    if (preopens_initialized) return;
    preopens_initialized = true;

    var list: CanonPreopenList = .{ .ptr = 0, .len = 0 };
    @"get-directories"(&list);

    const count = @min(@as(usize, list.len), max_fds - 3);
    preopens_count = count;
    const entries = list.ptrSlice();
    for (0..count) |i| {
        const entry = entries[i];
        fd_table[3 + i] = .{
            .in_use = true,
            .is_preopen = true,
            .append = false,
            .handle = entry.handle,
            .position = 0,
            .preopen_name_ptr = entry.namePtrSlice(),
            .preopen_name_len = entry.name_len,
        };
    }
}

fn getFdEntry(fd: wasi.fd_t) ?*FdEntry {
    initPreopens();
    if (fd < 3) return null;
    const idx: usize = @intCast(fd);
    if (idx >= max_fds) return null;
    if (!fd_table[idx].in_use) return null;
    return &fd_table[idx];
}

fn allocUserFdSlot() ?usize {
    initPreopens();
    const start = 3 + preopens_count;
    for (start..max_fds) |idx| {
        if (!fd_table[idx].in_use) return idx;
    }
    return null;
}

// ============================================================================
// WASI Preview 1 Wrapper Functions
// ============================================================================

fn ensureArgs() CanonStringList {
    if (!args_initialized) {
        args_initialized = true;
        @"get-arguments"(&cached_args);
    }
    return cached_args;
}

pub fn args_sizes_get(argc: *usize, argv_buf_size: *usize) callconv(.c) wasi.errno_t {
    const list = ensureArgs();
    const args = list.ptrSlice();
    var total_bytes: usize = 0;
    for (0..list.len) |i| {
        total_bytes += args[i].len + 1;
    }
    argc.* = list.len;
    argv_buf_size.* = total_bytes;
    return .SUCCESS;
}

pub fn args_get(argv: [*][*:0]u8, argv_buf: [*]u8) callconv(.c) wasi.errno_t {
    const list = ensureArgs();
    const args = list.ptrSlice();
    var buf_offset: usize = 0;
    for (0..list.len) |i| {
        const arg = args[i];
        const dst = argv_buf + buf_offset;
        if (arg.len > 0) {
            @memcpy(dst[0..arg.len], arg.ptrSlice()[0..arg.len]);
        }
        dst[arg.len] = 0;
        argv[i] = @ptrCast(dst);
        buf_offset += arg.len + 1;
    }
    return .SUCCESS;
}

fn ensureEnv() CanonEnvList {
    if (!env_initialized) {
        env_initialized = true;
        @"get-environment"(&cached_env);
    }
    return cached_env;
}

pub fn environ_sizes_get(environ_count: *usize, environ_buf_size: *usize) callconv(.c) wasi.errno_t {
    const list = ensureEnv();
    const pairs = list.ptrSlice();
    var total_bytes: usize = 0;
    for (0..list.len) |i| {
        const pair = pairs[i];
        total_bytes += pair.k_len + 1 + pair.v_len + 1;
    }
    environ_count.* = list.len;
    environ_buf_size.* = total_bytes;
    return .SUCCESS;
}

pub fn environ_get(environ: [*][*:0]u8, environ_buf: [*]u8) callconv(.c) wasi.errno_t {
    const list = ensureEnv();
    const pairs = list.ptrSlice();
    var buf_offset: usize = 0;
    for (0..list.len) |i| {
        const pair = pairs[i];
        const dst = environ_buf + buf_offset;
        if (pair.k_len > 0) {
            @memcpy(dst[0..pair.k_len], pair.kPtrSlice()[0..pair.k_len]);
        }
        dst[pair.k_len] = '=';
        if (pair.v_len > 0) {
            @memcpy(dst[pair.k_len + 1 ..][0..pair.v_len], pair.vPtrSlice()[0..pair.v_len]);
        }
        dst[pair.k_len + 1 + pair.v_len] = 0;
        environ[i] = @ptrCast(dst);
        buf_offset += pair.k_len + 1 + pair.v_len + 1;
    }
    return .SUCCESS;
}

pub fn clock_res_get(clock_id: wasi.clockid_t, resolution: *wasi.timestamp_t) callconv(.c) wasi.errno_t {
    switch (clock_id) {
        .REALTIME => {
            resolution.* = system_clock.@"get-resolution"();
            return .SUCCESS;
        },
        .MONOTONIC => {
            resolution.* = monotonic_clock.@"get-resolution"();
            return .SUCCESS;
        },
        else => return .INVAL,
    }
}

pub fn clock_time_get(clock_id: wasi.clockid_t, precision: wasi.timestamp_t, timestamp: *wasi.timestamp_t) callconv(.c) wasi.errno_t {
    _ = precision;
    switch (clock_id) {
        .REALTIME => {
            var inst: CanonInstant = .{ .seconds = 0, .nanoseconds = 0 };
            system_clock.now(&inst);
            const sec: u64 = if (inst.seconds < 0) 0 else @intCast(inst.seconds);
            timestamp.* = sec *| std.time.ns_per_s +| inst.nanoseconds;
            return .SUCCESS;
        },
        .MONOTONIC => {
            timestamp.* = monotonic_clock.now();
            return .SUCCESS;
        },
        else => return .INVAL,
    }
}

pub fn fd_advise(fd: wasi.fd_t, offset: wasi.filesize_t, len: wasi.filesize_t, advice: wasi.advice_t) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    var ret: [20]u8 align(4) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.advise"(entry.handle, offset, len, @backingInt(advice), &ret));
    return descriptorResult20ToErrno(&ret);
}

pub fn fd_allocate(fd: wasi.fd_t, offset: wasi.filesize_t, len: wasi.filesize_t) callconv(.c) wasi.errno_t {
    _ = offset;
    _ = len;
    _ = getFdEntry(fd) orelse return .BADF;
    return .OPNOTSUPP;
}

pub fn fd_close(fd: wasi.fd_t) callconv(.c) wasi.errno_t {
    if (fd < 0) return .BADF;
    if (fd <= 2) return .SUCCESS;
    const entry = getFdEntry(fd) orelse return .BADF;
    if (!entry.is_preopen) {
        @"[resource-drop]descriptor"(entry.handle);
        entry.* = .{};
    }
    return .SUCCESS;
}

pub fn fd_datasync(fd: wasi.fd_t) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    var ret: [20]u8 align(4) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.sync-data"(entry.handle, &ret));
    return descriptorResult20ToErrno(&ret);
}

pub fn fd_fdstat_get(fd: wasi.fd_t, buf: *wasi.fdstat_t) callconv(.c) wasi.errno_t {
    if (fd < 0) return .BADF;
    if (fd <= 2) {
        buf.* = .{
            .fs_filetype = .CHARACTER_DEVICE,
            .fs_flags = .{},
            .fs_rights_base = if (fd == 0) .{ .FD_READ = true } else .{ .FD_WRITE = true },
            .fs_rights_inheriting = .{},
        };
        return .SUCCESS;
    }

    const entry = getFdEntry(fd) orelse return .BADF;

    var type_ret: [20]u8 align(4) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.get-type"(entry.handle, &type_ret));
    if (type_ret[0] != 0) return descriptorResult20ToErrno(&type_ret);
    freeDescriptorTypePayload(type_ret[4..20]);
    const filetype = descriptorTypeToFiletype(type_ret[4]);

    var flags_ret: [20]u8 align(4) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.get-flags"(entry.handle, &flags_ret));
    if (flags_ret[0] != 0) return descriptorResult20ToErrno(&flags_ret);
    const dflags = flags_ret[4];

    const fs_flags: wasi.fdflags_t = .{
        .APPEND = entry.append,
        .DSYNC = (dflags & 8) != 0,
        .NONBLOCK = false,
        .RSYNC = (dflags & 16) != 0,
        .SYNC = (dflags & 4) != 0,
    };

    var rights_base: wasi.rights_t = @bitCast(@as(u64, std.math.maxInt(u64)));
    if ((dflags & 1) == 0) rights_base.FD_READ = false;
    if ((dflags & 2) == 0) rights_base.FD_WRITE = false;

    buf.* = .{
        .fs_filetype = filetype,
        .fs_flags = fs_flags,
        .fs_rights_base = rights_base,
        .fs_rights_inheriting = @bitCast(@as(u64, std.math.maxInt(u64))),
    };
    return .SUCCESS;
}

pub fn fd_fdstat_set_flags(fd: wasi.fd_t, flags: wasi.fdflags_t) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    entry.append = flags.APPEND;
    return .SUCCESS;
}

pub fn fd_fdstat_set_rights(fd: wasi.fd_t, fs_rights_base: wasi.rights_t, fs_rights_inheriting: wasi.rights_t) callconv(.c) wasi.errno_t {
    _ = fs_rights_base;
    _ = fs_rights_inheriting;
    if (fd >= 0 and fd <= 2) return .SUCCESS;
    _ = getFdEntry(fd) orelse return .BADF;
    return .SUCCESS;
}

pub fn fd_filestat_get(fd: wasi.fd_t, buf: *wasi.filestat_t) callconv(.c) wasi.errno_t {
    if (fd < 0) return .BADF;
    if (fd <= 2) {
        buf.* = .{
            .dev = 0,
            .ino = 0,
            .filetype = .CHARACTER_DEVICE,
            .nlink = 1,
            .size = 0,
            .atim = 0,
            .mtim = 0,
            .ctim = 0,
        };
        return .SUCCESS;
    }

    const entry = getFdEntry(fd) orelse return .BADF;
    var ret: [112]u8 align(8) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.stat"(entry.handle, &ret));
    if (ret[0] != 0) return descriptorStatResultToErrno(&ret);
    writeFilestatFromDescriptorStat(&ret, buf);
    var hash_ret: [24]u8 align(8) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.metadata-hash"(entry.handle, &hash_ret));
    if (hash_ret[0] == 0) {
        const lower = std.mem.readInt(u64, hash_ret[8..16], .little);
        const upper = std.mem.readInt(u64, hash_ret[16..24], .little);
        buf.dev = upper;
        buf.ino = lower;
    } else {
        freeErrorCodePayload(hash_ret[8..24]);
    }
    return .SUCCESS;
}

pub fn fd_filestat_set_size(fd: wasi.fd_t, st_size: wasi.filesize_t) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    var ret: [20]u8 align(4) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.set-size"(entry.handle, st_size, &ret));
    return descriptorResult20ToErrno(&ret);
}

pub fn fd_filestat_set_times(
    fd: wasi.fd_t,
    st_atim: wasi.timestamp_t,
    st_mtim: wasi.timestamp_t,
    fstflags: wasi.fstflags_t,
) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    const ts = decodeFstTimestamps(st_atim, st_mtim, fstflags) orelse return .INVAL;
    var params: [56]u8 align(8) = packSetTimesParams(entry.handle, ts.atim, ts.mtim);
    var ret: [20]u8 align(4) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.set-times"(&params, &ret));
    return descriptorResult20ToErrno(&ret);
}

pub fn fd_pread(
    fd: wasi.fd_t,
    iovs: [*]const wasi.iovec_t,
    iovs_len: usize,
    offset: wasi.filesize_t,
    nread: *usize,
) callconv(.c) wasi.errno_t {
    nread.* = 0;
    if (fd >= 0 and fd <= 2) return .SPIPE;
    const entry = getFdEntry(fd) orelse return .BADF;

    var pair: [2]i32 = .{ 0, 0 };
    @"[method]descriptor.read-via-stream"(entry.handle, offset, &pair);
    const rx = pair[0];
    const fut_handle = pair[1];

    var total: usize = 0;
    var saw_dropped = false;
    outer: for (0..iovs_len) |i| {
        const iov = iovs[i];
        if (iov.len == 0) continue;

        var off: usize = 0;
        while (off < iov.len) {
            var rc = stream_u8.read(rx, iov.base + off, iov.len - off);
            if (@as(u32, @truncate(rc)) == BLOCKED) {
                rc = waitReady(rx);
            }
            const status = rc & 0xf;
            const count: usize = @intCast(rc >> 4);
            off += count;
            total += count;
            if (status == 1) {
                saw_dropped = true;
                break :outer;
            }
            if (status == 2 or count == 0) {
                break :outer;
            }
        }
    }

    stream_u8.@"drop-readable"(rx);
    if (total == 0 and saw_dropped) {
        const err = awaitFsFuture(future_fs_read, fut_handle);
        if (err != .SUCCESS) return err;
    } else {
        future_fs_read.@"drop-readable"(fut_handle);
    }

    nread.* = total;
    return .SUCCESS;
}

pub fn fd_prestat_get(fd: wasi.fd_t, buf: *wasi.prestat_t) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    if (!entry.is_preopen) return .BADF;
    buf.* = .{
        .pr_type = .DIR,
        .u = .{
            .dir = .{
                .pr_name_len = entry.preopen_name_len,
            },
        },
    };
    return .SUCCESS;
}

pub fn fd_prestat_dir_name(fd: wasi.fd_t, path: [*]u8, path_len: usize) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    if (!entry.is_preopen) return .BADF;
    const copy_len = @min(path_len, entry.preopen_name_len);
    if (copy_len > 0) {
        @memcpy(path[0..copy_len], entry.preopen_name_ptr[0..copy_len]);
    }
    return .SUCCESS;
}

pub fn fd_pwrite(
    fd: wasi.fd_t,
    iovs: [*]const wasi.ciovec_t,
    iovs_len: usize,
    offset: wasi.filesize_t,
    nwritten: *usize,
) callconv(.c) wasi.errno_t {
    nwritten.* = 0;
    if (fd >= 0 and fd <= 2) return .SPIPE;
    const entry = getFdEntry(fd) orelse return .BADF;

    const pair = stream_u8.new();
    const rx: i32 = @bitCast(@as(u32, @truncate(pair)));
    const tx: i32 = @bitCast(@as(u32, @truncate(pair >> 32)));

    const fut_handle = @"[method]descriptor.write-via-stream"(entry.handle, rx, offset);
    const written = writeStreamU8Iovs(tx, iovs, iovs_len);
    stream_u8.@"drop-writable"(tx);
    const err = awaitFsFuture(future_fs_write, fut_handle);
    nwritten.* = written;
    return err;
}

pub fn fd_read(
    fd: wasi.fd_t,
    iovs: [*]const wasi.iovec_t,
    iovs_len: usize,
    nread: *usize,
) callconv(.c) wasi.errno_t {
    nread.* = 0;
    if (fd == 0) {
        for (0..iovs_len) |i| {
            const iov = iovs[i];
            if (iov.len == 0) continue;

            var pair: [2]i32 = .{ 0, 0 };
            stdin_mod.@"read-via-stream"(&pair);
            const rx = pair[0];
            const fut_handle = pair[1];

            var rc = stream_u8.read(rx, iov.base, iov.len);
            if (@as(u32, @truncate(rc)) == BLOCKED) {
                rc = waitReady(rx);
            }
            const status = rc & 0xf;
            const count: usize = @intCast(rc >> 4);
            stream_u8.@"drop-readable"(rx);

            if (count == 0 and status == 1) {
                const err = awaitCliFuture(future_stdin, fut_handle);
                if (err != .SUCCESS) return err;
            } else {
                future_stdin.@"drop-readable"(fut_handle);
            }

            nread.* = count;
            return .SUCCESS;
        }
        return .SUCCESS;
    }

    if (fd == 1 or fd == 2) return .BADF;

    const entry = getFdEntry(fd) orelse return .BADF;
    const err = fd_pread(fd, iovs, iovs_len, entry.position, nread);
    if (err == .SUCCESS) {
        entry.position += nread.*;
    }
    return err;
}

pub fn fd_readdir(
    fd: wasi.fd_t,
    buf: [*]u8,
    buf_len: usize,
    cookie: wasi.dircookie_t,
    bufused: *usize,
) callconv(.c) wasi.errno_t {
    bufused.* = 0;
    const entry = getFdEntry(fd) orelse return .BADF;

    var pair: [2]i32 = .{ 0, 0 };
    @"[method]descriptor.read-directory"(entry.handle, &pair);
    const dir_stream = pair[0];
    const fut_handle = pair[1];

    var idx: u64 = 0;
    var used: usize = 0;
    var saw_dropped_empty = false;

    while (true) {
        var dent: [1]CanonDirectoryEntry = undefined;
        var rc = stream_dir_entry.read(dir_stream, &dent, 1);
        if (@as(u32, @truncate(rc)) == BLOCKED) {
            rc = waitReady(dir_stream);
        }
        const status = rc & 0xf;
        const count: usize = @intCast(rc >> 4);
        if (count == 0) {
            if (idx == 0 and status == 1) {
                saw_dropped_empty = true;
            }
            break;
        }

        const d = dent[0];
        const d_name_ptr = d.namePtrSlice();
        const d_name_len: usize = d.name_len;
        defer {
            if (d.dtype_disc == 7 and d.dtype_opt_tag != 0 and d.dtype_opt_len > 0) {
                freeGuestSlice(@ptrFromInt(d.dtype_opt_ptr), d.dtype_opt_len);
            }
            if (d_name_len > 0) {
                freeGuestSlice(d_name_ptr, d_name_len);
            }
        }

        if (idx < cookie) {
            idx += 1;
            if (status == 1 or status == 2) break;
            continue;
        }

        var d_ino: u64 = 0;
        if (!std.mem.eql(u8, d_name_ptr[0..d_name_len], "..")) {
            var hash_ret: [24]u8 align(8) = @splat(0);
            awaitAsyncCall(@"[method]descriptor.metadata-hash-at"(entry.handle, 0, d_name_ptr, d_name_len, &hash_ret));
            if (hash_ret[0] == 0) {
                d_ino = std.mem.readInt(u64, hash_ret[8..16], .little);
            } else {
                freeErrorCodePayload(hash_ret[8..24]);
            }
        }

        var dirent_bytes: [24]u8 = @splat(0);
        std.mem.writeInt(u64, dirent_bytes[0..8], idx + 1, .little);
        std.mem.writeInt(u64, dirent_bytes[8..16], d_ino, .little);
        std.mem.writeInt(u32, dirent_bytes[16..20], d.name_len, .little);
        dirent_bytes[20] = @backingInt(descriptorTypeToFiletype(d.dtype_disc));

        const copy_hdr = @min(dirent_bytes.len, buf_len - used);
        if (copy_hdr > 0) {
            @memcpy(buf[used..][0..copy_hdr], dirent_bytes[0..copy_hdr]);
            used += copy_hdr;
        }

        const copy_name = @min(d_name_len, buf_len - used);
        if (copy_name > 0) {
            @memcpy(buf[used..][0..copy_name], d_name_ptr[0..copy_name]);
            used += copy_name;
        }

        idx += 1;
        if (used == buf_len or status == 1 or status == 2) break;
    }

    stream_dir_entry.@"drop-readable"(dir_stream);
    if (saw_dropped_empty) {
        const err = awaitFsFuture(future_fs_readdir, fut_handle);
        if (err != .SUCCESS) return err;
    } else {
        future_fs_readdir.@"drop-readable"(fut_handle);
    }

    bufused.* = used;
    return .SUCCESS;
}

pub fn fd_renumber(from: wasi.fd_t, to: wasi.fd_t) callconv(.c) wasi.errno_t {
    if (from == to) {
        if (from >= 0 and from <= 2) return .SUCCESS;
        _ = getFdEntry(from) orelse return .BADF;
        return .SUCCESS;
    }
    const from_entry = getFdEntry(from) orelse return .BADF;
    if (to < 3) return .BADF;
    const to_idx: usize = @intCast(to);
    if (to_idx >= max_fds) return .BADF;
    if (from_entry.is_preopen or fd_table[to_idx].is_preopen) return .OPNOTSUPP;

    if (fd_table[to_idx].in_use) {
        @"[resource-drop]descriptor"(fd_table[to_idx].handle);
    }

    fd_table[to_idx] = from_entry.*;
    from_entry.* = .{};
    return .SUCCESS;
}

pub fn fd_seek(
    fd: wasi.fd_t,
    offset: wasi.filedelta_t,
    whence: wasi.whence_t,
    newoffset: *wasi.filesize_t,
) callconv(.c) wasi.errno_t {
    if (fd >= 0 and fd <= 2) return .SPIPE;
    const entry = getFdEntry(fd) orelse return .BADF;

    const base: i64 = switch (whence) {
        .SET => 0,
        .CUR => @intCast(entry.position),
        .END => blk: {
            var stat_ret: [112]u8 align(8) = @splat(0);
            awaitAsyncCall(@"[method]descriptor.stat"(entry.handle, &stat_ret));
            if (stat_ret[0] != 0) return descriptorStatResultToErrno(&stat_ret);
            freeDescriptorTypePayload(stat_ret[8..24]);
            break :blk @intCast(std.mem.readInt(u64, stat_ret[32..40], .little));
        },
    };

    const target = std.math.add(i64, base, offset) catch return .OVERFLOW;
    if (target < 0) return .INVAL;
    entry.position = @intCast(target);
    newoffset.* = entry.position;
    return .SUCCESS;
}

pub fn fd_sync(fd: wasi.fd_t) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    var ret: [20]u8 align(4) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.sync"(entry.handle, &ret));
    return descriptorResult20ToErrno(&ret);
}

pub fn fd_tell(fd: wasi.fd_t, newoffset: *wasi.filesize_t) callconv(.c) wasi.errno_t {
    if (fd >= 0 and fd <= 2) return .SPIPE;
    const entry = getFdEntry(fd) orelse return .BADF;
    newoffset.* = entry.position;
    return .SUCCESS;
}

pub fn fd_write(
    fd: wasi.fd_t,
    iovs: [*]const wasi.ciovec_t,
    iovs_len: usize,
    nwritten: *usize,
) callconv(.c) wasi.errno_t {
    nwritten.* = 0;
    if (fd == 0) return .BADF;
    if (fd == 1 or fd == 2) {
        const pair = stream_u8.new();
        const rx: i32 = @bitCast(@as(u32, @truncate(pair)));
        const tx: i32 = @bitCast(@as(u32, @truncate(pair >> 32)));

        const fut_handle = if (fd == 1)
            stdout_mod.@"write-via-stream"(rx)
        else
            stderr_mod.@"write-via-stream"(rx);

        const written = writeStreamU8Iovs(tx, iovs, iovs_len);
        stream_u8.@"drop-writable"(tx);

        const err = if (fd == 1)
            awaitCliFuture(future_stdout, fut_handle)
        else
            awaitCliFuture(future_stderr, fut_handle);

        nwritten.* = written;
        return err;
    }

    const entry = getFdEntry(fd) orelse return .BADF;
    if (entry.append) {
        const pair = stream_u8.new();
        const rx: i32 = @bitCast(@as(u32, @truncate(pair)));
        const tx: i32 = @bitCast(@as(u32, @truncate(pair >> 32)));

        const fut_handle = @"[method]descriptor.append-via-stream"(entry.handle, rx);
        const written = writeStreamU8Iovs(tx, iovs, iovs_len);
        stream_u8.@"drop-writable"(tx);
        const err = awaitFsFuture(future_fs_append, fut_handle);
        nwritten.* = written;
        if (err == .SUCCESS) {
            var stat_ret: [112]u8 align(8) = @splat(0);
            awaitAsyncCall(@"[method]descriptor.stat"(entry.handle, &stat_ret));
            if (stat_ret[0] == 0) {
                freeDescriptorTypePayload(stat_ret[8..24]);
                entry.position = std.mem.readInt(u64, stat_ret[32..40], .little);
            } else {
                freeErrorCodePayload(stat_ret[8..24]);
                entry.position += written;
            }
        }
        return err;
    }

    const err = fd_pwrite(fd, iovs, iovs_len, entry.position, nwritten);
    if (err == .SUCCESS) {
        entry.position += nwritten.*;
    }
    return err;
}

pub fn path_create_directory(fd: wasi.fd_t, path: [*]const u8, path_len: usize) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    if (!std.unicode.utf8ValidateSlice(path[0..path_len])) return .ILSEQ;
    var ret: [20]u8 align(4) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.create-directory-at"(entry.handle, path, path_len, &ret));
    return descriptorResult20ToErrno(&ret);
}

pub fn path_filestat_get(
    fd: wasi.fd_t,
    flags: wasi.lookupflags_t,
    path: [*]const u8,
    path_len: usize,
    buf: *wasi.filestat_t,
) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    if (!std.unicode.utf8ValidateSlice(path[0..path_len])) return .ILSEQ;
    const path_flags = translateLookupFlags(flags);
    var ret: [112]u8 align(8) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.stat-at"(entry.handle, path_flags, path, path_len, &ret));
    if (ret[0] != 0) return descriptorStatResultToErrno(&ret);
    writeFilestatFromDescriptorStat(&ret, buf);
    var hash_ret: [24]u8 align(8) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.metadata-hash-at"(entry.handle, path_flags, path, path_len, &hash_ret));
    if (hash_ret[0] == 0) {
        const lower = std.mem.readInt(u64, hash_ret[8..16], .little);
        const upper = std.mem.readInt(u64, hash_ret[16..24], .little);
        buf.dev = upper;
        buf.ino = lower;
    } else {
        freeErrorCodePayload(hash_ret[8..24]);
    }
    return .SUCCESS;
}

pub fn path_filestat_set_times(
    fd: wasi.fd_t,
    flags: wasi.lookupflags_t,
    path: [*]const u8,
    path_len: usize,
    st_atim: wasi.timestamp_t,
    st_mtim: wasi.timestamp_t,
    fstflags: wasi.fstflags_t,
) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    if (!std.unicode.utf8ValidateSlice(path[0..path_len])) return .ILSEQ;
    const ts = decodeFstTimestamps(st_atim, st_mtim, fstflags) orelse return .INVAL;
    const path_flags = translateLookupFlags(flags);
    var params: [64]u8 align(8) = packSetTimesAtParams(
        entry.handle,
        path_flags,
        @intFromPtr(path),
        path_len,
        ts.atim,
        ts.mtim,
    );
    var ret: [20]u8 align(4) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.set-times-at"(&params, &ret));
    return descriptorResult20ToErrno(&ret);
}

pub fn path_link(
    old_fd: wasi.fd_t,
    old_flags: wasi.lookupflags_t,
    old_path: [*]const u8,
    old_path_len: usize,
    new_fd: wasi.fd_t,
    new_path: [*]const u8,
    new_path_len: usize,
) callconv(.c) wasi.errno_t {
    const old_entry = getFdEntry(old_fd) orelse return .BADF;
    const new_entry = getFdEntry(new_fd) orelse return .BADF;
    if (!std.unicode.utf8ValidateSlice(old_path[0..old_path_len])) return .ILSEQ;
    if (!std.unicode.utf8ValidateSlice(new_path[0..new_path_len])) return .ILSEQ;
    const path_flags = translateLookupFlags(old_flags);
    var params: [28]u8 align(4) = packLinkAtParams(
        old_entry.handle,
        path_flags,
        @intFromPtr(old_path),
        old_path_len,
        new_entry.handle,
        @intFromPtr(new_path),
        new_path_len,
    );
    var ret: [20]u8 align(4) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.link-at"(&params, &ret));
    return descriptorResult20ToErrno(&ret);
}

pub fn path_open(
    dirfd: wasi.fd_t,
    dirflags: wasi.lookupflags_t,
    path: [*]const u8,
    path_len: usize,
    oflags: wasi.oflags_t,
    fs_rights_base: wasi.rights_t,
    fs_rights_inheriting: wasi.rights_t,
    fs_flags: wasi.fdflags_t,
    fd: *wasi.fd_t,
) callconv(.c) wasi.errno_t {
    _ = fs_rights_inheriting;
    const dir_entry = getFdEntry(dirfd) orelse return .BADF;
    if (!std.unicode.utf8ValidateSlice(path[0..path_len])) return .ILSEQ;
    const slot_idx = allocUserFdSlot() orelse return .MFILE;

    const path_flags = translateLookupFlags(dirflags);
    const open_flags = translateOpenFlags(oflags);
    const desc_flags = translateDescriptorFlags(fs_rights_base, oflags, fs_flags);

    var params: [20]u8 align(4) = packOpenAtParams(
        dir_entry.handle,
        path_flags,
        @intFromPtr(path),
        path_len,
        open_flags,
        desc_flags,
    );
    var ret: [20]u8 align(4) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.open-at"(&params, &ret));
    if (ret[0] != 0 and (desc_flags & 32) != 0) {
        freeErrorCodePayload(ret[4..20]);
        var fallback_flags = desc_flags & ~@as(u32, 32);
        if (fallback_flags == 0) fallback_flags = 1;
        params = packOpenAtParams(
            dir_entry.handle,
            path_flags,
            @intFromPtr(path),
            path_len,
            open_flags,
            fallback_flags,
        );
        ret = @splat(0);
        awaitAsyncCall(@"[method]descriptor.open-at"(&params, &ret));
    }
    if (ret[0] != 0) return descriptorResult20ToErrno(&ret);

    const new_handle = std.mem.readInt(i32, ret[4..8], .little);
    fd_table[slot_idx] = .{
        .in_use = true,
        .is_preopen = false,
        .append = fs_flags.APPEND,
        .handle = new_handle,
        .position = 0,
    };
    fd.* = @intCast(slot_idx);
    return .SUCCESS;
}

pub fn path_readlink(
    fd: wasi.fd_t,
    path: [*]const u8,
    path_len: usize,
    buf: [*]u8,
    buf_len: usize,
    bufused: *usize,
) callconv(.c) wasi.errno_t {
    bufused.* = 0;
    const entry = getFdEntry(fd) orelse return .BADF;
    if (!std.unicode.utf8ValidateSlice(path[0..path_len])) return .ILSEQ;
    var ret: [20]u8 align(4) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.readlink-at"(entry.handle, path, path_len, &ret));
    if (ret[0] != 0) return descriptorResult20ToErrno(&ret);

    const ptr_addr: usize = std.mem.readInt(u32, ret[4..8], .little);
    const len: usize = std.mem.readInt(u32, ret[8..12], .little);
    const copy_len = @min(len, buf_len);
    if (copy_len > 0) {
        const ptr: [*]const u8 = @ptrFromInt(ptr_addr);
        @memcpy(buf[0..copy_len], ptr[0..copy_len]);
    }
    if (len > 0) {
        freeGuestSlice(@ptrFromInt(ptr_addr), len);
    }
    bufused.* = copy_len;
    return .SUCCESS;
}

pub fn path_remove_directory(fd: wasi.fd_t, path: [*]const u8, path_len: usize) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    if (!std.unicode.utf8ValidateSlice(path[0..path_len])) return .ILSEQ;
    var ret: [20]u8 align(4) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.remove-directory-at"(entry.handle, path, path_len, &ret));
    return descriptorResult20ToErrno(&ret);
}

pub fn path_rename(
    old_fd: wasi.fd_t,
    old_path: [*]const u8,
    old_path_len: usize,
    new_fd: wasi.fd_t,
    new_path: [*]const u8,
    new_path_len: usize,
) callconv(.c) wasi.errno_t {
    const old_entry = getFdEntry(old_fd) orelse return .BADF;
    const new_entry = getFdEntry(new_fd) orelse return .BADF;
    if (!std.unicode.utf8ValidateSlice(old_path[0..old_path_len])) return .ILSEQ;
    if (!std.unicode.utf8ValidateSlice(new_path[0..new_path_len])) return .ILSEQ;
    var params: [24]u8 align(4) = packRenameAtParams(
        old_entry.handle,
        @intFromPtr(old_path),
        old_path_len,
        new_entry.handle,
        @intFromPtr(new_path),
        new_path_len,
    );
    var ret: [20]u8 align(4) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.rename-at"(&params, &ret));
    return descriptorResult20ToErrno(&ret);
}

pub fn path_symlink(
    old_path: [*]const u8,
    old_path_len: usize,
    fd: wasi.fd_t,
    new_path: [*]const u8,
    new_path_len: usize,
) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    if (!std.unicode.utf8ValidateSlice(old_path[0..old_path_len])) return .ILSEQ;
    if (!std.unicode.utf8ValidateSlice(new_path[0..new_path_len])) return .ILSEQ;
    var params: [20]u8 align(4) = packSymlinkAtParams(
        entry.handle,
        @intFromPtr(old_path),
        old_path_len,
        @intFromPtr(new_path),
        new_path_len,
    );
    var ret: [20]u8 align(4) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.symlink-at"(&params, &ret));
    return descriptorResult20ToErrno(&ret);
}

pub fn path_unlink_file(fd: wasi.fd_t, path: [*]const u8, path_len: usize) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    if (!std.unicode.utf8ValidateSlice(path[0..path_len])) return .ILSEQ;
    var ret: [20]u8 align(4) = @splat(0);
    awaitAsyncCall(@"[method]descriptor.unlink-file-at"(entry.handle, path, path_len, &ret));
    return descriptorResult20ToErrno(&ret);
}

pub fn poll_oneoff(
    in: *const wasi.subscription_t,
    out: *wasi.event_t,
    nsubscriptions: usize,
    nevents: *usize,
) callconv(.c) wasi.errno_t {
    nevents.* = 0;
    if (nsubscriptions == 0) return .SUCCESS;

    const subs: [*]const wasi.subscription_t = @ptrCast(in);
    const events: [*]wasi.event_t = @ptrCast(out);

    var out_idx: usize = 0;
    for (0..nsubscriptions) |i| {
        const sub = subs[i];
        switch (sub.u.tag) {
            .CLOCK => {
                const clock_sub = sub.u.u.clock;
                const is_abstime = (clock_sub.flags & wasi.SUBSCRIPTION_CLOCK_ABSTIME) != 0;
                const callstatus: i32 = if (is_abstime and clock_sub.id == .MONOTONIC)
                    @"wait-until"(clock_sub.timeout)
                else
                    @"wait-for"(clock_sub.timeout);
                awaitAsyncCall(callstatus);

                events[out_idx] = .{
                    .userdata = sub.userdata,
                    .@"error" = .SUCCESS,
                    .type = .CLOCK,
                    .fd_readwrite = .{
                        .nbytes = 0,
                        .flags = 0,
                    },
                };
                out_idx += 1;
            },
            .FD_READ, .FD_WRITE => {
                events[out_idx] = .{
                    .userdata = sub.userdata,
                    .@"error" = .OPNOTSUPP,
                    .type = sub.u.tag,
                    .fd_readwrite = .{
                        .nbytes = 0,
                        .flags = 0,
                    },
                };
                out_idx += 1;
            },
        }
    }

    nevents.* = out_idx;
    return .SUCCESS;
}

pub fn proc_exit(rval: wasi.exitcode_t) callconv(.c) noreturn {
    @"exit-with-code"(@intCast(rval & 0xff));
}

pub fn random_get(buf: [*]u8, buf_len: usize) callconv(.c) wasi.errno_t {
    var offset: usize = 0;
    while (offset + 8 <= buf_len) : (offset += 8) {
        const val = @"get-random-u64"();
        std.mem.writeInt(u64, buf[offset..][0..8], val, .little);
    }
    if (offset < buf_len) {
        var tmp: [8]u8 = undefined;
        std.mem.writeInt(u64, &tmp, @"get-random-u64"(), .little);
        const rem = buf_len - offset;
        @memcpy(buf[offset..][0..rem], tmp[0..rem]);
    }
    return .SUCCESS;
}

pub fn sched_yield() callconv(.c) wasi.errno_t {
    return .SUCCESS;
}

fn validateSocketFd(sock: wasi.fd_t) wasi.errno_t {
    if (sock < 0) return .BADF;
    if (sock <= 2) return .NOTSOCK;
    _ = getFdEntry(sock) orelse return .BADF;
    return .NOTSOCK;
}

pub fn sock_accept(sock: wasi.fd_t, flags: wasi.fdflags_t, fd: *wasi.fd_t) callconv(.c) wasi.errno_t {
    _ = flags;
    _ = fd;
    return validateSocketFd(sock);
}

pub fn sock_recv(
    sock: wasi.fd_t,
    ri_data: [*]wasi.iovec_t,
    ri_data_len: usize,
    ri_flags: wasi.riflags_t,
    ro_datalen: *usize,
    ro_flags: *wasi.roflags_t,
) callconv(.c) wasi.errno_t {
    _ = ri_data;
    _ = ri_data_len;
    _ = ri_flags;
    ro_datalen.* = 0;
    ro_flags.* = 0;
    return validateSocketFd(sock);
}

pub fn sock_send(
    sock: wasi.fd_t,
    si_data: [*]const wasi.ciovec_t,
    si_data_len: usize,
    si_flags: wasi.siflags_t,
    so_datalen: *usize,
) callconv(.c) wasi.errno_t {
    _ = si_data;
    _ = si_data_len;
    _ = si_flags;
    so_datalen.* = 0;
    return validateSocketFd(sock);
}

pub fn sock_shutdown(sock: wasi.fd_t, how: wasi.sdflags_t) callconv(.c) wasi.errno_t {
    _ = how;
    return validateSocketFd(sock);
}

// ============================================================================
// Unit Tests
// ============================================================================

test "errorCodeToErrno 0.3.0 mapping" {
    try std.testing.expectEqual(wasi.errno_t.ACCES, errorCodeToErrno(0));
    try std.testing.expectEqual(wasi.errno_t.ALREADY, errorCodeToErrno(1));
    try std.testing.expectEqual(wasi.errno_t.BADF, errorCodeToErrno(2));
    try std.testing.expectEqual(wasi.errno_t.EXIST, errorCodeToErrno(6));
    try std.testing.expectEqual(wasi.errno_t.INVAL, errorCodeToErrno(11));
    try std.testing.expectEqual(wasi.errno_t.IO, errorCodeToErrno(12));
    try std.testing.expectEqual(wasi.errno_t.ISDIR, errorCodeToErrno(13));
    try std.testing.expectEqual(wasi.errno_t.NOENT, errorCodeToErrno(19));
    try std.testing.expectEqual(wasi.errno_t.NOTDIR, errorCodeToErrno(23));
    try std.testing.expectEqual(wasi.errno_t.NOTEMPTY, errorCodeToErrno(24));
    try std.testing.expectEqual(wasi.errno_t.OPNOTSUPP, errorCodeToErrno(26));
    try std.testing.expectEqual(wasi.errno_t.PERM, errorCodeToErrno(30));
    try std.testing.expectEqual(wasi.errno_t.PIPE, errorCodeToErrno(31));
    try std.testing.expectEqual(wasi.errno_t.ROFS, errorCodeToErrno(32));
    try std.testing.expectEqual(wasi.errno_t.SPIPE, errorCodeToErrno(33));
    try std.testing.expectEqual(wasi.errno_t.XDEV, errorCodeToErrno(35));
    try std.testing.expectEqual(wasi.errno_t.IO, errorCodeToErrno(36));
    try std.testing.expectEqual(wasi.errno_t.IO, errorCodeToErrno(99));

    try std.testing.expectEqual(wasi.errno_t.IO, cliErrorCodeToErrno(0));
    try std.testing.expectEqual(wasi.errno_t.ILSEQ, cliErrorCodeToErrno(1));
    try std.testing.expectEqual(wasi.errno_t.PIPE, cliErrorCodeToErrno(2));
}

test "descriptorTypeToFiletype 0.3.0 mapping" {
    try std.testing.expectEqual(wasi.filetype_t.BLOCK_DEVICE, descriptorTypeToFiletype(0));
    try std.testing.expectEqual(wasi.filetype_t.CHARACTER_DEVICE, descriptorTypeToFiletype(1));
    try std.testing.expectEqual(wasi.filetype_t.DIRECTORY, descriptorTypeToFiletype(2));
    try std.testing.expectEqual(wasi.filetype_t.UNKNOWN, descriptorTypeToFiletype(3));
    try std.testing.expectEqual(wasi.filetype_t.SYMBOLIC_LINK, descriptorTypeToFiletype(4));
    try std.testing.expectEqual(wasi.filetype_t.REGULAR_FILE, descriptorTypeToFiletype(5));
    try std.testing.expectEqual(wasi.filetype_t.SOCKET_STREAM, descriptorTypeToFiletype(6));
    try std.testing.expectEqual(wasi.filetype_t.UNKNOWN, descriptorTypeToFiletype(7));
}

test "writeFilestatFromDescriptorStat 0.3.0 layout" {
    var raw: [112]u8 align(8) = @splat(0);
    raw[0] = 0; // ok
    raw[8] = 5; // regular-file (0.3.0 index 5)
    std.mem.writeInt(u64, raw[24..32], 2, .little); // link-count
    std.mem.writeInt(u64, raw[32..40], 4096, .little); // size
    raw[40] = 1; // atim some
    std.mem.writeInt(i64, raw[48..56], 10, .little);
    std.mem.writeInt(u32, raw[56..60], 500, .little);
    raw[64] = 1; // mtim some
    std.mem.writeInt(i64, raw[72..80], 20, .little);
    std.mem.writeInt(u32, raw[80..84], 250, .little);
    raw[88] = 0; // ctim none

    var st: wasi.filestat_t = undefined;
    writeFilestatFromDescriptorStat(&raw, &st);
    try std.testing.expectEqual(wasi.filetype_t.REGULAR_FILE, st.filetype);
    try std.testing.expectEqual(@as(u64, 2), st.nlink);
    try std.testing.expectEqual(@as(u64, 4096), st.size);
    try std.testing.expectEqual(@as(u64, 10 * std.time.ns_per_s + 500), st.atim);
    try std.testing.expectEqual(@as(u64, 20 * std.time.ns_per_s + 250), st.mtim);
    try std.testing.expectEqual(@as(u64, 0), st.ctim);
}

test "canonical ABI 0.3.0 struct layouts and spilled async parameter packing" {
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(CanonString));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(CanonStringList));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(CanonEnvPair));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(CanonEnvList));
    try std.testing.expectEqual(@as(usize, 12), @sizeOf(CanonPreopenEntry));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(CanonPreopenList));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(CanonDirectoryEntry));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(CanonDirectoryEntry));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(CanonInstant));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(CanonInstant));

    const open_params = packOpenAtParams(7, 1, 0x1000, 12, 0b1001, 0b0011);
    try std.testing.expectEqual(@as(i32, 7), std.mem.readInt(i32, open_params[0..4], .little));
    try std.testing.expectEqual(@as(u8, 1), open_params[4]);
    try std.testing.expectEqual(@as(u32, 0x1000), std.mem.readInt(u32, open_params[8..12], .little));
    try std.testing.expectEqual(@as(u32, 12), std.mem.readInt(u32, open_params[12..16], .little));
    try std.testing.expectEqual(@as(u8, 0b1001), open_params[16]);
    try std.testing.expectEqual(@as(u8, 0b0011), open_params[17]);

    var ok_ret: [20]u8 align(4) = @splat(0);
    try std.testing.expectEqual(wasi.errno_t.SUCCESS, descriptorResult20ToErrno(&ok_ret));

    var err_ret: [20]u8 align(4) = @splat(0);
    err_ret[0] = 1;
    err_ret[4] = 19; // no-entry at offset 4
    try std.testing.expectEqual(wasi.errno_t.NOENT, descriptorResult20ToErrno(&err_ret));

    if (builtin.os.tag.isWasi()) {
        var n: usize = 0;
        try std.testing.expectEqual(wasi.errno_t.SPIPE, fd_pread(0, undefined, 0, 0, &n));
        try std.testing.expectEqual(wasi.errno_t.SPIPE, fd_pwrite(1, undefined, 0, 0, &n));
        try std.testing.expectEqual(wasi.errno_t.SPIPE, fd_pwrite(2, undefined, 0, 0, &n));
    }
}
