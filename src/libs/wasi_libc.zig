const std = @import("std");
const mem = std.mem;
const path = std.fs.path;

const Allocator = std.mem.Allocator;
const Compilation = @import("../Compilation.zig");
const build_options = @import("build_options");

pub const CrtFile = enum {
    crt1_reactor_o,
    crt1_command_o,
    libc_a,
};

pub fn execModelCrtFile(wasi_exec_model: std.builtin.WasiExecModel) CrtFile {
    return switch (wasi_exec_model) {
        .reactor => CrtFile.crt1_reactor_o,
        .command => CrtFile.crt1_command_o,
    };
}

pub fn execModelCrtFileFullName(wasi_exec_model: std.builtin.WasiExecModel) []const u8 {
    return switch (execModelCrtFile(wasi_exec_model)) {
        .crt1_reactor_o => "crt1-reactor.o",
        .crt1_command_o => "crt1-command.o",
        else => unreachable,
    };
}

/// TODO replace anyerror with explicit error set, recording user-friendly errors with
/// lockAndSetMiscFailure and returning error.AlreadyReported. see libcxx.zig for example.
pub fn buildCrtFile(comp: *Compilation, crt_file: CrtFile, prog_node: std.Progress.Node) anyerror!void {
    if (!build_options.have_llvm) {
        return error.ZigCompilerNotBuiltWithLLVMExtensions;
    }

    const gpa = comp.gpa;
    var arena_allocator = std.heap.ArenaAllocator.init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    switch (crt_file) {
        .crt1_reactor_o => {
            var args = std.array_list.Managed([]const u8).init(arena);
            try addCCArgs(comp, arena, &args, .{});
            try addLibcBottomHalfIncludes(comp, arena, &args);

            var files = [_]Compilation.CSourceFile{
                .{
                    .src_path = try comp.dirs.zig_lib.join(arena, &.{
                        "libc", try sanitize(arena, crt1_reactor_src_file),
                    }),
                    .extra_flags = args.items,
                    .owner = undefined,
                },
            };

            return comp.build_crt_file("crt1-reactor", .Obj, .@"wasi crt1-reactor.o", prog_node, &files, .{});
        },
        .crt1_command_o => {
            var args = std.array_list.Managed([]const u8).init(arena);
            try addCCArgs(comp, arena, &args, .{});
            try addLibcBottomHalfIncludes(comp, arena, &args);

            var files = [_]Compilation.CSourceFile{
                .{
                    .src_path = try comp.dirs.zig_lib.join(arena, &.{
                        "libc", try sanitize(arena, crt1_command_src_file),
                    }),
                    .extra_flags = args.items,
                    .owner = undefined,
                },
            };

            return comp.build_crt_file("crt1-command", .Obj, .@"wasi crt1-command.o", prog_node, &files, .{});
        },
        .libc_a => {
            var libc_sources = std.array_list.Managed(Compilation.CSourceFile).init(arena);

            {
                // Compile libc-bottom-half.
                var args = std.array_list.Managed([]const u8).init(arena);
                try addCCArgs(comp, arena, &args, .{ .want_O3 = true });
                try addLibcBottomHalfIncludes(comp, arena, &args);

                for (libc_bottom_half_src_files) |file_path| {
                    try libc_sources.append(.{
                        .src_path = try comp.dirs.zig_lib.join(arena, &.{
                            "libc", try sanitize(arena, file_path),
                        }),
                        .extra_flags = args.items,
                        .owner = undefined,
                    });
                }
            }

            {
                // Compile libc-top-half.
                var args = std.array_list.Managed([]const u8).init(arena);
                try addCCArgs(comp, arena, &args, .{ .want_O3 = true });
                try addLibcTopHalfIncludes(comp, arena, &args);

                for (libc_top_half_src_files) |file_path| {
                    try libc_sources.append(.{
                        .src_path = try comp.dirs.zig_lib.join(arena, &.{
                            "libc", try sanitize(arena, file_path),
                        }),
                        .extra_flags = args.items,
                        .owner = undefined,
                    });
                }
            }

            {
                // Compile musl-fts.
                var args = std.array_list.Managed([]const u8).init(arena);
                try addCCArgs(comp, arena, &args, .{ .want_O3 = true });
                try args.appendSlice(&[_][]const u8{
                    "-I",
                    try comp.dirs.zig_lib.join(arena, &.{
                        "libc",
                        "wasi",
                        "fts",
                    }),
                });

                for (fts_src_files) |file_path| {
                    try libc_sources.append(.{
                        .src_path = try comp.dirs.zig_lib.join(arena, &.{
                            "libc", try sanitize(arena, file_path),
                        }),
                        .extra_flags = args.items,
                        .owner = undefined,
                    });
                }
            }

            if (comp.getTarget().cpu.has(.wasm, .exception_handling)) {
                // Compile libsetjmp.
                var args = std.array_list.Managed([]const u8).init(arena);
                try addCCArgs(comp, arena, &args, .{ .want_O3 = true });
                try addLibcTopHalfIncludes(comp, arena, &args);

                for (setjmp_src_files) |file_path| {
                    try libc_sources.append(.{
                        .src_path = try comp.dirs.zig_lib.join(arena, &.{
                            "libc", try sanitize(arena, file_path),
                        }),
                        .extra_flags = args.items,
                        .owner = undefined,
                    });
                }
            }

            {
                // Compile libdl.
                var args = std.array_list.Managed([]const u8).init(arena);
                try addCCArgs(comp, arena, &args, .{ .want_O3 = true });
                try addLibcTopHalfIncludes(comp, arena, &args);

                for (emulated_dl_src_files) |file_path| {
                    try libc_sources.append(.{
                        .src_path = try comp.dirs.zig_lib.join(arena, &.{
                            "libc", try sanitize(arena, file_path),
                        }),
                        .extra_flags = args.items,
                        .owner = undefined,
                    });
                }
            }

            {
                // Compile libwasi-emulated-process-clocks.
                var args = std.array_list.Managed([]const u8).init(arena);
                try addCCArgs(comp, arena, &args, .{ .want_O3 = true });

                for (emulated_process_clocks_src_files) |file_path| {
                    try libc_sources.append(.{
                        .src_path = try comp.dirs.zig_lib.join(arena, &.{
                            "libc", try sanitize(arena, file_path),
                        }),
                        .extra_flags = args.items,
                        .owner = undefined,
                    });
                }
            }

            {
                // Compile libwasi-emulated-getpid.
                var args = std.array_list.Managed([]const u8).init(arena);
                try addCCArgs(comp, arena, &args, .{ .want_O3 = true });

                for (emulated_getpid_src_files) |file_path| {
                    try libc_sources.append(.{
                        .src_path = try comp.dirs.zig_lib.join(arena, &.{
                            "libc", try sanitize(arena, file_path),
                        }),
                        .extra_flags = args.items,
                        .owner = undefined,
                    });
                }
            }

            {
                // Compile libwasi-emulated-mman.
                var args = std.array_list.Managed([]const u8).init(arena);
                try addCCArgs(comp, arena, &args, .{ .want_O3 = true });

                for (emulated_mman_src_files) |file_path| {
                    try libc_sources.append(.{
                        .src_path = try comp.dirs.zig_lib.join(arena, &.{
                            "libc", try sanitize(arena, file_path),
                        }),
                        .extra_flags = args.items,
                        .owner = undefined,
                    });
                }
            }

            {
                // Compile libwasi-emulated-signal.
                var bottom_args = std.array_list.Managed([]const u8).init(arena);
                try addCCArgs(comp, arena, &bottom_args, .{ .want_O3 = true });

                for (emulated_signal_bottom_half_src_files) |file_path| {
                    try libc_sources.append(.{
                        .src_path = try comp.dirs.zig_lib.join(arena, &.{
                            "libc", try sanitize(arena, file_path),
                        }),
                        .extra_flags = bottom_args.items,
                        .owner = undefined,
                    });
                }

                var top_args = std.array_list.Managed([]const u8).init(arena);
                try addCCArgs(comp, arena, &top_args, .{ .want_O3 = true });
                try addLibcTopHalfIncludes(comp, arena, &top_args);
                try top_args.append("-D_WASI_EMULATED_SIGNAL");

                for (emulated_signal_top_half_src_files) |file_path| {
                    try libc_sources.append(.{
                        .src_path = try comp.dirs.zig_lib.join(arena, &.{
                            "libc", try sanitize(arena, file_path),
                        }),
                        .extra_flags = top_args.items,
                        .owner = undefined,
                    });
                }
            }

            try comp.build_crt_file("c", .Lib, .@"wasi libc.a", prog_node, libc_sources.items, .{});
        },
    }
}

fn sanitize(arena: Allocator, file_path: []const u8) ![]const u8 {
    // TODO do this at comptime on the comptime data rather than at runtime
    // probably best to wait until self-hosted is done and our comptime execution
    // is faster and uses less memory.
    const out_path = if (path.sep != '/') blk: {
        const mutable_file_path = try arena.dupe(u8, file_path);
        for (mutable_file_path) |*c| {
            if (c.* == '/') {
                c.* = path.sep;
            }
        }
        break :blk mutable_file_path;
    } else file_path;
    return out_path;
}

const CCOptions = struct {
    want_O3: bool = false,
    no_strict_aliasing: bool = false,
};

fn addCCArgs(
    comp: *Compilation,
    arena: Allocator,
    args: *std.array_list.Managed([]const u8),
    options: CCOptions,
) error{OutOfMemory}!void {
    const target = comp.getTarget();
    const arch_name = std.zig.target.muslArchNameHeaders(target.cpu.arch);
    const os_name = @tagName(target.os.tag);
    const triple = try std.fmt.allocPrint(arena, "{s}-{s}-musl", .{ arch_name, os_name });
    const o_arg = if (options.want_O3) "-O3" else "-Os";

    try args.appendSlice(&[_][]const u8{
        "-std=gnu17",
        "-fno-trapping-math",
        "-w", // ignore all warnings

        o_arg,

        "-mthread-model",
        "single",

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{
            "libc",
            "wasi",
            "libc-bottom-half",
            "cloudlibc",
            "src",
        }),

        "-isystem",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "include", triple }),
        "-isystem",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "include", "generic-musl" }),

        "-DBULK_MEMORY_THRESHOLD=32",
    });

    if (options.no_strict_aliasing) {
        try args.appendSlice(&[_][]const u8{"-fno-strict-aliasing"});
    }
}

fn addLibcBottomHalfIncludes(
    comp: *Compilation,
    arena: Allocator,
    args: *std.array_list.Managed([]const u8),
) error{OutOfMemory}!void {
    try args.appendSlice(&[_][]const u8{
        "-I",
        try comp.dirs.zig_lib.join(arena, &.{
            "libc",
            "wasi",
            "libc-bottom-half",
            "headers",
            "private",
        }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{
            "libc",
            "wasi",
            "libc-bottom-half",
            "cloudlibc",
            "src",
            "include",
        }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{
            "libc",
            "wasi",
            "libc-bottom-half",
            "cloudlibc",
            "src",
        }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{
            "libc",
            "wasi",
            "libc-top-half",
            "musl",
            "src",
            "include",
        }),
        "-I",
        try comp.dirs.zig_lib.join(arena, &.{
            "libc",
            "musl",
            "src",
            "include",
        }),
        "-I",

        try comp.dirs.zig_lib.join(arena, &.{
            "libc",
            "wasi",
            "libc-top-half",
            "musl",
            "src",
            "internal",
        }),
        "-I",
        try comp.dirs.zig_lib.join(arena, &.{
            "libc",
            "musl",
            "src",
            "internal",
        }),
    });
}

fn addLibcTopHalfIncludes(
    comp: *Compilation,
    arena: Allocator,
    args: *std.array_list.Managed([]const u8),
) error{OutOfMemory}!void {
    try args.appendSlice(&[_][]const u8{
        "-I",
        try comp.dirs.zig_lib.join(arena, &.{
            "libc",
            "wasi",
            "libc-top-half",
            "musl",
            "src",
            "include",
        }),
        "-I",
        try comp.dirs.zig_lib.join(arena, &.{
            "libc",
            "musl",
            "src",
            "include",
        }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{
            "libc",
            "wasi",
            "libc-top-half",
            "musl",
            "src",
            "internal",
        }),
        "-I",
        try comp.dirs.zig_lib.join(arena, &.{
            "libc",
            "musl",
            "src",
            "internal",
        }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{
            "libc",
            "wasi",
            "libc-top-half",
            "musl",
            "arch",
            "wasm32",
        }),
        "-I",
        try comp.dirs.zig_lib.join(arena, &.{
            "libc",
            "musl",
            "arch",
            "generic",
        }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{
            "libc",
            "wasi",
            "libc-top-half",
            "headers",
            "private",
        }),
    });
}

const libc_bottom_half_src_files = [_][]const u8{
};

const libc_top_half_src_files = [_][]const u8{
    "musl/src/crypt/crypt_blowfish.c",
    "musl/src/crypt/crypt.c",
    "musl/src/crypt/crypt_des.c",
    "musl/src/crypt/crypt_md5.c",
    "musl/src/crypt/crypt_r.c",
    "musl/src/crypt/crypt_sha256.c",
    "musl/src/crypt/crypt_sha512.c",
    "musl/src/crypt/encrypt.c",
    "musl/src/math/acosh.c",
    "musl/src/math/acoshl.c",
    "musl/src/math/atan2l.c",
    "musl/src/math/atanh.c",
    "musl/src/math/atanhl.c",
    "musl/src/math/cbrtl.c",
    "musl/src/math/coshl.c",
    "musl/src/math/erfl.c",
    "musl/src/math/exp10l.c",
    "musl/src/math/expm1.c",
    "musl/src/math/expm1l.c",
    "musl/src/math/llround.c",
    "musl/src/math/log1p.c",
    "musl/src/math/log1pl.c",
    "musl/src/math/lround.c",
    "musl/src/math/__math_divzero.c",
    "musl/src/math/__math_divzerof.c",
    "musl/src/math/__math_invalid.c",
    "musl/src/math/__math_invalidf.c",
    "musl/src/math/__math_invalidl.c",
    "musl/src/math/__math_oflow.c",
    "musl/src/math/__math_oflowf.c",
    "musl/src/math/__math_uflow.c",
    "musl/src/math/__math_uflowf.c",
    "musl/src/math/__math_xflow.c",
    "musl/src/math/__math_xflowf.c",
    "musl/src/math/tanhl.c",
    "musl/src/math/tgamma.c",
    "musl/src/math/tgammaf.c",
    "musl/src/math/tgammal.c",
    "musl/src/misc/getdomainname.c",
    "musl/src/network/htonl.c",
    "musl/src/network/htons.c",
    "musl/src/network/in6addr_any.c",
    "musl/src/network/in6addr_loopback.c",
    "musl/src/network/inet_aton.c",
    "musl/src/network/inet_ntop.c",
    "musl/src/network/inet_pton.c",
    "musl/src/network/ntohl.c",
    "musl/src/network/ntohs.c",
    "musl/src/stdio/asprintf.c",
    "musl/src/stdio/clearerr.c",
    "musl/src/stdio/dprintf.c",
    "musl/src/stdio/ext2.c",
    "musl/src/stdio/ext.c",
    "musl/src/stdio/fclose.c",
    "musl/src/stdio/__fclose_ca.c",
    "musl/src/stdio/feof.c",
    "musl/src/stdio/ferror.c",
    "musl/src/stdio/fflush.c",
    "musl/src/stdio/fgetln.c",
    "musl/src/stdio/fgets.c",
    "musl/src/stdio/fgetwc.c",
    "musl/src/stdio/fgetws.c",
    "musl/src/stdio/fileno.c",
    "musl/src/stdio/__fmodeflags.c",
    "musl/src/stdio/fopencookie.c",
    "musl/src/stdio/fprintf.c",
    "musl/src/stdio/fputs.c",
    "musl/src/stdio/fputwc.c",
    "musl/src/stdio/fputws.c",
    "musl/src/stdio/fread.c",
    "musl/src/stdio/fscanf.c",
    "musl/src/stdio/fwide.c",
    "musl/src/stdio/fwprintf.c",
    "musl/src/stdio/fwrite.c",
    "musl/src/stdio/fwscanf.c",
    "musl/src/stdio/getchar_unlocked.c",
    "musl/src/stdio/getc_unlocked.c",
    "musl/src/stdio/getdelim.c",
    "musl/src/stdio/getline.c",
    "musl/src/stdio/getw.c",
    "musl/src/stdio/getwc.c",
    "musl/src/stdio/getwchar.c",
    "musl/src/stdio/ofl_add.c",
    "musl/src/stdio/__overflow.c",
    "musl/src/stdio/perror.c",
    "musl/src/stdio/putchar_unlocked.c",
    "musl/src/stdio/putc_unlocked.c",
    "musl/src/stdio/puts.c",
    "musl/src/stdio/putw.c",
    "musl/src/stdio/putwc.c",
    "musl/src/stdio/putwchar.c",
    "musl/src/stdio/rewind.c",
    "musl/src/stdio/scanf.c",
    "musl/src/stdio/setbuf.c",
    "musl/src/stdio/setbuffer.c",
    "musl/src/stdio/setlinebuf.c",
    "musl/src/stdio/setvbuf.c",
    "musl/src/stdio/snprintf.c",
    "musl/src/stdio/sprintf.c",
    "musl/src/stdio/sscanf.c",
    "musl/src/stdio/__stdio_exit.c",
    "musl/src/stdio/swprintf.c",
    "musl/src/stdio/swscanf.c",
    "musl/src/stdio/__toread.c",
    "musl/src/stdio/__towrite.c",
    "musl/src/stdio/__uflow.c",
    "musl/src/stdio/ungetc.c",
    "musl/src/stdio/ungetwc.c",
    "musl/src/stdio/vasprintf.c",
    "musl/src/stdio/vfwscanf.c",
    "musl/src/stdio/vprintf.c",
    "musl/src/stdio/vscanf.c",
    "musl/src/stdio/vsprintf.c",
    "musl/src/stdio/vwprintf.c",
    "musl/src/stdio/vwscanf.c",
    "musl/src/stdio/wprintf.c",
    "musl/src/stdio/wscanf.c",
    "musl/src/thread/default_attr.c",
    "musl/src/thread/pthread_attr_destroy.c",
    "musl/src/thread/pthread_attr_init.c",
    "musl/src/thread/pthread_attr_setdetachstate.c",
    "musl/src/thread/pthread_attr_setstack.c",
    "musl/src/thread/pthread_attr_setstacksize.c",
    "musl/src/thread/pthread_barrierattr_destroy.c",
    "musl/src/thread/pthread_barrierattr_init.c",
    "musl/src/thread/pthread_barrierattr_setpshared.c",
    "musl/src/thread/pthread_cleanup_push.c",
    "musl/src/thread/pthread_condattr_destroy.c",
    "musl/src/thread/pthread_condattr_init.c",
    "musl/src/thread/pthread_condattr_setpshared.c",
    "musl/src/thread/pthread_equal.c",
    "musl/src/thread/pthread_getspecific.c",
    "musl/src/thread/pthread_mutexattr_destroy.c",
    "musl/src/thread/pthread_mutexattr_init.c",
    "musl/src/thread/pthread_mutexattr_setpshared.c",
    "musl/src/thread/pthread_mutexattr_settype.c",
    "musl/src/thread/pthread_mutex_init.c",
    "musl/src/thread/pthread_rwlockattr_destroy.c",
    "musl/src/thread/pthread_rwlockattr_init.c",
    "musl/src/thread/pthread_rwlockattr_setpshared.c",
    "musl/src/thread/pthread_rwlock_destroy.c",
    "musl/src/thread/pthread_rwlock_init.c",
    "musl/src/thread/pthread_setcancelstate.c",
    "musl/src/thread/pthread_setcanceltype.c",
    "musl/src/thread/pthread_setspecific.c",
    "musl/src/thread/pthread_spin_destroy.c",
    "musl/src/thread/pthread_spin_init.c",
    "musl/src/thread/pthread_testcancel.c",
    "musl/src/thread/thrd_sleep.c",
    "musl/src/time/difftime.c",
    "musl/src/time/ftime.c",
    "musl/src/time/strptime.c",
    "musl/src/time/timespec_get.c",

    "wasi/libc-top-half/musl/src/dirent/alphasort.c",
    "wasi/libc-top-half/musl/src/dirent/versionsort.c",
    "wasi/libc-top-half/musl/src/fcntl/creat.c",
    "wasi/libc-top-half/musl/src/internal/defsysinfo.c",
    "wasi/libc-top-half/musl/src/internal/floatscan.c",
    "wasi/libc-top-half/musl/src/internal/intscan.c",
    "wasi/libc-top-half/musl/src/internal/libc.c",
    "wasi/libc-top-half/musl/src/internal/shgetc.c",
    "wasi/libc-top-half/musl/src/stat/futimesat.c",
    "wasi/libc-top-half/musl/src/stdio/__fdopen.c",
    "wasi/libc-top-half/musl/src/stdio/fgetc.c",
    "wasi/libc-top-half/musl/src/stdio/fgetpos.c",
    "wasi/libc-top-half/musl/src/stdio/fmemopen.c",
    "wasi/libc-top-half/musl/src/stdio/fopen.c",
    "wasi/libc-top-half/musl/src/stdio/__fopen_rb_ca.c",
    "wasi/libc-top-half/musl/src/stdio/fputc.c",
    "wasi/libc-top-half/musl/src/stdio/freopen.c",
    "wasi/libc-top-half/musl/src/stdio/fseek.c",
    "wasi/libc-top-half/musl/src/stdio/fsetpos.c",
    "wasi/libc-top-half/musl/src/stdio/ftell.c",
    "wasi/libc-top-half/musl/src/stdio/getc.c",
    "wasi/libc-top-half/musl/src/stdio/getchar.c",
    "wasi/libc-top-half/musl/src/stdio/ofl.c",
    "wasi/libc-top-half/musl/src/stdio/open_memstream.c",
    "wasi/libc-top-half/musl/src/stdio/open_wmemstream.c",
    "wasi/libc-top-half/musl/src/stdio/printf.c",
    "wasi/libc-top-half/musl/src/stdio/putc.c",
    "wasi/libc-top-half/musl/src/stdio/putchar.c",
    "wasi/libc-top-half/musl/src/stdio/stderr.c",
    "wasi/libc-top-half/musl/src/stdio/stdin.c",
    "wasi/libc-top-half/musl/src/stdio/__stdio_close.c",
    "wasi/libc-top-half/musl/src/stdio/__stdio_read.c",
    "wasi/libc-top-half/musl/src/stdio/__stdio_seek.c",
    "wasi/libc-top-half/musl/src/stdio/__stdio_write.c",
    "wasi/libc-top-half/musl/src/stdio/stdout.c",
    "wasi/libc-top-half/musl/src/stdio/__stdout_write.c",
    "wasi/libc-top-half/musl/src/stdio/vdprintf.c",
    "wasi/libc-top-half/musl/src/stdio/vfprintf.c",
    "wasi/libc-top-half/musl/src/stdio/vfscanf.c",
    "wasi/libc-top-half/musl/src/stdio/vfwprintf.c",
    "wasi/libc-top-half/musl/src/stdio/vsnprintf.c",
    "wasi/libc-top-half/musl/src/stdio/vsscanf.c",
    "wasi/libc-top-half/musl/src/stdio/vswprintf.c",
    "wasi/libc-top-half/musl/src/stdio/vswscanf.c",
    "wasi/libc-top-half/musl/src/thread/pthread_attr_get.c",
    "wasi/libc-top-half/musl/src/thread/pthread_attr_setguardsize.c",
    "wasi/libc-top-half/musl/src/thread/pthread_attr_setschedparam.c",
    "wasi/libc-top-half/musl/src/thread/pthread_cancel.c",
    "wasi/libc-top-half/musl/src/thread/pthread_condattr_setclock.c",
    "wasi/libc-top-half/musl/src/thread/pthread_key_create.c",
    "wasi/libc-top-half/musl/src/thread/pthread_mutexattr_setprotocol.c",
    "wasi/libc-top-half/musl/src/thread/pthread_mutexattr_setrobust.c",
    "wasi/libc-top-half/musl/src/thread/pthread_mutex_destroy.c",
    "wasi/libc-top-half/musl/src/thread/pthread_self.c",
    "wasi/libc-top-half/musl/src/time/getdate.c",
    "wasi/libc-top-half/musl/src/time/localtime.c",
    "wasi/libc-top-half/musl/src/time/localtime_r.c",
    "wasi/libc-top-half/musl/src/time/mktime.c",
    "wasi/libc-top-half/musl/src/time/strftime.c",
    "wasi/libc-top-half/musl/src/time/__tz.c",
    "wasi/libc-top-half/musl/src/time/wcsftime.c",

};

const crt1_command_src_file = "wasi/libc-bottom-half/crt/crt1-command.c";
const crt1_reactor_src_file = "wasi/libc-bottom-half/crt/crt1-reactor.c";

const fts_src_files = &[_][]const u8{
    "wasi/fts/musl-fts/fts.c",
};

const setjmp_src_files = &[_][]const u8{
    "wasi/libc-top-half/musl/src/setjmp/wasm32/rt.c",
};

const emulated_dl_src_files = &[_][]const u8{
    "wasi/libc-top-half/musl/src/misc/dl.c",
};

const emulated_process_clocks_src_files = &[_][]const u8{
    "wasi/libc-bottom-half/clocks/clock.c",
    "wasi/libc-bottom-half/clocks/getrusage.c",
    "wasi/libc-bottom-half/clocks/times.c",
};

const emulated_getpid_src_files = &[_][]const u8{
    "wasi/libc-bottom-half/getpid/getpid.c",
};

const emulated_mman_src_files = &[_][]const u8{
    "wasi/libc-bottom-half/mman/mman.c",
};

const emulated_signal_bottom_half_src_files = &[_][]const u8{
    "wasi/libc-bottom-half/signal/signal.c",
};

const emulated_signal_top_half_src_files = &[_][]const u8{
    "musl/src/signal/psignal.c",
};
