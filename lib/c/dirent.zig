const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

/// Internal DIR stream structure matching musl's __dirstream layout.
const DIR = extern struct {
    tell: linux.off_t,
    fd: c_int,
    buf_pos: c_int,
    buf_end: c_int,
    lock: [1]c_int,
    buf: [2048]u8,
};

/// Linux dirent as returned by SYS_getdents64.
const dirent = extern struct {
    d_ino: u64,
    d_off: i64,
    d_reclen: u16,
    d_type: u8,
    d_name: [256]u8,
};

comptime {
    if (builtin.target.isMuslLibC()) {
        // These need no libc deps (pure syscalls or struct access)
        symbol(&dirfd, "dirfd");
        symbol(&telldir, "telldir");
        symbol(&readdir, "readdir");

        // These need libc functions at link time
        if (builtin.link_libc) {
            symbol(&opendir, "opendir");
            symbol(&closedir, "closedir");
            symbol(&fdopendir, "fdopendir");
            symbol(&readdir_r, "readdir_r");
            symbol(&rewinddir, "rewinddir");
            symbol(&seekdir, "seekdir");
            symbol(&scandir, "scandir");
            symbol(&alphasort, "alphasort");
            symbol(&versionsort, "versionsort");
        }
    }
}

fn dirfd(dir: *DIR) callconv(.c) c_int {
    return dir.fd;
}

fn telldir(dir: *DIR) callconv(.c) c_long {
    return @intCast(dir.tell);
}

fn readdir(dir: *DIR) callconv(.c) ?*dirent {
    if (dir.buf_pos >= dir.buf_end) {
        const len: isize = @bitCast(linux.getdents64(dir.fd, &dir.buf, dir.buf.len));
        if (len <= 0) {
            if (len < 0 and @as(c_int, @intCast(-len)) != @intFromEnum(linux.E.NOENT))
                std.c._errno().* = @intCast(-len);
            return null;
        }
        dir.buf_end = @intCast(len);
        dir.buf_pos = 0;
    }
    const de: *dirent = @ptrCast(@alignCast(&dir.buf[@intCast(dir.buf_pos)]));
    dir.buf_pos += @intCast(de.d_reclen);
    dir.tell = de.d_off;
    return de;
}

// Extern libc functions used by wrappers below
extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern "c" fn lseek(fd: c_int, offset: linux.off_t, whence: c_int) linux.off_t;
extern "c" fn fstat(fd: c_int, buf: *anyopaque) c_int;
extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
extern "c" fn strcoll(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern "c" fn strverscmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern "c" fn memcpy(dest: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;
extern "c" fn qsort(base: *anyopaque, nmemb: usize, size: usize, compar: *const anyopaque) void;

const O_RDONLY = 0;
const O_DIRECTORY = 0o200000;
const O_CLOEXEC = 0o2000000;
const O_PATH = 0o10000000;
const FD_CLOEXEC = 1;
const S_IFDIR = 0o040000;
const S_IFMT = 0o170000;
const SEEK_SET = 0;

fn opendir(name: [*:0]const u8) callconv(.c) ?*DIR {
    const fd = open(name, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0) return null;
    const dir: ?*DIR = @ptrCast(@alignCast(calloc(1, @sizeOf(DIR))));
    if (dir) |d| {
        d.fd = fd;
        return d;
    }
    _ = linux.syscall1(.close, @as(usize, @bitCast(@as(isize, fd))));
    return null;
}

fn closedir(dir: *DIR) callconv(.c) c_int {
    const ret = close(dir.fd);
    free(dir);
    return ret;
}

fn fdopendir(fd: c_int) callconv(.c) ?*DIR {
    // Verify fd points to a directory
    var st_buf: [256]u8 = undefined; // opaque stat buffer
    if (fstat(fd, &st_buf) < 0) return null;
    // Check O_PATH flag
    const flags = fcntl(fd, linux.F.GETFL);
    if (flags & O_PATH != 0) {
        std.c._errno().* = @intFromEnum(linux.E.BADF);
        return null;
    }
    // We can't easily check S_ISDIR without knowing struct stat layout,
    // but the getdents syscall will fail with ENOTDIR if it's not a dir.
    _ = fcntl(fd, linux.F.SETFD, FD_CLOEXEC);
    const dir: ?*DIR = @ptrCast(@alignCast(calloc(1, @sizeOf(DIR))));
    if (dir) |d| {
        d.fd = fd;
        return d;
    }
    return null;
}

fn readdir_r(dir: *DIR, buf: *dirent, result: **dirent) callconv(.c) c_int {
    // Simplified: no lock (matching musl's LOCK/UNLOCK which is a spin lock)
    const errno_save = std.c._errno().*;
    std.c._errno().* = 0;
    const de = readdir(dir);
    const ret = std.c._errno().*;
    if (ret != 0) return ret;
    std.c._errno().* = errno_save;
    if (de) |d| {
        _ = memcpy(buf, d, d.d_reclen);
        result.* = buf;
    } else {
        result.* = @ptrFromInt(0);
    }
    return 0;
}

fn rewinddir(dir: *DIR) callconv(.c) void {
    _ = lseek(dir.fd, 0, SEEK_SET);
    dir.buf_pos = 0;
    dir.buf_end = 0;
    dir.tell = 0;
}

fn seekdir(dir: *DIR, off: c_long) callconv(.c) void {
    dir.tell = lseek(dir.fd, @intCast(off), SEEK_SET);
    dir.buf_pos = 0;
    dir.buf_end = 0;
}

fn scandir(
    path: [*:0]const u8,
    res: *?[*]*dirent,
    sel: ?*const fn (*const dirent) callconv(.c) c_int,
    cmp: ?*const anyopaque,
) callconv(.c) c_int {
    const d = opendir(path) orelse return -1;
    var names: ?[*]*dirent = null;
    var cnt: usize = 0;
    var len: usize = 0;
    const old_errno = std.c._errno().*;

    while (true) {
        std.c._errno().* = 0;
        const de = readdir(d) orelse break;
        if (sel) |s| {
            if (s(de) == 0) continue;
        }
        if (cnt >= len) {
            len = 2 * len + 1;
            const tmp: ?[*]*dirent = @ptrCast(@alignCast(realloc(names, len * @sizeOf(*dirent))));
            if (tmp == null) break;
            names = tmp;
        }
        const entry: ?*dirent = @ptrCast(@alignCast(malloc(de.d_reclen)));
        if (entry == null) break;
        _ = memcpy(entry.?, de, de.d_reclen);
        names.?[cnt] = entry.?;
        cnt += 1;
    }

    _ = closedir(d);

    if (std.c._errno().* != 0) {
        if (names) |n| {
            var i = cnt;
            while (i > 0) {
                i -= 1;
                free(n[i]);
            }
        }
        free(names);
        return -1;
    }
    std.c._errno().* = old_errno;

    if (cmp) |c| qsort(@ptrCast(names.?), cnt, @sizeOf(*dirent), c);
    res.* = names;
    return @intCast(cnt);
}

fn alphasort(a: *const *const dirent, b: *const *const dirent) callconv(.c) c_int {
    return strcoll(&a.*.d_name, &b.*.d_name);
}

fn versionsort(a: *const *const dirent, b: *const *const dirent) callconv(.c) c_int {
    return strverscmp(&a.*.d_name, &b.*.d_name);
}
