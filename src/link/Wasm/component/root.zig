//! WebAssembly Component Model library for Zig's Wasm linker (`wasm32-wasip2`).
//!
//! Vendored from `cataggar/wabt` (`src/component/` and `src/tools/component_new.zig`),
//! licensed under the Apache License, Version 2.0 (see `NOTICE`).
//!
//! Provides an in-process, purely in-memory (`[]const u8` -> `[]u8`) pipeline for:
//! - Encoding WIT worlds (including bundled `wasi-canon/` 0.2.x packages) into
//!   `component-type:<world>` custom section payloads (`encodeWorldFromSource`)
//!   and splicing them onto core `.wasm` modules (`embed`, `embedWorldFromSource`).
//! - Wrapping core `.wasm` modules importing `wasi:*` directly (or via preview1)
//!   into WASI 0.2 components (`buildComponent`).
//! - Splicing preview1->preview2 adapter modules with core `.wasm` modules
//!   (`splice`, `spliceMany`, `wasi_preview1_command_wasm`, `wasi_preview1_reactor_wasm`).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Feature = @import("Feature.zig");
pub const Opcode = @import("Opcode.zig");
pub const leb128 = @import("leb128.zig");
pub const core_types = @import("core_types.zig");
pub const Module = @import("Module.zig").Module;
pub const binary = struct {
    pub const instr = @import("binary/instr.zig");
    pub const reader = @import("binary/reader.zig");
    pub const writer = @import("binary/writer.zig");
};

pub const types = @import("types.zig");
pub const writer = @import("writer.zig");
pub const loader = @import("loader.zig");
pub const compose = @import("compose.zig");
pub const extern_name = @import("extern_name.zig");
pub const rewrite_extern_names = @import("rewrite_extern_names.zig");
pub const resource_intrinsics = @import("resource_intrinsics.zig");
pub const type_walk = @import("type_walk.zig");
pub const build_component = @import("build_component.zig");

pub const wit = struct {
    pub const ast = @import("wit/ast.zig");
    pub const lexer = @import("wit/lexer.zig");
    pub const parser = @import("wit/parser.zig");
    pub const embed = @import("wit/embed.zig");
    pub const lift_types = @import("wit/lift_types.zig");
    pub const metadata_decode = @import("wit/metadata_decode.zig");
    pub const metadata_encode = @import("wit/metadata_encode.zig");
    pub const resolver = @import("wit/resolver.zig");
    pub const wasi_canon = @import("wit/wasi_canon.zig");
};

pub const adapter = struct {
    pub const abi = @import("adapter/abi.zig");
    pub const adapter = @import("adapter/adapter.zig");
    pub const core_imports = @import("adapter/core_imports.zig");
    pub const decode = @import("adapter/decode.zig");
    pub const fixup = @import("adapter/fixup.zig");
    pub const gc = @import("adapter/gc.zig");
    pub const shim = @import("adapter/shim.zig");
    pub const stack_init = @import("adapter/stack_init.zig");
    pub const types_import = @import("adapter/types_import.zig");
    pub const world_gc = @import("adapter/world_gc.zig");

    pub const splice = @This().adapter.splice;
    pub const spliceMany = @This().adapter.spliceMany;
    pub const AdapterSpec = @This().adapter.AdapterSpec;
    pub const SplicedComponent = @This().adapter.SplicedComponent;
    pub const SplicerError = @This().adapter.SplicerError;
    pub const wasi_preview1_command_wasm = build_component.builtin_adapter.wasi_preview1_command_wasm;
    pub const wasi_preview1_reactor_wasm = build_component.builtin_adapter.wasi_preview1_reactor_wasm;
};

// ── Top-level post-link API ────────────────────────────────────────────────

pub const encodeWorldFromSource = wit.metadata_encode.encodeWorldFromSource;
pub const encodeWorld = wit.metadata_encode.encodeWorld;
pub const encodeWorldFromResolver = wit.metadata_encode.encodeWorldFromResolver;
pub const encodeWorldFromResolverWithDiag = wit.metadata_encode.encodeWorldFromResolverWithDiag;
pub const embedCustomSection = wit.embed.embedCustomSection;

pub const buildComponent = build_component.buildComponent;
pub const coreImportsModule = build_component.coreImportsModule;
pub const probeStartExport = build_component.probeStartExport;
pub const pickBuiltinAdapter = build_component.pickBuiltinAdapter;
pub const StartExportProbe = build_component.StartExportProbe;
pub const builtin_adapter = build_component.builtin_adapter;

pub const splice = adapter.adapter.splice;
pub const spliceMany = adapter.adapter.spliceMany;
pub const AdapterSpec = adapter.adapter.AdapterSpec;
pub const SplicedComponent = adapter.adapter.SplicedComponent;
pub const SplicerError = adapter.adapter.SplicerError;

pub const wasi_preview1_command_wasm: []const u8 = build_component.builtin_adapter.wasi_preview1_command_wasm;
pub const wasi_preview1_reactor_wasm: []const u8 = build_component.builtin_adapter.wasi_preview1_reactor_wasm;

pub const wasi_canon = wit.wasi_canon;

/// Canonical bundled WIT sources for standard WASI 0.2 worlds.
pub const bundled_wit = struct {
    pub const cli_command_0_2_6: []const u8 = @embedFile("wit/wasi-canon/0.2.6/cli/command.wit");
    pub const cli_command_0_2_12: []const u8 = @embedFile("wit/wasi-canon/0.2.12/cli/command.wit");
    pub const http_proxy_0_2_6: []const u8 = @embedFile("wit/wasi-canon/0.2.6/http/proxy.wit");
    pub const http_proxy_0_2_12: []const u8 = @embedFile("wit/wasi-canon/0.2.12/http/proxy.wit");
    pub const cli_command: []const u8 = cli_command_0_2_6;
    pub const http_proxy: []const u8 = http_proxy_0_2_6;
};

/// Encode `world_name` from `wit_source` (resolving against bundled `wasi-canon/`
/// packages when needed) and append the `component-type:<world>` custom section
/// onto `core_wasm`. Caller owns the returned slice.
pub fn embedWorldFromSource(
    allocator: Allocator,
    core_wasm: []const u8,
    wit_source: []const u8,
    world_name: []const u8,
) ![]u8 {
    const payload = try encodeWorldFromSource(allocator, wit_source, world_name);
    defer allocator.free(payload);
    const short_name = if (std.mem.lastIndexOfScalar(u8, world_name, '/')) |slash|
        if (std.mem.indexOfScalar(u8, world_name[slash + 1 ..], '@')) |at|
            world_name[slash + 1 ..][0..at]
        else
            world_name[slash + 1 ..]
    else
        world_name;
    const section_name = try std.fmt.allocPrint(allocator, "component-type:{s}", .{short_name});
    defer allocator.free(section_name);
    return embedCustomSection(allocator, core_wasm, section_name, payload);
}

test {
    _ = Feature;
    _ = Opcode;
    _ = leb128;
    _ = core_types;
    _ = Module;
    _ = binary.instr;
    _ = binary.reader;
    _ = binary.writer;
    _ = types;
    _ = writer;
    _ = loader;
    _ = compose;
    _ = extern_name;
    _ = rewrite_extern_names;
    _ = resource_intrinsics;
    _ = type_walk;
    _ = build_component;
    _ = wit.ast;
    _ = wit.lexer;
    _ = wit.parser;
    _ = wit.embed;
    _ = wit.lift_types;
    _ = wit.metadata_decode;
    _ = wit.metadata_encode;
    _ = wit.resolver;
    _ = wit.wasi_canon;
    _ = adapter.abi;
    _ = adapter.adapter;
    _ = adapter.core_imports;
    _ = adapter.decode;
    _ = adapter.fixup;
    _ = adapter.gc;
    _ = adapter.shim;
    _ = adapter.stack_init;
    _ = adapter.types_import;
    _ = adapter.world_gc;
}

test "encodeWorldFromSource: bundled wasi:cli/command and wasi:http/proxy worlds (cataggar/wabt#234)" {
    const testing = std.testing;

    // 1. Encode bundled `wasi:cli/command` (both short and qualified world names).
    const cli_payload = try encodeWorldFromSource(
        testing.allocator,
        bundled_wit.cli_command,
        "command",
    );
    defer testing.allocator.free(cli_payload);
    try testing.expect(cli_payload.len > 8);
    try testing.expectEqualSlices(u8, "\x00asm\x0d\x00\x01\x00", cli_payload[0..8]);

    var cli_arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer cli_arena.deinit();
    const cli_meta = try wit.metadata_decode.decode(cli_arena.allocator(), cli_payload);
    try testing.expect(cli_meta.externs.len >= 2);

    const cli_qual_payload = try encodeWorldFromSource(
        testing.allocator,
        bundled_wit.cli_command,
        "wasi:cli/command",
    );
    defer testing.allocator.free(cli_qual_payload);
    try testing.expectEqualSlices(u8, cli_payload, cli_qual_payload);

    // 2. Encode bundled `wasi:http/proxy` and a custom world importing
    // `wasi:http/outgoing-handler` (cataggar/wabt#234 regression check).
    const http_payload = try encodeWorldFromSource(
        testing.allocator,
        bundled_wit.http_proxy,
        "proxy",
    );
    defer testing.allocator.free(http_payload);
    try testing.expect(http_payload.len > 8);
    try testing.expectEqualSlices(u8, "\x00asm\x0d\x00\x01\x00", http_payload[0..8]);

    var http_arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer http_arena.deinit();
    const http_meta = try wit.metadata_decode.decode(http_arena.allocator(), http_payload);
    try testing.expect(http_meta.externs.len >= 2);

    const http_client_wit =
        \\package test:http-client@0.1.0;
        \\
        \\world client {
        \\  import wasi:http/types@0.2.6;
        \\  import wasi:http/outgoing-handler@0.2.6;
        \\}
    ;
    const client_payload = try encodeWorldFromSource(
        testing.allocator,
        http_client_wit,
        "client",
    );
    defer testing.allocator.free(client_payload);
    try testing.expectEqualSlices(u8, "\x00asm\x0d\x00\x01\x00", client_payload[0..8]);
}

test "buildComponent: round-trip core wasm with embedded WIT metadata into component binary" {
    const testing = std.testing;

    const wit_src =
        \\package docs:adder@0.1.0;
        \\
        \\interface add {
        \\  add: func(x: u32, y: u32) -> u32;
        \\}
        \\
        \\world adder {
        \\  export add;
        \\}
    ;

    // Minimal core module exporting `docs:adder/add@0.1.0#add` ((i32, i32) -> i32).
    const core_bytes = [_]u8{
        0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
        0x01, 0x07, 0x01, 0x60, 0x02, 0x7f, 0x7f, 0x01,
        0x7f, 0x03, 0x02, 0x01, 0x00, 0x07, 25,   0x01,
        23,   'd',  'o',  'c',  's',  ':',  'a',  'd',
        'd',  'e',  'r',  '/',  'a',  'd',  'd',  '@',
        '0',  '.',  '1',  '.',  '0',  '#',  'a',  'd',
        'd',  0x00, 0x00, 0x0a, 0x09, 0x01, 0x07, 0x00,
        0x20, 0x00, 0x20, 0x01, 0x6a, 0x0b,
    };

    const embedded_core = try embedWorldFromSource(
        testing.allocator,
        &core_bytes,
        wit_src,
        "adder",
    );
    defer testing.allocator.free(embedded_core);

    const comp_bytes = try buildComponent(testing.allocator, embedded_core);
    defer testing.allocator.free(comp_bytes);

    try testing.expect(comp_bytes.len > 8);
    try testing.expectEqualSlices(u8, "\x00asm\x0d\x00\x01\x00", comp_bytes[0..8]);

    var loaded_arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer loaded_arena.deinit();
    const loaded = try loader.load(comp_bytes, loaded_arena.allocator());
    try testing.expect(loaded.core_modules.len >= 1);
}

test "adapter.splice: wrap preview1 core module into a component" {
    const testing = std.testing;

    // Minimal preview1 command core module importing
    // `wasi_snapshot_preview1.proc_exit` (i32) -> () and exporting
    // `memory` + `_start` () -> ().
    const main_bytes = [_]u8{
        // preamble
        0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
        // type section: 2 types: 0 = (i32) -> (), 1 = () -> ()
        0x01, 0x08, 0x02, 0x60, 0x01, 0x7f, 0x00, 0x60,
        0x00, 0x00,
        // import section: 1 import: wasi_snapshot_preview1.proc_exit (func type 0)
        0x02, 36,   0x01, 22,   'w',  'a',
        's',  'i',  '_',  's',  'n',  'a',  'p',  's',
        'h',  'o',  't',  '_',  'p',  'r',  'e',  'v',
        'i',  'e',  'w',  '1',  9,    'p',  'r',  'o',
        'c',  '_',  'e',  'x',  'i',  't',  0x00, 0x00,
        // function section: 1 defined func (type 1)
        0x03, 0x02, 0x01, 0x01,
        // memory section: 1 memory (min 1 page)
        0x05, 0x03, 0x01, 0x00,
        0x01,
        // export section: 2 exports: "memory" (mem 0), "_start" (func 1)
        0x07, 19,   0x02, 6,    'm',  'e',  'm',
        'o',  'r',  'y',  0x02, 0x00, 6,    '_',  's',
        't',  'a',  'r',  't',  0x00, 0x01,
        // code section: 1 body: i32.const 0; call 0; end
        0x0a, 0x08,
        0x01, 0x06, 0x00, 0x41, 0x00, 0x10, 0x00, 0x0b,
    };

    const spliced = try splice(
        testing.allocator,
        &main_bytes,
        wasi_preview1_command_wasm,
        "wasi_snapshot_preview1",
    );
    defer testing.allocator.free(spliced);
    try testing.expect(spliced.len > 8);
    try testing.expectEqualSlices(u8, "\x00asm\x0d\x00\x01\x00", spliced[0..8]);
}
