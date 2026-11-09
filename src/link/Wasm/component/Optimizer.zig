//! WebAssembly module optimizer.
//!
//! Performs deterministic intrafunction optimizations (constant folding,
//! control-flow simplification, dead-code elimination) and module-level
//! dead-function removal with function index remapping.

const std = @import("std");
const types = @import("core_types.zig");
const Mod = @import("Module.zig");
const leb128 = @import("leb128.zig");
const instr = @import("binary/instr.zig");
const reader = @import("binary/reader.zig");
const writer = @import("binary/writer.zig");

pub const CustomSectionPolicy = enum {
    reject,
    strip,
    preserve,
};

pub const OptimizeMode = enum {
    small,
    fast,
};

pub const Options = struct {
    custom_sections: CustomSectionPolicy = .reject,
    optimize_mode: OptimizeMode = .small,
};

pub const Error = error{
    ComponentNotSupported,
    CustomSectionsPresent,
    UnsupportedFeature,
    UnsupportedOpcode,
    InvalidInput,
    InvalidOutput,
    OutOfMemory,
};

const component_version: u32 = 0x0001_000d;
const max_pass_rounds: usize = 8;

/// Optimize a binary WebAssembly module and return the optimized binary bytes.
pub fn optimize(allocator: std.mem.Allocator, wasm_bytes: []const u8, options: Options) Error![]u8 {
    if (wasm_bytes.len >= 8 and
        std.mem.eql(u8, wasm_bytes[0..4], &reader.magic) and
        std.mem.readInt(u32, wasm_bytes[4..8], .little) == component_version)
    {
        return error.ComponentNotSupported;
    }

    var module = reader.readModule(allocator, wasm_bytes) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidInput,
    };
    defer module.deinit();

    try optimizeModule(allocator, &module, options);

    const out_bytes = writer.writeModule(allocator, &module) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidOutput,
    };
    errdefer allocator.free(out_bytes);

    var out_mod = reader.readModule(allocator, out_bytes) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidOutput,
    };
    defer out_mod.deinit();

    return out_bytes;
}

/// Optimize a parsed WebAssembly module in place.
pub fn optimizeModule(allocator: std.mem.Allocator, module: *Mod.Module, options: Options) Error!void {
    try preflightModule(module);

    if (module.customs.items.len > 0) {
        switch (options.custom_sections) {
            .reject => return error.CustomSectionsPresent,
            .strip => {
                for (module.customs.items) |custom| {
                    if (custom.owns_data and custom.data.len > 0) {
                        module.allocator.free(custom.data);
                    }
                }
                module.customs.clearRetainingCapacity();
            },
            .preserve => {
                for (module.customs.items) |custom| {
                    if (std.mem.startsWith(u8, custom.name, "reloc.") or
                        std.mem.startsWith(u8, custom.name, ".debug_"))
                    {
                        return error.CustomSectionsPresent;
                    }
                }
            },
        }
    }

    const locals_compacted = allocator.alloc(bool, module.funcs.items.len) catch return error.OutOfMemory;
    defer allocator.free(locals_compacted);
    @memset(locals_compacted, false);

    for (module.num_func_imports..module.funcs.items.len) |i| {
        const func = &module.funcs.items[i];
        if (func.is_import or func.code_bytes.len == 0) continue;
        if (try optimizeFuncBody(allocator, module, func, options.optimize_mode, false)) {
            locals_compacted[i] = true;
        }
    }

    const max_inline_rounds: usize = switch (options.optimize_mode) {
        .small => 2,
        .fast => 4,
    };
    if (module.funcs.items.len > module.num_func_imports) {
        const modified_funcs = allocator.alloc(bool, module.funcs.items.len) catch return error.OutOfMemory;
        defer allocator.free(modified_funcs);

        for (0..max_inline_rounds) |_| {
            @memset(modified_funcs, false);
            const any_inlined = try inlineTrivialFunctions(allocator, module, options.optimize_mode, modified_funcs);
            if (!any_inlined) break;
            for (module.num_func_imports..module.funcs.items.len) |i| {
                if (modified_funcs[i]) {
                    if (try optimizeFuncBody(allocator, module, &module.funcs.items[i], options.optimize_mode, true)) {
                        locals_compacted[i] = true;
                    }
                }
            }
        }
    }

    try removeDeadFunctions(allocator, module, locals_compacted);
}

// ── Preflight validation ─────────────────────────────────────────────────

fn isAllowedValType(vt: types.ValType, type_idx: u32) bool {
    if (type_idx != types.invalid_index) return false;
    return switch (vt) {
        .i32, .i64, .f32, .f64, .v128, .funcref, .externref => true,
        else => false,
    };
}

fn isAllowedValTypeByte(byte: u8) bool {
    return switch (byte) {
        0x7f, // i32
        0x7e, // i64
        0x7d, // f32
        0x7c, // f64
        0x7b, // v128
        0x70, // funcref
        0x6f, // externref
        => true,
        else => false,
    };
}

fn preflightDeclarations(module: *const Mod.Module) Error!void {
    if (module.tags.items.len > 0 or module.num_tag_imports > 0) {
        return error.UnsupportedFeature;
    }
    for (module.imports.items) |imp| {
        if (imp.kind == .tag or imp.tag != null) return error.UnsupportedFeature;
    }
    for (module.exports.items) |exp| {
        if (exp.kind == .tag) return error.UnsupportedFeature;
    }

    if (module.empty_rec_group_positions.items.len > 0) {
        return error.UnsupportedFeature;
    }
    for (module.type_meta.items) |meta| {
        if (meta.kind != .func or meta.is_sub or !meta.is_final or meta.in_rec_group or meta.parent != types.invalid_index) {
            return error.UnsupportedFeature;
        }
    }
    for (module.module_types.items) |entry| {
        switch (entry) {
            .struct_type, .array_type, .cont_type => return error.UnsupportedFeature,
            .func_type => |ft| {
                for (ft.params, 0..) |p, i| {
                    if (!isAllowedValType(p, Mod.FuncSignature.concreteIdxAt(ft.param_type_idxs, i))) {
                        return error.UnsupportedFeature;
                    }
                }
                for (ft.results, 0..) |r, i| {
                    if (!isAllowedValType(r, Mod.FuncSignature.concreteIdxAt(ft.result_type_idxs, i))) {
                        return error.UnsupportedFeature;
                    }
                }
            },
        }
    }

    for (module.funcs.items) |func| {
        for (func.decl.sig.params, 0..) |p, i| {
            const tidx = if (i < func.decl.sig.param_type_idxs.len) func.decl.sig.param_type_idxs[i] else types.invalid_index;
            if (!isAllowedValType(p, tidx)) return error.UnsupportedFeature;
        }
        for (func.decl.sig.results, 0..) |r, i| {
            const tidx = if (i < func.decl.sig.result_type_idxs.len) func.decl.sig.result_type_idxs[i] else types.invalid_index;
            if (!isAllowedValType(r, tidx)) return error.UnsupportedFeature;
        }
        for (func.local_types.items, 0..) |lt, i| {
            const tidx = if (i < func.local_type_idxs.items.len) func.local_type_idxs.items[i] else types.invalid_index;
            if (!isAllowedValType(lt, tidx)) return error.UnsupportedFeature;
        }
    }

    for (module.globals.items) |global| {
        if (!isAllowedValType(global.type.val_type, global.type_idx)) {
            return error.UnsupportedFeature;
        }
    }

    for (module.tables.items) |table| {
        if (!isAllowedValType(table.type.elem_type, table.type_idx)) {
            return error.UnsupportedFeature;
        }
        if (table.type.limits.is_shared or table.type.limits.usesCustomPageSize()) {
            return error.UnsupportedFeature;
        }
    }

    for (module.memories.items) |mem| {
        if (mem.type.limits.usesCustomPageSize()) {
            return error.UnsupportedFeature;
        }
    }

    for (module.imports.items) |imp| {
        switch (imp.kind) {
            .func => if (imp.func) |f| {
                for (f.sig.params, 0..) |p, i| {
                    const tidx = if (i < f.sig.param_type_idxs.len) f.sig.param_type_idxs[i] else types.invalid_index;
                    if (!isAllowedValType(p, tidx)) return error.UnsupportedFeature;
                }
                for (f.sig.results, 0..) |r, i| {
                    const tidx = if (i < f.sig.result_type_idxs.len) f.sig.result_type_idxs[i] else types.invalid_index;
                    if (!isAllowedValType(r, tidx)) return error.UnsupportedFeature;
                }
            },
            .table => if (imp.table) |t| {
                if (!isAllowedValType(t.elem_type, imp.table_type_idx)) return error.UnsupportedFeature;
                if (t.limits.is_shared or t.limits.usesCustomPageSize()) return error.UnsupportedFeature;
            },
            .memory => if (imp.memory) |m| {
                if (m.limits.usesCustomPageSize()) return error.UnsupportedFeature;
            },
            .global => if (imp.global) |g| {
                if (!isAllowedValType(g.val_type, imp.global_type_idx)) return error.UnsupportedFeature;
            },
            .tag => return error.UnsupportedFeature,
        }
    }

    for (module.elem_segments.items) |seg| {
        if (seg.elem_type_idx != types.invalid_index) return error.UnsupportedFeature;
        if (seg.uses_elem_exprs) {
            if (!isAllowedValType(seg.elem_type, seg.elem_type_idx)) return error.UnsupportedFeature;
        } else {
            if (seg.elem_type != .funcref and seg.elem_type != .ref_func and seg.elem_type != .externref) {
                return error.UnsupportedFeature;
            }
        }
    }
}

fn preflightModule(module: *const Mod.Module) Error!void {
    try preflightDeclarations(module);

    for (module.funcs.items[module.num_func_imports..]) |func| {
        if (func.is_import or func.code_bytes.len == 0) continue;
        try preflightInstrBytes(module, func.code_bytes);
    }

    for (module.globals.items) |global| {
        if (!global.is_import and global.init_expr_bytes.len > 0) {
            try preflightInstrBytes(module, global.init_expr_bytes);
        }
    }

    for (module.tables.items) |table| {
        if (!table.is_import and table.hasInitExpr() and table.init_expr_bytes.len > 0) {
            try preflightInstrBytes(module, table.init_expr_bytes);
        }
    }

    for (module.elem_segments.items) |seg| {
        if (seg.kind == .active and seg.offset_expr_bytes.len > 0) {
            try preflightInstrBytes(module, seg.offset_expr_bytes);
        }
        if (seg.elem_expr_bytes.len > 0) {
            try preflightInstrBytes(module, seg.elem_expr_bytes);
        }
    }

    for (module.data_segments.items) |seg| {
        if (seg.kind == .active and seg.offset_expr_bytes.len > 0) {
            try preflightInstrBytes(module, seg.offset_expr_bytes);
        }
    }
}

fn preflightInstrBytes(module: *const Mod.Module, bytes: []const u8) Error!void {
    var pos: usize = 0;
    while (pos < bytes.len) {
        const byte = bytes[pos];
        pos += 1;

        switch (byte) {
            0xfb => return error.UnsupportedOpcode,
            0xfd, 0xfe => {
                pos -= 1;
                const decoded = instr.decode(bytes, &pos) catch return error.InvalidInput;
                instr.skipImmediates(decoded.shape, bytes, &pos) catch return error.InvalidInput;
            },
            0xfc => {
                const sub = readU32(bytes, &pos) catch return error.InvalidInput;
                switch (sub) {
                    0x00...0x07 => {},
                    0x08, 0x0a, 0x0c, 0x0e => {
                        _ = readU32(bytes, &pos) catch return error.InvalidInput;
                        _ = readU32(bytes, &pos) catch return error.InvalidInput;
                    },
                    0x09, 0x0b, 0x0d, 0x0f, 0x10, 0x11 => {
                        _ = readU32(bytes, &pos) catch return error.InvalidInput;
                    },
                    else => return error.UnsupportedOpcode,
                }
            },
            0x00, 0x01, 0x05, 0x0b, 0x0f, 0x1a, 0x1b, 0xd1 => {},
            0x02, 0x03, 0x04 => {
                try preflightBlockType(module, bytes, &pos);
            },
            0x0c, 0x0d, 0x10, 0x12, 0x20...0x26, 0x3f, 0x40, 0xd2 => {
                _ = readU32(bytes, &pos) catch return error.InvalidInput;
            },
            0x0e => {
                const count = readU32(bytes, &pos) catch return error.InvalidInput;
                for (0..@as(usize, count) + 1) |_| {
                    _ = readU32(bytes, &pos) catch return error.InvalidInput;
                }
            },
            0x11, 0x13 => {
                _ = readU32(bytes, &pos) catch return error.InvalidInput;
                _ = readU32(bytes, &pos) catch return error.InvalidInput;
            },
            0x1c => {
                const count = readU32(bytes, &pos) catch return error.InvalidInput;
                if (count != 1) return error.InvalidInput;
                if (pos >= bytes.len) return error.InvalidInput;
                const vt_byte = bytes[pos];
                pos += 1;
                if (!isAllowedValTypeByte(vt_byte)) {
                    return error.UnsupportedFeature;
                }
            },
            0x28...0x3e => {
                const align_flags = readU32(bytes, &pos) catch return error.InvalidInput;
                if ((align_flags & 0x40) != 0) {
                    _ = readU32(bytes, &pos) catch return error.InvalidInput;
                }
                _ = readU64(bytes, &pos) catch return error.InvalidInput;
            },
            0x41 => {
                _ = readS32(bytes, &pos) catch return error.InvalidInput;
            },
            0x42 => {
                _ = readS64(bytes, &pos) catch return error.InvalidInput;
            },
            0x43 => {
                if (pos + 4 > bytes.len) return error.InvalidInput;
                pos += 4;
            },
            0x44 => {
                if (pos + 8 > bytes.len) return error.InvalidInput;
                pos += 8;
            },
            0x45...0xc4 => {},
            0xd0 => {
                const ht = readS33(bytes, &pos) catch return error.InvalidInput;
                if (ht != -0x10 and ht != -0x11) {
                    return error.UnsupportedFeature;
                }
            },
            0x06...0x0a, 0x14, 0x15, 0x18, 0x19, 0x1f, 0xd3...0xd6, 0xe0...0xe6 => {
                return error.UnsupportedOpcode;
            },
            else => return error.InvalidInput,
        }
    }
}

fn preflightBlockType(module: *const Mod.Module, bytes: []const u8, pos: *usize) Error!void {
    if (pos.* >= bytes.len) return error.InvalidInput;
    const byte = bytes[pos.*];
    if (byte == 0x40 or isAllowedValTypeByte(byte)) {
        pos.* += 1;
        return;
    }
    if (byte == reader.ref_null_prefix or byte == reader.ref_prefix) {
        return error.UnsupportedFeature;
    }
    if (byte >= 0x40 and byte < 0x80) {
        return error.UnsupportedFeature;
    }
    const s33 = readS33(bytes, pos) catch return error.InvalidInput;
    if (s33 < 0 or s33 > std.math.maxInt(u32)) return error.InvalidInput;
    const type_idx: u32 = @intCast(s33);
    if (type_idx >= module.module_types.items.len) return error.InvalidInput;
    switch (module.module_types.items[type_idx]) {
        .func_type => {},
        else => return error.UnsupportedFeature,
    }
}

// ── LEB128 helpers ───────────────────────────────────────────────────────

fn readU32(bytes: []const u8, pos: *usize) leb128.ReadError!u32 {
    const r = try leb128.readU32Leb128(bytes[pos.*..]);
    pos.* += r.bytes_read;
    return r.value;
}

fn readU64(bytes: []const u8, pos: *usize) leb128.ReadError!u64 {
    const r = try leb128.readU64Leb128(bytes[pos.*..]);
    pos.* += r.bytes_read;
    return r.value;
}

fn readS32(bytes: []const u8, pos: *usize) leb128.ReadError!i32 {
    const r = try leb128.readS32Leb128(bytes[pos.*..]);
    pos.* += r.bytes_read;
    return r.value;
}

fn readS33(bytes: []const u8, pos: *usize) leb128.ReadError!i64 {
    const r = try leb128.readS33Leb128(bytes[pos.*..]);
    pos.* += r.bytes_read;
    return r.value;
}

fn readS64(bytes: []const u8, pos: *usize) leb128.ReadError!i64 {
    const r = try leb128.readS64Leb128(bytes[pos.*..]);
    pos.* += r.bytes_read;
    return r.value;
}

fn appendU32Leb(allocator: std.mem.Allocator, buf: *std.ArrayListUnmanaged(u8), v: u32) std.mem.Allocator.Error!void {
    var tmp: [leb128.max_u32_bytes]u8 = undefined;
    const n = leb128.writeU32Leb128(&tmp, v);
    try buf.appendSlice(allocator, tmp[0..n]);
}

fn appendS32Leb(allocator: std.mem.Allocator, buf: *std.ArrayListUnmanaged(u8), v: i32) std.mem.Allocator.Error!void {
    var tmp: [leb128.max_s32_bytes]u8 = undefined;
    const n = leb128.writeS32Leb128(&tmp, v);
    try buf.appendSlice(allocator, tmp[0..n]);
}

fn appendS64Leb(allocator: std.mem.Allocator, buf: *std.ArrayListUnmanaged(u8), v: i64) std.mem.Allocator.Error!void {
    var tmp: [leb128.max_s64_bytes]u8 = undefined;
    const n = leb128.writeS64Leb128(&tmp, v);
    try buf.appendSlice(allocator, tmp[0..n]);
}

// ── Intrafunction AST & Passes ───────────────────────────────────────────

const BlockTypeBytes = struct {
    bytes: [leb128.max_s33_bytes]u8 = undefined,
    len: u8 = 0,

    fn slice(self: *const BlockTypeBytes) []const u8 {
        return self.bytes[0..self.len];
    }

    fn isEmpty(self: BlockTypeBytes) bool {
        return self.len == 1 and self.bytes[0] == 0x40;
    }
};

const InstrList = std.ArrayListUnmanaged(Instr);

const BlockInstr = struct {
    block_type: BlockTypeBytes,
    body: InstrList = .empty,
};

const IfInstr = struct {
    block_type: BlockTypeBytes,
    then_body: InstrList = .empty,
    has_else: bool = false,
    else_body: InstrList = .empty,
};

const Instr = union(enum) {
    unreachable_,
    nop,
    block: BlockInstr,
    loop: BlockInstr,
    if_: IfInstr,
    br: u32,
    br_if: u32,
    br_table: []u32,
    return_,
    call: u32,
    return_call: u32,
    return_call_indirect: []const u8,
    local_get: u32,
    local_set: u32,
    local_tee: u32,
    i32_const: i32,
    i64_const: i64,
    ref_func: u32,
    numeric_op: u8,
    raw: []const u8,

    fn isUnconditionalTransfer(self: Instr) bool {
        return switch (self) {
            .unreachable_,
            .br,
            .br_table,
            .return_,
            .return_call,
            .return_call_indirect,
            => true,
            else => false,
        };
    }
};

const EndKind = enum {
    end,
    else_,
};

fn readBlockTypeBytes(bytes: []const u8, pos: *usize) Error!BlockTypeBytes {
    if (pos.* >= bytes.len) return error.InvalidInput;
    const start = pos.*;
    const b = bytes[pos.*];
    if (b < 0x80) {
        pos.* += 1;
    } else {
        _ = readS33(bytes, pos) catch return error.InvalidInput;
    }
    const len = pos.* - start;
    if (len > leb128.max_s33_bytes) return error.InvalidInput;
    var bt = BlockTypeBytes{ .len = @intCast(len) };
    @memcpy(bt.bytes[0..len], bytes[start..pos.*]);
    return bt;
}

fn parseInstrBlock(
    arena: std.mem.Allocator,
    bytes: []const u8,
    pos: *usize,
    allow_else: bool,
    out_list: *InstrList,
) Error!EndKind {
    while (pos.* < bytes.len) {
        const instr_start = pos.*;
        const b = bytes[pos.*];
        pos.* += 1;

        switch (b) {
            0x0b => return .end,
            0x05 => {
                if (!allow_else) return error.InvalidInput;
                return .else_;
            },
            0x00 => out_list.append(arena, .unreachable_) catch return error.OutOfMemory,
            0x01 => out_list.append(arena, .nop) catch return error.OutOfMemory,
            0x02 => {
                const bt = try readBlockTypeBytes(bytes, pos);
                var body: InstrList = .empty;
                const end_kind = try parseInstrBlock(arena, bytes, pos, false, &body);
                if (end_kind != .end) return error.InvalidInput;
                out_list.append(arena, .{ .block = .{ .block_type = bt, .body = body } }) catch return error.OutOfMemory;
            },
            0x03 => {
                const bt = try readBlockTypeBytes(bytes, pos);
                var body: InstrList = .empty;
                const end_kind = try parseInstrBlock(arena, bytes, pos, false, &body);
                if (end_kind != .end) return error.InvalidInput;
                out_list.append(arena, .{ .loop = .{ .block_type = bt, .body = body } }) catch return error.OutOfMemory;
            },
            0x04 => {
                const bt = try readBlockTypeBytes(bytes, pos);
                var then_body: InstrList = .empty;
                var else_body: InstrList = .empty;
                const end_kind = try parseInstrBlock(arena, bytes, pos, true, &then_body);
                var has_else = false;
                if (end_kind == .else_) {
                    has_else = true;
                    const else_end = try parseInstrBlock(arena, bytes, pos, false, &else_body);
                    if (else_end != .end) return error.InvalidInput;
                }
                out_list.append(arena, .{
                    .if_ = .{
                        .block_type = bt,
                        .then_body = then_body,
                        .has_else = has_else,
                        .else_body = else_body,
                    },
                }) catch return error.OutOfMemory;
            },
            0x0c => {
                const label = readU32(bytes, pos) catch return error.InvalidInput;
                out_list.append(arena, .{ .br = label }) catch return error.OutOfMemory;
            },
            0x0d => {
                const label = readU32(bytes, pos) catch return error.InvalidInput;
                out_list.append(arena, .{ .br_if = label }) catch return error.OutOfMemory;
            },
            0x0e => {
                const count = readU32(bytes, pos) catch return error.InvalidInput;
                const total = @as(usize, count) + 1;
                const targets = arena.alloc(u32, total) catch return error.OutOfMemory;
                for (0..total) |i| {
                    targets[i] = readU32(bytes, pos) catch return error.InvalidInput;
                }
                out_list.append(arena, .{ .br_table = targets }) catch return error.OutOfMemory;
            },
            0x0f => out_list.append(arena, .return_) catch return error.OutOfMemory,
            0x10 => {
                const idx = readU32(bytes, pos) catch return error.InvalidInput;
                out_list.append(arena, .{ .call = idx }) catch return error.OutOfMemory;
            },
            0x12 => {
                const idx = readU32(bytes, pos) catch return error.InvalidInput;
                out_list.append(arena, .{ .return_call = idx }) catch return error.OutOfMemory;
            },
            0x13 => {
                _ = readU32(bytes, pos) catch return error.InvalidInput;
                _ = readU32(bytes, pos) catch return error.InvalidInput;
                out_list.append(arena, .{ .return_call_indirect = bytes[instr_start..pos.*] }) catch return error.OutOfMemory;
            },
            0x20 => {
                const idx = readU32(bytes, pos) catch return error.InvalidInput;
                out_list.append(arena, .{ .local_get = idx }) catch return error.OutOfMemory;
            },
            0x21 => {
                const idx = readU32(bytes, pos) catch return error.InvalidInput;
                out_list.append(arena, .{ .local_set = idx }) catch return error.OutOfMemory;
            },
            0x22 => {
                const idx = readU32(bytes, pos) catch return error.InvalidInput;
                out_list.append(arena, .{ .local_tee = idx }) catch return error.OutOfMemory;
            },
            0x41 => {
                const val = readS32(bytes, pos) catch return error.InvalidInput;
                out_list.append(arena, .{ .i32_const = val }) catch return error.OutOfMemory;
            },
            0x42 => {
                const val = readS64(bytes, pos) catch return error.InvalidInput;
                out_list.append(arena, .{ .i64_const = val }) catch return error.OutOfMemory;
            },
            0x45...0xc4 => {
                out_list.append(arena, .{ .numeric_op = b }) catch return error.OutOfMemory;
            },
            0xd2 => {
                const idx = readU32(bytes, pos) catch return error.InvalidInput;
                out_list.append(arena, .{ .ref_func = idx }) catch return error.OutOfMemory;
            },
            else => {
                var probe = instr_start;
                const decoded = instr.decode(bytes, &probe) catch return error.InvalidInput;
                instr.skipImmediates(decoded.shape, bytes, &probe) catch return error.InvalidInput;
                pos.* = probe;
                out_list.append(arena, .{ .raw = bytes[instr_start..pos.*] }) catch return error.OutOfMemory;
            },
        }
    }
    return error.InvalidInput;
}

fn encodeInstrList(allocator: std.mem.Allocator, list: []const Instr, buf: *std.ArrayListUnmanaged(u8)) Error!void {
    for (list) |inst| {
        switch (inst) {
            .unreachable_ => buf.append(allocator, 0x00) catch return error.OutOfMemory,
            .nop => buf.append(allocator, 0x01) catch return error.OutOfMemory,
            .block => |b| {
                buf.append(allocator, 0x02) catch return error.OutOfMemory;
                buf.appendSlice(allocator, b.block_type.slice()) catch return error.OutOfMemory;
                try encodeInstrList(allocator, b.body.items, buf);
                buf.append(allocator, 0x0b) catch return error.OutOfMemory;
            },
            .loop => |l| {
                buf.append(allocator, 0x03) catch return error.OutOfMemory;
                buf.appendSlice(allocator, l.block_type.slice()) catch return error.OutOfMemory;
                try encodeInstrList(allocator, l.body.items, buf);
                buf.append(allocator, 0x0b) catch return error.OutOfMemory;
            },
            .if_ => |i| {
                buf.append(allocator, 0x04) catch return error.OutOfMemory;
                buf.appendSlice(allocator, i.block_type.slice()) catch return error.OutOfMemory;
                try encodeInstrList(allocator, i.then_body.items, buf);
                if (i.has_else) {
                    buf.append(allocator, 0x05) catch return error.OutOfMemory;
                    try encodeInstrList(allocator, i.else_body.items, buf);
                }
                buf.append(allocator, 0x0b) catch return error.OutOfMemory;
            },
            .br => |label| {
                buf.append(allocator, 0x0c) catch return error.OutOfMemory;
                try appendU32Leb(allocator, buf, label);
            },
            .br_if => |label| {
                buf.append(allocator, 0x0d) catch return error.OutOfMemory;
                try appendU32Leb(allocator, buf, label);
            },
            .br_table => |targets| {
                buf.append(allocator, 0x0e) catch return error.OutOfMemory;
                const count: u32 = @intCast(targets.len - 1);
                try appendU32Leb(allocator, buf, count);
                for (targets) |t| {
                    try appendU32Leb(allocator, buf, t);
                }
            },
            .return_ => buf.append(allocator, 0x0f) catch return error.OutOfMemory,
            .call => |idx| {
                buf.append(allocator, 0x10) catch return error.OutOfMemory;
                try appendU32Leb(allocator, buf, idx);
            },
            .return_call => |idx| {
                buf.append(allocator, 0x12) catch return error.OutOfMemory;
                try appendU32Leb(allocator, buf, idx);
            },
            .return_call_indirect => |raw| {
                buf.appendSlice(allocator, raw) catch return error.OutOfMemory;
            },
            .local_get => |idx| {
                buf.append(allocator, 0x20) catch return error.OutOfMemory;
                try appendU32Leb(allocator, buf, idx);
            },
            .local_set => |idx| {
                buf.append(allocator, 0x21) catch return error.OutOfMemory;
                try appendU32Leb(allocator, buf, idx);
            },
            .local_tee => |idx| {
                buf.append(allocator, 0x22) catch return error.OutOfMemory;
                try appendU32Leb(allocator, buf, idx);
            },
            .i32_const => |val| {
                buf.append(allocator, 0x41) catch return error.OutOfMemory;
                try appendS32Leb(allocator, buf, val);
            },
            .i64_const => |val| {
                buf.append(allocator, 0x42) catch return error.OutOfMemory;
                try appendS64Leb(allocator, buf, val);
            },
            .ref_func => |idx| {
                buf.append(allocator, 0xd2) catch return error.OutOfMemory;
                try appendU32Leb(allocator, buf, idx);
            },
            .numeric_op => |op| {
                buf.append(allocator, op) catch return error.OutOfMemory;
            },
            .raw => |raw| {
                buf.appendSlice(allocator, raw) catch return error.OutOfMemory;
            },
        }
    }
}

fn optimizeFuncBody(
    allocator: std.mem.Allocator,
    module: *const Mod.Module,
    func: *Mod.Func,
    optimize_mode: OptimizeMode,
    is_post_inline: bool,
) Error!bool {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var pos: usize = 0;
    var root_list: InstrList = .empty;
    const end_kind = try parseInstrBlock(arena, func.code_bytes, &pos, false, &root_list);
    if (end_kind != .end or pos != func.code_bytes.len) return error.InvalidInput;

    var had_offset_fold = false;
    for (0..max_pass_rounds) |_| {
        var changed = false;
        if (eliminateLeafStackCopy(&root_list)) changed = true;
        if (try forwardDeadStackCopyLoads(arena, &root_list)) changed = true;
        if (try forwardAndEliminateMemoryOps(arena, &root_list)) changed = true;
        if (try simplifyLocals(arena, &root_list, optimize_mode)) changed = true;
        if (try foldConstants(arena, &root_list, optimize_mode)) changed = true;
        if (try foldDerivedPtrOffsets(arena, module, func, &root_list, is_post_inline, &had_offset_fold)) {
            changed = true;
            _ = try forwardDeadStackCopyLoads(arena, &root_list);
        }
        if (try scalarizeShadowStackSlots(arena, module, func, &root_list, is_post_inline, had_offset_fold)) changed = true;
        if (try hoistLoopInvariantCode(arena, module, func, &root_list, optimize_mode)) changed = true;
        if (try simplifyControlFlow(arena, &root_list)) changed = true;
        if (eliminateDeadCode(&root_list)) changed = true;
        if (!changed) {
            if (try coalesceConstantStores(arena, module, &root_list, is_post_inline)) continue;
            break;
        }
    }

    const compacted = compactLocals(arena, module, func, &root_list) catch return error.OutOfMemory;

    var out_buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out_buf.deinit(allocator);
    try encodeInstrList(allocator, root_list.items, &out_buf);
    out_buf.append(allocator, 0x0b) catch return error.OutOfMemory;

    const new_bytes = out_buf.toOwnedSlice(allocator) catch return error.OutOfMemory;
    if (func.owns_code_bytes and func.code_bytes.len > 0) {
        allocator.free(func.code_bytes);
    }
    func.code_bytes = new_bytes;
    func.owns_code_bytes = true;
    return compacted;
}

// ── Pass L: Local Simplification and Compaction ──────────────────────────

const MemAccessInfo = struct {
    opcode: u8,
    simd_sub: u32 = 0,
    align_val: u32,
    mem_idx: u32,
    offset: u64,
    size: u32,
};

fn decodeLoadAccess(inst: Instr) ?MemAccessInfo {
    if (inst != .raw) return null;
    const r = inst.raw;
    if (r.len == 0) return null;
    var pos: usize = 1;
    var simd_sub: u32 = 0;
    const size: u32 = switch (r[0]) {
        0x28, 0x2a, 0x34, 0x35 => 4,
        0x29, 0x2b => 8,
        0x2c, 0x2d, 0x30, 0x31 => 1,
        0x2e, 0x2f, 0x32, 0x33 => 2,
        0xfd => blk: {
            simd_sub = readU32(r, &pos) catch return null;
            break :blk switch (simd_sub) {
                0x00 => 16,
                0x01...0x06, 0x0a, 0x5d => 8,
                0x07 => 1,
                0x08 => 2,
                0x09, 0x5c => 4,
                else => return null,
            };
        },
        else => return null,
    };
    const align_raw = readU32(r, &pos) catch return null;
    const mem_idx = if ((align_raw & 0x40) != 0) (readU32(r, &pos) catch return null) else 0;
    const off_r = leb128.readU64Leb128(r[pos..]) catch return null;
    pos += off_r.bytes_read;
    if (pos != r.len) return null;
    return .{
        .opcode = r[0],
        .simd_sub = simd_sub,
        .align_val = align_raw & ~@as(u32, 0x40),
        .mem_idx = mem_idx,
        .offset = off_r.value,
        .size = size,
    };
}

fn decodeStoreAccess(inst: Instr) ?MemAccessInfo {
    if (inst != .raw) return null;
    const r = inst.raw;
    if (r.len == 0) return null;
    var pos: usize = 1;
    var simd_sub: u32 = 0;
    const size: u32 = switch (r[0]) {
        0x36, 0x38, 0x3e => 4,
        0x37, 0x39 => 8,
        0x3a, 0x3c => 1,
        0x3b, 0x3d => 2,
        0xfd => blk: {
            simd_sub = readU32(r, &pos) catch return null;
            break :blk switch (simd_sub) {
                0x0b => 16,
                0x58 => 1,
                0x59 => 2,
                0x5a => 4,
                0x5b => 8,
                else => return null,
            };
        },
        else => return null,
    };
    const align_raw = readU32(r, &pos) catch return null;
    const mem_idx = if ((align_raw & 0x40) != 0) (readU32(r, &pos) catch return null) else 0;
    const off_r = leb128.readU64Leb128(r[pos..]) catch return null;
    pos += off_r.bytes_read;
    if (r[0] == 0xfd and simd_sub >= 0x58 and simd_sub <= 0x5b) {
        if (pos >= r.len) return null;
        pos += 1;
    }
    if (pos != r.len) return null;
    return .{
        .opcode = r[0],
        .simd_sub = simd_sub,
        .align_val = align_raw & ~@as(u32, 0x40),
        .mem_idx = mem_idx,
        .offset = off_r.value,
        .size = size,
    };
}

fn encodeLoadInstr(
    arena: std.mem.Allocator,
    access: MemAccessInfo,
    new_align: u32,
    new_offset: u64,
) Error!Instr {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    buf.append(arena, access.opcode) catch return error.OutOfMemory;
    if (access.opcode == 0xfd) {
        appendU32Leb(arena, &buf, access.simd_sub) catch return error.OutOfMemory;
    }
    appendU32Leb(arena, &buf, new_align) catch return error.OutOfMemory;
    var off_tmp: [leb128.max_u64_bytes]u8 = undefined;
    const off_n = leb128.writeU64Leb128(&off_tmp, new_offset);
    buf.appendSlice(arena, off_tmp[0..off_n]) catch return error.OutOfMemory;
    return .{ .raw = buf.items };
}

fn encodeStoreInstr(
    arena: std.mem.Allocator,
    access: MemAccessInfo,
    new_align: u32,
    new_offset: u64,
) Error!Instr {
    return encodeLoadInstr(arena, access, new_align, new_offset);
}

fn canEliminateLeafStackCopyInSlice(
    slice: []const Instr,
    tmp_local: u32,
    src_param: u32,
    copy_size: u64,
    allow_return: bool,
) bool {
    for (slice, 0..) |inst, idx| {
        switch (inst) {
            .block => |b| {
                if (!canEliminateLeafStackCopyInSlice(b.body.items, tmp_local, src_param, copy_size, allow_return)) return false;
            },
            .loop => |l| {
                if (!canEliminateLeafStackCopyInSlice(l.body.items, tmp_local, src_param, copy_size, allow_return)) return false;
            },
            .if_ => |i| {
                if (!canEliminateLeafStackCopyInSlice(i.then_body.items, tmp_local, src_param, copy_size, allow_return)) return false;
                if (i.has_else and !canEliminateLeafStackCopyInSlice(i.else_body.items, tmp_local, src_param, copy_size, allow_return)) return false;
            },
            .return_ => if (!allow_return) return false,
            .unreachable_, .call, .return_call, .return_call_indirect => return false,
            .local_set, .local_tee => |lidx| if (lidx == tmp_local or lidx == src_param) return false,
            .local_get => |lidx| if (lidx == tmp_local) {
                if (idx + 1 < slice.len) {
                    if (decodeLoadAccess(slice[idx + 1])) |access| {
                        if (access.mem_idx == 0 and access.offset + access.size <= copy_size) continue;
                    }
                }
                if (idx + 3 < slice.len and
                    slice[idx + 1] == .i32_const and slice[idx + 1].i32_const >= 0 and
                    slice[idx + 2] == .numeric_op and slice[idx + 2].numeric_op == 0x6a)
                {
                    if (decodeLoadAccess(slice[idx + 3])) |access| {
                        const add_off: u64 = @intCast(slice[idx + 1].i32_const);
                        if (access.mem_idx == 0 and add_off + access.offset + access.size <= copy_size) continue;
                    }
                }
                return false;
            },
            .raw => |r| {
                if (r.len == 0) return false;
                switch (r[0]) {
                    0x10...0x15, 0x24, 0x26, 0x36...0x3e, 0x40, 0xfb, 0xfe => return false,
                    0xfc => {
                        var p: usize = 1;
                        const sub = readU32(r, &p) catch return false;
                        if (sub > 0x07) return false;
                    },
                    0xfd => {
                        var p: usize = 1;
                        const sub = readU32(r, &p) catch return false;
                        if (sub == 0x0b or (sub >= 0x58 and sub <= 0x5b)) return false;
                    },
                    else => {},
                }
            },
            else => {},
        }
    }
    return true;
}

fn rewriteLocalGetInSlice(slice: []Instr, from_local: u32, to_local: u32) void {
    for (slice) |*inst| {
        switch (inst.*) {
            .local_get => |*idx| if (idx.* == from_local) {
                idx.* = to_local;
            },
            .block => |*b| rewriteLocalGetInSlice(b.body.items, from_local, to_local),
            .loop => |*l| rewriteLocalGetInSlice(l.body.items, from_local, to_local),
            .if_ => |*i| {
                rewriteLocalGetInSlice(i.then_body.items, from_local, to_local);
                if (i.has_else) rewriteLocalGetInSlice(i.else_body.items, from_local, to_local);
            },
            else => {},
        }
    }
}

fn eliminateLeafStackCopy(root_list: *InstrList) bool {
    const items = root_list.items;
    if (items.len < 8) return false;

    // Match stage2_wasm leaf by-value aggregate copy prologue:
    //   0: global.get _       (.raw { 0x23, 0x00 })
    //   1: i32.const stack_sz (stack_sz > 0)
    //   2: i32.sub            (.numeric_op 0x6b)
    //   3: local.tee tmp      (.local_tee tmp_local)
    //   [optional 4..6: global.set 0; local.get tmp]
    //   local.get src         (.local_get src_param, src_param != tmp_local)
    //   i32.const copy_sz     (0 < copy_sz <= stack_sz)
    //   memory.copy 0 0       (.raw { 0xfc, 0x0a, 0x00, 0x00 })
    if (items[0] != .raw or !std.mem.eql(u8, items[0].raw, &.{ 0x23, 0x00 })) return false;
    if (items[1] != .i32_const or items[1].i32_const <= 0) return false;
    const stack_size = items[1].i32_const;
    if (items[2] != .numeric_op or items[2].numeric_op != 0x6b) return false;
    if (items[3] != .local_tee) return false;
    const tmp_local = items[3].local_tee;

    var prologue_len: usize = 7;
    var has_global_set_in_prologue = false;
    if (items.len >= 10 and
        items[4] == .raw and std.mem.eql(u8, items[4].raw, &.{ 0x24, 0x00 }) and
        items[5] == .local_get and items[5].local_get == tmp_local)
    {
        prologue_len = 9;
        has_global_set_in_prologue = true;
    }

    if (items.len <= prologue_len) return false;
    if (items[prologue_len - 3] != .local_get) return false;
    const src_param = items[prologue_len - 3].local_get;
    if (src_param == tmp_local) return false;
    if (items[prologue_len - 2] != .i32_const) return false;
    const copy_size = items[prologue_len - 2].i32_const;
    if (copy_size <= 0 or copy_size > stack_size) return false;
    if (items[prologue_len - 1] != .raw or !std.mem.eql(u8, items[prologue_len - 1].raw, &.{ 0xfc, 0x0a, 0x00, 0x00 })) return false;

    const has_trailing_return = items[items.len - 1] == .return_;
    const pre_ret_end = if (has_trailing_return) items.len - 1 else items.len;
    const has_epilogue = pre_ret_end >= prologue_len + 4 and
        items[pre_ret_end - 4] == .local_get and items[pre_ret_end - 4].local_get == tmp_local and
        items[pre_ret_end - 3] == .i32_const and items[pre_ret_end - 3].i32_const == stack_size and
        items[pre_ret_end - 2] == .numeric_op and items[pre_ret_end - 2].numeric_op == 0x6a and
        items[pre_ret_end - 1] == .raw and std.mem.eql(u8, items[pre_ret_end - 1].raw, &.{ 0x24, 0x00 });

    if (has_global_set_in_prologue and !has_epilogue) return false;

    const body_end = if (has_epilogue) pre_ret_end - 4 else items.len;
    if (body_end < prologue_len) return false;

    if (!canEliminateLeafStackCopyInSlice(
        items[prologue_len..body_end],
        tmp_local,
        src_param,
        @intCast(copy_size),
        !has_epilogue,
    )) return false;

    rewriteLocalGetInSlice(root_list.items[prologue_len..body_end], tmp_local, src_param);

    const body_len = body_end - prologue_len;
    std.mem.copyForwards(Instr, root_list.items[0..body_len], root_list.items[prologue_len..body_end]);
    var new_len = body_len;
    if (has_epilogue and has_trailing_return) {
        root_list.items[new_len] = .return_;
        new_len += 1;
    }
    root_list.shrinkRetainingCapacity(new_len);
    return true;
}

const StackCopyCand = struct {
    start_idx: usize,
    end_idx: usize,
    dst_offset: u64,
    src_local: u32,
    src_offset: u64,
    copy_len: u64,
};

fn matchStackFrameCopyAt(slice: []const Instr, idx: usize, fp: u32) ?StackCopyCand {
    if (idx >= slice.len or slice[idx] != .local_get or slice[idx].local_get != fp) return null;

    // 1. `memory.copy` form: `local.get fp; [i32.const dst_off; i32.add;] local.get src; [i32.const src_off; i32.add;] i32.const len; memory.copy 0, 0`
    blk: {
        var pos = idx + 1;
        var dst_offset: u64 = 0;
        if (pos + 1 < slice.len and
            slice[pos] == .i32_const and slice[pos].i32_const >= 0 and
            slice[pos + 1] == .numeric_op and slice[pos + 1].numeric_op == 0x6a)
        {
            dst_offset = @intCast(slice[pos].i32_const);
            pos += 2;
        }
        if (pos >= slice.len or slice[pos] != .local_get) break :blk;
        const src_local = slice[pos].local_get;
        pos += 1;
        var src_offset: u64 = 0;
        if (pos + 1 < slice.len and
            slice[pos] == .i32_const and slice[pos].i32_const >= 0 and
            slice[pos + 1] == .numeric_op and slice[pos + 1].numeric_op == 0x6a)
        {
            src_offset = @intCast(slice[pos].i32_const);
            pos += 2;
        }
        if (pos + 1 >= slice.len) break :blk;
        if (slice[pos] != .i32_const or slice[pos].i32_const <= 0) break :blk;
        const copy_len: u64 = @intCast(slice[pos].i32_const);
        if (slice[pos + 1] != .raw or !std.mem.eql(u8, slice[pos + 1].raw, &.{ 0xfc, 0x0a, 0x00, 0x00 })) break :blk;
        return .{
            .start_idx = idx,
            .end_idx = pos + 2,
            .dst_offset = dst_offset,
            .src_local = src_local,
            .src_offset = src_offset,
            .copy_len = copy_len,
        };
    }

    // 2. Unrolled `CodeGen.memcpy` chunk copy (`1 <= K <= 12` chunks):
    // `K` triples of `(local.get fp; local.get src_local; <load src_offset + off_c>)`
    // followed by `K` reverse-order stores `<store dst_offset + off_{K - 1 - s}>`.
    if (idx + 4 <= slice.len and slice[idx + 1] == .local_get) {
        const u_src_local = slice[idx + 1].local_get;
        // Pattern 2a: sequential chunk copy (`local.get fp; local.get src; <load>; <store>` repeated)
        {
            var seq_chunks: usize = 0;
            var seq_base_src: u64 = 0;
            var seq_base_dst: u64 = 0;
            var seq_len: u64 = 0;
            var prev_size: u32 = 16;
            while (seq_chunks < 12 and idx + 4 * (seq_chunks + 1) <= slice.len) {
                const base_i = idx + 4 * seq_chunks;
                if (slice[base_i] != .local_get or slice[base_i].local_get != fp) break;
                if (slice[base_i + 1] != .local_get or slice[base_i + 1].local_get != u_src_local) break;
                const load_acc = decodeLoadAccess(slice[base_i + 2]) orelse break;
                const st_acc = decodeStoreAccess(slice[base_i + 3]) orelse break;
                if (load_acc.mem_idx != 0 or st_acc.mem_idx != 0) break;
                if (load_acc.size > prev_size) break;
                const match_op = switch (load_acc.opcode) {
                    0x28 => st_acc.opcode == 0x36,
                    0x29 => st_acc.opcode == 0x37,
                    0x2d => st_acc.opcode == 0x3a,
                    0x2f => st_acc.opcode == 0x3b,
                    0xfd => load_acc.simd_sub == 0x00 and st_acc.opcode == 0xfd and st_acc.simd_sub == 0x0b,
                    else => false,
                };
                if (!match_op) break;
                if (seq_chunks == 0) {
                    seq_base_src = load_acc.offset;
                    seq_base_dst = st_acc.offset;
                } else if (load_acc.offset != seq_base_src + seq_len or st_acc.offset != seq_base_dst + seq_len) {
                    break;
                }
                seq_len += load_acc.size;
                prev_size = load_acc.size;
                seq_chunks += 1;
            }
            if (seq_chunks >= 2 or seq_len >= 16) {
                return .{
                    .start_idx = idx,
                    .end_idx = idx + 4 * seq_chunks,
                    .dst_offset = seq_base_dst,
                    .src_local = u_src_local,
                    .src_offset = seq_base_src,
                    .copy_len = seq_len,
                };
            }
        }
        // Pattern 2b: stacked chunk copy (all loads then all stores in reverse order)
        const ChunkInfo = struct {
            opcode: u8,
            simd_sub: u32,
            rel_off: u64,
            size: u32,
        };
        var chunks: [12]ChunkInfo = undefined;
        var max_chunks: usize = 0;
        var base_src_off: u64 = 0;
        var running_len: u64 = 0;
        while (max_chunks < chunks.len and idx + 3 * max_chunks + 2 < slice.len) {
            const base_i = idx + 3 * max_chunks;
            if (slice[base_i] != .local_get or slice[base_i].local_get != fp) break;
            if (slice[base_i + 1] != .local_get or slice[base_i + 1].local_get != u_src_local) break;
            const load_acc = decodeLoadAccess(slice[base_i + 2]) orelse break;
            if (load_acc.mem_idx != 0) break;
            const valid_load = switch (load_acc.opcode) {
                0x28, 0x29, 0x2d, 0x2f => true,
                0xfd => load_acc.simd_sub == 0x00,
                else => false,
            };
            if (!valid_load) break;
            if (max_chunks == 0) {
                base_src_off = load_acc.offset;
            } else if (load_acc.offset != base_src_off + running_len) {
                break;
            }
            chunks[max_chunks] = .{
                .opcode = load_acc.opcode,
                .simd_sub = load_acc.simd_sub,
                .rel_off = running_len,
                .size = load_acc.size,
            };
            running_len += load_acc.size;
            max_chunks += 1;
        }
        var chunk_count = max_chunks;
        while (chunk_count >= 1) : (chunk_count -= 1) {
            const total_len = chunks[chunk_count - 1].rel_off + chunks[chunk_count - 1].size;
            if (chunk_count < 2 and total_len < 16) continue;
            if (idx + 4 * chunk_count > slice.len) continue;
            const store_start = idx + 3 * chunk_count;
            const last_store = decodeStoreAccess(slice[store_start + chunk_count - 1]) orelse continue;
            const base_dst_off = last_store.offset;
            var stores_ok = true;
            for (0..chunk_count) |s| {
                const chunk = chunks[chunk_count - 1 - s];
                const st_acc = decodeStoreAccess(slice[store_start + s]) orelse {
                    stores_ok = false;
                    break;
                };
                if (st_acc.mem_idx != 0 or st_acc.offset != base_dst_off + chunk.rel_off) {
                    stores_ok = false;
                    break;
                }
                const match_op = switch (chunk.opcode) {
                    0x28 => st_acc.opcode == 0x36,
                    0x29 => st_acc.opcode == 0x37,
                    0x2d => st_acc.opcode == 0x3a,
                    0x2f => st_acc.opcode == 0x3b,
                    0xfd => st_acc.opcode == 0xfd and st_acc.simd_sub == 0x0b,
                    else => false,
                };
                if (!match_op) {
                    stores_ok = false;
                    break;
                }
            }
            if (stores_ok) {
                return .{
                    .start_idx = idx,
                    .end_idx = idx + 4 * chunk_count,
                    .dst_offset = base_dst_off,
                    .src_local = u_src_local,
                    .src_offset = base_src_off,
                    .copy_len = total_len,
                };
            }
        }
    }

    return null;
}

fn matchFpSrcCopyAt(slice: []const Instr, idx: usize, fp: u32) ?struct { end_idx: usize, src_offset: u64, copy_len: u64 } {
    var pos = idx;
    if (pos >= slice.len or slice[pos] != .local_get or slice[pos].local_get != fp) return null;
    pos += 1;
    var src_offset: u64 = 0;
    if (pos + 1 < slice.len and
        slice[pos] == .i32_const and slice[pos].i32_const >= 0 and
        slice[pos + 1] == .numeric_op and slice[pos + 1].numeric_op == 0x6a)
    {
        src_offset = @intCast(slice[pos].i32_const);
        pos += 2;
    }
    if (pos + 1 >= slice.len) return null;
    if (slice[pos] != .i32_const or slice[pos].i32_const <= 0) return null;
    const copy_len: u64 = @intCast(slice[pos].i32_const);
    if (slice[pos + 1] != .raw or !std.mem.eql(u8, slice[pos + 1].raw, &.{ 0xfc, 0x0a, 0x00, 0x00 })) return null;
    return .{
        .end_idx = pos + 2,
        .src_offset = src_offset,
        .copy_len = copy_len,
    };
}

fn matchFpFillAt(slice: []const Instr, idx: usize, fp: u32) ?struct { end_idx: usize, dst_offset: u64, fill_len: u64 } {
    var pos = idx;
    if (pos >= slice.len or slice[pos] != .local_get or slice[pos].local_get != fp) return null;
    pos += 1;
    var dst_offset: u64 = 0;
    if (pos + 1 < slice.len and
        slice[pos] == .i32_const and slice[pos].i32_const >= 0 and
        slice[pos + 1] == .numeric_op and slice[pos + 1].numeric_op == 0x6a)
    {
        dst_offset = @intCast(slice[pos].i32_const);
        pos += 2;
    }
    if (pos >= slice.len or !isPureZeroPopInstr(slice[pos])) return null;
    if (slice[pos] == .local_get and slice[pos].local_get == fp) return null;
    pos += 1;
    if (pos + 1 >= slice.len) return null;
    if (slice[pos] != .i32_const or slice[pos].i32_const <= 0) return null;
    const fill_len: u64 = @intCast(slice[pos].i32_const);
    if (slice[pos + 1] != .raw or !std.mem.eql(u8, slice[pos + 1].raw, &.{ 0xfc, 0x0b, 0x00 })) return null;
    return .{
        .end_idx = pos + 2,
        .dst_offset = dst_offset,
        .fill_len = fill_len,
    };
}

fn rangesOverlap(a_start: u64, a_len: u64, b_start: u64, b_len: u64) bool {
    return a_start < b_start + b_len and b_start < a_start + a_len;
}

fn verifyDisjointFpUsesInSlice(
    slice: []const Instr,
    fp: u32,
    sp_save: ?u32,
    slot_start: u64,
    slot_len: u64,
    target_slice_ptr: ?[*]const Instr,
    skip_start: ?usize,
    skip_end: ?usize,
    window_start: ?usize,
    window_end: ?usize,
) bool {
    const is_target = target_slice_ptr != null and slice.ptr == target_slice_ptr.?;
    var i: usize = 0;
    while (i < slice.len) {
        if (is_target and skip_start != null and i >= skip_start.? and i < skip_end.?) {
            i = skip_end.?;
            continue;
        }
        const in_window = is_target and window_start != null and i >= window_start.? and i < window_end.?;
        const inst = slice[i];
        switch (inst) {
            .block => |b| {
                if (!verifyDisjointFpUsesInSlice(b.body.items, fp, sp_save, slot_start, slot_len, target_slice_ptr, skip_start, skip_end, window_start, window_end)) return false;
            },
            .loop => |l| {
                if (!verifyDisjointFpUsesInSlice(l.body.items, fp, sp_save, slot_start, slot_len, target_slice_ptr, skip_start, skip_end, window_start, window_end)) return false;
            },
            .if_ => |if_inst| {
                if (!verifyDisjointFpUsesInSlice(if_inst.then_body.items, fp, sp_save, slot_start, slot_len, target_slice_ptr, skip_start, skip_end, window_start, window_end)) return false;
                if (if_inst.has_else and !verifyDisjointFpUsesInSlice(if_inst.else_body.items, fp, sp_save, slot_start, slot_len, target_slice_ptr, skip_start, skip_end, window_start, window_end)) return false;
            },
            .local_set, .local_tee => |lidx| {
                if (lidx == fp) return false;
                if (sp_save != null and lidx == sp_save.?) return false;
            },
            .local_get => |lidx| {
                if (sp_save != null and lidx == sp_save.?) {
                    if (i + 1 < slice.len and slice[i + 1] == .raw and std.mem.eql(u8, slice[i + 1].raw, &.{ 0x24, 0x00 })) {
                        i += 2;
                        continue;
                    }
                    return false;
                }
                if (lidx == fp) {
                    // 1. Direct load: `local.get fp; <load>`
                    if (i + 1 < slice.len) {
                        if (decodeLoadAccess(slice[i + 1])) |access| {
                            if (access.mem_idx != 0) return false;
                            if (in_window and access.offset >= slot_start and access.offset + access.size <= slot_start + slot_len) {
                                i += 2;
                                continue;
                            }
                            if (!rangesOverlap(access.offset, access.size, slot_start, slot_len)) {
                                i += 2;
                                continue;
                            }
                            return false;
                        }
                    }
                    // 2. Offset load: `local.get fp; i32.const C; i32.add; <load>`
                    if (i + 3 < slice.len and
                        slice[i + 1] == .i32_const and slice[i + 1].i32_const >= 0 and
                        slice[i + 2] == .numeric_op and slice[i + 2].numeric_op == 0x6a)
                    {
                        if (decodeLoadAccess(slice[i + 3])) |access| {
                            if (access.mem_idx != 0) return false;
                            const total_off = @as(u64, @intCast(slice[i + 1].i32_const)) + access.offset;
                            if (in_window and total_off >= slot_start and total_off + access.size <= slot_start + slot_len) {
                                i += 4;
                                continue;
                            }
                            if (!rangesOverlap(total_off, access.size, slot_start, slot_len)) {
                                i += 4;
                                continue;
                            }
                            return false;
                        }
                    }
                    // 2b. Indexed load in window: `local.get fp; [i32.const C; i32.add;] <index_expr>; i32.add; <load>`
                    if (in_window) {
                        const has_const_base = i + 3 < slice.len and
                            slice[i + 1] == .i32_const and slice[i + 1].i32_const >= 0 and
                            slice[i + 2] == .numeric_op and slice[i + 2].numeric_op == 0x6a;
                        const base_off: u64 = if (has_const_base) @intCast(slice[i + 1].i32_const) else 0;
                        const expr_start: usize = if (has_const_base) i + 3 else i + 1;
                        if (findSingleValueIndexLoadIdx(slice, expr_start, fp)) |add_idx| {
                            if (add_idx + 1 < window_end.? and
                                (sp_save == null or !sliceUsesLocalOrEarlyExit(slice[expr_start..add_idx], sp_save.?, null, false)))
                            {
                                const access = decodeLoadAccess(slice[add_idx + 1]).?;
                                const total_base_off = base_off + access.offset;
                                if (total_base_off >= slot_start and
                                    total_base_off + access.size <= slot_start + slot_len and
                                    base_off >= slot_start)
                                {
                                    i = add_idx + 2;
                                    continue;
                                }
                            }
                        }
                    }
                    // 3. Direct store: `local.get fp; <val_expr>; <store>`
                    if (findSingleValueStoreIdx(slice, i + 1, fp)) |store_idx| {
                        const access = decodeStoreAccess(slice[store_idx]).?;
                        if (access.mem_idx == 0 and
                            !rangesOverlap(access.offset, access.size, slot_start, slot_len) and
                            verifyDisjointFpUsesInSlice(slice[i + 1 .. store_idx], fp, sp_save, slot_start, slot_len, null, null, null, null, null))
                        {
                            i = store_idx + 1;
                            continue;
                        }
                    }
                    // 4. Offset store: `local.get fp; i32.const C; i32.add; <val_expr>; <store>`
                    if (i + 3 < slice.len and
                        slice[i + 1] == .i32_const and slice[i + 1].i32_const >= 0 and
                        slice[i + 2] == .numeric_op and slice[i + 2].numeric_op == 0x6a)
                    {
                        if (findSingleValueStoreIdx(slice, i + 3, fp)) |store_idx| {
                            const access = decodeStoreAccess(slice[store_idx]).?;
                            const total_off = @as(u64, @intCast(slice[i + 1].i32_const)) + access.offset;
                            if (access.mem_idx == 0 and
                                !rangesOverlap(total_off, access.size, slot_start, slot_len) and
                                verifyDisjointFpUsesInSlice(slice[i + 3 .. store_idx], fp, sp_save, slot_start, slot_len, null, null, null, null, null))
                            {
                                i = store_idx + 1;
                                continue;
                            }
                        }
                    }
                    // 5. Disjoint `memory.copy` / unrolled copy into `fp + D2`
                    if (matchStackFrameCopyAt(slice, i, fp)) |other_copy| {
                        if (!rangesOverlap(other_copy.dst_offset, other_copy.copy_len, slot_start, slot_len) and
                            (other_copy.src_local != fp or !rangesOverlap(other_copy.src_offset, other_copy.copy_len, slot_start, slot_len)) and
                            (sp_save == null or other_copy.src_local != sp_save.?))
                        {
                            i = other_copy.end_idx;
                            continue;
                        }
                    }
                    if (matchFpSrcCopyAt(slice, i, fp)) |src_copy| {
                        if (!rangesOverlap(src_copy.src_offset, src_copy.copy_len, slot_start, slot_len)) {
                            i = src_copy.end_idx;
                            continue;
                        }
                    }
                    if (matchFpFillAt(slice, i, fp)) |fill_cand| {
                        if (!rangesOverlap(fill_cand.dst_offset, fill_cand.fill_len, slot_start, slot_len)) {
                            i = fill_cand.end_idx;
                            continue;
                        }
                    }
                    // 6. Disjoint address computation `local.get fp; i32.const C; i32.add` where `C >= slot_start + slot_len`
                    if (i + 2 < slice.len and
                        slice[i + 1] == .i32_const and slice[i + 1].i32_const >= 0 and
                        slice[i + 2] == .numeric_op and slice[i + 2].numeric_op == 0x6a and
                        @as(u64, @intCast(slice[i + 1].i32_const)) >= slot_start + slot_len)
                    {
                        const has_backward_arith = (i + 3 < slice.len and slice[i + 3] == .numeric_op and slice[i + 3].numeric_op == 0x6b) or
                            (i + 4 < slice.len and slice[i + 3] == .i32_const and slice[i + 3].i32_const < 0 and
                                slice[i + 4] == .numeric_op and slice[i + 4].numeric_op == 0x6a);
                        if (!has_backward_arith) {
                            i += 3;
                            continue;
                        }
                    }
                    return false;
                }
            },
            else => {},
        }
        i += 1;
    }
    return true;
}

fn sliceUsesLocalOrEarlyExit(slice: []const Instr, fp: u32, sp_save: ?u32, forbid_return_or_trap: bool) bool {
    for (slice) |inst| {
        switch (inst) {
            .local_get, .local_set, .local_tee => |lidx| {
                if (lidx == fp) return true;
                if (sp_save != null and lidx == sp_save.?) return true;
            },
            .return_, .unreachable_ => if (forbid_return_or_trap) return true,
            .block => |b| if (sliceUsesLocalOrEarlyExit(b.body.items, fp, sp_save, forbid_return_or_trap)) return true,
            .loop => |l| if (sliceUsesLocalOrEarlyExit(l.body.items, fp, sp_save, forbid_return_or_trap)) return true,
            .if_ => |if_inst| {
                if (sliceUsesLocalOrEarlyExit(if_inst.then_body.items, fp, sp_save, forbid_return_or_trap)) return true;
                if (if_inst.has_else and sliceUsesLocalOrEarlyExit(if_inst.else_body.items, fp, sp_save, forbid_return_or_trap)) return true;
            },
            else => {},
        }
    }
    return false;
}

const ShadowStackFrame = struct {
    fp: u32,
    sp_save: ?u32,
    frame_size: u64,
    body_start: usize,
    body_end: usize,
    has_epilogue: bool,
    has_trailing_return: bool,
};

fn detectShadowStackFrame(items: []const Instr) ?ShadowStackFrame {
    if (items.len < 6) return null;

    const has_trailing_return = items[items.len - 1] == .return_;
    const pre_ret_end = if (has_trailing_return) items.len - 1 else items.len;

    if (items[0] != .raw or !std.mem.eql(u8, items[0].raw, &.{ 0x23, 0x00 })) return null;

    var fp: u32 = 0;
    var sp_save: ?u32 = null;
    var frame_size: u64 = 0;
    var body_start: usize = 0;
    var body_end: usize = 0;
    var has_epilogue = false;

    if (pre_ret_end >= 9 and
        items[1] == .i32_const and items[1].i32_const > 0 and
        items[2] == .numeric_op and items[2].numeric_op == 0x6b and
        (items[3] == .local_tee or items[3] == .local_set) and
        items[4] == .raw and std.mem.eql(u8, items[4].raw, &.{ 0x24, 0x00 }))
    {
        const cand_fp = if (items[3] == .local_tee) items[3].local_tee else items[3].local_set;
        const cand_sz = items[1].i32_const;
        if (items[pre_ret_end - 4] == .local_get and items[pre_ret_end - 4].local_get == cand_fp and
            items[pre_ret_end - 3] == .i32_const and items[pre_ret_end - 3].i32_const == cand_sz and
            items[pre_ret_end - 2] == .numeric_op and items[pre_ret_end - 2].numeric_op == 0x6a and
            items[pre_ret_end - 1] == .raw and std.mem.eql(u8, items[pre_ret_end - 1].raw, &.{ 0x24, 0x00 }))
        {
            fp = cand_fp;
            frame_size = @intCast(cand_sz);
            body_start = 5;
            body_end = pre_ret_end - 4;
            has_epilogue = true;
        }
    }

    if (body_start == 0 and pre_ret_end >= 8 and
        items[1] == .local_tee and
        items[2] == .i32_const and items[2].i32_const > 0 and
        items[3] == .numeric_op and items[3].numeric_op == 0x6b and
        (items[4] == .local_tee or items[4] == .local_set) and
        items[5] == .raw and std.mem.eql(u8, items[5].raw, &.{ 0x24, 0x00 }))
    {
        const cand_sp = items[1].local_tee;
        const cand_fp = if (items[4] == .local_tee) items[4].local_tee else items[4].local_set;
        if (cand_sp != cand_fp and
            items[pre_ret_end - 2] == .local_get and items[pre_ret_end - 2].local_get == cand_sp and
            items[pre_ret_end - 1] == .raw and std.mem.eql(u8, items[pre_ret_end - 1].raw, &.{ 0x24, 0x00 }))
        {
            fp = cand_fp;
            sp_save = cand_sp;
            frame_size = @intCast(items[2].i32_const);
            body_start = 6;
            body_end = pre_ret_end - 2;
            has_epilogue = true;
        }
    }

    if (body_start == 0 and pre_ret_end >= 5 and
        items[1] == .i32_const and items[1].i32_const > 0 and
        items[2] == .numeric_op and items[2].numeric_op == 0x6b and
        items[3] == .local_set)
    {
        fp = items[3].local_set;
        frame_size = @intCast(items[1].i32_const);
        body_start = 4;
        body_end = pre_ret_end;
        has_epilogue = false;
    }

    if (body_start == 0 or body_end < body_start) return null;
    return .{
        .fp = fp,
        .sp_save = sp_save,
        .frame_size = frame_size,
        .body_start = body_start,
        .body_end = body_end,
        .has_epilogue = has_epilogue,
        .has_trailing_return = has_trailing_return,
    };
}

fn tryForwardDeadStackCopyInSlice(
    arena: std.mem.Allocator,
    root_body: []const Instr,
    cur_list: *InstrList,
    fp: u32,
    sp_save: ?u32,
    frame_size: u64,
) Error!bool {
    const body_slice = cur_list.items;
    var matched_cand: ?StackCopyCand = null;
    var matched_window_end: usize = 0;

    var scan_idx: usize = 0;
    while (scan_idx < body_slice.len) : (scan_idx += 1) {
        const cand = matchStackFrameCopyAt(body_slice, scan_idx, fp) orelse continue;
        if (cand.dst_offset + cand.copy_len > frame_size) continue;
        if (sp_save != null and cand.src_local == sp_save.?) continue;
        if (cand.src_local == fp and rangesOverlap(cand.src_offset, cand.copy_len, cand.dst_offset, cand.copy_len)) continue;

        // Find the straight-line window after `cand.end_idx` before any memory write, call, branch, or modification of `src_local`/`fp`.
        var win_end = cand.end_idx;
        while (win_end < body_slice.len) {
            if (matchStackFrameCopyAt(body_slice, win_end, fp)) |other_copy| {
                if (!rangesOverlap(other_copy.dst_offset, other_copy.copy_len, cand.dst_offset, cand.copy_len) and
                    (cand.src_local == fp and !rangesOverlap(other_copy.dst_offset, other_copy.copy_len, cand.src_offset, cand.copy_len)) and
                    other_copy.src_local != cand.src_local)
                {
                    win_end = other_copy.end_idx;
                    continue;
                }
                break;
            }
            const winst = body_slice[win_end];
            const stop = switch (winst) {
                .block, .loop, .if_, .br, .br_if, .br_table, .return_, .unreachable_, .call, .return_call, .return_call_indirect => true,
                .local_set, .local_tee => |lidx| lidx == cand.src_local or lidx == fp or (sp_save != null and lidx == sp_save.?),
                .raw => |r| blk: {
                    if (r.len == 0) break :blk true;
                    break :blk switch (r[0]) {
                        0x10...0x15, 0x24, 0x26, 0x36...0x3e, 0x40, 0xfb, 0xfe => true,
                        0xfc => sub_blk: {
                            var p: usize = 1;
                            const sub = readU32(r, &p) catch break :sub_blk true;
                            break :sub_blk sub > 0x07;
                        },
                        0xfd => sub_blk: {
                            var p: usize = 1;
                            const sub = readU32(r, &p) catch break :sub_blk true;
                            break :sub_blk sub == 0x0b or (sub >= 0x58 and sub <= 0x5b);
                        },
                        else => false,
                    };
                },
                else => false,
            };
            if (stop) break;
            win_end += 1;
        }

        var has_load_in_win = false;
        {
            var wi = cand.end_idx;
            while (wi < win_end) : (wi += 1) {
                if (body_slice[wi] == .local_get and body_slice[wi].local_get == fp) {
                    if (wi + 1 < win_end) {
                        if (decodeLoadAccess(body_slice[wi + 1])) |access| {
                            if (access.mem_idx == 0 and access.offset >= cand.dst_offset and access.offset + access.size <= cand.dst_offset + cand.copy_len) {
                                has_load_in_win = true;
                                break;
                            }
                        }
                    }
                    if (wi + 3 < win_end and
                        body_slice[wi + 1] == .i32_const and body_slice[wi + 1].i32_const >= 0 and
                        body_slice[wi + 2] == .numeric_op and body_slice[wi + 2].numeric_op == 0x6a)
                    {
                        if (decodeLoadAccess(body_slice[wi + 3])) |access| {
                            const total_off = @as(u64, @intCast(body_slice[wi + 1].i32_const)) + access.offset;
                            if (access.mem_idx == 0 and total_off >= cand.dst_offset and total_off + access.size <= cand.dst_offset + cand.copy_len) {
                                has_load_in_win = true;
                                break;
                            }
                        }
                    }
                    const has_const_base = wi + 3 < win_end and
                        body_slice[wi + 1] == .i32_const and body_slice[wi + 1].i32_const >= 0 and
                        body_slice[wi + 2] == .numeric_op and body_slice[wi + 2].numeric_op == 0x6a;
                    const base_off: u64 = if (has_const_base) @intCast(body_slice[wi + 1].i32_const) else 0;
                    const expr_start: usize = if (has_const_base) wi + 3 else wi + 1;
                    if (findSingleValueIndexLoadIdx(body_slice, expr_start, fp)) |add_idx| {
                        if (add_idx + 1 < win_end) {
                            const access = decodeLoadAccess(body_slice[add_idx + 1]).?;
                            const total_base_off = base_off + access.offset;
                            if (total_base_off >= cand.dst_offset and
                                total_base_off + access.size <= cand.dst_offset + cand.copy_len and
                                base_off >= cand.dst_offset)
                            {
                                has_load_in_win = true;
                                break;
                            }
                        }
                    }
                }
            }
        }
        if (!has_load_in_win) continue;

        if (verifyDisjointFpUsesInSlice(
            root_body,
            fp,
            sp_save,
            cand.dst_offset,
            cand.copy_len,
            body_slice.ptr,
            cand.start_idx,
            cand.end_idx,
            cand.end_idx,
            win_end,
        )) {
            matched_cand = cand;
            matched_window_end = win_end;
            break;
        }
    }

    if (matched_cand) |cand| {
        var new_list: InstrList = .empty;
        new_list.ensureTotalCapacity(arena, body_slice.len) catch return error.OutOfMemory;

        var bi: usize = 0;
        while (bi < body_slice.len) {
            if (bi == cand.start_idx) {
                bi = cand.end_idx;
                continue;
            }
            if (bi >= cand.end_idx and bi < matched_window_end and
                body_slice[bi] == .local_get and body_slice[bi].local_get == fp)
            {
                if (bi + 1 < matched_window_end) {
                    if (decodeLoadAccess(body_slice[bi + 1])) |access| {
                        if (access.mem_idx == 0 and access.offset >= cand.dst_offset and access.offset + access.size <= cand.dst_offset + cand.copy_len) {
                            const rel_off = access.offset - cand.dst_offset;
                            const new_off = cand.src_offset + rel_off;
                            const shift_align: u32 = if (access.align_val == 0) 0 else @min(access.align_val, @ctz(cand.dst_offset | cand.src_offset | (@as(u64, 1) << @intCast(access.align_val))));
                            const new_load = try encodeLoadInstr(arena, access, shift_align, new_off);
                            new_list.append(arena, .{ .local_get = cand.src_local }) catch return error.OutOfMemory;
                            new_list.append(arena, new_load) catch return error.OutOfMemory;
                            bi += 2;
                            continue;
                        }
                    }
                }
                if (bi + 3 < matched_window_end and
                    body_slice[bi + 1] == .i32_const and body_slice[bi + 1].i32_const >= 0 and
                    body_slice[bi + 2] == .numeric_op and body_slice[bi + 2].numeric_op == 0x6a)
                {
                    if (decodeLoadAccess(body_slice[bi + 3])) |access| {
                        const total_off = @as(u64, @intCast(body_slice[bi + 1].i32_const)) + access.offset;
                        if (access.mem_idx == 0 and total_off >= cand.dst_offset and total_off + access.size <= cand.dst_offset + cand.copy_len) {
                            const rel_off = total_off - cand.dst_offset;
                            const new_off = cand.src_offset + rel_off;
                            const shift_align: u32 = if (access.align_val == 0) 0 else @min(access.align_val, @ctz(cand.dst_offset | cand.src_offset | (@as(u64, 1) << @intCast(access.align_val))));
                            const new_load = try encodeLoadInstr(arena, access, shift_align, new_off);
                            new_list.append(arena, .{ .local_get = cand.src_local }) catch return error.OutOfMemory;
                            new_list.append(arena, new_load) catch return error.OutOfMemory;
                            bi += 4;
                            continue;
                        }
                    }
                }
                const has_const_base = bi + 3 < matched_window_end and
                    body_slice[bi + 1] == .i32_const and body_slice[bi + 1].i32_const >= 0 and
                    body_slice[bi + 2] == .numeric_op and body_slice[bi + 2].numeric_op == 0x6a;
                const base_off: u64 = if (has_const_base) @intCast(body_slice[bi + 1].i32_const) else 0;
                const expr_start: usize = if (has_const_base) bi + 3 else bi + 1;
                if (findSingleValueIndexLoadIdx(body_slice, expr_start, fp)) |add_idx| {
                    if (add_idx + 1 < matched_window_end) {
                        const access = decodeLoadAccess(body_slice[add_idx + 1]).?;
                        const total_base_off = base_off + access.offset;
                        if (total_base_off >= cand.dst_offset and
                            total_base_off + access.size <= cand.dst_offset + cand.copy_len and
                            base_off >= cand.dst_offset)
                        {
                            const new_ptr_off = cand.src_offset + (base_off - cand.dst_offset);
                            if (new_ptr_off <= std.math.maxInt(i32)) {
                                const shift_align: u32 = if (access.align_val == 0) 0 else @min(access.align_val, @ctz(cand.dst_offset | cand.src_offset | (@as(u64, 1) << @intCast(access.align_val))));
                                const new_load = try encodeLoadInstr(arena, access, shift_align, access.offset);
                                new_list.append(arena, .{ .local_get = cand.src_local }) catch return error.OutOfMemory;
                                if (new_ptr_off > 0) {
                                    new_list.append(arena, .{ .i32_const = @intCast(new_ptr_off) }) catch return error.OutOfMemory;
                                    new_list.append(arena, .{ .numeric_op = 0x6a }) catch return error.OutOfMemory;
                                }
                                new_list.appendSlice(arena, body_slice[expr_start .. add_idx + 1]) catch return error.OutOfMemory;
                                new_list.append(arena, new_load) catch return error.OutOfMemory;
                                bi = add_idx + 2;
                                continue;
                            }
                        }
                    }
                }
            }
            new_list.append(arena, body_slice[bi]) catch return error.OutOfMemory;
            bi += 1;
        }
        cur_list.* = new_list;
        return true;
    }

    for (cur_list.items) |*inst| {
        switch (inst.*) {
            .block => |*b| {
                if (try tryForwardDeadStackCopyInSlice(arena, root_body, &b.body, fp, sp_save, frame_size)) return true;
            },
            .loop => |*l| {
                if (try tryForwardDeadStackCopyInSlice(arena, root_body, &l.body, fp, sp_save, frame_size)) return true;
            },
            .if_ => |*if_inst| {
                if (try tryForwardDeadStackCopyInSlice(arena, root_body, &if_inst.then_body, fp, sp_save, frame_size)) return true;
                if (if_inst.has_else and try tryForwardDeadStackCopyInSlice(arena, root_body, &if_inst.else_body, fp, sp_save, frame_size)) return true;
            },
            else => {},
        }
    }
    return false;
}

fn forwardDeadStackCopyLoads(arena: std.mem.Allocator, root_list: *InstrList) Error!bool {
    const items = root_list.items;
    const frame = detectShadowStackFrame(items) orelse return false;
    const fp = frame.fp;
    const sp_save = frame.sp_save;
    const frame_size = frame.frame_size;
    const body_start = frame.body_start;
    const body_end = frame.body_end;
    const has_epilogue = frame.has_epilogue;
    const has_trailing_return = frame.has_trailing_return;

    var body_list: InstrList = .empty;
    body_list.appendSlice(arena, items[body_start..body_end]) catch return error.OutOfMemory;

    var any_changed = false;
    while (try tryForwardDeadStackCopyInSlice(arena, body_list.items, &body_list, fp, sp_save, frame_size)) {
        any_changed = true;
    }
    if (!any_changed) return false;

    var new_list: InstrList = .empty;
    const cap = body_start + body_list.items.len + (items.len - body_end);
    new_list.ensureTotalCapacity(arena, cap) catch return error.OutOfMemory;
    new_list.appendSliceAssumeCapacity(items[0..body_start]);
    new_list.appendSliceAssumeCapacity(body_list.items);
    const new_body_end = new_list.items.len;
    new_list.appendSliceAssumeCapacity(items[body_end..]);

    // Bonus: if `fp` (and `sp_save`) now has no remaining uses in the body and there are no early returns/traps, strip the prologue and epilogue too.
    if (!sliceUsesLocalOrEarlyExit(new_list.items[body_start..new_body_end], fp, sp_save, has_epilogue)) {
        const stripped_body_len = new_body_end - body_start;
        std.mem.copyForwards(Instr, new_list.items[0..stripped_body_len], new_list.items[body_start..new_body_end]);
        var final_len = stripped_body_len;
        if (has_trailing_return) {
            new_list.items[final_len] = .return_;
            final_len += 1;
        }
        new_list.shrinkRetainingCapacity(final_len);
    }

    root_list.* = new_list;
    return true;
}

fn isCleanValSubtree(slice: []const Instr, forbidden_local: ?u32) bool {
    for (slice) |inst| {
        switch (inst) {
            .nop, .local_get, .i32_const, .i64_const, .ref_func, .numeric_op => {},
            .local_set, .local_tee => |lidx| {
                if (forbidden_local != null and lidx == forbidden_local.?) return false;
            },
            .block => |b| if (!isCleanValSubtree(b.body.items, forbidden_local)) return false,
            .if_ => |if_inst| {
                if (!isCleanValSubtree(if_inst.then_body.items, forbidden_local)) return false;
                if (if_inst.has_else and !isCleanValSubtree(if_inst.else_body.items, forbidden_local)) return false;
            },
            .raw => |r| {
                if (r.len == 0) return false;
                switch (r[0]) {
                    0x1a, 0x1b, 0x1c, 0x23, 0x28...0x35, 0x3f, 0x43, 0x44, 0xd0, 0xd1 => {},
                    0xfc => {
                        var p: usize = 1;
                        const sub = readU32(r, &p) catch return false;
                        if (sub > 0x07) return false;
                    },
                    0xfd => {
                        if (decodeStoreAccess(inst) != null) return false;
                    },
                    else => return false,
                }
            },
            else => return false,
        }
    }
    return true;
}

fn valExprStackEffect(inst: Instr, forbidden_local: ?u32) ?struct { pops: isize, pushes: isize } {
    return switch (inst) {
        .nop => .{ .pops = 0, .pushes = 0 },
        .local_get, .i32_const, .i64_const, .ref_func => .{ .pops = 0, .pushes = 1 },
        .local_tee => |lidx| blk: {
            if (forbidden_local != null and lidx == forbidden_local.?) break :blk null;
            break :blk .{ .pops = 1, .pushes = 1 };
        },
        .numeric_op => |op| switch (op) {
            0x45, 0x50, 0x67...0x69, 0x79...0x7b, 0x8b...0x91, 0x99...0x9f, 0xa7...0xc4 => .{ .pops = 1, .pushes = 1 },
            0x46...0x4f, 0x51...0x66, 0x6a...0x78, 0x7c...0x8a, 0x92...0x98, 0xa0...0xa6 => .{ .pops = 2, .pushes = 1 },
            else => null,
        },
        .block => |b| blk: {
            if (b.block_type.len == 1 and
                isAllowedValTypeByte(b.block_type.bytes[0]) and
                !hasBranchToDepth(b.body.items, 0) and
                isCleanValSubtree(b.body.items, forbidden_local))
            {
                break :blk .{ .pops = 0, .pushes = 1 };
            }
            break :blk null;
        },
        .if_ => |if_inst| blk: {
            if (if_inst.has_else and
                if_inst.block_type.len == 1 and
                isAllowedValTypeByte(if_inst.block_type.bytes[0]) and
                !hasBranchToDepth(if_inst.then_body.items, 0) and
                !hasBranchToDepth(if_inst.else_body.items, 0) and
                isCleanValSubtree(if_inst.then_body.items, forbidden_local) and
                isCleanValSubtree(if_inst.else_body.items, forbidden_local))
            {
                break :blk .{ .pops = 1, .pushes = 1 };
            }
            break :blk null;
        },
        .raw => |r| blk: {
            if (r.len == 0) break :blk null;
            break :blk switch (r[0]) {
                0x1b, 0x1c => .{ .pops = 3, .pushes = 1 },
                0x23, 0x3f, 0x43, 0x44, 0xd0 => .{ .pops = 0, .pushes = 1 },
                0x28...0x35, 0xd1 => .{ .pops = 1, .pushes = 1 },
                0xfc => {
                    var p: usize = 1;
                    const sub = readU32(r, &p) catch break :blk null;
                    if (sub <= 0x07) break :blk .{ .pops = 1, .pushes = 1 };
                    break :blk null;
                },
                0xfd => {
                    var p: usize = 1;
                    const sub = readU32(r, &p) catch break :blk null;
                    break :blk switch (sub) {
                        0x00...0x0a => .{ .pops = 1, .pushes = 1 },
                        0x0c => .{ .pops = 0, .pushes = 1 },
                        0x0d => .{ .pops = 2, .pushes = 1 },
                        0x0f...0x16, 0x18, 0x19, 0x1b, 0x1d, 0x1f, 0x21 => .{ .pops = 1, .pushes = 1 },
                        0x17, 0x1a, 0x1c, 0x1e, 0x20, 0x22 => .{ .pops = 2, .pushes = 1 },
                        0x52 => .{ .pops = 3, .pushes = 1 },
                        else => null,
                    };
                },
                else => null,
            };
        },
        else => null,
    };
}

fn findSingleValueStoreIdx(
    slice: []const Instr,
    val_start: usize,
    forbidden_local: ?u32,
) ?usize {
    var height: isize = 0;
    var idx = val_start;
    while (idx < slice.len) : (idx += 1) {
        if (height == 1) {
            if (decodeStoreAccess(slice[idx])) |access| {
                if (access.mem_idx == 0 and (access.opcode != 0xfd or access.simd_sub == 0x0b)) {
                    return idx;
                }
            }
        }
        const eff = valExprStackEffect(slice[idx], forbidden_local) orelse return null;
        if (height < eff.pops) return null;
        height = height - eff.pops + eff.pushes;
        if (slice[idx] != .nop and height <= 0) return null;
    }
    return null;
}

fn findSingleValueIndexLoadIdx(
    slice: []const Instr,
    val_start: usize,
    forbidden_local: ?u32,
) ?usize {
    var height: isize = 0;
    var idx = val_start;
    while (idx < slice.len) : (idx += 1) {
        if (height == 1 and idx + 1 < slice.len and
            slice[idx] == .numeric_op and slice[idx].numeric_op == 0x6a)
        {
            if (decodeLoadAccess(slice[idx + 1])) |access| {
                if (access.mem_idx == 0 and (access.opcode != 0xfd or access.simd_sub <= 0x0a)) {
                    return idx;
                }
            }
        }
        const eff = valExprStackEffect(slice[idx], forbidden_local) orelse return null;
        if (height < eff.pops) return null;
        height = height - eff.pops + eff.pushes;
        if (slice[idx] != .nop and height <= 0) return null;
    }
    return null;
}

const DerivedPtr = struct {
    base: u32,
    offset: u32,
    from_set: bool = false,
    in_current_slice: bool = true,
};

fn countLocalWritesInSlice(slice: []const Instr, write_counts: []u32) void {
    for (slice) |inst| {
        switch (inst) {
            .local_set, .local_tee => |x| {
                if (x < write_counts.len) write_counts[x] += 1;
            },
            .block => |b| countLocalWritesInSlice(b.body.items, write_counts),
            .loop => |l| countLocalWritesInSlice(l.body.items, write_counts),
            .if_ => |if_inst| {
                countLocalWritesInSlice(if_inst.then_body.items, write_counts);
                if (if_inst.has_else) countLocalWritesInSlice(if_inst.else_body.items, write_counts);
            },
            else => {},
        }
    }
}

fn countLocalReadsInSlice(slice: []const Instr, read_counts: []u32) void {
    for (slice) |inst| {
        switch (inst) {
            .local_get => |x| {
                if (x < read_counts.len) read_counts[x] += 1;
            },
            .block => |b| countLocalReadsInSlice(b.body.items, read_counts),
            .loop => |l| countLocalReadsInSlice(l.body.items, read_counts),
            .if_ => |if_inst| {
                countLocalReadsInSlice(if_inst.then_body.items, read_counts);
                if (if_inst.has_else) countLocalReadsInSlice(if_inst.else_body.items, read_counts);
            },
            else => {},
        }
    }
}

fn invalidateModifiedDerivedInSlice(slice: []const Instr, bindings: []?DerivedPtr) void {
    for (slice) |inst| {
        switch (inst) {
            .local_set, .local_tee => |x| {
                if (x < bindings.len) bindings[x] = null;
            },
            .block => |b| invalidateModifiedDerivedInSlice(b.body.items, bindings),
            .loop => |l| invalidateModifiedDerivedInSlice(l.body.items, bindings),
            .if_ => |if_inst| {
                invalidateModifiedDerivedInSlice(if_inst.then_body.items, bindings);
                if (if_inst.has_else) invalidateModifiedDerivedInSlice(if_inst.else_body.items, bindings);
            },
            else => {},
        }
    }
}

fn collectDerivedBasesInSlice(
    slice: []const Instr,
    param_count: u32,
    write_counts: []const u32,
    derived_bases: []bool,
) void {
    for (slice, 0..) |inst, i| {
        switch (inst) {
            .local_set, .local_tee => |ptr| {
                if (ptr >= param_count and i >= 3 and
                    slice[i - 3] == .local_get and
                    slice[i - 2] == .i32_const and
                    slice[i - 2].i32_const > 0 and
                    slice[i - 2].i32_const <= 65536 and
                    slice[i - 1] == .numeric_op and
                    slice[i - 1].numeric_op == 0x6a)
                {
                    const raw_base = slice[i - 3].local_get;
                    if (raw_base != ptr and raw_base < write_counts.len and write_counts[raw_base] == 0) {
                        derived_bases[raw_base] = true;
                    }
                }
            },
            .block => |b| collectDerivedBasesInSlice(b.body.items, param_count, write_counts, derived_bases),
            .loop => |l| collectDerivedBasesInSlice(l.body.items, param_count, write_counts, derived_bases),
            .if_ => |if_inst| {
                collectDerivedBasesInSlice(if_inst.then_body.items, param_count, write_counts, derived_bases);
                if (if_inst.has_else) collectDerivedBasesInSlice(if_inst.else_body.items, param_count, write_counts, derived_bases);
            },
            else => {},
        }
    }
}

fn bindDerivedPtrFromOut(
    out_items: []const Instr,
    ptr: u32,
    from_set: bool,
    param_count: u32,
    fp: ?u32,
    sp_save: ?u32,
    write_counts: []const u32,
    bindings: []?DerivedPtr,
    derived_bases: []bool,
) void {
    if (ptr >= bindings.len) return;
    bindings[ptr] = null;
    if (ptr < param_count) return;
    if (fp != null and ptr == fp.?) return;
    if (sp_save != null and ptr == sp_save.?) return;

    if (out_items.len >= 3 and
        out_items[out_items.len - 3] == .local_get and
        out_items[out_items.len - 2] == .i32_const and
        out_items[out_items.len - 2].i32_const > 0 and
        out_items[out_items.len - 2].i32_const <= 65536 and
        out_items[out_items.len - 1] == .numeric_op and
        out_items[out_items.len - 1].numeric_op == 0x6a)
    {
        const raw_base = out_items[out_items.len - 3].local_get;
        const k: u32 = @intCast(out_items[out_items.len - 2].i32_const);
        if (raw_base != ptr) {
            if (raw_base < write_counts.len and write_counts[raw_base] == 0) {
                bindings[ptr] = .{ .base = raw_base, .offset = k, .from_set = from_set, .in_current_slice = true };
                derived_bases[raw_base] = true;
            } else if (raw_base < bindings.len) {
                if (bindings[raw_base]) |parent_dp| {
                    if (parent_dp.base != ptr and parent_dp.offset + k <= 65536) {
                        bindings[ptr] = .{ .base = parent_dp.base, .offset = parent_dp.offset + k, .from_set = from_set, .in_current_slice = true };
                        derived_bases[parent_dp.base] = true;
                    }
                }
            }
        }
    } else if (out_items.len >= 1 and out_items[out_items.len - 1] == .local_get) {
        const raw_base = out_items[out_items.len - 1].local_get;
        if (raw_base != ptr and raw_base < bindings.len) {
            if (bindings[raw_base]) |parent_dp| {
                if (parent_dp.base != ptr) {
                    bindings[ptr] = .{ .base = parent_dp.base, .offset = parent_dp.offset, .from_set = from_set, .in_current_slice = true };
                }
            }
        }
    }
}

fn rewriteDerivedPtrsInSlice(
    arena: std.mem.Allocator,
    slice: []const Instr,
    param_count: u32,
    bindings: []?DerivedPtr,
    derived_bases: []bool,
    write_counts: []const u32,
    read_counts: []const u32,
    fp: ?u32,
    sp_save: ?u32,
    is_post_inline: bool,
    had_offset_fold: *bool,
    out: *InstrList,
) Error!bool {
    var changed = false;
    var i: usize = 0;
    while (i < slice.len) {
        switch (slice[i]) {
            .block => |b_in| {
                var b = b_in;
                const blk_bindings = arena.dupe(?DerivedPtr, bindings) catch return error.OutOfMemory;
                var new_body: InstrList = .empty;
                if (try rewriteDerivedPtrsInSlice(arena, b.body.items, param_count, blk_bindings, derived_bases, write_counts, read_counts, fp, sp_save, is_post_inline, had_offset_fold, &new_body)) {
                    changed = true;
                }
                b.body = new_body;
                invalidateModifiedDerivedInSlice(b.body.items, bindings);
                out.append(arena, .{ .block = b }) catch return error.OutOfMemory;
                i += 1;
                continue;
            },
            .loop => |l_in| {
                var l = l_in;
                invalidateModifiedDerivedInSlice(l.body.items, bindings);
                const lp_bindings = arena.dupe(?DerivedPtr, bindings) catch return error.OutOfMemory;
                for (lp_bindings) |*b_opt| {
                    if (b_opt.*) |*dp| dp.in_current_slice = false;
                }
                var new_body: InstrList = .empty;
                if (try rewriteDerivedPtrsInSlice(arena, l.body.items, param_count, lp_bindings, derived_bases, write_counts, read_counts, fp, sp_save, is_post_inline, had_offset_fold, &new_body)) {
                    changed = true;
                }
                l.body = new_body;
                invalidateModifiedDerivedInSlice(l.body.items, bindings);
                out.append(arena, .{ .loop = l }) catch return error.OutOfMemory;
                i += 1;
                continue;
            },
            .if_ => |if_in| {
                var if_inst = if_in;
                const then_bindings = arena.dupe(?DerivedPtr, bindings) catch return error.OutOfMemory;
                var new_then: InstrList = .empty;
                if (try rewriteDerivedPtrsInSlice(arena, if_inst.then_body.items, param_count, then_bindings, derived_bases, write_counts, read_counts, fp, sp_save, is_post_inline, had_offset_fold, &new_then)) {
                    changed = true;
                }
                if_inst.then_body = new_then;
                if (if_inst.has_else) {
                    const else_bindings = arena.dupe(?DerivedPtr, bindings) catch return error.OutOfMemory;
                    var new_else: InstrList = .empty;
                    if (try rewriteDerivedPtrsInSlice(arena, if_inst.else_body.items, param_count, else_bindings, derived_bases, write_counts, read_counts, fp, sp_save, is_post_inline, had_offset_fold, &new_else)) {
                        changed = true;
                    }
                    if_inst.else_body = new_else;
                }
                invalidateModifiedDerivedInSlice(if_inst.then_body.items, bindings);
                if (if_inst.has_else) invalidateModifiedDerivedInSlice(if_inst.else_body.items, bindings);
                out.append(arena, .{ .if_ = if_inst }) catch return error.OutOfMemory;
                i += 1;
                continue;
            },
            .local_set, .local_tee => |ptr| {
                bindDerivedPtrFromOut(out.items, ptr, slice[i] == .local_set, param_count, fp, sp_save, write_counts, bindings, derived_bases);
                out.append(arena, slice[i]) catch return error.OutOfMemory;
                i += 1;
                continue;
            },
            .local_get => |lidx| {
                // Case 1: derived pointer local `ptr = base + K`
                if (lidx < bindings.len) {
                    if (bindings[lidx]) |dp| {
                        // Subcase 1a: `local.get ptr; i32.const C (C >= 0); i32.add`
                        if (i + 2 < slice.len and
                            slice[i + 1] == .i32_const and slice[i + 1].i32_const >= 0 and
                            slice[i + 2] == .numeric_op and slice[i + 2].numeric_op == 0x6a)
                        {
                            const c: u64 = @intCast(slice[i + 1].i32_const);
                            const total_off: u64 = @as(u64, dp.offset) + c;
                            if (i + 3 < slice.len) {
                                if (decodeLoadAccess(slice[i + 3])) |access| {
                                    if (access.mem_idx == 0 and (access.opcode != 0xfd or access.simd_sub <= 0x0a) and
                                        access.offset + total_off <= std.math.maxInt(u32))
                                    {
                                        out.append(arena, .{ .local_get = dp.base }) catch return error.OutOfMemory;
                                        out.append(arena, try encodeLoadInstr(arena, access, access.align_val, access.offset + total_off)) catch return error.OutOfMemory;
                                        changed = true;
                                        had_offset_fold.* = true;
                                        i += 4;
                                        continue;
                                    }
                                }
                            }
                            if (findSingleValueStoreIdx(slice, i + 3, dp.base)) |store_idx| {
                                const access = decodeStoreAccess(slice[store_idx]).?;
                                if (access.offset + total_off <= std.math.maxInt(u32)) {
                                    out.append(arena, .{ .local_get = dp.base }) catch return error.OutOfMemory;
                                    _ = try rewriteDerivedPtrsInSlice(arena, slice[i + 3 .. store_idx], param_count, bindings, derived_bases, write_counts, read_counts, fp, sp_save, is_post_inline, had_offset_fold, out);
                                    out.append(arena, try encodeStoreInstr(arena, access, access.align_val, access.offset + total_off)) catch return error.OutOfMemory;
                                    changed = true;
                                    had_offset_fold.* = true;
                                    i = store_idx + 1;
                                    continue;
                                }
                            }
                            if (total_off <= std.math.maxInt(i32)) {
                                out.append(arena, .{ .local_get = dp.base }) catch return error.OutOfMemory;
                                out.append(arena, .{ .i32_const = @intCast(total_off) }) catch return error.OutOfMemory;
                                out.append(arena, .{ .numeric_op = 0x6a }) catch return error.OutOfMemory;
                                changed = true;
                                had_offset_fold.* = true;
                                i += 3;
                                continue;
                            }
                        }

                        // Subcase 1b: `local.get ptr; <load offset=O>`
                        if (i + 1 < slice.len) {
                            if (decodeLoadAccess(slice[i + 1])) |access| {
                                if (access.mem_idx == 0 and (access.opcode != 0xfd or access.simd_sub <= 0x0a) and
                                    access.offset + dp.offset <= std.math.maxInt(u32))
                                {
                                    out.append(arena, .{ .local_get = dp.base }) catch return error.OutOfMemory;
                                    out.append(arena, try encodeLoadInstr(arena, access, access.align_val, access.offset + dp.offset)) catch return error.OutOfMemory;
                                    changed = true;
                                    had_offset_fold.* = true;
                                    i += 2;
                                    continue;
                                }
                            }
                        }

                        // Subcase 1c: `local.get ptr; <val_expr>; <store offset=O>`
                        if (findSingleValueStoreIdx(slice, i + 1, dp.base)) |store_idx| {
                            const access = decodeStoreAccess(slice[store_idx]).?;
                            if (access.offset + dp.offset <= std.math.maxInt(u32)) {
                                out.append(arena, .{ .local_get = dp.base }) catch return error.OutOfMemory;
                                _ = try rewriteDerivedPtrsInSlice(arena, slice[i + 1 .. store_idx], param_count, bindings, derived_bases, write_counts, read_counts, fp, sp_save, is_post_inline, had_offset_fold, out);
                                out.append(arena, try encodeStoreInstr(arena, access, access.align_val, access.offset + dp.offset)) catch return error.OutOfMemory;
                                changed = true;
                                had_offset_fold.* = true;
                                i = store_idx + 1;
                                continue;
                            }
                        }

                        // Subcase 1d: single-write, single-read `ptr = base + K` -> inline `local.get base; i32.const K; i32.add`
                        if (dp.from_set and dp.in_current_slice and
                            lidx < write_counts.len and write_counts[lidx] == 1 and
                            lidx < read_counts.len and read_counts[lidx] == 1 and
                            dp.offset <= std.math.maxInt(i32))
                        {
                            out.append(arena, .{ .local_get = dp.base }) catch return error.OutOfMemory;
                            if (dp.offset > 0) {
                                out.append(arena, .{ .i32_const = @intCast(dp.offset) }) catch return error.OutOfMemory;
                                out.append(arena, .{ .numeric_op = 0x6a }) catch return error.OutOfMemory;
                            }
                            changed = true;
                            had_offset_fold.* = true;
                            i += 1;
                            continue;
                        }
                    }
                }

                // Case 2: direct `local.get base; i32.const K (0 <= K <= 65536); i32.add`
                if (lidx < write_counts.len and write_counts[lidx] == 0 and
                    i + 2 < slice.len and
                    slice[i + 1] == .i32_const and
                    slice[i + 1].i32_const >= 0 and
                    slice[i + 1].i32_const <= 65536 and
                    slice[i + 2] == .numeric_op and
                    slice[i + 2].numeric_op == 0x6a)
                {
                    const k: u64 = @intCast(slice[i + 1].i32_const);

                    // Subcase 2a: `local.get base; i32.const K; i32.add; local.tee ptr` followed by load/store
                    if (i + 3 < slice.len and slice[i + 3] == .local_tee) {
                        const ptr = slice[i + 3].local_tee;
                        if (ptr >= param_count and ptr < bindings.len and ptr != lidx and
                            (fp == null or ptr != fp.?) and (sp_save == null or ptr != sp_save.?))
                        {
                            if (i + 4 < slice.len) {
                                if (decodeLoadAccess(slice[i + 4])) |access| {
                                    if (access.mem_idx == 0 and (access.opcode != 0xfd or access.simd_sub <= 0x0a) and
                                        access.offset + k <= std.math.maxInt(u32))
                                    {
                                        out.append(arena, slice[i]) catch return error.OutOfMemory;
                                        out.append(arena, slice[i + 1]) catch return error.OutOfMemory;
                                        out.append(arena, slice[i + 2]) catch return error.OutOfMemory;
                                        bindDerivedPtrFromOut(out.items, ptr, true, param_count, fp, sp_save, write_counts, bindings, derived_bases);
                                        out.append(arena, .{ .local_set = ptr }) catch return error.OutOfMemory;
                                        out.append(arena, .{ .local_get = lidx }) catch return error.OutOfMemory;
                                        out.append(arena, try encodeLoadInstr(arena, access, access.align_val, access.offset + k)) catch return error.OutOfMemory;
                                        changed = true;
                                        had_offset_fold.* = true;
                                        i += 5;
                                        continue;
                                    }
                                }
                            }
                            if (findSingleValueStoreIdx(slice, i + 4, lidx)) |store_idx| {
                                const access = decodeStoreAccess(slice[store_idx]).?;
                                if (access.offset + k <= std.math.maxInt(u32)) {
                                    out.append(arena, slice[i]) catch return error.OutOfMemory;
                                    out.append(arena, slice[i + 1]) catch return error.OutOfMemory;
                                    out.append(arena, slice[i + 2]) catch return error.OutOfMemory;
                                    bindDerivedPtrFromOut(out.items, ptr, true, param_count, fp, sp_save, write_counts, bindings, derived_bases);
                                    out.append(arena, .{ .local_set = ptr }) catch return error.OutOfMemory;
                                    out.append(arena, .{ .local_get = lidx }) catch return error.OutOfMemory;
                                    _ = try rewriteDerivedPtrsInSlice(arena, slice[i + 4 .. store_idx], param_count, bindings, derived_bases, write_counts, read_counts, fp, sp_save, is_post_inline, had_offset_fold, out);
                                    out.append(arena, try encodeStoreInstr(arena, access, access.align_val, access.offset + k)) catch return error.OutOfMemory;
                                    changed = true;
                                    had_offset_fold.* = true;
                                    i = store_idx + 1;
                                    continue;
                                }
                            }
                        }
                    }

                    // Subcase 2b: `local.get base; i32.const K; i32.add; <load offset=O>`
                    const allow_load_fold = (fp != null and lidx == fp.?) or
                        is_post_inline or
                        (lidx < derived_bases.len and derived_bases[lidx]);
                    if (allow_load_fold and i + 3 < slice.len) {
                        if (decodeLoadAccess(slice[i + 3])) |access| {
                            if (access.mem_idx == 0 and (access.opcode != 0xfd or access.simd_sub <= 0x0a) and
                                access.offset + k <= std.math.maxInt(u32))
                            {
                                out.append(arena, .{ .local_get = lidx }) catch return error.OutOfMemory;
                                out.append(arena, try encodeLoadInstr(arena, access, access.align_val, access.offset + k)) catch return error.OutOfMemory;
                                changed = true;
                                had_offset_fold.* = true;
                                i += 4;
                                continue;
                            }
                        }
                    }

                    // Subcase 2c: `local.get base; i32.const K; i32.add; <val_expr>; <store offset=O>`
                    if (allow_load_fold) {
                        if (findSingleValueStoreIdx(slice, i + 3, lidx)) |store_idx| {
                            const access = decodeStoreAccess(slice[store_idx]).?;
                            if (access.offset + k <= std.math.maxInt(u32)) {
                                out.append(arena, .{ .local_get = lidx }) catch return error.OutOfMemory;
                                _ = try rewriteDerivedPtrsInSlice(arena, slice[i + 3 .. store_idx], param_count, bindings, derived_bases, write_counts, read_counts, fp, sp_save, is_post_inline, had_offset_fold, out);
                                out.append(arena, try encodeStoreInstr(arena, access, access.align_val, access.offset + k)) catch return error.OutOfMemory;
                                changed = true;
                                had_offset_fold.* = true;
                                i = store_idx + 1;
                                continue;
                            }
                        }
                    }
                }
            },
            else => {},
        }
        out.append(arena, slice[i]) catch return error.OutOfMemory;
        if (slice[i].isUnconditionalTransfer()) {
            @memset(bindings, null);
        }
        i += 1;
    }
    return changed;
}

fn foldDerivedPtrOffsets(
    arena: std.mem.Allocator,
    module: *const Mod.Module,
    func: *const Mod.Func,
    root_list: *InstrList,
    is_post_inline: bool,
    had_offset_fold: *bool,
) Error!bool {
    const sig = getFuncSignature(module, func) orelse return false;
    const param_count: u32 = @intCast(sig.params.len);
    const total_locals: usize = param_count + func.local_types.items.len;
    if (total_locals == 0) return false;

    const frame = detectShadowStackFrame(root_list.items);
    const body_slice = if (frame) |f| root_list.items[f.body_start..f.body_end] else root_list.items;
    if (body_slice.len == 0) return false;

    const write_counts = arena.alloc(u32, total_locals) catch return error.OutOfMemory;
    @memset(write_counts, 0);
    countLocalWritesInSlice(body_slice, write_counts);

    const init_read_counts = arena.alloc(u32, total_locals) catch return error.OutOfMemory;
    @memset(init_read_counts, 0);
    countLocalReadsInSlice(body_slice, init_read_counts);

    const bindings = arena.alloc(?DerivedPtr, total_locals) catch return error.OutOfMemory;
    @memset(bindings, null);
    const derived_bases = arena.alloc(bool, total_locals) catch return error.OutOfMemory;
    @memset(derived_bases, false);
    collectDerivedBasesInSlice(body_slice, param_count, write_counts, derived_bases);

    var rewritten_body: InstrList = .empty;
    rewritten_body.ensureTotalCapacity(arena, body_slice.len) catch return error.OutOfMemory;
    const fp_opt: ?u32 = if (frame) |f| f.fp else null;
    const sp_opt: ?u32 = if (frame) |f| f.sp_save else null;
    if (!(try rewriteDerivedPtrsInSlice(arena, body_slice, param_count, bindings, derived_bases, write_counts, init_read_counts, fp_opt, sp_opt, is_post_inline, had_offset_fold, &rewritten_body))) {
        return false;
    }

    while (true) {
        var read_counts: std.AutoHashMapUnmanaged(u32, u32) = .empty;
        try countLocalReads(&rewritten_body, arena, &read_counts);
        if (frame) |f| {
            const fp_entry = read_counts.getOrPut(arena, f.fp) catch return error.OutOfMemory;
            if (!fp_entry.found_existing) fp_entry.value_ptr.* = 0;
            fp_entry.value_ptr.* += 1;
            if (f.sp_save) |sp| {
                const sp_entry = read_counts.getOrPut(arena, sp) catch return error.OutOfMemory;
                if (!sp_entry.found_existing) sp_entry.value_ptr.* = 0;
                sp_entry.value_ptr.* += 1;
            }
        }
        if (!(try eliminateDeadLocalStores(arena, &rewritten_body, &read_counts))) break;
    }

    if (frame) |f| {
        var new_root: InstrList = .empty;
        const cap = f.body_start + rewritten_body.items.len + (root_list.items.len - f.body_end);
        new_root.ensureTotalCapacity(arena, cap) catch return error.OutOfMemory;
        new_root.appendSliceAssumeCapacity(root_list.items[0..f.body_start]);
        new_root.appendSliceAssumeCapacity(rewritten_body.items);
        new_root.appendSliceAssumeCapacity(root_list.items[f.body_end..]);
        root_list.* = new_root;
    } else {
        root_list.* = rewritten_body;
    }
    return true;
}

const ScalarSlotCand = struct {
    offset: u64,
    size: u32,
    val_type: ?types.ValType,
    promotable: bool = true,
    store_count: u32 = 0,
    load_count: u32 = 0,
    used_in_loop: bool = false,
    new_local: u32 = types.invalid_index,
};

fn fullWidthLoadValType(access: MemAccessInfo) ?types.ValType {
    return switch (access.opcode) {
        0x28 => .i32,
        0x29 => .i64,
        0x2a => .f32,
        0x2b => .f64,
        0xfd => if (access.simd_sub == 0x00) .v128 else null,
        else => null,
    };
}

fn fullWidthStoreValType(access: MemAccessInfo) ?types.ValType {
    return switch (access.opcode) {
        0x36 => .i32,
        0x37 => .i64,
        0x38 => .f32,
        0x39 => .f64,
        0xfd => if (access.simd_sub == 0x0b) .v128 else null,
        else => null,
    };
}

fn recordShadowSlotAccess(
    arena: std.mem.Allocator,
    slots: *std.ArrayListUnmanaged(ScalarSlotCand),
    offset: u64,
    size: u32,
    val_type: ?types.ValType,
    is_store: bool,
    in_loop: bool,
) Error!void {
    for (slots.items) |*slot| {
        if (slot.offset == offset and slot.size == size) {
            if (val_type == null or slot.val_type == null or slot.val_type.? != val_type.?) {
                slot.promotable = false;
                slot.val_type = null;
            }
            if (is_store) slot.store_count += 1 else slot.load_count += 1;
            if (in_loop) slot.used_in_loop = true;
            return;
        }
    }
    slots.append(arena, .{
        .offset = offset,
        .size = size,
        .val_type = val_type,
        .promotable = val_type != null,
        .store_count = if (is_store) 1 else 0,
        .load_count = if (is_store) 0 else 1,
        .used_in_loop = in_loop,
    }) catch return error.OutOfMemory;
}

fn analyzeFpUsesInSlice(
    arena: std.mem.Allocator,
    slice: []const Instr,
    fp: u32,
    sp_save: ?u32,
    frame_size: u64,
    in_loop: bool,
    slots: *std.ArrayListUnmanaged(ScalarSlotCand),
) Error!bool {
    var i: usize = 0;
    while (i < slice.len) {
        switch (slice[i]) {
            .local_set, .local_tee => |lidx| {
                if (lidx == fp) return false;
                if (sp_save != null and lidx == sp_save.?) return false;
            },
            .local_get => |lidx| {
                if (sp_save != null and lidx == sp_save.?) {
                    if (i + 1 < slice.len and slice[i + 1] == .raw and std.mem.eql(u8, slice[i + 1].raw, &.{ 0x24, 0x00 })) {
                        i += 2;
                        continue;
                    }
                    return false;
                }
                if (lidx == fp) {
                    if (i + 1 < slice.len) {
                        if (decodeLoadAccess(slice[i + 1])) |access| {
                            if (access.mem_idx != 0 or (access.opcode == 0xfd and access.simd_sub > 0x0a)) return false;
                            if (access.offset + access.size > frame_size) return false;
                            try recordShadowSlotAccess(arena, slots, access.offset, access.size, fullWidthLoadValType(access), false, in_loop);
                            i += 2;
                            continue;
                        }
                    }
                    if (findSingleValueStoreIdx(slice, i + 1, fp)) |store_idx| {
                        const access = decodeStoreAccess(slice[store_idx]).?;
                        if (access.mem_idx != 0 or access.offset + access.size > frame_size) return false;
                        if (!(try analyzeFpUsesInSlice(arena, slice[i + 1 .. store_idx], fp, sp_save, frame_size, in_loop, slots))) {
                            return false;
                        }
                        try recordShadowSlotAccess(arena, slots, access.offset, access.size, fullWidthStoreValType(access), true, in_loop);
                        i = store_idx + 1;
                        continue;
                    }
                    if (matchStackFrameCopyAt(slice, i, fp)) |copy_cand| {
                        if (copy_cand.dst_offset + copy_cand.copy_len > frame_size) return false;
                        if (copy_cand.copy_len > std.math.maxInt(u32)) return false;
                        if (sp_save != null and copy_cand.src_local == sp_save.?) return false;
                        try recordShadowSlotAccess(arena, slots, copy_cand.dst_offset, @intCast(copy_cand.copy_len), null, true, in_loop);
                        if (copy_cand.src_local == fp) {
                            if (copy_cand.src_offset + copy_cand.copy_len > frame_size) return false;
                            try recordShadowSlotAccess(arena, slots, copy_cand.src_offset, @intCast(copy_cand.copy_len), null, false, in_loop);
                        }
                        i = copy_cand.end_idx;
                        continue;
                    }
                    // `memory.copy` where `src` is `fp` or `fp + src_off`:
                    if (matchFpSrcCopyAt(slice, i, fp)) |src_copy| {
                        if (src_copy.src_offset + src_copy.copy_len > frame_size) return false;
                        if (src_copy.copy_len > std.math.maxInt(u32)) return false;
                        try recordShadowSlotAccess(arena, slots, src_copy.src_offset, @intCast(src_copy.copy_len), null, false, in_loop);
                        i = src_copy.end_idx;
                        continue;
                    }
                    // `memory.fill` where `dst` is `fp` or `fp + dst_off`:
                    if (matchFpFillAt(slice, i, fp)) |fill_cand| {
                        if (fill_cand.dst_offset + fill_cand.fill_len > frame_size) return false;
                        if (fill_cand.fill_len > std.math.maxInt(u32)) return false;
                        try recordShadowSlotAccess(arena, slots, fill_cand.dst_offset, @intCast(fill_cand.fill_len), null, true, in_loop);
                        i = fill_cand.end_idx;
                        continue;
                    }
                    // In-function non-escaping address `local.get fp; i32.const c; i32.add` (`c >= 0`)
                    // consumed directly by a load or store (never passed to a call or stored as a pointer,
                    // preserving `@fieldParentPtr` safety):
                    if (i + 3 < slice.len and
                        slice[i + 1] == .i32_const and slice[i + 1].i32_const >= 0 and
                        slice[i + 2] == .numeric_op and slice[i + 2].numeric_op == 0x6a)
                    {
                        const add_off: u64 = @intCast(slice[i + 1].i32_const);
                        if (decodeLoadAccess(slice[i + 3])) |access| {
                            if (access.mem_idx != 0 or (access.opcode == 0xfd and access.simd_sub > 0x0a)) return false;
                            if (add_off + access.offset + access.size > frame_size) return false;
                            try recordShadowSlotAccess(arena, slots, add_off + access.offset, access.size, null, false, in_loop);
                            i += 4;
                            continue;
                        }
                        if (findSingleValueStoreIdx(slice, i + 3, fp)) |store_idx| {
                            const access = decodeStoreAccess(slice[store_idx]).?;
                            if (access.mem_idx != 0 or add_off + access.offset + access.size > frame_size) return false;
                            if (!(try analyzeFpUsesInSlice(arena, slice[i + 3 .. store_idx], fp, sp_save, frame_size, in_loop, slots))) {
                                return false;
                            }
                            try recordShadowSlotAccess(arena, slots, add_off + access.offset, access.size, null, true, in_loop);
                            i = store_idx + 1;
                            continue;
                        }
                    }
                    return false;
                }
            },
            .block => |b| {
                if (!(try analyzeFpUsesInSlice(arena, b.body.items, fp, sp_save, frame_size, in_loop, slots))) return false;
            },
            .loop => |l| {
                if (!(try analyzeFpUsesInSlice(arena, l.body.items, fp, sp_save, frame_size, true, slots))) return false;
            },
            .if_ => |if_inst| {
                if (!(try analyzeFpUsesInSlice(arena, if_inst.then_body.items, fp, sp_save, frame_size, in_loop, slots))) return false;
                if (if_inst.has_else and !(try analyzeFpUsesInSlice(arena, if_inst.else_body.items, fp, sp_save, frame_size, in_loop, slots))) return false;
            },
            else => {},
        }
        i += 1;
    }
    return true;
}

fn findPromotedSlot(slots: []const ScalarSlotCand, offset: u64, size: u32) ?ScalarSlotCand {
    for (slots) |slot| {
        if (slot.promotable and slot.offset == offset and slot.size == size and slot.new_local != types.invalid_index) {
            return slot;
        }
    }
    return null;
}

fn rewriteScalarizedSlotsInSlice(
    arena: std.mem.Allocator,
    slice: []const Instr,
    fp: u32,
    slots: []const ScalarSlotCand,
    out: *InstrList,
) Error!void {
    var i: usize = 0;
    while (i < slice.len) {
        switch (slice[i]) {
            .block => |b_in| {
                var b = b_in;
                var new_body: InstrList = .empty;
                try rewriteScalarizedSlotsInSlice(arena, b.body.items, fp, slots, &new_body);
                b.body = new_body;
                out.append(arena, .{ .block = b }) catch return error.OutOfMemory;
                i += 1;
                continue;
            },
            .loop => |l_in| {
                var l = l_in;
                var new_body: InstrList = .empty;
                try rewriteScalarizedSlotsInSlice(arena, l.body.items, fp, slots, &new_body);
                l.body = new_body;
                out.append(arena, .{ .loop = l }) catch return error.OutOfMemory;
                i += 1;
                continue;
            },
            .if_ => |if_in| {
                var if_inst = if_in;
                var new_then: InstrList = .empty;
                try rewriteScalarizedSlotsInSlice(arena, if_inst.then_body.items, fp, slots, &new_then);
                if_inst.then_body = new_then;
                if (if_inst.has_else) {
                    var new_else: InstrList = .empty;
                    try rewriteScalarizedSlotsInSlice(arena, if_inst.else_body.items, fp, slots, &new_else);
                    if_inst.else_body = new_else;
                }
                out.append(arena, .{ .if_ = if_inst }) catch return error.OutOfMemory;
                i += 1;
                continue;
            },
            .local_get => |lidx| {
                if (lidx == fp) {
                    if (i + 1 < slice.len) {
                        if (decodeLoadAccess(slice[i + 1])) |access| {
                            if (findPromotedSlot(slots, access.offset, access.size)) |slot| {
                                out.append(arena, .{ .local_get = slot.new_local }) catch return error.OutOfMemory;
                                i += 2;
                                continue;
                            }
                        }
                    }
                    if (findSingleValueStoreIdx(slice, i + 1, fp)) |store_idx| {
                        const access = decodeStoreAccess(slice[store_idx]).?;
                        if (findPromotedSlot(slots, access.offset, access.size)) |slot| {
                            try rewriteScalarizedSlotsInSlice(arena, slice[i + 1 .. store_idx], fp, slots, out);
                            out.append(arena, .{ .local_set = slot.new_local }) catch return error.OutOfMemory;
                            i = store_idx + 1;
                            continue;
                        }
                    }
                }
            },
            else => {},
        }
        out.append(arena, slice[i]) catch return error.OutOfMemory;
        i += 1;
    }
}

fn scalarizeShadowStackSlots(
    arena: std.mem.Allocator,
    module: *const Mod.Module,
    func: *Mod.Func,
    root_list: *InstrList,
    is_post_inline: bool,
    had_offset_fold: bool,
) Error!bool {
    const frame = detectShadowStackFrame(root_list.items) orelse return false;
    const body_slice = root_list.items[frame.body_start..frame.body_end];

    if (!sliceUsesLocalOrEarlyExit(body_slice, frame.fp, frame.sp_save, frame.has_epilogue) and
        (!frame.has_epilogue or !hasBranchToDepth(body_slice, 0)))
    {
        const stripped_body_len = frame.body_end - frame.body_start;
        std.mem.copyForwards(Instr, root_list.items[0..stripped_body_len], body_slice);
        var final_len = stripped_body_len;
        if (frame.has_trailing_return) {
            root_list.items[final_len] = .return_;
            final_len += 1;
        }
        root_list.shrinkRetainingCapacity(final_len);
        return true;
    }

    var slots: std.ArrayListUnmanaged(ScalarSlotCand) = .empty;
    if (!(try analyzeFpUsesInSlice(arena, body_slice, frame.fp, frame.sp_save, frame.frame_size, false, &slots))) {
        return false;
    }
    if (slots.items.len == 0) return false;

    for (0..slots.items.len) |i| {
        for (i + 1..slots.items.len) |j| {
            if (rangesOverlap(slots.items[i].offset, slots.items[i].size, slots.items[j].offset, slots.items[j].size)) {
                slots.items[i].promotable = false;
                slots.items[j].promotable = false;
            }
        }
    }

    std.mem.sort(ScalarSlotCand, slots.items, {}, struct {
        fn lessThan(_: void, a: ScalarSlotCand, b: ScalarSlotCand) bool {
            if (a.offset != b.offset) return a.offset < b.offset;
            return a.size < b.size;
        }
    }.lessThan);

    const sig = getFuncSignature(module, func) orelse return false;
    const param_count: u32 = @intCast(sig.params.len);

    var any_promoted = false;
    for (slots.items) |*slot| {
        const worth = is_post_inline or
            had_offset_fold or
            slots.items.len >= 2 or
            slot.used_in_loop or
            (slot.store_count + slot.load_count >= 3);
        if (slot.promotable and slot.val_type != null and slot.store_count >= 1 and worth) {
            const new_idx: u32 = param_count + @as(u32, @intCast(func.local_types.items.len));
            if (func.local_type_idxs.items.len == func.local_types.items.len and func.local_type_idxs.items.len > 0) {
                func.local_type_idxs.append(module.allocator, types.invalid_index) catch return error.OutOfMemory;
            } else {
                func.local_type_idxs.clearRetainingCapacity();
            }
            func.local_types.append(module.allocator, slot.val_type.?) catch return error.OutOfMemory;
            slot.new_local = new_idx;
            any_promoted = true;
        } else {
            slot.promotable = false;
        }
    }
    if (!any_promoted) return false;

    var rewritten_body: InstrList = .empty;
    rewritten_body.ensureTotalCapacity(arena, body_slice.len) catch return error.OutOfMemory;
    try rewriteScalarizedSlotsInSlice(arena, body_slice, frame.fp, slots.items, &rewritten_body);

    if (!sliceUsesLocalOrEarlyExit(rewritten_body.items, frame.fp, frame.sp_save, frame.has_epilogue) and
        (!frame.has_epilogue or !hasBranchToDepth(rewritten_body.items, 0)))
    {
        if (frame.has_trailing_return) {
            rewritten_body.append(arena, .return_) catch return error.OutOfMemory;
        }
        root_list.* = rewritten_body;
    } else {
        var new_root: InstrList = .empty;
        const cap = frame.body_start + rewritten_body.items.len + (root_list.items.len - frame.body_end);
        new_root.ensureTotalCapacity(arena, cap) catch return error.OutOfMemory;
        new_root.appendSliceAssumeCapacity(root_list.items[0..frame.body_start]);
        new_root.appendSliceAssumeCapacity(rewritten_body.items);
        new_root.appendSliceAssumeCapacity(root_list.items[frame.body_end..]);
        root_list.* = new_root;
    }
    return true;
}

const TrackedMemEntry = struct {
    base_local: u32,
    offset: u64,
    size: u32,
    opcode: u8,
    simd_sub: u32 = 0,
    val_instr: Instr,
    is_from_store: bool,
};

const PendingDeadStore = struct {
    base_local: u32,
    offset: u64,
    size: u32,
    out_idx: usize,
    active: bool = true,
};

fn memRangesOverlap(off_a: u64, size_a: u32, off_b: u64, size_b: u32) bool {
    return off_a < off_b + size_b and off_b < off_a + size_a;
}

fn isForwardableMemVal(inst: Instr, base_local: u32) bool {
    return switch (inst) {
        .i32_const, .i64_const => true,
        .local_get => |l| l != base_local,
        .raw => |r| r.len > 0 and switch (r[0]) {
            0x43, 0x44 => true,
            0xfd => blk: {
                var p: usize = 1;
                const sub = readU32(r, &p) catch break :blk false;
                break :blk sub == 0x0c; // v128.const
            },
            else => false,
        },
        else => false,
    };
}

fn checkFpNeverEscapesToCallOrMem(slice: []const Instr, fp: u32, sp_updated_in_prologue: bool) bool {
    var i: usize = 0;
    while (i < slice.len) : (i += 1) {
        switch (slice[i]) {
            .local_set => |l| if (l == fp) return false,
            .local_tee => |l| if (l == fp) return false,
            .call, .return_call, .return_call_indirect => if (!sp_updated_in_prologue) return false,
            .raw => |r| if (!sp_updated_in_prologue and r.len > 0) switch (r[0]) {
                0x10, 0x11, 0x12, 0x13, 0x14, 0x15 => return false,
                else => {},
            },
            .local_get => |l| if (l == fp) {
                if (i + 1 < slice.len) {
                    if (decodeLoadAccess(slice[i + 1]) != null) {
                        i += 1;
                        continue;
                    }
                    if (i + 2 < slice.len and isPureZeroPopInstr(slice[i + 1]) and decodeStoreAccess(slice[i + 2]) != null) {
                        if (slice[i + 1] == .local_get and slice[i + 1].local_get == fp) return false;
                        i += 2;
                        continue;
                    }
                    if (findSingleValueStoreIdx(slice, i + 1, fp)) |store_idx| {
                        if (!checkFpNeverEscapesToCallOrMem(slice[i + 1 .. store_idx], fp, sp_updated_in_prologue)) return false;
                        i = store_idx;
                        continue;
                    }
                }
                return false;
            },
            .block => |b| if (!checkFpNeverEscapesToCallOrMem(b.body.items, fp, sp_updated_in_prologue)) return false,
            .loop => |lp| if (!checkFpNeverEscapesToCallOrMem(lp.body.items, fp, sp_updated_in_prologue)) return false,
            .if_ => |if_inst| {
                if (!checkFpNeverEscapesToCallOrMem(if_inst.then_body.items, fp, sp_updated_in_prologue)) return false;
                if (if_inst.has_else and !checkFpNeverEscapesToCallOrMem(if_inst.else_body.items, fp, sp_updated_in_prologue)) return false;
            },
            else => {},
        }
    }
    return true;
}

fn invalidateMemEntriesForLocal(active: *std.ArrayListUnmanaged(TrackedMemEntry), local_idx: u32) void {
    var i: usize = 0;
    while (i < active.items.len) {
        const e = active.items[i];
        if (e.base_local == local_idx or (e.val_instr == .local_get and e.val_instr.local_get == local_idx)) {
            _ = active.swapRemove(i);
        } else {
            i += 1;
        }
    }
}

fn invalidateMemEntriesForStore(
    active: *std.ArrayListUnmanaged(TrackedMemEntry),
    store_base: ?u32,
    offset: u64,
    size: u32,
    non_escaping_fp: ?u32,
) void {
    var i: usize = 0;
    while (i < active.items.len) {
        const e = active.items[i];
        const remove = if (store_base) |sb| blk: {
            if (e.base_local == sb) {
                break :blk memRangesOverlap(e.offset, e.size, offset, size);
            }
            if (non_escaping_fp != null and (e.base_local == non_escaping_fp.? or sb == non_escaping_fp.?)) {
                break :blk false;
            }
            break :blk true;
        } else blk: {
            if (non_escaping_fp != null and e.base_local == non_escaping_fp.?) {
                break :blk false;
            }
            break :blk true;
        };
        if (remove) {
            _ = active.swapRemove(i);
        } else {
            i += 1;
        }
    }
}

fn invalidateMemEntriesForCall(active: *std.ArrayListUnmanaged(TrackedMemEntry), non_escaping_fp: ?u32) void {
    var i: usize = 0;
    while (i < active.items.len) {
        if (non_escaping_fp != null and active.items[i].base_local == non_escaping_fp.?) {
            i += 1;
        } else {
            _ = active.swapRemove(i);
        }
    }
}

fn invalidateClobberedMemEntries(
    list: *const InstrList,
    arena: std.mem.Allocator,
    active: *std.ArrayListUnmanaged(TrackedMemEntry),
    non_escaping_fp: ?u32,
) Error!void {
    if (active.items.len == 0) return;
    var mod_locals: std.AutoHashMapUnmanaged(u32, void) = .empty;
    try collectModifiedLocals(list, arena, &mod_locals);
    var it = mod_locals.keyIterator();
    while (it.next()) |k| {
        invalidateMemEntriesForLocal(active, k.*);
    }
    invalidateClobberedMemEntriesInSlice(list.items, active, &mod_locals, non_escaping_fp);
}

fn invalidateClobberedMemEntriesInSlice(
    slice: []const Instr,
    active: *std.ArrayListUnmanaged(TrackedMemEntry),
    mod_locals: *const std.AutoHashMapUnmanaged(u32, void),
    non_escaping_fp: ?u32,
) void {
    for (slice, 0..) |inst, idx| {
        if (active.items.len == 0) return;
        if (decodeStoreAccess(inst)) |store_acc| {
            if (store_acc.mem_idx != 0) {
                active.clearRetainingCapacity();
                return;
            }
            var known_base: ?u32 = null;
            if (findPrevSingleValueExprStart(slice, idx)) |val_start| {
                if (val_start >= 1 and slice[val_start - 1] == .local_get) {
                    const b = slice[val_start - 1].local_get;
                    if (!mod_locals.contains(b)) known_base = b;
                }
            }
            invalidateMemEntriesForStore(active, known_base, store_acc.offset, store_acc.size, non_escaping_fp);
            continue;
        }
        switch (inst) {
            .call, .return_call, .return_call_indirect => invalidateMemEntriesForCall(active, non_escaping_fp),
            .block => |b| invalidateClobberedMemEntriesInSlice(b.body.items, active, mod_locals, non_escaping_fp),
            .loop => |lp| invalidateClobberedMemEntriesInSlice(lp.body.items, active, mod_locals, non_escaping_fp),
            .if_ => |if_inst| {
                invalidateClobberedMemEntriesInSlice(if_inst.then_body.items, active, mod_locals, non_escaping_fp);
                if (if_inst.has_else) invalidateClobberedMemEntriesInSlice(if_inst.else_body.items, active, mod_locals, non_escaping_fp);
            },
            .raw => |r| if (r.len > 0) switch (r[0]) {
                0x10, 0x11, 0x12, 0x13, 0x14, 0x15 => invalidateMemEntriesForCall(active, non_escaping_fp),
                0x40, 0xfb, 0xfe => active.clearRetainingCapacity(),
                0xfc => {
                    var p: usize = 1;
                    const sub = readU32(r, &p) catch {
                        active.clearRetainingCapacity();
                        return;
                    };
                    if (sub >= 0x08 and sub <= 0x0b) {
                        active.clearRetainingCapacity();
                        return;
                    }
                },
                0xfd => {
                    var p: usize = 1;
                    const sub = readU32(r, &p) catch {
                        active.clearRetainingCapacity();
                        return;
                    };
                    if (sub >= 0x58 and sub <= 0x5b) {
                        active.clearRetainingCapacity();
                        return;
                    }
                },
                else => {},
            },
            else => {},
        }
    }
}

fn emitForwardedLoadValue(
    arena: std.mem.Allocator,
    out: *InstrList,
    entry: TrackedMemEntry,
    load_acc: MemAccessInfo,
) Error!bool {
    if (load_acc.offset < entry.offset or load_acc.offset + load_acc.size > entry.offset + entry.size) return false;

    if (load_acc.offset == entry.offset and load_acc.size == entry.size) {
        if (!entry.is_from_store and load_acc.opcode == entry.opcode and load_acc.simd_sub == entry.simd_sub) {
            out.items[out.items.len - 1] = entry.val_instr;
            return true;
        }
        switch (load_acc.opcode) {
            0x28 => if (entry.opcode == 0x36 or entry.opcode == 0x28) {
                out.items[out.items.len - 1] = entry.val_instr;
                return true;
            },
            0x29 => if (entry.opcode == 0x37 or entry.opcode == 0x29) {
                out.items[out.items.len - 1] = entry.val_instr;
                return true;
            },
            0x2a => if (entry.opcode == 0x38 or entry.opcode == 0x2a) {
                out.items[out.items.len - 1] = entry.val_instr;
                return true;
            },
            0x2b => if (entry.opcode == 0x39 or entry.opcode == 0x2b) {
                out.items[out.items.len - 1] = entry.val_instr;
                return true;
            },
            0xfd => if (load_acc.simd_sub == 0x00 and entry.opcode == 0xfd and (entry.simd_sub == 0x0b or entry.simd_sub == 0x00)) {
                out.items[out.items.len - 1] = entry.val_instr;
                return true;
            },
            0x2d => if (entry.opcode == 0x3a) {
                if (entry.val_instr == .i32_const) {
                    out.items[out.items.len - 1] = .{ .i32_const = entry.val_instr.i32_const & 0xff };
                } else {
                    out.items[out.items.len - 1] = entry.val_instr;
                    out.append(arena, .{ .i32_const = 0xff }) catch return error.OutOfMemory;
                    out.append(arena, .{ .numeric_op = 0x71 }) catch return error.OutOfMemory;
                }
                return true;
            },
            0x2c => if (entry.opcode == 0x3a) {
                if (entry.val_instr == .i32_const) {
                    out.items[out.items.len - 1] = .{ .i32_const = @as(i32, @as(i8, @truncate(entry.val_instr.i32_const))) };
                } else {
                    out.items[out.items.len - 1] = entry.val_instr;
                    out.append(arena, .{ .numeric_op = 0xc0 }) catch return error.OutOfMemory;
                }
                return true;
            },
            0x2f => if (entry.opcode == 0x3b) {
                if (entry.val_instr == .i32_const) {
                    out.items[out.items.len - 1] = .{ .i32_const = entry.val_instr.i32_const & 0xffff };
                } else {
                    out.items[out.items.len - 1] = entry.val_instr;
                    out.append(arena, .{ .i32_const = 0xffff }) catch return error.OutOfMemory;
                    out.append(arena, .{ .numeric_op = 0x71 }) catch return error.OutOfMemory;
                }
                return true;
            },
            0x2e => if (entry.opcode == 0x3b) {
                if (entry.val_instr == .i32_const) {
                    out.items[out.items.len - 1] = .{ .i32_const = @as(i32, @as(i16, @truncate(entry.val_instr.i32_const))) };
                } else {
                    out.items[out.items.len - 1] = entry.val_instr;
                    out.append(arena, .{ .numeric_op = 0xc1 }) catch return error.OutOfMemory;
                }
                return true;
            },
            0x31 => if (entry.opcode == 0x3c) {
                if (entry.val_instr == .i64_const) {
                    out.items[out.items.len - 1] = .{ .i64_const = entry.val_instr.i64_const & 0xff };
                } else {
                    out.items[out.items.len - 1] = entry.val_instr;
                    out.append(arena, .{ .i64_const = 0xff }) catch return error.OutOfMemory;
                    out.append(arena, .{ .numeric_op = 0x83 }) catch return error.OutOfMemory;
                }
                return true;
            },
            0x30 => if (entry.opcode == 0x3c) {
                if (entry.val_instr == .i64_const) {
                    out.items[out.items.len - 1] = .{ .i64_const = @as(i64, @as(i8, @truncate(entry.val_instr.i64_const))) };
                } else {
                    out.items[out.items.len - 1] = entry.val_instr;
                    out.append(arena, .{ .numeric_op = 0xc2 }) catch return error.OutOfMemory;
                }
                return true;
            },
            0x33 => if (entry.opcode == 0x3d) {
                if (entry.val_instr == .i64_const) {
                    out.items[out.items.len - 1] = .{ .i64_const = entry.val_instr.i64_const & 0xffff };
                } else {
                    out.items[out.items.len - 1] = entry.val_instr;
                    out.append(arena, .{ .i64_const = 0xffff }) catch return error.OutOfMemory;
                    out.append(arena, .{ .numeric_op = 0x83 }) catch return error.OutOfMemory;
                }
                return true;
            },
            0x32 => if (entry.opcode == 0x3d) {
                if (entry.val_instr == .i64_const) {
                    out.items[out.items.len - 1] = .{ .i64_const = @as(i64, @as(i16, @truncate(entry.val_instr.i64_const))) };
                } else {
                    out.items[out.items.len - 1] = entry.val_instr;
                    out.append(arena, .{ .numeric_op = 0xc3 }) catch return error.OutOfMemory;
                }
                return true;
            },
            0x35 => if (entry.opcode == 0x3e) {
                if (entry.val_instr == .i64_const) {
                    out.items[out.items.len - 1] = .{ .i64_const = entry.val_instr.i64_const & 0xffff_ffff };
                } else {
                    out.items[out.items.len - 1] = entry.val_instr;
                    out.append(arena, .{ .i64_const = 0xffff_ffff }) catch return error.OutOfMemory;
                    out.append(arena, .{ .numeric_op = 0x83 }) catch return error.OutOfMemory;
                }
                return true;
            },
            0x34 => if (entry.opcode == 0x3e) {
                if (entry.val_instr == .i64_const) {
                    out.items[out.items.len - 1] = .{ .i64_const = @as(i64, @as(i32, @truncate(entry.val_instr.i64_const))) };
                } else {
                    out.items[out.items.len - 1] = entry.val_instr;
                    out.append(arena, .{ .numeric_op = 0xc4 }) catch return error.OutOfMemory;
                }
                return true;
            },
            else => return false,
        }
        return false;
    }

    // Narrow load bit-slice extraction (`load_acc.size < entry.size`)
    if (load_acc.size < entry.size) {
        const bit_shift: u32 = @intCast((load_acc.offset - entry.offset) * 8);
        if (entry.size == 4 and (entry.opcode == 0x36 or entry.opcode == 0x28)) {
            if (entry.val_instr == .i32_const) {
                const shifted: u32 = @as(u32, @bitCast(entry.val_instr.i32_const)) >> @as(u5, @intCast(bit_shift));
                const folded: i32 = switch (load_acc.opcode) {
                    0x2d => @intCast(shifted & 0xff),
                    0x2c => @as(i32, @as(i8, @bitCast(@as(u8, @truncate(shifted))))),
                    0x2f => @intCast(shifted & 0xffff),
                    0x2e => @as(i32, @as(i16, @bitCast(@as(u16, @truncate(shifted))))),
                    else => return false,
                };
                out.items[out.items.len - 1] = .{ .i32_const = folded };
                return true;
            }
            switch (load_acc.opcode) {
                0x2d, 0x2c, 0x2f, 0x2e => {
                    out.items[out.items.len - 1] = entry.val_instr;
                    if (bit_shift > 0) {
                        out.append(arena, .{ .i32_const = @intCast(bit_shift) }) catch return error.OutOfMemory;
                        out.append(arena, .{ .numeric_op = 0x76 }) catch return error.OutOfMemory; // i32.shr_u
                    }
                    switch (load_acc.opcode) {
                        0x2d => if (bit_shift < 24) {
                            out.append(arena, .{ .i32_const = 0xff }) catch return error.OutOfMemory;
                            out.append(arena, .{ .numeric_op = 0x71 }) catch return error.OutOfMemory;
                        },
                        0x2c => out.append(arena, .{ .numeric_op = 0xc0 }) catch return error.OutOfMemory,
                        0x2f => if (bit_shift < 16) {
                            out.append(arena, .{ .i32_const = 0xffff }) catch return error.OutOfMemory;
                            out.append(arena, .{ .numeric_op = 0x71 }) catch return error.OutOfMemory;
                        },
                        0x2e => out.append(arena, .{ .numeric_op = 0xc1 }) catch return error.OutOfMemory,
                        else => unreachable,
                    }
                    return true;
                },
                else => return false,
            }
        } else if (entry.size == 8 and (entry.opcode == 0x37 or entry.opcode == 0x29)) {
            if (entry.val_instr == .i64_const) {
                const shifted: u64 = @as(u64, @bitCast(entry.val_instr.i64_const)) >> @as(u6, @intCast(bit_shift));
                switch (load_acc.opcode) {
                    0x28 => out.items[out.items.len - 1] = .{ .i32_const = @bitCast(@as(u32, @truncate(shifted))) },
                    0x2d => out.items[out.items.len - 1] = .{ .i32_const = @intCast(shifted & 0xff) },
                    0x2c => out.items[out.items.len - 1] = .{ .i32_const = @as(i32, @as(i8, @bitCast(@as(u8, @truncate(shifted))))) },
                    0x2f => out.items[out.items.len - 1] = .{ .i32_const = @intCast(shifted & 0xffff) },
                    0x2e => out.items[out.items.len - 1] = .{ .i32_const = @as(i32, @as(i16, @bitCast(@as(u16, @truncate(shifted))))) },
                    0x31 => out.items[out.items.len - 1] = .{ .i64_const = @intCast(shifted & 0xff) },
                    0x30 => out.items[out.items.len - 1] = .{ .i64_const = @as(i64, @as(i8, @bitCast(@as(u8, @truncate(shifted))))) },
                    0x33 => out.items[out.items.len - 1] = .{ .i64_const = @intCast(shifted & 0xffff) },
                    0x32 => out.items[out.items.len - 1] = .{ .i64_const = @as(i64, @as(i16, @bitCast(@as(u16, @truncate(shifted))))) },
                    0x35 => out.items[out.items.len - 1] = .{ .i64_const = @intCast(shifted & 0xffff_ffff) },
                    0x34 => out.items[out.items.len - 1] = .{ .i64_const = @as(i64, @as(i32, @bitCast(@as(u32, @truncate(shifted))))) },
                    else => return false,
                }
                return true;
            }
            switch (load_acc.opcode) {
                0x28, 0x2d, 0x2c, 0x2f, 0x2e => {
                    out.items[out.items.len - 1] = entry.val_instr;
                    if (bit_shift > 0) {
                        out.append(arena, .{ .i64_const = @intCast(bit_shift) }) catch return error.OutOfMemory;
                        out.append(arena, .{ .numeric_op = 0x88 }) catch return error.OutOfMemory; // i64.shr_u
                    }
                    out.append(arena, .{ .numeric_op = 0xa7 }) catch return error.OutOfMemory; // i32.wrap_i64
                    switch (load_acc.opcode) {
                        0x28 => {},
                        0x2d => {
                            out.append(arena, .{ .i32_const = 0xff }) catch return error.OutOfMemory;
                            out.append(arena, .{ .numeric_op = 0x71 }) catch return error.OutOfMemory;
                        },
                        0x2c => out.append(arena, .{ .numeric_op = 0xc0 }) catch return error.OutOfMemory,
                        0x2f => {
                            out.append(arena, .{ .i32_const = 0xffff }) catch return error.OutOfMemory;
                            out.append(arena, .{ .numeric_op = 0x71 }) catch return error.OutOfMemory;
                        },
                        0x2e => out.append(arena, .{ .numeric_op = 0xc1 }) catch return error.OutOfMemory,
                        else => unreachable,
                    }
                    return true;
                },
                0x31, 0x30, 0x33, 0x32, 0x35, 0x34 => {
                    out.items[out.items.len - 1] = entry.val_instr;
                    if (bit_shift > 0) {
                        out.append(arena, .{ .i64_const = @intCast(bit_shift) }) catch return error.OutOfMemory;
                        out.append(arena, .{ .numeric_op = 0x88 }) catch return error.OutOfMemory; // i64.shr_u
                    }
                    switch (load_acc.opcode) {
                        0x31 => if (bit_shift < 56) {
                            out.append(arena, .{ .i64_const = 0xff }) catch return error.OutOfMemory;
                            out.append(arena, .{ .numeric_op = 0x83 }) catch return error.OutOfMemory;
                        },
                        0x30 => out.append(arena, .{ .numeric_op = 0xc2 }) catch return error.OutOfMemory,
                        0x33 => if (bit_shift < 48) {
                            out.append(arena, .{ .i64_const = 0xffff }) catch return error.OutOfMemory;
                            out.append(arena, .{ .numeric_op = 0x83 }) catch return error.OutOfMemory;
                        },
                        0x32 => out.append(arena, .{ .numeric_op = 0xc3 }) catch return error.OutOfMemory,
                        0x35 => if (bit_shift < 32) {
                            out.append(arena, .{ .i64_const = 0xffff_ffff }) catch return error.OutOfMemory;
                            out.append(arena, .{ .numeric_op = 0x83 }) catch return error.OutOfMemory;
                        },
                        0x34 => out.append(arena, .{ .numeric_op = 0xc4 }) catch return error.OutOfMemory,
                        else => unreachable,
                    }
                    return true;
                },
                else => return false,
            }
        }
    }

    return false;
}

fn forwardAndEliminateMemBlock(
    arena: std.mem.Allocator,
    list: *InstrList,
    active: *std.ArrayListUnmanaged(TrackedMemEntry),
    non_escaping_fp: ?u32,
    skip_exact_fp_store_forward: bool,
    is_epilogue_block: bool,
) Error!bool {
    var changed = false;
    var out: InstrList = .empty;
    out.ensureTotalCapacity(arena, list.items.len + 8) catch return error.OutOfMemory;

    var pending_stores: std.ArrayListUnmanaged(PendingDeadStore) = .empty;
    var any_nop_store = false;
    var just_loaded: ?struct { base_local: u32, access: MemAccessInfo } = null;

    var i: usize = 0;
    while (i < list.items.len) : (i += 1) {
        const prev_loaded = just_loaded;
        just_loaded = null;

        const inst = list.items[i];

        if (out.items.len >= 1 and out.items[out.items.len - 1] == .local_get) {
            if (decodeLoadAccess(inst)) |load_acc| {
                const base_local = out.items[out.items.len - 1].local_get;
                if (load_acc.mem_idx == 0) {
                    // Mark any potentially aliasing pending store as read (not dead)
                    for (pending_stores.items) |*ps| {
                        if (!ps.active) continue;
                        if (ps.base_local == base_local) {
                            if (memRangesOverlap(ps.offset, ps.size, load_acc.offset, load_acc.size)) {
                                ps.active = false;
                            }
                        } else if (!(non_escaping_fp != null and (ps.base_local == non_escaping_fp.? or base_local == non_escaping_fp.?))) {
                            ps.active = false;
                        }
                    }

                    // Search `active` for an entry covering `[load_acc.offset, load_acc.offset + load_acc.size)`
                    var forwarded = false;
                    var j = active.items.len;
                    while (j > 0) {
                        j -= 1;
                        const e = active.items[j];
                        if (e.base_local == base_local and
                            load_acc.offset >= e.offset and
                            load_acc.offset + load_acc.size <= e.offset + e.size)
                        {
                            if (skip_exact_fp_store_forward and non_escaping_fp != null and base_local == non_escaping_fp.? and
                                e.is_from_store and load_acc.size == e.size and e.size >= 4)
                            {
                                break;
                            }
                            if (try emitForwardedLoadValue(arena, &out, e, load_acc)) {
                                forwarded = true;
                                changed = true;
                            }
                            break;
                        }
                    }
                    if (forwarded) continue;

                    out.append(arena, inst) catch return error.OutOfMemory;
                    just_loaded = .{ .base_local = base_local, .access = load_acc };
                    continue;
                }
            }
        }

        if (decodeStoreAccess(inst)) |store_acc| {
            if (store_acc.mem_idx == 0 and out.items.len >= 2 and
                out.items[out.items.len - 2] == .local_get and
                isForwardableMemVal(out.items[out.items.len - 1], out.items[out.items.len - 2].local_get))
            {
                const base_local = out.items[out.items.len - 2].local_get;
                const val_instr = out.items[out.items.len - 1];

                // Overwrite DSE: check if an active pending store on `base_local` is completely covered
                for (pending_stores.items) |*ps| {
                    if (!ps.active) continue;
                    if (ps.base_local == base_local) {
                        if (store_acc.offset <= ps.offset and store_acc.offset + store_acc.size >= ps.offset + ps.size) {
                            ps.active = false;
                            out.items[ps.out_idx] = .nop;
                            out.items[ps.out_idx + 1] = .nop;
                            out.items[ps.out_idx + 2] = .nop;
                            any_nop_store = true;
                            changed = true;
                        } else if (memRangesOverlap(ps.offset, ps.size, store_acc.offset, store_acc.size)) {
                            ps.active = false;
                        }
                    } else if (!(non_escaping_fp != null and (ps.base_local == non_escaping_fp.? or base_local == non_escaping_fp.?))) {
                        ps.active = false;
                    }
                }

                invalidateMemEntriesForStore(active, base_local, store_acc.offset, store_acc.size, non_escaping_fp);
                active.append(arena, .{
                    .base_local = base_local,
                    .offset = store_acc.offset,
                    .size = store_acc.size,
                    .opcode = store_acc.opcode,
                    .simd_sub = store_acc.simd_sub,
                    .val_instr = val_instr,
                    .is_from_store = true,
                }) catch return error.OutOfMemory;
                pending_stores.append(arena, .{
                    .base_local = base_local,
                    .offset = store_acc.offset,
                    .size = store_acc.size,
                    .out_idx = out.items.len - 2,
                    .active = true,
                }) catch return error.OutOfMemory;
                out.append(arena, inst) catch return error.OutOfMemory;
                continue;
            } else {
                var known_base: ?u32 = null;
                if (store_acc.mem_idx == 0) {
                    if (findPrevSingleValueExprStart(out.items, out.items.len)) |val_start| {
                        if (val_start >= 1 and out.items[val_start - 1] == .local_get) {
                            known_base = out.items[val_start - 1].local_get;
                        }
                    }
                }
                for (pending_stores.items) |*ps| {
                    if (!ps.active) continue;
                    if (known_base) |kb| {
                        if (ps.base_local == kb) {
                            if (memRangesOverlap(ps.offset, ps.size, store_acc.offset, store_acc.size)) ps.active = false;
                        } else if (!(non_escaping_fp != null and (ps.base_local == non_escaping_fp.? or kb == non_escaping_fp.?))) {
                            ps.active = false;
                        }
                    } else if (!(non_escaping_fp != null and ps.base_local == non_escaping_fp.?)) {
                        ps.active = false;
                    }
                }
                invalidateMemEntriesForStore(active, known_base, store_acc.offset, store_acc.size, non_escaping_fp);
                if (known_base) |kb| {
                    if (out.items.len >= 1 and out.items[out.items.len - 1] == .local_tee) {
                        const tee_local = out.items[out.items.len - 1].local_tee;
                        if (tee_local != kb) {
                            active.append(arena, .{
                                .base_local = kb,
                                .offset = store_acc.offset,
                                .size = store_acc.size,
                                .opcode = store_acc.opcode,
                                .simd_sub = store_acc.simd_sub,
                                .val_instr = .{ .local_get = tee_local },
                                .is_from_store = true,
                            }) catch return error.OutOfMemory;
                        }
                    }
                }
                out.append(arena, inst) catch return error.OutOfMemory;
                continue;
            }
        }

        if (decodeLoadAccess(inst)) |load_acc| {
            // Non-`local.get` base load: mark potentially aliasing pending stores as read
            for (pending_stores.items) |*ps| {
                if (!ps.active) continue;
                if (!(non_escaping_fp != null and ps.base_local == non_escaping_fp.?)) {
                    ps.active = false;
                }
            }
            _ = load_acc;
        }

        switch (inst) {
            .local_set => |x| {
                invalidateMemEntriesForLocal(active, x);
                for (pending_stores.items) |*ps| {
                    if (ps.base_local == x) ps.active = false;
                }
                if (prev_loaded) |jl| {
                    if (x != jl.base_local) {
                        invalidateMemEntriesForStore(active, jl.base_local, jl.access.offset, jl.access.size, non_escaping_fp);
                        active.append(arena, .{
                            .base_local = jl.base_local,
                            .offset = jl.access.offset,
                            .size = jl.access.size,
                            .opcode = jl.access.opcode,
                            .simd_sub = jl.access.simd_sub,
                            .val_instr = .{ .local_get = x },
                            .is_from_store = false,
                        }) catch return error.OutOfMemory;
                    }
                }
                out.append(arena, inst) catch return error.OutOfMemory;
            },
            .local_tee => |x| {
                invalidateMemEntriesForLocal(active, x);
                for (pending_stores.items) |*ps| {
                    if (ps.base_local == x) ps.active = false;
                }
                if (prev_loaded) |jl| {
                    if (x != jl.base_local) {
                        invalidateMemEntriesForStore(active, jl.base_local, jl.access.offset, jl.access.size, non_escaping_fp);
                        active.append(arena, .{
                            .base_local = jl.base_local,
                            .offset = jl.access.offset,
                            .size = jl.access.size,
                            .opcode = jl.access.opcode,
                            .simd_sub = jl.access.simd_sub,
                            .val_instr = .{ .local_get = x },
                            .is_from_store = false,
                        }) catch return error.OutOfMemory;
                    }
                }
                out.append(arena, inst) catch return error.OutOfMemory;
            },
            .block => |b_in| {
                for (pending_stores.items) |*ps| ps.active = false;
                var b = b_in;
                var blk_active = active.clone(arena) catch return error.OutOfMemory;
                if (try forwardAndEliminateMemBlock(arena, &b.body, &blk_active, non_escaping_fp, skip_exact_fp_store_forward, false)) {
                    changed = true;
                }
                try invalidateClobberedMemEntries(&b.body, arena, active, non_escaping_fp);
                out.append(arena, .{ .block = b }) catch return error.OutOfMemory;
            },
            .if_ => |if_in| {
                for (pending_stores.items) |*ps| ps.active = false;
                var if_inst = if_in;
                var then_active = active.clone(arena) catch return error.OutOfMemory;
                if (try forwardAndEliminateMemBlock(arena, &if_inst.then_body, &then_active, non_escaping_fp, skip_exact_fp_store_forward, false)) {
                    changed = true;
                }
                if (if_inst.has_else) {
                    var else_active = active.clone(arena) catch return error.OutOfMemory;
                    if (try forwardAndEliminateMemBlock(arena, &if_inst.else_body, &else_active, non_escaping_fp, skip_exact_fp_store_forward, false)) {
                        changed = true;
                    }
                }
                try invalidateClobberedMemEntries(&if_inst.then_body, arena, active, non_escaping_fp);
                if (if_inst.has_else) {
                    try invalidateClobberedMemEntries(&if_inst.else_body, arena, active, non_escaping_fp);
                }
                out.append(arena, .{ .if_ = if_inst }) catch return error.OutOfMemory;
            },
            .loop => |lp_in| {
                for (pending_stores.items) |*ps| ps.active = false;
                var lp = lp_in;
                try invalidateClobberedMemEntries(&lp.body, arena, active, non_escaping_fp);
                var lp_active = active.clone(arena) catch return error.OutOfMemory;
                if (try forwardAndEliminateMemBlock(arena, &lp.body, &lp_active, non_escaping_fp, skip_exact_fp_store_forward, false)) {
                    changed = true;
                }
                out.append(arena, .{ .loop = lp }) catch return error.OutOfMemory;
            },
            .br, .br_if, .br_table, .return_, .unreachable_ => {
                for (pending_stores.items) |*ps| ps.active = false;
                out.append(arena, inst) catch return error.OutOfMemory;
            },
            .call, .return_call, .return_call_indirect => {
                for (pending_stores.items) |*ps| {
                    if (!(non_escaping_fp != null and ps.base_local == non_escaping_fp.?)) {
                        ps.active = false;
                    }
                }
                invalidateMemEntriesForCall(active, non_escaping_fp);
                out.append(arena, inst) catch return error.OutOfMemory;
            },
            .raw => |r| {
                if (r.len > 0) switch (r[0]) {
                    0x10, 0x11, 0x12, 0x13, 0x14, 0x15 => {
                        for (pending_stores.items) |*ps| {
                            if (!(non_escaping_fp != null and ps.base_local == non_escaping_fp.?)) {
                                ps.active = false;
                            }
                        }
                        invalidateMemEntriesForCall(active, non_escaping_fp);
                    },
                    0x40, 0xfb, 0xfe => {
                        for (pending_stores.items) |*ps| ps.active = false;
                        active.clearRetainingCapacity();
                    },
                    0xfc => {
                        var p: usize = 1;
                        const sub = readU32(r, &p) catch 0xff;
                        if (sub >= 0x08 and sub <= 0x0b) {
                            for (pending_stores.items) |*ps| ps.active = false;
                            active.clearRetainingCapacity();
                        }
                    },
                    0xfd => {
                        var p: usize = 1;
                        const sub = readU32(r, &p) catch 0xffff;
                        if (sub >= 0x54 and sub <= 0x5b) {
                            for (pending_stores.items) |*ps| ps.active = false;
                            if (sub >= 0x58) active.clearRetainingCapacity();
                        }
                    },
                    else => {},
                };
                out.append(arena, inst) catch return error.OutOfMemory;
            },
            else => {
                out.append(arena, inst) catch return error.OutOfMemory;
            },
        }
    }

    // Dead Frame Epilogue DSE: any pending store on `non_escaping_fp` reaching the end of the function body
    // without being read is dead because the stack frame is popped immediately after `body_end`.
    if (is_epilogue_block) {
        if (non_escaping_fp) |fp| {
            for (pending_stores.items) |*ps| {
                if (ps.active and ps.base_local == fp) {
                    ps.active = false;
                    out.items[ps.out_idx] = .nop;
                    out.items[ps.out_idx + 1] = .nop;
                    out.items[ps.out_idx + 2] = .nop;
                    any_nop_store = true;
                    changed = true;
                }
            }
        }
    }

    if (any_nop_store) {
        var write_idx: usize = 0;
        for (out.items) |item| {
            if (item != .nop) {
                out.items[write_idx] = item;
                write_idx += 1;
            }
        }
        out.items.len = write_idx;
    }

    list.* = out;
    return changed;
}

fn forwardAndEliminateMemoryOps(arena: std.mem.Allocator, root_list: *InstrList) Error!bool {
    var active: std.ArrayListUnmanaged(TrackedMemEntry) = .empty;
    if (detectShadowStackFrame(root_list.items)) |frame| {
        const body_slice = root_list.items[frame.body_start..frame.body_end];
        const fp_never_escapes = checkFpNeverEscapesToCallOrMem(body_slice, frame.fp, frame.has_epilogue);
        const non_escaping_fp: ?u32 = if (fp_never_escapes) frame.fp else null;

        // If `scalarizeShadowStackSlots` intentionally preserved a single-store + single-load full-width slot
        // on `fp` (as in `disjointFrame`), do not forward that exact full-width `fp` store to its load.
        var fp_stores: usize = 0;
        var fp_loads: usize = 0;
        if (fp_never_escapes) {
            for (body_slice, 0..) |inst, idx| {
                if (idx >= 1 and body_slice[idx - 1] == .local_get and body_slice[idx - 1].local_get == frame.fp) {
                    if (decodeLoadAccess(inst) != null) fp_loads += 1;
                }
                if (idx >= 2 and body_slice[idx - 2] == .local_get and body_slice[idx - 2].local_get == frame.fp) {
                    if (decodeStoreAccess(inst) != null) fp_stores += 1;
                }
            }
        }
        const skip_exact_fp_store_forward = fp_never_escapes and fp_stores == 1 and fp_loads == 1;

        var body_list: InstrList = .empty;
        body_list.appendSlice(arena, body_slice) catch return error.OutOfMemory;
        const self_off_changed = try foldSelfOffsetStores(arena, &body_list, frame.fp, frame.sp_save);
        const mem_changed = try forwardAndEliminateMemBlock(
            arena,
            &body_list,
            &active,
            non_escaping_fp,
            skip_exact_fp_store_forward,
            true,
        );
        if (!self_off_changed and !mem_changed) return false;

        if (!sliceUsesLocalOrEarlyExit(body_list.items, frame.fp, frame.sp_save, frame.has_epilogue) and
            (!frame.has_epilogue or !hasBranchToDepth(body_list.items, 0)))
        {
            if (frame.has_trailing_return) {
                body_list.append(arena, .return_) catch return error.OutOfMemory;
            }
            root_list.* = body_list;
        } else {
            var new_root: InstrList = .empty;
            const cap = frame.body_start + body_list.items.len + (root_list.items.len - frame.body_end);
            new_root.ensureTotalCapacity(arena, cap) catch return error.OutOfMemory;
            new_root.appendSliceAssumeCapacity(root_list.items[0..frame.body_start]);
            new_root.appendSliceAssumeCapacity(body_list.items);
            new_root.appendSliceAssumeCapacity(root_list.items[frame.body_end..]);
            root_list.* = new_root;
        }
        return true;
    }

    const self_off_changed = try foldSelfOffsetStores(arena, root_list, null, null);
    const mem_changed = try forwardAndEliminateMemBlock(arena, root_list, &active, null, false, false);
    return self_off_changed or mem_changed;
}

const SelfOffsetAncestor = struct {
    kind: enum { block, loop, if_ },
    after_slice: []const Instr,
    loop_slice: []const Instr = &.{},
    continuation_visited: bool = false,
    loop_visited: bool = false,
};

fn branchTargetReadsLocal(
    label: u32,
    local_idx: u32,
    ancestors: []SelfOffsetAncestor,
) bool {
    if (label >= ancestors.len) return false;
    const target_idx = ancestors.len - 1 - label;
    const target = &ancestors[target_idx];
    switch (target.kind) {
        .loop => {
            if (target.loop_visited) return false;
            target.loop_visited = true;
            return mayReadLocalBeforeWrite(target.loop_slice, local_idx, ancestors[0 .. target_idx + 1]);
        },
        .block, .if_ => {
            if (target.continuation_visited) return false;
            target.continuation_visited = true;
            return mayReadLocalBeforeWrite(target.after_slice, local_idx, ancestors[0..target_idx]);
        },
    }
}

fn mayReadLocalBeforeWrite(
    slice: []const Instr,
    local_idx: u32,
    ancestors: []SelfOffsetAncestor,
) bool {
    for (slice, 0..) |inst, idx| {
        switch (inst) {
            .local_get => |x| if (x == local_idx) return true,
            .local_set, .local_tee => |x| if (x == local_idx) return false,
            .return_, .unreachable_ => return false,
            .br => |label| return branchTargetReadsLocal(label, local_idx, ancestors),
            .br_if => |label| {
                if (branchTargetReadsLocal(label, local_idx, ancestors)) return true;
            },
            .br_table => |targets| {
                for (targets) |t| {
                    if (branchTargetReadsLocal(t, local_idx, ancestors)) return true;
                }
                return false;
            },
            .block => |b| {
                if (ancestors.len >= 64) return true;
                var next_ancestors: [64]SelfOffsetAncestor = undefined;
                @memcpy(next_ancestors[0..ancestors.len], ancestors);
                next_ancestors[ancestors.len] = .{
                    .kind = .block,
                    .after_slice = slice[idx + 1 ..],
                };
                if (mayReadLocalBeforeWrite(b.body.items, local_idx, next_ancestors[0 .. ancestors.len + 1])) return true;
                @memcpy(ancestors, next_ancestors[0..ancestors.len]);
                return false;
            },
            .loop => |lp| {
                if (ancestors.len >= 64) return true;
                var next_ancestors: [64]SelfOffsetAncestor = undefined;
                @memcpy(next_ancestors[0..ancestors.len], ancestors);
                next_ancestors[ancestors.len] = .{
                    .kind = .loop,
                    .after_slice = slice[idx + 1 ..],
                    .loop_slice = lp.body.items,
                    .loop_visited = true,
                };
                if (mayReadLocalBeforeWrite(lp.body.items, local_idx, next_ancestors[0 .. ancestors.len + 1])) return true;
                @memcpy(ancestors, next_ancestors[0..ancestors.len]);
                return false;
            },
            .if_ => |if_inst| {
                if (ancestors.len >= 64) return true;
                var next_ancestors: [64]SelfOffsetAncestor = undefined;
                @memcpy(next_ancestors[0..ancestors.len], ancestors);
                next_ancestors[ancestors.len] = .{
                    .kind = .if_,
                    .after_slice = slice[idx + 1 ..],
                };
                if (mayReadLocalBeforeWrite(if_inst.then_body.items, local_idx, next_ancestors[0 .. ancestors.len + 1])) {
                    return true;
                }
                const else_slice: []const Instr = if (if_inst.has_else) if_inst.else_body.items else &.{};
                if (mayReadLocalBeforeWrite(else_slice, local_idx, next_ancestors[0 .. ancestors.len + 1])) {
                    return true;
                }
                @memcpy(ancestors, next_ancestors[0..ancestors.len]);
                return false;
            },
            else => {},
        }
    }
    if (ancestors.len == 0) return false;
    const top_idx = ancestors.len - 1;
    if (ancestors[top_idx].continuation_visited) return false;
    ancestors[top_idx].continuation_visited = true;
    return mayReadLocalBeforeWrite(ancestors[top_idx].after_slice, local_idx, ancestors[0..top_idx]);
}

fn instrTouchesLocal(inst: Instr, local_idx: u32) bool {
    return switch (inst) {
        .local_get, .local_set, .local_tee => |x| x == local_idx,
        .block => |b| sliceTouchesLocal(b.body.items, local_idx),
        .loop => |lp| sliceTouchesLocal(lp.body.items, local_idx),
        .if_ => |if_inst| sliceTouchesLocal(if_inst.then_body.items, local_idx) or
            (if_inst.has_else and sliceTouchesLocal(if_inst.else_body.items, local_idx)),
        else => false,
    };
}

fn sliceTouchesLocal(slice: []const Instr, local_idx: u32) bool {
    for (slice) |inst| {
        if (instrTouchesLocal(inst, local_idx)) return true;
    }
    return false;
}

fn matchSelfOffsetUpdate(items: []const Instr, idx: usize) ?struct { base_local: u32, offset: u64 } {
    if (idx + 3 >= items.len) return null;
    if (items[idx + 3] != .local_set) return null;
    const b = items[idx + 3].local_set;
    if (items[idx + 2] != .numeric_op) return null;
    const op = items[idx + 2].numeric_op;
    if (op == 0x6a) {
        if (items[idx] == .local_get and items[idx].local_get == b and
            items[idx + 1] == .i32_const and items[idx + 1].i32_const >= 0 and items[idx + 1].i32_const <= 65536)
        {
            return .{ .base_local = b, .offset = @intCast(items[idx + 1].i32_const) };
        }
        if (items[idx + 1] == .local_get and items[idx + 1].local_get == b and
            items[idx] == .i32_const and items[idx].i32_const >= 0 and items[idx].i32_const <= 65536)
        {
            return .{ .base_local = b, .offset = @intCast(items[idx].i32_const) };
        }
    } else if (op == 0x6b) {
        if (items[idx] == .local_get and items[idx].local_get == b and
            items[idx + 1] == .i32_const and items[idx + 1].i32_const <= 0 and items[idx + 1].i32_const >= -65536)
        {
            return .{ .base_local = b, .offset = @intCast(-@as(i64, items[idx + 1].i32_const)) };
        }
    }
    return null;
}

fn foldSelfOffsetStoresInBlock(
    arena: std.mem.Allocator,
    list: *InstrList,
    ancestors: []const SelfOffsetAncestor,
    protected_fp: ?u32,
    protected_sp: ?u32,
) Error!bool {
    var changed = false;
    var any_nop = false;
    const items = list.items;
    var i: usize = 0;
    while (i + 3 < items.len) {
        if (matchSelfOffsetUpdate(items, i)) |upd| {
            const b = upd.base_local;
            const k_off = upd.offset;
            if ((protected_fp == null or b != protected_fp.?) and (protected_sp == null or b != protected_sp.?)) {
                var total_b_gets: usize = 0;
                var mem_b_gets: usize = 0;
                var last_addr_get_idx: usize = i + 3;
                var mem_indices_buf: [64]usize = undefined;
                var mem_count: usize = 0;
                var killed_in_block = false;
                var abort = false;

                var cur: usize = i + 4;
                while (cur < items.len) : (cur += 1) {
                    if (items[cur] == .local_get and items[cur].local_get == b) {
                        total_b_gets += 1;
                        continue;
                    }
                    if (decodeLoadAccess(items[cur])) |ld| {
                        if (ld.mem_idx == 0 and (ld.opcode != 0xfd or ld.simd_sub <= 0x0a) and
                            ld.offset + k_off <= std.math.maxInt(u32) and
                            cur > i + 4 and cur - 1 > last_addr_get_idx and
                            items[cur - 1] == .local_get and items[cur - 1].local_get == b)
                        {
                            if (mem_count >= mem_indices_buf.len) {
                                abort = true;
                                break;
                            }
                            mem_indices_buf[mem_count] = cur;
                            mem_count += 1;
                            mem_b_gets += 1;
                            last_addr_get_idx = cur - 1;
                        }
                        continue;
                    }
                    if (decodeStoreAccess(items[cur])) |st| {
                        if (st.mem_idx == 0 and (st.opcode != 0xfd or st.simd_sub == 0x0b) and
                            st.offset + k_off <= std.math.maxInt(u32))
                        {
                            if (findPrevSingleValueExprStart(items[i + 4 .. cur + 1], cur - (i + 4))) |rel_vs| {
                                const val_start = (i + 4) + rel_vs;
                                if (val_start > i + 4 and val_start - 1 > last_addr_get_idx and
                                    items[val_start - 1] == .local_get and items[val_start - 1].local_get == b and
                                    !sliceTouchesLocal(items[val_start..cur], b))
                                {
                                    if (mem_count >= mem_indices_buf.len) {
                                        abort = true;
                                        break;
                                    }
                                    mem_indices_buf[mem_count] = cur;
                                    mem_count += 1;
                                    mem_b_gets += 1;
                                    last_addr_get_idx = val_start - 1;
                                }
                            }
                        }
                        continue;
                    }
                    switch (items[cur]) {
                        .local_set, .local_tee => |x| {
                            if (x == b) {
                                if (total_b_gets == mem_b_gets) {
                                    killed_in_block = true;
                                } else {
                                    abort = true;
                                }
                                break;
                            }
                        },
                        .return_, .unreachable_ => {
                            if (total_b_gets == mem_b_gets) {
                                killed_in_block = true;
                            } else {
                                abort = true;
                            }
                            break;
                        },
                        .block, .loop, .if_, .br, .br_if, .br_table => break,
                        else => {},
                    }
                }

                if (!abort and mem_count > 0 and total_b_gets == mem_b_gets) {
                    var is_dead = killed_in_block;
                    if (!is_dead and ancestors.len <= 64) {
                        var anc_copy: [64]SelfOffsetAncestor = undefined;
                        @memcpy(anc_copy[0..ancestors.len], ancestors);
                        is_dead = !mayReadLocalBeforeWrite(items[cur..], b, anc_copy[0..ancestors.len]);
                    }
                    if (is_dead) {
                        for (mem_indices_buf[0..mem_count]) |mem_idx| {
                            if (decodeLoadAccess(items[mem_idx])) |ld| {
                                items[mem_idx] = try encodeLoadInstr(arena, ld, ld.align_val, ld.offset + k_off);
                            } else if (decodeStoreAccess(items[mem_idx])) |st| {
                                items[mem_idx] = try encodeStoreInstr(arena, st, st.align_val, st.offset + k_off);
                            }
                        }
                        items[i] = .nop;
                        items[i + 1] = .nop;
                        items[i + 2] = .nop;
                        items[i + 3] = .nop;
                        any_nop = true;
                        changed = true;
                        i += 4;
                        continue;
                    }
                }
            }
        }
        i += 1;
    }

    if (any_nop) {
        var write_idx: usize = 0;
        for (list.items) |item| {
            if (item != .nop) {
                list.items[write_idx] = item;
                write_idx += 1;
            }
        }
        list.items.len = write_idx;
    }

    if (ancestors.len < 64) {
        for (list.items, 0..) |*inst, idx| {
            switch (inst.*) {
                .block => |*b| {
                    var next_anc: [64]SelfOffsetAncestor = undefined;
                    @memcpy(next_anc[0..ancestors.len], ancestors);
                    next_anc[ancestors.len] = .{
                        .kind = .block,
                        .after_slice = list.items[idx + 1 ..],
                    };
                    if (try foldSelfOffsetStoresInBlock(arena, &b.body, next_anc[0 .. ancestors.len + 1], protected_fp, protected_sp)) {
                        changed = true;
                    }
                },
                .loop => |*lp| {
                    var next_anc: [64]SelfOffsetAncestor = undefined;
                    @memcpy(next_anc[0..ancestors.len], ancestors);
                    next_anc[ancestors.len] = .{
                        .kind = .loop,
                        .after_slice = list.items[idx + 1 ..],
                        .loop_slice = lp.body.items,
                    };
                    if (try foldSelfOffsetStoresInBlock(arena, &lp.body, next_anc[0 .. ancestors.len + 1], protected_fp, protected_sp)) {
                        changed = true;
                    }
                },
                .if_ => |*if_inst| {
                    var next_anc: [64]SelfOffsetAncestor = undefined;
                    @memcpy(next_anc[0..ancestors.len], ancestors);
                    next_anc[ancestors.len] = .{
                        .kind = .if_,
                        .after_slice = list.items[idx + 1 ..],
                    };
                    if (try foldSelfOffsetStoresInBlock(arena, &if_inst.then_body, next_anc[0 .. ancestors.len + 1], protected_fp, protected_sp)) {
                        changed = true;
                    }
                    if (if_inst.has_else) {
                        if (try foldSelfOffsetStoresInBlock(arena, &if_inst.else_body, next_anc[0 .. ancestors.len + 1], protected_fp, protected_sp)) {
                            changed = true;
                        }
                    }
                },
                else => {},
            }
        }
    }

    return changed;
}

fn foldSelfOffsetStores(
    arena: std.mem.Allocator,
    list: *InstrList,
    protected_fp: ?u32,
    protected_sp: ?u32,
) Error!bool {
    return foldSelfOffsetStoresInBlock(arena, list, &.{}, protected_fp, protected_sp);
}

fn moduleUsesSimd(module: *const Mod.Module) bool {
    for (module.module_types.items) |mt| {
        if (mt == .func_type) {
            for (mt.func_type.params) |vt| if (vt == .v128) return true;
            for (mt.func_type.results) |vt| if (vt == .v128) return true;
        }
    }
    for (module.globals.items) |g| {
        if (g.type.val_type == .v128) return true;
    }
    for (module.funcs.items) |*f| {
        for (f.local_types.items) |vt| if (vt == .v128) return true;
    }
    for (module.funcs.items) |*f| {
        if (f.is_import or f.code_bytes.len == 0) continue;
        if (std.mem.indexOfScalar(u8, f.code_bytes, 0xfd) == null) continue;
        var pos: usize = 0;
        while (pos < f.code_bytes.len) {
            const b = f.code_bytes[pos];
            if (b == 0x0b and pos + 1 == f.code_bytes.len) break;
            const decoded = instr.decode(f.code_bytes, &pos) catch break;
            if (decoded.prefix == 0xfd) return true;
            instr.skipImmediates(decoded.shape, f.code_bytes, &pos) catch break;
        }
    }
    return false;
}

const ConstScalarStore = struct {
    base_local: u32,
    offset: u64,
    size: u32,
    align_val: u32,
    is_const: bool,
    bytes: [8]u8 = @splat(0),
    inst_idx: usize,
};

fn decodeConstOrLocalScalarStore(items: []const Instr, idx: usize) ?ConstScalarStore {
    if (idx + 2 >= items.len) return null;
    if (items[idx] != .local_get) return null;
    const base_local = items[idx].local_get;
    const st = decodeStoreAccess(items[idx + 2]) orelse return null;
    if (st.mem_idx != 0 or st.offset > std.math.maxInt(u32) or st.size > 8 or st.opcode == 0xfd) return null;

    var res: ConstScalarStore = .{
        .base_local = base_local,
        .offset = st.offset,
        .size = st.size,
        .align_val = st.align_val,
        .is_const = true,
        .inst_idx = idx,
    };

    switch (items[idx + 1]) {
        .i32_const => |v| {
            const u: u32 = @bitCast(v);
            switch (st.opcode) {
                0x3a => res.bytes[0] = @truncate(u),
                0x3b => std.mem.writeInt(u16, res.bytes[0..2], @truncate(u), .little),
                0x36 => std.mem.writeInt(u32, res.bytes[0..4], u, .little),
                else => return null,
            }
        },
        .i64_const => |v| {
            const u: u64 = @bitCast(v);
            switch (st.opcode) {
                0x3c => res.bytes[0] = @truncate(u),
                0x3d => std.mem.writeInt(u16, res.bytes[0..2], @truncate(u), .little),
                0x3e => std.mem.writeInt(u32, res.bytes[0..4], @truncate(u), .little),
                0x37 => std.mem.writeInt(u64, res.bytes[0..8], u, .little),
                else => return null,
            }
        },
        .raw => |r| {
            if (r.len == 5 and r[0] == 0x43 and st.opcode == 0x38) {
                @memcpy(res.bytes[0..4], r[1..5]);
            } else if (r.len == 9 and r[0] == 0x44 and st.opcode == 0x39) {
                @memcpy(res.bytes[0..8], r[1..9]);
            } else {
                return null;
            }
        },
        .local_get => |val_local| {
            if (val_local == base_local) return null;
            switch (st.opcode) {
                0x36...0x3e => res.is_const = false,
                else => return null,
            }
        },
        else => return null,
    }
    return res;
}

fn sliceHasDirectCall(slice: []const Instr) bool {
    for (slice) |inst| {
        switch (inst) {
            .call, .return_call => return true,
            .block => |b| if (sliceHasDirectCall(b.body.items)) return true,
            .loop => |lp| if (sliceHasDirectCall(lp.body.items)) return true,
            .if_ => |if_inst| {
                if (sliceHasDirectCall(if_inst.then_body.items)) return true;
                if (if_inst.has_else and sliceHasDirectCall(if_inst.else_body.items)) return true;
            },
            else => {},
        }
    }
    return false;
}

fn coalesceConstantStoresInBlock(
    arena: std.mem.Allocator,
    list: *InstrList,
    module: *const Mod.Module,
    has_simd_cache: *?bool,
    skip_local: ?u32,
) Error!bool {
    var changed = false;
    for (list.items) |*inst| {
        switch (inst.*) {
            .block => |*b| {
                if (try coalesceConstantStoresInBlock(arena, &b.body, module, has_simd_cache, skip_local)) changed = true;
            },
            .loop => |*lp| {
                if (try coalesceConstantStoresInBlock(arena, &lp.body, module, has_simd_cache, skip_local)) changed = true;
            },
            .if_ => |*if_inst| {
                if (try coalesceConstantStoresInBlock(arena, &if_inst.then_body, module, has_simd_cache, skip_local)) changed = true;
                if (if_inst.has_else) {
                    if (try coalesceConstantStoresInBlock(arena, &if_inst.else_body, module, has_simd_cache, skip_local)) changed = true;
                }
            },
            else => {},
        }
    }

    const items = list.items;
    if (items.len < 6) return changed;

    var out: InstrList = .empty;
    out.ensureTotalCapacity(arena, items.len) catch return error.OutOfMemory;
    var block_changed = false;

    var i: usize = 0;
    while (i < items.len) {
        const first = decodeConstOrLocalScalarStore(items, i) orelse {
            out.append(arena, items[i]) catch return error.OutOfMemory;
            i += 1;
            continue;
        };
        if (!first.is_const or (skip_local != null and first.base_local == skip_local.?)) {
            out.appendSlice(arena, items[i .. i + 3]) catch return error.OutOfMemory;
            i += 3;
            continue;
        }

        var stores: std.ArrayListUnmanaged(ConstScalarStore) = .empty;
        stores.append(arena, first) catch return error.OutOfMemory;

        var pos = i + 3;
        while (pos < items.len) : (pos += 3) {
            const next = decodeConstOrLocalScalarStore(items, pos) orelse break;
            if (next.base_local != first.base_local) break;
            var overlaps = false;
            for (stores.items) |prev| {
                if (memRangesOverlap(prev.offset, prev.size, next.offset, next.size)) {
                    overlaps = true;
                    break;
                }
            }
            if (overlaps) break;
            stores.append(arena, next) catch return error.OutOfMemory;
        }

        while (stores.items.len > 0 and !stores.items[stores.items.len - 1].is_const) {
            _ = stores.pop();
        }

        var const_indices: std.ArrayListUnmanaged(usize) = .empty;
        for (stores.items, 0..) |st, s_idx| {
            if (st.is_const) {
                const_indices.append(arena, s_idx) catch return error.OutOfMemory;
            }
        }

        if (const_indices.items.len < 2) {
            out.appendSlice(arena, items[i .. i + 3]) catch return error.OutOfMemory;
            i += 3;
            continue;
        }

        // Sort `const_indices` by ascending offset.
        const c_idxs = const_indices.items;
        for (1..c_idxs.len) |m| {
            const key = c_idxs[m];
            const key_off = stores.items[key].offset;
            var n = m;
            while (n > 0 and stores.items[c_idxs[n - 1]].offset > key_off) : (n -= 1) {
                c_idxs[n] = c_idxs[n - 1];
            }
            c_idxs[n] = key;
        }

        const consumed = arena.alloc(bool, stores.items.len) catch return error.OutOfMemory;
        @memset(consumed, false);
        const leader_group_start = arena.alloc(?usize, stores.items.len) catch return error.OutOfMemory;
        @memset(leader_group_start, null);
        const leader_group_end = arena.alloc(usize, stores.items.len) catch return error.OutOfMemory;
        @memset(leader_group_end, 0);

        var any_group_coalesced = false;
        var g_start: usize = 0;
        while (g_start < c_idxs.len) {
            var g_end = g_start + 1;
            var total_len: usize = stores.items[c_idxs[g_start]].size;
            while (g_end < c_idxs.len) {
                const prev_st = stores.items[c_idxs[g_end - 1]];
                const cur_st = stores.items[c_idxs[g_end]];
                if (cur_st.offset != prev_st.offset + prev_st.size) break;
                total_len += cur_st.size;
                g_end += 1;
            }

            const grp = c_idxs[g_start..g_end];
            if (grp.len >= 2) {
                const has_simd = if (total_len >= 16) blk: {
                    if (has_simd_cache.*) |cached| break :blk cached;
                    const computed = moduleUsesSimd(module);
                    has_simd_cache.* = computed;
                    break :blk computed;
                } else false;

                var new_store_count: usize = 0;
                var rel: usize = 0;
                while (rel < total_len) {
                    const rem = total_len - rel;
                    const chunk_size: usize = if (rem >= 16 and has_simd)
                        16
                    else if (rem >= 8)
                        8
                    else if (rem >= 4)
                        4
                    else if (rem >= 2)
                        2
                    else
                        1;
                    new_store_count += 1;
                    rel += chunk_size;
                }

                if (new_store_count < grp.len) {
                    var min_s_idx = grp[0];
                    for (grp[1..]) |s_idx| {
                        if (s_idx < min_s_idx) min_s_idx = s_idx;
                    }
                    for (grp) |s_idx| {
                        consumed[s_idx] = true;
                    }
                    leader_group_start[min_s_idx] = g_start;
                    leader_group_end[min_s_idx] = g_end;
                    any_group_coalesced = true;
                }
            }
            g_start = g_end;
        }

        if (!any_group_coalesced) {
            const run_inst_len = stores.items.len * 3;
            out.appendSlice(arena, items[i .. i + run_inst_len]) catch return error.OutOfMemory;
            i += run_inst_len;
            continue;
        }

        block_changed = true;
        const has_simd = has_simd_cache.* orelse false;
        for (stores.items, 0..) |st, s_idx| {
            if (leader_group_start[s_idx]) |gs| {
                const ge = leader_group_end[s_idx];
                const grp = c_idxs[gs..ge];
                const first_grp_st = stores.items[grp[0]];
                const start_off = first_grp_st.offset;
                const a0 = first_grp_st.align_val;

                var total_len: usize = 0;
                for (grp) |g_idx| total_len += stores.items[g_idx].size;
                const byte_buf = arena.alloc(u8, total_len) catch return error.OutOfMemory;
                var write_pos: usize = 0;
                for (grp) |g_idx| {
                    const gst = stores.items[g_idx];
                    @memcpy(byte_buf[write_pos .. write_pos + gst.size], gst.bytes[0..gst.size]);
                    write_pos += gst.size;
                }

                var rel: usize = 0;
                while (rel < total_len) {
                    const rem = total_len - rel;
                    const chunk_size: usize = if (rem >= 16 and has_simd)
                        16
                    else if (rem >= 8)
                        8
                    else if (rem >= 4)
                        4
                    else if (rem >= 2)
                        2
                    else
                        1;
                    const cur_off = start_off + rel;

                    // If `[cur_off, cur_off + chunk_size)` is a single original store, keep it unchanged.
                    var single_orig_inst_idx: ?usize = null;
                    var exact_align: ?u32 = null;
                    for (grp) |g_idx| {
                        const gst = stores.items[g_idx];
                        if (gst.offset == cur_off) {
                            exact_align = gst.align_val;
                            if (gst.size == chunk_size) {
                                single_orig_inst_idx = gst.inst_idx;
                            }
                            break;
                        }
                    }

                    if (single_orig_inst_idx) |orig_idx| {
                        out.appendSlice(arena, items[orig_idx .. orig_idx + 3]) catch return error.OutOfMemory;
                        rel += chunk_size;
                        continue;
                    }

                    const from_a0: u32 = if (rel == 0) a0 else @min(a0, @as(u32, @ctz(rel)));
                    const base_align: u32 = if (exact_align) |ea| @max(from_a0, ea) else from_a0;

                    out.append(arena, .{ .local_get = first.base_local }) catch return error.OutOfMemory;
                    switch (chunk_size) {
                        16 => {
                            const eff_align = @min(@as(u32, 4), base_align);
                            const v128_raw = arena.alloc(u8, 18) catch return error.OutOfMemory;
                            v128_raw[0] = 0xfd;
                            v128_raw[1] = 0x0c;
                            @memcpy(v128_raw[2..18], byte_buf[rel .. rel + 16]);
                            out.append(arena, .{ .raw = v128_raw }) catch return error.OutOfMemory;
                            const store_inst = try encodeStoreInstr(
                                arena,
                                .{ .opcode = 0xfd, .simd_sub = 0x0b, .align_val = eff_align, .mem_idx = 0, .offset = cur_off, .size = 16 },
                                eff_align,
                                cur_off,
                            );
                            out.append(arena, store_inst) catch return error.OutOfMemory;
                        },
                        8 => {
                            const eff_align = @min(@as(u32, 3), base_align);
                            const v64: i64 = std.mem.readInt(i64, byte_buf[rel..][0..8], .little);
                            out.append(arena, .{ .i64_const = v64 }) catch return error.OutOfMemory;
                            const store_inst = try encodeStoreInstr(
                                arena,
                                .{ .opcode = 0x37, .align_val = eff_align, .mem_idx = 0, .offset = cur_off, .size = 8 },
                                eff_align,
                                cur_off,
                            );
                            out.append(arena, store_inst) catch return error.OutOfMemory;
                        },
                        4 => {
                            const eff_align = @min(@as(u32, 2), base_align);
                            const v32: i32 = std.mem.readInt(i32, byte_buf[rel..][0..4], .little);
                            out.append(arena, .{ .i32_const = v32 }) catch return error.OutOfMemory;
                            const store_inst = try encodeStoreInstr(
                                arena,
                                .{ .opcode = 0x36, .align_val = eff_align, .mem_idx = 0, .offset = cur_off, .size = 4 },
                                eff_align,
                                cur_off,
                            );
                            out.append(arena, store_inst) catch return error.OutOfMemory;
                        },
                        2 => {
                            const eff_align = @min(@as(u32, 1), base_align);
                            const v16: i16 = std.mem.readInt(i16, byte_buf[rel..][0..2], .little);
                            out.append(arena, .{ .i32_const = v16 }) catch return error.OutOfMemory;
                            const store_inst = try encodeStoreInstr(
                                arena,
                                .{ .opcode = 0x3b, .align_val = eff_align, .mem_idx = 0, .offset = cur_off, .size = 2 },
                                eff_align,
                                cur_off,
                            );
                            out.append(arena, store_inst) catch return error.OutOfMemory;
                        },
                        1 => {
                            const v8: i8 = @bitCast(byte_buf[rel]);
                            out.append(arena, .{ .i32_const = v8 }) catch return error.OutOfMemory;
                            const store_inst = try encodeStoreInstr(
                                arena,
                                .{ .opcode = 0x3a, .align_val = 0, .mem_idx = 0, .offset = cur_off, .size = 1 },
                                0,
                                cur_off,
                            );
                            out.append(arena, store_inst) catch return error.OutOfMemory;
                        },
                        else => unreachable,
                    }
                    rel += chunk_size;
                }
            } else if (!consumed[s_idx]) {
                out.appendSlice(arena, items[st.inst_idx .. st.inst_idx + 3]) catch return error.OutOfMemory;
            }
        }

        i += stores.items.len * 3;
    }

    if (block_changed) {
        list.* = out;
        changed = true;
    }
    return changed;
}

fn coalesceConstantStores(
    arena: std.mem.Allocator,
    module: *const Mod.Module,
    root_list: *InstrList,
    is_post_inline: bool,
) Error!bool {
    var skip_local: ?u32 = null;
    if (!is_post_inline) {
        if (detectShadowStackFrame(root_list.items)) |frame| {
            if (sliceHasDirectCall(root_list.items[frame.body_start..frame.body_end])) {
                skip_local = frame.fp;
            }
        }
    }
    var has_simd_cache: ?bool = null;
    return coalesceConstantStoresInBlock(arena, root_list, module, &has_simd_cache, skip_local);
}

const LoopStoreInfo = struct {
    base_local: u32,
    offset: u64,
    size: u32,
};

const LoopSideEffects = struct {
    modified_locals: std.AutoHashMapUnmanaged(u32, void) = .empty,
    local_write_counts: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    modified_globals: std.AutoHashMapUnmanaged(u32, void) = .empty,
    stores: std.ArrayListUnmanaged(LoopStoreInfo) = .empty,
    has_call_or_barrier: bool = false,
    has_unknown_store: bool = false,
};

fn collectLoopLocalAndGlobalWrites(
    slice: []const Instr,
    arena: std.mem.Allocator,
    effects: *LoopSideEffects,
) Error!void {
    for (slice) |inst| {
        switch (inst) {
            .local_set, .local_tee => |x| {
                effects.modified_locals.put(arena, x, {}) catch return error.OutOfMemory;
                const gop = effects.local_write_counts.getOrPut(arena, x) catch return error.OutOfMemory;
                if (!gop.found_existing) gop.value_ptr.* = 0;
                gop.value_ptr.* += 1;
            },
            .raw => |r| if (r.len > 0 and r[0] == 0x24) {
                var p: usize = 1;
                if (readU32(r, &p)) |g| {
                    effects.modified_globals.put(arena, g, {}) catch return error.OutOfMemory;
                } else |_| {
                    effects.has_call_or_barrier = true;
                }
            },
            .block => |b| try collectLoopLocalAndGlobalWrites(b.body.items, arena, effects),
            .loop => |lp| try collectLoopLocalAndGlobalWrites(lp.body.items, arena, effects),
            .if_ => |if_inst| {
                try collectLoopLocalAndGlobalWrites(if_inst.then_body.items, arena, effects);
                if (if_inst.has_else) try collectLoopLocalAndGlobalWrites(if_inst.else_body.items, arena, effects);
            },
            else => {},
        }
    }
}

fn collectLoopMemoryEffects(
    slice: []const Instr,
    arena: std.mem.Allocator,
    effects: *LoopSideEffects,
) Error!void {
    for (slice, 0..) |inst, idx| {
        if (decodeStoreAccess(inst)) |store_acc| {
            if (store_acc.mem_idx != 0) {
                effects.has_unknown_store = true;
                continue;
            }
            if (findPrevSingleValueExprStart(slice, idx)) |val_start| {
                if (val_start >= 1 and slice[val_start - 1] == .local_get) {
                    const b = slice[val_start - 1].local_get;
                    if (!effects.modified_locals.contains(b)) {
                        effects.stores.append(arena, .{
                            .base_local = b,
                            .offset = store_acc.offset,
                            .size = store_acc.size,
                        }) catch return error.OutOfMemory;
                        continue;
                    }
                } else if (val_start >= 3 and
                    slice[val_start - 3] == .local_get and
                    slice[val_start - 2] == .i32_const and
                    slice[val_start - 2].i32_const >= 0 and
                    slice[val_start - 1] == .numeric_op and
                    slice[val_start - 1].numeric_op == 0x6a)
                {
                    const b = slice[val_start - 3].local_get;
                    if (!effects.modified_locals.contains(b)) {
                        effects.stores.append(arena, .{
                            .base_local = b,
                            .offset = store_acc.offset + @as(u64, @intCast(slice[val_start - 2].i32_const)),
                            .size = store_acc.size,
                        }) catch return error.OutOfMemory;
                        continue;
                    }
                }
            }
            effects.has_unknown_store = true;
            continue;
        }
        switch (inst) {
            .call, .return_call, .return_call_indirect => effects.has_call_or_barrier = true,
            .block => |b| try collectLoopMemoryEffects(b.body.items, arena, effects),
            .loop => |lp| try collectLoopMemoryEffects(lp.body.items, arena, effects),
            .if_ => |if_inst| {
                try collectLoopMemoryEffects(if_inst.then_body.items, arena, effects);
                if (if_inst.has_else) try collectLoopMemoryEffects(if_inst.else_body.items, arena, effects);
            },
            .raw => |r| if (r.len > 0) switch (r[0]) {
                0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x40, 0xfb, 0xfe => effects.has_call_or_barrier = true,
                0xfc => {
                    var p: usize = 1;
                    const sub = readU32(r, &p) catch {
                        effects.has_call_or_barrier = true;
                        continue;
                    };
                    if (sub >= 0x08 and sub <= 0x0b) effects.has_call_or_barrier = true;
                },
                else => {},
            },
            else => {},
        }
    }
}

fn getLocalValType(module: *const Mod.Module, func: *const Mod.Func, local_idx: u32) ?types.ValType {
    if (func.decl.type_var.index >= module.module_types.items.len) return null;
    const params = module.module_types.items[func.decl.type_var.index].func_type.params;
    if (local_idx < params.len) return params[local_idx];
    const rel = local_idx - @as(u32, @intCast(params.len));
    if (rel < func.local_types.items.len) return func.local_types.items[rel];
    return null;
}

fn inferExprValType(cand: []const Instr, module: *const Mod.Module, func: *const Mod.Func) ?types.ValType {
    var end = cand.len;
    while (end > 0 and cand[end - 1] == .nop) end -= 1;
    if (end == 0) return null;
    return switch (cand[end - 1]) {
        .i32_const => .i32,
        .i64_const => .i64,
        .local_get => |l| getLocalValType(module, func, l),
        .numeric_op => |op| switch (op) {
            0x45...0x78, 0xa7...0xab, 0xbc, 0xc0, 0xc1 => .i32,
            0x79...0x8a, 0xac...0xb1, 0xbd, 0xc2...0xc4 => .i64,
            0x8b...0x98, 0xb2...0xb6, 0xbe => .f32,
            0x99...0xa6, 0xb7...0xbb, 0xbf => .f64,
            else => null,
        },
        .raw => |r| if (r.len > 0) switch (r[0]) {
            0x43 => .f32,
            0x44 => .f64,
            0x28, 0x2c...0x2f => .i32,
            0x29, 0x30...0x35 => .i64,
            0x2a => .f32,
            0x2b => .f64,
            0x23 => blk: {
                var p: usize = 1;
                const g = readU32(r, &p) catch break :blk null;
                if (g < module.globals.items.len) break :blk module.globals.items[g].type.val_type;
                break :blk null;
            },
            0x1b => blk: {
                const c = findPrevSingleValueExprStart(cand, end - 1) orelse break :blk null;
                const v2 = findPrevSingleValueExprStart(cand, c) orelse break :blk null;
                break :blk inferExprValType(cand[0..v2], module, func) orelse inferExprValType(cand[0..c], module, func);
            },
            0xfc => blk: {
                var p: usize = 1;
                const sub = readU32(r, &p) catch break :blk null;
                break :blk switch (sub) {
                    0x00...0x03 => .i32,
                    0x04...0x07 => .i64,
                    else => null,
                };
            },
            0xfd => blk: {
                var p: usize = 1;
                const sub = readU32(r, &p) catch break :blk null;
                break :blk switch (sub) {
                    0x15, 0x16, 0x18, 0x19, 0x1b, 0x53, 0x63, 0x64, 0x83, 0x84, 0xa3, 0xa4, 0xc3, 0xc4 => .i32,
                    0x1d => .i64,
                    0x1f => .f32,
                    0x21 => .f64,
                    else => .v128,
                };
            },
            else => null,
        } else null,
        else => null,
    };
}

fn isLoopInvariantExpr(
    cand: []const Instr,
    effects: *const LoopSideEffects,
    allow_loads_and_globals: bool,
    non_escaping_fp: ?u32,
) bool {
    for (cand, 0..) |inst, idx| {
        if (decodeLoadAccess(inst)) |load_acc| {
            if (!allow_loads_and_globals) return false;
            if (effects.has_call_or_barrier or effects.has_unknown_store) return false;
            if (load_acc.mem_idx != 0) return false;

            var base_local: ?u32 = null;
            var eff_offset: u64 = load_acc.offset;
            if (idx >= 1 and cand[idx - 1] == .local_get) {
                base_local = cand[idx - 1].local_get;
            } else if (idx >= 3 and
                cand[idx - 3] == .local_get and
                cand[idx - 2] == .i32_const and
                cand[idx - 2].i32_const >= 0 and
                cand[idx - 1] == .numeric_op and
                cand[idx - 1].numeric_op == 0x6a)
            {
                base_local = cand[idx - 3].local_get;
                eff_offset += @as(u64, @intCast(cand[idx - 2].i32_const));
            }
            const b = base_local orelse return false;
            if (effects.modified_locals.contains(b)) return false;

            for (effects.stores.items) |s| {
                if (s.base_local == b) {
                    if (memRangesOverlap(eff_offset, load_acc.size, s.offset, s.size)) return false;
                } else if (!(non_escaping_fp != null and (b == non_escaping_fp.? or s.base_local == non_escaping_fp.?))) {
                    return false;
                }
            }
            continue;
        }

        switch (inst) {
            .nop, .i32_const, .i64_const => {},
            .local_get => |l| if (effects.modified_locals.contains(l)) return false,
            .local_set, .local_tee => return false,
            .numeric_op => |op| switch (op) {
                // Trapping integer div/rem and float-to-int truncations cannot be hoisted speculatively
                0x6d...0x70, 0x7f...0x82, 0xa8...0xab, 0xae...0xb1 => return false,
                0x45...0x6c, 0x71...0x7e, 0x83...0xa7, 0xac, 0xad, 0xb2...0xc4 => {},
                else => return false,
            },
            .raw => |r| {
                if (r.len == 0) return false;
                switch (r[0]) {
                    0x1b, 0x43, 0x44 => {},
                    0x23 => {
                        if (!allow_loads_and_globals or effects.has_call_or_barrier) return false;
                        var p: usize = 1;
                        const g = readU32(r, &p) catch return false;
                        if (effects.modified_globals.contains(g)) return false;
                    },
                    0xfc => {
                        var p: usize = 1;
                        const sub = readU32(r, &p) catch return false;
                        if (sub > 0x07) return false;
                    },
                    0xfd => {
                        var p: usize = 1;
                        const sub = readU32(r, &p) catch return false;
                        if (sub < 0x0c or (sub >= 0x54 and sub <= 0x5b)) return false;
                    },
                    else => return false,
                }
            },
            else => return false,
        }
    }
    return true;
}

fn isLoopPrefixTerminator(inst: Instr) bool {
    if (decodeStoreAccess(inst) != null) return true;
    return switch (inst) {
        .block, .loop, .if_, .br, .br_if, .br_table, .return_, .unreachable_, .call, .return_call, .return_call_indirect => true,
        .raw => |r| r.len > 0 and switch (r[0]) {
            0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x24, 0x40, 0xfb, 0xfc, 0xfe => true,
            else => false,
        },
        else => false,
    };
}

fn allocateScratchLocal(module: *const Mod.Module, func: *Mod.Func, val_type: types.ValType) Error!u32 {
    const param_count: u32 = if (func.decl.type_var.index < module.module_types.items.len)
        @intCast(module.module_types.items[func.decl.type_var.index].func_type.params.len)
    else
        0;
    const new_idx: u32 = param_count + @as(u32, @intCast(func.local_types.items.len));
    if (func.local_type_idxs.items.len == func.local_types.items.len and func.local_type_idxs.items.len > 0) {
        func.local_type_idxs.append(module.allocator, types.invalid_index) catch return error.OutOfMemory;
    } else {
        func.local_type_idxs.clearRetainingCapacity();
    }
    func.local_types.append(module.allocator, val_type) catch return error.OutOfMemory;
    return new_idx;
}

fn hoistLoopInvariantInBlock(
    arena: std.mem.Allocator,
    module: *const Mod.Module,
    func: *Mod.Func,
    list: *InstrList,
    non_escaping_fp: ?u32,
) Error!bool {
    var changed = false;
    var out: InstrList = .empty;
    out.ensureTotalCapacity(arena, list.items.len + 8) catch return error.OutOfMemory;

    for (list.items) |inst| {
        switch (inst) {
            .block => |b_in| {
                var b = b_in;
                if (try hoistLoopInvariantInBlock(arena, module, func, &b.body, non_escaping_fp)) changed = true;
                out.append(arena, .{ .block = b }) catch return error.OutOfMemory;
            },
            .if_ => |if_in| {
                var if_inst = if_in;
                if (try hoistLoopInvariantInBlock(arena, module, func, &if_inst.then_body, non_escaping_fp)) changed = true;
                if (if_inst.has_else) {
                    if (try hoistLoopInvariantInBlock(arena, module, func, &if_inst.else_body, non_escaping_fp)) changed = true;
                }
                out.append(arena, .{ .if_ = if_inst }) catch return error.OutOfMemory;
            },
            .loop => |lp_in| {
                var lp = lp_in;
                if (try hoistLoopInvariantInBlock(arena, module, func, &lp.body, non_escaping_fp)) changed = true;

                var effects: LoopSideEffects = .{};
                try collectLoopLocalAndGlobalWrites(lp.body.items, arena, &effects);
                try collectLoopMemoryEffects(lp.body.items, arena, &effects);

                // First: hoist top-level `<invariant_expr>; local.set X` in the unconditional loop entry prefix
                // when `X` is assigned only once in the loop and not read earlier in the prefix.
                var scan_idx: usize = 0;
                while (scan_idx < lp.body.items.len) {
                    const item = lp.body.items[scan_idx];
                    if (isLoopPrefixTerminator(item)) break;
                    if (item == .local_set) {
                        const target_local = item.local_set;
                        if ((effects.local_write_counts.get(target_local) orelse 0) == 1) {
                            if (findPrevSingleValueExprStart(lp.body.items, scan_idx)) |expr_start| {
                                const expr_slice = lp.body.items[expr_start..scan_idx];
                                if (expr_slice.len >= 1 and
                                    !sliceReferencesLocal(lp.body.items[0..expr_start], target_local) and
                                    isLoopInvariantExpr(expr_slice, &effects, true, non_escaping_fp))
                                {
                                    out.appendSlice(arena, expr_slice) catch return error.OutOfMemory;
                                    out.append(arena, .{ .local_set = target_local }) catch return error.OutOfMemory;

                                    const remove_count = (scan_idx + 1) - expr_start;
                                    std.mem.copyForwards(
                                        Instr,
                                        lp.body.items[expr_start .. lp.body.items.len - remove_count],
                                        lp.body.items[scan_idx + 1 ..],
                                    );
                                    lp.body.items.len -= remove_count;
                                    _ = effects.modified_locals.remove(target_local);
                                    changed = true;
                                    scan_idx = expr_start;
                                    continue;
                                }
                            }
                        }
                    }
                    scan_idx += 1;
                }

                // Compute `prefix_end` (before first branch, conditional, call, or store)
                var prefix_end: usize = 0;
                while (prefix_end < lp.body.items.len and !isLoopPrefixTerminator(lp.body.items[prefix_end])) {
                    prefix_end += 1;
                }

                // Second: scan maximal single-value expressions in `lp.body.items` (in the unconditional prefix,
                // both pure expressions and proven-safe invariant loads are eligible; after `prefix_end`,
                // multi-op pure arithmetic expressions `>= 2` ops with no loads/globals are also eligible).
                const HoistedChunk = struct {
                    start: usize,
                    end: usize,
                    scratch_local: u32,
                };
                var chunks: std.ArrayListUnmanaged(HoistedChunk) = .empty;
                var end_idx: usize = lp.body.items.len;
                while (end_idx >= 2) {
                    const allow_loads = end_idx <= prefix_end;
                    if (findPrevSingleValueExprStart(lp.body.items, end_idx)) |start_idx| {
                        const cand = lp.body.items[start_idx..end_idx];
                        if (cand.len >= 2 and isLoopInvariantExpr(cand, &effects, allow_loads, non_escaping_fp)) {
                            if (inferExprValType(cand, module, func)) |val_type| {
                                const scratch_local = try allocateScratchLocal(module, func, val_type);
                                chunks.append(arena, .{
                                    .start = start_idx,
                                    .end = end_idx,
                                    .scratch_local = scratch_local,
                                }) catch return error.OutOfMemory;
                                end_idx = start_idx;
                                continue;
                            }
                        }
                    }
                    end_idx -= 1;
                }

                if (chunks.items.len > 0) {
                    // Emit preheader computations in forward order (`chunks` was collected from high `end_idx` to low)
                    var ci = chunks.items.len;
                    while (ci > 0) {
                        ci -= 1;
                        const ch = chunks.items[ci];
                        out.appendSlice(arena, lp.body.items[ch.start..ch.end]) catch return error.OutOfMemory;
                        out.append(arena, .{ .local_set = ch.scratch_local }) catch return error.OutOfMemory;
                    }

                    // Rewrite `lp.body` replacing each `[ch.start..ch.end)` with `.local_get = ch.scratch_local`
                    var new_lp_body: InstrList = .empty;
                    new_lp_body.ensureTotalCapacity(arena, lp.body.items.len) catch return error.OutOfMemory;
                    var cursor: usize = 0;
                    var ri = chunks.items.len;
                    while (ri > 0) {
                        ri -= 1;
                        const ch = chunks.items[ri];
                        new_lp_body.appendSliceAssumeCapacity(lp.body.items[cursor..ch.start]);
                        new_lp_body.appendAssumeCapacity(.{ .local_get = ch.scratch_local });
                        cursor = ch.end;
                    }
                    new_lp_body.appendSliceAssumeCapacity(lp.body.items[cursor..]);
                    lp.body = new_lp_body;
                    changed = true;
                }

                out.append(arena, .{ .loop = lp }) catch return error.OutOfMemory;
            },
            else => {
                out.append(arena, inst) catch return error.OutOfMemory;
            },
        }
    }

    list.* = out;
    return changed;
}

fn hoistLoopInvariantCode(
    arena: std.mem.Allocator,
    module: *const Mod.Module,
    func: *Mod.Func,
    root_list: *InstrList,
    optimize_mode: OptimizeMode,
) Error!bool {
    _ = optimize_mode;
    var non_escaping_fp: ?u32 = null;
    if (detectShadowStackFrame(root_list.items)) |frame| {
        const body_slice = root_list.items[frame.body_start..frame.body_end];
        if (checkFpNeverEscapesToCallOrMem(body_slice, frame.fp, frame.has_epilogue)) {
            non_escaping_fp = frame.fp;
        }
    }
    return hoistLoopInvariantInBlock(arena, module, func, root_list, non_escaping_fp);
}

fn isPropagatableInstr(inst: Instr) bool {
    return switch (inst) {
        .i32_const, .i64_const, .ref_func, .local_get => true,
        .raw => |r| r.len > 0 and switch (r[0]) {
            0x43, 0x44, 0xd0 => true,
            else => false,
        },
        else => false,
    };
}

fn isLargeConstantInstr(inst: Instr) bool {
    return switch (inst) {
        .i32_const => |v| v < -64 or v > 63,
        .i64_const => |v| v < -64 or v > 63,
        .raw => |r| r.len > 0 and (r[0] == 0x43 or r[0] == 0x44),
        else => false,
    };
}

fn invalidateLocal(bindings: *std.AutoHashMapUnmanaged(u32, Instr), local_idx: u32) void {
    _ = bindings.remove(local_idx);
    while (true) {
        var victim: ?u32 = null;
        var it = bindings.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == .local_get and entry.value_ptr.local_get == local_idx) {
                victim = entry.key_ptr.*;
                break;
            }
        }
        if (victim) |k| {
            _ = bindings.remove(k);
        } else {
            break;
        }
    }
}

fn collectModifiedLocals(
    list: *const InstrList,
    arena: std.mem.Allocator,
    modified: *std.AutoHashMapUnmanaged(u32, void),
) Error!void {
    for (list.items) |inst| {
        switch (inst) {
            .local_set => |x| modified.put(arena, x, {}) catch return error.OutOfMemory,
            .local_tee => |x| modified.put(arena, x, {}) catch return error.OutOfMemory,
            .block => |*b| try collectModifiedLocals(&b.body, arena, modified),
            .loop => |*l| try collectModifiedLocals(&l.body, arena, modified),
            .if_ => |*i| {
                try collectModifiedLocals(&i.then_body, arena, modified);
                if (i.has_else) try collectModifiedLocals(&i.else_body, arena, modified);
            },
            else => {},
        }
    }
}

fn simplifyLocalsBlock(
    arena: std.mem.Allocator,
    list: *InstrList,
    bindings: *std.AutoHashMapUnmanaged(u32, Instr),
    optimize_mode: OptimizeMode,
    initial_reads: *const std.AutoHashMapUnmanaged(u32, u32),
) Error!bool {
    var changed = false;
    var out: InstrList = .empty;
    out.ensureTotalCapacity(arena, list.items.len) catch return error.OutOfMemory;

    for (list.items) |inst| {
        switch (inst) {
            .local_get => |idx| {
                if (out.items.len > 0 and out.items[out.items.len - 1] == .local_set and out.items[out.items.len - 1].local_set == idx) {
                    if (bindings.get(idx)) |repl| {
                        out.append(arena, repl) catch return error.OutOfMemory;
                        changed = true;
                        continue;
                    } else {
                        out.items[out.items.len - 1] = .{ .local_tee = idx };
                        changed = true;
                        continue;
                    }
                }
                if (bindings.get(idx)) |repl| {
                    out.append(arena, repl) catch return error.OutOfMemory;
                    changed = true;
                    continue;
                }
                out.append(arena, inst) catch return error.OutOfMemory;
                continue;
            },
            .local_set => |x| {
                if (out.items.len > 0 and out.items[out.items.len - 1] == .local_get and out.items[out.items.len - 1].local_get == x) {
                    _ = out.pop();
                    changed = true;
                    continue;
                }
                var k: usize = 0;
                while (k < out.items.len and out.items[out.items.len - 1 - k] == .local_set) : (k += 1) {}
                var producer: ?Instr = null;
                if (out.items.len >= 2 * k + 1) {
                    var all_prop = true;
                    for (out.items[out.items.len - 2 * k - 1 .. out.items.len - k]) |item| {
                        if (!isPropagatableInstr(item)) {
                            all_prop = false;
                            break;
                        }
                    }
                    if (all_prop) {
                        const cand = out.items[out.items.len - 2 * k - 1];
                        var valid = true;
                        if (cand == .local_get) {
                            const src = cand.local_get;
                            if (src == x) {
                                valid = false;
                            } else {
                                for (out.items[out.items.len - k ..]) |set_item| {
                                    if (set_item.local_set == src) {
                                        valid = false;
                                        break;
                                    }
                                }
                            }
                        }
                        if (valid) producer = cand;
                    }
                }
                invalidateLocal(bindings, x);
                if (producer) |prod| {
                    const allow_bind = !(optimize_mode == .small and
                        isLargeConstantInstr(prod) and
                        (initial_reads.get(x) orelse 0) > 1);
                    if (allow_bind) {
                        bindings.put(arena, x, prod) catch return error.OutOfMemory;
                    }
                }
                out.append(arena, inst) catch return error.OutOfMemory;
                continue;
            },
            .local_tee => |x| {
                if (out.items.len > 0 and out.items[out.items.len - 1] == .local_get and out.items[out.items.len - 1].local_get == x) {
                    changed = true;
                    continue;
                }
                invalidateLocal(bindings, x);
                if (out.items.len > 0 and isPropagatableInstr(out.items[out.items.len - 1])) {
                    const prev = out.items[out.items.len - 1];
                    const ok = switch (prev) {
                        .local_get => |src| src != x,
                        else => !(optimize_mode == .small and
                            isLargeConstantInstr(prev) and
                            (initial_reads.get(x) orelse 0) > 1),
                    };
                    if (ok) {
                        bindings.put(arena, x, prev) catch return error.OutOfMemory;
                    }
                }
                out.append(arena, inst) catch return error.OutOfMemory;
                continue;
            },
            .block => |b_in| {
                var b = b_in;
                var blk_bindings = bindings.clone(arena) catch return error.OutOfMemory;
                if (try simplifyLocalsBlock(arena, &b.body, &blk_bindings, optimize_mode, initial_reads)) changed = true;
                var modified: std.AutoHashMapUnmanaged(u32, void) = .empty;
                try collectModifiedLocals(&b.body, arena, &modified);
                var mod_it = modified.keyIterator();
                while (mod_it.next()) |k| {
                    invalidateLocal(bindings, k.*);
                }
                out.append(arena, .{ .block = b }) catch return error.OutOfMemory;
                continue;
            },
            .if_ => |if_in| {
                var if_inst = if_in;
                var then_bindings = bindings.clone(arena) catch return error.OutOfMemory;
                if (try simplifyLocalsBlock(arena, &if_inst.then_body, &then_bindings, optimize_mode, initial_reads)) changed = true;
                if (if_inst.has_else) {
                    var else_bindings = bindings.clone(arena) catch return error.OutOfMemory;
                    if (try simplifyLocalsBlock(arena, &if_inst.else_body, &else_bindings, optimize_mode, initial_reads)) changed = true;
                }
                var modified: std.AutoHashMapUnmanaged(u32, void) = .empty;
                try collectModifiedLocals(&if_inst.then_body, arena, &modified);
                if (if_inst.has_else) {
                    try collectModifiedLocals(&if_inst.else_body, arena, &modified);
                }
                var mod_it = modified.keyIterator();
                while (mod_it.next()) |k| {
                    invalidateLocal(bindings, k.*);
                }
                out.append(arena, .{ .if_ = if_inst }) catch return error.OutOfMemory;
                continue;
            },
            .loop => |lp_in| {
                var lp = lp_in;
                var modified: std.AutoHashMapUnmanaged(u32, void) = .empty;
                try collectModifiedLocals(&lp.body, arena, &modified);
                var mod_it = modified.keyIterator();
                while (mod_it.next()) |k| {
                    invalidateLocal(bindings, k.*);
                }
                var lp_bindings = bindings.clone(arena) catch return error.OutOfMemory;
                if (try simplifyLocalsBlock(arena, &lp.body, &lp_bindings, optimize_mode, initial_reads)) changed = true;
                var mod_it2 = modified.keyIterator();
                while (mod_it2.next()) |k| {
                    invalidateLocal(bindings, k.*);
                }
                out.append(arena, .{ .loop = lp }) catch return error.OutOfMemory;
                continue;
            },
            else => {
                out.append(arena, inst) catch return error.OutOfMemory;
                if (inst.isUnconditionalTransfer()) {
                    bindings.clearRetainingCapacity();
                }
                continue;
            },
        }
    }

    list.* = out;
    return changed;
}

fn countLocalReads(
    list: *const InstrList,
    arena: std.mem.Allocator,
    read_counts: *std.AutoHashMapUnmanaged(u32, u32),
) Error!void {
    for (list.items) |inst| {
        switch (inst) {
            .local_get => |x| {
                const gop = read_counts.getOrPutValue(arena, x, 0) catch return error.OutOfMemory;
                gop.value_ptr.* += 1;
            },
            .block => |*b| try countLocalReads(&b.body, arena, read_counts),
            .loop => |*l| try countLocalReads(&l.body, arena, read_counts),
            .if_ => |*i| {
                try countLocalReads(&i.then_body, arena, read_counts);
                if (i.has_else) try countLocalReads(&i.else_body, arena, read_counts);
            },
            else => {},
        }
    }
}

fn isPureUnaryNumericOp(op: u8) bool {
    return switch (op) {
        0x45, 0x50, 0x67, 0x68, 0x69, 0x79, 0x7a, 0x7b => true,
        0x8b...0x91, 0x99...0x9f => true,
        0xa7, 0xac, 0xad, 0xb2...0xbb, 0xbc...0xc4 => true,
        else => false,
    };
}

fn isPureBinaryNumericOp(op: u8) bool {
    return switch (op) {
        0x46...0x4f, 0x51...0x66 => true,
        0x6a...0x6c, 0x71...0x78, 0x7c...0x7e, 0x83...0x8a => true,
        0x92...0x98, 0xa0...0xa6 => true,
        else => false,
    };
}

fn eliminateDeadLocalStores(
    arena: std.mem.Allocator,
    list: *InstrList,
    read_counts: *const std.AutoHashMapUnmanaged(u32, u32),
) Error!bool {
    var changed = false;
    var out: InstrList = .empty;
    out.ensureTotalCapacity(arena, list.items.len) catch return error.OutOfMemory;

    for (list.items) |inst| {
        switch (inst) {
            .local_tee => |x| {
                if ((read_counts.get(x) orelse 0) == 0) {
                    changed = true;
                    continue;
                }
                out.append(arena, inst) catch return error.OutOfMemory;
            },
            .local_set => |x| {
                if ((read_counts.get(x) orelse 0) == 0) {
                    if (out.items.len > 0 and isPureZeroPopInstr(out.items[out.items.len - 1])) {
                        _ = out.pop();
                    } else if (out.items.len >= 2 and
                        isPureZeroPopInstr(out.items[out.items.len - 2]) and
                        out.items[out.items.len - 1] == .numeric_op and
                        isPureUnaryNumericOp(out.items[out.items.len - 1].numeric_op))
                    {
                        out.items.len -= 2;
                    } else if (out.items.len >= 3 and
                        isPureZeroPopInstr(out.items[out.items.len - 3]) and
                        isPureZeroPopInstr(out.items[out.items.len - 2]) and
                        out.items[out.items.len - 1] == .numeric_op and
                        isPureBinaryNumericOp(out.items[out.items.len - 1].numeric_op))
                    {
                        out.items.len -= 3;
                    } else {
                        out.append(arena, .{ .raw = &[_]u8{0x1a} }) catch return error.OutOfMemory;
                    }
                    changed = true;
                    continue;
                }
                out.append(arena, inst) catch return error.OutOfMemory;
            },
            .block => |b_in| {
                var b = b_in;
                if (try eliminateDeadLocalStores(arena, &b.body, read_counts)) changed = true;
                out.append(arena, .{ .block = b }) catch return error.OutOfMemory;
            },
            .loop => |l_in| {
                var l = l_in;
                if (try eliminateDeadLocalStores(arena, &l.body, read_counts)) changed = true;
                out.append(arena, .{ .loop = l }) catch return error.OutOfMemory;
            },
            .if_ => |if_in| {
                var if_inst = if_in;
                if (try eliminateDeadLocalStores(arena, &if_inst.then_body, read_counts)) changed = true;
                if (if_inst.has_else and try eliminateDeadLocalStores(arena, &if_inst.else_body, read_counts)) changed = true;
                out.append(arena, .{ .if_ = if_inst }) catch return error.OutOfMemory;
            },
            else => {
                out.append(arena, inst) catch return error.OutOfMemory;
            },
        }
    }

    list.* = out;
    return changed;
}

fn findPrevSingleValueExprStart(slice: []const Instr, end_pos: usize) ?usize {
    if (end_pos == 0) return null;
    var needed: isize = 1;
    var pos: usize = end_pos;
    while (pos > 0) {
        pos -= 1;
        if (pos < end_pos - 1 and slice[pos] == .nop) continue;
        const eff = valExprStackEffect(slice[pos], null) orelse return null;
        if (eff.pushes == 0) return null;
        needed = needed - eff.pushes + eff.pops;
        if (needed == 0) return pos;
    }
    return null;
}

fn sliceReferencesLocal(slice: []const Instr, local_idx: u32) bool {
    for (slice) |inst| {
        switch (inst) {
            .local_get, .local_set, .local_tee => |idx| if (idx == local_idx) return true,
            .block => |b| if (sliceReferencesLocal(b.body.items, local_idx)) return true,
            .loop => |l| if (sliceReferencesLocal(l.body.items, local_idx)) return true,
            .if_ => |i| {
                if (sliceReferencesLocal(i.then_body.items, local_idx)) return true;
                if (i.has_else and sliceReferencesLocal(i.else_body.items, local_idx)) return true;
            },
            else => {},
        }
    }
    return false;
}

fn unstackMultiParamLocalSets(arena: std.mem.Allocator, list: *InstrList) Error!bool {
    var changed = false;
    var out: InstrList = .empty;
    out.ensureTotalCapacity(arena, list.items.len) catch return error.OutOfMemory;

    var i: usize = 0;
    while (i < list.items.len) {
        switch (list.items[i]) {
            .block => |b_in| {
                var b = b_in;
                if (try unstackMultiParamLocalSets(arena, &b.body)) changed = true;
                out.append(arena, .{ .block = b }) catch return error.OutOfMemory;
                i += 1;
                continue;
            },
            .loop => |l_in| {
                var l = l_in;
                if (try unstackMultiParamLocalSets(arena, &l.body)) changed = true;
                out.append(arena, .{ .loop = l }) catch return error.OutOfMemory;
                i += 1;
                continue;
            },
            .if_ => |if_in| {
                var if_inst = if_in;
                if (try unstackMultiParamLocalSets(arena, &if_inst.then_body)) changed = true;
                if (if_inst.has_else and try unstackMultiParamLocalSets(arena, &if_inst.else_body)) changed = true;
                out.append(arena, .{ .if_ = if_inst }) catch return error.OutOfMemory;
                i += 1;
                continue;
            },
            .local_set => {
                var k: usize = 1;
                while (k < 8 and i + k < list.items.len and list.items[i + k] == .local_set) : (k += 1) {}
                if (k >= 2) {
                    const sets = list.items[i .. i + k];
                    var distinct = true;
                    for (sets, 0..) |s1, idx1| {
                        for (sets[idx1 + 1 ..]) |s2| {
                            if (s1.local_set == s2.local_set) {
                                distinct = false;
                                break;
                            }
                        }
                        if (!distinct) break;
                    }
                    if (distinct) {
                        var expr_starts: [8]usize = undefined;
                        var expr_ends: [8]usize = undefined;
                        var matched_all = true;
                        for (0..k) |s| {
                            const e = k - 1 - s;
                            const end_pos = if (s == 0) out.items.len else expr_starts[e + 1];
                            const start_pos = findPrevSingleValueExprStart(out.items, end_pos) orelse {
                                matched_all = false;
                                break;
                            };
                            expr_starts[e] = start_pos;
                            expr_ends[e] = end_pos;
                        }
                        if (matched_all) {
                            var safe = true;
                            for (0..k - 1) |e| {
                                const target_local = sets[k - 1 - e].local_set;
                                if (sliceReferencesLocal(out.items[expr_starts[e + 1]..expr_ends[k - 1]], target_local)) {
                                    safe = false;
                                    break;
                                }
                            }
                            if (safe) {
                                const base_start = expr_starts[0];
                                const saved = try arena.dupe(Instr, out.items[base_start..expr_ends[k - 1]]);
                                out.items.len = base_start;
                                for (0..k) |e| {
                                    const rel_start = expr_starts[e] - base_start;
                                    const rel_end = expr_ends[e] - base_start;
                                    out.appendSlice(arena, saved[rel_start..rel_end]) catch return error.OutOfMemory;
                                    out.append(arena, sets[k - 1 - e]) catch return error.OutOfMemory;
                                }
                                changed = true;
                                i += k;
                                continue;
                            }
                        }
                    }
                }
            },
            else => {},
        }
        out.append(arena, list.items[i]) catch return error.OutOfMemory;
        i += 1;
    }

    list.* = out;
    return changed;
}

fn simplifyLocals(
    arena: std.mem.Allocator,
    root_list: *InstrList,
    optimize_mode: OptimizeMode,
) Error!bool {
    var changed = try unstackMultiParamLocalSets(arena, root_list);
    var initial_reads: std.AutoHashMapUnmanaged(u32, u32) = .empty;
    if (optimize_mode == .small) {
        try countLocalReads(root_list, arena, &initial_reads);
    }
    var bindings: std.AutoHashMapUnmanaged(u32, Instr) = .empty;
    if (try simplifyLocalsBlock(arena, root_list, &bindings, optimize_mode, &initial_reads)) changed = true;

    while (true) {
        var read_counts: std.AutoHashMapUnmanaged(u32, u32) = .empty;
        try countLocalReads(root_list, arena, &read_counts);
        if (try eliminateDeadLocalStores(arena, root_list, &read_counts)) {
            changed = true;
        } else {
            break;
        }
    }

    return changed;
}

fn markUsedLocals(list: *const InstrList, param_count: u32, used: []bool) void {
    for (list.items) |inst| {
        switch (inst) {
            .local_get, .local_set, .local_tee => |idx| {
                if (idx >= param_count and idx - param_count < used.len) {
                    used[idx - param_count] = true;
                }
            },
            .block => |*b| markUsedLocals(&b.body, param_count, used),
            .loop => |*l| markUsedLocals(&l.body, param_count, used),
            .if_ => |*i| {
                markUsedLocals(&i.then_body, param_count, used);
                if (i.has_else) markUsedLocals(&i.else_body, param_count, used);
            },
            else => {},
        }
    }
}

fn rewriteLocalIndices(list: *InstrList, param_count: u32, remap: []const u32) void {
    for (list.items) |*inst| {
        switch (inst.*) {
            .local_get => |*idx| if (idx.* >= param_count and idx.* - param_count < remap.len) {
                idx.* = remap[idx.* - param_count];
            },
            .local_set => |*idx| if (idx.* >= param_count and idx.* - param_count < remap.len) {
                idx.* = remap[idx.* - param_count];
            },
            .local_tee => |*idx| if (idx.* >= param_count and idx.* - param_count < remap.len) {
                idx.* = remap[idx.* - param_count];
            },
            .block => |*b| rewriteLocalIndices(&b.body, param_count, remap),
            .loop => |*l| rewriteLocalIndices(&l.body, param_count, remap),
            .if_ => |*i| {
                rewriteLocalIndices(&i.then_body, param_count, remap);
                if (i.has_else) rewriteLocalIndices(&i.else_body, param_count, remap);
            },
            else => {},
        }
    }
}

fn compactLocals(
    arena: std.mem.Allocator,
    module: *const Mod.Module,
    func: *Mod.Func,
    root_list: *InstrList,
) std.mem.Allocator.Error!bool {
    const num_locals = func.local_types.items.len;
    if (num_locals == 0) return false;

    const sig = getFuncSignature(module, func) orelse return false;
    const param_count: u32 = @intCast(sig.params.len);

    const used = try arena.alloc(bool, num_locals);
    @memset(used, false);
    markUsedLocals(root_list, param_count, used);

    var all_used = true;
    for (used) |u| {
        if (!u) {
            all_used = false;
            break;
        }
    }
    if (all_used) return false;

    const remap = try arena.alloc(u32, num_locals);
    const has_type_idxs = func.local_type_idxs.items.len == num_locals;
    var write_idx: usize = 0;
    for (0..num_locals) |i| {
        if (used[i]) {
            remap[i] = param_count + @as(u32, @intCast(write_idx));
            func.local_types.items[write_idx] = func.local_types.items[i];
            if (has_type_idxs) {
                func.local_type_idxs.items[write_idx] = func.local_type_idxs.items[i];
            }
            write_idx += 1;
        } else {
            remap[i] = types.invalid_index;
        }
    }
    func.local_types.shrinkRetainingCapacity(write_idx);
    if (has_type_idxs) {
        func.local_type_idxs.shrinkRetainingCapacity(write_idx);
    } else {
        func.local_type_idxs.clearRetainingCapacity();
    }

    rewriteLocalIndices(root_list, param_count, remap);
    return true;
}

// ── Pass A: Constant Folding (i32 and i64) ───────────────────────────────

fn foldI32Unary(a: i32, op: u8) ?Instr {
    const ua: u32 = @bitCast(a);
    return switch (op) {
        0x45 => .{ .i32_const = if (a == 0) 1 else 0 }, // i32.eqz
        0x67 => .{ .i32_const = @intCast(@clz(ua)) }, // i32.clz
        0x68 => .{ .i32_const = @intCast(@ctz(ua)) }, // i32.ctz
        0x69 => .{ .i32_const = @intCast(@popCount(ua)) }, // i32.popcnt
        0xac => .{ .i64_const = @as(i64, a) }, // i64.extend_i32_s
        0xad => .{ .i64_const = @intCast(ua) }, // i64.extend_i32_u
        0xc0 => .{ .i32_const = @as(i32, @as(i8, @truncate(a))) }, // i32.extend8_s
        0xc1 => .{ .i32_const = @as(i32, @as(i16, @truncate(a))) }, // i32.extend16_s
        else => null,
    };
}

fn foldI32Binary(a: i32, b: i32, op: u8) ?Instr {
    const ua: u32 = @bitCast(a);
    const ub: u32 = @bitCast(b);
    const shift: u5 = @truncate(ub);
    return switch (op) {
        0x6a => .{ .i32_const = a +% b }, // i32.add
        0x6b => .{ .i32_const = a -% b }, // i32.sub
        0x6c => .{ .i32_const = a *% b }, // i32.mul
        0x6d => if (b != 0 and !(a == std.math.minInt(i32) and b == -1))
            .{ .i32_const = @divTrunc(a, b) }
        else
            null, // i32.div_s
        0x6e => if (ub != 0) .{ .i32_const = @bitCast(ua / ub) } else null, // i32.div_u
        0x6f => if (b != 0 and !(a == std.math.minInt(i32) and b == -1))
            .{ .i32_const = @rem(a, b) }
        else
            null, // i32.rem_s
        0x70 => if (ub != 0) .{ .i32_const = @bitCast(ua % ub) } else null, // i32.rem_u
        0x71 => .{ .i32_const = a & b }, // i32.and
        0x72 => .{ .i32_const = a | b }, // i32.or
        0x73 => .{ .i32_const = a ^ b }, // i32.xor
        0x74 => .{ .i32_const = @bitCast(ua << shift) }, // i32.shl
        0x75 => .{ .i32_const = a >> shift }, // i32.shr_s
        0x76 => .{ .i32_const = @bitCast(ua >> shift) }, // i32.shr_u
        0x77 => .{ .i32_const = @bitCast(std.math.rotl(u32, ua, shift)) }, // i32.rotl
        0x78 => .{ .i32_const = @bitCast(std.math.rotr(u32, ua, shift)) }, // i32.rotr
        0x46 => .{ .i32_const = if (a == b) 1 else 0 }, // i32.eq
        0x47 => .{ .i32_const = if (a != b) 1 else 0 }, // i32.ne
        0x48 => .{ .i32_const = if (a < b) 1 else 0 }, // i32.lt_s
        0x49 => .{ .i32_const = if (ua < ub) 1 else 0 }, // i32.lt_u
        0x4a => .{ .i32_const = if (a > b) 1 else 0 }, // i32.gt_s
        0x4b => .{ .i32_const = if (ua > ub) 1 else 0 }, // i32.gt_u
        0x4c => .{ .i32_const = if (a <= b) 1 else 0 }, // i32.le_s
        0x4d => .{ .i32_const = if (ua <= ub) 1 else 0 }, // i32.le_u
        0x4e => .{ .i32_const = if (a >= b) 1 else 0 }, // i32.ge_s
        0x4f => .{ .i32_const = if (ua >= ub) 1 else 0 }, // i32.ge_u
        else => null,
    };
}

fn foldI64Unary(a: i64, op: u8) ?Instr {
    const ua: u64 = @bitCast(a);
    return switch (op) {
        0x50 => .{ .i32_const = if (a == 0) 1 else 0 }, // i64.eqz
        0x79 => .{ .i64_const = @intCast(@clz(ua)) }, // i64.clz
        0x7a => .{ .i64_const = @intCast(@ctz(ua)) }, // i64.ctz
        0x7b => .{ .i64_const = @intCast(@popCount(ua)) }, // i64.popcnt
        0xa7 => .{ .i32_const = @bitCast(@as(u32, @truncate(ua))) }, // i32.wrap_i64
        0xc2 => .{ .i64_const = @as(i64, @as(i8, @truncate(a))) }, // i64.extend8_s
        0xc3 => .{ .i64_const = @as(i64, @as(i16, @truncate(a))) }, // i64.extend16_s
        0xc4 => .{ .i64_const = @as(i64, @as(i32, @truncate(a))) }, // i64.extend32_s
        else => null,
    };
}

fn foldI64Binary(a: i64, b: i64, op: u8) ?Instr {
    const ua: u64 = @bitCast(a);
    const ub: u64 = @bitCast(b);
    const shift: u6 = @truncate(ub);
    return switch (op) {
        0x7c => .{ .i64_const = a +% b }, // i64.add
        0x7d => .{ .i64_const = a -% b }, // i64.sub
        0x7e => .{ .i64_const = a *% b }, // i64.mul
        0x7f => if (b != 0 and !(a == std.math.minInt(i64) and b == -1))
            .{ .i64_const = @divTrunc(a, b) }
        else
            null, // i64.div_s
        0x80 => if (ub != 0) .{ .i64_const = @bitCast(ua / ub) } else null, // i64.div_u
        0x81 => if (b != 0 and !(a == std.math.minInt(i64) and b == -1))
            .{ .i64_const = @rem(a, b) }
        else
            null, // i64.rem_s
        0x82 => if (ub != 0) .{ .i64_const = @bitCast(ua % ub) } else null, // i64.rem_u
        0x83 => .{ .i64_const = a & b }, // i64.and
        0x84 => .{ .i64_const = a | b }, // i64.or
        0x85 => .{ .i64_const = a ^ b }, // i64.xor
        0x86 => .{ .i64_const = @bitCast(ua << shift) }, // i64.shl
        0x87 => .{ .i64_const = a >> shift }, // i64.shr_s
        0x88 => .{ .i64_const = @bitCast(ua >> shift) }, // i64.shr_u
        0x89 => .{ .i64_const = @bitCast(std.math.rotl(u64, ua, shift)) }, // i64.rotl
        0x8a => .{ .i64_const = @bitCast(std.math.rotr(u64, ua, shift)) }, // i64.rotr
        0x51 => .{ .i32_const = if (a == b) 1 else 0 }, // i64.eq
        0x52 => .{ .i32_const = if (a != b) 1 else 0 }, // i64.ne
        0x53 => .{ .i32_const = if (a < b) 1 else 0 }, // i64.lt_s
        0x54 => .{ .i32_const = if (ua < ub) 1 else 0 }, // i64.lt_u
        0x55 => .{ .i32_const = if (a > b) 1 else 0 }, // i64.gt_s
        0x56 => .{ .i32_const = if (ua > ub) 1 else 0 }, // i64.gt_u
        0x57 => .{ .i32_const = if (a <= b) 1 else 0 }, // i64.le_s
        0x58 => .{ .i32_const = if (ua <= ub) 1 else 0 }, // i64.le_u
        0x59 => .{ .i32_const = if (a >= b) 1 else 0 }, // i64.ge_s
        0x5a => .{ .i32_const = if (ua >= ub) 1 else 0 }, // i64.ge_u
        else => null,
    };
}

fn isBoolProducer(inst: Instr) bool {
    return switch (inst) {
        .numeric_op => |op| op >= 0x45 and op <= 0x66,
        else => false,
    };
}

fn invertComparisonOp(op: u8) ?u8 {
    return switch (op) {
        0x46 => 0x47, // i32.eq -> i32.ne
        0x47 => 0x46, // i32.ne -> i32.eq
        0x48 => 0x4e, // i32.lt_s -> i32.ge_s
        0x4e => 0x48, // i32.ge_s -> i32.lt_s
        0x49 => 0x4f, // i32.lt_u -> i32.ge_u
        0x4f => 0x49, // i32.ge_u -> i32.lt_u
        0x4a => 0x4c, // i32.gt_s -> i32.le_s
        0x4c => 0x4a, // i32.le_s -> i32.gt_s
        0x4b => 0x4d, // i32.gt_u -> i32.le_u
        0x4d => 0x4b, // i32.le_u -> i32.gt_u
        0x51 => 0x52, // i64.eq -> i64.ne
        0x52 => 0x51, // i64.ne -> i64.eq
        0x53 => 0x59, // i64.lt_s -> i64.ge_s
        0x59 => 0x53, // i64.ge_s -> i64.lt_s
        0x54 => 0x5a, // i64.lt_u -> i64.ge_u
        0x5a => 0x54, // i64.ge_u -> i64.lt_u
        0x55 => 0x57, // i64.gt_s -> i64.le_s
        0x57 => 0x55, // i64.le_s -> i64.gt_s
        0x56 => 0x58, // i64.gt_u -> i64.le_u
        0x58 => 0x56, // i64.le_u -> i64.gt_u
        0x5b => 0x5c, // f32.eq -> f32.ne
        0x5c => 0x5b, // f32.ne -> f32.eq
        0x61 => 0x62, // f64.eq -> f64.ne
        0x62 => 0x61, // f64.ne -> f64.eq
        0x73 => 0x46, // i32.eqz(i32.xor(a, b)) -> i32.eq(a, b)
        else => null,
    };
}

fn isPureZeroPopInstr(inst: Instr) bool {
    return switch (inst) {
        .i32_const, .i64_const, .ref_func, .local_get => true,
        .raw => |r| r.len > 0 and switch (r[0]) {
            0x23, 0x43, 0x44, 0xd0 => true,
            else => false,
        },
        else => false,
    };
}

fn instrEql(a: Instr, b: Instr) bool {
    return switch (a) {
        .nop => b == .nop,
        .i32_const => |v| b == .i32_const and b.i32_const == v,
        .i64_const => |v| b == .i64_const and b.i64_const == v,
        .local_get => |v| b == .local_get and b.local_get == v,
        .local_set => |v| b == .local_set and b.local_set == v,
        .local_tee => |v| b == .local_tee and b.local_tee == v,
        .ref_func => |v| b == .ref_func and b.ref_func == v,
        .numeric_op => |v| b == .numeric_op and b.numeric_op == v,
        .raw => |r| b == .raw and std.mem.eql(u8, r, b.raw),
        else => false,
    };
}

const MagicU32 = struct {
    mul: u64,
    shift: u6,
    add: bool,
};

fn magicU32(d: u32) MagicU32 {
    const ad: u64 = d;
    const nc: u64 = @as(u64, 0xffff_ffff) - (@as(u64, 0 -% d) % ad);
    var p: u32 = 31;
    var q1: u64 = 0x8000_0000 / nc;
    var r1: u64 = 0x8000_0000 - q1 * nc;
    var q2: u64 = 0x7fff_ffff / ad;
    var r2: u64 = 0x7fff_ffff - q2 * ad;
    var add = false;
    while (true) {
        p += 1;
        if (r1 >= nc - r1) {
            q1 = q1 * 2 + 1;
            r1 = r1 * 2 - nc;
        } else {
            q1 = q1 * 2;
            r1 = r1 * 2;
        }
        if (r2 + 1 >= ad - r2) {
            if (q2 >= 0x7fff_ffff) add = true;
            q2 = q2 * 2 + 1;
            r2 = r2 * 2 + 1 - ad;
        } else {
            if (q2 >= 0x8000_0000) add = true;
            q2 = q2 * 2;
            r2 = r2 * 2 + 1;
        }
        const delta = ad - 1 - r2;
        if (p >= 64 or !(q1 < delta or (q1 == delta and r1 == 0))) break;
    }
    return .{
        .mul = (q2 + 1) & 0xffff_ffff,
        .shift = @intCast(p - 32),
        .add = add,
    };
}

const MagicS32 = struct {
    mul: i64,
    shift: u6,
};

fn magicS32(d: u32) MagicS32 {
    const ad: u64 = d;
    const t: u64 = 0x8000_0000;
    const anc: u64 = t - 1 - (t % ad);
    var p: u32 = 31;
    var q1: u64 = 0x8000_0000 / anc;
    var r1: u64 = 0x8000_0000 - q1 * anc;
    var q2: u64 = 0x8000_0000 / ad;
    var r2: u64 = 0x8000_0000 - q2 * ad;
    while (true) {
        p += 1;
        q1 *= 2;
        r1 *= 2;
        if (r1 >= anc) {
            q1 += 1;
            r1 -= anc;
        }
        q2 *= 2;
        r2 *= 2;
        if (r2 >= ad) {
            q2 += 1;
            r2 -= ad;
        }
        const delta = ad - r2;
        if (p >= 64 or !(q1 < delta or (q1 == delta and r1 == 0))) break;
    }
    return .{
        .mul = @intCast(q2 + 1),
        .shift = @intCast(p),
    };
}

fn emitMagicDivU32(arena: std.mem.Allocator, out: *InstrList, d: u32, lhs_local: ?u32) Error!bool {
    const mag = magicU32(d);
    if (!mag.add) {
        try out.appendSlice(arena, &.{
            .{ .numeric_op = 0xad }, // i64.extend_i32_u
            .{ .i64_const = @intCast(mag.mul) },
            .{ .numeric_op = 0x7e }, // i64.mul
            .{ .i64_const = 32 + @as(i64, mag.shift) },
            .{ .numeric_op = 0x88 }, // i64.shr_u
            .{ .numeric_op = 0xa7 }, // i32.wrap_i64
        });
        return true;
    }
    const l = lhs_local orelse return false;
    try out.appendSlice(arena, &.{
        .{ .numeric_op = 0xad }, // i64.extend_i32_u
        .{ .i64_const = @intCast(mag.mul) },
        .{ .numeric_op = 0x7e }, // i64.mul
        .{ .i64_const = 32 },
        .{ .numeric_op = 0x88 }, // i64.shr_u
        .{ .local_get = l },
        .{ .numeric_op = 0xad }, // i64.extend_i32_u
        .{ .numeric_op = 0x7c }, // i64.add
    });
    if (mag.shift > 0) {
        try out.appendSlice(arena, &.{
            .{ .i64_const = @as(i64, mag.shift) },
            .{ .numeric_op = 0x88 }, // i64.shr_u
        });
    }
    try out.append(arena, .{ .numeric_op = 0xa7 }); // i32.wrap_i64
    return true;
}

fn emitStrengthReducedDivS32(arena: std.mem.Allocator, out: *InstrList, d: u32, l: u32) Error!void {
    if (std.math.isPowerOfTwo(d)) {
        const k: i32 = @intCast(@ctz(d));
        if (k == 1) {
            try out.appendSlice(arena, &.{
                .{ .i32_const = 31 },
                .{ .numeric_op = 0x76 }, // i32.shr_u
                .{ .local_get = l },
                .{ .numeric_op = 0x6a }, // i32.add
                .{ .i32_const = 1 },
                .{ .numeric_op = 0x75 }, // i32.shr_s
            });
        } else {
            try out.appendSlice(arena, &.{
                .{ .i32_const = 31 },
                .{ .numeric_op = 0x75 }, // i32.shr_s
                .{ .i32_const = 32 - k },
                .{ .numeric_op = 0x76 }, // i32.shr_u
                .{ .local_get = l },
                .{ .numeric_op = 0x6a }, // i32.add
                .{ .i32_const = k },
                .{ .numeric_op = 0x75 }, // i32.shr_s
            });
        }
        return;
    }
    const mag = magicS32(d);
    try out.appendSlice(arena, &.{
        .{ .numeric_op = 0xac }, // i64.extend_i32_s
        .{ .i64_const = mag.mul },
        .{ .numeric_op = 0x7e }, // i64.mul
        .{ .i64_const = @as(i64, mag.shift) },
        .{ .numeric_op = 0x87 }, // i64.shr_s
        .{ .numeric_op = 0xa7 }, // i32.wrap_i64
        .{ .local_get = l },
        .{ .i32_const = 31 },
        .{ .numeric_op = 0x76 }, // i32.shr_u
        .{ .numeric_op = 0x6a }, // i32.add
    });
}

fn possibleOnesI32(slice: []const Instr) u32 {
    if (slice.len == 0) return 0xffff_ffff;
    const last = slice[slice.len - 1];
    switch (last) {
        .i32_const => |c| return @bitCast(c),
        .numeric_op => |op| switch (op) {
            0x45...0x66 => return 1,
            0x67, 0x68, 0x69 => return 0x3f, // clz, ctz, popcnt in 0..32
            0x71 => { // i32.and
                const r_start = findPrevSingleValueExprStart(slice, slice.len - 1) orelse return 0xffff_ffff;
                const l_start = findPrevSingleValueExprStart(slice, r_start) orelse return possibleOnesI32(slice[r_start .. slice.len - 1]);
                return possibleOnesI32(slice[l_start..r_start]) & possibleOnesI32(slice[r_start .. slice.len - 1]);
            },
            0x72, 0x73 => { // i32.or, i32.xor
                const r_start = findPrevSingleValueExprStart(slice, slice.len - 1) orelse return 0xffff_ffff;
                const l_start = findPrevSingleValueExprStart(slice, r_start) orelse return 0xffff_ffff;
                return possibleOnesI32(slice[l_start..r_start]) | possibleOnesI32(slice[r_start .. slice.len - 1]);
            },
            0x74 => { // i32.shl
                if (slice.len >= 2 and slice[slice.len - 2] == .i32_const) {
                    const sh: u5 = @truncate(@as(u32, @bitCast(slice[slice.len - 2].i32_const)));
                    const l_start = findPrevSingleValueExprStart(slice, slice.len - 2) orelse return (@as(u32, 0xffff_ffff) << sh);
                    return possibleOnesI32(slice[l_start .. slice.len - 2]) << sh;
                }
                return 0xffff_ffff;
            },
            0x76 => { // i32.shr_u
                if (slice.len >= 2 and slice[slice.len - 2] == .i32_const) {
                    const sh: u5 = @truncate(@as(u32, @bitCast(slice[slice.len - 2].i32_const)));
                    const l_start = findPrevSingleValueExprStart(slice, slice.len - 2) orelse return (@as(u32, 0xffff_ffff) >> sh);
                    return possibleOnesI32(slice[l_start .. slice.len - 2]) >> sh;
                }
                return 0xffff_ffff;
            },
            0x70 => { // i32.rem_u
                if (slice.len >= 2 and slice[slice.len - 2] == .i32_const) {
                    const d: u32 = @bitCast(slice[slice.len - 2].i32_const);
                    if (d == 1) return 0;
                    if (d > 1) {
                        const rem_mask: u32 = @as(u32, 0xffff_ffff) >> @intCast(@clz(d - 1));
                        const l_start = findPrevSingleValueExprStart(slice, slice.len - 2) orelse return rem_mask;
                        return possibleOnesI32(slice[l_start .. slice.len - 2]) & rem_mask;
                    }
                }
                return 0xffff_ffff;
            },
            0xa7 => { // i32.wrap_i64
                return @truncate(possibleOnesI64(slice[0 .. slice.len - 1]));
            },
            else => return 0xffff_ffff,
        },
        .raw => |r| {
            if (r.len == 0) return 0xffff_ffff;
            return switch (r[0]) {
                0x2d => 0xff, // i32.load8_u
                0x2f => 0xffff, // i32.load16_u
                0x1b, 0x1c => blk: { // select
                    const c_start = findPrevSingleValueExprStart(slice, slice.len - 1) orelse break :blk 0xffff_ffff;
                    const f_start = findPrevSingleValueExprStart(slice, c_start) orelse break :blk 0xffff_ffff;
                    const t_start = findPrevSingleValueExprStart(slice, f_start) orelse break :blk 0xffff_ffff;
                    break :blk possibleOnesI32(slice[t_start..f_start]) | possibleOnesI32(slice[f_start..c_start]);
                },
                else => 0xffff_ffff,
            };
        },
        .if_ => |if_inst| {
            if (if_inst.has_else and if_inst.then_body.items.len > 0 and if_inst.else_body.items.len > 0) {
                return possibleOnesI32(if_inst.then_body.items) | possibleOnesI32(if_inst.else_body.items);
            }
            return 0xffff_ffff;
        },
        else => return 0xffff_ffff,
    }
}

fn possibleOnesI64(slice: []const Instr) u64 {
    if (slice.len == 0) return 0xffff_ffff_ffff_ffff;
    const last = slice[slice.len - 1];
    switch (last) {
        .i64_const => |c| return @bitCast(c),
        .numeric_op => |op| switch (op) {
            0x79, 0x7a, 0x7b => return 0x7f, // i64 clz, ctz, popcnt in 0..64
            0x83 => { // i64.and
                const r_start = findPrevSingleValueExprStart(slice, slice.len - 1) orelse return 0xffff_ffff_ffff_ffff;
                const l_start = findPrevSingleValueExprStart(slice, r_start) orelse return possibleOnesI64(slice[r_start .. slice.len - 1]);
                return possibleOnesI64(slice[l_start..r_start]) & possibleOnesI64(slice[r_start .. slice.len - 1]);
            },
            0x84, 0x85 => { // i64.or, i64.xor
                const r_start = findPrevSingleValueExprStart(slice, slice.len - 1) orelse return 0xffff_ffff_ffff_ffff;
                const l_start = findPrevSingleValueExprStart(slice, r_start) orelse return 0xffff_ffff_ffff_ffff;
                return possibleOnesI64(slice[l_start..r_start]) | possibleOnesI64(slice[r_start .. slice.len - 1]);
            },
            0x86 => { // i64.shl
                if (slice.len >= 2 and slice[slice.len - 2] == .i64_const) {
                    const sh: u6 = @truncate(@as(u64, @bitCast(slice[slice.len - 2].i64_const)));
                    const l_start = findPrevSingleValueExprStart(slice, slice.len - 2) orelse return (@as(u64, 0xffff_ffff_ffff_ffff) << sh);
                    return possibleOnesI64(slice[l_start .. slice.len - 2]) << sh;
                }
                return 0xffff_ffff_ffff_ffff;
            },
            0x88 => { // i64.shr_u
                if (slice.len >= 2 and slice[slice.len - 2] == .i64_const) {
                    const sh: u6 = @truncate(@as(u64, @bitCast(slice[slice.len - 2].i64_const)));
                    const l_start = findPrevSingleValueExprStart(slice, slice.len - 2) orelse return (@as(u64, 0xffff_ffff_ffff_ffff) >> sh);
                    return possibleOnesI64(slice[l_start .. slice.len - 2]) >> sh;
                }
                return 0xffff_ffff_ffff_ffff;
            },
            0x82 => { // i64.rem_u
                if (slice.len >= 2 and slice[slice.len - 2] == .i64_const) {
                    const d: u64 = @bitCast(slice[slice.len - 2].i64_const);
                    if (d == 1) return 0;
                    if (d > 1) {
                        const rem_mask: u64 = @as(u64, 0xffff_ffff_ffff_ffff) >> @intCast(@clz(d - 1));
                        const l_start = findPrevSingleValueExprStart(slice, slice.len - 2) orelse return rem_mask;
                        return possibleOnesI64(slice[l_start .. slice.len - 2]) & rem_mask;
                    }
                }
                return 0xffff_ffff_ffff_ffff;
            },
            0xad => { // i64.extend_i32_u
                return @as(u64, possibleOnesI32(slice[0 .. slice.len - 1]));
            },
            else => return 0xffff_ffff_ffff_ffff,
        },
        .raw => |r| {
            if (r.len == 0) return 0xffff_ffff_ffff_ffff;
            return switch (r[0]) {
                0x31 => 0xff, // i64.load8_u
                0x33 => 0xffff, // i64.load16_u
                0x35 => 0xffff_ffff, // i64.load32_u
                0x1b, 0x1c => blk: {
                    const c_start = findPrevSingleValueExprStart(slice, slice.len - 1) orelse break :blk 0xffff_ffff_ffff_ffff;
                    const f_start = findPrevSingleValueExprStart(slice, c_start) orelse break :blk 0xffff_ffff_ffff_ffff;
                    const t_start = findPrevSingleValueExprStart(slice, f_start) orelse break :blk 0xffff_ffff_ffff_ffff;
                    break :blk possibleOnesI64(slice[t_start..f_start]) | possibleOnesI64(slice[f_start..c_start]);
                },
                else => 0xffff_ffff_ffff_ffff,
            };
        },
        .if_ => |if_inst| {
            if (if_inst.has_else and if_inst.then_body.items.len > 0 and if_inst.else_body.items.len > 0) {
                return possibleOnesI64(if_inst.then_body.items) | possibleOnesI64(if_inst.else_body.items);
            }
            return 0xffff_ffff_ffff_ffff;
        },
        else => return 0xffff_ffff_ffff_ffff,
    }
}

fn extractLocalGetOrTee(inst: Instr) ?u32 {
    return switch (inst) {
        .local_get => |l| l,
        .local_tee => |l| l,
        else => null,
    };
}

fn emitOrFoldI32Eqz(arena: std.mem.Allocator, out: *InstrList) Error!bool {
    if (out.items.len >= 1) {
        switch (out.items[out.items.len - 1]) {
            .i32_const => |c| {
                out.items[out.items.len - 1] = .{ .i32_const = if (c == 0) 1 else 0 };
                return true;
            },
            .numeric_op => |prev_op| {
                if (invertComparisonOp(prev_op)) |inv| {
                    out.items[out.items.len - 1] = .{ .numeric_op = inv };
                    if (inv == 0x46 and out.items.len >= 2 and out.items[out.items.len - 2] == .i32_const and out.items[out.items.len - 2].i32_const == 0) {
                        out.items.len -= 2;
                        _ = try emitOrFoldI32Eqz(arena, out);
                    } else if (inv == 0x51 and out.items.len >= 2 and out.items[out.items.len - 2] == .i64_const and out.items[out.items.len - 2].i64_const == 0) {
                        out.items[out.items.len - 2] = .{ .numeric_op = 0x50 };
                        out.items.len -= 1;
                    }
                    return true;
                }
                if (prev_op == 0x45 and out.items.len >= 2) {
                    const before_eqz = out.items[0 .. out.items.len - 1];
                    if (isBoolProducer(before_eqz[before_eqz.len - 1]) or possibleOnesI32(before_eqz) <= 1) {
                        out.items.len -= 1;
                        return true;
                    }
                }
            },
            else => {},
        }
    }
    out.append(arena, .{ .numeric_op = 0x45 }) catch return error.OutOfMemory;
    return false;
}

fn foldConstants(arena: std.mem.Allocator, list: *InstrList, optimize_mode: OptimizeMode) Error!bool {
    var changed = false;

    for (list.items) |*inst| {
        switch (inst.*) {
            .block => |*b| {
                if (try foldConstants(arena, &b.body, optimize_mode)) changed = true;
            },
            .loop => |*l| {
                if (try foldConstants(arena, &l.body, optimize_mode)) changed = true;
            },
            .if_ => |*i| {
                if (try foldConstants(arena, &i.then_body, optimize_mode)) changed = true;
                if (i.has_else and try foldConstants(arena, &i.else_body, optimize_mode)) changed = true;
            },
            else => {},
        }
    }

    var out: InstrList = .empty;
    out.ensureTotalCapacity(arena, list.items.len) catch return error.OutOfMemory;

    for (list.items) |inst| {
        switch (inst) {
            .numeric_op => |op| {
                if (op == 0x45) {
                    if (try emitOrFoldI32Eqz(arena, &out)) {
                        changed = true;
                    }
                    continue;
                }
                if (op == 0x50 and out.items.len >= 1 and out.items[out.items.len - 1] == .numeric_op and out.items[out.items.len - 1].numeric_op == 0x85) {
                    out.items[out.items.len - 1] = .{ .numeric_op = 0x51 };
                    if (out.items.len >= 2 and out.items[out.items.len - 2] == .i64_const and out.items[out.items.len - 2].i64_const == 0) {
                        out.items[out.items.len - 2] = .{ .numeric_op = 0x50 };
                        out.items.len -= 1;
                    }
                    changed = true;
                    continue;
                }
                if (out.items.len >= 1) {
                    switch (out.items[out.items.len - 1]) {
                        .i32_const => |a| {
                            if (foldI32Unary(a, op)) |folded| {
                                out.items[out.items.len - 1] = folded;
                                changed = true;
                                continue;
                            }
                        },
                        .i64_const => |a| {
                            if (foldI64Unary(a, op)) |folded| {
                                out.items[out.items.len - 1] = folded;
                                changed = true;
                                continue;
                            }
                        },
                        .numeric_op => |prev_op| {
                            // `i32.wrap_i64` of `i64.extend_i32_s` or `i64.extend_i32_u` -> elide both
                            if (op == 0xa7 and (prev_op == 0xac or prev_op == 0xad)) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                            // Float unary idempotents: abs(abs(x)) -> abs(x), abs(neg(x)) -> abs(x), neg(neg(x)) -> x
                            if (op == 0x8b and (prev_op == 0x8b or prev_op == 0x8c)) {
                                out.items[out.items.len - 1] = .{ .numeric_op = 0x8b };
                                changed = true;
                                continue;
                            }
                            if (op == 0x8c and prev_op == 0x8c) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                            if (op == 0x99 and (prev_op == 0x99 or prev_op == 0x9a)) {
                                out.items[out.items.len - 1] = .{ .numeric_op = 0x99 };
                                changed = true;
                                continue;
                            }
                            if (op == 0x9a and prev_op == 0x9a) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                        },
                        .raw => {
                            // Fuse `extend*_s` of `load*_u` into `load*_s`
                            if (op >= 0xc0 and op <= 0xc4) {
                                if (decodeLoadAccess(out.items[out.items.len - 1])) |load_acc| {
                                    const fused_opc: ?u8 = switch (op) {
                                        0xc0 => if (load_acc.opcode == 0x2d) @as(u8, 0x2c) else null,
                                        0xc1 => if (load_acc.opcode == 0x2f) @as(u8, 0x2e) else null,
                                        0xc2 => if (load_acc.opcode == 0x31) @as(u8, 0x30) else null,
                                        0xc3 => if (load_acc.opcode == 0x33) @as(u8, 0x32) else null,
                                        0xc4 => if (load_acc.opcode == 0x35) @as(u8, 0x34) else null,
                                        else => null,
                                    };
                                    if (fused_opc) |new_opc| {
                                        const new_raw = arena.dupe(u8, out.items[out.items.len - 1].raw) catch return error.OutOfMemory;
                                        new_raw[0] = new_opc;
                                        out.items[out.items.len - 1] = .{ .raw = new_raw };
                                        changed = true;
                                        continue;
                                    }
                                }
                            }
                        },
                        else => {},
                    }
                }
                if (out.items.len >= 2) {
                    if (out.items[out.items.len - 2] == .i32_const and out.items[out.items.len - 1] == .i32_const) {
                        const a = out.items[out.items.len - 2].i32_const;
                        const b = out.items[out.items.len - 1].i32_const;
                        if (foldI32Binary(a, b, op)) |folded| {
                            out.items[out.items.len - 2] = folded;
                            out.items.len -= 1;
                            changed = true;
                            continue;
                        }
                    } else if (out.items[out.items.len - 2] == .i64_const and out.items[out.items.len - 1] == .i64_const) {
                        const a = out.items[out.items.len - 2].i64_const;
                        const b = out.items[out.items.len - 1].i64_const;
                        if (foldI64Binary(a, b, op)) |folded| {
                            out.items[out.items.len - 2] = folded;
                            out.items.len -= 1;
                            changed = true;
                            continue;
                        }
                    } else if (out.items[out.items.len - 2] == .local_get and out.items[out.items.len - 1] == .local_get and
                        out.items[out.items.len - 2].local_get == out.items[out.items.len - 1].local_get)
                    {
                        // Same-local integer binary/comparison folds
                        switch (op) {
                            0x6b, 0x73, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x52, 0x53, 0x54, 0x55, 0x56 => {
                                out.items[out.items.len - 2] = .{ .i32_const = 0 };
                                out.items.len -= 1;
                                changed = true;
                                continue;
                            },
                            0x7d, 0x85 => {
                                out.items[out.items.len - 2] = .{ .i64_const = 0 };
                                out.items.len -= 1;
                                changed = true;
                                continue;
                            },
                            0x71, 0x72, 0x83, 0x84 => {
                                out.items.len -= 1;
                                changed = true;
                                continue;
                            },
                            0x46, 0x4c, 0x4d, 0x4e, 0x4f, 0x51, 0x57, 0x58, 0x59, 0x5a => {
                                out.items[out.items.len - 2] = .{ .i32_const = 1 };
                                out.items.len -= 1;
                                changed = true;
                                continue;
                            },
                            else => {},
                        }
                    }
                }

                // Constant reassociation: (x +- c1) +- c2 and associative bitwise
                if (out.items.len >= 3) {
                    if ((op == 0x6a or op == 0x6b) and
                        out.items[out.items.len - 1] == .i32_const and
                        out.items[out.items.len - 2] == .numeric_op and
                        (out.items[out.items.len - 2].numeric_op == 0x6a or out.items[out.items.len - 2].numeric_op == 0x6b) and
                        out.items[out.items.len - 3] == .i32_const)
                    {
                        const c1 = out.items[out.items.len - 3].i32_const;
                        const op1 = out.items[out.items.len - 2].numeric_op;
                        const c2 = out.items[out.items.len - 1].i32_const;
                        const d1: i32 = if (op1 == 0x6a) c1 else 0 -% c1;
                        const d2: i32 = if (op == 0x6a) c2 else 0 -% c2;
                        const total: i32 = d1 +% d2;
                        if (total == 0) {
                            out.items.len -= 3;
                        } else {
                            out.items[out.items.len - 3] = .{ .i32_const = total };
                            out.items[out.items.len - 2] = .{ .numeric_op = 0x6a };
                            out.items.len -= 1;
                        }
                        changed = true;
                        continue;
                    }
                    if ((op == 0x71 or op == 0x72 or op == 0x73) and
                        out.items[out.items.len - 1] == .i32_const and
                        out.items[out.items.len - 2] == .numeric_op and
                        out.items[out.items.len - 2].numeric_op == op and
                        out.items[out.items.len - 3] == .i32_const)
                    {
                        const c1 = out.items[out.items.len - 3].i32_const;
                        const c2 = out.items[out.items.len - 1].i32_const;
                        const combined: i32 = switch (op) {
                            0x71 => c1 & c2,
                            0x72 => c1 | c2,
                            0x73 => c1 ^ c2,
                            else => unreachable,
                        };
                        const is_identity = switch (op) {
                            0x71 => combined == -1,
                            0x72, 0x73 => combined == 0,
                            else => unreachable,
                        };
                        if (is_identity) {
                            out.items.len -= 3;
                        } else {
                            out.items[out.items.len - 3] = .{ .i32_const = combined };
                            out.items.len -= 1;
                        }
                        changed = true;
                        continue;
                    }
                    if ((op == 0x7c or op == 0x7d) and
                        out.items[out.items.len - 1] == .i64_const and
                        out.items[out.items.len - 2] == .numeric_op and
                        (out.items[out.items.len - 2].numeric_op == 0x7c or out.items[out.items.len - 2].numeric_op == 0x7d) and
                        out.items[out.items.len - 3] == .i64_const)
                    {
                        const c1 = out.items[out.items.len - 3].i64_const;
                        const op1 = out.items[out.items.len - 2].numeric_op;
                        const c2 = out.items[out.items.len - 1].i64_const;
                        const d1: i64 = if (op1 == 0x7c) c1 else 0 -% c1;
                        const d2: i64 = if (op == 0x7c) c2 else 0 -% c2;
                        const total: i64 = d1 +% d2;
                        if (total == 0) {
                            out.items.len -= 3;
                        } else {
                            out.items[out.items.len - 3] = .{ .i64_const = total };
                            out.items[out.items.len - 2] = .{ .numeric_op = 0x7c };
                            out.items.len -= 1;
                        }
                        changed = true;
                        continue;
                    }
                    if ((op == 0x83 or op == 0x84 or op == 0x85) and
                        out.items[out.items.len - 1] == .i64_const and
                        out.items[out.items.len - 2] == .numeric_op and
                        out.items[out.items.len - 2].numeric_op == op and
                        out.items[out.items.len - 3] == .i64_const)
                    {
                        const c1 = out.items[out.items.len - 3].i64_const;
                        const c2 = out.items[out.items.len - 1].i64_const;
                        const combined: i64 = switch (op) {
                            0x83 => c1 & c2,
                            0x84 => c1 | c2,
                            0x85 => c1 ^ c2,
                            else => unreachable,
                        };
                        const is_identity = switch (op) {
                            0x83 => combined == -1,
                            0x84, 0x85 => combined == 0,
                            else => unreachable,
                        };
                        if (is_identity) {
                            out.items.len -= 3;
                        } else {
                            out.items[out.items.len - 3] = .{ .i64_const = combined };
                            out.items.len -= 1;
                        }
                        changed = true;
                        continue;
                    }
                }

                // Single-constant right-operand peepholes
                if (out.items.len >= 1) {
                    switch (out.items[out.items.len - 1]) {
                        .i32_const => |rhs| {
                            const rhs_u: u32 = @bitCast(rhs);
                            const shift_amt: u5 = @truncate(rhs_u);
                            switch (op) {
                                0x6a, 0x6b, 0x72 => if (rhs == 0) {
                                    out.items.len -= 1;
                                    changed = true;
                                    continue;
                                },
                                0x73 => {
                                    if (rhs == 0) {
                                        out.items.len -= 1;
                                        changed = true;
                                        continue;
                                    }
                                    if (rhs == 1 and out.items.len >= 2) {
                                        const lhs_slice = out.items[0 .. out.items.len - 1];
                                        if (isBoolProducer(lhs_slice[lhs_slice.len - 1]) or possibleOnesI32(lhs_slice) <= 1) {
                                            out.items.len -= 1;
                                            _ = try emitOrFoldI32Eqz(arena, &out);
                                            changed = true;
                                            continue;
                                        }
                                    }
                                },
                                0x71 => {
                                    if (rhs == -1 or (out.items.len >= 2 and isBoolProducer(out.items[out.items.len - 2]) and (rhs & 1) == 1)) {
                                        out.items.len -= 1;
                                        changed = true;
                                        continue;
                                    }
                                    if (out.items.len >= 2) {
                                        if (findPrevSingleValueExprStart(out.items, out.items.len - 1)) |lhs_start| {
                                            const lhs_slice = out.items[lhs_start .. out.items.len - 1];
                                            if ((possibleOnesI32(lhs_slice) & ~rhs_u) == 0) {
                                                out.items.len -= 1;
                                                changed = true;
                                                continue;
                                            }
                                        }
                                    }
                                },
                                0x74, 0x75, 0x76, 0x77, 0x78 => if (shift_amt == 0) {
                                    out.items.len -= 1;
                                    changed = true;
                                    continue;
                                },
                                0x46 => {
                                    if (rhs == 0) {
                                        out.items.len -= 1;
                                        _ = try emitOrFoldI32Eqz(arena, &out);
                                        changed = true;
                                        continue;
                                    }
                                    if (rhs == 1 and out.items.len >= 2) {
                                        const lhs_slice = out.items[0 .. out.items.len - 1];
                                        if (isBoolProducer(lhs_slice[lhs_slice.len - 1]) or possibleOnesI32(lhs_slice) <= 1) {
                                            out.items.len -= 1;
                                            changed = true;
                                            continue;
                                        }
                                    }
                                },
                                0x47 => {
                                    if (rhs == 0 and out.items.len >= 2) {
                                        const lhs_slice = out.items[0 .. out.items.len - 1];
                                        if (lhs_slice[lhs_slice.len - 1] == .numeric_op and lhs_slice[lhs_slice.len - 1].numeric_op == 0x73) {
                                            out.items[out.items.len - 2] = .{ .numeric_op = 0x47 };
                                            out.items.len -= 1;
                                            changed = true;
                                            continue;
                                        }
                                        if (isBoolProducer(lhs_slice[lhs_slice.len - 1]) or possibleOnesI32(lhs_slice) <= 1) {
                                            out.items.len -= 1;
                                            changed = true;
                                            continue;
                                        }
                                    }
                                    if (rhs == 1 and out.items.len >= 2) {
                                        const lhs_slice = out.items[0 .. out.items.len - 1];
                                        if (isBoolProducer(lhs_slice[lhs_slice.len - 1]) or possibleOnesI32(lhs_slice) <= 1) {
                                            out.items.len -= 1;
                                            _ = try emitOrFoldI32Eqz(arena, &out);
                                            changed = true;
                                            continue;
                                        }
                                    }
                                },
                                0x6c => {
                                    if (rhs == 1) {
                                        out.items.len -= 1;
                                        changed = true;
                                        continue;
                                    }
                                    if (rhs_u > 1 and std.math.isPowerOfTwo(rhs_u)) {
                                        out.items[out.items.len - 1] = .{ .i32_const = @intCast(@ctz(rhs_u)) };
                                        out.append(arena, .{ .numeric_op = 0x74 }) catch return error.OutOfMemory;
                                        changed = true;
                                        continue;
                                    }
                                    if (optimize_mode == .fast and out.items.len >= 2) {
                                        if (extractLocalGetOrTee(out.items[out.items.len - 2])) |l| {
                                            if (rhs_u > 2 and std.math.isPowerOfTwo(rhs_u - 1)) {
                                                const k: i32 = @intCast(@ctz(rhs_u - 1));
                                                out.items[out.items.len - 1] = .{ .i32_const = k };
                                                try out.appendSlice(arena, &.{
                                                    .{ .numeric_op = 0x74 }, // i32.shl
                                                    .{ .local_get = l },
                                                    .{ .numeric_op = 0x6a }, // i32.add
                                                });
                                                changed = true;
                                                continue;
                                            }
                                            if (rhs_u > 2 and rhs_u < 0x8000_0000 and std.math.isPowerOfTwo(rhs_u + 1)) {
                                                const k: i32 = @intCast(@ctz(rhs_u + 1));
                                                out.items[out.items.len - 1] = .{ .i32_const = k };
                                                try out.appendSlice(arena, &.{
                                                    .{ .numeric_op = 0x74 }, // i32.shl
                                                    .{ .local_get = l },
                                                    .{ .numeric_op = 0x6b }, // i32.sub
                                                });
                                                changed = true;
                                                continue;
                                            }
                                        }
                                    }
                                },
                                0x6d => {
                                    if (rhs == 1) {
                                        out.items.len -= 1;
                                        changed = true;
                                        continue;
                                    }
                                    if (optimize_mode == .fast and rhs > 1 and out.items.len >= 2) {
                                        if (extractLocalGetOrTee(out.items[out.items.len - 2])) |l| {
                                            out.items.len -= 1;
                                            try emitStrengthReducedDivS32(arena, &out, rhs_u, l);
                                            changed = true;
                                            continue;
                                        }
                                    }
                                },
                                0x6e => {
                                    if (rhs_u == 1) {
                                        out.items.len -= 1;
                                        changed = true;
                                        continue;
                                    }
                                    if (rhs_u > 1 and std.math.isPowerOfTwo(rhs_u)) {
                                        out.items[out.items.len - 1] = .{ .i32_const = @intCast(@ctz(rhs_u)) };
                                        out.append(arena, .{ .numeric_op = 0x76 }) catch return error.OutOfMemory;
                                        changed = true;
                                        continue;
                                    }
                                    if (optimize_mode == .fast and rhs_u > 1 and out.items.len >= 2) {
                                        const lhs_local = extractLocalGetOrTee(out.items[out.items.len - 2]);
                                        const saved_len = out.items.len - 1;
                                        out.items.len = saved_len;
                                        if (try emitMagicDivU32(arena, &out, rhs_u, lhs_local)) {
                                            changed = true;
                                            continue;
                                        }
                                        out.append(arena, .{ .i32_const = rhs }) catch return error.OutOfMemory;
                                    }
                                },
                                0x6f => {
                                    if (optimize_mode == .fast and rhs > 1 and out.items.len >= 2) {
                                        if (extractLocalGetOrTee(out.items[out.items.len - 2])) |l| {
                                            out.items[out.items.len - 1] = .{ .local_get = l };
                                            try emitStrengthReducedDivS32(arena, &out, rhs_u, l);
                                            try out.appendSlice(arena, &.{
                                                .{ .i32_const = rhs },
                                                .{ .numeric_op = 0x6c }, // i32.mul
                                                .{ .numeric_op = 0x6b }, // i32.sub
                                            });
                                            changed = true;
                                            continue;
                                        }
                                    }
                                },
                                0x70 => {
                                    if (rhs_u >= 1 and std.math.isPowerOfTwo(rhs_u)) {
                                        out.items[out.items.len - 1] = .{ .i32_const = @bitCast(rhs_u - 1) };
                                        out.append(arena, .{ .numeric_op = 0x71 }) catch return error.OutOfMemory;
                                        changed = true;
                                        continue;
                                    }
                                    if (optimize_mode == .fast and rhs_u > 1 and out.items.len >= 2) {
                                        if (extractLocalGetOrTee(out.items[out.items.len - 2])) |l| {
                                            out.items[out.items.len - 1] = .{ .local_get = l };
                                            _ = try emitMagicDivU32(arena, &out, rhs_u, l);
                                            try out.appendSlice(arena, &.{
                                                .{ .i32_const = rhs },
                                                .{ .numeric_op = 0x6c }, // i32.mul
                                                .{ .numeric_op = 0x6b }, // i32.sub
                                            });
                                            changed = true;
                                            continue;
                                        }
                                    }
                                },
                                else => {},
                            }
                        },
                        .i64_const => |rhs| {
                            const rhs_u: u64 = @bitCast(rhs);
                            const shift_amt: u6 = @truncate(rhs_u);
                            switch (op) {
                                0x7c, 0x7d, 0x84, 0x85 => if (rhs == 0) {
                                    out.items.len -= 1;
                                    changed = true;
                                    continue;
                                },
                                0x83 => {
                                    if (rhs == -1) {
                                        out.items.len -= 1;
                                        changed = true;
                                        continue;
                                    }
                                    if (out.items.len >= 2) {
                                        if (findPrevSingleValueExprStart(out.items, out.items.len - 1)) |lhs_start| {
                                            const lhs_slice = out.items[lhs_start .. out.items.len - 1];
                                            if ((possibleOnesI64(lhs_slice) & ~rhs_u) == 0) {
                                                out.items.len -= 1;
                                                changed = true;
                                                continue;
                                            }
                                        }
                                    }
                                },
                                0x86, 0x87, 0x88, 0x89, 0x8a => if (shift_amt == 0) {
                                    out.items.len -= 1;
                                    changed = true;
                                    continue;
                                },
                                0x51 => if (rhs == 0) {
                                    out.items[out.items.len - 1] = .{ .numeric_op = 0x50 };
                                    changed = true;
                                    continue;
                                },
                                0x7e => {
                                    if (rhs == 1) {
                                        out.items.len -= 1;
                                        changed = true;
                                        continue;
                                    }
                                    if (rhs_u > 1 and std.math.isPowerOfTwo(rhs_u)) {
                                        out.items[out.items.len - 1] = .{ .i64_const = @intCast(@ctz(rhs_u)) };
                                        out.append(arena, .{ .numeric_op = 0x86 }) catch return error.OutOfMemory;
                                        changed = true;
                                        continue;
                                    }
                                    if (optimize_mode == .fast and out.items.len >= 2) {
                                        if (extractLocalGetOrTee(out.items[out.items.len - 2])) |l| {
                                            if (rhs_u > 2 and std.math.isPowerOfTwo(rhs_u - 1)) {
                                                const k: i64 = @intCast(@ctz(rhs_u - 1));
                                                out.items[out.items.len - 1] = .{ .i64_const = k };
                                                try out.appendSlice(arena, &.{
                                                    .{ .numeric_op = 0x86 }, // i64.shl
                                                    .{ .local_get = l },
                                                    .{ .numeric_op = 0x7c }, // i64.add
                                                });
                                                changed = true;
                                                continue;
                                            }
                                            if (rhs_u > 2 and rhs_u < 0x8000_0000_0000_0000 and std.math.isPowerOfTwo(rhs_u + 1)) {
                                                const k: i64 = @intCast(@ctz(rhs_u + 1));
                                                out.items[out.items.len - 1] = .{ .i64_const = k };
                                                try out.appendSlice(arena, &.{
                                                    .{ .numeric_op = 0x86 }, // i64.shl
                                                    .{ .local_get = l },
                                                    .{ .numeric_op = 0x7d }, // i64.sub
                                                });
                                                changed = true;
                                                continue;
                                            }
                                        }
                                    }
                                },
                                0x7f => if (rhs == 1) {
                                    out.items.len -= 1;
                                    changed = true;
                                    continue;
                                },
                                0x80 => {
                                    if (rhs_u == 1) {
                                        out.items.len -= 1;
                                        changed = true;
                                        continue;
                                    }
                                    if (rhs_u > 1 and std.math.isPowerOfTwo(rhs_u)) {
                                        out.items[out.items.len - 1] = .{ .i64_const = @intCast(@ctz(rhs_u)) };
                                        out.append(arena, .{ .numeric_op = 0x88 }) catch return error.OutOfMemory;
                                        changed = true;
                                        continue;
                                    }
                                },
                                0x82 => if (rhs_u >= 1 and std.math.isPowerOfTwo(rhs_u)) {
                                    out.items[out.items.len - 1] = .{ .i64_const = @bitCast(rhs_u - 1) };
                                    out.append(arena, .{ .numeric_op = 0x83 }) catch return error.OutOfMemory;
                                    changed = true;
                                    continue;
                                },
                                else => {},
                            }
                        },
                        else => {},
                    }
                }

                // Commutative left-constant peepholes when RHS is a pure zero-pop instruction
                if (out.items.len >= 2 and isPureZeroPopInstr(out.items[out.items.len - 1])) {
                    const rhs_inst = out.items[out.items.len - 1];
                    switch (out.items[out.items.len - 2]) {
                        .i32_const => |lhs| {
                            const lhs_u: u32 = @bitCast(lhs);
                            switch (op) {
                                0x6a, 0x72, 0x73 => if (lhs == 0) {
                                    out.items[out.items.len - 2] = rhs_inst;
                                    out.items.len -= 1;
                                    changed = true;
                                    continue;
                                },
                                0x71 => if (lhs == -1) {
                                    out.items[out.items.len - 2] = rhs_inst;
                                    out.items.len -= 1;
                                    changed = true;
                                    continue;
                                },
                                0x46 => if (lhs == 0) {
                                    out.items[out.items.len - 2] = rhs_inst;
                                    out.items[out.items.len - 1] = .{ .numeric_op = 0x45 };
                                    changed = true;
                                    continue;
                                },
                                0x6c => {
                                    if (lhs == 1) {
                                        out.items[out.items.len - 2] = rhs_inst;
                                        out.items.len -= 1;
                                        changed = true;
                                        continue;
                                    }
                                    if (lhs_u > 1 and std.math.isPowerOfTwo(lhs_u)) {
                                        out.items[out.items.len - 2] = rhs_inst;
                                        out.items[out.items.len - 1] = .{ .i32_const = @intCast(@ctz(lhs_u)) };
                                        out.append(arena, .{ .numeric_op = 0x74 }) catch return error.OutOfMemory;
                                        changed = true;
                                        continue;
                                    }
                                },
                                else => {},
                            }
                        },
                        .i64_const => |lhs| {
                            const lhs_u: u64 = @bitCast(lhs);
                            switch (op) {
                                0x7c, 0x84, 0x85 => if (lhs == 0) {
                                    out.items[out.items.len - 2] = rhs_inst;
                                    out.items.len -= 1;
                                    changed = true;
                                    continue;
                                },
                                0x83 => if (lhs == -1) {
                                    out.items[out.items.len - 2] = rhs_inst;
                                    out.items.len -= 1;
                                    changed = true;
                                    continue;
                                },
                                0x51 => if (lhs == 0) {
                                    out.items[out.items.len - 2] = rhs_inst;
                                    out.items[out.items.len - 1] = .{ .numeric_op = 0x50 };
                                    changed = true;
                                    continue;
                                },
                                0x7e => {
                                    if (lhs == 1) {
                                        out.items[out.items.len - 2] = rhs_inst;
                                        out.items.len -= 1;
                                        changed = true;
                                        continue;
                                    }
                                    if (lhs_u > 1 and std.math.isPowerOfTwo(lhs_u)) {
                                        out.items[out.items.len - 2] = rhs_inst;
                                        out.items[out.items.len - 1] = .{ .i64_const = @intCast(@ctz(lhs_u)) };
                                        out.append(arena, .{ .numeric_op = 0x86 }) catch return error.OutOfMemory;
                                        changed = true;
                                        continue;
                                    }
                                },
                                else => {},
                            }
                        },
                        else => {},
                    }
                }
            },
            .raw => |r| {
                if (r.len > 0 and (r[0] == 0x1b or r[0] == 0x1c)) {
                    // `select` on `i32.eqz`: swap pure zero-pop arms and pop `i32.eqz`
                    if (out.items.len >= 1 and out.items[out.items.len - 1] == .numeric_op and out.items[out.items.len - 1].numeric_op == 0x45) {
                        if (findPrevSingleValueExprStart(out.items, out.items.len - 1)) |cond_start| {
                            if (cond_start >= 2 and isPureZeroPopInstr(out.items[cond_start - 2]) and isPureZeroPopInstr(out.items[cond_start - 1])) {
                                const tmp = out.items[cond_start - 2];
                                out.items[cond_start - 2] = out.items[cond_start - 1];
                                out.items[cond_start - 1] = tmp;
                                _ = out.pop();
                                changed = true;
                            }
                        }
                    }
                    // `select(a, a, cond) -> a` and constant-cond `select` when arms/cond are pure zero-pop
                    if (out.items.len >= 3 and
                        isPureZeroPopInstr(out.items[out.items.len - 3]) and
                        isPureZeroPopInstr(out.items[out.items.len - 2]) and
                        isPureZeroPopInstr(out.items[out.items.len - 1]))
                    {
                        const val1 = out.items[out.items.len - 3];
                        const val2 = out.items[out.items.len - 2];
                        const cond = out.items[out.items.len - 1];
                        if (instrEql(val1, val2)) {
                            out.items.len -= 2;
                            changed = true;
                            continue;
                        }
                        if (cond == .i32_const) {
                            out.items[out.items.len - 3] = if (cond.i32_const != 0) val1 else val2;
                            out.items.len -= 2;
                            changed = true;
                            continue;
                        }
                    }
                }
            },
            else => {},
        }
        out.append(arena, inst) catch return error.OutOfMemory;
    }
    list.* = out;
    return changed;
}

// ── Pass B: Control-Flow Simplification ──────────────────────────────────

fn hasBranchToDepth(instrs: []const Instr, target_depth: u32) bool {
    for (instrs) |inst| {
        switch (inst) {
            .br => |l| if (l == target_depth) return true,
            .br_if => |l| if (l == target_depth) return true,
            .br_table => |targets| {
                for (targets) |l| {
                    if (l == target_depth) return true;
                }
            },
            .block => |b| if (hasBranchToDepth(b.body.items, target_depth + 1)) return true,
            .loop => |l| if (hasBranchToDepth(l.body.items, target_depth + 1)) return true,
            .if_ => |i| {
                if (hasBranchToDepth(i.then_body.items, target_depth + 1)) return true;
                if (i.has_else and hasBranchToDepth(i.else_body.items, target_depth + 1)) return true;
            },
            else => {},
        }
    }
    return false;
}

fn canInlineBlock(body: []const Instr) bool {
    for (body) |inst| {
        if (inst.isUnconditionalTransfer()) return false;
    }
    return !hasBranchToDepth(body, 0);
}

fn decrementOuterLabels(instrs: []Instr, min_depth: u32) void {
    for (instrs) |*inst| {
        switch (inst.*) {
            .br => |*l| if (l.* > min_depth) {
                l.* -= 1;
            },
            .br_if => |*l| if (l.* > min_depth) {
                l.* -= 1;
            },
            .br_table => |targets| {
                for (targets) |*l| {
                    if (l.* > min_depth) l.* -= 1;
                }
            },
            .block => |*b| decrementOuterLabels(b.body.items, min_depth + 1),
            .loop => |*l| decrementOuterLabels(l.body.items, min_depth + 1),
            .if_ => |*i| {
                decrementOuterLabels(i.then_body.items, min_depth + 1);
                if (i.has_else) decrementOuterLabels(i.else_body.items, min_depth + 1);
            },
            else => {},
        }
    }
}

fn isBranchFreeStraightLine(instrs: []const Instr) bool {
    for (instrs) |inst| {
        switch (inst) {
            .block, .loop, .if_, .br, .br_if, .br_table, .return_, .unreachable_ => return false,
            else => {},
        }
    }
    return true;
}

fn sliceStackDelta(instrs: []const Instr) ?isize {
    var height: isize = 0;
    for (instrs) |inst| {
        const pops_and_pushes: struct { pops: isize, pushes: isize } = switch (inst) {
            .nop => .{ .pops = 0, .pushes = 0 },
            .local_get, .i32_const, .i64_const, .ref_func => .{ .pops = 0, .pushes = 1 },
            .local_set => .{ .pops = 1, .pushes = 0 },
            .local_tee => .{ .pops = 1, .pushes = 1 },
            .numeric_op => |op| switch (op) {
                0x45, 0x50, 0x67...0x69, 0x79...0x7b, 0x8b...0x91, 0x99...0x9f, 0xa7...0xc4 => .{ .pops = 1, .pushes = 1 },
                0x46...0x4f, 0x51...0x66, 0x6a...0x78, 0x7c...0x8a, 0x92...0x98, 0xa0...0xa6 => .{ .pops = 2, .pushes = 1 },
                else => return null,
            },
            .raw => |r| blk: {
                if (r.len == 0) return null;
                break :blk switch (r[0]) {
                    0x1a, 0x24 => .{ .pops = 1, .pushes = 0 },
                    0x1b, 0x1c => .{ .pops = 3, .pushes = 1 },
                    0x36...0x3e => .{ .pops = 2, .pushes = 0 },
                    0x23, 0x3f, 0x43, 0x44, 0xd0 => .{ .pops = 0, .pushes = 1 },
                    0x28...0x35, 0x40, 0xd1 => .{ .pops = 1, .pushes = 1 },
                    else => return null,
                };
            },
            else => return null,
        };
        if (height < pops_and_pushes.pops) return null;
        height = height - pops_and_pushes.pops + pops_and_pushes.pushes;
    }
    return height;
}

fn stripRedundantCondTests(out: *InstrList) bool {
    var stripped = false;
    while (out.items.len >= 2) {
        const prev = out.items[out.items.len - 2];
        const last = out.items[out.items.len - 1];
        if (prev == .i32_const and prev.i32_const == 0 and last == .numeric_op and last.numeric_op == 0x47) {
            out.items.len -= 2;
            stripped = true;
        } else if (prev == .numeric_op and prev.numeric_op == 0x45 and last == .numeric_op and last.numeric_op == 0x45) {
            out.items.len -= 2;
            stripped = true;
        } else {
            break;
        }
    }
    if (out.items.len >= 1 and out.items[out.items.len - 1] == .numeric_op and out.items[out.items.len - 1].numeric_op == 0x73) {
        out.items[out.items.len - 1] = .{ .numeric_op = 0x47 };
        stripped = true;
    }
    return stripped;
}

fn simplifyControlFlow(arena: std.mem.Allocator, list: *InstrList) Error!bool {
    var changed = false;

    for (list.items) |*inst| {
        switch (inst.*) {
            .block => |*b| {
                if (try simplifyControlFlow(arena, &b.body)) changed = true;
            },
            .loop => |*l| {
                if (try simplifyControlFlow(arena, &l.body)) changed = true;
            },
            .if_ => |*i| {
                if (try simplifyControlFlow(arena, &i.then_body)) changed = true;
                if (i.has_else and try simplifyControlFlow(arena, &i.else_body)) changed = true;
            },
            else => {},
        }
    }

    var out: InstrList = .empty;
    out.ensureTotalCapacity(arena, list.items.len) catch return error.OutOfMemory;

    for (list.items) |inst| {
        switch (inst) {
            .nop => {
                changed = true;
                continue;
            },
            .br_if => |label| {
                if (stripRedundantCondTests(&out)) {
                    changed = true;
                }
                if (out.items.len > 0 and out.items[out.items.len - 1] == .i32_const) {
                    const cond = out.pop().?.i32_const;
                    changed = true;
                    if (cond != 0) {
                        out.append(arena, .{ .br = label }) catch return error.OutOfMemory;
                    }
                    continue;
                }
            },
            .if_ => |if_inst| {
                if (stripRedundantCondTests(&out)) {
                    changed = true;
                }
                if (out.items.len > 0 and out.items[out.items.len - 1] == .i32_const) {
                    const cond = out.pop().?.i32_const;
                    changed = true;
                    const chosen_body = if (cond != 0) if_inst.then_body else if_inst.else_body;
                    if (canInlineBlock(chosen_body.items)) {
                        decrementOuterLabels(chosen_body.items, 0);
                        out.appendSlice(arena, chosen_body.items) catch return error.OutOfMemory;
                    } else {
                        out.append(arena, .{
                            .block = .{
                                .block_type = if_inst.block_type,
                                .body = chosen_body,
                            },
                        }) catch return error.OutOfMemory;
                    }
                    continue;
                }
            },
            .block => |b_inst| {
                if ((b_inst.block_type.isEmpty() and b_inst.body.items.len == 0) or
                    canInlineBlock(b_inst.body.items))
                {
                    changed = true;
                    decrementOuterLabels(b_inst.body.items, 0);
                    out.appendSlice(arena, b_inst.body.items) catch return error.OutOfMemory;
                    continue;
                }
                if (b_inst.block_type.isEmpty()) {
                    const items = b_inst.body.items;
                    if (items.len == 3 and
                        isPureZeroPopInstr(items[0]) and
                        items[1] == .br_if and items[1].br_if == 0 and
                        items[2] == .unreachable_)
                    {
                        var then_body: InstrList = .empty;
                        then_body.append(arena, .unreachable_) catch return error.OutOfMemory;
                        out.append(arena, items[0]) catch return error.OutOfMemory;
                        out.append(arena, .{ .numeric_op = 0x45 }) catch return error.OutOfMemory;
                        out.append(arena, .{
                            .if_ = .{
                                .block_type = b_inst.block_type,
                                .then_body = then_body,
                            },
                        }) catch return error.OutOfMemory;
                        changed = true;
                        continue;
                    }
                    if (items.len == 4 and
                        isPureZeroPopInstr(items[0]) and
                        items[1] == .numeric_op and items[1].numeric_op == 0x45 and
                        items[2] == .br_if and items[2].br_if == 0 and
                        items[3] == .unreachable_)
                    {
                        var then_body: InstrList = .empty;
                        then_body.append(arena, .unreachable_) catch return error.OutOfMemory;
                        out.append(arena, items[0]) catch return error.OutOfMemory;
                        out.append(arena, .{
                            .if_ = .{
                                .block_type = b_inst.block_type,
                                .then_body = then_body,
                            },
                        }) catch return error.OutOfMemory;
                        changed = true;
                        continue;
                    }
                    if (items.len >= 2 and
                        items[items.len - 1] == .unreachable_ and
                        items[items.len - 2] == .block)
                    {
                        const inner_blk = items[items.len - 2].block;
                        const inner_items = inner_blk.body.items;
                        if (inner_blk.block_type.isEmpty() and
                            inner_items.len >= 3 and
                            inner_items[inner_items.len - 2] == .br_if and inner_items[inner_items.len - 2].br_if == 0 and
                            inner_items[inner_items.len - 1] == .br and inner_items[inner_items.len - 1].br == 1)
                        {
                            const setup_slice = items[0 .. items.len - 2];
                            const cond_slice = inner_items[0 .. inner_items.len - 2];
                            if (isBranchFreeStraightLine(setup_slice) and
                                isBranchFreeStraightLine(cond_slice) and
                                sliceStackDelta(setup_slice) == @as(?isize, 0) and
                                sliceStackDelta(cond_slice) == @as(?isize, 1))
                            {
                                var then_body: InstrList = .empty;
                                then_body.append(arena, .unreachable_) catch return error.OutOfMemory;
                                out.appendSlice(arena, setup_slice) catch return error.OutOfMemory;
                                out.appendSlice(arena, cond_slice) catch return error.OutOfMemory;
                                out.append(arena, .{
                                    .if_ = .{
                                        .block_type = b_inst.block_type,
                                        .then_body = then_body,
                                    },
                                }) catch return error.OutOfMemory;
                                changed = true;
                                continue;
                            }
                        }
                    }
                }
            },
            else => {},
        }
        out.append(arena, inst) catch return error.OutOfMemory;
    }

    list.* = out;
    return changed;
}

// ── Pass C: Dead-Code Elimination (Intrafunction) ────────────────────────

fn eliminateDeadCode(list: *InstrList) bool {
    var changed = false;

    for (list.items, 0..) |*inst, i| {
        switch (inst.*) {
            .block => |*b| {
                if (eliminateDeadCode(&b.body)) changed = true;
            },
            .loop => |*l| {
                if (eliminateDeadCode(&l.body)) changed = true;
            },
            .if_ => |*if_inst| {
                if (eliminateDeadCode(&if_inst.then_body)) changed = true;
                if (if_inst.has_else and eliminateDeadCode(&if_inst.else_body)) changed = true;
            },
            else => {},
        }

        if (inst.isUnconditionalTransfer()) {
            if (i + 1 < list.items.len) {
                list.shrinkRetainingCapacity(i + 1);
                changed = true;
            }
            break;
        }
    }

    return changed;
}

// ── Dead-function removal and index remapping ────────────────────────────

fn markLiveFunc(
    num_funcs: usize,
    live: []bool,
    worklist: *std.ArrayListUnmanaged(u32),
    allocator: std.mem.Allocator,
    idx: u32,
) Error!void {
    if (idx >= num_funcs) return;
    if (!live[idx]) {
        live[idx] = true;
        worklist.append(allocator, idx) catch return error.OutOfMemory;
    }
}

fn scanExprFuncRefs(
    bytes: []const u8,
    num_funcs: usize,
    live: []bool,
    worklist: *std.ArrayListUnmanaged(u32),
    uses_table: *bool,
    allocator: std.mem.Allocator,
) Error!void {
    var pos: usize = 0;
    while (pos < bytes.len) {
        const decoded = instr.decode(bytes, &pos) catch return error.InvalidInput;
        if (decoded.prefix == 0 and (decoded.code == 0x10 or decoded.code == 0x12 or decoded.code == 0xd2)) {
            const idx = readU32(bytes, &pos) catch return error.InvalidInput;
            try markLiveFunc(num_funcs, live, worklist, allocator, idx);
        } else {
            if ((decoded.prefix == 0 and (decoded.code == 0x11 or decoded.code == 0x13 or decoded.code == 0x25 or decoded.code == 0x26)) or
                (decoded.prefix == 0xfc and decoded.code >= 12 and decoded.code <= 17))
            {
                uses_table.* = true;
            }
            instr.skipImmediates(decoded.shape, bytes, &pos) catch return error.InvalidInput;
        }
    }
}

fn rewriteExprFuncIndices(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    old_to_new: []const u32,
) Error![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    out.ensureTotalCapacity(allocator, bytes.len) catch return error.OutOfMemory;

    var pos: usize = 0;
    while (pos < bytes.len) {
        const start = pos;
        const decoded = instr.decode(bytes, &pos) catch return error.InvalidInput;
        if (decoded.prefix == 0 and (decoded.code == 0x10 or decoded.code == 0x12 or decoded.code == 0xd2)) {
            const old_idx = readU32(bytes, &pos) catch return error.InvalidInput;
            if (old_idx >= old_to_new.len) return error.InvalidInput;
            const new_idx = old_to_new[old_idx];
            out.append(allocator, @intCast(decoded.code)) catch return error.OutOfMemory;
            try appendU32Leb(allocator, &out, new_idx);
        } else {
            instr.skipImmediates(decoded.shape, bytes, &pos) catch return error.InvalidInput;
            out.appendSlice(allocator, bytes[start..pos]) catch return error.OutOfMemory;
        }
    }

    return out.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

const max_inline_params = 16;
const max_inline_locals = 32;
const max_inline_results = 4;
const max_inline_total_locals = max_inline_params + max_inline_locals;

const TrivialLeaf = struct {
    body_bytes: []const u8 = &.{},
    effective_end: usize = 0,
    op_count: u32 = 0,
    param_types: [max_inline_params]types.ValType = undefined,
    param_count: u8 = 0,
    result_types: [max_inline_results]types.ValType = undefined,
    result_count: u8 = 0,
    local_types: [max_inline_locals]types.ValType = undefined,
    local_count: u8 = 0,
    prefix_params: u8 = 0,
    leading_end_offsets: [max_inline_params]usize = @splat(0),
    needs_local_zero_init: [max_inline_locals]bool = @splat(false),
    needs_result_block: bool = false,
    has_early_return: bool = false,
    uses_global_op: bool = false,
    inner_callees: [4]u32 = @splat(types.invalid_index),
    inner_calls_count: u8 = 0,
};

const TrivialKind = union(enum) {
    none,
    leaf: TrivialLeaf,
    forward: struct {
        callee: u32,
        is_tail: bool,
    },
};

fn getFuncSignature(module: *const Mod.Module, func: *const Mod.Func) ?Mod.FuncSignature {
    if (func.decl.type_var == .index and func.decl.type_var.index < module.module_types.items.len) {
        return switch (module.module_types.items[func.decl.type_var.index]) {
            .func_type => |ft| ft,
            else => null,
        };
    }
    if (func.decl.sig.params.len > 0 or func.decl.sig.results.len > 0) {
        return .{ .params = func.decl.sig.params, .results = func.decl.sig.results };
    }
    return null;
}

fn isTrivialTail(tail: []const u8) bool {
    return std.mem.eql(u8, tail, &.{ 0x0f, 0x0b });
}

fn isZeroInitSupportedType(vt: types.ValType) bool {
    return switch (vt) {
        .i32, .i64, .f32, .f64, .v128, .funcref, .externref => true,
        else => false,
    };
}

fn depth0StackDelta(code: u8) ?i32 {
    return switch (code) {
        0x1a, 0x21, 0x24 => -1,
        0x1b, 0x1c, 0x36...0x3e => -2,
        0x20, 0x23, 0x3f, 0x41...0x44, 0xd0, 0xd2 => 1,
        0x22, 0x28...0x35, 0x40, 0x45, 0x50, 0x67...0x69, 0x79...0x7b, 0x8b...0x91, 0x99...0x9f, 0xa7...0xc4, 0xd1 => 0,
        0x46...0x4f, 0x51...0x66, 0x6a...0x78, 0x7c...0x8a, 0x92...0x98, 0xa0...0xa6 => -1,
        else => null,
    };
}

fn depth0MiscStackDelta(misc_op: u32) ?i32 {
    return switch (misc_op) {
        0x00...0x07, 0x09, 0x0d => 0,
        0x08, 0x0a, 0x0b, 0x0c, 0x0e, 0x11 => -3,
        0x0f => -1,
        0x10 => 1,
        else => null,
    };
}

fn depth0SimdStackDelta(simd_op: u32) ?i32 {
    return switch (simd_op) {
        0x0c => 1,
        0x00...0x0a,
        0x0f...0x16,
        0x18,
        0x19,
        0x1b,
        0x1d,
        0x1f,
        0x21,
        0x4d,
        0x53,
        0x5c...0x64,
        0x67...0x6a,
        0x74,
        0x75,
        0x7a,
        0x7c...0x81,
        0x83,
        0x84,
        0x87...0x8a,
        0x94,
        0xa0,
        0xa1,
        0xa3,
        0xa4,
        0xa7...0xaa,
        0xc0,
        0xc1,
        0xc3,
        0xc4,
        0xc7...0xca,
        0xe0,
        0xe1,
        0xe3,
        0xec,
        0xed,
        0xef,
        0xf8...0xff,
        0x101...0x104,
        => 0,
        0x0d,
        0x0e,
        0x17,
        0x1a,
        0x1c,
        0x1e,
        0x20,
        0x22...0x4c,
        0x4e...0x51,
        0x54...0x57,
        0x65,
        0x66,
        0x6b...0x73,
        0x76...0x79,
        0x7b,
        0x82,
        0x85,
        0x86,
        0x8b...0x93,
        0x95...0x99,
        0x9b...0x9f,
        0xab...0xae,
        0xb1,
        0xb5...0xba,
        0xbc...0xbf,
        0xcb...0xce,
        0xd1,
        0xd5...0xdf,
        0xe4...0xeb,
        0xf0...0xf7,
        0x100,
        0x10d...0x112,
        => -1,
        0x0b,
        0x52,
        0x58...0x5b,
        0x105...0x10c,
        0x113,
        0x114,
        => -2,
        else => null,
    };
}

fn classifyTrivialFunc(
    module: *const Mod.Module,
    fidx: u32,
    func: *const Mod.Func,
    optimize_mode: OptimizeMode,
    call_count: u32,
    is_externally_used: bool,
) TrivialKind {
    if (func.is_import or func.code_bytes.len == 0) return .none;
    const mode_max_params: usize = switch (optimize_mode) {
        .small => 6,
        .fast => max_inline_params,
    };
    const mode_max_locals: usize = switch (optimize_mode) {
        .small => 12,
        .fast => max_inline_locals,
    };
    const mode_max_results: usize = switch (optimize_mode) {
        .small => 2,
        .fast => max_inline_results,
    };
    if (func.local_types.items.len > mode_max_locals) return .none;
    const sig = getFuncSignature(module, func) orelse return .none;
    if (sig.params.len > mode_max_params or sig.results.len > mode_max_results) return .none;

    for (sig.params, 0..) |p, i| {
        if (!isAllowedValType(p, Mod.FuncSignature.concreteIdxAt(sig.param_type_idxs, i))) return .none;
    }
    for (sig.results, 0..) |r, i| {
        if (!isAllowedValType(r, Mod.FuncSignature.concreteIdxAt(sig.result_type_idxs, i))) return .none;
    }
    for (func.local_types.items, 0..) |lt, i| {
        const tidx = if (i < func.local_type_idxs.items.len) func.local_type_idxs.items[i] else types.invalid_index;
        if (!isAllowedValType(lt, tidx) or !isZeroInitSupportedType(lt)) return .none;
    }

    const bytes = func.code_bytes;
    if (bytes[bytes.len - 1] != 0x0b) return .none;

    if (sig.params.len == 0 and func.local_types.items.len == 0) {
        var fpos: usize = 0;
        if (instr.decode(bytes, &fpos)) |decoded| {
            if (decoded.prefix == 0 and (decoded.code == 0x10 or decoded.code == 0x12)) {
                if (readU32(bytes, &fpos)) |callee| {
                    if (isTrivialTail(bytes[fpos..]) and callee < module.funcs.items.len and callee != fidx) {
                        if (getFuncSignature(module, &module.funcs.items[callee])) |callee_sig| {
                            if (Mod.FuncSignature.eql(sig, callee_sig)) {
                                return .{ .forward = .{ .callee = callee, .is_tail = decoded.code == 0x12 } };
                            }
                        }
                    }
                } else |_| {}
            }
        } else |_| {}
    }

    const body_end = bytes.len - 1;
    var effective_end: usize = body_end;
    var pos: usize = 0;
    var depth: u32 = 0;
    var block_types: [32]i64 = undefined;
    var op_count: u32 = 0;
    var depth0_stack: i32 = 0;
    var depth0_stack_exact: bool = true;
    var had_trailing_return: bool = false;

    const param_count: u32 = @intCast(sig.params.len);
    const local_count: u32 = @intCast(func.local_types.items.len);
    const total_locals: u32 = param_count + local_count;

    var local_use_counts: [max_inline_total_locals]u32 = @splat(0);
    var local_written_at_depth0: [max_inline_total_locals]bool = @splat(false);
    var needs_local_zero_init: [max_inline_locals]bool = @splat(false);

    var leading_matched: u8 = 0;
    var leading_still_matching: bool = true;
    var leading_end_offsets: [max_inline_params]usize = @splat(0);

    var needs_result_block: bool = false;
    var has_early_return: bool = false;
    var has_branch_to_func_block: bool = false;
    var uses_global_op: bool = false;
    var uses_global_set: bool = false;
    var has_loop: bool = false;
    var seen_cond_branch: bool = false;
    var inner_callees: [4]u32 = @splat(types.invalid_index);
    var inner_calls_count: u8 = 0;

    const max_scan_ops: u32 = switch (optimize_mode) {
        .small => 46,
        .fast => 221,
    };

    while (pos < body_end) {
        const instr_start = pos;
        const decoded = instr.decode(bytes, &pos) catch return .none;
        if (decoded.prefix == 0) {
            switch (decoded.code) {
                0x01 => {
                    leading_still_matching = false;
                    continue;
                },
                0x0b => {
                    if (depth == 0) return .none;
                    depth -= 1;
                    if (depth == 0) {
                        if (block_types[0] < -64) {
                            depth0_stack += 1;
                        } else if (block_types[0] != -64) {
                            depth0_stack_exact = false;
                        }
                    }
                    leading_still_matching = false;
                    continue;
                },
                0x05 => {
                    if (depth == 0) return .none;
                    leading_still_matching = false;
                    continue;
                },
                else => {},
            }
        }

        op_count += 1;
        if (op_count > max_scan_ops) return .none;

        if (decoded.prefix == 0) {
            if (decoded.code == 0x23 or decoded.code == 0x24) {
                uses_global_op = true;
                if (decoded.code == 0x24) uses_global_set = true;
            }
            switch (decoded.code) {
                0x11, 0x12, 0x13 => return .none,
                0x10 => {
                    leading_still_matching = false;
                    const callee = readU32(bytes, &pos) catch return .none;
                    const is_cond_call = (depth > 0 or has_early_return) and seen_cond_branch;
                    const max_inner_calls: u8 = if (call_count == 1 and !is_externally_used) 4 else 2;
                    if (optimize_mode != .fast or
                        has_loop or
                        inner_calls_count >= max_inner_calls or
                        callee >= module.funcs.items.len or
                        callee == fidx or
                        (!is_cond_call and module.funcs.items[callee].is_import))
                    {
                        return .none;
                    }
                    const callee_sig = getFuncSignature(module, &module.funcs.items[callee]) orelse return .none;
                    if (depth == 0) {
                        depth0_stack = depth0_stack - @as(i32, @intCast(callee_sig.params.len)) + @as(i32, @intCast(callee_sig.results.len));
                        if (depth0_stack < 0) depth0_stack_exact = false;
                    }
                    inner_callees[inner_calls_count] = callee;
                    inner_calls_count += 1;
                    continue;
                },
                0x00 => {
                    if (depth == 0) return .none;
                    leading_still_matching = false;
                    continue;
                },
                0x02, 0x03, 0x04 => {
                    leading_still_matching = false;
                    if (decoded.code == 0x03) {
                        has_loop = true;
                        if (inner_calls_count > 0) return .none;
                    } else if (decoded.code == 0x04) {
                        seen_cond_branch = true;
                    }
                    if (depth >= block_types.len or pos >= body_end) return .none;
                    const bt_byte = bytes[pos];
                    var bt_val: i64 = 0;
                    if (bt_byte == 0x40) {
                        pos += 1;
                        bt_val = -64;
                    } else if (bt_byte < 0x80) {
                        pos += 1;
                        bt_val = -@as(i64, bt_byte);
                        if (depth == 0 and bt_byte < 0x40) {
                            depth0_stack_exact = false;
                        }
                    } else {
                        return .none;
                    }
                    if (depth == 0 and decoded.code == 0x04) {
                        depth0_stack -= 1;
                    }
                    block_types[depth] = bt_val;
                    depth += 1;
                    continue;
                },
                0x0f => {
                    leading_still_matching = false;
                    if (depth == 0 and pos == body_end) {
                        had_trailing_return = true;
                        if (depth0_stack_exact and depth0_stack == @as(i32, @intCast(sig.results.len))) {
                            effective_end = instr_start;
                            op_count -= 1;
                        } else {
                            has_early_return = true;
                            needs_result_block = true;
                        }
                    } else if (depth > 0 and pos < body_end and (bytes[pos] == 0x0b or bytes[pos] == 0x05)) {
                        if (sig.results.len > 1 and (!depth0_stack_exact or depth0_stack != 0)) return .none;
                        has_early_return = true;
                        needs_result_block = true;
                    } else {
                        return .none;
                    }
                    continue;
                },
                0x0c, 0x0d => {
                    leading_still_matching = false;
                    if (decoded.code == 0x0d) seen_cond_branch = true;
                    const target = readU32(bytes, &pos) catch return .none;
                    if (target > depth) return .none;
                    if (target == depth) {
                        needs_result_block = true;
                        has_branch_to_func_block = true;
                    }
                    if (depth == 0) {
                        if (decoded.code == 0x0d) {
                            depth0_stack -= 1;
                        } else {
                            depth0_stack_exact = false;
                        }
                    }
                    continue;
                },
                0x0e => {
                    leading_still_matching = false;
                    seen_cond_branch = true;
                    const count = readU32(bytes, &pos) catch return .none;
                    for (0..@as(usize, count) + 1) |_| {
                        const target = readU32(bytes, &pos) catch return .none;
                        if (target > depth) return .none;
                        if (target == depth) {
                            needs_result_block = true;
                            has_branch_to_func_block = true;
                        }
                    }
                    if (depth == 0) depth0_stack_exact = false;
                    continue;
                },
                0x20 => {
                    const idx = readU32(bytes, &pos) catch return .none;
                    if (idx >= total_locals) return .none;
                    local_use_counts[idx] += 1;
                    if (depth == 0) depth0_stack += 1;
                    if (idx >= param_count and !local_written_at_depth0[idx]) {
                        needs_local_zero_init[idx - param_count] = true;
                    }
                    if (leading_still_matching and
                        depth == 0 and
                        op_count == @as(u32, leading_matched) + 1 and
                        idx == @as(u32, leading_matched) and
                        leading_matched < sig.params.len)
                    {
                        leading_end_offsets[leading_matched] = pos;
                        leading_matched += 1;
                    } else {
                        leading_still_matching = false;
                    }
                    continue;
                },
                0x21, 0x22 => {
                    leading_still_matching = false;
                    const idx = readU32(bytes, &pos) catch return .none;
                    if (idx >= total_locals) return .none;
                    local_use_counts[idx] += 1;
                    if (depth == 0) {
                        local_written_at_depth0[idx] = true;
                        if (decoded.code == 0x21) depth0_stack -= 1;
                    }
                    continue;
                },
                else => {
                    if (depth == 0) {
                        if (depth0StackDelta(@intCast(decoded.code))) |delta| {
                            depth0_stack += delta;
                            if (depth0_stack < 0) depth0_stack_exact = false;
                        } else {
                            depth0_stack_exact = false;
                        }
                    }
                },
            }
        } else if (depth == 0) {
            const maybe_delta = switch (decoded.prefix) {
                0xfc => depth0MiscStackDelta(decoded.code),
                0xfd => depth0SimdStackDelta(decoded.code),
                else => null,
            };
            if (maybe_delta) |delta| {
                depth0_stack += delta;
                if (depth0_stack < 0) depth0_stack_exact = false;
            } else {
                depth0_stack_exact = false;
            }
        }

        leading_still_matching = false;
        instr.skipImmediates(decoded.shape, bytes, &pos) catch return .none;
    }

    if (pos != body_end or depth != 0) return .none;
    if (needs_result_block and !depth0_stack_exact) return .none;
    if (sig.results.len > 1 and (has_branch_to_func_block or !depth0_stack_exact or depth0_stack != @as(i32, @intCast(sig.results.len)))) {
        return .none;
    }
    if (sig.params.len == 0 and op_count <= 1 and !had_trailing_return and !std.mem.eql(u8, bytes, &.{ 0x01, 0x0b })) {
        return .none;
    }

    var prefix_params: u8 = 0;
    if (!needs_result_block) {
        while (prefix_params < leading_matched) : (prefix_params += 1) {
            if (local_use_counts[prefix_params] != 1) break;
        }
    }

    switch (optimize_mode) {
        .small => {
            if (inner_calls_count > 0) return .none;
            if (call_count == 1 and !is_externally_used) {
                if (op_count > 45 or func.local_types.items.len > 8 or sig.params.len > 6) return .none;
            } else {
                if (uses_global_op) return .none;
                const allow_zero_local = func.local_types.items.len == 0 and
                    op_count <= 7 and
                    sig.params.len <= 2;
                const allow_one_local = func.local_types.items.len <= 1 and
                    !needs_result_block and
                    ((op_count <= 10 and sig.params.len <= 3 and (prefix_params == sig.params.len or (sig.params.len <= 2 and op_count <= 9))) or
                        (sig.params.len >= 1 and sig.params.len <= 2 and op_count <= 12 and bytes.len <= 32));
                if (!allow_zero_local and !allow_one_local) return .none;
            }
        },
        .fast => {
            if (uses_global_set and has_early_return) return .none;
            const single_internal = call_count == 1 and !is_externally_used;
            if (inner_calls_count == 0) {
                if (single_internal) {
                    if (op_count > 220 or bytes.len > 600) return .none;
                } else {
                    if (uses_global_op or op_count > 135) return .none;
                }
            } else if (inner_calls_count == 1) {
                if (has_loop) return .none;
                if (single_internal) {
                    if (op_count > 180 or bytes.len > 500) return .none;
                } else {
                    if (uses_global_op or op_count > 85 or bytes.len > 240) return .none;
                }
            } else {
                if (has_loop) return .none;
                if (single_internal) {
                    if (inner_calls_count > 4 or uses_global_set or op_count > 180 or bytes.len > 500) return .none;
                } else {
                    if (inner_calls_count > 2 or uses_global_op or op_count > 95 or bytes.len > 260) return .none;
                }
            }
        },
    }

    var leaf = TrivialLeaf{
        .body_bytes = bytes,
        .effective_end = effective_end,
        .op_count = op_count,
        .param_count = @intCast(sig.params.len),
        .result_count = @intCast(sig.results.len),
        .local_count = @intCast(func.local_types.items.len),
        .prefix_params = prefix_params,
        .leading_end_offsets = leading_end_offsets,
        .needs_local_zero_init = needs_local_zero_init,
        .needs_result_block = needs_result_block,
        .has_early_return = has_early_return,
        .uses_global_op = uses_global_op,
        .inner_callees = inner_callees,
        .inner_calls_count = inner_calls_count,
    };
    @memcpy(leaf.param_types[0..sig.params.len], sig.params);
    @memcpy(leaf.result_types[0..sig.results.len], sig.results);
    @memcpy(leaf.local_types[0..func.local_types.items.len], func.local_types.items);
    return .{ .leaf = leaf };
}

fn markExprExternalRefs(
    bytes: []const u8,
    num_funcs: usize,
    is_externally_used: []bool,
) Error!void {
    var pos: usize = 0;
    while (pos < bytes.len) {
        const decoded = instr.decode(bytes, &pos) catch return error.InvalidInput;
        if (decoded.prefix == 0 and (decoded.code == 0x10 or decoded.code == 0x12 or decoded.code == 0xd2)) {
            const idx = readU32(bytes, &pos) catch return error.InvalidInput;
            if (idx < num_funcs) is_externally_used[idx] = true;
        } else {
            instr.skipImmediates(decoded.shape, bytes, &pos) catch return error.InvalidInput;
        }
    }
}

fn inlineTrivialFunctions(
    allocator: std.mem.Allocator,
    module: *Mod.Module,
    optimize_mode: OptimizeMode,
    modified_funcs: []bool,
) Error!bool {
    const num_funcs = module.funcs.items.len;
    if (num_funcs <= module.num_func_imports) return false;

    const call_counts = allocator.alloc(u32, num_funcs) catch return error.OutOfMemory;
    defer allocator.free(call_counts);
    @memset(call_counts, 0);

    const is_externally_used = allocator.alloc(bool, num_funcs) catch return error.OutOfMemory;
    defer allocator.free(is_externally_used);
    @memset(is_externally_used, false);

    for (0..module.num_func_imports) |i| {
        is_externally_used[i] = true;
    }
    for (module.exports.items) |exp| {
        if (exp.kind == .func and exp.var_ == .index and exp.var_.index < num_funcs) {
            is_externally_used[exp.var_.index] = true;
        }
    }
    if (module.start_var) |sv| {
        if (sv == .index and sv.index < num_funcs) {
            is_externally_used[sv.index] = true;
        }
    }
    for (module.elem_segments.items) |seg| {
        for (seg.elem_var_indices.items) |v| {
            if (v == .index and v.index < num_funcs) {
                is_externally_used[v.index] = true;
            }
        }
        if (seg.elem_expr_bytes.len > 0) {
            try markExprExternalRefs(seg.elem_expr_bytes, num_funcs, is_externally_used);
        }
        if (seg.kind == .active and seg.offset_expr_bytes.len > 0) {
            try markExprExternalRefs(seg.offset_expr_bytes, num_funcs, is_externally_used);
        }
    }
    for (module.globals.items) |g| {
        if (!g.is_import and g.init_expr_bytes.len > 0) {
            try markExprExternalRefs(g.init_expr_bytes, num_funcs, is_externally_used);
        }
    }
    for (module.tables.items) |t| {
        if (!t.is_import and t.hasInitExpr() and t.init_expr_bytes.len > 0) {
            try markExprExternalRefs(t.init_expr_bytes, num_funcs, is_externally_used);
        }
    }
    for (module.funcs.items[module.num_func_imports..]) |func| {
        if (func.is_import or func.code_bytes.len == 0) continue;
        var pos: usize = 0;
        const bytes = func.code_bytes;
        while (pos < bytes.len) {
            const decoded = instr.decode(bytes, &pos) catch return error.InvalidInput;
            if (decoded.prefix == 0 and (decoded.code == 0x10 or decoded.code == 0x12)) {
                const callee = readU32(bytes, &pos) catch return error.InvalidInput;
                if (callee < num_funcs) call_counts[callee] +|= 1;
            } else if (decoded.prefix == 0 and decoded.code == 0xd2) {
                const idx = readU32(bytes, &pos) catch return error.InvalidInput;
                if (idx < num_funcs) is_externally_used[idx] = true;
            } else {
                instr.skipImmediates(decoded.shape, bytes, &pos) catch return error.InvalidInput;
            }
        }
    }

    const trivials = allocator.alloc(TrivialKind, num_funcs) catch return error.OutOfMemory;
    defer allocator.free(trivials);
    @memset(trivials, .none);

    const orig_forwards = allocator.alloc(TrivialKind, num_funcs) catch return error.OutOfMemory;
    defer allocator.free(orig_forwards);
    @memset(orig_forwards, .none);

    var any_trivial = false;
    for (module.num_func_imports..num_funcs) |i| {
        const kind = classifyTrivialFunc(
            module,
            @intCast(i),
            &module.funcs.items[i],
            optimize_mode,
            call_counts[i],
            is_externally_used[i],
        );
        trivials[i] = kind;
        orig_forwards[i] = kind;
        if (kind != .none) any_trivial = true;
    }
    if (!any_trivial) return false;

    // Resolve forwarding chains (e.g. getFactoryThunk -> host.getFactoryThunk -> export.getFactoryThunk).
    for (module.num_func_imports..num_funcs) |i| {
        if (orig_forwards[i] != .forward) continue;
        var curr = orig_forwards[i].forward.callee;
        const orig_tail = orig_forwards[i].forward.is_tail;
        var chain_single_use: bool = (@as(u32, @intFromBool(is_externally_used[i])) + call_counts[i]) <= 1;
        var resolved: TrivialKind = .none;
        for (0..16) |_| {
            if (curr < module.num_func_imports) {
                resolved = .{ .forward = .{ .callee = curr, .is_tail = orig_tail } };
                break;
            }
            if ((@as(u32, @intFromBool(is_externally_used[curr])) + call_counts[curr]) > 1) {
                chain_single_use = false;
            }
            switch (orig_forwards[curr]) {
                .leaf => |leaf| {
                    const small_leaf_ok = (optimize_mode == .fast) or
                        chain_single_use or
                        (leaf.op_count <= 7 and leaf.local_count == 0 and !leaf.uses_global_op);
                    if (small_leaf_ok and
                        leaf.param_count == 0 and
                        leaf.local_count == 0 and
                        !leaf.needs_result_block and
                        !leaf.has_early_return and
                        leaf.inner_calls_count == 0)
                    {
                        resolved = .{ .leaf = leaf };
                    } else {
                        resolved = .{ .forward = .{ .callee = curr, .is_tail = orig_tail } };
                    }
                    break;
                },
                .forward => |fwd| {
                    if (fwd.callee == i or fwd.callee == curr) {
                        resolved = .none;
                        break;
                    }
                    curr = fwd.callee;
                },
                .none => {
                    resolved = .{ .forward = .{ .callee = curr, .is_tail = orig_tail } };
                    break;
                },
            }
        }
        trivials[i] = resolved;
    }

    for (module.num_func_imports..num_funcs) |i| {
        if (trivials[i] == .leaf) {
            for (trivials[i].leaf.inner_callees[0..trivials[i].leaf.inner_calls_count]) |inner_c| {
                if (trivials[inner_c] != .none or orig_forwards[inner_c] != .none) {
                    trivials[i] = .none;
                    break;
                }
            }
        }
    }

    var any_inlined = false;

    for (module.num_func_imports..num_funcs) |i| {
        const func = &module.funcs.items[i];
        if (func.is_import or func.code_bytes.len == 0) continue;

        if (orig_forwards[i] == .forward) {
            switch (trivials[i]) {
                .leaf => |leaf| {
                    var out: std.ArrayListUnmanaged(u8) = .empty;
                    errdefer out.deinit(module.allocator);
                    out.ensureTotalCapacity(module.allocator, leaf.effective_end + 1) catch return error.OutOfMemory;
                    out.appendSliceAssumeCapacity(leaf.body_bytes[0..leaf.effective_end]);
                    out.appendAssumeCapacity(0x0b);
                    const new_bytes = out.toOwnedSlice(module.allocator) catch return error.OutOfMemory;
                    if (func.owns_code_bytes and func.code_bytes.len > 0) {
                        module.allocator.free(func.code_bytes);
                    }
                    func.code_bytes = new_bytes;
                    func.owns_code_bytes = true;
                    modified_funcs[i] = true;
                    any_inlined = true;
                },
                .forward => |fwd| {
                    if (fwd.callee != orig_forwards[i].forward.callee) {
                        var out: std.ArrayListUnmanaged(u8) = .empty;
                        errdefer out.deinit(module.allocator);
                        out.append(module.allocator, if (fwd.is_tail) 0x12 else 0x10) catch return error.OutOfMemory;
                        try appendU32Leb(module.allocator, &out, fwd.callee);
                        out.append(module.allocator, 0x0b) catch return error.OutOfMemory;
                        const new_bytes = out.toOwnedSlice(module.allocator) catch return error.OutOfMemory;
                        if (func.owns_code_bytes and func.code_bytes.len > 0) {
                            module.allocator.free(func.code_bytes);
                        }
                        func.code_bytes = new_bytes;
                        func.owns_code_bytes = true;
                        any_inlined = true;
                    }
                },
                .none => {},
            }
            continue;
        }

        const caller_sig = getFuncSignature(module, func) orelse continue;
        const caller_param_count: u32 = @intCast(caller_sig.params.len);
        const can_inline_leaves = (optimize_mode == .small) or
            (func.code_bytes.len <= 16384 and func.local_types.items.len <= 512);

        // Check whether this non-trivial function calls any trivial function.
        var has_trivial_call = false;
        {
            var pos: usize = 0;
            const bytes = func.code_bytes;
            while (pos < bytes.len) {
                const decoded = instr.decode(bytes, &pos) catch return error.InvalidInput;
                if (decoded.prefix == 0 and (decoded.code == 0x10 or decoded.code == 0x12)) {
                    const callee = readU32(bytes, &pos) catch return error.InvalidInput;
                    if (callee != i and callee >= module.num_func_imports and callee < num_funcs) {
                        switch (trivials[callee]) {
                            .leaf => if (can_inline_leaves) {
                                has_trivial_call = true;
                                break;
                            },
                            .forward => {
                                has_trivial_call = true;
                                break;
                            },
                            .none => {},
                        }
                    }
                } else {
                    instr.skipImmediates(decoded.shape, bytes, &pos) catch return error.InvalidInput;
                }
            }
        }
        if (!has_trivial_call) continue;

        var out: std.ArrayListUnmanaged(u8) = .empty;
        errdefer out.deinit(module.allocator);
        out.ensureTotalCapacity(module.allocator, func.code_bytes.len) catch return error.OutOfMemory;

        var inlined_leaf = false;
        var pos: usize = 0;
        const bytes = func.code_bytes;
        while (pos < bytes.len) {
            const start = pos;
            const decoded = instr.decode(bytes, &pos) catch return error.InvalidInput;
            if (decoded.prefix == 0 and (decoded.code == 0x10 or decoded.code == 0x12)) {
                const callee = readU32(bytes, &pos) catch return error.InvalidInput;
                if (callee != i and callee >= module.num_func_imports and callee < num_funcs) {
                    switch (trivials[callee]) {
                        .leaf => |*leaf| {
                            const extra_result_locals: usize = if (leaf.needs_result_block and leaf.result_count > 1) leaf.result_count else 0;
                            const needed_locals: usize = (leaf.param_count - leaf.prefix_params) + leaf.local_count + extra_result_locals;
                            const can_inline_site = switch (optimize_mode) {
                                .small => func.local_types.items.len + needed_locals <= 4096,
                                .fast => out.items.len + (bytes.len - pos) <= 16384 and func.local_types.items.len + needed_locals <= 512,
                            };
                            if (can_inline_site) {
                                var local_map: [max_inline_total_locals]u32 = undefined;
                                for (leaf.prefix_params..leaf.param_count) |p| {
                                    const new_idx: u32 = caller_param_count + @as(u32, @intCast(func.local_types.items.len));
                                    if (func.local_type_idxs.items.len == func.local_types.items.len and func.local_type_idxs.items.len > 0) {
                                        func.local_type_idxs.append(module.allocator, types.invalid_index) catch return error.OutOfMemory;
                                    } else {
                                        func.local_type_idxs.clearRetainingCapacity();
                                    }
                                    func.local_types.append(module.allocator, leaf.param_types[p]) catch return error.OutOfMemory;
                                    local_map[p] = new_idx;
                                }
                                for (0..leaf.local_count) |l| {
                                    const new_idx: u32 = caller_param_count + @as(u32, @intCast(func.local_types.items.len));
                                    if (func.local_type_idxs.items.len == func.local_types.items.len and func.local_type_idxs.items.len > 0) {
                                        func.local_type_idxs.append(module.allocator, types.invalid_index) catch return error.OutOfMemory;
                                    } else {
                                        func.local_type_idxs.clearRetainingCapacity();
                                    }
                                    func.local_types.append(module.allocator, leaf.local_types[l]) catch return error.OutOfMemory;
                                    local_map[leaf.param_count + l] = new_idx;
                                }
                                var result_locals: [max_inline_results]u32 = @splat(0);
                                if (leaf.needs_result_block and leaf.result_count > 1) {
                                    for (0..leaf.result_count) |r| {
                                        result_locals[r] = caller_param_count + @as(u32, @intCast(func.local_types.items.len));
                                        if (func.local_type_idxs.items.len == func.local_types.items.len and func.local_type_idxs.items.len > 0) {
                                            func.local_type_idxs.append(module.allocator, types.invalid_index) catch return error.OutOfMemory;
                                        } else {
                                            func.local_type_idxs.clearRetainingCapacity();
                                        }
                                        func.local_types.append(module.allocator, leaf.result_types[r]) catch return error.OutOfMemory;
                                    }
                                }

                                var p: usize = leaf.param_count;
                                while (p > leaf.prefix_params) {
                                    p -= 1;
                                    out.append(module.allocator, 0x21) catch return error.OutOfMemory;
                                    try appendU32Leb(module.allocator, &out, local_map[p]);
                                }

                                for (0..leaf.local_count) |l| {
                                    if (!leaf.needs_local_zero_init[l]) continue;
                                    switch (leaf.local_types[l]) {
                                        .i32 => out.appendSlice(module.allocator, &.{ 0x41, 0x00 }) catch return error.OutOfMemory,
                                        .i64 => out.appendSlice(module.allocator, &.{ 0x42, 0x00 }) catch return error.OutOfMemory,
                                        .f32 => out.appendSlice(module.allocator, &.{ 0x43, 0, 0, 0, 0 }) catch return error.OutOfMemory,
                                        .f64 => out.appendSlice(module.allocator, &.{ 0x44, 0, 0, 0, 0, 0, 0, 0, 0 }) catch return error.OutOfMemory,
                                        .v128 => out.appendSlice(module.allocator, &([_]u8{ 0xfd, 0x0c } ++ (@as([16]u8, @splat(0))))) catch return error.OutOfMemory,
                                        .funcref => out.appendSlice(module.allocator, &.{ 0xd0, 0x70 }) catch return error.OutOfMemory,
                                        .externref => out.appendSlice(module.allocator, &.{ 0xd0, 0x6f }) catch return error.OutOfMemory,
                                        else => unreachable,
                                    }
                                    out.append(module.allocator, 0x21) catch return error.OutOfMemory;
                                    try appendU32Leb(module.allocator, &out, local_map[leaf.param_count + l]);
                                }

                                if (leaf.needs_result_block) {
                                    out.append(module.allocator, 0x02) catch return error.OutOfMemory;
                                    if (leaf.result_count != 1) {
                                        out.append(module.allocator, 0x40) catch return error.OutOfMemory;
                                    } else {
                                        const vt_byte: u8 = @bitCast(@as(i8, @intCast(@backingInt(leaf.result_types[0]))));
                                        out.append(module.allocator, vt_byte) catch return error.OutOfMemory;
                                    }
                                }

                                const body_start: usize = if (leaf.prefix_params > 0)
                                    leaf.leading_end_offsets[leaf.prefix_params - 1]
                                else
                                    0;
                                var bpos: usize = body_start;
                                var inner_depth: u32 = 0;
                                while (bpos < leaf.effective_end) {
                                    const bstart = bpos;
                                    const bdecoded = instr.decode(leaf.body_bytes, &bpos) catch return error.InvalidInput;
                                    if (bdecoded.prefix == 0) {
                                        switch (bdecoded.code) {
                                            0x02, 0x03, 0x04 => {
                                                inner_depth += 1;
                                                instr.skipImmediates(bdecoded.shape, leaf.body_bytes, &bpos) catch return error.InvalidInput;
                                                out.appendSlice(module.allocator, leaf.body_bytes[bstart..bpos]) catch return error.OutOfMemory;
                                                continue;
                                            },
                                            0x0b => {
                                                if (inner_depth > 0) inner_depth -= 1;
                                                out.append(module.allocator, 0x0b) catch return error.OutOfMemory;
                                                continue;
                                            },
                                            0x20, 0x21, 0x22 => {
                                                const old_local = readU32(leaf.body_bytes, &bpos) catch return error.InvalidInput;
                                                out.append(module.allocator, @intCast(bdecoded.code)) catch return error.OutOfMemory;
                                                try appendU32Leb(module.allocator, &out, local_map[old_local]);
                                                continue;
                                            },
                                            0x0f => {
                                                if (leaf.needs_result_block and leaf.result_count > 1) {
                                                    var ri: usize = leaf.result_count;
                                                    while (ri > 0) {
                                                        ri -= 1;
                                                        out.append(module.allocator, 0x21) catch return error.OutOfMemory;
                                                        try appendU32Leb(module.allocator, &out, result_locals[ri]);
                                                    }
                                                }
                                                out.append(module.allocator, 0x0c) catch return error.OutOfMemory;
                                                try appendU32Leb(module.allocator, &out, inner_depth);
                                                continue;
                                            },
                                            else => {},
                                        }
                                    }
                                    instr.skipImmediates(bdecoded.shape, leaf.body_bytes, &bpos) catch return error.InvalidInput;
                                    out.appendSlice(module.allocator, leaf.body_bytes[bstart..bpos]) catch return error.OutOfMemory;
                                }

                                if (leaf.needs_result_block) {
                                    if (leaf.result_count > 1) {
                                        var ri: usize = leaf.result_count;
                                        while (ri > 0) {
                                            ri -= 1;
                                            out.append(module.allocator, 0x21) catch return error.OutOfMemory;
                                            try appendU32Leb(module.allocator, &out, result_locals[ri]);
                                        }
                                    }
                                    out.append(module.allocator, 0x0b) catch return error.OutOfMemory;
                                    if (leaf.result_count > 1) {
                                        for (0..leaf.result_count) |ri| {
                                            out.append(module.allocator, 0x20) catch return error.OutOfMemory;
                                            try appendU32Leb(module.allocator, &out, result_locals[ri]);
                                        }
                                    }
                                }
                                if (decoded.code == 0x12) {
                                    out.append(module.allocator, 0x0f) catch return error.OutOfMemory;
                                }
                                inlined_leaf = true;
                                any_inlined = true;
                                continue;
                            }
                        },
                        .forward => |fwd| {
                            out.append(module.allocator, @intCast(decoded.code)) catch return error.OutOfMemory;
                            try appendU32Leb(module.allocator, &out, fwd.callee);
                            if (fwd.callee != callee) any_inlined = true;
                            continue;
                        },
                        .none => {},
                    }
                }
                out.appendSlice(module.allocator, bytes[start..pos]) catch return error.OutOfMemory;
            } else {
                instr.skipImmediates(decoded.shape, bytes, &pos) catch return error.InvalidInput;
                out.appendSlice(module.allocator, bytes[start..pos]) catch return error.OutOfMemory;
            }
        }

        const new_bytes = out.toOwnedSlice(module.allocator) catch return error.OutOfMemory;
        if (func.owns_code_bytes and func.code_bytes.len > 0) {
            module.allocator.free(func.code_bytes);
        }
        func.code_bytes = new_bytes;
        func.owns_code_bytes = true;

        if (inlined_leaf) {
            modified_funcs[i] = true;
        }
    }

    return any_inlined;
}

fn removeDeadFunctions(
    allocator: std.mem.Allocator,
    module: *Mod.Module,
    locals_compacted: []const bool,
) Error!void {
    const num_funcs = module.funcs.items.len;
    if (num_funcs <= module.num_func_imports) return;

    var any_locals_compacted = false;
    for (locals_compacted) |c| {
        if (c) {
            any_locals_compacted = true;
            break;
        }
    }

    const live = allocator.alloc(bool, num_funcs) catch return error.OutOfMemory;
    defer allocator.free(live);
    @memset(live, false);

    var worklist: std.ArrayListUnmanaged(u32) = .empty;
    defer worklist.deinit(allocator);

    for (0..module.num_func_imports) |i| {
        try markLiveFunc(num_funcs, live, &worklist, allocator, @intCast(i));
    }

    var uses_table = module.num_table_imports > 0;
    for (module.exports.items) |exp| {
        if (exp.kind == .func and exp.var_ == .index) {
            try markLiveFunc(num_funcs, live, &worklist, allocator, exp.var_.index);
        } else if (exp.kind == .table) {
            uses_table = true;
        }
    }

    if (module.start_var) |sv| {
        if (sv == .index) {
            try markLiveFunc(num_funcs, live, &worklist, allocator, sv.index);
        }
    }

    for (module.globals.items) |global| {
        if (!global.is_import and global.init_expr_bytes.len > 0) {
            try scanExprFuncRefs(global.init_expr_bytes, num_funcs, live, &worklist, &uses_table, allocator);
        }
    }

    for (module.tables.items) |table| {
        if (!table.is_import and table.hasInitExpr() and table.init_expr_bytes.len > 0) {
            try scanExprFuncRefs(table.init_expr_bytes, num_funcs, live, &worklist, &uses_table, allocator);
        }
    }

    for (module.data_segments.items) |seg| {
        if (seg.kind == .active and seg.offset_expr_bytes.len > 0) {
            try scanExprFuncRefs(seg.offset_expr_bytes, num_funcs, live, &worklist, &uses_table, allocator);
        }
    }

    var elems_seeded = false;
    while (true) {
        if (uses_table and !elems_seeded) {
            elems_seeded = true;
            for (module.elem_segments.items) |seg| {
                for (seg.elem_var_indices.items) |v| {
                    if (v == .index and v.index != types.invalid_index) {
                        try markLiveFunc(num_funcs, live, &worklist, allocator, v.index);
                    }
                }
                if (seg.elem_expr_bytes.len > 0) {
                    try scanExprFuncRefs(seg.elem_expr_bytes, num_funcs, live, &worklist, &uses_table, allocator);
                }
                if (seg.kind == .active and seg.offset_expr_bytes.len > 0) {
                    try scanExprFuncRefs(seg.offset_expr_bytes, num_funcs, live, &worklist, &uses_table, allocator);
                }
            }
        }
        const fidx = worklist.pop() orelse {
            if (uses_table and !elems_seeded) continue;
            break;
        };
        if (fidx < module.num_func_imports or fidx >= num_funcs) continue;
        const func = module.funcs.items[fidx];
        if (func.code_bytes.len > 0) {
            try scanExprFuncRefs(func.code_bytes, num_funcs, live, &worklist, &uses_table, allocator);
        }
    }

    if (!elems_seeded) {
        for (module.elem_segments.items) |*seg| {
            seg.elem_var_indices.deinit(module.allocator);
            if (seg.owns_offset_expr_bytes and seg.offset_expr_bytes.len > 0) {
                module.allocator.free(seg.offset_expr_bytes);
            }
            if (seg.owns_elem_expr_bytes and seg.elem_expr_bytes.len > 0) {
                module.allocator.free(seg.elem_expr_bytes);
            }
        }
        module.elem_segments.clearRetainingCapacity();

        for (module.tables.items) |*table| {
            if (table.owns_init_expr_bytes and table.init_expr_bytes.len > 0) {
                module.allocator.free(table.init_expr_bytes);
            }
        }
        module.tables.clearRetainingCapacity();
    }

    var all_live = true;
    for (live) |is_live| {
        if (!is_live) {
            all_live = false;
            break;
        }
    }
    if (all_live and !any_locals_compacted) return;

    const old_to_new = allocator.alloc(u32, num_funcs) catch return error.OutOfMemory;
    defer allocator.free(old_to_new);
    var next_idx: u32 = 0;
    for (0..num_funcs) |i| {
        if (live[i]) {
            old_to_new[i] = next_idx;
            next_idx += 1;
        } else {
            old_to_new[i] = types.invalid_index;
        }
    }

    if (all_live) {
        if (module.customs.items.len > 0) {
            var custom_write_idx: usize = 0;
            for (module.customs.items) |custom| {
                if (!std.mem.eql(u8, custom.name, "name")) {
                    module.customs.items[custom_write_idx] = custom;
                    custom_write_idx += 1;
                    continue;
                }
                if (rewriteNameSectionPayload(module.allocator, custom.data, old_to_new, locals_compacted, any_locals_compacted)) |rewritten| {
                    if (custom.owns_data and custom.data.len > 0) {
                        module.allocator.free(custom.data);
                    }
                    var updated = custom;
                    updated.data = rewritten;
                    updated.owns_data = true;
                    module.customs.items[custom_write_idx] = updated;
                    custom_write_idx += 1;
                } else |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidNameSection => {
                        if (custom.owns_data and custom.data.len > 0) {
                            module.allocator.free(custom.data);
                        }
                    },
                }
            }
            module.customs.shrinkRetainingCapacity(custom_write_idx);
        }
        return;
    }

    // Rewrite function indices in live defined functions before compacting module.funcs.
    for (module.funcs.items, 0..) |*func, i| {
        if (!live[i] or i < module.num_func_imports or func.code_bytes.len == 0) continue;
        const rewritten = try rewriteExprFuncIndices(module.allocator, func.code_bytes, old_to_new);
        if (func.owns_code_bytes and func.code_bytes.len > 0) {
            module.allocator.free(func.code_bytes);
        }
        func.code_bytes = rewritten;
        func.owns_code_bytes = true;
    }

    for (module.elem_segments.items) |*seg| {
        for (seg.elem_var_indices.items) |*v| {
            if (v.* == .index and v.index < num_funcs) {
                v.index = old_to_new[v.index];
            }
        }
        if (seg.elem_expr_bytes.len > 0) {
            const rewritten = try rewriteExprFuncIndices(module.allocator, seg.elem_expr_bytes, old_to_new);
            if (seg.owns_elem_expr_bytes and seg.elem_expr_bytes.len > 0) {
                module.allocator.free(seg.elem_expr_bytes);
            }
            seg.elem_expr_bytes = rewritten;
            seg.owns_elem_expr_bytes = true;
        }
        if (seg.kind == .active and seg.offset_expr_bytes.len > 0) {
            const rewritten = try rewriteExprFuncIndices(module.allocator, seg.offset_expr_bytes, old_to_new);
            if (seg.owns_offset_expr_bytes and seg.offset_expr_bytes.len > 0) {
                module.allocator.free(seg.offset_expr_bytes);
            }
            seg.offset_expr_bytes = rewritten;
            seg.owns_offset_expr_bytes = true;
        }
    }

    for (module.globals.items) |*global| {
        if (!global.is_import and global.init_expr_bytes.len > 0) {
            const rewritten = try rewriteExprFuncIndices(module.allocator, global.init_expr_bytes, old_to_new);
            if (global.owns_init_expr_bytes and global.init_expr_bytes.len > 0) {
                module.allocator.free(global.init_expr_bytes);
            }
            global.init_expr_bytes = rewritten;
            global.owns_init_expr_bytes = true;
        }
    }

    for (module.tables.items) |*table| {
        if (!table.is_import and table.hasInitExpr() and table.init_expr_bytes.len > 0) {
            const rewritten = try rewriteExprFuncIndices(module.allocator, table.init_expr_bytes, old_to_new);
            if (table.owns_init_expr_bytes and table.init_expr_bytes.len > 0) {
                module.allocator.free(table.init_expr_bytes);
            }
            table.init_expr_bytes = rewritten;
            table.owns_init_expr_bytes = true;
        }
    }

    for (module.data_segments.items) |*seg| {
        if (seg.kind == .active and seg.offset_expr_bytes.len > 0) {
            const rewritten = try rewriteExprFuncIndices(module.allocator, seg.offset_expr_bytes, old_to_new);
            if (seg.owns_offset_expr_bytes and seg.offset_expr_bytes.len > 0) {
                module.allocator.free(seg.offset_expr_bytes);
            }
            seg.offset_expr_bytes = rewritten;
            seg.owns_offset_expr_bytes = true;
        }
    }

    for (module.exports.items) |*exp| {
        if (exp.kind == .func and exp.var_ == .index and exp.var_.index < num_funcs) {
            exp.var_.index = old_to_new[exp.var_.index];
        }
    }

    if (module.start_var) |*sv| {
        if (sv.* == .index and sv.index < num_funcs) {
            sv.index = old_to_new[sv.index];
        }
    }

    if (next_idx != num_funcs and module.customs.items.len > 0) {
        var custom_write_idx: usize = 0;
        for (module.customs.items) |custom| {
            if (!std.mem.eql(u8, custom.name, "name")) {
                module.customs.items[custom_write_idx] = custom;
                custom_write_idx += 1;
                continue;
            }
            if (rewriteNameSectionPayload(module.allocator, custom.data, old_to_new, locals_compacted, any_locals_compacted)) |rewritten| {
                if (custom.owns_data and custom.data.len > 0) {
                    module.allocator.free(custom.data);
                }
                var updated = custom;
                updated.data = rewritten;
                updated.owns_data = true;
                module.customs.items[custom_write_idx] = updated;
                custom_write_idx += 1;
            } else |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidNameSection => {
                    if (custom.owns_data and custom.data.len > 0) {
                        module.allocator.free(custom.data);
                    }
                },
            }
        }
        module.customs.shrinkRetainingCapacity(custom_write_idx);
    }

    var write_idx: usize = 0;
    for (module.funcs.items, 0..) |*func, i| {
        if (live[i]) {
            module.funcs.items[write_idx] = func.*;
            write_idx += 1;
        } else {
            func.local_types.deinit(module.allocator);
            func.local_type_idxs.deinit(module.allocator);
            if (func.owns_code_bytes and func.code_bytes.len > 0) {
                module.allocator.free(func.code_bytes);
            }
        }
    }
    module.funcs.shrinkRetainingCapacity(write_idx);
}

const RewriteNameSectionError = std.mem.Allocator.Error || error{InvalidNameSection};

fn rewriteNameSectionPayload(
    allocator: std.mem.Allocator,
    data: []const u8,
    old_to_new: []const u32,
    locals_compacted: []const bool,
    any_locals_compacted: bool,
) RewriteNameSectionError![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);

    var entries_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer entries_buf.deinit(allocator);

    var pos: usize = 0;
    while (pos < data.len) {
        const subsec_id = data[pos];
        pos += 1;
        const subsec_size = readU32(data, &pos) catch return error.InvalidNameSection;
        if (subsec_size > data.len - pos) return error.InvalidNameSection;
        const subsec_body = data[pos .. pos + subsec_size];
        pos += subsec_size;

        switch (subsec_id) {
            1 => {
                entries_buf.clearRetainingCapacity();
                var sub_pos: usize = 0;
                const count = readU32(subsec_body, &sub_pos) catch return error.InvalidNameSection;
                var surviving_count: u32 = 0;
                for (0..count) |_| {
                    const func_idx = readU32(subsec_body, &sub_pos) catch return error.InvalidNameSection;
                    const name_len = readU32(subsec_body, &sub_pos) catch return error.InvalidNameSection;
                    if (name_len > subsec_body.len - sub_pos) return error.InvalidNameSection;
                    const name_bytes = subsec_body[sub_pos .. sub_pos + name_len];
                    sub_pos += name_len;

                    if (func_idx < old_to_new.len and old_to_new[func_idx] != types.invalid_index) {
                        try appendU32Leb(allocator, &entries_buf, old_to_new[func_idx]);
                        try appendU32Leb(allocator, &entries_buf, name_len);
                        try entries_buf.appendSlice(allocator, name_bytes);
                        surviving_count += 1;
                    }
                }
                if (sub_pos != subsec_body.len) return error.InvalidNameSection;

                var count_tmp: [leb128.max_u32_bytes]u8 = undefined;
                const count_len = leb128.writeU32Leb128(&count_tmp, surviving_count);
                const new_subsec_size: u32 = @intCast(count_len + entries_buf.items.len);
                try out.append(allocator, subsec_id);
                try appendU32Leb(allocator, &out, new_subsec_size);
                try out.appendSlice(allocator, count_tmp[0..count_len]);
                try out.appendSlice(allocator, entries_buf.items);
            },
            2, 3 => {
                entries_buf.clearRetainingCapacity();
                var sub_pos: usize = 0;
                const count = readU32(subsec_body, &sub_pos) catch return error.InvalidNameSection;
                var surviving_count: u32 = 0;
                for (0..count) |_| {
                    const func_idx = readU32(subsec_body, &sub_pos) catch return error.InvalidNameSection;
                    const inner_start = sub_pos;
                    const inner_count = readU32(subsec_body, &sub_pos) catch return error.InvalidNameSection;
                    for (0..inner_count) |_| {
                        _ = readU32(subsec_body, &sub_pos) catch return error.InvalidNameSection;
                        const name_len = readU32(subsec_body, &sub_pos) catch return error.InvalidNameSection;
                        if (name_len > subsec_body.len - sub_pos) return error.InvalidNameSection;
                        sub_pos += name_len;
                    }
                    const inner_bytes = subsec_body[inner_start..sub_pos];

                    const keep_entry = func_idx < old_to_new.len and
                        old_to_new[func_idx] != types.invalid_index and
                        !(subsec_id == 2 and func_idx < locals_compacted.len and locals_compacted[func_idx]);
                    if (keep_entry) {
                        try appendU32Leb(allocator, &entries_buf, old_to_new[func_idx]);
                        try entries_buf.appendSlice(allocator, inner_bytes);
                        surviving_count += 1;
                    }
                }
                if (sub_pos != subsec_body.len) return error.InvalidNameSection;

                if (surviving_count > 0 or !(subsec_id == 2 and any_locals_compacted)) {
                    var count_tmp: [leb128.max_u32_bytes]u8 = undefined;
                    const count_len = leb128.writeU32Leb128(&count_tmp, surviving_count);
                    const new_subsec_size: u32 = @intCast(count_len + entries_buf.items.len);
                    try out.append(allocator, subsec_id);
                    try appendU32Leb(allocator, &out, new_subsec_size);
                    try out.appendSlice(allocator, count_tmp[0..count_len]);
                    try out.appendSlice(allocator, entries_buf.items);
                }
            },
            else => {
                try out.append(allocator, subsec_id);
                try appendU32Leb(allocator, &out, subsec_size);
                try out.appendSlice(allocator, subsec_body);
            },
        }
    }

    return try out.toOwnedSlice(allocator);
}

// ── Unit Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

fn buildSingleFuncModule(
    allocator: std.mem.Allocator,
    params: []const types.ValType,
    results: []const types.ValType,
    locals: []const types.ValType,
    code_bytes: []const u8,
) ![]u8 {
    var mod = Mod.Module.init(allocator);
    defer mod.deinit();

    const p_copy = try allocator.dupe(types.ValType, params);
    const r_copy = try allocator.dupe(types.ValType, results);
    try mod.module_types.append(allocator, .{ .func_type = .{ .params = p_copy, .results = r_copy } });
    try mod.type_meta.append(allocator, .{});

    var func = Mod.Func{
        .decl = .{
            .type_var = .{ .index = 0 },
            .sig = .{ .params = p_copy, .results = r_copy },
        },
        .code_bytes = code_bytes,
    };
    try func.local_types.appendSlice(allocator, locals);
    try mod.funcs.append(allocator, func);
    try mod.exports.append(allocator, .{
        .name = "f",
        .kind = .func,
        .var_ = .{ .index = 0 },
    });

    return try writer.writeModule(allocator, &mod);
}

test "Optimizer: i32 and i64 constant folding" {
    const allocator = testing.allocator;
    // (i32.add (i32.mul (i32.const 6) (i32.const 7)) (i32.sub (i32.const 10) (i32.const 2))) -> i32.const 50
    const code = [_]u8{
        0x41, 0x06, // i32.const 6
        0x41, 0x07, // i32.const 7
        0x6c, // i32.mul
        0x41, 0x0a, // i32.const 10
        0x41, 0x02, // i32.const 2
        0x6b, // i32.sub
        0x6a, // i32.add
        0x0b, // end
    };
    const wasm = try buildSingleFuncModule(allocator, &.{}, &.{.i32}, &.{}, &code);
    defer allocator.free(wasm);

    const opt_bytes = try optimize(allocator, wasm, .{});
    defer allocator.free(opt_bytes);

    var mod = try reader.readModule(allocator, opt_bytes);
    defer mod.deinit();
    try testing.expectEqualSlices(u8, &[_]u8{ 0x41, 50, 0x0b }, mod.funcs.items[0].code_bytes);
}

test "Optimizer: control-flow simplification and intrafunction DCE" {
    const allocator = testing.allocator;
    // nop, (block (result i32) (i32.const 1) (if (result i32) (then (i32.const 42)) (else (i32.const 99)))), return, i32.const 77
    const code = [_]u8{
        0x01, // nop
        0x02, 0x7f, // block (result i32)
        0x41, 0x01, // i32.const 1
        0x04, 0x7f, // if (result i32)
        0x41, 42, // i32.const 42
        0x05, // else
        0x41, 99, // i32.const 99
        0x0b, // end if
        0x0b, // end block
        0x0f, // return
        0x41, 77, // dead i32.const 77
        0x0b, // end func
    };
    const wasm = try buildSingleFuncModule(allocator, &.{}, &.{.i32}, &.{}, &code);
    defer allocator.free(wasm);

    const opt_bytes = try optimize(allocator, wasm, .{});
    defer allocator.free(opt_bytes);

    var mod = try reader.readModule(allocator, opt_bytes);
    defer mod.deinit();
    try testing.expectEqualSlices(u8, &[_]u8{ 0x41, 42, 0x0f, 0x0b }, mod.funcs.items[0].code_bytes);
}

test "Optimizer: dead-function removal prunes unreachable stubs and remaps indices" {
    const allocator = testing.allocator;
    var mod = Mod.Module.init(allocator);
    defer mod.deinit();

    const r_copy = try allocator.dupe(types.ValType, &.{.i32});
    try mod.module_types.append(allocator, .{ .func_type = .{ .params = &.{}, .results = r_copy } });
    try mod.type_meta.append(allocator, .{});

    const sig = types.FuncType{ .params = &.{}, .results = r_copy };
    // func 0: dead Zig-style stub (unreachable; end)
    try mod.funcs.append(allocator, .{
        .decl = .{ .type_var = .{ .index = 0 }, .sig = sig },
        .code_bytes = &[_]u8{ 0x00, 0x0b },
    });
    // func 1: live helper returning 42
    try mod.funcs.append(allocator, .{
        .decl = .{ .type_var = .{ .index = 0 }, .sig = sig },
        .code_bytes = &[_]u8{ 0x41, 42, 0x0b },
    });
    // func 2: exported caller calling func 1
    try mod.funcs.append(allocator, .{
        .decl = .{ .type_var = .{ .index = 0 }, .sig = sig },
        .code_bytes = &[_]u8{ 0x10, 0x01, 0x0b },
    });
    try mod.exports.append(allocator, .{
        .name = "main",
        .kind = .func,
        .var_ = .{ .index = 2 },
    });

    const wasm = try writer.writeModule(allocator, &mod);
    defer allocator.free(wasm);

    const opt_bytes = try optimize(allocator, wasm, .{});
    defer allocator.free(opt_bytes);

    var opt_mod = try reader.readModule(allocator, opt_bytes);
    defer opt_mod.deinit();

    try testing.expectEqual(@as(usize, 2), opt_mod.funcs.items.len);
    try testing.expectEqual(@as(u32, 1), opt_mod.exports.items[0].var_.index);
    // func 1 (was func 2) now calls func 0 (was func 1)
    try testing.expectEqualSlices(u8, &[_]u8{ 0x10, 0x00, 0x0b }, opt_mod.funcs.items[1].code_bytes);
}

test "Optimizer: CustomSectionPolicy.preserve and SIMD/atomics passthrough" {
    const allocator = testing.allocator;
    // Function with v128 local, 0xfe memory.atomic.notify, and foldable i32.add
    const code = [_]u8{
        0x41, 0x00, // i32.const 0
        0x41, 0x01, // i32.const 1
        0xfe, 0x00, 0x02, 0x00, // memory.atomic.notify align=2 offset=0
        0x1a, // drop
        0x41, 20, // i32.const 20
        0x41, 22, // i32.const 22
        0x6a, // i32.add -> 42
        0x0b, // end
    };

    var mod = Mod.Module.init(allocator);
    defer mod.deinit();

    const r_copy = try allocator.dupe(types.ValType, &.{.i32});
    try mod.module_types.append(allocator, .{ .func_type = .{ .params = &.{}, .results = r_copy } });
    try mod.type_meta.append(allocator, .{});

    try mod.memories.append(allocator, .{
        .type = .{ .limits = .{ .initial = 1, .max = 2, .has_max = true, .is_shared = true } },
    });

    var func = Mod.Func{
        .decl = .{ .type_var = .{ .index = 0 }, .sig = .{ .params = &.{}, .results = r_copy } },
        .code_bytes = &code,
    };
    try func.local_types.append(allocator, .v128);
    try mod.funcs.append(allocator, func);
    try mod.exports.append(allocator, .{ .name = "f", .kind = .func, .var_ = .{ .index = 0 } });
    try mod.customs.append(allocator, .{ .name = "component-type:world", .data = &[_]u8{ 1, 2, 3 } });

    const wasm = try writer.writeModule(allocator, &mod);
    defer allocator.free(wasm);

    const opt_bytes = try optimize(allocator, wasm, .{ .custom_sections = .preserve });
    defer allocator.free(opt_bytes);

    var opt_mod = try reader.readModule(allocator, opt_bytes);
    defer opt_mod.deinit();

    try testing.expectEqual(@as(usize, 1), opt_mod.customs.items.len);
    try testing.expectEqualStrings("component-type:world", opt_mod.customs.items[0].name);
    try testing.expectEqualSlices(
        u8,
        &[_]u8{ 0x41, 0x00, 0x41, 0x01, 0xfe, 0x00, 0x02, 0x00, 0x1a, 0x41, 42, 0x0b },
        opt_mod.funcs.items[0].code_bytes,
    );
}

test "Optimizer: CustomSectionPolicy.preserve rewrites name section on dead-function removal" {
    const allocator = testing.allocator;
    var mod = Mod.Module.init(allocator);
    defer mod.deinit();

    const r_copy = try allocator.dupe(types.ValType, &.{.i32});
    try mod.module_types.append(allocator, .{ .func_type = .{ .params = &.{}, .results = r_copy } });
    try mod.type_meta.append(allocator, .{});

    const sig = types.FuncType{ .params = &.{}, .results = r_copy };

    // func 0: imported function
    try mod.imports.append(allocator, .{
        .module_name = "env",
        .field_name = "imp",
        .kind = .func,
        .func = .{ .type_var = .{ .index = 0 }, .sig = sig },
    });
    try mod.funcs.append(allocator, .{
        .decl = .{ .type_var = .{ .index = 0 }, .sig = sig },
        .is_import = true,
    });
    mod.num_func_imports = 1;

    // func 1: dead function
    try mod.funcs.append(allocator, .{
        .decl = .{ .type_var = .{ .index = 0 }, .sig = sig },
        .code_bytes = &[_]u8{ 0x00, 0x0b },
    });

    // func 2: live helper returning 42
    try mod.funcs.append(allocator, .{
        .decl = .{ .type_var = .{ .index = 0 }, .sig = sig },
        .code_bytes = &[_]u8{ 0x41, 42, 0x0b },
    });

    // func 3: exported caller calling func 0 and func 2
    try mod.funcs.append(allocator, .{
        .decl = .{ .type_var = .{ .index = 0 }, .sig = sig },
        .code_bytes = &[_]u8{ 0x10, 0x00, 0x1a, 0x10, 0x02, 0x0b },
    });

    try mod.exports.append(allocator, .{
        .name = "main",
        .kind = .func,
        .var_ = .{ .index = 3 },
    });

    // Build a "name" custom section with:
    // - subsec 0 (module name): "m"
    // - subsec 1 (function names): 0->"imp", 1->"dead", 2->"live", 3->"main"
    // - subsec 2 (local names): 1->{0->"d0"}, 2->{0->"l0", 1->"l1"}, 3->{0->"m0"}
    // - subsec 7 (global names): 0->"g0"
    // - subsec 9 (data segment names): 0->"dseg"
    const name_payload = [_]u8{
        // subsec 0: module name "m"
        0x00, 0x02, 0x01, 'm',
        // subsec 1: 4 entries:
        // (0, 3, "imp") = 5 bytes
        // (1, 4, "dead") = 6 bytes
        // (2, 4, "live") = 6 bytes
        // (3, 4, "main") = 6 bytes
        // count (1) + 5 + 6 + 6 + 6 = 24 (0x18)
        0x01, 24,   0x04, 0x00,
        0x03, 'i',  'm',  'p',
        0x01, 0x04, 'd',  'e',
        'a',  'd',  0x02, 0x04,
        'l',  'i',  'v',  'e',
        0x03, 0x04, 'm',  'a',
        'i',  'n',
        // subsec 2: 3 entries:
        // func 1: count 1, (0, 2, "d0") -> 1 + 1 + 4 = 6 bytes
        // func 2: count 2, (0, 2, "l0"), (1, 2, "l1") -> 1 + 1 + 4 + 4 = 10 bytes
        // func 3: count 1, (0, 2, "m0") -> 1 + 1 + 4 = 6 bytes
        // count (1) + 6 + 10 + 6 = 23 (0x17)
         0x02, 23,
        0x03, 0x01, 0x01, 0x00,
        0x02, 'd',  '0',  0x02,
        0x02, 0x00, 0x02, 'l',
        '0',  0x01, 0x02, 'l',
        '1',  0x03, 0x01, 0x00,
        0x02, 'm',  '0',
        // subsec 7: global names: count 1, (0, 2, "g0") -> size 5
         0x07,
        0x05, 0x01, 0x00, 0x02,
        'g',  '0',
        // subsec 9: data names: count 1, (0, 4, "dseg") -> size 7
         0x09, 0x07,
        0x01, 0x00, 0x04, 'd',
        's',  'e',  'g',
    };
    try mod.customs.append(allocator, .{ .name = "name", .data = &name_payload });

    const wasm = try writer.writeModule(allocator, &mod);
    defer allocator.free(wasm);

    const opt_bytes = try optimize(allocator, wasm, .{ .custom_sections = .preserve });
    defer allocator.free(opt_bytes);

    var opt_mod = try reader.readModule(allocator, opt_bytes);
    defer opt_mod.deinit();

    // 3 functions survive: 0 (imp), 1 (was 2, live), 2 (was 3, main)
    try testing.expectEqual(@as(usize, 3), opt_mod.funcs.items.len);
    try testing.expectEqual(@as(usize, 1), opt_mod.customs.items.len);
    try testing.expectEqualStrings("name", opt_mod.customs.items[0].name);

    const expected_name_payload = [_]u8{
        // subsec 0: module name "m" preserved verbatim
        0x00, 0x02, 0x01, 'm',
        // subsec 1: 3 entries:
        // (0, 3, "imp") = 5 bytes
        // (1, 4, "live") = 6 bytes
        // (2, 4, "main") = 6 bytes
        // count (1) + 5 + 6 + 6 = 18
        0x01, 18,   0x03, 0x00,
        0x03, 'i',  'm',  'p',
        0x01, 0x04, 'l',  'i',
        'v',  'e',  0x02, 0x04,
        'm',  'a',  'i',  'n',
        // subsec 2: 2 entries:
        // func 1 (was 2): count 2, (0, 2, "l0"), (1, 2, "l1") -> 10 bytes
        // func 2 (was 3): count 1, (0, 2, "m0") -> 6 bytes
        // count (1) + 10 + 6 = 17
        0x02, 17,   0x02, 0x01,
        0x02, 0x00, 0x02, 'l',
        '0',  0x01, 0x02, 'l',
        '1',  0x02, 0x01, 0x00,
        0x02, 'm',  '0',
        // subsec 7: global names preserved verbatim
         0x07,
        0x05, 0x01, 0x00, 0x02,
        'g',  '0',
        // subsec 9: data names preserved verbatim
         0x09, 0x07,
        0x01, 0x00, 0x04, 'd',
        's',  'e',  'g',
    };
    try testing.expectEqualSlices(u8, &expected_name_payload, opt_mod.customs.items[0].data);
}

test "Optimizer: untyped post-link i32.add and i64.add are not folded into MemArg.offset" {
    const allocator = testing.allocator;
    // Post-link bytecode may contain negative LLVM LSR induction variables added to
    // relocated static addresses (`local.get $neg_iv; i64.const <end_addr>; i64.add; i64.load offset=0`),
    // which rely on wrapping modular addition rather than non-wrapping MemArg.offset addition.
    var code_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer code_buf.deinit(allocator);
    try code_buf.appendSlice(allocator, &[_]u8{ 0x20, 0x00, 0x42 });
    try appendS64Leb(allocator, &code_buf, 74967360);
    try code_buf.appendSlice(allocator, &[_]u8{ 0x7c, 0x29, 0x03, 0x00, 0x0b });

    const wasm = try buildSingleFuncModule(allocator, &.{.i64}, &.{.i64}, &.{}, code_buf.items);
    defer allocator.free(wasm);

    const opt_bytes = try optimize(allocator, wasm, .{});
    defer allocator.free(opt_bytes);

    var mod = try reader.readModule(allocator, opt_bytes);
    defer mod.deinit();
    try testing.expectEqualSlices(u8, code_buf.items, mod.funcs.items[0].code_bytes);
}

test "Optimizer: i32 and i64 additive, bitwise, shift, and rotate identities" {
    const allocator = testing.allocator;

    // i32 right-constant identities and left-constant commutative identities
    // local.get 0; +0; -0; |0; ^0; &-1; <<0; >>_s 0; >>_u 0; rotl 0; rotr 0 -> local.get 0
    const i32_code = [_]u8{
        0x41, 0x00, // i32.const 0 (left identity: 0 + local.get 0)
        0x20, 0x00, // local.get 0
        0x6a, // i32.add
        0x41, 0x00, 0x6a, // + 0
        0x41, 0x00, 0x6b, // - 0
        0x41, 0x00, 0x72, // | 0
        0x41, 0x00, 0x73, // ^ 0
        0x41, 0x7f, 0x71, // & -1
        0x41, 0x00, 0x74, // << 0
        0x41, 0x00, 0x75, // >>_s 0
        0x41, 0x00, 0x76, // >>_u 0
        0x41, 0x00, 0x77, // rotl 0
        0x41, 0x00, 0x78, // rotr 0
        0x0b, // end
    };
    const wasm32 = try buildSingleFuncModule(allocator, &.{.i32}, &.{.i32}, &.{}, &i32_code);
    defer allocator.free(wasm32);
    const opt32 = try optimize(allocator, wasm32, .{});
    defer allocator.free(opt32);
    var mod32 = try reader.readModule(allocator, opt32);
    defer mod32.deinit();
    try testing.expectEqualSlices(u8, &[_]u8{ 0x20, 0x00, 0x0b }, mod32.funcs.items[0].code_bytes);

    // i64 right-constant identities and left-constant commutative identities
    const i64_code = [_]u8{
        0x42, 0x7f, // i64.const -1 (left identity: -1 & local.get 0)
        0x20, 0x00, // local.get 0
        0x83, // i64.and
        0x42, 0x00, 0x7c, // + 0
        0x42, 0x00, 0x7d, // - 0
        0x42, 0x00, 0x84, // | 0
        0x42, 0x00, 0x85, // ^ 0
        0x42, 0x7f, 0x83, // & -1
        0x42, 0x00, 0x86, // << 0
        0x42, 0x00, 0x87, // >>_s 0
        0x42, 0x00, 0x88, // >>_u 0
        0x42, 0x00, 0x89, // rotl 0
        0x42, 0x00, 0x8a, // rotr 0
        0x0b, // end
    };
    const wasm64 = try buildSingleFuncModule(allocator, &.{.i64}, &.{.i64}, &.{}, &i64_code);
    defer allocator.free(wasm64);
    const opt64 = try optimize(allocator, wasm64, .{});
    defer allocator.free(opt64);
    var mod64 = try reader.readModule(allocator, opt64);
    defer mod64.deinit();
    try testing.expectEqualSlices(u8, &[_]u8{ 0x20, 0x00, 0x0b }, mod64.funcs.items[0].code_bytes);
}

test "Optimizer: zero comparison, comparison negation, double-boolean, and condition normalization" {
    const allocator = testing.allocator;

    // 1. x == 0 -> i32.eqz and i64.eqz
    const eq0_code = [_]u8{
        0x20, 0x00, // local.get 0 (i32)
        0x41, 0x00, // i32.const 0
        0x46, // i32.eq -> i32.eqz (0x45)
        0x1a, // drop
        0x20, 0x01, // local.get 1 (i64)
        0x42, 0x00, // i64.const 0
        0x51, // i64.eq -> i64.eqz (0x50)
        0x0b,
    };
    const wasm_eq0 = try buildSingleFuncModule(allocator, &.{ .i32, .i64 }, &.{.i32}, &.{}, &eq0_code);
    defer allocator.free(wasm_eq0);
    const opt_eq0 = try optimize(allocator, wasm_eq0, .{});
    defer allocator.free(opt_eq0);
    var mod_eq0 = try reader.readModule(allocator, opt_eq0);
    defer mod_eq0.deinit();
    try testing.expectEqualSlices(
        u8,
        &[_]u8{ 0x20, 0x00, 0x45, 0x1a, 0x20, 0x01, 0x50, 0x0b },
        mod_eq0.funcs.items[0].code_bytes,
    );

    // 2. <cmp>; i32.eqz -> inverted comparison, and <cmp>; i32.const 0; i32.ne -> <cmp>
    // local.get 0; local.get 1; i32.lt_s; i32.eqz; i32.const 0; i32.ne -> local.get 0; local.get 1; i32.ge_s
    const cmp_code = [_]u8{
        0x20, 0x00, // local.get 0
        0x20, 0x01, // local.get 1
        0x48, // i32.lt_s
        0x45, // i32.eqz -> i32.ge_s (0x4e)
        0x41, 0x00, // i32.const 0
        0x47, // i32.ne -> redundant on bool producer
        0x41, 0x01, // i32.const 1
        0x71, // i32.and -> redundant on bool producer
        0x0b,
    };
    const wasm_cmp = try buildSingleFuncModule(allocator, &.{ .i32, .i32 }, &.{.i32}, &.{}, &cmp_code);
    defer allocator.free(wasm_cmp);
    const opt_cmp = try optimize(allocator, wasm_cmp, .{});
    defer allocator.free(opt_cmp);
    var mod_cmp = try reader.readModule(allocator, opt_cmp);
    defer mod_cmp.deinit();
    try testing.expectEqualSlices(
        u8,
        &[_]u8{ 0x20, 0x00, 0x20, 0x01, 0x4e, 0x0b },
        mod_cmp.funcs.items[0].code_bytes,
    );

    // 3. br_if / if condition normalization:
    // (block
    //   local.get 0; i32.const 0; i32.ne; br_if 0
    //   local.get 0; i32.eqz; i32.eqz; br_if 0
    // )
    // local.get 0; i32.const 0; i32.eq; i32.eqz; if (result i32) (i32.const 10) else (i32.const 20) end
    const br_if_code = [_]u8{
        0x02, 0x40, // block
        0x20, 0x00, // local.get 0
        0x41, 0x00, // i32.const 0
        0x47, // i32.ne
        0x0d, 0x00, // br_if 0
        0x20, 0x00, // local.get 0
        0x45, // i32.eqz
        0x45, // i32.eqz
        0x0d, 0x00, // br_if 0
        0x0b, // end block
        0x20, 0x00, // local.get 0
        0x41, 0x00, // i32.const 0
        0x46, // i32.eq -> i32.eqz
        0x45, // i32.eqz -> i32.eqz; i32.eqz stripped before if
        0x04, 0x7f, // if (result i32)
        0x41, 10,
        0x05, // else
        0x41,
        20,
        0x0b, // end if
        0x0b, // end func
    };
    const wasm_br = try buildSingleFuncModule(allocator, &.{.i32}, &.{.i32}, &.{}, &br_if_code);
    defer allocator.free(wasm_br);
    const opt_br = try optimize(allocator, wasm_br, .{});
    defer allocator.free(opt_br);
    var mod_br = try reader.readModule(allocator, opt_br);
    defer mod_br.deinit();
    try testing.expectEqualSlices(
        u8,
        &[_]u8{
            0x02, 0x40,
            0x20, 0x00,
            0x0d, 0x00,
            0x20, 0x00,
            0x0d, 0x00,
            0x0b, 0x20,
            0x00, 0x04,
            0x7f, 0x41,
            10,   0x05,
            0x41, 20,
            0x0b, 0x0b,
        },
        mod_br.funcs.items[0].code_bytes,
    );
}

test "Optimizer: multiplicative identities, power-of-two strength reductions, and division folding" {
    const allocator = testing.allocator;

    // i32: (local.get 0 * 1 /_s 1 /_u 1 * 8) -> local.get 0; i32.const 3; i32.shl
    //      (local.get 0 /_u 16) -> local.get 0; i32.const 4; i32.shr_u
    //      (local.get 0 %_u 32) -> local.get 0; i32.const 31; i32.and
    const i32_strength_code = [_]u8{
        0x20, 0x00, // local.get 0
        0x41, 0x01, 0x6c, // * 1
        0x41, 0x01, 0x6d, // /_s 1
        0x41, 0x01, 0x6e, // /_u 1
        0x41, 0x08, 0x6c, // * 8 -> << 3
        0x41, 0x10, 0x6e, // /_u 16 -> >>_u 4
        0x41, 0x20, 0x70, // %_u 32 -> & 31
        0x0b,
    };
    const wasm32 = try buildSingleFuncModule(allocator, &.{.i32}, &.{.i32}, &.{}, &i32_strength_code);
    defer allocator.free(wasm32);
    const opt32 = try optimize(allocator, wasm32, .{});
    defer allocator.free(opt32);
    var mod32 = try reader.readModule(allocator, opt32);
    defer mod32.deinit();
    try testing.expectEqualSlices(
        u8,
        &[_]u8{
            0x20, 0x00,
            0x41, 0x03, 0x74, // i32.const 3; i32.shl
            0x41, 0x04, 0x76, // i32.const 4; i32.shr_u
            0x41, 0x1f, 0x71, // i32.const 31; i32.and
            0x0b,
        },
        mod32.funcs.items[0].code_bytes,
    );

    // i64: (4 * local.get 0 * 1 /_s 1 /_u 1 /_u 8 %_u 16)
    const i64_strength_code = [_]u8{
        0x42, 0x04, // i64.const 4
        0x20, 0x00, // local.get 0
        0x7e, // * -> local.get 0; i64.const 2; i64.shl
        0x42, 0x01, 0x7e, // * 1
        0x42, 0x01, 0x7f, // /_s 1
        0x42, 0x01, 0x80, // /_u 1
        0x42, 0x08, 0x80, // /_u 8 -> >>_u 3
        0x42, 0x10, 0x82, // %_u 16 -> & 15
        0x0b,
    };
    const wasm64 = try buildSingleFuncModule(allocator, &.{.i64}, &.{.i64}, &.{}, &i64_strength_code);
    defer allocator.free(wasm64);
    const opt64 = try optimize(allocator, wasm64, .{});
    defer allocator.free(opt64);
    var mod64 = try reader.readModule(allocator, opt64);
    defer mod64.deinit();
    try testing.expectEqualSlices(
        u8,
        &[_]u8{
            0x20, 0x00,
            0x42, 0x02, 0x86, // i64.const 2; i64.shl
            0x42, 0x03, 0x88, // i64.const 3; i64.shr_u
            0x42, 0x0f, 0x83, // i64.const 15; i64.and
            0x0b,
        },
        mod64.funcs.items[0].code_bytes,
    );

    // Two-constant non-trapping division/remainder folding:
    // (-20 /_s 3) = -6, (-20 %_s 3) = -2 -> (-6 + -2 = -8)
    const div_fold_code = [_]u8{
        0x41, 0x6c, // i32.const -20
        0x41, 0x03, // i32.const 3
        0x6d, // i32.div_s -> -6
        0x41, 0x6c, // i32.const -20
        0x41, 0x03, // i32.const 3
        0x6f, // i32.rem_s -> -2
        0x6a, // i32.add -> -8 (0x78)
        0x0b,
    };
    const wasm_div = try buildSingleFuncModule(allocator, &.{}, &.{.i32}, &.{}, &div_fold_code);
    defer allocator.free(wasm_div);
    const opt_div = try optimize(allocator, wasm_div, .{});
    defer allocator.free(opt_div);
    var mod_div = try reader.readModule(allocator, opt_div);
    defer mod_div.deinit();
    try testing.expectEqualSlices(u8, &[_]u8{ 0x41, 0x78, 0x0b }, mod_div.funcs.items[0].code_bytes);
}

test "Optimizer: constant reassociation without folding into MemArg.offset" {
    const allocator = testing.allocator;

    // 1. Cancelling reassociation: (x + 12) - 12 -> x
    const cancel_code = [_]u8{
        0x20, 0x00, // local.get 0
        0x41, 12, // i32.const 12
        0x6a, // i32.add
        0x41, 12, // i32.const 12
        0x6b, // i32.sub
        0x0b,
    };
    const wasm_cancel = try buildSingleFuncModule(allocator, &.{.i32}, &.{.i32}, &.{}, &cancel_code);
    defer allocator.free(wasm_cancel);
    const opt_cancel = try optimize(allocator, wasm_cancel, .{});
    defer allocator.free(opt_cancel);
    var mod_cancel = try reader.readModule(allocator, opt_cancel);
    defer mod_cancel.deinit();
    try testing.expectEqualSlices(u8, &[_]u8{ 0x20, 0x00, 0x0b }, mod_cancel.funcs.items[0].code_bytes);

    // 2. (x + 16) - 4 before i32.load reassociates to (x + 12) without folding into MemArg.offset
    const mem_reassoc_code = [_]u8{
        0x20, 0x00, // local.get 0
        0x41, 16, // i32.const 16
        0x6a, // i32.add
        0x41, 0x04, // i32.const 4
        0x6b, // i32.sub -> reassociates to (local.get 0 + 12)
        0x28, 0x02, 0x04, // i32.load align=2 offset=4
        0x0b,
    };
    const wasm_mem = try buildSingleFuncModule(allocator, &.{.i32}, &.{.i32}, &.{}, &mem_reassoc_code);
    defer allocator.free(wasm_mem);
    const opt_mem = try optimize(allocator, wasm_mem, .{});
    defer allocator.free(opt_mem);
    var mod_mem = try reader.readModule(allocator, opt_mem);
    defer mod_mem.deinit();
    try testing.expectEqualSlices(
        u8,
        &[_]u8{ 0x20, 0x00, 0x41, 12, 0x6a, 0x28, 0x02, 0x04, 0x0b },
        mod_mem.funcs.items[0].code_bytes,
    );
}

test "Optimizer: trivial 0-param constant and forwarding callee chain inlining" {
    const allocator = testing.allocator;

    var mod = Mod.Module.init(allocator);
    defer mod.deinit();

    const r_i32 = try allocator.dupe(types.ValType, &.{.i32});
    try mod.module_types.append(allocator, .{ .func_type = .{ .params = &.{}, .results = r_i32 } });
    try mod.type_meta.append(allocator, .{});

    // func 0 (getFactoryThunk): call 1; return; end
    const code0 = [_]u8{ 0x10, 0x01, 0x0f, 0x0b };
    // func 1 (host.getFactoryThunk): call 2; return; end
    const code1 = [_]u8{ 0x10, 0x02, 0x0f, 0x0b };
    // func 2 (export.getFactoryThunk): i32.const 1; return; end
    const code2 = [_]u8{ 0x41, 0x01, 0x0f, 0x0b };
    // func 3 (caller arithmetic): call 0; i32.const 41; i32.add; end
    const code3 = [_]u8{ 0x10, 0x00, 0x41, 41, 0x6a, 0x0b };

    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &code0 });
    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &code1 });
    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &code2 });
    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &code3 });

    try mod.exports.append(allocator, .{ .name = "getFactoryThunk", .kind = .func, .var_ = .{ .index = 0 } });
    try mod.exports.append(allocator, .{ .name = "compute", .kind = .func, .var_ = .{ .index = 3 } });

    const wasm = try writer.writeModule(allocator, &mod);
    defer allocator.free(wasm);

    const opt_bytes = try optimize(allocator, wasm, .{});
    defer allocator.free(opt_bytes);

    var opt_mod = try reader.readModule(allocator, opt_bytes);
    defer opt_mod.deinit();

    // Intermediate funcs 1 and 2 are pruned; only getFactoryThunk (0) and compute (1) remain.
    try testing.expectEqual(@as(usize, 2), opt_mod.funcs.items.len);
    // getFactoryThunk collapsed to `i32.const 1; end` (0x41 0x01 0x0b).
    try testing.expectEqualSlices(u8, &[_]u8{ 0x41, 0x01, 0x0b }, opt_mod.funcs.items[0].code_bytes);
    // compute inlined `call 0` -> `i32.const 1` and folded `1 + 41` -> `i32.const 42; end`.
    try testing.expectEqualSlices(u8, &[_]u8{ 0x41, 42, 0x0b }, opt_mod.funcs.items[1].code_bytes);
}

test "Optimizer: 1-parameter leaf inlining (field load, std.debug.assert, and std.math.isNan)" {
    const allocator = testing.allocator;

    var mod = Mod.Module.init(allocator);
    defer mod.deinit();

    try mod.memories.append(allocator, .{
        .type = .{ .limits = .{ .initial = 1 } },
    });

    // Type 0: (param i32) -> (result f32)
    try mod.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{.i32}),
        .results = try allocator.dupe(types.ValType, &.{.f32}),
    } });
    try mod.type_meta.append(allocator, .{});

    // Type 1: (param i32) -> ()
    try mod.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{.i32}),
        .results = &.{},
    } });
    try mod.type_meta.append(allocator, .{});

    // Type 2: (param f32) -> (result i32)
    try mod.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{.f32}),
        .results = try allocator.dupe(types.ValType, &.{.i32}),
    } });
    try mod.type_meta.append(allocator, .{});

    // Type 3: (param i32, i32) -> (result i32)
    try mod.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
        .results = try allocator.dupe(types.ValType, &.{.i32}),
    } });
    try mod.type_meta.append(allocator, .{});

    // func 0 (Rect.x): local.get 0; f32.load align=2 offset=4; return; end
    const rect_x_code = [_]u8{ 0x20, 0x00, 0x2a, 0x02, 0x04, 0x0f, 0x0b };
    // func 1 (std.debug.assert): block (empty) { local.get 0; br_if 0; unreachable } end; return; end
    const assert_code = [_]u8{ 0x02, 0x40, 0x20, 0x00, 0x0d, 0x00, 0x00, 0x0b, 0x0f, 0x0b };
    // func 2 (std.math.isNan): local.get 0; local.get 0; f32.ne; return; end
    const is_nan_code = [_]u8{ 0x20, 0x00, 0x20, 0x00, 0x5c, 0x0f, 0x0b };
    // func 3 (caller_pure):
    //   local.get 0; local.get 1; i32.lt_u; call $assert;
    //   local.get 0; call $rect_x; call $is_nan; end
    const caller_code = [_]u8{
        0x20, 0x00, // local.get 0
        0x20, 0x01, // local.get 1
        0x49, // i32.lt_u
        0x10, 0x01, // call $assert
        0x20, 0x00, // local.get 0
        0x10, 0x00, // call $rect_x
        0x10, 0x02, // call $is_nan
        0x0b, // end
    };
    // func 4 (caller_pure_isnan): local.get 0; call $is_nan; end
    const caller_pure_isnan_code = [_]u8{
        0x20, 0x00, // local.get 0
        0x10, 0x02, // call $is_nan
        0x0b, // end
    };

    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &rect_x_code });
    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 1 } }, .code_bytes = &assert_code });
    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 2 } }, .code_bytes = &is_nan_code });
    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 3 } }, .code_bytes = &caller_code });
    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 2 } }, .code_bytes = &caller_pure_isnan_code });

    try mod.exports.append(allocator, .{ .name = "caller", .kind = .func, .var_ = .{ .index = 3 } });
    try mod.exports.append(allocator, .{ .name = "caller_pure_isnan", .kind = .func, .var_ = .{ .index = 4 } });

    const wasm = try writer.writeModule(allocator, &mod);
    defer allocator.free(wasm);

    const opt_bytes = try optimize(allocator, wasm, .{});
    defer allocator.free(opt_bytes);

    var opt_mod = try reader.readModule(allocator, opt_bytes);
    defer opt_mod.deinit();

    // Helpers 0, 1, 2 were inlined and pruned; only the 2 exported callers remain.
    try testing.expectEqual(@as(usize, 2), opt_mod.funcs.items.len);

    // caller (func 0):
    // - `local.get 0; local.get 1; i32.lt_u; call $assert` inlined with zero scratch locals and
    //   folded `i32.lt_u; i32.eqz` -> `i32.ge_u; if (empty) { unreachable } end`
    // - `local.get 0; call $rect_x` inlined with zero scratch locals -> `local.get 0; f32.load align=2 offset=4`
    // - `call $is_nan` on non-pure `f32.load` folded `local.set 2; local.get 2` -> `local.tee 2; local.get 2; f32.ne`
    try testing.expectEqualSlices(types.ValType, &.{.f32}, opt_mod.funcs.items[0].local_types.items);
    try testing.expectEqualSlices(
        u8,
        &[_]u8{
            0x20, 0x00, // local.get 0
            0x20, 0x01, // local.get 1
            0x4f, // i32.ge_u
            0x04, 0x40, // if (empty)
            0x00, // unreachable
            0x0b, // end
            0x20, 0x00, // local.get 0
            0x2a, 0x02, 0x04, // f32.load align=2 offset=4
            0x22, 0x02, // local.tee 2
            0x20, 0x02, // local.get 2
            0x5c, // f32.ne
            0x0b, // end
        },
        opt_mod.funcs.items[0].code_bytes,
    );

    // caller_pure_isnan (func 1):
    // `local.get 0; call $is_nan` propagated `local.get 0` to both uses and compacted away the scratch local!
    try testing.expectEqual(@as(usize, 0), opt_mod.funcs.items[1].local_types.items.len);
    try testing.expectEqualSlices(
        u8,
        &[_]u8{
            0x20, 0x00, // local.get 0
            0x20, 0x00, // local.get 0
            0x5c, // f32.ne
            0x0b, // end
        },
        opt_mod.funcs.items[1].code_bytes,
    );
}

test "Optimizer: multi-parameter leaf inlining with simplifyLocals and compactLocals" {
    const allocator = testing.allocator;

    var mod = Mod.Module.init(allocator);
    defer mod.deinit();

    try mod.memories.append(allocator, .{
        .type = .{ .limits = .{ .initial = 1 } },
    });

    // Type 0: (param i32, i32) -> (result i32)
    try mod.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
        .results = try allocator.dupe(types.ValType, &.{.i32}),
    } });
    try mod.type_meta.append(allocator, .{});

    // Type 1: (param i32, i32, i32) -> (result i32)
    try mod.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{ .i32, .i32, .i32 }),
        .results = try allocator.dupe(types.ValType, &.{.i32}),
    } });
    try mod.type_meta.append(allocator, .{});

    // Type 2: (param i32) -> (result i32)
    try mod.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{.i32}),
        .results = try allocator.dupe(types.ValType, &.{.i32}),
    } });
    try mod.type_meta.append(allocator, .{});

    // func 0 (sub2): local.get 0; local.get 1; i32.sub; return; end (prefix_params = 2)
    const sub2_code = [_]u8{ 0x20, 0x00, 0x20, 0x01, 0x6b, 0x0f, 0x0b };
    // func 1 (fma_reuse): (a * b) + (c - a)
    // Uses param 0 (`a`) twice and accesses `c` then `a`, so params 0..2 use scratch locals on inline.
    const fma_code = [_]u8{
        0x20, 0x00, // local.get 0 (a)
        0x20, 0x01, // local.get 1 (b)
        0x6c, // i32.mul
        0x20, 0x02, // local.get 2 (c)
        0x20, 0x00, // local.get 0 (a)
        0x6b, // i32.sub
        0x6a, // i32.add
        0x0f, // return
        0x0b, // end
    };
    // func 2 (exported caller):
    //   local.get 0; i32.const 4; i32.const 20; call $fma_reuse;
    //   i32.const 5; call $sub2; end
    // Expected after inlining + simplifyLocals + foldConstants + compactLocals:
    //   ((x << 2) + (20 - x)) - 5, with 0 scratch locals remaining!
    const caller_code = [_]u8{
        0x20, 0x00, // local.get 0 (x)
        0x41, 0x04, // i32.const 4
        0x41, 20, // i32.const 20
        0x10, 0x01, // call $fma_reuse
        0x41, 0x05, // i32.const 5
        0x10, 0x00, // call $sub2
        0x0b, // end
    };

    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &sub2_code });
    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 1 } }, .code_bytes = &fma_code });
    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 2 } }, .code_bytes = &caller_code });

    try mod.exports.append(allocator, .{ .name = "compute", .kind = .func, .var_ = .{ .index = 2 } });

    const wasm = try writer.writeModule(allocator, &mod);
    defer allocator.free(wasm);

    const opt_bytes = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
    defer allocator.free(opt_bytes);

    var opt_mod = try reader.readModule(allocator, opt_bytes);
    defer opt_mod.deinit();

    try testing.expectEqual(@as(usize, 1), opt_mod.funcs.items.len);
    // All 3 temporary parameter locals from $fma_reuse were propagated and compacted away!
    try testing.expectEqual(@as(usize, 0), opt_mod.funcs.items[0].local_types.items.len);
    try testing.expectEqualSlices(
        u8,
        &[_]u8{
            0x20, 0x00, // local.get 0
            0x41, 0x02, // i32.const 2 (strength-reduced from * 4)
            0x74, // i32.shl
            0x41, 20, // i32.const 20
            0x20, 0x00, // local.get 0
            0x6b, // i32.sub
            0x6a, // i32.add
            0x41, 0x05, // i32.const 5
            0x6b, // i32.sub
            0x0b, // end
        },
        opt_mod.funcs.items[0].code_bytes,
    );
}

test "Optimizer: OptimizeMode.small vs OptimizeMode.fast leaf inlining thresholds" {
    const allocator = testing.allocator;

    var mod = Mod.Module.init(allocator);
    defer mod.deinit();

    // Type 0: (param i32) -> (result i32)
    try mod.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{.i32}),
        .results = try allocator.dupe(types.ValType, &.{.i32}),
    } });
    try mod.type_meta.append(allocator, .{});

    // func 0: 13-op leaf hash step (exceeds .small multi-call limit of 6 ops, within .fast limit of 64 ops)
    const medium_leaf_code = [_]u8{
        0x20, 0x00, // 1: local.get 0
        0x41, 16, // 2: i32.const 16
        0x76, // 3: i32.shr_u
        0x20, 0x00, // 4: local.get 0
        0x73, // 5: i32.xor
        0x41, 0x45, // 6: i32.const 0x45
        0x6c, // 7: i32.mul
        0x20, 0x00, // 8: local.get 0
        0x41, 0x07, // 9: i32.const 7
        0x77, // 10: i32.rotl
        0x73, // 11: i32.xor
        0x41, 0x01, // 12: i32.const 1
        0x6a, // 13: i32.add
        0x0f, // return
        0x0b, // end
    };

    // func 1 (exported caller calling func 0 twice):
    const dual_caller_code = [_]u8{
        0x20, 0x00, // local.get 0
        0x10, 0x00, // call 0
        0x10, 0x00, // call 0
        0x0b, // end
    };

    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &medium_leaf_code });
    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &dual_caller_code });
    try mod.exports.append(allocator, .{ .name = "hash2", .kind = .func, .var_ = .{ .index = 1 } });

    const wasm = try writer.writeModule(allocator, &mod);
    defer allocator.free(wasm);

    // In .small mode, func 0 has 2 call sites and 13 ops (> 6), so it is NOT inlined.
    const opt_small = try optimize(allocator, wasm, .{ .optimize_mode = .small });
    defer allocator.free(opt_small);
    var mod_small = try reader.readModule(allocator, opt_small);
    defer mod_small.deinit();
    try testing.expectEqual(@as(usize, 2), mod_small.funcs.items.len);
    try testing.expectEqualSlices(u8, &dual_caller_code, mod_small.funcs.items[1].code_bytes);

    // In .fast mode, func 0 (13 ops <= 64) IS inlined at both call sites and pruned!
    const opt_fast = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
    defer allocator.free(opt_fast);
    var mod_fast = try reader.readModule(allocator, opt_fast);
    defer mod_fast.deinit();
    try testing.expectEqual(@as(usize, 1), mod_fast.funcs.items.len);
}

test "Optimizer: early return, depth-0 br_if, return_call, and zero-init local in loop" {
    const allocator = testing.allocator;

    var mod = Mod.Module.init(allocator);
    defer mod.deinit();

    // Type 0: (param i32) -> (result i32)
    try mod.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{.i32}),
        .results = try allocator.dupe(types.ValType, &.{.i32}),
    } });
    try mod.type_meta.append(allocator, .{});

    // Type 1: (param i32) -> ()
    try mod.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{.i32}),
        .results = &.{},
    } });
    try mod.type_meta.append(allocator, .{});

    // func 0 (early_ret_1):
    //   local.get 0; if (empty) { i32.const 99; return } end; local.get 0; i32.const 1; i32.add; return; end
    const early_ret_1_code = [_]u8{
        0x20, 0x00, // local.get 0
        0x04, 0x40, // if (empty)
        0x41, 99, // i32.const 99
        0x0f, // return -> rewritten to `br 1` inside `block (result i32)`
        0x0b, // end
        0x20, 0x00, // local.get 0
        0x41, 0x01, // i32.const 1
        0x6a, // i32.add
        0x0f, // return
        0x0b, // end
    };

    // func 1 (depth0_br_if_0):
    //   local.get 0; br_if 0; nop; return; end (0-result, depth-0 br_if triggers needs_result_block)
    const depth0_br_if_code = [_]u8{
        0x20, 0x00, // local.get 0
        0x0d, 0x00, // br_if 0 (targets function root -> needs_result_block = true)
        0x0f, // return
        0x0b, // end
    };

    // func 2 (zero_init_local):
    //   has 1 non-param local (local 1: i32) read before write at depth 0:
    //   local.get 1; local.get 0; i32.add; local.tee 1; return; end
    const zero_init_code = [_]u8{
        0x20, 0x01, // local.get 1 (unwritten non-param local -> needs_local_zero_init[0] = true)
        0x20, 0x00, // local.get 0
        0x6a, // i32.add
        0x0f, // return
        0x0b, // end
    };

    // func 3 (tail_callee): local.get 0; i32.const 7; i32.add; return; end
    const tail_callee_code = [_]u8{ 0x20, 0x00, 0x41, 0x07, 0x6a, 0x0f, 0x0b };

    // func 4 (exported caller exercising early return, depth-0 br_if, zero-init inside loop, and return_call):
    const caller_code = [_]u8{
        0x20, 0x00, // local.get 0
        0x10, 0x01, // call $depth0_br_if_0
        0x03, 0x40, // loop (empty)
        0x20, 0x00, // local.get 0
        0x10, 0x02, // call $zero_init_local
        0x1a, // drop
        0x0b, // end loop
        0x20, 0x00, // local.get 0
        0x10, 0x00, // call $early_ret_1
        0x12, 0x03, // return_call $tail_callee -> emits `<spliced>; return`
        0x0b, // end
    };

    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &early_ret_1_code });
    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 1 } }, .code_bytes = &depth0_br_if_code });
    var func2 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &zero_init_code };
    try func2.local_types.append(allocator, .i32);
    try mod.funcs.append(allocator, func2);
    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &tail_callee_code });
    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &caller_code });

    try mod.exports.append(allocator, .{ .name = "run", .kind = .func, .var_ = .{ .index = 4 } });

    const wasm = try writer.writeModule(allocator, &mod);
    defer allocator.free(wasm);

    const opt_bytes = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
    defer allocator.free(opt_bytes);

    var opt_mod = try reader.readModule(allocator, opt_bytes);
    defer opt_mod.deinit();

    // All 4 helpers were inlined into `run` and pruned!
    try testing.expectEqual(@as(usize, 1), opt_mod.funcs.items.len);
    // Verify `return_call $tail_callee` emitted trailing `0x0f` (`return`) before `0x0b` (`end`).
    const run_bytes = opt_mod.funcs.items[0].code_bytes;
    try testing.expect(run_bytes.len >= 2);
    try testing.expectEqual(@as(u8, 0x0f), run_bytes[run_bytes.len - 2]);
    try testing.expectEqual(@as(u8, 0x0b), run_bytes[run_bytes.len - 1]);

    // Trailing `return` (0x0f) with extra stack values (`i32.const 1; local.get 0; return; end`)
    // is wrapped in `block (result i32)` and rewritten to `br 0` so extra stack values are unwound!
    var mod_stack = Mod.Module.init(allocator);
    defer mod_stack.deinit();
    try mod_stack.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{.i32}),
        .results = try allocator.dupe(types.ValType, &.{.i32}),
    } });
    try mod_stack.type_meta.append(allocator, .{});

    const extra_stack_callee = [_]u8{
        0x41, 0x01, // i32.const 1 (extra stack value)
        0x20, 0x00, // local.get 0 (actual return value)
        0x0f, // return (unwinds extra i32.const 1)
        0x0b, // end
    };
    const extra_stack_caller = [_]u8{
        0x20, 0x00, // local.get 0
        0x10, 0x00, // call 0
        0x0b, // end
    };
    try mod_stack.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &extra_stack_callee });
    try mod_stack.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &extra_stack_caller });
    try mod_stack.exports.append(allocator, .{ .name = "f", .kind = .func, .var_ = .{ .index = 1 } });

    const wasm_stack = try writer.writeModule(allocator, &mod_stack);
    defer allocator.free(wasm_stack);
    const opt_stack = try optimize(allocator, wasm_stack, .{ .optimize_mode = .fast });
    defer allocator.free(opt_stack);
    var mod_stack_opt = try reader.readModule(allocator, opt_stack);
    defer mod_stack_opt.deinit();

    try testing.expectEqual(@as(usize, 1), mod_stack_opt.funcs.items.len);
    try testing.expectEqualSlices(
        u8,
        &[_]u8{
            0x02, 0x7f, // block (result i32)
            0x41, 0x01, // i32.const 1
            0x20, 0x00, // local.get 0
            0x0c, 0x00, // br 0
            0x0b, // end block
            0x0b, // end func
        },
        mod_stack_opt.funcs.items[0].code_bytes,
    );
}

test "Optimizer: multi-caller forwarder to single-use medium leaf and large constant preservation in .small mode" {
    const allocator = testing.allocator;

    // 1. Multi-caller forwarder F -> 10-op single-use leaf L in .small mode:
    //    F is called twice, L is called once (by F). Resolving F -> L must NOT inline L twice in .small mode.
    var mod = Mod.Module.init(allocator);
    defer mod.deinit();

    try mod.module_types.append(allocator, .{ .func_type = .{
        .params = &.{},
        .results = try allocator.dupe(types.ValType, &.{.i32}),
    } });
    try mod.type_meta.append(allocator, .{});

    try mod.globals.append(allocator, .{
        .type = .{ .val_type = .i32, .mutability = .mutable },
        .init_expr_bytes = &[_]u8{ 0x41, 0x00 },
    });

    // func 0 (L): 9-op leaf reading global 0 (cannot be constant-folded, > 6 ops)
    const leaf_code = [_]u8{
        0x23, 0x00, // 1: global.get 0
        0x41, 0x03, // 2: i32.const 3
        0x73, // 3: i32.xor
        0x23, 0x00, // 4: global.get 0
        0x6a, // 5: i32.add
        0x23, 0x00, // 6: global.get 0
        0x73, // 7: i32.xor
        0x23, 0x00, // 8: global.get 0
        0x6a, // 9: i32.add
        0x0f, // return
        0x0b, // end
    };
    // func 1 (F): forwarder `call 0; return; end`
    const fwd_code = [_]u8{ 0x10, 0x00, 0x0f, 0x0b };
    // func 2 (exported caller): calls F twice (`call 1; call 1; i32.add; end`)
    const caller_code = [_]u8{ 0x10, 0x01, 0x10, 0x01, 0x6a, 0x0b };

    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &leaf_code });
    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &fwd_code });
    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &caller_code });
    try mod.exports.append(allocator, .{ .name = "main", .kind = .func, .var_ = .{ .index = 2 } });

    const wasm = try writer.writeModule(allocator, &mod);
    defer allocator.free(wasm);

    const opt_small = try optimize(allocator, wasm, .{ .optimize_mode = .small });
    defer allocator.free(opt_small);
    var mod_small = try reader.readModule(allocator, opt_small);
    defer mod_small.deinit();

    // Forwarder F (func 1) was bypassed and pruned, but L (func 0) was NOT inlined twice in .small mode!
    try testing.expectEqual(@as(usize, 2), mod_small.funcs.items.len);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x10, 0x00, 0x10, 0x00, 0x6a, 0x0b }, mod_small.funcs.items[1].code_bytes);

    // 2. Large constant local read 3 times is kept in a local in .small mode, but propagated in .fast mode:
    const large_const_code = [_]u8{
        0x41, 0x80, 0x80, 0x04, // i32.const 65536 (4 bytes)
        0x21, 0x00, // local.set 0
        0x20, 0x00, // local.get 0
        0x20, 0x00, // local.get 0
        0x20, 0x00, // local.get 0
        0x6c, // i32.mul
        0x6a, // i32.add
        0x0b, // end
    };
    const wasm_lc = try buildSingleFuncModule(allocator, &.{}, &.{.i32}, &.{.i32}, &large_const_code);
    defer allocator.free(wasm_lc);

    const opt_lc_small = try optimize(allocator, wasm_lc, .{ .optimize_mode = .small });
    defer allocator.free(opt_lc_small);
    var mod_lc_small = try reader.readModule(allocator, opt_lc_small);
    defer mod_lc_small.deinit();
    // In .small mode, local 0 is kept (`local.tee 0; local.get 0; local.get 0; i32.mul; i32.add`).
    try testing.expectEqual(@as(usize, 1), mod_lc_small.funcs.items[0].local_types.items.len);

    const opt_lc_fast = try optimize(allocator, wasm_lc, .{ .optimize_mode = .fast });
    defer allocator.free(opt_lc_fast);
    var mod_lc_fast = try reader.readModule(allocator, opt_lc_fast);
    defer mod_lc_fast.deinit();
    // In .fast mode, local 0 is propagated, constant-folded, and compacted away!
    try testing.expectEqual(@as(usize, 0), mod_lc_fast.funcs.items[0].local_types.items.len);
}

test "Optimizer: stage2_wasm assert inner-block and Rect.x shadow-stack copy inlining in .small mode" {
    const allocator = testing.allocator;

    var mod = Mod.Module.init(allocator);
    defer mod.deinit();

    try mod.memories.append(allocator, .{
        .type = .{ .limits = .{ .initial = 1 } },
    });
    try mod.globals.append(allocator, .{
        .type = .{ .val_type = .i32, .mutability = .mutable },
        .init_expr_bytes = &[_]u8{ 0x41, 0x00 },
    });

    // Type 0: (param i32) -> ()  (std.debug.assert)
    try mod.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{.i32}),
        .results = &.{},
    } });
    try mod.type_meta.append(allocator, .{});

    // Type 1: (param i32) -> (result f32)  (Rect.y)
    try mod.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{.i32}),
        .results = try allocator.dupe(types.ValType, &.{.f32}),
    } });
    try mod.type_meta.append(allocator, .{});

    // func 0: stage2_wasm lowering of `std.debug.assert(ok: bool)`:
    //   (local i32)
    //   block (0x40)
    //     local.get 0; i32.eqz; local.set 1;
    //     block (0x40)
    //       local.get 1; br_if 0; br 1
    //     end
    //     unreachable
    //   end
    //   return; end
    const stage2_assert_code = [_]u8{
        0x02, 0x40, // block (empty)
        0x20, 0x00, // local.get 0
        0x45, // i32.eqz
        0x21, 0x01, // local.set 1
        0x02, 0x40, // block (empty)
        0x20, 0x01, // local.get 1
        0x0d, 0x00, // br_if 0
        0x0c, 0x01, // br 1
        0x0b, // end inner block
        0x00, // unreachable
        0x0b, // end outer block
        0x0f, // return
        0x0b, // end
    };

    // func 1: stage2_wasm lowering of `Rect.y(self: Rect) f32` with 16-byte shadow-stack copy:
    //   (local i32)
    //   global.get 0; i32.const 16; i32.sub; local.tee 1;
    //   local.get 0; i32.const 16; memory.copy 0 0;
    //   local.get 1; f32.load align=2 offset=4; return; end
    const stage2_rect_y_code = [_]u8{
        0x23, 0x00, // global.get 0
        0x41, 16, // i32.const 16
        0x6b, // i32.sub
        0x22, 0x01, // local.tee 1
        0x20, 0x00, // local.get 0
        0x41, 16, // i32.const 16
        0xfc, 0x0a, 0x00, 0x00, // memory.copy 0 0
        0x20, 0x01, // local.get 1
        0x2a, 0x02, 0x04, // f32.load align=2 offset=4
        0x0f, // return
        0x0b, // end
    };

    // func 2 (exported caller):
    //   local.get 0; i32.const 0; i32.ne; call $assert;
    //   local.get 0; call $rect_y; end
    const caller_code = [_]u8{
        0x20, 0x00, // local.get 0
        0x41, 0x00, // i32.const 0
        0x47, // i32.ne
        0x10, 0x00, // call $assert
        0x20, 0x00, // local.get 0
        0x10, 0x01, // call $rect_y
        0x0b, // end
    };

    var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &stage2_assert_code };
    try f0.local_types.append(allocator, .i32);
    try mod.funcs.append(allocator, f0);

    var f1 = Mod.Func{ .decl = .{ .type_var = .{ .index = 1 } }, .code_bytes = &stage2_rect_y_code };
    try f1.local_types.append(allocator, .i32);
    try mod.funcs.append(allocator, f1);

    try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 1 } }, .code_bytes = &caller_code });
    try mod.exports.append(allocator, .{ .name = "get_y", .kind = .func, .var_ = .{ .index = 2 } });

    const wasm = try writer.writeModule(allocator, &mod);
    defer allocator.free(wasm);

    const opt_small = try optimize(allocator, wasm, .{ .optimize_mode = .small });
    defer allocator.free(opt_small);

    var opt_mod = try reader.readModule(allocator, opt_small);
    defer opt_mod.deinit();

    // Both `std.debug.assert` and `Rect.y` were simplified to 0-local prefix_params=1 leaves,
    // inlined into `get_y` in .small mode, and pruned!
    try testing.expectEqual(@as(usize, 1), opt_mod.funcs.items.len);
    try testing.expectEqual(@as(usize, 0), opt_mod.funcs.items[0].local_types.items.len);
    try testing.expectEqualSlices(
        u8,
        &[_]u8{
            0x20, 0x00, // local.get 0
            0x45, // i32.eqz (folded from `i32.const 0; i32.ne; i32.eqz`)
            0x04, 0x40, // if (empty)
            0x00, // unreachable
            0x0b, // end
            0x20, 0x00, // local.get 0
            0x2a, 0x02, 0x04, // f32.load align=2 offset=4
            0x0b, // end
        },
        opt_mod.funcs.items[0].code_bytes,
    );

    // 2. `eliminateLeafStackCopy` must NOT strip the prologue if the tail contains a 0xfd SIMD store (`v128.store`):
    var mod_simd = Mod.Module.init(allocator);
    defer mod_simd.deinit();
    try mod_simd.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
    try mod_simd.globals.append(allocator, .{
        .type = .{ .val_type = .i32, .mutability = .mutable },
        .init_expr_bytes = &[_]u8{ 0x41, 0x00 },
    });
    try mod_simd.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{ .i32, .v128 }),
        .results = try allocator.dupe(types.ValType, &.{.f32}),
    } });
    try mod_simd.type_meta.append(allocator, .{});

    const simd_store_code = [_]u8{
        0x23, 0x00, // global.get 0
        0x41, 16, // i32.const 16
        0x6b, // i32.sub
        0x22, 0x02, // local.tee 2
        0x20, 0x00, // local.get 0
        0x41, 16, // i32.const 16
        0xfc, 0x0a, 0x00, 0x00, // memory.copy 0 0
        0x20, 0x00, // local.get 0
        0x20, 0x01, // local.get 1 (v128)
        0xfd, 0x0b, 0x04, 0x00, // v128.store align=4 offset=0
        0x20, 0x02, // local.get 2
        0x2a, 0x02, 0x00, // f32.load align=2 offset=0
        0x0b, // end
    };
    var f_simd = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &simd_store_code };
    try f_simd.local_types.append(allocator, .i32);
    try mod_simd.funcs.append(allocator, f_simd);
    try mod_simd.exports.append(allocator, .{ .name = "simd_fn", .kind = .func, .var_ = .{ .index = 0 } });

    const wasm_simd = try writer.writeModule(allocator, &mod_simd);
    defer allocator.free(wasm_simd);
    const opt_simd = try optimize(allocator, wasm_simd, .{ .optimize_mode = .small });
    defer allocator.free(opt_simd);
    var mod_simd_opt = try reader.readModule(allocator, opt_simd);
    defer mod_simd_opt.deinit();
    // Prologue and scratch local 2 are preserved because of `v128.store`!
    try testing.expectEqual(@as(usize, 1), mod_simd_opt.funcs.items[0].local_types.items.len);
    try testing.expectEqualSlices(u8, &simd_store_code, mod_simd_opt.funcs.items[0].code_bytes);

    // 3. `rewriteNameSectionPayload` on the `all_live` path (no dead functions removed) prunes
    //    stale subsection 2 (local names) when `compactLocals` removes an unused local:
    var mod_names = Mod.Module.init(allocator);
    defer mod_names.deinit();
    try mod_names.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{.i32}),
        .results = try allocator.dupe(types.ValType, &.{.i32}),
    } });
    try mod_names.type_meta.append(allocator, .{});

    // Exported function 0 has 1 unused non-parameter local (local 1: i32) that `compactLocals` removes.
    const unused_local_code = [_]u8{ 0x20, 0x00, 0x0b };
    var f_names = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &unused_local_code };
    try f_names.local_types.append(allocator, .i32);
    try mod_names.funcs.append(allocator, f_names);
    try mod_names.exports.append(allocator, .{ .name = "id", .kind = .func, .var_ = .{ .index = 0 } });

    // Name section with subsec 1 (func 0 -> "id") and subsec 2 (func 0 -> { local 0 -> "x", local 1 -> "unused" })
    const name_sec = [_]u8{
        1, 5, 1, 0, 2, 'i', 'd', // subsec 1: 1 entry (func 0 -> "id")
        2, 14, 1, 0, 2, 0, 1, 'x', 1, 6, 'u', 'n', 'u', 's', 'e', 'd', // subsec 2: 1 func (0) with 2 local names
    };
    try mod_names.customs.append(allocator, .{ .name = "name", .data = &name_sec });

    const wasm_names = try writer.writeModule(allocator, &mod_names);
    defer allocator.free(wasm_names);
    const opt_names = try optimize(allocator, wasm_names, .{ .custom_sections = .preserve, .optimize_mode = .small });
    defer allocator.free(opt_names);
    var mod_names_opt = try reader.readModule(allocator, opt_names);
    defer mod_names_opt.deinit();

    try testing.expectEqual(@as(usize, 0), mod_names_opt.funcs.items[0].local_types.items.len);
    try testing.expectEqual(@as(usize, 1), mod_names_opt.customs.items.len);
    // Subsec 1 (func names) is preserved, while stale subsec 2 (local names for compacted func 0) is dropped!
    try testing.expectEqualSlices(u8, &[_]u8{ 1, 5, 1, 0, 2, 'i', 'd' }, mod_names_opt.customs.items[0].data);

    // 4. 2-result leaf function without early returns is inlined in .fast mode:
    var mod_mv = Mod.Module.init(allocator);
    defer mod_mv.deinit();
    try mod_mv.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{ .f32, .f32, .f32 }),
        .results = try allocator.dupe(types.ValType, &.{ .f32, .f32 }),
    } });
    try mod_mv.type_meta.append(allocator, .{});
    try mod_mv.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{ .f32, .f32, .f32 }),
        .results = try allocator.dupe(types.ValType, &.{.f32}),
    } });
    try mod_mv.type_meta.append(allocator, .{});

    const curve_extent_code = [_]u8{
        0x20, 0x00, // local.get 0
        0x20, 0x01, // local.get 1
        0x96, // f32.min
        0x20, 0x02, // local.get 2
        0x96, // f32.min
        0x20, 0x00, // local.get 0
        0x20, 0x01, // local.get 1
        0x97, // f32.max
        0x20, 0x02, // local.get 2
        0x97, // f32.max
        0x0f, // return
        0x0b, // end
    };
    const mv_caller_code = [_]u8{
        0x20, 0x00, // local.get 0
        0x20, 0x01, // local.get 1
        0x20, 0x02, // local.get 2
        0x10, 0x00, // call $curveExtent
        0x92, // f32.add
        0x0f, // return
        0x0b, // end
    };
    try mod_mv.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &curve_extent_code });
    try mod_mv.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 1 } }, .code_bytes = &mv_caller_code });
    try mod_mv.exports.append(allocator, .{ .name = "sum_extent", .kind = .func, .var_ = .{ .index = 1 } });

    const wasm_mv = try writer.writeModule(allocator, &mod_mv);
    defer allocator.free(wasm_mv);
    const opt_mv = try optimize(allocator, wasm_mv, .{ .optimize_mode = .fast });
    defer allocator.free(opt_mv);
    var mod_mv_opt = try reader.readModule(allocator, opt_mv);
    defer mod_mv_opt.deinit();

    // `curveExtent` was inlined into `sum_extent` and pruned by dead-function removal!
    try testing.expectEqual(@as(usize, 1), mod_mv_opt.funcs.items.len);
}

test "Optimizer: .small mode single-caller leaf and multi-caller 7-op/1-local accessor inlining" {
    const allocator = testing.allocator;

    // 1. Single-caller internal leaf with 18 ops and 2 locals is inlined in .small mode and removed:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        // func 0: single-caller internal leaf (2 params, 2 locals, 18 ops)
        const single_caller_leaf = [_]u8{
            0x20, 0x00, // 1: local.get 0
            0x28, 0x02, 0x00, // 2: i32.load align=2 offset=0
            0x22, 0x02, // 3: local.tee 2
            0x20, 0x01, // 4: local.get 1
            0x6a, // 5: i32.add
            0x22, 0x03, // 6: local.tee 3
            0x20, 0x00, // 7: local.get 0
            0x28, 0x02, 0x04, // 8: i32.load align=2 offset=4
            0x73, // 9: i32.xor
            0x20, 0x02, // 10: local.get 2
            0x6c, // 11: i32.mul
            0x20, 0x03, // 12: local.get 3
            0x41, 0x03, // 13: i32.const 3
            0x74, // 14: i32.shl
            0x6a, // 15: i32.add
            0x20, 0x01, // 16: local.get 1
            0x73, // 17: i32.xor
            0x0f, // 18: return (stripped at effective_end)
            0x0b, // end
        };
        const sole_caller = [_]u8{
            0x20, 0x00, // local.get 0
            0x20, 0x01, // local.get 1
            0x10, 0x00, // call 0
            0x41, 0x01, // i32.const 1
            0x6a, // i32.add
            0x0b, // end
        };

        var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &single_caller_leaf };
        try f0.local_types.appendSlice(allocator, &.{ .i32, .i32 });
        try mod.funcs.append(allocator, f0);
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &sole_caller });
        try mod.exports.append(allocator, .{ .name = "entry", .kind = .func, .var_ = .{ .index = 1 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt_small = try optimize(allocator, wasm, .{ .optimize_mode = .small });
        defer allocator.free(opt_small);
        var opt_mod = try reader.readModule(allocator, opt_small);
        defer opt_mod.deinit();

        // Single-caller leaf (func 0) was inlined into `entry` and pruned by removeDeadFunctions!
        try testing.expectEqual(@as(usize, 1), opt_mod.funcs.items.len);
    }

    // 2. Multi-caller 7-op, 2-param, 0-local accessor with prefix_params == 0 (like ArrayList.appendAssumeCapacity)
    //    and multi-caller 9-op, 2-param, 1-local accessor (like ElementPool.get) are inlined in .small mode,
    //    while a multi-caller accessor touching globals (`uses_global_op`) is NOT inlined:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.globals.append(allocator, .{
            .type = .{ .val_type = .i32, .mutability = .mutable },
            .init_expr_bytes = &[_]u8{ 0x41, 0x00 },
        });

        // Type 0: (param i32, i32) -> ()
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
            .results = &.{},
        } });
        try mod.type_meta.append(allocator, .{});

        // Type 1: (param i32, i32) -> (result i32)
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        // func 0 (appendAssumeCapacity-like): 2 params, 0 locals, 7 ops, reads param 0 twice (prefix_params == 0)
        //   local.get 0; local.get 0; i32.load offset=4; i32.add; local.get 1; i32.store offset=0; return; end
        const append_assume_cap = [_]u8{
            0x20, 0x00, // 1: local.get 0
            0x20, 0x00, // 2: local.get 0
            0x28, 0x02, 0x04, // 3: i32.load align=2 offset=4
            0x6a, // 4: i32.add
            0x20, 0x01, // 5: local.get 1
            0x36, 0x02, 0x00, // 6: i32.store align=2 offset=0
            0x0f, // 7: return
            0x0b, // end
        };

        // func 1 (ElementPool.get-like): 2 params, 1 local, 9 ops
        //   local.get 0; i32.load offset=0; local.get 1; i32.const 12; i32.mul; local.tee 2; i32.add; i32.load offset=0; return; end
        const pool_get = [_]u8{
            0x20, 0x00, // 1: local.get 0
            0x28, 0x02, 0x00, // 2: i32.load align=2 offset=0
            0x20, 0x01, // 3: local.get 1
            0x41, 12, // 4: i32.const 12
            0x6c, // 5: i32.mul
            0x22, 0x02, // 6: local.tee 2
            0x6a, // 7: i32.add
            0x20, 0x02, // 8: local.get 2
            0x73, // 9: i32.xor
            0x0f, // return (stripped -> 9 ops)
            0x0b, // end
        };

        // func 2 (global-touching helper): 1 param, 0 locals, 4 ops, uses global.get 0
        const global_helper = [_]u8{
            0x20, 0x00, // 1: local.get 0
            0x23, 0x00, // 2: global.get 0
            0x6a, // 3: i32.add
            0x20, 0x01, // 4: local.get 1
            0x6a, // 5: i32.add
            0x0f, // return
            0x0b, // end
        };

        // func 3 (exported caller calling each helper twice):
        const multi_caller = [_]u8{
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x00, // call $append_assume_cap (1)
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x00, // call $append_assume_cap (2)
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x01, // call $pool_get (1)
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x01, // call $pool_get (2)
            0x6a, 0x20,
            0x00, 0x20,
            0x01,
            0x10, 0x02, // call $global_helper (1)
            0x6a, 0x20,
            0x00, 0x20,
            0x01,
            0x10, 0x02, // call $global_helper (2)
            0x6a, 0x0b,
        };

        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &append_assume_cap });
        var f1 = Mod.Func{ .decl = .{ .type_var = .{ .index = 1 } }, .code_bytes = &pool_get };
        try f1.local_types.append(allocator, .i32);
        try mod.funcs.append(allocator, f1);
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 1 } }, .code_bytes = &global_helper });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 1 } }, .code_bytes = &multi_caller });
        try mod.exports.append(allocator, .{ .name = "run", .kind = .func, .var_ = .{ .index = 3 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt_small = try optimize(allocator, wasm, .{ .optimize_mode = .small });
        defer allocator.free(opt_small);
        var opt_mod = try reader.readModule(allocator, opt_small);
        defer opt_mod.deinit();

        // `append_assume_cap` (func 0) and `pool_get` (func 1) were inlined and pruned;
        // only `global_helper` (now func 0) and `run` (now func 1) remain!
        try testing.expectEqual(@as(usize, 2), opt_mod.funcs.items.len);
    }
}

test "Optimizer: .fast mode 1-cold-call wrapper inlining and trivial inner-callee chaining" {
    const allocator = testing.allocator;

    // 1. 1-cold-call wrapper (`if (len == cap) call $slow_grow`) is inlined in .fast mode,
    //    NOT inlined in .small mode, and a depth-0 call wrapper is NOT inlined as a 1-cold-call wrapper:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        // Imported slow-path function (index 0): (param i32, i32) -> ()
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
            .results = &.{},
        } });
        try mod.type_meta.append(allocator, .{});

        try mod.imports.append(allocator, .{
            .module_name = "env",
            .field_name = "slow_grow",
            .kind = .func,
            .func = .{ .type_var = .{ .index = 0 } },
        });
        try mod.funcs.append(allocator, .{
            .is_import = true,
            .decl = .{ .type_var = .{ .index = 0 } },
        });
        mod.num_func_imports = 1;

        // func 1 (ensureUnusedCapacity):
        //   local.get 0; i32.load offset=4 (len); local.get 0; i32.load offset=8 (cap); i32.eq;
        //   if (empty) { local.get 0; local.get 1; call $slow_grow } end; return; end
        const ensure_cap_wrapper = [_]u8{
            0x20, 0x00, // local.get 0
            0x28, 0x02, 0x04, // i32.load align=2 offset=4
            0x20, 0x00, // local.get 0
            0x28, 0x02, 0x08, // i32.load align=2 offset=8
            0x46, // i32.eq
            0x04, 0x40, // if (empty) (depth becomes 1 > 0)
            0x20, 0x00, // local.get 0
            0x20, 0x01, // local.get 1
            0x10, 0x00, // call $slow_grow (at depth 1)
            0x0b, // end if
            0x0f, // return
            0x0b, // end
        };

        // func 2 (depth-0 unconditional call wrapper — must NOT be inlined):
        const depth0_call_wrapper = [_]u8{
            0x20, 0x00, // local.get 0
            0x28, 0x02, 0x04, // i32.load align=2 offset=4
            0x20, 0x01, // local.get 1
            0x6a, // i32.add
            0x20, 0x00, // local.get 0
            0x10, 0x00, // call $slow_grow (at depth 0 -> rejected!)
            0x0f, // return
            0x0b, // end
        };

        // func 3 (exported caller): calls both func 1 and func 2
        const caller_code = [_]u8{
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x01, // call $ensure_cap_wrapper
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x02, // call $depth0_call_wrapper
            0x0b,
        };

        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &ensure_cap_wrapper });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &depth0_call_wrapper });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &caller_code });
        try mod.exports.append(allocator, .{ .name = "push", .kind = .func, .var_ = .{ .index = 3 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);

        // In .small mode, neither wrapper is inlined (all 4 funcs remain: 1 import + 3 defined).
        const opt_small = try optimize(allocator, wasm, .{ .optimize_mode = .small });
        defer allocator.free(opt_small);
        var mod_small = try reader.readModule(allocator, opt_small);
        defer mod_small.deinit();
        try testing.expectEqual(@as(usize, 4), mod_small.funcs.items.len);

        // In .fast mode, `ensure_cap_wrapper` (func 1) IS inlined and pruned, while `depth0_call_wrapper` (func 2) is NOT!
        const opt_fast = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt_fast);
        var mod_fast = try reader.readModule(allocator, opt_fast);
        defer mod_fast.deinit();
        try testing.expectEqual(@as(usize, 3), mod_fast.funcs.items.len);
    }

    // 2. Chained case: 1-cold-call wrapper calls a trivial leaf/forward function (verifies no UAF across rounds):
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        // Type 0: (param i32, i32) -> ()
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
            .results = &.{},
        } });
        try mod.type_meta.append(allocator, .{});

        // func 0 (wrapper): 1-cold-call wrapper calling trivial leaf func 1 at depth 1
        //   Placed BEFORE func 1 and before caller func 2 so if func 0 were inlined in the same round
        //   that func 0 inlines func 1, freeing func 0's code_bytes would UAF when func 2 inlines func 0!
        const wrapper_code = [_]u8{
            0x20, 0x00, // local.get 0
            0x28, 0x02, 0x04, // i32.load align=2 offset=4
            0x04, 0x40, // if (empty)
            0x20, 0x00, // local.get 0
            0x20, 0x01, // local.get 1
            0x10, 0x01, // call $trivial_leaf (func 1)
            0x0b, // end if
            0x0f, // return
            0x0b, // end
        };

        // func 1 (trivial_leaf): `local.get 0; local.get 1; i32.store offset=0; return; end`
        const trivial_leaf_code = [_]u8{
            0x20, 0x00, // local.get 0
            0x20, 0x01, // local.get 1
            0x36, 0x02, 0x00, // i32.store align=2 offset=0
            0x0f, // return
            0x0b, // end
        };

        // func 2 (exported caller): calls wrapper (func 0) twice
        const caller_code = [_]u8{
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x00, // call $wrapper
            0x20, 0x00,
            0x41, 42,
            0x10, 0x00, // call $wrapper
            0x0b,
        };

        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &wrapper_code });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &trivial_leaf_code });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &caller_code });
        try mod.exports.append(allocator, .{ .name = "run_chained", .kind = .func, .var_ = .{ .index = 2 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);

        const opt_fast = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt_fast);
        var mod_fast = try reader.readModule(allocator, opt_fast);
        defer mod_fast.deinit();

        // Round 1: `trivial_leaf` (func 1) is inlined into `wrapper` (func 0).
        // Round 2: `wrapper` (func 0, now a pure leaf) is inlined into `run_chained` (func 2).
        // Both helpers are pruned, leaving only `run_chained`!
        try testing.expectEqual(@as(usize, 1), mod_fast.funcs.items.len);
    }

    // 3. Conditional guard (`seen_cond_branch`) and `!has_loop` requirements for .fast 1-cold-call wrappers,
    //    plus multi-hop forward-chain `orig_forwards` / `!leaf.uses_global_op` check in .small mode:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
            .results = &.{},
        } });
        try mod.type_meta.append(allocator, .{});

        try mod.imports.append(allocator, .{
            .module_name = "env",
            .field_name = "slow_grow",
            .kind = .func,
            .func = .{ .type_var = .{ .index = 0 } },
        });
        try mod.funcs.append(allocator, .{
            .is_import = true,
            .decl = .{ .type_var = .{ .index = 0 } },
        });
        mod.num_func_imports = 1;

        // func 1 (br_if guarded block wrapper — `seen_cond_branch == true, !has_loop` -> inlined in .fast):
        const br_if_wrapper = [_]u8{
            0x02, 0x40, // block (empty)
            0x20, 0x00, // local.get 0
            0x28, 0x02, 0x04, // i32.load align=2 offset=4
            0x20, 0x01, // local.get 1
            0x49, // i32.lt_u
            0x0d, 0x00, // br_if 0 (sets seen_cond_branch = true)
            0x20, 0x00, // local.get 0
            0x20, 0x01, // local.get 1
            0x10, 0x00, // call $slow_grow
            0x0b, // end block
            0x0f, // return
            0x0b, // end
        };

        // func 2 (unconditional block wrapper — `seen_cond_branch == false` -> rejected!):
        const uncond_block_wrapper = [_]u8{
            0x02, 0x40, // block (empty)
            0x20, 0x00, // local.get 0
            0x20, 0x01, // local.get 1
            0x10, 0x00, // call $slow_grow (depth 1, but seen_cond_branch == false!)
            0x0b, // end block
            0x0f, // return
            0x0b, // end
        };

        // func 3 (loop wrapper — `has_loop == true` -> rejected!):
        const loop_wrapper = [_]u8{
            0x03, 0x40, // loop (empty)
            0x20, 0x00, // local.get 0
            0x04, 0x40, // if (empty)
            0x20, 0x00, // local.get 0
            0x20, 0x01, // local.get 1
            0x10, 0x00, // call $slow_grow (inside loop -> rejected!)
            0x0b, // end if
            0x0b, // end loop
            0x0f, // return
            0x0b, // end
        };

        // func 4 (exported caller): calls funcs 1, 2, 3
        const caller_code = [_]u8{
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x01, // call $br_if_wrapper (inlined)
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x02, // call $uncond_block_wrapper (not inlined)
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x03, // call $loop_wrapper (not inlined)
            0x0b,
        };

        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &br_if_wrapper });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &uncond_block_wrapper });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &loop_wrapper });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &caller_code });
        try mod.exports.append(allocator, .{ .name = "test_guards", .kind = .func, .var_ = .{ .index = 4 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);

        const opt_fast = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt_fast);
        var mod_fast = try reader.readModule(allocator, opt_fast);
        defer mod_fast.deinit();

        // Only `br_if_wrapper` (func 1) was inlined and pruned; import (0), uncond_block_wrapper, loop_wrapper, and caller remain (4 funcs).
        try testing.expectEqual(@as(usize, 4), mod_fast.funcs.items.len);
    }

    // 4. Multi-hop forward chain `F2 -> F1 -> F0 -> L` in .small mode where F0 has 2 callers and L uses a global:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = &.{},
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});
        try mod.globals.append(allocator, .{
            .type = .{ .val_type = .i32, .mutability = .mutable },
            .init_expr_bytes = &[_]u8{ 0x41, 0x00 },
        });

        // func 0 (L): 5-op leaf using global.get 0 (called once by F0, so classified as single-caller .leaf in round 1)
        const leaf_global = [_]u8{
            0x23, 0x00, // 1: global.get 0
            0x41, 0x07, // 2: i32.const 7
            0x73, // 3: i32.xor
            0x23, 0x00, // 4: global.get 0
            0x6a, // 5: i32.add
            0x0f, // return
            0x0b, // end
        };
        // func 1 (F0): forwards to L (0), called twice (by F1 and directly by caller)
        const f0_code = [_]u8{ 0x10, 0x00, 0x0f, 0x0b };
        // func 2 (F1): forwards to F0 (1), called once (by F2)
        const f1_code = [_]u8{ 0x10, 0x01, 0x0f, 0x0b };
        // func 3 (F2): forwards to F1 (2), called once (by caller)
        const f2_code = [_]u8{ 0x10, 0x02, 0x0f, 0x0b };
        // func 4 (exported caller): calls F0 (1) and F2 (3)
        const caller_code = [_]u8{ 0x10, 0x01, 0x10, 0x03, 0x6a, 0x0b };

        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &leaf_global });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &f0_code });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &f1_code });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &f2_code });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &caller_code });
        try mod.exports.append(allocator, .{ .name = "main", .kind = .func, .var_ = .{ .index = 4 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);

        const opt_small = try optimize(allocator, wasm, .{ .optimize_mode = .small });
        defer allocator.free(opt_small);
        var mod_small = try reader.readModule(allocator, opt_small);
        defer mod_small.deinit();

        // F0, F1, F2 are bypassed and pruned, but L (func 0, uses_global_op) is NOT inlined twice into `main`!
        try testing.expectEqual(@as(usize, 2), mod_small.funcs.items.len);
        try testing.expectEqualSlices(u8, &[_]u8{ 0x10, 0x00, 0x10, 0x00, 0x6a, 0x0b }, mod_small.funcs.items[1].code_bytes);
    }
}

test "Optimizer: eliminateLeafStackCopy with padded stack frame (copy_size < stack_size) and read-only control flow" {
    const allocator = testing.allocator;

    // 1. 24-byte `Curve` copy in 32-byte aligned stack frame with read-only `block`/`if` control flow (`band.curveExtent` pattern):
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.globals.append(allocator, .{
            .type = .{ .val_type = .i32, .mutability = .mutable },
            .init_expr_bytes = &[_]u8{ 0x41, 0x80, 0x80, 0x04 },
        });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{.i32}),
            .results = try allocator.dupe(types.ValType, &.{ .f32, .f32 }),
        } });
        try mod.type_meta.append(allocator, .{});

        const curve_extent_body = [_]u8{
            0x23, 0x00, // global.get 0
            0x41, 32, // i32.const 32 (stack_size = 32)
            0x6b, // i32.sub
            0x22, 0x01, // local.tee 1 (tmp_local)
            0x20, 0x00, // local.get 0 (src_param)
            0x41, 24, // i32.const 24 (copy_size = 24 < 32)
            0xfc, 0x0a, 0x00, 0x00, // memory.copy 0 0
            0x02, 0x7d, // block (result f32)
            0x20, 0x01, // local.get 1
            0x2a, 0x02, 0x04, // f32.load align=2 offset=4
            0x20, 0x01, // local.get 1
            0x2a, 0x02, 0x0c, // f32.load align=2 offset=12
            0x96, // f32.min
            0x0b, // end block
            0x20, 0x01, // local.get 1
            0x28, 0x02, 0x10, // i32.load align=2 offset=16 (within [0, 24))
            0x04, 0x7d, // if (result f32)
            0x20, 0x01, // local.get 1
            0x2a, 0x02, 0x14, // f32.load align=2 offset=20 (20 + 4 <= 24)
            0x05, // else
            0x20, 0x01, // local.get 1
            0x2a, 0x02, 0x04, // f32.load align=2 offset=4
            0x0b, // end if
            0x0f, // return
            0x0b, // end
        };

        var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &curve_extent_body };
        try f0.local_types.append(allocator, .i32); // local 1 (tmp_local)
        try mod.funcs.append(allocator, f0);
        try mod.exports.append(allocator, .{ .name = "curveExtent", .kind = .func, .var_ = .{ .index = 0 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        // Scratch local 1 and the 7-op stack copy prologue are completely eliminated!
        try testing.expectEqual(@as(usize, 0), opt_mod.funcs.items[0].local_types.items.len);
        const expected = [_]u8{
            0x20, 0x00, // local.get 0
            0x2a, 0x02, 0x04, // f32.load align=2 offset=4
            0x20, 0x00, // local.get 0
            0x2a, 0x02, 0x0c, // f32.load align=2 offset=12
            0x96, // f32.min
            0x20, 0x00, // local.get 0
            0x28, 0x02, 0x10, // i32.load align=2 offset=16
            0x04, 0x7d, // if (result f32)
            0x20, 0x00, // local.get 0
            0x2a, 0x02, 0x14, // f32.load align=2 offset=20
            0x05, // else
            0x20, 0x00, // local.get 0
            0x2a, 0x02, 0x04, // f32.load align=2 offset=4
            0x0b, // end if
            0x0f, // return
            0x0b, // end
        };
        try testing.expectEqualSlices(u8, &expected, opt_mod.funcs.items[0].code_bytes);
    }

    // 2. Load accessing uncopied padding `[24, 32)` (offset 24 when copy_size == 24) is NOT rewritten:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.globals.append(allocator, .{
            .type = .{ .val_type = .i32, .mutability = .mutable },
            .init_expr_bytes = &[_]u8{ 0x41, 0x80, 0x80, 0x04 },
        });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{.i32}),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        const out_of_range_body = [_]u8{
            0x23, 0x00,
            0x41, 32,
            0x6b, 0x22,
            0x01, 0x20,
            0x00, 0x41,
            24,   0xfc,
            0x0a, 0x00,
            0x00, 0x20,
            0x01,
            0x28, 0x02, 24, // i32.load offset=24 (24 + 4 > 24 -> out of copied range!)
            0x0b,
        };
        var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &out_of_range_body };
        try f0.local_types.append(allocator, .i32);
        try mod.funcs.append(allocator, f0);
        try mod.exports.append(allocator, .{ .name = "oob", .kind = .func, .var_ = .{ .index = 0 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .small });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        try testing.expectEqual(@as(usize, 1), opt_mod.funcs.items[0].local_types.items.len);
        try testing.expectEqualSlices(u8, &out_of_range_body, opt_mod.funcs.items[0].code_bytes);
    }
}

test "Optimizer: caller dead stack-slot memory.copy load forwarding and frame stripping" {
    const allocator = testing.allocator;

    // 1. Dead stack copy at offset D=16 (`local.get fp; i32.const 16; i32.add; local.get src; i32.const 16; memory.copy`)
    //    followed by loads from `fp` at offsets 16 and 20: rewrites loads to `src` at offsets 0 and 4,
    //    deletes the `memory.copy`, and strips the now-unused stack frame prologue & epilogue!
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.globals.append(allocator, .{
            .type = .{ .val_type = .i32, .mutability = .mutable },
            .init_expr_bytes = &[_]u8{ 0x41, 0x80, 0x80, 0x04 },
        });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{.i32}),
            .results = try allocator.dupe(types.ValType, &.{.f32}),
        } });
        try mod.type_meta.append(allocator, .{});

        // Caller after inlining `Padding.left` + `Padding.right`:
        //   global.get 0; i32.const 32; i32.sub; local.tee 1; global.set 0;
        //   local.get 1; i32.const 16; i32.add; local.get 0; i32.const 16; memory.copy 0 0;
        //   local.get 1; f32.load align=2 offset=16;
        //   local.get 1; f32.load align=2 offset=20;
        //   f32.add;
        //   local.get 1; i32.const 32; i32.add; global.set 0;
        //   return; end
        const caller_body = [_]u8{
            0x23, 0x00, // global.get 0
            0x41, 32, // i32.const 32
            0x6b, // i32.sub
            0x22, 0x01, // local.tee 1 (fp)
            0x24, 0x00, // global.set 0
            0x20, 0x01, // local.get 1 (fp)
            0x41, 16, // i32.const 16 (D = 16)
            0x6a, // i32.add
            0x20, 0x00, // local.get 0 (src)
            0x41, 16, // i32.const 16 (N = 16)
            0xfc, 0x0a, 0x00, 0x00, // memory.copy 0 0
            0x20, 0x01, // local.get 1 (fp)
            0x2a, 0x02, 16, // f32.load align=2 offset=16
            0x20, 0x01, // local.get 1 (fp)
            0x2a, 0x02, 20, // f32.load align=2 offset=20
            0x92, // f32.add
            0x20, 0x01, // local.get 1 (fp)
            0x41, 32, // i32.const 32
            0x6a, // i32.add
            0x24, 0x00, // global.set 0
            0x0f, // return
            0x0b, // end
        };

        var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &caller_body };
        try f0.local_types.append(allocator, .i32); // local 1 (fp)
        try mod.funcs.append(allocator, f0);
        try mod.exports.append(allocator, .{ .name = "sumPadding", .kind = .func, .var_ = .{ .index = 0 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .small });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        // Both the `memory.copy` AND the stack frame prologue/epilogue + `fp` local are eliminated!
        try testing.expectEqual(@as(usize, 0), opt_mod.funcs.items[0].local_types.items.len);
        const expected = [_]u8{
            0x20, 0x00, // local.get 0
            0x2a, 0x02, 0x00, // f32.load align=2 offset=0
            0x20, 0x00, // local.get 0
            0x2a, 0x02, 0x04, // f32.load align=2 offset=4
            0x92, // f32.add
            0x0f, // return
            0x0b, // end
        };
        try testing.expectEqualSlices(u8, &expected, opt_mod.funcs.items[0].code_bytes);
    }

    // 2. When `fp` still has a disjoint store/load at `[0, 4)`, the dead `memory.copy` at `[16, 32)` is
    //    eliminated while the prologue/epilogue for `[0, 4)` are preserved:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.globals.append(allocator, .{
            .type = .{ .val_type = .i32, .mutability = .mutable },
            .init_expr_bytes = &[_]u8{ 0x41, 0x80, 0x80, 0x04 },
        });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        const caller_disjoint = [_]u8{
            0x23, 0x00, // global.get 0
            0x41, 32, // i32.const 32
            0x6b, // i32.sub
            0x22, 0x02, // local.tee 2 (fp)
            0x24, 0x00, // global.set 0
            0x20, 0x02, // local.get 2 (fp)
            0x20, 0x01, // local.get 1
            0x36, 0x02, 0x00, // i32.store align=2 offset=0 (disjoint slot [0, 4))
            0x20, 0x02, // local.get 2 (fp)
            0x41, 16, // i32.const 16
            0x6a, // i32.add
            0x20, 0x00, // local.get 0 (src)
            0x41, 16, // i32.const 16
            0xfc, 0x0a, 0x00, 0x00, // memory.copy 0 0
            0x20, 0x02, // local.get 2 (fp)
            0x28, 0x02, 20, // i32.load align=2 offset=20 (inside [16, 32))
            0x20, 0x02, // local.get 2 (fp)
            0x28, 0x02, 0x00, // i32.load align=2 offset=0 (disjoint slot [0, 4))
            0x6a, // i32.add
            0x20, 0x02, // local.get 2 (fp)
            0x41, 32, // i32.const 32
            0x6a, // i32.add
            0x24, 0x00, // global.set 0
            0x0f, // return
            0x0b, // end
        };

        var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &caller_disjoint };
        try f0.local_types.append(allocator, .i32);
        try mod.funcs.append(allocator, f0);
        try mod.exports.append(allocator, .{ .name = "disjointFrame", .kind = .func, .var_ = .{ .index = 0 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .small });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        const expected = [_]u8{
            0x23, 0x00, // global.get 0
            0x41, 32, // i32.const 32
            0x6b, // i32.sub
            0x22, 0x02, // local.tee 2 (fp)
            0x24, 0x00, // global.set 0
            0x20, 0x02, // local.get 2 (fp)
            0x20, 0x01, // local.get 1
            0x36, 0x02, 0x00, // i32.store align=2 offset=0
            0x20, 0x00, // local.get 0 (src — forwarded from fp+20!)
            0x28, 0x02, 0x04, // i32.load align=2 offset=4
            0x20, 0x02, // local.get 2 (fp)
            0x28, 0x02, 0x00, // i32.load align=2 offset=0
            0x6a, // i32.add
            0x20, 0x02, // local.get 2 (fp)
            0x41, 32, // i32.const 32
            0x6a, // i32.add
            0x24, 0x00, // global.set 0
            0x0f, // return
            0x0b, // end
        };
        try testing.expectEqualSlices(u8, &expected, opt_mod.funcs.items[0].code_bytes);
    }
}

test "Optimizer: 0xfc stack delta tracking, post-early-return cold calls, 2-result early return, and .small 12-op leaf cap" {
    const allocator = testing.allocator;

    // 1. `0xfc` stack delta tracking (`memory.copy` and `i32.trunc_sat_f32_s`) at depth 0 preserves
    //    `depth0_stack_exact` in a function with early return (`needs_result_block`):
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32, .f32 }),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        // Helper with early return AND depth-0 `memory.copy` (`0xfc 0x0a`, delta -3) + `i32.trunc_sat_f32_s` (`0xfc 0x00`, delta 0)
        const fc_helper = [_]u8{
            0x02, 0x40, // block (empty)
            0x20, 0x00, // local.get 0
            0x0d, 0x00, // br_if 0
            0x41, 0x00, // i32.const 0
            0x0f, // return (early return -> needs_result_block = true)
            0x0b, // end block
            0x20, 0x00, // local.get 0 (dst)
            0x20, 0x01, // local.get 1 (src)
            0x41, 0x08, // i32.const 8 (len)
            0xfc, 0x0a, 0x00, 0x00, // memory.copy 0 0 (depth 0: pops 3 -> depth0_stack remains 0!)
            0x20, 0x02, // local.get 2 (f32)
            0xfc, 0x00, // i32.trunc_sat_f32_s (depth 0: pops 1, pushes 1 -> depth0_stack == 1!)
            0x0f, // return
            0x0b, // end
        };
        const caller = [_]u8{
            0x20, 0x00,
            0x20, 0x01,
            0x20, 0x02,
            0x10, 0x00, // call $fc_helper
            0x0b,
        };

        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &fc_helper });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &caller });
        try mod.exports.append(allocator, .{ .name = "run_fc", .kind = .func, .var_ = .{ .index = 1 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        // `fc_helper` was classified as trivial (depth0_stack_exact preserved) and inlined into `run_fc`!
        try testing.expectEqual(@as(usize, 1), opt_mod.funcs.items.len);
    }

    // 2. `.fast` mode inlining of post-early-return depth-0 cold call (`ensureTotalCapacity` pattern)
    //    AND 2-result early-return cold-call wrapper (`ArrayList.addOne` pattern):
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        // Type 0: (param i32, i32) -> (result i32) (`ensureTotalCapacityPrecise` / `ensureTotalCapacity`)
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});
        // Type 1: (param i32) -> (result i32, i32) (`addOne`: returns `(ptr, err)`)
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{.i32}),
            .results = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
        } });
        try mod.type_meta.append(allocator, .{});

        // func 0 (imported `ensureTotalCapacityPrecise`):
        try mod.imports.append(allocator, .{
            .module_name = "env",
            .field_name = "ensureTotalCapacityPrecise",
            .kind = .func,
            .func = .{ .type_var = .{ .index = 0 } },
        });
        try mod.funcs.append(allocator, .{
            .is_import = true,
            .decl = .{ .type_var = .{ .index = 0 } },
        });
        mod.num_func_imports = 1;

        // func 1 (`ensureTotalCapacity` with post-early-return cold call at depth 0):
        //   block (empty) { local.get 0; i32.load offset=8; local.get 1; i32.lt_u; br_if 0; i32.const 0; return; }
        //   local.get 0; local.get 1; call $ensureTotalCapacityPrecise; return; end
        const ensure_total_cap = [_]u8{
            0x02, 0x40, // block (empty)
            0x20, 0x00, // local.get 0
            0x28, 0x02, 0x08, // i32.load align=2 offset=8 (cap)
            0x20, 0x01, // local.get 1 (new_cap)
            0x49, // i32.lt_u
            0x0d, 0x00, // br_if 0
            0x41, 0x00, // i32.const 0 (ok)
            0x0f, // return (early return at depth 1)
            0x0b, // end block
            0x20, 0x00, // local.get 0
            0x20, 0x01, // local.get 1
            0x10, 0x00, // call $ensureTotalCapacityPrecise (at depth 0 after has_early_return!)
            0x0f, // return
            0x0b, // end
        };

        // func 2 (`addOne` returning 2 results `(i32, i32)` with early return + cold call):
        //   local.get 0; local.get 0; i32.load offset=4; i32.const 1; i32.add; local.tee 1;
        //   block (empty) {
        //     local.get 0; i32.load offset=8; local.get 1; i32.ge_u; br_if 0;
        //     local.get 0; local.get 1; call $ensureTotalCapacityPrecise; local.tee 2;
        //     if (empty) { i32.const 0; local.get 2; return; }
        //   }
        //   local.get 0; local.get 1; i32.store offset=4;
        //   local.get 0; i32.load offset=0; i32.const 0; return; end
        const add_one = [_]u8{
            0x20, 0x00, // local.get 0
            0x28, 0x02, 0x04, // i32.load offset=4 (len)
            0x41, 0x01, // i32.const 1
            0x6a, // i32.add
            0x21, 0x01, // local.set 1 (new_len)
            0x02, 0x40, // block (empty)
            0x20, 0x00, // local.get 0
            0x28, 0x02, 0x08, // i32.load offset=8 (cap)
            0x20, 0x01, // local.get 1
            0x4f, // i32.ge_u
            0x0d, 0x00, // br_if 0
            0x20, 0x00, // local.get 0
            0x20, 0x01, // local.get 1
            0x10, 0x00, // call $ensureTotalCapacityPrecise
            0x22, 0x02, // local.tee 2 (err)
            0x04, 0x40, // if (empty)
            0x41, 0x00, // i32.const 0 (undef ptr)
            0x20, 0x02, // local.get 2 (err)
            0x0f, // return (2-result early return!)
            0x0b, // end if
            0x0b, // end block
            0x20, 0x00, // local.get 0
            0x20, 0x01, // local.get 1
            0x36, 0x02, 0x04, // i32.store offset=4
            0x20, 0x00, // local.get 0
            0x28, 0x02, 0x00, // i32.load offset=0 (ptr)
            0x41, 0x00, // i32.const 0 (ok err)
            0x0f, // return
            0x0b, // end
        };

        // func 3 (exported caller): calls both `ensureTotalCapacity` (func 1) and `addOne` (func 2)
        const caller = [_]u8{
            0x20, 0x00,
            0x41, 16,
            0x10, 0x01, // call $ensureTotalCapacity
            0x1a, // drop
            0x20,
            0x00,
            0x10, 0x02, // call $addOne
            0x0b,
        };

        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &ensure_total_cap });
        var f_add_one = Mod.Func{ .decl = .{ .type_var = .{ .index = 1 } }, .code_bytes = &add_one };
        try f_add_one.local_types.appendSlice(allocator, &.{ .i32, .i32 }); // locals 1, 2
        try mod.funcs.append(allocator, f_add_one);
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 1 } }, .code_bytes = &caller });
        try mod.exports.append(allocator, .{ .name = "caller", .kind = .func, .var_ = .{ .index = 3 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        // Both `ensureTotalCapacity` (func 1) and `addOne` (func 2) were inlined into `caller` and pruned,
        // leaving only import 0 (`ensureTotalCapacityPrecise`) and `caller` (func 1)!
        try testing.expectEqual(@as(usize, 2), opt_mod.funcs.items.len);
    }

    // 3. `.small` mode inlining of 1-local, 11–12 op (`<= 32B`) multi-caller leaf accessors
    //    (`ElementPool.get` = 2 params, 1 local, 11 ops, 27B; `hash_map.header` = 1 param, 1 local, 12 ops, 29B):
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        // Type 0: (param i32, i32) -> (result i32)
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});
        // Type 1: (param i32) -> (result i32)
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{.i32}),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        // func 0 (`ElementPool.get` pattern: 2 params, 1 local, 11 ops, 27 bytes, prefix_params < 2):
        const elem_pool_get = [_]u8{
            0x20, 0x00, // 1: local.get 0
            0x28, 0x02, 0x00, // 2: i32.load align=2 offset=0
            0x20, 0x01, // 3: local.get 1
            0x41, 24, // 4: i32.const 24
            0x6c, // 5: i32.mul
            0x22, 0x02, // 6: local.tee 2
            0x6a, // 7: i32.add
            0x28, 0x02, 0x04, // 8: i32.load align=2 offset=4
            0x20, 0x02, // 9: local.get 2
            0x6a, // 10: i32.add
            0x20, 0x00, // 11: local.get 0
            0x6a, // 12: i32.add
            0x0f, // return (stripped -> 12 ops, 26 bytes)
            0x0b, // end
        };

        // func 1 (`hash_map.header` pattern: 1 param, 1 local, 12 ops, 26 bytes, prefix_params == 0):
        const hm_header_valid = [_]u8{
            0x20, 0x00, // 1: local.get 0
            0x28, 0x02, 0x00, // 2: i32.load align=2 offset=0
            0x22, 0x01, // 3: local.tee 1
            0x41, 16, // 4: i32.const 16
            0x6b, // 5: i32.sub
            0x28, 0x02, 0x00, // 6: i32.load align=2 offset=0
            0x20, 0x01, // 7: local.get 1
            0x6a, // 8: i32.add
            0x20, 0x00, // 9: local.get 0
            0x28, 0x02, 0x04, // 10: i32.load align=2 offset=4
            0x6a, // 11: i32.add
            0x67, // 12: i32.clz (12 ops, 26 bytes <= 32B)
            0x0f, // return (stripped -> 12 ops)
            0x0b, // end
        };

        // func 2 (exported caller calling both func 0 and func 1 twice):
        const caller = [_]u8{
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x00, // call $elem_pool_get (1)
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x00, // call $elem_pool_get (2)
            0x6a, 0x20,
            0x00,
            0x10, 0x01, // call $hm_header_valid (1)
            0x6a, 0x20,
            0x00,
            0x10, 0x01, // call $hm_header_valid (2)
            0x6a, 0x0b,
        };

        var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &elem_pool_get };
        try f0.local_types.append(allocator, .i32);
        try mod.funcs.append(allocator, f0);
        var f1 = Mod.Func{ .decl = .{ .type_var = .{ .index = 1 } }, .code_bytes = &hm_header_valid };
        try f1.local_types.append(allocator, .i32);
        try mod.funcs.append(allocator, f1);
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &caller });
        try mod.exports.append(allocator, .{ .name = "small_12op", .kind = .func, .var_ = .{ .index = 2 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .small });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        // Both multi-caller 12-op 1-local helpers were inlined in .small mode and pruned!
        try testing.expectEqual(@as(usize, 1), opt_mod.funcs.items.len);
    }
}

test "Optimizer: 0xfd SIMD stack delta tracking and trivial function inlining" {
    const allocator = testing.allocator;

    // 1. Exhaustive verification that every `std.wasm.SimdOpcode` has a non-null delta in `depth0SimdStackDelta`:
    for (std.enums.values(std.wasm.SimdOpcode)) |op| {
        const delta = depth0SimdStackDelta(@backingInt(op));
        try testing.expect(delta != null);
    }
    // Unassigned opcodes in 0xfd space return null:
    try testing.expectEqual(@as(?i32, null), depth0SimdStackDelta(0x9a));
    try testing.expectEqual(@as(?i32, null), depth0SimdStackDelta(0xaf));
    try testing.expectEqual(@as(?i32, null), depth0SimdStackDelta(0x115));

    // 2. Inlining a SIMD helper with early return (`needs_result_block = true`), `v128.load`, `v128.const`,
    //    `f32x4.extract_lane`, `f32x4.replace_lane`, `f32x4.eq`, `i32x4.all_true`, and trailing `return`:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        // Type 0: (param i32, f32) -> (result i32)
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .f32 }),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        const simd_helper = [_]u8{
            0x02, 0x40, // block (empty)
            0x20, 0x00, // local.get 0 (ptr)
            0x0d, 0x00, // br_if 0
            0x41, 0x00, // i32.const 0
            0x0f, // return (early return -> needs_result_block = true)
            0x0b, // end block
            0x20, 0x00, // local.get 0 (ptr) -> stack: 1
            0xfd, 0x00, 0x04, 0x00, // v128.load align=4 offset=0 (delta 0) -> stack: 1
            0x20, 0x01, // local.get 1 (f32) -> stack: 2
            0xfd, 0x20, 0x01, // f32x4.replace_lane 1 (delta -1) -> stack: 1
            0xfd, 0x0c, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // v128.const 0 (delta +1) -> stack: 2
            0xfd, 0x1f, 0x00, // f32x4.extract_lane 0 (delta 0) -> stack: 2
            0xfd, 0x20, 0x02, // f32x4.replace_lane 2 (delta -1) -> stack: 1
            0xfd, 0x0c, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // v128.const 0 (delta +1) -> stack: 2
            0xfd, 0x41, // f32x4.eq (delta -1) -> stack: 1
            0xfd, 0xa3, 0x01, // i32x4.all_true (0xa3 LEB128, delta 0) -> stack: 1
            0x0f, // trailing return (stripped since depth0_stack_exact and depth0_stack == 1)
            0x0b, // end
        };
        const caller = [_]u8{
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x00, // call $simd_helper
            0x0b,
        };

        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &simd_helper });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &caller });
        try mod.exports.append(allocator, .{ .name = "run_simd", .kind = .func, .var_ = .{ .index = 1 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        // `simd_helper` was classified as trivial (depth0_stack_exact preserved) and inlined into `run_simd`!
        try testing.expectEqual(@as(usize, 1), opt_mod.funcs.items.len);
    }

    // 3. Multi-value return helper using `0xfd` SIMD instructions (`sig.results.len == 2`, requires `depth0_stack_exact`):
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        // Type 0: (param i32) -> (result f32, i32)
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{.i32}),
            .results = try allocator.dupe(types.ValType, &.{ .f32, .i32 }),
        } });
        try mod.type_meta.append(allocator, .{});

        const simd_pair_helper = [_]u8{
            0x20, 0x00, // local.get 0 -> stack: 1
            0xfd, 0x00, 0x04, 0x00, // v128.load (delta 0) -> stack: 1
            0x22, 0x01, // local.tee 1 (v128) -> stack: 1
            0xfd, 0x1f, 0x00, // f32x4.extract_lane 0 (delta 0) -> stack: 1 (first result: f32)
            0x20, 0x01, // local.get 1 (v128) -> stack: 2
            0xfd, 0xa3, 0x01, // i32x4.all_true (delta 0) -> stack: 2 (second result: i32)
            0x0f, // return
            0x0b, // end
        };
        const caller = [_]u8{
            0x20, 0x00,
            0x10, 0x00, // call $simd_pair_helper
            0x0b,
        };

        var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &simd_pair_helper };
        try f0.local_types.append(allocator, .v128);
        try mod.funcs.append(allocator, f0);
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &caller });
        try mod.exports.append(allocator, .{ .name = "run_simd_pair", .kind = .func, .var_ = .{ .index = 1 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .small });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        // `simd_pair_helper` was inlined and pruned in `.small` mode as well!
        try testing.expectEqual(@as(usize, 1), opt_mod.funcs.items.len);
    }
}

test "Optimizer: post-inlining shadow-stack slot scalarization (SROA) and derived pointer offset folding" {
    const allocator = testing.allocator;

    // 1. `DrawList.commandBounds` + `Box.add` at `fp + 0` inside a loop with `if (result f32)` and derived field pointers `+4, +8, +12`:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.globals.append(allocator, .{
            .type = .{ .val_type = .i32, .mutability = .mutable },
            .init_expr_bytes = &[_]u8{ 0x41, 0x80, 0x80, 0x04 },
        });
        // Type 0: `Box.add(self: i32, x: f32, y: f32) -> ()`
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .f32, .f32 }),
            .results = &.{},
        } });
        try mod.type_meta.append(allocator, .{});
        // Type 1: `commandBounds(pts_ptr: i32, count: i32) -> (result f32)`
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
            .results = try allocator.dupe(types.ValType, &.{.f32}),
        } });
        try mod.type_meta.append(allocator, .{});

        // func 0 (`Box.add`): locals: 3 = i32 (field_ptr), 4 = f32 (scratch)
        const box_add_code = [_]u8{
            // self.x0 = min(self.x0, x) via `if (result f32)`
            0x20, 0x00, // local.get 0 (self)
            0x2a, 0x02, 0x00, // f32.load align=2 offset=0
            0x22, 0x04, // local.tee 4
            0x20, 0x01, // local.get 1 (x)
            0x5e, // f32.gt
            0x04, 0x7d, // if (result f32)
            0x20, 0x01, // local.get 1
            0x05, // else
            0x20, 0x04, // local.get 4
            0x0b, // end if
            0x21, 0x04, // local.set 4
            0x20, 0x00, // local.get 0
            0x20, 0x04, // local.get 4
            0x38, 0x02, 0x00, // f32.store align=2 offset=0
            // self.y0 = min(self.y0, y) via derived field pointer `self + 4`
            0x20, 0x00, // local.get 0
            0x41, 0x04, // i32.const 4
            0x6a, // i32.add
            0x21, 0x03, // local.set 3 (self + 4)
            0x20, 0x00, // local.get 0
            0x2a, 0x02, 0x04, // f32.load align=2 offset=4
            0x22, 0x04, // local.tee 4
            0x20, 0x02, // local.get 2 (y)
            0x5e, // f32.gt
            0x04, 0x7d, // if (result f32)
            0x20, 0x02, // local.get 2
            0x05, // else
            0x20, 0x04, // local.get 4
            0x0b, // end if
            0x21, 0x04, // local.set 4
            0x20, 0x03, // local.get 3 (self + 4)
            0x20, 0x04, // local.get 4
            0x38, 0x02, 0x00, // f32.store align=2 offset=0
            // self.x1 = max(self.x1, x) via derived field pointer `self + 8`
            0x20, 0x00, // local.get 0
            0x41, 0x08, // i32.const 8
            0x6a, // i32.add
            0x21, 0x03, // local.set 3 (self + 8)
            0x20, 0x00, // local.get 0
            0x2a, 0x02, 0x08, // f32.load align=2 offset=8
            0x20, 0x01, // local.get 1 (x)
            0x97, // f32.max
            0x21, 0x04, // local.set 4
            0x20, 0x03, // local.get 3 (self + 8)
            0x20, 0x04, // local.get 4
            0x38, 0x02, 0x00, // f32.store align=2 offset=0
            // self.y1 = max(self.y1, y) via derived field pointer `self + 12`
            0x20, 0x00, // local.get 0
            0x41, 0x0c, // i32.const 12
            0x6a, // i32.add
            0x21, 0x03, // local.set 3 (self + 12)
            0x20, 0x00, // local.get 0
            0x2a, 0x02, 0x0c, // f32.load align=2 offset=12
            0x20, 0x02, // local.get 2 (y)
            0x97, // f32.max
            0x21, 0x04, // local.set 4
            0x20, 0x03, // local.get 3 (self + 12)
            0x20, 0x04, // local.get 4
            0x38, 0x02, 0x00, // f32.store align=2 offset=0
            0x0f, // return
            0x0b, // end
        };

        // func 1 (`commandBounds`): params 0=pts_ptr, 1=count; locals: 2=fp (i32), 3=idx (i32)
        const command_bounds_code = [_]u8{
            0x23, 0x00, // global.get 0
            0x41, 16, // i32.const 16
            0x6b, // i32.sub
            0x22, 0x02, // local.tee 2 (fp)
            0x24, 0x00, // global.set 0
            // box = .{ .x0 = inf, .y0 = inf, .x1 = -inf, .y1 = -inf }
            0x20, 0x02, // local.get 2 (fp)
            0x43, 0x00, 0x00, 0x80, 0x7f, // f32.const +inf
            0x38, 0x02, 0x00, // f32.store align=2 offset=0
            0x20, 0x02, // local.get 2 (fp)
            0x43, 0x00, 0x00, 0x80, 0x7f, // f32.const +inf
            0x38, 0x02, 0x04, // f32.store align=2 offset=4
            0x20, 0x02, // local.get 2 (fp)
            0x43, 0x00, 0x00, 0x80, 0xff, // f32.const -inf
            0x38, 0x02, 0x08, // f32.store align=2 offset=8
            0x20, 0x02, // local.get 2 (fp)
            0x43, 0x00, 0x00, 0x80, 0xff, // f32.const -inf
            0x38, 0x02, 0x0c, // f32.store align=2 offset=12
            // loop over points
            0x02, 0x40, // block (empty)
            0x03, 0x40, // loop (empty)
            0x20, 0x03, // local.get 3 (idx)
            0x20, 0x01, // local.get 1 (count)
            0x4f, // i32.ge_u
            0x0d, 0x01, // br_if 1
            0x20, 0x02, // local.get 2 (fp)
            0x20, 0x00, // local.get 0 (pts_ptr)
            0x2a, 0x02, 0x00, // f32.load offset=0 (x)
            0x20, 0x00, // local.get 0 (pts_ptr)
            0x2a, 0x02, 0x04, // f32.load offset=4 (y)
            0x10, 0x00, // call $Box_add
            0x20, 0x03, // local.get 3 (idx)
            0x41, 0x01, // i32.const 1
            0x6a, // i32.add
            0x21, 0x03, // local.set 3
            0x0c, 0x00, // br 0
            0x0b, // end loop
            0x0b, // end block
            // return (box.x1 - box.x0) + (box.y1 - box.y0)
            0x20, 0x02, // local.get 2 (fp)
            0x2a, 0x02, 0x08, // f32.load offset=8 (x1)
            0x20, 0x02, // local.get 2 (fp)
            0x2a, 0x02, 0x00, // f32.load offset=0 (x0)
            0x93, // f32.sub
            0x20, 0x02, // local.get 2 (fp)
            0x2a, 0x02, 0x0c, // f32.load offset=12 (y1)
            0x20, 0x02, // local.get 2 (fp)
            0x2a, 0x02, 0x04, // f32.load offset=4 (y0)
            0x93, // f32.sub
            0x92, // f32.add
            0x20, 0x02, // local.get 2 (fp)
            0x41, 16, // i32.const 16
            0x6a, // i32.add
            0x24, 0x00, // global.set 0
            0x0f, // return
            0x0b, // end
        };

        var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &box_add_code };
        try f0.local_types.appendSlice(allocator, &.{ .i32, .f32 });
        try mod.funcs.append(allocator, f0);

        var f1 = Mod.Func{ .decl = .{ .type_var = .{ .index = 1 } }, .code_bytes = &command_bounds_code };
        try f1.local_types.appendSlice(allocator, &.{ .i32, .i32 }); // fp, idx
        try mod.funcs.append(allocator, f1);
        try mod.exports.append(allocator, .{ .name = "commandBounds", .kind = .func, .var_ = .{ .index = 1 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        // `Box.add` was inlined and pruned!
        try testing.expectEqual(@as(usize, 1), opt_mod.funcs.items.len);
        const opt_fn = &opt_mod.funcs.items[0];

        // Parse instructions of the optimized `commandBounds` to verify:
        // - 0 `global.get 0` / `global.set 0` (shadow-stack prologue/epilogue completely stripped)
        // - 0 `f32.store` (all 4 Box fields promoted to locals)
        // - Only 2 `f32.load` (reading `pts_ptr` x and y; 0 stack loads!)
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        var parse_pos: usize = 0;
        var parsed: InstrList = .empty;
        _ = try parseInstrBlock(arena_state.allocator(), opt_fn.code_bytes, &parse_pos, false, &parsed);

        const Counts = struct {
            global_ops: usize = 0,
            f32_stores: usize = 0,
            f32_loads: usize = 0,
            fn scan(slice: []const Instr, self: *@This()) void {
                for (slice) |inst| {
                    switch (inst) {
                        .raw => |r| if (r.len > 0) switch (r[0]) {
                            0x23, 0x24 => self.global_ops += 1,
                            0x38 => self.f32_stores += 1,
                            0x2a => self.f32_loads += 1,
                            else => {},
                        },
                        .block => |b| scan(b.body.items, self),
                        .loop => |l| scan(l.body.items, self),
                        .if_ => |i| {
                            scan(i.then_body.items, self);
                            if (i.has_else) scan(i.else_body.items, self);
                        },
                        else => {},
                    }
                }
            }
        };
        var counts: Counts = .{};
        Counts.scan(parsed.items, &counts);
        try testing.expectEqual(@as(usize, 0), counts.global_ops);
        try testing.expectEqual(@as(usize, 0), counts.f32_stores);
        try testing.expectEqual(@as(usize, 2), counts.f32_loads);
    }

    // 2. Non-zero base offset `Box.add(fp + 16, x, y)` in a 32-byte shadow-stack frame (transitive derived pointers
    //    `$self = fp + 16` and `$field = $self + 4/8/12 -> fp + 20/24/28`):
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.globals.append(allocator, .{
            .type = .{ .val_type = .i32, .mutability = .mutable },
            .init_expr_bytes = &[_]u8{ 0x41, 0x80, 0x80, 0x04 },
        });
        // Type 0: `Box.add(self: i32, x: f32, y: f32) -> ()`
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .f32, .f32 }),
            .results = &.{},
        } });
        try mod.type_meta.append(allocator, .{});
        // Type 1: `caller(x: f32, y: f32) -> (result f32)`
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .f32, .f32 }),
            .results = try allocator.dupe(types.ValType, &.{.f32}),
        } });
        try mod.type_meta.append(allocator, .{});

        // func 0 (`Box.add` using `f32.min`/`f32.max` and derived field pointers `self + 4/8/12`):
        const box_add_simple = [_]u8{
            0x20, 0x00, // local.get 0 (self)
            0x20, 0x00, // local.get 0
            0x2a, 0x02, 0x00, // f32.load offset=0
            0x20, 0x01, // local.get 1 (x)
            0x96, // f32.min
            0x38, 0x02, 0x00, // f32.store offset=0
            // self + 4
            0x20, 0x00, 0x41,
            0x04, 0x6a,
            0x21, 0x03, // local.set 3 (self + 4)
            0x20, 0x03,
            0x20, 0x00,
            0x2a, 0x02,
            0x04, 0x20,
            0x02,
            0x96, // f32.min
            0x38,
            0x02,
            0x00,
            // self + 8
            0x20,
            0x00,
            0x41,
            0x08,
            0x6a,
            0x21, 0x04, // local.set 4 (self + 8)
            0x20, 0x04,
            0x20, 0x00,
            0x2a, 0x02,
            0x08, 0x20,
            0x01,
            0x97, // f32.max
            0x38,
            0x02,
            0x00,
            // self + 12
            0x20,
            0x00,
            0x41,
            0x0c,
            0x6a,
            0x21, 0x05, // local.set 5 (self + 12)
            0x20, 0x05,
            0x20, 0x00,
            0x2a, 0x02,
            0x0c, 0x20,
            0x02,
            0x97, // f32.max
            0x38,
            0x02,
            0x00,
            0x0f, // return
            0x0b, // end
        };

        // func 1 (`caller` with `box` at `fp + 16`):
        const caller_k16 = [_]u8{
            0x23, 0x00, // global.get 0
            0x41, 32, // i32.const 32
            0x6b, // i32.sub
            0x22, 0x02, // local.tee 2 (fp)
            0x24, 0x00, // global.set 0
            // init `box` at `fp + 16..28` (including a direct `fp + 16` add store!)
            0x20, 0x02, // local.get 2 (fp)
            0x41, 16, // i32.const 16
            0x6a, // i32.add
            0x43, 0x00, 0x00, 0x00, 0x00, // f32.const 0
            0x38, 0x02, 0x00, // f32.store offset=0 -> folded to fp offset=16
            0x20, 0x02, 0x43,
            0x00, 0x00, 0x00,
            0x00,
            0x38, 0x02, 20, // f32.store offset=20
            0x20, 0x02, 0x43,
            0x00, 0x00, 0x00,
            0x00,
            0x38, 0x02, 24, // f32.store offset=24
            0x20, 0x02, 0x43,
            0x00, 0x00, 0x00,
            0x00,
            0x38, 0x02, 28, // f32.store offset=28
            // call `Box.add(fp + 16, x, y)`
            0x20, 0x02, // local.get 2 (fp)
            0x41, 16, // i32.const 16
            0x6a, // i32.add
            0x20, 0x00, // local.get 0 (x)
            0x20, 0x01, // local.get 1 (y)
            0x10, 0x00, // call $Box_add
            // return `box.x0 + box.y1`
            0x20, 0x02, // local.get 2 (fp)
            0x41, 16, // i32.const 16
            0x6a, // i32.add
            0x2a, 0x02, 0x00, // f32.load offset=0 -> folded to fp offset=16
            0x20, 0x02,
            0x2a, 0x02, 28, // f32.load offset=28
            0x92, // f32.add
            0x20,
            0x02,
            0x41,
            32,
            0x6a,
            0x24, 0x00, // global.set 0
            0x0f, // return
            0x0b, // end
        };

        var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &box_add_simple };
        try f0.local_types.appendSlice(allocator, &.{ .i32, .i32, .i32 });
        try mod.funcs.append(allocator, f0);

        var f1 = Mod.Func{ .decl = .{ .type_var = .{ .index = 1 } }, .code_bytes = &caller_k16 };
        try f1.local_types.append(allocator, .i32); // local 2 (fp)
        try mod.funcs.append(allocator, f1);
        try mod.exports.append(allocator, .{ .name = "caller_k16", .kind = .func, .var_ = .{ .index = 1 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        try testing.expectEqual(@as(usize, 1), opt_mod.funcs.items.len);
        const opt_fn = &opt_mod.funcs.items[0];
        // Even more: after SROA + simplifyLocals, x0 and y1 are pure expressions of params x and y,
        // and y0/x1 stores become dead local stores and are completely eliminated!
        for (opt_fn.code_bytes) |b| {
            try testing.expect(b != 0x23 and b != 0x24 and b != 0x2a and b != 0x38);
        }
    }

    // 3. Mixed/type-punned slot `[0..4)` (`i32.store` + `f32.load`) is NOT promoted and preserves
    //    the shadow-stack frame, while disjoint consistent slot `[8..12)` (`f32.store` + 2 `f32.load`s)
    //    in the same frame IS promoted to a local:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.globals.append(allocator, .{
            .type = .{ .val_type = .i32, .mutability = .mutable },
            .init_expr_bytes = &[_]u8{ 0x41, 0x80, 0x80, 0x04 },
        });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .f32 }),
            .results = try allocator.dupe(types.ValType, &.{.f32}),
        } });
        try mod.type_meta.append(allocator, .{});

        const mixed_code = [_]u8{
            0x23, 0x00, // global.get 0
            0x41, 16, // i32.const 16
            0x6b, // i32.sub
            0x22, 0x02, // local.tee 2 (fp)
            0x24, 0x00, // global.set 0
            // Slot [0..4): i32.store followed by f32.load (type-punning / bitcast via memory -> not promotable)
            0x20, 0x02, // local.get 2 (fp)
            0x20, 0x00, // local.get 0 (i32 param)
            0x36, 0x02, 0x00, // i32.store offset=0
            // Slot [8..12): consistent f32 store + 2 f32 loads -> promoted!
            0x20, 0x02, // local.get 2 (fp)
            0x20, 0x01, // local.get 1 (f32 param)
            0x20, 0x01, // local.get 1
            0x92, // f32.add
            0x38, 0x02, 0x08, // f32.store offset=8
            // Load [0..4) as f32 + load [8..12) as f32 twice
            0x20, 0x02, // local.get 2 (fp)
            0x2a, 0x02, 0x00, // f32.load offset=0 (preserved!)
            0x20, 0x02, // local.get 2 (fp)
            0x2a, 0x02, 0x08, // f32.load offset=8 (promoted!)
            0x92, // f32.add
            0x20, 0x02, // local.get 2 (fp)
            0x2a, 0x02, 0x08, // f32.load offset=8 (promoted!)
            0x92, // f32.add
            // Epilogue (preserved because slot [0..4) still uses fp)
            0x20,
            0x02,
            0x41,
            16,
            0x6a,
            0x24, 0x00, // global.set 0
            0x0f, // return
            0x0b, // end
        };

        var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &mixed_code };
        try f0.local_types.append(allocator, .i32); // local 2 (fp)
        try mod.funcs.append(allocator, f0);
        try mod.exports.append(allocator, .{ .name = "mixed", .kind = .func, .var_ = .{ .index = 0 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        const opt_fn = &opt_mod.funcs.items[0];
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        var parse_pos: usize = 0;
        var parsed: InstrList = .empty;
        _ = try parseInstrBlock(arena_state.allocator(), opt_fn.code_bytes, &parse_pos, false, &parsed);

        var i32_stores: usize = 0;
        var f32_stores: usize = 0;
        var f32_loads: usize = 0;
        var global_ops: usize = 0;
        for (parsed.items) |inst| {
            if (inst == .raw and inst.raw.len > 0) {
                switch (inst.raw[0]) {
                    0x23, 0x24 => global_ops += 1,
                    0x36 => i32_stores += 1,
                    0x38 => f32_stores += 1,
                    0x2a => f32_loads += 1,
                    else => {},
                }
            }
        }
        try testing.expectEqual(@as(usize, 3), global_ops); // frame preserved for slot [0..4)
        try testing.expectEqual(@as(usize, 1), i32_stores); // slot [0..4) i32.store preserved
        try testing.expectEqual(@as(usize, 0), f32_stores); // slot [8..12) f32.store promoted!
        try testing.expectEqual(@as(usize, 1), f32_loads); // only slot [0..4) f32.load remains!
    }

    // 4. Edge cases: `.nop` before stacked `local.set`s is not misidentified as a 1-value expression,
    //    and non-inlined raw parameter `local.get 0; i32.const 4; i32.add; local.get 1; i32.store offset=0`
    //    is not folded into `memarg.offset` when `base != fp` and `derived_bases[0] == false`:
    {
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        // `.nop` pushes 0 values; `findPrevSingleValueExprStart` must return `null` rather than matching `.nop`:
        const nop_slice = [_]Instr{
            .{ .i32_const = 10 },
            .{ .i32_const = 20 },
            .nop,
        };
        try testing.expectEqual(@as(?usize, null), findPrevSingleValueExprStart(&nop_slice, nop_slice.len));

        var unstack_list: InstrList = .empty;
        try unstack_list.appendSlice(arena, &.{
            .{ .i32_const = 10 },
            .{ .i32_const = 20 },
            .nop,
            .{ .local_set = 3 },
            .{ .local_set = 2 },
        });
        try testing.expect(!(try unstackMultiParamLocalSets(arena, &unstack_list)));

        // Non-inlined `local.get 0; i32.const 4; i32.add; local.get 1; i32.store offset=0`:
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();
        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
            .results = &.{},
        } });
        try mod.type_meta.append(allocator, .{});

        const raw_store_code = [_]u8{
            0x20, 0x00, // local.get 0
            0x41, 0x04, // i32.const 4
            0x6a, // i32.add
            0x20, 0x01, // local.get 1
            0x36, 0x02, 0x00, // i32.store align=2 offset=0
            0x0b, // end
        };
        const f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &raw_store_code };
        try mod.funcs.append(allocator, f0);
        try mod.exports.append(allocator, .{ .name = "raw_store", .kind = .func, .var_ = .{ .index = 0 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        try testing.expectEqualSlices(u8, &raw_store_code, opt_mod.funcs.items[0].code_bytes);
    }
}

test "Optimizer: structured Wasm LICM (hoistLoopInvariantCode)" {
    const allocator = testing.allocator;

    // 1. Hoists multi-instruction pure expression (`(a << 4) + b`), proven-safe non-aliasing load (`*ptr`),
    //    and single-assignment `local.set` out of `.loop`:
    var mod = Mod.Module.init(allocator);
    defer mod.deinit();

    try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
    // Type 0: (param i32 ptr, i32 a, i32 b, i32 n) -> (result i32)
    try mod.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{ .i32, .i32, .i32, .i32 }),
        .results = try allocator.dupe(types.ValType, &.{.i32}),
    } });
    try mod.type_meta.append(allocator, .{});

    // locals: 4 = i (loop counter), 5 = acc, 6 = inv_single_set
    const loop_code = [_]u8{
        0x02, 0x40, // block
        0x03, 0x40, // loop
        // Single-assignment local.set 6 = a ^ b in loop entry prefix:
        0x20, 0x01, // local.get 1 (a)
        0x20, 0x02, // local.get 2 (b)
        0x73, // i32.xor
        0x21, 0x06, // local.set 6
        // Proven-safe invariant load from ptr offset=0 (loop only stores to ptr offset=8) + ((a << 4) + b):
        0x20, 0x05, // local.get 5 (acc)
        0x20, 0x00, // local.get 0 (ptr)
        0x28, 0x02, 0x00, // i32.load align=2 offset=0 (disjoint from store at offset=8)
        0x20, 0x01, // local.get 1 (a)
        0x41, 0x04, // i32.const 4
        0x74, // i32.shl
        0x20, 0x02, // local.get 2 (b)
        0x6a, // i32.add
        0x6a, // i32.add
        0x20, 0x06, // local.get 6
        0x6a, // i32.add
        0x21, 0x05, // local.set 5 (acc)
        // Store to ptr offset=8 (disjoint from [0..4)):
        0x20, 0x00, // local.get 0 (ptr)
        0x20, 0x05, // local.get 5 (acc)
        0x36, 0x02, 0x08, // i32.store align=2 offset=8
        // i += 1; br_if 0 (i < n)
        0x20, 0x04, // local.get 4 (i)
        0x41, 0x01, // i32.const 1
        0x6a, // i32.add
        0x22, 0x04, // local.tee 4
        0x20, 0x03, // local.get 3 (n)
        0x49, // i32.lt_u
        0x0d, 0x00, // br_if 0 (continue loop)
        0x0b, // end loop
        0x0b, // end block
        0x20, 0x05, // local.get 5 (acc)
        0x0b, // end
    };

    var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &loop_code };
    try f0.local_types.appendSlice(allocator, &.{ .i32, .i32, .i32 });
    try mod.funcs.append(allocator, f0);
    try mod.exports.append(allocator, .{ .name = "licm_loop", .kind = .func, .var_ = .{ .index = 0 } });

    const wasm = try writer.writeModule(allocator, &mod);
    defer allocator.free(wasm);
    const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
    defer allocator.free(opt);
    var opt_mod = try reader.readModule(allocator, opt);
    defer opt_mod.deinit();

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    var parse_pos: usize = 0;
    var parsed: InstrList = .empty;
    _ = try parseInstrBlock(arena_state.allocator(), opt_mod.funcs.items[0].code_bytes, &parse_pos, false, &parsed);

    // Find the `.loop` (either top-level after unused `.block` unwrapping or inside `.block`)
    // and verify `i32.load`, `i32.shl`, and `i32.xor` were hoisted out of `.loop`:
    var found_loop = false;
    for (parsed.items) |inst| {
        const maybe_lp_items: ?[]const Instr = switch (inst) {
            .loop => |lp| lp.body.items,
            .block => |b| blk: {
                for (b.body.items) |b_inst| {
                    if (b_inst == .loop) break :blk b_inst.loop.body.items;
                }
                break :blk null;
            },
            else => null,
        };
        if (maybe_lp_items) |lp_items| {
            found_loop = true;
            for (lp_items) |lp_inst| {
                if (lp_inst == .numeric_op) {
                    try testing.expect(lp_inst.numeric_op != 0x73); // i32.xor hoisted
                    try testing.expect(lp_inst.numeric_op != 0x74); // i32.shl hoisted
                }
                if (lp_inst == .raw and lp_inst.raw.len > 0) {
                    try testing.expect(lp_inst.raw[0] != 0x28); // i32.load hoisted
                }
            }
        }
    }
    try testing.expect(found_loop);

    // 2. Hoist loop-invariant `i64` `select` expression and verify scratch local has type `.i64`:
    {
        var mod2 = Mod.Module.init(allocator);
        defer mod2.deinit();

        // Type 0: (param i64 a, i64 b, i32 cond, i32 n) -> (result i64)
        try mod2.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i64, .i64, .i32, .i32 }),
            .results = try allocator.dupe(types.ValType, &.{.i64}),
        } });
        try mod2.type_meta.append(allocator, .{});

        // local 4 = i (i32), local 5 = acc (i64)
        const select_loop_code = [_]u8{
            0x03, 0x40, // loop (empty)
            0x20, 0x05, // local.get 5 (acc)
            // Loop-invariant i64 select: `select(a, b, cond)`
            0x20, 0x00, // local.get 0 (a: i64)
            0x20, 0x01, // local.get 1 (b: i64)
            0x20, 0x02, // local.get 2 (cond: i32)
            0x1b, // select (result is i64!)
            0x7c, // i64.add
            0x21, 0x05, // local.set 5 (acc)
            0x20, 0x04, // local.get 4 (i)
            0x41, 0x01, // i32.const 1
            0x6a, // i32.add
            0x22, 0x04, // local.tee 4 (i)
            0x20, 0x03, // local.get 3 (n)
            0x49, // i32.lt_u
            0x0d, 0x00, // br_if 0
            0x0b, // end loop
            0x20, 0x05, // local.get 5 (acc)
            0x0b, // end
        };

        var f_sel = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &select_loop_code };
        try f_sel.local_types.appendSlice(allocator, &.{ .i32, .i64 });
        try mod2.funcs.append(allocator, f_sel);
        try mod2.exports.append(allocator, .{ .name = "licm_i64_select", .kind = .func, .var_ = .{ .index = 0 } });

        const wasm2 = try writer.writeModule(allocator, &mod2);
        defer allocator.free(wasm2);
        const opt2 = try optimize(allocator, wasm2, .{ .optimize_mode = .fast });
        defer allocator.free(opt2);
        var opt_mod2 = try reader.readModule(allocator, opt2);
        defer opt_mod2.deinit();

        var arena2 = std.heap.ArenaAllocator.init(allocator);
        defer arena2.deinit();
        var pos2: usize = 0;
        var parsed2: InstrList = .empty;
        _ = try parseInstrBlock(arena2.allocator(), opt_mod2.funcs.items[0].code_bytes, &pos2, false, &parsed2);

        // Verify `select` (`0x1b`) was hoisted out of `.loop` and the new scratch local is `.i64`:
        var i64_locals: usize = 0;
        for (opt_mod2.funcs.items[0].local_types.items) |lt| {
            if (lt == .i64) i64_locals += 1;
        }
        try testing.expectEqual(@as(usize, 2), i64_locals); // `acc` + hoisted `select` scratch local
        for (parsed2.items) |inst| {
            if (inst == .loop) {
                for (inst.loop.body.items) |lp_inst| {
                    if (lp_inst == .raw and lp_inst.raw.len > 0) {
                        try testing.expect(lp_inst.raw[0] != 0x1b);
                    }
                }
            }
        }
    }
}

test "Optimizer: store-to-load forwarding, redundant-load elimination, narrow bit-slice extraction, and DSE" {
    const allocator = testing.allocator;

    // 1. Overwrite DSE, exact store-to-load forwarding, narrow load8_u bit-slice extraction,
    //    and cross-block load-to-load forwarding across a non-aliasing store:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        // Type 0: (param i32 ptr, i32 val, i32 cond) -> (result i32)
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32, .i32 }),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        // local 3 = loaded_v
        const mem_code = [_]u8{
            // Dead overwritten store at offset=0:
            0x20, 0x00, // local.get 0 (ptr)
            0x41, 0x01, // i32.const 1
            0x36, 0x02, 0x00, // i32.store offset=0 (DEAD: overwritten below!)
            // Live store at offset=0:
            0x20, 0x00, // local.get 0 (ptr)
            0x20, 0x01, // local.get 1 (val)
            0x36, 0x02, 0x00, // i32.store offset=0
            // Load from offset=4 and tee into local 3:
            0x20, 0x00, // local.get 0 (ptr)
            0x28, 0x02, 0x04, // i32.load offset=4
            0x22, 0x03, // local.tee 3
            // Non-overlapping store at offset=8 inside `if`:
            0x20, 0x02, // local.get 2 (cond)
            0x04, 0x40, // if (empty)
            0x20, 0x00, // local.get 0 (ptr)
            0x41, 0x2a, // i32.const 42
            0x36, 0x02, 0x08, // i32.store offset=8 (disjoint from offset=0 and offset=4!)
            0x0b, // end if
            // Redundant load from offset=4 (forwarded from local 3!)
            0x20, 0x00, // local.get 0 (ptr)
            0x28, 0x02, 0x04, // i32.load offset=4 -> local.get 3
            0x6a, // i32.add
            // Exact load from offset=0 (forwarded from local 1!)
            0x20, 0x00, // local.get 0 (ptr)
            0x28, 0x02, 0x00, // i32.load offset=0 -> local.get 1
            0x6a, // i32.add
            // Narrow load8_u at offset=2 within stored [0..4) (extracted via `(val >> 16) & 0xff`!)
            0x20, 0x00, // local.get 0 (ptr)
            0x2d, 0x00, 0x02, // i32.load8_u offset=2 -> (local.get 1 >> 16) & 255
            0x6a, // i32.add
            0x0b, // end
        };

        var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &mem_code };
        try f0.local_types.append(allocator, .i32); // local 3
        try mod.funcs.append(allocator, f0);
        try mod.exports.append(allocator, .{ .name = "mem_forward", .kind = .func, .var_ = .{ .index = 0 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        var parse_pos: usize = 0;
        var parsed: InstrList = .empty;
        _ = try parseInstrBlock(arena_state.allocator(), opt_mod.funcs.items[0].code_bytes, &parse_pos, false, &parsed);

        var top_stores: usize = 0;
        var top_i32_loads: usize = 0;
        var top_i32_load8_u: usize = 0;
        for (parsed.items) |inst| {
            if (inst == .raw and inst.raw.len > 0) {
                switch (inst.raw[0]) {
                    0x36 => top_stores += 1,
                    0x28 => top_i32_loads += 1,
                    0x2d => top_i32_load8_u += 1,
                    else => {},
                }
            }
        }
        // Only 1 top-level store remains (the overwritten store at offset=0 was eliminated by DSE),
        // only 1 `i32.load` remains (the initial load at offset=4; the second offset=4 load and offset=0 load were forwarded),
        // and 0 `i32.load8_u` remain (extracted via bit shift + mask)!
        try testing.expectEqual(@as(usize, 1), top_stores);
        try testing.expectEqual(@as(usize, 1), top_i32_loads);
        try testing.expectEqual(@as(usize, 0), top_i32_load8_u);
    }

    // 2. Dead Frame Epilogue DSE eliminates unread stores to `fp` and strips the dead shadow-stack frame:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.globals.append(allocator, .{
            .type = .{ .val_type = .i32, .mutability = .mutable },
            .init_expr_bytes = &[_]u8{ 0x41, 0x80, 0x80, 0x04 },
        });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{.i32}),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        const dead_frame_code = [_]u8{
            0x23, 0x00, // global.get 0
            0x41, 16, // i32.const 16
            0x6b, // i32.sub
            0x22, 0x01, // local.tee 1 (fp)
            0x24, 0x00, // global.set 0
            0x20, 0x01, // local.get 1 (fp)
            0x20, 0x00, // local.get 0 (x)
            0x36, 0x02, 0x00, // i32.store offset=0 (never read before epilogue!)
            0x20, 0x00, // local.get 0 (x)
            0x20, 0x01, // local.get 1 (fp)
            0x41, 16, // i32.const 16
            0x6a, // i32.add
            0x24, 0x00, // global.set 0
            0x0b, // end
        };

        var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &dead_frame_code };
        try f0.local_types.append(allocator, .i32); // local 1 (fp)
        try mod.funcs.append(allocator, f0);
        try mod.exports.append(allocator, .{ .name = "dead_epilogue_dse", .kind = .func, .var_ = .{ .index = 0 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .small });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        const expected = [_]u8{
            0x20, 0x00, // local.get 0
            0x0b, // end
        };
        try testing.expectEqualSlices(u8, &expected, opt_mod.funcs.items[0].code_bytes);
    }

    // 3. Storing `fp + 16` into `[fp + 0]` escapes `fp` into memory; store to `[fp + 16]` must NOT be eliminated:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.globals.append(allocator, .{
            .type = .{ .val_type = .i32, .mutability = .mutable },
            .init_expr_bytes = &[_]u8{ 0x41, 0x80, 0x80, 0x04 },
        });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{.i32}),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        const escaped_fp_store_code = [_]u8{
            0x23, 0x00, // global.get 0
            0x41, 32, // i32.const 32
            0x6b, // i32.sub
            0x22, 0x01, // local.tee 1 (fp)
            0x24, 0x00, // global.set 0
            // Store `fp + 16` as a pointer value into `[fp + 0]`:
            0x20, 0x01, // local.get 1 (fp)
            0x20, 0x01, // local.get 1 (fp)
            0x41, 16, // i32.const 16
            0x6a, // i32.add
            0x36, 0x02, 0x00, // i32.store offset=0
            // Store `x` into `[fp + 16]`:
            0x20, 0x01, // local.get 1 (fp)
            0x20, 0x00, // local.get 0 (x)
            0x36, 0x02, 16, // i32.store offset=16 (LIVE: read indirectly via `[fp + 0]` below!)
            // Load pointer `p = [fp + 0]` and dereference `[p + 0]`:
            0x20, 0x01, // local.get 1 (fp)
            0x28, 0x02, 0x00, // i32.load offset=0
            0x28, 0x02, 0x00, // i32.load offset=0
            // Epilogue:
            0x20, 0x01, // local.get 1 (fp)
            0x41, 32, // i32.const 32
            0x6a, // i32.add
            0x24, 0x00, // global.set 0
            0x0b, // end
        };

        var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &escaped_fp_store_code };
        try f0.local_types.append(allocator, .i32); // local 1 (fp)
        try mod.funcs.append(allocator, f0);
        try mod.exports.append(allocator, .{ .name = "escaped_fp_val", .kind = .func, .var_ = .{ .index = 0 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        var parse_pos: usize = 0;
        var parsed: InstrList = .empty;
        _ = try parseInstrBlock(arena_state.allocator(), opt_mod.funcs.items[0].code_bytes, &parse_pos, false, &parsed);

        var stores_to_16: usize = 0;
        for (parsed.items) |inst| {
            if (decodeStoreAccess(inst)) |acc| {
                if (acc.offset == 16) stores_to_16 += 1;
            }
        }
        try testing.expectEqual(@as(usize, 1), stores_to_16);
    }
}

test "Optimizer: post-link arithmetic strength reduction, possibleOnes mask stripping, and peepholes" {
    const allocator = testing.allocator;

    // 1. Verify `magicU32` and `magicS32` exactness across divisors and sample dividends:
    {
        const divisors = [_]u32{ 3, 5, 6, 7, 9, 10, 11, 12, 13, 25, 100, 1000 };
        const u_samples = [_]u32{ 0, 1, 2, 3, 7, 9, 10, 11, 99, 100, 101, 12345678, 0x7fff_ffff, 0x8000_0000, 0xffff_fffe, 0xffff_ffff };
        for (divisors) |d| {
            const mu = magicU32(d);
            for (u_samples) |n| {
                const q: u32 = if (!mu.add)
                    @truncate((@as(u64, n) * mu.mul) >> @intCast(32 + @as(u32, mu.shift)))
                else
                    @truncate((((@as(u64, n) * mu.mul) >> 32) + @as(u64, n)) >> @intCast(mu.shift));
                try testing.expectEqual(n / d, q);
            }

            const sd: i32 = @intCast(d);
            const ms = magicS32(d);
            const s_samples = [_]i32{ -2147483648, -2147483647, -12345678, -101, -100, -99, -11, -10, -9, -1, 0, 1, 9, 10, 11, 99, 100, 101, 12345678, 2147483647 };
            for (s_samples) |sn| {
                const prod: i64 = @as(i64, sn) * ms.mul;
                const sq: i32 = @as(i32, @truncate(prod >> ms.shift)) +% @as(i32, @intCast(@as(u32, @bitCast(sn)) >> 31));
                try testing.expectEqual(@divTrunc(sn, sd), sq);
            }
        }
    }

    // 2. `.fast` mode `mul` by 2^k +- 1 and `div_u`/`rem_u`/`div_s`/`rem_s` by constant:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        const fast_arith_code = [_]u8{
            // (p0 * 9) + (p0 /u 10) + (p1 %s 10)
            0x20, 0x00, // local.get 0
            0x41, 0x09, // i32.const 9 (2^3 + 1)
            0x6c, // i32.mul -> (p0 << 3) + p0
            0x20, 0x00, // local.get 0
            0x41, 0x0a, // i32.const 10
            0x6e, // i32.div_u -> 64-bit magic mul
            0x6a, // i32.add
            0x20, 0x01, // local.get 1
            0x41, 0x0a, // i32.const 10
            0x6f, // i32.rem_s -> 64-bit magic mul + sub
            0x6a, // i32.add
            0x0b, // end
        };

        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &fast_arith_code });
        try mod.exports.append(allocator, .{ .name = "fast_arith", .kind = .func, .var_ = .{ .index = 0 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        var parse_pos: usize = 0;
        var parsed: InstrList = .empty;
        _ = try parseInstrBlock(arena_state.allocator(), opt_mod.funcs.items[0].code_bytes, &parse_pos, false, &parsed);

        for (parsed.items) |inst| {
            if (inst == .numeric_op) {
                try testing.expect(inst.numeric_op != 0x6e); // i32.div_u eliminated
                try testing.expect(inst.numeric_op != 0x6f); // i32.rem_s eliminated
            }
        }
    }

    // 3. `possibleOnes` mask stripping, `wrap(extend)`, `extend8_s(load8_u)`, `eqz(xor)`, `select(..., eqz)`,
    //    float `abs`/`neg` idempotents, and same-local identities:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();
        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32, .f32 }),
            .results = try allocator.dupe(types.ValType, &.{ .i32, .f32 }),
        } });
        try mod.type_meta.append(allocator, .{});

        const peephole_code = [_]u8{
            // 1) `i32.extend8_s(i32.load8_u)` -> `i32.load8_s`
            0x20, 0x00, // local.get 0
            0x2d, 0x00, 0x00, // i32.load8_u offset=0
            0xc0, // i32.extend8_s -> fused into 0x2c i32.load8_s!
            // 2) `((p1 >>u 24) & 0xff)` -> redundant mask stripped!
            0x20, 0x01, // local.get 1
            0x41, 24, // i32.const 24
            0x76, // i32.shr_u (possibleOnes = 0xff)
            0x41, 0xff, 0x01, // i32.const 255
            0x71, // i32.and (stripped!)
            0x6a, // i32.add
            // 3) `i32.wrap_i64(i64.extend_i32_u(p0))` -> `p0`
            0x20, 0x00, // local.get 0
            0xad, // i64.extend_i32_u
            0xa7, // i32.wrap_i64
            0x6a, // i32.add
            // 4) `select(p0, p1, i32.eqz(i32.xor(p0, p1)))` -> `select(p1, p0, i32.eq(p0, p1))`
            0x20, 0x00, // local.get 0
            0x20, 0x01, // local.get 1
            0x20, 0x00, // local.get 0
            0x20, 0x01, // local.get 1
            0x73, // i32.xor
            0x45, // i32.eqz -> folded with xor to i32.eq!
            0x1b, // select
            0x6a, // i32.add
            // 5) `f32.abs(f32.neg(f32.neg(f2)))` -> `f32.abs(f2)`
            0x20, 0x02, // local.get 2 (f32)
            0x8c, // f32.neg
            0x8c, // f32.neg (elided!)
            0x8b, // f32.abs
            0x0b, // end
        };

        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &peephole_code });
        try mod.exports.append(allocator, .{ .name = "peepholes", .kind = .func, .var_ = .{ .index = 0 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .small });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        const expected = [_]u8{
            0x20, 0x00, // local.get 0
            0x2c, 0x00, 0x00, // i32.load8_s offset=0
            0x20, 0x01, // local.get 1
            0x41, 24, // i32.const 24
            0x76, // i32.shr_u
            0x6a, // i32.add
            0x20, 0x00, // local.get 0
            0x6a, // i32.add
            0x20, 0x00, // local.get 0
            0x20, 0x01, // local.get 1
            0x20, 0x00, // local.get 0
            0x20, 0x01, // local.get 1
            0x46, // i32.eq
            0x1b, // select
            0x6a, // i32.add
            0x20, 0x02, // local.get 2
            0x8b, // f32.abs
            0x0b, // end
        };
        try testing.expectEqualSlices(u8, &expected, opt_mod.funcs.items[0].code_bytes);
    }
}

test "Optimizer: 2-pass bottom-up inlining, unconditional 1-call wrapper inlining, and partial-frame SROA" {
    const allocator = testing.allocator;

    // 1. 2-pass bottom-up inlining of unconditional 1-call wrapper chain (`caller -> scissorEql -> rectEql`):
    //    `scissorEql` compares `(a ^ b)` and then unconditionally calls `rectEql(a, b)` and combines with `i32.or`.
    //    Pass 1 inlines leaf `rectEql` into `scissorEql`, turning `scissorEql` into a leaf, and Pass 2 inlines
    //    `scissorEql` into `caller`, pruning both helpers!
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        // func 0 (`rectEql`): leaf comparing `[a + 0] == [b + 0]`
        const rect_eql = [_]u8{
            0x20, 0x00, // local.get 0 (a)
            0x28, 0x02, 0x00, // i32.load offset=0
            0x20, 0x01, // local.get 1 (b)
            0x28, 0x02, 0x00, // i32.load offset=0
            0x46, // i32.eq
            0x0b, // end
        };

        // func 1 (`scissorEql`): unconditional 1-call wrapper calling `rectEql`
        const scissor_eql = [_]u8{
            0x20, 0x00, // local.get 0 (a)
            0x28, 0x02, 0x04, // i32.load offset=4
            0x20, 0x01, // local.get 1 (b)
            0x28, 0x02, 0x04, // i32.load offset=4
            0x46, // i32.eq
            0x20, 0x00, // local.get 0 (a)
            0x20, 0x01, // local.get 1 (b)
            0x10, 0x00, // call $rectEql (unconditional depth-0 call!)
            0x71, // i32.and
            0x0b, // end
        };

        // func 2 (`caller`): calls `scissorEql` twice
        const caller = [_]u8{
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x01, // call $scissorEql
            0x20, 0x01,
            0x20, 0x00,
            0x10, 0x01, // call $scissorEql
            0x72, // i32.or
            0x0b,
        };

        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &rect_eql });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &scissor_eql });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &caller });
        try mod.exports.append(allocator, .{ .name = "caller", .kind = .func, .var_ = .{ .index = 2 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        // Both `rectEql` and `scissorEql` were inlined across the 2 passes and pruned!
        try testing.expectEqual(@as(usize, 1), opt_mod.funcs.items.len);
    }

    // 2. Partial-frame per-slot shadow-stack scalarization when `[fp + 16]` has overlapping mixed-type
    //    accesses (`i64.store` + `i32.load`) while `[fp + 0]` is a clean scalar `i32` slot:
    //    Slot `[fp + 0]` is promoted to a local while keeping the stack frame for `[fp + 16]`.
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.globals.append(allocator, .{
            .type = .{ .val_type = .i32, .mutability = .mutable },
            .init_expr_bytes = &[_]u8{ 0x41, 0x80, 0x80, 0x04 },
        });
        // Type 0: (param i32, i64) -> (result i32)
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i64 }),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        const partial_frame_code = [_]u8{
            0x23, 0x00, // global.get 0
            0x41, 32, // i32.const 32
            0x6b, // i32.sub
            0x22, 0x02, // local.tee 2 (fp)
            0x24, 0x00, // global.set 0
            // Clean scalar slot at `fp + 0`:
            0x20, 0x02, // local.get 2 (fp)
            0x20, 0x00, // local.get 0 (p0: i32)
            0x41, 0x07, // i32.const 7
            0x6a, // i32.add
            0x36, 0x02, 0x00, // i32.store offset=0
            // Non-promotable overlapping mixed-type slot at `fp + 16` (`i64.store` + `i32.load` at offset=20):
            0x20, 0x02, // local.get 2 (fp)
            0x20, 0x01, // local.get 1 (p1: i64)
            0x37, 0x03, 16, // i64.store offset=16
            0x20, 0x02, // local.get 2 (fp)
            0x28, 0x02, 20, // i32.load offset=20 (overlaps [16..24))
            // Read clean scalar slot `fp + 0` twice:
            0x20, 0x02, // local.get 2 (fp)
            0x28, 0x02, 0x00, // i32.load offset=0
            0x6a, // i32.add
            0x20, 0x02, // local.get 2 (fp)
            0x28, 0x02, 0x00, // i32.load offset=0
            0x6a, // i32.add
            // Epilogue:
            0x20, 0x02, // local.get 2 (fp)
            0x41, 32, // i32.const 32
            0x6a, // i32.add
            0x24, 0x00, // global.set 0
            0x0b, // end
        };

        var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &partial_frame_code };
        try f0.local_types.append(allocator, .i32); // local 2 (fp)
        try mod.funcs.append(allocator, f0);
        try mod.exports.append(allocator, .{ .name = "partial_sroa", .kind = .func, .var_ = .{ .index = 0 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        var parse_pos: usize = 0;
        var parsed: InstrList = .empty;
        _ = try parseInstrBlock(arena_state.allocator(), opt_mod.funcs.items[0].code_bytes, &parse_pos, false, &parsed);

        var stores_at_0: usize = 0;
        var loads_at_0: usize = 0;
        for (parsed.items) |inst| {
            if (decodeStoreAccess(inst)) |acc| {
                if (acc.offset == 0) stores_at_0 += 1;
            }
            if (decodeLoadAccess(inst)) |acc| {
                if (acc.offset == 0) loads_at_0 += 1;
            }
        }
        // Clean scalar slot `fp + 0` was promoted to a local (0 stores/loads at offset 0)!
        try testing.expectEqual(@as(usize, 0), stores_at_0);
        try testing.expectEqual(@as(usize, 0), loads_at_0);
    }

    // 3. `@fieldParentPtr` safety: when `fp + 16` escapes to an opaque `call`, `[fp + 0]` is NOT promoted
    //    because the callee could compute `@fieldParentPtr` (`(fp + 16) - 16`) to access `[fp + 0]`:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.globals.append(allocator, .{
            .type = .{ .val_type = .i32, .mutability = .mutable },
            .init_expr_bytes = &[_]u8{ 0x41, 0x80, 0x80, 0x04 },
        });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{.i32}),
            .results = &.{},
        } });
        try mod.type_meta.append(allocator, .{});
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{.i32}),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        try mod.imports.append(allocator, .{
            .module_name = "env",
            .field_name = "use_field_ptr",
            .kind = .func,
            .func = .{ .type_var = .{ .index = 0 } },
        });
        try mod.funcs.append(allocator, .{
            .is_import = true,
            .decl = .{ .type_var = .{ .index = 0 } },
        });
        mod.num_func_imports = 1;

        const escaped_call_code = [_]u8{
            0x23, 0x00, // global.get 0
            0x41, 32, // i32.const 32
            0x6b, // i32.sub
            0x22, 0x01, // local.tee 1 (fp)
            0x24, 0x00, // global.set 0
            0x20, 0x01, // local.get 1 (fp)
            0x20, 0x00, // local.get 0 (param)
            0x36, 0x02, 0x00, // i32.store offset=0
            0x20, 0x01, // local.get 1 (fp)
            0x41, 16, // i32.const 16
            0x6a, // i32.add
            0x10, 0x00, // call $use_field_ptr (could subtract 16 via @fieldParentPtr!)
            0x20, 0x01, // local.get 1 (fp)
            0x28, 0x02, 0x00, // i32.load offset=0
            0x20, 0x01, // local.get 1 (fp)
            0x41, 32, // i32.const 32
            0x6a, // i32.add
            0x24, 0x00, // global.set 0
            0x0b, // end
        };

        var f1 = Mod.Func{ .decl = .{ .type_var = .{ .index = 1 } }, .code_bytes = &escaped_call_code };
        try f1.local_types.append(allocator, .i32); // local 1 (fp)
        try mod.funcs.append(allocator, f1);
        try mod.exports.append(allocator, .{ .name = "field_parent_ptr_safe", .kind = .func, .var_ = .{ .index = 1 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        var parse_pos: usize = 0;
        var parsed: InstrList = .empty;
        _ = try parseInstrBlock(arena_state.allocator(), opt_mod.funcs.items[1].code_bytes, &parse_pos, false, &parsed);

        var i32_stores: usize = 0;
        var i32_loads: usize = 0;
        for (parsed.items) |inst| {
            if (inst == .raw and inst.raw.len > 0) {
                if (inst.raw[0] == 0x36) i32_stores += 1;
                if (inst.raw[0] == 0x28) i32_loads += 1;
            }
        }
        // Both store and load at `[fp + 0]` remain in memory because `fp + 16` escaped to `use_field_ptr`!
        try testing.expectEqual(@as(usize, 1), i32_stores);
        try testing.expectEqual(@as(usize, 1), i32_loads);
    }
}

test "Optimizer: .fast mode 8-param 4-result inlining and 2-call wrapper inlining" {
    const allocator = testing.allocator;

    // 1. 8-parameter, 4-result function with early return (`needs_result_block = true`) is inlined
    //    in `.fast` mode (and pruned), while remaining out-of-line in `.small` mode (`max_params = 6`, `max_results = 2`):
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        // Type 0: 8 i32 params -> 4 i32 results
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32, .i32, .i32, .i32, .i32, .i32, .i32 }),
            .results = try allocator.dupe(types.ValType, &.{ .i32, .i32, .i32, .i32 }),
        } });
        try mod.type_meta.append(allocator, .{});
        // Type 1: 8 i32 params -> 1 i32 result (caller)
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32, .i32, .i32, .i32, .i32, .i32, .i32 }),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        // func 0 (`lerp4_early`): if (p0 == 0) return (p4, p5, p6, p7); return (p0+p4, p1+p5, p2+p6, p3+p7)
        const lerp4_early = [_]u8{
            0x20, 0x00, // local.get 0
            0x45, // i32.eqz
            0x04, 0x40, // if (empty)
            0x20, 0x04, // local.get 4
            0x20, 0x05, // local.get 5
            0x20, 0x06, // local.get 6
            0x20, 0x07, // local.get 7
            0x0f, // return (4-result early return!)
            0x0b, // end if
            0x20, 0x00, // local.get 0
            0x20, 0x04, // local.get 4
            0x6a, // i32.add
            0x20, 0x01, // local.get 1
            0x20, 0x05, // local.get 5
            0x6a, // i32.add
            0x20, 0x02, // local.get 2
            0x20, 0x06, // local.get 6
            0x6a, // i32.add
            0x20, 0x03, // local.get 3
            0x20, 0x07, // local.get 7
            0x6a, // i32.add
            0x0f, // return
            0x0b, // end
        };

        // func 1 (`caller`): calls `lerp4_early` twice and sums the 4 results each time
        const caller_code = [_]u8{
            0x20, 0x00, 0x20, 0x01, 0x20, 0x02, 0x20, 0x03,
            0x20, 0x04, 0x20, 0x05, 0x20, 0x06, 0x20, 0x07,
            0x10, 0x00, // call $lerp4_early (1)
            0x6a, 0x6a, 0x6a, // sum 4 results
            0x20, 0x07, 0x20, 0x06, 0x20, 0x05, 0x20, 0x04,
            0x20, 0x03, 0x20, 0x02, 0x20, 0x01, 0x20, 0x00,
            0x10, 0x00, // call $lerp4_early (2)
            0x6a, 0x6a, 0x6a, // sum 4 results
            0x6a, // combine
            0x0b,
        };

        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &lerp4_early });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 1 } }, .code_bytes = &caller_code });
        try mod.exports.append(allocator, .{ .name = "run_lerp4", .kind = .func, .var_ = .{ .index = 1 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);

        // In `.small` mode, `lerp4_early` (8 params, 4 results) is NOT inlined:
        const opt_small = try optimize(allocator, wasm, .{ .optimize_mode = .small });
        defer allocator.free(opt_small);
        var mod_small = try reader.readModule(allocator, opt_small);
        defer mod_small.deinit();
        try testing.expectEqual(@as(usize, 2), mod_small.funcs.items.len);

        // In `.fast` mode, `lerp4_early` IS inlined at both call sites and pruned!
        const opt_fast = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt_fast);
        var mod_fast = try reader.readModule(allocator, opt_fast);
        defer mod_fast.deinit();
        try testing.expectEqual(@as(usize, 1), mod_fast.funcs.items.len);
    }

    // 2. 2-call wrapper function (`inner_calls_count == 2`) calling two non-trivial internal functions
    //    is inlined into its multi-caller in `.fast` mode, while remaining out-of-line in `.small` mode:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        // func 0: imported function `imp`
        try mod.imports.append(allocator, .{
            .module_name = "env",
            .field_name = "imp",
            .kind = .func,
            .func = .{ .type_var = .{ .index = 0 } },
        });
        try mod.funcs.append(allocator, .{
            .is_import = true,
            .decl = .{ .type_var = .{ .index = 0 } },
        });
        mod.num_func_imports = 1;

        // func 1 & func 2: non-trivial internal functions (unconditional call to import 0)
        const callee_a = [_]u8{
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x00, // call $imp (unconditional call to import -> not inlined)
            0x41, 0x01,
            0x6a,
            0x0b,
        };
        const callee_b = [_]u8{
            0x20, 0x01,
            0x20, 0x00,
            0x10, 0x00, // call $imp (unconditional call to import -> not inlined)
            0x41, 0x02,
            0x6a,
            0x0b,
        };

        // func 3 (`two_call_wrapper`): makes 2 direct calls (`call 1` and `call 2`) and combines results
        const two_call_wrapper = [_]u8{
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x01, // call $callee_a (inner call 1)
            0x20, 0x01,
            0x20, 0x00,
            0x10, 0x02, // call $callee_b (inner call 2)
            0x6a, // i32.add
            0x0f, // return
            0x0b, // end
        };

        // func 4 (exported caller): calls `two_call_wrapper` twice, and also references 1 & 2 so they are multi-caller
        const caller_code = [_]u8{
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x03, // call $two_call_wrapper (1)
            0x20, 0x01,
            0x20, 0x00,
            0x10, 0x03, // call $two_call_wrapper (2)
            0x6a,
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x01, // extra call to 1
            0x6a,
            0x20, 0x00,
            0x20, 0x01,
            0x10, 0x02, // extra call to 2
            0x6a,
            0x0b,
        };

        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &callee_a });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &callee_b });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &two_call_wrapper });
        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &caller_code });
        try mod.exports.append(allocator, .{ .name = "run_2call", .kind = .func, .var_ = .{ .index = 4 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);

        // In `.small` mode, `two_call_wrapper` is NOT inlined (all 5 funcs remain):
        const opt_small = try optimize(allocator, wasm, .{ .optimize_mode = .small });
        defer allocator.free(opt_small);
        var mod_small = try reader.readModule(allocator, opt_small);
        defer mod_small.deinit();
        try testing.expectEqual(@as(usize, 5), mod_small.funcs.items.len);

        // In `.fast` mode, `two_call_wrapper` IS inlined at both sites and pruned (4 funcs remain):
        const opt_fast = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt_fast);
        var mod_fast = try reader.readModule(allocator, opt_fast);
        defer mod_fast.deinit();
        try testing.expectEqual(@as(usize, 4), mod_fast.funcs.items.len);
    }
}

test "Optimizer: contiguous constant scalar store coalescing and trailing self-offset store folding" {
    const allocator = testing.allocator;

    // 1. Coalesce 4 `f32.const` stores (`0..16`) into `v128.store`, fold trailing `dst += 72; store(dst, 0)`
    //    into `store(dst, 72)`, DSE the overwritten store at offset 72, and coalesce `68..76` into `i64.store`:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        // Mark module as SIMD-enabled via a v128 global.
        try mod.globals.append(allocator, .{
            .type = .{ .val_type = .v128, .mutability = .immutable },
            .init_expr_bytes = &([_]u8{ 0xfd, 0x0c } ++ (@as([16]u8, @splat(0)))),
        });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{ .i32, .f32 }),
            .results = &.{},
        } });
        try mod.type_meta.append(allocator, .{});

        const slug_init_code = [_]u8{
            // Offsets 0..16: 4 constant f32 stores (1.0, 2.0, 3.0, 4.0)
            0x20, 0x00, // local.get 0 (dst)
            0x43, 0x00, 0x00, 0x80, 0x3f, // f32.const 1.0
            0x38, 0x02, 0x00, // f32.store align=2 offset=0
            0x20, 0x00, // local.get 0
            0x43, 0x00, 0x00, 0x00, 0x40, // f32.const 2.0
            0x38, 0x02, 0x04, // f32.store align=2 offset=4
            0x20, 0x00, // local.get 0
            0x43, 0x00, 0x00, 0x40, 0x40, // f32.const 3.0
            0x38, 0x02, 0x08, // f32.store align=2 offset=8
            0x20, 0x00, // local.get 0
            0x43, 0x00, 0x00, 0x80, 0x40, // f32.const 4.0
            0x38, 0x02, 0x0c, // f32.store align=2 offset=12
            // Non-constant store at offset 16:
            0x20, 0x00, // local.get 0
            0x20, 0x01, // local.get 1 (dyn)
            0x38, 0x02, 16, // f32.store align=2 offset=16
            // Offsets 68..76: 2 constant f32 stores (5.0 at 68, dead 9.0 at 72)
            0x20, 0x00, // local.get 0
            0x43, 0x00, 0x00, 0xa0, 0x40, // f32.const 5.0
            0x38, 0x02, 68, // f32.store align=2 offset=68
            0x20, 0x00, // local.get 0
            0x43, 0x00, 0x00, 0x10, 0x41, // f32.const 9.0 (overwritten below!)
            0x38, 0x02, 72, // f32.store align=2 offset=72
            // Trailing in-place self-offset store: `dst = dst + 72; *dst = 0.0`
            0x20, 0x00, // local.get 0
            0x41, 0xc8, 0x00, // i32.const 72
            0x6a, // i32.add
            0x21, 0x00, // local.set 0
            0x20, 0x00, // local.get 0
            0x43, 0x00, 0x00, 0x00, 0x00, // f32.const 0.0
            0x38, 0x02, 0x00, // f32.store align=2 offset=0
            0x0b, // end
        };

        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &slug_init_code });
        try mod.exports.append(allocator, .{ .name = "slug_init", .kind = .func, .var_ = .{ .index = 0 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        var parse_pos: usize = 0;
        var parsed: InstrList = .empty;
        _ = try parseInstrBlock(arena_state.allocator(), opt_mod.funcs.items[0].code_bytes, &parse_pos, false, &parsed);

        var v128_stores: usize = 0;
        var i64_stores: usize = 0;
        var f32_stores: usize = 0;
        var i32_adds: usize = 0;
        var last_i64_const: ?i64 = null;
        for (parsed.items) |inst| {
            if (inst == .i64_const) last_i64_const = inst.i64_const;
            if (inst == .numeric_op and inst.numeric_op == 0x6a) i32_adds += 1;
            if (decodeStoreAccess(inst)) |acc| {
                if (acc.opcode == 0xfd and acc.simd_sub == 0x0b) v128_stores += 1;
                if (acc.opcode == 0x37) i64_stores += 1;
                if (acc.opcode == 0x38) f32_stores += 1;
            }
        }
        // 1 `v128.store` (offsets 0..16), 1 dynamic `f32.store` (offset 16), 1 `i64.store` (offsets 68..76), 0 `i32.add`!
        try testing.expectEqual(@as(usize, 1), v128_stores);
        try testing.expectEqual(@as(usize, 1), i64_stores);
        try testing.expectEqual(@as(usize, 1), f32_stores);
        try testing.expectEqual(@as(usize, 0), i32_adds);
        // The `i64.store` at offset 68 packs `5.0` (0x40a00000) in the low 32 bits and `0.0` (0x00000000) in the high 32 bits!
        try testing.expectEqual(@as(?i64, 0x0000_0000_40a0_0000), last_i64_const);
    }

    // 2. Negative case: when `dst` is read after the store (returned), `dst += 72` must NOT be eliminated:
    {
        var mod = Mod.Module.init(allocator);
        defer mod.deinit();

        try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
        try mod.module_types.append(allocator, .{ .func_type = .{
            .params = try allocator.dupe(types.ValType, &.{.i32}),
            .results = try allocator.dupe(types.ValType, &.{.i32}),
        } });
        try mod.type_meta.append(allocator, .{});

        const live_ptr_code = [_]u8{
            0x20, 0x00, // local.get 0
            0x41, 0xc8, 0x00, // i32.const 72
            0x6a, // i32.add
            0x21, 0x00, // local.set 0
            0x20, 0x00, // local.get 0
            0x43, 0x00, 0x00, 0x00, 0x00, // f32.const 0.0
            0x38, 0x02, 0x00, // f32.store align=2 offset=0
            0x20, 0x00, // local.get 0 (returned!)
            0x0b, // end
        };

        try mod.funcs.append(allocator, .{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &live_ptr_code });
        try mod.exports.append(allocator, .{ .name = "live_ptr", .kind = .func, .var_ = .{ .index = 0 } });

        const wasm = try writer.writeModule(allocator, &mod);
        defer allocator.free(wasm);
        const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
        defer allocator.free(opt);
        var opt_mod = try reader.readModule(allocator, opt);
        defer opt_mod.deinit();

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        var parse_pos: usize = 0;
        var parsed: InstrList = .empty;
        _ = try parseInstrBlock(arena_state.allocator(), opt_mod.funcs.items[0].code_bytes, &parse_pos, false, &parsed);

        var i32_adds: usize = 0;
        for (parsed.items) |inst| {
            if (inst == .numeric_op and inst.numeric_op == 0x6a) i32_adds += 1;
        }
        try testing.expectEqual(@as(usize, 1), i32_adds);
    }
}

test "Optimizer: unrolled SIMD stack-copy forwarding with derived pointer and indexed load" {
    const allocator = testing.allocator;

    var mod = Mod.Module.init(allocator);
    defer mod.deinit();

    try mod.memories.append(allocator, .{ .type = .{ .limits = .{ .initial = 1 } } });
    try mod.globals.append(allocator, .{
        .type = .{ .val_type = .i32, .mutability = .mutable },
        .init_expr_bytes = &[_]u8{ 0x41, 0x80, 0x80, 0x04 },
    });
    // Type 0: (param i32 self_ptr, i32 bit_idx) -> (result i32)
    try mod.module_types.append(allocator, .{ .func_type = .{
        .params = try allocator.dupe(types.ValType, &.{ .i32, .i32 }),
        .results = try allocator.dupe(types.ValType, &.{.i32}),
    } });
    try mod.type_meta.append(allocator, .{});

    // Simulate `self.layers_dirty.isSet(bit_idx)` after inlining in `ReleaseFast` (+simd128):
    //   local 2 = fp, local 3 = derived_ptr, local 4 = word_idx
    //   Prologue allocates 64-byte frame (`fp = global 0 - 64`).
    //   Unrolled 32-byte copy from `self_ptr + 2140..2172` to `fp + 32..64`:
    //     local.get 2; local.get 0; v128.load offset=2140;
    //     local.get 2; local.get 0; v128.load offset=2156;
    //     v128.store offset=48;
    //     v128.store offset=32;
    //   Followed by inlined `ArrayBitSet.isSet` inside a block:
    //     local.get 2; i32.const 32; i32.add; local.set 3;
    //     local.get 1; i32.const 5; i32.shr_u; local.set 4;
    //     block (result i32)
    //       local.get 3; local.get 4; i32.const 2; i32.shl; i32.add; i32.load offset=0;
    //     end
    //   Epilogue restores `global 0 = fp + 64`.
    const is_set_code = [_]u8{
        // Prologue (frame_size = 64, fp = local 2):
        0x23, 0x00, // global.get 0
        0x41, 0xc0, 0x00, // i32.const 64
        0x6b, // i32.sub
        0x22, 0x02, // local.tee 2 (fp)
        0x24, 0x00, // global.set 0
        // Unrolled 32-byte SIMD stack copy (`self_ptr + 2140..2172` -> `fp + 32..64`):
        0x20, 0x02, // local.get 2 (fp)
        0x20, 0x00, // local.get 0 (self_ptr)
        0xfd, 0x00, 0x02, 0xdc, 0x10, // v128.load align=2 offset=2140
        0x20, 0x02, // local.get 2 (fp)
        0x20, 0x00, // local.get 0 (self_ptr)
        0xfd, 0x00, 0x02, 0xec, 0x10, // v128.load align=2 offset=2156
        0xfd, 0x0b, 0x04, 0x30, // v128.store align=4 offset=48
        0xfd, 0x0b, 0x04, 0x20, // v128.store align=4 offset=32
        // Single-write, single-read derived pointer `local 3 = fp + 32`:
        0x20, 0x02, // local.get 2 (fp)
        0x41, 0x20, // i32.const 32
        0x6a, // i32.add
        0x21, 0x03, // local.set 3
        // `local 4 = bit_idx >> 5`:
        0x20, 0x01, // local.get 1 (bit_idx)
        0x41, 0x05, // i32.const 5
        0x76, // i32.shr_u
        0x21, 0x04, // local.set 4
        // Indexed load `(local 3 + (local 4 << 2))`:
        0x20, 0x03, // local.get 3
        0x20, 0x04, // local.get 4
        0x41, 0x02, // i32.const 2
        0x74, // i32.shl
        0x6a, // i32.add
        0x28, 0x02, 0x00, // i32.load align=2 offset=0
        // Epilogue:
        0x20, 0x02, // local.get 2 (fp)
        0x41, 0xc0, 0x00, // i32.const 64
        0x6a, // i32.add
        0x24, 0x00, // global.set 0
        0x0b, // end
    };

    var f0 = Mod.Func{ .decl = .{ .type_var = .{ .index = 0 } }, .code_bytes = &is_set_code };
    try f0.local_types.appendSlice(allocator, &.{ .i32, .i32, .i32 }); // locals 2, 3, 4
    try mod.funcs.append(allocator, f0);
    try mod.exports.append(allocator, .{ .name = "is_layer_dirty", .kind = .func, .var_ = .{ .index = 0 } });

    const wasm = try writer.writeModule(allocator, &mod);
    defer allocator.free(wasm);
    const opt = try optimize(allocator, wasm, .{ .optimize_mode = .fast });
    defer allocator.free(opt);
    var opt_mod = try reader.readModule(allocator, opt);
    defer opt_mod.deinit();

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    var parse_pos: usize = 0;
    var parsed: InstrList = .empty;
    _ = try parseInstrBlock(arena_state.allocator(), opt_mod.funcs.items[0].code_bytes, &parse_pos, false, &parsed);

    // Verify the unrolled `v128.load`/`v128.store` copy and the entire shadow-stack frame were eliminated,
    // leaving only 1 `i32.load` directly from `self_ptr + 2140 + ((bit_idx >> 5) << 2)` and 0 `v128` ops!
    try testing.expectEqual(@as(usize, 1), opt_mod.funcs.items[0].local_types.items.len);
    var v128_ops: usize = 0;
    var i32_loads: usize = 0;
    for (parsed.items) |inst| {
        if (inst == .raw and inst.raw.len > 0 and inst.raw[0] == 0xfd) v128_ops += 1;
        if (decodeLoadAccess(inst)) |acc| {
            if (acc.opcode == 0x28) i32_loads += 1;
        }
    }
    try testing.expectEqual(@as(usize, 0), v128_ops);
    try testing.expectEqual(@as(usize, 1), i32_loads);
}

