const builtin = @import("builtin");
const std = @import("std");

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.link_libc) {
        symbol(&wordexp_fn, "wordexp");
        symbol(&wordfree_fn, "wordfree");
    }
}

const FILE = anyopaque;
const sigset_t = [128 / @sizeOf(c_ulong)]c_ulong;

const wordexp_t = extern struct {
    we_wordc: usize,
    we_wordv: ?[*]?[*:0]u8,
    we_offs: usize,
};

const WRDE_DOOFFS: c_int = 1;
const WRDE_APPEND: c_int = 2;
const WRDE_NOCMD: c_int = 4;
const WRDE_REUSE: c_int = 8;
const WRDE_SHOWERR: c_int = 16;
const WRDE_NOSPACE: c_int = 1;
const WRDE_BADCHAR: c_int = 2;
const WRDE_CMDSUB: c_int = 4;
const WRDE_SYNTAX: c_int = 5;

const O_CLOEXEC = 0o2000000;
const F_SETFD: c_int = 2;
const SIGKILL: c_int = 9;

extern "c" fn pipe2(fds: *[2]c_int, flags: c_int) c_int;
extern "c" fn fork() c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn dup2(old: c_int, new: c_int) c_int;
extern "c" fn execl(path: [*:0]const u8, arg0: [*:0]const u8, ...) c_int;
extern "c" fn _exit(code: c_int) noreturn;
extern "c" fn kill(pid: c_int, sig: c_int) c_int;
extern "c" fn waitpid(pid: c_int, status: ?*c_int, options: c_int) c_int;
extern "c" fn fdopen(fd: c_int, mode: [*:0]const u8) ?*FILE;
extern "c" fn feof(f: *FILE) c_int;
extern "c" fn fclose(f: *FILE) c_int;
extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
extern "c" fn getdelim(lineptr: *?[*:0]u8, n: *usize, delim: c_int, f: *FILE) isize;
extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?[*]u8;
extern "c" fn calloc(nmemb: usize, size: usize) ?[*]u8;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn __block_all_sigs(set: ?*sigset_t) void;
extern "c" fn __restore_sigs(set: *const sigset_t) void;
extern "c" fn pthread_setcancelstate(state: c_int, oldstate: ?*c_int) c_int;

const PTHREAD_CANCEL_DISABLE: c_int = 1;

fn reap(pid: c_int) void {
    var status: c_int = undefined;
    while (waitpid(pid, &status, 0) < 0 and std.c._errno().* == @intFromEnum(std.os.linux.E.INTR)) {}
}

fn getword(f: *FILE) ?[*:0]u8 {
    var s: ?[*:0]u8 = null;
    var n: usize = 0;
    return if (getdelim(&s, &n, 0, f) < 0) null else s;
}

fn do_wordexp(s: [*:0]const u8, we: *wordexp_t, flags: c_int) c_int {
    if (flags & WRDE_REUSE != 0) wordfree_fn(we);

    if (flags & WRDE_NOCMD != 0) {
        var sq = false;
        var dq = false;
        var np: usize = 0;
        var idx: usize = 0;
        while (s[idx] != 0) : (idx += 1) {
            const c = s[idx];
            if (c == '\\') {
                if (!sq) {
                    idx += 1;
                    if (s[idx] == 0) return WRDE_SYNTAX;
                }
            } else if (c == '\'') {
                if (!dq) sq = !sq;
            } else if (c == '"') {
                if (!sq) dq = !dq;
            } else if (c == '(') {
                if (np > 0) np += 1;
            } else if (c == ')') {
                if (np > 0) np -= 1;
            } else if (c == '\n' or c == '|' or c == '&' or c == ';' or c == '<' or c == '>' or c == '{' or c == '}') {
                if (!(sq or dq or np > 0)) return WRDE_BADCHAR;
            } else if (c == '$') {
                if (!sq and s[idx + 1] == '(' and s[idx + 2] == '(') {
                    idx += 2;
                    np += 2;
                } else if (!sq and s[idx + 1] == '(') {
                    return WRDE_CMDSUB;
                }
            } else if (c == '`') {
                if (!sq) return WRDE_CMDSUB;
            }
        }
    }

    var wc: usize = 0;
    var wv: ?[*]?[*:0]u8 = null;
    if (flags & WRDE_APPEND != 0) {
        wc = we.we_wordc;
        wv = we.we_wordv;
    }

    var i: usize = wc;
    if (flags & WRDE_DOOFFS != 0) {
        if (we.we_offs > std.math.maxInt(usize) / @sizeOf(?*anyopaque) / 4)
            return nospace(we, flags);
        i += we.we_offs;
    } else {
        we.we_offs = 0;
    }

    var p: [2]c_int = undefined;
    if (pipe2(&p, O_CLOEXEC) < 0) return nospace(we, flags);
    var set: sigset_t = undefined;
    __block_all_sigs(&set);
    const pid = fork();
    __restore_sigs(&set);
    if (pid < 0) {
        _ = close(p[0]);
        _ = close(p[1]);
        return nospace(we, flags);
    }
    if (pid == 0) {
        if (p[1] == 1) _ = fcntl(1, F_SETFD, @as(c_int, 0)) else _ = dup2(p[1], 1);
        const redir: [*:0]const u8 = if (flags & WRDE_SHOWERR != 0) "" else "2>/dev/null";
        _ = execl("/bin/sh", "sh", "-c", "eval \"printf %s\\\\\\\\0 x $1 $2\"", "sh", s, redir, @as(?[*:0]const u8, null));
        _exit(1);
    }
    _ = close(p[1]);

    const f: *FILE = fdopen(p[0], "r") orelse {
        _ = close(p[0]);
        _ = kill(pid, SIGKILL);
        reap(pid);
        return nospace(we, flags);
    };

    var l: usize = if (wv != null) i + 1 else 0;

    free(getword(f));
    if (feof(f) != 0) {
        _ = fclose(f);
        reap(pid);
        return WRDE_SYNTAX;
    }

    var err: c_int = 0;
    while (getword(f)) |w| {
        if (i + 1 >= l) {
            l += l / 2 + 10;
            const tmp: ?[*]?[*:0]u8 = @ptrCast(@alignCast(realloc(@ptrCast(wv), l * @sizeOf(?[*:0]u8))));
            if (tmp == null) break;
            wv = tmp;
        }
        wv.?[i] = w;
        i += 1;
        wv.?[i] = null;
    }
    if (feof(f) == 0) err = WRDE_NOSPACE;
    _ = fclose(f);
    reap(pid);

    if (wv == null) wv = @ptrCast(@alignCast(calloc(i + 1, @sizeOf(?[*:0]u8))));

    we.we_wordv = wv;
    we.we_wordc = i;

    if (flags & WRDE_DOOFFS != 0) {
        if (wv) |v| {
            var j = we.we_offs;
            while (j > 0) : (j -= 1) v[j - 1] = null;
        }
        we.we_wordc -= we.we_offs;
    }
    return err;
}

fn nospace(we: *wordexp_t, flags: c_int) c_int {
    if (flags & WRDE_APPEND == 0) {
        we.we_wordc = 0;
        we.we_wordv = null;
    }
    return WRDE_NOSPACE;
}

fn wordexp_fn(s: [*:0]const u8, we: *wordexp_t, flags: c_int) callconv(.c) c_int {
    var cs: c_int = undefined;
    _ = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cs);
    const r = do_wordexp(s, we, flags);
    _ = pthread_setcancelstate(cs, null);
    return r;
}

fn wordfree_fn(we: *wordexp_t) callconv(.c) void {
    const wv = we.we_wordv orelse return;
    for (0..we.we_wordc) |j| free(wv[we.we_offs + j]);
    free(@ptrCast(wv));
    we.we_wordv = null;
    we.we_wordc = 0;
}
