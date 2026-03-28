const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.link_libc) {
        symbol(&nftw_fn, "nftw");
    }
}

const DIR = anyopaque;
const stat_buf = [256]u8;
const PATH_MAX = 4096;

const FTW_F: c_int = 1;
const FTW_D: c_int = 2;
const FTW_DNR: c_int = 3;
const FTW_NS: c_int = 4;
const FTW_SL: c_int = 5;
const FTW_DP: c_int = 6;
const FTW_SLN: c_int = 7;

const FTW_PHYS: c_int = 1;
const FTW_MOUNT: c_int = 2;
const FTW_DEPTH: c_int = 8;

const FTW = extern struct { base: c_int, level: c_int };

const nftw_fn_t = *const fn ([*:0]const u8, *const stat_buf, c_int, *FTW) callconv(.c) c_int;

extern "c" fn @"stat"(path: [*:0]const u8, buf: *stat_buf) c_int;
extern "c" fn lstat(path: [*:0]const u8, buf: *stat_buf) c_int;
extern "c" fn @"open"(path: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn fdopendir(fd: c_int) ?*DIR;
extern "c" fn readdir(d: *DIR) ?*anyopaque; // returns struct dirent*
extern "c" fn closedir(d: *DIR) c_int;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn strcpy(dst: [*]u8, src: [*:0]const u8) [*]u8;
extern "c" fn memcpy(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;
extern "c" fn pthread_setcancelstate(state: c_int, oldstate: ?*c_int) c_int;

const O_RDONLY = 0;
const S_IFMT: u32 = 0o170000;
const S_IFDIR: u32 = 0o040000;
const S_IFLNK: u32 = 0o120000;
const PTHREAD_CANCEL_DISABLE: c_int = 1;

// Offsets for st_dev, st_ino, st_mode in struct stat (Linux 64-bit musl)
const ST_DEV_OFF = 0;
const ST_INO_OFF = 8;
const ST_MODE_OFF = 24; // after dev(8) + ino(8) + nlink(8)

fn get_dev(st: *const stat_buf) u64 {
    return @as(*const u64, @ptrCast(@alignCast(&st.*[ST_DEV_OFF]))).*;
}
fn get_ino(st: *const stat_buf) u64 {
    return @as(*const u64, @ptrCast(@alignCast(&st.*[ST_INO_OFF]))).*;
}
fn get_mode(st: *const stat_buf) u32 {
    return @as(*const u32, @ptrCast(@alignCast(&st.*[ST_MODE_OFF]))).*;
}

// dirent d_name offset: after d_ino(8) + d_off(8) + d_reclen(2) + d_type(1) = 19
const DIRENT_DNAME_OFF = 19;

fn d_name(de: *anyopaque) [*:0]const u8 {
    return @ptrCast(@as([*]const u8, @ptrCast(de)) + DIRENT_DNAME_OFF);
}

const History = struct {
    chain: ?*const History,
    dev: u64,
    ino: u64,
    level: c_int,
    base: usize,
};

fn do_nftw(path: [*:0]u8, func: nftw_fn_t, fd_limit: c_int, flags: c_int, h: ?*const History) c_int {
    const l = strlen(path);
    const j: usize = if (l > 0 and path[l - 1] == '/') l - 1 else l;
    var st: stat_buf = std.mem.zeroes(stat_buf);
    var ftw_type: c_int = undefined;
    var dfd: c_int = -1;
    var err: c_int = 0;

    const stat_rc = if (flags & FTW_PHYS != 0) lstat(path, &st) else @"stat"(path, &st);
    if (stat_rc < 0) {
        const e = std.c._errno().*;
        if (flags & FTW_PHYS == 0 and e == @intFromEnum(linux.E.NOENT) and lstat(path, &st) == 0)
            ftw_type = FTW_SLN
        else if (e != @intFromEnum(linux.E.ACCES))
            return -1
        else
            ftw_type = FTW_NS;
    } else {
        const mode = get_mode(&st) & S_IFMT;
        if (mode == S_IFDIR)
            ftw_type = if (flags & FTW_DEPTH != 0) FTW_DP else FTW_D
        else if (mode == S_IFLNK)
            ftw_type = if (flags & FTW_PHYS != 0) FTW_SL else FTW_SLN
        else
            ftw_type = FTW_F;
    }

    if (flags & FTW_MOUNT != 0 and h != null and ftw_type != FTW_NS and get_dev(&st) != h.?.dev)
        return 0;

    const new_h = History{
        .chain = h,
        .dev = get_dev(&st),
        .ino = get_ino(&st),
        .level = if (h) |hh| hh.level + 1 else 0,
        .base = j + 1,
    };

    var lev = FTW{
        .level = new_h.level,
        .base = @intCast(if (h) |hh| hh.base else blk: {
            var k = j;
            while (k > 0 and path[k] == '/') : (k -= 1) {}
            while (k > 0 and path[k - 1] != '/') : (k -= 1) {}
            break :blk k;
        }),
    };

    if (ftw_type == FTW_D or ftw_type == FTW_DP) {
        dfd = @"open"(path, O_RDONLY);
        err = std.c._errno().*;
        if (dfd < 0 and err == @intFromEnum(linux.E.ACCES)) ftw_type = FTW_DNR;
        if (fd_limit == 0) _ = close(dfd);
    }

    if (flags & FTW_DEPTH == 0) {
        const r = func(path, &st, ftw_type, &lev);
        if (r != 0) return r;
    }

    // Check for cycles
    var hh = h;
    while (hh) |cur| : (hh = cur.chain) {
        if (cur.dev == get_dev(&st) and cur.ino == get_ino(&st)) return 0;
    }

    if ((ftw_type == FTW_D or ftw_type == FTW_DP) and fd_limit > 0) {
        if (dfd < 0) {
            std.c._errno().* = err;
            return -1;
        }
        const d = fdopendir(dfd) orelse {
            _ = close(dfd);
            return -1;
        };
        while (readdir(d)) |de| {
            const name = d_name(de);
            if (name[0] == '.' and (name[1] == 0 or (name[1] == '.' and name[2] == 0))) continue;
            if (strlen(name) >= PATH_MAX - l) {
                std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
                _ = closedir(d);
                return -1;
            }
            @as([*]u8, @ptrCast(path))[j] = '/';
            _ = strcpy(@as([*]u8, @ptrCast(path)) + j + 1, name);
            const r = do_nftw(path, func, fd_limit - 1, flags, &new_h);
            if (r != 0) {
                _ = closedir(d);
                return r;
            }
        }
        _ = closedir(d);
    }

    @as([*]u8, @ptrCast(path))[l] = 0;
    if (flags & FTW_DEPTH != 0) {
        const r = func(path, &st, ftw_type, &lev);
        if (r != 0) return r;
    }
    return 0;
}

fn nftw_fn(path: [*:0]const u8, func: nftw_fn_t, fd_limit: c_int, flags: c_int) callconv(.c) c_int {
    if (fd_limit <= 0) return 0;
    const l = strlen(path);
    if (l > PATH_MAX) {
        std.c._errno().* = @intFromEnum(linux.E.NAMETOOLONG);
        return -1;
    }
    var pathbuf: [PATH_MAX + 1]u8 = undefined;
    _ = memcpy(&pathbuf, path, l + 1);
    var cs: c_int = undefined;
    _ = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cs);
    const r = do_nftw(@ptrCast(pathbuf[0..l :0]), func, fd_limit, flags, null);
    _ = pthread_setcancelstate(cs, null);
    return r;
}
