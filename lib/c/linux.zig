const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

/// Like `errno` but for syscalls that return an `isize` (ssize_t).
fn errnoSize(v: usize) isize {
    const signed: isize = @bitCast(v);
    if (signed < 0) {
        @branchHint(.unlikely);
        std.c._errno().* = @intCast(-signed);
        return -1;
    }
    return signed;
}

comptime {
    if (builtin.target.isMuslLibC()) {
        // brk / sbrk
        symbol(&brkLinux, "brk");
        symbol(&sbrkLinux, "sbrk");

        // copy_file_range
        symbol(&copy_file_rangeLinux, "copy_file_range");

        // epoll
        symbol(&epoll_createLinux, "epoll_create");
        symbol(&epoll_create1Linux, "epoll_create1");
        symbol(&epoll_ctlLinux, "epoll_ctl");
        symbol(&epoll_pwaitLinux, "epoll_pwait");
        symbol(&epoll_waitLinux, "epoll_wait");

        // eventfd
        symbol(&eventfdLinux, "eventfd");
        symbol(&eventfd_readLinux, "eventfd_read");
        symbol(&eventfd_writeLinux, "eventfd_write");

        // fanotify
        symbol(&fanotify_initLinux, "fanotify_init");
        symbol(&fanotify_markLinux, "fanotify_mark");

        // getdents
        if (@hasField(linux.SYS, "getdents"))
            symbol(&getdentsLinux, "getdents");

        // getrandom
        symbol(&getrandomLinux, "getrandom");

        // gettid
        symbol(&gettidLinux, "gettid");

        // inotify
        symbol(&inotify_initLinux, "inotify_init");
        symbol(&inotify_init1Linux, "inotify_init1");
        symbol(&inotify_add_watchLinux, "inotify_add_watch");
        symbol(&inotify_rm_watchLinux, "inotify_rm_watch");

        // klogctl
        symbol(&klogctlLinux, "klogctl");

        // memfd_create
        symbol(&memfd_createLinux, "memfd_create");

        // mlock2
        symbol(&mlock2Linux, "mlock2");

        // module
        symbol(&init_moduleLinux, "init_module");
        symbol(&delete_moduleLinux, "delete_module");

        // mount
        symbol(&mountLinux, "mount");
        symbol(&umountLinux, "umount");
        symbol(&umount2Linux, "umount2");

        // name_to_handle_at / open_by_handle_at
        symbol(&name_to_handle_atLinux, "name_to_handle_at");
        symbol(&open_by_handle_atLinux, "open_by_handle_at");

        // pivot_root
        symbol(&pivot_rootLinux, "pivot_root");

        // prctl
        symbol(&prctlLinux, "prctl");

        // process_vm
        symbol(&process_vm_readvLinux, "process_vm_readv");
        symbol(&process_vm_writevLinux, "process_vm_writev");

        // prlimit
        symbol(&prlimitLinux, "prlimit");

        // ptrace
        symbol(&ptraceLinux, "ptrace");

        // quotactl
        symbol(&quotactlLinux, "quotactl");

        // readahead
        symbol(&readaheadLinux, "readahead");

        // remap_file_pages
        symbol(&remap_file_pagesLinux, "remap_file_pages");

        // sendfile
        symbol(&sendfileLinux, "sendfile");

        // setfsgid / setfsuid
        symbol(&setfsgidLinux, "setfsgid");
        symbol(&setfsuidLinux, "setfsuid");

        // setgroups
        symbol(&setgroupsLinux, "setgroups");

        // sethostname
        symbol(&sethostnameLinux, "sethostname");

        // setns
        symbol(&setnsLinux, "setns");

        // signalfd
        symbol(&signalfdLinux, "signalfd");

        // splice / tee / vmsplice
        symbol(&spliceLinux, "splice");
        symbol(&teeLinux, "tee");
        symbol(&vmspliceLinux, "vmsplice");

        // statx
        symbol(&statxLinux, "statx");

        // swap
        symbol(&swaponLinux, "swapon");
        symbol(&swapoffLinux, "swapoff");

        // syncfs
        symbol(&syncfsLinux, "syncfs");

        // sync_file_range
        if (@hasField(linux.SYS, "sync_file_range"))
            symbol(&sync_file_rangeLinux, "sync_file_range")
        else if (@hasField(linux.SYS, "sync_file_range2"))

        // sysinfo
        symbol(&sysinfoLinux, "__lsysinfo");

        // timerfd
        symbol(&timerfd_createLinux, "timerfd_create");
        symbol(&timerfd_settimeLinux, "timerfd_settime");
        symbol(&timerfd_gettimeLinux, "timerfd_gettime");

        // unshare
        symbol(&unshareLinux, "unshare");

        // vhangup
        symbol(&vhangupLinux, "vhangup");

        // wait
        symbol(&wait3Linux, "wait3");
        symbol(&wait4Linux, "wait4");

        // xattr
        symbol(&getxattrLinux, "getxattr");
        symbol(&lgetxattrLinux, "lgetxattr");
        symbol(&fgetxattrLinux, "fgetxattr");
        symbol(&listxattrLinux, "listxattr");
        symbol(&llistxattrLinux, "llistxattr");
        symbol(&flistxattrLinux, "flistxattr");
        symbol(&setxattrLinux, "setxattr");
        symbol(&lsetxattrLinux, "lsetxattr");
        symbol(&fsetxattrLinux, "fsetxattr");
        symbol(&removexattrLinux, "removexattr");
        symbol(&lremovexattrLinux, "lremovexattr");
        symbol(&fremovexattrLinux, "fremovexattr");

        // preadv2 / pwritev2
        symbol(&preadv2Linux, "preadv2");
        symbol(&pwritev2Linux, "pwritev2");

        // clock_adjtime / adjtimex
        symbol(&clock_adjtimeLinux, "clock_adjtime");
        symbol(&adjtimexLinux, "adjtimex");

        // settimeofday / stime
        symbol(&settimeofdayLinux, "settimeofday");
        symbol(&stimeLinux, "stime");

        // utimes
        symbol(&utimesLinux, "utimes");

        // arch-specific
        if (@hasField(linux.SYS, "ioperm"))
            symbol(&iopermLinux, "ioperm");
        if (@hasField(linux.SYS, "iopl"))
            symbol(&ioplLinux, "iopl");
        if (@hasField(linux.SYS, "arch_prctl"))
            symbol(&arch_prctlLinux, "arch_prctl");
        if (@hasField(linux.SYS, "personality"))
            symbol(&personalityLinux, "personality");

        // cache (arch-specific)
        if (@hasField(linux.SYS, "cacheflush")) {
            symbol(&cacheflushLinux, "_flush_cache");
        }
        if (@hasField(linux.SYS, "cachectl")) {
            symbol(&cachectlLinux, "__cachectl");
        }
        if (@hasField(linux.SYS, "riscv_flush_icache")) {
            symbol(&riscv_flush_icacheLinux, "__riscv_flush_icache");
        }
    }
    // Functions that depend on other C library internals
    if (builtin.link_libc) {
        symbol(&cloneLinux, "clone");
        symbol(&membarrierLinux, "membarrier");
        symbol(&membarrier_initLinux, "__membarrier_init");
    }
}

// ─── helpers ────────────────────────────────────────────────────────────────

fn arg(val: anytype) usize {
    const T = @TypeOf(val);
    return switch (@typeInfo(T)) {
        .pointer => @intFromPtr(val),
        .optional => if (val) |p| @intFromPtr(p) else 0,
        .int => |i| if (i.signedness == .signed)
            @bitCast(@as(isize, @intCast(val)))
        else
            @intCast(val),
        .@"enum" => @bitCast(@as(isize, @intCast(@intFromEnum(val)))),
        else => @compileError("unsupported arg type"),
    };
}

const SC = linux.SYS;

// ─── brk / sbrk ────────────────────────────────────────────────────────────

fn brkLinux(_: ?*anyopaque) callconv(.c) c_int {
    std.c._errno().* = @intFromEnum(linux.E.NOMEM);
    return -1;
}

fn sbrkLinux(inc: isize) callconv(.c) ?*anyopaque {
    if (inc != 0) {
        std.c._errno().* = @intFromEnum(linux.E.NOMEM);
        return @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
    }
    const rc: isize = @bitCast(linux.brk(0));
    if (rc < 0) {
        std.c._errno().* = @intCast(-rc);
        return @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
    }
    return @ptrFromInt(@as(usize, @bitCast(rc)));
}

// ─── copy_file_range ────────────────────────────────────────────────────────

fn copy_file_rangeLinux(fd_in: c_int, off_in: ?*i64, fd_out: c_int, off_out: ?*i64, len: usize, flags: c_uint) callconv(.c) isize {
    return errnoSize(linux.copy_file_range(fd_in, off_in, fd_out, off_out, len, flags));
}

// ─── epoll ──────────────────────────────────────────────────────────────────

fn epoll_createLinux(size: c_int) callconv(.c) c_int {
    if (size <= 0) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    return epoll_create1Linux(0);
}

fn epoll_create1Linux(flags: c_int) callconv(.c) c_int {
    return errno(linux.epoll_create1(@bitCast(@as(isize, flags))));
}

fn epoll_ctlLinux(epfd: c_int, op: c_int, fd: c_int, ev: ?*linux.epoll_event) callconv(.c) c_int {
    return errno(linux.epoll_ctl(epfd, @bitCast(op), fd, ev));
}

fn epoll_pwaitLinux(epfd: c_int, events: [*]linux.epoll_event, maxevents: c_int, timeout: c_int, sigmask: ?*const linux.sigset_t) callconv(.c) c_int {
    return errno(linux.epoll_pwait(epfd, events, @bitCast(maxevents), timeout, sigmask));
}

fn epoll_waitLinux(epfd: c_int, events: [*]linux.epoll_event, maxevents: c_int, timeout: c_int) callconv(.c) c_int {
    return epoll_pwaitLinux(epfd, events, maxevents, timeout, null);
}

// ─── eventfd ────────────────────────────────────────────────────────────────

fn eventfdLinux(count: c_uint, flags: c_int) callconv(.c) c_int {
    return errno(linux.eventfd(count, @bitCast(flags)));
}

fn eventfd_readLinux(fd: c_int, value: *u64) callconv(.c) c_int {
    const rc: isize = @bitCast(linux.read(fd, @as([*]u8, @ptrCast(value)), 8));
    if (rc == 8) return 0;
    if (rc < 0) {
        std.c._errno().* = @intCast(-rc);
    }
    return -1;
}

fn eventfd_writeLinux(fd: c_int, value: u64) callconv(.c) c_int {
    var buf = value;
    const rc: isize = @bitCast(linux.write(fd, @as([*]const u8, @ptrCast(&buf)), 8));
    if (rc == 8) return 0;
    if (rc < 0) {
        std.c._errno().* = @intCast(-rc);
    }
    return -1;
}

// ─── fanotify ───────────────────────────────────────────────────────────────

fn fanotify_initLinux(flags: c_uint, event_f_flags: c_uint) callconv(.c) c_int {
    return errno(linux.syscall2(.fanotify_init, arg(flags), arg(event_f_flags)));
}

fn fanotify_markLinux(fanotify_fd: c_int, flags: c_uint, mask: u64, dfd: c_int, pathname: ?[*:0]const u8) callconv(.c) c_int {
    return errno(linux.syscall5(.fanotify_mark, arg(fanotify_fd), arg(flags), arg(mask), arg(dfd), arg(pathname)));
}

// ─── getdents ───────────────────────────────────────────────────────────────

fn getdentsLinux(fd: c_int, buf: *anyopaque, len: usize) callconv(.c) c_int {
    const clamped = @min(len, @as(usize, @intCast(std.math.maxInt(c_int))));
    return errno(linux.getdents(fd, @ptrCast(buf), clamped));
}

// ─── getrandom ──────────────────────────────────────────────────────────────

fn getrandomLinux(buf: *anyopaque, buflen: usize, flags: c_uint) callconv(.c) isize {
    return errnoSize(linux.getrandom(@ptrCast(buf), buflen, flags));
}

// ─── gettid ─────────────────────────────────────────────────────────────────

fn gettidLinux() callconv(.c) c_int {
    return @bitCast(@as(u32, @truncate(linux.syscall0(.gettid))));
}

// ─── inotify ────────────────────────────────────────────────────────────────

fn inotify_initLinux() callconv(.c) c_int {
    return inotify_init1Linux(0);
}

fn inotify_init1Linux(flags: c_int) callconv(.c) c_int {
    return errno(linux.inotify_init1(@bitCast(flags)));
}

fn inotify_add_watchLinux(fd: c_int, pathname: [*:0]const u8, mask: u32) callconv(.c) c_int {
    return errno(linux.inotify_add_watch(fd, pathname, mask));
}

fn inotify_rm_watchLinux(fd: c_int, wd: c_int) callconv(.c) c_int {
    return errno(linux.inotify_rm_watch(fd, wd));
}

// ─── klogctl ────────────────────────────────────────────────────────────────

fn klogctlLinux(log_type: c_int, buf: ?[*]u8, len: c_int) callconv(.c) c_int {
    return errno(linux.syscall3(.syslog, arg(log_type), arg(buf), arg(len)));
}

// ─── memfd_create ───────────────────────────────────────────────────────────

fn memfd_createLinux(name: [*:0]const u8, flags: c_uint) callconv(.c) c_int {
    return errno(linux.memfd_create(name, flags));
}

// ─── mlock2 ─────────────────────────────────────────────────────────────────

fn mlock2Linux(addr: *const anyopaque, len: usize, flags: c_uint) callconv(.c) c_int {
    if (flags == 0)
        return errno(linux.syscall2(.mlock, arg(addr), arg(len)));
    return errno(linux.syscall3(.mlock2, arg(addr), arg(len), arg(flags)));
}

// ─── module ─────────────────────────────────────────────────────────────────

fn init_moduleLinux(image: *anyopaque, len: c_ulong, params: [*:0]const u8) callconv(.c) c_int {
    return errno(linux.syscall3(.init_module, arg(image), arg(len), arg(params)));
}

fn delete_moduleLinux(name: [*:0]const u8, flags: c_uint) callconv(.c) c_int {
    return errno(linux.syscall2(.delete_module, arg(name), arg(flags)));
}

// ─── mount ──────────────────────────────────────────────────────────────────

fn mountLinux(special: ?[*:0]const u8, dir: [*:0]const u8, fstype: ?[*:0]const u8, flags: c_ulong, data: ?*const anyopaque) callconv(.c) c_int {
    return errno(linux.mount(special, dir, fstype, @intCast(flags), arg(data)));
}

fn umountLinux(special: [*:0]const u8) callconv(.c) c_int {
    return errno(linux.umount2(special, 0));
}

fn umount2Linux(special: [*:0]const u8, flags: c_int) callconv(.c) c_int {
    return errno(linux.umount2(special, @bitCast(flags)));
}

// ─── name_to_handle_at / open_by_handle_at ──────────────────────────────────

fn name_to_handle_atLinux(dirfd: c_int, pathname: [*:0]const u8, handle: *anyopaque, mount_id: *c_int, flags: c_int) callconv(.c) c_int {
    return errno(linux.syscall5(.name_to_handle_at, arg(dirfd), arg(pathname), arg(handle), arg(mount_id), arg(flags)));
}

fn open_by_handle_atLinux(mount_fd: c_int, handle: *anyopaque, flags: c_int) callconv(.c) c_int {
    return errno(linux.syscall3(.open_by_handle_at, arg(mount_fd), arg(handle), arg(flags)));
}

// ─── pivot_root ─────────────────────────────────────────────────────────────

fn pivot_rootLinux(new_root: [*:0]const u8, put_old: [*:0]const u8) callconv(.c) c_int {
    return errno(linux.pivot_root(new_root, put_old));
}

// ─── prctl ──────────────────────────────────────────────────────────────────

fn prctlLinux(op: c_int, a2: c_ulong, a3: c_ulong, a4: c_ulong, a5: c_ulong) callconv(.c) c_int {
    return errno(linux.prctl(op, a2, a3, a4, a5));
}

// ─── process_vm ─────────────────────────────────────────────────────────────

fn process_vm_readvLinux(pid: linux.pid_t, lvec: *const anyopaque, liovcnt: c_ulong, rvec: *const anyopaque, riovcnt: c_ulong, flags: c_ulong) callconv(.c) isize {
    return errnoSize(linux.syscall6(.process_vm_readv, arg(pid), arg(lvec), arg(liovcnt), arg(rvec), arg(riovcnt), arg(flags)));
}

fn process_vm_writevLinux(pid: linux.pid_t, lvec: *const anyopaque, liovcnt: c_ulong, rvec: *const anyopaque, riovcnt: c_ulong, flags: c_ulong) callconv(.c) isize {
    return errnoSize(linux.syscall6(.process_vm_writev, arg(pid), arg(lvec), arg(liovcnt), arg(rvec), arg(riovcnt), arg(flags)));
}

// ─── prlimit ────────────────────────────────────────────────────────────────

fn prlimitLinux(pid: linux.pid_t, resource: c_int, new_limit: ?*const anyopaque, old_limit: ?*anyopaque) callconv(.c) c_int {
    return errno(linux.syscall4(.prlimit64, arg(pid), arg(resource), arg(new_limit), arg(old_limit)));
}

// ─── ptrace ─────────────────────────────────────────────────────────────────

fn ptraceLinux(req: c_int, pid: linux.pid_t, addr: ?*anyopaque, data: ?*anyopaque) callconv(.c) c_long {
    const req_u: c_uint = @bitCast(req);
    var result: c_long = 0;
    // For PEEKTEXT(1), PEEKDATA(2), PEEKUSER(3): result is returned via &result
    const actual_data: usize = if (req_u -% 1 < 3) arg(&result) else arg(data);
    const ret: isize = @bitCast(linux.ptrace(@intCast(req_u), pid, arg(addr), actual_data, 0));
    if (ret < 0) {
        @branchHint(.unlikely);
        std.c._errno().* = @intCast(-ret);
        return -1;
    }
    return if (req_u -% 1 < 3) result else @intCast(ret);
}

// ─── quotactl ───────────────────────────────────────────────────────────────

fn quotactlLinux(cmd: c_int, special: ?[*:0]const u8, id: c_int, addr: ?[*]u8) callconv(.c) c_int {
    return errno(linux.syscall4(.quotactl, arg(cmd), arg(special), arg(id), arg(addr)));
}

// ─── readahead ──────────────────────────────────────────────────────────────

fn readaheadLinux(fd: c_int, pos: i64, len: usize) callconv(.c) isize {
    return errnoSize(linux.syscall3(.readahead, arg(fd), arg(pos), arg(len)));
}

// ─── remap_file_pages ───────────────────────────────────────────────────────

fn remap_file_pagesLinux(addr: *anyopaque, size: usize, prot: c_int, pgoff: usize, flags: c_int) callconv(.c) c_int {
    return errno(linux.syscall5(.remap_file_pages, arg(addr), arg(size), arg(prot), arg(pgoff), arg(flags)));
}

// ─── sendfile ───────────────────────────────────────────────────────────────

fn sendfileLinux(out_fd: c_int, in_fd: c_int, ofs: ?*i64, count: usize) callconv(.c) isize {
    return errnoSize(linux.sendfile(out_fd, in_fd, ofs, count));
}

// ─── setfsgid / setfsuid ────────────────────────────────────────────────────

fn setfsgidLinux(gid: linux.gid_t) callconv(.c) c_int {
    return errno(linux.syscall1(.setfsgid, arg(gid)));
}

fn setfsuidLinux(uid: linux.uid_t) callconv(.c) c_int {
    return errno(linux.syscall1(.setfsuid, arg(uid)));
}

// ─── setgroups ──────────────────────────────────────────────────────────────

fn setgroupsLinux(count: usize, list: [*]const linux.gid_t) callconv(.c) c_int {
    return errno(linux.setgroups(count, list));
}

// ─── sethostname ────────────────────────────────────────────────────────────

fn sethostnameLinux(name: [*]const u8, len: usize) callconv(.c) c_int {
    return errno(linux.syscall2(.sethostname, arg(name), arg(len)));
}

// ─── setns ──────────────────────────────────────────────────────────────────

fn setnsLinux(fd: c_int, nstype: c_int) callconv(.c) c_int {
    return errno(linux.setns(fd, @bitCast(nstype)));
}

// ─── signalfd ───────────────────────────────────────────────────────────────

fn signalfdLinux(fd: c_int, sigs: *const linux.sigset_t, flags: c_int) callconv(.c) c_int {
    return errno(linux.signalfd(fd, sigs, @bitCast(flags)));
}

// ─── splice / tee / vmsplice ────────────────────────────────────────────────

fn spliceLinux(fd_in: c_int, off_in: ?*i64, fd_out: c_int, off_out: ?*i64, len: usize, flags: c_uint) callconv(.c) isize {
    return errnoSize(linux.syscall6(.splice, arg(fd_in), arg(off_in), arg(fd_out), arg(off_out), arg(len), arg(flags)));
}

fn teeLinux(src: c_int, dest: c_int, len: usize, flags: c_uint) callconv(.c) isize {
    return errnoSize(linux.syscall4(.tee, arg(src), arg(dest), arg(len), arg(flags)));
}

fn vmspliceLinux(fd: c_int, iov: *const anyopaque, cnt: usize, flags: c_uint) callconv(.c) isize {
    return errnoSize(linux.syscall4(.vmsplice, arg(fd), arg(iov), arg(cnt), arg(flags)));
}

// ─── statx ──────────────────────────────────────────────────────────────────

fn statxLinux(dirfd: c_int, path: [*:0]const u8, flags: c_int, mask: c_uint, stx: *anyopaque) callconv(.c) c_int {
    return errno(linux.syscall5(.statx, arg(dirfd), arg(path), arg(flags), arg(mask), arg(stx)));
}

// ─── swap ───────────────────────────────────────────────────────────────────

fn swaponLinux(path: [*:0]const u8, flags: c_int) callconv(.c) c_int {
    return errno(linux.syscall2(.swapon, arg(path), arg(flags)));
}

fn swapoffLinux(path: [*:0]const u8) callconv(.c) c_int {
    return errno(linux.syscall1(.swapoff, arg(path)));
}

// ─── syncfs ─────────────────────────────────────────────────────────────────

fn syncfsLinux(fd: c_int) callconv(.c) c_int {
    return errno(linux.syncfs(fd));
}

// ─── sync_file_range ────────────────────────────────────────────────────────

fn sync_file_rangeLinux(fd: c_int, pos: i64, len: i64, flags: c_uint) callconv(.c) c_int {
    const sys = if (@hasField(SC, "sync_file_range2"))
        SC.sync_file_range2
    else if (@hasField(SC, "sync_file_range"))
        SC.sync_file_range
    else
        return errno(@as(usize, @bitCast(@as(isize, -@as(isize, @intFromEnum(linux.E.NOSYS))))));
    if (@hasField(SC, "sync_file_range2")) {
        return errno(linux.syscall4(sys, arg(fd), arg(flags), arg(pos), arg(len)));
    }
    return errno(linux.syscall4(sys, arg(fd), arg(pos), arg(len), arg(flags)));
}

// ─── sysinfo ────────────────────────────────────────────────────────────────

fn sysinfoLinux(info: *anyopaque) callconv(.c) c_int {
    return errno(linux.syscall1(.sysinfo, arg(info)));
}

// ─── timerfd ────────────────────────────────────────────────────────────────

fn timerfd_createLinux(clockid: c_int, flags: c_int) callconv(.c) c_int {
    return errno(linux.syscall2(.timerfd_create, arg(clockid), arg(flags)));
}

fn timerfd_settimeLinux(fd: c_int, flags: c_int, new_value: *const anyopaque, old_value: ?*anyopaque) callconv(.c) c_int {
    const sys = if (@hasField(SC, "timerfd_settime64")) SC.timerfd_settime64 else SC.timerfd_settime;
    return errno(linux.syscall4(sys, arg(fd), arg(flags), arg(new_value), arg(old_value)));
}

fn timerfd_gettimeLinux(fd: c_int, cur: *anyopaque) callconv(.c) c_int {
    const sys = if (@hasField(SC, "timerfd_gettime64")) SC.timerfd_gettime64 else SC.timerfd_gettime;
    return errno(linux.syscall2(sys, arg(fd), arg(cur)));
}

// ─── unshare ────────────────────────────────────────────────────────────────

fn unshareLinux(flags: c_int) callconv(.c) c_int {
    return errno(linux.unshare(@bitCast(@as(isize, flags))));
}

// ─── vhangup ────────────────────────────────────────────────────────────────

fn vhangupLinux() callconv(.c) c_int {
    return errno(linux.syscall0(.vhangup));
}

// ─── wait ───────────────────────────────────────────────────────────────────

fn wait3Linux(status: ?*c_int, options: c_int, usage: ?*anyopaque) callconv(.c) linux.pid_t {
    return wait4Linux(-1, status, options, usage);
}

fn wait4Linux(pid: linux.pid_t, status: ?*c_int, options: c_int, ru: ?*anyopaque) callconv(.c) linux.pid_t {
    return errno(linux.syscall4(.wait4, arg(pid), arg(status), arg(options), arg(ru)));
}

// ─── xattr ──────────────────────────────────────────────────────────────────

fn getxattrLinux(path: [*:0]const u8, name: [*:0]const u8, value: ?*anyopaque, size: usize) callconv(.c) isize {
    return errnoSize(linux.syscall4(.getxattr, arg(path), arg(name), arg(value), arg(size)));
}

fn lgetxattrLinux(path: [*:0]const u8, name: [*:0]const u8, value: ?*anyopaque, size: usize) callconv(.c) isize {
    return errnoSize(linux.syscall4(.lgetxattr, arg(path), arg(name), arg(value), arg(size)));
}

fn fgetxattrLinux(fd: c_int, name: [*:0]const u8, value: ?*anyopaque, size: usize) callconv(.c) isize {
    return errnoSize(linux.syscall4(.fgetxattr, arg(fd), arg(name), arg(value), arg(size)));
}

fn listxattrLinux(path: [*:0]const u8, list: ?[*]u8, size: usize) callconv(.c) isize {
    return errnoSize(linux.syscall3(.listxattr, arg(path), arg(list), arg(size)));
}

fn llistxattrLinux(path: [*:0]const u8, list: ?[*]u8, size: usize) callconv(.c) isize {
    return errnoSize(linux.syscall3(.llistxattr, arg(path), arg(list), arg(size)));
}

fn flistxattrLinux(fd: c_int, list: ?[*]u8, size: usize) callconv(.c) isize {
    return errnoSize(linux.syscall3(.flistxattr, arg(fd), arg(list), arg(size)));
}

fn setxattrLinux(path: [*:0]const u8, name: [*:0]const u8, value: ?*const anyopaque, size: usize, flags: c_int) callconv(.c) c_int {
    return errno(linux.syscall5(.setxattr, arg(path), arg(name), arg(value), arg(size), arg(flags)));
}

fn lsetxattrLinux(path: [*:0]const u8, name: [*:0]const u8, value: ?*const anyopaque, size: usize, flags: c_int) callconv(.c) c_int {
    return errno(linux.syscall5(.lsetxattr, arg(path), arg(name), arg(value), arg(size), arg(flags)));
}

fn fsetxattrLinux(fd: c_int, name: [*:0]const u8, value: ?*const anyopaque, size: usize, flags: c_int) callconv(.c) c_int {
    return errno(linux.syscall5(.fsetxattr, arg(fd), arg(name), arg(value), arg(size), arg(flags)));
}

fn removexattrLinux(path: [*:0]const u8, name: [*:0]const u8) callconv(.c) c_int {
    return errno(linux.syscall2(.removexattr, arg(path), arg(name)));
}

fn lremovexattrLinux(path: [*:0]const u8, name: [*:0]const u8) callconv(.c) c_int {
    return errno(linux.syscall2(.lremovexattr, arg(path), arg(name)));
}

fn fremovexattrLinux(fd: c_int, name: [*:0]const u8) callconv(.c) c_int {
    return errno(linux.syscall2(.fremovexattr, arg(fd), arg(name)));
}

// ─── preadv2 / pwritev2 ────────────────────────────────────────────────────

fn preadv2Linux(fd: c_int, iov: *const anyopaque, count: c_int, ofs: i64, flags: c_int) callconv(.c) isize {
    return errnoSize(linux.syscall6(.preadv2, arg(fd), arg(iov), arg(count), arg(ofs), arg(@as(u64, @bitCast(ofs)) >> 32), arg(flags)));
}

fn pwritev2Linux(fd: c_int, iov: *const anyopaque, count: c_int, ofs: i64, flags: c_int) callconv(.c) isize {
    return errnoSize(linux.syscall6(.pwritev2, arg(fd), arg(iov), arg(count), arg(ofs), arg(@as(u64, @bitCast(ofs)) >> 32), arg(flags)));
}

// ─── clock_adjtime / adjtimex ───────────────────────────────────────────────

fn clock_adjtimeLinux(clock_id: c_int, utx: *anyopaque) callconv(.c) c_int {
    const sys = if (@hasField(SC, "clock_adjtime64")) SC.clock_adjtime64 else SC.clock_adjtime;
    return errno(linux.syscall2(sys, arg(clock_id), arg(utx)));
}

fn adjtimexLinux(tx: *anyopaque) callconv(.c) c_int {
    return clock_adjtimeLinux(0, tx); // CLOCK_REALTIME = 0
}

// ─── settimeofday / stime ───────────────────────────────────────────────────

fn settimeofdayLinux(tv: ?*const linux.timeval, _: ?*const anyopaque) callconv(.c) c_int {
    const t = tv orelse return 0;
    if (@as(u64, @bitCast(t.usec)) >= 1000000) {
        std.c._errno().* = @intFromEnum(linux.E.INVAL);
        return -1;
    }
    const ts = linux.timespec{
        .sec = t.sec,
        .nsec = @intCast(t.usec * 1000),
    };
    return errno(linux.clock_settime(.REALTIME, &ts));
}

fn stimeLinux(t: *const linux.time_t) callconv(.c) c_int {
    const tv = linux.timeval{ .sec = t.*, .usec = 0 };
    return settimeofdayLinux(&tv, null);
}

// ─── utimes ─────────────────────────────────────────────────────────────────

fn utimesLinux(path: [*:0]const u8, times: ?*const [2]linux.timeval) callconv(.c) c_int {
    if (times) |tv| {
        const ts = [2]linux.timespec{
            .{ .sec = tv[0].sec, .nsec = @intCast(tv[0].usec * 1000) },
            .{ .sec = tv[1].sec, .nsec = @intCast(tv[1].usec * 1000) },
        };
        return errno(linux.utimensat(linux.AT.FDCWD, path, &ts, 0));
    }
    return errno(linux.utimensat(linux.AT.FDCWD, path, null, 0));
}

// ─── arch-specific ──────────────────────────────────────────────────────────

fn iopermLinux(from: c_ulong, num: c_ulong, turn_on: c_int) callconv(.c) c_int {
    return errno(linux.syscall3(.ioperm, arg(from), arg(num), arg(turn_on)));
}

fn ioplLinux(level: c_int) callconv(.c) c_int {
    return errno(linux.syscall1(.iopl, arg(level)));
}

fn arch_prctlLinux(code: c_int, addr: c_ulong) callconv(.c) c_int {
    return errno(linux.syscall2(.arch_prctl, arg(code), arg(addr)));
}

fn personalityLinux(persona: c_ulong) callconv(.c) c_int {
    return errno(linux.syscall1(.personality, arg(persona)));
}

// ─── cache (arch-specific) ──────────────────────────────────────────────────

fn cacheflushLinux(addr: *anyopaque, len: c_int, op: c_int) callconv(.c) c_int {
    return errno(linux.syscall3(.cacheflush, arg(addr), arg(len), arg(op)));
}

fn cachectlLinux(addr: *anyopaque, len: c_int, op: c_int) callconv(.c) c_int {
    return errno(linux.syscall3(.cachectl, arg(addr), arg(len), arg(op)));
}

fn riscv_flush_icacheLinux(start: *anyopaque, end: *anyopaque, flags: c_ulong) callconv(.c) c_int {
    return errno(linux.syscall3(.riscv_flush_icache, arg(start), arg(end), arg(flags)));
}

// ─── clone (link_libc) ─────────────────────────────────────────────────────

fn cloneLinux(func: *const fn (*anyopaque) callconv(.c) c_int, stack: ?*anyopaque, flags: c_int, func_arg: ?*anyopaque) callconv(.c) c_int {
    _ = func;
    _ = stack;
    _ = flags;
    _ = func_arg;
    std.c._errno().* = @intFromEnum(linux.E.NOSYS);
    return -1;
}

// ─── membarrier (link_libc) ─────────────────────────────────────────────────

fn membarrierLinux(cmd: c_int, flags: c_int) callconv(.c) c_int {
    return errno(linux.syscall2(.membarrier, arg(cmd), arg(flags)));
}

fn membarrier_initLinux() callconv(.c) void {
    _ = linux.syscall2(.membarrier, 4, 0); // MEMBARRIER_CMD_REGISTER_PRIVATE_EXPEDITED = 4
}
