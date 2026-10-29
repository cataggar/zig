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
    return Pass(Inst).simplifyLocals(gpa, insts, out);
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

                if (try Self.simplifyLocals(gpa, current.items, &next)) {
                    std.mem.swap(std.ArrayList(Inst), &current, &next);
                    round_changed = true;
                }

                if (try Self.foldConstants(gpa, current.items, &next, mir_extra)) {
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

        fn isConstTag(tag: Inst.Tag) bool {
            return switch (tag) {
                .i32_const, .i64_const, .f32_const, .f64_const => true,
                else => false,
            };
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
                    .@"return", .@"unreachable" => return false,
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

        fn simplifyLocals(
            gpa: Allocator,
            insts: []const Inst,
            out: *std.ArrayList(Inst),
        ) Allocator.Error!bool {
            out.clearRetainingCapacity();
            try out.ensureTotalCapacity(gpa, insts.len);

            var changed = false;
            var i: usize = 0;
            while (i < insts.len) {
                const inst = insts[i];
                if (inst.tag == .local_set) {
                    var k: usize = i + 1;
                    while (k < insts.len and insts[k].tag == .dbg_line) : (k += 1) {}
                    if (k < insts.len and
                        insts[k].tag == .local_get and
                        inst.data.local == insts[k].data.local)
                    {
                        const local = inst.data.local;
                        if (isLocalReadBeforeOverwriteOrExit(insts, k + 1, local, k)) {
                            out.appendAssumeCapacity(.{ .tag = .local_tee, .data = .{ .local = local } });
                        }
                        for (insts[i + 1 .. k]) |dbg_inst| {
                            out.appendAssumeCapacity(dbg_inst);
                        }
                        changed = true;
                        i = k + 1;
                        continue;
                    }
                }
                if (inst.tag == .local_tee) {
                    const local = inst.data.local;
                    if (!isLocalReadBeforeOverwriteOrExit(insts, i + 1, local, null)) {
                        changed = true;
                        i += 1;
                        continue;
                    }
                }
                out.appendAssumeCapacity(inst);
                i += 1;
            }
            return changed;
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
                const len = out.items.len;

                // Constant drop: `<const>, .drop` -> remove both
                if (inst.tag == .drop and len >= 1 and isConstTag(out.items[len - 1].tag)) {
                    _ = out.pop();
                    changed = true;
                    continue;
                }

                // Constant select: `<const1>, <const2>, .i32_const cond, .select` -> `<const1>` or `<const2>`
                if (inst.tag == .select and len >= 3) {
                    const c1 = out.items[len - 3];
                    const c2 = out.items[len - 2];
                    const cond = out.items[len - 1];
                    if (cond.tag == .i32_const and isConstTag(c1.tag) and c1.tag == c2.tag) {
                        const chosen = if (cond.data.imm32 != 0) c1 else c2;
                        out.items.len = len - 2;
                        out.items[len - 3] = chosen;
                        changed = true;
                        continue;
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
                        .i32_and => lhs & rhs,
                        .i32_or => lhs | rhs,
                        .i32_xor => lhs ^ rhs,
                        .i32_shl => @bitCast(lhs_u << shift_amt),
                        .i32_shr_s => lhs >> shift_amt,
                        .i32_shr_u => @bitCast(lhs_u >> shift_amt),
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
                        .i64_and => lhs_u & rhs_u,
                        .i64_or => lhs_u | rhs_u,
                        .i64_xor => lhs_u ^ rhs_u,
                        .i64_shl => lhs_u << shift_amt,
                        .i64_shr_s => @bitCast(lhs_s >> shift_amt),
                        .i64_shr_u => lhs_u >> shift_amt,
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

                out.appendAssumeCapacity(inst);
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

                if (inst.tag == .br_if and len >= 1 and out.items[len - 1].tag == .i32_const) {
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

                if (inst.tag == .br_table and len >= 1 and out.items[len - 1].tag == .i32_const) {
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

                        // Pattern 1: `block (.empty)` whose body is solely `br 0` (ignoring `.dbg_line`).
                        if (inst.data.block_type == .empty) {
                            if (findSoleBr0(body)) |br_pos| {
                                try out.appendSlice(gpa, body[0..br_pos]);
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
            for (body, 0..) |inst, idx| {
                if (inst.tag == .br and inst.data.label == 0) {
                    if (br_idx != null) return null;
                    br_idx = idx;
                } else if (inst.tag != .dbg_line) {
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
                    .@"unreachable", .br, .br_table, .@"return" => return true,
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
                    .@"unreachable", .br, .br_table, .@"return" => {
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
            call_tag_index,
            enum_tag_name_table_ref,
            call_intrinsic,
            drop = 0x1A,
            select = 0x1B,
            local_get = 0x20,
            local_set = 0x21,
            local_tee = 0x22,
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
            misc_prefix,
            simd_prefix,
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
        };
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
