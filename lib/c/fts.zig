//! WASI file tree stream (fts) implementation, ported from `lib/libc/wasi/fts/musl-fts/fts.c`.

const std = @import("std");
const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isWasiLibC()) {
        symbol(&fts_open, "fts_open");
        symbol(&fts_close, "fts_close");
        symbol(&fts_read, "fts_read");
        symbol(&fts_children, "fts_children");
        symbol(&fts_set, "fts_set");
    }
}

const Timespec = extern struct {
    tv_sec: i64,
    tv_nsec: c_long,
};

/// Matches `struct stat` in `lib/libc/include/wasm-wasi-musl/__struct_stat.h`.
const Stat = extern struct {
    st_dev: u64,
    st_ino: u64,
    st_nlink: u64,
    st_mode: c_uint,
    st_uid: c_uint,
    st_gid: c_uint,
    __pad0: c_uint,
    st_rdev: u64,
    st_size: i64,
    st_blksize: c_long,
    st_blocks: i64,
    st_atim: Timespec,
    st_mtim: Timespec,
    st_ctim: Timespec,
    __reserved: [3]c_longlong,
};

/// Matches `struct dirent` in `lib/libc/include/wasm-wasi-musl/__struct_dirent.h`.
const Dirent = extern struct {
    d_ino: u64,
    d_type: u8,
    d_name: [1]u8,

    inline fn namePtr(self: *Dirent) [*:0]u8 {
        return @ptrCast(&self.d_name);
    }
};

const DIR = opaque {};

const ComparFn = *const fn (*const *const FTSENT, *const *const FTSENT) callconv(.c) c_int;
const QsortComparFn = *const fn (*const anyopaque, *const anyopaque) callconv(.c) c_int;

/// Matches `FTS` in `lib/libc/include/wasm-wasi-musl/fts.h`.
const FTS = extern struct {
    fts_cur: ?*FTSENT,
    fts_child: ?*FTSENT,
    fts_array: ?[*]*FTSENT,
    fts_dev: u64,
    fts_path: ?[*:0]u8,
    fts_rfd: c_int,
    fts_pathlen: c_uint,
    fts_nitems: c_uint,
    fts_compar: ?ComparFn,
    fts_options: c_int,
};

/// Matches `FTSENT` in `lib/libc/include/wasm-wasi-musl/fts.h`.
const FTSENT = extern struct {
    fts_cycle: ?*FTSENT,
    fts_parent: ?*FTSENT,
    fts_link: ?*FTSENT,
    fts_number: i64,
    fts_pointer: ?*anyopaque,
    fts_accpath: ?[*:0]u8,
    fts_path: ?[*:0]u8,
    fts_errno: c_int,
    fts_symfd: c_int,
    fts_pathlen: c_uint,
    fts_namelen: c_uint,
    fts_ino: u64,
    fts_dev: u64,
    fts_nlink: u64,
    fts_level: c_int,
    fts_info: c_ushort,
    fts_flags: c_ushort,
    fts_instr: c_ushort,
    fts_statp: ?*Stat,
    fts_name: [1]u8,

    inline fn namePtr(self: *FTSENT) [*:0]u8 {
        return @ptrCast(&self.fts_name);
    }
};

// fts_options flags
const FTS_COMFOLLOW: c_int = 0x001;
const FTS_LOGICAL: c_int = 0x002;
const FTS_NOCHDIR: c_int = 0x004;
const FTS_NOSTAT: c_int = 0x008;
const FTS_PHYSICAL: c_int = 0x010;
const FTS_SEEDOT: c_int = 0x020;
const FTS_XDEV: c_int = 0x040;
const FTS_WHITEOUT: c_int = 0x080;
const FTS_OPTIONMASK: c_int = 0x0ff;
const FTS_NAMEONLY: c_int = 0x100;
const FTS_STOP: c_int = 0x200;

// fts_level special values
const FTS_ROOTPARENTLEVEL: c_int = -1;
const FTS_ROOTLEVEL: c_int = 0;

// fts_info values
const FTS_D: c_ushort = 1;
const FTS_DC: c_ushort = 2;
const FTS_DEFAULT: c_ushort = 3;
const FTS_DNR: c_ushort = 4;
const FTS_DOT: c_ushort = 5;
const FTS_DP: c_ushort = 6;
const FTS_ERR: c_ushort = 7;
const FTS_F: c_ushort = 8;
const FTS_INIT: c_ushort = 9;
const FTS_NS: c_ushort = 10;
const FTS_NSOK: c_ushort = 11;
const FTS_SL: c_ushort = 12;
const FTS_SLNONE: c_ushort = 13;

// fts_flags values
const FTS_DONTCHDIR: c_ushort = 0x01;
const FTS_SYMFOLLOW: c_ushort = 0x02;

// fts_instr values
const FTS_AGAIN: c_ushort = 1;
const FTS_FOLLOW: c_ushort = 2;
const FTS_NOINSTR: c_ushort = 3;
const FTS_SKIP: c_ushort = 4;

// fts_build flags
const BCHILD: c_int = 1;
const BNAMES: c_int = 2;
const BREAD: c_int = 3;

const MAXPATHLEN: usize = 4096;

// WASI mode_t constants (from __mode_t.h)
const S_IFIFO: c_uint = 0x1000;
const S_IFCHR: c_uint = 0x2000;
const S_IFDIR: c_uint = 0x4000;
const S_IFBLK: c_uint = 0x6000;
const S_IFREG: c_uint = 0x8000;
const S_IFLNK: c_uint = 0xa000;
const S_IFSOCK: c_uint = 0xc000;
const S_IFMT: c_uint = S_IFBLK | S_IFCHR | S_IFDIR | S_IFIFO | S_IFLNK | S_IFREG | S_IFSOCK;

// WASI dirent d_type constants (from __header_dirent.h / wasi/api.h)
const DT_UNKNOWN: u8 = 0; // __WASI_FILETYPE_UNKNOWN
const DT_DIR: u8 = 3; // __WASI_FILETYPE_DIRECTORY

// WASI errno values
const EINVAL: c_int = 28;
const ENOENT: c_int = 44;

// WASI open flags
const O_RDONLY: c_int = 0x04000000;
const O_CLOEXEC: c_int = 0;

extern "c" fn malloc(size: usize) ?[*]align(@alignOf(usize)) u8;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?[*]align(@alignOf(usize)) u8;
extern "c" fn qsort(base: ?*anyopaque, nmemb: usize, size: usize, compar: QsortComparFn) void;
extern "c" fn opendir(name: [*:0]const u8) ?*DIR;
extern "c" fn readdir(dirp: *DIR) ?*Dirent;
extern "c" fn closedir(dirp: *DIR) c_int;
extern "c" fn dirfd(dirp: *DIR) c_int;
extern "c" fn open(path: [*:0]const u8, oflag: c_int, ...) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn stat(path: [*:0]const u8, buf: *Stat) c_int;
extern "c" fn lstat(path: [*:0]const u8, buf: *Stat) c_int;

inline fn getErrno() c_int {
    return std.c._errno().*;
}

inline fn setErrno(e: c_int) void {
    std.c._errno().* = e;
}

inline fn isSet(sp: *const FTS, opt: c_int) bool {
    return (sp.fts_options & opt) != 0;
}

inline fn setOpt(sp: *FTS, opt: c_int) void {
    sp.fts_options |= opt;
}

inline fn clrOpt(sp: *FTS, opt: c_int) void {
    sp.fts_options &= ~opt;
}

inline fn isDot(a: [*:0]const u8) bool {
    return a[0] == '.' and (a[1] == 0 or (a[1] == '.' and a[2] == 0));
}

inline fn truncateUint(a: usize) c_uint {
    return if (a > std.math.maxInt(c_uint)) std.math.maxInt(c_uint) else @intCast(a);
}

inline fn nappend(p: *const FTSENT) usize {
    const path = p.fts_path.?;
    const plen: usize = p.fts_pathlen;
    return if (path[plen - 1] == '/') plen - 1 else plen;
}

fn cStrLen(s: [*:0]const u8) usize {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

fn cMemMove(dst: [*]u8, src: [*]const u8, n: usize) void {
    if (dst == src or n == 0) return;
    if (@intFromPtr(dst) < @intFromPtr(src)) {
        for (0..n) |i| dst[i] = src[i];
    } else {
        var i: usize = n;
        while (i > 0) {
            i -= 1;
            dst[i] = src[i];
        }
    }
}

fn fts_open(
    argv_arg: [*:null]const ?[*:0]u8,
    options_arg: c_int,
    compar: ?ComparFn,
) callconv(.c) ?*FTS {
    var argv = argv_arg;
    // HAVE_FCHDIR is 0 on WASI: pretend FTS_NOCHDIR is always set.
    const options = options_arg | FTS_NOCHDIR;

    if ((options & ~FTS_OPTIONMASK) != 0) {
        setErrno(EINVAL);
        return null;
    }

    const sp_raw = malloc(@sizeOf(FTS)) orelse return null;
    const sp: *FTS = @ptrCast(@alignCast(sp_raw));
    sp.* = std.mem.zeroes(FTS);
    sp.fts_compar = compar;
    sp.fts_options = options;

    if (isSet(sp, FTS_LOGICAL))
        setOpt(sp, FTS_NOCHDIR);

    if (fts_palloc(sp, @max(fts_maxarglen(argv), MAXPATHLEN)) != 0) {
        free(sp);
        return null;
    }

    const parent = fts_alloc(sp, "", 0) orelse {
        free(sp.fts_path);
        free(sp);
        return null;
    };
    parent.fts_level = FTS_ROOTPARENTLEVEL;

    var root: ?*FTSENT = null;
    var tmp: ?*FTSENT = null;
    var nitems: usize = 0;

    while (argv[0]) |arg| : ({
        argv += 1;
        nitems += 1;
    }) {
        const len = cStrLen(arg);
        if (len == 0) {
            setErrno(ENOENT);
            fts_lfree(root);
            fts_free(parent);
            free(sp.fts_path);
            free(sp);
            return null;
        }

        const p = fts_alloc(sp, arg, len) orelse {
            fts_lfree(root);
            fts_free(parent);
            free(sp.fts_path);
            free(sp);
            return null;
        };
        p.fts_level = FTS_ROOTLEVEL;
        p.fts_parent = parent;
        p.fts_accpath = p.namePtr();
        p.fts_info = fts_stat(sp, p, isSet(sp, FTS_COMFOLLOW));

        if (p.fts_info == FTS_DOT)
            p.fts_info = FTS_D;

        if (compar != null) {
            p.fts_link = root;
            root = p;
        } else {
            p.fts_link = null;
            if (root == null) {
                tmp = p;
                root = p;
            } else {
                tmp.?.fts_link = p;
                tmp = p;
            }
        }
    }

    if (compar != null and nitems > 1)
        root = fts_sort(sp, root.?, nitems);

    sp.fts_cur = fts_alloc(sp, "", 0) orelse {
        fts_lfree(root);
        fts_free(parent);
        free(sp.fts_path);
        free(sp);
        return null;
    };
    sp.fts_cur.?.fts_link = root;
    sp.fts_cur.?.fts_info = FTS_INIT;

    if (!isSet(sp, FTS_NOCHDIR)) {
        sp.fts_rfd = open(".", O_RDONLY | O_CLOEXEC, @as(c_int, 0));
        if (sp.fts_rfd == -1)
            setOpt(sp, FTS_NOCHDIR);
    }

    if (nitems == 0)
        fts_free(parent);

    return sp;
}

fn fts_load(sp: *FTS, p: *FTSENT) void {
    var len: usize = p.fts_namelen;
    p.fts_pathlen = p.fts_namelen;
    const sp_path = sp.fts_path.?;
    const p_name = p.namePtr();
    cMemMove(sp_path, p_name, len + 1);

    // strrchr(p->fts_name, '/')
    var last_slash: ?usize = null;
    for (0..len) |i| {
        if (p_name[i] == '/') last_slash = i;
    }
    if (last_slash) |slash_idx| {
        if (slash_idx != 0 or p_name[1] != 0) {
            const cp = p_name + slash_idx + 1;
            len = cStrLen(cp);
            cMemMove(p_name, cp, len + 1);
            p.fts_namelen = truncateUint(len);
        }
    }
    p.fts_path = sp.fts_path;
    p.fts_accpath = sp.fts_path;
    sp.fts_dev = p.fts_dev;
}

fn fts_close(sp: *FTS) callconv(.c) c_int {
    if (sp.fts_cur) |cur| {
        if ((cur.fts_flags & FTS_SYMFOLLOW) != 0)
            _ = close(cur.fts_symfd);
        var p: *FTSENT = cur;
        while (p.fts_level >= FTS_ROOTLEVEL) {
            const freep = p;
            p = if (p.fts_link) |link| link else p.fts_parent.?;
            fts_free(freep);
        }
        fts_free(p);
    }

    if (sp.fts_child) |child|
        fts_lfree(child);
    if (sp.fts_array) |arr|
        free(@ptrCast(arr));
    free(sp.fts_path);

    // HAVE_FCHDIR is 0 on WASI.
    free(sp);
    return 0;
}

fn fts_read(sp: *FTS) callconv(.c) ?*FTSENT {
    if (sp.fts_cur == null or isSet(sp, FTS_STOP))
        return null;

    var p: *FTSENT = sp.fts_cur.?;
    const instr = p.fts_instr;
    p.fts_instr = FTS_NOINSTR;

    if (instr == FTS_AGAIN) {
        p.fts_info = fts_stat(sp, p, false);
        return p;
    }

    if (instr == FTS_FOLLOW and (p.fts_info == FTS_SL or p.fts_info == FTS_SLNONE)) {
        p.fts_info = fts_stat(sp, p, true);
        if (p.fts_info == FTS_D and !isSet(sp, FTS_NOCHDIR)) {
            p.fts_symfd = open(".", O_RDONLY | O_CLOEXEC, @as(c_int, 0));
            if (p.fts_symfd == -1) {
                p.fts_errno = getErrno();
                p.fts_info = FTS_ERR;
            } else {
                p.fts_flags |= FTS_SYMFOLLOW;
            }
        }
        return p;
    }

    if (p.fts_info == FTS_D) {
        if (instr == FTS_SKIP or (isSet(sp, FTS_XDEV) and p.fts_dev != sp.fts_dev)) {
            if ((p.fts_flags & FTS_SYMFOLLOW) != 0)
                _ = close(p.fts_symfd);
            if (sp.fts_child) |child| {
                fts_lfree(child);
                sp.fts_child = null;
            }
            p.fts_info = FTS_DP;
            return p;
        }

        if (sp.fts_child != null and isSet(sp, FTS_NAMEONLY)) {
            clrOpt(sp, FTS_NAMEONLY);
            fts_lfree(sp.fts_child);
            sp.fts_child = null;
        }

        if (sp.fts_child != null) {
            if (fts_safe_changedir(sp, p, -1, p.fts_accpath) != 0) {
                p.fts_errno = getErrno();
                p.fts_flags |= FTS_DONTCHDIR;
                var c = sp.fts_child;
                while (c) |cur_c| : (c = cur_c.fts_link) {
                    cur_c.fts_accpath = cur_c.fts_parent.?.fts_accpath;
                }
            }
        } else {
            sp.fts_child = fts_build(sp, BREAD);
            if (sp.fts_child == null) {
                if (isSet(sp, FTS_STOP))
                    return null;
                return p;
            }
        }
        p = sp.fts_child.?;
        sp.fts_child = null;
        return nameStep(sp, p);
    }

    while (true) {
        const tmp = p;
        sp.fts_cur = null;

        if (p.fts_link) |next_p| {
            p = next_p;
            fts_free(tmp);

            if (p.fts_level == FTS_ROOTLEVEL) {
                // FCHDIR(sp, sp->fts_rfd) is 0 on WASI.
                fts_load(sp, p);
                sp.fts_cur = p;
                return p;
            }

            if (p.fts_instr == FTS_SKIP)
                continue;
            if (p.fts_instr == FTS_FOLLOW) {
                p.fts_info = fts_stat(sp, p, true);
                if (p.fts_info == FTS_D and !isSet(sp, FTS_NOCHDIR)) {
                    p.fts_symfd = open(".", O_RDONLY | O_CLOEXEC, @as(c_int, 0));
                    if (p.fts_symfd == -1) {
                        p.fts_errno = getErrno();
                        p.fts_info = FTS_ERR;
                    } else {
                        p.fts_flags |= FTS_SYMFOLLOW;
                    }
                }
                p.fts_instr = FTS_NOINSTR;
            }

            return nameStep(sp, p);
        }

        // Move up to the parent node.
        const parent = tmp.fts_parent.?;
        fts_free(tmp);
        p = parent;

        if (p.fts_level == FTS_ROOTPARENTLEVEL) {
            fts_free(p);
            setErrno(0);
            sp.fts_cur = null;
            return null;
        }

        sp.fts_path.?[p.fts_pathlen] = 0;

        if (p.fts_level == FTS_ROOTLEVEL) {
            // FCHDIR is 0 on WASI.
        } else if ((p.fts_flags & FTS_SYMFOLLOW) != 0) {
            _ = close(p.fts_symfd);
        } else if ((p.fts_flags & FTS_DONTCHDIR) == 0 and
            fts_safe_changedir(sp, p.fts_parent, -1, "..") != 0)
        {
            setOpt(sp, FTS_STOP);
            return null;
        }
        p.fts_info = if (p.fts_errno != 0) FTS_ERR else FTS_DP;
        sp.fts_cur = p;
        return p;
    }
}

fn nameStep(sp: *FTS, p: *FTSENT) *FTSENT {
    const t = sp.fts_path.? + nappend(p.fts_parent.?);
    t[0] = '/';
    cMemMove(t + 1, p.namePtr(), @as(usize, p.fts_namelen) + 1);
    sp.fts_cur = p;
    return p;
}

fn fts_set(sp: ?*FTS, p: *FTSENT, instr: c_int) callconv(.c) c_int {
    _ = sp;
    if (instr != 0 and instr != FTS_AGAIN and instr != FTS_FOLLOW and
        instr != FTS_NOINSTR and instr != FTS_SKIP)
    {
        setErrno(EINVAL);
        return 1;
    }
    p.fts_instr = @intCast(instr);
    return 0;
}

fn fts_children(sp: *FTS, instr_arg: c_int) callconv(.c) ?*FTSENT {
    var instr = instr_arg;
    if (instr != 0 and instr != FTS_NAMEONLY) {
        setErrno(EINVAL);
        return null;
    }

    const p = sp.fts_cur orelse return null;
    setErrno(0);

    if (isSet(sp, FTS_STOP))
        return null;

    if (p.fts_info == FTS_INIT)
        return p.fts_link;

    if (p.fts_info != FTS_D)
        return null;

    if (sp.fts_child) |child|
        fts_lfree(child);

    if (instr == FTS_NAMEONLY) {
        setOpt(sp, FTS_NAMEONLY);
        instr = BNAMES;
    } else {
        instr = BCHILD;
    }

    // HAVE_FCHDIR is 0 on WASI: just build the list.
    sp.fts_child = fts_build(sp, instr);
    return sp.fts_child;
}

fn fts_build(sp: *FTS, build_type: c_int) ?*FTSENT {
    const cur = sp.fts_cur.?;

    const dirp = opendir(cur.fts_accpath.?) orelse {
        if (build_type == BREAD) {
            cur.fts_info = FTS_DNR;
            cur.fts_errno = getErrno();
        }
        return null;
    };

    var nlinks: isize = undefined;
    var nostat: bool = undefined;
    if (build_type == BNAMES) {
        nlinks = 0;
        nostat = true;
    } else if (isSet(sp, FTS_NOSTAT) and isSet(sp, FTS_PHYSICAL)) {
        const sub: u64 = if (isSet(sp, FTS_SEEDOT)) 0 else 2;
        nlinks = @as(isize, @intCast(cur.fts_nlink)) - @as(isize, @intCast(sub));
        nostat = true;
    } else {
        nlinks = -1;
        nostat = false;
    }

    var cderrno: c_int = 0;
    var descend: bool = false;
    if (nlinks != 0 or build_type == BREAD) {
        if (fts_safe_changedir(sp, cur, dirfd(dirp), null) != 0) {
            if (nlinks != 0 and build_type == BREAD)
                cur.fts_errno = getErrno();
            cur.fts_flags |= FTS_DONTCHDIR;
            descend = false;
            cderrno = getErrno();
        } else {
            descend = true;
        }
    }

    var len = nappend(cur);
    var cp: [*]u8 = undefined;
    if (isSet(sp, FTS_NOCHDIR)) {
        cp = sp.fts_path.? + len;
        cp[0] = '/';
        cp += 1;
    }
    len += 1;
    var maxlen: usize = sp.fts_pathlen - len;

    const level = cur.fts_level + 1;

    var doadjust = false;
    var head: ?*FTSENT = null;
    var tail: ?*FTSENT = null;
    var nitems: usize = 0;

    while (readdir(dirp)) |dp| {
        const dname = dp.namePtr();
        if (!isSet(sp, FTS_SEEDOT) and isDot(dname))
            continue;

        const dnamlen = cStrLen(dname);
        const p = fts_alloc(sp, dname, dnamlen) orelse {
            const saved_errno = getErrno();
            fts_lfree(head);
            _ = closedir(dirp);
            setErrno(saved_errno);
            cur.fts_info = FTS_ERR;
            setOpt(sp, FTS_STOP);
            return null;
        };

        if (dnamlen >= maxlen) {
            const oldaddr = sp.fts_path;
            if (fts_palloc(sp, dnamlen + len + 1) != 0) {
                const saved_errno = getErrno();
                fts_free(p);
                fts_lfree(head);
                _ = closedir(dirp);
                setErrno(saved_errno);
                cur.fts_info = FTS_ERR;
                setOpt(sp, FTS_STOP);
                return null;
            }
            if (oldaddr != sp.fts_path) {
                doadjust = true;
                if (isSet(sp, FTS_NOCHDIR))
                    cp = sp.fts_path.? + len;
            }
            maxlen = sp.fts_pathlen - len;
        }

        p.fts_level = level;
        p.fts_pathlen = truncateUint(len + dnamlen);
        p.fts_parent = sp.fts_cur;

        if (cderrno != 0) {
            if (nlinks != 0) {
                p.fts_info = FTS_NS;
                p.fts_errno = cderrno;
            } else {
                p.fts_info = FTS_NSOK;
            }
            p.fts_accpath = cur.fts_accpath;
        } else if (nlinks == 0 or (nostat and dp.d_type != DT_DIR and dp.d_type != DT_UNKNOWN)) {
            p.fts_accpath = if (isSet(sp, FTS_NOCHDIR)) p.fts_path else p.namePtr();
            p.fts_info = FTS_NSOK;
        } else {
            if (isSet(sp, FTS_NOCHDIR)) {
                p.fts_accpath = p.fts_path;
                cMemMove(cp, p.namePtr(), @as(usize, p.fts_namelen) + 1);
            } else {
                p.fts_accpath = p.namePtr();
            }
            p.fts_info = fts_stat(sp, p, false);

            if (nlinks > 0 and (p.fts_info == FTS_D or p.fts_info == FTS_DC or p.fts_info == FTS_DOT))
                nlinks -= 1;
        }

        p.fts_link = null;
        if (head == null) {
            head = p;
            tail = p;
        } else {
            tail.?.fts_link = p;
            tail = p;
        }
        nitems += 1;
    }
    _ = closedir(dirp);

    if (doadjust)
        fts_padjust(sp, head);

    if (isSet(sp, FTS_NOCHDIR)) {
        if (len == sp.fts_pathlen or nitems == 0)
            cp -= 1;
        cp[0] = 0;
    }

    if (descend and (build_type == BCHILD or nitems == 0) and
        (if (cur.fts_level == FTS_ROOTLEVEL)
            false
        else
            fts_safe_changedir(sp, cur.fts_parent, -1, "..") != 0))
    {
        cur.fts_info = FTS_ERR;
        setOpt(sp, FTS_STOP);
        return null;
    }

    if (nitems == 0) {
        if (build_type == BREAD)
            cur.fts_info = FTS_DP;
        return null;
    }

    if (sp.fts_compar != null and nitems > 1)
        head = fts_sort(sp, head.?, nitems);
    return head;
}

fn fts_stat(sp: *FTS, p: *FTSENT, follow: bool) c_ushort {
    var sb: Stat = undefined;
    const sbp: *Stat = if (isSet(sp, FTS_NOSTAT)) &sb else p.fts_statp.?;

    if (isSet(sp, FTS_LOGICAL) or follow) {
        if (stat(p.fts_accpath.?, sbp) != 0) {
            const saved_errno = getErrno();
            if (lstat(p.fts_accpath.?, sbp) == 0) {
                setErrno(0);
                return FTS_SLNONE;
            }
            p.fts_errno = saved_errno;
            sbp.* = std.mem.zeroes(Stat);
            return FTS_NS;
        }
    } else if (lstat(p.fts_accpath.?, sbp) != 0) {
        p.fts_errno = getErrno();
        sbp.* = std.mem.zeroes(Stat);
        return FTS_NS;
    }

    if ((sbp.st_mode & S_IFMT) == S_IFDIR) {
        const dev = sbp.st_dev;
        const ino = sbp.st_ino;
        p.fts_dev = dev;
        p.fts_ino = ino;
        p.fts_nlink = sbp.st_nlink;

        if (isDot(p.namePtr()))
            return FTS_DOT;

        var t = p.fts_parent;
        while (t) |cur_t| : (t = cur_t.fts_parent) {
            if (cur_t.fts_level < FTS_ROOTLEVEL) break;
            if (ino == cur_t.fts_ino and dev == cur_t.fts_dev) {
                p.fts_cycle = cur_t;
                return FTS_DC;
            }
        }
        return FTS_D;
    }
    if ((sbp.st_mode & S_IFMT) == S_IFLNK)
        return FTS_SL;
    if ((sbp.st_mode & S_IFMT) == S_IFREG)
        return FTS_F;
    return FTS_DEFAULT;
}

fn fts_sort(sp: *FTS, head_arg: *FTSENT, nitems_arg: usize) *FTSENT {
    var head = head_arg;
    var nitems = nitems_arg;

    if (nitems > sp.fts_nitems) {
        const new_raw = realloc(@ptrCast(sp.fts_array), @sizeOf(*FTSENT) * (nitems + 40)) orelse return head;
        sp.fts_array = @ptrCast(@alignCast(new_raw));
        sp.fts_nitems = truncateUint(nitems + 40);
    }

    const array = sp.fts_array.?;
    var i: usize = 0;
    var p: ?*FTSENT = head;
    while (p) |cur_p| : (p = cur_p.fts_link) {
        array[i] = cur_p;
        i += 1;
    }

    qsort(@ptrCast(array), nitems, @sizeOf(*FTSENT), @ptrCast(sp.fts_compar.?));

    head = array[0];
    var idx: usize = 0;
    while (nitems > 1) : ({
        nitems -= 1;
        idx += 1;
    }) {
        array[idx].fts_link = array[idx + 1];
    }
    array[idx].fts_link = null;
    return head;
}

fn fts_alloc(sp: *FTS, name: [*:0]const u8, namelen: usize) ?*FTSENT {
    const raw = malloc(@sizeOf(FTSENT) + namelen) orelse return null;
    const p: *FTSENT = @ptrCast(@alignCast(raw));

    if (!isSet(sp, FTS_NOSTAT)) {
        const stat_raw = malloc(@sizeOf(Stat)) orelse {
            free(p);
            return null;
        };
        p.fts_statp = @ptrCast(@alignCast(stat_raw));
    } else {
        p.fts_statp = null;
    }

    cMemMove(p.namePtr(), name, namelen + 1);

    p.fts_namelen = truncateUint(namelen);
    p.fts_path = sp.fts_path;
    p.fts_errno = 0;
    p.fts_flags = 0;
    p.fts_instr = FTS_NOINSTR;
    p.fts_number = 0;
    p.fts_pointer = null;
    return p;
}

fn fts_free(p: *FTSENT) void {
    if (p.fts_statp) |statp|
        free(statp);
    free(p);
}

fn fts_lfree(head_arg: ?*FTSENT) void {
    var head = head_arg;
    while (head) |p| {
        head = p.fts_link;
        fts_free(p);
    }
}

fn fts_pow2(x_arg: usize) usize {
    var x = x_arg -% 1;
    x |= x >> 1;
    x |= x >> 2;
    x |= x >> 4;
    x |= x >> 8;
    x |= x >> 16;
    if (@bitSizeOf(usize) > 32) {
        x |= x >> 32;
    }
    return x +% 1;
}

fn fts_palloc(sp: *FTS, size_arg: usize) c_int {
    const size = fts_pow2(size_arg);
    const new_raw = realloc(@ptrCast(sp.fts_path), size) orelse return 1;
    sp.fts_path = @ptrCast(new_raw);
    sp.fts_pathlen = truncateUint(size);
    return 0;
}

fn adjustNode(p: *FTSENT, addr: [*:0]u8) void {
    if (p.fts_accpath != p.namePtr()) {
        const offset = @intFromPtr(p.fts_accpath.?) - @intFromPtr(p.fts_path.?);
        p.fts_accpath = @ptrFromInt(@intFromPtr(addr) + offset);
    }
    p.fts_path = addr;
}

fn fts_padjust(sp: *FTS, head: ?*FTSENT) void {
    const addr = sp.fts_path.?;

    var c = sp.fts_child;
    while (c) |p| : (c = p.fts_link) {
        adjustNode(p, addr);
    }

    var cur = head;
    while (cur) |p| {
        if (p.fts_level < FTS_ROOTLEVEL) break;
        adjustNode(p, addr);
        cur = if (p.fts_link != null) p.fts_link else p.fts_parent;
    }
}

fn fts_maxarglen(argv_arg: [*:null]const ?[*:0]u8) usize {
    var argv = argv_arg;
    var max: usize = 0;
    while (argv[0]) |arg| : (argv += 1) {
        const len = cStrLen(arg);
        if (len > max) max = len;
    }
    return max + 1;
}

fn fts_safe_changedir(sp: *const FTS, p: ?*const FTSENT, fd: c_int, path: ?[*:0]const u8) c_int {
    // HAVE_FCHDIR is 0 on WASI.
    _ = .{ sp, p, fd, path };
    return 0;
}
