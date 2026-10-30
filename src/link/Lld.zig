base: link.File,
ofmt: union(enum) {
    elf: Elf,
    coff: Coff,
    wasm: Wasm,
},

const Coff = struct {
    image_base: u64,
    entry: link.File.OpenOptions.Entry,
    pdb_out_path: ?[]const u8,
    repro: bool,
    tsaware: bool,
    nxcompat: bool,
    dynamicbase: bool,
    /// TODO this and minor_subsystem_version should be combined into one property and left as
    /// default or populated together. They should not be separate fields.
    major_subsystem_version: u16,
    minor_subsystem_version: u16,
    lib_directories: []const Cache.Directory,
    module_definition_file: ?[]const u8,
    subsystem: ?std.zig.Subsystem,
    /// These flags are populated by `codegen.llvm.updateExports` to allow us to guess the subsystem.
    lld_export_flags: struct {
        c_main: bool,
        winmain: bool,
        wwinmain: bool,
        winmain_crt_startup: bool,
        wwinmain_crt_startup: bool,
        dllmain_crt_startup: bool,
    },
    fn init(comp: *Compilation, options: link.File.OpenOptions) !Coff {
        const target = &comp.root_mod.resolved_target.result;
        const output_mode = comp.config.output_mode;
        return .{
            .image_base = options.image_base orelse switch (output_mode) {
                .Exe => switch (target.cpu.arch) {
                    .aarch64, .x86_64 => 0x140000000,
                    .thumb, .x86 => 0x400000,
                    else => return error.UnsupportedCoffArchitecture,
                },
                .Lib => switch (target.cpu.arch) {
                    .aarch64, .x86_64 => 0x180000000,
                    .thumb, .x86 => 0x10000000,
                    else => return error.UnsupportedCoffArchitecture,
                },
                .Obj => 0,
            },
            .entry = options.entry,
            .pdb_out_path = options.pdb_out_path,
            .repro = options.repro,
            .tsaware = options.tsaware,
            .nxcompat = options.nxcompat,
            .dynamicbase = options.dynamicbase,
            .major_subsystem_version = options.major_subsystem_version orelse 6,
            .minor_subsystem_version = options.minor_subsystem_version orelse 0,
            .lib_directories = options.lib_directories,
            .module_definition_file = options.module_definition_file,
            // Subsystem depends on the set of public symbol names from linked objects.
            // See LinkerDriver::inferSubsystem from the LLD project for the flow chart.
            .subsystem = options.subsystem,
            // These flags are initially all `false`; the LLVM backend populates them when it learns about exports.
            .lld_export_flags = .{
                .c_main = false,
                .winmain = false,
                .wwinmain = false,
                .winmain_crt_startup = false,
                .wwinmain_crt_startup = false,
                .dllmain_crt_startup = false,
            },
        };
    }
};
pub const Elf = struct {
    entry_name: ?[]const u8,
    hash_style: HashStyle,
    image_base: u64,
    linker_scripts: []const Cache.Path,
    default_linker_script: ?Cache.Path,
    define_common: bool,
    version_script: ?Cache.Path,
    sort_section: ?SortSection,
    print_icf_sections: bool,
    print_map: bool,
    nmagic: bool,
    fatal_warnings: bool,
    emit_relocs: bool,
    z_nodelete: bool,
    z_notext: bool,
    z_defs: bool,
    z_origin: bool,
    z_nocopyreloc: bool,
    z_now: bool,
    z_relro: bool,
    z_common_page_size: ?u64,
    z_max_page_size: ?u64,
    rpath_list: []const []const u8,
    symbol_wrap_set: []const []const u8,
    soname: ?[]const u8,
    allow_undefined_version: bool,
    enable_new_dtags: ?bool,
    compress_debug_sections: std.zig.CompressDebugSections,
    bind_global_refs_locally: bool,
    pub const HashStyle = enum { sysv, gnu, both };
    pub const SortSection = enum { name, alignment };

    fn init(comp: *Compilation, options: link.File.OpenOptions) !Elf {
        const PtrWidth = enum { p32, p64 };
        const target = &comp.root_mod.resolved_target.result;
        const output_mode = comp.config.output_mode;
        const is_dyn_lib = output_mode == .Lib and comp.config.link_mode == .dynamic;
        const ptr_width: PtrWidth = switch (target.ptrBitWidth()) {
            0...32 => .p32,
            33...64 => .p64,
            else => return error.UnsupportedElfArchitecture,
        };
        const default_entry_name: []const u8 = switch (target.cpu.arch) {
            .mips, .mipsel, .mips64, .mips64el => "__start",
            else => "_start",
        };
        return .{
            .entry_name = switch (options.entry) {
                .disabled => null,
                .default => if (output_mode != .Exe) null else default_entry_name,
                .enabled => default_entry_name,
                .named => |name| name,
            },
            .hash_style = options.hash_style,
            .image_base = b: {
                if (is_dyn_lib) break :b 0;
                if (output_mode == .Exe and (comp.config.pie or target.os.tag == .haiku)) break :b 0;
                break :b options.image_base orelse switch (ptr_width) {
                    .p32 => 0x10000,
                    .p64 => 0x1000000,
                };
            },
            .linker_scripts = options.linker_scripts,
            .default_linker_script = options.default_linker_script,
            .define_common = options.define_common,
            .version_script = options.version_script,
            .sort_section = options.sort_section,
            .print_icf_sections = options.print_icf_sections,
            .print_map = options.print_map,
            .nmagic = options.nmagic,
            .fatal_warnings = options.fatal_warnings,
            .emit_relocs = options.emit_relocs,
            .z_nodelete = options.z_nodelete,
            .z_notext = options.z_notext,
            .z_defs = options.z_defs,
            .z_origin = options.z_origin,
            .z_nocopyreloc = options.z_nocopyreloc,
            .z_now = options.z_now,
            .z_relro = options.z_relro,
            .z_common_page_size = options.z_common_page_size,
            .z_max_page_size = options.z_max_page_size,
            .rpath_list = options.rpath_list,
            .symbol_wrap_set = options.symbol_wrap_set.keys(),
            .soname = options.soname,
            .allow_undefined_version = options.allow_undefined_version,
            .enable_new_dtags = options.enable_new_dtags,
            .compress_debug_sections = options.compress_debug_sections,
            .bind_global_refs_locally = options.bind_global_refs_locally,
        };
    }
};
const Wasm = struct {
    /// Symbol name of the entry function to export
    entry_name: ?[]const u8,
    /// When true, will import the function table from the host environment.
    import_table: bool,
    /// When true, will export the function table to the host environment.
    export_table: bool,
    /// When true, remove maximum size from function table, allowing table to grow.
    growable_table: bool,
    /// When defined, sets the initial memory size of the memory.
    initial_memory: ?u64,
    /// When defined, sets the maximum memory size of the memory.
    max_memory: ?u64,
    /// When defined, sets the start of the data section.
    global_base: ?u64,
    /// Set of *global* symbol names to export to the host environment.
    export_symbol_names: []const []const u8,
    /// When true, will allow undefined symbols
    import_symbols: bool,
    wit_path: ?[]const u8,
    wit_world: ?[]const u8,
    wasi_adapter_path: ?[]const u8,
    fn init(comp: *Compilation, options: link.File.OpenOptions) !Wasm {
        const target = &comp.root_mod.resolved_target.result;
        const default_entry_name: []const u8 = switch (comp.config.wasi_exec_model) {
            .reactor => "_initialize",
            .command => switch (target.os.tag) {
                .wasip2 => "wasi:cli/run@0.2.6#run",
                .wasip3 => "wasi:cli/run@0.3.0#run",
                else => "_start",
            },
        };
        return .{
            .entry_name = switch (options.entry) {
                .disabled => null,
                .default => if (comp.config.output_mode != .Exe) null else default_entry_name,
                .enabled => default_entry_name,
                .named => |name| name,
            },
            .import_table = options.import_table,
            .export_table = options.export_table,
            .growable_table = options.growable_table,
            .initial_memory = options.initial_memory,
            .max_memory = options.max_memory,
            .global_base = options.global_base,
            .export_symbol_names = options.export_symbol_names,
            .import_symbols = options.import_symbols,
            .wit_path = options.wit_path,
            .wit_world = options.wit_world,
            .wasi_adapter_path = options.wasi_adapter_path,
        };
    }
};

pub fn createEmpty(
    arena: Allocator,
    comp: *Compilation,
    emit: Cache.Path,
    options: link.File.OpenOptions,
) !*Lld {
    const target = &comp.root_mod.resolved_target.result;
    const output_mode = comp.config.output_mode;
    const optimize_mode = comp.root_mod.optimize_mode;

    const gc_sections: bool = options.gc_sections orelse switch (target.ofmt) {
        .coff => optimize_mode != .debug,
        .elf => optimize_mode != .debug and output_mode != .Obj,
        .wasm => output_mode != .Obj,
        else => unreachable,
    };
    const stack_size: u64 = options.stack_size orelse default: {
        if (target.ofmt == .wasm and target.os.tag == .freestanding)
            break :default 1 * 1024 * 1024; // 1 MiB
        break :default 16 * 1024 * 1024; // 16 MiB
    };

    const lld = try arena.create(Lld);
    lld.* = .{
        .base = .{
            .tag = .lld,
            .comp = comp,
            .emit = emit,
            .gc_sections = gc_sections,
            .print_gc_sections = options.print_gc_sections,
            .stack_size = stack_size,
            .allow_shlib_undefined = options.allow_shlib_undefined orelse false,
            .file = null,
            .build_id = options.build_id,
        },
        .ofmt = switch (target.ofmt) {
            .coff => .{ .coff = try .init(comp, options) },
            .elf => .{ .elf = try .init(comp, options) },
            .wasm => .{ .wasm = try .init(comp, options) },
            else => unreachable,
        },
    };
    return lld;
}
pub fn deinit(lld: *Lld) void {
    _ = lld;
}
pub fn flush(
    lld: *Lld,
    arena: Allocator,
    tid: Zcu.PerThread.Id,
    prog_node: std.Progress.Node,
) link.Error!void {
    dev.check(.lld_linker);
    _ = tid;

    const tracy = trace(@src());
    defer tracy.end();

    const sub_prog_node = prog_node.start("LLD Link", 0);
    defer sub_prog_node.end();

    const comp = lld.base.comp;
    const result = if (comp.config.output_mode == .Lib and comp.config.link_mode == .static) r: {
        if (!@import("build_options").have_llvm or !comp.config.use_lib_llvm) {
            return lld.base.comp.link_diags.fail("using lld without libllvm not implemented", .{});
        }
        break :r linkAsArchive(lld, arena);
    } else switch (lld.ofmt) {
        .coff => coffLink(lld, arena),
        .elf => elfLink(lld, arena),
        .wasm => wasmLink(lld, arena),
    };
    result catch |err| switch (err) {
        error.OutOfMemory, error.AlreadyReported, error.Canceled => |e| return e,
        else => |e| return lld.base.comp.link_diags.fail("failed to link with LLD: {t}", .{e}),
    };
}

fn linkAsArchive(lld: *Lld, arena: Allocator) link.Error!void {
    const base = &lld.base;
    const comp = base.comp;
    const directory = base.emit.root_dir; // Just an alias to make it shorter to type.
    const full_out_path = try directory.join(arena, &[_][]const u8{base.emit.sub_path});
    const full_out_path_z = try arena.dupeSentinel(u8, full_out_path, 0);
    const opt_zcu = comp.zcu;

    const zcu_obj_path: ?Cache.Path = if (opt_zcu) |zcu| p: {
        break :p try comp.resolveEmitPathFlush(arena, .temp, zcu.llvm_object.?.out_bin_basename);
    } else null;

    log.debug("zcu_obj_path={?f}", .{zcu_obj_path});

    const compiler_rt_path: ?Cache.Path = if (comp.compiler_rt_strat == .obj)
        comp.compiler_rt_obj.?.full_object_path
    else
        null;

    const ubsan_rt_path: ?Cache.Path = if (comp.ubsan_rt_strat == .obj)
        comp.ubsan_rt_obj.?.full_object_path
    else
        null;

    var object_files: std.ArrayList([*:0]const u8) = .empty;

    try object_files.ensureUnusedCapacity(arena, comp.link_inputs.len);
    for (comp.link_inputs) |input| switch (input) {
        .dso, .tbd, .archive => {}, // static archives should not contain shared libraries or other static archives
        .res, .object => {
            const path = try input.path().toStringZ(arena);
            object_files.appendAssumeCapacity(path);
        },
    };

    try object_files.ensureUnusedCapacity(arena, comp.c_objects.items.len +
        comp.win32_resources.items.len + 2);

    for (comp.c_objects.items) |c_object| {
        object_files.appendAssumeCapacity(try c_object.status.success.object_path.toStringZ(arena));
    }
    for (comp.win32_resources.items) |win32_resource| {
        object_files.appendAssumeCapacity(try arena.dupeSentinel(u8, win32_resource.status.success.res_path, 0));
    }
    if (zcu_obj_path) |p| object_files.appendAssumeCapacity(try p.toStringZ(arena));
    if (compiler_rt_path) |p| object_files.appendAssumeCapacity(try p.toStringZ(arena));
    if (ubsan_rt_path) |p| object_files.appendAssumeCapacity(try p.toStringZ(arena));

    if (comp.verbose_link) {
        std.debug.print("ar rcs {s}", .{full_out_path_z});
        for (object_files.items) |arg| {
            std.debug.print(" {s}", .{arg});
        }
        std.debug.print("\n", .{});
    }

    const llvm_bindings = @import("../codegen/llvm/bindings.zig");
    const llvm = @import("../codegen/llvm.zig");
    const target = &comp.root_mod.resolved_target.result;
    llvm.initializeLLVMTarget(comp.io, target.cpu.arch);
    var err_file_index: usize = undefined;
    var err_msg: [*:0]u8 = undefined;
    if (llvm_bindings.WriteArchive(
        full_out_path_z,
        object_files.items.ptr,
        object_files.items.len,
        switch (target.os.tag) {
            .windows => .COFF,
            else => if (target.os.tag.isDarwin()) .DARWIN else .GNU,
        },
        &err_file_index,
        &err_msg,
    )) {
        defer std.c.free(err_msg);
        if (err_file_index < object_files.items.len) {
            return comp.link_diags.fail("LLD failed to open input file '{s}': {s}", .{
                object_files.items[err_file_index],
                err_msg,
            });
        } else {
            return comp.link_diags.fail("LLD failed to write archive: {s}", .{err_msg});
        }
    }
}

fn addCommonArgs(argv: *std.array_list.Managed([]const u8), coff: bool) !void {
    if (builtin.os.tag == .netbsd) {
        // NetBSD 10.1's `malloc` appears to have some nasty bugs that occur
        // when doing parallel linking in LLD, manifesting as input and/or
        // output section memory randomly being unmapped. So just don't do
        // parallel linking for now.
        try argv.append(if (coff) "-threads:1" else "--threads=1");
    }
}

fn coffLink(lld: *Lld, arena: Allocator) !void {
    const comp = lld.base.comp;
    const gpa = comp.gpa;
    const io = comp.io;
    const base = &lld.base;
    const coff = &lld.ofmt.coff;

    const directory = base.emit.root_dir; // Just an alias to make it shorter to type.
    const full_out_path = try directory.join(arena, &[_][]const u8{base.emit.sub_path});

    const zcu_obj_path: ?Cache.Path = if (comp.zcu) |zcu| p: {
        break :p try comp.resolveEmitPathFlush(arena, .temp, zcu.llvm_object.?.out_bin_basename);
    } else null;

    const is_lib = comp.config.output_mode == .Lib;
    const is_dyn_lib = comp.config.link_mode == .dynamic and is_lib;
    const is_exe_or_dyn_lib = is_dyn_lib or comp.config.output_mode == .Exe;
    const link_in_crt = comp.config.link_libc and is_exe_or_dyn_lib;
    const target = &comp.root_mod.resolved_target.result;
    const optimize_mode = comp.root_mod.optimize_mode;
    const entry_name: ?[]const u8 = switch (coff.entry) {
        // This logic isn't quite right for default or enabled. No point in fixing it
        // when the goal is to eliminate dependency on LLD anyway.
        // https://github.com/ziglang/zig/issues/17751
        .disabled, .default, .enabled => null,
        .named => |name| name,
    };

    if (comp.config.output_mode == .Obj) {
        // LLD's COFF driver does not support the equivalent of `-r` so we do a simple file copy
        // here. TODO: think carefully about how we can avoid this redundant operation when doing
        // build-obj. See also the corresponding TODO in linkAsArchive.
        const the_object_path = blk: {
            if (link.firstObjectInput(comp.link_inputs)) |obj| break :blk obj.path;

            if (comp.c_objects.items.len != 0)
                break :blk comp.c_objects.items[0].status.success.object_path;

            if (zcu_obj_path) |p|
                break :blk p;

            // TODO I think this is unreachable. Audit this situation when solving the above TODO
            // regarding eliding redundant object -> object transformations.
            return error.NoObjectsToLink;
        };
        try Io.Dir.copyFile(
            the_object_path.root_dir.handle,
            the_object_path.sub_path,
            directory.handle,
            base.emit.sub_path,
            io,
            .{},
        );
    } else {
        // Create an LLD command line and invoke it.
        var argv = std.array_list.Managed([]const u8).init(gpa);
        defer argv.deinit();
        // We will invoke ourselves as a child process to gain access to LLD.
        // This is necessary because LLD does not behave properly as a library -
        // it calls exit() and does not reset all global data between invocations.
        const linker_command = "lld-link";
        try argv.appendSlice(&[_][]const u8{ comp.self_exe_path orelse "zig", linker_command });
        try addCommonArgs(&argv, true);

        if (target.isMinGW()) {
            try argv.append("-lldmingw");
        }

        try argv.append("-ERRORLIMIT:0");
        try argv.append("-NOLOGO");
        if (comp.config.debug_format != .strip) {
            try argv.append("-DEBUG");

            const out_ext = std.fs.path.extension(full_out_path);
            const out_pdb = coff.pdb_out_path orelse try arena.print("{s}.pdb", .{
                full_out_path[0 .. full_out_path.len - out_ext.len],
            });
            const out_pdb_basename = std.fs.path.basename(out_pdb);

            try argv.append(try arena.print("-PDB:{s}", .{out_pdb}));
            try argv.append(try arena.print("-PDBALTPATH:{s}", .{out_pdb_basename}));
        }
        if (comp.version) |version| {
            try argv.append(try arena.print("-VERSION:{d}.{d}", .{ version.major, version.minor }));
        }

        if (target_util.llvmMachineAbi(target)) |mabi| {
            try argv.append(try arena.print("-MLLVM:-target-abi={s}", .{mabi}));
        }

        try argv.append(try arena.print("-MLLVM:-float-abi={s}", .{if (target.abi.float() == .hard) "hard" else "soft"}));

        if (comp.config.lto != .none) {
            switch (optimize_mode) {
                .debug => {},
                .small => try argv.append("-OPT:lldlto=2"),
                .fast, .safe => try argv.append("-OPT:lldlto=3"),
            }
        }
        if (comp.config.output_mode == .Exe) {
            try argv.append(try arena.print("-STACK:{d}", .{base.stack_size}));
        }
        try argv.append(try arena.print("-BASE:{d}", .{coff.image_base}));

        switch (base.build_id) {
            .none => try argv.append("-BUILD-ID:NO"),
            .fast => try argv.append("-BUILD-ID"),
            .uuid, .sha1, .md5, .hexstring => {},
        }

        if (target.cpu.arch == .x86) {
            try argv.append("-MACHINE:X86");
        } else if (target.cpu.arch == .x86_64) {
            try argv.append("-MACHINE:X64");
        } else if (target.cpu.arch == .thumb) {
            try argv.append("-MACHINE:ARM");
        } else if (target.cpu.arch == .aarch64) {
            try argv.append("-MACHINE:ARM64");
        }

        for (comp.force_undefined_symbols.keys()) |symbol| {
            try argv.append(try arena.print("-INCLUDE:{s}", .{symbol}));
        }

        if (is_dyn_lib) {
            try argv.append("-DLL");
        }

        if (entry_name) |name| {
            try argv.append(try arena.print("-ENTRY:{s}", .{name}));
        } else if (coff.entry == .disabled) {
            try argv.append("-NOENTRY");
        }

        if (coff.repro) {
            try argv.append("-BREPRO");
        }

        if (coff.tsaware) {
            try argv.append("-tsaware");
        }
        if (coff.nxcompat) {
            try argv.append("-nxcompat");
        }
        if (!coff.dynamicbase) {
            try argv.append("-dynamicbase:NO");
        }
        if (base.allow_shlib_undefined) {
            try argv.append("-FORCE:UNRESOLVED");
        }

        try argv.append(try arena.print("-OUT:{s}", .{full_out_path}));

        if (comp.emit_implib) |raw_emit_path| {
            const path = try comp.resolveEmitPathFlush(arena, .artifact, raw_emit_path);
            try argv.append(try arena.print("-IMPLIB:{f}", .{path}));
        }

        if (comp.config.link_libc) {
            if (comp.libc_installation) |libc_installation| {
                try argv.append(try arena.print("-LIBPATH:{s}", .{libc_installation.crt_dir.?}));

                if (target.abi == .msvc or target.abi == .itanium) {
                    try argv.append(try arena.print("-LIBPATH:{s}", .{libc_installation.msvc_lib_dir.?}));
                    try argv.append(try arena.print("-LIBPATH:{s}", .{libc_installation.kernel32_lib_dir.?}));
                }
            }
        }

        for (coff.lib_directories) |lib_directory| {
            try argv.append(try arena.print("-LIBPATH:{s}", .{lib_directory.path orelse "."}));
        }

        try argv.ensureUnusedCapacity(comp.link_inputs.len);
        for (comp.link_inputs) |link_input| switch (link_input) {
            inline .dso, .res => |x| {
                argv.appendAssumeCapacity(try x.path.toString(arena));
            },
            .object, .archive => |obj| {
                if (obj.must_link) {
                    argv.appendAssumeCapacity(try arena.print("-WHOLEARCHIVE:{f}", .{@as(Cache.Path, obj.path)}));
                } else {
                    argv.appendAssumeCapacity(try obj.path.toString(arena));
                }
            },
            .tbd => unreachable,
        };

        for (comp.c_objects.items) |c_object| {
            try argv.append(try c_object.status.success.object_path.toString(arena));
        }

        for (comp.win32_resources.items) |win32_resource| {
            try argv.append(win32_resource.status.success.res_path);
        }

        if (zcu_obj_path) |p| {
            try argv.append(try p.toString(arena));
        }

        if (coff.module_definition_file) |def| {
            try argv.append(try arena.print("-DEF:{s}", .{def}));
        }

        const resolved_subsystem: ?std.zig.Subsystem = blk: {
            if (coff.subsystem) |explicit| break :blk explicit;
            switch (target.os.tag) {
                .windows => {
                    if (comp.zcu != null) {
                        if (coff.lld_export_flags.dllmain_crt_startup or is_dyn_lib)
                            break :blk null;
                        if (coff.lld_export_flags.c_main or comp.config.is_test or
                            coff.lld_export_flags.winmain_crt_startup or
                            coff.lld_export_flags.wwinmain_crt_startup)
                        {
                            break :blk .console;
                        }
                        if (coff.lld_export_flags.winmain or coff.lld_export_flags.wwinmain)
                            break :blk .windows;
                    }
                },
                .uefi => break :blk .efi_application,
                else => {},
            }
            break :blk null;
        };

        const Mode = enum { uefi, win32 };
        const mode: Mode = mode: {
            if (resolved_subsystem) |subsystem| {
                try argv.append(try arena.print("-SUBSYSTEM:{s},{d}.{d}", .{
                    @tagName(subsystem),
                    coff.major_subsystem_version,
                    coff.minor_subsystem_version,
                }));
                break :mode switch (subsystem) {
                    .console,
                    .windows,
                    .posix,
                    .native,
                    => .win32,
                    .efi_application,
                    .efi_boot_service_driver,
                    .efi_rom,
                    .efi_runtime_driver,
                    => .uefi,
                };
            } else if (target.os.tag == .uefi) {
                break :mode .uefi;
            } else {
                break :mode .win32;
            }
        };

        switch (mode) {
            .uefi => try argv.appendSlice(&[_][]const u8{
                "-BASE:0",
                "-ENTRY:EfiMain",
                "-OPT:REF",
                "-SAFESEH:NO",
                "-MERGE:.rdata=.data",
                "-NODEFAULTLIB",
                "-SECTION:.xdata,D",
            }),
            .win32 => {
                if (link_in_crt) {
                    if (target.abi.isGnu()) {
                        if (target.cpu.arch == .x86) {
                            try argv.append("-ALTERNATENAME:__image_base__=___ImageBase");
                        } else {
                            try argv.append("-ALTERNATENAME:__image_base__=__ImageBase");
                        }

                        try argv.append(try comp.crtFileAsString(arena, if (is_dyn_lib) "dllcrt2.obj" else "crt2.obj"));
                        try argv.append(try comp.crtFileAsString(arena, "libmingw32.lib"));
                    } else {
                        try argv.append(switch (comp.config.link_mode) {
                            .static => "libcmt.lib",
                            .dynamic => "msvcrt.lib",
                        });

                        const lib_str = switch (comp.config.link_mode) {
                            .static => "lib",
                            .dynamic => "",
                        };
                        try argv.append(try arena.print("{s}vcruntime.lib", .{lib_str}));
                        try argv.append(try arena.print("{s}ucrt.lib", .{lib_str}));

                        //Visual C++ 2015 Conformance Changes
                        //https://msdn.microsoft.com/en-us/library/bb531344.aspx
                        try argv.append("legacy_stdio_definitions.lib");

                        // msvcrt depends on kernel32 and ntdll
                        try argv.append("kernel32.lib");
                        try argv.append("ntdll.lib");
                    }
                } else {
                    try argv.append("-NODEFAULTLIB");
                    if (!is_lib and entry_name == null) {
                        if (comp.zcu != null) {
                            if (coff.lld_export_flags.winmain_crt_startup) {
                                try argv.append("-ENTRY:WinMainCRTStartup");
                            } else {
                                try argv.append("-ENTRY:wWinMainCRTStartup");
                            }
                        } else {
                            try argv.append("-ENTRY:wWinMainCRTStartup");
                        }
                    }
                }
            },
        }

        if (comp.config.link_libc and link_in_crt) {
            if (comp.zigc_static_lib) |zigc| {
                try argv.append(try zigc.full_object_path.toString(arena));
            }
        }

        // libc++ dep
        if (comp.config.link_libcpp) {
            try argv.append(try comp.libcxxabi_static_lib.?.full_object_path.toString(arena));
            try argv.append(try comp.libcxx_static_lib.?.full_object_path.toString(arena));
        }

        // libunwind dep
        if (comp.config.link_libunwind) {
            try argv.append(try comp.libunwind_static_lib.?.full_object_path.toString(arena));
        }

        if (comp.config.any_fuzz) {
            try argv.append(try comp.fuzzer_lib.?.full_object_path.toString(arena));
        }

        const ubsan_rt_path: ?Cache.Path = blk: {
            if (comp.ubsan_rt_lib) |x| break :blk x.full_object_path;
            if (comp.ubsan_rt_obj) |x| break :blk x.full_object_path;
            break :blk null;
        };
        if (ubsan_rt_path) |path| {
            try argv.append(try path.toString(arena));
        }

        if (is_exe_or_dyn_lib and !comp.skip_linker_dependencies) {
            // MSVC compiler_rt is missing some stuff, so we build it unconditionally but
            // and rely on weak linkage to allow MSVC compiler_rt functions to override ours.
            if (comp.compiler_rt_obj) |obj| try argv.append(try obj.full_object_path.toString(arena));
            if (comp.compiler_rt_lib) |lib| try argv.append(try lib.full_object_path.toString(arena));
        }

        try argv.ensureUnusedCapacity(comp.windows_libs.count());
        for (comp.windows_libs.keys()) |key| {
            const lib_basename = try arena.print("{s}.lib", .{key});
            if (comp.crt_files.get(lib_basename)) |crt_file| {
                argv.appendAssumeCapacity(try crt_file.full_object_path.toString(arena));
                continue;
            }
            if (try findLib(arena, io, lib_basename, coff.lib_directories)) |full_path| {
                argv.appendAssumeCapacity(full_path);
                continue;
            }
            if (target.abi.isGnu()) {
                const fallback_name = try arena.print("lib{s}.dll.a", .{key});
                if (try findLib(arena, io, fallback_name, coff.lib_directories)) |full_path| {
                    argv.appendAssumeCapacity(full_path);
                    continue;
                }
            }
            if (target.abi == .msvc or target.abi == .itanium) {
                argv.appendAssumeCapacity(lib_basename);
                continue;
            }

            log.err("DLL import library for -l{s} not found", .{key});
            return error.DllImportLibraryNotFound;
        }

        try spawnLld(comp, arena, argv.items);
    }
}
fn findLib(arena: Allocator, io: Io, name: []const u8, lib_directories: []const Cache.Directory) !?[]const u8 {
    for (lib_directories) |lib_directory| {
        lib_directory.handle.access(io, name, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => |e| return e,
        };
        return try lib_directory.join(arena, &.{name});
    }
    return null;
}

fn elfLink(lld: *Lld, arena: Allocator) !void {
    const comp = lld.base.comp;
    const gpa = comp.gpa;
    const io = comp.io;
    const diags = &comp.link_diags;
    const base = &lld.base;
    const elf = &lld.ofmt.elf;

    const directory = base.emit.root_dir; // Just an alias to make it shorter to type.
    const full_out_path = try directory.join(arena, &[_][]const u8{base.emit.sub_path});

    const zcu_obj_path: ?Cache.Path = if (comp.zcu) |zcu| p: {
        break :p try comp.resolveEmitPathFlush(arena, .temp, zcu.llvm_object.?.out_bin_basename);
    } else null;

    const output_mode = comp.config.output_mode;
    const is_obj = output_mode == .Obj;
    const is_lib = output_mode == .Lib;
    const link_mode = comp.config.link_mode;
    const is_dyn_lib = link_mode == .dynamic and is_lib;
    const is_exe_or_dyn_lib = is_dyn_lib or output_mode == .Exe;
    const target = &comp.root_mod.resolved_target.result;
    const compiler_rt_path: ?Cache.Path = blk: {
        if (comp.compiler_rt_lib) |x| break :blk x.full_object_path;
        if (comp.compiler_rt_obj) |x| break :blk x.full_object_path;
        break :blk null;
    };
    const ubsan_rt_path: ?Cache.Path = blk: {
        if (comp.ubsan_rt_lib) |x| break :blk x.full_object_path;
        if (comp.ubsan_rt_obj) |x| break :blk x.full_object_path;
        break :blk null;
    };

    // Due to a deficiency in LLD, we need to special-case BPF to a simple file
    // copy when generating relocatables. Normally, we would expect `lld -r` to work.
    // However, because LLD wants to resolve BPF relocations which it shouldn't, it fails
    // before even generating the relocatable.
    //
    // For m68k, we go through this path because LLD doesn't support it yet, but LLVM can
    // produce usable object files.
    if (output_mode == .Obj and
        (comp.config.lto != .none or
            target.cpu.arch.isBpf() or
            target.cpu.arch == .lanai or
            target.cpu.arch == .m68k or
            target.cpu.arch.isSPARC() or
            target.cpu.arch == .ve or
            target.cpu.arch == .xcore or
            target.cpu.arch == .xtensa))
    {
        // In this case we must do a simple file copy
        // here. TODO: think carefully about how we can avoid this redundant operation when doing
        // build-obj. See also the corresponding TODO in linkAsArchive.
        const the_object_path = blk: {
            if (link.firstObjectInput(comp.link_inputs)) |obj| break :blk obj.path;

            if (comp.c_objects.items.len != 0)
                break :blk comp.c_objects.items[0].status.success.object_path;

            if (zcu_obj_path) |p|
                break :blk p;

            // TODO I think this is unreachable. Audit this situation when solving the above TODO
            // regarding eliding redundant object -> object transformations.
            return error.NoObjectsToLink;
        };
        try Io.Dir.copyFile(
            the_object_path.root_dir.handle,
            the_object_path.sub_path,
            directory.handle,
            base.emit.sub_path,
            io,
            .{},
        );
        if (elf.define_common) {
            try defineCommonSymbolsInRelocatable(gpa, io, full_out_path);
        }
    } else {
        // Create an LLD command line and invoke it.
        var argv = std.array_list.Managed([]const u8).init(gpa);
        defer argv.deinit();
        // We will invoke ourselves as a child process to gain access to LLD.
        // This is necessary because LLD does not behave properly as a library -
        // it calls exit() and does not reset all global data between invocations.
        const linker_command = "ld.lld";
        try argv.appendSlice(&[_][]const u8{ comp.self_exe_path orelse "zig", linker_command });
        try addCommonArgs(&argv, false);

        if (is_obj) {
            try argv.append("-r");
        }

        try argv.append("--error-limit=0");

        if (comp.sysroot) |sysroot| {
            try argv.append(try arena.print("--sysroot={s}", .{sysroot}));
        }

        if (target_util.llvmMachineAbi(target)) |mabi| {
            try argv.appendSlice(&.{
                "-mllvm",
                try arena.print("-target-abi={s}", .{mabi}),
            });
        }

        try argv.appendSlice(&.{
            "-mllvm",
            try arena.print("-float-abi={s}", .{if (target.abi.float() == .hard) "hard" else "soft"}),
        });

        switch (target.cpu.arch) {
            .armeb, .thumbeb => if (is_exe_or_dyn_lib and target.cpu.has(.arm, .has_v6)) try argv.append("--be8"),
            else => {},
        }

        if (comp.config.lto != .none) {
            switch (comp.root_mod.optimize_mode) {
                .debug => {},
                .small => try argv.append("--lto-O2"),
                .fast, .safe => try argv.append("--lto-O3"),
            }
        }
        switch (comp.root_mod.optimize_mode) {
            .debug => {},
            .small => try argv.append("-O2"),
            .fast, .safe => try argv.append("-O3"),
        }

        if (elf.entry_name) |name| {
            try argv.appendSlice(&.{ "--entry", name });
        }

        for (comp.force_undefined_symbols.keys()) |sym| {
            try argv.append("-u");
            try argv.append(sym);
        }

        switch (elf.hash_style) {
            .gnu => try argv.append("--hash-style=gnu"),
            .sysv => try argv.append("--hash-style=sysv"),
            .both => {}, // this is the default
        }

        if (output_mode == .Exe) {
            try argv.appendSlice(&.{
                "-z",
                try arena.print("stack-size={d}", .{base.stack_size}),
            });
        }

        switch (base.build_id) {
            .none => try argv.append("--build-id=none"),
            .fast, .uuid, .sha1, .md5 => try argv.append(try arena.print("--build-id={s}", .{
                @tagName(base.build_id),
            })),
            .hexstring => |hs| try argv.append(try arena.print("--build-id=0x{x}", .{hs.toSlice()})),
        }

        try argv.append(try arena.print("--image-base={d}", .{elf.image_base}));

        const default_script_overridden = if (elf.default_linker_script != null) blk: {
            for (elf.linker_scripts) |script_path| {
                if (isReplacementLinkerScript(io, gpa, script_path)) break :blk true;
            }
            break :blk false;
        } else false;

        if (elf.default_linker_script == null or default_script_overridden) {
            for (elf.linker_scripts) |linker_script| {
                try argv.append("-T");
                try argv.append(try linker_script.toString(arena));
            }
        }

        if (elf.sort_section) |how| {
            const arg = try arena.print("--sort-section={s}", .{@tagName(how)});
            try argv.append(arg);
        }

        if (base.gc_sections) {
            try argv.append("--gc-sections");
        }

        if (base.print_gc_sections) {
            try argv.append("--print-gc-sections");
        }

        if (elf.print_icf_sections) {
            try argv.append("--print-icf-sections");
        }

        if (elf.print_map) {
            try argv.append("--print-map");
        }

        if (elf.nmagic) {
            try argv.append("--nmagic");
        }

        if (elf.fatal_warnings) {
            try argv.append("--fatal-warnings");
        }

        if (comp.link_eh_frame_hdr) {
            try argv.append("--eh-frame-hdr");
        }

        if (elf.emit_relocs) {
            try argv.append("--emit-relocs");
        }

        if (comp.config.rdynamic) {
            try argv.append("--export-dynamic");
        }

        if (comp.config.debug_format == .strip) {
            try argv.append("-s");
        }

        if (elf.z_nodelete) {
            try argv.append("-z");
            try argv.append("nodelete");
        }
        if (elf.z_notext) {
            try argv.append("-z");
            try argv.append("notext");
        }
        if (elf.z_defs) {
            try argv.append("-z");
            try argv.append("defs");
        }
        if (elf.z_origin) {
            try argv.append("-z");
            try argv.append("origin");
        }
        if (elf.z_nocopyreloc) {
            try argv.append("-z");
            try argv.append("nocopyreloc");
        }
        if (elf.z_now) {
            // LLD defaults to -zlazy
            try argv.append("-znow");
        }
        if (!elf.z_relro) {
            // LLD defaults to -zrelro
            try argv.append("-znorelro");
        }
        if (elf.z_common_page_size) |size| {
            try argv.append("-z");
            try argv.append(try arena.print("common-page-size={d}", .{size}));
        }
        if (elf.z_max_page_size) |size| {
            try argv.append("-z");
            try argv.append(try arena.print("max-page-size={d}", .{size}));
        }

        if (getLDMOption(target)) |ldm| {
            try argv.append("-m");
            try argv.append(ldm);
        }

        if (link_mode == .static) {
            if (target.cpu.arch.isArm()) {
                try argv.append("-Bstatic");
            } else {
                try argv.append("-static");
            }
        } else if (switch (target.os.tag) {
            else => is_dyn_lib,
            .haiku => is_exe_or_dyn_lib,
        }) {
            try argv.append("-shared");
        }

        if (comp.config.pie and output_mode == .Exe) {
            try argv.append("-pie");
        }

        if (is_exe_or_dyn_lib and target.os.tag == .netbsd) {
            // Add options to produce shared objects with only 2 PT.LOAD segments.
            // NetBSD expects 2 PT.LOAD segments in a shared object, otherwise
            // ld.elf_so fails loading dynamic libraries with "not found" error.
            // See https://github.com/ziglang/zig/issues/9109 .
            try argv.append("--no-rosegment");
            try argv.append("-znorelro");
        }

        try argv.append("-o");
        try argv.append(full_out_path);

        // csu prelude
        const csu = try comp.getCrtPaths(arena);
        if (csu.crt0) |p| try argv.append(try p.toString(arena));
        if (csu.crti) |p| try argv.append(try p.toString(arena));
        if (csu.crtbegin) |p| try argv.append(try p.toString(arena));

        for (elf.rpath_list) |rpath| {
            try argv.appendSlice(&.{ "-rpath", rpath });
        }

        for (elf.symbol_wrap_set) |symbol_name| {
            try argv.appendSlice(&.{ "-wrap", symbol_name });
        }

        if (comp.config.link_libc) {
            if (comp.libc_installation) |libc_installation| {
                try argv.append("-L");
                try argv.append(libc_installation.crt_dir.?);
            }
        }

        if (output_mode == .Exe and link_mode == .dynamic) {
            if (target.dynamic_linker.get()) |dynamic_linker| {
                try argv.append("--dynamic-linker");
                try argv.append(dynamic_linker);
            } else {
                try argv.append("--no-dynamic-linker");
            }
        }

        if (is_dyn_lib) {
            if (elf.soname) |soname| {
                try argv.append("-soname");
                try argv.append(soname);
            }
            if (elf.version_script) |version_script| {
                try argv.append("-version-script");
                try argv.append(try version_script.toString(arena));
            }
            if (elf.allow_undefined_version) {
                try argv.append("--undefined-version");
            } else {
                try argv.append("--no-undefined-version");
            }
            if (elf.enable_new_dtags) |enable_new_dtags| {
                if (enable_new_dtags) {
                    try argv.append("--enable-new-dtags");
                } else {
                    try argv.append("--disable-new-dtags");
                }
            }
        }

        // Positional arguments to the linker such as object files.
        var whole_archive = false;

        for (base.comp.link_inputs) |link_input| switch (link_input) {
            .res => unreachable, // Windows-only
            .tbd => unreachable, // Darwin-only
            .dso => continue,
            .object, .archive => |obj| {
                if (obj.must_link and !whole_archive) {
                    try argv.append("--whole-archive");
                    whole_archive = true;
                } else if (!obj.must_link and whole_archive) {
                    try argv.append("--no-whole-archive");
                    whole_archive = false;
                }
                try argv.append(try obj.path.toString(arena));
            },
        };

        if (whole_archive) {
            try argv.append("--no-whole-archive");
            whole_archive = false;
        }

        for (comp.c_objects.items) |c_object| {
            try argv.append(try c_object.status.success.object_path.toString(arena));
        }

        if (zcu_obj_path) |p| {
            try argv.append(try p.toString(arena));
        }

        if (comp.tsan_lib) |lib| {
            assert(comp.config.any_sanitize_thread);
            try argv.appendSlice(&.{
                "--whole-archive",
                try lib.full_object_path.toString(arena),
                "--no-whole-archive",
            });
        }

        if (comp.fuzzer_lib) |lib| {
            assert(comp.config.any_fuzz);
            try argv.append(try lib.full_object_path.toString(arena));
        }

        if (ubsan_rt_path) |p| {
            try argv.append(try p.toString(arena));
        }

        // Shared libraries.
        if (is_exe_or_dyn_lib) {
            // Worst-case, we need an --as-needed argument for every lib, as well
            // as one before and one after.
            try argv.ensureUnusedCapacity(2 * base.comp.link_inputs.len + 2);
            argv.appendAssumeCapacity("--as-needed");
            var as_needed = true;

            // When we have a DSO input, in order to trick LLD into putting the basename in its
            // `DT_NEEDED` entry while still allowing us to tell it the exact path to the shared
            // object, we pass it on the CLI as "-l:/absolute/path/to/libfoo.so". This will treat
            // the given path not actually as an absolute path, but as relative to the library
            // search path, so the root directory must therefore be the only library search path.
            try argv.append("-L/");

            for (base.comp.link_inputs) |link_input| switch (link_input) {
                .res => unreachable, // Windows-only
                .tbd => unreachable, // Darwin-only
                .object, .archive => continue,
                .dso => |dso| {
                    const lib_as_needed = !dso.needed;
                    switch ((@as(u2, @intFromBool(lib_as_needed)) << 1) | @intFromBool(as_needed)) {
                        0b00, 0b11 => {},
                        0b01 => {
                            argv.appendAssumeCapacity("--no-as-needed");
                            as_needed = false;
                        },
                        0b10 => {
                            argv.appendAssumeCapacity("--as-needed");
                            as_needed = true;
                        },
                    }

                    // By this time, we depend on these libs being dynamically linked libraries and
                    // not static libraries (the check for that needs to be earlier), but they could
                    // be full file paths, in which case we don't want to use the "-l:" strategy.
                    switch (dso.fallback_soname) {
                        .basename => try argv.append(try arena.print("-l:{s}", .{try fs.path.resolve(arena, &.{
                            comp.dirs.cwd,
                            dso.path.root_dir.path orelse ".",
                            dso.path.sub_path,
                        })})),
                        .full_path => try argv.append(try dso.path.toString(arena)),
                    }
                },
            };

            if (!as_needed) {
                argv.appendAssumeCapacity("--as-needed");
                as_needed = true;
            }

            // libc++ dep
            if (comp.config.link_libcpp) {
                try argv.append(try comp.libcxxabi_static_lib.?.full_object_path.toString(arena));
                try argv.append(try comp.libcxx_static_lib.?.full_object_path.toString(arena));
            }

            // libunwind dep
            if (comp.config.link_libunwind) {
                try argv.append(try comp.libunwind_static_lib.?.full_object_path.toString(arena));
            }

            // libc dep
            diags.flags.missing_libc = false;
            if (comp.config.link_libc) {
                if (comp.libc_installation != null) {
                    const needs_grouping = link_mode == .static;
                    if (needs_grouping) try argv.append("--start-group");
                    try argv.appendSlice(target_util.libcFullLinkFlags(target));
                    if (needs_grouping) try argv.append("--end-group");
                } else if (target.isGnuLibC()) {
                    for (glibc.libs) |lib| {
                        if (lib.removed_in) |rem_in| {
                            if (target.os.versionRange().gnuLibCVersion().?.order(rem_in) != .lt) continue;
                        }

                        const lib_path = try arena.print("{f}{c}lib{s}.so.{d}", .{
                            comp.glibc_so_files.?.dir_path, fs.path.sep, lib.name, lib.sover,
                        });
                        try argv.append(lib_path);
                    }
                    try argv.append(try comp.crtFileAsString(arena, "libc_nonshared.a"));
                } else if (target.isMuslLibC()) {
                    try argv.append(try comp.crtFileAsString(arena, switch (link_mode) {
                        .static => "libc.a",
                        .dynamic => "libc.so",
                    }));
                } else if (target.isFreeBSDLibC()) {
                    for (freebsd.libs) |lib| {
                        if (lib.added_in) |add_in| {
                            if (target.os.version_range.semver.min.order(add_in) == .lt) continue;
                        }

                        const lib_path = try arena.print("{f}{c}lib{s}.so.{d}", .{
                            comp.freebsd_so_files.?.dir_path, fs.path.sep, lib.name, lib.getSoVersion(&target.os),
                        });
                        try argv.append(lib_path);
                    }
                } else if (target.isNetBSDLibC()) {
                    for (netbsd.libs) |lib| {
                        const lib_path = try arena.print("{f}{c}lib{s}.so.{d}", .{
                            comp.netbsd_so_files.?.dir_path, fs.path.sep, lib.name, lib.sover,
                        });
                        try argv.append(lib_path);
                    }
                } else if (target.isOpenBSDLibC()) {
                    for (openbsd.libs) |lib| {
                        const lib_path = try arena.print("{f}{c}lib{s}.so", .{
                            comp.openbsd_so_files.?.dir_path, fs.path.sep, lib.name,
                        });
                        try argv.append(lib_path);
                    }
                } else {
                    diags.flags.missing_libc = true;
                }

                if (comp.zigc_static_lib) |zigc| {
                    try argv.append(try zigc.full_object_path.toString(arena));
                }
            }
        }

        // compiler-rt. Since compiler_rt exports symbols like `memset`, it needs
        // to be after the shared libraries, so they are picked up from the shared
        // libraries, not libcompiler_rt.
        if (compiler_rt_path) |p| {
            try argv.append(try p.toString(arena));
        }

        // crt postlude
        if (csu.crtend) |p| try argv.append(try p.toString(arena));
        if (csu.crtn) |p| try argv.append(try p.toString(arena));

        if (base.allow_shlib_undefined) {
            try argv.append("--allow-shlib-undefined");
        }

        switch (elf.compress_debug_sections) {
            .none => {},
            .zlib => try argv.append("--compress-debug-sections=zlib"),
            .zstd => try argv.append("--compress-debug-sections=zstd"),
        }

        if (elf.bind_global_refs_locally) {
            try argv.append("-Bsymbolic");
        }

        if (elf.default_linker_script) |default_linker_script| {
            if (elf.linker_scripts.len == 0 or default_script_overridden) {
                try argv.append("--default-script");
                try argv.append(try default_linker_script.toString(arena));
            } else {
                try argv.append("-T");
                try argv.append(try default_linker_script.toString(arena));
                for (elf.linker_scripts) |linker_script| {
                    try argv.append("-T");
                    try argv.append(try linker_script.toString(arena));
                }
            }
        }

        try spawnLld(comp, arena, argv.items);

        if (is_obj and elf.define_common) {
            try defineCommonSymbolsInRelocatable(gpa, io, full_out_path);
        }
    }
}

fn isLinkerScriptIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '.';
}

/// Returns true if the linker script at `path` contains a top-level `SECTIONS`
/// command without an `INSERT` (`INSERT BEFORE` / `INSERT AFTER`) directive,
/// meaning it replaces the default linker script rather than augmenting it.
fn isReplacementLinkerScript(io: Io, gpa: Allocator, path: Cache.Path) bool {
    const bytes = path.root_dir.handle.readFileAlloc(io, path.sub_path, gpa, .limited(16 * 1024 * 1024)) catch return false;
    defer gpa.free(bytes);

    var has_sections = false;
    var has_insert = false;
    var i: usize = 0;
    while (i < bytes.len) {
        const c = bytes[i];
        if (c == '/' and i + 1 < bytes.len and bytes[i + 1] == '*') {
            i += 2;
            while (i + 1 < bytes.len and !(bytes[i] == '*' and bytes[i + 1] == '/')) : (i += 1) {}
            i = @min(i + 2, bytes.len);
            continue;
        }
        if (c == '#') {
            while (i < bytes.len and bytes[i] != '\n') : (i += 1) {}
            continue;
        }
        if (c == '"') {
            i += 1;
            while (i < bytes.len and bytes[i] != '"') : (i += 1) {
                if (bytes[i] == '\\' and i + 1 < bytes.len) i += 1;
            }
            i = @min(i + 1, bytes.len);
            continue;
        }
        if (isLinkerScriptIdentChar(c)) {
            const start = i;
            while (i < bytes.len and isLinkerScriptIdentChar(bytes[i])) : (i += 1) {}
            const tok = bytes[start..i];
            if (mem.eql(u8, tok, "SECTIONS")) {
                has_sections = true;
            } else if (mem.eql(u8, tok, "INSERT")) {
                has_insert = true;
            }
            continue;
        }
        i += 1;
    }
    return has_sections and !has_insert;
}

fn defineCommonSymbolsInRelocatable(gpa: Allocator, io: Io, path: []const u8) !void {
    const bytes = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited);
    defer gpa.free(bytes);

    if (bytes.len < std.elf.EI_NIDENT) return;
    if (!mem.eql(u8, bytes[0..4], std.elf.MAGIC)) return;

    const endian: std.builtin.Endian = switch (bytes[std.elf.EI_DATA]) {
        std.elf.ELFDATA2LSB => .little,
        std.elf.ELFDATA2MSB => .big,
        else => return,
    };

    const modified = switch (bytes[std.elf.EI_CLASS]) {
        std.elf.ELFCLASS32 => defineCommonSymbolsInRelocatableImpl(
            std.elf.Elf32_Ehdr,
            std.elf.Elf32_Shdr,
            std.elf.Elf32_Sym,
            bytes,
            endian,
        ),
        std.elf.ELFCLASS64 => defineCommonSymbolsInRelocatableImpl(
            std.elf.Elf64_Ehdr,
            std.elf.Elf64_Shdr,
            std.elf.Elf64_Sym,
            bytes,
            endian,
        ),
        else => false,
    };

    if (modified) {
        try Io.Dir.cwd().writeFile(io, .{
            .sub_path = path,
            .data = bytes,
        });
    }
}

fn defineCommonSymbolsInRelocatableImpl(
    comptime Ehdr: type,
    comptime Shdr: type,
    comptime Sym: type,
    bytes: []u8,
    endian: std.builtin.Endian,
) bool {
    if (bytes.len < @sizeOf(Ehdr)) return false;
    const ehdr = mem.bytesAsValue(Ehdr, bytes[0..@sizeOf(Ehdr)]);
    if (mem.toNative(u16, @backingInt(ehdr.e_type), endian) != @backingInt(std.elf.ET.REL)) return false;

    const shoff: usize = @intCast(mem.toNative(@TypeOf(ehdr.e_shoff), ehdr.e_shoff, endian));
    const shnum: usize = mem.toNative(u16, ehdr.e_shnum, endian);
    const shentsize: usize = mem.toNative(u16, ehdr.e_shentsize, endian);
    if (shnum == 0 or shentsize < @sizeOf(Shdr)) return false;
    if (shoff + shnum * shentsize > bytes.len) return false;

    const shstrndx: usize = mem.toNative(u16, ehdr.e_shstrndx, endian);
    if (shstrndx >= shnum) return false;
    const shstr_shdr = mem.bytesAsValue(Shdr, bytes[shoff + shstrndx * shentsize ..][0..@sizeOf(Shdr)]);
    const shstr_off: usize = @intCast(mem.toNative(@TypeOf(shstr_shdr.sh_offset), shstr_shdr.sh_offset, endian));
    const shstr_size: usize = @intCast(mem.toNative(@TypeOf(shstr_shdr.sh_size), shstr_shdr.sh_size, endian));
    if (shstr_off + shstr_size > bytes.len) return false;
    const shstrtab = bytes[shstr_off .. shstr_off + shstr_size];

    var symtab_shdr_opt: ?*align(1) Shdr = null;
    var common_shndx: ?u16 = null;
    var bss_shndx: ?u16 = null;
    var fallback_nobits_shndx: ?u16 = null;

    for (0..shnum) |idx| {
        const shdr = mem.bytesAsValue(Shdr, bytes[shoff + idx * shentsize ..][0..@sizeOf(Shdr)]);
        const sh_type = mem.toNative(u32, shdr.sh_type, endian);
        if (sh_type == std.elf.SHT_SYMTAB) {
            symtab_shdr_opt = shdr;
        } else if (sh_type == std.elf.SHT_NOBITS) {
            const sh_name: usize = mem.toNative(u32, shdr.sh_name, endian);
            if (sh_name < shstrtab.len) {
                const name = mem.sliceTo(shstrtab[sh_name..], 0);
                if (mem.eql(u8, name, "COMMON")) {
                    common_shndx = @intCast(idx);
                } else if (mem.eql(u8, name, ".bss")) {
                    bss_shndx = @intCast(idx);
                } else if (fallback_nobits_shndx == null) {
                    const sh_flags = mem.toNative(@TypeOf(shdr.sh_flags), shdr.sh_flags, endian);
                    if ((sh_flags & std.elf.SHF_ALLOC) != 0 and (sh_flags & std.elf.SHF_WRITE) != 0) {
                        fallback_nobits_shndx = @intCast(idx);
                    }
                }
            }
        }
    }

    const symtab_shdr = symtab_shdr_opt orelse return false;
    const sym_off: usize = @intCast(mem.toNative(@TypeOf(symtab_shdr.sh_offset), symtab_shdr.sh_offset, endian));
    const sym_size_bytes: usize = @intCast(mem.toNative(@TypeOf(symtab_shdr.sh_size), symtab_shdr.sh_size, endian));
    const symentsize: usize = @intCast(mem.toNative(@TypeOf(symtab_shdr.sh_entsize), symtab_shdr.sh_entsize, endian));
    if (symentsize < @sizeOf(Sym) or sym_off + sym_size_bytes > bytes.len) return false;
    const sym_count = sym_size_bytes / symentsize;

    var has_common_syms = false;
    for (0..sym_count) |i| {
        const sym = mem.bytesAsValue(Sym, bytes[sym_off + i * symentsize ..][0..@sizeOf(Sym)]);
        if (mem.toNative(u16, sym.st_shndx, endian) == std.elf.SHN_COMMON) {
            has_common_syms = true;
            break;
        }
    }
    if (!has_common_syms) return false;

    const Word = @TypeOf(symtab_shdr.sh_size);
    var target_shndx: u16 = undefined;
    var offset: u64 = 0;

    if (common_shndx != null and bss_shndx == null) {
        target_shndx = common_shndx.?;
        const common_shdr = mem.bytesAsValue(Shdr, bytes[shoff + @as(usize, target_shndx) * shentsize ..][0..@sizeOf(Shdr)]);
        const sh_name: usize = mem.toNative(u32, common_shdr.sh_name, endian);
        if (sh_name + 7 <= shstrtab.len and mem.eql(u8, shstrtab[sh_name .. sh_name + 7], "COMMON\x00")) {
            @memcpy(shstrtab[sh_name .. sh_name + 7], ".bss\x00\x00\x00");
        }
        common_shdr.sh_size = mem.nativeTo(Word, 0, endian);
        offset = 0;
    } else if (bss_shndx != null and common_shndx != null) {
        target_shndx = bss_shndx.?;
        const bss_shdr = mem.bytesAsValue(Shdr, bytes[shoff + @as(usize, target_shndx) * shentsize ..][0..@sizeOf(Shdr)]);
        const common_shdr = mem.bytesAsValue(Shdr, bytes[shoff + @as(usize, common_shndx.?) * shentsize ..][0..@sizeOf(Shdr)]);
        offset = mem.toNative(Word, bss_shdr.sh_size, endian);
        common_shdr.sh_size = mem.nativeTo(Word, 0, endian);
    } else if (bss_shndx != null or fallback_nobits_shndx != null) {
        target_shndx = bss_shndx orelse fallback_nobits_shndx.?;
        var max_defined_end: u64 = 0;
        for (0..sym_count) |i| {
            const sym = mem.bytesAsValue(Sym, bytes[sym_off + i * symentsize ..][0..@sizeOf(Sym)]);
            if (mem.toNative(u16, sym.st_shndx, endian) == target_shndx) {
                const val: u64 = mem.toNative(Word, sym.st_value, endian);
                const sz: u64 = mem.toNative(Word, sym.st_size, endian);
                max_defined_end = @max(max_defined_end, val + sz);
            }
        }
        offset = max_defined_end;
    } else {
        return false;
    }

    const target_shdr = mem.bytesAsValue(Shdr, bytes[shoff + @as(usize, target_shndx) * shentsize ..][0..@sizeOf(Shdr)]);
    var max_align: u64 = @max(@as(u64, mem.toNative(Word, target_shdr.sh_addralign, endian)), 1);

    for (0..sym_count) |i| {
        const sym = mem.bytesAsValue(Sym, bytes[sym_off + i * symentsize ..][0..@sizeOf(Sym)]);
        if (mem.toNative(u16, sym.st_shndx, endian) != std.elf.SHN_COMMON) continue;

        const sym_align: u64 = @max(@as(u64, mem.toNative(Word, sym.st_value, endian)), 1);
        const sym_size: u64 = mem.toNative(Word, sym.st_size, endian);
        offset = mem.alignForward(u64, offset, sym_align);

        sym.st_shndx = mem.nativeTo(u16, target_shndx, endian);
        sym.st_value = mem.nativeTo(Word, @intCast(offset), endian);
        if ((sym.st_info & 0xf) == std.elf.STT_NOTYPE) {
            sym.st_info = (sym.st_info & 0xf0) | std.elf.STT_OBJECT;
        }

        offset += sym_size;
        max_align = @max(max_align, sym_align);
    }

    const cur_size: u64 = mem.toNative(Word, target_shdr.sh_size, endian);
    target_shdr.sh_size = mem.nativeTo(Word, @intCast(@max(cur_size, offset)), endian);
    target_shdr.sh_addralign = mem.nativeTo(Word, @intCast(max_align), endian);
    return true;
}
fn getLDMOption(target: *const std.Target) ?[]const u8 {
    // This should only return emulations understood by LLD's parseEmulation().
    return switch (target.cpu.arch) {
        .aarch64 => switch (target.os.tag) {
            .linux => "aarch64linux",
            else => "aarch64elf",
        },
        .aarch64_be => switch (target.os.tag) {
            .linux => "aarch64linuxb",
            else => "aarch64elfb",
        },
        .amdgcn => "elf64_amdgpu",
        .arm, .thumb => switch (target.os.tag) {
            .linux => "armelf_linux_eabi",
            else => "armelf",
        },
        .armeb, .thumbeb => switch (target.os.tag) {
            .linux => "armelfb_linux_eabi",
            else => "armelfb",
        },
        .hexagon => "hexagonelf",
        .loongarch32 => "elf32loongarch",
        .loongarch64 => "elf64loongarch",
        .mips => switch (target.os.tag) {
            .freebsd => "elf32btsmip_fbsd",
            else => "elf32btsmip",
        },
        .mipsel => switch (target.os.tag) {
            .freebsd => "elf32ltsmip_fbsd",
            else => "elf32ltsmip",
        },
        .mips64 => switch (target.os.tag) {
            .freebsd => switch (target.abi) {
                .gnuabin32, .muslabin32, .abin32 => "elf32btsmipn32_fbsd",
                else => "elf64btsmip_fbsd",
            },
            else => switch (target.abi) {
                .gnuabin32, .muslabin32, .abin32 => "elf32btsmipn32",
                else => "elf64btsmip",
            },
        },
        .mips64el => switch (target.os.tag) {
            .freebsd => switch (target.abi) {
                .gnuabin32, .muslabin32, .abin32 => "elf32ltsmipn32_fbsd",
                else => "elf64ltsmip_fbsd",
            },
            else => switch (target.abi) {
                .gnuabin32, .muslabin32, .abin32 => "elf32ltsmipn32",
                else => "elf64ltsmip",
            },
        },
        .msp430 => "msp430elf",
        .powerpc => switch (target.os.tag) {
            .freebsd => "elf32ppc_fbsd",
            .linux => "elf32ppclinux",
            else => "elf32ppc",
        },
        .powerpcle => switch (target.os.tag) {
            .linux => "elf32lppclinux",
            else => "elf32lppc",
        },
        .powerpc64 => "elf64ppc",
        .powerpc64le => "elf64lppc",
        .riscv32 => "elf32lriscv",
        .riscv32be => "elf32briscv",
        .riscv64 => "elf64lriscv",
        .riscv64be => "elf64briscv",
        .s390x => "elf64_s390",
        .sparc64 => "elf64_sparc",
        .x86 => switch (target.os.tag) {
            .freebsd => "elf_i386_fbsd",
            else => "elf_i386",
        },
        .x86_64 => switch (target.abi) {
            .gnux32, .muslx32, .x32 => "elf32_x86_64",
            else => "elf_x86_64",
        },
        else => null,
    };
}
fn wasmLink(lld: *Lld, arena: Allocator) !void {
    const comp = lld.base.comp;
    const diags = &comp.link_diags;
    const shared_memory = comp.config.shared_memory;
    const export_memory = comp.config.export_memory;
    const import_memory = comp.config.import_memory;
    const target = &comp.root_mod.resolved_target.result;
    const base = &lld.base;
    const wasm = &lld.ofmt.wasm;

    const gpa = comp.gpa;
    const io = comp.io;

    const directory = base.emit.root_dir; // Just an alias to make it shorter to type.
    const full_out_path = try directory.join(arena, &[_][]const u8{base.emit.sub_path});

    const zcu_obj_path: ?Cache.Path = if (comp.zcu) |zcu| p: {
        break :p try comp.resolveEmitPathFlush(arena, .temp, zcu.llvm_object.?.out_bin_basename);
    } else null;

    const is_obj = comp.config.output_mode == .Obj;
    const compiler_rt_path: ?Cache.Path = blk: {
        if (comp.compiler_rt_lib) |lib| break :blk lib.full_object_path;
        if (comp.compiler_rt_obj) |obj| break :blk obj.full_object_path;
        break :blk null;
    };
    const ubsan_rt_path: ?Cache.Path = blk: {
        if (comp.ubsan_rt_lib) |lib| break :blk lib.full_object_path;
        if (comp.ubsan_rt_obj) |obj| break :blk obj.full_object_path;
        break :blk null;
    };

    if (is_obj) {
        // LLD's WASM driver does not support the equivalent of `-r` so we do a simple file copy
        // here. TODO: think carefully about how we can avoid this redundant operation when doing
        // build-obj. See also the corresponding TODO in linkAsArchive.
        const the_object_path = blk: {
            if (link.firstObjectInput(comp.link_inputs)) |obj| break :blk obj.path;

            if (comp.c_objects.items.len != 0)
                break :blk comp.c_objects.items[0].status.success.object_path;

            if (zcu_obj_path) |p|
                break :blk p;

            // TODO I think this is unreachable. Audit this situation when solving the above TODO
            // regarding eliding redundant object -> object transformations.
            return error.NoObjectsToLink;
        };
        try Io.Dir.copyFile(
            the_object_path.root_dir.handle,
            the_object_path.sub_path,
            directory.handle,
            base.emit.sub_path,
            io,
            .{},
        );
    } else {
        // Create an LLD command line and invoke it.
        var argv = std.array_list.Managed([]const u8).init(gpa);
        defer argv.deinit();
        // We will invoke ourselves as a child process to gain access to LLD.
        // This is necessary because LLD does not behave properly as a library -
        // it calls exit() and does not reset all global data between invocations.
        const linker_command = "wasm-ld";
        try argv.appendSlice(&[_][]const u8{ comp.self_exe_path orelse "zig", linker_command });
        try addCommonArgs(&argv, false);

        try argv.append("--error-limit=0");

        if (comp.config.lto != .none) {
            switch (comp.root_mod.optimize_mode) {
                .debug => {},
                .small => try argv.append("-O2"),
                .fast, .safe => try argv.append("-O3"),
            }
        }

        if (import_memory) {
            try argv.append("--import-memory");
        }

        if (export_memory) {
            try argv.append("--export-memory");
        }

        if (wasm.import_table) {
            assert(!wasm.export_table);
            try argv.append("--import-table");
        }

        if (wasm.export_table) {
            assert(!wasm.import_table);
            try argv.append("--export-table");
        }

        if (wasm.growable_table) {
            try argv.append("--growable-table");
        }

        // For wasm-ld we only need to specify '--no-gc-sections' when the user explicitly
        // specified it as garbage collection is enabled by default.
        if (!base.gc_sections) {
            try argv.append("--no-gc-sections");
        }

        if (comp.config.debug_format == .strip) {
            try argv.append("-s");
        }

        if (wasm.initial_memory) |initial_memory| {
            const arg = try arena.print("--initial-memory={d}", .{initial_memory});
            try argv.append(arg);
        }

        if (wasm.max_memory) |max_memory| {
            const arg = try arena.print("--max-memory={d}", .{max_memory});
            try argv.append(arg);
        }

        if (shared_memory) {
            try argv.append("--shared-memory");
        }

        if (wasm.global_base) |global_base| {
            const arg = try arena.print("--global-base={d}", .{global_base});
            try argv.append(arg);
        } else {
            // We prepend it by default, so when a stack overflow happens the runtime will trap correctly,
            // rather than silently overwrite all global declarations. See https://github.com/ziglang/zig/issues/4496
            //
            // The user can overwrite this behavior by setting the global-base
            try argv.append("--stack-first");
        }

        // Users are allowed to specify which symbols they want to export to the wasm host.
        for (wasm.export_symbol_names) |symbol_name| {
            const arg = try arena.print("--export={s}", .{symbol_name});
            try argv.append(arg);
        }

        if (target.os.tag == .wasip2 or target.os.tag == .wasip3) {
            try argv.append("--export-if-defined=cabi_realloc");
        }

        if (comp.config.rdynamic) {
            try argv.append("--export-dynamic");
        }

        if (wasm.entry_name) |entry_name| {
            try argv.appendSlice(&.{ "--entry", entry_name });
        } else {
            try argv.append("--no-entry");
        }

        try argv.appendSlice(&.{
            "-z",
            try arena.print("stack-size={d}", .{base.stack_size}),
        });

        switch (base.build_id) {
            .none => try argv.append("--build-id=none"),
            .fast, .uuid, .sha1 => try argv.append(try arena.print("--build-id={s}", .{
                @tagName(base.build_id),
            })),
            .hexstring => |hs| try argv.append(try arena.print("--build-id=0x{x}", .{hs.toSlice()})),
            .md5 => {},
        }

        if (wasm.import_symbols) {
            try argv.append("--allow-undefined");
        }

        if (comp.config.output_mode == .Lib and comp.config.link_mode == .dynamic) {
            try argv.append("--shared");
        }
        if (comp.config.pie) {
            try argv.append("--pie");
        }

        try argv.appendSlice(&.{ "-o", full_out_path });

        if (target.cpu.arch == .wasm64) {
            try argv.append("-mwasm64");
        }

        const is_exe_or_dyn_lib = comp.config.output_mode == .Exe or
            (comp.config.output_mode == .Lib and comp.config.link_mode == .dynamic);

        if (comp.config.link_libc and is_exe_or_dyn_lib) {
            if (target.os.tag.isWasi()) {
                try argv.append(try comp.crtFileAsString(
                    arena,
                    wasi_libc.execModelCrtFileFullName(comp.config.wasi_exec_model),
                ));
            }

            if (comp.zigc_static_lib) |zigc| {
                try argv.append(try zigc.full_object_path.toString(arena));
            }

            if (comp.config.link_libcpp) {
                try argv.append(try comp.libcxx_static_lib.?.full_object_path.toString(arena));
                try argv.append(try comp.libcxxabi_static_lib.?.full_object_path.toString(arena));
            }
        }

        // Positional arguments to the linker such as object files.
        var whole_archive = false;
        for (comp.link_inputs) |link_input| switch (link_input) {
            .object, .archive => |obj| {
                if (obj.must_link and !whole_archive) {
                    try argv.append("--whole-archive");
                    whole_archive = true;
                } else if (!obj.must_link and whole_archive) {
                    try argv.append("--no-whole-archive");
                    whole_archive = false;
                }
                try argv.append(try obj.path.toString(arena));
            },
            .dso => |dso| {
                try argv.append(try dso.path.toString(arena));
            },
            .tbd => unreachable,
            .res => unreachable,
        };
        if (whole_archive) {
            try argv.append("--no-whole-archive");
            whole_archive = false;
        }

        for (comp.c_objects.items) |c_object| {
            try argv.append(try c_object.status.success.object_path.toString(arena));
        }
        if (zcu_obj_path) |p| {
            try argv.append(try p.toString(arena));
        }

        if (compiler_rt_path) |p| {
            try argv.append(try p.toString(arena));
        }

        if (ubsan_rt_path) |p| {
            try argv.append(try p.toStringZ(arena));
        }

        try spawnLld(comp, arena, argv.items);

        if (target.os.tag == .wasip2 or target.os.tag == .wasip3) {
            const core_wasm_bytes = Io.Dir.cwd().readFileAlloc(io, full_out_path, gpa, .unlimited) catch |err|
                return diags.fail("failed to read core wasm '{s}': {s}", .{ full_out_path, @errorName(err) });
            defer gpa.free(core_wasm_bytes);

            const wit_source = if (wasm.wit_path) |wit_path|
                readWitPathAlloc(io, gpa, wit_path) catch |err|
                    return diags.fail("failed to read WIT path '{s}': {s}", .{ wit_path, @errorName(err) })
            else
                null;
            defer if (wit_source) |s| gpa.free(s);

            const custom_adapter_bytes = if (wasm.wasi_adapter_path) |adapter_path|
                Io.Dir.cwd().readFileAlloc(io, adapter_path, gpa, .unlimited) catch |err|
                    return diags.fail("failed to read WASI adapter file '{s}': {s}", .{ adapter_path, @errorName(err) })
            else
                null;
            defer if (custom_adapter_bytes) |b| gpa.free(b);

            const exec_model: std.builtin.WasiExecModel = if (comp.config.output_mode == .Lib)
                .reactor
            else
                comp.config.wasi_exec_model;

            const component_bytes = wasm_component.linkComponent(gpa, core_wasm_bytes, .{
                .exec_model = exec_model,
                .wasi_version = if (target.os.tag == .wasip3) .p3 else .p2,
                .wit_source = wit_source,
                .wit_world = wasm.wit_world,
                .custom_adapter_bytes = custom_adapter_bytes,
            }) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return diags.fail("failed to build WASI component: {s}", .{@errorName(err)}),
            };
            defer gpa.free(component_bytes);

            Io.Dir.cwd().writeFile(io, .{
                .sub_path = full_out_path,
                .data = component_bytes,
            }) catch |err|
                return diags.fail("failed to write WASI component '{s}': {s}", .{ full_out_path, @errorName(err) });
        }

        // Give +x to the .wasm file if it is an executable and the OS is WASI.
        // Some systems may be configured to execute such binaries directly. Even if that
        // is not the case, it means we will get "exec format error" when trying to run
        // it, and then can react to that in the same way as trying to run an ELF file
        // from a foreign CPU architecture.
        if (Io.File.Permissions.has_executable_bit and target.os.tag.isWasi() and
            comp.config.output_mode == .Exe)
        {
            // chmod does not interact with umask, so we use a conservative -rwxr--r-- here.
            Io.Dir.cwd().setFilePermissions(io, full_out_path, .fromMode(0o744), .{}) catch |err|
                return diags.fail("{s}: failed to enable executable permissions: {t}", .{ full_out_path, err });
        }
    }
}

fn spawnLld(comp: *Compilation, arena: Allocator, argv: []const []const u8) !void {
    const io = comp.io;

    if (comp.verbose_link) {
        // Skip over our own name so that the LLD linker name is the first argv item.
        try Compilation.dumpArgv(io, argv[1..]);
    }

    // If possible, we run LLD as a child process because it does not always
    // behave properly as a library, unfortunately.
    // https://github.com/ziglang/zig/issues/3825
    if (!std.process.can_spawn) {
        const exit_code = try lldMain(arena, argv, false);
        if (exit_code == 0) return;
        if (comp.clang_passthrough_mode) std.process.exit(exit_code);
        return error.AlreadyReported;
    }

    var diags: Compilation.EvalZigLlvmProcessDiagnostics = undefined;
    const result = comp.evalZigLlvmProcess(arena, &diags, argv) catch |err| switch (err) {
        else => |e| return e,
        error.EvalZigLlvmFail => {
            log.err("failed to evaluate LLD '{s}': {f}", .{ argv[0], diags });
            return error.UnableToSpawnSelf;
        },
    };

    switch (result.term) {
        .exited => |code| if (code != 0) {
            if (comp.clang_passthrough_mode) std.process.exit(code);
            comp.link_diags.lockAndParseLldStderr(argv[1], result.stderr);
            return error.AlreadyReported;
        },
        .signal => |sig| {
            if (comp.clang_passthrough_mode) std.process.abort();
            return comp.link_diags.fail("{s} terminated with signal {t} and stderr:\n{s}", .{ argv[0], sig, result.stderr });
        },
        .stopped => |sig| {
            if (comp.clang_passthrough_mode) std.process.abort();
            return comp.link_diags.fail("{s} stopped with signal {t} and stderr:\n{s}", .{ argv[0], sig, result.stderr });
        },
        .unknown => |code| {
            if (comp.clang_passthrough_mode) std.process.abort();
            return comp.link_diags.fail("{s} terminated for unknown reason with code {d} and stderr:\n{s}", .{ argv[0], code, result.stderr });
        },
    }

    if (result.stderr.len > 0) log.warn("unexpected LLD stderr:\n{s}", .{result.stderr});
}

fn readWitPathAlloc(io: Io, gpa: Allocator, wit_path: []const u8) ![]u8 {
    return Io.Dir.cwd().readFileAlloc(io, wit_path, gpa, .unlimited) catch |err| switch (err) {
        error.IsDir => {
            var dir = try Io.Dir.cwd().openDir(io, wit_path, .{ .iterate = true });
            defer dir.close(io);
            var it = dir.iterate();
            var names: std.ArrayList([]u8) = .empty;
            defer {
                for (names.items) |n| gpa.free(n);
                names.deinit(gpa);
            }
            while (try it.next(io)) |entry| {
                if (entry.kind == .file and mem.endsWith(u8, entry.name, ".wit")) {
                    const duped_name = try gpa.dupe(u8, entry.name);
                    errdefer gpa.free(duped_name);
                    try names.append(gpa, duped_name);
                }
            }
            if (names.items.len == 0) return error.FileNotFound;
            mem.sort([]u8, names.items, {}, struct {
                fn lessThan(_: void, a: []u8, b: []u8) bool {
                    return mem.lessThan(u8, a, b);
                }
            }.lessThan);
            const WitSource = wasm_component.wit.resolver.WitSource;
            var sources: std.ArrayList(WitSource) = .empty;
            defer {
                for (sources.items) |s| gpa.free(s.text);
                sources.deinit(gpa);
            }
            for (names.items) |name| {
                const text = try dir.readFileAlloc(io, name, gpa, .unlimited);
                errdefer gpa.free(text);
                try sources.append(gpa, .{
                    .path = name,
                    .text = text,
                });
            }
            const combined = try wasm_component.wit.resolver.combineWitSources(gpa, sources.items, wit_path, null);
            for (combined.paths) |p| gpa.free(p);
            gpa.free(combined.paths);
            return combined.text;
        },
        else => return err,
    };
}

const builtin = @import("builtin");
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Cache = std.Build.Cache;
const assert = std.debug.assert;
const fs = std.fs;
const log = std.log.scoped(.link);
const mem = std.mem;

const Compilation = @import("../Compilation.zig");
const Zcu = @import("../Zcu.zig");
const dev = @import("../dev.zig");
const freebsd = @import("../libs/freebsd.zig");
const glibc = @import("../libs/glibc.zig");
const netbsd = @import("../libs/netbsd.zig");
const openbsd = @import("../libs/openbsd.zig");
const wasm_component = @import("Wasm/component/root.zig");
const wasi_libc = @import("../libs/wasi_libc.zig");
const link = @import("../link.zig");
const lldMain = @import("../main.zig").lldMain;
const target_util = @import("../target.zig");
const trace = @import("../tracy.zig").trace;
const Lld = @This();

test "isReplacementLinkerScript" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const Helper = struct {
        fn check(test_io: Io, test_gpa: Allocator, dir: Io.Dir, name: []const u8, contents: []const u8) !bool {
            try dir.writeFile(test_io, .{
                .sub_path = name,
                .data = contents,
            });
            return isReplacementLinkerScript(test_io, test_gpa, .{
                .root_dir = .{ .path = null, .handle = dir },
                .sub_path = name,
            });
        }
    };

    try std.testing.expect(try Helper.check(
        io,
        gpa,
        tmp.dir,
        "full.lds",
        "SECTIONS { .text : { *(.text) } }",
    ));
    try std.testing.expect(!try Helper.check(
        io,
        gpa,
        tmp.dir,
        "before.lds",
        "SECTIONS { .uk_before : { KEEP(*(.uk_before)) } } INSERT BEFORE .text;",
    ));
    try std.testing.expect(!try Helper.check(
        io,
        gpa,
        tmp.dir,
        "after.lds",
        "SECTIONS { .uk_after : { KEEP(*(.uk_after)) } } INSERT AFTER .text;",
    ));
    try std.testing.expect(!try Helper.check(
        io,
        gpa,
        tmp.dir,
        "block_comment.lds",
        "/* SECTIONS { .text : { *(.text) } } */\nEXTERN(foo);",
    ));
    try std.testing.expect(!try Helper.check(
        io,
        gpa,
        tmp.dir,
        "line_comment.lds",
        "# SECTIONS { .text : { *(.text) } }\nEXTERN(foo);",
    ));
    try std.testing.expect(!try Helper.check(
        io,
        gpa,
        tmp.dir,
        "string_literal.lds",
        "OUTPUT_ARCH(\"SECTIONS\")\nEXTERN(\"SECTIONS\");",
    ));
}

test "defineCommonSymbolsInRelocatable" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const TestElfBuilder = struct {
        const SectionSpec = struct {
            name_off: u32,
            sh_type: u32,
            sh_flags: u64 = 0,
            sh_size: u64 = 0,
            sh_addralign: u64 = 1,
        };

        fn buildRelocatable(
            alloc: Allocator,
            shstrtab: []const u8,
            extra_sections: []const SectionSpec,
            syms: []const std.elf.Elf64_Sym,
        ) ![]u8 {
            const ehdr_size = @sizeOf(std.elf.Elf64_Ehdr);
            const shstr_off = ehdr_size;
            const sym_off = mem.alignForward(usize, shstr_off + shstrtab.len, 8);
            const sym_bytes_len = syms.len * @sizeOf(std.elf.Elf64_Sym);
            const shoff = mem.alignForward(usize, sym_off + sym_bytes_len, 8);
            // Sections: [0]=NULL, [1..1+extra_sections.len]=extra, [last-1]=.symtab, [last]=.shstrtab
            const shnum = 1 + extra_sections.len + 2;
            const total_len = shoff + shnum * @sizeOf(std.elf.Elf64_Shdr);

            const buf = try alloc.alloc(u8, total_len);
            @memset(buf, 0);

            var ehdr: std.elf.Elf64_Ehdr = std.mem.zeroes(std.elf.Elf64_Ehdr);
            @memcpy(ehdr.e_ident[0..4], std.elf.MAGIC);
            ehdr.e_ident[std.elf.EI_CLASS] = std.elf.ELFCLASS64;
            ehdr.e_ident[std.elf.EI_DATA] = std.elf.ELFDATA2LSB;
            ehdr.e_ident[std.elf.EI.VERSION] = 1;
            ehdr.e_type = @fromBackingInt(@intCast(mem.nativeTo(u16, @backingInt(std.elf.ET.REL), .little)));
            ehdr.e_machine = @fromBackingInt(@intCast(mem.nativeTo(u16, @backingInt(std.elf.EM.X86_64), .little)));
            ehdr.e_version = mem.nativeTo(u32, 1, .little);
            ehdr.e_shoff = mem.nativeTo(u64, shoff, .little);
            ehdr.e_ehsize = mem.nativeTo(u16, @sizeOf(std.elf.Elf64_Ehdr), .little);
            ehdr.e_shentsize = mem.nativeTo(u16, @sizeOf(std.elf.Elf64_Shdr), .little);
            ehdr.e_shnum = mem.nativeTo(u16, @intCast(shnum), .little);
            ehdr.e_shstrndx = mem.nativeTo(u16, @intCast(shnum - 1), .little);
            @memcpy(buf[0..ehdr_size], mem.asBytes(&ehdr));

            @memcpy(buf[shstr_off .. shstr_off + shstrtab.len], shstrtab);

            for (syms, 0..) |sym, i| {
                const off = sym_off + i * @sizeOf(std.elf.Elf64_Sym);
                @memcpy(buf[off .. off + @sizeOf(std.elf.Elf64_Sym)], mem.asBytes(&sym));
            }

            const writeShdr = struct {
                fn call(b: []u8, base_shoff: usize, idx: usize, shdr: std.elf.Elf64_Shdr) void {
                    const off = base_shoff + idx * @sizeOf(std.elf.Elf64_Shdr);
                    @memcpy(b[off .. off + @sizeOf(std.elf.Elf64_Shdr)], mem.asBytes(&shdr));
                }
            }.call;

            for (extra_sections, 0..) |sec, i| {
                var shdr: std.elf.Elf64_Shdr = std.mem.zeroes(std.elf.Elf64_Shdr);
                shdr.sh_name = mem.nativeTo(u32, sec.name_off, .little);
                shdr.sh_type = mem.nativeTo(u32, sec.sh_type, .little);
                shdr.sh_flags = mem.nativeTo(u64, sec.sh_flags, .little);
                shdr.sh_size = mem.nativeTo(u64, sec.sh_size, .little);
                shdr.sh_addralign = mem.nativeTo(u64, sec.sh_addralign, .little);
                writeShdr(buf, shoff, 1 + i, shdr);
            }

            var symtab_shdr: std.elf.Elf64_Shdr = std.mem.zeroes(std.elf.Elf64_Shdr);
            symtab_shdr.sh_type = mem.nativeTo(u32, std.elf.SHT_SYMTAB, .little);
            symtab_shdr.sh_offset = mem.nativeTo(u64, sym_off, .little);
            symtab_shdr.sh_size = mem.nativeTo(u64, sym_bytes_len, .little);
            symtab_shdr.sh_addralign = mem.nativeTo(u64, 8, .little);
            symtab_shdr.sh_entsize = mem.nativeTo(u64, @sizeOf(std.elf.Elf64_Sym), .little);
            writeShdr(buf, shoff, shnum - 2, symtab_shdr);

            var shstr_shdr: std.elf.Elf64_Shdr = std.mem.zeroes(std.elf.Elf64_Shdr);
            shstr_shdr.sh_type = mem.nativeTo(u32, std.elf.SHT_STRTAB, .little);
            shstr_shdr.sh_offset = mem.nativeTo(u64, shstr_off, .little);
            shstr_shdr.sh_size = mem.nativeTo(u64, shstrtab.len, .little);
            shstr_shdr.sh_addralign = mem.nativeTo(u64, 1, .little);
            writeShdr(buf, shoff, shnum - 1, shstr_shdr);

            return buf;
        }

        fn makeSym(shndx: u16, value: u64, size: u64, st_type: u4) std.elf.Elf64_Sym {
            var sym: std.elf.Elf64_Sym = std.mem.zeroes(std.elf.Elf64_Sym);
            sym.st_info = (@as(u8, std.elf.STB_GLOBAL) << 4) | st_type;
            sym.st_shndx = mem.nativeTo(u16, shndx, .little);
            sym.st_value = mem.nativeTo(u64, value, .little);
            sym.st_size = mem.nativeTo(u64, size, .little);
            return sym;
        }

        fn readShdr(bytes: []const u8, idx: usize) std.elf.Elf64_Shdr {
            const ehdr = mem.bytesAsValue(std.elf.Elf64_Ehdr, bytes[0..@sizeOf(std.elf.Elf64_Ehdr)]);
            const shoff: usize = @intCast(mem.toNative(u64, ehdr.e_shoff, .little));
            const off = shoff + idx * @sizeOf(std.elf.Elf64_Shdr);
            return mem.bytesToValue(std.elf.Elf64_Shdr, bytes[off .. off + @sizeOf(std.elf.Elf64_Shdr)]);
        }

        fn readSym(bytes: []const u8, symtab_shdr: std.elf.Elf64_Shdr, idx: usize) std.elf.Elf64_Sym {
            const sym_off: usize = @intCast(mem.toNative(u64, symtab_shdr.sh_offset, .little));
            const off = sym_off + idx * @sizeOf(std.elf.Elf64_Sym);
            return mem.bytesToValue(std.elf.Elf64_Sym, bytes[off .. off + @sizeOf(std.elf.Elf64_Sym)]);
        }
    };

    const shstrtab = "\x00COMMON\x00.bss\x00.symtab\x00.shstrtab\x00";
    const common_name_off: u32 = 1;
    const bss_name_off: u32 = 8;

    // Case A: COMMON SHT_NOBITS section, no .bss section.
    {
        const obj_bytes = try TestElfBuilder.buildRelocatable(
            gpa,
            shstrtab,
            &.{.{
                .name_off = common_name_off,
                .sh_type = std.elf.SHT_NOBITS,
                .sh_flags = std.elf.SHF_ALLOC | std.elf.SHF_WRITE,
                .sh_size = 16,
                .sh_addralign = 8,
            }},
            &.{
                std.mem.zeroes(std.elf.Elf64_Sym),
                // common_a: size 4, align 4
                TestElfBuilder.makeSym(std.elf.SHN_COMMON, 4, 4, std.elf.STT_NOTYPE),
                // common_b: size 8, align 8
                TestElfBuilder.makeSym(std.elf.SHN_COMMON, 8, 8, std.elf.STT_OBJECT),
            },
        );
        defer gpa.free(obj_bytes);

        try tmp.dir.writeFile(io, .{ .sub_path = "case_a.o", .data = obj_bytes });
        const rel_path = try fs.path.join(gpa, &.{ ".zig-cache", "tmp", &tmp.sub_path, "case_a.o" });
        defer gpa.free(rel_path);

        try defineCommonSymbolsInRelocatable(gpa, io, rel_path);

        const out = try tmp.dir.readFileAlloc(io, "case_a.o", gpa, .unlimited);
        defer gpa.free(out);

        const bss_shdr = TestElfBuilder.readShdr(out, 1);
        const shstr_shdr = TestElfBuilder.readShdr(out, 3);
        const shstr_off: usize = @intCast(mem.toNative(u64, shstr_shdr.sh_offset, .little));
        const sec_name = mem.sliceTo(out[shstr_off + mem.toNative(u32, bss_shdr.sh_name, .little) ..], 0);
        try std.testing.expectEqualStrings(".bss", sec_name);
        try std.testing.expectEqual(@as(u64, 16), mem.toNative(u64, bss_shdr.sh_size, .little));
        try std.testing.expectEqual(@as(u64, 8), mem.toNative(u64, bss_shdr.sh_addralign, .little));

        const symtab_shdr = TestElfBuilder.readShdr(out, 2);
        const common_a = TestElfBuilder.readSym(out, symtab_shdr, 1);
        const common_b = TestElfBuilder.readSym(out, symtab_shdr, 2);
        try std.testing.expectEqual(@as(u16, 1), mem.toNative(u16, common_a.st_shndx, .little));
        try std.testing.expectEqual(@as(u64, 0), mem.toNative(u64, common_a.st_value, .little));
        try std.testing.expectEqual(@as(u4, std.elf.STT_OBJECT), common_a.st_type());
        try std.testing.expectEqual(@as(u16, 1), mem.toNative(u16, common_b.st_shndx, .little));
        try std.testing.expectEqual(@as(u64, 8), mem.toNative(u64, common_b.st_value, .little));
    }

    // Case B: both .bss (size 4) and COMMON exist.
    {
        const obj_bytes = try TestElfBuilder.buildRelocatable(
            gpa,
            shstrtab,
            &.{
                .{
                    .name_off = bss_name_off,
                    .sh_type = std.elf.SHT_NOBITS,
                    .sh_flags = std.elf.SHF_ALLOC | std.elf.SHF_WRITE,
                    .sh_size = 4,
                    .sh_addralign = 4,
                },
                .{
                    .name_off = common_name_off,
                    .sh_type = std.elf.SHT_NOBITS,
                    .sh_flags = std.elf.SHF_ALLOC | std.elf.SHF_WRITE,
                    .sh_size = 16,
                    .sh_addralign = 8,
                },
            },
            &.{
                std.mem.zeroes(std.elf.Elf64_Sym),
                // existing .bss symbol at 0..4
                TestElfBuilder.makeSym(1, 0, 4, std.elf.STT_OBJECT),
                // common_a: size 4, align 4
                TestElfBuilder.makeSym(std.elf.SHN_COMMON, 4, 4, std.elf.STT_OBJECT),
                // common_b: size 8, align 8
                TestElfBuilder.makeSym(std.elf.SHN_COMMON, 8, 8, std.elf.STT_OBJECT),
            },
        );
        defer gpa.free(obj_bytes);

        try tmp.dir.writeFile(io, .{ .sub_path = "case_b.o", .data = obj_bytes });
        const rel_path = try fs.path.join(gpa, &.{ ".zig-cache", "tmp", &tmp.sub_path, "case_b.o" });
        defer gpa.free(rel_path);

        try defineCommonSymbolsInRelocatable(gpa, io, rel_path);

        const out = try tmp.dir.readFileAlloc(io, "case_b.o", gpa, .unlimited);
        defer gpa.free(out);

        const bss_shdr = TestElfBuilder.readShdr(out, 1);
        const common_shdr = TestElfBuilder.readShdr(out, 2);
        try std.testing.expectEqual(@as(u64, 16), mem.toNative(u64, bss_shdr.sh_size, .little));
        try std.testing.expectEqual(@as(u64, 8), mem.toNative(u64, bss_shdr.sh_addralign, .little));
        try std.testing.expectEqual(@as(u64, 0), mem.toNative(u64, common_shdr.sh_size, .little));

        const symtab_shdr = TestElfBuilder.readShdr(out, 3);
        const common_a = TestElfBuilder.readSym(out, symtab_shdr, 2);
        const common_b = TestElfBuilder.readSym(out, symtab_shdr, 3);
        try std.testing.expectEqual(@as(u16, 1), mem.toNative(u16, common_a.st_shndx, .little));
        try std.testing.expectEqual(@as(u64, 4), mem.toNative(u64, common_a.st_value, .little));
        try std.testing.expectEqual(@as(u16, 1), mem.toNative(u16, common_b.st_shndx, .little));
        try std.testing.expectEqual(@as(u64, 8), mem.toNative(u64, common_b.st_value, .little));
    }

    // Case C: linker-script-merged .bss with existing defined symbol at 0..4 and no COMMON section.
    {
        const obj_bytes = try TestElfBuilder.buildRelocatable(
            gpa,
            shstrtab,
            &.{.{
                .name_off = bss_name_off,
                .sh_type = std.elf.SHT_NOBITS,
                .sh_flags = std.elf.SHF_ALLOC | std.elf.SHF_WRITE,
                .sh_size = 16,
                .sh_addralign = 8,
            }},
            &.{
                std.mem.zeroes(std.elf.Elf64_Sym),
                // existing .bss symbol at 0..4
                TestElfBuilder.makeSym(1, 0, 4, std.elf.STT_OBJECT),
                // common_a: size 4, align 4
                TestElfBuilder.makeSym(std.elf.SHN_COMMON, 4, 4, std.elf.STT_OBJECT),
                // common_b: size 8, align 8
                TestElfBuilder.makeSym(std.elf.SHN_COMMON, 8, 8, std.elf.STT_OBJECT),
            },
        );
        defer gpa.free(obj_bytes);

        try tmp.dir.writeFile(io, .{ .sub_path = "case_c.o", .data = obj_bytes });
        const rel_path = try fs.path.join(gpa, &.{ ".zig-cache", "tmp", &tmp.sub_path, "case_c.o" });
        defer gpa.free(rel_path);

        try defineCommonSymbolsInRelocatable(gpa, io, rel_path);

        const out = try tmp.dir.readFileAlloc(io, "case_c.o", gpa, .unlimited);
        defer gpa.free(out);

        const bss_shdr = TestElfBuilder.readShdr(out, 1);
        try std.testing.expectEqual(@as(u64, 16), mem.toNative(u64, bss_shdr.sh_size, .little));
        try std.testing.expectEqual(@as(u64, 8), mem.toNative(u64, bss_shdr.sh_addralign, .little));

        const symtab_shdr = TestElfBuilder.readShdr(out, 2);
        const bss_sym = TestElfBuilder.readSym(out, symtab_shdr, 1);
        const common_a = TestElfBuilder.readSym(out, symtab_shdr, 2);
        const common_b = TestElfBuilder.readSym(out, symtab_shdr, 3);
        try std.testing.expectEqual(@as(u16, 1), mem.toNative(u16, bss_sym.st_shndx, .little));
        try std.testing.expectEqual(@as(u64, 0), mem.toNative(u64, bss_sym.st_value, .little));
        try std.testing.expectEqual(@as(u16, 1), mem.toNative(u16, common_a.st_shndx, .little));
        try std.testing.expectEqual(@as(u64, 4), mem.toNative(u64, common_a.st_value, .little));
        try std.testing.expectEqual(@as(u16, 1), mem.toNative(u16, common_b.st_shndx, .little));
        try std.testing.expectEqual(@as(u64, 8), mem.toNative(u64, common_b.st_value, .little));
    }
}
