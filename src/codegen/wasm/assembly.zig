const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const CodeGen = @import("CodeGen.zig");
const Mir = @import("Mir.zig");
const InternPool = @import("../../InternPool.zig");

pub const Operand = union(enum) {
    local: u32,
    imm: i64,
    func_nav: InternPool.Nav.Index,
};

pub const OperandMap = std.array_hash_map.String(Operand);

pub fn assemble(
    cg: *CodeGen,
    source: [:0]const u8,
    operand_map: *const OperandMap,
) !void {
    cg.asm_operands = operand_map;
    defer cg.asm_operands = null;

    var line_it = mem.tokenizeAny(u8, source, "\n\r;");
    next_line: while (line_it.next()) |line| {
        var word_it = mem.tokenizeAny(u8, line, " \t");
        const inst = word_it.next() orelse continue :next_line;

        if (mem.eql(u8, inst, ".globaltype")) {
            try parseGlobalType(cg, inst, &word_it);
        } else if (mem.eql(u8, inst, "unreachable")) {
            try cg.addTag(.@"unreachable");
        } else if (mem.eql(u8, inst, "block")) {
            try cg.addTag(.block);
        } else if (mem.eql(u8, inst, "loop")) {
            try cg.addTag(.loop);
        } else if (mem.eql(u8, inst, "end")) {
            try cg.addTag(.end);
        } else if (mem.eql(u8, inst, "br")) {
            const label = try parseLabel(cg, inst, &word_it);
            try cg.addLabel(.br, label);
        } else if (mem.eql(u8, inst, "br_if")) {
            const label = try parseLabel(cg, inst, &word_it);
            try cg.addLabel(.br_if, label);
        } else if (mem.eql(u8, inst, "return")) {
            try cg.addTag(.@"return");
        } else if (mem.eql(u8, inst, "call")) {
            const nav_index = try parseCallArg(cg, inst, &word_it, operand_map);
            try cg.addInst(.{ .tag = .call_nav, .data = .{ .nav_index = nav_index } });
        } else if (mem.eql(u8, inst, "drop")) {
            try cg.addTag(.drop);
        } else if (mem.eql(u8, inst, "select")) {
            try cg.addTag(.select);
        } else if (mem.eql(u8, inst, "local.get")) {
            const local = try parseLocalArg(cg, inst, &word_it, operand_map);
            try cg.addLocal(.local_get, local);
        } else if (mem.eql(u8, inst, "local.set")) {
            const local = try parseLocalArg(cg, inst, &word_it, operand_map);
            try cg.addLocal(.local_set, local);
        } else if (mem.eql(u8, inst, "local.tee")) {
            const local = try parseLocalArg(cg, inst, &word_it, operand_map);
            try cg.addLocal(.local_tee, local);
        } else if (mem.eql(u8, inst, "global.get")) {
            const global_str = try parseGlobalArg(cg, inst, &word_it);
            try cg.addInst(.{ .tag = .global_get, .data = .{ .str = global_str } });
        } else if (mem.eql(u8, inst, "global.set")) {
            const global_str = try parseGlobalArg(cg, inst, &word_it);
            try cg.addInst(.{ .tag = .global_set, .data = .{ .str = global_str } });
        } else if (mem.eql(u8, inst, "i32.load")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i32_load, mem_arg);
        } else if (mem.eql(u8, inst, "i64.load")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_load, mem_arg);
        } else if (mem.eql(u8, inst, "f32.load")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.f32_load, mem_arg);
        } else if (mem.eql(u8, inst, "f64.load")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.f64_load, mem_arg);
        } else if (mem.eql(u8, inst, "i32.load8_s")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i32_load8_s, mem_arg);
        } else if (mem.eql(u8, inst, "i32.load8_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i32_load8_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.load16_s")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i32_load16_s, mem_arg);
        } else if (mem.eql(u8, inst, "i32.load16_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i32_load16_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.load8_s")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_load8_s, mem_arg);
        } else if (mem.eql(u8, inst, "i64.load8_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_load8_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.load16_s")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_load16_s, mem_arg);
        } else if (mem.eql(u8, inst, "i64.load16_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_load16_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.load32_s")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_load32_s, mem_arg);
        } else if (mem.eql(u8, inst, "i64.load32_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_load32_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.store")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i32_store, mem_arg);
        } else if (mem.eql(u8, inst, "i64.store")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_store, mem_arg);
        } else if (mem.eql(u8, inst, "f32.store")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.f32_store, mem_arg);
        } else if (mem.eql(u8, inst, "f64.store")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.f64_store, mem_arg);
        } else if (mem.eql(u8, inst, "i32.store8")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i32_store8, mem_arg);
        } else if (mem.eql(u8, inst, "i32.store16")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i32_store16, mem_arg);
        } else if (mem.eql(u8, inst, "i64.store8")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_store8, mem_arg);
        } else if (mem.eql(u8, inst, "i64.store16")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_store16, mem_arg);
        } else if (mem.eql(u8, inst, "i64.store32")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_store32, mem_arg);
        } else if (mem.eql(u8, inst, "memory.size")) {
            try cg.addLabel(.memory_size, 0);
        } else if (mem.eql(u8, inst, "memory.grow")) {
            try cg.addLabel(.memory_grow, 0);
        } else if (mem.eql(u8, inst, "i32.const")) {
            const value = try parseInt(i32, cg, inst, &word_it);
            try cg.addImm32(@bitCast(value));
        } else if (mem.eql(u8, inst, "i64.const")) {
            const value = try parseInt(i64, cg, inst, &word_it);
            try cg.addImm64(@bitCast(value));
        } else if (mem.eql(u8, inst, "f32.const")) {
            const value = try parseFloat(f32, cg, inst, &word_it);
            try cg.addFloat32(value);
        } else if (mem.eql(u8, inst, "f64.const")) {
            const value = try parseFloat(f64, cg, inst, &word_it);
            try cg.addFloat64(value);
        } else if (mem.eql(u8, inst, "i32.eqz")) {
            try cg.addTag(.i32_eqz);
        } else if (mem.eql(u8, inst, "i32.eq")) {
            try cg.addTag(.i32_eq);
        } else if (mem.eql(u8, inst, "i32.ne")) {
            try cg.addTag(.i32_ne);
        } else if (mem.eql(u8, inst, "i32.lt_s")) {
            try cg.addTag(.i32_lt_s);
        } else if (mem.eql(u8, inst, "i32.lt_u")) {
            try cg.addTag(.i32_lt_u);
        } else if (mem.eql(u8, inst, "i32.gt_s")) {
            try cg.addTag(.i32_gt_s);
        } else if (mem.eql(u8, inst, "i32.gt_u")) {
            try cg.addTag(.i32_gt_u);
        } else if (mem.eql(u8, inst, "i32.le_s")) {
            try cg.addTag(.i32_le_s);
        } else if (mem.eql(u8, inst, "i32.le_u")) {
            try cg.addTag(.i32_le_u);
        } else if (mem.eql(u8, inst, "i32.ge_s")) {
            try cg.addTag(.i32_ge_s);
        } else if (mem.eql(u8, inst, "i32.ge_u")) {
            try cg.addTag(.i32_ge_u);
        } else if (mem.eql(u8, inst, "i64.eqz")) {
            try cg.addTag(.i64_eqz);
        } else if (mem.eql(u8, inst, "i64.eq")) {
            try cg.addTag(.i64_eq);
        } else if (mem.eql(u8, inst, "i64.ne")) {
            try cg.addTag(.i64_ne);
        } else if (mem.eql(u8, inst, "i64.lt_s")) {
            try cg.addTag(.i64_lt_s);
        } else if (mem.eql(u8, inst, "i64.lt_u")) {
            try cg.addTag(.i64_lt_u);
        } else if (mem.eql(u8, inst, "i64.gt_s")) {
            try cg.addTag(.i64_gt_s);
        } else if (mem.eql(u8, inst, "i64.gt_u")) {
            try cg.addTag(.i64_gt_u);
        } else if (mem.eql(u8, inst, "i64.le_s")) {
            try cg.addTag(.i64_le_s);
        } else if (mem.eql(u8, inst, "i64.le_u")) {
            try cg.addTag(.i64_le_u);
        } else if (mem.eql(u8, inst, "i64.ge_s")) {
            try cg.addTag(.i64_ge_s);
        } else if (mem.eql(u8, inst, "i64.ge_u")) {
            try cg.addTag(.i64_ge_u);
        } else if (mem.eql(u8, inst, "f32.eq")) {
            try cg.addTag(.f32_eq);
        } else if (mem.eql(u8, inst, "f32.ne")) {
            try cg.addTag(.f32_ne);
        } else if (mem.eql(u8, inst, "f32.lt")) {
            try cg.addTag(.f32_lt);
        } else if (mem.eql(u8, inst, "f32.gt")) {
            try cg.addTag(.f32_gt);
        } else if (mem.eql(u8, inst, "f32.le")) {
            try cg.addTag(.f32_le);
        } else if (mem.eql(u8, inst, "f32.ge")) {
            try cg.addTag(.f32_ge);
        } else if (mem.eql(u8, inst, "f64.eq")) {
            try cg.addTag(.f64_eq);
        } else if (mem.eql(u8, inst, "f64.ne")) {
            try cg.addTag(.f64_ne);
        } else if (mem.eql(u8, inst, "f64.lt")) {
            try cg.addTag(.f64_lt);
        } else if (mem.eql(u8, inst, "f64.gt")) {
            try cg.addTag(.f64_gt);
        } else if (mem.eql(u8, inst, "f64.le")) {
            try cg.addTag(.f64_le);
        } else if (mem.eql(u8, inst, "f64.ge")) {
            try cg.addTag(.f64_ge);
        } else if (mem.eql(u8, inst, "i32.clz")) {
            try cg.addTag(.i32_clz);
        } else if (mem.eql(u8, inst, "i32.ctz")) {
            try cg.addTag(.i32_ctz);
        } else if (mem.eql(u8, inst, "i32.popcnt")) {
            try cg.addTag(.i32_popcnt);
        } else if (mem.eql(u8, inst, "i32.add")) {
            try cg.addTag(.i32_add);
        } else if (mem.eql(u8, inst, "i32.sub")) {
            try cg.addTag(.i32_sub);
        } else if (mem.eql(u8, inst, "i32.mul")) {
            try cg.addTag(.i32_mul);
        } else if (mem.eql(u8, inst, "i32.div_s")) {
            try cg.addTag(.i32_div_s);
        } else if (mem.eql(u8, inst, "i32.div_u")) {
            try cg.addTag(.i32_div_u);
        } else if (mem.eql(u8, inst, "i32.rem_s")) {
            try cg.addTag(.i32_rem_s);
        } else if (mem.eql(u8, inst, "i32.rem_u")) {
            try cg.addTag(.i32_rem_u);
        } else if (mem.eql(u8, inst, "i32.and")) {
            try cg.addTag(.i32_and);
        } else if (mem.eql(u8, inst, "i32.or")) {
            try cg.addTag(.i32_or);
        } else if (mem.eql(u8, inst, "i32.xor")) {
            try cg.addTag(.i32_xor);
        } else if (mem.eql(u8, inst, "i32.shl")) {
            try cg.addTag(.i32_shl);
        } else if (mem.eql(u8, inst, "i32.shr_s")) {
            try cg.addTag(.i32_shr_s);
        } else if (mem.eql(u8, inst, "i32.shr_u")) {
            try cg.addTag(.i32_shr_u);
        } else if (mem.eql(u8, inst, "i64.clz")) {
            try cg.addTag(.i64_clz);
        } else if (mem.eql(u8, inst, "i64.ctz")) {
            try cg.addTag(.i64_ctz);
        } else if (mem.eql(u8, inst, "i64.popcnt")) {
            try cg.addTag(.i64_popcnt);
        } else if (mem.eql(u8, inst, "i64.add")) {
            try cg.addTag(.i64_add);
        } else if (mem.eql(u8, inst, "i64.sub")) {
            try cg.addTag(.i64_sub);
        } else if (mem.eql(u8, inst, "i64.mul")) {
            try cg.addTag(.i64_mul);
        } else if (mem.eql(u8, inst, "i64.div_s")) {
            try cg.addTag(.i64_div_s);
        } else if (mem.eql(u8, inst, "i64.div_u")) {
            try cg.addTag(.i64_div_u);
        } else if (mem.eql(u8, inst, "i64.rem_s")) {
            try cg.addTag(.i64_rem_s);
        } else if (mem.eql(u8, inst, "i64.rem_u")) {
            try cg.addTag(.i64_rem_u);
        } else if (mem.eql(u8, inst, "i64.and")) {
            try cg.addTag(.i64_and);
        } else if (mem.eql(u8, inst, "i64.or")) {
            try cg.addTag(.i64_or);
        } else if (mem.eql(u8, inst, "i64.xor")) {
            try cg.addTag(.i64_xor);
        } else if (mem.eql(u8, inst, "i64.shl")) {
            try cg.addTag(.i64_shl);
        } else if (mem.eql(u8, inst, "i64.shr_s")) {
            try cg.addTag(.i64_shr_s);
        } else if (mem.eql(u8, inst, "i64.shr_u")) {
            try cg.addTag(.i64_shr_u);
        } else if (mem.eql(u8, inst, "f32.abs")) {
            try cg.addTag(.f32_abs);
        } else if (mem.eql(u8, inst, "f32.neg")) {
            try cg.addTag(.f32_neg);
        } else if (mem.eql(u8, inst, "f32.ceil")) {
            try cg.addTag(.f32_ceil);
        } else if (mem.eql(u8, inst, "f32.floor")) {
            try cg.addTag(.f32_floor);
        } else if (mem.eql(u8, inst, "f32.trunc")) {
            try cg.addTag(.f32_trunc);
        } else if (mem.eql(u8, inst, "f32.nearest")) {
            try cg.addTag(.f32_nearest);
        } else if (mem.eql(u8, inst, "f32.sqrt")) {
            try cg.addTag(.f32_sqrt);
        } else if (mem.eql(u8, inst, "f32.add")) {
            try cg.addTag(.f32_add);
        } else if (mem.eql(u8, inst, "f32.sub")) {
            try cg.addTag(.f32_sub);
        } else if (mem.eql(u8, inst, "f32.mul")) {
            try cg.addTag(.f32_mul);
        } else if (mem.eql(u8, inst, "f32.div")) {
            try cg.addTag(.f32_div);
        } else if (mem.eql(u8, inst, "f32.min")) {
            try cg.addTag(.f32_min);
        } else if (mem.eql(u8, inst, "f32.max")) {
            try cg.addTag(.f32_max);
        } else if (mem.eql(u8, inst, "f32.copysign")) {
            try cg.addTag(.f32_copysign);
        } else if (mem.eql(u8, inst, "f64.abs")) {
            try cg.addTag(.f64_abs);
        } else if (mem.eql(u8, inst, "f64.neg")) {
            try cg.addTag(.f64_neg);
        } else if (mem.eql(u8, inst, "f64.ceil")) {
            try cg.addTag(.f64_ceil);
        } else if (mem.eql(u8, inst, "f64.floor")) {
            try cg.addTag(.f64_floor);
        } else if (mem.eql(u8, inst, "f64.trunc")) {
            try cg.addTag(.f64_trunc);
        } else if (mem.eql(u8, inst, "f64.nearest")) {
            try cg.addTag(.f64_nearest);
        } else if (mem.eql(u8, inst, "f64.sqrt")) {
            try cg.addTag(.f64_sqrt);
        } else if (mem.eql(u8, inst, "f64.add")) {
            try cg.addTag(.f64_add);
        } else if (mem.eql(u8, inst, "f64.sub")) {
            try cg.addTag(.f64_sub);
        } else if (mem.eql(u8, inst, "f64.mul")) {
            try cg.addTag(.f64_mul);
        } else if (mem.eql(u8, inst, "f64.div")) {
            try cg.addTag(.f64_div);
        } else if (mem.eql(u8, inst, "f64.min")) {
            try cg.addTag(.f64_min);
        } else if (mem.eql(u8, inst, "f64.max")) {
            try cg.addTag(.f64_max);
        } else if (mem.eql(u8, inst, "f64.copysign")) {
            try cg.addTag(.f64_copysign);
        } else if (mem.eql(u8, inst, "i32.wrap_i64")) {
            try cg.addTag(.i32_wrap_i64);
        } else if (mem.eql(u8, inst, "i32.trunc_f32_s")) {
            try cg.addTag(.i32_trunc_f32_s);
        } else if (mem.eql(u8, inst, "i32.trunc_f32_u")) {
            try cg.addTag(.i32_trunc_f32_u);
        } else if (mem.eql(u8, inst, "i32.trunc_f64_s")) {
            try cg.addTag(.i32_trunc_f64_s);
        } else if (mem.eql(u8, inst, "i32.trunc_f64_u")) {
            try cg.addTag(.i32_trunc_f64_u);
        } else if (mem.eql(u8, inst, "i64.extend_i32_s")) {
            try cg.addTag(.i64_extend_i32_s);
        } else if (mem.eql(u8, inst, "i64.extend_i32_u")) {
            try cg.addTag(.i64_extend_i32_u);
        } else if (mem.eql(u8, inst, "i64.trunc_f32_s")) {
            try cg.addTag(.i64_trunc_f32_s);
        } else if (mem.eql(u8, inst, "i64.trunc_f32_u")) {
            try cg.addTag(.i64_trunc_f32_u);
        } else if (mem.eql(u8, inst, "i64.trunc_f64_s")) {
            try cg.addTag(.i64_trunc_f64_s);
        } else if (mem.eql(u8, inst, "i64.trunc_f64_u")) {
            try cg.addTag(.i64_trunc_f64_u);
        } else if (mem.eql(u8, inst, "f32.convert_i32_s")) {
            try cg.addTag(.f32_convert_i32_s);
        } else if (mem.eql(u8, inst, "f32.convert_i32_u")) {
            try cg.addTag(.f32_convert_i32_u);
        } else if (mem.eql(u8, inst, "f32.convert_i64_s")) {
            try cg.addTag(.f32_convert_i64_s);
        } else if (mem.eql(u8, inst, "f32.convert_i64_u")) {
            try cg.addTag(.f32_convert_i64_u);
        } else if (mem.eql(u8, inst, "f32.demote_f64")) {
            try cg.addTag(.f32_demote_f64);
        } else if (mem.eql(u8, inst, "f64.convert_i32_s")) {
            try cg.addTag(.f64_convert_i32_s);
        } else if (mem.eql(u8, inst, "f64.convert_i32_u")) {
            try cg.addTag(.f64_convert_i32_u);
        } else if (mem.eql(u8, inst, "f64.convert_i64_s")) {
            try cg.addTag(.f64_convert_i64_s);
        } else if (mem.eql(u8, inst, "f64.convert_i64_u")) {
            try cg.addTag(.f64_convert_i64_u);
        } else if (mem.eql(u8, inst, "f64.promote_f32")) {
            try cg.addTag(.f64_promote_f32);
        } else if (mem.eql(u8, inst, "i32.reinterpret_f32")) {
            try cg.addTag(.i32_reinterpret_f32);
        } else if (mem.eql(u8, inst, "i64.reinterpret_f64")) {
            try cg.addTag(.i64_reinterpret_f64);
        } else if (mem.eql(u8, inst, "f32.reinterpret_i32")) {
            try cg.addTag(.f32_reinterpret_i32);
        } else if (mem.eql(u8, inst, "f64.reinterpret_i64")) {
            try cg.addTag(.f64_reinterpret_i64);
        } else if (mem.eql(u8, inst, "i32.extend8_s")) {
            try cg.addTag(.i32_extend8_s);
        } else if (mem.eql(u8, inst, "i32.extend16_s")) {
            try cg.addTag(.i32_extend16_s);
        } else if (mem.eql(u8, inst, "i64.extend8_s")) {
            try cg.addTag(.i64_extend8_s);
        } else if (mem.eql(u8, inst, "i64.extend16_s")) {
            try cg.addTag(.i64_extend16_s);
        } else if (mem.eql(u8, inst, "i64.extend32_s")) {
            try cg.addTag(.i64_extend32_s);
        } else if (mem.eql(u8, inst, "i32.trunc_sat_f32_s")) {
            try cg.addExtended(.i32_trunc_sat_f32_s);
        } else if (mem.eql(u8, inst, "i32.trunc_sat_f32_u")) {
            try cg.addExtended(.i32_trunc_sat_f32_u);
        } else if (mem.eql(u8, inst, "i32.trunc_sat_f64_s")) {
            try cg.addExtended(.i32_trunc_sat_f64_s);
        } else if (mem.eql(u8, inst, "i32.trunc_sat_f64_u")) {
            try cg.addExtended(.i32_trunc_sat_f64_u);
        } else if (mem.eql(u8, inst, "i64.trunc_sat_f32_s")) {
            try cg.addExtended(.i64_trunc_sat_f32_s);
        } else if (mem.eql(u8, inst, "i64.trunc_sat_f32_u")) {
            try cg.addExtended(.i64_trunc_sat_f32_u);
        } else if (mem.eql(u8, inst, "i64.trunc_sat_f64_s")) {
            try cg.addExtended(.i64_trunc_sat_f64_s);
        } else if (mem.eql(u8, inst, "i64.trunc_sat_f64_u")) {
            try cg.addExtended(.i64_trunc_sat_f64_u);
        } else if (mem.eql(u8, inst, "memory.init")) {
            try cg.addExtended(.memory_init);
        } else if (mem.eql(u8, inst, "data.drop")) {
            try cg.addExtended(.data_drop);
        } else if (mem.eql(u8, inst, "memory.copy")) {
            const str1 = word_it.next();
            if (str1 == null or !mem.eql(u8, str1.?, "0,")) {
                return cg.fail("Self-hosted backend requires memory.copy be in form of \"memory.copy 0, 0\"", .{});
            }
            const str2 = word_it.next();
            if (str2 == null or !mem.eql(u8, str2.?, "0")) {
                return cg.fail("Self-hosted backend requires memory.copy be in form of \"memory.copy 0, 0\"", .{});
            }
            try cg.addExtended(.memory_copy);
        } else if (mem.eql(u8, inst, "memory.fill")) {
            const str = word_it.next();
            if (str == null or !mem.eql(u8, str.?, "0")) {
                return cg.fail("Self-hosted backend requires memory.fill be in form of \"memory.fill 0\"", .{});
            }
            try cg.addExtended(.memory_fill);
        } else if (mem.eql(u8, inst, "table.init")) {
            try cg.addExtended(.table_init);
        } else if (mem.eql(u8, inst, "elem.drop")) {
            try cg.addExtended(.elem_drop);
        } else if (mem.eql(u8, inst, "table.copy")) {
            try cg.addExtended(.table_copy);
        } else if (mem.eql(u8, inst, "table.grow")) {
            try cg.addExtended(.table_grow);
        } else if (mem.eql(u8, inst, "table.size")) {
            try cg.addExtended(.table_size);
        } else if (mem.eql(u8, inst, "table.fill")) {
            try cg.addExtended(.table_fill);
        } else if (mem.eql(u8, inst, "memory.atomic.notify")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.memory_atomic_notify, mem_arg);
        } else if (mem.eql(u8, inst, "memory.atomic.wait32")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.memory_atomic_wait32, mem_arg);
        } else if (mem.eql(u8, inst, "memory.atomic.wait64")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.memory_atomic_wait64, mem_arg);
        } else if (mem.eql(u8, inst, "atomic.fence")) {
            try cg.addAtomicTag(.atomic_fence);
        } else if (mem.eql(u8, inst, "i32.atomic.load")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_load, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.load")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_load, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.load8_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_load8_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.load16_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_load16_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.load8_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_load8_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.load16_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_load16_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.load32_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_load32_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.store")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_store, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.store")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_store, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.store8")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_store8, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.store16")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_store16, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.store8")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_store8, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.store16")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_store16, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.store32")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_store32, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw.add")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw_add, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw.add")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw_add, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw8.add_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw8_add_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw16.add_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw16_add_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw8.add_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw8_add_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw16.add_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw16_add_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw32.add_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw32_add_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw.sub")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw_sub, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw.sub")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw_sub, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw8.sub_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw8_sub_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw16.sub_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw16_sub_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw8.sub_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw8_sub_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw16.sub_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw16_sub_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw32.sub_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw32_sub_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw.and")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw_and, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw.and")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw_and, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw8.and_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw8_and_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw16.and_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw16_and_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw8.and_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw8_and_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw16.and_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw16_and_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw32.and_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw32_and_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw.or")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw_or, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw.or")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw_or, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw8.or_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw8_or_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw16.or_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw16_or_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw8.or_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw8_or_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw16.or_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw16_or_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw32.or_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw32_or_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw.xor")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw_xor, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw.xor")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw_xor, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw8.xor_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw8_xor_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw16.xor_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw16_xor_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw8.xor_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw8_xor_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw16.xor_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw16_xor_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw32.xor_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw32_xor_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw.xchg")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw_xchg, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw.xchg")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw_xchg, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw8.xchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw8_xchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw16.xchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw16_xchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw8.xchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw8_xchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw16.xchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw16_xchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw32.xchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw32_xchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw.cmpxchg")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw_cmpxchg, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw.cmpxchg")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw_cmpxchg, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw8.cmpxchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw8_cmpxchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw16.cmpxchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw16_cmpxchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw8.cmpxchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw8_cmpxchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw16.cmpxchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw16_cmpxchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw32.cmpxchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw32_cmpxchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "cont.new")) {
            const type_idx = try parseLabel(cg, inst, &word_it);
            try cg.addLabel(.cont_new, type_idx);
        } else if (mem.eql(u8, inst, "cont.bind")) {
            const pair = try parseIndexPair(cg, inst, &word_it);
            try cg.addIndexPair(.cont_bind, pair);
        } else if (mem.eql(u8, inst, "suspend")) {
            const tag_idx = try parseLabel(cg, inst, &word_it);
            try cg.addLabel(.@"suspend", tag_idx);
        } else if (mem.eql(u8, inst, "resume")) {
            const type_idx = try parseLabel(cg, inst, &word_it);
            try cg.addLabel(.@"resume", type_idx);
        } else if (mem.eql(u8, inst, "resume_throw")) {
            const pair = try parseIndexPair(cg, inst, &word_it);
            try cg.addIndexPair(.resume_throw, pair);
        } else if (mem.eql(u8, inst, "resume_throw_ref")) {
            const type_idx = try parseLabel(cg, inst, &word_it);
            try cg.addLabel(.resume_throw_ref, type_idx);
        } else if (mem.eql(u8, inst, "switch")) {
            const pair = try parseIndexPair(cg, inst, &word_it);
            try cg.addIndexPair(.@"switch", pair);
        } else {
            if (mem.startsWith(u8, inst, "#")) continue :next_line;
            if (mem.startsWith(u8, inst, "//")) continue :next_line;

            return cg.fail("Malformed assembly, unknown instruction \"{s}\"", .{inst});
        }

        const remaining = word_it.next() orelse continue :next_line;
        if (mem.startsWith(u8, remaining, "#")) continue :next_line;
        if (mem.startsWith(u8, remaining, "//")) continue :next_line;
        return cg.fail("Malformed assembly, unknown string after instruction \"{s}\"", .{remaining});
    }
}

fn parseGlobalType(
    cg: *CodeGen,
    inst: []const u8,
    word_it: *mem.TokenIterator(u8, .any),
) !void {
    const raw_name = word_it.next() orelse {
        return cg.fail("Malformed assembly, global name not found for \"{s}\"", .{inst});
    };
    if (!mem.endsWith(u8, raw_name, ",") or raw_name.len <= 1) {
        return cg.fail("Malformed assembly, expected comma after global name \"{s}\"", .{raw_name});
    }
    const raw_valtype = word_it.next() orelse {
        return cg.fail("Malformed assembly, valtype not found for \"{s}\"", .{inst});
    };
    const has_trailing_comma = mem.endsWith(u8, raw_valtype, ",");
    const valtype_str = if (has_trailing_comma) raw_valtype[0 .. raw_valtype.len - 1] else raw_valtype;
    if (!mem.eql(u8, valtype_str, "i32") and
        !mem.eql(u8, valtype_str, "i64") and
        !mem.eql(u8, valtype_str, "f32") and
        !mem.eql(u8, valtype_str, "f64"))
    {
        return cg.fail("Malformed assembly, unknown global valtype \"{s}\"", .{valtype_str});
    }
    if (has_trailing_comma) {
        const mut_str = word_it.next() orelse {
            return cg.fail("Malformed assembly, expected \"immutable\" after comma in \"{s}\"", .{inst});
        };
        if (!mem.eql(u8, mut_str, "immutable")) {
            return cg.fail("Malformed assembly, unknown global qualifier \"{s}\"", .{mut_str});
        }
    }
}

fn parseGlobalArg(
    cg: *CodeGen,
    inst: []const u8,
    word_it: *mem.TokenIterator(u8, .any),
) !InternPool.NullTerminatedString {
    const name = word_it.next() orelse {
        return cg.fail("Malformed assembly, argument not found for \"{s}\"", .{inst});
    };
    const zcu = cg.pt.zcu;
    return zcu.intern_pool.getOrPutString(cg.gpa, zcu.comp.io, cg.pt.tid, name, .no_embedded_nulls);
}

fn parseCallArg(
    cg: *CodeGen,
    inst: []const u8,
    word_it: *mem.TokenIterator(u8, .any),
    operand_map: *const OperandMap,
) !InternPool.Nav.Index {
    const arg = word_it.next() orelse {
        return cg.fail("Malformed assembly, argument not found for \"{s}\"", .{inst});
    };
    if (arg.len >= 3 and arg[0] == '%' and arg[1] == '[' and arg[arg.len - 1] == ']') {
        const name = arg[2 .. arg.len - 1];
        const op = operand_map.get(name) orelse {
            return cg.fail("Malformed assembly, unknown name \"{s}\"", .{name});
        };
        return switch (op) {
            .func_nav => |nav| nav,
            else => cg.fail("Malformed assembly, operand \"{s}\" is not a function", .{name}),
        };
    }
    return cg.fail("Malformed assembly, malformed call target \"{s}\"", .{arg});
}

fn parseLocalArg(
    cg: *CodeGen,
    inst: []const u8,
    word_it: *mem.TokenIterator(u8, .any),
    operand_map: *const OperandMap,
) !u32 {
    const arg = word_it.next() orelse {
        return cg.fail("Malformed assembly, argument not found for \"{s}\"", .{inst});
    };
    if (arg.len < 3 or arg[0] != '%' or arg[1] != '[' or arg[arg.len - 1] != ']') {
        const local = std.fmt.parseInt(u32, arg, 0) catch {
            return cg.fail("Malformed assembly, malformed argument \"{s}\"", .{arg});
        };
        return local;
    }
    const name = arg[2 .. arg.len - 1];
    const op = operand_map.get(name) orelse {
        return cg.fail("Malformed assembly, unknown name \"{s}\"", .{name});
    };
    return switch (op) {
        .local => |local| local,
        else => cg.fail("Malformed assembly, operand \"{s}\" is not a local", .{name}),
    };
}

fn parseLabel(cg: *CodeGen, inst: []const u8, word_it: *mem.TokenIterator(u8, .any)) !u32 {
    const label_str = word_it.next() orelse {
        return cg.fail("Malformed assembly, label not found for \"{s}\"", .{inst});
    };
    return (try parseImmOrInt(u32, cg, label_str)) orelse {
        return cg.fail("Malformed assembly, malformed label \"{s}\"", .{label_str});
    };
}

fn parseIndexPair(cg: *CodeGen, inst: []const u8, word_it: *mem.TokenIterator(u8, .any)) !Mir.IndexPair {
    const raw_first = word_it.next() orelse {
        return cg.fail("Malformed assembly, index not found for \"{s}\"", .{inst});
    };
    const first_str = if (mem.endsWith(u8, raw_first, ",")) raw_first[0 .. raw_first.len - 1] else raw_first;
    const first = (try parseImmOrInt(u32, cg, first_str)) orelse {
        return cg.fail("Malformed assembly, malformed index \"{s}\"", .{first_str});
    };
    const raw_second = word_it.next() orelse {
        return cg.fail("Malformed assembly, second index not found for \"{s}\"", .{inst});
    };
    const second = (try parseImmOrInt(u32, cg, raw_second)) orelse {
        return cg.fail("Malformed assembly, malformed index \"{s}\"", .{raw_second});
    };
    return .{ .first = first, .second = second };
}

fn parseImmOrInt(comptime T: type, cg: *CodeGen, arg: []const u8) !?T {
    if (arg.len >= 3 and arg[0] == '%' and arg[1] == '[' and arg[arg.len - 1] == ']') {
        const name = arg[2 .. arg.len - 1];
        const op = cg.asm_operands.?.get(name) orelse {
            return cg.fail("Malformed assembly, unknown name \"{s}\"", .{name});
        };
        return switch (op) {
            .imm => |imm| std.math.cast(T, imm),
            else => cg.fail("Malformed assembly, operand \"{s}\" is not an immediate", .{name}),
        };
    }
    return std.fmt.parseInt(T, arg, 0) catch null;
}

fn parseMemArg(cg: *CodeGen, inst: []const u8, word_it: *mem.TokenIterator(u8, .any)) !Mir.MemArg {
    const mem_arg_str = word_it.next() orelse {
        return cg.fail("Malformed assembly, memory argument not found for \"{s}\"", .{inst});
    };
    if (mem.cut(u8, mem_arg_str, ":p2align=")) |oa| {
        const offset_str = oa[0];
        const alignment_str = oa[1];

        const offset = (try parseImmOrInt(i64, cg, offset_str)) orelse {
            return cg.fail("Malformed assembly, malformed offset \"{s}\"", .{offset_str});
        };
        const alignment_p2 = (try parseImmOrInt(u5, cg, alignment_str)) orelse {
            return cg.fail("Malformed assembly, malformed offset \"{s}\"", .{alignment_str});
        };

        return .{ .offset = @bitCast(offset), .alignment = .fromLog2Units(alignment_p2) };
    } else {
        const offset_str = mem_arg_str;
        const offset = (try parseImmOrInt(i64, cg, offset_str)) orelse {
            return cg.fail("Malformed assembly, malformed offset \"{s}\"", .{offset_str});
        };
        return .{ .offset = @bitCast(offset), .alignment = defaultAlignment(inst) };
    }
}

fn defaultAlignment(inst: []const u8) InternPool.Alignment {
    if (mem.indexOf(u8, inst, "8") != null) return .@"1";
    if (mem.indexOf(u8, inst, "16") != null) return .@"2";
    if (mem.indexOf(u8, inst, "32") != null or
        mem.startsWith(u8, inst, "i32.") or
        mem.startsWith(u8, inst, "f32.") or
        mem.eql(u8, inst, "memory.atomic.notify"))
    {
        return .@"4";
    }
    if (mem.indexOf(u8, inst, "64") != null or
        mem.startsWith(u8, inst, "i64.") or
        mem.startsWith(u8, inst, "f64."))
    {
        return .@"8";
    }
    return .@"1";
}

fn parseInt(comptime T: type, cg: *CodeGen, inst: []const u8, word_it: *mem.TokenIterator(u8, .any)) !T {
    const value_str = word_it.next() orelse {
        return cg.fail("Malformed assembly, value not found for \"{s}\"", .{inst});
    };
    return (try parseImmOrInt(T, cg, value_str)) orelse {
        return cg.fail("Malformed assembly, malformed integer value \"{s}\"", .{value_str});
    };
}

fn parseFloat(comptime T: type, cg: *CodeGen, inst: []const u8, word_it: *mem.TokenIterator(u8, .any)) !T {
    const value_str = word_it.next() orelse {
        return cg.fail("Malformed assembly, value not found for \"{s}\"", .{inst});
    };
    const value = std.fmt.parseFloat(T, value_str) catch {
        return cg.fail("Malformed assembly, malformed float value \"{s}\"", .{value_str});
    };
    return value;
}
