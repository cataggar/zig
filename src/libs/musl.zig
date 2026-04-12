const std = @import("std");
const Allocator = std.mem.Allocator;
const mem = std.mem;
const path = std.fs.path;
const assert = std.debug.assert;
const Module = @import("../Package/Module.zig");

const Compilation = @import("../Compilation.zig");
const build_options = @import("build_options");

pub const CrtFile = enum {
    crt1_o,
    rcrt1_o,
    scrt1_o,
    libc_a,
    libc_so,
};

/// TODO replace anyerror with explicit error set, recording user-friendly errors with
/// lockAndSetMiscFailure and returning error.AlreadyReported. see libcxx.zig for example.
pub fn buildCrtFile(comp: *Compilation, in_crt_file: CrtFile, prog_node: std.Progress.Node) anyerror!void {
    if (!build_options.have_llvm) {
        return error.ZigCompilerNotBuiltWithLLVMExtensions;
    }
    const gpa = comp.gpa;
    var arena_allocator = std.heap.ArenaAllocator.init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    const io = comp.io;

    switch (in_crt_file) {
        .crt1_o => {
            var args = std.array_list.Managed([]const u8).init(arena);
            try addCcArgs(comp, arena, &args, false);
            try args.append("-DCRT");
            var files = [_]Compilation.CSourceFile{
                .{
                    .src_path = try comp.dirs.zig_lib.join(arena, &.{
                        "libc", "musl", "crt", "crt1.c",
                    }),
                    .extra_flags = args.items,
                    .owner = undefined,
                },
            };
            return comp.build_crt_file("crt1", .Obj, .@"musl crt1.o", prog_node, &files, .{
                .omit_frame_pointer = true,
                .no_builtin = true,
            });
        },
        .rcrt1_o => {
            var args = std.array_list.Managed([]const u8).init(arena);
            try addCcArgs(comp, arena, &args, false);
            try args.append("-DCRT");
            var files = [_]Compilation.CSourceFile{
                .{
                    .src_path = try comp.dirs.zig_lib.join(arena, &.{
                        "libc", "musl", "crt", "rcrt1.c",
                    }),
                    .extra_flags = args.items,
                    .owner = undefined,
                },
            };
            return comp.build_crt_file("rcrt1", .Obj, .@"musl rcrt1.o", prog_node, &files, .{
                .omit_frame_pointer = true,
                .pic = true,
                .no_builtin = true,
            });
        },
        .scrt1_o => {
            var args = std.array_list.Managed([]const u8).init(arena);
            try addCcArgs(comp, arena, &args, false);
            try args.append("-DCRT");
            var files = [_]Compilation.CSourceFile{
                .{
                    .src_path = try comp.dirs.zig_lib.join(arena, &.{
                        "libc", "musl", "crt", "Scrt1.c",
                    }),
                    .extra_flags = args.items,
                    .owner = undefined,
                },
            };
            return comp.build_crt_file("Scrt1", .Obj, .@"musl Scrt1.o", prog_node, &files, .{
                .omit_frame_pointer = true,
                .pic = true,
                .no_builtin = true,
            });
        },
        .libc_a => {
            // When there is a src/<arch>/foo.* then it should substitute for src/foo.*
            // Even a .s file can substitute for a .c file.
            const target = comp.getTarget();
            const arch_name = std.zig.target.muslArchName(target.cpu.arch, target.abi);
            var source_table: std.array_hash_map.String(Ext) = .empty;
            defer source_table.deinit(gpa);

            try source_table.ensureTotalCapacity(gpa, compat_time32_files.len + src_files.len);

            for (src_files) |src_file| {
                try addSrcFile(arena, &source_table, src_file);
            }

            for (time32_compat_arch_list) |time32_compat_arch| {
                if (mem.eql(u8, arch_name, time32_compat_arch)) {
                    for (compat_time32_files) |compat_time32_file| {
                        try addSrcFile(arena, &source_table, compat_time32_file);
                    }
                }
            }

            var c_source_files = std.array_list.Managed(Compilation.CSourceFile).init(gpa);
            defer c_source_files.deinit();

            var override_path = std.array_list.Managed(u8).init(gpa);
            defer override_path.deinit();

            const s = path.sep_str;

            var it = source_table.iterator();
            while (it.next()) |entry| {
                const src_file = entry.key_ptr.*;
                const ext = entry.value_ptr.*;

                const dirname = path.dirname(src_file).?;
                const basename = path.basename(src_file);
                const noextbasename = basename[0 .. basename.len - std.fs.path.extension(basename).len];
                const dirbasename = path.basename(dirname);

                var is_arch_specific = false;
                // Architecture-specific implementations are under a <arch>/ folder.
                if (isArchName(dirbasename)) {
                    if (!mem.eql(u8, dirbasename, arch_name))
                        continue; // Not the architecture we're compiling for.
                    is_arch_specific = true;
                }
                if (!is_arch_specific) {
                    // Look for an arch specific override.
                    override_path.shrinkRetainingCapacity(0);
                    try override_path.print("{s}" ++ s ++ "{s}" ++ s ++ "{s}.s", .{
                        dirname, arch_name, noextbasename,
                    });
                    if (source_table.contains(override_path.items))
                        continue;

                    override_path.shrinkRetainingCapacity(0);
                    try override_path.print("{s}" ++ s ++ "{s}" ++ s ++ "{s}.S", .{
                        dirname, arch_name, noextbasename,
                    });
                    if (source_table.contains(override_path.items))
                        continue;

                    override_path.shrinkRetainingCapacity(0);
                    try override_path.print("{s}" ++ s ++ "{s}" ++ s ++ "{s}.c", .{
                        dirname, arch_name, noextbasename,
                    });
                    if (source_table.contains(override_path.items))
                        continue;
                }

                var args = std.array_list.Managed([]const u8).init(arena);
                try addCcArgs(comp, arena, &args, ext == .o3);
                const c_source_file = try c_source_files.addOne();
                c_source_file.* = .{
                    .src_path = try comp.dirs.zig_lib.join(arena, &.{ "libc", src_file }),
                    .extra_flags = args.items,
                    .owner = undefined,
                };
            }
            return comp.build_crt_file("c", .Lib, .@"musl libc.a", prog_node, c_source_files.items, .{
                .omit_frame_pointer = true,
                .no_builtin = true,
            });
        },
        .libc_so => {
            const optimize_mode = comp.compilerRtOptMode();
            const strip = comp.compilerRtStrip();
            const output_mode: std.builtin.OutputMode = .Lib;
            const config = try Compilation.Config.resolve(.{
                .output_mode = output_mode,
                .link_mode = .dynamic,
                .resolved_target = comp.root_mod.resolved_target,
                .is_test = false,
                .have_zcu = false,
                .emit_bin = true,
                .root_optimize_mode = optimize_mode,
                .root_strip = strip,
                .link_libc = false,
            });

            const target = &comp.root_mod.resolved_target.result;
            const arch_name = std.zig.target.muslArchName(target.cpu.arch, target.abi);
            const time32 = for (time32_compat_arch_list) |time32_compat_arch| {
                if (mem.eql(u8, arch_name, time32_compat_arch)) break true;
            } else false;
            const arch_define = try std.fmt.allocPrint(arena, "-DARCH_{s}", .{arch_name});
            const family_define = switch (target.cpu.arch) {
                .arm, .armeb, .thumb, .thumbeb => "-DFAMILY_arm",
                .aarch64, .aarch64_be => "-DFAMILY_aarch64",
                .hexagon => "-DFAMILY_hexagon",
                .loongarch64 => "-DFAMILY_loongarch",
                .m68k => "-DFAMILY_m68k",
                .mips, .mipsel, .mips64, .mips64el => "-DFAMILY_mips",
                .powerpc, .powerpc64, .powerpc64le => "-DFAMILY_powerpc",
                .riscv32, .riscv64 => "-DFAMILY_riscv",
                .s390x => "-DFAMILY_s390x",
                .x86, .x86_64 => "-DFAMILY_x86",
                else => unreachable,
            };
            const cc_argv: []const []const u8 = if (target.ptrBitWidth() == 64)
                &.{ "-DPTR64", arch_define, family_define }
            else if (time32)
                &.{ "-DTIME32", arch_define, family_define }
            else
                &.{ arch_define, family_define };

            const root_mod = try Module.create(arena, .{
                .paths = .{
                    .root = .zig_lib_root,
                    .root_src_path = "",
                },
                .fully_qualified_name = "root",
                .inherited = .{
                    .resolved_target = comp.root_mod.resolved_target,
                    .strip = strip,
                    .stack_check = false,
                    .stack_protector = 0,
                    .sanitize_c = .off,
                    .sanitize_thread = false,
                    .red_zone = comp.root_mod.red_zone,
                    .omit_frame_pointer = comp.root_mod.omit_frame_pointer,
                    .valgrind = false,
                    .optimize_mode = optimize_mode,
                    .structured_cfg = comp.root_mod.structured_cfg,
                },
                .global = config,
                .cc_argv = cc_argv,
                .parent = null,
            });

            const misc_task: Compilation.MiscTask = .@"musl libc.so";

            var sub_create_diag: Compilation.CreateDiagnostic = undefined;
            const sub_compilation = Compilation.create(comp.gpa, arena, io, &sub_create_diag, .{
                .thread_limit = comp.thread_limit,
                .dirs = comp.dirs.withoutLocalCache(),
                .self_exe_path = comp.self_exe_path,
                .cache_mode = .whole,
                .config = config,
                .root_mod = root_mod,
                .root_name = "c",
                .libc_installation = comp.libc_installation,
                .emit_bin = .yes_cache,
                .verbose_cc = comp.verbose_cc,
                .verbose_link = comp.verbose_link,
                .verbose_air = comp.verbose_air,
                .verbose_llvm_ir = comp.verbose_llvm_ir,
                .verbose_cimport = comp.verbose_cimport,
                .verbose_llvm_cpu_features = comp.verbose_llvm_cpu_features,
                .clang_passthrough_mode = comp.clang_passthrough_mode,
                .c_source_files = &.{
                    .{
                        .src_path = try comp.dirs.zig_lib.join(arena, &.{ "libc", "musl", "libc.S" }),
                        .owner = root_mod,
                    },
                },
                .skip_linker_dependencies = true,
                .soname = "libc.so",
                .environ_map = comp.environ_map,
            }) catch |err| switch (err) {
                error.CreateFail => {
                    comp.lockAndSetMiscFailure(misc_task, "sub-compilation of {t} failed: {f}", .{ misc_task, sub_create_diag });
                    return error.AlreadyReported;
                },
                else => |e| return e,
            };
            defer sub_compilation.destroy();

            try comp.updateSubCompilation(sub_compilation, misc_task, prog_node);

            const basename = try comp.gpa.dupe(u8, "libc.so");
            errdefer comp.gpa.free(basename);

            const crt_file = try sub_compilation.toCrtFile();
            try comp.queuePrelinkTaskMode(crt_file.full_object_path, &config);
            {
                comp.mutex.lockUncancelable(io);
                defer comp.mutex.unlock(io);
                try comp.crt_files.ensureUnusedCapacity(comp.gpa, 1);
                comp.crt_files.putAssumeCapacityNoClobber(basename, crt_file);
            }
        },
    }
}

pub fn needsCrt0(output_mode: std.builtin.OutputMode, link_mode: std.builtin.LinkMode, pie: bool) ?CrtFile {
    return switch (output_mode) {
        .Obj, .Lib => null,
        .Exe => switch (link_mode) {
            .dynamic => if (pie) .scrt1_o else .crt1_o,
            .static => if (pie) .rcrt1_o else .crt1_o,
        },
    };
}

const time32_compat_arch_list = [_][]const u8{
    "arm",
    "i386",
    "m68k",
    "microblaze",
    "mips",
    "mipsn32",
    "or1k",
    "powerpc",
    "sh",
};

fn isArchName(name: []const u8) bool {
    const musl_arch_names = [_][]const u8{
        "aarch64",
        "arm",
        "generic",
        "hexagon",
        "i386",
        "loongarch64",
        "m68k",
        "microblaze",
        "mips",
        "mips64",
        "mipsn32",
        "or1k",
        "powerpc",
        "powerpc64",
        "riscv32",
        "riscv64",
        "s390x",
        "sh",
        "x32",
        "x86_64",
    };
    for (musl_arch_names) |musl_arch_name| {
        if (mem.eql(u8, musl_arch_name, name)) {
            return true;
        }
    }
    return false;
}

const Ext = enum {
    assembly,
    o3,
};

fn addSrcFile(arena: Allocator, source_table: *std.array_hash_map.String(Ext), file_path: []const u8) !void {
    const ext: Ext = ext: {
        if (mem.endsWith(u8, file_path, ".c")) {
            if (mem.startsWith(u8, file_path, "musl/src/string/") or
                mem.startsWith(u8, file_path, "musl/src/internal/"))
            {
                break :ext .o3;
            } else {
                break :ext .assembly;
            }
        } else if (mem.endsWith(u8, file_path, ".s") or mem.endsWith(u8, file_path, ".S")) {
            break :ext .assembly;
        } else {
            unreachable;
        }
    };
    // TODO do this at comptime on the comptime data rather than at runtime
    // probably best to wait until self-hosted is done and our comptime execution
    // is faster and uses less memory.
    const key = if (path.sep != '/') blk: {
        const mutable_file_path = try arena.dupe(u8, file_path);
        for (mutable_file_path) |*c| {
            if (c.* == '/') {
                c.* = path.sep;
            }
        }
        break :blk mutable_file_path;
    } else file_path;
    source_table.putAssumeCapacityNoClobber(key, ext);
}

fn addCcArgs(
    comp: *Compilation,
    arena: Allocator,
    args: *std.array_list.Managed([]const u8),
    want_O3: bool,
) error{OutOfMemory}!void {
    const target = comp.getTarget();
    const arch_name = std.zig.target.muslArchName(target.cpu.arch, target.abi);
    const os_name = @tagName(target.os.tag);
    const triple = try std.fmt.allocPrint(arena, "{s}-{s}-{s}", .{
        std.zig.target.muslArchNameHeaders(target.cpu.arch),
        os_name,
        std.zig.target.muslAbiNameHeaders(target.abi),
    });
    const o_arg = if (want_O3) "-O3" else "-Os";

    try args.appendSlice(&[_][]const u8{
        "-std=c99",
        "-ffreestanding",
        "-fexcess-precision=standard",
        "-frounding-math",
        "-ffp-contract=off",
        "-fno-strict-aliasing",
        "-Wa,--noexecstack",
        "-D_XOPEN_SOURCE=700",

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "musl", "arch", arch_name }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "musl", "arch", "generic" }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "musl", "src", "include" }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "musl", "src", "internal" }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "musl", "include" }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "include", triple }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "include", "generic-musl" }),

        o_arg,

        "-Qunused-arguments",
        "-w", // disable all warnings
    });

    if (target.cpu.arch.isThumb()) {
        try args.append("-mimplicit-it=always");
    }
}

fn start_asm_path(comp: *Compilation, arena: Allocator, basename: []const u8) ![]const u8 {
    const target = comp.getTarget();
    return comp.dirs.zig_lib.join(arena, &.{
        "libc", "musl", "crt", std.zig.target.muslArchName(target.cpu.arch, target.abi), basename,
    });
}

const src_files = [_][]const u8{
    "musl/src/env/__init_tls.c",
    "musl/src/fenv/aarch64/fenv.s",
    "musl/src/fenv/arm/fenv.c",
    "musl/src/fenv/arm/fenv-hf.S",
    "musl/src/fenv/hexagon/fenv.S",
    "musl/src/fenv/i386/fenv.s",
    "musl/src/fenv/loongarch64/fenv.S",
    "musl/src/fenv/loongarch64/fenv-sf.c",
    "musl/src/fenv/m68k/fenv.c",
    "musl/src/fenv/mips64/fenv.S",
    "musl/src/fenv/mips64/fenv-sf.c",
    "musl/src/fenv/mips/fenv.S",
    "musl/src/fenv/mips/fenv-sf.c",
    "musl/src/fenv/mipsn32/fenv.S",
    "musl/src/fenv/mipsn32/fenv-sf.c",
    "musl/src/fenv/powerpc64/fenv.c",
    "musl/src/fenv/powerpc/fenv.S",
    "musl/src/fenv/powerpc/fenv-sf.c",
    "musl/src/fenv/riscv32/fenv.S",
    "musl/src/fenv/riscv32/fenv-sf.c",
    "musl/src/fenv/riscv64/fenv.S",
    "musl/src/fenv/riscv64/fenv-sf.c",
    "musl/src/fenv/s390x/fenv.c",
    "musl/src/fenv/x32/fenv.s",
    "musl/src/fenv/x86_64/fenv.s",
    "musl/src/internal/emulate_wait4.c",
    "musl/src/internal/floatscan.c",
    "musl/src/internal/i386/defsysinfo.s",
    "musl/src/internal/intscan.c",
    "musl/src/internal/shgetc.c",
    "musl/src/internal/vdso.c",
    "musl/src/ldso/aarch64/dlsym.s",
    "musl/src/ldso/aarch64/tlsdesc.s",
    "musl/src/ldso/arm/dlsym.s",
    "musl/src/ldso/arm/dlsym_time64.S",
    //"musl/src/ldso/arm/find_exidx.c", // migrated to lib/c/ldso.zig
    "musl/src/ldso/arm/tlsdesc.S",
    //"musl/src/ldso/dladdr.c", // migrated to lib/c/ldso.zig
    //"musl/src/ldso/dlclose.c", // migrated to lib/c/ldso.zig
    //"musl/src/ldso/dlopen.c", // migrated to lib/c/ldso.zig
    //"musl/src/ldso/__dlsym.c", // migrated to lib/c/ldso.zig
    //"musl/src/ldso/dlsym.c", // migrated to lib/c/ldso.zig
    "musl/src/ldso/i386/dlsym.s",
    "musl/src/ldso/i386/dlsym_time64.S",
    "musl/src/ldso/i386/tlsdesc.s",
    "musl/src/ldso/loongarch64/dlsym.s",
    "musl/src/ldso/m68k/dlsym.s",
    "musl/src/ldso/m68k/dlsym_time64.S",
    "musl/src/ldso/mips64/dlsym.s",
    "musl/src/ldso/mips/dlsym.s",
    "musl/src/ldso/mips/dlsym_time64.S",
    "musl/src/ldso/mipsn32/dlsym.s",
    "musl/src/ldso/mipsn32/dlsym_time64.S",
    "musl/src/ldso/powerpc64/dlsym.s",
    "musl/src/ldso/powerpc/dlsym.s",
    "musl/src/ldso/powerpc/dlsym_time64.S",
    "musl/src/ldso/riscv32/dlsym.s",
    "musl/src/ldso/riscv64/dlsym.s",
    "musl/src/ldso/riscv64/tlsdesc.s",
    "musl/src/ldso/s390x/dlsym.s",
    //"musl/src/ldso/tlsdesc.c", // migrated to lib/c/ldso.zig
    "musl/src/ldso/x32/dlsym.s",
    "musl/src/ldso/x86_64/dlsym.s",
    "musl/src/ldso/x86_64/tlsdesc.s",
    "musl/src/math/erfl.c",
    "musl/src/math/exp10l.c",
    "musl/src/math/expm1.c",
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
    "musl/src/misc/getauxval.c",
    "musl/src/misc/getdomainname.c",
    "musl/src/network/accept4.c",
    "musl/src/network/accept.c",
    "musl/src/network/bind.c",
    "musl/src/network/connect.c",
    "musl/src/network/dn_comp.c",
    "musl/src/network/dn_expand.c",
    "musl/src/network/dn_skipname.c",
    "musl/src/network/dns_parse.c",
    "musl/src/network/ent.c",
    "musl/src/network/ether.c",
    "musl/src/network/freeaddrinfo.c",
    "musl/src/network/gai_strerror.c",
    "musl/src/network/getaddrinfo.c",
    "musl/src/network/gethostbyaddr.c",
    "musl/src/network/gethostbyaddr_r.c",
    "musl/src/network/gethostbyname2.c",
    "musl/src/network/gethostbyname2_r.c",
    "musl/src/network/gethostbyname.c",
    "musl/src/network/gethostbyname_r.c",
    "musl/src/network/getifaddrs.c",
    "musl/src/network/getnameinfo.c",
    "musl/src/network/getpeername.c",
    "musl/src/network/getservbyname.c",
    "musl/src/network/getservbyname_r.c",
    "musl/src/network/getservbyport.c",
    "musl/src/network/getservbyport_r.c",
    "musl/src/network/getsockname.c",
    "musl/src/network/getsockopt.c",
    "musl/src/network/h_errno.c",
    "musl/src/network/herror.c",
    "musl/src/network/hstrerror.c",
    "musl/src/network/htonl.c",
    "musl/src/network/htons.c",
    "musl/src/network/if_freenameindex.c",
    "musl/src/network/if_indextoname.c",
    "musl/src/network/if_nameindex.c",
    "musl/src/network/if_nametoindex.c",
    "musl/src/network/in6addr_any.c",
    "musl/src/network/in6addr_loopback.c",
    "musl/src/network/inet_addr.c",
    "musl/src/network/inet_aton.c",
    "musl/src/network/inet_legacy.c",
    "musl/src/network/inet_ntoa.c",
    "musl/src/network/inet_ntop.c",
    "musl/src/network/inet_pton.c",
    "musl/src/network/listen.c",
    "musl/src/network/lookup_ipliteral.c",
    "musl/src/network/lookup_name.c",
    "musl/src/network/lookup_serv.c",
    "musl/src/network/netlink.c",
    "musl/src/network/netname.c",
    "musl/src/network/ns_parse.c",
    "musl/src/network/ntohl.c",
    "musl/src/network/ntohs.c",
    "musl/src/network/proto.c",
    "musl/src/network/recv.c",
    "musl/src/network/recvfrom.c",
    "musl/src/network/recvmmsg.c",
    "musl/src/network/recvmsg.c",
    "musl/src/network/res_init.c",
    "musl/src/network/res_mkquery.c",
    "musl/src/network/res_msend.c",
    "musl/src/network/resolvconf.c",
    "musl/src/network/res_query.c",
    "musl/src/network/res_querydomain.c",
    "musl/src/network/res_send.c",
    "musl/src/network/res_state.c",
    "musl/src/network/send.c",
    "musl/src/network/sendmmsg.c",
    "musl/src/network/sendmsg.c",
    "musl/src/network/sendto.c",
    "musl/src/network/serv.c",
    "musl/src/network/setsockopt.c",
    "musl/src/network/shutdown.c",
    "musl/src/network/sockatmark.c",
    "musl/src/network/socket.c",
    "musl/src/network/socketpair.c",
    "musl/src/process/posix_spawn.c",
    "musl/src/process/posix_spawnp.c",
    "musl/src/sched/affinity.c",
    "musl/src/setjmp/aarch64/longjmp.s",
    "musl/src/setjmp/aarch64/setjmp.s",
    "musl/src/setjmp/arm/longjmp.S",
    "musl/src/setjmp/arm/setjmp.S",
    "musl/src/setjmp/hexagon/longjmp.s",
    "musl/src/setjmp/hexagon/setjmp.s",
    "musl/src/setjmp/i386/longjmp.s",
    "musl/src/setjmp/i386/setjmp.s",
    "musl/src/setjmp/loongarch64/longjmp.S",
    "musl/src/setjmp/loongarch64/setjmp.S",
    "musl/src/setjmp/m68k/longjmp.s",
    "musl/src/setjmp/m68k/setjmp.s",
    "musl/src/setjmp/mips64/longjmp.S",
    "musl/src/setjmp/mips64/setjmp.S",
    "musl/src/setjmp/mips/longjmp.S",
    "musl/src/setjmp/mipsn32/longjmp.S",
    "musl/src/setjmp/mipsn32/setjmp.S",
    "musl/src/setjmp/mips/setjmp.S",
    "musl/src/setjmp/powerpc64/longjmp.s",
    "musl/src/setjmp/powerpc64/setjmp.s",
    "musl/src/setjmp/powerpc/longjmp.S",
    "musl/src/setjmp/powerpc/setjmp.S",
    "musl/src/setjmp/riscv32/longjmp.S",
    "musl/src/setjmp/riscv32/setjmp.S",
    "musl/src/setjmp/riscv64/longjmp.S",
    "musl/src/setjmp/riscv64/setjmp.S",
    "musl/src/setjmp/s390x/longjmp.s",
    "musl/src/setjmp/s390x/setjmp.s",
    "musl/src/setjmp/x32/longjmp.s",
    "musl/src/setjmp/x32/setjmp.s",
    "musl/src/setjmp/x86_64/longjmp.s",
    "musl/src/setjmp/x86_64/setjmp.s",
    "musl/src/signal/aarch64/restore.s",
    "musl/src/signal/aarch64/sigsetjmp.s",
    "musl/src/signal/arm/restore.s",
    "musl/src/signal/arm/sigsetjmp.s",
    "musl/src/signal/hexagon/sigsetjmp.s",
    "musl/src/signal/i386/restore.s",
    "musl/src/signal/i386/sigsetjmp.s",
    "musl/src/signal/loongarch64/sigsetjmp.s",
    "musl/src/signal/m68k/sigsetjmp.s",
    "musl/src/signal/mips64/sigsetjmp.s",
    "musl/src/signal/mipsn32/sigsetjmp.s",
    "musl/src/signal/mips/sigsetjmp.s",
    "musl/src/signal/powerpc64/restore.s",
    "musl/src/signal/powerpc64/sigsetjmp.s",
    "musl/src/signal/powerpc/restore.s",
    "musl/src/signal/powerpc/sigsetjmp.s",
    "musl/src/signal/psignal.c",
    "musl/src/signal/riscv32/sigsetjmp.s",
    "musl/src/signal/riscv64/sigsetjmp.s",
    "musl/src/signal/s390x/restore.s",
    "musl/src/signal/s390x/sigsetjmp.s",
    "musl/src/signal/sigaction.c",
    "musl/src/signal/x32/restore.s",
    "musl/src/signal/x32/sigsetjmp.s",
    "musl/src/signal/x86_64/restore.s",
    "musl/src/signal/x86_64/sigsetjmp.s",
    //"musl/src/stdio/ext2.c", // migrated to lib/c/stdio.zig
    //"musl/src/stdio/ext.c", // migrated to lib/c/stdio.zig
    "musl/src/stdio/fclose.c",
    //"musl/src/stdio/__fclose_ca.c", // migrated to lib/c/stdio.zig
    "musl/src/stdio/__fdopen.c",
    //"musl/src/stdio/feof.c", // migrated to lib/c/stdio.zig
    //"musl/src/stdio/ferror.c", // migrated to lib/c/stdio.zig
    "musl/src/stdio/fflush.c",
    //"musl/src/stdio/fgetc.c", // migrated to lib/c/stdio.zig
    "musl/src/stdio/fgetwc.c",
    "musl/src/stdio/fgetws.c",
    //"musl/src/stdio/fileno.c", // migrated to lib/c/stdio.zig
    "musl/src/stdio/flockfile.c",
    "musl/src/stdio/fmemopen.c",
    //"musl/src/stdio/__fmodeflags.c", // migrated to lib/c/stdio.zig
    "musl/src/stdio/fopen.c",
    "musl/src/stdio/fopencookie.c",
    "musl/src/stdio/__fopen_rb_ca.c",
    //"musl/src/stdio/fputs.c", // migrated to lib/c/stdio.zig
    "musl/src/stdio/fputwc.c",
    "musl/src/stdio/fputws.c",
    //"musl/src/stdio/fread.c", // migrated to lib/c/stdio.zig
    "musl/src/stdio/freopen.c",
    //"musl/src/stdio/getline.c", // migrated to lib/c/stdio.zig
    //"musl/src/stdio/gets.c", // migrated to lib/c/stdio.zig
    //"musl/src/stdio/getw.c", // migrated to lib/c/stdio.zig
    //"musl/src/stdio/getwc.c", // migrated to lib/c/stdio.zig
    //"musl/src/stdio/getwchar.c", // migrated to lib/c/stdio.zig
    "musl/src/stdio/__lockfile.c",
    "musl/src/stdio/ofl_add.c",
    "musl/src/stdio/ofl.c",
    "musl/src/stdio/open_memstream.c",
    "musl/src/stdio/open_wmemstream.c",
    //"musl/src/stdio/__overflow.c", // migrated to lib/c/stdio.zig
    "musl/src/stdio/pclose.c",
    //"musl/src/stdio/perror.c", // migrated to lib/c/stdio.zig
    "musl/src/stdio/popen.c",
    //"musl/src/stdio/puts.c", // migrated to lib/c/stdio.zig
    //"musl/src/stdio/putw.c", // migrated to lib/c/stdio.zig
    //"musl/src/stdio/putwc.c", // migrated to lib/c/stdio.zig
    //"musl/src/stdio/putwchar.c", // migrated to lib/c/stdio.zig
    "musl/src/stdio/stderr.c",
    "musl/src/stdio/stdin.c",
    "musl/src/stdio/__stdio_close.c",
    "musl/src/stdio/__stdio_exit.c",
    "musl/src/stdio/__stdio_read.c",
    //"musl/src/stdio/__stdio_seek.c", // migrated to lib/c/stdio.zig
    "musl/src/stdio/__stdio_write.c",
    "musl/src/stdio/stdout.c",
    "musl/src/stdio/__stdout_write.c",
    //"musl/src/stdio/swprintf.c", // migrated to lib/c/stdio.zig
    //"musl/src/stdio/swscanf.c", // migrated to lib/c/stdio.zig
    "musl/src/stdio/tempnam.c",
    "musl/src/stdio/tmpfile.c",
    "musl/src/stdio/tmpnam.c",
    //"musl/src/stdio/ungetc.c", // migrated to lib/c/stdio.zig
    "musl/src/stdio/ungetwc.c",
    //"musl/src/stdio/vasprintf.c", // migrated to lib/c/stdio.zig
    //"musl/src/stdio/vdprintf.c", // migrated to lib/c/stdio.zig
    "musl/src/stdio/vfprintf.c",
    "musl/src/stdio/vfscanf.c",
    "musl/src/stdio/vfwprintf.c",
    "musl/src/stdio/vfwscanf.c",
    "musl/src/thread/aarch64/clone.s",
    "musl/src/thread/aarch64/__set_thread_area.s",
    "musl/src/thread/aarch64/syscall_cp.s",
    "musl/src/thread/aarch64/__unmapself.s",
    "musl/src/thread/arm/__aeabi_read_tp.s",
    "musl/src/thread/arm/atomics.s",
    "musl/src/thread/arm/clone.s",
    "musl/src/thread/arm/__set_thread_area.c",
    "musl/src/thread/arm/syscall_cp.s",
    "musl/src/thread/arm/__unmapself.s",
    "musl/src/thread/hexagon/clone.s",
    "musl/src/thread/hexagon/__set_thread_area.s",
    "musl/src/thread/hexagon/syscall_cp.s",
    "musl/src/thread/hexagon/__unmapself.s",
    "musl/src/thread/i386/clone.s",
    "musl/src/thread/i386/__set_thread_area.s",
    "musl/src/thread/i386/syscall_cp.s",
    "musl/src/thread/i386/tls.s",
    "musl/src/thread/i386/__unmapself.s",
    //"musl/src/thread/lock_ptc.c", // migrated to lib/c/thread.zig
    "musl/src/thread/loongarch64/clone.s",
    "musl/src/thread/loongarch64/__set_thread_area.s",
    "musl/src/thread/loongarch64/syscall_cp.s",
    "musl/src/thread/loongarch64/__unmapself.s",
    "musl/src/thread/m68k/clone.s",
    "musl/src/thread/m68k/__m68k_read_tp.s",
    "musl/src/thread/m68k/syscall_cp.s",
    "musl/src/thread/mips64/clone.s",
    "musl/src/thread/mips64/syscall_cp.s",
    "musl/src/thread/mips64/__unmapself.s",
    "musl/src/thread/mips/clone.s",
    "musl/src/thread/mipsn32/clone.s",
    "musl/src/thread/mipsn32/syscall_cp.s",
    "musl/src/thread/mipsn32/__unmapself.s",
    "musl/src/thread/mips/syscall_cp.s",
    "musl/src/thread/mips/__unmapself.s",
    //"musl/src/thread/mtx_destroy.c", // migrated to lib/c/thread.zig
    //"musl/src/thread/mtx_init.c", // migrated to lib/c/thread.zig
    //"musl/src/thread/mtx_lock.c", // migrated to lib/c/thread.zig
    //"musl/src/thread/mtx_timedlock.c", // migrated to lib/c/thread.zig
    //"musl/src/thread/mtx_trylock.c", // migrated to lib/c/thread.zig
    //"musl/src/thread/mtx_unlock.c", // migrated to lib/c/thread.zig
    "musl/src/thread/powerpc64/clone.s",
    "musl/src/thread/powerpc64/__set_thread_area.s",
    "musl/src/thread/powerpc64/syscall_cp.s",
    "musl/src/thread/powerpc64/__unmapself.s",
    "musl/src/thread/powerpc/clone.s",
    "musl/src/thread/powerpc/__set_thread_area.s",
    "musl/src/thread/powerpc/syscall_cp.s",
    "musl/src/thread/powerpc/__unmapself.s",
    "musl/src/thread/pthread_atfork.c",
    //"musl/src/thread/pthread_attr_destroy.c", // migrated to lib/c/thread.zig
    //"musl/src/thread/pthread_attr_get.c", // migrated to lib/c/thread.zig
    "musl/src/thread/riscv32/clone.s",
    "musl/src/thread/riscv32/__set_thread_area.s",
    "musl/src/thread/riscv32/syscall_cp.s",
    "musl/src/thread/riscv32/__unmapself.s",
    "musl/src/thread/riscv64/clone.s",
    "musl/src/thread/riscv64/__set_thread_area.s",
    "musl/src/thread/riscv64/syscall_cp.s",
    "musl/src/thread/riscv64/__unmapself.s",
    "musl/src/thread/s390x/clone.s",
    "musl/src/thread/s390x/__set_thread_area.s",
    "musl/src/thread/s390x/syscall_cp.s",
    "musl/src/thread/s390x/__tls_get_offset.s",
    "musl/src/thread/s390x/__unmapself.s",
    //"musl/src/thread/sem_destroy.c", // migrated to lib/c/thread.zig
    //"musl/src/thread/sem_getvalue.c", // migrated to lib/c/thread.zig
    //"musl/src/thread/sem_init.c", // migrated to lib/c/thread.zig
    "musl/src/thread/sem_open.c",
    "musl/src/thread/__timedwait.c",
    //"musl/src/thread/tls.c", // empty file
    "musl/src/thread/__tls_get_addr.c",
    //"musl/src/thread/tss_create.c", // migrated to lib/c/thread.zig
    //"musl/src/thread/tss_delete.c", // migrated to lib/c/thread.zig
    "musl/src/thread/__unmapself.c",
    //"musl/src/thread/vmlock.c", // migrated to lib/c/thread.zig
    //"musl/src/thread/__wait.c", // migrated to lib/c/thread.zig
    "musl/src/thread/x32/clone.s",
    "musl/src/thread/x32/__set_thread_area.s",
    "musl/src/thread/x32/syscall_cp.s",
    "musl/src/thread/x32/__unmapself.s",
    "musl/src/thread/x86_64/clone.s",
    "musl/src/thread/x86_64/__set_thread_area.s",
    "musl/src/thread/x86_64/syscall_cp.s",
    "musl/src/thread/x86_64/__unmapself.s",
    "musl/src/time/clock.c",
    "musl/src/time/clock_getcpuclockid.c",
    "musl/src/time/clock_getres.c",
    "musl/src/time/clock_gettime.c",
    "musl/src/time/clock_settime.c",
    "musl/src/time/difftime.c",
    "musl/src/time/gettimeofday.c",
    "musl/src/time/strftime.c",
    "musl/src/time/strptime.c",
    "musl/src/time/time.c",
    "musl/src/time/timer_create.c",
    "musl/src/time/timer_delete.c",
    "musl/src/time/timer_getoverrun.c",
    "musl/src/time/timer_gettime.c",
    "musl/src/time/timer_settime.c",
    "musl/src/time/__tz.c",
    "musl/src/time/wcsftime.c",
};

const compat_time32_files = [_][]const u8{
    "musl/compat/time32/adjtime32.c",
    "musl/compat/time32/adjtimex_time32.c",
    "musl/compat/time32/clock_adjtime32.c",
    "musl/compat/time32/clock_getres_time32.c",
    "musl/compat/time32/clock_gettime32.c",
    "musl/compat/time32/clock_nanosleep_time32.c",
    "musl/compat/time32/clock_settime32.c",
    "musl/compat/time32/cnd_timedwait_time32.c",
    "musl/compat/time32/ctime32.c",
    "musl/compat/time32/ctime32_r.c",
    "musl/compat/time32/difftime32.c",
    "musl/compat/time32/fstatat_time32.c",
    "musl/compat/time32/fstat_time32.c",
    "musl/compat/time32/ftime32.c",
    "musl/compat/time32/futimens_time32.c",
    "musl/compat/time32/futimesat_time32.c",
    "musl/compat/time32/futimes_time32.c",
    "musl/compat/time32/getitimer_time32.c",
    "musl/compat/time32/getrusage_time32.c",
    "musl/compat/time32/gettimeofday_time32.c",
    "musl/compat/time32/gmtime32.c",
    "musl/compat/time32/gmtime32_r.c",
    "musl/compat/time32/localtime32.c",
    "musl/compat/time32/localtime32_r.c",
    "musl/compat/time32/lstat_time32.c",
    "musl/compat/time32/lutimes_time32.c",
    "musl/compat/time32/mktime32.c",

    "musl/compat/time32/mtx_timedlock_time32.c",
    "musl/compat/time32/nanosleep_time32.c",
    "musl/compat/time32/ppoll_time32.c",
    "musl/compat/time32/pselect_time32.c",
    "musl/compat/time32/pthread_cond_timedwait_time32.c",
    "musl/compat/time32/pthread_mutex_timedlock_time32.c",
    "musl/compat/time32/pthread_rwlock_timedrdlock_time32.c",
    "musl/compat/time32/pthread_rwlock_timedwrlock_time32.c",
    "musl/compat/time32/pthread_timedjoin_np_time32.c",
    "musl/compat/time32/recvmmsg_time32.c",
    "musl/compat/time32/sched_rr_get_interval_time32.c",
    "musl/compat/time32/select_time32.c",
    "musl/compat/time32/semtimedop_time32.c",
    "musl/compat/time32/sem_timedwait_time32.c",
    "musl/compat/time32/setitimer_time32.c",
    "musl/compat/time32/settimeofday_time32.c",
    "musl/compat/time32/sigtimedwait_time32.c",
    "musl/compat/time32/stat_time32.c",
    "musl/compat/time32/stime32.c",
    "musl/compat/time32/thrd_sleep_time32.c",
    "musl/compat/time32/time32.c",
    "musl/compat/time32/time32gm.c",
    "musl/compat/time32/timerfd_gettime32.c",
    "musl/compat/time32/timerfd_settime32.c",
    "musl/compat/time32/timer_gettime32.c",
    "musl/compat/time32/timer_settime32.c",
    "musl/compat/time32/timespec_get_time32.c",
    "musl/compat/time32/utimensat_time32.c",
    "musl/compat/time32/utimes_time32.c",
    "musl/compat/time32/utime_time32.c",
    "musl/compat/time32/wait3_time32.c",
    "musl/compat/time32/wait4_time32.c",
    "musl/compat/time32/__xstat.c",
};
