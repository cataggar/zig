//! WASI Preview 2 (0.2.6) Canonical ABI imports and Preview 1 compatibility wrappers.

const std = @import("std");
const wasi = std.os.wasi;

// ============================================================================
// Canonical ABI 0.2.6 Extern Declarations
// ============================================================================

// wasi:cli/exit@0.2.6
pub extern "wasi:cli/exit@0.2.6" fn exit(status: i32) noreturn;

// wasi:cli/stdin@0.2.6, wasi:cli/stdout@0.2.6, wasi:cli/stderr@0.2.6
pub extern "wasi:cli/stdin@0.2.6" fn @"get-stdin"() i32;
pub extern "wasi:cli/stdout@0.2.6" fn @"get-stdout"() i32;
pub extern "wasi:cli/stderr@0.2.6" fn @"get-stderr"() i32;

// wasi:cli/environment@0.2.6
pub extern "wasi:cli/environment@0.2.6" fn @"get-arguments"(ret_area: *anyopaque) void;
pub extern "wasi:cli/environment@0.2.6" fn @"get-environment"(ret_area: *anyopaque) void;
pub extern "wasi:cli/environment@0.2.6" fn @"initial-cwd"(ret_area: *anyopaque) void;

// wasi:io/error@0.2.6
pub extern "wasi:io/error@0.2.6" fn @"[resource-drop]error"(handle: i32) void;

// wasi:io/poll@0.2.6
pub extern "wasi:io/poll@0.2.6" fn @"[method]pollable.ready"(self: i32) i32;
pub extern "wasi:io/poll@0.2.6" fn @"[method]pollable.block"(self: i32) void;
pub extern "wasi:io/poll@0.2.6" fn poll(in_ptr: [*]const i32, in_len: usize, ret_area: *anyopaque) void;
pub extern "wasi:io/poll@0.2.6" fn @"[resource-drop]pollable"(handle: i32) void;

// wasi:io/streams@0.2.6
pub extern "wasi:io/streams@0.2.6" fn @"[method]input-stream.read"(self: i32, len: u64, ret_area: *anyopaque) void;
pub extern "wasi:io/streams@0.2.6" fn @"[method]input-stream.blocking-read"(self: i32, len: u64, ret_area: *anyopaque) void;
pub extern "wasi:io/streams@0.2.6" fn @"[method]input-stream.subscribe"(self: i32) i32;
pub extern "wasi:io/streams@0.2.6" fn @"[resource-drop]input-stream"(handle: i32) void;
pub extern "wasi:io/streams@0.2.6" fn @"[method]output-stream.check-write"(self: i32, ret_area: *anyopaque) void;
pub extern "wasi:io/streams@0.2.6" fn @"[method]output-stream.write"(self: i32, ptr: [*]const u8, len: usize, ret_area: *anyopaque) void;
pub extern "wasi:io/streams@0.2.6" fn @"[method]output-stream.blocking-write-and-flush"(self: i32, ptr: [*]const u8, len: usize, ret_area: *anyopaque) void;
pub extern "wasi:io/streams@0.2.6" fn @"[method]output-stream.flush"(self: i32, ret_area: *anyopaque) void;
pub extern "wasi:io/streams@0.2.6" fn @"[method]output-stream.blocking-flush"(self: i32, ret_area: *anyopaque) void;
pub extern "wasi:io/streams@0.2.6" fn @"[method]output-stream.subscribe"(self: i32) i32;
pub extern "wasi:io/streams@0.2.6" fn @"[resource-drop]output-stream"(handle: i32) void;

// wasi:clocks/monotonic-clock@0.2.6
pub const monotonic_clock = struct {
    pub extern "wasi:clocks/monotonic-clock@0.2.6" fn now() u64;
    pub extern "wasi:clocks/monotonic-clock@0.2.6" fn resolution() u64;
    pub extern "wasi:clocks/monotonic-clock@0.2.6" fn @"subscribe-instant"(when: u64) i32;
    pub extern "wasi:clocks/monotonic-clock@0.2.6" fn @"subscribe-duration"(when: u64) i32;
};
pub const @"subscribe-instant" = monotonic_clock.@"subscribe-instant";
pub const @"subscribe-duration" = monotonic_clock.@"subscribe-duration";

// wasi:clocks/wall-clock@0.2.6
pub const wall_clock = struct {
    pub extern "wasi:clocks/wall-clock@0.2.6" fn now(ret_area: *anyopaque) void;
    pub extern "wasi:clocks/wall-clock@0.2.6" fn resolution(ret_area: *anyopaque) void;
};

// wasi:random/random@0.2.6
pub extern "wasi:random/random@0.2.6" fn @"get-random-bytes"(len: u64, ret_area: *anyopaque) void;
pub extern "wasi:random/random@0.2.6" fn @"get-random-u64"() u64;

// wasi:filesystem/preopens@0.2.6
pub extern "wasi:filesystem/preopens@0.2.6" fn @"get-directories"(ret_area: *anyopaque) void;

// wasi:filesystem/types@0.2.6
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.read-via-stream"(self: i32, offset: u64, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.write-via-stream"(self: i32, offset: u64, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.append-via-stream"(self: i32, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.advise"(self: i32, offset: u64, length: u64, advice: i32, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.sync-data"(self: i32, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.get-flags"(self: i32, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.get-type"(self: i32, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.set-size"(self: i32, size: u64, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.set-times"(
    self: i32,
    atim_tag: i32,
    atim_sec: u64,
    atim_nsec: u32,
    mtim_tag: i32,
    mtim_sec: u64,
    mtim_nsec: u32,
    ret_area: *anyopaque,
) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.read"(self: i32, length: u64, offset: u64, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.write"(self: i32, buf_ptr: [*]const u8, buf_len: usize, offset: u64, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.read-directory"(self: i32, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.sync"(self: i32, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.create-directory-at"(self: i32, path_ptr: [*]const u8, path_len: usize, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.stat"(self: i32, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.stat-at"(self: i32, path_flags: u32, path_ptr: [*]const u8, path_len: usize, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.set-times-at"(
    self: i32,
    path_flags: u32,
    path_ptr: [*]const u8,
    path_len: usize,
    atim_tag: i32,
    atim_sec: u64,
    atim_nsec: u32,
    mtim_tag: i32,
    mtim_sec: u64,
    mtim_nsec: u32,
    ret_area: *anyopaque,
) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.link-at"(
    self: i32,
    old_path_flags: u32,
    old_path_ptr: [*]const u8,
    old_path_len: usize,
    new_descriptor: i32,
    new_path_ptr: [*]const u8,
    new_path_len: usize,
    ret_area: *anyopaque,
) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.open-at"(
    self: i32,
    path_flags: u32,
    path_ptr: [*]const u8,
    path_len: usize,
    open_flags: u32,
    flags: u32,
    ret_area: *anyopaque,
) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.readlink-at"(self: i32, path_ptr: [*]const u8, path_len: usize, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.remove-directory-at"(self: i32, path_ptr: [*]const u8, path_len: usize, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.rename-at"(
    self: i32,
    old_path_ptr: [*]const u8,
    old_path_len: usize,
    new_descriptor: i32,
    new_path_ptr: [*]const u8,
    new_path_len: usize,
    ret_area: *anyopaque,
) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.symlink-at"(
    self: i32,
    old_path_ptr: [*]const u8,
    old_path_len: usize,
    new_path_ptr: [*]const u8,
    new_path_len: usize,
    ret_area: *anyopaque,
) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.unlink-file-at"(self: i32, path_ptr: [*]const u8, path_len: usize, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.is-same-object"(self: i32, other: i32) i32;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.metadata-hash"(self: i32, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]descriptor.metadata-hash-at"(self: i32, path_flags: u32, path_ptr: [*]const u8, path_len: usize, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[method]directory-entry-stream.read-directory-entry"(self: i32, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"filesystem-error-code"(err: i32, ret_area: *anyopaque) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[resource-drop]descriptor"(handle: i32) void;
pub extern "wasi:filesystem/types@0.2.6" fn @"[resource-drop]directory-entry-stream"(handle: i32) void;

// ============================================================================
// Canonical ABI Return Area Structures & Helpers
// ============================================================================

pub const CanonString = extern struct {
    ptr: [*]u8,
    len: usize,
};

pub const CanonStringList = extern struct {
    ptr: [*]const CanonString,
    len: usize,
};

pub const CanonEnvPair = extern struct {
    k_ptr: [*]u8,
    k_len: usize,
    v_ptr: [*]u8,
    v_len: usize,
};

pub const CanonEnvList = extern struct {
    ptr: [*]const CanonEnvPair,
    len: usize,
};

pub const CanonPreopenEntry = extern struct {
    handle: i32,
    name_ptr: [*]const u8,
    name_len: usize,
};

pub const CanonPreopenList = extern struct {
    ptr: [*]const CanonPreopenEntry,
    len: usize,
};

pub const CanonDatetime = extern struct {
    seconds: u64,
    nanoseconds: u32,
    _pad: u32 = 0,
};

pub fn errorCodeToErrno(code: u32) wasi.errno_t {
    return switch (code) {
        0 => .ACCES, // access
        1 => .AGAIN, // would-block
        2 => .ALREADY, // already
        3 => .BADF, // bad-descriptor
        4 => .BUSY, // busy
        5 => .DEADLK, // deadlock
        6 => .DQUOT, // quota
        7 => .EXIST, // exist
        8 => .FBIG, // file-too-large
        9 => .ILSEQ, // illegal-byte-sequence
        10 => .INPROGRESS, // in-progress
        11 => .INTR, // interrupted
        12 => .INVAL, // invalid
        13 => .IO, // io
        14 => .ISDIR, // is-directory
        15 => .LOOP, // loop
        16 => .MLINK, // too-many-links
        17 => .MSGSIZE, // message-size
        18 => .NAMETOOLONG, // name-too-long
        19 => .NODEV, // no-device
        20 => .NOENT, // no-entry
        21 => .NOLCK, // no-lock
        22 => .NOMEM, // insufficient-memory
        23 => .NOSPC, // insufficient-space
        24 => .NOTDIR, // not-directory
        25 => .NOTEMPTY, // not-empty
        26 => .NOTRECOVERABLE, // not-recoverable
        27 => .OPNOTSUPP, // unsupported
        28 => .NOTTY, // no-tty
        29 => .NXIO, // no-such-device
        30 => .OVERFLOW, // overflow
        31 => .PERM, // not-permitted
        32 => .PIPE, // pipe
        33 => .ROFS, // read-only
        34 => .SPIPE, // invalid-seek
        35 => .TXTBSY, // text-file-busy
        36 => .XDEV, // cross-device
        else => .IO,
    };
}

pub fn descriptorTypeToFiletype(dtype: u8) wasi.filetype_t {
    return switch (dtype) {
        0 => .UNKNOWN, // unknown
        1 => .BLOCK_DEVICE, // block-device
        2 => .CHARACTER_DEVICE, // character-device
        3 => .DIRECTORY, // directory
        4 => .UNKNOWN, // fifo
        5 => .SYMBOLIC_LINK, // symbolic-link
        6 => .REGULAR_FILE, // regular-file
        7 => .SOCKET_STREAM, // socket
        else => .UNKNOWN,
    };
}

fn descriptorErrorOnlyResult(ret: *const [8]u8) wasi.errno_t {
    if (ret[0] == 0) return .SUCCESS;
    const code: u32 = if (ret[1] != 0) ret[1] else std.mem.readInt(u32, ret[4..8], .little);
    return errorCodeToErrno(code);
}

fn optionDatetimeToTimestamp(opt: *const [24]u8) wasi.timestamp_t {
    if (opt[0] == 0) return 0;
    const sec = std.mem.readInt(u64, opt[8..16], .little);
    const nsec = std.mem.readInt(u32, opt[16..20], .little);
    return sec *| std.time.ns_per_s +| nsec;
}

pub fn writeFilestatFromDescriptorStat(ret: *const [104]u8, buf: *wasi.filestat_t) void {
    buf.* = .{
        .dev = 0,
        .ino = 0,
        .filetype = descriptorTypeToFiletype(ret[8]),
        .nlink = std.mem.readInt(u64, ret[16..24], .little),
        .size = std.mem.readInt(u64, ret[24..32], .little),
        .atim = optionDatetimeToTimestamp(ret[32..56]),
        .mtim = optionDatetimeToTimestamp(ret[56..80]),
        .ctim = optionDatetimeToTimestamp(ret[80..104]),
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

const NewTimestamp = struct {
    tag: i32,
    sec: u64,
    nsec: u32,
};

fn decodeFstTimestamps(
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
        .sec = st_atim / std.time.ns_per_s,
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
        .sec = st_mtim / std.time.ns_per_s,
        .nsec = @intCast(st_mtim % std.time.ns_per_s),
    } else .{
        .tag = 0,
        .sec = 0,
        .nsec = 0,
    };

    return .{ .atim = atim, .mtim = mtim };
}

fn freeGuestSlice(ptr: [*]u8, len: usize) void {
    if (len > 0) {
        std.heap.wasm_allocator.free(ptr[0..len]);
    }
}

// ============================================================================
// Stdio & Descriptor Table State
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

var stdin_handle: i32 = -1;
var stdout_handle: i32 = -1;
var stderr_handle: i32 = -1;

var fd_table: [max_fds]FdEntry = @splat(.{});
var preopens_initialized: bool = false;
var preopens_count: usize = 0;

var cached_args: CanonStringList = .{ .ptr = undefined, .len = 0 };
var args_initialized: bool = false;

var cached_env: CanonEnvList = .{ .ptr = undefined, .len = 0 };
var env_initialized: bool = false;

fn getStdinHandle() i32 {
    if (stdin_handle < 0) {
        stdin_handle = @"get-stdin"();
    }
    return stdin_handle;
}

fn getStdoutHandle() i32 {
    if (stdout_handle < 0) {
        stdout_handle = @"get-stdout"();
    }
    return stdout_handle;
}

fn getStderrHandle() i32 {
    if (stderr_handle < 0) {
        stderr_handle = @"get-stderr"();
    }
    return stderr_handle;
}

fn initPreopens() void {
    if (preopens_initialized) return;
    preopens_initialized = true;

    var list: CanonPreopenList = .{ .ptr = undefined, .len = 0 };
    @"get-directories"(&list);

    const count = @min(list.len, max_fds - 3);
    preopens_count = count;
    for (0..count) |i| {
        const entry = list.ptr[i];
        fd_table[3 + i] = .{
            .in_use = true,
            .is_preopen = true,
            .append = false,
            .handle = entry.handle,
            .position = 0,
            .preopen_name_ptr = entry.name_ptr,
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
    var total_bytes: usize = 0;
    for (0..list.len) |i| {
        total_bytes += list.ptr[i].len + 1;
    }
    argc.* = list.len;
    argv_buf_size.* = total_bytes;
    return .SUCCESS;
}

pub fn args_get(argv: [*][*:0]u8, argv_buf: [*]u8) callconv(.c) wasi.errno_t {
    const list = ensureArgs();
    var buf_offset: usize = 0;
    for (0..list.len) |i| {
        const arg = list.ptr[i];
        const dst = argv_buf + buf_offset;
        if (arg.len > 0) {
            @memcpy(dst[0..arg.len], arg.ptr[0..arg.len]);
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
    var total_bytes: usize = 0;
    for (0..list.len) |i| {
        const pair = list.ptr[i];
        total_bytes += pair.k_len + 1 + pair.v_len + 1;
    }
    environ_count.* = list.len;
    environ_buf_size.* = total_bytes;
    return .SUCCESS;
}

pub fn environ_get(environ: [*][*:0]u8, environ_buf: [*]u8) callconv(.c) wasi.errno_t {
    const list = ensureEnv();
    var buf_offset: usize = 0;
    for (0..list.len) |i| {
        const pair = list.ptr[i];
        const dst = environ_buf + buf_offset;
        if (pair.k_len > 0) {
            @memcpy(dst[0..pair.k_len], pair.k_ptr[0..pair.k_len]);
        }
        dst[pair.k_len] = '=';
        if (pair.v_len > 0) {
            @memcpy(dst[pair.k_len + 1 ..][0..pair.v_len], pair.v_ptr[0..pair.v_len]);
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
            var dt: CanonDatetime = .{ .seconds = 0, .nanoseconds = 0 };
            wall_clock.resolution(&dt);
            resolution.* = dt.seconds *| std.time.ns_per_s +| dt.nanoseconds;
            return .SUCCESS;
        },
        .MONOTONIC => {
            resolution.* = monotonic_clock.resolution();
            return .SUCCESS;
        },
        else => return .INVAL,
    }
}

pub fn clock_time_get(clock_id: wasi.clockid_t, precision: wasi.timestamp_t, timestamp: *wasi.timestamp_t) callconv(.c) wasi.errno_t {
    _ = precision;
    switch (clock_id) {
        .REALTIME => {
            var dt: CanonDatetime = .{ .seconds = 0, .nanoseconds = 0 };
            wall_clock.now(&dt);
            timestamp.* = dt.seconds *| std.time.ns_per_s +| dt.nanoseconds;
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
    var ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.advise"(entry.handle, offset, len, @backingInt(advice), &ret);
    return descriptorErrorOnlyResult(&ret);
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
    var ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.sync-data"(entry.handle, &ret);
    return descriptorErrorOnlyResult(&ret);
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

    var type_ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.get-type"(entry.handle, &type_ret);
    if (type_ret[0] != 0) return errorCodeToErrno(type_ret[1]);
    const filetype = descriptorTypeToFiletype(type_ret[1]);

    var flags_ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.get-flags"(entry.handle, &flags_ret);
    if (flags_ret[0] != 0) return errorCodeToErrno(flags_ret[1]);
    const dflags = flags_ret[1];

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
    var ret: [104]u8 align(8) = @splat(0);
    @"[method]descriptor.stat"(entry.handle, &ret);
    if (ret[0] != 0) return errorCodeToErrno(ret[8]);
    writeFilestatFromDescriptorStat(&ret, buf);

    var hash_ret: [24]u8 align(8) = @splat(0);
    @"[method]descriptor.metadata-hash"(entry.handle, &hash_ret);
    if (hash_ret[0] == 0) {
        const lower = std.mem.readInt(u64, hash_ret[8..16], .little);
        const upper = std.mem.readInt(u64, hash_ret[16..24], .little);
        buf.dev = upper;
        buf.ino = lower;
    }
    return .SUCCESS;
}

pub fn fd_filestat_set_size(fd: wasi.fd_t, st_size: wasi.filesize_t) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    var ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.set-size"(entry.handle, st_size, &ret);
    return descriptorErrorOnlyResult(&ret);
}

pub fn fd_filestat_set_times(
    fd: wasi.fd_t,
    st_atim: wasi.timestamp_t,
    st_mtim: wasi.timestamp_t,
    fstflags: wasi.fstflags_t,
) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    const ts = decodeFstTimestamps(st_atim, st_mtim, fstflags) orelse return .INVAL;
    var ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.set-times"(
        entry.handle,
        ts.atim.tag,
        ts.atim.sec,
        ts.atim.nsec,
        ts.mtim.tag,
        ts.mtim.sec,
        ts.mtim.nsec,
        &ret,
    );
    return descriptorErrorOnlyResult(&ret);
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

    var stream_ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.read-via-stream"(entry.handle, offset, &stream_ret);
    if (stream_ret[0] != 0) return errorCodeToErrno(stream_ret[4]);
    const stream = std.mem.readInt(i32, stream_ret[4..8], .little);
    defer @"[resource-drop]input-stream"(stream);

    var total: usize = 0;
    for (0..iovs_len) |i| {
        const iov = iovs[i];
        if (iov.len == 0) continue;

        var read_ret: [12]u8 align(4) = @splat(0);
        @"[method]input-stream.blocking-read"(stream, iov.len, &read_ret);
        if (read_ret[0] != 0) {
            if (read_ret[4] == 1) break; // stream-error::closed (EOF)
            @"[resource-drop]error"(std.mem.readInt(i32, read_ret[8..12], .little));
            nread.* = total;
            return .IO;
        }

        const ptr_addr = std.mem.readInt(usize, read_ret[4..8], .little);
        const len = std.mem.readInt(usize, read_ret[8..12], .little);
        const copy_len = @min(len, iov.len);
        if (copy_len > 0) {
            const ptr: [*]u8 = @ptrFromInt(ptr_addr);
            @memcpy(iov.base[0..copy_len], ptr[0..copy_len]);
        }
        if (len > 0) {
            freeGuestSlice(@ptrFromInt(ptr_addr), len);
        }
        total += copy_len;
        if (copy_len < iov.len) break;
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

fn writeOutputStreamIovs(stream: i32, iovs: [*]const wasi.ciovec_t, iovs_len: usize, nwritten: *usize) wasi.errno_t {
    var total: usize = 0;
    for (0..iovs_len) |i| {
        const iov = iovs[i];
        var off: usize = 0;
        while (off < iov.len) {
            const chunk = @min(iov.len - off, 4096);
            var write_ret: [12]u8 align(4) = @splat(0);
            @"[method]output-stream.blocking-write-and-flush"(stream, iov.base + off, chunk, &write_ret);
            if (write_ret[0] != 0) {
                if (write_ret[4] == 0) {
                    @"[resource-drop]error"(std.mem.readInt(i32, write_ret[8..12], .little));
                }
                nwritten.* = total;
                return if (write_ret[4] == 1) .PIPE else .IO;
            }
            off += chunk;
            total += chunk;
        }
    }
    nwritten.* = total;
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

    var stream_ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.write-via-stream"(entry.handle, offset, &stream_ret);
    if (stream_ret[0] != 0) return errorCodeToErrno(stream_ret[4]);
    const stream = std.mem.readInt(i32, stream_ret[4..8], .little);
    defer @"[resource-drop]output-stream"(stream);

    return writeOutputStreamIovs(stream, iovs, iovs_len, nwritten);
}

pub fn fd_read(
    fd: wasi.fd_t,
    iovs: [*]const wasi.iovec_t,
    iovs_len: usize,
    nread: *usize,
) callconv(.c) wasi.errno_t {
    nread.* = 0;
    if (fd == 0) {
        const stream = getStdinHandle();
        for (0..iovs_len) |i| {
            const iov = iovs[i];
            if (iov.len == 0) continue;

            var read_ret: [12]u8 align(4) = @splat(0);
            @"[method]input-stream.blocking-read"(stream, iov.len, &read_ret);
            if (read_ret[0] != 0) {
                if (read_ret[4] == 1) return .SUCCESS; // stream-error::closed (EOF)
                @"[resource-drop]error"(std.mem.readInt(i32, read_ret[8..12], .little));
                return .IO;
            }

            const ptr_addr = std.mem.readInt(usize, read_ret[4..8], .little);
            const len = std.mem.readInt(usize, read_ret[8..12], .little);
            const copy_len = @min(len, iov.len);
            if (copy_len > 0) {
                const ptr: [*]u8 = @ptrFromInt(ptr_addr);
                @memcpy(iov.base[0..copy_len], ptr[0..copy_len]);
            }
            if (len > 0) {
                freeGuestSlice(@ptrFromInt(ptr_addr), len);
            }
            nread.* = copy_len;
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

    var stream_ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.read-directory"(entry.handle, &stream_ret);
    if (stream_ret[0] != 0) return errorCodeToErrno(stream_ret[4]);
    const stream = std.mem.readInt(i32, stream_ret[4..8], .little);
    defer @"[resource-drop]directory-entry-stream"(stream);

    var idx: u64 = 0;
    var used: usize = 0;
    while (true) {
        var entry_ret: [20]u8 align(4) = @splat(0);
        @"[method]directory-entry-stream.read-directory-entry"(stream, &entry_ret);
        if (entry_ret[0] != 0) {
            return errorCodeToErrno(entry_ret[4]);
        }
        if (entry_ret[4] == 0) break; // option::none

        const dtype = entry_ret[8];
        const name_addr = std.mem.readInt(usize, entry_ret[12..16], .little);
        const name_len = std.mem.readInt(usize, entry_ret[16..20], .little);
        defer if (name_len > 0) freeGuestSlice(@ptrFromInt(name_addr), name_len);

        if (idx < cookie) {
            idx += 1;
            continue;
        }

        const name_ptr: [*]const u8 = @ptrFromInt(name_addr);
        var d_ino: u64 = 0;
        var hash_ret: [24]u8 align(8) = @splat(0);
        @"[method]descriptor.metadata-hash-at"(entry.handle, 0, name_ptr, name_len, &hash_ret);
        if (hash_ret[0] == 0) {
            d_ino = std.mem.readInt(u64, hash_ret[8..16], .little);
        }

        var dirent_bytes: [24]u8 = @splat(0);
        std.mem.writeInt(u64, dirent_bytes[0..8], idx + 1, .little);
        std.mem.writeInt(u64, dirent_bytes[8..16], d_ino, .little);
        std.mem.writeInt(u32, dirent_bytes[16..20], @intCast(name_len), .little);
        dirent_bytes[20] = @backingInt(descriptorTypeToFiletype(dtype));

        const copy_hdr = @min(dirent_bytes.len, buf_len - used);
        if (copy_hdr > 0) {
            @memcpy(buf[used..][0..copy_hdr], dirent_bytes[0..copy_hdr]);
            used += copy_hdr;
        }

        const copy_name = @min(name_len, buf_len - used);
        if (copy_name > 0) {
            @memcpy(buf[used..][0..copy_name], name_ptr[0..copy_name]);
            used += copy_name;
        }

        idx += 1;
        if (used == buf_len) break;
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
            var stat_ret: [104]u8 align(8) = @splat(0);
            @"[method]descriptor.stat"(entry.handle, &stat_ret);
            if (stat_ret[0] != 0) return errorCodeToErrno(stat_ret[8]);
            break :blk @intCast(std.mem.readInt(u64, stat_ret[24..32], .little));
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
    var ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.sync"(entry.handle, &ret);
    return descriptorErrorOnlyResult(&ret);
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
        const stream = if (fd == 1) getStdoutHandle() else getStderrHandle();
        return writeOutputStreamIovs(stream, iovs, iovs_len, nwritten);
    }

    const entry = getFdEntry(fd) orelse return .BADF;
    if (entry.append) {
        var stream_ret: [8]u8 align(4) = @splat(0);
        @"[method]descriptor.append-via-stream"(entry.handle, &stream_ret);
        if (stream_ret[0] != 0) return errorCodeToErrno(stream_ret[4]);
        const stream = std.mem.readInt(i32, stream_ret[4..8], .little);
        defer @"[resource-drop]output-stream"(stream);

        const err = writeOutputStreamIovs(stream, iovs, iovs_len, nwritten);
        if (err == .SUCCESS) {
            var stat_ret: [104]u8 align(8) = @splat(0);
            @"[method]descriptor.stat"(entry.handle, &stat_ret);
            if (stat_ret[0] == 0) {
                entry.position = std.mem.readInt(u64, stat_ret[24..32], .little);
            } else {
                entry.position += nwritten.*;
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
    var ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.create-directory-at"(entry.handle, path, path_len, &ret);
    return descriptorErrorOnlyResult(&ret);
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
    var ret: [104]u8 align(8) = @splat(0);
    @"[method]descriptor.stat-at"(entry.handle, path_flags, path, path_len, &ret);
    if (ret[0] != 0) return errorCodeToErrno(ret[8]);
    writeFilestatFromDescriptorStat(&ret, buf);

    var hash_ret: [24]u8 align(8) = @splat(0);
    @"[method]descriptor.metadata-hash-at"(entry.handle, path_flags, path, path_len, &hash_ret);
    if (hash_ret[0] == 0) {
        const lower = std.mem.readInt(u64, hash_ret[8..16], .little);
        const upper = std.mem.readInt(u64, hash_ret[16..24], .little);
        buf.dev = upper;
        buf.ino = lower;
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
    var ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.set-times-at"(
        entry.handle,
        path_flags,
        path,
        path_len,
        ts.atim.tag,
        ts.atim.sec,
        ts.atim.nsec,
        ts.mtim.tag,
        ts.mtim.sec,
        ts.mtim.nsec,
        &ret,
    );
    return descriptorErrorOnlyResult(&ret);
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
    var ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.link-at"(
        old_entry.handle,
        path_flags,
        old_path,
        old_path_len,
        new_entry.handle,
        new_path,
        new_path_len,
        &ret,
    );
    return descriptorErrorOnlyResult(&ret);
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

    var ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.open-at"(
        dir_entry.handle,
        path_flags,
        path,
        path_len,
        open_flags,
        desc_flags,
        &ret,
    );
    if (ret[0] != 0 and (desc_flags & 32) != 0) {
        var fallback_flags = desc_flags & ~@as(u32, 32);
        if (fallback_flags == 0) fallback_flags = 1;
        ret = @splat(0);
        @"[method]descriptor.open-at"(
            dir_entry.handle,
            path_flags,
            path,
            path_len,
            open_flags,
            fallback_flags,
            &ret,
        );
    }
    if (ret[0] != 0) return errorCodeToErrno(ret[4]);

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
    var ret: [12]u8 align(4) = @splat(0);
    @"[method]descriptor.readlink-at"(entry.handle, path, path_len, &ret);
    if (ret[0] != 0) return errorCodeToErrno(ret[4]);

    const ptr_addr = std.mem.readInt(usize, ret[4..8], .little);
    const len = std.mem.readInt(usize, ret[8..12], .little);
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
    var ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.remove-directory-at"(entry.handle, path, path_len, &ret);
    return descriptorErrorOnlyResult(&ret);
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
    var ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.rename-at"(
        old_entry.handle,
        old_path,
        old_path_len,
        new_entry.handle,
        new_path,
        new_path_len,
        &ret,
    );
    return descriptorErrorOnlyResult(&ret);
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
    var ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.symlink-at"(entry.handle, old_path, old_path_len, new_path, new_path_len, &ret);
    return descriptorErrorOnlyResult(&ret);
}

pub fn path_unlink_file(fd: wasi.fd_t, path: [*]const u8, path_len: usize) callconv(.c) wasi.errno_t {
    const entry = getFdEntry(fd) orelse return .BADF;
    if (!std.unicode.utf8ValidateSlice(path[0..path_len])) return .ILSEQ;
    var ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.unlink-file-at"(entry.handle, path, path_len, &ret);
    return descriptorErrorOnlyResult(&ret);
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
                const pollable: i32 = if (is_abstime and clock_sub.id == .MONOTONIC)
                    @"subscribe-instant"(clock_sub.timeout)
                else
                    @"subscribe-duration"(clock_sub.timeout);
                @"[method]pollable.block"(pollable);
                @"[resource-drop]pollable"(pollable);

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
    exit(if (rval == 0) 0 else 1);
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
    const entry = getFdEntry(sock) orelse return .BADF;
    var type_ret: [8]u8 align(4) = @splat(0);
    @"[method]descriptor.get-type"(entry.handle, &type_ret);
    if (type_ret[0] != 0) return errorCodeToErrno(type_ret[1]);
    if (type_ret[1] != 7) return .NOTSOCK;
    return .OPNOTSUPP;
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

test "errorCodeToErrno mapping" {
    try std.testing.expectEqual(wasi.errno_t.ACCES, errorCodeToErrno(0));
    try std.testing.expectEqual(wasi.errno_t.AGAIN, errorCodeToErrno(1));
    try std.testing.expectEqual(wasi.errno_t.BADF, errorCodeToErrno(3));
    try std.testing.expectEqual(wasi.errno_t.EXIST, errorCodeToErrno(7));
    try std.testing.expectEqual(wasi.errno_t.INVAL, errorCodeToErrno(12));
    try std.testing.expectEqual(wasi.errno_t.IO, errorCodeToErrno(13));
    try std.testing.expectEqual(wasi.errno_t.ISDIR, errorCodeToErrno(14));
    try std.testing.expectEqual(wasi.errno_t.NOENT, errorCodeToErrno(20));
    try std.testing.expectEqual(wasi.errno_t.NOTDIR, errorCodeToErrno(24));
    try std.testing.expectEqual(wasi.errno_t.NOTEMPTY, errorCodeToErrno(25));
    try std.testing.expectEqual(wasi.errno_t.OPNOTSUPP, errorCodeToErrno(27));
    try std.testing.expectEqual(wasi.errno_t.PERM, errorCodeToErrno(31));
    try std.testing.expectEqual(wasi.errno_t.PIPE, errorCodeToErrno(32));
    try std.testing.expectEqual(wasi.errno_t.ROFS, errorCodeToErrno(33));
    try std.testing.expectEqual(wasi.errno_t.SPIPE, errorCodeToErrno(34));
    try std.testing.expectEqual(wasi.errno_t.XDEV, errorCodeToErrno(36));
    try std.testing.expectEqual(wasi.errno_t.IO, errorCodeToErrno(99));
}

test "descriptorTypeToFiletype mapping" {
    try std.testing.expectEqual(wasi.filetype_t.UNKNOWN, descriptorTypeToFiletype(0));
    try std.testing.expectEqual(wasi.filetype_t.BLOCK_DEVICE, descriptorTypeToFiletype(1));
    try std.testing.expectEqual(wasi.filetype_t.CHARACTER_DEVICE, descriptorTypeToFiletype(2));
    try std.testing.expectEqual(wasi.filetype_t.DIRECTORY, descriptorTypeToFiletype(3));
    try std.testing.expectEqual(wasi.filetype_t.SYMBOLIC_LINK, descriptorTypeToFiletype(5));
    try std.testing.expectEqual(wasi.filetype_t.REGULAR_FILE, descriptorTypeToFiletype(6));
    try std.testing.expectEqual(wasi.filetype_t.SOCKET_STREAM, descriptorTypeToFiletype(7));
}

test "flag translations" {
    try std.testing.expectEqual(@as(u32, 0), translateLookupFlags(.{}));
    try std.testing.expectEqual(@as(u32, 1), translateLookupFlags(.{ .SYMLINK_FOLLOW = true }));

    try std.testing.expectEqual(@as(u32, 0b1111), translateOpenFlags(.{
        .CREAT = true,
        .DIRECTORY = true,
        .EXCL = true,
        .TRUNC = true,
    }));

    try std.testing.expectEqual(@as(u32, 1), translateDescriptorFlags(.{}, .{}, .{}));
    try std.testing.expectEqual(@as(u32, 3), translateDescriptorFlags(.{ .FD_READ = true, .FD_WRITE = true }, .{}, .{}));
    try std.testing.expectEqual(@as(u32, 2 | 4 | 8 | 16), translateDescriptorFlags(
        .{ .FD_WRITE = true },
        .{},
        .{ .SYNC = true, .DSYNC = true, .RSYNC = true },
    ));
    try std.testing.expectEqual(@as(u32, 1 | 32), translateDescriptorFlags(
        .{ .FD_READDIR = true, .PATH_CREATE_FILE = true },
        .{ .DIRECTORY = true },
        .{},
    ));
}

test "writeFilestatFromDescriptorStat layout" {
    var raw: [104]u8 align(8) = @splat(0);
    raw[0] = 0; // ok
    raw[8] = 6; // regular-file
    std.mem.writeInt(u64, raw[16..24], 2, .little); // link-count
    std.mem.writeInt(u64, raw[24..32], 4096, .little); // size
    raw[32] = 1; // atim some
    std.mem.writeInt(u64, raw[40..48], 10, .little);
    std.mem.writeInt(u32, raw[48..52], 500, .little);
    raw[56] = 1; // mtim some
    std.mem.writeInt(u64, raw[64..72], 20, .little);
    std.mem.writeInt(u32, raw[72..76], 250, .little);
    raw[80] = 0; // ctim none

    var st: wasi.filestat_t = undefined;
    writeFilestatFromDescriptorStat(&raw, &st);
    try std.testing.expectEqual(wasi.filetype_t.REGULAR_FILE, st.filetype);
    try std.testing.expectEqual(@as(u64, 2), st.nlink);
    try std.testing.expectEqual(@as(u64, 4096), st.size);
    try std.testing.expectEqual(@as(u64, 10 * std.time.ns_per_s + 500), st.atim);
    try std.testing.expectEqual(@as(u64, 20 * std.time.ns_per_s + 250), st.mtim);
    try std.testing.expectEqual(@as(u64, 0), st.ctim);
}

test "canonical ABI struct layouts and timestamp decoding" {
    if (@sizeOf(usize) == 4) {
        try std.testing.expectEqual(@as(usize, 8), @sizeOf(CanonString));
        try std.testing.expectEqual(@as(usize, 8), @sizeOf(CanonStringList));
        try std.testing.expectEqual(@as(usize, 16), @sizeOf(CanonEnvPair));
        try std.testing.expectEqual(@as(usize, 8), @sizeOf(CanonEnvList));
        try std.testing.expectEqual(@as(usize, 12), @sizeOf(CanonPreopenEntry));
        try std.testing.expectEqual(@as(usize, 8), @sizeOf(CanonPreopenList));
    }
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(CanonDatetime));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(CanonDatetime));

    try std.testing.expect(decodeFstTimestamps(0, 0, .{ .ATIM = true, .ATIM_NOW = true }) == null);
    try std.testing.expect(decodeFstTimestamps(0, 0, .{ .MTIM = true, .MTIM_NOW = true }) == null);

    const decoded = decodeFstTimestamps(
        3 * std.time.ns_per_s + 42,
        0,
        .{ .ATIM = true, .MTIM_NOW = true },
    ).?;
    try std.testing.expectEqual(@as(i32, 2), decoded.atim.tag);
    try std.testing.expectEqual(@as(u64, 3), decoded.atim.sec);
    try std.testing.expectEqual(@as(u32, 42), decoded.atim.nsec);
    try std.testing.expectEqual(@as(i32, 1), decoded.mtim.tag);

    var ok_ret: [8]u8 align(4) = @splat(0);
    try std.testing.expectEqual(wasi.errno_t.SUCCESS, descriptorErrorOnlyResult(&ok_ret));

    var err_ret_canon: [8]u8 align(4) = @splat(0);
    err_ret_canon[0] = 1;
    err_ret_canon[1] = 20; // no-entry at offset 1
    try std.testing.expectEqual(wasi.errno_t.NOENT, descriptorErrorOnlyResult(&err_ret_canon));

    var n: usize = 0;
    try std.testing.expectEqual(wasi.errno_t.SPIPE, fd_pread(0, undefined, 0, 0, &n));
    try std.testing.expectEqual(wasi.errno_t.SPIPE, fd_pwrite(1, undefined, 0, 0, &n));
    try std.testing.expectEqual(wasi.errno_t.SPIPE, fd_pwrite(2, undefined, 0, 0, &n));
}
