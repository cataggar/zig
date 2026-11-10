const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const max_pass_rounds: usize = 4;

pub fn optimize(
    gpa: Allocator,
    mir_instructions: anytype,
    mir_extra: *std.ArrayList(u32),
    error_name_table_ref_count: *u32,
) Allocator.Error!void {
    const Inst = @TypeOf(mir_instructions.get(0));
    return Pass(Inst).optimize(gpa, mir_instructions, mir_extra, error_name_table_ref_count);
}

pub fn foldConstants(
    gpa: Allocator,
    insts: anytype,
    out: anytype,
    mir_extra: *std.ArrayList(u32),
) Allocator.Error!bool {
    const Inst = std.meta.Elem(@TypeOf(insts));
    return Pass(Inst).foldConstants(gpa, insts, out, mir_extra);
}

pub fn simplifyControlFlow(
    gpa: Allocator,
    current: anytype,
    scratch: anytype,
    mir_extra: *std.ArrayList(u32),
) Allocator.Error!bool {
    const Inst = std.meta.Elem(@TypeOf(current.items));
    return Pass(Inst).simplifyControlFlow(gpa, current, scratch, mir_extra);
}

pub fn eliminateDeadCode(
    gpa: Allocator,
    insts: anytype,
    out: anytype,
) Allocator.Error!bool {
    const Inst = std.meta.Elem(@TypeOf(insts));
    return Pass(Inst).eliminateDeadCode(gpa, insts, out);
}

pub fn simplifyLocals(
    gpa: Allocator,
    insts: anytype,
    out: anytype,
) Allocator.Error!bool {
    const Inst = std.meta.Elem(@TypeOf(insts));
    return Pass(Inst).simplifyLocals(gpa, insts, out, &.{});
}

pub fn hoistLoopInvariantLocalSets(
    gpa: Allocator,
    insts: anytype,
    out: anytype,
) Allocator.Error!bool {
    const Inst = std.meta.Elem(@TypeOf(insts));
    return Pass(Inst).hoistLoopInvariantLocalSets(gpa, insts, out);
}

pub fn optimizeMemoryAccesses(
    gpa: Allocator,
    out: anytype,
    insts: anytype,
    mir_extra: *std.ArrayList(u32),
) Allocator.Error!bool {
    const Inst = std.meta.Elem(@TypeOf(insts));
    return Pass(Inst).optimizeMemoryAccesses(gpa, out, insts, mir_extra);
}

pub fn compactLocals(
    gpa: Allocator,
    mir_instructions: anytype,
    mir_locals: *std.ArrayList(std.wasm.Valtype),
    wasm_param_count: u32,
    bottom_stack_local: ?*u32,
    sp_local: ?*u32,
) Allocator.Error!void {
    const Inst = @TypeOf(mir_instructions.get(0));
    return Pass(Inst).compactLocals(
        gpa,
        mir_instructions,
        mir_locals,
        wasm_param_count,
        bottom_stack_local,
        sp_local,
    );
}

/// Asserts `code` has at least `5 + locals.len * 6` bytes of unused capacity.
pub fn encodeLocals(code: *std.ArrayList(u8), locals: []const std.wasm.Valtype) void {
    if (locals.len == 0) {
        writeUleb128(code, @as(u32, 0));
        return;
    }
    var num_decls: u32 = 1;
    for (1..locals.len) |i| {
        if (locals[i] != locals[i - 1]) num_decls += 1;
    }
    writeUleb128(code, num_decls);
    var run_start: usize = 0;
    while (run_start < locals.len) {
        var run_end = run_start + 1;
        while (run_end < locals.len and locals[run_end] == locals[run_start]) : (run_end += 1) {}
        writeUleb128(code, @as(u32, @intCast(run_end - run_start)));
        code.appendAssumeCapacity(@backingInt(locals[run_start]));
        run_start = run_end;
    }
}

fn writeUleb128(code: *std.ArrayList(u8), arg: anytype) void {
    var w: std.Io.Writer = .fixed(code.unusedCapacitySlice());
    w.writeUleb128(arg) catch unreachable;
    code.items.len += w.end;
}

fn readImm64(mir_extra: []const u32, payload: u32) u64 {
    const msb = mir_extra[payload];
    const lsb = mir_extra[payload + 1];
    return (@as(u64, msb) << 32) | @as(u64, lsb);
}

fn appendImm64(gpa: Allocator, mir_extra: *std.ArrayList(u32), val: u64) Allocator.Error!u32 {
    const msb: u32 = @truncate(val >> 32);
    const lsb: u32 = @truncate(val);
    const payload: u32 = @intCast(mir_extra.items.len);
    try mir_extra.ensureUnusedCapacity(gpa, 2);
    mir_extra.appendAssumeCapacity(msb);
    mir_extra.appendAssumeCapacity(lsb);
    return payload;
}

pub fn readMemArgOffset(mir_extra: []const u32, memarg_idx: u32) u64 {
    const lo = mir_extra[memarg_idx];
    const hi = mir_extra[memarg_idx + 1];
    return (@as(u64, hi) << 32) | @as(u64, lo);
}

fn appendMemArg(
    gpa: Allocator,
    mir_extra: *std.ArrayList(u32),
    offset: u64,
    alignment: u32,
    prefix_opcode: ?u32,
) Allocator.Error!u32 {
    const lo: u32 = @truncate(offset);
    const hi: u32 = @truncate(offset >> 32);
    const payload: u32 = @intCast(mir_extra.items.len);
    if (prefix_opcode) |op| {
        try mir_extra.ensureUnusedCapacity(gpa, 4);
        mir_extra.appendAssumeCapacity(op);
    } else {
        try mir_extra.ensureUnusedCapacity(gpa, 3);
    }
    mir_extra.appendAssumeCapacity(lo);
    mir_extra.appendAssumeCapacity(hi);
    mir_extra.appendAssumeCapacity(alignment);
    return payload;
}

fn Pass(comptime Inst: type) type {
    return struct {
        const Self = @This();

        fn optimize(
            gpa: Allocator,
            mir_instructions: *std.MultiArrayList(Inst),
            mir_extra: *std.ArrayList(u32),
            error_name_table_ref_count: *u32,
        ) Allocator.Error!void {
            if (mir_instructions.len == 0) {
                error_name_table_ref_count.* = 0;
                return;
            }

            var current: std.ArrayList(Inst) = .empty;
            defer current.deinit(gpa);
            var next: std.ArrayList(Inst) = .empty;
            defer next.deinit(gpa);

            try current.ensureTotalCapacity(gpa, mir_instructions.len);
            {
                const slice = mir_instructions.slice();
                const tags = slice.items(.tag);
                const datas = slice.items(.data);
                for (tags, datas) |tag, data| {
                    current.appendAssumeCapacity(.{ .tag = tag, .data = data });
                }
            }

            const body_len = splitBodyAndSuffix(current.items);
            var suffix: std.ArrayList(Inst) = .empty;
            defer suffix.deinit(gpa);
            try suffix.appendSlice(gpa, current.items[body_len..]);
            current.shrinkRetainingCapacity(body_len);

            var any_changed = false;
            var round: usize = 0;
            while (round < max_pass_rounds) : (round += 1) {
                var round_changed = false;

                if (try Self.hoistLoopInvariantLocalSets(gpa, current.items, &next)) {
                    std.mem.swap(std.ArrayList(Inst), &current, &next);
                    round_changed = true;
                }

                if (try Self.simplifyLocals(gpa, current.items, &next, mir_extra.items)) {
                    std.mem.swap(std.ArrayList(Inst), &current, &next);
                    round_changed = true;
                }

                if (try Self.foldConstants(gpa, current.items, &next, mir_extra)) {
                    std.mem.swap(std.ArrayList(Inst), &current, &next);
                    round_changed = true;
                }

                if (try Self.optimizeMemoryAccesses(gpa, &next, current.items, mir_extra)) {
                    std.mem.swap(std.ArrayList(Inst), &current, &next);
                    round_changed = true;
                }

                if (try Self.simplifyControlFlow(gpa, &current, &next, mir_extra)) {
                    round_changed = true;
                }

                if (try Self.eliminateDeadCode(gpa, current.items, &next)) {
                    std.mem.swap(std.ArrayList(Inst), &current, &next);
                    round_changed = true;
                }

                if (!round_changed) break;
                any_changed = true;
            }

            if (any_changed) {
                mir_instructions.len = 0;
                try mir_instructions.ensureUnusedCapacity(gpa, current.items.len + suffix.items.len);
                for (current.items) |inst| {
                    mir_instructions.appendAssumeCapacity(inst);
                }
                for (suffix.items) |inst| {
                    mir_instructions.appendAssumeCapacity(inst);
                }
            }

            var err_refs: u32 = 0;
            for (mir_instructions.items(.tag)) |tag| {
                if (tag == .error_name_table_ref) err_refs += 1;
            }
            error_name_table_ref_count.* = err_refs;
        }

        fn splitBodyAndSuffix(insts: []const Inst) usize {
            var depth: usize = 0;
            for (insts, 0..) |inst, i| {
                switch (inst.tag) {
                    .block, .loop => depth += 1,
                    .end => {
                        if (depth > 0) {
                            depth -= 1;
                        } else {
                            return i;
                        }
                    },
                    .dbg_epilogue_begin => {
                        if (depth == 0) return i;
                    },
                    else => {},
                }
            }
            return insts.len;
        }

        fn makeI32Const(val: i32) Inst {
            return .{ .tag = .i32_const, .data = .{ .imm32 = val } };
        }

        fn makeI64Const(gpa: Allocator, mir_extra: *std.ArrayList(u32), val: u64) Allocator.Error!Inst {
            const payload = try appendImm64(gpa, mir_extra, val);
            return .{ .tag = .i64_const, .data = .{ .payload = payload } };
        }

        fn makeSimdInst(gpa: Allocator, mir_extra: *std.ArrayList(u32), op: std.wasm.SimdOpcode) Allocator.Error!Inst {
            const payload: u32 = @intCast(mir_extra.items.len);
            try mir_extra.append(gpa, @backingInt(op));
            return .{ .tag = .simd_prefix, .data = .{ .payload = payload } };
        }

        fn isSimdOp(inst: Inst, mir_extra: []const u32, op: std.wasm.SimdOpcode) bool {
            return inst.tag == .simd_prefix and
                inst.data.payload < mir_extra.len and
                mir_extra[inst.data.payload] == @backingInt(op);
        }

        fn isPureZeroPopOrSimdConst(inst: Inst, mir_extra: []const u32) bool {
            return isPureZeroPopTag(inst.tag) or isSimdOp(inst, mir_extra, .v128_const);
        }

        fn pureScalarIntrinsicPops(intrinsic: anytype) ?i32 {
            return switch (intrinsic) {
                .__extendhfsf2,
                .__truncsfhf2,
                .__bitreversesi2,
                .__bitreversedi2,
                .__bswapsi2,
                .__bswapdi2,
                .__floatsihf,
                .__floatunsihf,
                .__floatdihf,
                .__floatundihf,
                .__ceilh,
                .__floorh,
                .__trunch,
                .__roundh,
                .__fabsh,
                .__sqrth,
                .__sinh,
                .__cosh,
                .__tanh,
                .__exph,
                .__exp2h,
                .__logh,
                .__log2h,
                .__log10h,
                .sinf,
                .cosf,
                .tanf,
                .expf,
                .exp2f,
                .logf,
                .log2f,
                .log10f,
                .sin,
                .cos,
                .tan,
                .exp,
                .exp2,
                .log,
                .log2,
                .log10,
                => 1,

                .__addhf3,
                .__subhf3,
                .__mulhf3,
                .__divhf3,
                .__fmodh,
                .__fmaxh,
                .__fminh,
                .fmodf,
                .fmod,
                .__fmax,
                .__truncxfhf2,
                .__trunctfhf2,
                .__truncxfsf2,
                .__trunctfsf2,
                .__truncxfdf2,
                .__trunctfdf2,
                .__fixxfsi,
                .__fixunsxfsi,
                .__fixtfsi,
                .__fixunstfsi,
                .__fixxfdi,
                .__fixunsxfdi,
                .__fixtfdi,
                .__fixunstfdi,
                .__floattihf,
                .__floatuntihf,
                .__floattisf,
                .__floatuntisf,
                .__floattidf,
                .__floatuntidf,
                => 2,

                .__fmah,
                .fmaf,
                .fma,
                => 3,

                .__eqtf2,
                .__netf2,
                .__lttf2,
                .__letf2,
                .__gttf2,
                .__getf2,
                .__eqxf2,
                .__nexf2,
                .__ltxf2,
                .__lexf2,
                .__gtxf2,
                .__gexf2,
                => 4,

                else => null,
            };
        }

        fn isExtendHfSf2(inst: Inst) bool {
            return inst.tag == .call_intrinsic and inst.data.intrinsic == .__extendhfsf2;
        }

        fn isTruncSfHf2(inst: Inst) bool {
            return inst.tag == .call_intrinsic and inst.data.intrinsic == .__truncsfhf2;
        }

        fn pureNonTrappingInstPops(inst: Inst, mir_extra: []const u32) ?i32 {
            if (pureNonTrappingPops(inst.tag)) |pops| return pops;
            return switch (inst.tag) {
                .call_intrinsic => pureScalarIntrinsicPops(inst.data.intrinsic),
                .simd_prefix => if (inst.data.payload < mir_extra.len) blk: {
                    const simd_op: std.wasm.SimdOpcode = @fromBackingInt(mir_extra[inst.data.payload]);
                    break :blk switch (simd_op) {
                        .v128_load,
                        .v128_load8x8_s,
                        .v128_load8x8_u,
                        .v128_load16x4_s,
                        .v128_load16x4_u,
                        .v128_load32x2_s,
                        .v128_load32x2_u,
                        .v128_load8_splat,
                        .v128_load16_splat,
                        .v128_load32_splat,
                        .v128_load64_splat,
                        .v128_load32_zero,
                        .v128_load64_zero,
                        .v128_load8_lane,
                        .v128_load16_lane,
                        .v128_load32_lane,
                        .v128_load64_lane,
                        .v128_store,
                        .v128_store8_lane,
                        .v128_store16_lane,
                        .v128_store32_lane,
                        .v128_store64_lane,
                        => null,
                        else => singlePushInstPops(inst, mir_extra),
                    };
                } else null,
                else => null,
            };
        }

        fn findPureValStartIndex(insts: []const Inst, mir_extra: []const u32) ?usize {
            var needed: i32 = 1;
            var idx: usize = insts.len;
            while (idx > 0) {
                idx -= 1;
                const prev = insts[idx];
                if (prev.tag == .dbg_line) continue;
                const pops: i32 = pureNonTrappingInstPops(prev, mir_extra) orelse return null;
                needed = needed - 1 + pops;
                if (needed == 0) return idx;
            }
            return null;
        }

        fn isPtrRefTag(tag: Inst.Tag) bool {
            return switch (tag) {
                .uav_ref,
                .uav_ref_off,
                .nav_ref,
                .nav_ref_off,
                .func_ref,
                .tls_nav_ref,
                .error_name_table_ref,
                .enum_tag_name_table_ref,
                => true,
                else => false,
            };
        }

        fn isConstTag(tag: Inst.Tag) bool {
            return switch (tag) {
                .i32_const, .i64_const, .f32_const, .f64_const, .errors_len => true,
                else => isPtrRefTag(tag),
            };
        }

        fn isBoolProducerTag(tag: Inst.Tag) bool {
            return switch (tag) {
                .i32_eqz,
                .i64_eqz,
                .i32_eq,
                .i32_ne,
                .i32_lt_s,
                .i32_lt_u,
                .i32_gt_s,
                .i32_gt_u,
                .i32_le_s,
                .i32_le_u,
                .i32_ge_s,
                .i32_ge_u,
                .i64_eq,
                .i64_ne,
                .i64_lt_s,
                .i64_lt_u,
                .i64_gt_s,
                .i64_gt_u,
                .i64_le_s,
                .i64_le_u,
                .i64_ge_s,
                .i64_ge_u,
                .f32_eq,
                .f32_ne,
                .f32_lt,
                .f32_gt,
                .f32_le,
                .f32_ge,
                .f64_eq,
                .f64_ne,
                .f64_lt,
                .f64_gt,
                .f64_le,
                .f64_ge,
                => true,
                else => false,
            };
        }

        fn invertComparisonTag(tag: Inst.Tag) ?Inst.Tag {
            return switch (tag) {
                .i32_eq => .i32_ne,
                .i32_ne => .i32_eq,
                .i32_lt_s => .i32_ge_s,
                .i32_ge_s => .i32_lt_s,
                .i32_lt_u => .i32_ge_u,
                .i32_ge_u => .i32_lt_u,
                .i32_gt_s => .i32_le_s,
                .i32_le_s => .i32_gt_s,
                .i32_gt_u => .i32_le_u,
                .i32_le_u => .i32_gt_u,
                .i64_eq => .i64_ne,
                .i64_ne => .i64_eq,
                .i64_lt_s => .i64_ge_s,
                .i64_ge_s => .i64_lt_s,
                .i64_lt_u => .i64_ge_u,
                .i64_ge_u => .i64_lt_u,
                .i64_gt_s => .i64_le_s,
                .i64_le_s => .i64_gt_s,
                .i64_gt_u => .i64_le_u,
                .i64_le_u => .i64_gt_u,
                .f32_eq => .f32_ne,
                .f32_ne => .f32_eq,
                .f64_eq => .f64_ne,
                .f64_ne => .f64_eq,
                else => null,
            };
        }

        fn isPureZeroPopTag(tag: Inst.Tag) bool {
            return switch (tag) {
                .local_get, .global_get => true,
                else => isConstTag(tag),
            };
        }

        fn emitOrFoldI32Eqz(out: *std.ArrayList(Inst), mir_extra: []const u32) bool {
            const len = out.items.len;
            if (len >= 1) {
                const last = out.items[len - 1];
                if (last.tag == .i32_const) {
                    out.items[len - 1] = makeI32Const(if (last.data.imm32 == 0) 1 else 0);
                    return true;
                }
                if (last.tag == .i32_xor) {
                    out.items[len - 1].tag = .i32_eq;
                    if (len >= 2 and out.items[len - 2].tag == .i32_const and out.items[len - 2].data.imm32 == 0) {
                        out.items.len = len - 2;
                        _ = emitOrFoldI32Eqz(out, mir_extra);
                    }
                    return true;
                }
                if (invertComparisonTag(last.tag)) |inv| {
                    out.items[len - 1].tag = inv;
                    if (inv == .i32_eq and len >= 2 and out.items[len - 2].tag == .i32_const and out.items[len - 2].data.imm32 == 0) {
                        out.items.len = len - 2;
                        _ = emitOrFoldI32Eqz(out, mir_extra);
                    } else if (inv == .i64_eq and len >= 2 and out.items[len - 2].tag == .i64_const and readImm64(mir_extra, out.items[len - 2].data.payload) == 0) {
                        out.items.len = len - 1;
                        out.items[len - 2] = .{ .tag = .i64_eqz, .data = .{ .tag = {} } };
                    }
                    return true;
                }
                if (last.tag == .i32_eqz and len >= 2 and isBoolProducerTag(out.items[len - 2].tag)) {
                    _ = out.pop();
                    return true;
                }
            }
            out.appendAssumeCapacity(.{ .tag = .i32_eqz, .data = .{ .tag = {} } });
            return false;
        }

        fn isLocalReadBeforeOverwriteOrExit(
            insts: []const Inst,
            start_idx: usize,
            local: u32,
            ignore_get_idx: ?usize,
        ) bool {
            var j: usize = start_idx;
            while (j < insts.len) : (j += 1) {
                switch (insts[j].tag) {
                    .local_get => {
                        if (insts[j].data.local == local) return true;
                    },
                    .local_set, .local_tee => {
                        if (insts[j].data.local == local) return false;
                    },
                    .@"return", .return_call_nav, .return_call_indirect, .@"unreachable" => return false,
                    .block, .loop, .end, .br, .br_if, .br_table => {
                        for (insts, 0..) |other, k| {
                            if (ignore_get_idx != null and k == ignore_get_idx.?) continue;
                            if (other.tag == .local_get and other.data.local == local) return true;
                        }
                        return false;
                    },
                    else => {},
                }
            }
            return false;
        }

        fn isF16ExtReadBeforeOverwriteOrExit(
            insts: []const Inst,
            start_idx: usize,
            local: u32,
        ) bool {
            var j: usize = start_idx;
            while (j + 1 < insts.len) : (j += 1) {
                switch (insts[j].tag) {
                    .local_get => {
                        if (insts[j].data.local == local and isExtendHfSf2(insts[j + 1])) return true;
                    },
                    .local_set, .local_tee => {
                        if (insts[j].data.local == local) return false;
                    },
                    .@"return",
                    .return_call_nav,
                    .return_call_indirect,
                    .@"unreachable",
                    .block,
                    .loop,
                    .end,
                    .br,
                    .br_if,
                    .br_table,
                    => return false,
                    else => {},
                }
            }
            return false;
        }

        fn invalidateF16ExtLocal(f16_ext_locals: *std.AutoArrayHashMapUnmanaged(u32, u32), local: u32) void {
            _ = f16_ext_locals.swapRemove(local);
            var idx: usize = f16_ext_locals.count();
            while (idx > 0) {
                idx -= 1;
                if (f16_ext_locals.values()[idx] == local) {
                    f16_ext_locals.swapRemoveAt(idx);
                }
            }
        }

        fn invalidateLocal(known_locals: *std.AutoArrayHashMapUnmanaged(u32, Inst), local: u32) void {
            _ = known_locals.swapRemove(local);
            var idx: usize = known_locals.count();
            while (idx > 0) {
                idx -= 1;
                const val = known_locals.values()[idx];
                if (val.tag == .local_get and val.data.local == local) {
                    known_locals.swapRemoveAt(idx);
                }
            }
        }

        fn invalidateModifiedLocalsInSpan(
            known_locals: *std.AutoArrayHashMapUnmanaged(u32, Inst),
            span: []const Inst,
        ) void {
            if (known_locals.count() == 0) return;
            for (span) |inst| {
                switch (inst.tag) {
                    .local_set, .local_tee => {
                        invalidateLocal(known_locals, inst.data.local);
                        if (known_locals.count() == 0) return;
                    },
                    else => {},
                }
            }
        }

        fn recordLocalSet(
            gpa: Allocator,
            known_locals: *std.AutoArrayHashMapUnmanaged(u32, Inst),
            local: u32,
            prev_inst: ?Inst,
        ) Allocator.Error!void {
            invalidateLocal(known_locals, local);
            const prev = prev_inst orelse return;
            if (isConstTag(prev.tag) and prev.tag != .error_name_table_ref) {
                try known_locals.put(gpa, local, prev);
            } else if (prev.tag == .local_get) {
                const resolved = if (known_locals.get(prev.data.local)) |known| known else prev;
                if (!(resolved.tag == .local_get and resolved.data.local == local)) {
                    try known_locals.put(gpa, local, resolved);
                }
            } else if (prev.tag == .local_tee) {
                const tee_local = prev.data.local;
                const resolved = if (known_locals.get(tee_local)) |known|
                    known
                else
                    Inst{ .tag = .local_get, .data = .{ .local = tee_local } };
                if (!(resolved.tag == .local_get and resolved.data.local == local)) {
                    try known_locals.put(gpa, local, resolved);
                }
            }
        }

        const ScopeFrame = struct {
            start_idx: usize,
            entry_known: std.AutoArrayHashMapUnmanaged(u32, Inst),
        };

        fn simplifyLocals(
            gpa: Allocator,
            insts: []const Inst,
            out: *std.ArrayList(Inst),
            mir_extra: []const u32,
        ) Allocator.Error!bool {
            out.clearRetainingCapacity();
            try out.ensureTotalCapacity(gpa, insts.len);

            var known_locals: std.AutoArrayHashMapUnmanaged(u32, Inst) = .empty;
            defer known_locals.deinit(gpa);

            var f16_ext_locals: std.AutoArrayHashMapUnmanaged(u32, u32) = .empty;
            defer f16_ext_locals.deinit(gpa);

            var scope_stack: std.ArrayList(ScopeFrame) = .empty;
            defer {
                for (scope_stack.items) |*frame| {
                    frame.entry_known.deinit(gpa);
                }
                scope_stack.deinit(gpa);
            }

            var changed = false;
            var i: usize = 0;
            while (i < insts.len) {
                const inst = insts[i];
                switch (inst.tag) {
                    .loop => {
                        f16_ext_locals.clearRetainingCapacity();
                        if (findMatchingEnd(insts, i)) |end_idx| {
                            invalidateModifiedLocalsInSpan(&known_locals, insts[i + 1 .. end_idx]);
                            const cloned = try known_locals.clone(gpa);
                            errdefer {
                                var c = cloned;
                                c.deinit(gpa);
                            }
                            try scope_stack.append(gpa, .{
                                .start_idx = i,
                                .entry_known = cloned,
                            });
                        } else {
                            known_locals.clearRetainingCapacity();
                        }
                    },
                    .block => {
                        f16_ext_locals.clearRetainingCapacity();
                        if (findMatchingEnd(insts, i) != null) {
                            const cloned = try known_locals.clone(gpa);
                            errdefer {
                                var c = cloned;
                                c.deinit(gpa);
                            }
                            try scope_stack.append(gpa, .{
                                .start_idx = i,
                                .entry_known = cloned,
                            });
                        } else {
                            known_locals.clearRetainingCapacity();
                        }
                    },
                    .br_if => {},
                    .br,
                    .br_table,
                    .@"return",
                    .return_call_nav,
                    .return_call_indirect,
                    .@"unreachable",
                    => {
                        known_locals.clearRetainingCapacity();
                        f16_ext_locals.clearRetainingCapacity();
                    },
                    .end => {
                        f16_ext_locals.clearRetainingCapacity();
                        if (scope_stack.pop()) |frame_val| {
                            var frame = frame_val;
                            defer frame.entry_known.deinit(gpa);
                            known_locals.clearRetainingCapacity();
                            const keys = frame.entry_known.keys();
                            const vals = frame.entry_known.values();
                            try known_locals.ensureTotalCapacity(gpa, keys.len);
                            for (keys, vals) |k_local, v_inst| {
                                known_locals.putAssumeCapacity(k_local, v_inst);
                            }
                            invalidateModifiedLocalsInSpan(&known_locals, insts[frame.start_idx + 1 .. i]);
                        } else {
                            known_locals.clearRetainingCapacity();
                        }
                    },
                    else => {},
                }
                if (inst.tag == .local_get) {
                    if (i + 1 < insts.len and isExtendHfSf2(insts[i + 1])) {
                        const resolved_local = blk: {
                            if (known_locals.get(inst.data.local)) |rep| {
                                if (rep.tag == .local_get) break :blk rep.data.local;
                            }
                            break :blk inst.data.local;
                        };
                        if (f16_ext_locals.get(resolved_local)) |ext_local| {
                            out.appendAssumeCapacity(.{ .tag = .local_get, .data = .{ .local = ext_local } });
                            changed = true;
                            i += 2;
                            continue;
                        }
                    }
                    if (!(i + 1 < insts.len and insts[i + 1].tag == .local_set and insts[i + 1].data.local == inst.data.local)) {
                        if (known_locals.get(inst.data.local)) |replacement| {
                            out.appendAssumeCapacity(replacement);
                            changed = true;
                            i += 1;
                            continue;
                        }
                    }
                }
                if (inst.tag == .local_set) {
                    const prev_is_ext_of_src: ?u32 = if (out.items.len >= 2 and
                        out.items[out.items.len - 2].tag == .local_get and
                        isExtendHfSf2(out.items[out.items.len - 1]) and
                        out.items[out.items.len - 2].data.local != inst.data.local)
                        out.items[out.items.len - 2].data.local
                    else
                        null;
                    invalidateF16ExtLocal(&f16_ext_locals, inst.data.local);
                    if (out.items.len >= 1 and
                        out.items[out.items.len - 1].tag == .local_get and
                        out.items[out.items.len - 1].data.local == inst.data.local)
                    {
                        _ = out.pop();
                        changed = true;
                        i += 1;
                        continue;
                    }
                    const has_num_const_prev = out.items.len >= 1 and switch (out.items[out.items.len - 1].tag) {
                        .i32_const, .i64_const, .f32_const, .f64_const => true,
                        else => false,
                    };
                    var k: usize = i + 1;
                    var crossed_block = false;
                    while (k < insts.len) : (k += 1) {
                        if (insts[k].tag == .dbg_line) continue;
                        if (has_num_const_prev and insts[k].tag == .block and insts[k].data.block_type == .empty) {
                            crossed_block = true;
                            continue;
                        }
                        break;
                    }
                    if (k < insts.len and
                        insts[k].tag == .local_get and
                        inst.data.local == insts[k].data.local)
                    {
                        const local = inst.data.local;
                        const keep_set = isLocalReadBeforeOverwriteOrExit(insts, k + 1, local, k) or
                            (prev_is_ext_of_src != null and isF16ExtReadBeforeOverwriteOrExit(insts, k + 1, prev_is_ext_of_src.?));
                        if (crossed_block) {
                            const const_inst = out.pop().?;
                            if (keep_set) {
                                try recordLocalSet(gpa, &known_locals, local, const_inst);
                            } else {
                                invalidateLocal(&known_locals, local);
                            }
                            for (i + 1..k) |inter_idx| {
                                const inter_inst = insts[inter_idx];
                                if (inter_inst.tag == .block) {
                                    if (findMatchingEnd(insts, inter_idx) != null) {
                                        const cloned = try known_locals.clone(gpa);
                                        errdefer {
                                            var c = cloned;
                                            c.deinit(gpa);
                                        }
                                        try scope_stack.append(gpa, .{
                                            .start_idx = inter_idx,
                                            .entry_known = cloned,
                                        });
                                    } else {
                                        known_locals.clearRetainingCapacity();
                                    }
                                }
                                out.appendAssumeCapacity(inter_inst);
                            }
                            out.appendAssumeCapacity(const_inst);
                            if (keep_set) {
                                out.appendAssumeCapacity(.{ .tag = .local_tee, .data = .{ .local = local } });
                            }
                        } else {
                            const val_inst: ?Inst = if (out.items.len >= 1) out.items[out.items.len - 1] else null;
                            if (keep_set) {
                                out.appendAssumeCapacity(.{ .tag = .local_tee, .data = .{ .local = local } });
                                try recordLocalSet(gpa, &known_locals, local, val_inst);
                                if (prev_is_ext_of_src) |src_l| {
                                    try f16_ext_locals.put(gpa, src_l, local);
                                }
                            } else {
                                invalidateLocal(&known_locals, local);
                            }
                            for (insts[i + 1 .. k]) |dbg_inst| {
                                out.appendAssumeCapacity(dbg_inst);
                            }
                        }
                        changed = true;
                        i = k + 1;
                        continue;
                    }
                    if (!crossed_block and k < insts.len and
                        isPureZeroPopOrSimdConst(insts[k], mir_extra) and
                        !(insts[k].tag == .local_get and insts[k].data.local == inst.data.local))
                    {
                        var k2 = k + 1;
                        while (k2 < insts.len and insts[k2].tag == .dbg_line) : (k2 += 1) {}
                        var unary_idx: ?usize = null;
                        if (k2 < insts.len and pureNonTrappingInstPops(insts[k2], mir_extra) == 1) {
                            unary_idx = k2;
                            k2 += 1;
                            while (k2 < insts.len and insts[k2].tag == .dbg_line) : (k2 += 1) {}
                        }
                        if (k2 < insts.len and
                            insts[k2].tag == .local_get and
                            insts[k2].data.local == inst.data.local and
                            !isLocalReadBeforeOverwriteOrExit(insts, k2 + 1, inst.data.local, k2))
                        {
                            if (findPureValStartIndex(out.items, mir_extra)) |rhs_start| {
                                const raw_x = insts[k];
                                const x_inst: Inst = if (raw_x.tag == .local_get)
                                    known_locals.get(raw_x.data.local) orelse raw_x
                                else
                                    raw_x;
                                const can_move = switch (x_inst.tag) {
                                    .local_get => x_inst.data.local != inst.data.local and
                                        !isLocalModifiedInSpan(out.items[rhs_start..], x_inst.data.local),
                                    else => true,
                                };
                                if (can_move) {
                                    if (unary_idx) |u_idx| {
                                        if (x_inst.tag == .local_get and isExtendHfSf2(insts[u_idx])) {
                                            if (f16_ext_locals.get(x_inst.data.local)) |ext_local| {
                                                if (ext_local != inst.data.local and
                                                    !isLocalModifiedInSpan(out.items[rhs_start..], ext_local))
                                                {
                                                    try out.insert(gpa, rhs_start, .{ .tag = .local_get, .data = .{ .local = ext_local } });
                                                    invalidateLocal(&known_locals, inst.data.local);
                                                    for (insts[i + 1 .. k2]) |inter_inst| {
                                                        if (inter_inst.tag == .dbg_line) {
                                                            out.appendAssumeCapacity(inter_inst);
                                                        }
                                                    }
                                                    changed = true;
                                                    i = k2 + 1;
                                                    continue;
                                                }
                                            }
                                        }
                                        try out.insertSlice(gpa, rhs_start, &.{ x_inst, insts[u_idx] });
                                    } else {
                                        try out.insert(gpa, rhs_start, x_inst);
                                    }
                                    invalidateLocal(&known_locals, inst.data.local);
                                    for (insts[i + 1 .. k2]) |inter_inst| {
                                        if (inter_inst.tag == .dbg_line) {
                                            out.appendAssumeCapacity(inter_inst);
                                        }
                                    }
                                    changed = true;
                                    i = k2 + 1;
                                    continue;
                                }
                            }
                        }
                    }
                    if (out.items.len >= 1 and
                        isPureZeroPopTag(out.items[out.items.len - 1].tag) and
                        !isLocalReadBeforeOverwriteOrExit(insts, i + 1, inst.data.local, null))
                    {
                        _ = out.pop();
                        invalidateLocal(&known_locals, inst.data.local);
                        changed = true;
                        i += 1;
                        continue;
                    }
                    const prev_inst: ?Inst = if (out.items.len >= 1) out.items[out.items.len - 1] else null;
                    try recordLocalSet(gpa, &known_locals, inst.data.local, prev_inst);
                    if (prev_is_ext_of_src) |src_l| {
                        try f16_ext_locals.put(gpa, src_l, inst.data.local);
                    }
                }
                if (inst.tag == .local_tee) {
                    const local = inst.data.local;
                    const prev_is_ext_of_src: ?u32 = if (out.items.len >= 2 and
                        out.items[out.items.len - 2].tag == .local_get and
                        isExtendHfSf2(out.items[out.items.len - 1]) and
                        out.items[out.items.len - 2].data.local != local)
                        out.items[out.items.len - 2].data.local
                    else
                        null;
                    invalidateF16ExtLocal(&f16_ext_locals, local);
                    const keep_tee = isLocalReadBeforeOverwriteOrExit(insts, i + 1, local, null) or
                        (prev_is_ext_of_src != null and isF16ExtReadBeforeOverwriteOrExit(insts, i + 1, prev_is_ext_of_src.?));
                    if (!keep_tee) {
                        invalidateLocal(&known_locals, local);
                        changed = true;
                        i += 1;
                        continue;
                    }
                    const prev_inst: ?Inst = if (out.items.len >= 1) out.items[out.items.len - 1] else null;
                    try recordLocalSet(gpa, &known_locals, local, prev_inst);
                    if (prev_is_ext_of_src) |src_l| {
                        try f16_ext_locals.put(gpa, src_l, local);
                    }
                }
                out.appendAssumeCapacity(inst);
                i += 1;
            }
            return changed;
        }

        fn pureNonTrappingPops(tag: Inst.Tag) ?i32 {
            return switch (tag) {
                .i32_const,
                .i64_const,
                .f32_const,
                .f64_const,
                .local_get,
                .uav_ref,
                .uav_ref_off,
                .nav_ref,
                .nav_ref_off,
                .func_ref,
                .tls_nav_ref,
                .errors_len,
                .error_name_table_ref,
                .enum_tag_name_table_ref,
                => 0,

                .i32_eqz,
                .i64_eqz,
                .i32_clz,
                .i32_ctz,
                .i32_popcnt,
                .i64_clz,
                .i64_ctz,
                .i64_popcnt,
                .f32_abs,
                .f32_neg,
                .f32_ceil,
                .f32_floor,
                .f32_trunc,
                .f32_nearest,
                .f32_sqrt,
                .f64_abs,
                .f64_neg,
                .f64_ceil,
                .f64_floor,
                .f64_trunc,
                .f64_nearest,
                .f64_sqrt,
                .i32_wrap_i64,
                .i64_extend_i32_s,
                .i64_extend_i32_u,
                .f32_convert_i32_s,
                .f32_convert_i32_u,
                .f32_convert_i64_s,
                .f32_convert_i64_u,
                .f32_demote_f64,
                .f64_convert_i32_s,
                .f64_convert_i32_u,
                .f64_convert_i64_s,
                .f64_convert_i64_u,
                .f64_promote_f32,
                .i32_reinterpret_f32,
                .i64_reinterpret_f64,
                .f32_reinterpret_i32,
                .f64_reinterpret_i64,
                .i32_extend8_s,
                .i32_extend16_s,
                .i64_extend8_s,
                .i64_extend16_s,
                .i64_extend32_s,
                => 1,

                .i32_eq,
                .i32_ne,
                .i32_lt_s,
                .i32_lt_u,
                .i32_gt_s,
                .i32_gt_u,
                .i32_le_s,
                .i32_le_u,
                .i32_ge_s,
                .i32_ge_u,
                .i64_eq,
                .i64_ne,
                .i64_lt_s,
                .i64_lt_u,
                .i64_gt_s,
                .i64_gt_u,
                .i64_le_s,
                .i64_le_u,
                .i64_ge_s,
                .i64_ge_u,
                .f32_eq,
                .f32_ne,
                .f32_lt,
                .f32_gt,
                .f32_le,
                .f32_ge,
                .f64_eq,
                .f64_ne,
                .f64_lt,
                .f64_gt,
                .f64_le,
                .f64_ge,
                .i32_add,
                .i32_sub,
                .i32_mul,
                .i32_and,
                .i32_or,
                .i32_xor,
                .i32_shl,
                .i32_shr_s,
                .i32_shr_u,
                .i32_rotl,
                .i32_rotr,
                .i64_add,
                .i64_sub,
                .i64_mul,
                .i64_and,
                .i64_or,
                .i64_xor,
                .i64_shl,
                .i64_shr_s,
                .i64_shr_u,
                .i64_rotl,
                .i64_rotr,
                .f32_add,
                .f32_sub,
                .f32_mul,
                .f32_div,
                .f32_min,
                .f32_max,
                .f32_copysign,
                .f64_add,
                .f64_sub,
                .f64_mul,
                .f64_div,
                .f64_min,
                .f64_max,
                .f64_copysign,
                => 2,

                .select => 3,

                else => null,
            };
        }

        fn isLocalModifiedInSpan(span: []const Inst, local: u32) bool {
            for (span) |inst| {
                switch (inst.tag) {
                    .local_set, .local_tee => {
                        if (inst.data.local == local) return true;
                    },
                    else => {},
                }
            }
            return false;
        }

        fn hoistLoopInvariantLocalSets(
            gpa: Allocator,
            insts: []const Inst,
            out: *std.ArrayList(Inst),
        ) Allocator.Error!bool {
            out.clearRetainingCapacity();
            try out.ensureTotalCapacity(gpa, insts.len);

            const StmtSpan = struct {
                start: usize,
                end: usize,
                hoist: bool,
                target_local: u32,
            };
            var prefix_stmts: std.ArrayList(StmtSpan) = .empty;
            defer prefix_stmts.deinit(gpa);

            var changed = false;
            var i: usize = 0;
            while (i < insts.len) {
                const inst = insts[i];
                if (inst.tag == .loop) {
                    if (findMatchingEnd(insts, i)) |end_idx| {
                        prefix_stmts.clearRetainingCapacity();
                        var cursor: usize = i + 1;
                        var any_hoisted = false;

                        while (cursor < end_idx) {
                            while (cursor < end_idx and insts[cursor].tag == .dbg_line) : (cursor += 1) {}
                            if (cursor >= end_idx) break;

                            const stmt_start = cursor;
                            var stack_height: i32 = 0;
                            var k: usize = stmt_start;
                            var found_set = false;
                            while (k < end_idx) {
                                const cur = insts[k];
                                if (cur.tag == .dbg_line) {
                                    k += 1;
                                    continue;
                                }
                                if (cur.tag == .local_set and stack_height == 1) {
                                    found_set = true;
                                    break;
                                }
                                const pops = pureNonTrappingPops(cur.tag) orelse
                                    (if (cur.tag == .call_intrinsic) pureScalarIntrinsicPops(cur.data.intrinsic) else null) orelse break;
                                if (stack_height < pops) break;
                                stack_height = stack_height - pops + 1;
                                k += 1;
                            }
                            if (!found_set) break;

                            const target_local = insts[k].data.local;
                            var can_hoist = true;

                            // 1. `target_local` must be written only once in `insts[i + 1 .. end_idx]` (at `k`)
                            //    and never read before `k` inside the loop.
                            for (i + 1..end_idx) |m| {
                                if (m == k) continue;
                                const m_inst = insts[m];
                                if ((m_inst.tag == .local_set or m_inst.tag == .local_tee) and m_inst.data.local == target_local) {
                                    can_hoist = false;
                                    break;
                                }
                                if (m < k and m_inst.tag == .local_get and m_inst.data.local == target_local) {
                                    can_hoist = false;
                                    break;
                                }
                            }

                            // 2. Every `local_get Y` in `<val_expr>` must have `Y != target_local` and `Y`
                            //    never modified in `insts[i + 1 .. end_idx]` (unless `Y` was already hoisted).
                            if (can_hoist) {
                                for (stmt_start..k) |m| {
                                    const m_inst = insts[m];
                                    if (m_inst.tag == .local_get) {
                                        const y = m_inst.data.local;
                                        if (y == target_local) {
                                            can_hoist = false;
                                            break;
                                        }
                                        var y_hoisted = false;
                                        for (prefix_stmts.items) |prev_stmt| {
                                            if (prev_stmt.hoist and prev_stmt.target_local == y) {
                                                y_hoisted = true;
                                                break;
                                            }
                                        }
                                        if (!y_hoisted and isLocalModifiedInSpan(insts[i + 1 .. end_idx], y)) {
                                            can_hoist = false;
                                            break;
                                        }
                                    }
                                }
                            }

                            try prefix_stmts.append(gpa, .{
                                .start = stmt_start,
                                .end = k + 1,
                                .hoist = can_hoist,
                                .target_local = target_local,
                            });
                            if (can_hoist) any_hoisted = true;
                            cursor = k + 1;
                        }

                        if (any_hoisted) {
                            // Emit hoisted statements before `.loop`
                            for (prefix_stmts.items) |stmt| {
                                if (stmt.hoist) {
                                    for (insts[stmt.start..stmt.end]) |h_inst| {
                                        if (h_inst.tag != .dbg_line) {
                                            out.appendAssumeCapacity(h_inst);
                                        }
                                    }
                                }
                            }
                            // Emit `.loop`
                            out.appendAssumeCapacity(inst);
                            // Emit non-hoisted prefix instructions and leading `.dbg_line`s
                            var prev_end: usize = i + 1;
                            for (prefix_stmts.items) |stmt| {
                                for (insts[prev_end..stmt.start]) |d_inst| {
                                    out.appendAssumeCapacity(d_inst);
                                }
                                if (!stmt.hoist) {
                                    for (insts[stmt.start..stmt.end]) |u_inst| {
                                        out.appendAssumeCapacity(u_inst);
                                    }
                                }
                                prev_end = stmt.end;
                            }
                            changed = true;
                            i = prev_end;
                            continue;
                        }
                    }
                }
                out.appendAssumeCapacity(inst);
                i += 1;
            }
            return changed;
        }

        const ShiftPlusMinusOne = struct {
            shift: u6,
            is_add: bool,
        };

        fn matchShiftPlusMinusOne(c: u64, max_shift: u6) ?ShiftPlusMinusOne {
            if (c <= 2 or std.math.isPowerOfTwo(c)) return null;
            if (std.math.isPowerOfTwo(c - 1)) {
                const k = @ctz(c - 1);
                if (k >= 1 and k <= max_shift) {
                    return .{ .shift = @intCast(k), .is_add = true };
                }
            }
            if (c < std.math.maxInt(u64) and std.math.isPowerOfTwo(c + 1)) {
                const k = @ctz(c + 1);
                if (k >= 2 and k <= max_shift) {
                    return .{ .shift = @intCast(k), .is_add = false };
                }
            }
            return null;
        }

        fn instEquals(a: Inst, b: Inst, mir_extra: []const u32) bool {
            if (a.tag != b.tag) return false;
            return switch (a.tag) {
                .local_get, .local_set, .local_tee => a.data.local == b.data.local,
                .i32_const => a.data.imm32 == b.data.imm32,
                .f32_const => @as(u32, @bitCast(a.data.float32)) == @as(u32, @bitCast(b.data.float32)),
                .i64_const, .f64_const => readImm64(mir_extra, a.data.payload) == readImm64(mir_extra, b.data.payload),
                .global_get,
                .uav_ref,
                .uav_ref_off,
                .nav_ref,
                .nav_ref_off,
                .func_ref,
                .tls_nav_ref,
                .enum_tag_name_table_ref,
                => a.data.payload == b.data.payload,
                .errors_len, .error_name_table_ref => true,
                else => false,
            };
        }

        fn possibleOnesI32(expr: []const Inst, mir_extra: []const u32) u32 {
            const last_idx = prevNonDbgIndex(expr, expr.len) orelse return std.math.maxInt(u32);
            const last = expr[last_idx];
            return switch (last.tag) {
                .i32_const => @bitCast(last.data.imm32),
                .i32_load8_u => 0xFF,
                .i32_load16_u => 0xFFFF,
                .i32_wrap_i64 => @truncate(possibleOnesI64(expr[0..last_idx], mir_extra)),
                .i32_and, .i32_or, .i32_xor => blk: {
                    const rhs_start = findValStartIndex(expr[0..last_idx], mir_extra) orelse break :blk std.math.maxInt(u32);
                    const lhs_ones = possibleOnesI32(expr[0..rhs_start], mir_extra);
                    const rhs_ones = possibleOnesI32(expr[rhs_start..last_idx], mir_extra);
                    break :blk switch (last.tag) {
                        .i32_and => lhs_ones & rhs_ones,
                        .i32_or, .i32_xor => lhs_ones | rhs_ones,
                        else => unreachable,
                    };
                },
                .i32_shr_u => blk: {
                    const c_idx = prevNonDbgIndex(expr, last_idx) orelse break :blk std.math.maxInt(u32);
                    if (expr[c_idx].tag != .i32_const) break :blk std.math.maxInt(u32);
                    const shift_amt: u5 = @truncate(@as(u32, @bitCast(expr[c_idx].data.imm32)));
                    const lhs_ones = possibleOnesI32(expr[0..c_idx], mir_extra);
                    break :blk lhs_ones >> shift_amt;
                },
                .i32_shl => blk: {
                    const c_idx = prevNonDbgIndex(expr, last_idx) orelse break :blk std.math.maxInt(u32);
                    if (expr[c_idx].tag != .i32_const) break :blk std.math.maxInt(u32);
                    const shift_amt: u5 = @truncate(@as(u32, @bitCast(expr[c_idx].data.imm32)));
                    const lhs_ones = possibleOnesI32(expr[0..c_idx], mir_extra);
                    break :blk lhs_ones << shift_amt;
                },
                .select => blk: {
                    const cond_start = findValStartIndex(expr[0..last_idx], mir_extra) orelse break :blk std.math.maxInt(u32);
                    const op2_start = findValStartIndex(expr[0..cond_start], mir_extra) orelse break :blk std.math.maxInt(u32);
                    const op1_ones = possibleOnesI32(expr[0..op2_start], mir_extra);
                    const op2_ones = possibleOnesI32(expr[op2_start..cond_start], mir_extra);
                    break :blk op1_ones | op2_ones;
                },
                .call_intrinsic => switch (last.data.intrinsic) {
                    .__truncsfhf2,
                    .__trunctfhf2,
                    .__truncxfhf2,
                    => 0xFFFF,
                    else => std.math.maxInt(u32),
                },
                else => if (isBoolProducerTag(last.tag)) 1 else std.math.maxInt(u32),
            };
        }

        fn possibleOnesI64(expr: []const Inst, mir_extra: []const u32) u64 {
            const last_idx = prevNonDbgIndex(expr, expr.len) orelse return std.math.maxInt(u64);
            const last = expr[last_idx];
            return switch (last.tag) {
                .i64_const => readImm64(mir_extra, last.data.payload),
                .i64_load8_u => 0xFF,
                .i64_load16_u => 0xFFFF,
                .i64_load32_u => 0xFFFF_FFFF,
                .i64_extend_i32_u => @as(u64, possibleOnesI32(expr[0..last_idx], mir_extra)),
                .i64_and, .i64_or, .i64_xor => blk: {
                    const rhs_start = findValStartIndex(expr[0..last_idx], mir_extra) orelse break :blk std.math.maxInt(u64);
                    const lhs_ones = possibleOnesI64(expr[0..rhs_start], mir_extra);
                    const rhs_ones = possibleOnesI64(expr[rhs_start..last_idx], mir_extra);
                    break :blk switch (last.tag) {
                        .i64_and => lhs_ones & rhs_ones,
                        .i64_or, .i64_xor => lhs_ones | rhs_ones,
                        else => unreachable,
                    };
                },
                .i64_shr_u => blk: {
                    const c_idx = prevNonDbgIndex(expr, last_idx) orelse break :blk std.math.maxInt(u64);
                    if (expr[c_idx].tag != .i64_const) break :blk std.math.maxInt(u64);
                    const shift_amt: u6 = @truncate(readImm64(mir_extra, expr[c_idx].data.payload));
                    const lhs_ones = possibleOnesI64(expr[0..c_idx], mir_extra);
                    break :blk lhs_ones >> shift_amt;
                },
                .i64_shl => blk: {
                    const c_idx = prevNonDbgIndex(expr, last_idx) orelse break :blk std.math.maxInt(u64);
                    if (expr[c_idx].tag != .i64_const) break :blk std.math.maxInt(u64);
                    const shift_amt: u6 = @truncate(readImm64(mir_extra, expr[c_idx].data.payload));
                    const lhs_ones = possibleOnesI64(expr[0..c_idx], mir_extra);
                    break :blk lhs_ones << shift_amt;
                },
                .select => blk: {
                    const cond_start = findValStartIndex(expr[0..last_idx], mir_extra) orelse break :blk std.math.maxInt(u64);
                    const op2_start = findValStartIndex(expr[0..cond_start], mir_extra) orelse break :blk std.math.maxInt(u64);
                    const op1_ones = possibleOnesI64(expr[0..op2_start], mir_extra);
                    const op2_ones = possibleOnesI64(expr[op2_start..cond_start], mir_extra);
                    break :blk op1_ones | op2_ones;
                },
                else => std.math.maxInt(u64),
            };
        }

        fn emitSignedDivByConstI32(
            gpa: Allocator,
            out: *std.ArrayList(Inst),
            mir_extra: *std.ArrayList(u32),
            local: u32,
            d_s: i32,
        ) Allocator.Error!void {
            assert(d_s > 1);
            const d: u32 = @bitCast(d_s);
            if (std.math.isPowerOfTwo(d)) {
                const k: i32 = @intCast(@ctz(d));
                out.appendAssumeCapacity(.{ .tag = .local_get, .data = .{ .local = local } });
                out.appendAssumeCapacity(makeI32Const(31));
                out.appendAssumeCapacity(.{ .tag = .i32_shr_s, .data = .{ .tag = {} } });
                out.appendAssumeCapacity(makeI32Const(32 - k));
                out.appendAssumeCapacity(.{ .tag = .i32_shr_u, .data = .{ .tag = {} } });
                out.appendAssumeCapacity(.{ .tag = .i32_add, .data = .{ .tag = {} } });
                out.appendAssumeCapacity(makeI32Const(k));
                out.appendAssumeCapacity(.{ .tag = .i32_shr_s, .data = .{ .tag = {} } });
            } else {
                const l: u6 = @intCast(32 - @clz(d - 1));
                const shift: u7 = 31 + @as(u7, l);
                const m: u64 = @intCast(((@as(u128, 1) << shift) / @as(u128, d)) + 1);
                const m_inst = try makeI64Const(gpa, mir_extra, m);
                const shift_inst = try makeI64Const(gpa, mir_extra, shift);
                out.appendAssumeCapacity(.{ .tag = .i64_extend_i32_s, .data = .{ .tag = {} } });
                out.appendAssumeCapacity(m_inst);
                out.appendAssumeCapacity(.{ .tag = .i64_mul, .data = .{ .tag = {} } });
                out.appendAssumeCapacity(shift_inst);
                out.appendAssumeCapacity(.{ .tag = .i64_shr_s, .data = .{ .tag = {} } });
                out.appendAssumeCapacity(.{ .tag = .i32_wrap_i64, .data = .{ .tag = {} } });
                out.appendAssumeCapacity(.{ .tag = .local_get, .data = .{ .local = local } });
                out.appendAssumeCapacity(makeI32Const(31));
                out.appendAssumeCapacity(.{ .tag = .i32_shr_u, .data = .{ .tag = {} } });
                out.appendAssumeCapacity(.{ .tag = .i32_add, .data = .{ .tag = {} } });
            }
        }

        fn emitUnsignedDivByConstI32(
            gpa: Allocator,
            out: *std.ArrayList(Inst),
            mir_extra: *std.ArrayList(u32),
            d: u32,
            numerator_local: ?u32,
        ) Allocator.Error!bool {
            assert(d > 1 and !std.math.isPowerOfTwo(d));
            const l: u5 = @intCast(31 - @clz(d));
            const shift_low: u6 = 32 + @as(u6, l);
            const two_pow_32_plus_l: u128 = @as(u128, 1) << shift_low;
            const m_low_128: u128 = (two_pow_32_plus_l / @as(u128, d)) + 1;
            if ((m_low_128 * @as(u128, d) - two_pow_32_plus_l) <= (@as(u128, 1) << l) and
                m_low_128 < (@as(u128, 1) << 32))
            {
                const m_low: u64 = @intCast(m_low_128);
                const m_inst = try makeI64Const(gpa, mir_extra, m_low);
                const shift_inst = try makeI64Const(gpa, mir_extra, shift_low);
                out.appendAssumeCapacity(.{ .tag = .i64_extend_i32_u, .data = .{ .tag = {} } });
                out.appendAssumeCapacity(m_inst);
                out.appendAssumeCapacity(.{ .tag = .i64_mul, .data = .{ .tag = {} } });
                out.appendAssumeCapacity(shift_inst);
                out.appendAssumeCapacity(.{ .tag = .i64_shr_u, .data = .{ .tag = {} } });
                out.appendAssumeCapacity(.{ .tag = .i32_wrap_i64, .data = .{ .tag = {} } });
                return true;
            }
            const x_local = numerator_local orelse return false;
            const s: u6 = @as(u6, l) + 1;
            const shift_high: u7 = 32 + @as(u7, s);
            const m_full: u128 = ((@as(u128, 1) << shift_high) / @as(u128, d)) + 1;
            const m_prime: u64 = @intCast(m_full - (@as(u128, 1) << 32));
            const m_prime_inst = try makeI64Const(gpa, mir_extra, m_prime);
            const c32_inst = try makeI64Const(gpa, mir_extra, 32);
            const s_inst = try makeI64Const(gpa, mir_extra, s);
            out.appendAssumeCapacity(.{ .tag = .i64_extend_i32_u, .data = .{ .tag = {} } });
            out.appendAssumeCapacity(m_prime_inst);
            out.appendAssumeCapacity(.{ .tag = .i64_mul, .data = .{ .tag = {} } });
            out.appendAssumeCapacity(c32_inst);
            out.appendAssumeCapacity(.{ .tag = .i64_shr_u, .data = .{ .tag = {} } });
            out.appendAssumeCapacity(.{ .tag = .local_get, .data = .{ .local = x_local } });
            out.appendAssumeCapacity(.{ .tag = .i64_extend_i32_u, .data = .{ .tag = {} } });
            out.appendAssumeCapacity(.{ .tag = .i64_add, .data = .{ .tag = {} } });
            out.appendAssumeCapacity(s_inst);
            out.appendAssumeCapacity(.{ .tag = .i64_shr_u, .data = .{ .tag = {} } });
            out.appendAssumeCapacity(.{ .tag = .i32_wrap_i64, .data = .{ .tag = {} } });
            return true;
        }

        fn foldConstants(
            gpa: Allocator,
            insts: []const Inst,
            out: *std.ArrayList(Inst),
            mir_extra: *std.ArrayList(u32),
        ) Allocator.Error!bool {
            out.clearRetainingCapacity();
            try out.ensureTotalCapacity(gpa, insts.len);

            var changed = false;

            for (insts) |inst| {
                try out.ensureUnusedCapacity(gpa, 16);
                const len = out.items.len;

                // Constant drop: `<const>, .drop` -> remove both
                if (inst.tag == .drop and len >= 1 and isConstTag(out.items[len - 1].tag)) {
                    _ = out.pop();
                    changed = true;
                    continue;
                }
                // Dead pure 1-pop scalar intrinsic drop: `<pure_0pop>; call_intrinsic <1pop_pure>; drop` -> remove all 3
                if (inst.tag == .drop and len >= 2 and
                    out.items[len - 1].tag == .call_intrinsic and
                    pureScalarIntrinsicPops(out.items[len - 1].data.intrinsic) == 1 and
                    isPureZeroPopTag(out.items[len - 2].tag))
                {
                    out.items.len = len - 2;
                    changed = true;
                    continue;
                }

                // Constant select: `<const1>, <const2>, .i32_const cond, .select` -> `<const1>` or `<const2>`
                if (inst.tag == .select and len >= 3) {
                    const c1 = out.items[len - 3];
                    const c2 = out.items[len - 2];
                    const cond = out.items[len - 1];
                    if (cond.tag == .i32_const and isConstTag(c1.tag) and
                        (c1.tag == c2.tag or (isPtrRefTag(c1.tag) and isPtrRefTag(c2.tag))))
                    {
                        const chosen = if (cond.data.imm32 != 0) c1 else c2;
                        out.items.len = len - 2;
                        out.items[len - 3] = chosen;
                        changed = true;
                        continue;
                    }
                    // `select(a, a, cond) -> a` when `a == b` and `cond` are pure zero-pop instructions
                    if (isPureZeroPopTag(c1.tag) and isPureZeroPopTag(c2.tag) and isPureZeroPopTag(cond.tag) and
                        instEquals(c1, c2, mir_extra.items))
                    {
                        out.items.len = len - 2;
                        changed = true;
                        continue;
                    }
                }

                // Select condition normalization:
                // `<cond>; i32_const 0; i32_ne; select` -> `<cond>; select`
                // `<cond>; i32_eqz; i32_eqz; select` -> `<cond>; select`
                if (inst.tag == .select and len >= 2) {
                    if ((out.items[len - 2].tag == .i32_const and out.items[len - 2].data.imm32 == 0 and out.items[len - 1].tag == .i32_ne) or
                        (out.items[len - 2].tag == .i32_eqz and out.items[len - 1].tag == .i32_eqz))
                    {
                        out.items.len = len - 2;
                        out.appendAssumeCapacity(inst);
                        changed = true;
                        continue;
                    }
                    // `select(a, b, i32_eqz(c)) -> select(b, a, c)` when `a` and `b` are pure zero-pop instructions
                    if (out.items[len - 1].tag == .i32_eqz) {
                        if (findValStartIndex(out.items[0 .. len - 1], mir_extra.items)) |c_start| {
                            if (c_start >= 2) {
                                const a = out.items[c_start - 2];
                                const b = out.items[c_start - 1];
                                if (isPureZeroPopTag(a.tag) and isPureZeroPopTag(b.tag)) {
                                    out.items[c_start - 2] = b;
                                    out.items[c_start - 1] = a;
                                    out.items[len - 1] = inst;
                                    changed = true;
                                    continue;
                                }
                            }
                        }
                    }
                }

                // Conversion, sign-extension, and float unary idempotents
                if (len >= 1) {
                    const prev = out.items[len - 1];
                    switch (inst.tag) {
                        .i32_wrap_i64 => {
                            if (prev.tag == .i64_extend_i32_s or prev.tag == .i64_extend_i32_u) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                        },
                        .i32_extend8_s => {
                            if (prev.tag == .i32_load8_u) {
                                out.items[len - 1].tag = .i32_load8_s;
                                changed = true;
                                continue;
                            }
                            if (prev.tag == .i32_load8_s or prev.tag == .i32_extend8_s) {
                                changed = true;
                                continue;
                            }
                        },
                        .i32_extend16_s => {
                            if (prev.tag == .i32_load16_u) {
                                out.items[len - 1].tag = .i32_load16_s;
                                changed = true;
                                continue;
                            }
                            if (prev.tag == .i32_load16_s or prev.tag == .i32_extend16_s or
                                prev.tag == .i32_load8_s or prev.tag == .i32_extend8_s)
                            {
                                changed = true;
                                continue;
                            }
                        },
                        .i64_extend8_s => {
                            if (prev.tag == .i64_load8_u) {
                                out.items[len - 1].tag = .i64_load8_s;
                                changed = true;
                                continue;
                            }
                            if (prev.tag == .i64_load8_s or prev.tag == .i64_extend8_s) {
                                changed = true;
                                continue;
                            }
                        },
                        .i64_extend16_s => {
                            if (prev.tag == .i64_load16_u) {
                                out.items[len - 1].tag = .i64_load16_s;
                                changed = true;
                                continue;
                            }
                            if (prev.tag == .i64_load16_s or prev.tag == .i64_extend16_s or
                                prev.tag == .i64_load8_s or prev.tag == .i64_extend8_s)
                            {
                                changed = true;
                                continue;
                            }
                        },
                        .i64_extend32_s => {
                            if (prev.tag == .i64_load32_u) {
                                out.items[len - 1].tag = .i64_load32_s;
                                changed = true;
                                continue;
                            }
                            if (prev.tag == .i64_load32_s or prev.tag == .i64_extend32_s or
                                prev.tag == .i64_load16_s or prev.tag == .i64_extend16_s or
                                prev.tag == .i64_load8_s or prev.tag == .i64_extend8_s or
                                prev.tag == .i64_extend_i32_s)
                            {
                                changed = true;
                                continue;
                            }
                        },
                        .i64_eqz => {
                            if (prev.tag == .i64_xor) {
                                out.items[len - 1].tag = .i64_eq;
                                changed = true;
                                continue;
                            }
                        },
                        .f32_abs => {
                            if (prev.tag == .f32_abs or prev.tag == .f32_neg) {
                                out.items[len - 1].tag = .f32_abs;
                                changed = true;
                                continue;
                            }
                        },
                        .f32_neg => {
                            if (prev.tag == .f32_neg) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                        },
                        .f64_abs => {
                            if (prev.tag == .f64_abs or prev.tag == .f64_neg) {
                                out.items[len - 1].tag = .f64_abs;
                                changed = true;
                                continue;
                            }
                        },
                        .f64_neg => {
                            if (prev.tag == .f64_neg) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                        },
                        .f32_demote_f64 => {
                            if (prev.tag == .f64_promote_f32) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                        },
                        .call_intrinsic => {
                            if (isTruncSfHf2(inst) and isExtendHfSf2(prev)) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                            if (isExtendHfSf2(inst) and prev.tag == .i32_const) {
                                const h_bits: u16 = @truncate(@as(u32, @bitCast(prev.data.imm32)));
                                const h: f16 = @bitCast(h_bits);
                                if (!std.math.isNan(h)) {
                                    const f: f32 = @floatCast(h);
                                    out.items[len - 1] = .{ .tag = .f32_const, .data = .{ .float32 = f } };
                                    changed = true;
                                    continue;
                                }
                            }
                            if (isTruncSfHf2(inst) and prev.tag == .f32_const) {
                                const f: f32 = prev.data.float32;
                                if (!std.math.isNan(f)) {
                                    const h: f16 = @floatCast(f);
                                    const h_bits: u16 = @bitCast(h);
                                    out.items[len - 1] = makeI32Const(@intCast(h_bits));
                                    changed = true;
                                    continue;
                                }
                            }
                        },
                        else => {},
                    }
                }

                // f32 unary ops preceded by `f32_const`
                if (len >= 1 and out.items[len - 1].tag == .f32_const) {
                    const v: f32 = out.items[len - 1].data.float32;
                    switch (inst.tag) {
                        .f32_abs => {
                            out.items[len - 1] = .{ .tag = .f32_const, .data = .{ .float32 = @abs(v) } };
                            changed = true;
                            continue;
                        },
                        .f32_neg => {
                            out.items[len - 1] = .{ .tag = .f32_const, .data = .{ .float32 = -v } };
                            changed = true;
                            continue;
                        },
                        .f32_ceil => if (!std.math.isNan(v)) {
                            out.items[len - 1] = .{ .tag = .f32_const, .data = .{ .float32 = @ceil(v) } };
                            changed = true;
                            continue;
                        },
                        .f32_floor => if (!std.math.isNan(v)) {
                            out.items[len - 1] = .{ .tag = .f32_const, .data = .{ .float32 = @floor(v) } };
                            changed = true;
                            continue;
                        },
                        .f32_trunc => if (!std.math.isNan(v)) {
                            out.items[len - 1] = .{ .tag = .f32_const, .data = .{ .float32 = @trunc(v) } };
                            changed = true;
                            continue;
                        },
                        .f32_sqrt => if (!std.math.isNan(v) and v >= 0.0) {
                            out.items[len - 1] = .{ .tag = .f32_const, .data = .{ .float32 = @sqrt(v) } };
                            changed = true;
                            continue;
                        },
                        .i32_reinterpret_f32 => {
                            out.items[len - 1] = makeI32Const(@bitCast(v));
                            changed = true;
                            continue;
                        },
                        else => {},
                    }
                }

                // f32 binary ops preceded by two `f32_const`
                if (len >= 2 and out.items[len - 2].tag == .f32_const and out.items[len - 1].tag == .f32_const) {
                    const lhs: f32 = out.items[len - 2].data.float32;
                    const rhs: f32 = out.items[len - 1].data.float32;
                    if (!std.math.isNan(lhs) and !std.math.isNan(rhs)) {
                        const folded_f32: ?f32 = switch (inst.tag) {
                            .f32_add => lhs + rhs,
                            .f32_sub => lhs - rhs,
                            .f32_mul => lhs * rhs,
                            .f32_div => lhs / rhs,
                            .f32_copysign => std.math.copysign(lhs, rhs),
                            else => null,
                        };
                        if (folded_f32) |res| {
                            if (!std.math.isNan(res)) {
                                out.items.len = len - 1;
                                out.items[len - 2] = .{ .tag = .f32_const, .data = .{ .float32 = res } };
                                changed = true;
                                continue;
                            }
                        }
                        const folded_cmp: ?i32 = switch (inst.tag) {
                            .f32_eq => if (lhs == rhs) 1 else 0,
                            .f32_ne => if (lhs != rhs) 1 else 0,
                            .f32_lt => if (lhs < rhs) 1 else 0,
                            .f32_gt => if (lhs > rhs) 1 else 0,
                            .f32_le => if (lhs <= rhs) 1 else 0,
                            .f32_ge => if (lhs >= rhs) 1 else 0,
                            else => null,
                        };
                        if (folded_cmp) |res_cmp| {
                            out.items.len = len - 1;
                            out.items[len - 2] = makeI32Const(res_cmp);
                            changed = true;
                            continue;
                        }
                    }
                }

                // Same-local `local_get L; local_get L; <op>` folds
                if (len >= 2 and out.items[len - 2].tag == .local_get and out.items[len - 1].tag == .local_get and
                    out.items[len - 2].data.local == out.items[len - 1].data.local)
                {
                    switch (inst.tag) {
                        .i32_sub, .i32_xor, .i32_ne, .i32_lt_s, .i32_lt_u, .i32_gt_s, .i32_gt_u,
                        .i64_ne, .i64_lt_s, .i64_lt_u, .i64_gt_s, .i64_gt_u,
                        => {
                            out.items.len = len - 1;
                            out.items[len - 2] = makeI32Const(0);
                            changed = true;
                            continue;
                        },
                        .i64_sub, .i64_xor => {
                            const zero = try makeI64Const(gpa, mir_extra, 0);
                            out.items.len = len - 1;
                            out.items[len - 2] = zero;
                            changed = true;
                            continue;
                        },
                        .i32_eq, .i32_le_s, .i32_le_u, .i32_ge_s, .i32_ge_u,
                        .i64_eq, .i64_le_s, .i64_le_u, .i64_ge_s, .i64_ge_u,
                        => {
                            out.items.len = len - 1;
                            out.items[len - 2] = makeI32Const(1);
                            changed = true;
                            continue;
                        },
                        .i32_and, .i32_or, .i64_and, .i64_or => {
                            out.items.len = len - 1;
                            changed = true;
                            continue;
                        },
                        else => {},
                    }
                }

                // i32 unary ops preceded by `i32_const`
                if (len >= 1 and out.items[len - 1].tag == .i32_const) {
                    const v: i32 = out.items[len - 1].data.imm32;
                    const v_u: u32 = @bitCast(v);
                    switch (inst.tag) {
                        .i32_eqz => {
                            out.items[len - 1] = makeI32Const(if (v == 0) 1 else 0);
                            changed = true;
                            continue;
                        },
                        .i32_clz => {
                            out.items[len - 1] = makeI32Const(@intCast(@clz(v_u)));
                            changed = true;
                            continue;
                        },
                        .i32_ctz => {
                            out.items[len - 1] = makeI32Const(@intCast(@ctz(v_u)));
                            changed = true;
                            continue;
                        },
                        .i32_popcnt => {
                            out.items[len - 1] = makeI32Const(@intCast(@popCount(v_u)));
                            changed = true;
                            continue;
                        },
                        .i32_extend8_s => {
                            out.items[len - 1] = makeI32Const(@as(i8, @truncate(v)));
                            changed = true;
                            continue;
                        },
                        .i32_extend16_s => {
                            out.items[len - 1] = makeI32Const(@as(i16, @truncate(v)));
                            changed = true;
                            continue;
                        },
                        .i64_extend_i32_s => {
                            out.items[len - 1] = try makeI64Const(gpa, mir_extra, @bitCast(@as(i64, v)));
                            changed = true;
                            continue;
                        },
                        .i64_extend_i32_u => {
                            out.items[len - 1] = try makeI64Const(gpa, mir_extra, @as(u64, v_u));
                            changed = true;
                            continue;
                        },
                        else => {},
                    }
                }

                if (inst.tag == .i32_eqz) {
                    if (emitOrFoldI32Eqz(out, mir_extra.items)) {
                        changed = true;
                    }
                    continue;
                }

                // i32 binary ops preceded by two `i32_const`
                if (len >= 2 and out.items[len - 2].tag == .i32_const and out.items[len - 1].tag == .i32_const) {
                    const lhs: i32 = out.items[len - 2].data.imm32;
                    const rhs: i32 = out.items[len - 1].data.imm32;
                    const lhs_u: u32 = @bitCast(lhs);
                    const rhs_u: u32 = @bitCast(rhs);
                    const shift_amt: u5 = @truncate(rhs_u);

                    const folded_i32: ?i32 = switch (inst.tag) {
                        .i32_add => lhs +% rhs,
                        .i32_sub => lhs -% rhs,
                        .i32_mul => lhs *% rhs,
                        .i32_div_u => if (rhs_u != 0) @bitCast(lhs_u / rhs_u) else null,
                        .i32_rem_u => if (rhs_u != 0) @bitCast(lhs_u % rhs_u) else null,
                        .i32_div_s => if (rhs != 0 and !(lhs == std.math.minInt(i32) and rhs == -1)) @divTrunc(lhs, rhs) else null,
                        .i32_rem_s => if (rhs != 0 and !(lhs == std.math.minInt(i32) and rhs == -1)) @rem(lhs, rhs) else null,
                        .i32_and => lhs & rhs,
                        .i32_or => lhs | rhs,
                        .i32_xor => lhs ^ rhs,
                        .i32_shl => @bitCast(lhs_u << shift_amt),
                        .i32_shr_s => lhs >> shift_amt,
                        .i32_shr_u => @bitCast(lhs_u >> shift_amt),
                        .i32_rotl => @bitCast(std.math.rotl(u32, lhs_u, shift_amt)),
                        .i32_rotr => @bitCast(std.math.rotr(u32, lhs_u, shift_amt)),
                        .i32_eq => if (lhs == rhs) 1 else 0,
                        .i32_ne => if (lhs != rhs) 1 else 0,
                        .i32_lt_s => if (lhs < rhs) 1 else 0,
                        .i32_lt_u => if (lhs_u < rhs_u) 1 else 0,
                        .i32_gt_s => if (lhs > rhs) 1 else 0,
                        .i32_gt_u => if (lhs_u > rhs_u) 1 else 0,
                        .i32_le_s => if (lhs <= rhs) 1 else 0,
                        .i32_le_u => if (lhs_u <= rhs_u) 1 else 0,
                        .i32_ge_s => if (lhs >= rhs) 1 else 0,
                        .i32_ge_u => if (lhs_u >= rhs_u) 1 else 0,
                        else => null,
                    };

                    if (folded_i32) |res| {
                        out.items.len = len - 1;
                        out.items[len - 2] = makeI32Const(res);
                        changed = true;
                        continue;
                    }
                }

                // i32 constant reassociation: `(x +- c1) +- c2 -> x + (d1 +% d2)` (or `x` if 0)
                if ((inst.tag == .i32_add or inst.tag == .i32_sub) and len >= 3 and
                    out.items[len - 1].tag == .i32_const and
                    (out.items[len - 2].tag == .i32_add or out.items[len - 2].tag == .i32_sub) and
                    out.items[len - 3].tag == .i32_const)
                {
                    const c1 = out.items[len - 3].data.imm32;
                    const c2 = out.items[len - 1].data.imm32;
                    const d1: i32 = if (out.items[len - 2].tag == .i32_add) c1 else 0 -% c1;
                    const d2: i32 = if (inst.tag == .i32_add) c2 else 0 -% c2;
                    const total: i32 = d1 +% d2;
                    if (total == 0) {
                        out.items.len = len - 3;
                    } else {
                        out.items[len - 3] = makeI32Const(total);
                        out.items[len - 2] = .{ .tag = .i32_add, .data = .{ .tag = {} } };
                        out.items.len = len - 1;
                    }
                    changed = true;
                    continue;
                }

                // i32 associative bitwise reassociation: `(x op c1) op c2 -> x op (c1 op c2)`
                if ((inst.tag == .i32_and or inst.tag == .i32_or or inst.tag == .i32_xor) and len >= 3 and
                    out.items[len - 1].tag == .i32_const and
                    out.items[len - 2].tag == inst.tag and
                    out.items[len - 3].tag == .i32_const)
                {
                    const c1 = out.items[len - 3].data.imm32;
                    const c2 = out.items[len - 1].data.imm32;
                    const combined: i32 = switch (inst.tag) {
                        .i32_and => c1 & c2,
                        .i32_or => c1 | c2,
                        .i32_xor => c1 ^ c2,
                        else => unreachable,
                    };
                    const is_identity = switch (inst.tag) {
                        .i32_and => combined == -1,
                        .i32_or, .i32_xor => combined == 0,
                        else => unreachable,
                    };
                    if (is_identity) {
                        out.items.len = len - 3;
                    } else {
                        out.items[len - 3] = makeI32Const(combined);
                        out.items.len = len - 1;
                    }
                    changed = true;
                    continue;
                }

                // i32 single-constant right-operand peepholes: `<x>; i32_const C; <op>`
                if (len >= 1 and out.items[len - 1].tag == .i32_const and
                    !(len >= 2 and out.items[len - 2].tag == .i32_const))
                {
                    const rhs: i32 = out.items[len - 1].data.imm32;
                    const rhs_u: u32 = @bitCast(rhs);
                    const shift_amt: u5 = @truncate(rhs_u);
                    switch (inst.tag) {
                        .i32_add, .i32_sub, .i32_or => {
                            if (rhs == 0) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                        },
                        .i32_xor => {
                            if (rhs == 0) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                            if (rhs == 1 and len >= 2 and isBoolProducerTag(out.items[len - 2].tag)) {
                                _ = out.pop();
                                _ = emitOrFoldI32Eqz(out, mir_extra.items);
                                changed = true;
                                continue;
                            }
                        },
                        .i32_and => {
                            const possible_ones = possibleOnesI32(out.items[0 .. len - 1], mir_extra.items);
                            if ((possible_ones & ~rhs_u) == 0) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                        },
                        .i32_shl, .i32_shr_s, .i32_shr_u, .i32_rotl, .i32_rotr => {
                            if (shift_amt == 0) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                        },
                        .i32_eq => {
                            if (rhs == 0) {
                                _ = out.pop();
                                _ = emitOrFoldI32Eqz(out, mir_extra.items);
                                changed = true;
                                continue;
                            }
                            if (rhs == 1 and len >= 2 and isBoolProducerTag(out.items[len - 2].tag)) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                        },
                        .i32_ne => {
                            if (rhs == 0 and len >= 2 and isBoolProducerTag(out.items[len - 2].tag)) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                            if (rhs == 1 and len >= 2 and isBoolProducerTag(out.items[len - 2].tag)) {
                                _ = out.pop();
                                _ = emitOrFoldI32Eqz(out, mir_extra.items);
                                changed = true;
                                continue;
                            }
                        },
                        .i32_mul => {
                            if (rhs == 1) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                            if (rhs_u > 1 and std.math.isPowerOfTwo(rhs_u)) {
                                out.items[len - 1] = makeI32Const(@intCast(@ctz(rhs_u)));
                                out.appendAssumeCapacity(.{ .tag = .i32_shl, .data = .{ .tag = {} } });
                                changed = true;
                                continue;
                            }
                            if (len >= 2 and (out.items[len - 2].tag == .local_get or out.items[len - 2].tag == .local_tee)) {
                                if (matchShiftPlusMinusOne(rhs_u, 31)) |spm| {
                                    const local = out.items[len - 2].data.local;
                                    out.items[len - 1] = makeI32Const(spm.shift);
                                    out.appendAssumeCapacity(.{ .tag = .i32_shl, .data = .{ .tag = {} } });
                                    out.appendAssumeCapacity(.{ .tag = .local_get, .data = .{ .local = local } });
                                    out.appendAssumeCapacity(.{ .tag = if (spm.is_add) .i32_add else .i32_sub, .data = .{ .tag = {} } });
                                    changed = true;
                                    continue;
                                }
                            }
                        },
                        .i32_div_s => {
                            if (rhs == 1) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                            if (rhs > 1 and len >= 2 and out.items[len - 2].tag == .local_get) {
                                const local = out.items[len - 2].data.local;
                                _ = out.pop();
                                try emitSignedDivByConstI32(gpa, out, mir_extra, local, rhs);
                                changed = true;
                                continue;
                            }
                        },
                        .i32_rem_s => {
                            if (rhs > 1 and len >= 2 and out.items[len - 2].tag == .local_get) {
                                const local = out.items[len - 2].data.local;
                                out.items[len - 1] = .{ .tag = .local_get, .data = .{ .local = local } };
                                try emitSignedDivByConstI32(gpa, out, mir_extra, local, rhs);
                                out.appendAssumeCapacity(makeI32Const(rhs));
                                out.appendAssumeCapacity(.{ .tag = .i32_mul, .data = .{ .tag = {} } });
                                out.appendAssumeCapacity(.{ .tag = .i32_sub, .data = .{ .tag = {} } });
                                changed = true;
                                continue;
                            }
                        },
                        .i32_div_u => {
                            if (rhs_u == 1) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                            if (rhs_u > 1 and std.math.isPowerOfTwo(rhs_u)) {
                                out.items[len - 1] = makeI32Const(@intCast(@ctz(rhs_u)));
                                out.appendAssumeCapacity(.{ .tag = .i32_shr_u, .data = .{ .tag = {} } });
                                changed = true;
                                continue;
                            }
                            if (rhs_u > 1 and !std.math.isPowerOfTwo(rhs_u)) {
                                const num_local: ?u32 = if (len >= 2 and out.items[len - 2].tag == .local_get)
                                    out.items[len - 2].data.local
                                else
                                    null;
                                _ = out.pop();
                                if (try emitUnsignedDivByConstI32(gpa, out, mir_extra, rhs_u, num_local)) {
                                    changed = true;
                                    continue;
                                }
                                out.appendAssumeCapacity(makeI32Const(rhs));
                            }
                        },
                        .i32_rem_u => {
                            if (rhs_u >= 1 and std.math.isPowerOfTwo(rhs_u)) {
                                out.items[len - 1] = makeI32Const(@bitCast(rhs_u - 1));
                                out.appendAssumeCapacity(.{ .tag = .i32_and, .data = .{ .tag = {} } });
                                changed = true;
                                continue;
                            }
                            if (rhs_u > 1 and !std.math.isPowerOfTwo(rhs_u) and len >= 2 and out.items[len - 2].tag == .local_get) {
                                const local = out.items[len - 2].data.local;
                                out.items[len - 1] = .{ .tag = .local_get, .data = .{ .local = local } };
                                const emitted = try emitUnsignedDivByConstI32(gpa, out, mir_extra, rhs_u, local);
                                assert(emitted);
                                out.appendAssumeCapacity(makeI32Const(rhs));
                                out.appendAssumeCapacity(.{ .tag = .i32_mul, .data = .{ .tag = {} } });
                                out.appendAssumeCapacity(.{ .tag = .i32_sub, .data = .{ .tag = {} } });
                                changed = true;
                                continue;
                            }
                        },
                        else => {},
                    }
                }

                // i32 commutative left-constant peepholes when RHS is a single pure 0-pop instruction:
                // `i32_const C; <pure_0pop x>; <op>`
                if (len >= 2 and out.items[len - 2].tag == .i32_const and isPureZeroPopTag(out.items[len - 1].tag)) {
                    const lhs: i32 = out.items[len - 2].data.imm32;
                    const lhs_u: u32 = @bitCast(lhs);
                    const x_inst = out.items[len - 1];
                    switch (inst.tag) {
                        .i32_add, .i32_or, .i32_xor => {
                            if (lhs == 0) {
                                out.items[len - 2] = x_inst;
                                out.items.len = len - 1;
                                changed = true;
                                continue;
                            }
                        },
                        .i32_and => {
                            if (lhs == -1) {
                                out.items[len - 2] = x_inst;
                                out.items.len = len - 1;
                                changed = true;
                                continue;
                            }
                        },
                        .i32_eq => {
                            if (lhs == 0) {
                                out.items[len - 2] = x_inst;
                                out.items[len - 1] = .{ .tag = .i32_eqz, .data = .{ .tag = {} } };
                                changed = true;
                                continue;
                            }
                        },
                        .i32_mul => {
                            if (lhs == 1) {
                                out.items[len - 2] = x_inst;
                                out.items.len = len - 1;
                                changed = true;
                                continue;
                            }
                            if (lhs_u > 1 and std.math.isPowerOfTwo(lhs_u)) {
                                out.items[len - 2] = x_inst;
                                out.items[len - 1] = makeI32Const(@intCast(@ctz(lhs_u)));
                                out.appendAssumeCapacity(.{ .tag = .i32_shl, .data = .{ .tag = {} } });
                                changed = true;
                                continue;
                            }
                            if (x_inst.tag == .local_get) {
                                if (matchShiftPlusMinusOne(lhs_u, 31)) |spm| {
                                    out.items[len - 2] = x_inst;
                                    out.items[len - 1] = makeI32Const(spm.shift);
                                    out.appendAssumeCapacity(.{ .tag = .i32_shl, .data = .{ .tag = {} } });
                                    out.appendAssumeCapacity(x_inst);
                                    out.appendAssumeCapacity(.{ .tag = if (spm.is_add) .i32_add else .i32_sub, .data = .{ .tag = {} } });
                                    changed = true;
                                    continue;
                                }
                            }
                        },
                        else => {},
                    }
                }

                // i64 unary ops preceded by `i64_const`
                if (len >= 1 and out.items[len - 1].tag == .i64_const) {
                    const v_u: u64 = readImm64(mir_extra.items, out.items[len - 1].data.payload);
                    const v_s: i64 = @bitCast(v_u);
                    switch (inst.tag) {
                        .i64_eqz => {
                            out.items[len - 1] = makeI32Const(if (v_u == 0) 1 else 0);
                            changed = true;
                            continue;
                        },
                        .i64_clz => {
                            out.items[len - 1] = try makeI64Const(gpa, mir_extra, @clz(v_u));
                            changed = true;
                            continue;
                        },
                        .i64_ctz => {
                            out.items[len - 1] = try makeI64Const(gpa, mir_extra, @ctz(v_u));
                            changed = true;
                            continue;
                        },
                        .i64_popcnt => {
                            out.items[len - 1] = try makeI64Const(gpa, mir_extra, @popCount(v_u));
                            changed = true;
                            continue;
                        },
                        .i64_extend8_s => {
                            const ext: i64 = @as(i8, @truncate(v_s));
                            out.items[len - 1] = try makeI64Const(gpa, mir_extra, @bitCast(ext));
                            changed = true;
                            continue;
                        },
                        .i64_extend16_s => {
                            const ext: i64 = @as(i16, @truncate(v_s));
                            out.items[len - 1] = try makeI64Const(gpa, mir_extra, @bitCast(ext));
                            changed = true;
                            continue;
                        },
                        .i64_extend32_s => {
                            const ext: i64 = @as(i32, @truncate(v_s));
                            out.items[len - 1] = try makeI64Const(gpa, mir_extra, @bitCast(ext));
                            changed = true;
                            continue;
                        },
                        .i32_wrap_i64 => {
                            out.items[len - 1] = makeI32Const(@bitCast(@as(u32, @truncate(v_u))));
                            changed = true;
                            continue;
                        },
                        else => {},
                    }
                }

                // i64 binary ops preceded by two `i64_const`
                if (len >= 2 and out.items[len - 2].tag == .i64_const and out.items[len - 1].tag == .i64_const) {
                    const lhs_u: u64 = readImm64(mir_extra.items, out.items[len - 2].data.payload);
                    const rhs_u: u64 = readImm64(mir_extra.items, out.items[len - 1].data.payload);
                    const lhs_s: i64 = @bitCast(lhs_u);
                    const rhs_s: i64 = @bitCast(rhs_u);
                    const shift_amt: u6 = @truncate(rhs_u);

                    const folded_i64: ?u64 = switch (inst.tag) {
                        .i64_add => lhs_u +% rhs_u,
                        .i64_sub => lhs_u -% rhs_u,
                        .i64_mul => lhs_u *% rhs_u,
                        .i64_div_u => if (rhs_u != 0) lhs_u / rhs_u else null,
                        .i64_rem_u => if (rhs_u != 0) lhs_u % rhs_u else null,
                        .i64_div_s => if (rhs_s != 0 and !(lhs_s == std.math.minInt(i64) and rhs_s == -1)) @bitCast(@divTrunc(lhs_s, rhs_s)) else null,
                        .i64_rem_s => if (rhs_s != 0 and !(lhs_s == std.math.minInt(i64) and rhs_s == -1)) @bitCast(@rem(lhs_s, rhs_s)) else null,
                        .i64_and => lhs_u & rhs_u,
                        .i64_or => lhs_u | rhs_u,
                        .i64_xor => lhs_u ^ rhs_u,
                        .i64_shl => lhs_u << shift_amt,
                        .i64_shr_s => @bitCast(lhs_s >> shift_amt),
                        .i64_shr_u => lhs_u >> shift_amt,
                        .i64_rotl => std.math.rotl(u64, lhs_u, shift_amt),
                        .i64_rotr => std.math.rotr(u64, lhs_u, shift_amt),
                        else => null,
                    };

                    if (folded_i64) |res_u64| {
                        const new_inst = try makeI64Const(gpa, mir_extra, res_u64);
                        out.items.len = len - 1;
                        out.items[len - 2] = new_inst;
                        changed = true;
                        continue;
                    }

                    const folded_cmp: ?i32 = switch (inst.tag) {
                        .i64_eq => if (lhs_u == rhs_u) 1 else 0,
                        .i64_ne => if (lhs_u != rhs_u) 1 else 0,
                        .i64_lt_s => if (lhs_s < rhs_s) 1 else 0,
                        .i64_lt_u => if (lhs_u < rhs_u) 1 else 0,
                        .i64_gt_s => if (lhs_s > rhs_s) 1 else 0,
                        .i64_gt_u => if (lhs_u > rhs_u) 1 else 0,
                        .i64_le_s => if (lhs_s <= rhs_s) 1 else 0,
                        .i64_le_u => if (lhs_u <= rhs_u) 1 else 0,
                        .i64_ge_s => if (lhs_s >= rhs_s) 1 else 0,
                        .i64_ge_u => if (lhs_u >= rhs_u) 1 else 0,
                        else => null,
                    };

                    if (folded_cmp) |res_i32| {
                        out.items.len = len - 1;
                        out.items[len - 2] = makeI32Const(res_i32);
                        changed = true;
                        continue;
                    }
                }

                // i64 constant reassociation: `(x +- c1) +- c2 -> x + (d1 +% d2)` (or `x` if 0)
                if ((inst.tag == .i64_add or inst.tag == .i64_sub) and len >= 3 and
                    out.items[len - 1].tag == .i64_const and
                    (out.items[len - 2].tag == .i64_add or out.items[len - 2].tag == .i64_sub) and
                    out.items[len - 3].tag == .i64_const)
                {
                    const c1 = readImm64(mir_extra.items, out.items[len - 3].data.payload);
                    const c2 = readImm64(mir_extra.items, out.items[len - 1].data.payload);
                    const d1: u64 = if (out.items[len - 2].tag == .i64_add) c1 else 0 -% c1;
                    const d2: u64 = if (inst.tag == .i64_add) c2 else 0 -% c2;
                    const total: u64 = d1 +% d2;
                    if (total == 0) {
                        out.items.len = len - 3;
                    } else {
                        out.items[len - 3] = try makeI64Const(gpa, mir_extra, total);
                        out.items[len - 2] = .{ .tag = .i64_add, .data = .{ .tag = {} } };
                        out.items.len = len - 1;
                    }
                    changed = true;
                    continue;
                }

                // i64 associative bitwise reassociation: `(x op c1) op c2 -> x op (c1 op c2)`
                if ((inst.tag == .i64_and or inst.tag == .i64_or or inst.tag == .i64_xor) and len >= 3 and
                    out.items[len - 1].tag == .i64_const and
                    out.items[len - 2].tag == inst.tag and
                    out.items[len - 3].tag == .i64_const)
                {
                    const c1 = readImm64(mir_extra.items, out.items[len - 3].data.payload);
                    const c2 = readImm64(mir_extra.items, out.items[len - 1].data.payload);
                    const combined: u64 = switch (inst.tag) {
                        .i64_and => c1 & c2,
                        .i64_or => c1 | c2,
                        .i64_xor => c1 ^ c2,
                        else => unreachable,
                    };
                    const is_identity = switch (inst.tag) {
                        .i64_and => @as(i64, @bitCast(combined)) == -1,
                        .i64_or, .i64_xor => combined == 0,
                        else => unreachable,
                    };
                    if (is_identity) {
                        out.items.len = len - 3;
                    } else {
                        out.items[len - 3] = try makeI64Const(gpa, mir_extra, combined);
                        out.items.len = len - 1;
                    }
                    changed = true;
                    continue;
                }

                // i64 single-constant right-operand peepholes: `<x>; i64_const C; <op>`
                if (len >= 1 and out.items[len - 1].tag == .i64_const and
                    !(len >= 2 and out.items[len - 2].tag == .i64_const))
                {
                    const rhs_u: u64 = readImm64(mir_extra.items, out.items[len - 1].data.payload);
                    const rhs_s: i64 = @bitCast(rhs_u);
                    const shift_amt: u6 = @truncate(rhs_u);
                    switch (inst.tag) {
                        .i64_add, .i64_sub, .i64_or, .i64_xor => {
                            if (rhs_u == 0) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                        },
                        .i64_and => {
                            const possible_ones = possibleOnesI64(out.items[0 .. len - 1], mir_extra.items);
                            if ((possible_ones & ~rhs_u) == 0) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                        },
                        .i64_shl, .i64_shr_s, .i64_shr_u, .i64_rotl, .i64_rotr => {
                            if (shift_amt == 0) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                        },
                        .i64_eq => {
                            if (rhs_u == 0) {
                                out.items[len - 1] = .{ .tag = .i64_eqz, .data = .{ .tag = {} } };
                                changed = true;
                                continue;
                            }
                        },
                        .i64_mul => {
                            if (rhs_u == 1) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                            if (rhs_u > 1 and std.math.isPowerOfTwo(rhs_u)) {
                                out.items[len - 1] = try makeI64Const(gpa, mir_extra, @ctz(rhs_u));
                                out.appendAssumeCapacity(.{ .tag = .i64_shl, .data = .{ .tag = {} } });
                                changed = true;
                                continue;
                            }
                            if (len >= 2 and (out.items[len - 2].tag == .local_get or out.items[len - 2].tag == .local_tee)) {
                                if (matchShiftPlusMinusOne(rhs_u, 63)) |spm| {
                                    const local = out.items[len - 2].data.local;
                                    out.items[len - 1] = try makeI64Const(gpa, mir_extra, spm.shift);
                                    out.appendAssumeCapacity(.{ .tag = .i64_shl, .data = .{ .tag = {} } });
                                    out.appendAssumeCapacity(.{ .tag = .local_get, .data = .{ .local = local } });
                                    out.appendAssumeCapacity(.{ .tag = if (spm.is_add) .i64_add else .i64_sub, .data = .{ .tag = {} } });
                                    changed = true;
                                    continue;
                                }
                            }
                        },
                        .i64_div_s => {
                            if (rhs_s == 1) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                        },
                        .i64_div_u => {
                            if (rhs_u == 1) {
                                _ = out.pop();
                                changed = true;
                                continue;
                            }
                            if (rhs_u > 1 and std.math.isPowerOfTwo(rhs_u)) {
                                out.items[len - 1] = try makeI64Const(gpa, mir_extra, @ctz(rhs_u));
                                out.appendAssumeCapacity(.{ .tag = .i64_shr_u, .data = .{ .tag = {} } });
                                changed = true;
                                continue;
                            }
                        },
                        .i64_rem_u => {
                            if (rhs_u >= 1 and std.math.isPowerOfTwo(rhs_u)) {
                                out.items[len - 1] = try makeI64Const(gpa, mir_extra, rhs_u - 1);
                                out.appendAssumeCapacity(.{ .tag = .i64_and, .data = .{ .tag = {} } });
                                changed = true;
                                continue;
                            }
                        },
                        else => {},
                    }
                }

                // i64 commutative left-constant peepholes when RHS is a single pure 0-pop instruction:
                // `i64_const C; <pure_0pop x>; <op>`
                if (len >= 2 and out.items[len - 2].tag == .i64_const and isPureZeroPopTag(out.items[len - 1].tag)) {
                    const lhs_u: u64 = readImm64(mir_extra.items, out.items[len - 2].data.payload);
                    const lhs_s: i64 = @bitCast(lhs_u);
                    const x_inst = out.items[len - 1];
                    switch (inst.tag) {
                        .i64_add, .i64_or, .i64_xor => {
                            if (lhs_u == 0) {
                                out.items[len - 2] = x_inst;
                                out.items.len = len - 1;
                                changed = true;
                                continue;
                            }
                        },
                        .i64_and => {
                            if (lhs_s == -1) {
                                out.items[len - 2] = x_inst;
                                out.items.len = len - 1;
                                changed = true;
                                continue;
                            }
                        },
                        .i64_eq => {
                            if (lhs_u == 0) {
                                out.items[len - 2] = x_inst;
                                out.items[len - 1] = .{ .tag = .i64_eqz, .data = .{ .tag = {} } };
                                changed = true;
                                continue;
                            }
                        },
                        .i64_mul => {
                            if (lhs_u == 1) {
                                out.items[len - 2] = x_inst;
                                out.items.len = len - 1;
                                changed = true;
                                continue;
                            }
                            if (lhs_u > 1 and std.math.isPowerOfTwo(lhs_u)) {
                                out.items[len - 2] = x_inst;
                                out.items[len - 1] = try makeI64Const(gpa, mir_extra, @ctz(lhs_u));
                                out.appendAssumeCapacity(.{ .tag = .i64_shl, .data = .{ .tag = {} } });
                                changed = true;
                                continue;
                            }
                            if (x_inst.tag == .local_get) {
                                if (matchShiftPlusMinusOne(lhs_u, 63)) |spm| {
                                    out.items[len - 2] = x_inst;
                                    out.items[len - 1] = try makeI64Const(gpa, mir_extra, spm.shift);
                                    out.appendAssumeCapacity(.{ .tag = .i64_shl, .data = .{ .tag = {} } });
                                    out.appendAssumeCapacity(x_inst);
                                    out.appendAssumeCapacity(.{ .tag = if (spm.is_add) .i64_add else .i64_sub, .data = .{ .tag = {} } });
                                    changed = true;
                                    continue;
                                }
                            }
                        },
                        else => {},
                    }
                }

                // Shift and rotate bitmask elision:
                // WebAssembly shift and rotate instructions inherently mask the shift count modulo the bit-width (32 or 64).
                switch (inst.tag) {
                    .i32_shl, .i32_shr_s, .i32_shr_u, .i32_rotl, .i32_rotr => {
                        if (len >= 2 and out.items[len - 1].tag == .i32_and and out.items[len - 2].tag == .i32_const and
                            (@as(u32, @bitCast(out.items[len - 2].data.imm32)) & 31) == 31)
                        {
                            out.items.len = len - 2;
                            out.appendAssumeCapacity(inst);
                            changed = true;
                            continue;
                        }
                        if (len >= 3 and out.items[len - 1].tag == .i32_and and isPureZeroPopTag(out.items[len - 2].tag) and
                            out.items[len - 3].tag == .i32_const and (@as(u32, @bitCast(out.items[len - 3].data.imm32)) & 31) == 31)
                        {
                            out.items[len - 3] = out.items[len - 2];
                            out.items.len = len - 2;
                            out.appendAssumeCapacity(inst);
                            changed = true;
                            continue;
                        }
                    },
                    .i64_shl, .i64_shr_s, .i64_shr_u, .i64_rotl, .i64_rotr => {
                        if (len >= 2 and out.items[len - 1].tag == .i64_and and out.items[len - 2].tag == .i64_const and
                            (readImm64(mir_extra.items, out.items[len - 2].data.payload) & 63) == 63)
                        {
                            out.items.len = len - 2;
                            out.appendAssumeCapacity(inst);
                            changed = true;
                            continue;
                        }
                        if (len >= 3 and out.items[len - 1].tag == .i64_and and isPureZeroPopTag(out.items[len - 2].tag) and
                            out.items[len - 3].tag == .i64_const and (readImm64(mir_extra.items, out.items[len - 3].data.payload) & 63) == 63)
                        {
                            out.items[len - 3] = out.items[len - 2];
                            out.items.len = len - 2;
                            out.appendAssumeCapacity(inst);
                            changed = true;
                            continue;
                        }
                        if (len >= 3 and
                            (out.items[len - 1].tag == .i64_extend_i32_u or out.items[len - 1].tag == .i64_extend_i32_s) and
                            out.items[len - 2].tag == .i32_and and out.items[len - 3].tag == .i32_const and
                            (@as(u32, @bitCast(out.items[len - 3].data.imm32)) & 63) == 63)
                        {
                            out.items[len - 3] = out.items[len - 1];
                            out.items.len = len - 2;
                            out.appendAssumeCapacity(inst);
                            changed = true;
                            continue;
                        }
                        if (len >= 4 and
                            (out.items[len - 1].tag == .i64_extend_i32_u or out.items[len - 1].tag == .i64_extend_i32_s) and
                            out.items[len - 2].tag == .i32_and and isPureZeroPopTag(out.items[len - 3].tag) and
                            out.items[len - 4].tag == .i32_const and (@as(u32, @bitCast(out.items[len - 4].data.imm32)) & 63) == 63)
                        {
                            out.items[len - 4] = out.items[len - 3];
                            out.items[len - 3] = out.items[len - 1];
                            out.items.len = len - 2;
                            out.appendAssumeCapacity(inst);
                            changed = true;
                            continue;
                        }
                    },
                    .i32_or, .i32_add, .i32_xor => {
                        // Constant 32-bit rotate synthesis:
                        // `local_get X; i32_const C1; <sh1>; local_get X; i32_const C2; <sh2>; i32_or/add/xor`
                        if (len >= 6 and
                            out.items[len - 6].tag == .local_get and
                            out.items[len - 5].tag == .i32_const and
                            out.items[len - 3].tag == .local_get and
                            out.items[len - 6].data.local == out.items[len - 3].data.local and
                            out.items[len - 2].tag == .i32_const)
                        {
                            const sh1 = out.items[len - 4].tag;
                            const sh2 = out.items[len - 1].tag;
                            if ((sh1 == .i32_shl and sh2 == .i32_shr_u) or (sh1 == .i32_shr_u and sh2 == .i32_shl)) {
                                const c1: u5 = @truncate(@as(u32, @bitCast(out.items[len - 5].data.imm32)));
                                const c2: u5 = @truncate(@as(u32, @bitCast(out.items[len - 2].data.imm32)));
                                if (c1 != 0 and (c1 +% c2) == 0) {
                                    out.items[len - 5] = makeI32Const(c1);
                                    out.items[len - 4] = .{
                                        .tag = if (sh1 == .i32_shl) .i32_rotl else .i32_rotr,
                                        .data = .{ .tag = {} },
                                    };
                                    out.items.len = len - 3;
                                    changed = true;
                                    continue;
                                }
                            }
                        }
                        // Variable 32-bit rotate synthesis:
                        // `local_get X; local_get S; <sh1>; local_get X; i32_const C; local_get S; i32_sub; <sh2>; i32_or`
                        if (inst.tag == .i32_or and len >= 8 and
                            out.items[len - 8].tag == .local_get and
                            out.items[len - 7].tag == .local_get and
                            out.items[len - 5].tag == .local_get and
                            out.items[len - 8].data.local == out.items[len - 5].data.local and
                            out.items[len - 4].tag == .i32_const and
                            (@as(u32, @bitCast(out.items[len - 4].data.imm32)) & 31) == 0 and
                            out.items[len - 3].tag == .local_get and
                            out.items[len - 7].data.local == out.items[len - 3].data.local and
                            out.items[len - 2].tag == .i32_sub)
                        {
                            const sh1 = out.items[len - 6].tag;
                            const sh2 = out.items[len - 1].tag;
                            if ((sh1 == .i32_shl and sh2 == .i32_shr_u) or (sh1 == .i32_shr_u and sh2 == .i32_shl)) {
                                out.items[len - 6] = .{
                                    .tag = if (sh1 == .i32_shl) .i32_rotl else .i32_rotr,
                                    .data = .{ .tag = {} },
                                };
                                out.items.len = len - 5;
                                changed = true;
                                continue;
                            }
                        }
                    },
                    .i64_or, .i64_add, .i64_xor => {
                        // Constant 64-bit rotate synthesis:
                        // `local_get X; i64_const C1; <sh1>; local_get X; i64_const C2; <sh2>; i64_or/add/xor`
                        if (len >= 6 and
                            out.items[len - 6].tag == .local_get and
                            out.items[len - 5].tag == .i64_const and
                            out.items[len - 3].tag == .local_get and
                            out.items[len - 6].data.local == out.items[len - 3].data.local and
                            out.items[len - 2].tag == .i64_const)
                        {
                            const sh1 = out.items[len - 4].tag;
                            const sh2 = out.items[len - 1].tag;
                            if ((sh1 == .i64_shl and sh2 == .i64_shr_u) or (sh1 == .i64_shr_u and sh2 == .i64_shl)) {
                                const c1: u6 = @truncate(readImm64(mir_extra.items, out.items[len - 5].data.payload));
                                const c2: u6 = @truncate(readImm64(mir_extra.items, out.items[len - 2].data.payload));
                                if (c1 != 0 and (c1 +% c2) == 0) {
                                    out.items[len - 5] = try makeI64Const(gpa, mir_extra, c1);
                                    out.items[len - 4] = .{
                                        .tag = if (sh1 == .i64_shl) .i64_rotl else .i64_rotr,
                                        .data = .{ .tag = {} },
                                    };
                                    out.items.len = len - 3;
                                    changed = true;
                                    continue;
                                }
                            }
                        }
                        // Variable 64-bit rotate synthesis:
                        // `local_get X; local_get S; i64_extend_i32_u; <sh1>; local_get X; i32_const C; local_get S; i32_sub; i64_extend_i32_u; <sh2>; i64_or`
                        if (inst.tag == .i64_or and len >= 10 and
                            out.items[len - 10].tag == .local_get and
                            out.items[len - 9].tag == .local_get and
                            out.items[len - 8].tag == .i64_extend_i32_u and
                            out.items[len - 6].tag == .local_get and
                            out.items[len - 10].data.local == out.items[len - 6].data.local and
                            out.items[len - 5].tag == .i32_const and
                            (@as(u32, @bitCast(out.items[len - 5].data.imm32)) & 63) == 0 and
                            out.items[len - 4].tag == .local_get and
                            out.items[len - 9].data.local == out.items[len - 4].data.local and
                            out.items[len - 3].tag == .i32_sub and
                            out.items[len - 2].tag == .i64_extend_i32_u)
                        {
                            const sh1 = out.items[len - 7].tag;
                            const sh2 = out.items[len - 1].tag;
                            if ((sh1 == .i64_shl and sh2 == .i64_shr_u) or (sh1 == .i64_shr_u and sh2 == .i64_shl)) {
                                out.items[len - 7] = .{
                                    .tag = if (sh1 == .i64_shl) .i64_rotl else .i64_rotr,
                                    .data = .{ .tag = {} },
                                };
                                out.items.len = len - 6;
                                changed = true;
                                continue;
                            }
                        }
                    },
                    .simd_prefix => if (inst.data.payload < mir_extra.items.len) {
                        const simd_op: std.wasm.SimdOpcode = @fromBackingInt(mir_extra.items[inst.data.payload]);
                        switch (simd_op) {
                            .v128_not => {
                                if (len >= 1 and isSimdOp(out.items[len - 1], mir_extra.items, .v128_not)) {
                                    _ = out.pop();
                                    changed = true;
                                    continue;
                                }
                            },
                            .v128_and => {
                                // `a; b; v128_not; v128_and -> a; b; v128_andnot`
                                if (len >= 1 and isSimdOp(out.items[len - 1], mir_extra.items, .v128_not)) {
                                    out.items[len - 1] = try makeSimdInst(gpa, mir_extra, .v128_andnot);
                                    changed = true;
                                    continue;
                                }
                                // `<pure_0pop_v128 b>; v128_not; <pure_0pop_v128 a>; v128_and -> <pure_0pop_v128 a>; <pure_0pop_v128 b>; v128_andnot`
                                if (len >= 3 and
                                    isPureZeroPopOrSimdConst(out.items[len - 1], mir_extra.items) and
                                    isSimdOp(out.items[len - 2], mir_extra.items, .v128_not) and
                                    isPureZeroPopOrSimdConst(out.items[len - 3], mir_extra.items))
                                {
                                    const a_inst = out.items[len - 1];
                                    const b_inst = out.items[len - 3];
                                    out.items[len - 3] = a_inst;
                                    out.items[len - 2] = b_inst;
                                    out.items[len - 1] = try makeSimdInst(gpa, mir_extra, .v128_andnot);
                                    changed = true;
                                    continue;
                                }
                            },
                            .i8x16_shl, .i8x16_shr_s, .i8x16_shr_u,
                            .i16x8_shl, .i16x8_shr_s, .i16x8_shr_u,
                            .i32x4_shl, .i32x4_shr_s, .i32x4_shr_u,
                            .i64x2_shl, .i64x2_shr_s, .i64x2_shr_u,
                            => {
                                const mask: u32 = switch (simd_op) {
                                    .i8x16_shl, .i8x16_shr_s, .i8x16_shr_u => 7,
                                    .i16x8_shl, .i16x8_shr_s, .i16x8_shr_u => 15,
                                    .i32x4_shl, .i32x4_shr_s, .i32x4_shr_u => 31,
                                    .i64x2_shl, .i64x2_shr_s, .i64x2_shr_u => 63,
                                    else => unreachable,
                                };
                                if (len >= 2 and out.items[len - 1].tag == .i32_and and out.items[len - 2].tag == .i32_const and
                                    (@as(u32, @bitCast(out.items[len - 2].data.imm32)) & mask) == mask)
                                {
                                    out.items.len = len - 2;
                                    out.appendAssumeCapacity(inst);
                                    changed = true;
                                    continue;
                                }
                            },
                            else => {},
                        }
                    },
                    else => {},
                }

                if (try foldMemArgOffset(gpa, inst, out, mir_extra)) |folded_mem_inst| {
                    out.appendAssumeCapacity(folded_mem_inst);
                    changed = true;
                    continue;
                }

                out.appendAssumeCapacity(inst);
            }

            return changed;
        }

        const MemOpInfo = struct {
            val_operands: u1,
            memarg_idx: u32,
            prefix_opcode: ?u32,
        };

        fn memOpInfo(inst: Inst, mir_extra: []const u32) ?MemOpInfo {
            return switch (inst.tag) {
                .i32_load,
                .i64_load,
                .f32_load,
                .f64_load,
                .i32_load8_s,
                .i32_load8_u,
                .i32_load16_s,
                .i32_load16_u,
                .i64_load8_s,
                .i64_load8_u,
                .i64_load16_s,
                .i64_load16_u,
                .i64_load32_s,
                .i64_load32_u,
                => .{
                    .val_operands = 0,
                    .memarg_idx = inst.data.payload,
                    .prefix_opcode = null,
                },

                .i32_store,
                .i64_store,
                .f32_store,
                .f64_store,
                .i32_store8,
                .i32_store16,
                .i64_store8,
                .i64_store16,
                .i64_store32,
                => .{
                    .val_operands = 1,
                    .memarg_idx = inst.data.payload,
                    .prefix_opcode = null,
                },

                .simd_prefix => blk: {
                    const opcode = mir_extra[inst.data.payload];
                    break :blk switch (@as(std.wasm.SimdOpcode, @fromBackingInt(opcode))) {
                        .v128_load,
                        .v128_load8x8_s,
                        .v128_load8x8_u,
                        .v128_load16x4_s,
                        .v128_load16x4_u,
                        .v128_load32x2_s,
                        .v128_load32x2_u,
                        .v128_load8_splat,
                        .v128_load16_splat,
                        .v128_load32_splat,
                        .v128_load64_splat,
                        .v128_load32_zero,
                        .v128_load64_zero,
                        => .{
                            .val_operands = 0,
                            .memarg_idx = inst.data.payload + 1,
                            .prefix_opcode = opcode,
                        },
                        .v128_store => .{
                            .val_operands = 1,
                            .memarg_idx = inst.data.payload + 1,
                            .prefix_opcode = opcode,
                        },
                        else => null,
                    };
                },

                .atomics_prefix => blk: {
                    const opcode = mir_extra[inst.data.payload];
                    break :blk switch (@as(std.wasm.AtomicsOpcode, @fromBackingInt(opcode))) {
                        .i32_atomic_load,
                        .i64_atomic_load,
                        .i32_atomic_load8_u,
                        .i32_atomic_load16_u,
                        .i64_atomic_load8_u,
                        .i64_atomic_load16_u,
                        .i64_atomic_load32_u,
                        => .{
                            .val_operands = 0,
                            .memarg_idx = inst.data.payload + 1,
                            .prefix_opcode = opcode,
                        },
                        .memory_atomic_notify,
                        .i32_atomic_store,
                        .i64_atomic_store,
                        .i32_atomic_store8,
                        .i32_atomic_store16,
                        .i64_atomic_store8,
                        .i64_atomic_store16,
                        .i64_atomic_store32,
                        .i32_atomic_rmw_add,
                        .i64_atomic_rmw_add,
                        .i32_atomic_rmw8_add_u,
                        .i32_atomic_rmw16_add_u,
                        .i64_atomic_rmw8_add_u,
                        .i64_atomic_rmw16_add_u,
                        .i64_atomic_rmw32_add_u,
                        .i32_atomic_rmw_sub,
                        .i64_atomic_rmw_sub,
                        .i32_atomic_rmw8_sub_u,
                        .i32_atomic_rmw16_sub_u,
                        .i64_atomic_rmw8_sub_u,
                        .i64_atomic_rmw16_sub_u,
                        .i64_atomic_rmw32_sub_u,
                        .i32_atomic_rmw_and,
                        .i64_atomic_rmw_and,
                        .i32_atomic_rmw8_and_u,
                        .i32_atomic_rmw16_and_u,
                        .i64_atomic_rmw8_and_u,
                        .i64_atomic_rmw16_and_u,
                        .i64_atomic_rmw32_and_u,
                        .i32_atomic_rmw_or,
                        .i64_atomic_rmw_or,
                        .i32_atomic_rmw8_or_u,
                        .i32_atomic_rmw16_or_u,
                        .i64_atomic_rmw8_or_u,
                        .i64_atomic_rmw16_or_u,
                        .i64_atomic_rmw32_or_u,
                        .i32_atomic_rmw_xor,
                        .i64_atomic_rmw_xor,
                        .i32_atomic_rmw8_xor_u,
                        .i32_atomic_rmw16_xor_u,
                        .i64_atomic_rmw8_xor_u,
                        .i64_atomic_rmw16_xor_u,
                        .i64_atomic_rmw32_xor_u,
                        .i32_atomic_rmw_xchg,
                        .i64_atomic_rmw_xchg,
                        .i32_atomic_rmw8_xchg_u,
                        .i32_atomic_rmw16_xchg_u,
                        .i64_atomic_rmw8_xchg_u,
                        .i64_atomic_rmw16_xchg_u,
                        .i64_atomic_rmw32_xchg_u,
                        => .{
                            .val_operands = 1,
                            .memarg_idx = inst.data.payload + 1,
                            .prefix_opcode = opcode,
                        },
                        else => null,
                    };
                },

                else => null,
            };
        }

        /// For an instruction that pushes exactly 1 value onto the Wasm operand stack,
        /// returns the number of operand stack values it pops, or `null` if the instruction
        /// cannot be walked across when locating the `<val>` sub-expression of a store.
        fn singlePushInstPops(inst: Inst, mir_extra: []const u32) ?i32 {
            return switch (inst.tag) {
                .i32_const,
                .i64_const,
                .f32_const,
                .f64_const,
                .local_get,
                .global_get,
                .uav_ref,
                .uav_ref_off,
                .nav_ref,
                .nav_ref_off,
                .func_ref,
                .tls_nav_ref,
                .errors_len,
                .error_name_table_ref,
                .enum_tag_name_table_ref,
                .memory_size,
                => 0,

                .i32_eqz,
                .i64_eqz,
                .i32_clz,
                .i32_ctz,
                .i32_popcnt,
                .i64_clz,
                .i64_ctz,
                .i64_popcnt,
                .f32_abs,
                .f32_neg,
                .f32_ceil,
                .f32_floor,
                .f32_trunc,
                .f32_nearest,
                .f32_sqrt,
                .f64_abs,
                .f64_neg,
                .f64_ceil,
                .f64_floor,
                .f64_trunc,
                .f64_nearest,
                .f64_sqrt,
                .i32_wrap_i64,
                .i32_trunc_f32_s,
                .i32_trunc_f32_u,
                .i32_trunc_f64_s,
                .i32_trunc_f64_u,
                .i64_extend_i32_s,
                .i64_extend_i32_u,
                .i64_trunc_f32_s,
                .i64_trunc_f32_u,
                .i64_trunc_f64_s,
                .i64_trunc_f64_u,
                .f32_convert_i32_s,
                .f32_convert_i32_u,
                .f32_convert_i64_s,
                .f32_convert_i64_u,
                .f32_demote_f64,
                .f64_convert_i32_s,
                .f64_convert_i32_u,
                .f64_convert_i64_s,
                .f64_convert_i64_u,
                .f64_promote_f32,
                .i32_reinterpret_f32,
                .i64_reinterpret_f64,
                .f32_reinterpret_i32,
                .f64_reinterpret_i64,
                .i32_extend8_s,
                .i32_extend16_s,
                .i64_extend8_s,
                .i64_extend16_s,
                .i64_extend32_s,
                .local_tee,
                .memory_grow,
                .i32_load,
                .i64_load,
                .f32_load,
                .f64_load,
                .i32_load8_s,
                .i32_load8_u,
                .i32_load16_s,
                .i32_load16_u,
                .i64_load8_s,
                .i64_load8_u,
                .i64_load16_s,
                .i64_load16_u,
                .i64_load32_s,
                .i64_load32_u,
                => 1,

                .i32_eq,
                .i32_ne,
                .i32_lt_s,
                .i32_lt_u,
                .i32_gt_s,
                .i32_gt_u,
                .i32_le_s,
                .i32_le_u,
                .i32_ge_s,
                .i32_ge_u,
                .i64_eq,
                .i64_ne,
                .i64_lt_s,
                .i64_lt_u,
                .i64_gt_s,
                .i64_gt_u,
                .i64_le_s,
                .i64_le_u,
                .i64_ge_s,
                .i64_ge_u,
                .f32_eq,
                .f32_ne,
                .f32_lt,
                .f32_gt,
                .f32_le,
                .f32_ge,
                .f64_eq,
                .f64_ne,
                .f64_lt,
                .f64_gt,
                .f64_le,
                .f64_ge,
                .i32_add,
                .i32_sub,
                .i32_mul,
                .i32_div_s,
                .i32_div_u,
                .i32_rem_s,
                .i32_rem_u,
                .i32_and,
                .i32_or,
                .i32_xor,
                .i32_shl,
                .i32_shr_s,
                .i32_shr_u,
                .i32_rotl,
                .i32_rotr,
                .i64_add,
                .i64_sub,
                .i64_mul,
                .i64_div_s,
                .i64_div_u,
                .i64_rem_s,
                .i64_rem_u,
                .i64_and,
                .i64_or,
                .i64_xor,
                .i64_shl,
                .i64_shr_s,
                .i64_shr_u,
                .i64_rotl,
                .i64_rotr,
                .f32_add,
                .f32_sub,
                .f32_mul,
                .f32_div,
                .f32_min,
                .f32_max,
                .f32_copysign,
                .f64_add,
                .f64_sub,
                .f64_mul,
                .f64_div,
                .f64_min,
                .f64_max,
                .f64_copysign,
                => 2,

                .select => 3,

                .simd_prefix => switch (@as(std.wasm.SimdOpcode, @fromBackingInt(mir_extra[inst.data.payload]))) {
                    .v128_const => 0,

                    .v128_load,
                    .v128_load8x8_s,
                    .v128_load8x8_u,
                    .v128_load16x4_s,
                    .v128_load16x4_u,
                    .v128_load32x2_s,
                    .v128_load32x2_u,
                    .v128_load8_splat,
                    .v128_load16_splat,
                    .v128_load32_splat,
                    .v128_load64_splat,
                    .v128_load32_zero,
                    .v128_load64_zero,
                    .i8x16_extract_lane_s,
                    .i8x16_extract_lane_u,
                    .i16x8_extract_lane_s,
                    .i16x8_extract_lane_u,
                    .i32x4_extract_lane,
                    .i64x2_extract_lane,
                    .f32x4_extract_lane,
                    .f64x2_extract_lane,
                    .i8x16_splat,
                    .i16x8_splat,
                    .i32x4_splat,
                    .i64x2_splat,
                    .f32x4_splat,
                    .f64x2_splat,
                    .v128_not,
                    .v128_any_true,
                    .i8x16_abs,
                    .i8x16_neg,
                    .i8x16_popcnt,
                    .i8x16_all_true,
                    .i8x16_bitmask,
                    .i16x8_extadd_pairwise_i8x16_s,
                    .i16x8_extadd_pairwise_i8x16_u,
                    .i16x8_abs,
                    .i16x8_neg,
                    .i16x8_all_true,
                    .i16x8_bitmask,
                    .i16x8_extend_low_i8x16_s,
                    .i16x8_extend_high_i8x16_s,
                    .i16x8_extend_low_i8x16_u,
                    .i16x8_extend_high_i8x16_u,
                    .i32x4_extadd_pairwise_i16x8_s,
                    .i32x4_extadd_pairwise_i16x8_u,
                    .i32x4_abs,
                    .i32x4_neg,
                    .i32x4_all_true,
                    .i32x4_bitmask,
                    .i32x4_extend_low_i16x8_s,
                    .i32x4_extend_high_i16x8_s,
                    .i32x4_extend_low_i16x8_u,
                    .i32x4_extend_high_i16x8_u,
                    .i32x4_trunc_sat_f32x4_s,
                    .i32x4_trunc_sat_f32x4_u,
                    .i32x4_trunc_sat_f64x2_s_zero,
                    .i32x4_trunc_sat_f64x2_u_zero,
                    .i64x2_abs,
                    .i64x2_neg,
                    .i64x2_all_true,
                    .i64x2_bitmask,
                    .i64x2_extend_low_i32x4_s,
                    .i64x2_extend_high_i32x4_s,
                    .i64x2_extend_low_i32x4_u,
                    .i64x2_extend_high_i32x4_u,
                    .f32x4_ceil,
                    .f32x4_floor,
                    .f32x4_trunc,
                    .f32x4_nearest,
                    .f32x4_abs,
                    .f32x4_neg,
                    .f32x4_sqrt,
                    .f32x4_convert_i32x4_s,
                    .f32x4_convert_i32x4_u,
                    .f32x4_demote_f64x2_zero,
                    .f64x2_ceil,
                    .f64x2_floor,
                    .f64x2_trunc,
                    .f64x2_nearest,
                    .f64x2_abs,
                    .f64x2_neg,
                    .f64x2_sqrt,
                    .f64x2_promote_low_f32x4,
                    .f64x2_convert_low_i32x4_s,
                    .f64x2_convert_low_i32x4_u,
                    .i32x4_relaxed_trunc_f32x4_s,
                    .i32x4_relaxed_trunc_f32x4_u,
                    .i32x4_relaxed_trunc_f64x2_s_zero,
                    .i32x4_relaxed_trunc_f64x2_u_zero,
                    => 1,

                    .v128_load8_lane,
                    .v128_load16_lane,
                    .v128_load32_lane,
                    .v128_load64_lane,
                    .i8x16_replace_lane,
                    .i16x8_replace_lane,
                    .i32x4_replace_lane,
                    .i64x2_replace_lane,
                    .f32x4_replace_lane,
                    .f64x2_replace_lane,
                    .i8x16_shuffle,
                    .i8x16_swizzle,
                    .v128_and,
                    .v128_andnot,
                    .v128_or,
                    .v128_xor,
                    .i8x16_eq,
                    .i8x16_ne,
                    .i8x16_lt_s,
                    .i8x16_lt_u,
                    .i8x16_gt_s,
                    .i8x16_gt_u,
                    .i8x16_le_s,
                    .i8x16_le_u,
                    .i8x16_ge_s,
                    .i8x16_ge_u,
                    .i16x8_eq,
                    .i16x8_ne,
                    .i16x8_lt_s,
                    .i16x8_lt_u,
                    .i16x8_gt_s,
                    .i16x8_gt_u,
                    .i16x8_le_s,
                    .i16x8_le_u,
                    .i16x8_ge_s,
                    .i16x8_ge_u,
                    .i32x4_eq,
                    .i32x4_ne,
                    .i32x4_lt_s,
                    .i32x4_lt_u,
                    .i32x4_gt_s,
                    .i32x4_gt_u,
                    .i32x4_le_s,
                    .i32x4_le_u,
                    .i32x4_ge_s,
                    .i32x4_ge_u,
                    .i64x2_eq,
                    .i64x2_ne,
                    .i64x2_lt_s,
                    .i64x2_gt_s,
                    .i64x2_le_s,
                    .i64x2_ge_s,
                    .f32x4_eq,
                    .f32x4_ne,
                    .f32x4_lt,
                    .f32x4_gt,
                    .f32x4_le,
                    .f32x4_ge,
                    .f64x2_eq,
                    .f64x2_ne,
                    .f64x2_lt,
                    .f64x2_gt,
                    .f64x2_le,
                    .f64x2_ge,
                    .i8x16_narrow_i16x8_s,
                    .i8x16_narrow_i16x8_u,
                    .i16x8_narrow_i32x4_s,
                    .i16x8_narrow_i32x4_u,
                    .i8x16_shl,
                    .i8x16_shr_s,
                    .i8x16_shr_u,
                    .i16x8_shl,
                    .i16x8_shr_s,
                    .i16x8_shr_u,
                    .i32x4_shl,
                    .i32x4_shr_s,
                    .i32x4_shr_u,
                    .i64x2_shl,
                    .i64x2_shr_s,
                    .i64x2_shr_u,
                    .i8x16_add,
                    .i8x16_add_sat_s,
                    .i8x16_add_sat_u,
                    .i8x16_sub,
                    .i8x16_sub_sat_s,
                    .i8x16_sub_sat_u,
                    .i8x16_min_s,
                    .i8x16_min_u,
                    .i8x16_max_s,
                    .i8x16_max_u,
                    .i8x16_avgr_u,
                    .i16x8_q15mulr_sat_s,
                    .i16x8_add,
                    .i16x8_add_sat_s,
                    .i16x8_add_sat_u,
                    .i16x8_sub,
                    .i16x8_sub_sat_s,
                    .i16x8_sub_sat_u,
                    .i16x8_mul,
                    .i16x8_min_s,
                    .i16x8_min_u,
                    .i16x8_max_s,
                    .i16x8_max_u,
                    .i16x8_avgr_u,
                    .i16x8_extmul_low_i8x16_s,
                    .i16x8_extmul_high_i8x16_s,
                    .i16x8_extmul_low_i8x16_u,
                    .i16x8_extmul_high_i8x16_u,
                    .i32x4_add,
                    .i32x4_sub,
                    .i32x4_mul,
                    .i32x4_min_s,
                    .i32x4_min_u,
                    .i32x4_max_s,
                    .i32x4_max_u,
                    .i32x4_dot_i16x8_s,
                    .i32x4_extmul_low_i16x8_s,
                    .i32x4_extmul_high_i16x8_s,
                    .i32x4_extmul_low_i16x8_u,
                    .i32x4_extmul_high_i16x8_u,
                    .i64x2_add,
                    .i64x2_sub,
                    .i64x2_mul,
                    .i64x2_extmul_low_i32x4_s,
                    .i64x2_extmul_high_i32x4_s,
                    .i64x2_extmul_low_i32x4_u,
                    .i64x2_extmul_high_i32x4_u,
                    .f32x4_add,
                    .f32x4_sub,
                    .f32x4_mul,
                    .f32x4_div,
                    .f32x4_min,
                    .f32x4_max,
                    .f32x4_pmin,
                    .f32x4_pmax,
                    .f64x2_add,
                    .f64x2_sub,
                    .f64x2_mul,
                    .f64x2_div,
                    .f64x2_min,
                    .f64x2_max,
                    .f64x2_pmin,
                    .f64x2_pmax,
                    .i8x16_relaxed_swizzle,
                    .f32x4_relaxed_min,
                    .f32x4_relaxed_max,
                    .f64x2_relaxed_min,
                    .f64x2_relaxed_max,
                    .i16x8_relaxed_q15mulr_s,
                    .i16x8_relaxed_dot_i8x16_i7x16_s,
                    => 2,

                    .v128_bitselect,
                    .f32x4_relaxed_madd,
                    .f32x4_relaxed_nmadd,
                    .f64x2_relaxed_madd,
                    .f64x2_relaxed_nmadd,
                    .i8x16_relaxed_laneselect,
                    .i16x8_relaxed_laneselect,
                    .i32x4_relaxed_laneselect,
                    .i64x2_relaxed_laneselect,
                    .i32x4_relaxed_dot_i8x16_i7x16_add_s,
                    .f32x4_relaxed_dot_bf16x8_add_f32x4,
                    => 3,

                    .v128_store,
                    .v128_store8_lane,
                    .v128_store16_lane,
                    .v128_store32_lane,
                    .v128_store64_lane,
                    => null,
                },

                .atomics_prefix => blk: {
                    if (memOpInfo(inst, mir_extra)) |info| {
                        if (info.val_operands == 0) break :blk 1;
                    }
                    break :blk null;
                },

                .call_intrinsic => pureScalarIntrinsicPops(inst.data.intrinsic),

                else => null,
            };
        }

        fn findValStartIndex(insts: []const Inst, mir_extra: []const u32) ?usize {
            var needed: i32 = 1;
            var idx: usize = insts.len;
            while (idx > 0) {
                idx -= 1;
                const prev = insts[idx];
                if (prev.tag == .dbg_line) continue;
                const pops = singlePushInstPops(prev, mir_extra) orelse return null;
                needed = needed - 1 + pops;
                if (needed == 0) return idx;
            }
            return null;
        }

        fn prevNonDbgIndex(insts: []const Inst, end_idx: usize) ?usize {
            var idx = end_idx;
            while (idx > 0) {
                idx -= 1;
                if (insts[idx].tag != .dbg_line) return idx;
            }
            return null;
        }

        fn foldMemArgOffset(
            gpa: Allocator,
            inst: Inst,
            out: *std.ArrayList(Inst),
            mir_extra: *std.ArrayList(u32),
        ) Allocator.Error!?Inst {
            const info = memOpInfo(inst, mir_extra.items) orelse return null;
            const orig_offset = readMemArgOffset(mir_extra.items, info.memarg_idx);
            const alignment = mir_extra.items[info.memarg_idx + 2];

            var addr_end: usize = if (info.val_operands == 0)
                out.items.len
            else
                findValStartIndex(out.items, mir_extra.items) orelse return null;

            var current_offset = orig_offset;
            var folded = false;

            while (true) {
                const add_idx = prevNonDbgIndex(out.items, addr_end) orelse break;
                const add_inst = out.items[add_idx];
                if (add_inst.tag != .i32_add and add_inst.tag != .i64_add) break;

                const const_idx = prevNonDbgIndex(out.items, add_idx) orelse break;
                const const_inst = out.items[const_idx];

                const maybe_new_offset: ?u64 = switch (add_inst.tag) {
                    .i32_add => blk: {
                        if (const_inst.tag != .i32_const) break :blk null;
                        const k = const_inst.data.imm32;
                        if (k < 0) break :blk null;
                        if (current_offset > std.math.maxInt(u32)) break :blk null;
                        const sum = std.math.add(u32, @intCast(current_offset), @intCast(k)) catch break :blk null;
                        break :blk @as(u64, sum);
                    },
                    .i64_add => blk: {
                        if (const_inst.tag != .i64_const) break :blk null;
                        const k_u64 = readImm64(mir_extra.items, const_inst.data.payload);
                        if (@as(i64, @bitCast(k_u64)) < 0) break :blk null;
                        const sum = std.math.add(u64, current_offset, k_u64) catch break :blk null;
                        break :blk sum;
                    },
                    else => unreachable,
                };
                const new_offset = maybe_new_offset orelse break;

                _ = out.orderedRemove(add_idx);
                _ = out.orderedRemove(const_idx);
                addr_end -= 2;
                current_offset = new_offset;
                folded = true;
            }

            if (!folded) return null;

            const new_payload = try appendMemArg(gpa, mir_extra, current_offset, alignment, info.prefix_opcode);
            return .{ .tag = inst.tag, .data = .{ .payload = new_payload } };
        }

        const TrackedMemEntry = struct {
            base_local: u32,
            offset: u64,
            size: u8,
            store_or_load_tag: Inst.Tag,
            val_inst: Inst,
            store_out_start: ?usize,
            store_out_end: ?usize,
        };

        fn isScalarLoadTag(tag: Inst.Tag) bool {
            return switch (tag) {
                .i32_load,
                .i64_load,
                .f32_load,
                .f64_load,
                .i32_load8_s,
                .i32_load8_u,
                .i32_load16_s,
                .i32_load16_u,
                .i64_load8_s,
                .i64_load8_u,
                .i64_load16_s,
                .i64_load16_u,
                .i64_load32_s,
                .i64_load32_u,
                => true,
                else => false,
            };
        }

        fn isScalarStoreTag(tag: Inst.Tag) bool {
            return switch (tag) {
                .i32_store,
                .i64_store,
                .f32_store,
                .f64_store,
                .i32_store8,
                .i32_store16,
                .i64_store8,
                .i64_store16,
                .i64_store32,
                => true,
                else => false,
            };
        }

        fn scalarMemAccessSize(tag: Inst.Tag) ?u8 {
            return switch (tag) {
                .i32_load8_s,
                .i32_load8_u,
                .i64_load8_s,
                .i64_load8_u,
                .i32_store8,
                .i64_store8,
                => 1,
                .i32_load16_s,
                .i32_load16_u,
                .i64_load16_s,
                .i64_load16_u,
                .i32_store16,
                .i64_store16,
                => 2,
                .i32_load,
                .f32_load,
                .i64_load32_s,
                .i64_load32_u,
                .i32_store,
                .f32_store,
                .i64_store32,
                => 4,
                .i64_load,
                .f64_load,
                .i64_store,
                .f64_store,
                => 8,
                else => null,
            };
        }

        fn rangesOverlap(off_a: u64, size_a: u8, off_b: u64, size_b: u8) bool {
            const a0: u128 = off_a;
            const a1: u128 = a0 + size_a;
            const b0: u128 = off_b;
            const b1: u128 = b0 + size_b;
            return a0 < b1 and b0 < a1;
        }

        fn rangeContains(outer_off: u64, outer_size: u8, inner_off: u64, inner_size: u8) bool {
            const o0: u128 = outer_off;
            const o1: u128 = o0 + outer_size;
            const in0: u128 = inner_off;
            const in1: u128 = in0 + inner_size;
            return o0 <= in0 and in1 <= o1;
        }

        fn invalidateTrackedLocal(entries: *std.ArrayList(TrackedMemEntry), local: u32) void {
            var idx: usize = entries.items.len;
            while (idx > 0) {
                idx -= 1;
                const e = entries.items[idx];
                if (e.base_local == local or (e.val_inst.tag == .local_get and e.val_inst.data.local == local)) {
                    _ = entries.orderedRemove(idx);
                }
            }
        }

        fn tryForwardLoad(
            gpa: Allocator,
            out: *std.ArrayList(Inst),
            mir_extra: *std.ArrayList(u32),
            entry: TrackedMemEntry,
            load_tag: Inst.Tag,
            load_off: u64,
            load_size: u8,
        ) Allocator.Error!bool {
            if (entry.store_or_load_tag == .drop) return false;

            if (load_off == entry.offset and load_size == entry.size) {
                switch (load_tag) {
                    .i32_load => {
                        if (entry.store_or_load_tag == .i32_store or entry.store_or_load_tag == .i32_load) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            return true;
                        }
                    },
                    .i64_load => {
                        if (entry.store_or_load_tag == .i64_store or entry.store_or_load_tag == .i64_load) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            return true;
                        }
                    },
                    .f32_load => {
                        if (entry.store_or_load_tag == .f32_store or entry.store_or_load_tag == .f32_load) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            return true;
                        }
                    },
                    .f64_load => {
                        if (entry.store_or_load_tag == .f64_store or entry.store_or_load_tag == .f64_load) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            return true;
                        }
                    },
                    .i32_load8_u => {
                        if (entry.store_or_load_tag == .i32_load8_u) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            return true;
                        }
                        if (entry.store_or_load_tag == .i32_store8 or entry.store_or_load_tag == .i32_load8_s) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            out.appendAssumeCapacity(makeI32Const(0xFF));
                            out.appendAssumeCapacity(.{ .tag = .i32_and, .data = .{ .tag = {} } });
                            return true;
                        }
                    },
                    .i32_load16_u => {
                        if (entry.store_or_load_tag == .i32_load16_u) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            return true;
                        }
                        if (entry.store_or_load_tag == .i32_store16 or entry.store_or_load_tag == .i32_load16_s) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            out.appendAssumeCapacity(makeI32Const(0xFFFF));
                            out.appendAssumeCapacity(.{ .tag = .i32_and, .data = .{ .tag = {} } });
                            return true;
                        }
                    },
                    .i64_load8_u => {
                        if (entry.store_or_load_tag == .i64_load8_u) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            return true;
                        }
                        if (entry.store_or_load_tag == .i64_store8 or entry.store_or_load_tag == .i64_load8_s) {
                            const mask = try makeI64Const(gpa, mir_extra, 0xFF);
                            out.items[out.items.len - 1] = entry.val_inst;
                            out.appendAssumeCapacity(mask);
                            out.appendAssumeCapacity(.{ .tag = .i64_and, .data = .{ .tag = {} } });
                            return true;
                        }
                    },
                    .i64_load16_u => {
                        if (entry.store_or_load_tag == .i64_load16_u) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            return true;
                        }
                        if (entry.store_or_load_tag == .i64_store16 or entry.store_or_load_tag == .i64_load16_s) {
                            const mask = try makeI64Const(gpa, mir_extra, 0xFFFF);
                            out.items[out.items.len - 1] = entry.val_inst;
                            out.appendAssumeCapacity(mask);
                            out.appendAssumeCapacity(.{ .tag = .i64_and, .data = .{ .tag = {} } });
                            return true;
                        }
                    },
                    .i64_load32_u => {
                        if (entry.store_or_load_tag == .i64_load32_u) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            return true;
                        }
                        if (entry.store_or_load_tag == .i64_store32 or entry.store_or_load_tag == .i64_load32_s) {
                            const mask = try makeI64Const(gpa, mir_extra, 0xFFFF_FFFF);
                            out.items[out.items.len - 1] = entry.val_inst;
                            out.appendAssumeCapacity(mask);
                            out.appendAssumeCapacity(.{ .tag = .i64_and, .data = .{ .tag = {} } });
                            return true;
                        }
                    },
                    .i32_load8_s => {
                        if (entry.store_or_load_tag == .i32_load8_s) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            return true;
                        }
                        if (entry.store_or_load_tag == .i32_store8 or entry.store_or_load_tag == .i32_load8_u) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            out.appendAssumeCapacity(.{ .tag = .i32_extend8_s, .data = .{ .tag = {} } });
                            return true;
                        }
                    },
                    .i32_load16_s => {
                        if (entry.store_or_load_tag == .i32_load16_s) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            return true;
                        }
                        if (entry.store_or_load_tag == .i32_store16 or entry.store_or_load_tag == .i32_load16_u) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            out.appendAssumeCapacity(.{ .tag = .i32_extend16_s, .data = .{ .tag = {} } });
                            return true;
                        }
                    },
                    .i64_load8_s => {
                        if (entry.store_or_load_tag == .i64_load8_s) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            return true;
                        }
                        if (entry.store_or_load_tag == .i64_store8 or entry.store_or_load_tag == .i64_load8_u) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            out.appendAssumeCapacity(.{ .tag = .i64_extend8_s, .data = .{ .tag = {} } });
                            return true;
                        }
                    },
                    .i64_load16_s => {
                        if (entry.store_or_load_tag == .i64_load16_s) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            return true;
                        }
                        if (entry.store_or_load_tag == .i64_store16 or entry.store_or_load_tag == .i64_load16_u) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            out.appendAssumeCapacity(.{ .tag = .i64_extend16_s, .data = .{ .tag = {} } });
                            return true;
                        }
                    },
                    .i64_load32_s => {
                        if (entry.store_or_load_tag == .i64_load32_s) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            return true;
                        }
                        if (entry.store_or_load_tag == .i64_store32 or entry.store_or_load_tag == .i64_load32_u) {
                            out.items[out.items.len - 1] = entry.val_inst;
                            out.appendAssumeCapacity(.{ .tag = .i64_extend32_s, .data = .{ .tag = {} } });
                            return true;
                        }
                    },
                    else => {},
                }
            } else if (load_size < entry.size) {
                const is_i32_source = switch (entry.store_or_load_tag) {
                    .i32_store, .i32_load, .i32_store16, .i32_load16_u, .i32_load16_s => true,
                    else => false,
                };
                const is_i32_subload = switch (load_tag) {
                    .i32_load8_u, .i32_load8_s, .i32_load16_u, .i32_load16_s => true,
                    else => false,
                };
                if (is_i32_source and is_i32_subload) {
                    const bit_shift: i32 = @intCast((load_off - entry.offset) * 8);
                    out.items[out.items.len - 1] = entry.val_inst;
                    if (bit_shift > 0) {
                        out.appendAssumeCapacity(makeI32Const(bit_shift));
                        out.appendAssumeCapacity(.{ .tag = .i32_shr_u, .data = .{ .tag = {} } });
                    }
                    switch (load_tag) {
                        .i32_load8_u => {
                            out.appendAssumeCapacity(makeI32Const(0xFF));
                            out.appendAssumeCapacity(.{ .tag = .i32_and, .data = .{ .tag = {} } });
                        },
                        .i32_load16_u => {
                            out.appendAssumeCapacity(makeI32Const(0xFFFF));
                            out.appendAssumeCapacity(.{ .tag = .i32_and, .data = .{ .tag = {} } });
                        },
                        .i32_load8_s => {
                            out.appendAssumeCapacity(.{ .tag = .i32_extend8_s, .data = .{ .tag = {} } });
                        },
                        .i32_load16_s => {
                            out.appendAssumeCapacity(.{ .tag = .i32_extend16_s, .data = .{ .tag = {} } });
                        },
                        else => unreachable,
                    }
                    return true;
                }
            }
            return false;
        }

        fn optimizeMemoryAccesses(
            gpa: Allocator,
            out: *std.ArrayList(Inst),
            insts: []const Inst,
            mir_extra: *std.ArrayList(u32),
        ) Allocator.Error!bool {
            out.clearRetainingCapacity();
            try out.ensureTotalCapacity(gpa, insts.len);

            var tracked_entries: std.ArrayList(TrackedMemEntry) = .empty;
            defer tracked_entries.deinit(gpa);

            var changed = false;
            var i: usize = 0;
            while (i < insts.len) {
                try out.ensureUnusedCapacity(gpa, 8);
                const inst = insts[i];

                if (isScalarStoreTag(inst.tag)) {
                    const size = scalarMemAccessSize(inst.tag).?;
                    const off = readMemArgOffset(mir_extra.items, inst.data.payload);

                    if (findValStartIndex(out.items, mir_extra.items)) |orig_val_start| {
                        if (orig_val_start >= 1 and out.items[orig_val_start - 1].tag == .local_get) {
                            var addr_idx = orig_val_start - 1;
                            var val_start = orig_val_start;
                            const base_local = out.items[addr_idx].data.local;

                            // Overwrite DSE: check if any active entry on `base_local` is covered by `[off, off + size)`
                            // and has not been observed by any load or branch since it was emitted.
                            var e_idx: usize = tracked_entries.items.len;
                            while (e_idx > 0) {
                                e_idx -= 1;
                                const entry = tracked_entries.items[e_idx];
                                if (entry.base_local == base_local and
                                    rangeContains(off, size, entry.offset, entry.size) and
                                    entry.store_out_start != null)
                                {
                                    const dead_start = entry.store_out_start.?;
                                    const dead_end = entry.store_out_end.?;
                                    const removed_len = dead_end - dead_start;
                                    std.mem.copyForwards(Inst, out.items[dead_start..], out.items[dead_end..]);
                                    out.items.len -= removed_len;
                                    addr_idx -= removed_len;
                                    val_start -= removed_len;

                                    for (tracked_entries.items) |*other| {
                                        if (other.store_out_start) |s| {
                                            if (s >= dead_end) {
                                                other.store_out_start = s - removed_len;
                                                other.store_out_end = other.store_out_end.? - removed_len;
                                            } else if (s >= dead_start) {
                                                other.store_out_start = null;
                                                other.store_out_end = null;
                                            }
                                        }
                                    }
                                    _ = tracked_entries.orderedRemove(e_idx);
                                    changed = true;
                                }
                            }

                            // Remove any existing tracked entries that overlap `[off, off + size)` on `base_local`
                            // (or are on a different `base_local` that could alias), while preserving non-overlapping
                            // entries on `base_local`.
                            e_idx = tracked_entries.items.len;
                            while (e_idx > 0) {
                                e_idx -= 1;
                                const entry = tracked_entries.items[e_idx];
                                if (entry.base_local != base_local or rangesOverlap(entry.offset, entry.size, off, size)) {
                                    _ = tracked_entries.orderedRemove(e_idx);
                                }
                            }

                            var val_is_pure = true;
                            for (out.items[val_start..]) |v_inst| {
                                if (v_inst.tag != .dbg_line and pureNonTrappingInstPops(v_inst, mir_extra.items) == null) {
                                    val_is_pure = false;
                                    break;
                                }
                            }

                            const val_tag = out.items[val_start].tag;
                            const is_single_zero_pop = (val_start + 1 == out.items.len) and
                                ((isConstTag(val_tag) and val_tag != .error_name_table_ref) or
                                    (val_tag == .local_get and out.items[val_start].data.local != base_local));
                            const val_inst: Inst = if (is_single_zero_pop) out.items[val_start] else .{ .tag = .drop, .data = .{ .tag = {} } };

                            out.appendAssumeCapacity(inst);
                            if (is_single_zero_pop or val_is_pure) {
                                try tracked_entries.append(gpa, .{
                                    .base_local = base_local,
                                    .offset = off,
                                    .size = size,
                                    .store_or_load_tag = if (is_single_zero_pop) inst.tag else .drop,
                                    .val_inst = val_inst,
                                    .store_out_start = if (val_is_pure) addr_idx else null,
                                    .store_out_end = if (val_is_pure) out.items.len else null,
                                });
                            }
                            i += 1;
                            continue;
                        }
                    }

                    tracked_entries.clearRetainingCapacity();
                    out.appendAssumeCapacity(inst);
                    i += 1;
                    continue;
                }

                if (isScalarLoadTag(inst.tag)) {
                    const size = scalarMemAccessSize(inst.tag).?;
                    const off = readMemArgOffset(mir_extra.items, inst.data.payload);

                    if (out.items.len >= 1 and out.items[out.items.len - 1].tag == .local_get) {
                        const base_local = out.items[out.items.len - 1].data.local;

                        for (tracked_entries.items) |*entry| {
                            if (entry.base_local != base_local or rangesOverlap(entry.offset, entry.size, off, size)) {
                                entry.store_out_start = null;
                                entry.store_out_end = null;
                            }
                        }

                        var forwarded = false;
                        var e_idx: usize = tracked_entries.items.len;
                        while (e_idx > 0) {
                            e_idx -= 1;
                            const entry = tracked_entries.items[e_idx];
                            if (entry.base_local == base_local and rangeContains(entry.offset, entry.size, off, size)) {
                                if (try tryForwardLoad(gpa, out, mir_extra, entry, inst.tag, off, size)) {
                                    forwarded = true;
                                    changed = true;
                                    break;
                                }
                            }
                        }
                        if (forwarded) {
                            i += 1;
                            continue;
                        }

                        out.appendAssumeCapacity(inst);
                        if (i + 1 < insts.len and
                            (insts[i + 1].tag == .local_set or insts[i + 1].tag == .local_tee))
                        {
                            const v_local = insts[i + 1].data.local;
                            invalidateTrackedLocal(&tracked_entries, v_local);
                            out.appendAssumeCapacity(insts[i + 1]);
                            if (v_local != base_local) {
                                var r_idx: usize = tracked_entries.items.len;
                                while (r_idx > 0) {
                                    r_idx -= 1;
                                    const entry = tracked_entries.items[r_idx];
                                    if (entry.base_local == base_local and rangesOverlap(entry.offset, entry.size, off, size)) {
                                        _ = tracked_entries.orderedRemove(r_idx);
                                    }
                                }
                                try tracked_entries.append(gpa, .{
                                    .base_local = base_local,
                                    .offset = off,
                                    .size = size,
                                    .store_or_load_tag = inst.tag,
                                    .val_inst = .{ .tag = .local_get, .data = .{ .local = v_local } },
                                    .store_out_start = null,
                                    .store_out_end = null,
                                });
                            }
                            i += 2;
                            continue;
                        }
                        i += 1;
                        continue;
                    }

                    for (tracked_entries.items) |*entry| {
                        entry.store_out_start = null;
                        entry.store_out_end = null;
                    }
                    out.appendAssumeCapacity(inst);
                    i += 1;
                    continue;
                }

                switch (inst.tag) {
                    .local_set, .local_tee => {
                        invalidateTrackedLocal(&tracked_entries, inst.data.local);
                    },
                    .br_if => {
                        for (tracked_entries.items) |*entry| {
                            entry.store_out_start = null;
                            entry.store_out_end = null;
                        }
                    },
                    .call_intrinsic => {
                        if (pureScalarIntrinsicPops(inst.data.intrinsic) == null) {
                            tracked_entries.clearRetainingCapacity();
                        }
                    },
                    .block,
                    .loop,
                    .end,
                    .br,
                    .br_table,
                    .@"return",
                    .return_call_nav,
                    .return_call_indirect,
                    .@"unreachable",
                    .call_nav,
                    .call_indirect,
                    .call_tag_index,
                    .memory_grow,
                    .atomics_prefix,
                    .misc_prefix,
                    .cont_new,
                    .cont_bind,
                    .@"suspend",
                    .@"resume",
                    .resume_throw,
                    .resume_throw_ref,
                    .@"switch",
                    => {
                        tracked_entries.clearRetainingCapacity();
                    },
                    .simd_prefix => {
                        if (memOpInfo(inst, mir_extra.items)) |info| {
                            if (info.val_operands == 0) {
                                for (tracked_entries.items) |*entry| {
                                    entry.store_out_start = null;
                                    entry.store_out_end = null;
                                }
                            } else {
                                tracked_entries.clearRetainingCapacity();
                            }
                        } else {
                            const opcode = mir_extra.items[inst.data.payload];
                            switch (@as(std.wasm.SimdOpcode, @fromBackingInt(opcode))) {
                                .v128_store,
                                .v128_store8_lane,
                                .v128_store16_lane,
                                .v128_store32_lane,
                                .v128_store64_lane,
                                => tracked_entries.clearRetainingCapacity(),
                                .v128_load8_lane,
                                .v128_load16_lane,
                                .v128_load32_lane,
                                .v128_load64_lane,
                                => {
                                    for (tracked_entries.items) |*entry| {
                                        entry.store_out_start = null;
                                        entry.store_out_end = null;
                                    }
                                },
                                else => {},
                            }
                        }
                    },
                    else => {},
                }

                out.appendAssumeCapacity(inst);
                i += 1;
            }

            return changed;
        }

        fn simplifyControlFlow(
            gpa: Allocator,
            current: *std.ArrayList(Inst),
            scratch: *std.ArrayList(Inst),
            mir_extra: *std.ArrayList(u32),
        ) Allocator.Error!bool {
            var changed = false;

            if (try foldConstantBranches(gpa, current.items, scratch, mir_extra.items)) {
                std.mem.swap(std.ArrayList(Inst), current, scratch);
                changed = true;

                // Clean up any unreachable instructions exposed by `br_if` -> `br` before simplifying blocks.
                if (try Self.eliminateDeadCode(gpa, current.items, scratch)) {
                    std.mem.swap(std.ArrayList(Inst), current, scratch);
                }
            }

            if (try simplifyBlocks(gpa, current.items, scratch, mir_extra)) {
                std.mem.swap(std.ArrayList(Inst), current, scratch);
                changed = true;
            }

            return changed;
        }

        fn foldConstantBranches(
            gpa: Allocator,
            insts: []const Inst,
            out: *std.ArrayList(Inst),
            mir_extra: []const u32,
        ) Allocator.Error!bool {
            out.clearRetainingCapacity();
            try out.ensureTotalCapacity(gpa, insts.len);

            var changed = false;

            for (insts) |inst| {
                const len = out.items.len;

                if (inst.tag == .br_if) {
                    if (len >= 1 and out.items[len - 1].tag == .i32_const) {
                        const cond = out.items[len - 1].data.imm32;
                        const label = inst.data.label;
                        if (cond == 0) {
                            _ = out.pop();
                        } else {
                            out.items[len - 1] = .{ .tag = .br, .data = .{ .label = label } };
                        }
                        changed = true;
                        continue;
                    }
                    if (len >= 2 and out.items[len - 2].tag == .i32_const and out.items[len - 1].tag == .local_tee) {
                        const cond = out.items[len - 2].data.imm32;
                        const label = inst.data.label;
                        out.items[len - 1].tag = .local_set;
                        if (cond != 0) {
                            out.appendAssumeCapacity(.{ .tag = .br, .data = .{ .label = label } });
                        }
                        changed = true;
                        continue;
                    }
                    if (len >= 2 and
                        ((out.items[len - 2].tag == .i32_const and out.items[len - 2].data.imm32 == 0 and out.items[len - 1].tag == .i32_ne) or
                            (out.items[len - 2].tag == .i32_eqz and out.items[len - 1].tag == .i32_eqz)))
                    {
                        out.items.len = len - 2;
                        out.appendAssumeCapacity(inst);
                        changed = true;
                        continue;
                    }
                    if (len >= 1 and out.items[len - 1].tag == .i32_xor) {
                        out.items[len - 1].tag = .i32_ne;
                        out.appendAssumeCapacity(inst);
                        changed = true;
                        continue;
                    }
                }

                if (inst.tag == .br_table) {
                    if (len >= 1 and out.items[len - 1].tag == .i32_const) {
                        const c = out.items[len - 1].data.imm32;
                        const payload = inst.data.payload;
                        const table_len = mir_extra[payload];
                        if (table_len >= 1) {
                            const targets = mir_extra[payload + 1 ..][0..table_len];
                            const idx: u32 = @bitCast(c);
                            const target = if (idx < table_len - 1) targets[idx] else targets[table_len - 1];
                            out.items[len - 1] = .{ .tag = .br, .data = .{ .label = target } };
                            changed = true;
                            continue;
                        }
                    }
                    if (len >= 2 and out.items[len - 2].tag == .i32_const and out.items[len - 1].tag == .local_tee) {
                        const c = out.items[len - 2].data.imm32;
                        const payload = inst.data.payload;
                        const table_len = mir_extra[payload];
                        if (table_len >= 1) {
                            const targets = mir_extra[payload + 1 ..][0..table_len];
                            const idx: u32 = @bitCast(c);
                            const target = if (idx < table_len - 1) targets[idx] else targets[table_len - 1];
                            out.items[len - 1].tag = .local_set;
                            out.appendAssumeCapacity(.{ .tag = .br, .data = .{ .label = target } });
                            changed = true;
                            continue;
                        }
                    }
                }

                out.appendAssumeCapacity(inst);
            }

            return changed;
        }

        fn simplifyBlocks(
            gpa: Allocator,
            insts: []const Inst,
            out: *std.ArrayList(Inst),
            mir_extra: *std.ArrayList(u32),
        ) Allocator.Error!bool {
            out.clearRetainingCapacity();
            try out.ensureTotalCapacity(gpa, insts.len);

            var changed = false;
            var i: usize = 0;
            while (i < insts.len) {
                const inst = insts[i];
                if (inst.tag == .block) {
                    if (findMatchingEnd(insts, i)) |end_idx| {
                        const body = insts[i + 1 .. end_idx];

                        // Pattern 1: `block (.empty)` whose body is solely `br 0` (ignoring `.dbg_line`
                        // and `<const>; local_set` pairs).
                        if (inst.data.block_type == .empty) {
                            if (findSoleBr0(body)) |br_pos| {
                                try out.appendSlice(gpa, body[0..br_pos]);
                                try out.appendSlice(gpa, body[br_pos + 1 ..]);
                                i = end_idx + 1;
                                changed = true;
                                continue;
                            }
                        }

                        // Pattern 2: `block` whose body has no branch targeting depth 0.
                        if (!hasBranchToDepth(body, mir_extra.items, 0) and
                            (inst.data.block_type == .empty or !hasUnconditionalControlTransfer(body)))
                        {
                            const start_len = out.items.len;
                            try out.appendSlice(gpa, body);
                            try decrementOuterBranches(gpa, out.items[start_len..], mir_extra, 0);
                            i = end_idx + 1;
                            changed = true;
                            continue;
                        }
                    }
                }

                try out.append(gpa, inst);
                i += 1;
            }

            return changed;
        }

        fn findMatchingEnd(insts: []const Inst, block_idx: usize) ?usize {
            var depth: usize = 0;
            var j: usize = block_idx + 1;
            while (j < insts.len) : (j += 1) {
                switch (insts[j].tag) {
                    .block, .loop => depth += 1,
                    .end => {
                        if (depth == 0) return j;
                        depth -= 1;
                    },
                    else => {},
                }
            }
            return null;
        }

        fn findSoleBr0(body: []const Inst) ?usize {
            var br_idx: ?usize = null;
            var idx: usize = 0;
            while (idx < body.len) : (idx += 1) {
                const inst = body[idx];
                if (inst.tag == .br and inst.data.label == 0) {
                    if (br_idx != null) return null;
                    br_idx = idx;
                } else if (inst.tag == .dbg_line) {
                    continue;
                } else if (br_idx == null and (isConstTag(inst.tag) or inst.tag == .local_get) and idx + 1 < body.len and body[idx + 1].tag == .local_set) {
                    idx += 1;
                } else {
                    return null;
                }
            }
            return br_idx;
        }

        fn hasBranchToDepth(body: []const Inst, mir_extra: []const u32, initial_depth: u32) bool {
            var depth: u32 = initial_depth;
            for (body) |inst| {
                switch (inst.tag) {
                    .block, .loop => depth += 1,
                    .end => {
                        if (depth == initial_depth) return true;
                        depth -= 1;
                    },
                    .br, .br_if => {
                        if (inst.data.label == depth) return true;
                    },
                    .br_table => {
                        const payload = inst.data.payload;
                        const table_len = mir_extra[payload];
                        const targets = mir_extra[payload + 1 ..][0..table_len];
                        for (targets) |t| {
                            if (t == depth) return true;
                        }
                    },
                    else => {},
                }
            }
            return false;
        }

        fn hasUnconditionalControlTransfer(body: []const Inst) bool {
            for (body) |inst| {
                switch (inst.tag) {
                    .@"unreachable", .br, .br_table, .@"return", .return_call_nav, .return_call_indirect => return true,
                    else => {},
                }
            }
            return false;
        }

        fn decrementOuterBranches(
            gpa: Allocator,
            body: []Inst,
            mir_extra: *std.ArrayList(u32),
            initial_depth: u32,
        ) Allocator.Error!void {
            var depth: u32 = initial_depth;
            for (body) |*inst| {
                switch (inst.tag) {
                    .block, .loop => depth += 1,
                    .end => {
                        assert(depth > initial_depth);
                        depth -= 1;
                    },
                    .br, .br_if => {
                        if (inst.data.label > depth) {
                            inst.data.label -= 1;
                        }
                    },
                    .br_table => {
                        const payload = inst.data.payload;
                        const table_len = mir_extra.items[payload];
                        var needs_update = false;
                        for (mir_extra.items[payload + 1 ..][0..table_len]) |t| {
                            if (t > depth) {
                                needs_update = true;
                                break;
                            }
                        }
                        if (needs_update) {
                            const new_payload: u32 = @intCast(mir_extra.items.len);
                            try mir_extra.ensureUnusedCapacity(gpa, 1 + table_len);
                            mir_extra.appendAssumeCapacity(table_len);
                            var k: usize = 0;
                            while (k < table_len) : (k += 1) {
                                const t = mir_extra.items[payload + 1 + k];
                                mir_extra.appendAssumeCapacity(if (t > depth) t - 1 else t);
                            }
                            inst.data.payload = new_payload;
                        }
                    },
                    else => {},
                }
            }
        }

        fn eliminateDeadCode(
            gpa: Allocator,
            insts: []const Inst,
            out: *std.ArrayList(Inst),
        ) Allocator.Error!bool {
            out.clearRetainingCapacity();
            try out.ensureTotalCapacity(gpa, insts.len);

            var changed = false;
            var depth: u32 = 0;
            var dead_until_depth: ?u32 = null;

            for (insts) |inst| {
                if (dead_until_depth) |d_dead| {
                    switch (inst.tag) {
                        .block, .loop => {
                            depth += 1;
                            changed = true;
                        },
                        .end => {
                            if (depth == 0) {
                                dead_until_depth = null;
                                out.appendAssumeCapacity(inst);
                            } else if (depth == d_dead) {
                                depth -= 1;
                                dead_until_depth = null;
                                out.appendAssumeCapacity(inst);
                            } else {
                                depth -= 1;
                                changed = true;
                            }
                        },
                        else => {
                            changed = true;
                        },
                    }
                    continue;
                }

                switch (inst.tag) {
                    .block, .loop => {
                        depth += 1;
                        out.appendAssumeCapacity(inst);
                    },
                    .end => {
                        if (depth > 0) depth -= 1;
                        out.appendAssumeCapacity(inst);
                    },
                    .@"unreachable", .br, .br_table, .@"return", .return_call_nav, .return_call_indirect => {
                        out.appendAssumeCapacity(inst);
                        dead_until_depth = depth;
                    },
                    else => {
                        out.appendAssumeCapacity(inst);
                    },
                }
            }

            return changed;
        }

        const valtypes = [5]std.wasm.Valtype{ .i32, .i64, .f32, .f64, .v128 };

        fn valtypeBucket(vt: std.wasm.Valtype) usize {
            return switch (vt) {
                .i32 => 0,
                .i64 => 1,
                .f32 => 2,
                .f64 => 3,
                .v128 => 4,
            };
        }

        fn compactLocals(
            gpa: Allocator,
            mir_instructions: *std.MultiArrayList(Inst),
            mir_locals: *std.ArrayList(std.wasm.Valtype),
            wasm_param_count: u32,
            bottom_stack_local: ?*u32,
            sp_local: ?*u32,
        ) Allocator.Error!void {
            if (mir_locals.items.len == 0) return;

            const remap = try gpa.alloc(u32, mir_locals.items.len);
            defer gpa.free(remap);
            @memset(remap, std.math.maxInt(u32));

            if (bottom_stack_local) |bsl| {
                assert(bsl.* >= wasm_param_count);
                remap[bsl.* - wasm_param_count] = 0;
            }
            if (sp_local) |spl| {
                assert(spl.* >= wasm_param_count);
                remap[spl.* - wasm_param_count] = 0;
            }

            const tags = mir_instructions.items(.tag);
            const datas = mir_instructions.items(.data);
            for (tags, datas) |tag, data| {
                switch (tag) {
                    .local_get, .local_set, .local_tee => {
                        if (data.local >= wasm_param_count) {
                            const slot = data.local - wasm_param_count;
                            if (slot < remap.len) {
                                remap[slot] = 0;
                            }
                        }
                    },
                    else => {},
                }
            }

            var counts: [5]u32 = @splat(0);
            for (mir_locals.items, remap) |vt, slot_remap| {
                if (slot_remap == 0) {
                    counts[valtypeBucket(vt)] += 1;
                }
            }

            var next_idx: [5]u32 = undefined;
            var total_live: u32 = 0;
            for (&next_idx, counts) |*dst, c| {
                dst.* = wasm_param_count + total_live;
                total_live += c;
            }

            for (mir_locals.items, remap) |vt, *slot_remap| {
                if (slot_remap.* == 0) {
                    const b = valtypeBucket(vt);
                    slot_remap.* = next_idx[b];
                    next_idx[b] += 1;
                }
            }

            var write_pos: usize = 0;
            for (valtypes, counts) |vt, c| {
                @memset(mir_locals.items[write_pos..][0..c], vt);
                write_pos += c;
            }
            assert(write_pos == total_live);
            mir_locals.shrinkRetainingCapacity(total_live);

            if (bottom_stack_local) |bsl| {
                bsl.* = remap[bsl.* - wasm_param_count];
            }
            if (sp_local) |spl| {
                spl.* = remap[spl.* - wasm_param_count];
            }

            for (tags, datas) |tag, *data| {
                switch (tag) {
                    .local_get, .local_set, .local_tee => {
                        if (data.local >= wasm_param_count) {
                            const slot = data.local - wasm_param_count;
                            if (slot < remap.len) {
                                data.local = remap[slot];
                            }
                        }
                    },
                    else => {},
                }
            }
        }
    };
}

const Mir = StandaloneMir;

// ============================================================================
// Standalone Mir definition for direct `zig test src/codegen/wasm/Optimize.zig`
// (When imported from `Mir.zig` / `CodeGen.zig`, `@import("Mir.zig")` is used.)
// ============================================================================

const StandaloneMir = struct {
    pub const Inst = struct {
        tag: Tag,
        data: Data,

        pub const Index = u32;

        pub const Tag = enum(u8) {
            @"unreachable" = 0x00,
            dbg_epilogue_begin,
            block = 0x02,
            loop = 0x03,
            uav_ref,
            uav_ref_off,
            nav_ref,
            nav_ref_off,
            func_ref,
            dbg_line,
            errors_len,
            end = 0x0B,
            br = 0x0C,
            br_if = 0x0D,
            br_table,
            @"return" = 0x0F,
            error_name_table_ref,
            call_nav,
            call_indirect,
            return_call_nav,
            return_call_indirect,
            call_tag_index,
            enum_tag_name_table_ref,
            call_intrinsic,
            tls_nav_ref,
            drop = 0x1A,
            select = 0x1B,
            local_get = 0x20,
            local_set = 0x21,
            local_tee = 0x22,
            global_get = 0x23,
            global_set = 0x24,
            global_set_sp,
            i32_load = 0x28,
            i64_load = 0x29,
            f32_load = 0x2A,
            f64_load = 0x2B,
            i32_load8_s = 0x2C,
            i32_load8_u = 0x2D,
            i32_load16_s = 0x2E,
            i32_load16_u = 0x2F,
            i64_load8_s = 0x30,
            i64_load8_u = 0x31,
            i64_load16_s = 0x32,
            i64_load16_u = 0x33,
            i64_load32_s = 0x34,
            i64_load32_u = 0x35,
            i32_store = 0x36,
            i64_store = 0x37,
            f32_store = 0x38,
            f64_store = 0x39,
            i32_store8 = 0x3A,
            i32_store16 = 0x3B,
            i64_store8 = 0x3C,
            i64_store16 = 0x3D,
            i64_store32 = 0x3E,
            memory_size = 0x3F,
            memory_grow = 0x40,
            i32_const,
            i64_const,
            f32_const,
            f64_const,
            i32_eqz = 0x45,
            i32_eq = 0x46,
            i32_ne = 0x47,
            i32_lt_s = 0x48,
            i32_lt_u = 0x49,
            i32_gt_s = 0x4A,
            i32_gt_u = 0x4B,
            i32_le_s = 0x4C,
            i32_le_u = 0x4D,
            i32_ge_s = 0x4E,
            i32_ge_u = 0x4F,
            i64_eqz = 0x50,
            i64_eq = 0x51,
            i64_ne = 0x52,
            i64_lt_s = 0x53,
            i64_lt_u = 0x54,
            i64_gt_s = 0x55,
            i64_gt_u = 0x56,
            i64_le_s = 0x57,
            i64_le_u = 0x58,
            i64_ge_s = 0x59,
            i64_ge_u = 0x5A,
            f32_eq = 0x5B,
            f32_ne = 0x5C,
            f32_lt = 0x5D,
            f32_gt = 0x5E,
            f32_le = 0x5F,
            f32_ge = 0x60,
            f64_eq = 0x61,
            f64_ne = 0x62,
            f64_lt = 0x63,
            f64_gt = 0x64,
            f64_le = 0x65,
            f64_ge = 0x66,
            i32_clz = 0x67,
            i32_ctz = 0x68,
            i32_popcnt = 0x69,
            i32_add = 0x6A,
            i32_sub = 0x6B,
            i32_mul = 0x6C,
            i32_div_s = 0x6D,
            i32_div_u = 0x6E,
            i32_rem_s = 0x6F,
            i32_rem_u = 0x70,
            i32_and = 0x71,
            i32_or = 0x72,
            i32_xor = 0x73,
            i32_shl = 0x74,
            i32_shr_s = 0x75,
            i32_shr_u = 0x76,
            i32_rotl = 0x77,
            i32_rotr = 0x78,
            i64_clz = 0x79,
            i64_ctz = 0x7A,
            i64_popcnt = 0x7B,
            i64_add = 0x7C,
            i64_sub = 0x7D,
            i64_mul = 0x7E,
            i64_div_s = 0x7F,
            i64_div_u = 0x80,
            i64_rem_s = 0x81,
            i64_rem_u = 0x82,
            i64_and = 0x83,
            i64_or = 0x84,
            i64_xor = 0x85,
            i64_shl = 0x86,
            i64_shr_s = 0x87,
            i64_shr_u = 0x88,
            i64_rotl = 0x89,
            i64_rotr = 0x8A,
            f32_abs = 0x8B,
            f32_neg = 0x8C,
            f32_ceil = 0x8D,
            f32_floor = 0x8E,
            f32_trunc = 0x8F,
            f32_nearest = 0x90,
            f32_sqrt = 0x91,
            f32_add = 0x92,
            f32_sub = 0x93,
            f32_mul = 0x94,
            f32_div = 0x95,
            f32_min = 0x96,
            f32_max = 0x97,
            f32_copysign = 0x98,
            f64_abs = 0x99,
            f64_neg = 0x9A,
            f64_ceil = 0x9B,
            f64_floor = 0x9C,
            f64_trunc = 0x9D,
            f64_nearest = 0x9E,
            f64_sqrt = 0x9F,
            f64_add = 0xA0,
            f64_sub = 0xA1,
            f64_mul = 0xA2,
            f64_div = 0xA3,
            f64_min = 0xA4,
            f64_max = 0xA5,
            f64_copysign = 0xA6,
            i32_wrap_i64 = 0xA7,
            i32_trunc_f32_s = 0xA8,
            i32_trunc_f32_u = 0xA9,
            i32_trunc_f64_s = 0xAA,
            i32_trunc_f64_u = 0xAB,
            i64_extend_i32_s = 0xAC,
            i64_extend_i32_u = 0xAD,
            i64_trunc_f32_s = 0xAE,
            i64_trunc_f32_u = 0xAF,
            i64_trunc_f64_s = 0xB0,
            i64_trunc_f64_u = 0xB1,
            f32_convert_i32_s = 0xB2,
            f32_convert_i32_u = 0xB3,
            f32_convert_i64_s = 0xB4,
            f32_convert_i64_u = 0xB5,
            f32_demote_f64 = 0xB6,
            f64_convert_i32_s = 0xB7,
            f64_convert_i32_u = 0xB8,
            f64_convert_i64_s = 0xB9,
            f64_convert_i64_u = 0xBA,
            f64_promote_f32 = 0xBB,
            i32_reinterpret_f32 = 0xBC,
            i64_reinterpret_f64 = 0xBD,
            f32_reinterpret_i32 = 0xBE,
            f64_reinterpret_i64 = 0xBF,
            i32_extend8_s = 0xC0,
            i32_extend16_s = 0xC1,
            i64_extend8_s = 0xC2,
            i64_extend16_s = 0xC3,
            i64_extend32_s = 0xC4,
            cont_new = 0xE0,
            cont_bind = 0xE1,
            @"suspend" = 0xE2,
            @"resume" = 0xE3,
            resume_throw = 0xE4,
            resume_throw_ref = 0xE5,
            @"switch" = 0xE6,
            misc_prefix = 0xFC,
            simd_prefix = 0xFD,
            atomics_prefix = 0xFE,
        };

        pub const Data = union {
            tag: void,
            block_type: std.wasm.BlockType,
            label: u32,
            local: u32,
            imm32: i32,
            float32: f32,
            payload: u32,
            intrinsic: Intrinsic,
        };
    };

    pub const Intrinsic = enum(u32) {
        __addhf3,
        __addtf3,
        __addxf3,
        __bitreversedi2,
        __bitreversesi2,
        __bswapdi2,
        __bswapsi2,
        __ceilh,
        __ceilx,
        __cosh,
        __cosx,
        __divei5,
        __divhf3,
        __divtf3,
        __divti3,
        __divxf3,
        __eqtf2,
        __eqxf2,
        __exp2h,
        __exp2x,
        __exph,
        __expx,
        __extenddftf2,
        __extenddfxf2,
        __extendhfsf2,
        __extendhftf2,
        __extendhfxf2,
        __extendsftf2,
        __extendsfxf2,
        __extendxftf2,
        __fabsh,
        __fabsx,
        __fixdfdi,
        __fixdfei,
        __fixdfsi,
        __fixdfti,
        __fixhfdi,
        __fixhfei,
        __fixhfsi,
        __fixhfti,
        __fixsfdi,
        __fixsfei,
        __fixsfsi,
        __fixsfti,
        __fixtfdi,
        __fixtfei,
        __fixtfsi,
        __fixtfti,
        __fixunsdfdi,
        __fixunsdfei,
        __fixunsdfsi,
        __fixunsdfti,
        __fixunshfdi,
        __fixunshfei,
        __fixunshfsi,
        __fixunshfti,
        __fixunssfdi,
        __fixunssfei,
        __fixunssfsi,
        __fixunssfti,
        __fixunstfdi,
        __fixunstfei,
        __fixunstfsi,
        __fixunstfti,
        __fixunsxfdi,
        __fixunsxfei,
        __fixunsxfsi,
        __fixunsxfti,
        __fixxfdi,
        __fixxfei,
        __fixxfsi,
        __fixxfti,
        __floatdidf,
        __floatdihf,
        __floatdisf,
        __floatditf,
        __floatdixf,
        __floateidf,
        __floateihf,
        __floateisf,
        __floateitf,
        __floateixf,
        __floatsidf,
        __floatsihf,
        __floatsisf,
        __floatsitf,
        __floatsixf,
        __floattidf,
        __floattihf,
        __floattisf,
        __floattitf,
        __floattixf,
        __floatundidf,
        __floatundihf,
        __floatundisf,
        __floatunditf,
        __floatundixf,
        __floatuneidf,
        __floatuneihf,
        __floatuneisf,
        __floatuneitf,
        __floatuneixf,
        __floatunsidf,
        __floatunsihf,
        __floatunsisf,
        __floatunsitf,
        __floatunsixf,
        __floatuntidf,
        __floatuntihf,
        __floatuntisf,
        __floatuntitf,
        __floatuntixf,
        __floorh,
        __floorx,
        __fmah,
        __fmax,
        __fmaxh,
        __fmaxx,
        __fminh,
        __fminx,
        __fmodh,
        __fmodx,
        __getf2,
        __gexf2,
        __gttf2,
        __gtxf2,
        __letf2,
        __lexf2,
        __log10h,
        __log10x,
        __log2h,
        __log2x,
        __logh,
        __logx,
        __lttf2,
        __ltxf2,
        __modei5,
        __modti3,
        __mulhf3,
        __mulodi4,
        __muloti4,
        __multf3,
        __mulxf3,
        __netf2,
        __nexf2,
        __roundh,
        __roundx,
        __sinh,
        __sinx,
        __sqrth,
        __sqrtx,
        __subhf3,
        __subtf3,
        __subxf3,
        __tanh,
        __tanx,
        __trunch,
        __truncsfhf2,
        __trunctfdf2,
        __trunctfhf2,
        __trunctfsf2,
        __trunctfxf2,
        __truncx,
        __truncxfdf2,
        __truncxfhf2,
        __truncxfsf2,
        __udivei5,
        __udivti3,
        __umodei5,
        __umodti3,
        ceilf128,
        cos,
        cosf,
        cosf128,
        exp,
        exp2,
        exp2f,
        exp2f128,
        expf,
        expf128,
        fabsf128,
        floorf128,
        fma,
        fmaf,
        fmaf128,
        fmaxf128,
        fminf128,
        fmod,
        fmodf,
        fmodf128,
        log,
        log10,
        log10f,
        log10f128,
        log2,
        log2f,
        log2f128,
        logf,
        logf128,
        roundf128,
        sin,
        sinf,
        sinf128,
        sqrtf128,
        tan,
        tanf,
        tanf128,
        truncf128,
        memcpy,
        memmove,
        memset,
        __addo_limb64,
        __subo_limb64,
        __cmp_limb64,
        __and_limb64,
        __or_limb64,
        __xor_limb64,
        __not_limb64,
        __shlo_limb64,
        __shr_limb64,
        __clz_limb64,
        __ctz_limb64,
        __popcount_limb64,
        __bitreverse_limb64,
        __byteswap_limb64,
        __mulo_limb64,
        __abs_limb64,
    };

    pub const JumpTable = struct {
        length: u32,
    };

    pub const Imm64 = struct {
        msb: u32,
        lsb: u32,

        pub fn init(full: u64) Imm64 {
            return .{
                .msb = @truncate(full >> 32),
                .lsb = @truncate(full),
            };
        }

        pub fn toInt(i: Imm64) u64 {
            return (@as(u64, i.msb) << 32) | @as(u64, i.lsb);
        }
    };

    pub const Float64 = struct {
        msb: u32,
        lsb: u32,

        pub fn init(f: f64) Float64 {
            const int: u64 = @bitCast(f);
            return .{
                .msb = @truncate(int >> 32),
                .lsb = @truncate(int),
            };
        }

        pub fn toInt(f: Float64) u64 {
            return (@as(u64, f.msb) << 32) | @as(u64, f.lsb);
        }
    };

    pub const MemArg = struct {
        offset: u64,
        alignment: u32 = 2,
    };
};

// ============================================================================
// Unit Tests
// ============================================================================

const testing = std.testing;

const TestMir = struct {
    instructions: std.MultiArrayList(Mir.Inst) = .empty,
    extra: std.ArrayList(u32) = .empty,
    err_ref_count: u32 = 0,

    fn deinit(self: *TestMir) void {
        self.instructions.deinit(testing.allocator);
        self.extra.deinit(testing.allocator);
    }

    fn addTag(self: *TestMir, tag: Mir.Inst.Tag) !void {
        try self.instructions.append(testing.allocator, .{ .tag = tag, .data = .{ .tag = {} } });
    }

    fn addBlock(self: *TestMir, tag: Mir.Inst.Tag, block_type: std.wasm.BlockType) !void {
        try self.instructions.append(testing.allocator, .{ .tag = tag, .data = .{ .block_type = block_type } });
    }

    fn addLabel(self: *TestMir, tag: Mir.Inst.Tag, label: u32) !void {
        try self.instructions.append(testing.allocator, .{ .tag = tag, .data = .{ .label = label } });
    }

    fn addLocal(self: *TestMir, tag: Mir.Inst.Tag, local: u32) !void {
        try self.instructions.append(testing.allocator, .{ .tag = tag, .data = .{ .local = local } });
    }

    fn addIntrinsic(self: *TestMir, intrinsic: Mir.Intrinsic) !void {
        try self.instructions.append(testing.allocator, .{ .tag = .call_intrinsic, .data = .{ .intrinsic = intrinsic } });
    }

    fn addPayload(self: *TestMir, tag: Mir.Inst.Tag, payload: u32) !void {
        try self.instructions.append(testing.allocator, .{ .tag = tag, .data = .{ .payload = payload } });
    }

    fn addI32(self: *TestMir, val: i32) !void {
        try self.instructions.append(testing.allocator, .{ .tag = .i32_const, .data = .{ .imm32 = val } });
    }

    fn addI64(self: *TestMir, val: i64) !void {
        const payload = try appendImm64(testing.allocator, &self.extra, @bitCast(val));
        try self.instructions.append(testing.allocator, .{ .tag = .i64_const, .data = .{ .payload = payload } });
    }

    fn addF32(self: *TestMir, val: f32) !void {
        try self.instructions.append(testing.allocator, .{ .tag = .f32_const, .data = .{ .float32 = val } });
    }

    fn addF64(self: *TestMir, val: f64) !void {
        const f = Mir.Float64.init(val);
        const payload: u32 = @intCast(self.extra.items.len);
        try self.extra.appendSlice(testing.allocator, &.{ f.msb, f.lsb });
        try self.instructions.append(testing.allocator, .{ .tag = .f64_const, .data = .{ .payload = payload } });
    }

    fn addBrTable(self: *TestMir, targets: []const u32) !void {
        const payload: u32 = @intCast(self.extra.items.len);
        try self.extra.append(testing.allocator, @intCast(targets.len));
        try self.extra.appendSlice(testing.allocator, targets);
        try self.instructions.append(testing.allocator, .{ .tag = .br_table, .data = .{ .payload = payload } });
    }

    fn memOp(self: *TestMir, tag: Mir.Inst.Tag, offset: u64, alignment: u32) !void {
        const payload = try appendMemArg(testing.allocator, &self.extra, offset, alignment, null);
        try self.instructions.append(testing.allocator, .{ .tag = tag, .data = .{ .payload = payload } });
    }

    fn simdOp(self: *TestMir, opcode: std.wasm.SimdOpcode) !void {
        const payload: u32 = @intCast(self.extra.items.len);
        try self.extra.append(testing.allocator, @backingInt(opcode));
        try self.instructions.append(testing.allocator, .{ .tag = .simd_prefix, .data = .{ .payload = payload } });
    }

    fn simdMemOp(self: *TestMir, opcode: std.wasm.SimdOpcode, offset: u64, alignment: u32) !void {
        const payload = try appendMemArg(testing.allocator, &self.extra, offset, alignment, @backingInt(opcode));
        try self.instructions.append(testing.allocator, .{ .tag = .simd_prefix, .data = .{ .payload = payload } });
    }

    fn atomicMemOp(self: *TestMir, opcode: std.wasm.AtomicsOpcode, offset: u64, alignment: u32) !void {
        const payload = try appendMemArg(testing.allocator, &self.extra, offset, alignment, @backingInt(opcode));
        try self.instructions.append(testing.allocator, .{ .tag = .atomics_prefix, .data = .{ .payload = payload } });
    }

    fn memOffsetAt(self: *const TestMir, inst_idx: usize) u64 {
        const inst = self.instructions.get(inst_idx);
        const memarg_idx: u32 = switch (inst.tag) {
            .simd_prefix, .atomics_prefix => inst.data.payload + 1,
            else => inst.data.payload,
        };
        return readMemArgOffset(self.extra.items, memarg_idx);
    }

    fn memAlignmentAt(self: *const TestMir, inst_idx: usize) u32 {
        const inst = self.instructions.get(inst_idx);
        const memarg_idx: u32 = switch (inst.tag) {
            .simd_prefix, .atomics_prefix => inst.data.payload + 1,
            else => inst.data.payload,
        };
        return self.extra.items[memarg_idx + 2];
    }

    fn finishFunc(self: *TestMir) !void {
        try self.addTag(.end);
        try self.addTag(.dbg_epilogue_begin);
    }

    fn run(self: *TestMir) !void {
        try optimize(testing.allocator, &self.instructions, &self.extra, &self.err_ref_count);
    }
};

test "i32 constant folding: arithmetic, bitwise, shifts, comparisons, unary" {
    var m: TestMir = .{};
    defer m.deinit();

    // (10 + 20) * 3 - 5 = 85
    try m.addI32(10);
    try m.addI32(20);
    try m.addTag(.i32_add);
    try m.addI32(3);
    try m.addTag(.i32_mul);
    try m.addI32(5);
    try m.addTag(.i32_sub);

    // ((85 & 0xff) | 0x100) ^ 0x05 = (85 | 256) ^ 5 = 341 ^ 5 = 336
    try m.addI32(0xff);
    try m.addTag(.i32_and);
    try m.addI32(0x100);
    try m.addTag(.i32_or);
    try m.addI32(0x05);
    try m.addTag(.i32_xor);

    // (336 << (33 & 31)) >>_u 1 = 336
    try m.addI32(33); // masked to shift by 1
    try m.addTag(.i32_shl);
    try m.addI32(1);
    try m.addTag(.i32_shr_u);

    // extend8_s(0x80) = -128; (-128 >>_s 2) = -32
    try m.addI32(0x80);
    try m.addTag(.i32_extend8_s);
    try m.addI32(2);
    try m.addTag(.i32_shr_s);

    // 336 + (-32) = 304
    try m.addTag(.i32_add);

    // extend16_s(0xff00) = -256; 304 + (-256) = 48
    try m.addI32(0xff00);
    try m.addTag(.i32_extend16_s);
    try m.addTag(.i32_add);

    // popcnt(48 = 0b110000) = 2, ctz(48) = 4, clz(48) = 26 -> 2 + 4 + 26 = 32
    try m.addTag(.i32_popcnt);
    try m.addI32(48);
    try m.addTag(.i32_ctz);
    try m.addTag(.i32_add);
    try m.addI32(48);
    try m.addTag(.i32_clz);
    try m.addTag(.i32_add);

    // eqz(32) = 0, eqz(0) = 1
    try m.addTag(.i32_eqz);
    try m.addTag(.i32_eqz);

    // comparisons
    try m.addI32(1);
    try m.addTag(.i32_eq); // 1 == 1 -> 1
    try m.addI32(-1);
    try m.addTag(.i32_gt_s); // 1 >_s -1 -> 1
    try m.addI32(-1);
    try m.addTag(.i32_lt_u); // 1 <_u 0xffffffff -> 1

    try m.finishFunc();
    try m.run();

    const tags = m.instructions.items(.tag);
    const datas = m.instructions.items(.data);
    try testing.expectEqualSlices(Mir.Inst.Tag, &.{ .i32_const, .end, .dbg_epilogue_begin }, tags);
    try testing.expectEqual(@as(i32, 1), datas[0].imm32);
}

test "i64 constant folding and i32/i64 conversions" {
    var m: TestMir = .{};
    defer m.deinit();

    // i64_extend_i32_s(-10) = -10
    try m.addI32(-10);
    try m.addTag(.i64_extend_i32_s);
    // i64_extend_i32_u(25) = 25
    try m.addI32(25);
    try m.addTag(.i64_extend_i32_u);
    // -10 + 25 = 15
    try m.addTag(.i64_add);

    // (15 * 4 - 10) = 50
    try m.addI64(4);
    try m.addTag(.i64_mul);
    try m.addI64(10);
    try m.addTag(.i64_sub);

    // bitwise & shifts on i64: ((50 << 65) >>_u 1) = 50 (since 65 & 63 == 1)
    try m.addI64(65);
    try m.addTag(.i64_shl);
    try m.addI64(1);
    try m.addTag(.i64_shr_u);

    // extend8_s, extend16_s, extend32_s
    try m.addI64(0xff);
    try m.addTag(.i64_extend8_s); // -1
    try m.addTag(.i64_add); // 49
    try m.addI64(0xffff);
    try m.addTag(.i64_extend16_s); // -1
    try m.addTag(.i64_add); // 48
    try m.addI64(0xffffffff);
    try m.addTag(.i64_extend32_s); // -1
    try m.addTag(.i64_add); // 47

    // i32_wrap_i64(47 | (1 << 35)) = 47
    try m.addI64(1 << 35);
    try m.addTag(.i64_or);
    try m.addTag(.i32_wrap_i64);

    // i64 comparisons & unary: clz, ctz, popcnt, eqz
    try m.addI64(8);
    try m.addTag(.i64_ctz); // 3
    try m.addI64(3);
    try m.addTag(.i64_eq); // 1 (i32)
    try m.addTag(.i32_add); // 47 + 1 = 48

    try m.finishFunc();
    try m.run();

    const tags = m.instructions.items(.tag);
    const datas = m.instructions.items(.data);
    try testing.expectEqualSlices(Mir.Inst.Tag, &.{ .i32_const, .end, .dbg_epilogue_begin }, tags);
    try testing.expectEqual(@as(i32, 48), datas[0].imm32);
}

test "constant drop and constant select folding" {
    var m: TestMir = .{};
    defer m.deinit();

    // Constant drops of i32, i64, f32, f64 should all be removed
    try m.addI32(123);
    try m.addTag(.drop);
    try m.addI64(456);
    try m.addTag(.drop);
    try m.addF32(1.5);
    try m.addTag(.drop);
    try m.addF64(2.5);
    try m.addTag(.drop);

    // Constant select (cond != 0 picks first, cond == 0 picks second)
    try m.addI32(111);
    try m.addI32(222);
    try m.addI32(1);
    try m.addTag(.select);

    try m.addI32(333);
    try m.addI32(444);
    try m.addI32(0);
    try m.addTag(.select);

    try m.addTag(.i32_add); // 111 + 444 = 555

    try m.finishFunc();
    try m.run();

    const tags = m.instructions.items(.tag);
    const datas = m.instructions.items(.data);
    try testing.expectEqualSlices(Mir.Inst.Tag, &.{ .i32_const, .end, .dbg_epilogue_begin }, tags);
    try testing.expectEqual(@as(i32, 555), datas[0].imm32);
}

test "constant br_if and airCondBr collapsing" {
    // Pattern from CodeGen.airCondBr:
    // block (.empty) -> i32_const 1 -> br_if 0 -> <dead else> -> end -> <then>
    var m: TestMir = .{};
    defer m.deinit();

    try m.addBlock(.block, .empty);
    try m.addI32(1);
    try m.addLabel(.br_if, 0);
    // Dead else body (including nested block and error_name_table_ref)
    try m.addTag(.error_name_table_ref);
    try m.addTag(.drop);
    try m.addBlock(.block, .empty);
    try m.addI32(999);
    try m.addTag(.@"return");
    try m.addTag(.end);
    try m.addTag(.end);
    // Live then body
    try m.addI32(42);
    try m.addTag(.@"return");

    m.err_ref_count = 1;
    try m.finishFunc();
    try m.run();

    const tags = m.instructions.items(.tag);
    const datas = m.instructions.items(.data);
    try testing.expectEqualSlices(Mir.Inst.Tag, &.{ .i32_const, .@"return", .end, .dbg_epilogue_begin }, tags);
    try testing.expectEqual(@as(i32, 42), datas[0].imm32);
    try testing.expectEqual(@as(u32, 0), m.err_ref_count);
}

test "constant br_if 0 removal and trivial block inlining" {
    var m: TestMir = .{};
    defer m.deinit();

    try m.addBlock(.block, .empty);
    try m.addI32(0);
    try m.addLabel(.br_if, 0);
    try m.addI32(77);
    try m.addTag(.end);
    try m.addTag(.@"return");

    try m.finishFunc();
    try m.run();

    const tags = m.instructions.items(.tag);
    const datas = m.instructions.items(.data);
    try testing.expectEqualSlices(Mir.Inst.Tag, &.{ .i32_const, .@"return", .end, .dbg_epilogue_begin }, tags);
    try testing.expectEqual(@as(i32, 77), datas[0].imm32);
}

test "constant br_table folding: in-range and default target" {
    // Test 1: in-range index (1 -> target label 0)
    {
        var m: TestMir = .{};
        defer m.deinit();

        try m.addBlock(.block, .empty);
        try m.addI32(1);
        try m.addBrTable(&.{ 1, 0, 1 }); // targets[1] == 0
        try m.addI32(999);
        try m.addTag(.@"return");
        try m.addTag(.end);
        try m.addI32(10);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(Mir.Inst.Tag, &.{ .i32_const, .@"return", .end, .dbg_epilogue_begin }, tags);
        try testing.expectEqual(@as(i32, 10), datas[0].imm32);
    }

    // Test 2: out-of-range index (99 -> default target label 0)
    {
        var m: TestMir = .{};
        defer m.deinit();

        try m.addBlock(.block, .empty);
        try m.addI32(99);
        try m.addBrTable(&.{ 1, 1, 0 }); // default targets[2] == 0
        try m.addI32(999);
        try m.addTag(.@"return");
        try m.addTag(.end);
        try m.addI32(20);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(Mir.Inst.Tag, &.{ .i32_const, .@"return", .end, .dbg_epilogue_begin }, tags);
        try testing.expectEqual(@as(i32, 20), datas[0].imm32);
    }
}

test "trivial block inlining decrements outer br, br_if, and br_table labels" {
    // Test 1: outer `br_if 1` inside trivial inner block becomes `br_if 0`
    {
        var m: TestMir = .{};
        defer m.deinit();

        try m.addBlock(.block, .empty); // outer block (target label 0 after inner block is inlined)
        try m.addBlock(.block, .empty); // trivial inner block (no branch to depth 0)
        try m.addLocal(.local_get, 0);
        try m.addLabel(.br_if, 1); // targets outer block
        try m.addTag(.end);
        try m.addLocal(.local_get, 1);
        try m.addTag(.drop);
        try m.addTag(.end);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{ .block, .local_get, .br_if, .local_get, .drop, .end, .end, .dbg_epilogue_begin },
            tags,
        );
        try testing.expectEqual(@as(u32, 0), datas[2].label);
    }

    // Test 2: outer `br 1` inside trivial inner block becomes `br 0`, then collapses outer `block -> br 0 -> end`
    {
        var m: TestMir = .{};
        defer m.deinit();

        try m.addBlock(.block, .empty); // outer block
        try m.addBlock(.block, .empty); // trivial inner block
        try m.addLabel(.br, 1); // targets outer block -> becomes br 0 -> collapses outer block too!
        try m.addTag(.end);
        try m.addTag(.end);
        try m.addI32(55);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(Mir.Inst.Tag, &.{ .i32_const, .@"return", .end, .dbg_epilogue_begin }, tags);
        try testing.expectEqual(@as(i32, 55), datas[0].imm32);
    }

    // Test 3: `br_table` inside trivial inner block decrements outer labels > depth, while preserving inner loop labels
    {
        var m: TestMir = .{};
        defer m.deinit();

        try m.addBlock(.block, .empty); // outer block 1
        try m.addBlock(.block, .empty); // outer block 0
        try m.addBlock(.block, .empty); // trivial inner block (no branch to depth 0)
        try m.addBlock(.loop, .empty); // nested loop inside trivial block (depth 0 inside loop)
        try m.addLocal(.local_get, 0);
        // Inside the loop:
        // - label 0 targets the loop itself (depth <= 1 -> stays 0)
        // - label 2 targets outer block 0 (depth > 1 -> decrements to 1)
        // - label 3 targets outer block 1 (depth > 1 -> decrements to 2)
        try m.addBrTable(&.{ 0, 2, 3 });
        try m.addTag(.end);
        try m.addTag(.end);
        try m.addLocal(.local_get, 1);
        try m.addLabel(.br_if, 0); // keeps outer block 0 non-trivial
        try m.addTag(.end);
        try m.addLocal(.local_get, 2);
        try m.addLabel(.br_if, 0); // keeps outer block 1 non-trivial
        try m.addTag(.end);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        var br_table_payload: ?u32 = null;
        for (tags, datas) |t, d| {
            if (t == .br_table) {
                br_table_payload = d.payload;
                break;
            }
        }
        try testing.expect(br_table_payload != null);
        const p = br_table_payload.?;
        const len = m.extra.items[p];
        try testing.expectEqual(@as(u32, 3), len);
        try testing.expectEqualSlices(u32, &.{ 0, 1, 2 }, m.extra.items[p + 1 ..][0..len]);
    }
}

test "all i32 and i64 comparison ops and dbg_line handling" {
    var m: TestMir = .{};
    defer m.deinit();

    // i32 comparisons: ne, lt_s, gt_u, le_s, le_u, ge_s, ge_u
    try m.addI32(5);
    try m.addI32(6);
    try m.addTag(.i32_ne); // 1

    try m.addI32(-5);
    try m.addI32(2);
    try m.addTag(.i32_lt_s); // 1
    try m.addTag(.i32_add); // 2

    try m.addI32(-1);
    try m.addI32(1);
    try m.addTag(.i32_gt_u); // 1
    try m.addTag(.i32_add); // 3

    try m.addI32(-2);
    try m.addI32(-2);
    try m.addTag(.i32_le_s); // 1
    try m.addTag(.i32_add); // 4

    try m.addI32(2);
    try m.addI32(-1);
    try m.addTag(.i32_le_u); // 1
    try m.addTag(.i32_add); // 5

    try m.addI32(-2);
    try m.addI32(-3);
    try m.addTag(.i32_ge_s); // 1
    try m.addTag(.i32_add); // 6

    try m.addI32(-1);
    try m.addI32(-1);
    try m.addTag(.i32_ge_u); // 1
    try m.addTag(.i32_add); // 7

    // i64 comparisons & unary: ne, lt_s, lt_u, gt_s, gt_u, le_s, le_u, ge_s, ge_u, clz, popcnt, eqz, shr_s, and, xor
    try m.addI64(-8);
    try m.addI64(1);
    try m.addTag(.i64_shr_s); // -4
    try m.addI64(-4);
    try m.addTag(.i64_le_s); // 1
    try m.addTag(.i32_add); // 8

    try m.addI64(0b1011);
    try m.addI64(0b1110);
    try m.addTag(.i64_and); // 0b1010
    try m.addI64(0b0011);
    try m.addTag(.i64_xor); // 0b1001
    try m.addTag(.i64_popcnt); // 2
    try m.addI64(0);
    try m.addTag(.i64_clz); // 64
    try m.addTag(.i64_lt_u); // 2 <_u 64 -> 1
    try m.addTag(.i32_add); // 9

    try m.addI64(0);
    try m.addTag(.i64_eqz); // 1
    try m.addTag(.i32_add); // 10

    try m.addI64(-1);
    try m.addI64(1);
    try m.addTag(.i64_lt_s); // 1
    try m.addTag(.i32_add); // 11

    try m.addI64(5);
    try m.addI64(-5);
    try m.addTag(.i64_gt_s); // 1
    try m.addTag(.i32_add); // 12

    try m.addI64(-1);
    try m.addI64(5);
    try m.addTag(.i64_gt_u); // 1
    try m.addTag(.i32_add); // 13

    try m.addI64(5);
    try m.addI64(5);
    try m.addTag(.i64_le_u); // 1
    try m.addTag(.i32_add); // 14

    try m.addI64(-5);
    try m.addI64(-10);
    try m.addTag(.i64_ge_s); // 1
    try m.addTag(.i32_add); // 15

    try m.addI64(-1);
    try m.addI64(10);
    try m.addTag(.i64_ge_u); // 1
    try m.addTag(.i32_add); // 16

    try m.addI64(1);
    try m.addI64(2);
    try m.addTag(.i64_ne); // 1
    try m.addTag(.i32_add); // 17

    // block (.empty) with dbg_line before br 0 collapses while preserving dbg_line
    try m.addBlock(.block, .empty);
    try m.instructions.append(testing.allocator, .{ .tag = .dbg_line, .data = .{ .payload = 0 } });
    try m.addLabel(.br, 0);
    try m.addTag(.end);

    try m.finishFunc();
    try m.run();

    const tags = m.instructions.items(.tag);
    const datas = m.instructions.items(.data);
    try testing.expectEqualSlices(Mir.Inst.Tag, &.{ .i32_const, .dbg_line, .end, .dbg_epilogue_begin }, tags);
    try testing.expectEqual(@as(i32, 17), datas[0].imm32);
}

test "intrafunction DCE after return, br, unreachable with nested blocks and error_name_table_ref_count" {
    var m: TestMir = .{};
    defer m.deinit();

    // Live error_name_table_ref
    try m.addTag(.error_name_table_ref);
    try m.addLocal(.local_set, 0);

    try m.addBlock(.block, .empty);
    try m.addLocal(.local_get, 0);
    try m.addLabel(.br_if, 0);
    try m.addTag(.@"unreachable");
    // Dead region inside block with nested block/loop and dead error_name_table_ref
    try m.addTag(.error_name_table_ref);
    try m.addTag(.drop);
    try m.addBlock(.block, .empty);
    try m.addBlock(.loop, .empty);
    try m.addLabel(.br, 0);
    try m.addTag(.end);
    try m.addTag(.end);
    try m.addTag(.end); // closes live block

    try m.addI32(1);
    try m.addTag(.@"return");
    // Dead region after top-level return
    try m.addTag(.error_name_table_ref);
    try m.addTag(.drop);
    try m.addBlock(.block, .empty);
    try m.addI32(2);
    try m.addTag(.drop);
    try m.addTag(.end);

    m.err_ref_count = 3;
    try m.finishFunc();
    try m.run();

    const tags = m.instructions.items(.tag);
    try testing.expectEqualSlices(
        Mir.Inst.Tag,
        &.{
            .error_name_table_ref,
            .local_set,
            .block,
            .local_get,
            .br_if,
            .@"unreachable",
            .end,
            .i32_const,
            .@"return",
            .end,
            .dbg_epilogue_begin,
        },
        tags,
    );
    try testing.expectEqual(@as(u32, 1), m.err_ref_count);
}

test "local_set + local_get coalescing and dead local_tee elimination unlock cross-instruction folding" {
    var m: TestMir = .{};
    defer m.deinit();

    // Temporary local 3 written and immediately read, then overwritten, then returned:
    // (6 * 7) -> local 3 -> + 8 -> local 3 -> return => i32.const 50; return
    try m.addI32(6);
    try m.addI32(7);
    try m.addTag(.i32_mul);
    try m.addLocal(.local_set, 3);
    try m.addLocal(.local_get, 3);
    try m.addI32(8);
    try m.addTag(.i32_add);
    try m.addLocal(.local_set, 3);
    try m.instructions.append(testing.allocator, .{ .tag = .dbg_line, .data = .{ .payload = 0 } });
    try m.addLocal(.local_get, 3);

    // Local 4 is read again later before return, so `local_set 4; local_get 4` becomes `local_tee 4`
    try m.addLocal(.local_set, 4);
    try m.addLocal(.local_get, 4);
    try m.addLocal(.local_get, 4);
    try m.addTag(.i32_add);
    try m.addTag(.@"return");

    try m.finishFunc();
    try m.run();

    const tags = m.instructions.items(.tag);
    const datas = m.instructions.items(.data);
    try testing.expectEqualSlices(
        Mir.Inst.Tag,
        &.{ .i32_const, .dbg_line, .local_tee, .local_get, .i32_add, .@"return", .end, .dbg_epilogue_begin },
        tags,
    );
    try testing.expectEqual(@as(i32, 50), datas[0].imm32);
    try testing.expectEqual(@as(u32, 4), datas[2].local);
    try testing.expectEqual(@as(u32, 4), datas[3].local);
}

test "MemArg offset folding: i32_load, i64_load, K == 0, and chained constant offsets" {
    // 1. i32_const K; i32_add; i32_load (offset=0 + K, offset=M + K, and K == 0)
    {
        var m: TestMir = .{};
        defer m.deinit();

        // offset=0 + 24 -> offset=24
        try m.addLocal(.local_get, 0);
        try m.addI32(24);
        try m.addTag(.i32_add);
        try m.memOp(.i32_load, 0, 2);

        // offset=16 + 12 -> offset=28
        try m.addLocal(.local_get, 0);
        try m.addI32(12);
        try m.addTag(.i32_add);
        try m.memOp(.i32_load8_u, 16, 0);

        // K == 0: removes i32_const 0; i32_add and preserves offset=8
        try m.addLocal(.local_get, 0);
        try m.addI32(0);
        try m.addTag(.i32_add);
        try m.memOp(.i32_load16_s, 8, 1);

        // Chained constant offsets: local_get 0; i32_const 4; i32_add; i32_const 8; i32_add; i32_load offset=16 -> offset=28
        try m.addLocal(.local_get, 0);
        try m.addI32(4);
        try m.addTag(.i32_add);
        try m.addI32(8);
        try m.addTag(.i32_add);
        try m.memOp(.i32_load, 16, 2);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .local_get, .i32_load,
                .local_get, .i32_load8_u,
                .local_get, .i32_load16_s,
                .local_get, .i32_load,
                .end,       .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(u64, 24), m.memOffsetAt(1));
        try testing.expectEqual(@as(u32, 2), m.memAlignmentAt(1));
        try testing.expectEqual(@as(u64, 28), m.memOffsetAt(3));
        try testing.expectEqual(@as(u32, 0), m.memAlignmentAt(3));
        try testing.expectEqual(@as(u64, 8), m.memOffsetAt(5));
        try testing.expectEqual(@as(u32, 1), m.memAlignmentAt(5));
        try testing.expectEqual(@as(u64, 28), m.memOffsetAt(7));
        try testing.expectEqual(@as(u32, 2), m.memAlignmentAt(7));
    }

    // 2. i64_const K; i64_add; i64_load on wasm64 (including 64-bit offsets > u32.max)
    {
        var m: TestMir = .{};
        defer m.deinit();

        try m.addLocal(.local_get, 0);
        try m.addI64(0x1_0000_0020);
        try m.addTag(.i64_add);
        try m.addI64(0x0_0000_0010);
        try m.addTag(.i64_add);
        try m.memOp(.i64_load, 0x2_0000_0008, 3);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{ .local_get, .i64_load, .end, .dbg_epilogue_begin },
            tags,
        );
        try testing.expectEqual(@as(u64, 0x3_0000_0038), m.memOffsetAt(1));
        try testing.expectEqual(@as(u32, 3), m.memAlignmentAt(1));
    }
}

test "MemArg offset folding: stores with single-inst and multi-inst <val>, and <val> vs <addr> disambiguation" {
    // 1. Single-instruction <val>: local_get, i32_const, f64_const, uav_ref
    {
        var m: TestMir = .{};
        defer m.deinit();

        // local_get $base; i32_const 12; i32_add; local_get $val; i32_store offset=4 -> offset=16
        try m.addLocal(.local_get, 0);
        try m.addI32(12);
        try m.addTag(.i32_add);
        try m.addLocal(.local_get, 1);
        try m.memOp(.i32_store, 4, 2);

        // local_get $base; i32_const 8; i32_add; f64_const 3.25; f64_store offset=0 -> offset=8
        try m.addLocal(.local_get, 0);
        try m.addI32(8);
        try m.addTag(.i32_add);
        try m.addF64(3.25);
        try m.memOp(.f64_store, 0, 3);

        // local_get $base; i32_const 16; i32_add; uav_ref; i32_store offset=4 -> offset=20
        try m.addLocal(.local_get, 0);
        try m.addI32(16);
        try m.addTag(.i32_add);
        try m.addTag(.uav_ref);
        try m.memOp(.i32_store, 4, 2);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .local_get, .local_get,          .i32_store,
                .local_get, .f64_const,          .f64_store,
                .local_get, .uav_ref,            .i32_store,
                .end,       .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(u64, 16), m.memOffsetAt(2));
        try testing.expectEqual(@as(u64, 8), m.memOffsetAt(5));
        try testing.expectEqual(@as(u64, 20), m.memOffsetAt(8));
    }

    // 2. Multi-instruction <val>: stack_offset value (local_get $sp; i32_const 32; i32_add) and loaded value (local_get $src; i32_load)
    {
        var m: TestMir = .{};
        defer m.deinit();

        // <addr>: local_get 0 + 12; <val>: local_get 1 + 32 -> folds 12 into i32_store, preserves <val>
        try m.addLocal(.local_get, 0);
        try m.addI32(12);
        try m.addTag(.i32_add);
        try m.addLocal(.local_get, 1);
        try m.addI32(32);
        try m.addTag(.i32_add);
        try m.memOp(.i32_store, 0, 2);

        // <addr>: local_get 0 + 20; <val>: (local_get 2 + 4)->i32_load -> folds 4 into i32_load and 20 into i32_store
        try m.addLocal(.local_get, 0);
        try m.addI32(20);
        try m.addTag(.i32_add);
        try m.addLocal(.local_get, 2);
        try m.addI32(4);
        try m.addTag(.i32_add);
        try m.memOp(.i32_load, 0, 2);
        try m.memOp(.i32_store, 8, 2);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .local_get,          .local_get, .i32_const, .i32_add,   .i32_store,
                .local_get,          .local_get, .i32_load,  .i32_store, .end,
                .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(i32, 32), datas[2].imm32);
        try testing.expectEqual(@as(u64, 12), m.memOffsetAt(4));
        try testing.expectEqual(@as(u64, 4), m.memOffsetAt(7));
        try testing.expectEqual(@as(u64, 28), m.memOffsetAt(8));
    }

    // 3. Store <val> vs <addr> disambiguation: local_get $base; local_get $val; i32_const 10; i32_add; i32_store offset=0
    // MUST NOT fold 10 into i32_store because 10 is added to $val, not $base!
    {
        var m: TestMir = .{};
        defer m.deinit();

        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 1);
        try m.addI32(10);
        try m.addTag(.i32_add);
        try m.memOp(.i32_store, 0, 2);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{ .local_get, .local_get, .i32_const, .i32_add, .i32_store, .end, .dbg_epilogue_begin },
            tags,
        );
        try testing.expectEqual(@as(i32, 10), datas[2].imm32);
        try testing.expectEqual(@as(u64, 0), m.memOffsetAt(4));
    }
}

test "MemArg offset folding: negative K and overflow rejection" {
    // 1. Negative K rejection on i32_add and i64_add
    {
        var m: TestMir = .{};
        defer m.deinit();

        try m.addLocal(.local_get, 0);
        try m.addI32(-4);
        try m.addTag(.i32_add);
        try m.memOp(.i32_load, 8, 2);

        try m.addLocal(.local_get, 0);
        try m.addI64(-8);
        try m.addTag(.i64_add);
        try m.memOp(.i64_load, 16, 3);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .local_get, .i32_const,          .i32_add, .i32_load,
                .local_get, .i64_const,          .i64_add, .i64_load,
                .end,       .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(u64, 8), m.memOffsetAt(3));
        try testing.expectEqual(@as(u64, 16), m.memOffsetAt(7));
    }

    // 2. Overflow rejection: u32 overflow on i32_add and u64 overflow on i64_add
    {
        var m: TestMir = .{};
        defer m.deinit();

        try m.addLocal(.local_get, 0);
        try m.addI32(16);
        try m.addTag(.i32_add);
        try m.memOp(.i32_load, 0xffff_fff8, 2);

        try m.addLocal(.local_get, 0);
        try m.addI64(16);
        try m.addTag(.i64_add);
        try m.memOp(.i64_load, 0xffff_ffff_ffff_fff8, 3);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .local_get, .i32_const,          .i32_add, .i32_load,
                .local_get, .i64_const,          .i64_add, .i64_load,
                .end,       .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(u64, 0xffff_fff8), m.memOffsetAt(3));
        try testing.expectEqual(@as(u64, 0xffff_ffff_ffff_fff8), m.memOffsetAt(7));
    }
}

test "MemArg offset folding: simd_prefix, atomics_prefix, and simplifyLocals multi-pass integration" {
    // 1. simd_prefix and atomics_prefix loads, stores, and RMWs
    {
        var m: TestMir = .{};
        defer m.deinit();

        // v128_load
        try m.addLocal(.local_get, 0);
        try m.addI32(16);
        try m.addTag(.i32_add);
        try m.simdMemOp(.v128_load, 32, 4);

        // v128_store
        try m.addLocal(.local_get, 0);
        try m.addI32(48);
        try m.addTag(.i32_add);
        try m.addLocal(.local_get, 1);
        try m.simdMemOp(.v128_store, 16, 4);

        // v128_load32_splat
        try m.addLocal(.local_get, 0);
        try m.addI32(8);
        try m.addTag(.i32_add);
        try m.simdMemOp(.v128_load32_splat, 4, 2);

        // i32_atomic_load
        try m.addLocal(.local_get, 0);
        try m.addI32(12);
        try m.addTag(.i32_add);
        try m.atomicMemOp(.i32_atomic_load, 4, 2);

        // i32_atomic_store
        try m.addLocal(.local_get, 0);
        try m.addI32(20);
        try m.addTag(.i32_add);
        try m.addLocal(.local_get, 2);
        try m.atomicMemOp(.i32_atomic_store, 8, 2);

        // i32_atomic_rmw_add
        try m.addLocal(.local_get, 0);
        try m.addI32(28);
        try m.addTag(.i32_add);
        try m.addI32(1);
        try m.atomicMemOp(.i32_atomic_rmw_add, 4, 2);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .local_get,          .simd_prefix,
                .local_get,          .local_get,
                .simd_prefix,        .local_get,
                .simd_prefix,        .local_get,
                .atomics_prefix,     .local_get,
                .local_get,          .atomics_prefix,
                .local_get,          .i32_const,
                .atomics_prefix,     .end,
                .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(u64, 48), m.memOffsetAt(1));
        try testing.expectEqual(@as(u64, 64), m.memOffsetAt(4));
        try testing.expectEqual(@as(u64, 12), m.memOffsetAt(6));
        try testing.expectEqual(@as(u64, 16), m.memOffsetAt(8));
        try testing.expectEqual(@as(u64, 28), m.memOffsetAt(11));
        try testing.expectEqual(@as(u64, 32), m.memOffsetAt(14));
    }

    // 1b. v128_store with composite SIMD <val> (0-pop v128_const, 1-pop splat/neg, 2-pop add, 3-pop bitselect)
    {
        var m: TestMir = .{};
        defer m.deinit();

        // <addr>: local_get 0 + 32
        try m.addLocal(.local_get, 0);
        try m.addI32(32);
        try m.addTag(.i32_add);
        // <val>: bitselect(f32x4_add(v128_const, f32x4_neg(local_get 1)), i32x4_splat(local_get 2), local_get 3)
        try m.simdOp(.v128_const);
        try m.addLocal(.local_get, 1);
        try m.simdOp(.f32x4_neg);
        try m.simdOp(.f32x4_add);
        try m.addLocal(.local_get, 2);
        try m.simdOp(.i32x4_splat);
        try m.addLocal(.local_get, 3);
        try m.simdOp(.v128_bitselect);
        try m.simdMemOp(.v128_store, 16, 4);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .local_get,   .simd_prefix, .local_get,   .simd_prefix,
                .simd_prefix, .local_get,   .simd_prefix, .local_get,
                .simd_prefix, .simd_prefix, .end,         .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(u64, 48), m.memOffsetAt(9));
    }

    // 2. Multi-pass optimize: simplifyLocals removes temporary local_set/local_get between i32_add and i32_load/i32_store
    {
        var m: TestMir = .{};
        defer m.deinit();

        // Address computed into temporary local 5, then loaded from:
        // local_get 0; i32_const 16; i32_add; local_set 5; local_get 5; i32_load offset=8
        // -> local_get 0; i32_load offset=24
        try m.addLocal(.local_get, 0);
        try m.addI32(16);
        try m.addTag(.i32_add);
        try m.addLocal(.local_set, 5);
        try m.addLocal(.local_get, 5);
        try m.memOp(.i32_load, 8, 2);

        // Store where address was saved in dead temporary local 6:
        // local_get 0; i32_const 32; i32_add; local_set 6; local_get 6; local_get 1; i32_store offset=4
        // -> local_get 0; local_get 1; i32_store offset=36
        try m.addLocal(.local_get, 0);
        try m.addI32(32);
        try m.addTag(.i32_add);
        try m.addLocal(.local_set, 6);
        try m.addLocal(.local_get, 6);
        try m.addLocal(.local_get, 1);
        try m.memOp(.i32_store, 4, 2);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .local_get,          .i32_load,
                .local_get,          .local_get,
                .i32_store,          .end,
                .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(u64, 24), m.memOffsetAt(1));
        try testing.expectEqual(@as(u64, 36), m.memOffsetAt(4));
    }
}

test "uav_ref, uav_ref_off, and reference constant pruning across DCE, drop, select, and dead local_set" {
    // 1. Elimination of dead uav_ref and uav_ref_off in untaken br_if branches and after return/unreachable
    {
        var m: TestMir = .{};
        defer m.deinit();

        // Untaken else branch (i32_const 1 -> br_if 0) containing dead uav_ref and uav_ref_off
        try m.addBlock(.block, .empty);
        try m.addI32(1);
        try m.addLabel(.br_if, 0);
        try m.addPayload(.uav_ref, 100);
        try m.memOp(.i32_load, 0, 2);
        try m.addTag(.@"return");
        try m.addTag(.end);

        // Block with unreachable followed by dead uav_ref_off
        try m.addBlock(.block, .empty);
        try m.addLocal(.local_get, 0);
        try m.addLabel(.br_if, 0);
        try m.addTag(.@"unreachable");
        try m.addPayload(.uav_ref_off, 200);
        try m.addTag(.drop);
        try m.addTag(.end);

        // Live uav_ref returned, followed by dead uav_ref_off after return
        try m.addPayload(.uav_ref, 42);
        try m.addTag(.@"return");
        try m.addPayload(.uav_ref_off, 300);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .block,
                .local_get,
                .br_if,
                .@"unreachable",
                .end,
                .uav_ref,
                .@"return",
                .end,
                .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(u32, 42), datas[5].payload);
    }

    // 2. Folding of uav_ref, uav_ref_off, func_ref, and other reference constants followed by drop
    {
        var m: TestMir = .{};
        defer m.deinit();

        try m.addPayload(.uav_ref, 10);
        try m.addTag(.drop);
        try m.addPayload(.uav_ref_off, 20);
        try m.addTag(.drop);
        try m.addPayload(.func_ref, 30);
        try m.addTag(.drop);
        try m.addPayload(.nav_ref, 40);
        try m.addTag(.drop);
        try m.addPayload(.nav_ref_off, 50);
        try m.addTag(.drop);
        try m.addPayload(.tls_nav_ref, 60);
        try m.addTag(.drop);
        try m.addTag(.error_name_table_ref);
        try m.addTag(.drop);
        try m.addPayload(.enum_tag_name_table_ref, 70);
        try m.addTag(.drop);
        try m.addTag(.errors_len);
        try m.addTag(.drop);

        try m.addI32(7);
        try m.addTag(.@"return");

        m.err_ref_count = 1;
        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{ .i32_const, .@"return", .end, .dbg_epilogue_begin },
            tags,
        );
        try testing.expectEqual(@as(i32, 7), datas[0].imm32);
        try testing.expectEqual(@as(u32, 0), m.err_ref_count);
    }

    // 3. Folding of select with constant condition over uav_ref and uav_ref_off operands
    {
        var m: TestMir = .{};
        defer m.deinit();

        // Same-tag select (cond != 0 picks first uav_ref 11, drops uav_ref 22)
        try m.addPayload(.uav_ref, 11);
        try m.addPayload(.uav_ref, 22);
        try m.addI32(1);
        try m.addTag(.select);
        try m.addLocal(.local_set, 0);

        // Mixed pointer-ref select (cond == 0 picks second uav_ref_off 44, drops uav_ref 33)
        try m.addPayload(.uav_ref, 33);
        try m.addPayload(.uav_ref_off, 44);
        try m.addI32(0);
        try m.addTag(.select);
        try m.addLocal(.local_get, 0);
        try m.addTag(.i32_add);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .uav_ref_off,
                .uav_ref,
                .i32_add,
                .@"return",
                .end,
                .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(u32, 44), datas[0].payload);
        try testing.expectEqual(@as(u32, 11), datas[1].payload);
    }

    // 4. Multi-round elimination of dead `uav_ref; local_set X` after the branch reading X is eliminated by DCE
    {
        var m: TestMir = .{};
        defer m.deinit();

        // Store uav_ref into local 2, only read inside a dead branch
        try m.addPayload(.uav_ref, 99);
        try m.addLocal(.local_set, 2);

        // Constant condition (1 == 1) folds to 1 in round 0, turning br_if 0 into br 0,
        // which eliminates the dead branch reading local 2 and collapses the block.
        // In round 1, simplifyLocals sees local 2 is no longer read before exit and removes `uav_ref 99; local_set 2`.
        try m.addBlock(.block, .empty);
        try m.addI32(5);
        try m.addI32(5);
        try m.addTag(.i32_eq);
        try m.addLabel(.br_if, 0);
        try m.addLocal(.local_get, 2);
        try m.memOp(.i32_load, 0, 2);
        try m.addTag(.@"return");
        try m.addTag(.end);

        try m.addI32(123);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{ .i32_const, .@"return", .end, .dbg_epilogue_begin },
            tags,
        );
        try testing.expectEqual(@as(i32, 123), datas[0].imm32);
    }

    // 5. `airCmp` + `airCondBr` pattern where the condition is stored to a local before `block (.empty)`
    // and that local is later reused after the branch.
    {
        var m: TestMir = .{};
        defer m.deinit();

        // `five = 5` stored in local 1, then compared `five != 5` stored in local 2 before `block (.empty)`
        try m.addI32(5);
        try m.addLocal(.local_set, 1);
        try m.addLocal(.local_get, 1);
        try m.addI32(5);
        try m.addTag(.i32_ne);
        try m.addLocal(.local_set, 2);

        try m.addBlock(.block, .empty);
        try m.addBlock(.block, .empty);
        try m.addLocal(.local_get, 2);
        try m.addLabel(.br_if, 0);
        try m.addLabel(.br, 1);
        try m.addTag(.end);
        // Dead branch referencing uav_ref and uav_ref_off
        try m.addPayload(.uav_ref, 77);
        try m.addPayload(.uav_ref_off, 88);
        try m.addTag(.i32_add);
        try m.addTag(.@"return");
        try m.addTag(.end);

        // Reuse local 2 inside a later block (simulating LocalPool reuse)
        try m.addBlock(.block, .empty);
        try m.addI32(42);
        try m.addLocal(.local_set, 2);
        try m.addLocal(.local_get, 2);
        try m.addTag(.@"return");
        try m.addTag(.end);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{ .i32_const, .@"return", .end, .dbg_epilogue_begin },
            tags,
        );
        try testing.expectEqual(@as(i32, 42), datas[0].imm32);
    }
}

test "compactLocals: drops dead interior locals, groups Valtypes in canonical order, and preserves params" {
    var m: TestMir = .{};
    defer m.deinit();

    var locals: std.ArrayList(std.wasm.Valtype) = .empty;
    defer locals.deinit(testing.allocator);

    // wasm_param_count = 2 (locals 0 and 1 are parameters)
    // mir_locals slots (starting at local index 2):
    //   slot 0 (local 2): .i32  (dead bottom_stack_local)
    //   slot 1 (local 3): .i32  (dead sp_local)
    //   slot 2 (local 4): .i64  (live #1 i64)
    //   slot 3 (local 5): .f64  (dead interior)
    //   slot 4 (local 6): .v128 (live #1 v128)
    //   slot 5 (local 7): .i32  (live #1 i32)
    //   slot 6 (local 8): .f32  (dead interior)
    //   slot 7 (local 9): .f64  (live #1 f64)
    //   slot 8 (local 10): .f32 (live #1 f32)
    //   slot 9 (local 11): .i32 (live #2 i32)
    //   slot 10 (local 12): .i64 (dead trailing)
    try locals.appendSlice(testing.allocator, &.{
        .i32, .i32, .i64, .f64, .v128, .i32,
        .f32, .f64, .f32, .i32, .i64,
    });

    // Reference params 0 and 1, and live locals 4, 6, 7, 9, 10, 11 via local_get/local_set/local_tee
    try m.addLocal(.local_get, 0);
    try m.addLocal(.local_set, 1);
    try m.addLocal(.local_get, 4); // i64  -> expected new index 4
    try m.addLocal(.local_set, 6); // v128 -> expected new index 7
    try m.addLocal(.local_tee, 7); // i32 #1 -> expected new index 2
    try m.addLocal(.local_get, 9); // f64  -> expected new index 6
    try m.addLocal(.local_set, 10); // f32 -> expected new index 5
    try m.addLocal(.local_get, 11); // i32 #2 -> expected new index 3
    try m.finishFunc();

    try compactLocals(testing.allocator, &m.instructions, &locals, 2, null, null);

    try testing.expectEqualSlices(
        std.wasm.Valtype,
        &.{ .i32, .i32, .i64, .f32, .f64, .v128 },
        locals.items,
    );

    const datas = m.instructions.items(.data);
    try testing.expectEqual(@as(u32, 0), datas[0].local);
    try testing.expectEqual(@as(u32, 1), datas[1].local);
    try testing.expectEqual(@as(u32, 4), datas[2].local);
    try testing.expectEqual(@as(u32, 7), datas[3].local);
    try testing.expectEqual(@as(u32, 2), datas[4].local);
    try testing.expectEqual(@as(u32, 6), datas[5].local);
    try testing.expectEqual(@as(u32, 5), datas[6].local);
    try testing.expectEqual(@as(u32, 3), datas[7].local);
}

test "compactLocals: remaps active bottom_stack_local and sp_local across leaf and non-leaf prologues" {
    // 1. Both bottom_stack_local and sp_local active (e.g. wasm64 where stack pointers are .i64 and move after .i32 locals)
    {
        var m: TestMir = .{};
        defer m.deinit();

        var locals: std.ArrayList(std.wasm.Valtype) = .empty;
        defer locals.deinit(testing.allocator);

        // wasm_param_count = 1
        // slot 0 (local 1): .i64 (bottom_stack_local, referenced only by prologue)
        // slot 1 (local 2): .i64 (sp_local, referenced by prologue and epilogue)
        // slot 2 (local 3): .i32 (dead local)
        // slot 3 (local 4): .i32 (live body local)
        try locals.appendSlice(testing.allocator, &.{ .i64, .i64, .i32, .i32 });

        var bottom_stack_local: u32 = 1;
        var sp_local: u32 = 2;

        try m.addLocal(.local_get, 0); // param 0
        try m.addLocal(.local_set, 4); // live .i32 local -> moves to index 1
        try m.addLocal(.local_get, 2); // epilogue sp_local read -> moves to index 3
        try m.addTag(.global_set_sp);
        try m.finishFunc();

        try compactLocals(
            testing.allocator,
            &m.instructions,
            &locals,
            1,
            &bottom_stack_local,
            &sp_local,
        );

        try testing.expectEqualSlices(std.wasm.Valtype, &.{ .i32, .i64, .i64 }, locals.items);
        try testing.expectEqual(@as(u32, 2), bottom_stack_local);
        try testing.expectEqual(@as(u32, 3), sp_local);

        const datas = m.instructions.items(.data);
        try testing.expectEqual(@as(u32, 0), datas[0].local);
        try testing.expectEqual(@as(u32, 1), datas[1].local);
        try testing.expectEqual(@as(u32, 3), datas[2].local);
    }

    // 2. Leaf prologue: bottom_stack_local active, sp_local is null (dead and dropped)
    {
        var m: TestMir = .{};
        defer m.deinit();

        var locals: std.ArrayList(std.wasm.Valtype) = .empty;
        defer locals.deinit(testing.allocator);

        // wasm_param_count = 0
        // slot 0 (local 0): .i32 (bottom_stack_local)
        // slot 1 (local 1): .i32 (dead sp_local)
        // slot 2 (local 2): .i64 (dead local)
        // slot 3 (local 3): .i32 (live body local)
        try locals.appendSlice(testing.allocator, &.{ .i32, .i32, .i64, .i32 });

        var bottom_stack_local: u32 = 0;

        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_tee, 3);
        try m.finishFunc();

        try compactLocals(
            testing.allocator,
            &m.instructions,
            &locals,
            0,
            &bottom_stack_local,
            null,
        );

        try testing.expectEqualSlices(std.wasm.Valtype, &.{ .i32, .i32 }, locals.items);
        try testing.expectEqual(@as(u32, 0), bottom_stack_local);

        const datas = m.instructions.items(.data);
        try testing.expectEqual(@as(u32, 0), datas[0].local);
        try testing.expectEqual(@as(u32, 1), datas[1].local);
    }
}

test "encodeLocals: run-length encodes empty, grouped, and large local runs" {
    var code: std.ArrayList(u8) = .empty;
    defer code.deinit(testing.allocator);

    // 1. Empty locals -> single 0x00 byte
    try code.ensureUnusedCapacity(testing.allocator, 5);
    encodeLocals(&code, &.{});
    try testing.expectEqualSlices(u8, &.{0x00}, code.items);

    // 2. Five runs of all 5 Wasm Valtypes: 3x i32, 2x i64, 1x f32, 4x f64, 2x v128
    code.clearRetainingCapacity();
    const mixed: []const std.wasm.Valtype = &.{
        .i32, .i32,  .i32,
        .i64, .i64,  .f32,
        .f64, .f64,  .f64,
        .f64, .v128, .v128,
    };
    try code.ensureUnusedCapacity(testing.allocator, 5 + mixed.len * 6);
    encodeLocals(&code, mixed);
    try testing.expectEqualSlices(u8, &.{
        5, // 5 runs
        3,
        @backingInt(std.wasm.Valtype.i32),
        2,
        @backingInt(std.wasm.Valtype.i64),
        1,
        @backingInt(std.wasm.Valtype.f32),
        4,
        @backingInt(std.wasm.Valtype.f64),
        2,
        @backingInt(std.wasm.Valtype.v128),
    }, code.items);

    // 3. Multi-byte ULEB128 run count (130x i32 -> count = 0x82, 0x01)
    code.clearRetainingCapacity();
    const many_i32: [130]std.wasm.Valtype = @splat(.i32);
    try code.ensureUnusedCapacity(testing.allocator, 5 + many_i32.len * 6);
    encodeLocals(&code, &many_i32);
    try testing.expectEqualSlices(u8, &.{
        1, // 1 run
        0x82,
        0x01,
        @backingInt(std.wasm.Valtype.i32),
    }, code.items);
}

test "peepholes: i32 and i64 additive, bitwise, and shift identities (including commutative 0-pop)" {
    // 1. i32 right-operand and left-operand commutative identities
    {
        var m: TestMir = .{};
        defer m.deinit();

        try m.addLocal(.local_get, 0);
        try m.addI32(0);
        try m.addTag(.i32_add);
        try m.addI32(0);
        try m.addTag(.i32_sub);
        try m.addI32(0);
        try m.addTag(.i32_or);
        try m.addI32(0);
        try m.addTag(.i32_xor);
        try m.addI32(-1);
        try m.addTag(.i32_and);
        try m.addI32(0);
        try m.addTag(.i32_shl);
        try m.addI32(32); // shift_amt == 0 (mod 32)
        try m.addTag(.i32_shr_s);
        try m.addI32(0);
        try m.addTag(.i32_shr_u);

        // Commutative left-constant with local_get: 0 + x, 0 | x, 0 ^ x, -1 & x
        try m.addI32(0);
        try m.addLocal(.local_get, 1);
        try m.addTag(.i32_add);
        try m.addTag(.i32_add);

        try m.addI32(0);
        try m.addLocal(.local_get, 2);
        try m.addTag(.i32_or);
        try m.addTag(.i32_add);

        try m.addI32(0);
        try m.addLocal(.local_get, 3);
        try m.addTag(.i32_xor);
        try m.addTag(.i32_add);

        try m.addI32(-1);
        try m.addLocal(.local_get, 4);
        try m.addTag(.i32_and);
        try m.addTag(.i32_add);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .local_get,
                .local_get,
                .i32_add,
                .local_get,
                .i32_add,
                .local_get,
                .i32_add,
                .local_get,
                .i32_add,
                .end,
                .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(u32, 0), datas[0].local);
        try testing.expectEqual(@as(u32, 1), datas[1].local);
        try testing.expectEqual(@as(u32, 2), datas[3].local);
        try testing.expectEqual(@as(u32, 3), datas[5].local);
        try testing.expectEqual(@as(u32, 4), datas[7].local);
    }

    // 2. i64 right-operand and left-operand commutative identities
    {
        var m: TestMir = .{};
        defer m.deinit();

        try m.addLocal(.local_get, 0);
        try m.addI64(0);
        try m.addTag(.i64_add);
        try m.addI64(0);
        try m.addTag(.i64_sub);
        try m.addI64(0);
        try m.addTag(.i64_or);
        try m.addI64(0);
        try m.addTag(.i64_xor);
        try m.addI64(-1);
        try m.addTag(.i64_and);
        try m.addI64(0);
        try m.addTag(.i64_shl);
        try m.addI64(64); // shift_amt == 0 (mod 64)
        try m.addTag(.i64_shr_s);
        try m.addI64(0);
        try m.addTag(.i64_shr_u);

        // Commutative left-constant with local_get
        try m.addI64(0);
        try m.addLocal(.local_get, 1);
        try m.addTag(.i64_add);
        try m.addTag(.i64_add);

        try m.addI64(-1);
        try m.addLocal(.local_get, 2);
        try m.addTag(.i64_and);
        try m.addTag(.i64_add);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .local_get,
                .local_get,
                .i64_add,
                .local_get,
                .i64_add,
                .end,
                .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(u32, 0), datas[0].local);
        try testing.expectEqual(@as(u32, 1), datas[1].local);
        try testing.expectEqual(@as(u32, 2), datas[3].local);
    }
}

test "peepholes: zero comparison, comparison negation, double-boolean, and br_if/select condition normalization" {
    // 1. x == 0 -> eqz, 0 == x -> eqz, comparison inversion, and double-boolean normalization
    {
        var m: TestMir = .{};
        defer m.deinit();

        // x == 0 -> i32_eqz
        try m.addLocal(.local_get, 0);
        try m.addI32(0);
        try m.addTag(.i32_eq);
        try m.addTag(.drop);

        // 0 == x -> i32_eqz
        try m.addI32(0);
        try m.addLocal(.local_get, 0);
        try m.addTag(.i32_eq);
        try m.addTag(.drop);

        // x_i64 == 0 and 0 == x_i64 -> i64_eqz
        try m.addLocal(.local_get, 1);
        try m.addI64(0);
        try m.addTag(.i64_eq);
        try m.addTag(.drop);

        try m.addI64(0);
        try m.addLocal(.local_get, 1);
        try m.addTag(.i64_eq);
        try m.addTag(.drop);

        // Comparison negation via i32_eqz, == 0, != 1, ^ 1
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 2);
        try m.addTag(.i32_lt_s);
        try m.addTag(.i32_eqz); // -> i32_ge_s
        try m.addTag(.drop);

        try m.addLocal(.local_get, 1);
        try m.addLocal(.local_get, 3);
        try m.addTag(.i64_gt_u);
        try m.addI32(0);
        try m.addTag(.i32_eq); // -> i64_le_u
        try m.addTag(.drop);

        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 2);
        try m.addTag(.i32_eq);
        try m.addI32(1);
        try m.addTag(.i32_ne); // -> i32_ne
        try m.addTag(.drop);

        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 2);
        try m.addTag(.i32_ge_u);
        try m.addI32(1);
        try m.addTag(.i32_xor); // -> i32_lt_u
        try m.addTag(.drop);

        // Double-boolean normalization: <cmp>; != 0, <cmp>; == 1, <cmp>; & 1, <bool>; eqz; eqz
        try m.addLocal(.local_get, 0);
        try m.addTag(.i32_eqz);
        try m.addI32(0);
        try m.addTag(.i32_ne);
        try m.addI32(1);
        try m.addTag(.i32_eq);
        try m.addI32(1);
        try m.addTag(.i32_and);
        try m.addTag(.i32_eqz);
        try m.addTag(.i32_eqz);
        try m.addTag(.drop);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .local_get, .i32_eqz,   .drop,
                .local_get, .i32_eqz,   .drop,
                .local_get, .i64_eqz,   .drop,
                .local_get, .i64_eqz,   .drop,
                .local_get, .local_get, .i32_ge_s,
                .drop,      .local_get, .local_get,
                .i64_le_u,  .drop,      .local_get,
                .local_get, .i32_ne,    .drop,
                .local_get, .local_get, .i32_lt_u,
                .drop,      .local_get, .i32_eqz,
                .drop,      .end,       .dbg_epilogue_begin,
            },
            tags,
        );
    }

    // 2. br_if and select condition normalization
    {
        var m: TestMir = .{};
        defer m.deinit();

        try m.addBlock(.block, .empty);
        // x; i32_const 0; i32_ne; br_if 0 -> x; br_if 0
        try m.addLocal(.local_get, 0);
        try m.addI32(0);
        try m.addTag(.i32_ne);
        try m.addLabel(.br_if, 0);

        // x; i32_eqz; i32_eqz; br_if 0 -> x; br_if 0
        try m.addLocal(.local_get, 1);
        try m.addTag(.i32_eqz);
        try m.addTag(.i32_eqz);
        try m.addLabel(.br_if, 0);

        // x; i32_const 0; i32_eq; i32_eqz; br_if 0 -> x; br_if 0
        try m.addLocal(.local_get, 2);
        try m.addI32(0);
        try m.addTag(.i32_eq);
        try m.addTag(.i32_eqz);
        try m.addLabel(.br_if, 0);
        try m.addTag(.end);

        // select with `i32_const 0; i32_ne` and `i32_eqz; i32_eqz`
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 1);
        try m.addLocal(.local_get, 2);
        try m.addI32(0);
        try m.addTag(.i32_ne);
        try m.addTag(.select);

        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 1);
        try m.addTag(.i32_eqz);
        try m.addTag(.i32_eqz);
        try m.addTag(.select);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .block,
                .local_get,
                .br_if,
                .local_get,
                .br_if,
                .local_get,
                .br_if,
                .end,
                .local_get,
                .local_get,
                .local_get,
                .select,
                .local_get,
                .local_get,
                .select,
                .@"return",
                .end,
                .dbg_epilogue_begin,
            },
            tags,
        );
    }
}

test "peepholes: multiplicative identities, power-of-two strength reductions, and non-trapping div/rem folding" {
    // 1. i32 and i64 multiplicative identities and power-of-two strength reductions
    {
        var m: TestMir = .{};
        defer m.deinit();

        // i32: * 1, /_s 1, /_u 1, %_u 1 -> 0 (& 0)
        try m.addLocal(.local_get, 0);
        try m.addI32(1);
        try m.addTag(.i32_mul);
        try m.addI32(1);
        try m.addTag(.i32_div_s);
        try m.addI32(1);
        try m.addTag(.i32_div_u);
        // x * 8 -> x << 3; /_u 16 -> >>_u 4; %_u 32 -> & 31
        try m.addI32(8);
        try m.addTag(.i32_mul);
        try m.addI32(16);
        try m.addTag(.i32_div_u);
        try m.addI32(32);
        try m.addTag(.i32_rem_u);
        try m.addTag(.drop);

        // Commutative left-constant 2^k * local_get: 4 * x -> x << 2
        try m.addI32(4);
        try m.addLocal(.local_get, 0);
        try m.addTag(.i32_mul);
        try m.addTag(.drop);

        // i64: * 1, /_s 1, /_u 1, * 16 -> << 4, /_u 8 -> >>_u 3, %_u 64 -> & 63
        try m.addLocal(.local_get, 1);
        try m.addI64(1);
        try m.addTag(.i64_mul);
        try m.addI64(1);
        try m.addTag(.i64_div_s);
        try m.addI64(1);
        try m.addTag(.i64_div_u);
        try m.addI64(16);
        try m.addTag(.i64_mul);
        try m.addI64(8);
        try m.addTag(.i64_div_u);
        try m.addI64(64);
        try m.addTag(.i64_rem_u);
        try m.addTag(.drop);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .local_get,
                .i32_const,
                .i32_shl,
                .i32_const,
                .i32_shr_u,
                .i32_const,
                .i32_and,
                .drop,
                .local_get,
                .i32_const,
                .i32_shl,
                .drop,
                .local_get,
                .i64_const,
                .i64_shl,
                .i64_const,
                .i64_shr_u,
                .i64_const,
                .i64_and,
                .drop,
                .end,
                .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(i32, 3), datas[1].imm32);
        try testing.expectEqual(@as(i32, 4), datas[3].imm32);
        try testing.expectEqual(@as(i32, 31), datas[5].imm32);
        try testing.expectEqual(@as(i32, 2), datas[9].imm32);
        try testing.expectEqual(@as(u64, 4), readImm64(m.extra.items, datas[13].payload));
        try testing.expectEqual(@as(u64, 3), readImm64(m.extra.items, datas[15].payload));
        try testing.expectEqual(@as(u64, 63), readImm64(m.extra.items, datas[17].payload));
    }

    // 2. Two-constant non-trapping div/rem folding and trapping preservation
    {
        var m: TestMir = .{};
        defer m.deinit();

        // Non-trapping i32 div/rem
        try m.addI32(-17);
        try m.addI32(5);
        try m.addTag(.i32_div_s); // -3
        try m.addI32(-17);
        try m.addI32(5);
        try m.addTag(.i32_rem_s); // -2
        try m.addTag(.i32_add); // -5
        try m.addI32(100);
        try m.addI32(7);
        try m.addTag(.i32_div_u); // 14
        try m.addTag(.i32_add); // 9
        try m.addI32(100);
        try m.addI32(7);
        try m.addTag(.i32_rem_u); // 2
        try m.addTag(.i32_add); // 11

        // Non-trapping i64 div/rem
        try m.addI64(-23);
        try m.addI64(6);
        try m.addTag(.i64_div_s); // -3
        try m.addI64(-23);
        try m.addI64(6);
        try m.addTag(.i64_rem_s); // -5
        try m.addTag(.i64_add); // -8
        try m.addI64(50);
        try m.addI64(8);
        try m.addTag(.i64_div_u); // 6
        try m.addTag(.i64_add); // -2
        try m.addI64(50);
        try m.addI64(8);
        try m.addTag(.i64_rem_u); // 2
        try m.addTag(.i64_add); // 0
        try m.addTag(.i32_wrap_i64); // 0
        try m.addTag(.i32_add); // 11

        // Trapping i32_div_s(minInt(i32), -1) must be preserved
        try m.addI32(std.math.minInt(i32));
        try m.addI32(-1);
        try m.addTag(.i32_div_s);
        try m.addTag(.drop);

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .i32_const,
                .i32_const,
                .i32_const,
                .i32_div_s,
                .drop,
                .end,
                .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(i32, 11), datas[0].imm32);
    }
}

test "peepholes: constant reassociation and MemArg offset integration" {
    var m: TestMir = .{};
    defer m.deinit();

    // (x + 10) + 20 -> x + 30
    try m.addLocal(.local_get, 0);
    try m.addI32(10);
    try m.addTag(.i32_add);
    try m.addI32(20);
    try m.addTag(.i32_add);
    try m.addTag(.drop);

    // (x + 16) - 4 -> x + 12, then folded into i32_load offset=8 -> offset=20
    try m.addLocal(.local_get, 0);
    try m.addI32(16);
    try m.addTag(.i32_add);
    try m.addI32(4);
    try m.addTag(.i32_sub);
    try m.memOp(.i32_load, 8, 2);
    try m.addTag(.drop);

    // (x - 12) + 12 -> x (cancels completely)
    try m.addLocal(.local_get, 0);
    try m.addI32(12);
    try m.addTag(.i32_sub);
    try m.addI32(12);
    try m.addTag(.i32_add);
    try m.addTag(.drop);

    // i64: (x - 4) + 20 -> x + 16, then folded into i64_load offset=4 -> offset=20
    try m.addLocal(.local_get, 1);
    try m.addI64(4);
    try m.addTag(.i64_sub);
    try m.addI64(20);
    try m.addTag(.i64_add);
    try m.memOp(.i64_load, 4, 3);
    try m.addTag(.drop);

    // Bitwise reassociation: (x & 0xff) & 0x0f -> x & 0x0f; (x ^ 5) ^ 5 -> x
    try m.addLocal(.local_get, 0);
    try m.addI32(0xff);
    try m.addTag(.i32_and);
    try m.addI32(0x0f);
    try m.addTag(.i32_and);
    try m.addI32(5);
    try m.addTag(.i32_xor);
    try m.addI32(5);
    try m.addTag(.i32_xor);
    try m.addTag(.@"return");

    try m.finishFunc();
    try m.run();

    const tags = m.instructions.items(.tag);
    const datas = m.instructions.items(.data);
    try testing.expectEqualSlices(
        Mir.Inst.Tag,
        &.{
            .local_get, .i32_const,          .i32_add,  .drop,
            .local_get, .i32_load,           .drop,     .local_get,
            .drop,      .local_get,          .i64_load, .drop,
            .local_get, .i32_const,          .i32_and,  .@"return",
            .end,       .dbg_epilogue_begin,
        },
        tags,
    );
    try testing.expectEqual(@as(i32, 30), datas[1].imm32);
    try testing.expectEqual(@as(u64, 20), m.memOffsetAt(5));
    try testing.expectEqual(@as(u64, 20), m.memOffsetAt(10));
    try testing.expectEqual(@as(i32, 0x0f), datas[13].imm32);
}

test "simplifyLocals: dead zero-pop local_set, self-set elimination, and intra-block constant/copy propagation" {
    // 1. Dead `local_get src; local_set dst`, `global_get G; local_set dst`, and self-set `local_get X; local_set X`
    {
        var m: TestMir = .{};
        defer m.deinit();

        // Dead local copy: local 5 is never read
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_set, 5);

        // Dead global_get into local 6 (overwritten before any read)
        try m.addPayload(.global_get, 0);
        try m.addLocal(.local_set, 6);
        try m.addLocal(.local_get, 1);
        try m.addLocal(.local_set, 6);

        // Self-set `local_get 0; local_set 0` is a no-op
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_set, 0);

        try m.addLocal(.local_get, 0);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{ .local_get, .@"return", .end, .dbg_epilogue_begin },
            tags,
        );
        try testing.expectEqual(@as(u32, 0), datas[0].local);
    }

    // 2. Multi-field promoted aggregate constant & copy propagation chain
    {
        var m: TestMir = .{};
        defer m.deinit();

        // Promoted 2-field struct initialized with constants (L2=10, L3=20), copied to (L4, L5),
        // then copied to (L6, L7), then summed:
        try m.addI32(10);
        try m.addLocal(.local_set, 2);
        try m.addI32(20);
        try m.addLocal(.local_set, 3);

        try m.addLocal(.local_get, 2);
        try m.addLocal(.local_set, 4);
        try m.addLocal(.local_get, 3);
        try m.addLocal(.local_set, 5);

        try m.addLocal(.local_get, 4);
        try m.addLocal(.local_set, 6);
        try m.addLocal(.local_get, 5);
        try m.addLocal(.local_set, 7);

        try m.addLocal(.local_get, 6);
        try m.addLocal(.local_get, 7);
        try m.addTag(.i32_add);

        // Promoted 2-field struct from runtime params (0, 1) copied through (L8, L9) -> (L10, L11):
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_set, 8);
        try m.addLocal(.local_get, 1);
        try m.addLocal(.local_set, 9);

        try m.addLocal(.local_get, 8);
        try m.addLocal(.local_set, 10);
        try m.addLocal(.local_get, 9);
        try m.addLocal(.local_set, 11);

        try m.addLocal(.local_get, 10);
        try m.addLocal(.local_get, 11);
        try m.addTag(.i32_sub);
        try m.addTag(.i32_add);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .i32_const,
                .local_get,
                .local_get,
                .i32_sub,
                .i32_add,
                .@"return",
                .end,
                .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(i32, 30), datas[0].imm32);
        try testing.expectEqual(@as(u32, 0), datas[1].local);
        try testing.expectEqual(@as(u32, 1), datas[2].local);
    }

    // 3. Invalidation when source local Y is overwritten after `local_get Y; local_set X`,
    // and invalidation across basic-block boundaries (`.block`, `.loop`, `.end`, `.br_if`).
    {
        var m: TestMir = .{};
        defer m.deinit();

        // X (local 2) = Y (local 0); then Y (local 0) is overwritten with 99;
        // reading X (local 2) MUST NOT propagate local 0 (which now holds 99) or 99!
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_set, 2);
        try m.addI32(99);
        try m.addLocal(.local_set, 0);
        try m.addLocal(.local_get, 2);
        try m.addLocal(.local_get, 0);
        try m.addTag(.i32_add);

        // Local 3 set to 77 before a loop must NOT propagate inside the loop (across `.loop` boundary)
        // when the loop modifies local 3.
        try m.addI32(77);
        try m.addLocal(.local_set, 3);
        try m.addBlock(.loop, .empty);
        try m.addLocal(.local_get, 3);
        try m.addI32(1);
        try m.addTag(.i32_sub);
        try m.addLocal(.local_tee, 3);
        try m.addLabel(.br_if, 0);
        try m.addTag(.end);

        // Local 3 read after `.end` must NOT propagate 77 from before the loop
        try m.addLocal(.local_get, 3);
        try m.addTag(.i32_add);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .local_get,
                .local_set,
                .i32_const,
                .local_set,
                .local_get,
                .i32_const,
                .i32_add,
                .i32_const,
                .local_set,
                .loop,
                .local_get,
                .i32_const,
                .i32_sub,
                .local_tee,
                .br_if,
                .end,
                .local_get,
                .i32_add,
                .@"return",
                .end,
                .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(u32, 0), datas[0].local);
        try testing.expectEqual(@as(u32, 2), datas[1].local);
        try testing.expectEqual(@as(u32, 2), datas[4].local);
        try testing.expectEqual(@as(i32, 99), datas[5].imm32);
        try testing.expectEqual(@as(u32, 3), datas[16].local);
    }

    // 4. `simplifyBlocks` collapses `.empty` block containing `local_get; local_set` pairs + `br 0`,
    // unlocking subsequent copy propagation and dead-local elimination.
    {
        var m: TestMir = .{};
        defer m.deinit();

        // Simulates an inlined function returning a promoted 2-field struct via `block (.empty)`:
        try m.addBlock(.block, .empty);
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_set, 4);
        try m.addLocal(.local_get, 1);
        try m.addLocal(.local_set, 5);
        try m.addLabel(.br, 0);
        try m.addTag(.end);

        try m.addLocal(.local_get, 4);
        try m.addLocal(.local_get, 5);
        try m.addTag(.i32_add);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .local_get,
                .local_get,
                .i32_add,
                .@"return",
                .end,
                .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(u32, 0), datas[0].local);
        try testing.expectEqual(@as(u32, 1), datas[1].local);
    }
}

test "simplifyLocals and hoistLoopInvariantLocalSets: structured block/loop scope preservation and LICM (#197)" {
    // 1. Unmodified known_locals survive across `.block`, `.loop`, `.br_if`, and `.end` even when
    // an inner branch + `return` clears `known_locals` inside the block, while loop-modified locals are invalidated.
    {
        var m: TestMir = .{};
        defer m.deinit();

        // Local 4 = 100 (invariant), Local 5 = local 0 (invariant copy), Local 6 = 50 (modified inside loop)
        try m.addI32(100);
        try m.addLocal(.local_set, 4);
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_set, 5);
        try m.addI32(50);
        try m.addLocal(.local_set, 6);

        try m.addBlock(.loop, .empty);
        // Inside loop: conditional block that has a `return` (clearing known_locals on the return path)
        try m.addBlock(.block, .empty);
        try m.addLocal(.local_get, 1);
        try m.addLabel(.br_if, 0);
        try m.addLocal(.local_get, 4); // propagates 100
        try m.addTag(.@"return");
        try m.addTag(.end);

        // After the inner `.end`, invariant locals 4 and 5 are restored from `entry_known`!
        try m.addLocal(.local_get, 4); // -> i32_const 100
        try m.addLocal(.local_get, 5); // -> local_get 0
        try m.addTag(.i32_add);
        try m.addLocal(.local_get, 6); // modified in loop -> stays local_get 6
        try m.addTag(.i32_add);
        try m.addLocal(.local_tee, 6);
        try m.addLabel(.br_if, 0);
        try m.addTag(.end);

        // After loop `.end`, invariant local 4 (100) and local 5 (local 0) are still known!
        try m.addLocal(.local_get, 4);
        try m.addLocal(.local_get, 5);
        try m.addTag(.i32_add);
        try m.addLocal(.local_get, 6);
        try m.addTag(.i32_add);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        // Local 4 and Local 5 should be completely eliminated!
        for (tags, datas) |t, d| {
            if (t == .local_get or t == .local_set or t == .local_tee) {
                try testing.expect(d.local != 4 and d.local != 5);
            }
        }
    }

    // 2. `hoistLoopInvariantLocalSets` hoists `<val_expr>; local_set X` out of `.loop` header
    // and then `simplifyLocals` propagates or folds it across the loop!
    {
        var m: TestMir = .{};
        defer m.deinit();

        try m.addBlock(.loop, .empty);
        // Loop-invariant header local_set: local 7 = local 0 + 16
        try m.addLocal(.local_get, 0);
        try m.addI32(16);
        try m.addTag(.i32_add);
        try m.addLocal(.local_set, 7);

        // Non-invariant local 8 (modified twice in loop -> must NOT be hoisted)
        try m.addI32(1);
        try m.addLocal(.local_set, 8);

        // Loop body uses local 7 and modifies local 1 and local 8
        try m.addLocal(.local_get, 7);
        try m.memOp(.i32_load, 0, 2);
        try m.addLocal(.local_get, 8);
        try m.addTag(.i32_add);
        try m.addLocal(.local_set, 8);

        try m.addLocal(.local_get, 1);
        try m.addI32(1);
        try m.addTag(.i32_sub);
        try m.addLocal(.local_tee, 1);
        try m.addLabel(.br_if, 0);
        try m.addTag(.end);

        try m.addLocal(.local_get, 8);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        // The invariant `local_get 0; i32_const 16; i32_add; local_set 7` must appear BEFORE `.loop`!
        var loop_idx: ?usize = null;
        for (tags, 0..) |t, idx| {
            if (t == .loop) {
                loop_idx = idx;
                break;
            }
        }
        try testing.expect(loop_idx != null);
        try testing.expectEqual(@as(usize, 4), loop_idx.?);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{ .local_get, .i32_const, .i32_add, .local_set },
            tags[0..loop_idx.?],
        );
    }
}

test "optimizeMemoryAccesses: store-to-load forwarding, narrow bit-slice extraction, non-overlap disambiguation, and DSE (#198)" {
    // 1. Overwrite DSE + Non-overlapping store-to-load forwarding on the same base_local
    {
        var m: TestMir = .{};
        defer m.deinit();

        // Store 111 to [base+0..4], then overwrite [base+0..4] with 222 -> first store is DSE-eliminated!
        try m.addLocal(.local_get, 0);
        try m.addI32(111);
        try m.memOp(.i32_store, 0, 2);

        try m.addLocal(.local_get, 0);
        try m.addI32(222);
        try m.memOp(.i32_store, 0, 2);

        // Non-overlapping store 333 to [base+4..8] -> preserves [base+0..4] == 222!
        try m.addLocal(.local_get, 0);
        try m.addI32(333);
        try m.memOp(.i32_store, 4, 2);

        // Load from [base+0..4] and [base+4..8] -> both forward to constants 222 and 333 and fold to 555!
        try m.addLocal(.local_get, 0);
        try m.memOp(.i32_load, 0, 2);
        try m.addLocal(.local_get, 0);
        try m.memOp(.i32_load, 4, 2);
        try m.addTag(.i32_add);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        const datas = m.instructions.items(.data);
        try testing.expectEqualSlices(
            Mir.Inst.Tag,
            &.{
                .local_get, .i32_const, .i32_store,
                .local_get, .i32_const, .i32_store,
                .i32_const, .@"return", .end,
                .dbg_epilogue_begin,
            },
            tags,
        );
        try testing.expectEqual(@as(i32, 222), datas[1].imm32);
        try testing.expectEqual(@as(i32, 333), datas[4].imm32);
        try testing.expectEqual(@as(i32, 555), datas[6].imm32);
    }

    // 2. Narrow bit-slice extraction (i32_store -> i32_load8_u, i32_load8_s, i32_load16_u, i32_load16_s)
    // and sub-word store-to-load forwarding
    {
        var m: TestMir = .{};
        defer m.deinit();

        // Store 0x80FF_7F01 to [base+0..4]
        try m.addLocal(.local_get, 0);
        try m.addI32(@bitCast(@as(u32, 0x80FF_7F01)));
        try m.memOp(.i32_store, 0, 2);

        // Load byte at offset 1 (unsigned -> 0x7F = 127)
        try m.addLocal(.local_get, 0);
        try m.memOp(.i32_load8_u, 1, 0);

        // Load byte at offset 3 (signed -> 0x80 sign-extended = -128)
        try m.addLocal(.local_get, 0);
        try m.memOp(.i32_load8_s, 3, 0);
        try m.addTag(.i32_add); // 127 + (-128) = -1

        // Sub-word store8 of local 1 at offset 8 followed by load8_u and load8_s
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 1);
        try m.memOp(.i32_store8, 8, 0);
        try m.addLocal(.local_get, 0);
        try m.memOp(.i32_load8_u, 8, 0);
        try m.addLocal(.local_get, 0);
        try m.memOp(.i32_load8_s, 8, 0);
        try m.addTag(.i32_add);
        try m.addTag(.i32_add);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        // No i32_load8_u or i32_load8_s instructions should remain!
        for (tags) |t| {
            try testing.expect(t != .i32_load8_u and t != .i32_load8_s);
        }
    }

    // 3. Redundant load-to-load elimination (`local_get base; i32_load off; local_set V; ...; local_get base; i32_load off`)
    {
        var m: TestMir = .{};
        defer m.deinit();

        try m.addLocal(.local_get, 0);
        try m.memOp(.i32_load, 12, 2);
        try m.addLocal(.local_set, 2);

        // Second load from the same (base=0, offset=12) forwards from local 2!
        try m.addLocal(.local_get, 0);
        try m.memOp(.i32_load, 12, 2);
        try m.addLocal(.local_get, 2);
        try m.addTag(.i32_add);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        var load_count: usize = 0;
        for (tags) |t| {
            if (t == .i32_load) load_count += 1;
        }
        try testing.expectEqual(@as(usize, 1), load_count);
    }
}

test "peepholes: mul by 2^k +- 1, magic div/rem strength reduction, possibleOnes mask stripping, and conversions (#199)" {
    // 1. `mul` by 2^k +- 1 (`* 3`, `* 5`, `* 7`, `* 9`) and non-power-of-two `div_u`/`rem_u`/`div_s`/`rem_s`
    {
        var m: TestMir = .{};
        defer m.deinit();

        // local 0 * 3 -> (local 0 << 1) + local 0
        try m.addLocal(.local_get, 0);
        try m.addI32(3);
        try m.addTag(.i32_mul);

        // local 0 * 7 -> (local 0 << 3) - local 0
        try m.addLocal(.local_get, 0);
        try m.addI32(7);
        try m.addTag(.i32_mul);
        try m.addTag(.i32_add);

        // local 0 /u 10 -> magic u64 multiply + shr_u
        try m.addLocal(.local_get, 0);
        try m.addI32(10);
        try m.addTag(.i32_div_u);
        try m.addTag(.i32_add);

        // local 0 %u 10 -> magic quotient * 10 subtracted from local 0
        try m.addLocal(.local_get, 0);
        try m.addI32(10);
        try m.addTag(.i32_rem_u);
        try m.addTag(.i32_add);

        // local 0 /s 4 (power of two signed div) and local 0 /s 10 (non-power-of-two signed div)
        try m.addLocal(.local_get, 0);
        try m.addI32(4);
        try m.addTag(.i32_div_s);
        try m.addTag(.i32_add);

        try m.addLocal(.local_get, 0);
        try m.addI32(10);
        try m.addTag(.i32_div_s);
        try m.addTag(.i32_add);

        try m.addLocal(.local_get, 0);
        try m.addI32(10);
        try m.addTag(.i32_rem_s);
        try m.addTag(.i32_add);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        for (tags) |t| {
            try testing.expect(t != .i32_div_u and t != .i32_rem_u and t != .i32_div_s and t != .i32_rem_s);
        }
    }

    // 2. `possibleOnesI32`/`possibleOnesI64` redundant mask stripping, extend/wrap conversions,
    // `eqz(xor)` -> `eq`, `br_if(xor)` -> `br_if(ne)`, `select` negation, float unary idempotents, and same-local ops
    {
        var m: TestMir = .{};
        defer m.deinit();

        // Redundant mask on i32_load8_u (& 0xFF and & 0xFFFF stripped)
        try m.addLocal(.local_get, 0);
        try m.memOp(.i32_load8_u, 0, 0);
        try m.addI32(0xFF);
        try m.addTag(.i32_and);

        // i32_extend8_s(i32_load8_u) -> i32_load8_s (and redundant second i32_extend8_s stripped)
        try m.addLocal(.local_get, 0);
        try m.memOp(.i32_load8_u, 1, 0);
        try m.addTag(.i32_extend8_s);
        try m.addTag(.i32_extend8_s);
        try m.addTag(.i32_add);

        // i32_wrap_i64(i64_extend_i32_u(x)) -> x
        try m.addLocal(.local_get, 1);
        try m.addTag(.i64_extend_i32_u);
        try m.addI64(0xFFFF_FFFF);
        try m.addTag(.i64_and); // stripped by possibleOnesI64!
        try m.addTag(.i32_wrap_i64); // elided with i64_extend_i32_u!
        try m.addTag(.i32_add);

        // i32_eqz(i32_xor(a, b)) -> i32_eq(a, b)
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 1);
        try m.addTag(.i32_xor);
        try m.addTag(.i32_eqz);
        try m.addTag(.i32_add);

        // select(local 0, local 1, i32_eqz(local 2)) -> select(local 1, local 0, local 2)
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 1);
        try m.addLocal(.local_get, 2);
        try m.addTag(.i32_eqz);
        try m.addTag(.select);
        try m.addTag(.i32_add);

        // select(local 0, local 0, local 2) -> local 0
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 2);
        try m.addTag(.select);
        try m.addTag(.i32_add);

        // Same-local folds: (L0 ^ L0) + (L0 == L0) -> 0 + 1 = 1
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 0);
        try m.addTag(.i32_xor);
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 0);
        try m.addTag(.i32_eq);
        try m.addTag(.i32_add);
        try m.addTag(.i32_add);

        // br_if(i32_xor(a, b)) -> br_if(i32_ne(a, b))
        try m.addBlock(.block, .empty);
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 1);
        try m.addTag(.i32_xor);
        try m.addLabel(.br_if, 0);
        try m.addLocal(.local_get, 2);
        try m.addTag(.@"return");
        try m.addTag(.end);

        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        const tags = m.instructions.items(.tag);
        for (tags) |t| {
            try testing.expect(t != .i32_and and t != .i64_and);
            try testing.expect(t != .i32_extend8_s);
            try testing.expect(t != .i64_extend_i32_u and t != .i32_wrap_i64);
            try testing.expect(t != .i32_xor and t != .i32_eqz);
        }
    }

    // 3. Exact 64-bit unsigned magic division/remainder verification across cheap (d=3, d=10)
    // and needs-add (d=7) divisors on boundary u32 inputs (including >= 0x80000000).
    {
        const divisors = [_]u32{ 3, 7, 10 };
        const inputs = [_]u32{
            0,          1,          2,          3,          6,
            7,          8,          9,          10,         11,
            0x7FFFFFFF, 0x80000000, 0xC0000000, 0xFFFFFFFE, 0xFFFFFFFF,
        };

        for (divisors) |d| {
            for ([_]Mir.Inst.Tag{ .i32_div_u, .i32_rem_u }) |op_tag| {
                // First optimize `local_get 0; i32_const d; <div_u/rem_u>; return`
                var base: TestMir = .{};
                defer base.deinit();

                try base.addLocal(.local_get, 0);
                try base.addI32(@bitCast(d));
                try base.addTag(op_tag);
                try base.addTag(.@"return");
                try base.finishFunc();
                try base.run();

                // Verify the division/remainder was strength-reduced (no i32_div_u / i32_rem_u remains)
                for (base.instructions.items(.tag)) |t| {
                    try testing.expect(t != .i32_div_u and t != .i32_rem_u);
                }

                // Now substitute `local_get 0` with `i32_const x` in the strength-reduced sequence
                // and run the optimizer to evaluate the exact emitted 64-bit arithmetic sequence!
                for (inputs) |x| {
                    var eval_mir: TestMir = .{};
                    defer eval_mir.deinit();

                    try eval_mir.extra.appendSlice(testing.allocator, base.extra.items);
                    for (base.instructions.items(.tag), base.instructions.items(.data)) |t, data| {
                        if (t == .local_get and data.local == 0) {
                            try eval_mir.addI32(@bitCast(x));
                        } else {
                            try eval_mir.instructions.append(testing.allocator, .{ .tag = t, .data = data });
                        }
                    }
                    try eval_mir.run();

                    const eval_tags = eval_mir.instructions.items(.tag);
                    const eval_datas = eval_mir.instructions.items(.data);
                    try testing.expectEqualSlices(
                        Mir.Inst.Tag,
                        &.{ .i32_const, .@"return", .end, .dbg_epilogue_begin },
                        eval_tags,
                    );
                    const expected: u32 = if (op_tag == .i32_div_u) (x / d) else (x % d);
                    try testing.expectEqual(@as(i32, @bitCast(expected)), eval_datas[0].imm32);
                }
            }
        }
    }
}

test "peepholes: v128.andnot, shift/rotate bitmask elision, and rotate synthesis (#233, #234)" {
    // 1. v128.and(a, v128.not(b)), v128.and(v128.not(b), a), and v128.not(v128.not(a)) (#233)
    {
        var m: TestMir = .{};
        defer m.deinit();

        // Direct: local_get 0; local_get 1; v128_not; v128_and -> local_get 0; local_get 1; v128_andnot
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 1);
        try m.simdOp(.v128_not);
        try m.simdOp(.v128_and);

        // CodeGen pattern with temporary local:
        // local_get 1; v128_not; local_set 2; local_get 0; local_get 2; v128_and
        // -> reordered by simplifyLocals and folded to local_get 0; local_get 1; v128_andnot
        try m.addLocal(.local_get, 1);
        try m.simdOp(.v128_not);
        try m.addLocal(.local_set, 2);
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 2);
        try m.simdOp(.v128_and);

        // Commuted: local_get 1; v128_not; local_get 0; v128_and -> local_get 0; local_get 1; v128_andnot
        try m.addLocal(.local_get, 1);
        try m.simdOp(.v128_not);
        try m.addLocal(.local_get, 0);
        try m.simdOp(.v128_and);

        // Double negation: local_get 0; v128_not; v128_not -> local_get 0
        try m.addLocal(.local_get, 0);
        try m.simdOp(.v128_not);
        try m.simdOp(.v128_not);

        try m.simdOp(.v128_xor);
        try m.simdOp(.v128_xor);
        try m.simdOp(.v128_xor);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        var andnot_count: usize = 0;
        var not_count: usize = 0;
        var and_count: usize = 0;
        for (m.instructions.items(.tag), m.instructions.items(.data)) |t, d| {
            if (t == .simd_prefix) {
                const op = m.extra.items[d.payload];
                if (op == @intFromEnum(std.wasm.SimdOpcode.v128_andnot)) andnot_count += 1;
                if (op == @intFromEnum(std.wasm.SimdOpcode.v128_not)) not_count += 1;
                if (op == @intFromEnum(std.wasm.SimdOpcode.v128_and)) and_count += 1;
            }
        }
        try testing.expectEqual(@as(usize, 3), andnot_count);
        try testing.expectEqual(@as(usize, 0), not_count);
        try testing.expectEqual(@as(usize, 0), and_count);
    }

    // 2. Shift/rotate bitmask elision: 32-bit (& 31), 64-bit (& 63 and i32 & 63 + extend), and SIMD shifts (#234)
    {
        var m: TestMir = .{};
        defer m.deinit();

        // 32-bit shift with & 31
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 1);
        try m.addI32(31);
        try m.addTag(.i32_and);
        try m.addTag(.i32_shl);

        // 64-bit shift with CodeGen's i32 & 63; i64_extend_i32_u
        try m.addLocal(.local_get, 2);
        try m.addLocal(.local_get, 1);
        try m.addI32(63);
        try m.addTag(.i32_and);
        try m.addTag(.i64_extend_i32_u);
        try m.addTag(.i64_shr_u);
        try m.addTag(.i32_wrap_i64);
        try m.addTag(.i32_add);

        // SIMD i8x16_shl with & 7 and i16x8_shr_u with & 15
        try m.addLocal(.local_get, 3);
        try m.addLocal(.local_get, 1);
        try m.addI32(7);
        try m.addTag(.i32_and);
        try m.simdOp(.i8x16_shl);
        try m.addLocal(.local_get, 1);
        try m.addI32(15);
        try m.addTag(.i32_and);
        try m.simdOp(.i16x8_shr_u);
        try m.addTag(.drop);

        try m.addTag(.@"return");
        try m.finishFunc();
        try m.run();

        for (m.instructions.items(.tag)) |t| {
            try testing.expect(t != .i32_and and t != .i64_and);
        }
    }

    // 3. 32-bit and 64-bit constant and variable rotate synthesis (#234)
    {
        var m: TestMir = .{};
        defer m.deinit();

        // Constant 32-bit rotate: (x << 5) | (x >> 27) -> x rotl 5
        try m.addLocal(.local_get, 0);
        try m.addI32(5);
        try m.addTag(.i32_shl);
        try m.addLocal(.local_get, 0);
        try m.addI32(27);
        try m.addTag(.i32_shr_u);
        try m.addTag(.i32_or);

        // Variable 32-bit rotate: (x << k) | (x >> ((0 - k) & 31)) -> x rotl k
        try m.addLocal(.local_get, 0);
        try m.addLocal(.local_get, 1);
        try m.addTag(.i32_shl);
        try m.addLocal(.local_get, 0);
        try m.addI32(0);
        try m.addLocal(.local_get, 1);
        try m.addTag(.i32_sub);
        try m.addI32(31);
        try m.addTag(.i32_and);
        try m.addTag(.i32_shr_u);
        try m.addTag(.i32_or);
        try m.addTag(.i32_add);

        // Constant 64-bit rotate: (y >> 13) | (y << 51) -> y rotr 13
        try m.addLocal(.local_get, 2);
        try m.addI64(13);
        try m.addTag(.i64_shr_u);
        try m.addLocal(.local_get, 2);
        try m.addI64(51);
        try m.addTag(.i64_shl);
        try m.addTag(.i64_or);
        try m.addTag(.i32_wrap_i64);
        try m.addTag(.i32_add);

        try m.addTag(.@"return");
        try m.finishFunc();
        try m.run();

        var rotl32_count: usize = 0;
        var rotr64_count: usize = 0;
        for (m.instructions.items(.tag)) |t| {
            try testing.expect(t != .i32_shl and t != .i32_shr_u and t != .i32_or);
            try testing.expect(t != .i64_shl and t != .i64_shr_u and t != .i64_or);
            if (t == .i32_rotl) rotl32_count += 1;
            if (t == .i64_rotr) rotr64_count += 1;
        }
        try testing.expectEqual(@as(usize, 2), rotl32_count);
        try testing.expectEqual(@as(usize, 1), rotr64_count);
    }
}

test "f16 soft-promotion optimizations: constant folding, redundant extend CSE, and memory forwarding (#231)" {
    // 1. Constant folding: `i32_const (f16 bits) + __extendhfsf2 -> f32_const`,
    //    `f32_const + f32_add -> f32_const`, `f32_const + __truncsfhf2 -> i32_const`,
    //    and `call_intrinsic .__extendhfsf2; call_intrinsic .__truncsfhf2` identity elimination
    {
        var m: TestMir = .{};
        defer m.deinit();

        const h_1_5: u16 = @bitCast(@as(f16, 1.5));
        const h_2_25: u16 = @bitCast(@as(f16, 2.25));
        const h_3_75: u16 = @bitCast(@as(f16, 3.75));

        // Constant f16 addition: @as(f16, 1.5) + @as(f16, 2.25) -> @as(f16, 3.75)
        try m.addI32(@intCast(h_1_5));
        try m.addIntrinsic(.__extendhfsf2);
        try m.addI32(@intCast(h_2_25));
        try m.addIntrinsic(.__extendhfsf2);
        try m.addTag(.f32_add);
        try m.addIntrinsic(.__truncsfhf2);

        // Redundant extend + trunc round-trip: `local_get 0; __extendhfsf2; __truncsfhf2` -> `local_get 0`
        try m.addLocal(.local_get, 0);
        try m.addIntrinsic(.__extendhfsf2);
        try m.addIntrinsic(.__truncsfhf2);

        try m.addTag(.i32_add);
        try m.addTag(.@"return");
        try m.finishFunc();
        try m.run();

        for (m.instructions.items(.tag)) |t| {
            try testing.expect(t != .call_intrinsic and t != .f32_const and t != .f32_add);
        }
        try testing.expectEqual(Mir.Inst.Tag.i32_const, m.instructions.items(.tag)[0]);
        try testing.expectEqual(@as(i32, @intCast(h_3_75)), m.instructions.items(.data)[0].imm32);
    }

    // 2. Temporary local reordering across `call_intrinsic .__extendhfsf2` and redundant
    //    `local_get X; call_intrinsic .__extendhfsf2` CSE when an extended f32 local is live
    {
        var m: TestMir = .{};
        defer m.deinit();

        // Extended f16 stored in local 2: `local_get 0; __extendhfsf2; local_set 2`
        // Followed by two uses of `local_get 0; __extendhfsf2`:
        // `local_get 2` is turned into `local_tee 2` and the second `local_get 0; __extendhfsf2`
        // is replaced with `local_get 2`, leaving only 1 call to `.__extendhfsf2` for local 0.
        try m.addLocal(.local_get, 0);
        try m.addIntrinsic(.__extendhfsf2);
        try m.addLocal(.local_set, 2);
        try m.addLocal(.local_get, 2);
        try m.addLocal(.local_get, 0);
        try m.addIntrinsic(.__extendhfsf2);
        try m.addTag(.f32_mul);
        try m.addIntrinsic(.__truncsfhf2);

        // CodeGen binary f16 rhs spill pattern (`lhs + (b - c)`):
        // `<pure rhs_expr>; local_set 3; local_get 0; __extendhfsf2; local_get 3; __extendhfsf2; f32_add`
        // -> reordered to eliminate temporary local 3, and `local_get 0; __extendhfsf2` is also CSE'd to `local_get 2`!
        try m.addLocal(.local_get, 1);
        try m.addIntrinsic(.__extendhfsf2);
        try m.addLocal(.local_get, 4);
        try m.addIntrinsic(.__extendhfsf2);
        try m.addTag(.f32_sub);
        try m.addIntrinsic(.__truncsfhf2);
        try m.addLocal(.local_set, 3);
        try m.addLocal(.local_get, 0);
        try m.addIntrinsic(.__extendhfsf2);
        try m.addLocal(.local_get, 3);
        try m.addIntrinsic(.__extendhfsf2);
        try m.addTag(.f32_add);
        try m.addIntrinsic(.__truncsfhf2);
        try m.addTag(.i32_add);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        var extend_count: usize = 0;
        var local0_get_count: usize = 0;
        for (m.instructions.items(.tag), m.instructions.items(.data)) |t, d| {
            if (t == .call_intrinsic and d.intrinsic == .__extendhfsf2) extend_count += 1;
            if (t == .local_get and d.local == 0) local0_get_count += 1;
            if (t == .local_set or t == .local_get or t == .local_tee) {
                try testing.expect(d.local != 3);
            }
        }
        try testing.expectEqual(@as(usize, 4), extend_count);
        try testing.expectEqual(@as(usize, 1), local0_get_count);
    }

    // 3. Store-to-load memory forwarding preserved across pure scalar conversion intrinsics
    //    (`__extendhfsf2`, `__truncsfhf2`, `__trunctfdf2`, etc.)
    {
        var m: TestMir = .{};
        defer m.deinit();

        const h_2_0: u16 = @bitCast(@as(f16, 2.0));
        const h_4_0: u16 = @bitCast(@as(f16, 4.0));

        // Store `f16(2.0)` at `[local 0 + 8]`, call `.__extendhfsf2` and `.__truncsfhf2` on
        // stack values, then reload `i32_load16_u [local 0 + 8]` and add to itself:
        // the reload is forwarded from the store and constant-folded to `f16(4.0)`!
        try m.addLocal(.local_get, 0);
        try m.addI32(@intCast(h_2_0));
        try m.memOp(.i32_store16, 8, 1);

        try m.addLocal(.local_get, 0);
        try m.memOp(.i32_load16_u, 8, 1);
        try m.addIntrinsic(.__extendhfsf2);

        try m.addLocal(.local_get, 0);
        try m.memOp(.i32_load16_u, 8, 1);
        try m.addIntrinsic(.__extendhfsf2);

        try m.addTag(.f32_add);
        try m.addIntrinsic(.__truncsfhf2);
        try m.addTag(.@"return");

        try m.finishFunc();
        try m.run();

        for (m.instructions.items(.tag)) |t| {
            try testing.expect(t != .i32_load16_u and t != .call_intrinsic);
        }
        var found_const_4 = false;
        for (m.instructions.items(.tag), m.instructions.items(.data)) |t, d| {
            if (t == .i32_const and d.imm32 == @as(i32, @intCast(h_4_0))) {
                found_const_4 = true;
            }
        }
        try testing.expect(found_const_4);
    }
}




