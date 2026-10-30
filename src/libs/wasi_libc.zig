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

pub fn execModelCrtFile(wasi_exec_model: std.lang.WasiExecModel) CrtFile {
    return switch (wasi_exec_model) {
        .reactor => CrtFile.crt1_reactor_o,
        .command => CrtFile.crt1_command_o,
    };
}

pub fn execModelCrtFileFullName(wasi_exec_model: std.lang.WasiExecModel) []const u8 {
    return switch (execModelCrtFile(wasi_exec_model)) {
        .crt1_reactor_o => "crt1-reactor.o",
        .crt1_command_o => "crt1-command.o",
        else => unreachable,
    };
}

/// TODO replace anyerror with explicit error set, recording user-friendly errors with
/// lockAndSetMiscFailure and returning error.AlreadyReported. see libcxx.zig for example.
pub fn buildCrtFile(comp: *Compilation, crt_file: CrtFile, prog_node: std.Progress.Node) anyerror!void {
    const gpa = comp.gpa;
    const io = comp.io;

    switch (crt_file) {
        .crt1_reactor_o => {
            var out: ?Compilation.CrtFile = null;
            try comp.buildOutputFromZig(
                "c/wasi_crt1_reactor.zig",
                "crt1-reactor",
                .Obj,
                .static,
                .@"wasi crt1-reactor.o",
                prog_node,
                .{},
                &out,
            );
            errdefer if (out) |*cf| cf.deinit(gpa, io);
            const basename = try gpa.dupe(u8, "crt1-reactor.o");
            errdefer gpa.free(basename);
            comp.mutex.lockUncancelable(io);
            defer comp.mutex.unlock(io);
            try comp.crt_files.ensureUnusedCapacity(gpa, 1);
            comp.crt_files.putAssumeCapacityNoClobber(basename, out.?);
        },
        .crt1_command_o => {
            var out: ?Compilation.CrtFile = null;
            try comp.buildOutputFromZig(
                "c/wasi_crt1_command.zig",
                "crt1-command",
                .Obj,
                .static,
                .@"wasi crt1-command.o",
                prog_node,
                .{},
                &out,
            );
            errdefer if (out) |*cf| cf.deinit(gpa, io);
            const basename = try gpa.dupe(u8, "crt1-command.o");
            errdefer gpa.free(basename);
            comp.mutex.lockUncancelable(io);
            defer comp.mutex.unlock(io);
            try comp.crt_files.ensureUnusedCapacity(gpa, 1);
            comp.crt_files.putAssumeCapacityNoClobber(basename, out.?);
        },
        .libc_a => {
            if (!build_options.have_llvm) {
                return error.ZigCompilerNotBuiltWithLLVMExtensions;
            }
            var arena_allocator = std.heap.ArenaAllocator.init(gpa);
            defer arena_allocator.deinit();
            const arena = arena_allocator.allocator();
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
    const os_name = if (target.isWasiLibC()) "wasi" else @tagName(target.os.tag);
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

const libc_bottom_half_src_files = [_][]const u8{};
const libc_top_half_src_files = [_][]const u8{
    // "musl/src/complex/__cexp.c", // migrated to lib/c/complex.zig
    // "musl/src/complex/__cexpf.c", // migrated to lib/c/complex.zig
    // "musl/src/conf/confstr.c", // migrated to lib/c/conf.zig
    // "musl/src/conf/legacy.c", // migrated to lib/c/conf.zig
    // "musl/src/conf/pathconf.c", // migrated to lib/c/conf.zig
    // "musl/src/crypt/crypt_blowfish.c", // migrated to lib/c/crypt.zig
    // "musl/src/crypt/crypt.c", // migrated to lib/c/crypt.zig
    // "musl/src/crypt/crypt_des.c", // migrated to lib/c/crypt.zig
    // "musl/src/crypt/crypt_md5.c", // migrated to lib/c/crypt.zig
    // "musl/src/crypt/crypt_r.c", // migrated to lib/c/crypt.zig
    // "musl/src/crypt/crypt_sha256.c", // migrated to lib/c/crypt.zig
    // "musl/src/crypt/crypt_sha512.c", // migrated to lib/c/crypt.zig
    // "musl/src/crypt/encrypt.c", // migrated to lib/c/crypt.zig
    // "musl/src/env/setenv.c", // migrated to lib/c/env.zig
    // "musl/src/exit/assert.c", // migrated to lib/c/exit.zig
    // "musl/src/exit/quick_exit.c", // migrated to lib/c/exit.zig
    // "musl/src/fenv/fegetexceptflag.c", // migrated to lib/c/fenv.zig
    // "musl/src/fenv/feholdexcept.c", // migrated to lib/c/fenv.zig
    // "musl/src/fenv/fenv.c", // migrated to lib/c/fenv.zig
    // "musl/src/fenv/fesetexceptflag.c", // migrated to lib/c/fenv.zig
    // "musl/src/fenv/fesetround.c", // migrated to lib/c/fenv.zig
    // "musl/src/fenv/feupdateenv.c", // migrated to lib/c/fenv.zig
    // "musl/src/legacy/getpagesize.c", // migrated to lib/c/legacy.zig
    // "musl/src/locale/c_locale.c", // migrated to lib/c/locale.zig
    // "musl/src/locale/duplocale.c", // migrated to lib/c/locale.zig
    // "musl/src/locale/freelocale.c", // migrated to lib/c/locale.zig
    // "musl/src/locale/iconv.c", // migrated to lib/c/locale.zig
    // "musl/src/locale/iconv_close.c", // migrated to lib/c/locale.zig
    // "musl/src/locale/langinfo.c", // migrated to lib/c/locale.zig
    // "musl/src/locale/__lctrans.c", // migrated to lib/c/locale.zig
    // "musl/src/locale/localeconv.c", // migrated to lib/c/locale.zig
    // "musl/src/locale/__mo_lookup.c", // migrated to lib/c/locale.zig
    // "musl/src/locale/pleval.c", // migrated to lib/c/locale.zig
    // "musl/src/locale/setlocale.c", // migrated to lib/c/locale.zig
    // "musl/src/locale/strfmon.c", // migrated to lib/c/locale.zig
    // "musl/src/locale/strtod_l.c", // migrated to lib/c/locale.zig
    // "musl/src/locale/wcscoll.c", // migrated to lib/c/locale.zig
    // "musl/src/locale/wcsxfrm.c", // migrated to lib/c/locale.zig
    // "musl/src/math/acosh.c", // migrated to lib/c/math.zig
    // "musl/src/math/asinh.c", // migrated to lib/c/math.zig
    // "musl/src/math/atan2l.c", // migrated to lib/c/math.zig
    // "musl/src/math/cbrtl.c", // migrated to lib/c/math.zig
    // "musl/src/math/__cos.c", // migrated to lib/c/math.zig
    // "musl/src/math/__cosdf.c", // migrated to lib/c/math.zig
    // "musl/src/math/erfl.c", // migrated to lib/c/math.zig
    // "musl/src/math/exp10l.c", // migrated to lib/c/math.zig
    // "musl/src/math/exp2f_data.c", // migrated to lib/c/math.zig
    // "musl/src/math/exp2l.c", // migrated to lib/c/math.zig
    // "musl/src/math/exp_data.c", // migrated to lib/c/math.zig
    // "musl/src/math/expm1.c", // migrated to lib/c/math.zig
    // "musl/src/math/expm1f.c", // migrated to lib/c/math.zig
    // "musl/src/math/expm1l.c", // migrated to lib/c/math.zig
    // "musl/src/math/__invtrigl.c", // migrated to lib/c/math.zig
    // "musl/src/math/j0.c", // migrated to lib/c/math.zig
    // "musl/src/math/j0f.c", // migrated to lib/c/math.zig
    // "musl/src/math/j1.c", // migrated to lib/c/math.zig
    // "musl/src/math/j1f.c", // migrated to lib/c/math.zig
    // "musl/src/math/jn.c", // migrated to lib/c/math.zig
    // "musl/src/math/jnf.c", // migrated to lib/c/math.zig
    // "musl/src/math/lgammal.c", // migrated to lib/c/math.zig
    // "musl/src/math/llround.c", // migrated to lib/c/math.zig
    // "musl/src/math/__math_divzero.c", // migrated to lib/c/math.zig
    // "musl/src/math/__math_divzerof.c", // migrated to lib/c/math.zig
    // "musl/src/math/__math_invalid.c", // migrated to lib/c/math.zig
    // "musl/src/math/__math_invalidf.c", // migrated to lib/c/math.zig
    // "musl/src/math/__math_invalidl.c", // migrated to lib/c/wasi_sources.zig
    // "musl/src/math/__math_oflow.c", // migrated to lib/c/math.zig
    // "musl/src/math/__math_oflowf.c", // migrated to lib/c/math.zig
    // "musl/src/math/__math_uflow.c", // migrated to lib/c/math.zig
    // "musl/src/math/__math_uflowf.c", // migrated to lib/c/math.zig
    // "musl/src/math/__math_xflow.c", // migrated to lib/c/math.zig
    // "musl/src/math/__math_xflowf.c", // migrated to lib/c/math.zig
    // "musl/src/math/__polevll.c", // migrated to lib/c/math.zig
    // "musl/src/math/pow_data.c", // migrated to lib/c/math.zig
    // "musl/src/math/powf_data.c", // migrated to lib/c/math.zig
    // "musl/src/math/__rem_pio2_large.c", // migrated to lib/c/math.zig
    // "musl/src/math/scalb.c", // migrated to lib/c/math.zig
    // "musl/src/math/__sin.c", // migrated to lib/c/math.zig
    // "musl/src/math/__sindf.c", // migrated to lib/c/math.zig
    // "musl/src/math/__tan.c", // migrated to lib/c/math.zig
    // "musl/src/math/__tandf.c", // migrated to lib/c/math.zig
    // "musl/src/math/tgamma.c", // migrated to lib/c/math.zig
    // "musl/src/math/tgammaf.c", // migrated to lib/c/math.zig
    // "musl/src/math/tgammal.c", // migrated to lib/c/math.zig
    // "musl/src/misc/a64l.c", // migrated to lib/c/misc.zig
    // "musl/src/misc/basename.c", // migrated to lib/c/misc.zig
    // "musl/src/misc/dirname.c", // migrated to lib/c/misc.zig
    // "musl/src/misc/getdomainname.c", // migrated to lib/c/misc.zig
    // "musl/src/misc/gethostid.c", // migrated to lib/c/misc.zig
    // "musl/src/misc/getopt.c", // migrated to lib/c/misc.zig
    // "musl/src/misc/getopt_long.c", // migrated to lib/c/misc.zig
    // "musl/src/misc/getsubopt.c", // migrated to lib/c/misc.zig
    // "musl/src/misc/realpath.c", // migrated to lib/c/misc.zig
    // "musl/src/multibyte/btowc.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/c16rtomb.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/c32rtomb.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/internal.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/mblen.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/mbrlen.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/mbrtoc16.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/mbrtoc32.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/mbrtowc.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/mbsinit.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/mbsnrtowcs.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/mbsrtowcs.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/mbstowcs.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/mbtowc.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/wcrtomb.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/wcsnrtombs.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/wcsrtombs.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/wcstombs.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/wctob.c", // migrated to lib/c/multibyte.zig
    // "musl/src/multibyte/wctomb.c", // migrated to lib/c/multibyte.zig
    // "musl/src/network/htonl.c", // migrated to lib/c/network.zig
    // "musl/src/network/htons.c", // migrated to lib/c/network.zig
    // "musl/src/network/in6addr_any.c", // migrated to lib/c/network.zig
    // "musl/src/network/in6addr_loopback.c", // migrated to lib/c/network.zig
    // "musl/src/network/inet_aton.c", // migrated to lib/c/network.zig
    // "musl/src/network/inet_ntop.c", // migrated to lib/c/network.zig
    // "musl/src/network/inet_pton.c", // migrated to lib/c/network.zig
    // "musl/src/network/ntohl.c", // migrated to lib/c/network.zig
    // "musl/src/network/ntohs.c", // migrated to lib/c/network.zig
    // "musl/src/regex/fnmatch.c", // migrated to lib/c/regex.zig
    // "musl/src/regex/regerror.c", // migrated to lib/c/regex.zig
    // "musl/src/stdio/asprintf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/clearerr.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/dprintf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/ext2.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/ext.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fclose.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/__fclose_ca.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/feof.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/ferror.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fflush.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fgetln.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fgets.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fgetwc.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fgetws.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fileno.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/__fmodeflags.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fopencookie.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fprintf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fputs.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fputwc.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fputws.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fread.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fscanf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fwide.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fwprintf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fwrite.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/fwscanf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/getchar_unlocked.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/getc_unlocked.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/getdelim.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/getline.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/getw.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/getwc.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/getwchar.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/ofl_add.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/__overflow.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/perror.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/putchar_unlocked.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/putc_unlocked.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/puts.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/putw.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/putwc.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/putwchar.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/rewind.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/scanf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/setbuf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/setbuffer.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/setlinebuf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/setvbuf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/snprintf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/sprintf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/sscanf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/__stdio_exit.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/swprintf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/swscanf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/__toread.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/__towrite.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/__uflow.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/ungetc.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/ungetwc.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/vasprintf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/vfwscanf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/vprintf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/vscanf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/vsprintf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/vwprintf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/vwscanf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/wprintf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdio/wscanf.c", // migrated to lib/c/stdio.zig
    // "musl/src/stdlib/atof.c", // migrated to lib/c/stdlib.zig
    // "musl/src/stdlib/ecvt.c", // migrated to lib/c/stdlib.zig
    // "musl/src/stdlib/fcvt.c", // migrated to lib/c/stdlib.zig
    // "musl/src/stdlib/gcvt.c", // migrated to lib/c/stdlib.zig
    // "musl/src/string/strerror_r.c", // migrated to lib/c/string.zig
    // "musl/src/string/strverscmp.c", // migrated to lib/c/string.zig
    // "musl/src/string/wcscasecmp.c", // migrated to lib/c/string.zig
    // "musl/src/string/wcscasecmp_l.c", // migrated to lib/c/string.zig
    // "musl/src/string/wcsncasecmp.c", // migrated to lib/c/string.zig
    // "musl/src/string/wcsncasecmp_l.c", // migrated to lib/c/string.zig
    // "musl/src/thread/default_attr.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_attr_destroy.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_attr_init.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_attr_setdetachstate.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_attr_setstack.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_attr_setstacksize.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_barrierattr_destroy.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_barrierattr_init.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_barrierattr_setpshared.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_cleanup_push.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_condattr_destroy.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_condattr_init.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_condattr_setpshared.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_equal.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_getspecific.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_mutexattr_destroy.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_mutexattr_init.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_mutexattr_setpshared.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_mutexattr_settype.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_mutex_init.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_rwlockattr_destroy.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_rwlockattr_init.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_rwlockattr_setpshared.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_rwlock_destroy.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_rwlock_init.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_setcancelstate.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_setcanceltype.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_setspecific.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/pthread_testcancel.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/thread/thrd_sleep.c", // migrated to lib/c/wasi_thread_stub.zig
    // "musl/src/time/ftime.c", // migrated to lib/c/time.zig
    // "musl/src/time/strptime.c", // migrated to lib/c/time.zig
    // "musl/src/time/timespec_get.c", // migrated to lib/c/time.zig

    // "wasi/libc-top-half/musl/src/conf/fpathconf.c", // migrated to lib/c/conf.zig
    // "wasi/libc-top-half/musl/src/conf/sysconf.c", // migrated to lib/c/conf.zig
    // "wasi/libc-top-half/musl/src/dirent/alphasort.c", // migrated to lib/c/dirent.zig
    // "wasi/libc-top-half/musl/src/dirent/versionsort.c", // migrated to lib/c/dirent.zig
    // "wasi/libc-top-half/musl/src/env/clearenv.c", // migrated to lib/c/env.zig
    // "wasi/libc-top-half/musl/src/env/getenv.c", // migrated to lib/c/env.zig
    // "wasi/libc-top-half/musl/src/env/putenv.c", // migrated to lib/c/env.zig
    // "wasi/libc-top-half/musl/src/env/__stack_chk_fail.c", // migrated to lib/c/env.zig
    // "wasi/libc-top-half/musl/src/env/unsetenv.c", // migrated to lib/c/env.zig
    // "wasi/libc-top-half/musl/src/errno/strerror.c", // migrated to lib/c/errno.zig
    // "wasi/libc-top-half/musl/src/exit/atexit.c", // migrated to lib/c/exit.zig
    // "wasi/libc-top-half/musl/src/exit/at_quick_exit.c", // migrated to lib/c/exit.zig
    // "wasi/libc-top-half/musl/src/exit/exit.c", // migrated to lib/c/exit.zig
    // "wasi/libc-top-half/musl/src/fcntl/creat.c", // migrated to lib/c/fcntl.zig
    // "wasi/libc-top-half/musl/src/internal/defsysinfo.c", // migrated to lib/c/internal.zig
    // "wasi/libc-top-half/musl/src/internal/floatscan.c", // migrated to lib/c/internal.zig
    // "wasi/libc-top-half/musl/src/internal/intscan.c", // migrated to lib/c/internal.zig
    // "wasi/libc-top-half/musl/src/internal/libc.c", // migrated to lib/c/internal.zig
    // "wasi/libc-top-half/musl/src/internal/shgetc.c", // migrated to lib/c/internal.zig
    // "wasi/libc-top-half/musl/src/locale/catclose.c", // migrated to lib/c/locale.zig
    // "wasi/libc-top-half/musl/src/locale/catgets.c", // migrated to lib/c/locale.zig
    // "wasi/libc-top-half/musl/src/locale/catopen.c", // migrated to lib/c/locale.zig
    // "wasi/libc-top-half/musl/src/locale/locale_map.c", // migrated to lib/c/locale.zig
    // "wasi/libc-top-half/musl/src/locale/newlocale.c", // migrated to lib/c/locale.zig
    // "wasi/libc-top-half/musl/src/locale/uselocale.c", // migrated to lib/c/locale.zig
    // "wasi/libc-top-half/musl/src/math/__expo2.c", // migrated to lib/c/math.zig
    // "wasi/libc-top-half/musl/src/math/__expo2f.c", // migrated to lib/c/math.zig
    // "wasi/libc-top-half/musl/src/math/__rem_pio2.c", // migrated to lib/c/math.zig
    // "wasi/libc-top-half/musl/src/math/__rem_pio2f.c", // migrated to lib/c/math.zig
    // "wasi/libc-top-half/musl/src/math/__rem_pio2l.c", // migrated to lib/c/math.zig
    // "wasi/libc-top-half/musl/src/math/sinh.c", // migrated to lib/c/math.zig
    // "wasi/libc-top-half/musl/src/misc/fmtmsg.c", // migrated to lib/c/misc.zig
    // "wasi/libc-top-half/musl/src/misc/nftw.c", // migrated to lib/c/misc.zig
    // "wasi/libc-top-half/musl/src/prng/random.c", // migrated to lib/c/stdlib/random.zig
    // "wasi/libc-top-half/musl/src/regex/glob.c", // migrated to lib/c/regex.zig
    // "wasi/libc-top-half/musl/src/regex/regcomp.c", // migrated to lib/c/regex.zig
    // "wasi/libc-top-half/musl/src/regex/regexec.c", // migrated to lib/c/regex.zig
    // "wasi/libc-top-half/musl/src/regex/tre-mem.c", // migrated to lib/c/regex.zig
    // "wasi/libc-top-half/musl/src/stat/futimesat.c", // migrated to lib/c/stat.zig
    // "wasi/libc-top-half/musl/src/stdio/__fdopen.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/fgetc.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/fgetpos.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/fmemopen.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/fopen.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/__fopen_rb_ca.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/fputc.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/freopen.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/fseek.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/fsetpos.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/ftell.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/getc.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/getchar.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/ofl.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/open_memstream.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/open_wmemstream.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/printf.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/putc.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/putchar.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/stderr.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/stdin.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/__stdio_close.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/__stdio_read.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/__stdio_seek.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/__stdio_write.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/stdout.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/__stdout_write.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/vdprintf.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/vfprintf.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/vfscanf.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/vfwprintf.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/vsnprintf.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/vsscanf.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/vswprintf.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdio/vswscanf.c", // migrated to lib/c/stdio.zig
    // "wasi/libc-top-half/musl/src/stdlib/strtod.c", // migrated to lib/c/stdlib.zig
    // "wasi/libc-top-half/musl/src/stdlib/wcstod.c", // migrated to lib/c/stdlib.zig
    // "wasi/libc-top-half/musl/src/stdlib/wcstol.c", // migrated to lib/c/stdlib.zig
    // "wasi/libc-top-half/musl/src/thread/pthread_attr_get.c", // migrated to lib/c/wasi_thread_stub.zig
    // "wasi/libc-top-half/musl/src/thread/pthread_attr_setguardsize.c", // migrated to lib/c/wasi_thread_stub.zig
    // "wasi/libc-top-half/musl/src/thread/pthread_attr_setschedparam.c", // migrated to lib/c/wasi_thread_stub.zig
    // "wasi/libc-top-half/musl/src/thread/pthread_cancel.c", // migrated to lib/c/wasi_thread_stub.zig
    // "wasi/libc-top-half/musl/src/thread/pthread_condattr_setclock.c", // migrated to lib/c/wasi_thread_stub.zig
    // "wasi/libc-top-half/musl/src/thread/pthread_key_create.c", // migrated to lib/c/wasi_thread_stub.zig
    // "wasi/libc-top-half/musl/src/thread/pthread_mutexattr_setprotocol.c", // migrated to lib/c/wasi_thread_stub.zig
    // "wasi/libc-top-half/musl/src/thread/pthread_mutexattr_setrobust.c", // migrated to lib/c/wasi_thread_stub.zig
    // "wasi/libc-top-half/musl/src/thread/pthread_mutex_destroy.c", // migrated to lib/c/wasi_thread_stub.zig
    // "wasi/libc-top-half/musl/src/thread/pthread_self.c", // migrated to lib/c/wasi_thread_stub.zig
    // "wasi/libc-top-half/musl/src/time/getdate.c", // migrated to lib/c/time.zig
    // "wasi/libc-top-half/musl/src/time/localtime.c", // migrated to lib/c/time.zig
    // "wasi/libc-top-half/musl/src/time/localtime_r.c", // migrated to lib/c/time.zig
    // "wasi/libc-top-half/musl/src/time/mktime.c", // migrated to lib/c/time.zig
    // "wasi/libc-top-half/musl/src/time/strftime.c", // migrated to lib/c/time.zig
    // "wasi/libc-top-half/musl/src/time/__tz.c", // migrated to lib/c/time.zig
    // "wasi/libc-top-half/musl/src/time/wcsftime.c", // migrated to lib/c/time.zig
};

// const crt1_command_src_file = "wasi/libc-bottom-half/crt/crt1-command.c"; // migrated to lib/c/wasi_crt1_command.zig
// const crt1_reactor_src_file = "wasi/libc-bottom-half/crt/crt1-reactor.c"; // migrated to lib/c/wasi_crt1_reactor.zig

const fts_src_files = &[_][]const u8{
    // "wasi/fts/musl-fts/fts.c", // migrated to lib/c/fts.zig
};

const setjmp_src_files = &[_][]const u8{
    // "wasi/libc-top-half/musl/src/setjmp/wasm32/rt.c", // migrated to lib/c/wasi_sources.zig
};

const emulated_dl_src_files = &[_][]const u8{
    // "wasi/libc-top-half/musl/src/misc/dl.c", // migrated to lib/c/wasi_sources.zig
};

const emulated_process_clocks_src_files = &[_][]const u8{
    // "wasi/libc-bottom-half/clocks/clock.c", // migrated to lib/c/wasi_sources.zig
    // "wasi/libc-bottom-half/clocks/getrusage.c", // migrated to lib/c/wasi_sources.zig
    // "wasi/libc-bottom-half/clocks/times.c", // migrated to lib/c/wasi_sources.zig
};

const emulated_getpid_src_files = &[_][]const u8{
    // "wasi/libc-bottom-half/getpid/getpid.c", // migrated to lib/c/wasi_sources.zig
};

const emulated_mman_src_files = &[_][]const u8{
    // "wasi/libc-bottom-half/mman/mman.c", // migrated to lib/c/wasi_sources.zig
};

const emulated_signal_bottom_half_src_files = &[_][]const u8{
    // "wasi/libc-bottom-half/signal/signal.c", // migrated to lib/c/wasi_sources.zig
};

const emulated_signal_top_half_src_files = &[_][]const u8{
    // "musl/src/signal/psignal.c", // migrated to lib/c/wasi_sources.zig
    // "musl/src/string/strsignal.c", // migrated to lib/c/wasi_sources.zig
};
