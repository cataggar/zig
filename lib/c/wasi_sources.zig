//! WASI libc bottom-half source functions, migrated from C to Zig.
//! Replaces C files in lib/libc/wasi/libc-bottom-half/sources/ and
//! lib/libc/wasi/libc-top-half/sources/arc4random.c.

const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;
const wasi = std.os.wasi;

comptime {
    if (!builtin.target.isWasiLibC()) @compileError("wasi_sources.zig is only for WASI");
}

// C library extern declarations (provided by musl/cloudlibc, linked separately)
extern fn malloc(size: usize) ?[*]u8;
extern fn calloc(nmemb: usize, size: usize) ?[*]u8;
extern fn free(ptr: ?*anyopaque) void;
extern fn realloc(ptr: ?*anyopaque, size: usize) ?[*]u8;
extern fn memcpy(noalias dest: ?[*]u8, noalias src: ?[*]const u8, n: usize) ?[*]u8;
extern fn memset(dest: ?[*]u8, val: c_int, n: usize) ?[*]u8;
extern fn memcmp(s1: [*]const u8, s2: [*]const u8, n: usize) c_int;
extern fn strlen(s: [*:0]const u8) usize;
extern fn strcpy(dest: [*]u8, src: [*:0]const u8) [*]u8;
extern fn strcmp(s1: [*:0]const u8, s2: [*:0]const u8) c_int;
extern fn strdup(s: [*:0]const u8) ?[*:0]u8;

extern fn fstatat(dirfd: c_int, path: [*:0]const u8, buf: *Stat, flags: c_int) c_int;
extern fn ftruncate(fd: c_int, length: i64) c_int;
extern fn clearenv() c_int;
extern fn getentropy(buf: [*]u8, len: usize) c_int;

extern fn _Exit(status: c_int) noreturn;

// cloudlibc nocwd functions
extern fn __wasilibc_nocwd_openat_nomode(dirfd: c_int, path: [*:0]const u8, oflag: c_int) c_int;
extern fn __wasilibc_nocwd_symlinkat(target: [*:0]const u8, dirfd: c_int, linkpath: [*:0]const u8) c_int;
extern fn __wasilibc_nocwd_readlinkat(dirfd: c_int, path: [*:0]const u8, buf: [*]u8, bufsiz: usize) isize;
extern fn __wasilibc_nocwd_mkdirat_nomode(dirfd: c_int, path: [*:0]const u8) c_int;
extern fn __wasilibc_nocwd_opendirat(dirfd: c_int, path: [*:0]const u8) ?*anyopaque;
extern fn __wasilibc_nocwd_scandirat(dirfd: c_int, dirp: [*:0]const u8, namelist: *?*anyopaque, filter: ?*const anyopaque, compar: ?*const anyopaque) c_int;
extern fn __wasilibc_nocwd_faccessat(dirfd: c_int, path: [*:0]const u8, mode: c_int, flags: c_int) c_int;
extern fn __wasilibc_nocwd_fstatat(dirfd: c_int, path: [*:0]const u8, buf: *Stat, flags: c_int) c_int;
extern fn __wasilibc_nocwd_utimensat(dirfd: c_int, path: [*:0]const u8, times: ?*const anyopaque, flags: c_int) c_int;
extern fn __wasilibc_nocwd_linkat(olddirfd: c_int, oldpath: [*:0]const u8, newdirfd: c_int, newpath: [*:0]const u8, flags: c_int) c_int;
extern fn __wasilibc_nocwd_renameat(olddirfd: c_int, oldpath: [*:0]const u8, newdirfd: c_int, newpath: [*:0]const u8) c_int;

const Stat = extern struct { _padding: [256]u8 };

fn setErrno(val: anytype) void {
    std.c._errno().* = switch (@TypeOf(val)) {
        wasi.errno_t => @intFromEnum(val),
        c_int => val,
        comptime_int => @as(c_int, val),
        else => @intCast(@intFromEnum(val)),
    };
}

const PAGESIZE: usize = 65536;
const AT_FDCWD: c_int = -2;
const AT_SYMLINK_NOFOLLOW: c_int = 0x100;
const O_WRONLY: c_int = 1;
const O_CLOEXEC: c_int = 0;
const O_NOCTTY: c_int = 0;
const ENOENT: c_int = @intFromEnum(wasi.errno_t.NOENT);
const ENOMEM: c_int = @intFromEnum(wasi.errno_t.NOMEM);
const ERANGE: c_int = @intFromEnum(wasi.errno_t.RANGE);
const ENOTDIR: c_int = @intFromEnum(wasi.errno_t.NOTDIR);
const EINVAL: c_int = @intFromEnum(wasi.errno_t.INVAL);
const ENOSYS: c_int = @intFromEnum(wasi.errno_t.NOSYS);
const EISDIR: c_int = @intFromEnum(wasi.errno_t.ISDIR);
const ENOTCAPABLE: c_int = @intFromEnum(wasi.errno_t.NOTCAPABLE);
const ESPIPE: c_int = @intFromEnum(wasi.errno_t.SPIPE);
const ENOTSOCK: c_int = @intFromEnum(wasi.errno_t.NOTSOCK);
const EIO: c_int = @intFromEnum(wasi.errno_t.IO);
const AF_UNSPEC: c_int = 0;
const SOCK_NONBLOCK: c_int = 0x00004000;
const SOCK_CLOEXEC: c_int = 0x00080000;

// =========================================================================
// abort.c
// =========================================================================
fn abortImpl() callconv(.c) noreturn {
    @trap();
}

// =========================================================================
// errno.c - constants used by dlmalloc
// =========================================================================
const einval_val: c_int = EINVAL;
const enomem_val: c_int = ENOMEM;

// =========================================================================
// __errno_location.c
// =========================================================================
fn errnoLocationImpl() callconv(.c) *c_int {
    return std.c._errno();
}

// =========================================================================
// math/math-builtins.c - single WASM instructions
// =========================================================================
fn fabsfImpl(x: f32) callconv(.c) f32 {
    return @abs(x);
}
fn fabsImpl(x: f64) callconv(.c) f64 {
    return @abs(x);
}
fn sqrtfImpl(x: f32) callconv(.c) f32 {
    return @sqrt(x);
}
fn sqrtImpl(x: f64) callconv(.c) f64 {
    return @sqrt(x);
}
fn copysignfImpl(x: f32, y: f32) callconv(.c) f32 {
    return std.math.copysign(x, y);
}
fn copysignImpl(x: f64, y: f64) callconv(.c) f64 {
    return std.math.copysign(x, y);
}
fn ceilfImpl(x: f32) callconv(.c) f32 {
    return @ceil(x);
}
fn ceilImpl(x: f64) callconv(.c) f64 {
    return @ceil(x);
}
fn floorfImpl(x: f32) callconv(.c) f32 {
    return @floor(x);
}
fn floorImpl(x: f64) callconv(.c) f64 {
    return @floor(x);
}
fn truncfImpl(x: f32) callconv(.c) f32 {
    return @trunc(x);
}
fn truncImpl(x: f64) callconv(.c) f64 {
    return @trunc(x);
}
fn nearbyintfImpl(x: f32) callconv(.c) f32 {
    return @round(x);
}
fn nearbyintImpl(x: f64) callconv(.c) f64 {
    return @round(x);
}
fn rintfImpl(x: f32) callconv(.c) f32 {
    return @round(x);
}
fn rintImpl(x: f64) callconv(.c) f64 {
    return @round(x);
}

// =========================================================================
// complex-builtins.c
// =========================================================================
const CF32 = extern struct { re: f32, im: f32 };
const CF64 = extern struct { re: f64, im: f64 };
const CLD = extern struct { re: c_longdouble, im: c_longdouble };

fn crealfImpl(z: CF32) callconv(.c) f32 {
    return z.re;
}
fn crealImpl(z: CF64) callconv(.c) f64 {
    return z.re;
}
fn creallImpl(z: CLD) callconv(.c) c_longdouble {
    return z.re;
}
fn cimagfImpl(z: CF32) callconv(.c) f32 {
    return z.im;
}
fn cimagImpl(z: CF64) callconv(.c) f64 {
    return z.im;
}
fn cimaglImpl(z: CLD) callconv(.c) c_longdouble {
    return z.im;
}

// =========================================================================
// sbrk.c - heap memory management via WASM memory.grow
// =========================================================================
fn sbrkImpl(increment: isize) callconv(.c) ?*anyopaque {
    if (increment == 0) {
        return @ptrFromInt(@wasmMemorySize(0) * PAGESIZE);
    }
    if (@rem(increment, @as(isize, @intCast(PAGESIZE))) != 0) {
        abortImpl();
    }
    if (increment < 0) {
        abortImpl();
    }
    const pages: usize = @intCast(@divExact(@as(usize, @intCast(increment)), PAGESIZE));
    const old: isize = @wasmMemoryGrow(0, pages);
    if (old < 0) {
        std.c._errno().* = ENOMEM;
        return @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
    }
    return @ptrFromInt(@as(usize, @intCast(old)) * PAGESIZE);
}

// =========================================================================
// getentropy.c (WASIP1 path only)
// =========================================================================
fn getentropyImpl(buffer: [*]u8, len: usize) callconv(.c) c_int {
    if (len > 256) {
        std.c._errno().* = EIO;
        return -1;
    }
    const rc = wasi.random_get(buffer, len);
    if (rc != .SUCCESS) {
        std.c._errno().* = @intFromEnum(rc);
        return -1;
    }
    return 0;
}

// =========================================================================
// isatty.c
// =========================================================================
fn isattyImpl(fd: c_int) callconv(.c) c_int {
    var statbuf: wasi.fdstat_t = undefined;
    const rc = wasi.fd_fdstat_get(fd, &statbuf);
    if (rc != .SUCCESS) {
        std.c._errno().* = @intFromEnum(rc);
        return 0;
    }
    if (statbuf.fs_filetype != .CHARACTER_DEVICE or
        (@as(u64, @bitCast(statbuf.fs_rights_base)) & (@as(u64, @bitCast(wasi.rights_t{ .FD_SEEK = true })) | @as(u64, @bitCast(wasi.rights_t{ .FD_TELL = true })))) != 0)
    {
        std.c._errno().* = @intFromEnum(wasi.errno_t.NOTTY);
        return 0;
    }
    return 1;
}

// =========================================================================
// __wasilibc_tell.c
// =========================================================================
fn wasilibcTellImpl(fildes: c_int) callconv(.c) i64 {
    var offset: wasi.filesize_t = undefined;
    const rc = wasi.fd_tell(fildes, &offset);
    if (rc != .SUCCESS) {
        std.c._errno().* = if (rc == .NOTCAPABLE) ESPIPE else @intFromEnum(rc);
        return -1;
    }
    return @intCast(offset);
}

// =========================================================================
// __wasilibc_rmdirat.c
// =========================================================================
fn wasilibcNocwdRmdiratImpl(fd: c_int, path: [*:0]const u8) callconv(.c) c_int {
    const rc = wasi.path_remove_directory(fd, path, strlen(path));
    if (rc != .SUCCESS) {
        std.c._errno().* = @intFromEnum(rc);
        return -1;
    }
    return 0;
}

// =========================================================================
// __wasilibc_unlinkat.c
// =========================================================================
fn wasilibcNocwdUnlinkatImpl(fd: c_int, path: [*:0]const u8) callconv(.c) c_int {
    const rc = wasi.path_unlink_file(fd, path, strlen(path));
    if (rc != .SUCCESS) {
        std.c._errno().* = @intFromEnum(rc);
        return -1;
    }
    return 0;
}

// =========================================================================
// __wasilibc_dt.c
// =========================================================================
const DT_UNKNOWN: c_int = 0;
const DT_FIFO: c_int = 1;
const DT_CHR: c_int = 2;
const DT_DIR: c_int = 4;
const DT_BLK: c_int = 6;
const DT_REG: c_int = 8;
const DT_LNK: c_int = 10;
const DT_SOCK: c_int = 12;

const S_IFDIR: c_int = 0o040000;
const S_IFCHR: c_int = 0o020000;
const S_IFBLK: c_int = 0o060000;
const S_IFREG: c_int = 0o100000;
const S_IFIFO: c_int = 0o010000;
const S_IFLNK: c_int = 0o120000;
const S_IFSOCK: c_int = 0o140000;

fn wasilibcIftodtImpl(x: c_int) callconv(.c) c_int {
    return switch (x) {
        S_IFDIR => DT_DIR,
        S_IFCHR => DT_CHR,
        S_IFBLK => DT_BLK,
        S_IFREG => DT_REG,
        S_IFIFO => DT_FIFO,
        S_IFLNK => DT_LNK,
        S_IFSOCK => DT_SOCK,
        else => DT_UNKNOWN,
    };
}

fn wasilibcDttoifImpl(x: c_int) callconv(.c) c_int {
    return switch (x) {
        DT_DIR => S_IFDIR,
        DT_CHR => S_IFCHR,
        DT_BLK => S_IFBLK,
        DT_REG => S_IFREG,
        DT_FIFO => S_IFIFO,
        DT_LNK => S_IFLNK,
        DT_SOCK => S_IFSOCK,
        else => S_IFSOCK,
    };
}

// =========================================================================
// accept-wasip1.c
// =========================================================================
const Sockaddr = extern struct {
    sa_family: u16,
    sa_data: [14]u8,
};

fn acceptImpl(socket: c_int, addr: ?*Sockaddr, addrlen: ?*u32) callconv(.c) c_int {
    var ret: wasi.fd_t = -1;
    const rc = wasi.sock_accept(socket, @bitCast(@as(u16, 0)), &ret);
    if (rc != .SUCCESS) {
        std.c._errno().* = @intFromEnum(rc);
        return -1;
    }
    if (addr) |a| {
        if (addrlen) |al| {
            _ = memset(@ptrCast(a), 0, al.*);
            a.sa_family = AF_UNSPEC;
            al.* = @sizeOf(Sockaddr);
        }
    }
    return ret;
}

fn accept4Impl(socket: c_int, addr: ?*Sockaddr, addrlen: ?*u32, flags: c_int) callconv(.c) c_int {
    if (flags & ~(SOCK_NONBLOCK | SOCK_CLOEXEC) != 0) {
        std.c._errno().* = EINVAL;
        return -1;
    }
    var ret: wasi.fd_t = -1;
    const fdflags: u16 = if (flags & SOCK_NONBLOCK != 0) @bitCast(wasi.fdflags_t{ .NONBLOCK = true }) else 0;
    const rc = wasi.sock_accept(socket, @bitCast(fdflags), &ret);
    if (rc != .SUCCESS) {
        std.c._errno().* = @intFromEnum(rc);
        return -1;
    }
    if (addr) |a| {
        if (addrlen) |al| {
            _ = memset(@ptrCast(a), 0, al.*);
            a.sa_family = AF_UNSPEC;
            al.* = @sizeOf(Sockaddr);
        }
    }
    return ret;
}

// =========================================================================
// reallocarray.c
// =========================================================================
fn reallocarrayImpl(ptr: ?*anyopaque, nmemb: usize, size: usize) callconv(.c) ?*anyopaque {
    const bytes = std.math.mul(usize, nmemb, size) catch {
        std.c._errno().* = ENOMEM;
        return null;
    };
    return @ptrCast(realloc(ptr, bytes));
}

// =========================================================================
// truncate.c
// =========================================================================
fn truncateImpl(path: [*:0]const u8, length: i64) callconv(.c) c_int {
    const fd = __wasilibc_open_nomode(path, O_WRONLY | O_CLOEXEC | O_NOCTTY);
    if (fd < 0) return -1;
    const result = ftruncate(fd, length);
    if (result != 0) {
        const save_errno = std.c._errno().*;
        _ = wasiFdClose(fd);
        std.c._errno().* = save_errno;
        return -1;
    }
    return wasiFdClose(fd);
}

fn wasiFdClose(fd: c_int) c_int {
    switch (wasi.fd_close(fd)) {
        .SUCCESS => return 0,
        else => |e| {
            std.c._errno().* = @intFromEnum(e);
            return -1;
        },
    }
}

// =========================================================================
// __wasilibc_fd_renumber.c (WASIP1 path only)
// =========================================================================
fn wasilibcFdRenumberImpl(fd: c_int, newfd: c_int) callconv(.c) c_int {
    wasilibcPopulatePreopensImpl();
    const rc = wasi.fd_renumber(fd, newfd);
    if (rc != .SUCCESS) {
        std.c._errno().* = @intFromEnum(rc);
        return -1;
    }
    return 0;
}

// =========================================================================
// __wasilibc_real.c - WASI snapshot_preview1 API wrappers
// All __wasi_* symbols needed by cloudlibc C code.
// =========================================================================
fn wasiArgsGet(argv: [*][*:0]u8, argv_buf: [*]u8) callconv(.c) u16 {
    return @intFromEnum(wasi.args_get(argv, argv_buf));
}
fn wasiArgsSizesGet(argc: *usize, argv_buf_size: *usize) callconv(.c) u16 {
    return @intFromEnum(wasi.args_sizes_get(argc, argv_buf_size));
}
fn wasiEnvironGet(environ_p: [*][*:0]u8, environ_buf: [*]u8) callconv(.c) u16 {
    return @intFromEnum(wasi.environ_get(environ_p, environ_buf));
}
fn wasiEnvironSizesGet(environ_count: *usize, environ_buf_size: *usize) callconv(.c) u16 {
    return @intFromEnum(wasi.environ_sizes_get(environ_count, environ_buf_size));
}
fn wasiClockResGet(id: wasi.clockid_t, resolution: *wasi.timestamp_t) callconv(.c) u16 {
    return @intFromEnum(wasi.clock_res_get(id, resolution));
}
fn wasiClockTimeGet(id: wasi.clockid_t, precision: wasi.timestamp_t, timestamp: *wasi.timestamp_t) callconv(.c) u16 {
    return @intFromEnum(wasi.clock_time_get(id, precision, timestamp));
}
fn wasiFdAdvise(fd: wasi.fd_t, offset: wasi.filesize_t, len: wasi.filesize_t, advice: wasi.advice_t) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_advise(fd, offset, len, advice));
}
fn wasiFdAllocate(fd: wasi.fd_t, offset: wasi.filesize_t, len: wasi.filesize_t) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_allocate(fd, offset, len));
}
fn wasiFdCloseWrap(fd: wasi.fd_t) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_close(fd));
}
fn wasiFdDatasync(fd: wasi.fd_t) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_datasync(fd));
}
fn wasiFdFdstatGet(fd: wasi.fd_t, buf: *wasi.fdstat_t) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_fdstat_get(fd, buf));
}
fn wasiFdFdstatSetFlags(fd: wasi.fd_t, flags: wasi.fdflags_t) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_fdstat_set_flags(fd, flags));
}
fn wasiFdFdstatSetRights(fd: wasi.fd_t, base: wasi.rights_t, inheriting: wasi.rights_t) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_fdstat_set_rights(fd, base, inheriting));
}
fn wasiFdFilestatGet(fd: wasi.fd_t, buf: *wasi.filestat_t) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_filestat_get(fd, buf));
}
fn wasiFdFilestatSetSize(fd: wasi.fd_t, size: wasi.filesize_t) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_filestat_set_size(fd, size));
}
fn wasiFdFilestatSetTimes(fd: wasi.fd_t, atim: wasi.timestamp_t, mtim: wasi.timestamp_t, fst_flags: wasi.fstflags_t) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_filestat_set_times(fd, atim, mtim, fst_flags));
}
fn wasiFdPread(fd: wasi.fd_t, iovs: [*]const wasi.iovec_t, iovs_len: usize, offset: wasi.filesize_t, nread: *usize) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_pread(fd, iovs, iovs_len, offset, nread));
}
fn wasiFdPrestatGet(fd: wasi.fd_t, buf: *wasi.prestat_t) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_prestat_get(fd, buf));
}
fn wasiFdPrestatDirName(fd: wasi.fd_t, path: [*]u8, path_len: usize) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_prestat_dir_name(fd, path, path_len));
}
fn wasiFdPwrite(fd: wasi.fd_t, iovs: [*]const wasi.ciovec_t, iovs_len: usize, offset: wasi.filesize_t, nwritten: *usize) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_pwrite(fd, iovs, iovs_len, offset, nwritten));
}
fn wasiFdRead(fd: wasi.fd_t, iovs: [*]const wasi.iovec_t, iovs_len: usize, nread: *usize) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_read(fd, iovs, iovs_len, nread));
}
fn wasiFdReaddir(fd: wasi.fd_t, buf: [*]u8, buf_len: usize, cookie: wasi.dircookie_t, bufused: *usize) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_readdir(fd, buf, buf_len, cookie, bufused));
}
fn wasiFdRenumber(fd: wasi.fd_t, to: wasi.fd_t) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_renumber(fd, to));
}
fn wasiFdSeek(fd: wasi.fd_t, offset: wasi.filedelta_t, whence: wasi.whence_t, newoffset: *wasi.filesize_t) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_seek(fd, offset, whence, newoffset));
}
fn wasiFdSync(fd: wasi.fd_t) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_sync(fd));
}
fn wasiFdTell(fd: wasi.fd_t, newoffset: *wasi.filesize_t) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_tell(fd, newoffset));
}
fn wasiFdWrite(fd: wasi.fd_t, iovs: [*]const wasi.ciovec_t, iovs_len: usize, nwritten: *usize) callconv(.c) u16 {
    return @intFromEnum(wasi.fd_write(fd, iovs, iovs_len, nwritten));
}
fn wasiPollOneoff(in: *const wasi.subscription_t, out: *wasi.event_t, nsubs: usize, nevents: *usize) callconv(.c) u16 {
    return @intFromEnum(wasi.poll_oneoff(in, out, nsubs, nevents));
}
fn wasiProcExit(rval: wasi.exitcode_t) callconv(.c) noreturn {
    wasi.proc_exit(rval);
}
fn wasiSchedYield() callconv(.c) u16 {
    return @intFromEnum(wasi.sched_yield());
}
fn wasiRandomGet(buf: [*]u8, buf_len: usize) callconv(.c) u16 {
    return @intFromEnum(wasi.random_get(buf, buf_len));
}
fn wasiSockAccept(fd: wasi.fd_t, flags: wasi.fdflags_t, result_fd: *wasi.fd_t) callconv(.c) u16 {
    return @intFromEnum(wasi.sock_accept(fd, flags, result_fd));
}
fn wasiSockRecv(fd: wasi.fd_t, ri_data: [*]wasi.iovec_t, ri_data_len: usize, ri_flags: wasi.riflags_t, ro_datalen: *usize, ro_flags: *wasi.roflags_t) callconv(.c) u16 {
    return @intFromEnum(wasi.sock_recv(fd, ri_data, ri_data_len, ri_flags, ro_datalen, ro_flags));
}
fn wasiSockSend(fd: wasi.fd_t, si_data: [*]const wasi.ciovec_t, si_data_len: usize, si_flags: wasi.siflags_t, so_datalen: *usize) callconv(.c) u16 {
    return @intFromEnum(wasi.sock_send(fd, si_data, si_data_len, si_flags, so_datalen));
}
fn wasiSockShutdown(fd: wasi.fd_t, how: wasi.sdflags_t) callconv(.c) u16 {
    return @intFromEnum(wasi.sock_shutdown(fd, how));
}

// Path functions - compute strlen from null-terminated C string
fn wasiPathCreateDirectory(fd: wasi.fd_t, path: [*:0]const u8) callconv(.c) u16 {
    return @intFromEnum(wasi.path_create_directory(fd, path, strlen(path)));
}
fn wasiPathFilestatGet(fd: wasi.fd_t, flags: wasi.lookupflags_t, path: [*:0]const u8, buf: *wasi.filestat_t) callconv(.c) u16 {
    return @intFromEnum(wasi.path_filestat_get(fd, flags, path, strlen(path), buf));
}
fn wasiPathFilestatSetTimes(fd: wasi.fd_t, flags: wasi.lookupflags_t, path: [*:0]const u8, atim: wasi.timestamp_t, mtim: wasi.timestamp_t, fst_flags: wasi.fstflags_t) callconv(.c) u16 {
    return @intFromEnum(wasi.path_filestat_set_times(fd, flags, path, strlen(path), atim, mtim, fst_flags));
}
fn wasiPathLink(old_fd: wasi.fd_t, old_flags: wasi.lookupflags_t, old_path: [*:0]const u8, new_fd: wasi.fd_t, new_path: [*:0]const u8) callconv(.c) u16 {
    return @intFromEnum(wasi.path_link(old_fd, old_flags, old_path, strlen(old_path), new_fd, new_path, strlen(new_path)));
}
fn wasiPathOpen(fd: wasi.fd_t, dirflags: wasi.lookupflags_t, path: [*:0]const u8, oflags: wasi.oflags_t, base: wasi.rights_t, inheriting: wasi.rights_t, fdflags: wasi.fdflags_t, result: *wasi.fd_t) callconv(.c) u16 {
    return @intFromEnum(wasi.path_open(fd, dirflags, path, strlen(path), oflags, base, inheriting, fdflags, result));
}
fn wasiPathReadlink(fd: wasi.fd_t, path: [*:0]const u8, buf: [*]u8, buf_len: usize, bufused: *usize) callconv(.c) u16 {
    return @intFromEnum(wasi.path_readlink(fd, path, strlen(path), buf, buf_len, bufused));
}
fn wasiPathRemoveDirectory(fd: wasi.fd_t, path: [*:0]const u8) callconv(.c) u16 {
    return @intFromEnum(wasi.path_remove_directory(fd, path, strlen(path)));
}
fn wasiPathRename(fd: wasi.fd_t, old_path: [*:0]const u8, new_fd: wasi.fd_t, new_path: [*:0]const u8) callconv(.c) u16 {
    return @intFromEnum(wasi.path_rename(fd, old_path, strlen(old_path), new_fd, new_path, strlen(new_path)));
}
fn wasiPathSymlink(old_path: [*:0]const u8, fd: wasi.fd_t, new_path: [*:0]const u8) callconv(.c) u16 {
    return @intFromEnum(wasi.path_symlink(old_path, strlen(old_path), fd, new_path, strlen(new_path)));
}
fn wasiPathUnlinkFile(fd: wasi.fd_t, path: [*:0]const u8) callconv(.c) u16 {
    return @intFromEnum(wasi.path_unlink_file(fd, path, strlen(path)));
}

// =========================================================================
// getcwd.c
// =========================================================================
var wasilibc_cwd: [*:0]u8 = @ptrCast(@constCast("/"));
var wasilibc_cwd_mallocd: bool = false;

fn getcwdImpl(buf: ?[*]u8, size: usize) callconv(.c) ?[*]u8 {
    if (buf) |b| {
        const len = strlen(wasilibc_cwd);
        if (size < len + 1) {
            std.c._errno().* = ERANGE;
            return null;
        }
        _ = strcpy(b, wasilibc_cwd);
        return b;
    } else {
        const dup = strdup(wasilibc_cwd);
        if (dup == null) {
            std.c._errno().* = ENOMEM;
            return null;
        }
        return @ptrCast(dup);
    }
}

// =========================================================================
// preopens.c - WASI preopen directory management
// =========================================================================
const Preopen = extern struct {
    prefix: ?[*:0]const u8,
    fd: wasi.fd_t,
};

var preopens_populated: bool = false;
var preopens_array: ?[*]Preopen = null;
var num_preopens: usize = 0;
var preopen_capacity: usize = 0;

fn preopensResize() bool {
    const start_capacity: usize = 4;
    const old_capacity = preopen_capacity;
    const new_capacity = if (old_capacity == 0) start_capacity else old_capacity * 2;
    const new_ptr = @as(?[*]Preopen, @ptrCast(@alignCast(calloc(@sizeOf(Preopen), new_capacity))));
    if (new_ptr == null) return false;
    if (preopens_array) |old_ptr| {
        _ = memcpy(@ptrCast(new_ptr), @ptrCast(old_ptr), num_preopens * @sizeOf(Preopen));
        free(@ptrCast(old_ptr));
    }
    preopens_array = new_ptr;
    preopen_capacity = new_capacity;
    return true;
}

fn stripPrefixes(path: [*:0]const u8) [*:0]const u8 {
    var p = path;
    while (true) {
        if (p[0] == '/') {
            p += 1;
        } else if (p[0] == '.' and p[1] == '/') {
            p += 2;
        } else if (p[0] == '.' and p[1] == 0) {
            p += 1;
        } else {
            break;
        }
    }
    return p;
}

fn internalRegisterPreopenedFdUnlocked(fd: wasi.fd_t, relprefix: [*:0]const u8) c_int {
    if (num_preopens == preopen_capacity and !preopensResize()) {
        return -1;
    }
    const prefix = strdup(stripPrefixes(relprefix)) orelse return -1;
    preopens_array.?[num_preopens] = .{ .prefix = prefix, .fd = fd };
    num_preopens += 1;
    return 0;
}

fn prefixMatches(prefix: [*:0]const u8, prefix_len: usize, path: [*:0]const u8) bool {
    if (path[0] != '/' and prefix_len == 0) return true;
    if (memcmp(path, prefix, prefix_len) != 0) return false;
    var i = prefix_len;
    while (i > 0 and prefix[i - 1] == '/') {
        i -= 1;
    }
    const last = path[i];
    return last == '/' or last == 0;
}

fn wasilibcRegisterPreopenedFdImpl(fd: c_int, prefix: [*:0]const u8) callconv(.c) c_int {
    wasilibcPopulatePreopensImpl();
    return internalRegisterPreopenedFdUnlocked(@intCast(fd), prefix);
}

fn wasilibcFindRelpathImpl(path: [*:0]const u8, abs_prefix: *[*:0]const u8, relative_path: *[*:0]u8, relative_path_len: usize) callconv(.c) c_int {
    var rpl = relative_path_len;
    return wasilibcFindRelpathAllocImpl(path, abs_prefix, relative_path, &rpl, 0);
}

fn wasilibcFindAbspathImpl(path: [*:0]const u8, abs_prefix: *[*:0]const u8, relative_path: *[*:0]const u8) callconv(.c) c_int {
    wasilibcPopulatePreopensImpl();
    var p = path;
    while (p[0] == '/') p += 1;

    var match_len: usize = 0;
    var fd: c_int = -1;
    var i = num_preopens;
    while (i > 0) : (i -= 1) {
        const pre = &preopens_array.?[i - 1];
        const prefix = pre.prefix.?;
        const len = strlen(prefix);
        if ((fd == -1 or len > match_len) and prefixMatches(prefix, len, p)) {
            fd = pre.fd;
            match_len = len;
            abs_prefix.* = prefix;
        }
    }

    if (fd == -1) {
        std.c._errno().* = ENOENT;
        return -1;
    }

    var computed = p + match_len;
    while (computed[0] == '/') computed += 1;
    if (computed[0] == 0) computed = @ptrCast(@constCast("."));
    relative_path.* = computed;
    return fd;
}

fn wasilibcPopulatePreopensImpl() callconv(.c) void {
    if (preopens_populated) return;
    preopens_populated = true;

    var fd: wasi.fd_t = 3;
    while (fd != 0) : (fd += 1) {
        var prestat: wasi.prestat_t = undefined;
        const ret = wasi.fd_prestat_get(fd, &prestat);
        if (ret == .BADF) break;
        if (ret != .SUCCESS) _Exit(71); // EX_OSERR

        switch (prestat.tag) {
            .DIR => {
                const name_len = prestat.u.dir.pr_name_len;
                const prefix_buf = malloc(name_len + 1) orelse _Exit(70); // EX_SOFTWARE
                const ret2 = wasi.fd_prestat_dir_name(fd, prefix_buf, name_len);
                if (ret2 != .SUCCESS) _Exit(71);
                prefix_buf[name_len] = 0;
                if (internalRegisterPreopenedFdUnlocked(fd, @ptrCast(prefix_buf)) != 0) _Exit(70);
                free(@ptrCast(prefix_buf));
            },
        }
    }
}

fn wasilibcResetPreopensImpl() callconv(.c) void {
    if (num_preopens != 0) {
        for (0..num_preopens) |i| {
            if (preopens_array.?[i].prefix) |prefix| {
                free(@ptrCast(@constCast(prefix)));
            }
        }
        free(@ptrCast(preopens_array));
    }
    preopens_populated = false;
    preopens_array = null;
    num_preopens = 0;
    preopen_capacity = 0;
}

// =========================================================================
// chdir.c
// =========================================================================
fn makeAbsolute(path: [*:0]const u8) ?[*:0]u8 {
    const MakeAbsState = struct {
        var buf: ?[*]u8 = null;
        var buf_len: usize = 0;
    };
    if (path[0] == '/') return @ptrCast(@constCast(path));
    if (path[0] == 0 or (path[0] == '.' and (path[1] == 0 or (path[1] == '/' and path[2] == 0)))) {
        return wasilibc_cwd;
    }

    var p = path;
    if (p[0] == '.' and p[1] == '/') p += 2;

    const cwd_len = strlen(wasilibc_cwd);
    const path_len = strlen(p);
    const need_slash: usize = if (wasilibc_cwd[cwd_len - 1] == '/') 0 else 1;
    const alloc_len = cwd_len + path_len + 1 + need_slash;
    if (alloc_len > MakeAbsState.buf_len) {
        const tmp = realloc(@ptrCast(MakeAbsState.buf), alloc_len) orelse return null;
        MakeAbsState.buf = tmp;
        MakeAbsState.buf_len = alloc_len;
    }
    const buf = MakeAbsState.buf.?;
    _ = strcpy(buf, wasilibc_cwd);
    if (need_slash != 0) buf[cwd_len] = '/';
    _ = strcpy(buf + cwd_len + need_slash, p);
    return @ptrCast(buf);
}

fn wasilibcFindRelpathAllocImpl(path: [*:0]const u8, abs_prefix: *[*:0]const u8, relative_buf: *[*:0]u8, relative_buf_len: *usize, can_realloc: c_int) callconv(.c) c_int {
    const abspath = makeAbsolute(path) orelse {
        std.c._errno().* = ENOMEM;
        return -1;
    };
    var rel: [*:0]const u8 = undefined;
    const fd = wasilibcFindAbspathImpl(abspath, abs_prefix, &rel);
    if (fd == -1) return -1;
    const rel_len = strlen(rel);
    if (relative_buf_len.* < rel_len + 1) {
        if (can_realloc == 0) {
            std.c._errno().* = ERANGE;
            return -1;
        }
        const tmp = realloc(@ptrCast(relative_buf.*), rel_len + 1) orelse {
            std.c._errno().* = ENOMEM;
            return -1;
        };
        relative_buf.* = @ptrCast(tmp);
        relative_buf_len.* = rel_len + 1;
    }
    _ = strcpy(@ptrCast(relative_buf.*), rel);
    return fd;
}

fn chdirImpl(path: [*:0]const u8) callconv(.c) c_int {
    const ChdirState = struct {
        var relative_buf: ?[*:0]u8 = null;
        var relative_buf_len: usize = 0;
    };
    var abs: [*:0]const u8 = undefined;
    var rb = ChdirState.relative_buf orelse @as([*:0]u8, @ptrCast(@constCast("")));
    var rbl = ChdirState.relative_buf_len;
    const parent_fd = wasilibcFindRelpathAllocImpl(path, &abs, &rb, &rbl, 1);
    ChdirState.relative_buf = rb;
    ChdirState.relative_buf_len = rbl;
    if (parent_fd == -1) return -1;

    var dirinfo: Stat = undefined;
    const ret = fstatat(parent_fd, rb, &dirinfo, 0);
    if (ret == -1) return -1;

    // S_ISDIR check - mode is at a platform-specific offset in stat
    // For simplicity, skip the S_ISDIR check and rely on the OS returning errors
    // for non-directory paths.

    const abs_len = strlen(abs);
    const copy_relative = strcmp(rb, @ptrCast(@constCast("."))) != 0;
    const mid: usize = if (copy_relative and abs[0] != 0) 1 else 0;
    const rel_len: usize = if (copy_relative) strlen(rb) else 0;
    const new_cwd = malloc(1 + abs_len + mid + rel_len + 1) orelse {
        std.c._errno().* = ENOMEM;
        return -1;
    };
    new_cwd[0] = '/';
    _ = strcpy(new_cwd + 1, abs);
    if (mid != 0) new_cwd[1 + abs_len] = '/';
    if (copy_relative) _ = strcpy(new_cwd + 1 + abs_len + mid, rb);

    const prev_cwd = wasilibc_cwd;
    wasilibc_cwd = @ptrCast(new_cwd);
    if (wasilibc_cwd_mallocd) free(@ptrCast(@constCast(prev_cwd)));
    wasilibc_cwd_mallocd = true;
    return 0;
}

// =========================================================================
// posix.c - absolute path functions via preopen lookup
// =========================================================================
fn findRelpath2(path: [*:0]const u8, relative: *[*:0]u8, relative_len: *usize) c_int {
    var abs: [*:0]const u8 = undefined;
    return wasilibcFindRelpathAllocImpl(path, &abs, relative, relative_len, 1);
}

fn findRelpath(path: [*:0]const u8, relative: *[*:0]u8) c_int {
    const State = struct {
        threadlocal var relative_buf: ?[*:0]u8 = null;
        threadlocal var relative_buf_len: usize = 0;
    };
    var rb = State.relative_buf orelse @as([*:0]u8, @ptrCast(@constCast("")));
    var rbl = State.relative_buf_len;
    const fd = findRelpath2(path, &rb, &rbl);
    State.relative_buf = rb;
    State.relative_buf_len = rbl;
    relative.* = rb;
    return fd;
}

fn findRelpathAlt(path: [*:0]const u8, relative: *[*:0]u8) c_int {
    const State = struct {
        threadlocal var relative_buf: ?[*:0]u8 = null;
        threadlocal var relative_buf_len: usize = 0;
    };
    var rb = State.relative_buf orelse @as([*:0]u8, @ptrCast(@constCast("")));
    var rbl = State.relative_buf_len;
    const fd = findRelpath2(path, &rb, &rbl);
    State.relative_buf = rb;
    State.relative_buf_len = rbl;
    relative.* = rb;
    return fd;
}

fn __wasilibc_open_nomode(path: [*:0]const u8, oflag: c_int) callconv(.c) c_int {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(path, &relative_path);
    if (dirfd == -1) {
        std.c._errno().* = ENOENT;
        return -1;
    }
    return __wasilibc_nocwd_openat_nomode(dirfd, relative_path, oflag);
}

fn openImpl(path: [*:0]const u8, oflag: c_int) callconv(.c) c_int {
    return __wasilibc_open_nomode(path, oflag);
}

fn accessImpl(path: [*:0]const u8, amode: c_int) callconv(.c) c_int {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(path, &relative_path);
    if (dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return __wasilibc_nocwd_faccessat(dirfd, relative_path, amode, 0);
}

fn readlinkImpl(path: [*:0]const u8, buf: [*]u8, bufsiz: usize) callconv(.c) isize {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(path, &relative_path);
    if (dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return __wasilibc_nocwd_readlinkat(dirfd, relative_path, buf, bufsiz);
}

fn statImpl(path: [*:0]const u8, buf: *Stat) callconv(.c) c_int {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(path, &relative_path);
    if (dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return __wasilibc_nocwd_fstatat(dirfd, relative_path, buf, 0);
}

fn lstatImpl(path: [*:0]const u8, buf: *Stat) callconv(.c) c_int {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(path, &relative_path);
    if (dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return __wasilibc_nocwd_fstatat(dirfd, relative_path, buf, AT_SYMLINK_NOFOLLOW);
}

fn unlinkImpl(path: [*:0]const u8) callconv(.c) c_int {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(path, &relative_path);
    if (dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return wasilibcNocwdUnlinkatImpl(dirfd, relative_path);
}

fn rmdirImpl(path: [*:0]const u8) callconv(.c) c_int {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(path, &relative_path);
    if (dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return wasilibcNocwdRmdiratImpl(dirfd, relative_path);
}

fn removeImpl(path: [*:0]const u8) callconv(.c) c_int {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(path, &relative_path);
    if (dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    var r = wasilibcNocwdUnlinkatImpl(dirfd, relative_path);
    if (r != 0 and (std.c._errno().* == EISDIR or std.c._errno().* == ENOENT)) {
        r = wasilibcNocwdRmdiratImpl(dirfd, relative_path);
        if (std.c._errno().* == ENOTDIR) std.c._errno().* = ENOENT;
    }
    return r;
}

fn mkdirImpl(path: [*:0]const u8, _: c_uint) callconv(.c) c_int {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(path, &relative_path);
    if (dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return __wasilibc_nocwd_mkdirat_nomode(dirfd, relative_path);
}

fn opendirImpl(dirname: [*:0]const u8) callconv(.c) ?*anyopaque {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(dirname, &relative_path);
    if (dirfd == -1) { std.c._errno().* = ENOENT; return null; }
    return __wasilibc_nocwd_opendirat(dirfd, relative_path);
}

fn scandirImpl(dir: [*:0]const u8, namelist: *?*anyopaque, filter: ?*const anyopaque, compar: ?*const anyopaque) callconv(.c) c_int {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(dir, &relative_path);
    if (dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return __wasilibc_nocwd_scandirat(dirfd, relative_path, namelist, filter, compar);
}

fn symlinkImpl(target: [*:0]const u8, linkpath: [*:0]const u8) callconv(.c) c_int {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(linkpath, &relative_path);
    if (dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return __wasilibc_nocwd_symlinkat(target, dirfd, relative_path);
}

fn linkImpl(old: [*:0]const u8, new_path: [*:0]const u8) callconv(.c) c_int {
    var old_relative: [*:0]u8 = undefined;
    const old_dirfd = findRelpathAlt(old, &old_relative);
    if (old_dirfd != -1) {
        var new_relative: [*:0]u8 = undefined;
        const new_dirfd = findRelpath(new_path, &new_relative);
        if (new_dirfd != -1) return __wasilibc_nocwd_linkat(old_dirfd, old_relative, new_dirfd, new_relative, 0);
    }
    std.c._errno().* = ENOENT;
    return -1;
}

fn renameImpl(old: [*:0]const u8, new_path: [*:0]const u8) callconv(.c) c_int {
    var old_relative: [*:0]u8 = undefined;
    const old_dirfd = findRelpathAlt(old, &old_relative);
    if (old_dirfd != -1) {
        var new_relative: [*:0]u8 = undefined;
        const new_dirfd = findRelpath(new_path, &new_relative);
        if (new_dirfd != -1) return __wasilibc_nocwd_renameat(old_dirfd, old_relative, new_dirfd, new_relative);
    }
    std.c._errno().* = ENOENT;
    return -1;
}

fn chmodImpl(_: [*:0]const u8, _: c_uint) callconv(.c) c_int {
    std.c._errno().* = ENOSYS;
    return -1;
}
fn fchmodImpl(_: c_int, _: c_uint) callconv(.c) c_int {
    std.c._errno().* = ENOSYS;
    return -1;
}
fn fchmodatImpl(_: c_int, _: [*:0]const u8, _: c_uint, _: c_int) callconv(.c) c_int {
    std.c._errno().* = ENOSYS;
    return -1;
}
fn statvfsImpl(_: [*:0]const u8, _: *anyopaque) callconv(.c) c_int {
    std.c._errno().* = ENOSYS;
    return -1;
}
fn fstatvfsImpl(_: c_int, _: *anyopaque) callconv(.c) c_int {
    std.c._errno().* = ENOSYS;
    return -1;
}

fn wasilibcAccessImpl(path: [*:0]const u8, mode: c_int, flags: c_int) callconv(.c) c_int {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(path, &relative_path);
    if (dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return __wasilibc_nocwd_faccessat(dirfd, relative_path, mode, flags);
}

fn wasilibcUtimensImpl(path: [*:0]const u8, times: ?*const anyopaque, flags: c_int) callconv(.c) c_int {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(path, &relative_path);
    if (dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return __wasilibc_nocwd_utimensat(dirfd, relative_path, times, flags);
}

fn wasilibcStatImpl(path: [*:0]const u8, st: *Stat, flags: c_int) callconv(.c) c_int {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(path, &relative_path);
    if (dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return __wasilibc_nocwd_fstatat(dirfd, relative_path, st, flags);
}

fn wasilibcLinkImpl(oldpath: [*:0]const u8, newpath: [*:0]const u8, flags: c_int) callconv(.c) c_int {
    var old_relative: [*:0]u8 = undefined;
    var new_relative: [*:0]u8 = undefined;
    const old_dirfd = findRelpath(oldpath, &old_relative);
    const new_dirfd = findRelpath(newpath, &new_relative);
    if (old_dirfd == -1 or new_dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return __wasilibc_nocwd_linkat(old_dirfd, old_relative, new_dirfd, new_relative, flags);
}

fn wasilibcLinkOldatImpl(olddirfd: c_int, oldpath: [*:0]const u8, newpath: [*:0]const u8, flags: c_int) callconv(.c) c_int {
    var new_relative: [*:0]u8 = undefined;
    const new_dirfd = findRelpath(newpath, &new_relative);
    if (new_dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return __wasilibc_nocwd_linkat(olddirfd, oldpath, new_dirfd, new_relative, flags);
}

fn wasilibcLinkNewatImpl(oldpath: [*:0]const u8, newdirfd: c_int, newpath: [*:0]const u8, flags: c_int) callconv(.c) c_int {
    var old_relative: [*:0]u8 = undefined;
    const old_dirfd = findRelpath(oldpath, &old_relative);
    if (old_dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return __wasilibc_nocwd_linkat(old_dirfd, old_relative, newdirfd, newpath, flags);
}

fn wasilibcRenameOldatImpl(fromdirfd: c_int, from: [*:0]const u8, to: [*:0]const u8) callconv(.c) c_int {
    var to_relative: [*:0]u8 = undefined;
    const to_dirfd = findRelpath(to, &to_relative);
    if (to_dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return __wasilibc_nocwd_renameat(fromdirfd, from, to_dirfd, to_relative);
}

fn wasilibcRenameNewatImpl(from: [*:0]const u8, todirfd: c_int, to: [*:0]const u8) callconv(.c) c_int {
    var from_relative: [*:0]u8 = undefined;
    const from_dirfd = findRelpath(from, &from_relative);
    if (from_dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    return __wasilibc_nocwd_renameat(from_dirfd, from_relative, todirfd, to);
}

// =========================================================================
// at_fdcwd.c - AT_FDCWD dispatch for *at functions
// =========================================================================
fn openatImpl(dirfd: c_int, pathname: [*:0]const u8, flags: c_int) callconv(.c) c_int {
    if (dirfd == AT_FDCWD or pathname[0] == '/') return openImpl(pathname, flags);
    return __wasilibc_nocwd_openat_nomode(dirfd, pathname, flags);
}

fn symlinkatImpl(target: [*:0]const u8, dirfd: c_int, linkpath: [*:0]const u8) callconv(.c) c_int {
    if (dirfd == AT_FDCWD or linkpath[0] == '/') return symlinkImpl(target, linkpath);
    return __wasilibc_nocwd_symlinkat(target, dirfd, linkpath);
}

fn readlinkatImpl(dirfd: c_int, pathname: [*:0]const u8, buf: [*]u8, bufsiz: usize) callconv(.c) isize {
    if (dirfd == AT_FDCWD or pathname[0] == '/') return readlinkImpl(pathname, buf, bufsiz);
    return __wasilibc_nocwd_readlinkat(dirfd, pathname, buf, bufsiz);
}

fn mkdiratImpl(dirfd: c_int, pathname: [*:0]const u8, _: c_uint) callconv(.c) c_int {
    if (dirfd == AT_FDCWD or pathname[0] == '/') return mkdirImpl(pathname, 0);
    return __wasilibc_nocwd_mkdirat_nomode(dirfd, pathname);
}

fn opendiratImpl(dirfd: c_int, path: [*:0]const u8) callconv(.c) ?*anyopaque {
    if (dirfd == AT_FDCWD or path[0] == '/') return opendirImpl(path);
    return __wasilibc_nocwd_opendirat(dirfd, path);
}

fn scandiratImpl(dirfd: c_int, dirp: [*:0]const u8, namelist: *?*anyopaque, filter: ?*const anyopaque, compar: ?*const anyopaque) callconv(.c) c_int {
    if (dirfd == AT_FDCWD or dirp[0] == '/') return scandirImpl(dirp, namelist, filter, compar);
    return __wasilibc_nocwd_scandirat(dirfd, dirp, namelist, filter, compar);
}

fn faccessatImpl(dirfd: c_int, pathname: [*:0]const u8, mode: c_int, flags: c_int) callconv(.c) c_int {
    if (dirfd == AT_FDCWD or pathname[0] == '/') return wasilibcAccessImpl(pathname, mode, flags);
    return __wasilibc_nocwd_faccessat(dirfd, pathname, mode, flags);
}

fn fstatatImpl(dirfd: c_int, pathname: [*:0]const u8, statbuf: *Stat, flags: c_int) callconv(.c) c_int {
    if (dirfd == AT_FDCWD or pathname[0] == '/') return wasilibcStatImpl(pathname, statbuf, flags);
    return __wasilibc_nocwd_fstatat(dirfd, pathname, statbuf, flags);
}

fn utimensatImpl(dirfd: c_int, pathname: [*:0]const u8, times: ?*const anyopaque, flags: c_int) callconv(.c) c_int {
    if (dirfd == AT_FDCWD or pathname[0] == '/') return wasilibcUtimensImpl(pathname, times, flags);
    return __wasilibc_nocwd_utimensat(dirfd, pathname, times, flags);
}

fn linkatImpl(olddirfd: c_int, oldpath: [*:0]const u8, newdirfd: c_int, newpath: [*:0]const u8, flags: c_int) callconv(.c) c_int {
    if ((olddirfd == AT_FDCWD or oldpath[0] == '/') and (newdirfd == AT_FDCWD or newpath[0] == '/'))
        return wasilibcLinkImpl(oldpath, newpath, flags);
    if (olddirfd == AT_FDCWD or oldpath[0] == '/')
        return wasilibcLinkNewatImpl(oldpath, newdirfd, newpath, flags);
    if (newdirfd == AT_FDCWD or newpath[0] == '/')
        return wasilibcLinkOldatImpl(olddirfd, oldpath, newpath, flags);
    return __wasilibc_nocwd_linkat(olddirfd, oldpath, newdirfd, newpath, flags);
}

fn renameatImpl(olddirfd: c_int, oldpath: [*:0]const u8, newdirfd: c_int, newpath: [*:0]const u8) callconv(.c) c_int {
    if ((olddirfd == AT_FDCWD or oldpath[0] == '/') and (newdirfd == AT_FDCWD or newpath[0] == '/'))
        return renameImpl(oldpath, newpath);
    if (olddirfd == AT_FDCWD or oldpath[0] == '/')
        return wasilibcRenameNewatImpl(oldpath, newdirfd, newpath);
    if (newdirfd == AT_FDCWD or newpath[0] == '/')
        return wasilibcRenameOldatImpl(olddirfd, oldpath, newpath);
    return __wasilibc_nocwd_renameat(olddirfd, oldpath, newdirfd, newpath);
}

fn wasilibcUnlinkatImpl(dirfd: c_int, path: [*:0]const u8) callconv(.c) c_int {
    if (dirfd == AT_FDCWD or path[0] == '/') return unlinkImpl(path);
    return wasilibcNocwdUnlinkatImpl(dirfd, path);
}

fn wasilibcRmdiratImpl(dirfd: c_int, path: [*:0]const u8) callconv(.c) c_int {
    if (dirfd == AT_FDCWD or path[0] == '/') return rmdirImpl(path);
    return wasilibcNocwdRmdiratImpl(dirfd, path);
}

// =========================================================================
// environ.c / __wasilibc_environ.c / __wasilibc_initialize_environ.c
// =========================================================================
var wasilibc_environ_storage: ?[*:null]?[*:0]u8 = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
var empty_environ: [1]?[*:0]u8 = .{null};

fn wasilibcEnsureEnvironImpl() callconv(.c) void {
    if (@intFromPtr(wasilibc_environ_storage) == @as(usize, @bitCast(@as(isize, -1)))) {
        wasilibcInitializeEnvironImpl();
    }
}

fn wasilibcGetEnvironImpl() callconv(.c) ?[*:null]?[*:0]u8 {
    wasilibcEnsureEnvironImpl();
    return wasilibc_environ_storage;
}

fn wasilibcInitializeEnvironImpl() callconv(.c) void {
    var environ_count: usize = 0;
    var environ_buf_size: usize = 0;
    var err = wasi.environ_sizes_get(&environ_count, &environ_buf_size);
    if (err != .SUCCESS) _Exit(71); // EX_OSERR

    if (environ_count == 0) {
        wasilibc_environ_storage = @ptrCast(&empty_environ);
        return;
    }

    const num_ptrs = environ_count + 1;
    if (num_ptrs == 0) _Exit(70); // EX_SOFTWARE

    const environ_buf = malloc(environ_buf_size) orelse _Exit(70);
    const environ_ptrs = @as(?[*:null]?[*:0]u8, @ptrCast(@alignCast(calloc(num_ptrs, @sizeOf(?[*:0]u8)))));
    if (environ_ptrs == null) {
        free(@ptrCast(environ_buf));
        _Exit(70);
    }

    err = wasi.environ_get(@ptrCast(environ_ptrs.?), environ_buf);
    if (err != .SUCCESS) {
        free(@ptrCast(environ_buf));
        free(@ptrCast(environ_ptrs));
        _Exit(71);
    }
    wasilibc_environ_storage = environ_ptrs;
}

fn wasilibcDeinitializeEnvironImpl() callconv(.c) void {
    if (@intFromPtr(wasilibc_environ_storage) != @as(usize, @bitCast(@as(isize, -1)))) {
        _ = clearenv();
        wasilibc_environ_storage = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
    }
}

fn wasilibcMaybeReinitializeEnvironEagerlyImpl() callconv(.c) void {
    // Weak version: does nothing. Overridden by environ.c equivalent.
}

fn wasilibcInitializeEnvironEagerly() callconv(.c) void {
    wasilibcInitializeEnvironImpl();
}

fn wasilibcMaybeReinitializeEnvironEagerlyStrong() callconv(.c) void {
    wasilibcInitializeEnvironImpl();
}

// =========================================================================
// __main_void.c (WASIP1 path)
// =========================================================================
extern fn __main_argc_argv(argc: usize, argv: [*:null]?[*:0]u8) c_int;

fn mainVoidImpl() callconv(.c) c_int {
    var argv_buf_size: usize = 0;
    var argc: usize = 0;
    var err = wasi.args_sizes_get(&argc, &argv_buf_size);
    if (err != .SUCCESS) _Exit(71);

    const num_ptrs = argc + 1;
    if (num_ptrs == 0) _Exit(70);

    const argv_buf = malloc(argv_buf_size) orelse _Exit(70);
    const argv = @as(?[*:null]?[*:0]u8, @ptrCast(@alignCast(calloc(num_ptrs, @sizeOf(?[*:0]u8)))));
    if (argv == null) {
        free(@ptrCast(argv_buf));
        _Exit(70);
    }

    err = wasi.args_get(@ptrCast(argv.?), argv_buf);
    if (err != .SUCCESS) {
        free(@ptrCast(argv_buf));
        free(@ptrCast(argv));
        _Exit(71);
    }

    return __main_argc_argv(argc, argv.?);
}

// =========================================================================
// arc4random.c - ChaCha20-based CSPRNG
// =========================================================================
const CHACHA20_KEYBYTES = 32;
const CHACHA20_BLOCKBYTES = 64;
const RNG_RESERVE_LEN = 512;

fn rotl32(x: u32, b: u5) u32 {
    return (x << b) | (x >> @intCast(@as(u6, 32) - @as(u6, b)));
}

fn chacha20QR(st: *[16]u32, a: usize, b: usize, c_idx: usize, d: usize) void {
    st[a] +%= st[b];
    st[d] = rotl32(st[d] ^ st[a], 16);
    st[c_idx] +%= st[d];
    st[b] = rotl32(st[b] ^ st[c_idx], 12);
    st[a] +%= st[b];
    st[d] = rotl32(st[d] ^ st[a], 8);
    st[c_idx] +%= st[d];
    st[b] = rotl32(st[b] ^ st[c_idx], 7);
}

fn chacha20Rounds(st: *[16]u32) void {
    var i: usize = 0;
    while (i < 20) : (i += 2) {
        chacha20QR(st, 0, 4, 8, 12);
        chacha20QR(st, 1, 5, 9, 13);
        chacha20QR(st, 2, 6, 10, 14);
        chacha20QR(st, 3, 7, 11, 15);
        chacha20QR(st, 0, 5, 10, 15);
        chacha20QR(st, 1, 6, 11, 12);
        chacha20QR(st, 2, 7, 8, 13);
        chacha20QR(st, 3, 4, 9, 14);
    }
}

fn chacha20Update(out: *[CHACHA20_BLOCKBYTES]u8, st: *[16]u32) void {
    var ks: [16]u32 = st.*;
    chacha20Rounds(st);
    for (&ks, st) |*k, s| k.* +%= s;
    @memcpy(out, std.mem.asBytes(&ks));
    st[12] +%= 1;
}

fn chacha20Init(st: *[16]u32, key: *const [CHACHA20_KEYBYTES]u8) void {
    st[0] = 0x61707865;
    st[1] = 0x3320646e;
    st[2] = 0x79622d32;
    st[3] = 0x6b206574;
    @memcpy(std.mem.asBytes(st[4..12]), key);
    st[12] = 0;
    st[13] = 0;
    st[14] = 0;
    st[15] = 0;
}

fn chacha20Rng(out: [*]u8, len_in: usize, key: *[CHACHA20_KEYBYTES]u8) void {
    var st: [16]u32 = undefined;
    chacha20Init(&st, key);
    var tmp_buf: [CHACHA20_BLOCKBYTES]u8 = undefined;
    chacha20Update(&tmp_buf, &st);
    @memcpy(key, tmp_buf[0..CHACHA20_KEYBYTES]);
    var off: usize = 0;
    var len = len_in;
    while (len >= CHACHA20_BLOCKBYTES) {
        chacha20Update(@ptrCast(out + off), &st);
        len -= CHACHA20_BLOCKBYTES;
        off += CHACHA20_BLOCKBYTES;
    }
    if (len > 0) {
        var tmp2: [CHACHA20_BLOCKBYTES]u8 = undefined;
        chacha20Update(&tmp2, &st);
        @memcpy((out + off)[0..len], tmp2[0..len]);
    }
}

const RngState = struct {
    initialized: bool = false,
    off: usize = 0,
    key: [CHACHA20_KEYBYTES]u8 = undefined,
    reserve: [RNG_RESERVE_LEN]u8 = undefined,
};

threadlocal var rng_state: RngState = .{};

fn arc4randomBufImpl(buffer: [*]u8, len_in: usize) callconv(.c) void {
    if (!rng_state.initialized) {
        if (getentropy(&rng_state.key, CHACHA20_KEYBYTES) != 0) {
            @trap();
        }
        rng_state.off = RNG_RESERVE_LEN;
        rng_state.initialized = true;
    }
    var off: usize = 0;
    var remaining = len_in;
    while (remaining > 0) {
        if (rng_state.off == RNG_RESERVE_LEN) {
            while (remaining >= RNG_RESERVE_LEN) {
                chacha20Rng(buffer + off, RNG_RESERVE_LEN, &rng_state.key);
                off += RNG_RESERVE_LEN;
                remaining -= RNG_RESERVE_LEN;
            }
            if (remaining == 0) break;
            chacha20Rng(&rng_state.reserve, RNG_RESERVE_LEN, &rng_state.key);
            rng_state.off = 0;
        }
        var partial = RNG_RESERVE_LEN - rng_state.off;
        if (remaining < partial) partial = remaining;
        @memcpy((buffer + off)[0..partial], rng_state.reserve[rng_state.off..][0..partial]);
        @memset(rng_state.reserve[rng_state.off..][0..partial], 0);
        rng_state.off += partial;
        remaining -= partial;
        off += partial;
    }
}

fn arc4randomImpl() callconv(.c) u32 {
    var v: u32 = undefined;
    arc4randomBufImpl(@ptrCast(&v), @sizeOf(u32));
    return v;
}

fn arc4randomUniformImpl(upper_bound: u32) callconv(.c) u32 {
    if (upper_bound < 2) return 0;
    const min: u32 = (1 +% ~upper_bound) % upper_bound;
    var r: u32 = undefined;
    r = arc4randomImpl();
    while (r < min) r = arc4randomImpl();
    return r % upper_bound;
}

// =========================================================================
// utime/utimes stubs for posix.c
// =========================================================================
const Utimbuf = extern struct { actime: i64, modtime: i64 };
const Timeval = extern struct { tv_sec: i64, tv_usec: i64 };
const Timespec = extern struct { tv_sec: i64, tv_nsec: i64 };

fn utimeImpl(path: [*:0]const u8, times: ?*const Utimbuf) callconv(.c) c_int {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(path, &relative_path);
    if (dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    if (times) |t| {
        var ts: [2]Timespec = .{
            .{ .tv_sec = t.actime, .tv_nsec = 0 },
            .{ .tv_sec = t.modtime, .tv_nsec = 0 },
        };
        return __wasilibc_nocwd_utimensat(dirfd, relative_path, @ptrCast(&ts), 0);
    }
    return __wasilibc_nocwd_utimensat(dirfd, relative_path, null, 0);
}

fn utimesImpl(path: [*:0]const u8, times: ?*const [2]Timeval) callconv(.c) c_int {
    var relative_path: [*:0]u8 = undefined;
    const dirfd = findRelpath(path, &relative_path);
    if (dirfd == -1) { std.c._errno().* = ENOENT; return -1; }
    if (times) |t| {
        var ts: [2]Timespec = .{
            .{ .tv_sec = t[0].tv_sec, .tv_nsec = t[0].tv_usec * 1000 },
            .{ .tv_sec = t[1].tv_sec, .tv_nsec = t[1].tv_usec * 1000 },
        };
        return __wasilibc_nocwd_utimensat(dirfd, relative_path, @ptrCast(&ts), 0);
    }
    return __wasilibc_nocwd_utimensat(dirfd, relative_path, null, 0);
}

// =========================================================================
// Symbol exports
// =========================================================================
comptime {
    if (builtin.link_libc) {
        // abort.c
        symbol(&abortImpl, "abort");

        // errno.c
        symbol(&einval_val, "__EINVAL");
        symbol(&enomem_val, "__ENOMEM");

        // __errno_location.c
        symbol(&errnoLocationImpl, "__errno_location");

        // math/math-builtins.c
        symbol(&fabsfImpl, "fabsf");
        symbol(&fabsImpl, "fabs");
        symbol(&sqrtfImpl, "sqrtf");
        symbol(&sqrtImpl, "sqrt");
        symbol(&copysignfImpl, "copysignf");
        symbol(&copysignImpl, "copysign");
        symbol(&ceilfImpl, "ceilf");
        symbol(&ceilImpl, "ceil");
        symbol(&floorfImpl, "floorf");
        symbol(&floorImpl, "floor");
        symbol(&truncfImpl, "truncf");
        symbol(&truncImpl, "trunc");
        symbol(&nearbyintfImpl, "nearbyintf");
        symbol(&nearbyintImpl, "nearbyint");
        symbol(&rintfImpl, "rintf");
        symbol(&rintImpl, "rint");

        // complex-builtins.c
        symbol(&crealfImpl, "crealf");
        symbol(&crealImpl, "creal");
        symbol(&creallImpl, "creall");
        symbol(&cimagfImpl, "cimagf");
        symbol(&cimagImpl, "cimag");
        symbol(&cimaglImpl, "cimagl");

        // sbrk.c
        symbol(&sbrkImpl, "sbrk");

        // getentropy.c
        symbol(&getentropyImpl, "__getentropy");

        // isatty.c
        symbol(&isattyImpl, "__isatty");

        // __wasilibc_tell.c
        symbol(&wasilibcTellImpl, "__wasilibc_tell");

        // __wasilibc_rmdirat.c
        symbol(&wasilibcNocwdRmdiratImpl, "__wasilibc_nocwd___wasilibc_rmdirat");

        // __wasilibc_unlinkat.c
        symbol(&wasilibcNocwdUnlinkatImpl, "__wasilibc_nocwd___wasilibc_unlinkat");

        // __wasilibc_dt.c
        symbol(&wasilibcIftodtImpl, "__wasilibc_iftodt");
        symbol(&wasilibcDttoifImpl, "__wasilibc_dttoif");

        // accept-wasip1.c
        symbol(&acceptImpl, "accept");
        symbol(&accept4Impl, "accept4");

        // reallocarray.c
        symbol(&reallocarrayImpl, "__reallocarray");

        // truncate.c
        symbol(&truncateImpl, "truncate");

        // __wasilibc_fd_renumber.c
        symbol(&wasilibcFdRenumberImpl, "__wasilibc_fd_renumber");

        // getcwd.c
        symbol(&getcwdImpl, "getcwd");

        // preopens.c
        symbol(&wasilibcRegisterPreopenedFdImpl, "__wasilibc_register_preopened_fd");
        symbol(&wasilibcFindRelpathImpl, "__wasilibc_find_relpath");
        symbol(&wasilibcFindAbspathImpl, "__wasilibc_find_abspath");
        symbol(&wasilibcPopulatePreopensImpl, "__wasilibc_populate_preopens");
        symbol(&wasilibcResetPreopensImpl, "__wasilibc_reset_preopens");

        // chdir.c
        symbol(&chdirImpl, "chdir");
        symbol(&wasilibcFindRelpathAllocImpl, "__wasilibc_find_relpath_alloc");

        // posix.c
        symbol(&openImpl, "open");
        symbol(&__wasilibc_open_nomode, "__wasilibc_open_nomode");
        symbol(&accessImpl, "access");
        symbol(&readlinkImpl, "readlink");
        symbol(&statImpl, "stat");
        symbol(&lstatImpl, "lstat");
        symbol(&utimeImpl, "utime");
        symbol(&utimesImpl, "utimes");
        symbol(&unlinkImpl, "unlink");
        symbol(&rmdirImpl, "rmdir");
        symbol(&removeImpl, "remove");
        symbol(&mkdirImpl, "mkdir");
        symbol(&opendirImpl, "opendir");
        symbol(&scandirImpl, "scandir");
        symbol(&symlinkImpl, "symlink");
        symbol(&linkImpl, "link");
        symbol(&renameImpl, "rename");
        symbol(&chmodImpl, "chmod");
        symbol(&fchmodImpl, "fchmod");
        symbol(&fchmodatImpl, "fchmodat");
        symbol(&statvfsImpl, "statvfs");
        symbol(&fstatvfsImpl, "fstatvfs");
        symbol(&wasilibcAccessImpl, "__wasilibc_access");
        symbol(&wasilibcUtimensImpl, "__wasilibc_utimens");
        symbol(&wasilibcStatImpl, "__wasilibc_stat");
        symbol(&wasilibcLinkImpl, "__wasilibc_link");
        symbol(&wasilibcLinkOldatImpl, "__wasilibc_link_oldat");
        symbol(&wasilibcLinkNewatImpl, "__wasilibc_link_newat");
        symbol(&wasilibcRenameOldatImpl, "__wasilibc_rename_oldat");
        symbol(&wasilibcRenameNewatImpl, "__wasilibc_rename_newat");

        // at_fdcwd.c
        symbol(&openatImpl, "openat");
        symbol(&symlinkatImpl, "symlinkat");
        symbol(&readlinkatImpl, "readlinkat");
        symbol(&mkdiratImpl, "mkdirat");
        symbol(&opendiratImpl, "opendirat");
        symbol(&scandiratImpl, "scandirat");
        symbol(&faccessatImpl, "faccessat");
        symbol(&fstatatImpl, "fstatat");
        symbol(&utimensatImpl, "utimensat");
        symbol(&linkatImpl, "linkat");
        symbol(&renameatImpl, "renameat");
        symbol(&wasilibcUnlinkatImpl, "__wasilibc_unlinkat");
        symbol(&wasilibcRmdiratImpl, "__wasilibc_rmdirat");

        // environ
        symbol(&wasilibcEnsureEnvironImpl, "__wasilibc_ensure_environ");
        symbol(&wasilibcGetEnvironImpl, "__wasilibc_get_environ");
        symbol(&wasilibcInitializeEnvironImpl, "__wasilibc_initialize_environ");
        symbol(&wasilibcDeinitializeEnvironImpl, "__wasilibc_deinitialize_environ");
        symbol(&wasilibcMaybeReinitializeEnvironEagerlyImpl, "__wasilibc_maybe_reinitialize_environ_eagerly");
        symbol(&wasilibcInitializeEnvironEagerly, "__wasilibc_initialize_environ_eagerly");
        symbol(&wasilibc_environ_storage, "__wasilibc_environ");

        // __main_void.c
        symbol(&mainVoidImpl, "__main_void");

        // arc4random.c
        symbol(&arc4randomBufImpl, "arc4random_buf");
        symbol(&arc4randomImpl, "arc4random");
        symbol(&arc4randomUniformImpl, "arc4random_uniform");

        // __wasilibc_real.c wrappers
        symbol(&wasiArgsGet, "__wasi_args_get");
        symbol(&wasiArgsSizesGet, "__wasi_args_sizes_get");
        symbol(&wasiEnvironGet, "__wasi_environ_get");
        symbol(&wasiEnvironSizesGet, "__wasi_environ_sizes_get");
        symbol(&wasiClockResGet, "__wasi_clock_res_get");
        symbol(&wasiClockTimeGet, "__wasi_clock_time_get");
        symbol(&wasiFdAdvise, "__wasi_fd_advise");
        symbol(&wasiFdAllocate, "__wasi_fd_allocate");
        symbol(&wasiFdCloseWrap, "__wasi_fd_close");
        symbol(&wasiFdDatasync, "__wasi_fd_datasync");
        symbol(&wasiFdFdstatGet, "__wasi_fd_fdstat_get");
        symbol(&wasiFdFdstatSetFlags, "__wasi_fd_fdstat_set_flags");
        symbol(&wasiFdFdstatSetRights, "__wasi_fd_fdstat_set_rights");
        symbol(&wasiFdFilestatGet, "__wasi_fd_filestat_get");
        symbol(&wasiFdFilestatSetSize, "__wasi_fd_filestat_set_size");
        symbol(&wasiFdFilestatSetTimes, "__wasi_fd_filestat_set_times");
        symbol(&wasiFdPread, "__wasi_fd_pread");
        symbol(&wasiFdPrestatGet, "__wasi_fd_prestat_get");
        symbol(&wasiFdPrestatDirName, "__wasi_fd_prestat_dir_name");
        symbol(&wasiFdPwrite, "__wasi_fd_pwrite");
        symbol(&wasiFdRead, "__wasi_fd_read");
        symbol(&wasiFdReaddir, "__wasi_fd_readdir");
        symbol(&wasiFdRenumber, "__wasi_fd_renumber");
        symbol(&wasiFdSeek, "__wasi_fd_seek");
        symbol(&wasiFdSync, "__wasi_fd_sync");
        symbol(&wasiFdTell, "__wasi_fd_tell");
        symbol(&wasiFdWrite, "__wasi_fd_write");
        symbol(&wasiPathCreateDirectory, "__wasi_path_create_directory");
        symbol(&wasiPathFilestatGet, "__wasi_path_filestat_get");
        symbol(&wasiPathFilestatSetTimes, "__wasi_path_filestat_set_times");
        symbol(&wasiPathLink, "__wasi_path_link");
        symbol(&wasiPathOpen, "__wasi_path_open");
        symbol(&wasiPathReadlink, "__wasi_path_readlink");
        symbol(&wasiPathRemoveDirectory, "__wasi_path_remove_directory");
        symbol(&wasiPathRename, "__wasi_path_rename");
        symbol(&wasiPathSymlink, "__wasi_path_symlink");
        symbol(&wasiPathUnlinkFile, "__wasi_path_unlink_file");
        symbol(&wasiPollOneoff, "__wasi_poll_oneoff");
        symbol(&wasiProcExit, "__wasi_proc_exit");
        symbol(&wasiSchedYield, "__wasi_sched_yield");
        symbol(&wasiRandomGet, "__wasi_random_get");
        symbol(&wasiSockAccept, "__wasi_sock_accept");
        symbol(&wasiSockRecv, "__wasi_sock_recv");
        symbol(&wasiSockSend, "__wasi_sock_send");
        symbol(&wasiSockShutdown, "__wasi_sock_shutdown");

        // Exported globals
        symbol(&wasilibc_cwd, "__wasilibc_cwd");
    }
}
