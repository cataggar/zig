pt: Zcu.PerThread,
target: *const std.Target,
air: Air,
nav_index: InternPool.Nav.Index,

// Blocks
def_order: std.array_hash_map.Auto(Air.Inst.Index, void),
blocks: std.array_hash_map.Auto(Air.Inst.Index, Block),
loops: std.array_hash_map.Auto(Air.Inst.Index, Loop),
active_loops: std.ArrayList(Loop.Index),
loop_live: struct {
    set: std.array_hash_map.Auto(struct { Loop.Index, Air.Inst.Index }, void),
    list: std.ArrayList(Air.Inst.Index),
},
dom_start: u32,
dom_len: u32,
dom: std.ArrayList(DomInt),

// Wip Mir
saved_registers: std.enums.EnumSet(Register.Alias),
instructions: std.ArrayList(codegen.aarch64.encoding.Instruction),
literals: std.ArrayList(u32),
nav_relocs: std.ArrayList(codegen.aarch64.Mir.Reloc.Nav),
uav_relocs: std.ArrayList(codegen.aarch64.Mir.Reloc.Uav),
lazy_relocs: std.ArrayList(codegen.aarch64.Mir.Reloc.Lazy),
global_relocs: std.ArrayList(codegen.aarch64.Mir.Reloc.Global),
literal_relocs: std.ArrayList(codegen.aarch64.Mir.Reloc.Literal),

// Stack Frame
returns: bool,
va_list: union(enum) {
    other: Value.Indirect,
    sysv: struct {
        __stack: Value.Indirect,
        __gr_top: Value.Indirect,
        __vr_top: Value.Indirect,
        __gr_offs: i32,
        __vr_offs: i32,
    },
},
stack_size: u24,
stack_align: InternPool.Alignment,

// Value Tracking
live_registers: LiveRegisters,
live_values: std.AutoHashMapUnmanaged(Air.Inst.Index, Value.Index),
values: std.ArrayList(Value),

pub const LiveRegisters = std.enums.EnumArray(Register.Alias, Value.Index);

pub const Block = struct {
    live_registers: LiveRegisters,
    target_label: u32,

    pub const main: Air.Inst.Index = @fromBackingInt(@intCast(
        std.math.maxInt(@typeInfo(Air.Inst.Index).@"enum".tag_type),
    ));

    fn branch(target_block: *const Block, isel: *Select) !void {
        if (isel.instructions.items.len > target_block.target_label) {
            try isel.emit(.b(@intCast((isel.instructions.items.len + 1 - target_block.target_label) << 2)));
        }
        try isel.merge(&target_block.live_registers, .{});
    }
};

pub const Loop = struct {
    def_order: u32,
    dom: u32,
    depth: u32,
    live: u32,
    live_registers: LiveRegisters,
    repeat_list: u32,
    dispatch_slot_offset: u24 = 0,

    pub const invalid: Air.Inst.Index = @fromBackingInt(@intCast(
        std.math.maxInt(@typeInfo(Air.Inst.Index).@"enum".tag_type),
    ));

    pub const Index = enum(u32) {
        _,

        fn inst(li: Loop.Index, isel: *Select) Air.Inst.Index {
            return isel.loops.keys()[@backingInt(li)];
        }

        fn get(li: Loop.Index, isel: *Select) *Loop {
            return &isel.loops.values()[@backingInt(li)];
        }
    };

    pub const empty_list: u32 = std.math.maxInt(u32);

    fn branch(target_loop: *Loop, isel: *Select) !void {
        try isel.instructions.ensureUnusedCapacity(isel.pt.zcu.gpa, 1);
        const repeat_list_tail = target_loop.repeat_list;
        target_loop.repeat_list = @intCast(isel.instructions.items.len);
        isel.instructions.appendAssumeCapacity(@bitCast(repeat_list_tail));
        try isel.merge(&target_loop.live_registers, .{});
    }
};

pub fn deinit(isel: *Select) void {
    const gpa = isel.pt.zcu.gpa;

    isel.def_order.deinit(gpa);
    isel.blocks.deinit(gpa);
    isel.loops.deinit(gpa);
    isel.active_loops.deinit(gpa);
    isel.loop_live.set.deinit(gpa);
    isel.loop_live.list.deinit(gpa);
    isel.dom.deinit(gpa);

    isel.instructions.deinit(gpa);
    isel.literals.deinit(gpa);
    isel.nav_relocs.deinit(gpa);
    isel.uav_relocs.deinit(gpa);
    isel.lazy_relocs.deinit(gpa);
    isel.global_relocs.deinit(gpa);
    isel.literal_relocs.deinit(gpa);

    isel.live_values.deinit(gpa);
    isel.values.deinit(gpa);

    isel.* = undefined;
}

pub fn analyze(isel: *Select, air_body: []const Air.Inst.Index) !void {
    const zcu = isel.pt.zcu;
    const ip = &zcu.intern_pool;
    const gpa = zcu.gpa;
    const air_tags = isel.air.instructions.items(.tag);
    const air_data = isel.air.instructions.items(.data);
    var air_body_index: usize = 0;
    var air_inst_index = air_body[air_body_index];
    const initial_def_order_len = isel.def_order.count();
    air_tag: switch (air_tags[@backingInt(air_inst_index)]) {
        // No "scalarize" legalizations are enabled, so these instructions never appear.
        .legalize_vec_elem_val => unreachable,
        .legalize_vec_store_elem => unreachable,
        // No soft float legalizations are enabled.
        .legalize_compiler_rt_call => unreachable,

        .arg,
        .ret_addr,
        .frame_addr,
        .err_return_trace,
        .save_err_return_trace_index,
        .runtime_nav_ptr,
        .c_va_start,
        => {
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .add,
        .add_safe,
        .add_optimized,
        .add_wrap,
        .add_sat,
        .sub,
        .sub_safe,
        .sub_optimized,
        .sub_wrap,
        .sub_sat,
        .mul,
        .mul_safe,
        .mul_optimized,
        .mul_wrap,
        .mul_sat,
        .div_float,
        .div_float_optimized,
        .div_trunc,
        .div_trunc_optimized,
        .div_floor,
        .div_floor_optimized,
        .div_ceil,
        .div_ceil_optimized,
        .div_exact,
        .div_exact_optimized,
        .rem,
        .rem_optimized,
        .mod,
        .mod_optimized,
        .max,
        .min,
        .bit_and,
        .bit_or,
        .shr,
        .shr_exact,
        .shl,
        .shl_exact,
        .shl_sat,
        .xor,
        .cmp_lt,
        .cmp_lt_optimized,
        .cmp_lte,
        .cmp_lte_optimized,
        .cmp_eq,
        .cmp_eq_optimized,
        .cmp_gte,
        .cmp_gte_optimized,
        .cmp_gt,
        .cmp_gt_optimized,
        .cmp_neq,
        .cmp_neq_optimized,
        .array_elem_val,
        .slice_elem_val,
        .ptr_elem_val,
        => {
            const bin_op = air_data[@backingInt(air_inst_index)].bin_op;

            try isel.analyzeUse(bin_op.lhs);
            try isel.analyzeUse(bin_op.rhs);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .ptr_add,
        .ptr_sub,
        .add_with_overflow,
        .sub_with_overflow,
        .mul_with_overflow,
        .shl_with_overflow,
        .slice,
        .slice_elem_ptr,
        .ptr_elem_ptr,
        => {
            const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
            const bin_op = isel.air.extraData(Air.Bin, ty_pl.payload).data;

            try isel.analyzeUse(bin_op.lhs);
            try isel.analyzeUse(bin_op.rhs);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .alloc => {
            const ty = air_data[@backingInt(air_inst_index)].ty;

            isel.stack_align = isel.stack_align.maxStrict(ty.ptrAlignment(zcu));
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .inferred_alloc,
        .inferred_alloc_comptime,
        .wasm_memory_size,
        .wasm_memory_grow,
        .work_item_id,
        .work_group_size,
        .work_group_id,
        .spirv_runtime_array_len,
        .array_to_vector,
        => unreachable,
        .ret_ptr => {
            const ty = air_data[@backingInt(air_inst_index)].ty;

            if (isel.live_values.get(Block.main)) |ret_vi| switch (ret_vi.parent(isel)) {
                .unallocated, .stack_slot => isel.stack_align = isel.stack_align.maxStrict(ty.ptrAlignment(zcu)),
                .value, .constant => unreachable,
                .address => |address_vi| try isel.live_values.putNoClobber(gpa, air_inst_index, address_vi.ref(isel)),
            };
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .assembly => {
            const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
            const unwrapped_asm = isel.air.unwrapAsm(air_inst_index);

            for (unwrapped_asm.outputs) |operand| if (operand != .none) try isel.analyzeUse(operand);
            for (unwrapped_asm.inputs) |operand| if (operand != .none) try isel.analyzeUse(operand);
            if (ty_pl.ty.ip_index != .void_type) try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .not,
        .clz,
        .ctz,
        .popcount,
        .byte_swap,
        .bit_reverse,
        .abs,
        .load,
        .fptrunc,
        .fpext,
        .int_cast,
        .int_cast_safe,
        .trunc,
        .optional_payload,
        .optional_payload_ptr,
        .optional_payload_ptr_set,
        .wrap_optional,
        .unwrap_errunion_payload,
        .unwrap_errunion_err,
        .unwrap_errunion_payload_ptr,
        .unwrap_errunion_err_ptr,
        .errunion_payload_ptr_set,
        .wrap_errunion_payload,
        .wrap_errunion_err,
        .struct_field_ptr_index_0,
        .struct_field_ptr_index_1,
        .struct_field_ptr_index_2,
        .struct_field_ptr_index_3,
        .get_union_tag,
        .ptr_slice_len_ptr,
        .ptr_slice_ptr_ptr,
        .array_to_slice,
        .int_from_float,
        .int_from_float_optimized,
        .int_from_float_safe,
        .int_from_float_optimized_safe,
        .float_from_int,
        .splat,
        .error_set_has_value,
        .addrspace_cast,
        .c_va_arg,
        .c_va_copy,
        => {
            const ty_op = air_data[@backingInt(air_inst_index)].ty_op;

            try isel.analyzeUse(ty_op.operand);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .bit_cast,
        .ptr_cast,
        .ptr_from_int,
        .int_from_ptr,
        .error_cast,
        .error_from_int,
        .int_from_error,
        .union_from_enum,
        => {
            const ty_op = air_data[@backingInt(air_inst_index)].ty_op;
            maybe_noop: {
                if (ty_op.ty.ip_index != isel.air.typeOf(ty_op.operand, ip).toIntern()) break :maybe_noop;
                if (true) break :maybe_noop;
                if (ty_op.operand.toIndex()) |src_air_inst_index| {
                    if (isel.hints.get(src_air_inst_index)) |hint_vpsi| {
                        try isel.hints.putNoClobber(gpa, air_inst_index, hint_vpsi);
                    }
                }
            }
            try isel.analyzeUse(ty_op.operand);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .bit_cast_safe => unreachable, // legalized
        inline .block, .dbg_inline_block => |air_tag| {
            const air_body_block = switch (air_tag) {
                else => comptime unreachable,
                .block => isel.air.unwrapBlock(air_inst_index),
                .dbg_inline_block => isel.air.unwrapDbgBlock(air_inst_index),
            };

            const result_ty = air_body_block.ty.toIntern();

            if (result_ty == .noreturn_type) {
                try isel.analyze(air_body_block.body);

                air_body_index += 1;
                break :air_tag;
            }

            assert(!(try isel.blocks.getOrPut(gpa, air_inst_index)).found_existing);
            try isel.analyze(air_body_block.body);
            const block_entry = isel.blocks.pop().?;
            assert(block_entry.key == air_inst_index);

            if (result_ty != .void_type) try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .loop => {
            const air_body_block = isel.air.unwrapBlock(air_inst_index);

            const initial_dom_start = isel.dom_start;
            const initial_dom_len = isel.dom_len;
            isel.dom_start = @intCast(isel.dom.items.len);
            isel.dom_len = @intCast(isel.blocks.count());
            try isel.active_loops.append(gpa, @fromBackingInt(@intCast(isel.loops.count())));
            try isel.loops.putNoClobber(gpa, air_inst_index, .{
                .def_order = @intCast(isel.def_order.count()),
                .dom = isel.dom_start,
                .depth = isel.dom_len,
                .live = 0,
                .live_registers = undefined,
                .repeat_list = undefined,
            });
            try isel.dom.appendNTimes(gpa, 0, @divCeil(isel.dom_len, @bitSizeOf(DomInt)));
            try isel.analyze(air_body_block.body);
            for (
                isel.dom.items[initial_dom_start..].ptr,
                isel.dom.items[isel.dom_start..][0..@divCeil(initial_dom_len, @bitSizeOf(DomInt))],
            ) |*initial_dom, loop_dom| initial_dom.* |= loop_dom;
            isel.dom_start = initial_dom_start;
            isel.dom_len = initial_dom_len;
            assert(isel.active_loops.pop().?.inst(isel) == air_inst_index);

            air_body_index += 1;
        },
        .repeat, .trap, .unreach => air_body_index += 1,
        .br => {
            const br = air_data[@backingInt(air_inst_index)].br;
            const block_index = isel.blocks.getIndex(br.block_inst).?;
            if (block_index < isel.dom_len) isel.dom.items[isel.dom_start + block_index / @bitSizeOf(DomInt)] |= @as(DomInt, 1) << @truncate(block_index);
            try isel.analyzeUse(br.operand);

            air_body_index += 1;
        },
        .breakpoint, .dbg_stmt, .dbg_empty_stmt, .dbg_var_ptr, .dbg_var_val, .dbg_arg_inline, .c_va_end => {
            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .call,
        .call_always_tail,
        .call_never_tail,
        .call_never_inline,
        => {
            const air_call = isel.air.unwrapCall(air_inst_index);
            const args = air_call.args;
            isel.saved_registers.insert(.lr);
            const callee_ty = isel.air.typeOf(air_call.callee, ip);
            const func_info = switch (ip.indexToKey(callee_ty.toIntern())) {
                else => unreachable,
                .func_type => |func_type| func_type,
                .ptr_type => |ptr_type| ip.indexToKey(ptr_type.child).func_type,
            };

            try isel.analyzeUse(air_call.callee);
            var param_it: CallAbiIterator = .init;
            for (args, 0..) |arg, arg_index| {
                const restore_values_len = isel.values.items.len;
                defer isel.values.shrinkRetainingCapacity(restore_values_len);
                const param_vi = param_vi: {
                    const param_ty = isel.air.typeOf(arg, ip);
                    if (arg_index >= func_info.param_types.len) {
                        assert(func_info.is_var_args);
                        switch (isel.va_list) {
                            .other => break :param_vi try param_it.nonSysvVarArg(isel, param_ty),
                            .sysv => {},
                        }
                    }
                    break :param_vi try param_it.param(isel, param_ty);
                } orelse continue;
                defer param_vi.deref(isel);
                const passed_vi = switch (param_vi.parent(isel)) {
                    .unallocated, .stack_slot => param_vi,
                    .value, .constant => unreachable,
                    .address => |address_vi| address_vi,
                };
                switch (passed_vi.parent(isel)) {
                    .unallocated => {},
                    .stack_slot => |stack_slot| {
                        assert(stack_slot.base == .sp);
                        isel.stack_size = @max(
                            isel.stack_size,
                            stack_slot.offset + @as(u24, @intCast(passed_vi.size(isel))),
                        );
                    },
                    .value, .constant, .address => unreachable,
                }

                try isel.analyzeUse(arg);
            }

            var ret_it: CallAbiIterator = .init;
            if (try ret_it.ret(isel, isel.air.typeOfIndex(air_inst_index, ip))) |ret_vi| {
                tracking_log.debug("${d} <- %{d}", .{ @backingInt(ret_vi), @backingInt(air_inst_index) });
                switch (ret_vi.parent(isel)) {
                    .unallocated, .stack_slot => {},
                    .value, .constant => unreachable,
                    .address => |address_vi| {
                        defer address_vi.deref(isel);
                        const ret_value = ret_vi.get(isel);
                        ret_value.flags.parent_tag = .unallocated;
                        ret_value.parent_payload = .{ .unallocated = {} };
                    },
                }
                try isel.live_values.putNoClobber(gpa, air_inst_index, ret_vi);

                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            }

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .sqrt,
        .sin,
        .cos,
        .tan,
        .exp,
        .exp2,
        .log,
        .log2,
        .log10,
        .floor,
        .ceil,
        .round,
        .trunc_float,
        .neg,
        .neg_optimized,
        .is_null,
        .is_non_null,
        .is_null_ptr,
        .is_non_null_ptr,
        .is_err,
        .is_non_err,
        .is_err_ptr,
        .is_non_err_ptr,
        .is_named_enum_value,
        .tag_name,
        .error_name,
        .cmp_lte_errors_len,
        => {
            const un_op = air_data[@backingInt(air_inst_index)].un_op;

            try isel.analyzeUse(un_op);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .cmp_vector, .cmp_vector_optimized => {
            const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
            const extra = isel.air.extraData(Air.VectorCmp, ty_pl.payload).data;

            try isel.analyzeUse(extra.lhs);
            try isel.analyzeUse(extra.rhs);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .cond_br => {
            const cond_br = isel.air.unwrapCondBr(air_inst_index);

            try isel.analyzeUse(cond_br.condition);

            try isel.analyze(cond_br.then_body);
            try isel.analyze(cond_br.else_body);

            air_body_index += 1;
        },
        .switch_br => {
            const switch_br = isel.air.unwrapSwitch(air_inst_index);

            try isel.analyzeUse(switch_br.operand);

            var cases_it = switch_br.iterateCases();
            while (cases_it.next()) |case| try isel.analyze(case.body);
            if (switch_br.else_body_len > 0) try isel.analyze(cases_it.elseBody());

            air_body_index += 1;
        },
        .loop_switch_br => {
            const switch_br = isel.air.unwrapSwitch(air_inst_index);

            try isel.analyzeUse(switch_br.operand);

            const initial_dom_start = isel.dom_start;
            const initial_dom_len = isel.dom_len;
            isel.dom_start = @intCast(isel.dom.items.len);
            isel.dom_len = @intCast(isel.blocks.count());
            try isel.active_loops.append(gpa, @fromBackingInt(@intCast(isel.loops.count())));
            try isel.loops.putNoClobber(gpa, air_inst_index, .{
                .def_order = @intCast(isel.def_order.count()),
                .dom = isel.dom_start,
                .depth = isel.dom_len,
                .live = 0,
                .live_registers = undefined,
                .repeat_list = undefined,
            });
            try isel.dom.appendNTimes(gpa, 0, @divCeil(isel.dom_len, @bitSizeOf(DomInt)));

            var cases_it = switch_br.iterateCases();
            while (cases_it.next()) |case| try isel.analyze(case.body);
            if (switch_br.else_body_len > 0) try isel.analyze(cases_it.elseBody());

            for (
                isel.dom.items[initial_dom_start..].ptr,
                isel.dom.items[isel.dom_start..][0..@divCeil(initial_dom_len, @bitSizeOf(DomInt))],
            ) |*initial_dom, loop_dom| initial_dom.* |= loop_dom;
            isel.dom_start = initial_dom_start;
            isel.dom_len = initial_dom_len;
            assert(isel.active_loops.pop().?.inst(isel) == air_inst_index);

            air_body_index += 1;
        },
        .switch_dispatch => {
            const br = air_data[@backingInt(air_inst_index)].br;

            try isel.analyzeUse(br.operand);

            air_body_index += 1;
        },
        .@"try", .try_cold => {
            const unwrapped_try = isel.air.unwrapTry(air_inst_index);

            try isel.analyzeUse(unwrapped_try.error_union);
            try isel.analyze(unwrapped_try.else_body);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .try_ptr, .try_ptr_cold => {
            const unwrapped_try = isel.air.unwrapTryPtr(air_inst_index);

            try isel.analyzeUse(unwrapped_try.error_union_ptr);
            try isel.analyze(unwrapped_try.else_body);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .ret, .ret_safe, .ret_load => {
            const un_op = air_data[@backingInt(air_inst_index)].un_op;
            isel.returns = true;

            const block_index = 0;
            assert(isel.blocks.keys()[block_index] == Block.main);
            if (isel.dom_len > 0) isel.dom.items[isel.dom_start] |= 1 << block_index;

            try isel.analyzeUse(un_op);

            air_body_index += 1;
        },
        .store,
        .store_safe,
        .memset,
        .memset_safe,
        .memcpy,
        .memmove,
        .atomic_store_unordered,
        .atomic_store_monotonic,
        .atomic_store_release,
        .atomic_store_seq_cst,
        => {
            const bin_op = air_data[@backingInt(air_inst_index)].bin_op;

            try isel.analyzeUse(bin_op.lhs);
            try isel.analyzeUse(bin_op.rhs);

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .set_union_tag => {
            const bin_op = air_data[@backingInt(air_inst_index)].bin_op;
            const union_ty = isel.air.typeOf(bin_op.lhs, ip).childType(zcu);
            const union_layout = union_ty.unionGetLayout(zcu);

            if (union_layout.tag_size > 0) {
                try isel.analyzeUse(bin_op.lhs);
                try isel.analyzeUse(bin_op.rhs);
            }

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .struct_field_ptr, .agg_field_val => {
            const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
            const extra = isel.air.extraData(Air.StructField, ty_pl.payload).data;

            try isel.analyzeUse(extra.struct_operand);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .slice_len => {
            const ty_op = air_data[@backingInt(air_inst_index)].ty_op;

            try isel.analyzeUse(ty_op.operand);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            if (ty_op.operand.toIndex() != null) {
                const slice_vi = try isel.use(ty_op.operand);
                var len_part_it = slice_vi.field(isel.air.typeOf(ty_op.operand, ip), 8, 8);
                if (try len_part_it.only(isel)) |len_part_vi|
                    try isel.live_values.putNoClobber(gpa, air_inst_index, len_part_vi.ref(isel));
            }

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .slice_ptr => {
            const ty_op = air_data[@backingInt(air_inst_index)].ty_op;

            try isel.analyzeUse(ty_op.operand);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            if (ty_op.operand.toIndex() != null) {
                const slice_vi = try isel.use(ty_op.operand);
                var ptr_part_it = slice_vi.field(isel.air.typeOf(ty_op.operand, ip), 0, 8);
                if (try ptr_part_it.only(isel)) |ptr_part_vi|
                    try isel.live_values.putNoClobber(gpa, air_inst_index, ptr_part_vi.ref(isel));
            }

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .reduce, .reduce_optimized => {
            const reduce = air_data[@backingInt(air_inst_index)].reduce;

            try isel.analyzeUse(reduce.operand);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .shuffle_one => {
            const extra = isel.air.unwrapShuffleOne(zcu, air_inst_index);

            try isel.analyzeUse(extra.operand);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .shuffle_two => {
            const extra = isel.air.unwrapShuffleTwo(zcu, air_inst_index);

            try isel.analyzeUse(extra.operand_a);
            try isel.analyzeUse(extra.operand_b);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .select, .mul_add => {
            const pl_op = air_data[@backingInt(air_inst_index)].pl_op;
            const bin_op = isel.air.extraData(Air.Bin, pl_op.payload).data;

            try isel.analyzeUse(pl_op.operand);
            try isel.analyzeUse(bin_op.lhs);
            try isel.analyzeUse(bin_op.rhs);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .cmpxchg_weak, .cmpxchg_strong => {
            const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
            const extra = isel.air.extraData(Air.Cmpxchg, ty_pl.payload).data;

            try isel.analyzeUse(extra.ptr);
            try isel.analyzeUse(extra.expected_value);
            try isel.analyzeUse(extra.new_value);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .atomic_load => {
            const atomic_load = air_data[@backingInt(air_inst_index)].atomic_load;

            try isel.analyzeUse(atomic_load.ptr);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .atomic_rmw => {
            const pl_op = air_data[@backingInt(air_inst_index)].pl_op;
            const extra = isel.air.extraData(Air.AtomicRmw, pl_op.payload).data;

            try isel.analyzeUse(pl_op.operand);
            try isel.analyzeUse(extra.operand);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .aggregate_init => {
            const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
            const elements: []const Air.Inst.Ref = @ptrCast(isel.air.extra.items[ty_pl.payload..][0..@intCast(ty_pl.ty.arrayLen(zcu))]);

            for (elements) |element| try isel.analyzeUse(element);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .union_init => {
            const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
            const extra = isel.air.extraData(Air.UnionInit, ty_pl.payload).data;

            try isel.analyzeUse(extra.init);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .prefetch => {
            const prefetch = air_data[@backingInt(air_inst_index)].prefetch;

            try isel.analyzeUse(prefetch.ptr);

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .field_parent_ptr => {
            const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
            const extra = isel.air.extraData(Air.FieldParentPtr, ty_pl.payload).data;

            try isel.analyzeUse(extra.field_ptr);
            try isel.def_order.putNoClobber(gpa, air_inst_index, {});

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
        .set_err_return_trace => {
            const un_op = air_data[@backingInt(air_inst_index)].un_op;

            try isel.analyzeUse(un_op);

            air_body_index += 1;
            air_inst_index = air_body[air_body_index];
            continue :air_tag air_tags[@backingInt(air_inst_index)];
        },
    }
    assert(air_body_index == air_body.len);
    isel.def_order.shrinkRetainingCapacity(initial_def_order_len);
}

fn analyzeUse(isel: *Select, air_ref: Air.Inst.Ref) !void {
    const air_inst_index = air_ref.toIndex() orelse return;
    const def_order_index = isel.def_order.getIndex(air_inst_index).?;

    // Loop liveness
    var active_loop_index = isel.active_loops.items.len;
    while (active_loop_index > 0) {
        const prev_active_loop_index = active_loop_index - 1;
        const active_loop = isel.active_loops.items[prev_active_loop_index];
        if (def_order_index >= active_loop.get(isel).def_order) break;
        active_loop_index = prev_active_loop_index;
    }
    if (active_loop_index < isel.active_loops.items.len) {
        const active_loop = isel.active_loops.items[active_loop_index];
        const loop_live_gop =
            try isel.loop_live.set.getOrPut(isel.pt.zcu.gpa, .{ active_loop, air_inst_index });
        if (!loop_live_gop.found_existing) active_loop.get(isel).live += 1;
    }
}

pub fn finishAnalysis(isel: *Select) !void {
    const gpa = isel.pt.zcu.gpa;

    // Loop Liveness
    if (isel.loops.count() > 0) {
        try isel.loops.ensureUnusedCapacity(gpa, 1);

        const loop_live_len: u32 = @intCast(isel.loop_live.set.count());
        if (loop_live_len > 0) {
            try isel.loop_live.list.resize(gpa, loop_live_len);

            const loops = isel.loops.values();
            for (loops[1..], loops[0 .. loops.len - 1]) |*loop, prev_loop| loop.live += prev_loop.live;
            assert(loops[loops.len - 1].live == loop_live_len);

            for (isel.loop_live.set.keys()) |entry| {
                const loop, const inst = entry;
                const loop_live = &loop.get(isel).live;
                loop_live.* -= 1;
                isel.loop_live.list.items[loop_live.*] = inst;
            }
            assert(loops[0].live == 0);
        }

        const invalid_gop = isel.loops.getOrPutAssumeCapacity(Loop.invalid);
        assert(!invalid_gop.found_existing);
        invalid_gop.value_ptr.live = loop_live_len;
    }
}

const AirIterator = struct {
    isel: *Select,
    tag_items: []const Air.Inst.Tag,
    data_items: []const Air.Inst.Data,
    body: []const Air.Inst.Index,
    body_index: u32,
    inst_index: Air.Inst.Index,

    fn tag(it: *@This(), inst_index: Air.Inst.Index) Air.Inst.Tag {
        return it.tag_items[@backingInt(inst_index)];
    }

    fn data(it: *@This(), inst_index: Air.Inst.Index) Air.Inst.Data {
        return it.data_items[@backingInt(inst_index)];
    }

    fn next(it: *@This()) ?Air.Inst.Tag {
        if (it.body_index == 0) {
            @branchHint(.unlikely);
            return null;
        }
        it.body_index -= 1;
        it.inst_index = it.body[it.body_index];
        wip_mir_log.debug("{f}", .{it.fmtAir(it.inst_index)});
        return it.tag(it.inst_index);
    }

    fn fmtAir(it: @This(), inst: Air.Inst.Index) struct {
        isel: *Select,
        inst: Air.Inst.Index,
        pub fn format(fmt_air: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            fmt_air.isel.air.writeInst(writer, fmt_air.inst, fmt_air.isel.pt.zcu, null);
        }
    } {
        return .{ .isel = it.isel, .inst = inst };
    }
};

fn leafBody(isel: *Select, air: *AirIterator, first_air_tag: Air.Inst.Tag) codegen.Error!?Air.Inst.Tag {
    const zcu = isel.pt.zcu;
    const ip = &zcu.intern_pool;
    const gpa = zcu.gpa;

    air_tag: switch (first_air_tag) {
        else => |air_tag| return isel.fail("unimplemented {t}", .{air_tag}),
        .block,
        .loop,
        .cond_br,
        .switch_br,
        .loop_switch_br,
        .@"try",
        .try_cold,
        .try_ptr,
        .try_ptr_cold,
        .dbg_inline_block,
        => |air_tag| return air_tag,

        // No "scalarize" legalizations are enabled, so these instructions never appear.
        .legalize_vec_elem_val => unreachable,
        .legalize_vec_store_elem => unreachable,

        .arg => {
            const arg_vi = isel.live_values.fetchRemove(air.inst_index).?.value;
            defer arg_vi.deref(isel);
            switch (arg_vi.parent(isel)) {
                .unallocated, .stack_slot => if (arg_vi.hint(isel)) |arg_ra| {
                    try arg_vi.defLiveIn(isel, arg_ra, comptime &.initFill(.free));
                } else {
                    var arg_part_it = arg_vi.parts(isel);
                    while (arg_part_it.next()) |arg_part| {
                        if (arg_part.hint(isel)) |arg_ra| {
                            try arg_part.defLiveIn(isel, arg_ra, comptime &.initFill(.free));
                        }
                    }
                },
                .value, .constant => unreachable,
                .address => |address_vi| if (address_vi.hint(isel)) |address_ra| {
                    try address_vi.defLiveIn(isel, address_ra, comptime &.initFill(.free));
                },
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .add, .add_safe, .add_optimized, .add_wrap, .sub, .sub_safe, .sub_optimized, .sub_wrap => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                if (!ty.isRuntimeFloat()) try res_vi.value.addOrSubtract(isel, ty, try isel.use(bin_op.lhs), switch (air_tag) {
                    else => unreachable,
                    .add, .add_safe, .add_wrap => .add,
                    .sub, .sub_safe, .sub_wrap => .sub,
                }, try isel.use(bin_op.rhs), .{
                    .overflow = switch (air_tag) {
                        else => unreachable,
                        .add, .sub => .@"unreachable",
                        .add_safe, .sub_safe => .{ .panic = .integer_overflow },
                        .add_wrap, .sub_wrap => .wrap,
                    },
                }) else switch (ty.floatBits(isel.target)) {
                    else => unreachable,
                    16, 32, 64 => |bits| {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const need_fcvt = switch (bits) {
                            else => unreachable,
                            16 => !isel.target.cpu.has(.aarch64, .fullfp16),
                            32, 64 => false,
                        };
                        if (need_fcvt) try isel.emit(.fcvt(res_ra.h(), res_ra.s()));
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        const lhs_mat = try lhs_vi.matReg(isel);
                        const rhs_mat = try rhs_vi.matReg(isel);
                        const lhs_ra = if (need_fcvt) try isel.allocVecReg() else lhs_mat.ra;
                        defer if (need_fcvt) isel.freeReg(lhs_ra);
                        const rhs_ra = if (need_fcvt) try isel.allocVecReg() else rhs_mat.ra;
                        defer if (need_fcvt) isel.freeReg(rhs_ra);
                        try isel.emit(bits: switch (bits) {
                            else => unreachable,
                            16 => if (need_fcvt) continue :bits 32 else switch (air_tag) {
                                else => unreachable,
                                .add, .add_optimized => .fadd(res_ra.h(), lhs_ra.h(), rhs_ra.h()),
                                .sub, .sub_optimized => .fsub(res_ra.h(), lhs_ra.h(), rhs_ra.h()),
                            },
                            32 => switch (air_tag) {
                                else => unreachable,
                                .add, .add_optimized => .fadd(res_ra.s(), lhs_ra.s(), rhs_ra.s()),
                                .sub, .sub_optimized => .fsub(res_ra.s(), lhs_ra.s(), rhs_ra.s()),
                            },
                            64 => switch (air_tag) {
                                else => unreachable,
                                .add, .add_optimized => .fadd(res_ra.d(), lhs_ra.d(), rhs_ra.d()),
                                .sub, .sub_optimized => .fsub(res_ra.d(), lhs_ra.d(), rhs_ra.d()),
                            },
                        });
                        if (need_fcvt) {
                            try isel.emit(.fcvt(rhs_ra.s(), rhs_mat.ra.h()));
                            try isel.emit(.fcvt(lhs_ra.s(), lhs_mat.ra.h()));
                        }
                        try rhs_mat.finish(isel);
                        try lhs_mat.finish(isel);
                    },
                    80, 128 => |bits| {
                        try call.prepareReturn(isel);
                        switch (bits) {
                            else => unreachable,
                            16, 32, 64, 128 => try call.returnLiveIn(isel, res_vi.value, .v0),
                            80 => {
                                var res_hi16_it = res_vi.value.field(ty, 8, 8);
                                const res_hi16_vi = try res_hi16_it.only(isel);
                                try call.returnLiveIn(isel, res_hi16_vi.?, .r1);
                                var res_lo64_it = res_vi.value.field(ty, 0, 8);
                                const res_lo64_vi = try res_lo64_it.only(isel);
                                try call.returnLiveIn(isel, res_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishReturn(isel);

                        try call.prepareCallee(isel);
                        try isel.global_relocs.append(gpa, .{
                            .name = switch (air_tag) {
                                else => unreachable,
                                .add, .add_optimized => switch (bits) {
                                    else => unreachable,
                                    16 => "__addhf3",
                                    32 => "__addsf3",
                                    64 => "__adddf3",
                                    80 => "__addxf3",
                                    128 => "__addtf3",
                                },
                                .sub, .sub_optimized => switch (bits) {
                                    else => unreachable,
                                    16 => "__subhf3",
                                    32 => "__subsf3",
                                    64 => "__subdf3",
                                    80 => "__subxf3",
                                    128 => "__subtf3",
                                },
                            },
                            .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                        });
                        try isel.emit(.bl(0));
                        try call.finishCallee(isel);

                        try call.prepareParams(isel);
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        switch (bits) {
                            else => unreachable,
                            16, 32, 64, 128 => {
                                try call.paramLiveOut(isel, rhs_vi, .v1);
                                try call.paramLiveOut(isel, lhs_vi, .v0);
                            },
                            80 => {
                                var rhs_hi16_it = rhs_vi.field(ty, 8, 8);
                                const rhs_hi16_vi = try rhs_hi16_it.only(isel);
                                try call.paramLiveOut(isel, rhs_hi16_vi.?, .r3);
                                var rhs_lo64_it = rhs_vi.field(ty, 0, 8);
                                const rhs_lo64_vi = try rhs_lo64_it.only(isel);
                                try call.paramLiveOut(isel, rhs_lo64_vi.?, .r2);
                                var lhs_hi16_it = lhs_vi.field(ty, 8, 8);
                                const lhs_hi16_vi = try lhs_hi16_it.only(isel);
                                try call.paramLiveOut(isel, lhs_hi16_vi.?, .r1);
                                var lhs_lo64_it = lhs_vi.field(ty, 0, 8);
                                const lhs_lo64_vi = try lhs_lo64_it.only(isel);
                                try call.paramLiveOut(isel, lhs_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishParams(isel);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .add_sat, .sub_sat => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                const int_info = ty.intInfo(zcu);
                switch (int_info.bits) {
                    0 => unreachable,
                    1...64 => |bits| {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        const lhs_mat = try lhs_vi.matReg(isel);
                        const rhs_mat = try rhs_vi.matReg(isel);
                        const unsat_res_ra = unsat_res_ra: {
                            const res_lock = isel.tryLockReg(res_ra);
                            defer res_lock.unlock(isel);
                            break :unsat_res_ra try isel.allocIntReg();
                        };
                        defer isel.freeReg(unsat_res_ra);
                        switch (int_info.signedness) {
                            .signed => switch (bits) {
                                else => unreachable,
                                1...31 => {
                                    const shift: u5 = @intCast(32 - bits);
                                    try isel.emit(.sbfm(res_ra.w(), res_ra.w(), .{
                                        .N = .word,
                                        .immr = shift,
                                        .imms = 31,
                                    }));
                                    try isel.emit(.csel(res_ra.w(), res_ra.w(), unsat_res_ra.w(), .vs));
                                    try isel.emit(.eor(res_ra.w(), res_ra.w(), .{ .immediate = .{
                                        .N = .word,
                                        .immr = 1,
                                        .imms = 0,
                                    } }));
                                    try isel.emit(.sbfm(res_ra.w(), unsat_res_ra.w(), .{
                                        .N = .word,
                                        .immr = 31,
                                        .imms = 31,
                                    }));
                                    try isel.emit(switch (air_tag) {
                                        else => unreachable,
                                        .add_sat => .adds(unsat_res_ra.w(), unsat_res_ra.w(), .{ .shifted_register = .{
                                            .register = rhs_mat.ra.w(),
                                            .shift = .{ .lsl = shift },
                                        } }),
                                        .sub_sat => .subs(unsat_res_ra.w(), unsat_res_ra.w(), .{ .shifted_register = .{
                                            .register = rhs_mat.ra.w(),
                                            .shift = .{ .lsl = shift },
                                        } }),
                                    });
                                    try isel.emit(.ubfm(unsat_res_ra.w(), lhs_mat.ra.w(), .{
                                        .N = .word,
                                        .immr = @intCast((-%shift) & 31),
                                        .imms = @intCast(bits - 1),
                                    }));
                                },
                                32 => {
                                    try isel.emit(.csel(res_ra.w(), res_ra.w(), unsat_res_ra.w(), .vs));
                                    try isel.emit(.eor(res_ra.w(), res_ra.w(), .{ .immediate = .{
                                        .N = .word,
                                        .immr = 1,
                                        .imms = 0,
                                    } }));
                                    try isel.emit(.sbfm(res_ra.w(), unsat_res_ra.w(), .{
                                        .N = .word,
                                        .immr = 31,
                                        .imms = 31,
                                    }));
                                    try isel.emit(switch (air_tag) {
                                        else => unreachable,
                                        .add_sat => .adds(unsat_res_ra.w(), lhs_mat.ra.w(), .{ .register = rhs_mat.ra.w() }),
                                        .sub_sat => .subs(unsat_res_ra.w(), lhs_mat.ra.w(), .{ .register = rhs_mat.ra.w() }),
                                    });
                                },
                                33...63 => {
                                    const shift: u6 = @intCast(64 - bits);
                                    try isel.emit(.sbfm(res_ra.x(), res_ra.x(), .{
                                        .N = .doubleword,
                                        .immr = shift,
                                        .imms = 63,
                                    }));
                                    try isel.emit(.csel(res_ra.x(), res_ra.x(), unsat_res_ra.x(), .vs));
                                    try isel.emit(.eor(res_ra.x(), res_ra.x(), .{ .immediate = .{
                                        .N = .doubleword,
                                        .immr = 1,
                                        .imms = 0,
                                    } }));
                                    try isel.emit(.sbfm(res_ra.x(), unsat_res_ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 63,
                                        .imms = 63,
                                    }));
                                    try isel.emit(switch (air_tag) {
                                        else => unreachable,
                                        .add_sat => .adds(unsat_res_ra.x(), unsat_res_ra.x(), .{ .shifted_register = .{
                                            .register = rhs_mat.ra.x(),
                                            .shift = .{ .lsl = shift },
                                        } }),
                                        .sub_sat => .subs(unsat_res_ra.x(), unsat_res_ra.x(), .{ .shifted_register = .{
                                            .register = rhs_mat.ra.x(),
                                            .shift = .{ .lsl = shift },
                                        } }),
                                    });
                                    try isel.emit(.ubfm(unsat_res_ra.x(), lhs_mat.ra.x(), .{
                                        .N = .doubleword,
                                        .immr = @intCast((-%shift) & 63),
                                        .imms = @intCast(bits - 1),
                                    }));
                                },
                                64 => {
                                    try isel.emit(.csel(res_ra.x(), res_ra.x(), unsat_res_ra.x(), .vs));
                                    try isel.emit(.eor(res_ra.x(), res_ra.x(), .{ .immediate = .{
                                        .N = .doubleword,
                                        .immr = 1,
                                        .imms = 0,
                                    } }));
                                    try isel.emit(.sbfm(res_ra.x(), unsat_res_ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 63,
                                        .imms = 63,
                                    }));
                                    try isel.emit(switch (air_tag) {
                                        else => unreachable,
                                        .add_sat => .adds(unsat_res_ra.x(), lhs_mat.ra.x(), .{ .register = rhs_mat.ra.x() }),
                                        .sub_sat => .subs(unsat_res_ra.x(), lhs_mat.ra.x(), .{ .register = rhs_mat.ra.x() }),
                                    });
                                },
                            },
                            .unsigned => switch (air_tag) {
                                else => unreachable,
                                .add_sat => switch (bits) {
                                    else => unreachable,
                                    1...31 => {
                                        const shift: u5 = @intCast(32 - bits);
                                        try isel.emit(.ubfm(res_ra.w(), res_ra.w(), .{
                                            .N = .word,
                                            .immr = shift,
                                            .imms = 31,
                                        }));
                                        try isel.emit(.csinv(res_ra.w(), unsat_res_ra.w(), .wzr, .invert(.cs)));
                                        try isel.emit(.adds(unsat_res_ra.w(), unsat_res_ra.w(), .{ .shifted_register = .{
                                            .register = rhs_mat.ra.w(),
                                            .shift = .{ .lsl = shift },
                                        } }));
                                        try isel.emit(.ubfm(unsat_res_ra.w(), lhs_mat.ra.w(), .{
                                            .N = .word,
                                            .immr = @intCast((-%shift) & 31),
                                            .imms = @intCast(bits - 1),
                                        }));
                                    },
                                    32 => {
                                        try isel.emit(.csinv(res_ra.w(), unsat_res_ra.w(), .wzr, .invert(.cs)));
                                        try isel.emit(.adds(unsat_res_ra.w(), lhs_mat.ra.w(), .{ .register = rhs_mat.ra.w() }));
                                    },
                                    33...63 => {
                                        const shift: u6 = @intCast(64 - bits);
                                        try isel.emit(.ubfm(res_ra.x(), res_ra.x(), .{
                                            .N = .doubleword,
                                            .immr = shift,
                                            .imms = 63,
                                        }));
                                        try isel.emit(.csinv(res_ra.x(), unsat_res_ra.x(), .xzr, .invert(.cs)));
                                        try isel.emit(.adds(unsat_res_ra.x(), unsat_res_ra.x(), .{ .shifted_register = .{
                                            .register = rhs_mat.ra.x(),
                                            .shift = .{ .lsl = shift },
                                        } }));
                                        try isel.emit(.ubfm(unsat_res_ra.x(), lhs_mat.ra.x(), .{
                                            .N = .doubleword,
                                            .immr = @intCast((-%shift) & 63),
                                            .imms = @intCast(bits - 1),
                                        }));
                                    },
                                    64 => {
                                        try isel.emit(.csinv(res_ra.x(), unsat_res_ra.x(), .xzr, .invert(.cs)));
                                        try isel.emit(.adds(unsat_res_ra.x(), lhs_mat.ra.x(), .{ .register = rhs_mat.ra.x() }));
                                    },
                                },
                                .sub_sat => switch (bits) {
                                    else => unreachable,
                                    1...32 => {
                                        try isel.emit(.csel(res_ra.w(), unsat_res_ra.w(), .wzr, .invert(.cc)));
                                        try isel.emit(.subs(unsat_res_ra.w(), lhs_mat.ra.w(), .{ .register = rhs_mat.ra.w() }));
                                    },
                                    33...64 => {
                                        try isel.emit(.csel(res_ra.x(), unsat_res_ra.x(), .xzr, .invert(.cc)));
                                        try isel.emit(.subs(unsat_res_ra.x(), lhs_mat.ra.x(), .{ .register = rhs_mat.ra.x() }));
                                    },
                                },
                            },
                        }
                        try rhs_mat.finish(isel);
                        try lhs_mat.finish(isel);
                    },
                    65...128 => |bits| {
                        var res_hi64_it = res_vi.value.field(ty, 8, 8);
                        const res_hi64_vi = try res_hi64_it.only(isel);
                        const res_hi64_ra = try res_hi64_vi.?.defReg(isel);
                        var res_lo64_it = res_vi.value.field(ty, 0, 8);
                        const res_lo64_vi = try res_lo64_it.only(isel);
                        const res_lo64_ra = res_lo64_ra: {
                            const res_hi64_lock: RegLock = if (res_hi64_ra) |ra| isel.tryLockReg(ra) else .empty;
                            defer res_hi64_lock.unlock(isel);
                            break :res_lo64_ra try res_lo64_vi.?.defReg(isel);
                        };
                        if (res_hi64_ra == null and res_lo64_ra == null) break :unused;

                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        var rhs_hi64_it = rhs_vi.field(ty, 8, 8);
                        const rhs_hi64_vi = try rhs_hi64_it.only(isel);
                        const rhs_hi64_mat = try rhs_hi64_vi.?.matReg(isel);
                        var lhs_hi64_it = lhs_vi.field(ty, 8, 8);
                        const lhs_hi64_vi = try lhs_hi64_it.only(isel);
                        const lhs_hi64_mat = try lhs_hi64_vi.?.matReg(isel);
                        var rhs_lo64_it = rhs_vi.field(ty, 0, 8);
                        const rhs_lo64_vi = try rhs_lo64_it.only(isel);
                        const rhs_lo64_mat = try rhs_lo64_vi.?.matReg(isel);
                        var lhs_lo64_it = lhs_vi.field(ty, 0, 8);
                        const lhs_lo64_vi = try lhs_lo64_it.only(isel);
                        const lhs_lo64_mat = try lhs_lo64_vi.?.matReg(isel);

                        const unsat_lo64_ra, const unsat_hi64_ra, const tmp_ra = alloc_ras: {
                            const res_hi64_lock: RegLock = if (res_hi64_ra) |ra| isel.tryLockReg(ra) else .empty;
                            defer res_hi64_lock.unlock(isel);
                            const res_lo64_lock: RegLock = if (res_lo64_ra) |ra| isel.tryLockReg(ra) else .empty;
                            defer res_lo64_lock.unlock(isel);
                            break :alloc_ras .{
                                try isel.allocIntReg(),
                                try isel.allocIntReg(),
                                if (int_info.signedness == .signed or bits < 128) try isel.allocIntReg() else .zr,
                            };
                        };
                        defer {
                            if (tmp_ra != .zr) isel.freeReg(tmp_ra);
                            isel.freeReg(unsat_hi64_ra);
                            isel.freeReg(unsat_lo64_ra);
                        }

                        const hi_bits = bits - 64;
                        switch (int_info.signedness) {
                            .signed => {
                                if (res_hi64_ra) |res_ra| {
                                    if (bits < 128) {
                                        try isel.emit(.sbfm(res_ra.x(), res_ra.x(), .{
                                            .N = .doubleword,
                                            .immr = @intCast(64 - hi_bits),
                                            .imms = 63,
                                        }));
                                    }
                                    try isel.emit(.csel(res_ra.x(), tmp_ra.x(), unsat_hi64_ra.x(), .vs));
                                    try isel.emit(.eor(tmp_ra.x(), tmp_ra.x(), .{ .immediate = .{
                                        .N = .doubleword,
                                        .immr = 1,
                                        .imms = 0,
                                    } }));
                                }
                                if (res_lo64_ra) |res_ra| {
                                    try isel.emit(.csel(res_ra.x(), tmp_ra.x(), unsat_lo64_ra.x(), .vs));
                                }
                                try isel.emit(.sbfm(tmp_ra.x(), unsat_hi64_ra.x(), .{
                                    .N = .doubleword,
                                    .immr = 63,
                                    .imms = 63,
                                }));
                            },
                            .unsigned => switch (air_tag) {
                                else => unreachable,
                                .add_sat => {
                                    if (res_hi64_ra) |res_ra| {
                                        if (bits < 128) {
                                            try isel.emit(.ubfm(res_ra.x(), res_ra.x(), .{
                                                .N = .doubleword,
                                                .immr = @intCast(64 - hi_bits),
                                                .imms = 63,
                                            }));
                                        }
                                        try isel.emit(.csinv(res_ra.x(), unsat_hi64_ra.x(), .xzr, .invert(.cs)));
                                    }
                                    if (res_lo64_ra) |res_ra| {
                                        try isel.emit(.csinv(res_ra.x(), unsat_lo64_ra.x(), .xzr, .invert(.cs)));
                                    }
                                },
                                .sub_sat => {
                                    if (res_hi64_ra) |res_ra| {
                                        if (bits < 128) {
                                            try isel.emit(.ubfm(res_ra.x(), res_ra.x(), .{
                                                .N = .doubleword,
                                                .immr = @intCast(64 - hi_bits),
                                                .imms = 63,
                                            }));
                                        }
                                        try isel.emit(.csel(res_ra.x(), unsat_hi64_ra.x(), .xzr, .invert(.cc)));
                                    }
                                    if (res_lo64_ra) |res_ra| {
                                        try isel.emit(.csel(res_ra.x(), unsat_lo64_ra.x(), .xzr, .invert(.cc)));
                                    }
                                },
                            },
                        }
                        if (bits < 128) {
                            const shift: u6 = @intCast(64 - hi_bits);
                            try isel.emit(switch (air_tag) {
                                else => unreachable,
                                .add_sat => .adcs(unsat_hi64_ra.x(), unsat_hi64_ra.x(), tmp_ra.x()),
                                .sub_sat => .sbcs(unsat_hi64_ra.x(), unsat_hi64_ra.x(), tmp_ra.x()),
                            });
                            try isel.emit(switch (air_tag) {
                                else => unreachable,
                                .add_sat => .adds(unsat_lo64_ra.x(), lhs_lo64_mat.ra.x(), .{ .register = rhs_lo64_mat.ra.x() }),
                                .sub_sat => .subs(unsat_lo64_ra.x(), lhs_lo64_mat.ra.x(), .{ .register = rhs_lo64_mat.ra.x() }),
                            });
                            try isel.emit(.ubfm(tmp_ra.x(), rhs_hi64_mat.ra.x(), .{
                                .N = .doubleword,
                                .immr = @intCast((-%shift) & 63),
                                .imms = @intCast(hi_bits - 1),
                            }));
                            if (air_tag == .add_sat) {
                                try isel.emit(.orr(unsat_hi64_ra.x(), unsat_hi64_ra.x(), .{ .immediate = .{
                                    .N = .doubleword,
                                    .immr = 0,
                                    .imms = @intCast(shift - 1),
                                } }));
                            }
                            try isel.emit(.ubfm(unsat_hi64_ra.x(), lhs_hi64_mat.ra.x(), .{
                                .N = .doubleword,
                                .immr = @intCast((-%shift) & 63),
                                .imms = @intCast(hi_bits - 1),
                            }));
                        } else {
                            try isel.emit(switch (air_tag) {
                                else => unreachable,
                                .add_sat => .adcs(unsat_hi64_ra.x(), lhs_hi64_mat.ra.x(), rhs_hi64_mat.ra.x()),
                                .sub_sat => .sbcs(unsat_hi64_ra.x(), lhs_hi64_mat.ra.x(), rhs_hi64_mat.ra.x()),
                            });
                            try isel.emit(switch (air_tag) {
                                else => unreachable,
                                .add_sat => .adds(unsat_lo64_ra.x(), lhs_lo64_mat.ra.x(), .{ .register = rhs_lo64_mat.ra.x() }),
                                .sub_sat => .subs(unsat_lo64_ra.x(), lhs_lo64_mat.ra.x(), .{ .register = rhs_lo64_mat.ra.x() }),
                            });
                        }

                        try lhs_lo64_mat.finish(isel);
                        try rhs_lo64_mat.finish(isel);
                        try lhs_hi64_mat.finish(isel);
                        try rhs_hi64_mat.finish(isel);
                    },
                    else => return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) }),
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .mul, .mul_optimized, .mul_wrap => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                if (ty.isVector(zcu)) {
                    const vector_type = ip.indexToKey(ty.toIntern()).vector_type;
                    const elem_ty: ZigType = .fromInterned(vector_type.child);
                    const elem_size = elem_ty.abiSize(zcu);
                    if (!elem_ty.isAbiInt(zcu) or elem_size > 8) {
                        return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                    }
                    const elem_int_info = elem_ty.intInfo(zcu);
                    const lhs_vi = try isel.use(bin_op.lhs);
                    const rhs_vi = try isel.use(bin_op.rhs);
                    if (ty.bitSize(zcu) == vector_type.len * elem_size * 8) {
                        var elem_index: u64 = vector_type.len;
                        while (elem_index > 0) {
                            elem_index -= 1;
                            const elem_offset = elem_index * elem_size;
                            var res_elem_it = res_vi.value.field(ty, elem_offset, elem_size);
                            const res_elem_vi = try res_elem_it.only(isel);
                            var lhs_elem_it = lhs_vi.field(ty, elem_offset, elem_size);
                            const lhs_elem_vi = try lhs_elem_it.only(isel);
                            var rhs_elem_it = rhs_vi.field(ty, elem_offset, elem_size);
                            const rhs_elem_vi = try rhs_elem_it.only(isel);
                            const res_elem_ra = try res_elem_vi.?.defReg(isel) orelse continue;
                            switch (elem_int_info.bits) {
                                0 => unreachable,
                                1...32 => |bits| {
                                    switch (air_tag) {
                                        else => unreachable,
                                        .mul => {},
                                        .mul_wrap => switch (bits) {
                                            else => unreachable,
                                            1...31 => try isel.emit(switch (elem_int_info.signedness) {
                                                .signed => .sbfm(res_elem_ra.w(), res_elem_ra.w(), .{
                                                    .N = .word,
                                                    .immr = 0,
                                                    .imms = @intCast(bits - 1),
                                                }),
                                                .unsigned => .ubfm(res_elem_ra.w(), res_elem_ra.w(), .{
                                                    .N = .word,
                                                    .immr = 0,
                                                    .imms = @intCast(bits - 1),
                                                }),
                                            }),
                                            32 => {},
                                        },
                                    }
                                    const lhs_mat = try lhs_elem_vi.?.matReg(isel);
                                    const rhs_mat = try rhs_elem_vi.?.matReg(isel);
                                    try isel.emit(.madd(res_elem_ra.w(), lhs_mat.ra.w(), rhs_mat.ra.w(), .wzr));
                                    try rhs_mat.finish(isel);
                                    try lhs_mat.finish(isel);
                                },
                                33...64 => |bits| {
                                    switch (air_tag) {
                                        else => unreachable,
                                        .mul => {},
                                        .mul_wrap => switch (bits) {
                                            else => unreachable,
                                            33...63 => try isel.emit(switch (elem_int_info.signedness) {
                                                .signed => .sbfm(res_elem_ra.x(), res_elem_ra.x(), .{
                                                    .N = .doubleword,
                                                    .immr = 0,
                                                    .imms = @intCast(bits - 1),
                                                }),
                                                .unsigned => .ubfm(res_elem_ra.x(), res_elem_ra.x(), .{
                                                    .N = .doubleword,
                                                    .immr = 0,
                                                    .imms = @intCast(bits - 1),
                                                }),
                                            }),
                                            64 => {},
                                        },
                                    }
                                    const lhs_mat = try lhs_elem_vi.?.matReg(isel);
                                    const rhs_mat = try rhs_elem_vi.?.matReg(isel);
                                    try isel.emit(.madd(res_elem_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x(), .xzr));
                                    try rhs_mat.finish(isel);
                                    try lhs_mat.finish(isel);
                                },
                                else => unreachable,
                            }
                        }
                        break :unused;
                    }
                    if (ty.abiSize(zcu) <= 8) {
                        const bits = elem_int_info.bits;
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        var res_lock = isel.lockReg(res_ra);
                        defer res_lock.unlock(isel);
                        const lhs_mat = try lhs_vi.matReg(isel);
                        const rhs_mat = try rhs_vi.matReg(isel);
                        const tmp_lhs_ra = try isel.allocIntReg();
                        defer isel.freeReg(tmp_lhs_ra);
                        const tmp_rhs_ra = try isel.allocIntReg();
                        defer isel.freeReg(tmp_rhs_ra);
                        var elem_index: u64 = vector_type.len;
                        while (elem_index > 0) {
                            elem_index -= 1;
                            const lsb: u6 = @intCast(elem_index * bits);
                            if (elem_index == 0) {
                                try isel.emit(.ubfm(res_ra.x(), tmp_lhs_ra.x(), .{
                                    .N = .doubleword,
                                    .immr = 0,
                                    .imms = @intCast(bits - 1),
                                }));
                            } else {
                                try isel.emit(.bfm(res_ra.x(), tmp_lhs_ra.x(), .{
                                    .N = .doubleword,
                                    .immr = @intCast((-%lsb) & 63),
                                    .imms = @intCast(bits - 1),
                                }));
                            }
                            try isel.emit(.madd(tmp_lhs_ra.x(), tmp_lhs_ra.x(), tmp_rhs_ra.x(), .xzr));
                            try isel.emit(.ubfm(tmp_rhs_ra.x(), rhs_mat.ra.x(), .{
                                .N = .doubleword,
                                .immr = lsb,
                                .imms = @intCast(lsb + bits - 1),
                            }));
                            try isel.emit(.ubfm(tmp_lhs_ra.x(), lhs_mat.ra.x(), .{
                                .N = .doubleword,
                                .immr = lsb,
                                .imms = @intCast(lsb + bits - 1),
                            }));
                        }
                        try rhs_mat.finish(isel);
                        try lhs_mat.finish(isel);
                        break :unused;
                    }
                    return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                }
                if (!ty.isRuntimeFloat()) {
                    if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                    const int_info = ty.intInfo(zcu);
                    switch (int_info.bits) {
                        0 => unreachable,
                        1 => {
                            const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                            switch (int_info.signedness) {
                                .signed => switch (air_tag) {
                                    else => unreachable,
                                    .mul => break :unused try isel.emit(.orr(res_ra.w(), .wzr, .{ .register = .wzr })),
                                    .mul_wrap => {},
                                },
                                .unsigned => {},
                            }
                            const lhs_vi = try isel.use(bin_op.lhs);
                            const rhs_vi = try isel.use(bin_op.rhs);
                            const lhs_mat = try lhs_vi.matReg(isel);
                            const rhs_mat = try rhs_vi.matReg(isel);
                            try isel.emit(.@"and"(res_ra.w(), lhs_mat.ra.w(), .{ .register = rhs_mat.ra.w() }));
                            try rhs_mat.finish(isel);
                            try lhs_mat.finish(isel);
                        },
                        2...32 => |bits| {
                            const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                            switch (air_tag) {
                                else => unreachable,
                                .mul => {},
                                .mul_wrap => switch (bits) {
                                    else => unreachable,
                                    1...31 => try isel.emit(switch (int_info.signedness) {
                                        .signed => .sbfm(res_ra.w(), res_ra.w(), .{
                                            .N = .word,
                                            .immr = 0,
                                            .imms = @intCast(bits - 1),
                                        }),
                                        .unsigned => .ubfm(res_ra.w(), res_ra.w(), .{
                                            .N = .word,
                                            .immr = 0,
                                            .imms = @intCast(bits - 1),
                                        }),
                                    }),
                                    32 => {},
                                },
                            }
                            const lhs_vi = try isel.use(bin_op.lhs);
                            const rhs_vi = try isel.use(bin_op.rhs);
                            const lhs_mat = try lhs_vi.matReg(isel);
                            const rhs_mat = try rhs_vi.matReg(isel);
                            try isel.emit(.madd(res_ra.w(), lhs_mat.ra.w(), rhs_mat.ra.w(), .wzr));
                            try rhs_mat.finish(isel);
                            try lhs_mat.finish(isel);
                        },
                        33...64 => |bits| {
                            const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                            switch (air_tag) {
                                else => unreachable,
                                .mul => {},
                                .mul_wrap => switch (bits) {
                                    else => unreachable,
                                    33...63 => try isel.emit(switch (int_info.signedness) {
                                        .signed => .sbfm(res_ra.x(), res_ra.x(), .{
                                            .N = .doubleword,
                                            .immr = 0,
                                            .imms = @intCast(bits - 1),
                                        }),
                                        .unsigned => .ubfm(res_ra.x(), res_ra.x(), .{
                                            .N = .doubleword,
                                            .immr = 0,
                                            .imms = @intCast(bits - 1),
                                        }),
                                    }),
                                    64 => {},
                                },
                            }
                            const lhs_vi = try isel.use(bin_op.lhs);
                            const rhs_vi = try isel.use(bin_op.rhs);
                            const lhs_mat = try lhs_vi.matReg(isel);
                            const rhs_mat = try rhs_vi.matReg(isel);
                            try isel.emit(.madd(res_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x(), .xzr));
                            try rhs_mat.finish(isel);
                            try lhs_mat.finish(isel);
                        },
                        65...128 => |bits| {
                            var res_hi64_it = res_vi.value.field(ty, 8, 8);
                            const res_hi64_vi = try res_hi64_it.only(isel);
                            const res_hi64_ra = try res_hi64_vi.?.defReg(isel);
                            var res_lo64_it = res_vi.value.field(ty, 0, 8);
                            const res_lo64_vi = try res_lo64_it.only(isel);
                            const res_lo64_ra = res_lo64_ra: {
                                const res_hi64_lock: RegLock = if (res_hi64_ra) |ra| isel.tryLockReg(ra) else .empty;
                                defer res_hi64_lock.unlock(isel);
                                break :res_lo64_ra try res_lo64_vi.?.defReg(isel);
                            };
                            if (res_hi64_ra == null and res_lo64_ra == null) break :unused;
                            if (res_hi64_ra) |res_ra| switch (air_tag) {
                                else => unreachable,
                                .mul => {},
                                .mul_wrap => switch (bits) {
                                    else => unreachable,
                                    65...127 => try isel.emit(switch (int_info.signedness) {
                                        .signed => .sbfm(res_ra.x(), res_ra.x(), .{
                                            .N = .doubleword,
                                            .immr = 0,
                                            .imms = @intCast(bits - 64 - 1),
                                        }),
                                        .unsigned => .ubfm(res_ra.x(), res_ra.x(), .{
                                            .N = .doubleword,
                                            .immr = 0,
                                            .imms = @intCast(bits - 64 - 1),
                                        }),
                                    }),
                                    128 => {},
                                },
                            };
                            const lhs_vi = try isel.use(bin_op.lhs);
                            const rhs_vi = try isel.use(bin_op.rhs);
                            const lhs_lo64_mat, const rhs_lo64_mat = lo64_mat: {
                                const res_hi64_lock: RegLock = if (res_hi64_ra != null and res_lo64_ra != null)
                                    isel.lockReg(res_hi64_ra.?)
                                else
                                    .empty;
                                defer res_hi64_lock.unlock(isel);

                                var rhs_lo64_it = rhs_vi.field(ty, 0, 8);
                                const rhs_lo64_vi = try rhs_lo64_it.only(isel);
                                const rhs_lo64_mat = try rhs_lo64_vi.?.matReg(isel);
                                var lhs_lo64_it = lhs_vi.field(ty, 0, 8);
                                const lhs_lo64_vi = try lhs_lo64_it.only(isel);
                                const lhs_lo64_mat = try lhs_lo64_vi.?.matReg(isel);
                                break :lo64_mat .{ lhs_lo64_mat, rhs_lo64_mat };
                            };
                            if (res_lo64_ra) |res_ra| try isel.emit(.madd(res_ra.x(), lhs_lo64_mat.ra.x(), rhs_lo64_mat.ra.x(), .xzr));
                            if (res_hi64_ra) |res_ra| {
                                var rhs_hi64_it = rhs_vi.field(ty, 8, 8);
                                const rhs_hi64_vi = try rhs_hi64_it.only(isel);
                                const rhs_hi64_mat = try rhs_hi64_vi.?.matReg(isel);
                                var lhs_hi64_it = lhs_vi.field(ty, 8, 8);
                                const lhs_hi64_vi = try lhs_hi64_it.only(isel);
                                const lhs_hi64_mat = try lhs_hi64_vi.?.matReg(isel);
                                const acc_ra = try isel.allocIntReg();
                                defer isel.freeReg(acc_ra);
                                try isel.emit(.madd(res_ra.x(), lhs_hi64_mat.ra.x(), rhs_lo64_mat.ra.x(), acc_ra.x()));
                                try isel.emit(.madd(acc_ra.x(), lhs_lo64_mat.ra.x(), rhs_hi64_mat.ra.x(), acc_ra.x()));
                                try isel.emit(.umulh(acc_ra.x(), lhs_lo64_mat.ra.x(), rhs_lo64_mat.ra.x()));
                                try rhs_hi64_mat.finish(isel);
                                try lhs_hi64_mat.finish(isel);
                            }
                            try rhs_lo64_mat.finish(isel);
                            try lhs_lo64_mat.finish(isel);
                        },
                        else => return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) }),
                    }
                } else switch (ty.floatBits(isel.target)) {
                    else => unreachable,
                    16, 32, 64 => |bits| {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const need_fcvt = switch (bits) {
                            else => unreachable,
                            16 => !isel.target.cpu.has(.aarch64, .fullfp16),
                            32, 64 => false,
                        };
                        if (need_fcvt) try isel.emit(.fcvt(res_ra.h(), res_ra.s()));
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        const lhs_mat = try lhs_vi.matReg(isel);
                        const rhs_mat = try rhs_vi.matReg(isel);
                        const lhs_ra = if (need_fcvt) try isel.allocVecReg() else lhs_mat.ra;
                        defer if (need_fcvt) isel.freeReg(lhs_ra);
                        const rhs_ra = if (need_fcvt) try isel.allocVecReg() else rhs_mat.ra;
                        defer if (need_fcvt) isel.freeReg(rhs_ra);
                        try isel.emit(bits: switch (bits) {
                            else => unreachable,
                            16 => if (need_fcvt)
                                continue :bits 32
                            else
                                .fmul(res_ra.h(), lhs_ra.h(), rhs_ra.h()),
                            32 => .fmul(res_ra.s(), lhs_ra.s(), rhs_ra.s()),
                            64 => .fmul(res_ra.d(), lhs_ra.d(), rhs_ra.d()),
                        });
                        if (need_fcvt) {
                            try isel.emit(.fcvt(rhs_ra.s(), rhs_mat.ra.h()));
                            try isel.emit(.fcvt(lhs_ra.s(), lhs_mat.ra.h()));
                        }
                        try rhs_mat.finish(isel);
                        try lhs_mat.finish(isel);
                    },
                    80, 128 => |bits| {
                        try call.prepareReturn(isel);
                        switch (bits) {
                            else => unreachable,
                            16, 32, 64, 128 => try call.returnLiveIn(isel, res_vi.value, .v0),
                            80 => {
                                var res_hi16_it = res_vi.value.field(ty, 8, 8);
                                const res_hi16_vi = try res_hi16_it.only(isel);
                                try call.returnLiveIn(isel, res_hi16_vi.?, .r1);
                                var res_lo64_it = res_vi.value.field(ty, 0, 8);
                                const res_lo64_vi = try res_lo64_it.only(isel);
                                try call.returnLiveIn(isel, res_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishReturn(isel);

                        try call.prepareCallee(isel);
                        try isel.global_relocs.append(gpa, .{
                            .name = switch (bits) {
                                else => unreachable,
                                16 => "__mulhf3",
                                32 => "__mulsf3",
                                64 => "__muldf3",
                                80 => "__mulxf3",
                                128 => "__multf3",
                            },
                            .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                        });
                        try isel.emit(.bl(0));
                        try call.finishCallee(isel);

                        try call.prepareParams(isel);
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        switch (bits) {
                            else => unreachable,
                            16, 32, 64, 128 => {
                                try call.paramLiveOut(isel, rhs_vi, .v1);
                                try call.paramLiveOut(isel, lhs_vi, .v0);
                            },
                            80 => {
                                var rhs_hi16_it = rhs_vi.field(ty, 8, 8);
                                const rhs_hi16_vi = try rhs_hi16_it.only(isel);
                                try call.paramLiveOut(isel, rhs_hi16_vi.?, .r3);
                                var rhs_lo64_it = rhs_vi.field(ty, 0, 8);
                                const rhs_lo64_vi = try rhs_lo64_it.only(isel);
                                try call.paramLiveOut(isel, rhs_lo64_vi.?, .r2);
                                var lhs_hi16_it = lhs_vi.field(ty, 8, 8);
                                const lhs_hi16_vi = try lhs_hi16_it.only(isel);
                                try call.paramLiveOut(isel, lhs_hi16_vi.?, .r1);
                                var lhs_lo64_it = lhs_vi.field(ty, 0, 8);
                                const lhs_lo64_vi = try lhs_lo64_it.only(isel);
                                try call.paramLiveOut(isel, lhs_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishParams(isel);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .mul_safe => |air_tag| {
            {
                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                if (ty.isVector(zcu)) continue :air_tag .mul_wrap;
                if (ty.isAbiInt(zcu)) {
                    const int_info = ty.intInfo(zcu);
                    if ((int_info.signedness == .signed and int_info.bits > 1) or int_info.bits > 64) {
                        continue :air_tag .mul_wrap;
                    }
                }
            }
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                const int_info = ty.intInfo(zcu);
                switch (int_info.signedness) {
                    .signed => switch (int_info.bits) {
                        0 => unreachable,
                        1 => {
                            const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                            const lhs_vi = try isel.use(bin_op.lhs);
                            const rhs_vi = try isel.use(bin_op.rhs);
                            const lhs_mat = try lhs_vi.matReg(isel);
                            const rhs_mat = try rhs_vi.matReg(isel);
                            try isel.emit(.orr(res_ra.w(), lhs_mat.ra.w(), .{ .register = rhs_mat.ra.w() }));
                            const skip_label = isel.instructions.items.len;
                            try isel.emitPanic(.integer_overflow);
                            try isel.emit(.@"b."(
                                .invert(.ne),
                                @intCast((isel.instructions.items.len + 1 - skip_label) << 2),
                            ));
                            try isel.emit(.ands(.wzr, lhs_mat.ra.w(), .{ .register = rhs_mat.ra.w() }));
                            try rhs_mat.finish(isel);
                            try lhs_mat.finish(isel);
                        },
                        else => return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) }),
                    },
                    .unsigned => switch (int_info.bits) {
                        0 => unreachable,
                        1 => {
                            const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                            const lhs_vi = try isel.use(bin_op.lhs);
                            const rhs_vi = try isel.use(bin_op.rhs);
                            const lhs_mat = try lhs_vi.matReg(isel);
                            const rhs_mat = try rhs_vi.matReg(isel);
                            try isel.emit(.@"and"(res_ra.w(), lhs_mat.ra.w(), .{ .register = rhs_mat.ra.w() }));
                            try rhs_mat.finish(isel);
                            try lhs_mat.finish(isel);
                        },
                        2...16 => |bits| {
                            const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                            const lhs_vi = try isel.use(bin_op.lhs);
                            const rhs_vi = try isel.use(bin_op.rhs);
                            const lhs_mat = try lhs_vi.matReg(isel);
                            const rhs_mat = try rhs_vi.matReg(isel);
                            const skip_label = isel.instructions.items.len;
                            try isel.emitPanic(.integer_overflow);
                            try isel.emit(.@"b."(
                                .eq,
                                @intCast((isel.instructions.items.len + 1 - skip_label) << 2),
                            ));
                            try isel.emit(.ands(.wzr, res_ra.w(), .{ .immediate = .{
                                .N = .word,
                                .immr = @intCast(32 - bits),
                                .imms = @intCast(32 - bits - 1),
                            } }));
                            try isel.emit(.madd(res_ra.w(), lhs_mat.ra.w(), rhs_mat.ra.w(), .wzr));
                            try rhs_mat.finish(isel);
                            try lhs_mat.finish(isel);
                        },
                        17...32 => |bits| {
                            const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                            const lhs_vi = try isel.use(bin_op.lhs);
                            const rhs_vi = try isel.use(bin_op.rhs);
                            const lhs_mat = try lhs_vi.matReg(isel);
                            const rhs_mat = try rhs_vi.matReg(isel);
                            const skip_label = isel.instructions.items.len;
                            try isel.emitPanic(.integer_overflow);
                            try isel.emit(.@"b."(
                                .eq,
                                @intCast((isel.instructions.items.len + 1 - skip_label) << 2),
                            ));
                            try isel.emit(.ands(.xzr, res_ra.x(), .{ .immediate = .{
                                .N = .doubleword,
                                .immr = @intCast(64 - bits),
                                .imms = @intCast(64 - bits - 1),
                            } }));
                            try isel.emit(.umaddl(res_ra.x(), lhs_mat.ra.w(), rhs_mat.ra.w(), .xzr));
                            try rhs_mat.finish(isel);
                            try lhs_mat.finish(isel);
                        },
                        33...63 => |bits| {
                            const lo64_ra = try res_vi.value.defReg(isel) orelse break :unused;
                            const lhs_vi = try isel.use(bin_op.lhs);
                            const rhs_vi = try isel.use(bin_op.rhs);
                            const lhs_mat = try lhs_vi.matReg(isel);
                            const rhs_mat = try rhs_vi.matReg(isel);
                            const hi64_ra = hi64_ra: {
                                const lo64_lock = isel.tryLockReg(lo64_ra);
                                defer lo64_lock.unlock(isel);
                                break :hi64_ra try isel.allocIntReg();
                            };
                            defer isel.freeReg(hi64_ra);
                            const skip_label = isel.instructions.items.len;
                            try isel.emitPanic(.integer_overflow);
                            try isel.emit(.cbz(
                                hi64_ra.x(),
                                @intCast((isel.instructions.items.len + 1 - skip_label) << 2),
                            ));
                            try isel.emit(.orr(hi64_ra.x(), hi64_ra.x(), .{ .shifted_register = .{
                                .register = lo64_ra.x(),
                                .shift = .{ .lsr = @intCast(bits) },
                            } }));
                            try isel.emit(.madd(lo64_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x(), .xzr));
                            try isel.emit(.umulh(hi64_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x()));
                            try rhs_mat.finish(isel);
                            try lhs_mat.finish(isel);
                        },
                        64 => {
                            const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                            const lhs_vi = try isel.use(bin_op.lhs);
                            const rhs_vi = try isel.use(bin_op.rhs);
                            const lhs_mat = try lhs_vi.matReg(isel);
                            const rhs_mat = try rhs_vi.matReg(isel);
                            try isel.emit(.madd(res_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x(), .xzr));
                            const hi64_ra = try isel.allocIntReg();
                            defer isel.freeReg(hi64_ra);
                            const skip_label = isel.instructions.items.len;
                            try isel.emitPanic(.integer_overflow);
                            try isel.emit(.cbz(
                                hi64_ra.x(),
                                @intCast((isel.instructions.items.len + 1 - skip_label) << 2),
                            ));
                            try isel.emit(.umulh(hi64_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x()));
                            try rhs_mat.finish(isel);
                            try lhs_mat.finish(isel);
                        },
                        65...128 => return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) }),
                        else => return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) }),
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .mul_sat => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                const int_info = ty.intInfo(zcu);
                switch (int_info.bits) {
                    0 => unreachable,
                    1 => {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        switch (int_info.signedness) {
                            .signed => try isel.emit(.orr(res_ra.w(), .wzr, .{ .register = .wzr })),
                            .unsigned => {
                                const lhs_vi = try isel.use(bin_op.lhs);
                                const rhs_vi = try isel.use(bin_op.rhs);
                                const lhs_mat = try lhs_vi.matReg(isel);
                                const rhs_mat = try rhs_vi.matReg(isel);
                                try isel.emit(.@"and"(res_ra.w(), lhs_mat.ra.w(), .{ .register = rhs_mat.ra.w() }));
                                try rhs_mat.finish(isel);
                                try lhs_mat.finish(isel);
                            },
                        }
                    },
                    2...32 => |bits| {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const saturated_ra = switch (int_info.signedness) {
                            .signed => try isel.allocIntReg(),
                            .unsigned => switch (bits) {
                                else => unreachable,
                                2...31 => try isel.allocIntReg(),
                                32 => .zr,
                            },
                        };
                        defer if (saturated_ra != .zr) isel.freeReg(saturated_ra);
                        const unwrapped_ra = try isel.allocIntReg();
                        defer isel.freeReg(unwrapped_ra);
                        try isel.emit(switch (saturated_ra) {
                            else => .csel(res_ra.w(), unwrapped_ra.w(), saturated_ra.w(), .eq),
                            .zr => .csinv(res_ra.w(), unwrapped_ra.w(), saturated_ra.w(), .eq),
                        });
                        switch (bits) {
                            else => unreachable,
                            2...7, 9...15, 17...31 => switch (int_info.signedness) {
                                .signed => {
                                    const wrapped_ra = try isel.allocIntReg();
                                    defer isel.freeReg(wrapped_ra);
                                    switch (bits) {
                                        else => unreachable,
                                        1...7, 9...15 => {
                                            try isel.emit(.subs(.wzr, unwrapped_ra.w(), .{ .register = wrapped_ra.w() }));
                                            try isel.emit(.sbfm(wrapped_ra.w(), unwrapped_ra.w(), .{
                                                .N = .word,
                                                .immr = 0,
                                                .imms = @intCast(bits - 1),
                                            }));
                                        },
                                        17...31 => {
                                            try isel.emit(.subs(.xzr, unwrapped_ra.x(), .{ .register = wrapped_ra.x() }));
                                            try isel.emit(.sbfm(wrapped_ra.x(), unwrapped_ra.x(), .{
                                                .N = .doubleword,
                                                .immr = 0,
                                                .imms = @intCast(bits - 1),
                                            }));
                                        },
                                    }
                                },
                                .unsigned => switch (bits) {
                                    else => unreachable,
                                    1...7, 9...15 => try isel.emit(.ands(.wzr, unwrapped_ra.w(), .{ .immediate = .{
                                        .N = .word,
                                        .immr = @intCast(32 - bits),
                                        .imms = @intCast(32 - bits - 1),
                                    } })),
                                    17...31 => try isel.emit(.ands(.xzr, unwrapped_ra.x(), .{ .immediate = .{
                                        .N = .doubleword,
                                        .immr = @intCast(64 - bits),
                                        .imms = @intCast(64 - bits - 1),
                                    } })),
                                },
                            },
                            8 => try isel.emit(.subs(.wzr, unwrapped_ra.w(), .{ .extended_register = .{
                                .register = unwrapped_ra.w(),
                                .extend = switch (int_info.signedness) {
                                    .signed => .{ .sxtb = 0 },
                                    .unsigned => .{ .uxtb = 0 },
                                },
                            } })),
                            16 => try isel.emit(.subs(.wzr, unwrapped_ra.w(), .{ .extended_register = .{
                                .register = unwrapped_ra.w(),
                                .extend = switch (int_info.signedness) {
                                    .signed => .{ .sxth = 0 },
                                    .unsigned => .{ .uxth = 0 },
                                },
                            } })),
                            32 => try isel.emit(.subs(.xzr, unwrapped_ra.x(), .{ .extended_register = .{
                                .register = unwrapped_ra.w(),
                                .extend = switch (int_info.signedness) {
                                    .signed => .{ .sxtw = 0 },
                                    .unsigned => .{ .uxtw = 0 },
                                },
                            } })),
                        }
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        const lhs_mat = try lhs_vi.matReg(isel);
                        const rhs_mat = try rhs_vi.matReg(isel);
                        switch (int_info.signedness) {
                            .signed => {
                                try isel.emit(.eor(saturated_ra.w(), saturated_ra.w(), .{ .immediate = .{
                                    .N = .word,
                                    .immr = 0,
                                    .imms = @intCast(bits - 1 - 1),
                                } }));
                                try isel.emit(.sbfm(saturated_ra.w(), saturated_ra.w(), .{
                                    .N = .word,
                                    .immr = @intCast(bits - 1),
                                    .imms = @intCast(bits - 1 + 1 - 1),
                                }));
                                try isel.emit(.eor(saturated_ra.w(), lhs_mat.ra.w(), .{ .register = rhs_mat.ra.w() }));
                            },
                            .unsigned => switch (bits) {
                                else => unreachable,
                                2...31 => try isel.movImmediate(saturated_ra.w(), @as(u32, std.math.maxInt(u32)) >> @intCast(32 - bits)),
                                32 => {},
                            },
                        }
                        switch (bits) {
                            else => unreachable,
                            2...16 => try isel.emit(.madd(unwrapped_ra.w(), lhs_mat.ra.w(), rhs_mat.ra.w(), .wzr)),
                            17...32 => switch (int_info.signedness) {
                                .signed => try isel.emit(.smaddl(unwrapped_ra.x(), lhs_mat.ra.w(), rhs_mat.ra.w(), .xzr)),
                                .unsigned => try isel.emit(.umaddl(unwrapped_ra.x(), lhs_mat.ra.w(), rhs_mat.ra.w(), .xzr)),
                            },
                        }
                        try rhs_mat.finish(isel);
                        try lhs_mat.finish(isel);
                    },
                    33...64 => |bits| {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const saturated_ra = switch (int_info.signedness) {
                            .signed => try isel.allocIntReg(),
                            .unsigned => switch (bits) {
                                else => unreachable,
                                33...63 => try isel.allocIntReg(),
                                64 => .zr,
                            },
                        };
                        defer if (saturated_ra != .zr) isel.freeReg(saturated_ra);
                        const unwrapped_lo64_ra = try isel.allocIntReg();
                        defer isel.freeReg(unwrapped_lo64_ra);
                        const unwrapped_hi64_ra = try isel.allocIntReg();
                        defer isel.freeReg(unwrapped_hi64_ra);
                        try isel.emit(switch (saturated_ra) {
                            else => .csel(res_ra.x(), unwrapped_lo64_ra.x(), saturated_ra.x(), .eq),
                            .zr => .csinv(res_ra.x(), unwrapped_lo64_ra.x(), saturated_ra.x(), .eq),
                        });
                        switch (int_info.signedness) {
                            .signed => switch (bits) {
                                else => unreachable,
                                32...63 => {
                                    const wrapped_lo64_ra = try isel.allocIntReg();
                                    defer isel.freeReg(wrapped_lo64_ra);
                                    try isel.emit(.ccmp(
                                        unwrapped_lo64_ra.x(),
                                        .{ .register = wrapped_lo64_ra.x() },
                                        .{ .n = false, .z = false, .c = false, .v = false },
                                        .eq,
                                    ));
                                    try isel.emit(.subs(.xzr, unwrapped_hi64_ra.x(), .{ .shifted_register = .{
                                        .register = unwrapped_lo64_ra.x(),
                                        .shift = .{ .asr = 63 },
                                    } }));
                                    try isel.emit(.sbfm(wrapped_lo64_ra.x(), unwrapped_lo64_ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 0,
                                        .imms = @intCast(bits - 1),
                                    }));
                                },
                                64 => try isel.emit(.subs(.xzr, unwrapped_hi64_ra.x(), .{ .shifted_register = .{
                                    .register = unwrapped_lo64_ra.x(),
                                    .shift = .{ .asr = @intCast(bits - 1) },
                                } })),
                            },
                            .unsigned => switch (bits) {
                                else => unreachable,
                                32...63 => {
                                    const overflow_ra = try isel.allocIntReg();
                                    defer isel.freeReg(overflow_ra);
                                    try isel.emit(.subs(.xzr, overflow_ra.x(), .{ .immediate = 0 }));
                                    try isel.emit(.orr(overflow_ra.x(), unwrapped_hi64_ra.x(), .{ .shifted_register = .{
                                        .register = unwrapped_lo64_ra.x(),
                                        .shift = .{ .lsr = @intCast(bits) },
                                    } }));
                                },
                                64 => try isel.emit(.subs(.xzr, unwrapped_hi64_ra.x(), .{ .immediate = 0 })),
                            },
                        }
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        const lhs_mat = try lhs_vi.matReg(isel);
                        const rhs_mat = try rhs_vi.matReg(isel);
                        switch (int_info.signedness) {
                            .signed => {
                                try isel.emit(.eor(saturated_ra.x(), saturated_ra.x(), .{ .immediate = .{
                                    .N = .doubleword,
                                    .immr = 0,
                                    .imms = @intCast(bits - 1 - 1),
                                } }));
                                try isel.emit(.sbfm(saturated_ra.x(), saturated_ra.x(), .{
                                    .N = .doubleword,
                                    .immr = @intCast(bits - 1),
                                    .imms = @intCast(bits - 1 + 1 - 1),
                                }));
                                try isel.emit(.eor(saturated_ra.x(), lhs_mat.ra.x(), .{ .register = rhs_mat.ra.x() }));
                                try isel.emit(.madd(unwrapped_lo64_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x(), .xzr));
                                try isel.emit(.smulh(unwrapped_hi64_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x()));
                            },
                            .unsigned => {
                                switch (bits) {
                                    else => unreachable,
                                    32...63 => try isel.movImmediate(saturated_ra.x(), @as(u64, std.math.maxInt(u64)) >> @intCast(64 - bits)),
                                    64 => {},
                                }
                                try isel.emit(.madd(unwrapped_lo64_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x(), .xzr));
                                try isel.emit(.umulh(unwrapped_hi64_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x()));
                            },
                        }
                        try rhs_mat.finish(isel);
                        try lhs_mat.finish(isel);
                    },
                    else => return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) }),
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .div_float, .div_float_optimized => {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                switch (ty.floatBits(isel.target)) {
                    else => unreachable,
                    16, 32, 64 => |bits| {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const need_fcvt = switch (bits) {
                            else => unreachable,
                            16 => !isel.target.cpu.has(.aarch64, .fullfp16),
                            32, 64 => false,
                        };
                        if (need_fcvt) try isel.emit(.fcvt(res_ra.h(), res_ra.s()));
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        const lhs_mat = try lhs_vi.matReg(isel);
                        const rhs_mat = try rhs_vi.matReg(isel);
                        const lhs_ra = if (need_fcvt) try isel.allocVecReg() else lhs_mat.ra;
                        defer if (need_fcvt) isel.freeReg(lhs_ra);
                        const rhs_ra = if (need_fcvt) try isel.allocVecReg() else rhs_mat.ra;
                        defer if (need_fcvt) isel.freeReg(rhs_ra);
                        try isel.emit(bits: switch (bits) {
                            else => unreachable,
                            16 => if (need_fcvt)
                                continue :bits 32
                            else
                                .fdiv(res_ra.h(), lhs_ra.h(), rhs_ra.h()),
                            32 => .fdiv(res_ra.s(), lhs_ra.s(), rhs_ra.s()),
                            64 => .fdiv(res_ra.d(), lhs_ra.d(), rhs_ra.d()),
                        });
                        if (need_fcvt) {
                            try isel.emit(.fcvt(rhs_ra.s(), rhs_mat.ra.h()));
                            try isel.emit(.fcvt(lhs_ra.s(), lhs_mat.ra.h()));
                        }
                        try rhs_mat.finish(isel);
                        try lhs_mat.finish(isel);
                    },
                    80, 128 => |bits| {
                        try call.prepareReturn(isel);
                        switch (bits) {
                            else => unreachable,
                            16, 32, 64, 128 => try call.returnLiveIn(isel, res_vi.value, .v0),
                            80 => {
                                var res_hi16_it = res_vi.value.field(ty, 8, 8);
                                const res_hi16_vi = try res_hi16_it.only(isel);
                                try call.returnLiveIn(isel, res_hi16_vi.?, .r1);
                                var res_lo64_it = res_vi.value.field(ty, 0, 8);
                                const res_lo64_vi = try res_lo64_it.only(isel);
                                try call.returnLiveIn(isel, res_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishReturn(isel);

                        try call.prepareCallee(isel);
                        try isel.global_relocs.append(gpa, .{
                            .name = switch (bits) {
                                else => unreachable,
                                16 => "__divhf3",
                                32 => "__divsf3",
                                64 => "__divdf3",
                                80 => "__divxf3",
                                128 => "__divtf3",
                            },
                            .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                        });
                        try isel.emit(.bl(0));
                        try call.finishCallee(isel);

                        try call.prepareParams(isel);
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        switch (bits) {
                            else => unreachable,
                            16, 32, 64, 128 => {
                                try call.paramLiveOut(isel, rhs_vi, .v1);
                                try call.paramLiveOut(isel, lhs_vi, .v0);
                            },
                            80 => {
                                var rhs_hi16_it = rhs_vi.field(ty, 8, 8);
                                const rhs_hi16_vi = try rhs_hi16_it.only(isel);
                                try call.paramLiveOut(isel, rhs_hi16_vi.?, .r3);
                                var rhs_lo64_it = rhs_vi.field(ty, 0, 8);
                                const rhs_lo64_vi = try rhs_lo64_it.only(isel);
                                try call.paramLiveOut(isel, rhs_lo64_vi.?, .r2);
                                var lhs_hi16_it = lhs_vi.field(ty, 8, 8);
                                const lhs_hi16_vi = try lhs_hi16_it.only(isel);
                                try call.paramLiveOut(isel, lhs_hi16_vi.?, .r1);
                                var lhs_lo64_it = lhs_vi.field(ty, 0, 8);
                                const lhs_lo64_vi = try lhs_lo64_it.only(isel);
                                try call.paramLiveOut(isel, lhs_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishParams(isel);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .div_trunc, .div_trunc_optimized, .div_floor, .div_floor_optimized, .div_exact, .div_exact_optimized => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                if (!ty.isRuntimeFloat()) {
                    if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                    const int_info = ty.intInfo(zcu);
                    switch (int_info.bits) {
                        0 => unreachable,
                        1...64 => |bits| {
                            const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                            const lhs_vi = try isel.use(bin_op.lhs);
                            const rhs_vi = try isel.use(bin_op.rhs);
                            const lhs_mat = try lhs_vi.matReg(isel);
                            const rhs_mat = try rhs_vi.matReg(isel);
                            const div_ra, const free_div_ra = div_ra: switch (air_tag) {
                                else => unreachable,
                                .div_trunc, .div_exact => .{ res_ra, false },
                                .div_floor => switch (int_info.signedness) {
                                    .signed => {
                                        const div_ra = try isel.allocIntReg();
                                        errdefer isel.freeReg(div_ra);
                                        const rem_ra = try isel.allocIntReg();
                                        defer isel.freeReg(rem_ra);
                                        switch (bits) {
                                            else => unreachable,
                                            1...32 => {
                                                try isel.emit(.csel(res_ra.w(), div_ra.w(), rem_ra.w(), .pl));
                                                try isel.emit(.sub(rem_ra.w(), div_ra.w(), .{ .immediate = 1 }));
                                                try isel.emit(.ccmp(
                                                    rem_ra.w(),
                                                    .{ .immediate = 0 },
                                                    .{ .n = false, .z = false, .c = false, .v = false },
                                                    .ne,
                                                ));
                                                try isel.emit(.eor(rem_ra.w(), rem_ra.w(), .{ .register = rhs_mat.ra.w() }));
                                                try isel.emit(.subs(.wzr, rem_ra.w(), .{ .immediate = 0 }));
                                                try isel.emit(.msub(rem_ra.w(), div_ra.w(), rhs_mat.ra.w(), lhs_mat.ra.w()));
                                            },
                                            33...64 => {
                                                try isel.emit(.csel(res_ra.x(), div_ra.x(), rem_ra.x(), .pl));
                                                try isel.emit(.sub(rem_ra.x(), div_ra.x(), .{ .immediate = 1 }));
                                                try isel.emit(.ccmp(
                                                    rem_ra.x(),
                                                    .{ .immediate = 0 },
                                                    .{ .n = false, .z = false, .c = false, .v = false },
                                                    .ne,
                                                ));
                                                try isel.emit(.eor(rem_ra.x(), rem_ra.x(), .{ .register = rhs_mat.ra.x() }));
                                                try isel.emit(.subs(.xzr, rem_ra.x(), .{ .immediate = 0 }));
                                                try isel.emit(.msub(rem_ra.x(), div_ra.x(), rhs_mat.ra.x(), lhs_mat.ra.x()));
                                            },
                                        }
                                        break :div_ra .{ div_ra, true };
                                    },
                                    .unsigned => .{ res_ra, false },
                                },
                            };
                            defer if (free_div_ra) isel.freeReg(div_ra);
                            try isel.emit(switch (bits) {
                                else => unreachable,
                                1...32 => switch (int_info.signedness) {
                                    .signed => .sdiv(div_ra.w(), lhs_mat.ra.w(), rhs_mat.ra.w()),
                                    .unsigned => .udiv(div_ra.w(), lhs_mat.ra.w(), rhs_mat.ra.w()),
                                },
                                33...64 => switch (int_info.signedness) {
                                    .signed => .sdiv(div_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x()),
                                    .unsigned => .udiv(div_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x()),
                                },
                            });
                            try rhs_mat.finish(isel);
                            try lhs_mat.finish(isel);
                        },
                        65...128 => |bits| {
                            const is_signed_floor = (air_tag == .div_floor or air_tag == .div_floor_optimized) and int_info.signedness == .signed;

                            try call.prepareReturn(isel);
                            var res_hi64_it = res_vi.value.field(ty, 8, 8);
                            const res_hi64_vi = try res_hi64_it.only(isel);
                            try call.returnLiveIn(isel, res_hi64_vi.?, .r1);
                            var res_lo64_it = res_vi.value.field(ty, 0, 8);
                            const res_lo64_vi = try res_lo64_it.only(isel);
                            try call.returnLiveIn(isel, res_lo64_vi.?, .r0);
                            try call.finishReturn(isel);

                            try call.prepareCallee(isel);
                            if (is_signed_floor) {
                                try isel.emit(.sbc(.x1, .x1, .xzr));
                                try isel.emit(.subs(.x0, .x0, .{ .register = .x7 }));
                                try isel.emit(.csel(.x7, .x7, .xzr, .ne));
                                try isel.emit(.subs(.xzr, .x6, .{ .immediate = 0 }));
                                try isel.emit(.ubfm(.x7, .x7, .{ .N = .doubleword, .immr = 63, .imms = 63 }));
                                try isel.emit(.eor(.x7, .x5, .{ .register = .x3 }));
                                try isel.emit(.orr(.x6, .x6, .{ .register = .x7 }));
                                try isel.emit(.eor(.x7, .x7, .{ .register = .x5 }));
                                try isel.emit(.eor(.x6, .x6, .{ .register = .x4 }));
                                try isel.emit(.madd(.x7, .x1, .x2, .x7));
                                try isel.emit(.madd(.x7, .x0, .x3, .x7));
                                try isel.emit(.umulh(.x7, .x0, .x2));
                                try isel.emit(.madd(.x6, .x0, .x2, .xzr));
                                try isel.emit(.ldp(.x4, .x5, .{ .post_index = .{ .base = .sp, .index = 32 } }));
                                try isel.emit(.ldp(.x2, .x3, .{ .signed_offset = .{ .base = .sp, .offset = 16 } }));
                            }
                            try isel.global_relocs.append(gpa, .{
                                .name = switch (int_info.signedness) {
                                    .signed => "__divti3",
                                    .unsigned => "__udivti3",
                                },
                                .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                            });
                            try isel.emit(.bl(0));
                            if (is_signed_floor) {
                                try isel.emit(.stp(.x2, .x3, .{ .signed_offset = .{ .base = .sp, .offset = 16 } }));
                                try isel.emit(.stp(.x0, .x1, .{ .pre_index = .{ .base = .sp, .index = -32 } }));
                            }
                            if (bits < 128) switch (int_info.signedness) {
                                .signed => {
                                    try isel.emit(.sbfm(.x3, .x3, .{ .N = .doubleword, .immr = 0, .imms = @intCast(bits - 64 - 1) }));
                                    try isel.emit(.sbfm(.x1, .x1, .{ .N = .doubleword, .immr = 0, .imms = @intCast(bits - 64 - 1) }));
                                },
                                .unsigned => {
                                    try isel.emit(.ubfm(.x3, .x3, .{ .N = .doubleword, .immr = 0, .imms = @intCast(bits - 64 - 1) }));
                                    try isel.emit(.ubfm(.x1, .x1, .{ .N = .doubleword, .immr = 0, .imms = @intCast(bits - 64 - 1) }));
                                },
                            };
                            try call.finishCallee(isel);

                            try call.prepareParams(isel);
                            const lhs_vi = try isel.use(bin_op.lhs);
                            const rhs_vi = try isel.use(bin_op.rhs);
                            var rhs_hi64_it = rhs_vi.field(ty, 8, 8);
                            const rhs_hi64_vi = try rhs_hi64_it.only(isel);
                            try call.paramLiveOut(isel, rhs_hi64_vi.?, .r3);
                            var rhs_lo64_it = rhs_vi.field(ty, 0, 8);
                            const rhs_lo64_vi = try rhs_lo64_it.only(isel);
                            try call.paramLiveOut(isel, rhs_lo64_vi.?, .r2);
                            var lhs_hi64_it = lhs_vi.field(ty, 8, 8);
                            const lhs_hi64_vi = try lhs_hi64_it.only(isel);
                            try call.paramLiveOut(isel, lhs_hi64_vi.?, .r1);
                            var lhs_lo64_it = lhs_vi.field(ty, 0, 8);
                            const lhs_lo64_vi = try lhs_lo64_it.only(isel);
                            try call.paramLiveOut(isel, lhs_lo64_vi.?, .r0);
                            try call.finishParams(isel);
                        },
                        else => return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) }),
                    }
                } else switch (ty.floatBits(isel.target)) {
                    else => unreachable,
                    16, 32, 64 => |bits| {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const need_fcvt = switch (bits) {
                            else => unreachable,
                            16 => !isel.target.cpu.has(.aarch64, .fullfp16),
                            32, 64 => false,
                        };
                        if (need_fcvt) try isel.emit(.fcvt(res_ra.h(), res_ra.s()));
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        const lhs_mat = try lhs_vi.matReg(isel);
                        const rhs_mat = try rhs_vi.matReg(isel);
                        const lhs_ra = if (need_fcvt) try isel.allocVecReg() else lhs_mat.ra;
                        defer if (need_fcvt) isel.freeReg(lhs_ra);
                        const rhs_ra = if (need_fcvt) try isel.allocVecReg() else rhs_mat.ra;
                        defer if (need_fcvt) isel.freeReg(rhs_ra);
                        bits: switch (bits) {
                            else => unreachable,
                            16 => if (need_fcvt) continue :bits 32 else {
                                switch (air_tag) {
                                    else => unreachable,
                                    .div_trunc, .div_trunc_optimized => try isel.emit(.frintz(res_ra.h(), res_ra.h())),
                                    .div_floor, .div_floor_optimized => try isel.emit(.frintm(res_ra.h(), res_ra.h())),
                                    .div_exact, .div_exact_optimized => {},
                                }
                                try isel.emit(.fdiv(res_ra.h(), lhs_ra.h(), rhs_ra.h()));
                            },
                            32 => {
                                switch (air_tag) {
                                    else => unreachable,
                                    .div_trunc, .div_trunc_optimized => try isel.emit(.frintz(res_ra.s(), res_ra.s())),
                                    .div_floor, .div_floor_optimized => try isel.emit(.frintm(res_ra.s(), res_ra.s())),
                                    .div_exact, .div_exact_optimized => {},
                                }
                                try isel.emit(.fdiv(res_ra.s(), lhs_ra.s(), rhs_ra.s()));
                            },
                            64 => {
                                switch (air_tag) {
                                    else => unreachable,
                                    .div_trunc, .div_trunc_optimized => try isel.emit(.frintz(res_ra.d(), res_ra.d())),
                                    .div_floor, .div_floor_optimized => try isel.emit(.frintm(res_ra.d(), res_ra.d())),
                                    .div_exact, .div_exact_optimized => {},
                                }
                                try isel.emit(.fdiv(res_ra.d(), lhs_ra.d(), rhs_ra.d()));
                            },
                        }
                        if (need_fcvt) {
                            try isel.emit(.fcvt(rhs_ra.s(), rhs_mat.ra.h()));
                            try isel.emit(.fcvt(lhs_ra.s(), lhs_mat.ra.h()));
                        }
                        try rhs_mat.finish(isel);
                        try lhs_mat.finish(isel);
                    },
                    80, 128 => |bits| {
                        try call.prepareReturn(isel);
                        switch (bits) {
                            else => unreachable,
                            16, 32, 64, 128 => try call.returnLiveIn(isel, res_vi.value, .v0),
                            80 => {
                                var res_hi16_it = res_vi.value.field(ty, 8, 8);
                                const res_hi16_vi = try res_hi16_it.only(isel);
                                try call.returnLiveIn(isel, res_hi16_vi.?, .r1);
                                var res_lo64_it = res_vi.value.field(ty, 0, 8);
                                const res_lo64_vi = try res_lo64_it.only(isel);
                                try call.returnLiveIn(isel, res_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishReturn(isel);

                        try call.prepareCallee(isel);
                        switch (air_tag) {
                            else => unreachable,
                            .div_trunc, .div_trunc_optimized => {
                                try isel.global_relocs.append(gpa, .{
                                    .name = switch (bits) {
                                        else => unreachable,
                                        16 => "__trunch",
                                        32 => "truncf",
                                        64 => "trunc",
                                        80 => "__truncx",
                                        128 => "truncf128",
                                    },
                                    .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                                });
                                try isel.emit(.bl(0));
                            },
                            .div_floor, .div_floor_optimized => {
                                try isel.global_relocs.append(gpa, .{
                                    .name = switch (bits) {
                                        else => unreachable,
                                        16 => "__floorh",
                                        32 => "floorf",
                                        64 => "floor",
                                        80 => "__floorx",
                                        128 => "floorf128",
                                    },
                                    .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                                });
                                try isel.emit(.bl(0));
                            },
                            .div_exact, .div_exact_optimized => {},
                        }
                        try isel.global_relocs.append(gpa, .{
                            .name = switch (bits) {
                                else => unreachable,
                                16 => "__divhf3",
                                32 => "__divsf3",
                                64 => "__divdf3",
                                80 => "__divxf3",
                                128 => "__divtf3",
                            },
                            .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                        });
                        try isel.emit(.bl(0));
                        try call.finishCallee(isel);

                        try call.prepareParams(isel);
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        switch (bits) {
                            else => unreachable,
                            16, 32, 64, 128 => {
                                try call.paramLiveOut(isel, rhs_vi, .v1);
                                try call.paramLiveOut(isel, lhs_vi, .v0);
                            },
                            80 => {
                                var rhs_hi16_it = rhs_vi.field(ty, 8, 8);
                                const rhs_hi16_vi = try rhs_hi16_it.only(isel);
                                try call.paramLiveOut(isel, rhs_hi16_vi.?, .r3);
                                var rhs_lo64_it = rhs_vi.field(ty, 0, 8);
                                const rhs_lo64_vi = try rhs_lo64_it.only(isel);
                                try call.paramLiveOut(isel, rhs_lo64_vi.?, .r2);
                                var lhs_hi16_it = lhs_vi.field(ty, 8, 8);
                                const lhs_hi16_vi = try lhs_hi16_it.only(isel);
                                try call.paramLiveOut(isel, lhs_hi16_vi.?, .r1);
                                var lhs_lo64_it = lhs_vi.field(ty, 0, 8);
                                const lhs_lo64_vi = try lhs_lo64_it.only(isel);
                                try call.paramLiveOut(isel, lhs_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishParams(isel);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .rem, .rem_optimized, .mod, .mod_optimized => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                if (!ty.isRuntimeFloat()) {
                    if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                    const int_info = ty.intInfo(zcu);
                    if (int_info.bits > 128) return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) });
                    if (int_info.bits > 64) {
                        const bits = int_info.bits;
                        const is_signed_mod = (air_tag == .mod or air_tag == .mod_optimized) and int_info.signedness == .signed;

                        try call.prepareReturn(isel);
                        var res_hi64_it = res_vi.value.field(ty, 8, 8);
                        const res_hi64_vi = try res_hi64_it.only(isel);
                        try call.returnLiveIn(isel, res_hi64_vi.?, .r1);
                        var res_lo64_it = res_vi.value.field(ty, 0, 8);
                        const res_lo64_vi = try res_lo64_it.only(isel);
                        try call.returnLiveIn(isel, res_lo64_vi.?, .r0);
                        try call.finishReturn(isel);

                        try call.prepareCallee(isel);
                        if (is_signed_mod) {
                            try isel.emit(.adc(.x1, .x1, .x3));
                            try isel.emit(.adds(.x0, .x0, .{ .register = .x2 }));
                            try isel.emit(.@"and"(.x3, .x3, .{ .register = .x4 }));
                            try isel.emit(.@"and"(.x2, .x2, .{ .register = .x4 }));
                            try isel.emit(.csel(.x4, .x5, .xzr, .ne));
                            try isel.emit(.subs(.xzr, .x4, .{ .immediate = 0 }));
                            try isel.emit(.sbfm(.x5, .x5, .{ .N = .doubleword, .immr = 63, .imms = 63 }));
                            try isel.emit(.eor(.x5, .x1, .{ .register = .x3 }));
                            try isel.emit(.orr(.x4, .x0, .{ .register = .x1 }));
                            try isel.emit(.ldp(.x2, .x3, .{ .post_index = .{ .base = .sp, .index = 16 } }));
                        }
                        try isel.global_relocs.append(gpa, .{
                            .name = switch (int_info.signedness) {
                                .signed => "__modti3",
                                .unsigned => "__umodti3",
                            },
                            .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                        });
                        try isel.emit(.bl(0));
                        if (is_signed_mod) {
                            try isel.emit(.stp(.x2, .x3, .{ .pre_index = .{ .base = .sp, .index = -16 } }));
                        }
                        if (bits < 128) switch (int_info.signedness) {
                            .signed => {
                                try isel.emit(.sbfm(.x3, .x3, .{ .N = .doubleword, .immr = 0, .imms = @intCast(bits - 64 - 1) }));
                                try isel.emit(.sbfm(.x1, .x1, .{ .N = .doubleword, .immr = 0, .imms = @intCast(bits - 64 - 1) }));
                            },
                            .unsigned => {
                                try isel.emit(.ubfm(.x3, .x3, .{ .N = .doubleword, .immr = 0, .imms = @intCast(bits - 64 - 1) }));
                                try isel.emit(.ubfm(.x1, .x1, .{ .N = .doubleword, .immr = 0, .imms = @intCast(bits - 64 - 1) }));
                            },
                        };
                        try call.finishCallee(isel);

                        try call.prepareParams(isel);
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        var rhs_hi64_it = rhs_vi.field(ty, 8, 8);
                        const rhs_hi64_vi = try rhs_hi64_it.only(isel);
                        try call.paramLiveOut(isel, rhs_hi64_vi.?, .r3);
                        var rhs_lo64_it = rhs_vi.field(ty, 0, 8);
                        const rhs_lo64_vi = try rhs_lo64_it.only(isel);
                        try call.paramLiveOut(isel, rhs_lo64_vi.?, .r2);
                        var lhs_hi64_it = lhs_vi.field(ty, 8, 8);
                        const lhs_hi64_vi = try lhs_hi64_it.only(isel);
                        try call.paramLiveOut(isel, lhs_hi64_vi.?, .r1);
                        var lhs_lo64_it = lhs_vi.field(ty, 0, 8);
                        const lhs_lo64_vi = try lhs_lo64_it.only(isel);
                        try call.paramLiveOut(isel, lhs_lo64_vi.?, .r0);
                        try call.finishParams(isel);
                        break :unused;
                    }

                    const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                    const lhs_vi = try isel.use(bin_op.lhs);
                    const rhs_vi = try isel.use(bin_op.rhs);
                    const lhs_mat = try lhs_vi.matReg(isel);
                    const rhs_mat = try rhs_vi.matReg(isel);
                    const div_ra = try isel.allocIntReg();
                    defer isel.freeReg(div_ra);
                    const rem_ra, const free_rem_ra = rem_ra: switch (air_tag) {
                        else => unreachable,
                        .rem => .{ res_ra, false },
                        .mod => switch (int_info.signedness) {
                            .signed => {
                                const rem_ra = try isel.allocIntReg();
                                errdefer isel.freeReg(rem_ra);
                                switch (int_info.bits) {
                                    else => unreachable,
                                    1...32 => {
                                        try isel.emit(.csel(res_ra.w(), rem_ra.w(), div_ra.w(), .pl));
                                        try isel.emit(.add(div_ra.w(), rem_ra.w(), .{ .register = rhs_mat.ra.w() }));
                                        try isel.emit(.ccmp(
                                            div_ra.w(),
                                            .{ .immediate = 0 },
                                            .{ .n = false, .z = false, .c = false, .v = false },
                                            .ne,
                                        ));
                                        try isel.emit(.eor(div_ra.w(), rem_ra.w(), .{ .register = rhs_mat.ra.w() }));
                                        try isel.emit(.subs(.wzr, rem_ra.w(), .{ .immediate = 0 }));
                                    },
                                    33...64 => {
                                        try isel.emit(.csel(res_ra.x(), rem_ra.x(), div_ra.x(), .pl));
                                        try isel.emit(.add(div_ra.x(), rem_ra.x(), .{ .register = rhs_mat.ra.x() }));
                                        try isel.emit(.ccmp(
                                            div_ra.x(),
                                            .{ .immediate = 0 },
                                            .{ .n = false, .z = false, .c = false, .v = false },
                                            .ne,
                                        ));
                                        try isel.emit(.eor(div_ra.x(), rem_ra.x(), .{ .register = rhs_mat.ra.x() }));
                                        try isel.emit(.subs(.xzr, rem_ra.x(), .{ .immediate = 0 }));
                                    },
                                }
                                break :rem_ra .{ rem_ra, true };
                            },
                            .unsigned => .{ res_ra, false },
                        },
                    };
                    defer if (free_rem_ra) isel.freeReg(rem_ra);
                    switch (int_info.bits) {
                        else => unreachable,
                        1...32 => {
                            try isel.emit(.msub(rem_ra.w(), div_ra.w(), rhs_mat.ra.w(), lhs_mat.ra.w()));
                            try isel.emit(switch (int_info.signedness) {
                                .signed => .sdiv(div_ra.w(), lhs_mat.ra.w(), rhs_mat.ra.w()),
                                .unsigned => .udiv(div_ra.w(), lhs_mat.ra.w(), rhs_mat.ra.w()),
                            });
                        },
                        33...64 => {
                            try isel.emit(.msub(rem_ra.x(), div_ra.x(), rhs_mat.ra.x(), lhs_mat.ra.x()));
                            try isel.emit(switch (int_info.signedness) {
                                .signed => .sdiv(div_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x()),
                                .unsigned => .udiv(div_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x()),
                            });
                        },
                    }
                    try rhs_mat.finish(isel);
                    try lhs_mat.finish(isel);
                } else {
                    const bits = ty.floatBits(isel.target);
                    switch (air_tag) {
                        else => unreachable,
                        .rem, .rem_optimized => {
                            if (!res_vi.value.isUsed(isel)) break :unused;
                            try call.prepareReturn(isel);
                            switch (bits) {
                                else => unreachable,
                                16, 32, 64, 128 => try call.returnLiveIn(isel, res_vi.value, .v0),
                                80 => {
                                    var res_hi16_it = res_vi.value.field(ty, 8, 8);
                                    const res_hi16_vi = try res_hi16_it.only(isel);
                                    try call.returnLiveIn(isel, res_hi16_vi.?, .r1);
                                    var res_lo64_it = res_vi.value.field(ty, 0, 8);
                                    const res_lo64_vi = try res_lo64_it.only(isel);
                                    try call.returnLiveIn(isel, res_lo64_vi.?, .r0);
                                },
                            }
                            try call.finishReturn(isel);
                        },
                        .mod, .mod_optimized => switch (bits) {
                            else => unreachable,
                            16, 32, 64 => {
                                const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                                try call.prepareReturn(isel);
                                const rem_ra: Register.Alias = .v0;
                                const temp1_ra: Register.Alias = .v1;
                                const temp2_ra: Register.Alias = switch (res_ra) {
                                    rem_ra, temp1_ra => .v2,
                                    else => res_ra,
                                };
                                try call.returnFill(isel, rem_ra);
                                try call.returnFill(isel, temp1_ra);
                                if (temp2_ra != res_ra) try call.returnFill(isel, temp2_ra);
                                const need_fcvt = switch (bits) {
                                    else => unreachable,
                                    16 => !isel.target.cpu.has(.aarch64, .fullfp16),
                                    32, 64 => false,
                                };
                                if (need_fcvt) try isel.emit(.fcvt(res_ra.h(), res_ra.s()));
                                try isel.emit(switch (res_ra) {
                                    rem_ra => .bif(res_ra.@"8b"(), temp2_ra.@"8b"(), temp1_ra.@"8b"()),
                                    temp1_ra => .bsl(res_ra.@"8b"(), rem_ra.@"8b"(), temp2_ra.@"8b"()),
                                    else => .bit(res_ra.@"8b"(), rem_ra.@"8b"(), temp1_ra.@"8b"()),
                                });
                                const rhs_vi = try isel.use(bin_op.rhs);
                                const rhs_mat = try rhs_vi.matReg(isel);
                                try isel.emit(bits: switch (bits) {
                                    else => unreachable,
                                    16 => if (need_fcvt)
                                        continue :bits 32
                                    else
                                        .fadd(temp2_ra.h(), rem_ra.h(), rhs_mat.ra.h()),
                                    32 => .fadd(temp2_ra.s(), rem_ra.s(), rhs_mat.ra.s()),
                                    64 => .fadd(temp2_ra.d(), rem_ra.d(), rhs_mat.ra.d()),
                                });
                                if (need_fcvt) {
                                    try isel.emit(.fcvt(rhs_mat.ra.s(), rhs_mat.ra.h()));
                                    try isel.emit(.fcvt(rem_ra.s(), rem_ra.h()));
                                }
                                try isel.emit(.orr(temp1_ra.@"8b"(), temp1_ra.@"8b"(), .{
                                    .register = temp2_ra.@"8b"(),
                                }));
                                try isel.emit(switch (bits) {
                                    else => unreachable,
                                    16 => .cmge(temp1_ra.@"4h"(), temp1_ra.@"4h"(), .zero),
                                    32 => .cmge(temp1_ra.@"2s"(), temp1_ra.@"2s"(), .zero),
                                    64 => .cmge(temp1_ra.d(), temp1_ra.d(), .zero),
                                });
                                try isel.emit(switch (bits) {
                                    else => unreachable,
                                    16 => .fcmeq(temp2_ra.h(), rem_ra.h(), .zero),
                                    32 => .fcmeq(temp2_ra.s(), rem_ra.s(), .zero),
                                    64 => .fcmeq(temp2_ra.d(), rem_ra.d(), .zero),
                                });
                                try isel.emit(.eor(temp1_ra.@"8b"(), rem_ra.@"8b"(), .{
                                    .register = rhs_mat.ra.@"8b"(),
                                }));
                                try rhs_mat.finish(isel);
                                try call.finishReturn(isel);
                            },
                            80, 128 => {
                                if (!res_vi.value.isUsed(isel)) break :unused;
                                try call.prepareReturn(isel);
                                switch (bits) {
                                    else => unreachable,
                                    16, 32, 64, 128 => try call.returnLiveIn(isel, res_vi.value, .v0),
                                    80 => {
                                        var res_hi16_it = res_vi.value.field(ty, 8, 8);
                                        const res_hi16_vi = try res_hi16_it.only(isel);
                                        try call.returnLiveIn(isel, res_hi16_vi.?, .r1);
                                        var res_lo64_it = res_vi.value.field(ty, 0, 8);
                                        const res_lo64_vi = try res_lo64_it.only(isel);
                                        try call.returnLiveIn(isel, res_lo64_vi.?, .r0);
                                    },
                                }
                                try call.finishReturn(isel);
                                const skip_label = isel.instructions.items.len;
                                try isel.global_relocs.append(gpa, .{
                                    .name = switch (bits) {
                                        else => unreachable,
                                        16 => "__addhf3",
                                        32 => "__addsf3",
                                        64 => "__adddf3",
                                        80 => "__addxf3",
                                        128 => "__addtf3",
                                    },
                                    .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                                });
                                try isel.emit(.bl(0));
                                const rhs_vi = try isel.use(bin_op.rhs);
                                switch (bits) {
                                    else => unreachable,
                                    80 => {
                                        const lhs_lo64_ra: Register.Alias = .r0;
                                        const lhs_hi16_ra: Register.Alias = .r1;
                                        const rhs_lo64_ra: Register.Alias = .r2;
                                        const rhs_hi16_ra: Register.Alias = .r3;
                                        const temp_ra: Register.Alias = .r4;
                                        var rhs_lo64_it = rhs_vi.field(ty, 0, 8);
                                        const rhs_lo64_vi = try rhs_lo64_it.only(isel);
                                        try call.paramLiveOut(isel, rhs_lo64_vi.?, rhs_lo64_ra);
                                        try isel.emit(.cbz(
                                            temp_ra.x(),
                                            @intCast((isel.instructions.items.len + 1 - skip_label) << 2),
                                        ));
                                        try isel.emit(.orr(temp_ra.x(), lhs_lo64_ra.x(), .{ .shifted_register = .{
                                            .register = lhs_hi16_ra.x(),
                                            .shift = .{ .lsl = 64 - 15 },
                                        } }));
                                        try isel.emit(.tbz(
                                            temp_ra.w(),
                                            15,
                                            @intCast((isel.instructions.items.len + 1 - skip_label) << 2),
                                        ));
                                        try isel.emit(.eor(temp_ra.w(), lhs_hi16_ra.w(), .{
                                            .register = rhs_hi16_ra.w(),
                                        }));
                                        var rhs_hi16_it = rhs_vi.field(ty, 8, 8);
                                        const rhs_hi16_vi = try rhs_hi16_it.only(isel);
                                        try call.paramLiveOut(isel, rhs_hi16_vi.?, rhs_hi16_ra);
                                    },
                                    128 => {
                                        const lhs_ra: Register.Alias = .v0;
                                        const rhs_ra: Register.Alias = .v1;
                                        const temp1_ra: Register.Alias = .r0;
                                        const temp2_ra: Register.Alias = .r1;
                                        try isel.emit(.@"b."(
                                            .pl,
                                            @intCast((isel.instructions.items.len + 1 - skip_label) << 2),
                                        ));
                                        try isel.emit(.cbz(
                                            temp1_ra.x(),
                                            @intCast((isel.instructions.items.len + 1 - skip_label) << 2),
                                        ));
                                        try isel.emit(.orr(temp1_ra.x(), temp1_ra.x(), .{ .shifted_register = .{
                                            .register = temp2_ra.x(),
                                            .shift = .{ .lsl = 1 },
                                        } }));
                                        try isel.emit(.fmov(temp1_ra.x(), .{
                                            .register = rhs_ra.d(),
                                        }));
                                        try isel.emit(.tbz(
                                            temp1_ra.x(),
                                            63,
                                            @intCast((isel.instructions.items.len + 1 - skip_label) << 2),
                                        ));
                                        try isel.emit(.eor(temp1_ra.x(), temp1_ra.x(), .{
                                            .register = temp2_ra.x(),
                                        }));
                                        try isel.emit(.fmov(temp2_ra.x(), .{
                                            .register = rhs_ra.@"d[]"(1),
                                        }));
                                        try isel.emit(.fmov(temp1_ra.x(), .{
                                            .register = lhs_ra.@"d[]"(1),
                                        }));
                                        try call.paramLiveOut(isel, rhs_vi, rhs_ra);
                                    },
                                }
                                try call.finishReturn(isel);
                            },
                        },
                    }

                    try call.prepareCallee(isel);
                    try isel.global_relocs.append(gpa, .{
                        .name = switch (bits) {
                            else => unreachable,
                            16 => "__fmodh",
                            32 => "fmodf",
                            64 => "fmod",
                            80 => "__fmodx",
                            128 => "fmodf128",
                        },
                        .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                    });
                    try isel.emit(.bl(0));
                    try call.finishCallee(isel);

                    try call.prepareParams(isel);
                    const lhs_vi = try isel.use(bin_op.lhs);
                    const rhs_vi = try isel.use(bin_op.rhs);
                    switch (bits) {
                        else => unreachable,
                        16, 32, 64, 128 => {
                            try call.paramLiveOut(isel, rhs_vi, .v1);
                            try call.paramLiveOut(isel, lhs_vi, .v0);
                        },
                        80 => {
                            var rhs_hi16_it = rhs_vi.field(ty, 8, 8);
                            const rhs_hi16_vi = try rhs_hi16_it.only(isel);
                            try call.paramLiveOut(isel, rhs_hi16_vi.?, .r3);
                            var rhs_lo64_it = rhs_vi.field(ty, 0, 8);
                            const rhs_lo64_vi = try rhs_lo64_it.only(isel);
                            try call.paramLiveOut(isel, rhs_lo64_vi.?, .r2);
                            var lhs_hi16_it = lhs_vi.field(ty, 8, 8);
                            const lhs_hi16_vi = try lhs_hi16_it.only(isel);
                            try call.paramLiveOut(isel, lhs_hi16_vi.?, .r1);
                            var lhs_lo64_it = lhs_vi.field(ty, 0, 8);
                            const lhs_lo64_vi = try lhs_lo64_it.only(isel);
                            try call.paramLiveOut(isel, lhs_lo64_vi.?, .r0);
                        },
                    }
                    try call.finishParams(isel);
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .ptr_add, .ptr_sub => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);
                const res_ra = try res_vi.value.defReg(isel) orelse break :unused;

                const ty_pl = air.data(air.inst_index).ty_pl;
                const bin_op = isel.air.extraData(Air.Bin, ty_pl.payload).data;
                const elem_size = ty_pl.ty.childType(zcu).abiSize(zcu);

                const base_vi = try isel.use(bin_op.lhs);
                var base_part_it = base_vi.field(ty_pl.ty, 0, 8);
                const base_part_vi = try base_part_it.only(isel);
                const base_part_mat = try base_part_vi.?.matReg(isel);
                const index_vi = try isel.use(bin_op.rhs);
                try isel.elemPtr(res_ra, base_part_mat.ra, switch (air_tag) {
                    else => unreachable,
                    .ptr_add => .add,
                    .ptr_sub => .sub,
                }, elem_size, index_vi);
                try base_part_mat.finish(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .max, .min => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                if (!ty.isRuntimeFloat()) {
                    if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                    const int_info = ty.intInfo(zcu);
                    if (int_info.bits > 64) return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) });

                    const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                    const lhs_vi = try isel.use(bin_op.lhs);
                    const rhs_vi = try isel.use(bin_op.rhs);
                    const lhs_mat = try lhs_vi.matReg(isel);
                    const rhs_mat = try rhs_vi.matReg(isel);
                    const cond: codegen.aarch64.encoding.ConditionCode = switch (air_tag) {
                        else => unreachable,
                        .max => switch (int_info.signedness) {
                            .signed => .ge,
                            .unsigned => .hs,
                        },
                        .min => switch (int_info.signedness) {
                            .signed => .lt,
                            .unsigned => .lo,
                        },
                    };
                    switch (int_info.bits) {
                        else => unreachable,
                        1...32 => {
                            try isel.emit(.csel(res_ra.w(), lhs_mat.ra.w(), rhs_mat.ra.w(), cond));
                            try isel.emit(.subs(.wzr, lhs_mat.ra.w(), .{ .register = rhs_mat.ra.w() }));
                        },
                        33...64 => {
                            try isel.emit(.csel(res_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x(), cond));
                            try isel.emit(.subs(.xzr, lhs_mat.ra.x(), .{ .register = rhs_mat.ra.x() }));
                        },
                    }
                    try rhs_mat.finish(isel);
                    try lhs_mat.finish(isel);
                } else switch (ty.floatBits(isel.target)) {
                    else => unreachable,
                    16, 32, 64 => |bits| {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const need_fcvt = switch (bits) {
                            else => unreachable,
                            16 => !isel.target.cpu.has(.aarch64, .fullfp16),
                            32, 64 => false,
                        };
                        if (need_fcvt) try isel.emit(.fcvt(res_ra.h(), res_ra.s()));
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        const lhs_mat = try lhs_vi.matReg(isel);
                        const rhs_mat = try rhs_vi.matReg(isel);
                        const lhs_ra = if (need_fcvt) try isel.allocVecReg() else lhs_mat.ra;
                        defer if (need_fcvt) isel.freeReg(lhs_ra);
                        const rhs_ra = if (need_fcvt) try isel.allocVecReg() else rhs_mat.ra;
                        defer if (need_fcvt) isel.freeReg(rhs_ra);
                        try isel.emit(bits: switch (bits) {
                            else => unreachable,
                            16 => if (need_fcvt) continue :bits 32 else switch (air_tag) {
                                else => unreachable,
                                .max => .fmaxnm(res_ra.h(), lhs_ra.h(), rhs_ra.h()),
                                .min => .fminnm(res_ra.h(), lhs_ra.h(), rhs_ra.h()),
                            },
                            32 => switch (air_tag) {
                                else => unreachable,
                                .max => .fmaxnm(res_ra.s(), lhs_ra.s(), rhs_ra.s()),
                                .min => .fminnm(res_ra.s(), lhs_ra.s(), rhs_ra.s()),
                            },
                            64 => switch (air_tag) {
                                else => unreachable,
                                .max => .fmaxnm(res_ra.d(), lhs_ra.d(), rhs_ra.d()),
                                .min => .fminnm(res_ra.d(), lhs_ra.d(), rhs_ra.d()),
                            },
                        });
                        if (need_fcvt) {
                            try isel.emit(.fcvt(rhs_ra.s(), rhs_mat.ra.h()));
                            try isel.emit(.fcvt(lhs_ra.s(), lhs_mat.ra.h()));
                        }
                        try rhs_mat.finish(isel);
                        try lhs_mat.finish(isel);
                    },
                    80, 128 => |bits| {
                        try call.prepareReturn(isel);
                        switch (bits) {
                            else => unreachable,
                            16, 32, 64, 128 => try call.returnLiveIn(isel, res_vi.value, .v0),
                            80 => {
                                var res_hi16_it = res_vi.value.field(ty, 8, 8);
                                const res_hi16_vi = try res_hi16_it.only(isel);
                                try call.returnLiveIn(isel, res_hi16_vi.?, .r1);
                                var res_lo64_it = res_vi.value.field(ty, 0, 8);
                                const res_lo64_vi = try res_lo64_it.only(isel);
                                try call.returnLiveIn(isel, res_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishReturn(isel);

                        try call.prepareCallee(isel);
                        try isel.global_relocs.append(gpa, .{
                            .name = switch (air_tag) {
                                else => unreachable,
                                .max => switch (bits) {
                                    else => unreachable,
                                    16 => "__fmaxh",
                                    32 => "fmaxf",
                                    64 => "fmax",
                                    80 => "__fmaxx",
                                    128 => "fmaxf128",
                                },
                                .min => switch (bits) {
                                    else => unreachable,
                                    16 => "__fminh",
                                    32 => "fminf",
                                    64 => "fmin",
                                    80 => "__fminx",
                                    128 => "fminf128",
                                },
                            },
                            .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                        });
                        try isel.emit(.bl(0));
                        try call.finishCallee(isel);

                        try call.prepareParams(isel);
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        switch (bits) {
                            else => unreachable,
                            16, 32, 64, 128 => {
                                try call.paramLiveOut(isel, rhs_vi, .v1);
                                try call.paramLiveOut(isel, lhs_vi, .v0);
                            },
                            80 => {
                                var rhs_hi16_it = rhs_vi.field(ty, 8, 8);
                                const rhs_hi16_vi = try rhs_hi16_it.only(isel);
                                try call.paramLiveOut(isel, rhs_hi16_vi.?, .r3);
                                var rhs_lo64_it = rhs_vi.field(ty, 0, 8);
                                const rhs_lo64_vi = try rhs_lo64_it.only(isel);
                                try call.paramLiveOut(isel, rhs_lo64_vi.?, .r2);
                                var lhs_hi16_it = lhs_vi.field(ty, 8, 8);
                                const lhs_hi16_vi = try lhs_hi16_it.only(isel);
                                try call.paramLiveOut(isel, lhs_hi16_vi.?, .r1);
                                var lhs_lo64_it = lhs_vi.field(ty, 0, 8);
                                const lhs_lo64_vi = try lhs_lo64_it.only(isel);
                                try call.paramLiveOut(isel, lhs_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishParams(isel);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .add_with_overflow, .sub_with_overflow => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| {
                defer res_vi.value.deref(isel);

                const ty_pl = air.data(air.inst_index).ty_pl;
                const bin_op = isel.air.extraData(Air.Bin, ty_pl.payload).data;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                const lhs_vi = try isel.use(bin_op.lhs);
                const rhs_vi = try isel.use(bin_op.rhs);
                const ty_size = lhs_vi.size(isel);
                var overflow_it = res_vi.value.field(ty_pl.ty, ty_size, 1);
                const overflow_vi = try overflow_it.only(isel);
                var wrapped_it = res_vi.value.field(ty_pl.ty, 0, ty_size);
                const wrapped_vi = try wrapped_it.only(isel);
                try wrapped_vi.?.addOrSubtract(isel, ty, lhs_vi, switch (air_tag) {
                    else => unreachable,
                    .add_with_overflow => .add,
                    .sub_with_overflow => .sub,
                }, rhs_vi, .{
                    .overflow = if (try overflow_vi.?.defReg(isel)) |overflow_ra| .{ .ra = overflow_ra } else .wrap,
                });
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .mul_with_overflow => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const ty_pl = air.data(air.inst_index).ty_pl;
                const bin_op = isel.air.extraData(Air.Bin, ty_pl.payload).data;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                const int_info = ty.intInfo(zcu);
                const ty_size = ty.abiSize(zcu);
                var overflow_it = res_vi.value.field(ty_pl.ty, ty_size, 1);
                const overflow_vi = try overflow_it.only(isel);
                const opt_ov_ra = try overflow_vi.?.defReg(isel);
                const ov_lock: RegLock = if (opt_ov_ra) |ov_ra| isel.tryLockReg(ov_ra) else .empty;
                defer ov_lock.unlock(isel);

                if (int_info.bits > 64) {
                    if (opt_ov_ra) |ov_ra| try isel.emit(.movz(ov_ra.w(), 0, .{ .lsl = .@"0" }));
                    var lo_it = res_vi.value.field(ty_pl.ty, 0, 8);
                    const lo_vi = try lo_it.only(isel);
                    const lo_ra = try lo_vi.?.defReg(isel);
                    const lo_lock: RegLock = if (lo_ra) |ra| isel.tryLockReg(ra) else .empty;
                    defer lo_lock.unlock(isel);
                    var hi_it = res_vi.value.field(ty_pl.ty, 8, ty_size - 8);
                    const hi_vi = try hi_it.only(isel);
                    const hi_ra = try hi_vi.?.defReg(isel);
                    const hi_lock: RegLock = if (hi_ra) |ra| isel.tryLockReg(ra) else .empty;
                    defer hi_lock.unlock(isel);
                    if (lo_ra != null or hi_ra != null) {
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        var lhs_lo_it = lhs_vi.field(ty, 0, 8);
                        const lhs_lo_vi = (try lhs_lo_it.only(isel)).?;
                        var lhs_hi_it = lhs_vi.field(ty, 8, ty_size - 8);
                        const lhs_hi_vi = (try lhs_hi_it.only(isel)).?;
                        var rhs_lo_it = rhs_vi.field(ty, 0, 8);
                        const rhs_lo_vi = (try rhs_lo_it.only(isel)).?;
                        var rhs_hi_it = rhs_vi.field(ty, 8, ty_size - 8);
                        const rhs_hi_vi = (try rhs_hi_it.only(isel)).?;
                        const lhs_lo_mat = try lhs_lo_vi.matReg(isel);
                        const lhs_hi_mat = try lhs_hi_vi.matReg(isel);
                        const rhs_lo_mat = try rhs_lo_vi.matReg(isel);
                        const rhs_hi_mat = try rhs_hi_vi.matReg(isel);
                        if (lo_ra) |ra| try isel.emit(.madd(ra.x(), lhs_lo_mat.ra.x(), rhs_lo_mat.ra.x(), .xzr));
                        if (hi_ra) |ra| {
                            if (int_info.bits < 128) {
                                try isel.emit(switch (int_info.signedness) {
                                    .signed => .sbfm(ra.x(), ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 0,
                                        .imms = @intCast(int_info.bits - 64 - 1),
                                    }),
                                    .unsigned => .ubfm(ra.x(), ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 0,
                                        .imms = @intCast(int_info.bits - 64 - 1),
                                    }),
                                });
                            }
                            try isel.emit(.madd(ra.x(), lhs_lo_mat.ra.x(), rhs_hi_mat.ra.x(), ra.x()));
                            try isel.emit(.madd(ra.x(), lhs_hi_mat.ra.x(), rhs_lo_mat.ra.x(), ra.x()));
                            try isel.emit(.umulh(ra.x(), lhs_lo_mat.ra.x(), rhs_lo_mat.ra.x()));
                        }
                        try rhs_hi_mat.finish(isel);
                        try rhs_lo_mat.finish(isel);
                        try lhs_hi_mat.finish(isel);
                        try lhs_lo_mat.finish(isel);
                    }
                    break :unused;
                }

                var wrapped_it = res_vi.value.field(ty_pl.ty, 0, ty_size);
                const wrapped_vi = try wrapped_it.only(isel);
                const opt_res_ra = try wrapped_vi.?.defReg(isel);
                if (opt_ov_ra == null and opt_res_ra == null) break :unused;
                const res_lock: RegLock = if (opt_res_ra) |res_ra| isel.tryLockReg(res_ra) else .empty;
                defer res_lock.unlock(isel);

                const lhs_vi = try isel.use(bin_op.lhs);
                const rhs_vi = try isel.use(bin_op.rhs);
                const lhs_mat = try lhs_vi.matReg(isel);
                const rhs_mat = try rhs_vi.matReg(isel);
                const res_ra = opt_res_ra orelse try isel.allocIntReg();
                defer if (opt_res_ra == null) isel.freeReg(res_ra);

                switch (int_info.signedness) {
                    .unsigned => switch (int_info.bits) {
                        0 => unreachable,
                        1 => {
                            if (opt_ov_ra) |ov_ra| try isel.emit(.movz(ov_ra.w(), 0, .{ .lsl = .@"0" }));
                            if (opt_res_ra != null) try isel.emit(.@"and"(res_ra.w(), lhs_mat.ra.w(), .{ .register = rhs_mat.ra.w() }));
                        },
                        2...16 => |bits| {
                            if (opt_ov_ra) |ov_ra| {
                                try isel.emit(.csinc(ov_ra.w(), .wzr, .wzr, .invert(.ne)));
                                try isel.emit(.ands(.wzr, res_ra.w(), .{ .immediate = .{
                                    .N = .word,
                                    .immr = @intCast(32 - bits),
                                    .imms = @intCast(32 - bits - 1),
                                } }));
                            }
                            if (opt_res_ra != null) try isel.emit(.ubfm(res_ra.w(), res_ra.w(), .{
                                .N = .word,
                                .immr = 0,
                                .imms = @intCast(bits - 1),
                            }));
                            try isel.emit(.madd(res_ra.w(), lhs_mat.ra.w(), rhs_mat.ra.w(), .wzr));
                        },
                        17...32 => |bits| {
                            if (opt_ov_ra) |ov_ra| {
                                try isel.emit(.csinc(ov_ra.w(), .wzr, .wzr, .invert(.ne)));
                                try isel.emit(.ands(.xzr, res_ra.x(), .{ .immediate = .{
                                    .N = .doubleword,
                                    .immr = @intCast(64 - bits),
                                    .imms = @intCast(64 - bits - 1),
                                } }));
                            }
                            if (opt_res_ra != null and bits < 32) try isel.emit(.ubfm(res_ra.w(), res_ra.w(), .{
                                .N = .word,
                                .immr = 0,
                                .imms = @intCast(bits - 1),
                            }));
                            try isel.emit(.umaddl(res_ra.x(), lhs_mat.ra.w(), rhs_mat.ra.w(), .xzr));
                        },
                        33...63 => |bits| {
                            if (opt_ov_ra) |ov_ra| {
                                const hi_ra = try isel.allocIntReg();
                                defer isel.freeReg(hi_ra);
                                try isel.emit(.csinc(ov_ra.w(), .wzr, .wzr, .invert(.ne)));
                                try isel.emit(.ands(.xzr, hi_ra.x(), .{ .register = hi_ra.x() }));
                                try isel.emit(.orr(hi_ra.x(), hi_ra.x(), .{ .shifted_register = .{
                                    .register = res_ra.x(),
                                    .shift = .{ .lsr = @intCast(bits) },
                                } }));
                                try isel.emit(.umulh(hi_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x()));
                            }
                            if (opt_res_ra != null) try isel.emit(.ubfm(res_ra.x(), res_ra.x(), .{
                                .N = .doubleword,
                                .immr = 0,
                                .imms = @intCast(bits - 1),
                            }));
                            try isel.emit(.madd(res_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x(), .xzr));
                        },
                        64 => {
                            if (opt_ov_ra) |ov_ra| {
                                const hi_ra = try isel.allocIntReg();
                                defer isel.freeReg(hi_ra);
                                try isel.emit(.csinc(ov_ra.w(), .wzr, .wzr, .invert(.ne)));
                                try isel.emit(.ands(.xzr, hi_ra.x(), .{ .register = hi_ra.x() }));
                                try isel.emit(.umulh(hi_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x()));
                            }
                            if (opt_res_ra != null) try isel.emit(.madd(res_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x(), .xzr));
                        },
                        else => unreachable,
                    },
                    .signed => switch (int_info.bits) {
                        0 => unreachable,
                        1 => {
                            if (opt_ov_ra) |ov_ra| {
                                try isel.emit(.csinc(ov_ra.w(), .wzr, .wzr, .invert(.ne)));
                                try isel.emit(.ands(.wzr, lhs_mat.ra.w(), .{ .register = rhs_mat.ra.w() }));
                            }
                            if (opt_res_ra != null) try isel.emit(.@"and"(res_ra.w(), lhs_mat.ra.w(), .{ .register = rhs_mat.ra.w() }));
                        },
                        2...32 => |bits| {
                            if (opt_ov_ra) |ov_ra| {
                                const sext_ra = try isel.allocIntReg();
                                defer isel.freeReg(sext_ra);
                                try isel.emit(.csinc(ov_ra.w(), .wzr, .wzr, .invert(.ne)));
                                try isel.emit(.subs(.xzr, res_ra.x(), .{ .register = sext_ra.x() }));
                                try isel.emit(.sbfm(sext_ra.x(), res_ra.x(), .{
                                    .N = .doubleword,
                                    .immr = 0,
                                    .imms = @intCast(bits - 1),
                                }));
                            }
                            if (opt_res_ra != null and bits < 32) try isel.emit(.sbfm(res_ra.w(), res_ra.w(), .{
                                .N = .word,
                                .immr = 0,
                                .imms = @intCast(bits - 1),
                            }));
                            try isel.emit(.smaddl(res_ra.x(), lhs_mat.ra.w(), rhs_mat.ra.w(), .xzr));
                        },
                        33...63 => |bits| {
                            if (opt_ov_ra) |ov_ra| {
                                const hi_ra = try isel.allocIntReg();
                                defer isel.freeReg(hi_ra);
                                const sign_ra = try isel.allocIntReg();
                                defer isel.freeReg(sign_ra);
                                try isel.emit(.csinc(ov_ra.w(), .wzr, .wzr, .invert(.ne)));
                                try isel.emit(.subs(.xzr, hi_ra.x(), .{ .register = sign_ra.x() }));
                                try isel.emit(.sbfm(sign_ra.x(), res_ra.x(), .{
                                    .N = .doubleword,
                                    .immr = @intCast(bits - 1),
                                    .imms = 63,
                                }));
                                try isel.emit(.extr(hi_ra.x(), hi_ra.x(), res_ra.x(), @intCast(bits)));
                                try isel.emit(.smulh(hi_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x()));
                            }
                            if (opt_res_ra != null) try isel.emit(.sbfm(res_ra.x(), res_ra.x(), .{
                                .N = .doubleword,
                                .immr = 0,
                                .imms = @intCast(bits - 1),
                            }));
                            try isel.emit(.madd(res_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x(), .xzr));
                        },
                        64 => {
                            if (opt_ov_ra) |ov_ra| {
                                const hi_ra = try isel.allocIntReg();
                                defer isel.freeReg(hi_ra);
                                try isel.emit(.csinc(ov_ra.w(), .wzr, .wzr, .invert(.ne)));
                                try isel.emit(.subs(.xzr, hi_ra.x(), .{ .shifted_register = .{
                                    .register = res_ra.x(),
                                    .shift = .{ .asr = 63 },
                                } }));
                                try isel.emit(.smulh(hi_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x()));
                            }
                            try isel.emit(.madd(res_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x(), .xzr));
                        },
                        else => unreachable,
                    },
                }
                try rhs_mat.finish(isel);
                try lhs_mat.finish(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .shl_with_overflow => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const ty_pl = air.data(air.inst_index).ty_pl;
                const bin_op = isel.air.extraData(Air.Bin, ty_pl.payload).data;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                const int_info = ty.intInfo(zcu);
                if (int_info.bits > 64) return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) });
                const ty_size = ty.abiSize(zcu);
                var overflow_it = res_vi.value.field(ty_pl.ty, ty_size, 1);
                const overflow_vi = try overflow_it.only(isel);
                const opt_ov_ra = try overflow_vi.?.defReg(isel);
                const ov_lock: RegLock = if (opt_ov_ra) |ov_ra| isel.tryLockReg(ov_ra) else .empty;
                defer ov_lock.unlock(isel);

                var wrapped_it = res_vi.value.field(ty_pl.ty, 0, ty_size);
                const wrapped_vi = try wrapped_it.only(isel);
                const opt_res_ra = try wrapped_vi.?.defReg(isel);
                if (opt_ov_ra == null and opt_res_ra == null) break :unused;
                const res_lock: RegLock = if (opt_res_ra) |res_ra| isel.tryLockReg(res_ra) else .empty;
                defer res_lock.unlock(isel);

                const lhs_vi = try isel.use(bin_op.lhs);
                const rhs_vi = try isel.use(bin_op.rhs);
                const lhs_mat = try lhs_vi.matReg(isel);
                const rhs_mat = try rhs_vi.matReg(isel);
                const res_ra = opt_res_ra orelse try isel.allocIntReg();
                defer if (opt_res_ra == null) isel.freeReg(res_ra);

                const bits = int_info.bits;
                if (opt_ov_ra) |ov_ra| {
                    const unshifted_ra = try isel.allocIntReg();
                    defer isel.freeReg(unshifted_ra);
                    try isel.emit(.csinc(ov_ra.w(), .wzr, .wzr, .invert(.ne)));
                    try isel.emit(switch (bits) {
                        1...32 => .subs(.wzr, unshifted_ra.w(), .{ .register = lhs_mat.ra.w() }),
                        33...64 => .subs(.xzr, unshifted_ra.x(), .{ .register = lhs_mat.ra.x() }),
                        else => unreachable,
                    });
                    try isel.emit(switch (bits) {
                        1...32 => switch (int_info.signedness) {
                            .signed => .asrv(unshifted_ra.w(), res_ra.w(), rhs_mat.ra.w()),
                            .unsigned => .lsrv(unshifted_ra.w(), res_ra.w(), rhs_mat.ra.w()),
                        },
                        33...64 => switch (int_info.signedness) {
                            .signed => .asrv(unshifted_ra.x(), res_ra.x(), rhs_mat.ra.x()),
                            .unsigned => .lsrv(unshifted_ra.x(), res_ra.x(), rhs_mat.ra.x()),
                        },
                        else => unreachable,
                    });
                }
                switch (bits) {
                    1...31 => try isel.emit(switch (int_info.signedness) {
                        .signed => .sbfm(res_ra.w(), res_ra.w(), .{
                            .N = .word,
                            .immr = 0,
                            .imms = @intCast(bits - 1),
                        }),
                        .unsigned => .ubfm(res_ra.w(), res_ra.w(), .{
                            .N = .word,
                            .immr = 0,
                            .imms = @intCast(bits - 1),
                        }),
                    }),
                    32 => {},
                    33...63 => try isel.emit(switch (int_info.signedness) {
                        .signed => .sbfm(res_ra.x(), res_ra.x(), .{
                            .N = .doubleword,
                            .immr = 0,
                            .imms = @intCast(bits - 1),
                        }),
                        .unsigned => .ubfm(res_ra.x(), res_ra.x(), .{
                            .N = .doubleword,
                            .immr = 0,
                            .imms = @intCast(bits - 1),
                        }),
                    }),
                    64 => {},
                    else => unreachable,
                }
                try isel.emit(switch (bits) {
                    1...32 => .lslv(res_ra.w(), lhs_mat.ra.w(), rhs_mat.ra.w()),
                    33...64 => .lslv(res_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x()),
                    else => unreachable,
                });
                try rhs_mat.finish(isel);
                try lhs_mat.finish(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .alloc, .ret_ptr => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |ptr_vi| unused: {
                defer ptr_vi.value.deref(isel);
                switch (air_tag) {
                    else => unreachable,
                    .alloc => {},
                    .ret_ptr => if (isel.live_values.get(Block.main)) |ret_vi| switch (ret_vi.parent(isel)) {
                        .unallocated, .stack_slot => {},
                        .value, .constant => unreachable,
                        .address => break :unused,
                    },
                }
                const ptr_ra = try ptr_vi.value.defReg(isel) orelse break :unused;

                const ty = air.data(air.inst_index).ty;
                const slot_size = ty.childType(zcu).abiSize(zcu);
                const slot_align = ty.ptrAlignment(zcu);
                const slot_offset = slot_align.forward(isel.stack_size);
                isel.stack_size = @intCast(slot_offset + slot_size);
                const lo12: u12 = @truncate(slot_offset >> 0);
                const hi12: u12 = @intCast(slot_offset >> 12);
                if (hi12 > 0) try isel.emit(.add(
                    ptr_ra.x(),
                    if (lo12 > 0) ptr_ra.x() else .sp,
                    .{ .shifted_immediate = .{ .immediate = hi12, .lsl = .@"12" } },
                ));
                if (lo12 > 0 or hi12 == 0) try isel.emit(.add(ptr_ra.x(), .sp, .{ .immediate = lo12 }));
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .inferred_alloc, .inferred_alloc_comptime => unreachable,
        .assembly => {
            const ty_pl = air.data(air.inst_index).ty_pl;
            const unwrapped_asm = isel.air.unwrapAsm(air.inst_index);
            const inputs = unwrapped_asm.inputs;

            var as: codegen.aarch64.Assemble = .{
                .source = undefined,
                .operands = .empty,
            };
            defer as.operands.deinit(gpa);

            var it = unwrapped_asm.iterateOutputs();
            while (it.next()) |output| {
                const constraint = output.constraint;
                const name = output.name;

                switch (output.operand) {
                    else => return isel.fail("invalid constraint: '{s}'", .{constraint}),
                    .none => if (std.mem.startsWith(u8, constraint, "={") and std.mem.endsWith(u8, constraint, "}")) {
                        const output_reg = Register.parse(constraint["={".len .. constraint.len - "}".len]) orelse
                            return isel.fail("invalid constraint: '{s}'", .{constraint});
                        const output_ra = output_reg.alias;
                        if (isel.live_values.fetchRemove(air.inst_index)) |output_vi| {
                            defer output_vi.value.deref(isel);
                            try output_vi.value.defLiveIn(isel, output_reg.alias, comptime &.initFill(.free));
                            isel.freeReg(output_ra);
                        }
                        if (!std.mem.eql(u8, name, "_")) {
                            const operand_gop = try as.operands.getOrPut(gpa, name);
                            if (operand_gop.found_existing) return isel.fail("duplicate output name: '{s}'", .{name});
                            operand_gop.value_ptr.* = .{ .register = switch (ty_pl.ty.abiSize(zcu)) {
                                0 => unreachable,
                                1...4 => output_ra.w(),
                                5...8 => output_ra.x(),
                                else => return isel.fail("too big output type: '{f}'", .{isel.fmtType(ty_pl.ty)}),
                            } };
                        }
                    } else if (std.mem.eql(u8, constraint, "=r")) {
                        const output_ra = if (isel.live_values.fetchRemove(air.inst_index)) |output_vi| output_ra: {
                            defer output_vi.value.deref(isel);
                            break :output_ra try output_vi.value.defReg(isel) orelse try isel.allocIntReg();
                        } else try isel.allocIntReg();
                        if (!std.mem.eql(u8, name, "_")) {
                            const operand_gop = try as.operands.getOrPut(gpa, name);
                            if (operand_gop.found_existing) return isel.fail("duplicate output name: '{s}'", .{name});
                            operand_gop.value_ptr.* = .{ .register = switch (ty_pl.ty.abiSize(zcu)) {
                                0 => unreachable,
                                1...4 => output_ra.w(),
                                5...8 => output_ra.x(),
                                else => return isel.fail("too big output type: '{f}'", .{isel.fmtType(ty_pl.ty)}),
                            } };
                        }
                    } else return isel.fail("invalid constraint: '{s}'", .{constraint}),
                }
            }

            const input_mats = try gpa.alloc(Value.Materialize, inputs.len);
            var index: u32 = 0;
            defer gpa.free(input_mats);
            it = unwrapped_asm.iterateInputs();
            while (it.next()) |input| : (index += 1) {
                const constraint = input.constraint;
                const name = input.name;

                if (std.mem.startsWith(u8, constraint, "{") and std.mem.endsWith(u8, constraint, "}")) {
                    const input_reg = Register.parse(constraint["{".len .. constraint.len - "}".len]) orelse
                        return isel.fail("invalid constraint: '{s}'", .{constraint});
                    input_mats[index] = .{ .vi = try isel.use(input.operand), .ra = input_reg.alias };
                    if (!std.mem.eql(u8, name, "_")) {
                        const operand_gop = try as.operands.getOrPut(gpa, name);
                        if (operand_gop.found_existing) return isel.fail("duplicate input name: '{s}'", .{name});
                        const input_ty = isel.air.typeOf(input.operand, ip);
                        operand_gop.value_ptr.* = .{ .register = switch (input_ty.abiSize(zcu)) {
                            0 => unreachable,
                            1...4 => input_reg.alias.w(),
                            5...8 => input_reg.alias.x(),
                            else => return isel.fail("too big input type: '{f}'", .{
                                isel.fmtType(isel.air.typeOf(input.operand, ip)),
                            }),
                        } };
                    }
                } else if (std.mem.eql(u8, constraint, "r")) {
                    const input_vi = try isel.use(input.operand);
                    input_mats[index] = try input_vi.matReg(isel);
                    if (!std.mem.eql(u8, name, "_")) {
                        const operand_gop = try as.operands.getOrPut(gpa, name);
                        if (operand_gop.found_existing) return isel.fail("duplicate input name: '{s}'", .{name});
                        operand_gop.value_ptr.* = .{ .register = switch (input_vi.size(isel)) {
                            0 => unreachable,
                            1...4 => input_mats[index].ra.w(),
                            5...8 => input_mats[index].ra.x(),
                            else => return isel.fail("too big input type: '{f}'", .{
                                isel.fmtType(isel.air.typeOf(input.operand, ip)),
                            }),
                        } };
                    }
                } else if (std.mem.eql(u8, name, "_")) {
                    input_mats[index].vi = try isel.use(input.operand);
                } else return isel.fail("invalid constraint: '{s}'", .{constraint});
            }

            const clobbers_val: Constant = .fromInterned(unwrapped_asm.clobbers);
            const clobbers_ty = clobbers_val.typeOf(zcu);
            var clobbers_bigint_buf: Constant.BigIntSpace = undefined;
            const clobbers_bigint = clobbers_val.toBigInt(&clobbers_bigint_buf, zcu);
            for (0..clobbers_ty.structFieldCount(zcu)) |field_index| {
                assert(clobbers_ty.fieldType(field_index, zcu).toIntern() == .bool_type);
                const limb_bits = @bitSizeOf(std.math.big.Limb);
                if (field_index / limb_bits >= clobbers_bigint.limbs.len) continue; // field is false
                switch (@as(u1, @truncate(clobbers_bigint.limbs[field_index / limb_bits] >> @intCast(field_index % limb_bits)))) {
                    0 => continue, // field is false
                    1 => {}, // field is true
                }
                const clobber_name = clobbers_ty.structFieldName(field_index, zcu).toSlice(ip).?;
                if (std.mem.eql(u8, clobber_name, "memory")) continue;
                if (std.mem.eql(u8, clobber_name, "nzcv")) continue;
                const clobber_reg = Register.parse(clobber_name) orelse
                    return isel.fail("unable to parse clobber: '{s}'", .{clobber_name});
                const live_vi = isel.live_registers.getPtr(clobber_reg.alias);
                switch (live_vi.*) {
                    _ => {},
                    .allocating => return isel.fail("clobbered twice: '{s}'", .{clobber_name}),
                    .free => live_vi.* = .allocating,
                }
            }
            for (0..clobbers_ty.structFieldCount(zcu)) |field_index| {
                const limb_bits = @bitSizeOf(std.math.big.Limb);
                if (field_index / limb_bits >= clobbers_bigint.limbs.len) continue; // field is false
                switch (@as(u1, @truncate(clobbers_bigint.limbs[field_index / limb_bits] >> @intCast(field_index % limb_bits)))) {
                    0 => continue, // field is false
                    1 => {}, // field is true
                }
                const clobber_name = clobbers_ty.structFieldName(field_index, zcu).toSlice(ip).?;
                if (std.mem.eql(u8, clobber_name, "memory")) continue;
                if (std.mem.eql(u8, clobber_name, "nzcv")) continue;
                const clobber_ra = Register.parse(clobber_name).?.alias;
                const live_vi = isel.live_registers.getPtr(clobber_ra);
                switch (live_vi.*) {
                    _ => {
                        if (!try isel.fill(clobber_ra))
                            return isel.fail("unable to clobber: '{s}'", .{clobber_name});
                        assert(live_vi.* == .free);
                        live_vi.* = .allocating;
                    },
                    .allocating => {},
                    .free => unreachable,
                }
            }

            as.source = unwrapped_asm.source;
            const asm_start = isel.instructions.items.len;
            while (as.nextInstruction() catch |err| switch (err) {
                error.InvalidSyntax => {
                    const remaining_source = std.mem.span(as.source);
                    return isel.fail("unable to assemble: '{s}'", .{std.mem.trim(
                        u8,
                        as.source[0 .. std.mem.findScalar(u8, remaining_source, '\n') orelse remaining_source.len],
                        &std.ascii.whitespace,
                    )});
                },
            }) |instruction| try isel.emit(instruction);
            std.mem.reverse(codegen.aarch64.encoding.Instruction, isel.instructions.items[asm_start..]);

            it = unwrapped_asm.iterateInputs();
            index = 0;
            while (it.next()) |input| : (index += 1) {
                const constraint = input.constraint;
                const name = input.name;

                if (std.mem.startsWith(u8, constraint, "{") and std.mem.endsWith(u8, constraint, "}")) {
                    try input_mats[index].vi.liveOut(isel, input_mats[index].ra);
                } else if (std.mem.eql(u8, constraint, "r")) {
                    try input_mats[index].finish(isel);
                } else if (std.mem.eql(u8, name, "_")) {
                    try input_mats[index].vi.mat(isel);
                } else unreachable;
            }

            for (0..clobbers_ty.structFieldCount(zcu)) |field_index| {
                const limb_bits = @bitSizeOf(std.math.big.Limb);
                if (field_index / limb_bits >= clobbers_bigint.limbs.len) continue; // field is false
                switch (@as(u1, @truncate(clobbers_bigint.limbs[field_index / limb_bits] >> @intCast(field_index % limb_bits)))) {
                    0 => continue, // field is false
                    1 => {}, // field is true
                }
                const clobber_name = clobbers_ty.structFieldName(field_index, zcu).toSlice(ip).?;
                if (std.mem.eql(u8, clobber_name, "memory")) continue;
                if (std.mem.eql(u8, clobber_name, "cc")) continue;
                if (std.mem.eql(u8, clobber_name, "nzcv")) continue;
                isel.freeReg(Register.parse(clobber_name).?.alias);
            }

            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .bit_and, .bit_or, .xor => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                const int_info: std.lang.Type.Int = if (ty.toIntern() == .bool_type)
                    .{ .signedness = .unsigned, .bits = 1 }
                else if (ty.isAbiInt(zcu))
                    ty.intInfo(zcu)
                else if (ty.zigTypeTag(zcu) == .vector)
                    .{ .signedness = .unsigned, .bits = @intCast(ty.bitSize(zcu)) }
                else
                    return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                if (int_info.bits > 64 * Value.max_parts) return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) });

                const lhs_vi = try isel.use(bin_op.lhs);
                const rhs_vi = try isel.use(bin_op.rhs);
                var offset = res_vi.value.size(isel);
                while (offset > 0) {
                    const size = @min(offset, 8);
                    offset -= size;
                    var res_part_it = res_vi.value.field(ty, offset, size);
                    while (try res_part_it.next(isel)) |res_part| {
                        const res_part_ra = try res_part.vi.defReg(isel) orelse continue;
                        const part_offset = offset + res_part.offset;
                        const part_size = res_part.vi.size(isel);
                        var lhs_part_it = lhs_vi.field(ty, part_offset, part_size);
                        const lhs_part_vi = try lhs_part_it.only(isel);
                        const lhs_part_mat = try lhs_part_vi.?.matReg(isel);
                        var rhs_part_it = rhs_vi.field(ty, part_offset, part_size);
                        const rhs_part_vi = try rhs_part_it.only(isel);
                        const rhs_part_mat = try rhs_part_vi.?.matReg(isel);
                        try isel.emit(switch (air_tag) {
                            else => unreachable,
                            .bit_and => switch (part_size) {
                                else => unreachable,
                                1, 2, 4 => .@"and"(res_part_ra.w(), lhs_part_mat.ra.w(), .{ .register = rhs_part_mat.ra.w() }),
                                8 => .@"and"(res_part_ra.x(), lhs_part_mat.ra.x(), .{ .register = rhs_part_mat.ra.x() }),
                            },
                            .bit_or => switch (part_size) {
                                else => unreachable,
                                1, 2, 4 => .orr(res_part_ra.w(), lhs_part_mat.ra.w(), .{ .register = rhs_part_mat.ra.w() }),
                                8 => .orr(res_part_ra.x(), lhs_part_mat.ra.x(), .{ .register = rhs_part_mat.ra.x() }),
                            },
                            .xor => switch (part_size) {
                                else => unreachable,
                                1, 2, 4 => .eor(res_part_ra.w(), lhs_part_mat.ra.w(), .{ .register = rhs_part_mat.ra.w() }),
                                8 => .eor(res_part_ra.x(), lhs_part_mat.ra.x(), .{ .register = rhs_part_mat.ra.x() }),
                            },
                        });
                        try rhs_part_mat.finish(isel);
                        try lhs_part_mat.finish(isel);
                    }
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .shr, .shr_exact, .shl, .shl_exact => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                const int_info = ty.intInfo(zcu);
                switch (int_info.bits) {
                    0 => unreachable,
                    1...64 => |bits| {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        switch (air_tag) {
                            else => unreachable,
                            .shr, .shr_exact, .shl_exact => {},
                            .shl => switch (bits) {
                                else => unreachable,
                                1...31 => try isel.emit(switch (int_info.signedness) {
                                    .signed => .sbfm(res_ra.w(), res_ra.w(), .{
                                        .N = .word,
                                        .immr = 0,
                                        .imms = @intCast(bits - 1),
                                    }),
                                    .unsigned => .ubfm(res_ra.w(), res_ra.w(), .{
                                        .N = .word,
                                        .immr = 0,
                                        .imms = @intCast(bits - 1),
                                    }),
                                }),
                                32 => {},
                                33...63 => try isel.emit(switch (int_info.signedness) {
                                    .signed => .sbfm(res_ra.x(), res_ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 0,
                                        .imms = @intCast(bits - 1),
                                    }),
                                    .unsigned => .ubfm(res_ra.x(), res_ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 0,
                                        .imms = @intCast(bits - 1),
                                    }),
                                }),
                                64 => {},
                            },
                        }

                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        const lhs_mat = try lhs_vi.matReg(isel);
                        const rhs_mat = try rhs_vi.matReg(isel);
                        try isel.emit(switch (air_tag) {
                            else => unreachable,
                            .shr, .shr_exact => switch (bits) {
                                else => unreachable,
                                1...32 => switch (int_info.signedness) {
                                    .signed => .asrv(res_ra.w(), lhs_mat.ra.w(), rhs_mat.ra.w()),
                                    .unsigned => .lsrv(res_ra.w(), lhs_mat.ra.w(), rhs_mat.ra.w()),
                                },
                                33...64 => switch (int_info.signedness) {
                                    .signed => .asrv(res_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x()),
                                    .unsigned => .lsrv(res_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x()),
                                },
                            },
                            .shl, .shl_exact => switch (bits) {
                                else => unreachable,
                                1...32 => .lslv(res_ra.w(), lhs_mat.ra.w(), rhs_mat.ra.w()),
                                33...64 => .lslv(res_ra.x(), lhs_mat.ra.x(), rhs_mat.ra.x()),
                            },
                        });
                        try rhs_mat.finish(isel);
                        try lhs_mat.finish(isel);
                    },
                    65...128 => |bits| {
                        var res_hi64_it = res_vi.value.field(ty, 8, 8);
                        const res_hi64_vi = try res_hi64_it.only(isel);
                        const res_hi64_ra = try res_hi64_vi.?.defReg(isel);
                        var res_lo64_it = res_vi.value.field(ty, 0, 8);
                        const res_lo64_vi = try res_lo64_it.only(isel);
                        const res_lo64_ra = res_lo64_ra: {
                            const res_hi64_lock: RegLock = if (res_hi64_ra) |ra| isel.tryLockReg(ra) else .empty;
                            defer res_hi64_lock.unlock(isel);
                            break :res_lo64_ra try res_lo64_vi.?.defReg(isel);
                        };
                        if (res_hi64_ra == null and res_lo64_ra == null) break :unused;
                        if (res_hi64_ra) |res_ra| switch (air_tag) {
                            else => unreachable,
                            .shr, .shr_exact, .shl_exact => {},
                            .shl => switch (bits) {
                                else => unreachable,
                                65...127 => try isel.emit(switch (int_info.signedness) {
                                    .signed => .sbfm(res_ra.x(), res_ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 0,
                                        .imms = @intCast(bits - 64 - 1),
                                    }),
                                    .unsigned => .ubfm(res_ra.x(), res_ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 0,
                                        .imms = @intCast(bits - 64 - 1),
                                    }),
                                }),
                                128 => {},
                            },
                        };

                        const lhs_vi = try isel.use(bin_op.lhs);
                        const lhs_hi64_mat = lhs_hi64_mat: {
                            const res_lock: RegLock = switch (air_tag) {
                                else => unreachable,
                                .shr, .shr_exact => switch (int_info.signedness) {
                                    .signed => if (res_lo64_ra) |res_ra| isel.lockReg(res_ra) else .empty,
                                    .unsigned => .empty,
                                },
                                .shl, .shl_exact => .empty,
                            };
                            defer res_lock.unlock(isel);
                            var lhs_hi64_it = lhs_vi.field(ty, 8, 8);
                            const lhs_hi64_vi = try lhs_hi64_it.only(isel);
                            break :lhs_hi64_mat try lhs_hi64_vi.?.matReg(isel);
                        };
                        var lhs_lo64_it = lhs_vi.field(ty, 0, 8);
                        const lhs_lo64_vi = try lhs_lo64_it.only(isel);
                        const lhs_lo64_mat = try lhs_lo64_vi.?.matReg(isel);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        const rhs_mat = try rhs_vi.matReg(isel);
                        const lo64_ra = lo64_ra: {
                            const res_lock: RegLock = switch (air_tag) {
                                else => unreachable,
                                .shr, .shr_exact => switch (int_info.signedness) {
                                    .signed => if (res_lo64_ra) |res_ra| isel.tryLockReg(res_ra) else .empty,
                                    .unsigned => .empty,
                                },
                                .shl, .shl_exact => if (res_hi64_ra) |res_ra| isel.tryLockReg(res_ra) else .empty,
                            };
                            defer res_lock.unlock(isel);
                            break :lo64_ra try isel.allocIntReg();
                        };
                        defer isel.freeReg(lo64_ra);
                        const hi64_ra = hi64_ra: {
                            const res_lock: RegLock = switch (air_tag) {
                                else => unreachable,
                                .shr, .shr_exact => if (res_lo64_ra) |res_ra| isel.tryLockReg(res_ra) else .empty,
                                .shl, .shl_exact => .empty,
                            };
                            defer res_lock.unlock(isel);
                            break :hi64_ra try isel.allocIntReg();
                        };
                        defer isel.freeReg(hi64_ra);
                        switch (air_tag) {
                            else => unreachable,
                            .shr, .shr_exact => {
                                if (res_hi64_ra) |res_ra| switch (int_info.signedness) {
                                    .signed => {
                                        try isel.emit(.csel(res_ra.x(), hi64_ra.x(), lo64_ra.x(), .eq));
                                        try isel.emit(.sbfm(lo64_ra.x(), lhs_hi64_mat.ra.x(), .{
                                            .N = .doubleword,
                                            .immr = @intCast(bits - 64 - 1),
                                            .imms = @intCast(bits - 64 - 1),
                                        }));
                                    },
                                    .unsigned => try isel.emit(.csel(res_ra.x(), hi64_ra.x(), .xzr, .eq)),
                                };
                                if (res_lo64_ra) |res_ra| try isel.emit(.csel(res_ra.x(), lo64_ra.x(), hi64_ra.x(), .eq));
                                switch (int_info.signedness) {
                                    .signed => try isel.emit(.asrv(hi64_ra.x(), lhs_hi64_mat.ra.x(), rhs_mat.ra.x())),
                                    .unsigned => try isel.emit(.lsrv(hi64_ra.x(), lhs_hi64_mat.ra.x(), rhs_mat.ra.x())),
                                }
                            },
                            .shl, .shl_exact => {
                                if (res_lo64_ra) |res_ra| try isel.emit(.csel(res_ra.x(), lo64_ra.x(), .xzr, .eq));
                                if (res_hi64_ra) |res_ra| try isel.emit(.csel(res_ra.x(), hi64_ra.x(), lo64_ra.x(), .eq));
                                try isel.emit(.lslv(lo64_ra.x(), lhs_lo64_mat.ra.x(), rhs_mat.ra.x()));
                            },
                        }
                        try isel.emit(.ands(.wzr, rhs_mat.ra.w(), .{ .immediate = .{ .N = .word, .immr = 32 - 6, .imms = 0 } }));
                        switch (air_tag) {
                            else => unreachable,
                            .shr, .shr_exact => if (res_lo64_ra) |_| {
                                try isel.emit(.orr(
                                    lo64_ra.x(),
                                    lo64_ra.x(),
                                    .{ .shifted_register = .{ .register = hi64_ra.x(), .shift = .{ .lsl = 1 } } },
                                ));
                                try isel.emit(.lslv(hi64_ra.x(), lhs_hi64_mat.ra.x(), hi64_ra.x()));
                                try isel.emit(.lsrv(lo64_ra.x(), lhs_lo64_mat.ra.x(), rhs_mat.ra.x()));
                                try isel.emit(.orn(hi64_ra.w(), .wzr, .{ .register = rhs_mat.ra.w() }));
                            },
                            .shl, .shl_exact => if (res_hi64_ra) |_| {
                                try isel.emit(.orr(
                                    hi64_ra.x(),
                                    hi64_ra.x(),
                                    .{ .shifted_register = .{ .register = lo64_ra.x(), .shift = .{ .lsr = 1 } } },
                                ));
                                try isel.emit(.lsrv(lo64_ra.x(), lhs_lo64_mat.ra.x(), lo64_ra.x()));
                                try isel.emit(.lslv(hi64_ra.x(), lhs_hi64_mat.ra.x(), rhs_mat.ra.x()));
                                try isel.emit(.orn(lo64_ra.w(), .wzr, .{ .register = rhs_mat.ra.w() }));
                            },
                        }
                        try rhs_mat.finish(isel);
                        try lhs_lo64_mat.finish(isel);
                        try lhs_hi64_mat.finish(isel);
                        break :unused;
                    },
                    else => return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) }),
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .not => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| {
                defer res_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const ty = ty_op.ty;
                const int_info: std.lang.Type.Int = int_info: {
                    if (ty_op.ty.ip_index == .bool_type) break :int_info .{ .signedness = .unsigned, .bits = 1 };
                    if (ty.zigTypeTag(zcu) == .vector) break :int_info .{ .signedness = .unsigned, .bits = @intCast(ty.bitSize(zcu)) };
                    if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                    break :int_info ty.intInfo(zcu);
                };
                if (int_info.bits > 64 * Value.max_parts) return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) });

                const src_vi = try isel.use(ty_op.operand);
                var offset = res_vi.value.size(isel);
                while (offset > 0) {
                    const size = @min(offset, 8);
                    offset -= size;
                    var res_part_it = res_vi.value.field(ty, offset, size);
                    const res_part_vi = try res_part_it.only(isel);
                    const res_part_ra = try res_part_vi.?.defReg(isel) orelse continue;
                    var src_part_it = src_vi.field(ty, offset, size);
                    const src_part_vi = try src_part_it.only(isel);
                    const src_part_mat = try src_part_vi.?.matReg(isel);
                    try isel.emit(switch (int_info.signedness) {
                        .signed => switch (size) {
                            else => unreachable,
                            1, 2, 4 => .orn(res_part_ra.w(), .wzr, .{ .register = src_part_mat.ra.w() }),
                            8 => .orn(res_part_ra.x(), .xzr, .{ .register = src_part_mat.ra.x() }),
                        },
                        .unsigned => switch (@min(int_info.bits - 8 * offset, 64)) {
                            else => unreachable,
                            1...31 => |bits| .eor(res_part_ra.w(), src_part_mat.ra.w(), .{ .immediate = .{
                                .N = .word,
                                .immr = 0,
                                .imms = @intCast(bits - 1),
                            } }),
                            32 => .orn(res_part_ra.w(), .wzr, .{ .register = src_part_mat.ra.w() }),
                            33...63 => |bits| .eor(res_part_ra.x(), src_part_mat.ra.x(), .{ .immediate = .{
                                .N = .doubleword,
                                .immr = 0,
                                .imms = @intCast(bits - 1),
                            } }),
                            64 => .orn(res_part_ra.x(), .xzr, .{ .register = src_part_mat.ra.x() }),
                        },
                    });
                    try src_part_mat.finish(isel);
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .bit_cast,
        .bit_cast_safe, // TODO safety check
        .ptr_cast,
        .ptr_from_int,
        .int_from_ptr,
        .error_cast,
        .error_from_int,
        .int_from_error,
        .union_from_enum,
        => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                const dst_ty = ty_op.ty;
                const dst_tag = dst_ty.zigTypeTag(zcu);
                const src_ty = isel.air.typeOf(ty_op.operand, ip);
                const src_tag = src_ty.zigTypeTag(zcu);
                if (dst_ty.isAbiInt(zcu) and (src_tag == .bool or src_ty.isAbiInt(zcu))) {
                    const dst_int_info = dst_ty.intInfo(zcu);
                    const src_int_info: std.lang.Type.Int = if (src_tag == .bool) .{ .signedness = undefined, .bits = 1 } else src_ty.intInfo(zcu);
                    assert(dst_int_info.bits == src_int_info.bits);
                    if (dst_tag != .@"struct" and src_tag != .@"struct" and src_tag != .bool and dst_int_info.signedness == src_int_info.signedness) {
                        try dst_vi.value.move(isel, ty_op.operand);
                    } else switch (dst_int_info.bits) {
                        0 => unreachable,
                        1...31 => |dst_bits| {
                            const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                            const src_vi = try isel.use(ty_op.operand);
                            const src_mat = try src_vi.matReg(isel);
                            try isel.emit(switch (dst_int_info.signedness) {
                                .signed => .sbfm(dst_ra.w(), src_mat.ra.w(), .{
                                    .N = .word,
                                    .immr = 0,
                                    .imms = @intCast(dst_bits - 1),
                                }),
                                .unsigned => .ubfm(dst_ra.w(), src_mat.ra.w(), .{
                                    .N = .word,
                                    .immr = 0,
                                    .imms = @intCast(dst_bits - 1),
                                }),
                            });
                            try src_mat.finish(isel);
                        },
                        32 => try dst_vi.value.move(isel, ty_op.operand),
                        33...63 => |dst_bits| {
                            const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                            const src_vi = try isel.use(ty_op.operand);
                            const src_mat = try src_vi.matReg(isel);
                            try isel.emit(switch (dst_int_info.signedness) {
                                .signed => .sbfm(dst_ra.x(), src_mat.ra.x(), .{
                                    .N = .doubleword,
                                    .immr = 0,
                                    .imms = @intCast(dst_bits - 1),
                                }),
                                .unsigned => .ubfm(dst_ra.x(), src_mat.ra.x(), .{
                                    .N = .doubleword,
                                    .immr = 0,
                                    .imms = @intCast(dst_bits - 1),
                                }),
                            });
                            try src_mat.finish(isel);
                        },
                        64 => try dst_vi.value.move(isel, ty_op.operand),
                        65...127 => |dst_bits| {
                            const src_vi = try isel.use(ty_op.operand);
                            var dst_hi64_it = dst_vi.value.field(dst_ty, 8, 8);
                            const dst_hi64_vi = try dst_hi64_it.only(isel);
                            if (try dst_hi64_vi.?.defReg(isel)) |dst_hi64_ra| {
                                var src_hi64_it = src_vi.field(src_ty, 8, 8);
                                const src_hi64_vi = try src_hi64_it.only(isel);
                                const src_hi64_mat = try src_hi64_vi.?.matReg(isel);
                                try isel.emit(switch (dst_int_info.signedness) {
                                    .signed => .sbfm(dst_hi64_ra.x(), src_hi64_mat.ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 0,
                                        .imms = @intCast(dst_bits - 64 - 1),
                                    }),
                                    .unsigned => .ubfm(dst_hi64_ra.x(), src_hi64_mat.ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 0,
                                        .imms = @intCast(dst_bits - 64 - 1),
                                    }),
                                });
                                try src_hi64_mat.finish(isel);
                            }
                            var dst_lo64_it = dst_vi.value.field(dst_ty, 0, 8);
                            const dst_lo64_vi = try dst_lo64_it.only(isel);
                            if (try dst_lo64_vi.?.defReg(isel)) |dst_lo64_ra| {
                                var src_lo64_it = src_vi.field(src_ty, 0, 8);
                                const src_lo64_vi = try src_lo64_it.only(isel);
                                try src_lo64_vi.?.liveOut(isel, dst_lo64_ra);
                            }
                        },
                        128 => try dst_vi.value.move(isel, ty_op.operand),
                        else => return isel.fail("bad {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) }),
                    }
                } else if ((dst_ty.isPtrAtRuntime(zcu) or dst_ty.isAbiInt(zcu)) and (src_ty.isPtrAtRuntime(zcu) or src_ty.isAbiInt(zcu))) {
                    try dst_vi.value.move(isel, ty_op.operand);
                } else if (dst_ty.isSliceAtRuntime(zcu) and src_ty.isSliceAtRuntime(zcu)) {
                    try dst_vi.value.move(isel, ty_op.operand);
                } else if (dst_tag == .error_union and src_tag == .error_union) {
                    assert(dst_ty.errorUnionSet(zcu).hasRuntimeBits(zcu) ==
                        src_ty.errorUnionSet(zcu).hasRuntimeBits(zcu));
                    if (dst_ty.errorUnionPayload(zcu).toIntern() == src_ty.errorUnionPayload(zcu).toIntern()) {
                        try dst_vi.value.move(isel, ty_op.operand);
                    } else return isel.fail("bad {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) });
                } else if (dst_tag == .float and src_tag == .float) {
                    assert(dst_ty.floatBits(isel.target) == src_ty.floatBits(isel.target));
                    try dst_vi.value.move(isel, ty_op.operand);
                } else if (dst_ty.isAbiInt(zcu) and src_tag == .float) {
                    const dst_int_info = dst_ty.intInfo(zcu);
                    assert(dst_int_info.bits == src_ty.floatBits(isel.target));
                    switch (dst_int_info.bits) {
                        else => unreachable,
                        16 => {
                            const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                            const src_vi = try isel.use(ty_op.operand);
                            const src_mat = try src_vi.matReg(isel);
                            switch (dst_int_info.signedness) {
                                .signed => try isel.emit(.smov(dst_ra.w(), src_mat.ra.@"h[]"(0))),
                                .unsigned => try isel.emit(if (isel.target.cpu.has(.aarch64, .fullfp16))
                                    .fmov(dst_ra.w(), .{ .register = src_mat.ra.h() })
                                else
                                    .umov(dst_ra.w(), src_mat.ra.@"h[]"(0))),
                            }
                            try src_mat.finish(isel);
                        },
                        32 => {
                            const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                            const src_vi = try isel.use(ty_op.operand);
                            const src_mat = try src_vi.matReg(isel);
                            try isel.emit(.fmov(dst_ra.w(), .{ .register = src_mat.ra.s() }));
                            try src_mat.finish(isel);
                        },
                        64 => {
                            const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                            const src_vi = try isel.use(ty_op.operand);
                            const src_mat = try src_vi.matReg(isel);
                            try isel.emit(.fmov(dst_ra.x(), .{ .register = src_mat.ra.d() }));
                            try src_mat.finish(isel);
                        },
                        80 => switch (dst_int_info.signedness) {
                            .signed => {
                                const src_vi = try isel.use(ty_op.operand);
                                var dst_hi16_it = dst_vi.value.field(dst_ty, 8, 8);
                                const dst_hi16_vi = try dst_hi16_it.only(isel);
                                if (try dst_hi16_vi.?.defReg(isel)) |dst_hi16_ra| {
                                    var src_hi16_it = src_vi.field(src_ty, 8, 8);
                                    const src_hi16_vi = try src_hi16_it.only(isel);
                                    const src_hi16_mat = try src_hi16_vi.?.matReg(isel);
                                    try isel.emit(.sbfm(dst_hi16_ra.x(), src_hi16_mat.ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 0,
                                        .imms = 16 - 1,
                                    }));
                                    try src_hi16_mat.finish(isel);
                                }
                                var dst_lo64_it = dst_vi.value.field(dst_ty, 0, 8);
                                const dst_lo64_vi = try dst_lo64_it.only(isel);
                                if (try dst_lo64_vi.?.defReg(isel)) |dst_lo64_ra| {
                                    var src_lo64_it = src_vi.field(src_ty, 0, 8);
                                    const src_lo64_vi = try src_lo64_it.only(isel);
                                    try src_lo64_vi.?.liveOut(isel, dst_lo64_ra);
                                }
                            },
                            else => try dst_vi.value.move(isel, ty_op.operand),
                        },
                        128 => {
                            const src_vi = try isel.use(ty_op.operand);
                            const src_mat = try src_vi.matReg(isel);
                            var dst_hi64_it = dst_vi.value.field(dst_ty, 8, 8);
                            const dst_hi64_vi = try dst_hi64_it.only(isel);
                            if (try dst_hi64_vi.?.defReg(isel)) |dst_hi64_ra| try isel.emit(.fmov(dst_hi64_ra.x(), .{ .register = src_mat.ra.@"d[]"(1) }));
                            var dst_lo64_it = dst_vi.value.field(dst_ty, 0, 8);
                            const dst_lo64_vi = try dst_lo64_it.only(isel);
                            if (try dst_lo64_vi.?.defReg(isel)) |dst_lo64_ra| try isel.emit(.fmov(dst_lo64_ra.x(), .{ .register = src_mat.ra.d() }));
                            try src_mat.finish(isel);
                        },
                    }
                } else if (dst_tag == .float and src_ty.isAbiInt(zcu)) {
                    const src_int_info = src_ty.intInfo(zcu);
                    assert(dst_ty.floatBits(isel.target) == src_int_info.bits);
                    switch (src_int_info.bits) {
                        else => unreachable,
                        16 => {
                            const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                            const src_vi = try isel.use(ty_op.operand);
                            const src_mat = try src_vi.matReg(isel);
                            try isel.emit(.fmov(
                                if (isel.target.cpu.has(.aarch64, .fullfp16)) dst_ra.h() else dst_ra.s(),
                                .{ .register = src_mat.ra.w() },
                            ));
                            try src_mat.finish(isel);
                        },
                        32 => {
                            const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                            const src_vi = try isel.use(ty_op.operand);
                            const src_mat = try src_vi.matReg(isel);
                            try isel.emit(.fmov(dst_ra.s(), .{ .register = src_mat.ra.w() }));
                            try src_mat.finish(isel);
                        },
                        64 => {
                            const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                            const src_vi = try isel.use(ty_op.operand);
                            const src_mat = try src_vi.matReg(isel);
                            try isel.emit(.fmov(dst_ra.d(), .{ .register = src_mat.ra.x() }));
                            try src_mat.finish(isel);
                        },
                        80 => switch (src_int_info.signedness) {
                            .signed => {
                                const src_vi = try isel.use(ty_op.operand);
                                var dst_hi16_it = dst_vi.value.field(dst_ty, 8, 8);
                                const dst_hi16_vi = try dst_hi16_it.only(isel);
                                if (try dst_hi16_vi.?.defReg(isel)) |dst_hi16_ra| {
                                    var src_hi16_it = src_vi.field(src_ty, 8, 8);
                                    const src_hi16_vi = try src_hi16_it.only(isel);
                                    const src_hi16_mat = try src_hi16_vi.?.matReg(isel);
                                    try isel.emit(.ubfm(dst_hi16_ra.x(), src_hi16_mat.ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 0,
                                        .imms = 16 - 1,
                                    }));
                                    try src_hi16_mat.finish(isel);
                                }
                                var dst_lo64_it = dst_vi.value.field(dst_ty, 0, 8);
                                const dst_lo64_vi = try dst_lo64_it.only(isel);
                                if (try dst_lo64_vi.?.defReg(isel)) |dst_lo64_ra| {
                                    var src_lo64_it = src_vi.field(src_ty, 0, 8);
                                    const src_lo64_vi = try src_lo64_it.only(isel);
                                    try src_lo64_vi.?.liveOut(isel, dst_lo64_ra);
                                }
                            },
                            else => try dst_vi.value.move(isel, ty_op.operand),
                        },
                        128 => {
                            const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                            const src_vi = try isel.use(ty_op.operand);
                            var src_hi64_it = src_vi.field(src_ty, 8, 8);
                            const src_hi64_vi = try src_hi64_it.only(isel);
                            const src_hi64_mat = try src_hi64_vi.?.matReg(isel);
                            try isel.emit(.fmov(dst_ra.@"d[]"(1), .{ .register = src_hi64_mat.ra.x() }));
                            try src_hi64_mat.finish(isel);
                            var src_lo64_it = src_vi.field(src_ty, 0, 8);
                            const src_lo64_vi = try src_lo64_it.only(isel);
                            const src_lo64_mat = try src_lo64_vi.?.matReg(isel);
                            try isel.emit(.fmov(dst_ra.d(), .{ .register = src_lo64_mat.ra.x() }));
                            try src_lo64_mat.finish(isel);
                        },
                    }
                } else if (air_tag == .union_from_enum) {
                    try dst_vi.value.move(isel, ty_op.operand);
                } else if (dst_tag == .bool and (src_tag == .bool or src_ty.isAbiInt(zcu))) {
                    if (src_tag == .bool or src_ty.intInfo(zcu).signedness == .unsigned) {
                        try dst_vi.value.move(isel, ty_op.operand);
                    } else {
                        const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        const src_mat = try src_vi.matReg(isel);
                        try isel.emit(.ubfm(dst_ra.w(), src_mat.ra.w(), .{
                            .N = .word,
                            .immr = 0,
                            .imms = 0,
                        }));
                        try src_mat.finish(isel);
                    }
                } else if (dst_ty.abiSize(zcu) == src_ty.abiSize(zcu) or dst_ty.bitSize(zcu) == src_ty.bitSize(zcu)) {
                    const size = @min(dst_ty.abiSize(zcu), src_ty.abiSize(zcu));
                    try dst_vi.value.defAddr(isel, dst_ty, .{
                        .wrap = if (dst_ty.isAbiInt(zcu)) dst_ty.intInfo(zcu) else null,
                    }) orelse break :unused;

                    try call.prepareReturn(isel);
                    try call.finishReturn(isel);

                    try call.prepareCallee(isel);
                    try isel.global_relocs.append(gpa, .{
                        .name = "memcpy",
                        .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                    });
                    try isel.emit(.bl(0));
                    try call.finishCallee(isel);

                    try call.prepareParams(isel);
                    const src_vi = try isel.use(ty_op.operand);
                    try isel.movImmediate(.x2, size);
                    try call.paramAddress(isel, src_vi, .r1);
                    try call.paramAddress(isel, dst_vi.value, .r0);
                    try call.finishParams(isel);
                } else return isel.fail("bad {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) });
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .repeat => {
            const repeat = air.data(air.inst_index).repeat;
            try isel.loops.getPtr(repeat.loop_inst).?.branch(isel);
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .br => {
            const br = air.data(air.inst_index).br;
            try isel.blocks.getPtr(br.block_inst).?.branch(isel);
            if (isel.live_values.get(br.block_inst)) |dst_vi| try dst_vi.move(isel, br.operand);
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .trap => {
            try isel.emit(.brk(0x1));
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .breakpoint => {
            try isel.emit(.brk(0xf000));
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .ret_addr => {
            if (isel.live_values.fetchRemove(air.inst_index)) |addr_vi| unused: {
                defer addr_vi.value.deref(isel);
                const addr_ra = try addr_vi.value.defReg(isel) orelse break :unused;
                try isel.emit(.ldr(addr_ra.x(), .{ .unsigned_offset = .{ .base = .fp, .offset = 8 } }));
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .reduce, .reduce_optimized => {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const reduce = air.data(air.inst_index).reduce;
                const operand_ty = isel.air.typeOf(reduce.operand, ip);
                const vector_type = ip.indexToKey(operand_ty.toIntern()).vector_type;
                const elem_ty: ZigType = .fromInterned(vector_type.child);
                const elem_size = elem_ty.abiSize(zcu);
                const int_info: std.lang.Type.Int = if (elem_ty.toIntern() == .bool_type)
                    .{ .signedness = .unsigned, .bits = 1 }
                else if (elem_ty.isAbiInt(zcu) and elem_size <= 8)
                    elem_ty.intInfo(zcu)
                else
                    return isel.fail("reduce {t} {f}", .{ reduce.operation, isel.fmtType(operand_ty) });
                const is_packed = operand_ty.bitSize(zcu) != vector_type.len * elem_size * 8;
                if (is_packed and operand_ty.abiSize(zcu) > 8) {
                    return isel.fail("reduce {t} {f}", .{ reduce.operation, isel.fmtType(operand_ty) });
                }
                const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                const operand_vi = try isel.use(reduce.operand);
                var res_lock = isel.lockReg(res_ra);
                defer res_lock.unlock(isel);

                switch (reduce.operation) {
                    .Add, .Mul => switch (int_info.bits) {
                        else => unreachable,
                        1...31 => |bits| try isel.emit(switch (int_info.signedness) {
                            .signed => .sbfm(res_ra.w(), res_ra.w(), .{
                                .N = .word,
                                .immr = 0,
                                .imms = @intCast(bits - 1),
                            }),
                            .unsigned => .ubfm(res_ra.w(), res_ra.w(), .{
                                .N = .word,
                                .immr = 0,
                                .imms = @intCast(bits - 1),
                            }),
                        }),
                        32, 64 => {},
                        33...63 => |bits| try isel.emit(switch (int_info.signedness) {
                            .signed => .sbfm(res_ra.x(), res_ra.x(), .{
                                .N = .doubleword,
                                .immr = 0,
                                .imms = @intCast(bits - 1),
                            }),
                            .unsigned => .ubfm(res_ra.x(), res_ra.x(), .{
                                .N = .doubleword,
                                .immr = 0,
                                .imms = @intCast(bits - 1),
                            }),
                        }),
                    },
                    .And, .Or, .Xor, .Min, .Max => {},
                }

                if (is_packed) {
                    const operand_mat = try operand_vi.matReg(isel);
                    const elem_ra = try isel.allocIntReg();
                    defer isel.freeReg(elem_ra);
                    const bits = int_info.bits;
                    var elem_index: u64 = vector_type.len;
                    while (elem_index > 1) {
                        elem_index -= 1;
                        switch (reduce.operation) {
                            .Add => try isel.emit(switch (elem_size) {
                                1...4 => .add(res_ra.w(), res_ra.w(), .{ .register = elem_ra.w() }),
                                5...8 => .add(res_ra.x(), res_ra.x(), .{ .register = elem_ra.x() }),
                                else => unreachable,
                            }),
                            .And => try isel.emit(switch (elem_size) {
                                1...4 => .@"and"(res_ra.w(), res_ra.w(), .{ .register = elem_ra.w() }),
                                5...8 => .@"and"(res_ra.x(), res_ra.x(), .{ .register = elem_ra.x() }),
                                else => unreachable,
                            }),
                            .Or => try isel.emit(switch (elem_size) {
                                1...4 => .orr(res_ra.w(), res_ra.w(), .{ .register = elem_ra.w() }),
                                5...8 => .orr(res_ra.x(), res_ra.x(), .{ .register = elem_ra.x() }),
                                else => unreachable,
                            }),
                            .Xor => try isel.emit(switch (elem_size) {
                                1...4 => .eor(res_ra.w(), res_ra.w(), .{ .register = elem_ra.w() }),
                                5...8 => .eor(res_ra.x(), res_ra.x(), .{ .register = elem_ra.x() }),
                                else => unreachable,
                            }),
                            .Mul => try isel.emit(switch (elem_size) {
                                1...4 => .madd(res_ra.w(), res_ra.w(), elem_ra.w(), .wzr),
                                5...8 => .madd(res_ra.x(), res_ra.x(), elem_ra.x(), .xzr),
                                else => unreachable,
                            }),
                            .Min, .Max => {
                                const cond: codegen.aarch64.encoding.ConditionCode = switch (reduce.operation) {
                                    .Min => switch (int_info.signedness) {
                                        .signed => .le,
                                        .unsigned => .ls,
                                    },
                                    .Max => switch (int_info.signedness) {
                                        .signed => .ge,
                                        .unsigned => .hs,
                                    },
                                    else => unreachable,
                                };
                                switch (elem_size) {
                                    1...4 => {
                                        try isel.emit(.csel(res_ra.w(), res_ra.w(), elem_ra.w(), cond));
                                        try isel.emit(.subs(.wzr, res_ra.w(), .{ .register = elem_ra.w() }));
                                    },
                                    5...8 => {
                                        try isel.emit(.csel(res_ra.x(), res_ra.x(), elem_ra.x(), cond));
                                        try isel.emit(.subs(.xzr, res_ra.x(), .{ .register = elem_ra.x() }));
                                    },
                                    else => unreachable,
                                }
                            },
                        }
                        const lsb: u6 = @intCast(elem_index * bits);
                        try isel.emit(switch (int_info.signedness) {
                            .signed => .sbfm(elem_ra.x(), operand_mat.ra.x(), .{
                                .N = .doubleword,
                                .immr = lsb,
                                .imms = @intCast(lsb + bits - 1),
                            }),
                            .unsigned => .ubfm(elem_ra.x(), operand_mat.ra.x(), .{
                                .N = .doubleword,
                                .immr = lsb,
                                .imms = @intCast(lsb + bits - 1),
                            }),
                        });
                    }
                    try isel.emit(switch (int_info.signedness) {
                        .signed => .sbfm(res_ra.x(), operand_mat.ra.x(), .{
                            .N = .doubleword,
                            .immr = 0,
                            .imms = @intCast(bits - 1),
                        }),
                        .unsigned => .ubfm(res_ra.x(), operand_mat.ra.x(), .{
                            .N = .doubleword,
                            .immr = 0,
                            .imms = @intCast(bits - 1),
                        }),
                    });
                    try operand_mat.finish(isel);
                    break :unused;
                }

                var elem_index: u64 = vector_type.len;
                while (elem_index > 1) {
                    elem_index -= 1;
                    var elem_it = operand_vi.field(operand_ty, elem_index * elem_size, elem_size);
                    const elem_vi = try elem_it.only(isel);
                    const elem_mat = try elem_vi.?.matReg(isel);
                    switch (reduce.operation) {
                        .Add => try isel.emit(switch (elem_size) {
                            1...4 => .add(res_ra.w(), res_ra.w(), .{ .register = elem_mat.ra.w() }),
                            5...8 => .add(res_ra.x(), res_ra.x(), .{ .register = elem_mat.ra.x() }),
                            else => unreachable,
                        }),
                        .And => try isel.emit(switch (elem_size) {
                            1...4 => .@"and"(res_ra.w(), res_ra.w(), .{ .register = elem_mat.ra.w() }),
                            5...8 => .@"and"(res_ra.x(), res_ra.x(), .{ .register = elem_mat.ra.x() }),
                            else => unreachable,
                        }),
                        .Or => try isel.emit(switch (elem_size) {
                            1...4 => .orr(res_ra.w(), res_ra.w(), .{ .register = elem_mat.ra.w() }),
                            5...8 => .orr(res_ra.x(), res_ra.x(), .{ .register = elem_mat.ra.x() }),
                            else => unreachable,
                        }),
                        .Xor => try isel.emit(switch (elem_size) {
                            1...4 => .eor(res_ra.w(), res_ra.w(), .{ .register = elem_mat.ra.w() }),
                            5...8 => .eor(res_ra.x(), res_ra.x(), .{ .register = elem_mat.ra.x() }),
                            else => unreachable,
                        }),
                        .Mul => try isel.emit(switch (elem_size) {
                            1...4 => .madd(res_ra.w(), res_ra.w(), elem_mat.ra.w(), .wzr),
                            5...8 => .madd(res_ra.x(), res_ra.x(), elem_mat.ra.x(), .xzr),
                            else => unreachable,
                        }),
                        .Min, .Max => {
                            const cond: codegen.aarch64.encoding.ConditionCode = switch (reduce.operation) {
                                .Min => switch (int_info.signedness) {
                                    .signed => .le,
                                    .unsigned => .ls,
                                },
                                .Max => switch (int_info.signedness) {
                                    .signed => .ge,
                                    .unsigned => .hs,
                                },
                                else => unreachable,
                            };
                            switch (elem_size) {
                                1...4 => {
                                    try isel.emit(.csel(res_ra.w(), res_ra.w(), elem_mat.ra.w(), cond));
                                    try isel.emit(.subs(.wzr, res_ra.w(), .{ .register = elem_mat.ra.w() }));
                                },
                                5...8 => {
                                    try isel.emit(.csel(res_ra.x(), res_ra.x(), elem_mat.ra.x(), cond));
                                    try isel.emit(.subs(.xzr, res_ra.x(), .{ .register = elem_mat.ra.x() }));
                                },
                                else => unreachable,
                            }
                        },
                    }
                    try elem_mat.finish(isel);
                }

                res_lock.unlock(isel);
                res_lock = .empty;
                var elem0_it = operand_vi.field(operand_ty, 0, elem_size);
                const elem0_vi = try elem0_it.only(isel);
                try elem0_vi.?.liveOut(isel, res_ra);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .frame_addr => {
            if (isel.live_values.fetchRemove(air.inst_index)) |addr_vi| unused: {
                defer addr_vi.value.deref(isel);
                const addr_ra = try addr_vi.value.defReg(isel) orelse break :unused;
                try isel.emit(.orr(addr_ra.x(), .xzr, .{ .register = .fp }));
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .call,
        .call_always_tail,
        .call_never_tail,
        .call_never_inline,
        => {
            const air_call = isel.air.unwrapCall(air.inst_index);
            const args = air_call.args;
            const callee_ty = isel.air.typeOf(air_call.callee, ip);
            const func_info = switch (ip.indexToKey(callee_ty.toIntern())) {
                else => unreachable,
                .func_type => |func_type| func_type,
                .ptr_type => |ptr_type| ip.indexToKey(ptr_type.child).func_type,
            };

            try call.prepareReturn(isel);
            const maybe_def_ret_vi = isel.live_values.fetchRemove(air.inst_index);
            var maybe_ret_addr_vi: ?Value.Index = null;
            if (maybe_def_ret_vi) |def_ret_vi| {
                defer def_ret_vi.value.deref(isel);

                var ret_it: CallAbiIterator = .init;
                const ret_vi = try ret_it.ret(isel, isel.air.typeOfIndex(air.inst_index, ip));
                defer ret_vi.?.deref(isel);
                switch (ret_vi.?.parent(isel)) {
                    .unallocated, .stack_slot => if (ret_vi.?.hint(isel)) |ret_ra| {
                        try call.returnLiveIn(isel, def_ret_vi.value, ret_ra);
                    } else {
                        var def_ret_part_it = def_ret_vi.value.parts(isel);
                        var ret_part_it = ret_vi.?.parts(isel);
                        while (def_ret_part_it.next()) |ret_part_vi| {
                            try call.returnLiveIn(isel, ret_part_vi, ret_part_it.next().?.hint(isel).?);
                        }
                    },
                    .value, .constant => unreachable,
                    .address => |address_vi| {
                        maybe_ret_addr_vi = address_vi;
                        _ = try def_ret_vi.value.defAddr(isel, isel.air.typeOfIndex(air.inst_index, ip), .{
                            .expected_live_registers = &call.caller_saved_regs,
                        });
                    },
                }
            }
            try call.finishReturn(isel);

            try call.prepareCallee(isel);
            if (air_call.callee.toInterned()) |ct_callee| {
                try isel.nav_relocs.append(gpa, switch (ip.indexToKey(ct_callee)) {
                    else => unreachable,
                    inline .@"extern", .func => |func| .{
                        .nav = func.owner_nav,
                        .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                    },
                    .ptr => |ptr| .{
                        .nav = ptr.base_addr.nav,
                        .reloc = .{
                            .label = @intCast(isel.instructions.items.len),
                            .addend = ptr.byte_offset,
                        },
                    },
                });
                try isel.emit(.bl(0));
            } else {
                const callee_vi = try isel.use(air_call.callee);
                const callee_mat = try callee_vi.matReg(isel);
                try isel.emit(.blr(callee_mat.ra.x()));
                try callee_mat.finish(isel);
            }
            try call.finishCallee(isel);

            try call.prepareParams(isel);
            if (maybe_ret_addr_vi) |ret_addr_vi| try call.paramAddress(
                isel,
                maybe_def_ret_vi.?.value,
                ret_addr_vi.hint(isel).?,
            );
            var param_it: CallAbiIterator = .init;
            for (args, 0..) |arg, arg_index| {
                const param_ty = isel.air.typeOf(arg, ip);
                const param_vi = param_vi: {
                    if (arg_index >= func_info.param_types.len) {
                        assert(func_info.is_var_args);
                        switch (isel.va_list) {
                            .other => break :param_vi try param_it.nonSysvVarArg(isel, param_ty),
                            .sysv => {},
                        }
                    }
                    break :param_vi try param_it.param(isel, param_ty);
                } orelse continue;
                defer param_vi.deref(isel);
                const arg_vi = try isel.use(arg);
                switch (param_vi.parent(isel)) {
                    .unallocated => if (param_vi.hint(isel)) |param_ra| {
                        try call.paramLiveOut(isel, arg_vi, param_ra);
                    } else {
                        var param_part_it = param_vi.parts(isel);
                        var arg_part_it = arg_vi.parts(isel);
                        if (arg_part_it.only()) |_| {
                            try isel.values.ensureUnusedCapacity(gpa, param_part_it.remaining);
                            arg_vi.setParts(isel, param_part_it.remaining);
                            while (param_part_it.next()) |param_part_vi| {
                                const arg_part_vi = arg_vi.addPart(
                                    isel,
                                    param_part_vi.get(isel).offset_from_parent,
                                    param_part_vi.size(isel),
                                );
                                switch (param_part_vi.signedness(isel)) {
                                    .signed => arg_part_vi.setSignedness(isel, .signed),
                                    .unsigned => {},
                                }
                                if (param_part_vi.isVector(isel)) arg_part_vi.setIsVector(isel);
                            }
                            param_part_it = param_vi.parts(isel);
                            arg_part_it = arg_vi.parts(isel);
                        }
                        while (param_part_it.next()) |param_part_vi| {
                            const arg_part_vi = arg_part_it.next().?;
                            assert(arg_part_vi.get(isel).offset_from_parent ==
                                param_part_vi.get(isel).offset_from_parent);
                            assert(arg_part_vi.size(isel) <= param_part_vi.size(isel));
                            try call.paramLiveOut(isel, arg_part_vi, param_part_vi.hint(isel).?);
                        }
                    },
                    .stack_slot => |stack_slot| try arg_vi.store(isel, param_ty, stack_slot.base, .{
                        .offset = @intCast(stack_slot.offset),
                    }),
                    .value, .constant => unreachable,
                    .address => |address_vi| switch (address_vi.parent(isel)) {
                        .unallocated => try call.paramAddress(isel, arg_vi, address_vi.hint(isel).?),
                        .stack_slot => |stack_slot| {
                            const addr_ra = try isel.allocIntReg();
                            try isel.storeReg(addr_ra, 8, stack_slot.base, stack_slot.offset);
                            isel.freeReg(addr_ra);
                            try arg_vi.address(isel, 0, addr_ra);
                        },
                        .value, .constant, .address => unreachable,
                    },
                }
            }
            try call.finishParams(isel);

            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .clz => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const ty = isel.air.typeOf(ty_op.operand, ip);
                if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                const int_info = ty.intInfo(zcu);
                switch (int_info.bits) {
                    0 => unreachable,
                    1...64 => {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        const src_mat = try src_vi.matReg(isel);
                        try isel.clzLimb(res_ra, int_info, src_mat.ra);
                        try src_mat.finish(isel);
                    },
                    65...128 => |bits| {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        var src_hi64_it = src_vi.field(ty, 8, 8);
                        const src_hi64_vi = try src_hi64_it.only(isel);
                        const src_hi64_mat = try src_hi64_vi.?.matReg(isel);
                        var src_lo64_it = src_vi.field(ty, 0, 8);
                        const src_lo64_vi = try src_lo64_it.only(isel);
                        const src_lo64_mat = try src_lo64_vi.?.matReg(isel);
                        const lo64_ra = try isel.allocIntReg();
                        defer isel.freeReg(lo64_ra);
                        const hi64_ra = try isel.allocIntReg();
                        defer isel.freeReg(hi64_ra);
                        try isel.emit(.csel(res_ra.w(), lo64_ra.w(), hi64_ra.w(), .eq));
                        try isel.emit(.add(lo64_ra.w(), lo64_ra.w(), .{ .immediate = @intCast(bits - 64) }));
                        try isel.emit(.subs(.xzr, src_hi64_mat.ra.x(), .{ .immediate = 0 }));
                        try isel.clzLimb(hi64_ra, .{ .signedness = int_info.signedness, .bits = bits - 64 }, src_hi64_mat.ra);
                        try isel.clzLimb(lo64_ra, .{ .signedness = .unsigned, .bits = 64 }, src_lo64_mat.ra);
                        try src_hi64_mat.finish(isel);
                        try src_lo64_mat.finish(isel);
                    },
                    else => return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) }),
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .ctz => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const ty = isel.air.typeOf(ty_op.operand, ip);
                if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                const int_info = ty.intInfo(zcu);
                switch (int_info.bits) {
                    0 => unreachable,
                    1...64 => {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        const src_mat = try src_vi.matReg(isel);
                        try isel.ctzLimb(res_ra, int_info, src_mat.ra);
                        try src_mat.finish(isel);
                    },
                    65...128 => |bits| {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        var src_hi64_it = src_vi.field(ty, 8, 8);
                        const src_hi64_vi = try src_hi64_it.only(isel);
                        const src_hi64_mat = try src_hi64_vi.?.matReg(isel);
                        var src_lo64_it = src_vi.field(ty, 0, 8);
                        const src_lo64_vi = try src_lo64_it.only(isel);
                        const src_lo64_mat = try src_lo64_vi.?.matReg(isel);
                        const lo64_ra = try isel.allocIntReg();
                        defer isel.freeReg(lo64_ra);
                        const hi64_ra = try isel.allocIntReg();
                        defer isel.freeReg(hi64_ra);
                        try isel.emit(.csel(res_ra.w(), lo64_ra.w(), hi64_ra.w(), .ne));
                        try isel.emit(.add(hi64_ra.w(), hi64_ra.w(), .{ .immediate = 64 }));
                        try isel.emit(.subs(.xzr, src_lo64_mat.ra.x(), .{ .immediate = 0 }));
                        try isel.ctzLimb(hi64_ra, .{ .signedness = .unsigned, .bits = 64 }, src_hi64_mat.ra);
                        try isel.ctzLimb(lo64_ra, .{ .signedness = int_info.signedness, .bits = bits - 64 }, src_lo64_mat.ra);
                        try src_hi64_mat.finish(isel);
                        try src_lo64_mat.finish(isel);
                    },
                    else => return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) }),
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .popcount => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const ty = isel.air.typeOf(ty_op.operand, ip);
                if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                const int_info = ty.intInfo(zcu);
                if (int_info.bits > 64) return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) });

                const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                const src_vi = try isel.use(ty_op.operand);
                const src_mat = try src_vi.matReg(isel);
                const vec_ra = try isel.allocVecReg();
                defer isel.freeReg(vec_ra);
                try isel.emit(.umov(res_ra.w(), vec_ra.@"b[]"(0)));
                switch (int_info.bits) {
                    else => unreachable,
                    1...8 => {},
                    9...16 => try isel.emit(.addp(vec_ra.@"8b"(), vec_ra.@"8b"(), .{ .vector = vec_ra.@"8b"() })),
                    17...64 => try isel.emit(.addv(vec_ra.b(), vec_ra.@"8b"())),
                }
                try isel.emit(.cnt(vec_ra.@"8b"(), vec_ra.@"8b"()));
                switch (int_info.bits) {
                    else => unreachable,
                    1...31 => |bits| switch (int_info.signedness) {
                        .signed => {
                            try isel.emit(.fmov(vec_ra.s(), .{ .register = res_ra.w() }));
                            try isel.emit(.ubfm(res_ra.w(), src_mat.ra.w(), .{
                                .N = .word,
                                .immr = 0,
                                .imms = @intCast(bits - 1),
                            }));
                        },
                        .unsigned => try isel.emit(.fmov(vec_ra.s(), .{ .register = src_mat.ra.w() })),
                    },
                    32 => try isel.emit(.fmov(vec_ra.s(), .{ .register = src_mat.ra.w() })),
                    33...63 => |bits| switch (int_info.signedness) {
                        .signed => {
                            try isel.emit(.fmov(vec_ra.d(), .{ .register = res_ra.x() }));
                            try isel.emit(.ubfm(res_ra.x(), src_mat.ra.x(), .{
                                .N = .doubleword,
                                .immr = 0,
                                .imms = @intCast(bits - 1),
                            }));
                        },
                        .unsigned => try isel.emit(.fmov(vec_ra.d(), .{ .register = src_mat.ra.x() })),
                    },
                    64 => try isel.emit(.fmov(vec_ra.d(), .{ .register = src_mat.ra.x() })),
                }
                try src_mat.finish(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .byte_swap => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const ty = ty_op.ty;
                if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                const int_info = ty.intInfo(zcu);
                if (int_info.bits > 128) return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) });

                switch (int_info.bits) {
                    else => unreachable,
                    8 => break :unused try res_vi.value.move(isel, ty_op.operand),
                    16, 24, 32, 40, 48, 56, 64 => |bits| {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        const src_mat = try src_vi.matReg(isel);
                        switch (bits) {
                            else => unreachable,
                            16 => switch (int_info.signedness) {
                                .signed => {
                                    try isel.emit(.sbfm(res_ra.w(), res_ra.w(), .{
                                        .N = .word,
                                        .immr = 32 - 16,
                                        .imms = 32 - 1,
                                    }));
                                    try isel.emit(.rev(res_ra.w(), src_mat.ra.w()));
                                },
                                .unsigned => try isel.emit(.rev16(res_ra.w(), src_mat.ra.w())),
                            },
                            24 => {
                                switch (int_info.signedness) {
                                    .signed => try isel.emit(.sbfm(res_ra.w(), res_ra.w(), .{
                                        .N = .word,
                                        .immr = 32 - 24,
                                        .imms = 32 - 1,
                                    })),
                                    .unsigned => try isel.emit(.ubfm(res_ra.w(), res_ra.w(), .{
                                        .N = .word,
                                        .immr = 32 - 24,
                                        .imms = 32 - 1,
                                    })),
                                }
                                try isel.emit(.rev(res_ra.w(), src_mat.ra.w()));
                            },
                            32 => try isel.emit(.rev(res_ra.w(), src_mat.ra.w())),
                            40, 48, 56 => {
                                switch (int_info.signedness) {
                                    .signed => try isel.emit(.sbfm(res_ra.x(), res_ra.x(), .{
                                        .N = .doubleword,
                                        .immr = @intCast(64 - bits),
                                        .imms = 64 - 1,
                                    })),
                                    .unsigned => try isel.emit(.ubfm(res_ra.x(), res_ra.x(), .{
                                        .N = .doubleword,
                                        .immr = @intCast(64 - bits),
                                        .imms = 64 - 1,
                                    })),
                                }
                                try isel.emit(.rev(res_ra.x(), src_mat.ra.x()));
                            },
                            64 => try isel.emit(.rev(res_ra.x(), src_mat.ra.x())),
                        }
                        try src_mat.finish(isel);
                    },
                    72, 80, 88, 96, 104, 112, 120 => |bits| {
                        var res_hi64_it = res_vi.value.field(ty, 8, 8);
                        const res_hi64_vi = try res_hi64_it.only(isel);
                        const res_hi64_ra = try res_hi64_vi.?.defReg(isel);
                        var res_lo64_it = res_vi.value.field(ty, 0, 8);
                        const res_lo64_vi = try res_lo64_it.only(isel);
                        const res_lo64_ra = try res_lo64_vi.?.defReg(isel);
                        if (res_hi64_ra == null and res_lo64_ra == null) break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        const lo64_ra = lo64_ra: {
                            const res_lo64_lock: RegLock = if (res_lo64_ra) |res_ra| isel.tryLockReg(res_ra) else .empty;
                            defer res_lo64_lock.unlock(isel);
                            break :lo64_ra try isel.allocIntReg();
                        };
                        defer isel.freeReg(lo64_ra);
                        if (res_hi64_ra) |res_ra| try isel.emit(switch (int_info.signedness) {
                            .signed => .sbfm(res_ra.x(), lo64_ra.x(), .{
                                .N = .doubleword,
                                .immr = @intCast(128 - bits),
                                .imms = 64 - 1,
                            }),
                            .unsigned => .ubfm(res_ra.x(), lo64_ra.x(), .{
                                .N = .doubleword,
                                .immr = @intCast(128 - bits),
                                .imms = 64 - 1,
                            }),
                        });
                        if (res_lo64_ra) |res_ra| {
                            var src_hi64_it = src_vi.field(ty, 8, 8);
                            const src_hi64_vi = try src_hi64_it.only(isel);
                            const src_hi64_mat = try src_hi64_vi.?.matReg(isel);
                            try isel.emit(.extr(res_ra.x(), lo64_ra.x(), res_ra.x(), @intCast(128 - bits)));
                            try isel.emit(.rev(res_ra.x(), src_hi64_mat.ra.x()));
                            try src_hi64_mat.finish(isel);
                        }
                        var src_lo64_it = src_vi.field(ty, 0, 8);
                        const src_lo64_vi = try src_lo64_it.only(isel);
                        const src_lo64_mat = try src_lo64_vi.?.matReg(isel);
                        try isel.emit(.rev(lo64_ra.x(), src_lo64_mat.ra.x()));
                        try src_lo64_mat.finish(isel);
                    },
                    128 => {
                        var res_hi64_it = res_vi.value.field(ty, 8, 8);
                        const res_hi64_vi = try res_hi64_it.only(isel);
                        const res_hi64_ra = try res_hi64_vi.?.defReg(isel);
                        var res_lo64_it = res_vi.value.field(ty, 0, 8);
                        const res_lo64_vi = try res_lo64_it.only(isel);
                        const res_lo64_ra = try res_lo64_vi.?.defReg(isel);
                        if (res_hi64_ra == null and res_lo64_ra == null) break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        if (res_lo64_ra) |res_ra| {
                            const res_hi64_lock: RegLock = if (res_hi64_ra) |hi_ra| isel.tryLockReg(hi_ra) else .empty;
                            defer res_hi64_lock.unlock(isel);
                            var src_hi64_it = src_vi.field(ty, 8, 8);
                            const src_hi64_vi = try src_hi64_it.only(isel);
                            const src_hi64_mat = try src_hi64_vi.?.matReg(isel);
                            try isel.emit(.rev(res_ra.x(), src_hi64_mat.ra.x()));
                            try src_hi64_mat.finish(isel);
                        }
                        if (res_hi64_ra) |res_ra| {
                            var src_lo64_it = src_vi.field(ty, 0, 8);
                            const src_lo64_vi = try src_lo64_it.only(isel);
                            const src_lo64_mat = try src_lo64_vi.?.matReg(isel);
                            try isel.emit(.rev(res_ra.x(), src_lo64_mat.ra.x()));
                            try src_lo64_mat.finish(isel);
                        }
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .bit_reverse => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const ty = ty_op.ty;
                if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                const int_info = ty.intInfo(zcu);
                if (int_info.bits > 64) return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) });

                const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                const src_vi = try isel.use(ty_op.operand);
                const src_mat = try src_vi.matReg(isel);
                switch (int_info.bits) {
                    else => unreachable,
                    1...31 => |bits| {
                        switch (int_info.signedness) {
                            .signed => try isel.emit(.sbfm(res_ra.w(), res_ra.w(), .{
                                .N = .word,
                                .immr = @intCast(32 - bits),
                                .imms = 32 - 1,
                            })),
                            .unsigned => try isel.emit(.ubfm(res_ra.w(), res_ra.w(), .{
                                .N = .word,
                                .immr = @intCast(32 - bits),
                                .imms = 32 - 1,
                            })),
                        }
                        try isel.emit(.rbit(res_ra.w(), src_mat.ra.w()));
                    },
                    32 => try isel.emit(.rbit(res_ra.w(), src_mat.ra.w())),
                    33...63 => |bits| {
                        switch (int_info.signedness) {
                            .signed => try isel.emit(.sbfm(res_ra.x(), res_ra.x(), .{
                                .N = .doubleword,
                                .immr = @intCast(64 - bits),
                                .imms = 64 - 1,
                            })),
                            .unsigned => try isel.emit(.ubfm(res_ra.x(), res_ra.x(), .{
                                .N = .doubleword,
                                .immr = @intCast(64 - bits),
                                .imms = 64 - 1,
                            })),
                        }
                        try isel.emit(.rbit(res_ra.x(), src_mat.ra.x()));
                    },
                    64 => try isel.emit(.rbit(res_ra.x(), src_mat.ra.x())),
                }
                try src_mat.finish(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .sqrt, .floor, .ceil, .round, .trunc_float => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const un_op = air.data(air.inst_index).un_op;
                const ty = isel.air.typeOf(un_op, ip);
                switch (ty.floatBits(isel.target)) {
                    else => unreachable,
                    16, 32, 64 => |bits| {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const need_fcvt = switch (bits) {
                            else => unreachable,
                            16 => !isel.target.cpu.has(.aarch64, .fullfp16),
                            32, 64 => false,
                        };
                        if (need_fcvt) try isel.emit(.fcvt(res_ra.h(), res_ra.s()));
                        const src_vi = try isel.use(un_op);
                        const src_mat = try src_vi.matReg(isel);
                        const src_ra = if (need_fcvt) try isel.allocVecReg() else src_mat.ra;
                        defer if (need_fcvt) isel.freeReg(src_ra);
                        try isel.emit(bits: switch (bits) {
                            else => unreachable,
                            16 => if (need_fcvt) continue :bits 32 else switch (air_tag) {
                                else => unreachable,
                                .sqrt => .fsqrt(res_ra.h(), src_ra.h()),
                                .floor => .frintm(res_ra.h(), src_ra.h()),
                                .ceil => .frintp(res_ra.h(), src_ra.h()),
                                .round => .frinta(res_ra.h(), src_ra.h()),
                                .trunc_float => .frintz(res_ra.h(), src_ra.h()),
                            },
                            32 => switch (air_tag) {
                                else => unreachable,
                                .sqrt => .fsqrt(res_ra.s(), src_ra.s()),
                                .floor => .frintm(res_ra.s(), src_ra.s()),
                                .ceil => .frintp(res_ra.s(), src_ra.s()),
                                .round => .frinta(res_ra.s(), src_ra.s()),
                                .trunc_float => .frintz(res_ra.s(), src_ra.s()),
                            },
                            64 => switch (air_tag) {
                                else => unreachable,
                                .sqrt => .fsqrt(res_ra.d(), src_ra.d()),
                                .floor => .frintm(res_ra.d(), src_ra.d()),
                                .ceil => .frintp(res_ra.d(), src_ra.d()),
                                .round => .frinta(res_ra.d(), src_ra.d()),
                                .trunc_float => .frintz(res_ra.d(), src_ra.d()),
                            },
                        });
                        if (need_fcvt) try isel.emit(.fcvt(src_ra.s(), src_mat.ra.h()));
                        try src_mat.finish(isel);
                    },
                    80, 128 => |bits| {
                        try call.prepareReturn(isel);
                        switch (bits) {
                            else => unreachable,
                            16, 32, 64, 128 => try call.returnLiveIn(isel, res_vi.value, .v0),
                            80 => {
                                var res_hi16_it = res_vi.value.field(ty, 8, 8);
                                const res_hi16_vi = try res_hi16_it.only(isel);
                                try call.returnLiveIn(isel, res_hi16_vi.?, .r1);
                                var res_lo64_it = res_vi.value.field(ty, 0, 8);
                                const res_lo64_vi = try res_lo64_it.only(isel);
                                try call.returnLiveIn(isel, res_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishReturn(isel);

                        try call.prepareCallee(isel);
                        try isel.global_relocs.append(gpa, .{
                            .name = switch (air_tag) {
                                else => unreachable,
                                .sqrt => switch (bits) {
                                    else => unreachable,
                                    16 => "__sqrth",
                                    32 => "sqrtf",
                                    64 => "sqrt",
                                    80 => "__sqrtx",
                                    128 => "sqrtf128",
                                },
                                .floor => switch (bits) {
                                    else => unreachable,
                                    16 => "__floorh",
                                    32 => "floorf",
                                    64 => "floor",
                                    80 => "__floorx",
                                    128 => "floorf128",
                                },
                                .ceil => switch (bits) {
                                    else => unreachable,
                                    16 => "__ceilh",
                                    32 => "ceilf",
                                    64 => "ceil",
                                    80 => "__ceilx",
                                    128 => "ceilf128",
                                },
                                .round => switch (bits) {
                                    else => unreachable,
                                    16 => "__roundh",
                                    32 => "roundf",
                                    64 => "round",
                                    80 => "__roundx",
                                    128 => "roundf128",
                                },
                                .trunc_float => switch (bits) {
                                    else => unreachable,
                                    16 => "__trunch",
                                    32 => "truncf",
                                    64 => "trunc",
                                    80 => "__truncx",
                                    128 => "truncf128",
                                },
                            },
                            .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                        });
                        try isel.emit(.bl(0));
                        try call.finishCallee(isel);

                        try call.prepareParams(isel);
                        const src_vi = try isel.use(un_op);
                        switch (bits) {
                            else => unreachable,
                            16, 32, 64, 128 => try call.paramLiveOut(isel, src_vi, .v0),
                            80 => {
                                var src_hi16_it = src_vi.field(ty, 8, 8);
                                const src_hi16_vi = try src_hi16_it.only(isel);
                                try call.paramLiveOut(isel, src_hi16_vi.?, .r1);
                                var src_lo64_it = src_vi.field(ty, 0, 8);
                                const src_lo64_vi = try src_lo64_it.only(isel);
                                try call.paramLiveOut(isel, src_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishParams(isel);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .sin, .cos, .tan, .exp, .exp2, .log, .log2, .log10 => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| {
                defer res_vi.value.deref(isel);

                const un_op = air.data(air.inst_index).un_op;
                const ty = isel.air.typeOf(un_op, ip);
                const bits = ty.floatBits(isel.target);
                try call.prepareReturn(isel);
                switch (bits) {
                    else => unreachable,
                    16, 32, 64, 128 => try call.returnLiveIn(isel, res_vi.value, .v0),
                    80 => {
                        var res_hi16_it = res_vi.value.field(ty, 8, 8);
                        const res_hi16_vi = try res_hi16_it.only(isel);
                        try call.returnLiveIn(isel, res_hi16_vi.?, .r1);
                        var res_lo64_it = res_vi.value.field(ty, 0, 8);
                        const res_lo64_vi = try res_lo64_it.only(isel);
                        try call.returnLiveIn(isel, res_lo64_vi.?, .r0);
                    },
                }
                try call.finishReturn(isel);

                try call.prepareCallee(isel);
                try isel.global_relocs.append(gpa, .{
                    .name = switch (air_tag) {
                        else => unreachable,
                        .sin => switch (bits) {
                            else => unreachable,
                            16 => "__sinh",
                            32 => "sinf",
                            64 => "sin",
                            80 => "__sinx",
                            128 => "sinf128",
                        },
                        .cos => switch (bits) {
                            else => unreachable,
                            16 => "__cosh",
                            32 => "cosf",
                            64 => "cos",
                            80 => "__cosx",
                            128 => "cosf128",
                        },
                        .tan => switch (bits) {
                            else => unreachable,
                            16 => "__tanh",
                            32 => "tanf",
                            64 => "tan",
                            80 => "__tanx",
                            128 => "tanf128",
                        },
                        .exp => switch (bits) {
                            else => unreachable,
                            16 => "__exph",
                            32 => "expf",
                            64 => "exp",
                            80 => "__expx",
                            128 => "expf128",
                        },
                        .exp2 => switch (bits) {
                            else => unreachable,
                            16 => "__exp2h",
                            32 => "exp2f",
                            64 => "exp2",
                            80 => "__exp2x",
                            128 => "exp2f128",
                        },
                        .log => switch (bits) {
                            else => unreachable,
                            16 => "__logh",
                            32 => "logf",
                            64 => "log",
                            80 => "__logx",
                            128 => "logf128",
                        },
                        .log2 => switch (bits) {
                            else => unreachable,
                            16 => "__log2h",
                            32 => "log2f",
                            64 => "log2",
                            80 => "__log2x",
                            128 => "log2f128",
                        },
                        .log10 => switch (bits) {
                            else => unreachable,
                            16 => "__log10h",
                            32 => "log10f",
                            64 => "log10",
                            80 => "__log10x",
                            128 => "log10f128",
                        },
                    },
                    .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                });
                try isel.emit(.bl(0));
                try call.finishCallee(isel);

                try call.prepareParams(isel);
                const src_vi = try isel.use(un_op);
                switch (bits) {
                    else => unreachable,
                    16, 32, 64, 128 => try call.paramLiveOut(isel, src_vi, .v0),
                    80 => {
                        var src_hi16_it = src_vi.field(ty, 8, 8);
                        const src_hi16_vi = try src_hi16_it.only(isel);
                        try call.paramLiveOut(isel, src_hi16_vi.?, .r1);
                        var src_lo64_it = src_vi.field(ty, 0, 8);
                        const src_lo64_vi = try src_lo64_it.only(isel);
                        try call.paramLiveOut(isel, src_lo64_vi.?, .r0);
                    },
                }
                try call.finishParams(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .abs => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const ty = ty_op.ty;
                if (!ty.isRuntimeFloat()) {
                    if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                    switch (ty.intInfo(zcu).bits) {
                        0 => unreachable,
                        1...32 => {
                            const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                            const src_vi = try isel.use(ty_op.operand);
                            const src_mat = try src_vi.matReg(isel);
                            try isel.emit(.csneg(res_ra.w(), src_mat.ra.w(), src_mat.ra.w(), .pl));
                            try isel.emit(.subs(.wzr, src_mat.ra.w(), .{ .immediate = 0 }));
                            try src_mat.finish(isel);
                        },
                        33...64 => {
                            const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                            const src_vi = try isel.use(ty_op.operand);
                            const src_mat = try src_vi.matReg(isel);
                            try isel.emit(.csneg(res_ra.x(), src_mat.ra.x(), src_mat.ra.x(), .pl));
                            try isel.emit(.subs(.xzr, src_mat.ra.x(), .{ .immediate = 0 }));
                            try src_mat.finish(isel);
                        },
                        65...128 => {
                            var res_hi64_it = res_vi.value.field(ty, 8, 8);
                            const res_hi64_vi = try res_hi64_it.only(isel);
                            const res_hi64_ra = try res_hi64_vi.?.defReg(isel);
                            var res_lo64_it = res_vi.value.field(ty, 0, 8);
                            const res_lo64_vi = try res_lo64_it.only(isel);
                            const res_lo64_ra = try res_lo64_vi.?.defReg(isel);
                            if (res_hi64_ra == null and res_lo64_ra == null) break :unused;
                            const src_ty = isel.air.typeOf(ty_op.operand, ip);
                            const src_vi = try isel.use(ty_op.operand);
                            var src_hi64_it = src_vi.field(src_ty, 8, 8);
                            const src_hi64_vi = try src_hi64_it.only(isel);
                            const src_hi64_mat = try src_hi64_vi.?.matReg(isel);
                            var src_lo64_it = src_vi.field(src_ty, 0, 8);
                            const src_lo64_vi = try src_lo64_it.only(isel);
                            const src_lo64_mat = try src_lo64_vi.?.matReg(isel);
                            const lo64_ra = try isel.allocIntReg();
                            defer isel.freeReg(lo64_ra);
                            const hi64_ra, const mask_ra = alloc_ras: {
                                const res_lo64_lock: RegLock = if (res_lo64_ra) |res_ra| isel.tryLockReg(res_ra) else .empty;
                                defer res_lo64_lock.unlock(isel);
                                break :alloc_ras .{ try isel.allocIntReg(), try isel.allocIntReg() };
                            };
                            defer {
                                isel.freeReg(hi64_ra);
                                isel.freeReg(mask_ra);
                            }
                            if (res_hi64_ra) |res_ra| try isel.emit(.sbc(res_ra.x(), hi64_ra.x(), mask_ra.x()));
                            try isel.emit(.subs(
                                if (res_lo64_ra) |res_ra| res_ra.x() else .xzr,
                                lo64_ra.x(),
                                .{ .register = mask_ra.x() },
                            ));
                            if (res_hi64_ra) |_| try isel.emit(.eor(hi64_ra.x(), src_hi64_mat.ra.x(), .{ .register = mask_ra.x() }));
                            try isel.emit(.eor(lo64_ra.x(), src_lo64_mat.ra.x(), .{ .register = mask_ra.x() }));
                            try isel.emit(.sbfm(mask_ra.x(), src_hi64_mat.ra.x(), .{
                                .N = .doubleword,
                                .immr = 64 - 1,
                                .imms = 64 - 1,
                            }));
                            try src_lo64_mat.finish(isel);
                            try src_hi64_mat.finish(isel);
                        },
                        else => return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) }),
                    }
                } else switch (ty.floatBits(isel.target)) {
                    else => unreachable,
                    16 => {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        const src_mat = try src_vi.matReg(isel);
                        try isel.emit(if (isel.target.cpu.has(.aarch64, .fullfp16))
                            .fabs(res_ra.h(), src_mat.ra.h())
                        else
                            .bic(res_ra.@"4h"(), res_ra.@"4h"(), .{ .shifted_immediate = .{
                                .immediate = 0b10000000,
                                .lsl = 8,
                            } }));
                        try src_mat.finish(isel);
                    },
                    32 => {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        const src_mat = try src_vi.matReg(isel);
                        try isel.emit(.fabs(res_ra.s(), src_mat.ra.s()));
                        try src_mat.finish(isel);
                    },
                    64 => {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        const src_mat = try src_vi.matReg(isel);
                        try isel.emit(.fabs(res_ra.d(), src_mat.ra.d()));
                        try src_mat.finish(isel);
                    },
                    80 => {
                        const src_vi = try isel.use(ty_op.operand);
                        var res_hi16_it = res_vi.value.field(ty, 8, 8);
                        const res_hi16_vi = try res_hi16_it.only(isel);
                        if (try res_hi16_vi.?.defReg(isel)) |res_hi16_ra| {
                            var src_hi16_it = src_vi.field(ty, 8, 8);
                            const src_hi16_vi = try src_hi16_it.only(isel);
                            const src_hi16_mat = try src_hi16_vi.?.matReg(isel);
                            try isel.emit(.@"and"(res_hi16_ra.w(), src_hi16_mat.ra.w(), .{ .immediate = .{
                                .N = .word,
                                .immr = 0,
                                .imms = 15 - 1,
                            } }));
                            try src_hi16_mat.finish(isel);
                        }
                        var res_lo64_it = res_vi.value.field(ty, 0, 8);
                        const res_lo64_vi = try res_lo64_it.only(isel);
                        if (try res_lo64_vi.?.defReg(isel)) |res_lo64_ra| {
                            var src_lo64_it = src_vi.field(ty, 0, 8);
                            const src_lo64_vi = try src_lo64_it.only(isel);
                            try src_lo64_vi.?.liveOut(isel, res_lo64_ra);
                        }
                    },
                    128 => {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        const src_mat = try src_vi.matReg(isel);
                        const neg_zero_ra = try isel.allocVecReg();
                        defer isel.freeReg(neg_zero_ra);
                        try isel.emit(.bic(res_ra.@"16b"(), src_mat.ra.@"16b"(), .{ .register = neg_zero_ra.@"16b"() }));
                        try isel.literals.appendNTimes(gpa, 0, -%isel.literals.items.len % 4);
                        try isel.literal_relocs.append(gpa, .{
                            .label = @intCast(isel.instructions.items.len),
                        });
                        try isel.emit(.ldr(neg_zero_ra.q(), .{
                            .literal = @intCast((isel.instructions.items.len + 1 + isel.literals.items.len) << 2),
                        }));
                        try isel.emitLiteral(&(@as([15]u8, @splat(0)) ++ .{0x80}));
                        try src_mat.finish(isel);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .neg, .neg_optimized => {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const un_op = air.data(air.inst_index).un_op;
                const ty = isel.air.typeOf(un_op, ip);
                switch (ty.floatBits(isel.target)) {
                    else => unreachable,
                    16 => {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(un_op);
                        const src_mat = try src_vi.matReg(isel);
                        if (isel.target.cpu.has(.aarch64, .fullfp16)) {
                            try isel.emit(.fneg(res_ra.h(), src_mat.ra.h()));
                        } else {
                            const neg_zero_ra = try isel.allocVecReg();
                            defer isel.freeReg(neg_zero_ra);
                            try isel.emit(.eor(res_ra.@"8b"(), res_ra.@"8b"(), .{ .register = neg_zero_ra.@"8b"() }));
                            try isel.emit(.movi(neg_zero_ra.@"4h"(), 0b10000000, .{ .lsl = 8 }));
                        }
                        try src_mat.finish(isel);
                    },
                    32 => {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(un_op);
                        const src_mat = try src_vi.matReg(isel);
                        try isel.emit(.fneg(res_ra.s(), src_mat.ra.s()));
                        try src_mat.finish(isel);
                    },
                    64 => {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(un_op);
                        const src_mat = try src_vi.matReg(isel);
                        try isel.emit(.fneg(res_ra.d(), src_mat.ra.d()));
                        try src_mat.finish(isel);
                    },
                    80 => {
                        const src_vi = try isel.use(un_op);
                        var res_hi16_it = res_vi.value.field(ty, 8, 8);
                        const res_hi16_vi = try res_hi16_it.only(isel);
                        if (try res_hi16_vi.?.defReg(isel)) |res_hi16_ra| {
                            var src_hi16_it = src_vi.field(ty, 8, 8);
                            const src_hi16_vi = try src_hi16_it.only(isel);
                            const src_hi16_mat = try src_hi16_vi.?.matReg(isel);
                            try isel.emit(.eor(res_hi16_ra.w(), src_hi16_mat.ra.w(), .{ .immediate = .{
                                .N = .word,
                                .immr = 32 - 15,
                                .imms = 1 - 1,
                            } }));
                            try src_hi16_mat.finish(isel);
                        }
                        var res_lo64_it = res_vi.value.field(ty, 0, 8);
                        const res_lo64_vi = try res_lo64_it.only(isel);
                        if (try res_lo64_vi.?.defReg(isel)) |res_lo64_ra| {
                            var src_lo64_it = src_vi.field(ty, 0, 8);
                            const src_lo64_vi = try src_lo64_it.only(isel);
                            try src_lo64_vi.?.liveOut(isel, res_lo64_ra);
                        }
                    },
                    128 => {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(un_op);
                        const src_mat = try src_vi.matReg(isel);
                        const neg_zero_ra = try isel.allocVecReg();
                        defer isel.freeReg(neg_zero_ra);
                        try isel.emit(.eor(res_ra.@"16b"(), src_mat.ra.@"16b"(), .{ .register = neg_zero_ra.@"16b"() }));
                        try isel.literals.appendNTimes(gpa, 0, -%isel.literals.items.len % 4);
                        try isel.literal_relocs.append(gpa, .{
                            .label = @intCast(isel.instructions.items.len),
                        });
                        try isel.emit(.ldr(neg_zero_ra.q(), .{
                            .literal = @intCast((isel.instructions.items.len + 1 + isel.literals.items.len) << 2),
                        }));
                        try isel.emitLiteral(&(@as([15]u8, @splat(0)) ++ .{0x80}));
                        try src_mat.finish(isel);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .cmp_vector, .cmp_vector_optimized => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const ty_pl = air.data(air.inst_index).ty_pl;
                const extra = isel.air.extraData(Air.VectorCmp, ty_pl.payload).data;
                const vec_ty = isel.air.typeOf(extra.lhs, ip);
                const vector_type = ip.indexToKey(vec_ty.toIntern()).vector_type;
                const elem_ty: ZigType = .fromInterned(vector_type.child);
                const elem_size = elem_ty.abiSize(zcu);
                if (vector_type.len > 64 or vec_ty.bitSize(zcu) != vector_type.len * elem_size * 8) {
                    return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(vec_ty) });
                }
                const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                const lhs_vi = try isel.use(extra.lhs);
                const rhs_vi = try isel.use(extra.rhs);
                var res_lock = isel.lockReg(res_ra);
                defer res_lock.unlock(isel);
                const tmp_ra = try isel.allocIntReg();
                defer isel.freeReg(tmp_ra);

                const cmp_op = extra.compareOperator();
                var elem_index: u64 = vector_type.len;
                while (elem_index > 0) {
                    elem_index -= 1;
                    var lhs_elem_it = lhs_vi.field(vec_ty, elem_index * elem_size, elem_size);
                    const lhs_elem_vi = (try lhs_elem_it.only(isel)).?;
                    var rhs_elem_it = rhs_vi.field(vec_ty, elem_index * elem_size, elem_size);
                    const rhs_elem_vi = (try rhs_elem_it.only(isel)).?;
                    if (elem_index > 0) {
                        try isel.emit(.bfm(res_ra.x(), tmp_ra.x(), .{
                            .N = .doubleword,
                            .immr = @as(u6, @truncate(64 - elem_index)),
                            .imms = 0,
                        }));
                        _ = try isel.cmp(tmp_ra, elem_ty, lhs_elem_vi, cmp_op, rhs_elem_vi);
                    } else {
                        _ = try isel.cmp(res_ra, elem_ty, lhs_elem_vi, cmp_op, rhs_elem_vi);
                    }
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .cmp_lt,
        .cmp_lt_optimized,
        .cmp_lte,
        .cmp_lte_optimized,
        .cmp_eq,
        .cmp_eq_optimized,
        .cmp_gte,
        .cmp_gte_optimized,
        .cmp_gt,
        .cmp_gt_optimized,
        .cmp_neq,
        .cmp_neq_optimized,
        => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                switch (ip.indexToKey(ty.toIntern())) {
                    else => {},
                    .opt_type => |payload_ty| switch (air_tag) {
                        else => unreachable,
                        .cmp_eq, .cmp_eq_optimized, .cmp_neq, .cmp_neq_optimized => if (!ty.optionalReprIsPayload(zcu)) {
                            const lhs_vi = try isel.use(bin_op.lhs);
                            const rhs_vi = try isel.use(bin_op.rhs);
                            const payload_size = ZigType.abiSize(.fromInterned(payload_ty), zcu);
                            var lhs_payload_part_it = lhs_vi.field(ty, 0, payload_size);
                            const lhs_payload_part_vi = try lhs_payload_part_it.only(isel);
                            var rhs_payload_part_it = rhs_vi.field(ty, 0, payload_size);
                            const rhs_payload_part_vi = try rhs_payload_part_it.only(isel);
                            const cmp_info = try isel.cmp(
                                try res_vi.value.defReg(isel) orelse break :unused,
                                .fromInterned(payload_ty),
                                lhs_payload_part_vi.?,
                                air_tag.toCmpOp().?,
                                rhs_payload_part_vi.?,
                            );
                            try isel.emit(.@"b."(
                                .vc,
                                @intCast((isel.instructions.items.len + 1 - cmp_info.cset_label) << 2),
                            ));
                            var lhs_has_value_part_it = lhs_vi.field(ty, payload_size, 1);
                            const lhs_has_value_part_vi = try lhs_has_value_part_it.only(isel);
                            const lhs_has_value_part_mat = try lhs_has_value_part_vi.?.matReg(isel);
                            var rhs_has_value_part_it = rhs_vi.field(ty, payload_size, 1);
                            const rhs_has_value_part_vi = try rhs_has_value_part_it.only(isel);
                            const rhs_has_value_part_mat = try rhs_has_value_part_vi.?.matReg(isel);
                            try isel.emit(.ccmp(
                                lhs_has_value_part_mat.ra.w(),
                                .{ .register = rhs_has_value_part_mat.ra.w() },
                                .{ .n = false, .z = false, .c = false, .v = true },
                                .eq,
                            ));
                            try isel.emit(.ands(
                                .wzr,
                                lhs_has_value_part_mat.ra.w(),
                                .{ .register = rhs_has_value_part_mat.ra.w() },
                            ));
                            try rhs_has_value_part_mat.finish(isel);
                            try lhs_has_value_part_mat.finish(isel);
                            break :unused;
                        },
                    },
                }
                _ = try isel.cmp(
                    try res_vi.value.defReg(isel) orelse break :unused,
                    ty,
                    try isel.use(bin_op.lhs),
                    air_tag.toCmpOp().?,
                    try isel.use(bin_op.rhs),
                );
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .switch_dispatch => {
            const br = air.data(air.inst_index).br;
            const target_loop = isel.loops.getPtr(br.block_inst).?;
            try target_loop.branch(isel);
            const cond_ty = isel.air.typeOf(br.operand, ip);
            const cond_size = cond_ty.abiSize(zcu);
            var cond_vi = try isel.use(br.operand);
            if (cond_size > 0) {
                const cond_mat = try cond_vi.matReg(isel);
                try isel.storeReg(
                    cond_mat.ra,
                    cond_size,
                    .sp,
                    target_loop.dispatch_slot_offset,
                );
                try cond_mat.finish(isel);
            } else {
                cond_vi.deref(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .dbg_stmt => if (air.next()) |next_air_tag| continue :air_tag next_air_tag,
        .dbg_empty_stmt => {
            try isel.emit(.nop());
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .dbg_var_ptr, .dbg_var_val, .dbg_arg_inline => {
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .is_null, .is_non_null, .is_null_ptr, .is_non_null_ptr => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |is_vi| unused: {
                defer is_vi.value.deref(isel);
                const is_ra = try is_vi.value.defReg(isel) orelse break :unused;

                const un_op = air.data(air.inst_index).un_op;
                const operand_ty = isel.air.typeOf(un_op, ip);
                const is_ptr = switch (air_tag) {
                    else => unreachable,
                    .is_null, .is_non_null => false,
                    .is_null_ptr, .is_non_null_ptr => true,
                };
                const opt_ty: ZigType = if (is_ptr) .fromInterned(operand_ty.ptrInfo(zcu).child) else operand_ty;
                const payload_ty = opt_ty.optionalChild(zcu);
                const payload_size = payload_ty.abiSize(zcu);
                const has_value_offset, const has_value_size = if (!opt_ty.optionalReprIsPayload(zcu))
                    .{ payload_size, 1 }
                else if (payload_ty.isSlice(zcu))
                    .{ 0, 8 }
                else
                    .{ 0, payload_size };

                try isel.emit(.csinc(is_ra.w(), .wzr, .wzr, .invert(switch (air_tag) {
                    else => unreachable,
                    .is_null, .is_null_ptr => .eq,
                    .is_non_null, .is_non_null_ptr => .ne,
                })));
                if (is_ptr) {
                    const ptr_vi = try isel.use(un_op);
                    const ptr_mat = try ptr_vi.matReg(isel);
                    const temp_ra = try isel.allocIntReg();
                    defer isel.freeReg(temp_ra);
                    try isel.emit(switch (has_value_size) {
                        else => unreachable,
                        1...4 => .subs(.wzr, temp_ra.w(), .{ .immediate = 0 }),
                        5...8 => .subs(.xzr, temp_ra.x(), .{ .immediate = 0 }),
                    });
                    try isel.loadReg(temp_ra, has_value_size, .unsigned, ptr_mat.ra, has_value_offset);
                    try ptr_mat.finish(isel);
                } else {
                    const opt_vi = try isel.use(un_op);
                    var has_value_part_it = opt_vi.field(opt_ty, has_value_offset, has_value_size);
                    const has_value_part_vi = try has_value_part_it.only(isel);
                    const has_value_part_mat = try has_value_part_vi.?.matReg(isel);
                    try isel.emit(switch (has_value_size) {
                        else => unreachable,
                        1...4 => .subs(.wzr, has_value_part_mat.ra.w(), .{ .immediate = 0 }),
                        5...8 => .subs(.xzr, has_value_part_mat.ra.x(), .{ .immediate = 0 }),
                    });
                    try has_value_part_mat.finish(isel);
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .is_err, .is_non_err, .is_err_ptr, .is_non_err_ptr => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |is_vi| unused: {
                defer is_vi.value.deref(isel);
                const is_ra = try is_vi.value.defReg(isel) orelse break :unused;

                const un_op = air.data(air.inst_index).un_op;
                const operand_ty = isel.air.typeOf(un_op, ip);
                const is_ptr = switch (air_tag) {
                    else => unreachable,
                    .is_err, .is_non_err => false,
                    .is_err_ptr, .is_non_err_ptr => true,
                };
                const error_union_ty: ZigType = if (is_ptr) .fromInterned(operand_ty.ptrInfo(zcu).child) else operand_ty;
                const error_union_info = ip.indexToKey(error_union_ty.toIntern()).error_union_type;
                const error_set_ty: ZigType = .fromInterned(error_union_info.error_set_type);
                const payload_ty: ZigType = .fromInterned(error_union_info.payload_type);
                const error_set_offset = codegen.errUnionErrorOffset(payload_ty, zcu);
                const error_set_size = error_set_ty.abiSize(zcu);

                try isel.emit(.csinc(is_ra.w(), .wzr, .wzr, .invert(switch (air_tag) {
                    else => unreachable,
                    .is_err, .is_err_ptr => .ne,
                    .is_non_err, .is_non_err_ptr => .eq,
                })));
                if (is_ptr) {
                    const ptr_vi = try isel.use(un_op);
                    const ptr_mat = try ptr_vi.matReg(isel);
                    const temp_ra = try isel.allocIntReg();
                    defer isel.freeReg(temp_ra);
                    try isel.emit(.ands(.wzr, temp_ra.w(), .{ .immediate = .{
                        .N = .word,
                        .immr = 0,
                        .imms = @intCast(8 * error_set_size - 1),
                    } }));
                    try isel.loadReg(temp_ra, error_set_size, .unsigned, ptr_mat.ra, error_set_offset);
                    try ptr_mat.finish(isel);
                } else {
                    const error_union_vi = try isel.use(un_op);
                    var error_set_part_it = error_union_vi.field(error_union_ty, error_set_offset, error_set_size);
                    const error_set_part_vi = try error_set_part_it.only(isel);
                    const error_set_part_mat = try error_set_part_vi.?.matReg(isel);
                    try isel.emit(.ands(.wzr, error_set_part_mat.ra.w(), .{ .immediate = .{
                        .N = .word,
                        .immr = 0,
                        .imms = @intCast(8 * error_set_size - 1),
                    } }));
                    try error_set_part_mat.finish(isel);
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .load => {
            const ty_op = air.data(air.inst_index).ty_op;
            const ptr_ty = isel.air.typeOf(ty_op.operand, ip);
            const ptr_info = ptr_ty.ptrInfo(zcu);
            if (ptr_info.packed_offset.host_size > 0) return isel.fail("packed load", .{});

            if (ptr_info.flags.is_volatile) _ = try isel.use(air.inst_index.toRef());
            if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);
                const size = dst_vi.value.size(isel);
                if (size <= Value.max_parts and ip.zigTypeTag(ptr_info.child) != .@"union") {
                    const ptr_vi = try isel.use(ty_op.operand);
                    const ptr_mat = try ptr_vi.matReg(isel);
                    _ = try dst_vi.value.load(isel, ty_op.ty, ptr_mat.ra, .{
                        .@"volatile" = ptr_info.flags.is_volatile,
                    });
                    try ptr_mat.finish(isel);
                } else {
                    try dst_vi.value.defAddr(isel, .fromInterned(ptr_info.child), .{}) orelse break :unused;

                    try call.prepareReturn(isel);
                    try call.finishReturn(isel);

                    try call.prepareCallee(isel);
                    try isel.global_relocs.append(gpa, .{
                        .name = "memcpy",
                        .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                    });
                    try isel.emit(.bl(0));
                    try call.finishCallee(isel);

                    try call.prepareParams(isel);
                    const ptr_vi = try isel.use(ty_op.operand);
                    try isel.movImmediate(.x2, size);
                    try call.paramLiveOut(isel, ptr_vi, .r1);
                    try call.paramAddress(isel, dst_vi.value, .r0);
                    try call.finishParams(isel);
                }
            }

            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .ret, .ret_safe => {
            assert(isel.blocks.keys()[0] == Block.main);
            try isel.blocks.values()[0].branch(isel);
            if (isel.live_values.get(Block.main)) |ret_vi| {
                const un_op = air.data(air.inst_index).un_op;
                const src_vi = try isel.use(un_op);
                switch (ret_vi.parent(isel)) {
                    .unallocated, .stack_slot => if (ret_vi.hint(isel)) |ret_ra| {
                        try src_vi.liveOut(isel, ret_ra);
                    } else {
                        var ret_part_it = ret_vi.parts(isel);
                        var src_part_it = src_vi.parts(isel);
                        if (src_part_it.only()) |_| {
                            try isel.values.ensureUnusedCapacity(gpa, ret_part_it.remaining);
                            src_vi.setParts(isel, ret_part_it.remaining);
                            while (ret_part_it.next()) |ret_part_vi| {
                                const src_part_vi = src_vi.addPart(
                                    isel,
                                    ret_part_vi.get(isel).offset_from_parent,
                                    ret_part_vi.size(isel),
                                );
                                switch (ret_part_vi.signedness(isel)) {
                                    .signed => src_part_vi.setSignedness(isel, .signed),
                                    .unsigned => {},
                                }
                                if (ret_part_vi.isVector(isel)) src_part_vi.setIsVector(isel);
                            }
                            ret_part_it = ret_vi.parts(isel);
                            src_part_it = src_vi.parts(isel);
                        }
                        while (ret_part_it.next()) |ret_part_vi| {
                            const src_part_vi = src_part_it.next().?;
                            assert(ret_part_vi.get(isel).offset_from_parent == src_part_vi.get(isel).offset_from_parent);
                            assert(ret_part_vi.size(isel) == src_part_vi.size(isel));
                            try src_part_vi.liveOut(isel, ret_part_vi.hint(isel).?);
                        }
                    },
                    .value, .constant => unreachable,
                    .address => |address_vi| {
                        const ret_ty = isel.air.typeOf(un_op, ip);
                        const size = src_vi.size(isel);
                        if (ret_ty.zigTypeTag(zcu) != .@"union" and size <= Value.max_parts) {
                            const ptr_mat = try address_vi.matReg(isel);
                            try src_vi.store(isel, ret_ty, ptr_mat.ra, .{});
                            try ptr_mat.finish(isel);
                        } else {
                            try call.prepareReturn(isel);
                            try call.finishReturn(isel);

                            try call.prepareCallee(isel);
                            try isel.global_relocs.append(gpa, .{
                                .name = "memcpy",
                                .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                            });
                            try isel.emit(.bl(0));
                            try call.finishCallee(isel);

                            try call.prepareParams(isel);
                            try isel.movImmediate(.x2, size);
                            try call.paramAddress(isel, src_vi, .r1);
                            try call.paramLiveOut(isel, address_vi, .r0);
                            try call.finishParams(isel);
                        }
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .ret_load => {
            const un_op = air.data(air.inst_index).un_op;
            const ptr_ty = isel.air.typeOf(un_op, ip);
            const ptr_info = ptr_ty.ptrInfo(zcu);
            if (ptr_info.packed_offset.host_size > 0) return isel.fail("packed load", .{});

            assert(isel.blocks.keys()[0] == Block.main);
            try isel.blocks.values()[0].branch(isel);
            if (isel.live_values.get(Block.main)) |ret_vi| switch (ret_vi.parent(isel)) {
                .unallocated, .stack_slot => {
                    var ret_part_it: Value.PartIterator = if (ret_vi.hint(isel)) |_| .initOne(ret_vi) else ret_vi.parts(isel);
                    while (ret_part_it.next()) |ret_part_vi| try ret_part_vi.liveOut(isel, ret_part_vi.hint(isel).?);
                    const ptr_vi = try isel.use(un_op);
                    const ptr_mat = try ptr_vi.matReg(isel);
                    _ = try ret_vi.load(isel, .fromInterned(ptr_info.child), ptr_mat.ra, .{});
                    try ptr_mat.finish(isel);
                },
                .value, .constant => unreachable,
                .address => {},
            };
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .store,
        .store_safe,
        .atomic_store_unordered,
        .atomic_store_monotonic,
        .atomic_store_release,
        .atomic_store_seq_cst,
        => |air_tag| {
            const bin_op = air.data(air.inst_index).bin_op;
            const ptr_ty = isel.air.typeOf(bin_op.lhs, ip);
            const ptr_info = ptr_ty.ptrInfo(zcu);
            if (ptr_info.packed_offset.host_size > 0) return isel.fail("packed store", .{});
            if (bin_op.rhs.toInterned()) |rhs_val| if (ip.isUndef(rhs_val))
                break :air_tag if (air.next()) |next_air_tag| continue :air_tag next_air_tag;

            const is_release = switch (air_tag) {
                .store, .store_safe, .atomic_store_unordered, .atomic_store_monotonic => false,
                .atomic_store_release, .atomic_store_seq_cst => true,
                else => unreachable,
            };
            const is_seq_cst = air_tag == .atomic_store_seq_cst;

            const src_vi = try isel.use(bin_op.rhs);
            const size = src_vi.size(isel);
            if (ZigType.fromInterned(ptr_info.child).zigTypeTag(zcu) != .@"union") switch (size) {
                0 => unreachable,
                1...Value.max_parts => {
                    if (is_seq_cst) try isel.emit(.dsb(.ish));
                    const ptr_vi = try isel.use(bin_op.lhs);
                    const ptr_mat = try ptr_vi.matReg(isel);
                    try src_vi.store(isel, isel.air.typeOf(bin_op.rhs, ip), ptr_mat.ra, .{
                        .@"volatile" = ptr_info.flags.is_volatile,
                    });
                    try ptr_mat.finish(isel);
                    if (is_release) try isel.emit(.dsb(.ish));

                    break :air_tag if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
                },
                else => {},
            };
            try call.prepareReturn(isel);
            try call.finishReturn(isel);

            try call.prepareCallee(isel);
            try isel.global_relocs.append(gpa, .{
                .name = "memcpy",
                .reloc = .{ .label = @intCast(isel.instructions.items.len) },
            });
            try isel.emit(.bl(0));
            try call.finishCallee(isel);

            try call.prepareParams(isel);
            const ptr_vi = try isel.use(bin_op.lhs);
            try isel.movImmediate(.x2, size);
            try call.paramAddress(isel, src_vi, .r1);
            try call.paramLiveOut(isel, ptr_vi, .r0);
            try call.finishParams(isel);

            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .unreach => if (air.next()) |next_air_tag| continue :air_tag next_air_tag,
        .fptrunc, .fpext => {
            if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const dst_ty = ty_op.ty;
                const dst_bits = dst_ty.floatBits(isel.target);
                const src_ty = isel.air.typeOf(ty_op.operand, ip);
                const src_bits = src_ty.floatBits(isel.target);
                assert(dst_bits != src_bits);
                switch (@max(dst_bits, src_bits)) {
                    else => unreachable,
                    16, 32, 64 => {
                        const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        const src_mat = try src_vi.matReg(isel);
                        try isel.emit(.fcvt(switch (dst_bits) {
                            else => unreachable,
                            16 => dst_ra.h(),
                            32 => dst_ra.s(),
                            64 => dst_ra.d(),
                        }, switch (src_bits) {
                            else => unreachable,
                            16 => src_mat.ra.h(),
                            32 => src_mat.ra.s(),
                            64 => src_mat.ra.d(),
                        }));
                        try src_mat.finish(isel);
                    },
                    80, 128 => {
                        try call.prepareReturn(isel);
                        switch (dst_bits) {
                            else => unreachable,
                            16, 32, 64, 128 => try call.returnLiveIn(isel, dst_vi.value, .v0),
                            80 => {
                                var dst_hi16_it = dst_vi.value.field(dst_ty, 8, 8);
                                const dst_hi16_vi = try dst_hi16_it.only(isel);
                                try call.returnLiveIn(isel, dst_hi16_vi.?, .r1);
                                var dst_lo64_it = dst_vi.value.field(dst_ty, 0, 8);
                                const dst_lo64_vi = try dst_lo64_it.only(isel);
                                try call.returnLiveIn(isel, dst_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishReturn(isel);

                        try call.prepareCallee(isel);
                        try isel.global_relocs.append(gpa, .{
                            .name = switch (dst_bits) {
                                else => unreachable,
                                16 => switch (src_bits) {
                                    else => unreachable,
                                    32 => "__truncsfhf2",
                                    64 => "__truncdfhf2",
                                    80 => "__truncxfhf2",
                                    128 => "__trunctfhf2",
                                },
                                32 => switch (src_bits) {
                                    else => unreachable,
                                    16 => "__extendhfsf2",
                                    64 => "__truncdfsf2",
                                    80 => "__truncxfsf2",
                                    128 => "__trunctfsf2",
                                },
                                64 => switch (src_bits) {
                                    else => unreachable,
                                    16 => "__extendhfdf2",
                                    32 => "__extendsfdf2",
                                    80 => "__truncxfdf2",
                                    128 => "__trunctfdf2",
                                },
                                80 => switch (src_bits) {
                                    else => unreachable,
                                    16 => "__extendhfxf2",
                                    32 => "__extendsfxf2",
                                    64 => "__extenddfxf2",
                                    128 => "__trunctfxf2",
                                },
                                128 => switch (src_bits) {
                                    else => unreachable,
                                    16 => "__extendhftf2",
                                    32 => "__extendsftf2",
                                    64 => "__extenddftf2",
                                    80 => "__extendxftf2",
                                },
                            },
                            .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                        });
                        try isel.emit(.bl(0));
                        try call.finishCallee(isel);

                        try call.prepareParams(isel);
                        const src_vi = try isel.use(ty_op.operand);
                        switch (src_bits) {
                            else => unreachable,
                            16, 32, 64, 128 => try call.paramLiveOut(isel, src_vi, .v0),
                            80 => {
                                var src_hi16_it = src_vi.field(src_ty, 8, 8);
                                const src_hi16_vi = try src_hi16_it.only(isel);
                                try call.paramLiveOut(isel, src_hi16_vi.?, .r1);
                                var src_lo64_it = src_vi.field(src_ty, 0, 8);
                                const src_lo64_vi = try src_lo64_it.only(isel);
                                try call.paramLiveOut(isel, src_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishParams(isel);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .int_cast => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const dst_ty = ty_op.ty;
                const dst_int_info = dst_ty.intInfo(zcu);
                const src_ty = isel.air.typeOf(ty_op.operand, ip);
                const src_int_info = src_ty.intInfo(zcu);
                const can_be_negative = dst_int_info.signedness == .signed and
                    src_int_info.signedness == .signed;
                if (dst_ty.isVector(zcu)) {
                    const vec_len = dst_ty.vectorLen(zcu);
                    const dst_elem_ty = dst_ty.childType(zcu);
                    const dst_elem_size = dst_elem_ty.abiSize(zcu);
                    const src_elem_ty = src_ty.childType(zcu);
                    const src_elem_size = src_elem_ty.abiSize(zcu);
                    const dst_unpacked = dst_ty.bitSize(zcu) == vec_len * dst_elem_size * 8;
                    const src_unpacked = src_ty.bitSize(zcu) == vec_len * src_elem_size * 8;
                    if (!dst_unpacked and !src_unpacked and dst_int_info.bits == src_int_info.bits) {
                        try dst_vi.value.move(isel, ty_op.operand);
                    } else if (dst_unpacked and !src_unpacked and dst_elem_size <= 8 and src_ty.abiSize(zcu) <= 8) {
                        const src_vi = try isel.use(ty_op.operand);
                        var elem_index: u64 = vec_len;
                        while (elem_index > 0) {
                            elem_index -= 1;
                            var dst_elem_it = dst_vi.value.field(dst_ty, elem_index * dst_elem_size, dst_elem_size);
                            const dst_elem_vi = (try dst_elem_it.only(isel)).?;
                            const dst_elem_ra = try dst_elem_vi.defReg(isel) orelse continue;
                            const src_mat = try src_vi.matReg(isel);
                            const bit_offset: u6 = @intCast(elem_index * src_int_info.bits);
                            const bit_end: u6 = @intCast(bit_offset + src_int_info.bits - 1);
                            try isel.emit(if (can_be_negative)
                                .sbfm(dst_elem_ra.x(), src_mat.ra.x(), .{
                                    .N = .doubleword,
                                    .immr = bit_offset,
                                    .imms = bit_end,
                                })
                            else
                                .ubfm(dst_elem_ra.x(), src_mat.ra.x(), .{
                                    .N = .doubleword,
                                    .immr = bit_offset,
                                    .imms = bit_end,
                                }));
                            try src_mat.finish(isel);
                        }
                    } else if (!dst_unpacked and src_unpacked and dst_ty.abiSize(zcu) <= 8 and src_elem_size <= 8) {
                        const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        var dst_lock = isel.lockReg(dst_ra);
                        defer dst_lock.unlock(isel);
                        var elem_index: u64 = vec_len;
                        while (elem_index > 0) {
                            elem_index -= 1;
                            var src_elem_it = src_vi.field(src_ty, elem_index * src_elem_size, src_elem_size);
                            const src_elem_vi = (try src_elem_it.only(isel)).?;
                            const src_elem_mat = try src_elem_vi.matReg(isel);
                            const bit_offset: u6 = @intCast(elem_index * dst_int_info.bits);
                            if (bit_offset > 0) {
                                try isel.emit(.bfm(dst_ra.x(), src_elem_mat.ra.x(), .{
                                    .N = .doubleword,
                                    .immr = @as(u6, @truncate(64 - @as(u7, bit_offset))),
                                    .imms = @intCast(dst_int_info.bits - 1),
                                }));
                            } else {
                                try isel.emit(.ubfm(dst_ra.x(), src_elem_mat.ra.x(), .{
                                    .N = .doubleword,
                                    .immr = 0,
                                    .imms = @intCast(dst_int_info.bits - 1),
                                }));
                            }
                            try src_elem_mat.finish(isel);
                        }
                    } else if (dst_unpacked and src_unpacked and dst_elem_size <= 8 and src_elem_size <= 8) {
                        const src_vi = try isel.use(ty_op.operand);
                        var elem_index: u64 = vec_len;
                        while (elem_index > 0) {
                            elem_index -= 1;
                            var dst_elem_it = dst_vi.value.field(dst_ty, elem_index * dst_elem_size, dst_elem_size);
                            const dst_elem_vi = (try dst_elem_it.only(isel)).?;
                            var src_elem_it = src_vi.field(src_ty, elem_index * src_elem_size, src_elem_size);
                            const src_elem_vi = (try src_elem_it.only(isel)).?;
                            const dst_elem_ra = try dst_elem_vi.defReg(isel) orelse continue;
                            const src_elem_mat = try src_elem_vi.matReg(isel);
                            if (dst_int_info.bits <= 32 and src_int_info.bits <= 64 and
                                (!can_be_negative or dst_elem_size <= src_elem_size))
                            {
                                try isel.emit(.orr(dst_elem_ra.w(), .wzr, .{ .register = src_elem_mat.ra.w() }));
                            } else if (can_be_negative) {
                                try isel.emit(.sbfm(dst_elem_ra.x(), src_elem_mat.ra.x(), .{
                                    .N = .doubleword,
                                    .immr = 0,
                                    .imms = @intCast(src_int_info.bits - 1),
                                }));
                            } else {
                                try isel.emit(.ubfm(dst_elem_ra.x(), src_elem_mat.ra.x(), .{
                                    .N = .doubleword,
                                    .immr = 0,
                                    .imms = @intCast(src_int_info.bits - 1),
                                }));
                            }
                            try src_elem_mat.finish(isel);
                        }
                    } else return isel.fail("too big {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) });
                } else if ((dst_int_info.bits <= 8 and src_int_info.bits <= 8) or
                    (dst_int_info.bits > 8 and dst_int_info.bits <= 16 and
                        src_int_info.bits > 8 and src_int_info.bits <= 16) or
                    (dst_int_info.bits > 16 and dst_int_info.bits <= 32 and
                        src_int_info.bits > 16 and src_int_info.bits <= 32) or
                    (dst_int_info.bits > 32 and dst_int_info.bits <= 64 and
                        src_int_info.bits > 32 and src_int_info.bits <= 64) or
                    (dst_int_info.bits > 64 and src_int_info.bits > 64 and
                        (dst_int_info.bits - 1) / 128 == (src_int_info.bits - 1) / 128))
                {
                    try dst_vi.value.move(isel, ty_op.operand);
                } else if (dst_int_info.bits <= 32 and src_int_info.bits <= 64) {
                    const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                    const src_vi = try isel.use(ty_op.operand);
                    const src_mat = try src_vi.matReg(isel);
                    try isel.emit(.orr(dst_ra.w(), .wzr, .{ .register = src_mat.ra.w() }));
                    try src_mat.finish(isel);
                } else if (dst_int_info.bits <= 64 and src_int_info.bits <= 32) {
                    const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                    const src_vi = try isel.use(ty_op.operand);
                    const src_mat = try src_vi.matReg(isel);
                    try isel.emit(if (can_be_negative) .sbfm(dst_ra.x(), src_mat.ra.x(), .{
                        .N = .doubleword,
                        .immr = 0,
                        .imms = @intCast(src_int_info.bits - 1),
                    }) else .orr(dst_ra.w(), .wzr, .{ .register = src_mat.ra.w() }));
                    try src_mat.finish(isel);
                } else if (dst_int_info.bits <= 32 and src_int_info.bits <= 128) {
                    assert(src_int_info.bits > 64);
                    const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                    const src_vi = try isel.use(ty_op.operand);

                    var src_lo64_it = src_vi.field(src_ty, 0, 8);
                    const src_lo64_vi = try src_lo64_it.only(isel);
                    const src_lo64_mat = try src_lo64_vi.?.matReg(isel);
                    try isel.emit(.orr(dst_ra.w(), .wzr, .{ .register = src_lo64_mat.ra.w() }));
                    try src_lo64_mat.finish(isel);
                } else if (dst_int_info.bits <= 64 and src_int_info.bits <= 128) {
                    assert(dst_int_info.bits > 32 and src_int_info.bits > 64);
                    const src_vi = try isel.use(ty_op.operand);

                    var src_lo64_it = src_vi.field(src_ty, 0, 8);
                    const src_lo64_vi = try src_lo64_it.only(isel);
                    try dst_vi.value.copy(isel, dst_ty, src_lo64_vi.?);
                } else if (dst_int_info.bits <= 128 and src_int_info.bits <= 64) {
                    assert(dst_int_info.bits > 64);
                    const src_vi = try isel.use(ty_op.operand);

                    var dst_lo64_it = dst_vi.value.field(dst_ty, 0, 8);
                    const dst_lo64_vi = try dst_lo64_it.only(isel);
                    if (src_int_info.bits <= 32) unused_lo64: {
                        const dst_lo64_ra = try dst_lo64_vi.?.defReg(isel) orelse break :unused_lo64;
                        const src_mat = try src_vi.matReg(isel);
                        try isel.emit(if (can_be_negative) .sbfm(dst_lo64_ra.x(), src_mat.ra.x(), .{
                            .N = .doubleword,
                            .immr = 0,
                            .imms = @intCast(src_int_info.bits - 1),
                        }) else .orr(dst_lo64_ra.w(), .wzr, .{ .register = src_mat.ra.w() }));
                        try src_mat.finish(isel);
                    } else try dst_lo64_vi.?.copy(isel, src_ty, src_vi);

                    var dst_hi64_it = dst_vi.value.field(dst_ty, 8, 8);
                    const dst_hi64_vi = try dst_hi64_it.only(isel);
                    const dst_hi64_ra = try dst_hi64_vi.?.defReg(isel);
                    if (dst_hi64_ra) |dst_ra| switch (can_be_negative) {
                        false => try isel.emit(.orr(dst_ra.x(), .xzr, .{ .register = .xzr })),
                        true => {
                            const src_mat = try src_vi.matReg(isel);
                            try isel.emit(.sbfm(dst_ra.x(), src_mat.ra.x(), .{
                                .N = .doubleword,
                                .immr = @intCast(src_int_info.bits - 1),
                                .imms = @intCast(src_int_info.bits - 1),
                            }));
                            try src_mat.finish(isel);
                        },
                    };
                } else return isel.fail("too big {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) });
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .int_cast_safe => |air_tag| {
            {
                const ty_op = air.data(air.inst_index).ty_op;
                const dst_ty = ty_op.ty;
                const src_ty = isel.air.typeOf(ty_op.operand, ip);
                if (dst_ty.isVector(zcu) or dst_ty.intInfo(zcu).bits > 64 or src_ty.intInfo(zcu).bits > 64) {
                    continue :air_tag .int_cast;
                }
            }
            if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const dst_ty = ty_op.ty;
                const dst_int_info = dst_ty.intInfo(zcu);
                const src_ty = isel.air.typeOf(ty_op.operand, ip);
                const src_int_info = src_ty.intInfo(zcu);
                const can_be_negative = dst_int_info.signedness == .signed and
                    src_int_info.signedness == .signed;
                const panic_id: Zcu.SimplePanicId = panic_id: switch (dst_ty.zigTypeTag(zcu)) {
                    else => unreachable,
                    .int => .integer_out_of_bounds,
                    .@"enum" => {
                        if (!dst_ty.isNonexhaustiveEnum(zcu)) {
                            return isel.fail("bad {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) });
                        }
                        break :panic_id .invalid_enum_value;
                    },
                };
                if (dst_ty.toIntern() == src_ty.toIntern()) {
                    try dst_vi.value.move(isel, ty_op.operand);
                } else if (dst_int_info.bits <= 64 and src_int_info.bits <= 64) {
                    const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                    const src_vi = try isel.use(ty_op.operand);
                    const dst_active_bits = dst_int_info.bits - @intFromBool(dst_int_info.signedness == .signed);
                    const src_active_bits = src_int_info.bits - @intFromBool(src_int_info.signedness == .signed);
                    if ((dst_int_info.signedness != .unsigned or src_int_info.signedness != .signed) and dst_active_bits >= src_active_bits) {
                        const src_mat = try src_vi.matReg(isel);
                        try isel.emit(if (can_be_negative and dst_active_bits > 32 and src_active_bits <= 32)
                            .sbfm(dst_ra.x(), src_mat.ra.x(), .{
                                .N = .doubleword,
                                .immr = 0,
                                .imms = @intCast(src_int_info.bits - 1),
                            })
                        else switch (src_int_info.bits) {
                            else => unreachable,
                            1...32 => .orr(dst_ra.w(), .wzr, .{ .register = src_mat.ra.w() }),
                            33...64 => .orr(dst_ra.x(), .xzr, .{ .register = src_mat.ra.x() }),
                        });
                        try src_mat.finish(isel);
                    } else {
                        const skip_label = isel.instructions.items.len;
                        try isel.emitPanic(panic_id);
                        try isel.emit(.@"b."(
                            .eq,
                            @intCast((isel.instructions.items.len + 1 - skip_label) << 2),
                        ));
                        if (can_be_negative) {
                            const src_mat = src_mat: {
                                const dst_lock = isel.lockReg(dst_ra);
                                defer dst_lock.unlock(isel);
                                break :src_mat try src_vi.matReg(isel);
                            };
                            try isel.emit(switch (src_int_info.bits) {
                                else => unreachable,
                                1...32 => .subs(.wzr, dst_ra.w(), .{ .register = src_mat.ra.w() }),
                                33...64 => .subs(.xzr, dst_ra.x(), .{ .register = src_mat.ra.x() }),
                            });
                            try isel.emit(switch (@max(dst_int_info.bits, src_int_info.bits)) {
                                else => unreachable,
                                1...32 => .sbfm(dst_ra.w(), src_mat.ra.w(), .{
                                    .N = .word,
                                    .immr = 0,
                                    .imms = @intCast(dst_int_info.bits - 1),
                                }),
                                33...64 => .sbfm(dst_ra.x(), src_mat.ra.x(), .{
                                    .N = .doubleword,
                                    .immr = 0,
                                    .imms = @intCast(dst_int_info.bits - 1),
                                }),
                            });
                            try src_mat.finish(isel);
                        } else {
                            const src_mat = try src_vi.matReg(isel);
                            try isel.emit(switch (@min(dst_int_info.bits, src_int_info.bits)) {
                                else => unreachable,
                                1...32 => .orr(dst_ra.w(), .wzr, .{ .register = src_mat.ra.w() }),
                                33...64 => .orr(dst_ra.x(), .xzr, .{ .register = src_mat.ra.x() }),
                            });
                            const active_bits = @min(dst_active_bits, src_active_bits);
                            try isel.emit(switch (src_int_info.bits) {
                                else => unreachable,
                                1...32 => .ands(.wzr, src_mat.ra.w(), .{ .immediate = .{
                                    .N = .word,
                                    .immr = @intCast(32 - active_bits),
                                    .imms = @intCast(32 - active_bits - 1),
                                } }),
                                33...64 => .ands(.xzr, src_mat.ra.x(), .{ .immediate = .{
                                    .N = .doubleword,
                                    .immr = @intCast(64 - active_bits),
                                    .imms = @intCast(64 - active_bits - 1),
                                } }),
                            });
                            try src_mat.finish(isel);
                        }
                    }
                } else return isel.fail("too big {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) });
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .trunc => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const dst_ty = ty_op.ty;
                const src_ty = isel.air.typeOf(ty_op.operand, ip);
                if (dst_ty.isVector(zcu)) {
                    const vec_len = dst_ty.vectorLen(zcu);
                    const dst_elem_ty = dst_ty.childType(zcu);
                    const dst_elem_size = dst_elem_ty.abiSize(zcu);
                    const src_elem_ty = src_ty.childType(zcu);
                    const src_elem_size = src_elem_ty.abiSize(zcu);
                    const dst_unpacked = dst_ty.bitSize(zcu) == vec_len * dst_elem_size * 8;
                    const src_unpacked = src_ty.bitSize(zcu) == vec_len * src_elem_size * 8;
                    const dst_int_info = dst_ty.intInfo(zcu);
                    const src_int_info = src_ty.intInfo(zcu);
                    if (!dst_unpacked and !src_unpacked and dst_int_info.bits == src_int_info.bits) {
                        try dst_vi.value.move(isel, ty_op.operand);
                    } else if (!dst_unpacked and !src_unpacked and dst_ty.abiSize(zcu) <= 8 and src_ty.abiSize(zcu) <= 8) {
                        const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        var dst_lock = isel.lockReg(dst_ra);
                        defer dst_lock.unlock(isel);
                        const tmp_ra = try isel.allocIntReg();
                        defer isel.freeReg(tmp_ra);
                        const src_mat = try src_vi.matReg(isel);
                        var elem_index: u64 = vec_len;
                        while (elem_index > 0) {
                            elem_index -= 1;
                            const dst_bit_offset: u6 = @intCast(elem_index * dst_int_info.bits);
                            const src_bit_offset: u6 = @intCast(elem_index * src_int_info.bits);
                            if (dst_bit_offset > 0) {
                                try isel.emit(.bfm(dst_ra.x(), tmp_ra.x(), .{
                                    .N = .doubleword,
                                    .immr = @as(u6, @truncate(64 - @as(u7, dst_bit_offset))),
                                    .imms = @intCast(dst_int_info.bits - 1),
                                }));
                                try isel.emit(.ubfm(tmp_ra.x(), src_mat.ra.x(), .{
                                    .N = .doubleword,
                                    .immr = src_bit_offset,
                                    .imms = @intCast(src_bit_offset + dst_int_info.bits - 1),
                                }));
                            } else {
                                try isel.emit(.ubfm(dst_ra.x(), src_mat.ra.x(), .{
                                    .N = .doubleword,
                                    .immr = 0,
                                    .imms = @intCast(dst_int_info.bits - 1),
                                }));
                            }
                        }
                        try src_mat.finish(isel);
                    } else if (!dst_unpacked and src_unpacked and dst_ty.abiSize(zcu) <= 8 and src_elem_size <= 8) {
                        const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        var dst_lock = isel.lockReg(dst_ra);
                        defer dst_lock.unlock(isel);
                        var elem_index: u64 = vec_len;
                        while (elem_index > 0) {
                            elem_index -= 1;
                            var src_elem_it = src_vi.field(src_ty, elem_index * src_elem_size, src_elem_size);
                            const src_elem_vi = (try src_elem_it.only(isel)).?;
                            const src_elem_mat = try src_elem_vi.matReg(isel);
                            const bit_offset: u6 = @intCast(elem_index * dst_int_info.bits);
                            if (bit_offset > 0) {
                                try isel.emit(.bfm(dst_ra.x(), src_elem_mat.ra.x(), .{
                                    .N = .doubleword,
                                    .immr = @as(u6, @truncate(64 - @as(u7, bit_offset))),
                                    .imms = @intCast(dst_int_info.bits - 1),
                                }));
                            } else {
                                try isel.emit(.ubfm(dst_ra.x(), src_elem_mat.ra.x(), .{
                                    .N = .doubleword,
                                    .immr = 0,
                                    .imms = @intCast(dst_int_info.bits - 1),
                                }));
                            }
                            try src_elem_mat.finish(isel);
                        }
                    } else if (dst_unpacked and src_unpacked and dst_elem_size <= 8) {
                        const src_vi = try isel.use(ty_op.operand);
                        var elem_index: u64 = vec_len;
                        while (elem_index > 0) {
                            elem_index -= 1;
                            var dst_elem_it = dst_vi.value.field(dst_ty, elem_index * dst_elem_size, dst_elem_size);
                            const dst_elem_vi = (try dst_elem_it.only(isel)).?;
                            const dst_elem_ra = try dst_elem_vi.defReg(isel) orelse continue;
                            var src_elem_it = src_vi.field(src_ty, elem_index * src_elem_size, @min(src_elem_size, 8));
                            const src_elem_vi = (try src_elem_it.only(isel)).?;
                            const src_elem_mat = try src_elem_vi.matReg(isel);
                            try isel.emit(switch (dst_int_info.bits) {
                                else => unreachable,
                                1...31 => |bits| switch (dst_int_info.signedness) {
                                    .signed => .sbfm(dst_elem_ra.w(), src_elem_mat.ra.w(), .{
                                        .N = .word,
                                        .immr = 0,
                                        .imms = @intCast(bits - 1),
                                    }),
                                    .unsigned => .ubfm(dst_elem_ra.w(), src_elem_mat.ra.w(), .{
                                        .N = .word,
                                        .immr = 0,
                                        .imms = @intCast(bits - 1),
                                    }),
                                },
                                32 => .orr(dst_elem_ra.w(), .wzr, .{ .register = src_elem_mat.ra.w() }),
                                33...63 => |bits| switch (dst_int_info.signedness) {
                                    .signed => .sbfm(dst_elem_ra.x(), src_elem_mat.ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 0,
                                        .imms = @intCast(bits - 1),
                                    }),
                                    .unsigned => .ubfm(dst_elem_ra.x(), src_elem_mat.ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 0,
                                        .imms = @intCast(bits - 1),
                                    }),
                                },
                                64 => .orr(dst_elem_ra.x(), .xzr, .{ .register = src_elem_mat.ra.x() }),
                            });
                            try src_elem_mat.finish(isel);
                        }
                    } else return isel.fail("too big {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) });
                    break :unused;
                }
                if (!dst_ty.isAbiInt(zcu) or !src_ty.isAbiInt(zcu)) return isel.fail("bad {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) });
                const dst_int_info = dst_ty.intInfo(zcu);
                switch (dst_int_info.bits) {
                    0 => unreachable,
                    1...64 => |dst_bits| {
                        const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        var src_part_it = src_vi.field(src_ty, 0, @min(src_vi.size(isel), 8));
                        const src_part_vi = try src_part_it.only(isel);
                        const src_part_mat = try src_part_vi.?.matReg(isel);
                        try isel.emit(switch (dst_bits) {
                            else => unreachable,
                            1...31 => |bits| switch (dst_int_info.signedness) {
                                .signed => .sbfm(dst_ra.w(), src_part_mat.ra.w(), .{
                                    .N = .word,
                                    .immr = 0,
                                    .imms = @intCast(bits - 1),
                                }),
                                .unsigned => .ubfm(dst_ra.w(), src_part_mat.ra.w(), .{
                                    .N = .word,
                                    .immr = 0,
                                    .imms = @intCast(bits - 1),
                                }),
                            },
                            32 => .orr(dst_ra.w(), .wzr, .{ .register = src_part_mat.ra.w() }),
                            33...63 => |bits| switch (dst_int_info.signedness) {
                                .signed => .sbfm(dst_ra.x(), src_part_mat.ra.x(), .{
                                    .N = .doubleword,
                                    .immr = 0,
                                    .imms = @intCast(bits - 1),
                                }),
                                .unsigned => .ubfm(dst_ra.x(), src_part_mat.ra.x(), .{
                                    .N = .doubleword,
                                    .immr = 0,
                                    .imms = @intCast(bits - 1),
                                }),
                            },
                            64 => .orr(dst_ra.x(), .xzr, .{ .register = src_part_mat.ra.x() }),
                        });
                        try src_part_mat.finish(isel);
                    },
                    65...128 => |dst_bits| switch (src_ty.intInfo(zcu).bits) {
                        0 => unreachable,
                        65...128 => {
                            const src_vi = try isel.use(ty_op.operand);
                            var dst_hi64_it = dst_vi.value.field(dst_ty, 8, 8);
                            const dst_hi64_vi = try dst_hi64_it.only(isel);
                            if (try dst_hi64_vi.?.defReg(isel)) |dst_hi64_ra| {
                                var src_hi64_it = src_vi.field(src_ty, 8, 8);
                                const src_hi64_vi = try src_hi64_it.only(isel);
                                const src_hi64_mat = try src_hi64_vi.?.matReg(isel);
                                try isel.emit(switch (dst_int_info.signedness) {
                                    .signed => .sbfm(dst_hi64_ra.x(), src_hi64_mat.ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 0,
                                        .imms = @intCast(dst_bits - 64 - 1),
                                    }),
                                    .unsigned => .ubfm(dst_hi64_ra.x(), src_hi64_mat.ra.x(), .{
                                        .N = .doubleword,
                                        .immr = 0,
                                        .imms = @intCast(dst_bits - 64 - 1),
                                    }),
                                });
                                try src_hi64_mat.finish(isel);
                            }
                            var dst_lo64_it = dst_vi.value.field(dst_ty, 0, 8);
                            const dst_lo64_vi = try dst_lo64_it.only(isel);
                            if (try dst_lo64_vi.?.defReg(isel)) |dst_lo64_ra| {
                                var src_lo64_it = src_vi.field(src_ty, 0, 8);
                                const src_lo64_vi = try src_lo64_it.only(isel);
                                try src_lo64_vi.?.liveOut(isel, dst_lo64_ra);
                            }
                        },
                        else => return isel.fail("too big {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) }),
                    },
                    else => return isel.fail("too big {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) }),
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .optional_payload => {
            if (isel.live_values.fetchRemove(air.inst_index)) |payload_vi| unused: {
                defer payload_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const opt_ty = isel.air.typeOf(ty_op.operand, ip);
                if (opt_ty.optionalReprIsPayload(zcu)) {
                    try payload_vi.value.move(isel, ty_op.operand);
                    break :unused;
                }

                const opt_vi = try isel.use(ty_op.operand);
                var payload_part_it = opt_vi.field(opt_ty, 0, payload_vi.value.size(isel));
                try payload_part_it.copyTo(isel, ty_op.ty, payload_vi.value);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .optional_payload_ptr => {
            if (isel.live_values.fetchRemove(air.inst_index)) |payload_ptr_vi| {
                defer payload_ptr_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                try payload_ptr_vi.value.move(isel, ty_op.operand);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .optional_payload_ptr_set => {
            if (isel.live_values.fetchRemove(air.inst_index)) |payload_ptr_vi| {
                defer payload_ptr_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                const opt_ty = isel.air.typeOf(ty_op.operand, ip).childType(zcu);
                if (!opt_ty.optionalReprIsPayload(zcu)) {
                    const opt_ptr_vi = try isel.use(ty_op.operand);
                    const opt_ptr_mat = try opt_ptr_vi.matReg(isel);
                    const has_value_ra = try isel.allocIntReg();
                    defer isel.freeReg(has_value_ra);
                    try isel.storeReg(
                        has_value_ra,
                        1,
                        opt_ptr_mat.ra,
                        opt_ty.optionalChild(zcu).abiSize(zcu),
                    );
                    try opt_ptr_mat.finish(isel);
                    try isel.emit(.movz(has_value_ra.w(), 1, .{ .lsl = .@"0" }));
                }
                try payload_ptr_vi.value.move(isel, ty_op.operand);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .wrap_optional => {
            if (isel.live_values.fetchRemove(air.inst_index)) |opt_vi| unused: {
                defer opt_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                if (ty_op.ty.optionalReprIsPayload(zcu)) {
                    try opt_vi.value.move(isel, ty_op.operand);
                    break :unused;
                }

                const payload_ty = isel.air.typeOf(ty_op.operand, ip);
                const payload_size = payload_ty.abiSize(zcu);
                var payload_part_it = opt_vi.value.field(ty_op.ty, 0, payload_size);
                try payload_part_it.move(isel, payload_ty, ty_op.operand);
                var has_value_part_it = opt_vi.value.field(ty_op.ty, payload_size, 1);
                const has_value_part_vi = try has_value_part_it.only(isel);
                const has_value_part_ra = try has_value_part_vi.?.defReg(isel) orelse break :unused;
                try isel.emit(.movz(has_value_part_ra.w(), 1, .{ .lsl = .@"0" }));
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .unwrap_errunion_payload => {
            if (isel.live_values.fetchRemove(air.inst_index)) |payload_vi| {
                defer payload_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const error_union_ty = isel.air.typeOf(ty_op.operand, ip);

                const error_union_vi = try isel.use(ty_op.operand);
                var payload_part_it = error_union_vi.field(
                    error_union_ty,
                    codegen.errUnionPayloadOffset(ty_op.ty, zcu),
                    payload_vi.value.size(isel),
                );
                try payload_part_it.copyTo(isel, ty_op.ty, payload_vi.value);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .unwrap_errunion_err => {
            if (isel.live_values.fetchRemove(air.inst_index)) |error_set_vi| {
                defer error_set_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const error_union_ty = isel.air.typeOf(ty_op.operand, ip);

                const error_union_vi = try isel.use(ty_op.operand);
                var error_set_part_it = error_union_vi.field(
                    error_union_ty,
                    codegen.errUnionErrorOffset(error_union_ty.errorUnionPayload(zcu), zcu),
                    error_set_vi.value.size(isel),
                );
                const error_set_part_vi = try error_set_part_it.only(isel);
                try error_set_vi.value.copy(isel, ty_op.ty, error_set_part_vi.?);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .unwrap_errunion_payload_ptr => {
            if (isel.live_values.fetchRemove(air.inst_index)) |payload_ptr_vi| unused: {
                defer payload_ptr_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                switch (codegen.errUnionPayloadOffset(ty_op.ty.childType(zcu), zcu)) {
                    0 => try payload_ptr_vi.value.move(isel, ty_op.operand),
                    else => |payload_offset| {
                        const payload_ptr_ra = try payload_ptr_vi.value.defReg(isel) orelse break :unused;
                        const error_union_ptr_vi = try isel.use(ty_op.operand);
                        const error_union_ptr_mat = try error_union_ptr_vi.matReg(isel);
                        const lo12: u12 = @truncate(payload_offset >> 0);
                        const hi12: u12 = @intCast(payload_offset >> 12);
                        if (hi12 > 0) try isel.emit(.add(
                            payload_ptr_ra.x(),
                            if (lo12 > 0) payload_ptr_ra.x() else error_union_ptr_mat.ra.x(),
                            .{ .shifted_immediate = .{ .immediate = hi12, .lsl = .@"12" } },
                        ));
                        if (lo12 > 0) try isel.emit(.add(payload_ptr_ra.x(), error_union_ptr_mat.ra.x(), .{ .immediate = lo12 }));
                        try error_union_ptr_mat.finish(isel);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .unwrap_errunion_err_ptr => {
            if (isel.live_values.fetchRemove(air.inst_index)) |error_vi| {
                defer error_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                const error_union_ptr_ty = isel.air.typeOf(ty_op.operand, ip);
                const error_union_ptr_info = error_union_ptr_ty.ptrInfo(zcu);
                const error_union_ptr_vi = try isel.use(ty_op.operand);
                const error_union_ptr_mat = try error_union_ptr_vi.matReg(isel);
                _ = try error_vi.value.load(isel, ty_op.ty, error_union_ptr_mat.ra, .{
                    .offset = codegen.errUnionErrorOffset(
                        ZigType.fromInterned(error_union_ptr_info.child).errorUnionPayload(zcu),
                        zcu,
                    ),
                    .@"volatile" = error_union_ptr_info.flags.is_volatile,
                });
                try error_union_ptr_mat.finish(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .errunion_payload_ptr_set => {
            if (isel.live_values.fetchRemove(air.inst_index)) |payload_ptr_vi| unused: {
                defer payload_ptr_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                const payload_ty = ty_op.ty.childType(zcu);
                const error_union_ty = isel.air.typeOf(ty_op.operand, ip).childType(zcu);
                const error_set_size = error_union_ty.errorUnionSet(zcu).abiSize(zcu);
                const error_union_ptr_vi = try isel.use(ty_op.operand);
                const error_union_ptr_mat = try error_union_ptr_vi.matReg(isel);
                if (error_set_size > 0) try isel.storeReg(
                    .zr,
                    error_set_size,
                    error_union_ptr_mat.ra,
                    codegen.errUnionErrorOffset(payload_ty, zcu),
                );
                switch (codegen.errUnionPayloadOffset(payload_ty, zcu)) {
                    0 => {
                        try error_union_ptr_mat.finish(isel);
                        try payload_ptr_vi.value.move(isel, ty_op.operand);
                    },
                    else => |payload_offset| {
                        const payload_ptr_ra = try payload_ptr_vi.value.defReg(isel) orelse break :unused;
                        const lo12: u12 = @truncate(payload_offset >> 0);
                        const hi12: u12 = @intCast(payload_offset >> 12);
                        if (hi12 > 0) try isel.emit(.add(
                            payload_ptr_ra.x(),
                            if (lo12 > 0) payload_ptr_ra.x() else error_union_ptr_mat.ra.x(),
                            .{ .shifted_immediate = .{ .immediate = hi12, .lsl = .@"12" } },
                        ));
                        if (lo12 > 0) try isel.emit(.add(payload_ptr_ra.x(), error_union_ptr_mat.ra.x(), .{ .immediate = lo12 }));
                        try error_union_ptr_mat.finish(isel);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .wrap_errunion_payload => {
            if (isel.live_values.fetchRemove(air.inst_index)) |error_union_vi| {
                defer error_union_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const error_union_ty = ty_op.ty;
                const error_union_info = ip.indexToKey(error_union_ty.toIntern()).error_union_type;
                const error_set_ty: ZigType = .fromInterned(error_union_info.error_set_type);
                const payload_ty: ZigType = .fromInterned(error_union_info.payload_type);
                const error_set_offset = codegen.errUnionErrorOffset(payload_ty, zcu);
                const payload_offset = codegen.errUnionPayloadOffset(payload_ty, zcu);
                const error_set_size = error_set_ty.abiSize(zcu);
                const payload_size = payload_ty.abiSize(zcu);

                var payload_part_it = error_union_vi.value.field(error_union_ty, payload_offset, payload_size);
                try payload_part_it.move(isel, payload_ty, ty_op.operand);
                var error_set_part_it = error_union_vi.value.field(error_union_ty, error_set_offset, error_set_size);
                const error_set_part_vi = try error_set_part_it.only(isel);
                if (try error_set_part_vi.?.defReg(isel)) |error_set_part_ra| try isel.emit(switch (error_set_size) {
                    else => unreachable,
                    1...4 => .orr(error_set_part_ra.w(), .wzr, .{ .register = .wzr }),
                    5...8 => .orr(error_set_part_ra.x(), .xzr, .{ .register = .xzr }),
                });
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .wrap_errunion_err => {
            if (isel.live_values.fetchRemove(air.inst_index)) |error_union_vi| {
                defer error_union_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const error_union_ty = ty_op.ty;
                const error_union_info = ip.indexToKey(error_union_ty.toIntern()).error_union_type;
                const error_set_ty: ZigType = .fromInterned(error_union_info.error_set_type);
                const payload_ty: ZigType = .fromInterned(error_union_info.payload_type);
                const error_set_offset = codegen.errUnionErrorOffset(payload_ty, zcu);
                const payload_offset = codegen.errUnionPayloadOffset(payload_ty, zcu);
                const error_set_size = error_set_ty.abiSize(zcu);
                const payload_size = payload_ty.abiSize(zcu);

                var error_set_part_it = error_union_vi.value.field(error_union_ty, error_set_offset, error_set_size);
                const error_set_part_vi = try error_set_part_it.only(isel);
                try error_set_part_vi.?.move(isel, ty_op.operand);
                if (payload_size > 0) {
                    var payload_part_it = error_union_vi.value.field(error_union_ty, payload_offset, payload_size);
                    while (try payload_part_it.next(isel)) |payload_part| {
                        try payload_part.vi.defUndef(isel, error_union_ty, .{
                            .root_vi = error_union_vi.value,
                            .offset = payload_offset + payload_part.offset,
                        });
                    }
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .struct_field_ptr => {
            if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);
                const ty_pl = air.data(air.inst_index).ty_pl;
                const extra = isel.air.extraData(Air.StructField, ty_pl.payload).data;
                switch (codegen.fieldOffset(
                    isel.air.typeOf(extra.struct_operand, ip),
                    ty_pl.ty,
                    extra.field_index,
                    zcu,
                )) {
                    0 => try dst_vi.value.move(isel, extra.struct_operand),
                    else => |field_offset| {
                        const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(extra.struct_operand);
                        const src_mat = try src_vi.matReg(isel);
                        const lo12: u12 = @truncate(field_offset >> 0);
                        const hi12: u12 = @intCast(field_offset >> 12);
                        if (hi12 > 0) try isel.emit(.add(
                            dst_ra.x(),
                            if (lo12 > 0) dst_ra.x() else src_mat.ra.x(),
                            .{ .shifted_immediate = .{ .immediate = hi12, .lsl = .@"12" } },
                        ));
                        if (lo12 > 0) try isel.emit(.add(dst_ra.x(), src_mat.ra.x(), .{ .immediate = lo12 }));
                        try src_mat.finish(isel);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .struct_field_ptr_index_0,
        .struct_field_ptr_index_1,
        .struct_field_ptr_index_2,
        .struct_field_ptr_index_3,
        => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                switch (codegen.fieldOffset(
                    isel.air.typeOf(ty_op.operand, ip),
                    ty_op.ty,
                    switch (air_tag) {
                        else => unreachable,
                        .struct_field_ptr_index_0 => 0,
                        .struct_field_ptr_index_1 => 1,
                        .struct_field_ptr_index_2 => 2,
                        .struct_field_ptr_index_3 => 3,
                    },
                    zcu,
                )) {
                    0 => try dst_vi.value.move(isel, ty_op.operand),
                    else => |field_offset| {
                        const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        const src_mat = try src_vi.matReg(isel);
                        const lo12: u12 = @truncate(field_offset >> 0);
                        const hi12: u12 = @intCast(field_offset >> 12);
                        if (hi12 > 0) try isel.emit(.add(
                            dst_ra.x(),
                            if (lo12 > 0) dst_ra.x() else src_mat.ra.x(),
                            .{ .shifted_immediate = .{ .immediate = hi12, .lsl = .@"12" } },
                        ));
                        if (lo12 > 0) try isel.emit(.add(dst_ra.x(), src_mat.ra.x(), .{ .immediate = lo12 }));
                        try src_mat.finish(isel);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .agg_field_val => {
            if (isel.live_values.fetchRemove(air.inst_index)) |field_vi| unused: {
                defer field_vi.value.deref(isel);

                const ty_pl = air.data(air.inst_index).ty_pl;
                const extra = isel.air.extraData(Air.StructField, ty_pl.payload).data;
                const agg_ty = isel.air.typeOf(extra.struct_operand, ip);
                const field_ty = ty_pl.ty;
                const field_bit_offset, const field_bit_size, const is_packed = switch (agg_ty.containerLayout(zcu)) {
                    .auto, .@"extern" => .{
                        8 * agg_ty.structFieldOffset(extra.field_index, zcu),
                        8 * field_ty.abiSize(zcu),
                        false,
                    },
                    .@"packed" => .{
                        if (zcu.typeToPackedStruct(agg_ty)) |loaded_struct|
                            zcu.structPackedFieldBitOffset(loaded_struct, extra.field_index)
                        else
                            0,
                        field_ty.bitSize(zcu),
                        true,
                    },
                };
                if (is_packed) return isel.fail("packed field of {f}", .{
                    isel.fmtType(agg_ty),
                });

                const agg_vi = try isel.use(extra.struct_operand);
                switch (agg_ty.zigTypeTag(zcu)) {
                    else => unreachable,
                    .@"struct" => {
                        var agg_part_it = agg_vi.field(agg_ty, @divExact(field_bit_offset, 8), @divExact(field_bit_size, 8));
                        try agg_part_it.copyTo(isel, field_ty, field_vi.value);
                    },
                    .@"union" => {
                        try field_vi.value.defAddr(isel, field_ty, .{}) orelse break :unused;

                        try call.prepareReturn(isel);
                        try call.finishReturn(isel);

                        try call.prepareCallee(isel);
                        try isel.global_relocs.append(gpa, .{
                            .name = "memcpy",
                            .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                        });
                        try isel.emit(.bl(0));
                        try call.finishCallee(isel);

                        try call.prepareParams(isel);
                        const union_layout = agg_ty.unionGetLayout(zcu);
                        var payload_it = agg_vi.field(agg_ty, union_layout.payloadOffset(), union_layout.payload_size);
                        _ = try payload_it.next(isel);
                        try isel.movImmediate(.x2, field_vi.value.size(isel));
                        try call.paramAddressOffset(isel, agg_vi, union_layout.payloadOffset(), .r1);
                        try call.paramAddress(isel, field_vi.value, .r0);
                        try call.finishParams(isel);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .set_union_tag => {
            const bin_op = air.data(air.inst_index).bin_op;
            const union_ty = isel.air.typeOf(bin_op.lhs, ip).childType(zcu);
            const union_layout = union_ty.unionGetLayout(zcu);
            if (union_layout.tag_size > 0) {
                const tag_vi = try isel.use(bin_op.rhs);
                const union_ptr_vi = try isel.use(bin_op.lhs);
                const union_ptr_mat = try union_ptr_vi.matReg(isel);
                try tag_vi.store(isel, isel.air.typeOf(bin_op.rhs, ip), union_ptr_mat.ra, .{
                    .offset = union_layout.tagOffset(),
                });
                try union_ptr_mat.finish(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .get_union_tag => {
            if (isel.live_values.fetchRemove(air.inst_index)) |tag_vi| {
                defer tag_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                const union_ty = isel.air.typeOf(ty_op.operand, ip);
                const union_layout = union_ty.unionGetLayout(zcu);
                const union_vi = try isel.use(ty_op.operand);
                var tag_part_it = union_vi.field(union_ty, union_layout.tagOffset(), union_layout.tag_size);
                const tag_part_vi = try tag_part_it.only(isel);
                try tag_vi.value.copy(isel, ty_op.ty, tag_part_vi.?);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .slice => {
            if (isel.live_values.fetchRemove(air.inst_index)) |slice_vi| {
                defer slice_vi.value.deref(isel);
                const ty_pl = air.data(air.inst_index).ty_pl;
                const bin_op = isel.air.extraData(Air.Bin, ty_pl.payload).data;
                var ptr_part_it = slice_vi.value.field(ty_pl.ty, 0, 8);
                const ptr_part_vi = try ptr_part_it.only(isel);
                try ptr_part_vi.?.move(isel, bin_op.lhs);
                var len_part_it = slice_vi.value.field(ty_pl.ty, 8, 8);
                const len_part_vi = try len_part_it.only(isel);
                try len_part_vi.?.move(isel, bin_op.rhs);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .slice_len => {
            if (isel.live_values.fetchRemove(air.inst_index)) |len_vi| {
                defer len_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                const slice_vi = try isel.use(ty_op.operand);
                var len_part_it = slice_vi.field(isel.air.typeOf(ty_op.operand, ip), 8, 8);
                const len_part_vi = try len_part_it.only(isel);
                try len_vi.value.copy(isel, ty_op.ty, len_part_vi.?);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .slice_ptr => {
            if (isel.live_values.fetchRemove(air.inst_index)) |ptr_vi| {
                defer ptr_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                const slice_vi = try isel.use(ty_op.operand);
                var ptr_part_it = slice_vi.field(isel.air.typeOf(ty_op.operand, ip), 0, 8);
                const ptr_part_vi = try ptr_part_it.only(isel);
                try ptr_vi.value.copy(isel, ty_op.ty, ptr_part_vi.?);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .ptr_slice_len_ptr => {
            if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                const src_vi = try isel.use(ty_op.operand);
                const src_mat = try src_vi.matReg(isel);
                try isel.emit(.add(dst_ra.x(), src_mat.ra.x(), .{ .immediate = 8 }));
                try src_mat.finish(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .ptr_slice_ptr_ptr => {
            if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| {
                defer dst_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                try dst_vi.value.move(isel, ty_op.operand);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .array_elem_val => {
            if (isel.live_values.fetchRemove(air.inst_index)) |elem_vi| unused: {
                defer elem_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const array_ty = isel.air.typeOf(bin_op.lhs, ip);
                const elem_ty = array_ty.childType(zcu);
                const elem_size = elem_ty.abiSize(zcu);
                if (elem_size <= 16 and array_ty.arrayLenIncludingSentinel(zcu) <= Value.max_parts) if (bin_op.rhs.toInterned()) |index_val| {
                    const elem_offset = elem_size * Constant.fromInterned(index_val).toUnsignedInt(zcu);
                    const array_vi = try isel.use(bin_op.lhs);
                    var elem_part_it = array_vi.field(array_ty, elem_offset, elem_size);
                    const elem_part_vi = try elem_part_it.only(isel);
                    try elem_vi.value.copy(isel, elem_ty, elem_part_vi.?);
                    break :unused;
                };
                switch (elem_size) {
                    0 => unreachable,
                    1, 2, 4, 8 => {
                        const elem_ra = try elem_vi.value.defReg(isel) orelse break :unused;
                        const array_ptr_ra = try isel.allocIntReg();
                        var array_ptr_freed = false;
                        defer if (!array_ptr_freed) isel.freeReg(array_ptr_ra);
                        const index_vi = try isel.use(bin_op.rhs);
                        const index_mat = try index_vi.matReg(isel);
                        try isel.emit(switch (elem_size) {
                            else => unreachable,
                            1 => if (elem_vi.value.isVector(isel)) .ldr(elem_ra.b(), .{ .extended_register = .{
                                .base = array_ptr_ra.x(),
                                .index = index_mat.ra.x(),
                                .extend = .{ .lsl = 0 },
                            } }) else switch (elem_vi.value.signedness(isel)) {
                                .signed => .ldrsb(elem_ra.w(), .{ .extended_register = .{
                                    .base = array_ptr_ra.x(),
                                    .index = index_mat.ra.x(),
                                    .extend = .{ .lsl = 0 },
                                } }),
                                .unsigned => .ldrb(elem_ra.w(), .{ .extended_register = .{
                                    .base = array_ptr_ra.x(),
                                    .index = index_mat.ra.x(),
                                    .extend = .{ .lsl = 0 },
                                } }),
                            },
                            2 => if (elem_vi.value.isVector(isel)) .ldr(elem_ra.h(), .{ .extended_register = .{
                                .base = array_ptr_ra.x(),
                                .index = index_mat.ra.x(),
                                .extend = .{ .lsl = 1 },
                            } }) else switch (elem_vi.value.signedness(isel)) {
                                .signed => .ldrsh(elem_ra.w(), .{ .extended_register = .{
                                    .base = array_ptr_ra.x(),
                                    .index = index_mat.ra.x(),
                                    .extend = .{ .lsl = 1 },
                                } }),
                                .unsigned => .ldrh(elem_ra.w(), .{ .extended_register = .{
                                    .base = array_ptr_ra.x(),
                                    .index = index_mat.ra.x(),
                                    .extend = .{ .lsl = 1 },
                                } }),
                            },
                            4 => .ldr(if (elem_vi.value.isVector(isel)) elem_ra.s() else elem_ra.w(), .{ .extended_register = .{
                                .base = array_ptr_ra.x(),
                                .index = index_mat.ra.x(),
                                .extend = .{ .lsl = 2 },
                            } }),
                            8 => .ldr(if (elem_vi.value.isVector(isel)) elem_ra.d() else elem_ra.x(), .{ .extended_register = .{
                                .base = array_ptr_ra.x(),
                                .index = index_mat.ra.x(),
                                .extend = .{ .lsl = 3 },
                            } }),
                            16 => .ldr(elem_ra.q(), .{ .extended_register = .{
                                .base = array_ptr_ra.x(),
                                .index = index_mat.ra.x(),
                                .extend = .{ .lsl = 4 },
                            } }),
                        });
                        try index_mat.finish(isel);
                        const array_vi = try isel.use(bin_op.lhs);
                        array_ptr_freed = true;
                        isel.freeReg(array_ptr_ra);
                        try array_vi.address(isel, 0, array_ptr_ra);
                    },
                    else => {
                        const ptr_ra = try isel.allocIntReg();
                        var ptr_freed = false;
                        defer if (!ptr_freed) isel.freeReg(ptr_ra);
                        if (!try elem_vi.value.load(isel, elem_ty, ptr_ra, .{})) break :unused;
                        const index_vi = try isel.use(bin_op.rhs);
                        try isel.elemPtr(ptr_ra, ptr_ra, .add, elem_size, index_vi);
                        const array_vi = try isel.use(bin_op.lhs);
                        ptr_freed = true;
                        isel.freeReg(ptr_ra);
                        try array_vi.address(isel, 0, ptr_ra);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .slice_elem_val => {
            if (isel.live_values.fetchRemove(air.inst_index)) |elem_vi| unused: {
                defer elem_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const slice_ty = isel.air.typeOf(bin_op.lhs, ip);
                const ptr_info = slice_ty.ptrInfo(zcu);
                const elem_size = elem_vi.value.size(isel);
                const elem_is_vector = elem_vi.value.isVector(isel);
                if (switch (elem_size) {
                    0 => unreachable,
                    1, 2, 4, 8 => true,
                    16 => elem_is_vector,
                    else => false,
                }) {
                    const elem_ra = try elem_vi.value.defReg(isel) orelse break :unused;
                    const slice_vi = try isel.use(bin_op.lhs);
                    const index_vi = try isel.use(bin_op.rhs);
                    var ptr_part_it = slice_vi.field(slice_ty, 0, 8);
                    const ptr_part_vi = try ptr_part_it.only(isel);
                    const base_mat = try ptr_part_vi.?.matReg(isel);
                    const index_mat = try index_vi.matReg(isel);
                    try isel.emit(switch (elem_size) {
                        else => unreachable,
                        1 => if (elem_is_vector) .ldr(elem_ra.b(), .{ .extended_register = .{
                            .base = base_mat.ra.x(),
                            .index = index_mat.ra.x(),
                            .extend = .{ .lsl = 0 },
                        } }) else switch (elem_vi.value.signedness(isel)) {
                            .signed => .ldrsb(elem_ra.w(), .{ .extended_register = .{
                                .base = base_mat.ra.x(),
                                .index = index_mat.ra.x(),
                                .extend = .{ .lsl = 0 },
                            } }),
                            .unsigned => .ldrb(elem_ra.w(), .{ .extended_register = .{
                                .base = base_mat.ra.x(),
                                .index = index_mat.ra.x(),
                                .extend = .{ .lsl = 0 },
                            } }),
                        },
                        2 => if (elem_is_vector) .ldr(elem_ra.h(), .{ .extended_register = .{
                            .base = base_mat.ra.x(),
                            .index = index_mat.ra.x(),
                            .extend = .{ .lsl = 1 },
                        } }) else switch (elem_vi.value.signedness(isel)) {
                            .signed => .ldrsh(elem_ra.w(), .{ .extended_register = .{
                                .base = base_mat.ra.x(),
                                .index = index_mat.ra.x(),
                                .extend = .{ .lsl = 1 },
                            } }),
                            .unsigned => .ldrh(elem_ra.w(), .{ .extended_register = .{
                                .base = base_mat.ra.x(),
                                .index = index_mat.ra.x(),
                                .extend = .{ .lsl = 1 },
                            } }),
                        },
                        4 => .ldr(if (elem_is_vector) elem_ra.s() else elem_ra.w(), .{ .extended_register = .{
                            .base = base_mat.ra.x(),
                            .index = index_mat.ra.x(),
                            .extend = .{ .lsl = 2 },
                        } }),
                        8 => .ldr(if (elem_is_vector) elem_ra.d() else elem_ra.x(), .{ .extended_register = .{
                            .base = base_mat.ra.x(),
                            .index = index_mat.ra.x(),
                            .extend = .{ .lsl = 3 },
                        } }),
                        16 => if (elem_is_vector) .ldr(elem_ra.q(), .{ .extended_register = .{
                            .base = base_mat.ra.x(),
                            .index = index_mat.ra.x(),
                            .extend = .{ .lsl = 4 },
                        } }) else unreachable,
                    });
                    try index_mat.finish(isel);
                    try base_mat.finish(isel);
                } else {
                    const elem_ptr_ra = try isel.allocIntReg();
                    defer isel.freeReg(elem_ptr_ra);
                    if (!try elem_vi.value.load(isel, slice_ty.childType(zcu), elem_ptr_ra, .{
                        .@"volatile" = ptr_info.flags.is_volatile,
                    })) break :unused;
                    const slice_vi = try isel.use(bin_op.lhs);
                    var ptr_part_it = slice_vi.field(slice_ty, 0, 8);
                    const ptr_part_vi = try ptr_part_it.only(isel);
                    const ptr_part_mat = try ptr_part_vi.?.matReg(isel);
                    const index_vi = try isel.use(bin_op.rhs);
                    try isel.elemPtr(elem_ptr_ra, ptr_part_mat.ra, .add, elem_size, index_vi);
                    try ptr_part_mat.finish(isel);
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .slice_elem_ptr => {
            if (isel.live_values.fetchRemove(air.inst_index)) |elem_ptr_vi| unused: {
                defer elem_ptr_vi.value.deref(isel);
                const elem_ptr_ra = try elem_ptr_vi.value.defReg(isel) orelse break :unused;

                const ty_pl = air.data(air.inst_index).ty_pl;
                const bin_op = isel.air.extraData(Air.Bin, ty_pl.payload).data;
                const elem_size = ty_pl.ty.childType(zcu).abiSize(zcu);

                const slice_vi = try isel.use(bin_op.lhs);
                var ptr_part_it = slice_vi.field(isel.air.typeOf(bin_op.lhs, ip), 0, 8);
                const ptr_part_vi = try ptr_part_it.only(isel);
                const ptr_part_mat = try ptr_part_vi.?.matReg(isel);
                const index_vi = try isel.use(bin_op.rhs);
                try isel.elemPtr(elem_ptr_ra, ptr_part_mat.ra, .add, elem_size, index_vi);
                try ptr_part_mat.finish(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .ptr_elem_val => {
            if (isel.live_values.fetchRemove(air.inst_index)) |elem_vi| unused: {
                defer elem_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ptr_ty = isel.air.typeOf(bin_op.lhs, ip);
                const ptr_info = ptr_ty.ptrInfo(zcu);
                const elem_size = elem_vi.value.size(isel);
                const elem_is_vector = elem_vi.value.isVector(isel);
                if (switch (elem_size) {
                    0 => unreachable,
                    1, 2, 4, 8 => true,
                    16 => elem_is_vector,
                    else => false,
                }) {
                    const elem_ra = try elem_vi.value.defReg(isel) orelse break :unused;
                    const base_vi = try isel.use(bin_op.lhs);
                    const index_vi = try isel.use(bin_op.rhs);
                    const base_mat = try base_vi.matReg(isel);
                    const index_mat = try index_vi.matReg(isel);
                    try isel.emit(switch (elem_size) {
                        else => unreachable,
                        1 => if (elem_is_vector) .ldr(elem_ra.b(), .{ .extended_register = .{
                            .base = base_mat.ra.x(),
                            .index = index_mat.ra.x(),
                            .extend = .{ .lsl = 0 },
                        } }) else switch (elem_vi.value.signedness(isel)) {
                            .signed => .ldrsb(elem_ra.w(), .{ .extended_register = .{
                                .base = base_mat.ra.x(),
                                .index = index_mat.ra.x(),
                                .extend = .{ .lsl = 0 },
                            } }),
                            .unsigned => .ldrb(elem_ra.w(), .{ .extended_register = .{
                                .base = base_mat.ra.x(),
                                .index = index_mat.ra.x(),
                                .extend = .{ .lsl = 0 },
                            } }),
                        },
                        2 => if (elem_is_vector) .ldr(elem_ra.h(), .{ .extended_register = .{
                            .base = base_mat.ra.x(),
                            .index = index_mat.ra.x(),
                            .extend = .{ .lsl = 1 },
                        } }) else switch (elem_vi.value.signedness(isel)) {
                            .signed => .ldrsh(elem_ra.w(), .{ .extended_register = .{
                                .base = base_mat.ra.x(),
                                .index = index_mat.ra.x(),
                                .extend = .{ .lsl = 1 },
                            } }),
                            .unsigned => .ldrh(elem_ra.w(), .{ .extended_register = .{
                                .base = base_mat.ra.x(),
                                .index = index_mat.ra.x(),
                                .extend = .{ .lsl = 1 },
                            } }),
                        },
                        4 => .ldr(if (elem_is_vector) elem_ra.s() else elem_ra.w(), .{ .extended_register = .{
                            .base = base_mat.ra.x(),
                            .index = index_mat.ra.x(),
                            .extend = .{ .lsl = 2 },
                        } }),
                        8 => .ldr(if (elem_is_vector) elem_ra.d() else elem_ra.x(), .{ .extended_register = .{
                            .base = base_mat.ra.x(),
                            .index = index_mat.ra.x(),
                            .extend = .{ .lsl = 3 },
                        } }),
                        16 => if (elem_is_vector) .ldr(elem_ra.q(), .{ .extended_register = .{
                            .base = base_mat.ra.x(),
                            .index = index_mat.ra.x(),
                            .extend = .{ .lsl = 4 },
                        } }) else unreachable,
                    });
                    try index_mat.finish(isel);
                    try base_mat.finish(isel);
                } else {
                    const elem_ptr_ra = try isel.allocIntReg();
                    defer isel.freeReg(elem_ptr_ra);
                    if (!try elem_vi.value.load(isel, ptr_ty.childType(zcu), elem_ptr_ra, .{
                        .@"volatile" = ptr_info.flags.is_volatile,
                    })) break :unused;
                    const base_vi = try isel.use(bin_op.lhs);
                    const base_mat = try base_vi.matReg(isel);
                    const index_vi = try isel.use(bin_op.rhs);
                    try isel.elemPtr(elem_ptr_ra, base_mat.ra, .add, elem_size, index_vi);
                    try base_mat.finish(isel);
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .ptr_elem_ptr => {
            if (isel.live_values.fetchRemove(air.inst_index)) |elem_ptr_vi| unused: {
                defer elem_ptr_vi.value.deref(isel);
                const elem_ptr_ra = try elem_ptr_vi.value.defReg(isel) orelse break :unused;

                const ty_pl = air.data(air.inst_index).ty_pl;
                const bin_op = isel.air.extraData(Air.Bin, ty_pl.payload).data;
                const elem_size = ty_pl.ty.childType(zcu).abiSize(zcu);

                const base_vi = try isel.use(bin_op.lhs);
                const base_mat = try base_vi.matReg(isel);
                const index_vi = try isel.use(bin_op.rhs);
                try isel.elemPtr(elem_ptr_ra, base_mat.ra, .add, elem_size, index_vi);
                try base_mat.finish(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .array_to_vector => unreachable, // legalize .expand_array_to_vector
        .array_to_slice => {
            if (isel.live_values.fetchRemove(air.inst_index)) |slice_vi| {
                defer slice_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                var ptr_part_it = slice_vi.value.field(ty_op.ty, 0, 8);
                const ptr_part_vi = try ptr_part_it.only(isel);
                try ptr_part_vi.?.move(isel, ty_op.operand);
                var len_part_it = slice_vi.value.field(ty_op.ty, 8, 8);
                const len_part_vi = try len_part_it.only(isel);
                if (try len_part_vi.?.defReg(isel)) |len_ra| try isel.movImmediate(
                    len_ra.x(),
                    isel.air.typeOf(ty_op.operand, ip).childType(zcu).arrayLen(zcu),
                );
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .int_from_float,
        .int_from_float_optimized,
        .int_from_float_safe, // TODO safety check
        .int_from_float_optimized_safe, // TODO safety check
        => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const dst_ty = ty_op.ty;
                const src_ty = isel.air.typeOf(ty_op.operand, ip);
                if (!dst_ty.isAbiInt(zcu)) return isel.fail("bad {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) });
                const dst_int_info = dst_ty.intInfo(zcu);
                const src_bits = src_ty.floatBits(isel.target);
                switch (@max(dst_int_info.bits, src_bits)) {
                    0 => unreachable,
                    1...64 => {
                        const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                        const need_fcvt = switch (src_bits) {
                            else => unreachable,
                            16 => !isel.target.cpu.has(.aarch64, .fullfp16),
                            32, 64 => false,
                        };
                        const src_vi = try isel.use(ty_op.operand);
                        const src_mat = try src_vi.matReg(isel);
                        const src_ra = if (need_fcvt) try isel.allocVecReg() else src_mat.ra;
                        defer if (need_fcvt) isel.freeReg(src_ra);
                        const dst_reg = switch (dst_int_info.bits) {
                            else => unreachable,
                            1...32 => dst_ra.w(),
                            33...64 => dst_ra.x(),
                        };
                        const src_reg = switch (src_bits) {
                            else => unreachable,
                            16 => if (need_fcvt) src_ra.s() else src_ra.h(),
                            32 => src_ra.s(),
                            64 => src_ra.d(),
                        };
                        try isel.emit(switch (dst_int_info.signedness) {
                            .signed => .fcvtzs(dst_reg, src_reg),
                            .unsigned => .fcvtzu(dst_reg, src_reg),
                        });
                        if (need_fcvt) try isel.emit(.fcvt(src_reg, src_mat.ra.h()));
                        try src_mat.finish(isel);
                    },
                    65...128 => {
                        try call.prepareReturn(isel);
                        switch (dst_int_info.bits) {
                            else => unreachable,
                            1...64 => try call.returnLiveIn(isel, dst_vi.value, .r0),
                            65...128 => {
                                var dst_hi64_it = dst_vi.value.field(dst_ty, 8, 8);
                                const dst_hi64_vi = try dst_hi64_it.only(isel);
                                try call.returnLiveIn(isel, dst_hi64_vi.?, .r1);
                                var dst_lo64_it = dst_vi.value.field(dst_ty, 0, 8);
                                const dst_lo64_vi = try dst_lo64_it.only(isel);
                                try call.returnLiveIn(isel, dst_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishReturn(isel);

                        try call.prepareCallee(isel);
                        try isel.global_relocs.append(gpa, .{
                            .name = switch (dst_int_info.bits) {
                                else => unreachable,
                                1...32 => switch (dst_int_info.signedness) {
                                    .signed => switch (src_bits) {
                                        else => unreachable,
                                        16 => "__fixhfsi",
                                        32 => "__fixsfsi",
                                        64 => "__fixdfsi",
                                        80 => "__fixxfsi",
                                        128 => "__fixtfsi",
                                    },
                                    .unsigned => switch (src_bits) {
                                        else => unreachable,
                                        16 => "__fixunshfsi",
                                        32 => "__fixunssfsi",
                                        64 => "__fixunsdfsi",
                                        80 => "__fixunsxfsi",
                                        128 => "__fixunstfsi",
                                    },
                                },
                                33...64 => switch (dst_int_info.signedness) {
                                    .signed => switch (src_bits) {
                                        else => unreachable,
                                        16 => "__fixhfdi",
                                        32 => "__fixsfdi",
                                        64 => "__fixdfdi",
                                        80 => "__fixxfdi",
                                        128 => "__fixtfdi",
                                    },
                                    .unsigned => switch (src_bits) {
                                        else => unreachable,
                                        16 => "__fixunshfdi",
                                        32 => "__fixunssfdi",
                                        64 => "__fixunsdfdi",
                                        80 => "__fixunsxfdi",
                                        128 => "__fixunstfdi",
                                    },
                                },
                                65...128 => switch (dst_int_info.signedness) {
                                    .signed => switch (src_bits) {
                                        else => unreachable,
                                        16 => "__fixhfti",
                                        32 => "__fixsfti",
                                        64 => "__fixdfti",
                                        80 => "__fixxfti",
                                        128 => "__fixtfti",
                                    },
                                    .unsigned => switch (src_bits) {
                                        else => unreachable,
                                        16 => "__fixunshfti",
                                        32 => "__fixunssfti",
                                        64 => "__fixunsdfti",
                                        80 => "__fixunsxfti",
                                        128 => "__fixunstfti",
                                    },
                                },
                            },
                            .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                        });
                        try isel.emit(.bl(0));
                        try call.finishCallee(isel);

                        try call.prepareParams(isel);
                        const src_vi = try isel.use(ty_op.operand);
                        switch (src_bits) {
                            else => unreachable,
                            16, 32, 64, 128 => try call.paramLiveOut(isel, src_vi, .v0),
                            80 => {
                                var src_hi16_it = src_vi.field(src_ty, 8, 8);
                                const src_hi16_vi = try src_hi16_it.only(isel);
                                try call.paramLiveOut(isel, src_hi16_vi.?, .r1);
                                var src_lo64_it = src_vi.field(src_ty, 0, 8);
                                const src_lo64_vi = try src_lo64_it.only(isel);
                                try call.paramLiveOut(isel, src_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishParams(isel);
                    },
                    else => return isel.fail("too big {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) }),
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .float_from_int => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const dst_ty = ty_op.ty;
                const src_ty = isel.air.typeOf(ty_op.operand, ip);
                const dst_bits = dst_ty.floatBits(isel.target);
                if (!src_ty.isAbiInt(zcu)) return isel.fail("bad {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) });
                const src_int_info = src_ty.intInfo(zcu);
                switch (@max(dst_bits, src_int_info.bits)) {
                    0 => unreachable,
                    1...64 => {
                        const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                        const need_fcvt = switch (dst_bits) {
                            else => unreachable,
                            16 => !isel.target.cpu.has(.aarch64, .fullfp16),
                            32, 64 => false,
                        };
                        if (need_fcvt) try isel.emit(.fcvt(dst_ra.h(), dst_ra.s()));
                        const src_vi = try isel.use(ty_op.operand);
                        const src_mat = try src_vi.matReg(isel);
                        const dst_reg = switch (dst_bits) {
                            else => unreachable,
                            16 => if (need_fcvt) dst_ra.s() else dst_ra.h(),
                            32 => dst_ra.s(),
                            64 => dst_ra.d(),
                        };
                        const src_reg = switch (src_int_info.bits) {
                            else => unreachable,
                            1...32 => src_mat.ra.w(),
                            33...64 => src_mat.ra.x(),
                        };
                        try isel.emit(switch (src_int_info.signedness) {
                            .signed => .scvtf(dst_reg, src_reg),
                            .unsigned => .ucvtf(dst_reg, src_reg),
                        });
                        try src_mat.finish(isel);
                    },
                    65...128 => {
                        try call.prepareReturn(isel);
                        switch (dst_bits) {
                            else => unreachable,
                            16, 32, 64, 128 => try call.returnLiveIn(isel, dst_vi.value, .v0),
                            80 => {
                                var dst_hi16_it = dst_vi.value.field(dst_ty, 8, 8);
                                const dst_hi16_vi = try dst_hi16_it.only(isel);
                                try call.returnLiveIn(isel, dst_hi16_vi.?, .r1);
                                var dst_lo64_it = dst_vi.value.field(dst_ty, 0, 8);
                                const dst_lo64_vi = try dst_lo64_it.only(isel);
                                try call.returnLiveIn(isel, dst_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishReturn(isel);

                        try call.prepareCallee(isel);
                        try isel.global_relocs.append(gpa, .{
                            .name = switch (src_int_info.bits) {
                                else => unreachable,
                                1...32 => switch (src_int_info.signedness) {
                                    .signed => switch (dst_bits) {
                                        else => unreachable,
                                        16 => "__floatsihf",
                                        32 => "__floatsisf",
                                        64 => "__floatsidf",
                                        80 => "__floatsixf",
                                        128 => "__floatsitf",
                                    },
                                    .unsigned => switch (dst_bits) {
                                        else => unreachable,
                                        16 => "__floatunsihf",
                                        32 => "__floatunsisf",
                                        64 => "__floatunsidf",
                                        80 => "__floatunsixf",
                                        128 => "__floatunsitf",
                                    },
                                },
                                33...64 => switch (src_int_info.signedness) {
                                    .signed => switch (dst_bits) {
                                        else => unreachable,
                                        16 => "__floatdihf",
                                        32 => "__floatdisf",
                                        64 => "__floatdidf",
                                        80 => "__floatdixf",
                                        128 => "__floatditf",
                                    },
                                    .unsigned => switch (dst_bits) {
                                        else => unreachable,
                                        16 => "__floatundihf",
                                        32 => "__floatundisf",
                                        64 => "__floatundidf",
                                        80 => "__floatundixf",
                                        128 => "__floatunditf",
                                    },
                                },
                                65...128 => switch (src_int_info.signedness) {
                                    .signed => switch (dst_bits) {
                                        else => unreachable,
                                        16 => "__floattihf",
                                        32 => "__floattisf",
                                        64 => "__floattidf",
                                        80 => "__floattixf",
                                        128 => "__floattitf",
                                    },
                                    .unsigned => switch (dst_bits) {
                                        else => unreachable,
                                        16 => "__floatuntihf",
                                        32 => "__floatuntisf",
                                        64 => "__floatuntidf",
                                        80 => "__floatuntixf",
                                        128 => "__floatuntitf",
                                    },
                                },
                            },
                            .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                        });
                        try isel.emit(.bl(0));
                        try call.finishCallee(isel);

                        try call.prepareParams(isel);
                        const src_vi = try isel.use(ty_op.operand);
                        switch (src_int_info.bits) {
                            else => unreachable,
                            1...64 => try call.paramLiveOut(isel, src_vi, .r0),
                            65...128 => {
                                var src_hi64_it = src_vi.field(src_ty, 8, 8);
                                const src_hi64_vi = try src_hi64_it.only(isel);
                                try call.paramLiveOut(isel, src_hi64_vi.?, .r1);
                                var src_lo64_it = src_vi.field(src_ty, 0, 8);
                                const src_lo64_vi = try src_lo64_it.only(isel);
                                try call.paramLiveOut(isel, src_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishParams(isel);
                    },
                    else => return isel.fail("too big {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) }),
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .memset, .memset_safe => |air_tag| {
            const bin_op = air.data(air.inst_index).bin_op;
            const dst_ty = isel.air.typeOf(bin_op.lhs, ip);
            const dst_info = dst_ty.ptrInfo(zcu);
            const fill_byte: union(enum) { constant: u8, value: Air.Inst.Ref } = fill_byte: {
                if (bin_op.rhs.toInterned()) |fill_val| {
                    if (ip.isUndef(fill_val)) switch (air_tag) {
                        else => unreachable,
                        .memset => break :air_tag if (air.next()) |next_air_tag| continue :air_tag next_air_tag,
                        .memset_safe => break :fill_byte .{ .constant = 0xaa },
                    };
                    if (try isel.hasRepeatedByteRepr(.fromInterned(fill_val))) |fill_byte|
                        break :fill_byte .{ .constant = fill_byte };
                }
                switch (dst_ty.indexableElem(zcu).abiSize(zcu)) {
                    0 => unreachable,
                    1 => break :fill_byte .{ .value = bin_op.rhs },
                    2, 4, 8 => |size| {
                        const dst_vi = try isel.use(bin_op.lhs);
                        const ptr_ra = try isel.allocIntReg();
                        const fill_vi = try isel.use(bin_op.rhs);
                        const fill_mat = try fill_vi.matReg(isel);
                        const len_mat: Value.Materialize = len_mat: switch (dst_info.flags.size) {
                            .one => .{ .vi = undefined, .ra = try isel.allocIntReg() },
                            .many => unreachable,
                            .slice => {
                                var dst_len_it = dst_vi.field(dst_ty, 8, 8);
                                const dst_len_vi = try dst_len_it.only(isel);
                                break :len_mat try dst_len_vi.?.matReg(isel);
                            },
                            .c => unreachable,
                        };

                        const skip_label = isel.instructions.items.len;
                        _ = try isel.instructions.addOne(gpa);
                        try isel.emit(.sub(len_mat.ra.x(), len_mat.ra.x(), .{ .immediate = 1 }));
                        try isel.emit(switch (size) {
                            else => unreachable,
                            2 => .strh(fill_mat.ra.w(), .{ .post_index = .{ .base = ptr_ra.x(), .index = 2 } }),
                            4 => .str(fill_mat.ra.w(), .{ .post_index = .{ .base = ptr_ra.x(), .index = 4 } }),
                            8 => .str(fill_mat.ra.x(), .{ .post_index = .{ .base = ptr_ra.x(), .index = 8 } }),
                        });
                        isel.instructions.items[skip_label] = .cbnz(
                            len_mat.ra.x(),
                            -@as(i21, @intCast((isel.instructions.items.len - 1 - skip_label) << 2)),
                        );
                        switch (dst_info.flags.size) {
                            .one => {
                                const len_imm = ZigType.fromInterned(dst_info.child).arrayLen(zcu);
                                assert(len_imm > 0);
                                try isel.movImmediate(len_mat.ra.x(), len_imm);
                                isel.freeReg(len_mat.ra);
                                try fill_mat.finish(isel);
                                isel.freeReg(ptr_ra);
                                try dst_vi.liveOut(isel, ptr_ra);
                            },
                            .many => unreachable,
                            .slice => {
                                try isel.emit(.cbz(
                                    len_mat.ra.x(),
                                    @intCast((isel.instructions.items.len + 1 - skip_label) << 2),
                                ));
                                try len_mat.finish(isel);
                                try fill_mat.finish(isel);
                                isel.freeReg(ptr_ra);
                                var dst_ptr_it = dst_vi.field(dst_ty, 0, 8);
                                const dst_ptr_vi = try dst_ptr_it.only(isel);
                                try dst_ptr_vi.?.liveOut(isel, ptr_ra);
                            },
                            .c => unreachable,
                        }

                        break :air_tag if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
                    },
                    else => |size| {
                        const abi_size = std.math.cast(usize, size) orelse
                            return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(dst_ty) });
                        const maybe_byte_buffer: ?[]u8 = if (bin_op.rhs.toInterned()) |fill_val| buf: {
                            const buf = try gpa.alloc(u8, abi_size);
                            if (try isel.writeToMemory(.fromInterned(fill_val), buf)) break :buf buf;
                            gpa.free(buf);
                            break :buf null;
                        } else null;
                        defer if (maybe_byte_buffer) |buf| gpa.free(buf);

                        const src_vi: ?Value.Index = if (maybe_byte_buffer == null) try isel.use(bin_op.rhs) else null;
                        const dst_vi = try isel.use(bin_op.lhs);
                        const ptr_ra = try isel.allocIntReg();
                        const len_ra = try isel.allocIntReg();
                        const tmp_ra = try isel.allocIntReg();
                        const src_ra: ?Register.Alias = if (maybe_byte_buffer == null) try isel.allocIntReg() else null;

                        const skip_label = isel.instructions.items.len;
                        _ = try isel.instructions.addOne(gpa);
                        try isel.emit(.sub(len_ra.x(), len_ra.x(), .{ .immediate = 1 }));
                        var offset: usize = abi_size;
                        while (offset > 0) {
                            const chunk: usize = @as(usize, 1) << @intCast(@min(3, @ctz(offset)));
                            offset -= chunk;
                            if (maybe_byte_buffer) |byte_buffer| {
                                switch (chunk) {
                                    8 => {
                                        const val = std.mem.readInt(u64, byte_buffer[offset..][0..8], isel.target.cpu.arch.endian());
                                        try isel.emit(.str(if (val == 0) .xzr else tmp_ra.x(), .{ .post_index = .{ .base = ptr_ra.x(), .index = 8 } }));
                                        if (val != 0) try isel.movImmediate(tmp_ra.x(), val);
                                    },
                                    4 => {
                                        const val = std.mem.readInt(u32, byte_buffer[offset..][0..4], isel.target.cpu.arch.endian());
                                        try isel.emit(.str(if (val == 0) .wzr else tmp_ra.w(), .{ .post_index = .{ .base = ptr_ra.x(), .index = 4 } }));
                                        if (val != 0) try isel.movImmediate(tmp_ra.w(), val);
                                    },
                                    2 => {
                                        const val = std.mem.readInt(u16, byte_buffer[offset..][0..2], isel.target.cpu.arch.endian());
                                        try isel.emit(.strh(if (val == 0) .wzr else tmp_ra.w(), .{ .post_index = .{ .base = ptr_ra.x(), .index = 2 } }));
                                        if (val != 0) try isel.movImmediate(tmp_ra.w(), val);
                                    },
                                    1 => {
                                        const val = byte_buffer[offset];
                                        try isel.emit(.strb(if (val == 0) .wzr else tmp_ra.w(), .{ .post_index = .{ .base = ptr_ra.x(), .index = 1 } }));
                                        if (val != 0) try isel.movImmediate(tmp_ra.w(), val);
                                    },
                                    else => unreachable,
                                }
                            } else {
                                switch (chunk) {
                                    8 => try isel.emit(.str(tmp_ra.x(), .{ .post_index = .{ .base = ptr_ra.x(), .index = 8 } })),
                                    4 => try isel.emit(.str(tmp_ra.w(), .{ .post_index = .{ .base = ptr_ra.x(), .index = 4 } })),
                                    2 => try isel.emit(.strh(tmp_ra.w(), .{ .post_index = .{ .base = ptr_ra.x(), .index = 2 } })),
                                    1 => try isel.emit(.strb(tmp_ra.w(), .{ .post_index = .{ .base = ptr_ra.x(), .index = 1 } })),
                                    else => unreachable,
                                }
                                try isel.loadReg(tmp_ra, @intCast(chunk), .unsigned, src_ra.?, @intCast(offset));
                            }
                        }
                        isel.instructions.items[skip_label] = .cbnz(
                            len_ra.x(),
                            -@as(i21, @intCast((isel.instructions.items.len - 1 - skip_label) << 2)),
                        );
                        switch (dst_info.flags.size) {
                            .one => {
                                const len_imm = ZigType.fromInterned(dst_info.child).arrayLen(zcu);
                                assert(len_imm > 0);
                                try isel.movImmediate(len_ra.x(), len_imm);
                                isel.freeReg(tmp_ra);
                                isel.freeReg(len_ra);
                                if (src_ra) |s_ra| {
                                    isel.freeReg(s_ra);
                                    try src_vi.?.address(isel, 0, s_ra);
                                    const src_lock = isel.tryLockReg(s_ra);
                                    defer src_lock.unlock(isel);
                                    isel.freeReg(ptr_ra);
                                    try dst_vi.liveOut(isel, ptr_ra);
                                } else {
                                    isel.freeReg(ptr_ra);
                                    try dst_vi.liveOut(isel, ptr_ra);
                                }
                            },
                            .many => unreachable,
                            .slice => {
                                try isel.emit(.cbz(
                                    len_ra.x(),
                                    @intCast((isel.instructions.items.len + 1 - skip_label) << 2),
                                ));
                                isel.freeReg(tmp_ra);
                                var dst_len_it = dst_vi.field(dst_ty, 8, 8);
                                const dst_len_vi = try dst_len_it.only(isel);
                                var dst_ptr_it = dst_vi.field(dst_ty, 0, 8);
                                const dst_ptr_vi = try dst_ptr_it.only(isel);
                                if (src_ra) |s_ra| {
                                    isel.freeReg(s_ra);
                                    try src_vi.?.address(isel, 0, s_ra);
                                }
                                const src_lock = if (src_ra) |s_ra| isel.tryLockReg(s_ra) else null;
                                defer if (src_lock) |l| l.unlock(isel);
                                isel.freeReg(len_ra);
                                try dst_len_vi.?.liveOut(isel, len_ra);
                                const len_lock = isel.tryLockReg(len_ra);
                                defer len_lock.unlock(isel);
                                isel.freeReg(ptr_ra);
                                try dst_ptr_vi.?.liveOut(isel, ptr_ra);
                            },
                            .c => unreachable,
                        }

                        break :air_tag if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
                    },
                }
            };

            try call.prepareReturn(isel);
            try call.finishReturn(isel);

            try call.prepareCallee(isel);
            try isel.global_relocs.append(gpa, .{
                .name = "memset",
                .reloc = .{ .label = @intCast(isel.instructions.items.len) },
            });
            try isel.emit(.bl(0));
            try call.finishCallee(isel);

            try call.prepareParams(isel);
            const dst_vi = try isel.use(bin_op.lhs);
            switch (dst_info.flags.size) {
                .one => {
                    try isel.movImmediate(.x2, ZigType.fromInterned(dst_info.child).abiSize(zcu));
                    switch (fill_byte) {
                        .constant => |byte| try isel.movImmediate(.w1, byte),
                        .value => |byte| try call.paramLiveOut(isel, try isel.use(byte), .r1),
                    }
                    try call.paramLiveOut(isel, dst_vi, .r0);
                },
                .many => unreachable,
                .slice => {
                    var dst_ptr_it = dst_vi.field(dst_ty, 0, 8);
                    const dst_ptr_vi = try dst_ptr_it.only(isel);
                    var dst_len_it = dst_vi.field(dst_ty, 8, 8);
                    const dst_len_vi = try dst_len_it.only(isel);
                    try isel.elemPtr(.r2, .zr, .add, ZigType.fromInterned(dst_info.child).abiSize(zcu), dst_len_vi.?);
                    switch (fill_byte) {
                        .constant => |byte| try isel.movImmediate(.w1, byte),
                        .value => |byte| try call.paramLiveOut(isel, try isel.use(byte), .r1),
                    }
                    try call.paramLiveOut(isel, dst_ptr_vi.?, .r0);
                },
                .c => unreachable,
            }
            try call.finishParams(isel);

            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .memcpy, .memmove => |air_tag| {
            const bin_op = air.data(air.inst_index).bin_op;
            const dst_ty = isel.air.typeOf(bin_op.lhs, ip);
            const dst_info = dst_ty.ptrInfo(zcu);

            try call.prepareReturn(isel);
            try call.finishReturn(isel);

            try call.prepareCallee(isel);
            try isel.global_relocs.append(gpa, .{
                .name = @tagName(air_tag),
                .reloc = .{ .label = @intCast(isel.instructions.items.len) },
            });
            try isel.emit(.bl(0));
            try call.finishCallee(isel);

            try call.prepareParams(isel);
            switch (dst_info.flags.size) {
                .one => {
                    const dst_vi = try isel.use(bin_op.lhs);
                    const src_vi = try isel.use(bin_op.rhs);
                    try isel.movImmediate(.x2, ZigType.fromInterned(dst_info.child).abiSize(zcu));
                    try call.paramLiveOut(isel, src_vi, .r1);
                    try call.paramLiveOut(isel, dst_vi, .r0);
                },
                .many => unreachable,
                .slice => {
                    const dst_vi = try isel.use(bin_op.lhs);
                    var dst_ptr_it = dst_vi.field(dst_ty, 0, 8);
                    const dst_ptr_vi = try dst_ptr_it.only(isel);
                    var dst_len_it = dst_vi.field(dst_ty, 8, 8);
                    const dst_len_vi = try dst_len_it.only(isel);
                    const src_vi = try isel.use(bin_op.rhs);
                    try isel.elemPtr(.r2, .zr, .add, ZigType.fromInterned(dst_info.child).abiSize(zcu), dst_len_vi.?);
                    try call.paramLiveOut(isel, src_vi, .r1);
                    try call.paramLiveOut(isel, dst_ptr_vi.?, .r0);
                },
                .c => unreachable,
            }
            try call.finishParams(isel);

            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .atomic_load => {
            const atomic_load = air.data(air.inst_index).atomic_load;
            const ptr_ty = isel.air.typeOf(atomic_load.ptr, ip);
            const ptr_info = ptr_ty.ptrInfo(zcu);
            if (ptr_info.packed_offset.host_size > 0) return isel.fail("packed atomic load", .{});
            const is_acquire = switch (atomic_load.order) {
                .unordered, .monotonic => false,
                .acquire, .seq_cst => true,
                .release, .acq_rel => unreachable,
            };

            if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| {
                defer dst_vi.value.deref(isel);
                var ptr_mat: ?Value.Materialize = null;
                if (is_acquire) try isel.emit(.dsb(.ish));
                var dst_part_it = dst_vi.value.parts(isel);
                while (dst_part_it.next()) |dst_part_vi| {
                    const dst_ra = try dst_part_vi.defReg(isel) orelse continue;
                    if (ptr_mat == null) {
                        const ptr_vi = try isel.use(atomic_load.ptr);
                        ptr_mat = try ptr_vi.matReg(isel);
                    }
                    try isel.emit(switch (dst_part_vi.size(isel)) {
                        else => |size| return isel.fail("bad atomic load size of {d} from {f}", .{
                            size, isel.fmtType(ptr_ty),
                        }),
                        1 => switch (dst_part_vi.signedness(isel)) {
                            .signed => .ldrsb(dst_ra.w(), .{ .unsigned_offset = .{
                                .base = ptr_mat.?.ra.x(),
                                .offset = @intCast(dst_part_vi.get(isel).offset_from_parent),
                            } }),
                            .unsigned => .ldrb(dst_ra.w(), .{ .unsigned_offset = .{
                                .base = ptr_mat.?.ra.x(),
                                .offset = @intCast(dst_part_vi.get(isel).offset_from_parent),
                            } }),
                        },
                        2 => switch (dst_part_vi.signedness(isel)) {
                            .signed => .ldrsh(dst_ra.w(), .{ .unsigned_offset = .{
                                .base = ptr_mat.?.ra.x(),
                                .offset = @intCast(dst_part_vi.get(isel).offset_from_parent),
                            } }),
                            .unsigned => .ldrh(dst_ra.w(), .{ .unsigned_offset = .{
                                .base = ptr_mat.?.ra.x(),
                                .offset = @intCast(dst_part_vi.get(isel).offset_from_parent),
                            } }),
                        },
                        4 => .ldr(dst_ra.w(), .{ .unsigned_offset = .{
                            .base = ptr_mat.?.ra.x(),
                            .offset = @intCast(dst_part_vi.get(isel).offset_from_parent),
                        } }),
                        8 => .ldr(dst_ra.x(), .{ .unsigned_offset = .{
                            .base = ptr_mat.?.ra.x(),
                            .offset = @intCast(dst_part_vi.get(isel).offset_from_parent),
                        } }),
                    });
                }
                if (ptr_mat) |mat| {
                    if (atomic_load.order == .seq_cst) try isel.emit(.dsb(.ish));
                    try mat.finish(isel);
                } else {
                    const ptr_vi = try isel.use(atomic_load.ptr);
                    ptr_vi.deref(isel);
                }
            } else {
                const ptr_vi = try isel.use(atomic_load.ptr);
                if (ptr_info.flags.is_volatile) {
                    const ptr_mat = try ptr_vi.matReg(isel);
                    if (is_acquire) try isel.emit(.dsb(.ish));
                    const elem_size = ZigType.fromInterned(ptr_info.child).abiSize(zcu);
                    try isel.emit(switch (elem_size) {
                        1 => .ldrb(.wzr, .{ .base = ptr_mat.ra.x() }),
                        2 => .ldrh(.wzr, .{ .base = ptr_mat.ra.x() }),
                        4 => .ldr(.wzr, .{ .base = ptr_mat.ra.x() }),
                        8 => .ldr(.xzr, .{ .base = ptr_mat.ra.x() }),
                        else => return isel.fail("volatile atomic load size {d}", .{elem_size}),
                    });
                    if (atomic_load.order == .seq_cst) try isel.emit(.dsb(.ish));
                    try ptr_mat.finish(isel);
                } else {
                    ptr_vi.deref(isel);
                }
            }

            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .atomic_rmw => {
            const pl_op = air.data(air.inst_index).pl_op;
            const extra = isel.air.extraData(Air.AtomicRmw, pl_op.payload).data;
            const ptr_ty = isel.air.typeOf(pl_op.operand, ip);
            const ptr_info = ptr_ty.ptrInfo(zcu);
            if (ptr_info.packed_offset.host_size > 0) return isel.fail("packed atomic rmw", .{});
            const elem_ty: ZigType = .fromInterned(ptr_info.child);
            const size = elem_ty.abiSize(zcu);
            switch (size) {
                1, 2, 4, 8 => {},
                else => return isel.fail("bad atomic_rmw size {d} for {f}", .{ size, isel.fmtType(elem_ty) }),
            }
            const op = extra.op();
            const order = extra.ordering();
            const acquire = switch (order) {
                .unordered, .monotonic, .release => false,
                .acquire, .acq_rel, .seq_cst => true,
            };
            const release = switch (order) {
                .unordered, .monotonic, .acquire => false,
                .release, .acq_rel, .seq_cst => true,
            };

            const opt_old_vi = isel.live_values.fetchRemove(air.inst_index);
            defer if (opt_old_vi) |old_vi| old_vi.value.deref(isel);
            const opt_old_ra = if (opt_old_vi) |old_vi| try old_vi.value.defReg(isel) else null;
            const opt_old_lock: RegLock = if (opt_old_ra) |ra| isel.tryLockReg(ra) else .empty;
            defer opt_old_lock.unlock(isel);

            const ptr_vi = try isel.use(pl_op.operand);
            const rhs_vi = try isel.use(extra.operand);
            const ptr_mat = try ptr_vi.matReg(isel);
            const rhs_mat = try rhs_vi.matReg(isel);

            const old_ra = opt_old_ra orelse try isel.allocIntReg();
            defer if (opt_old_ra == null) isel.freeReg(old_ra);

            const new_ra = try isel.allocIntReg();
            defer isel.freeReg(new_ra);
            const status_ra = try isel.allocIntReg();
            defer isel.freeReg(status_ra);

            if (size < 4 and opt_old_ra != null and elem_ty.isAbiInt(zcu) and elem_ty.intInfo(zcu).signedness == .signed) {
                try isel.emit(.sbfm(old_ra.w(), old_ra.w(), .{
                    .N = .word,
                    .immr = 0,
                    .imms = @intCast(size * 8 - 1),
                }));
            }

            const loop_end_label = isel.instructions.items.len;
            try isel.emit(.cbnz(status_ra.w(), 0));
            const stxr_src_ra = if (op == .Xchg) rhs_mat.ra else new_ra;
            try isel.emit(stxr(size, status_ra, stxr_src_ra, ptr_mat.ra, release));
            switch (op) {
                .Xchg => {},
                .Add => try isel.emit(if (size == 8)
                    .add(new_ra.x(), old_ra.x(), .{ .register = rhs_mat.ra.x() })
                else
                    .add(new_ra.w(), old_ra.w(), .{ .register = rhs_mat.ra.w() })),
                .Sub => try isel.emit(if (size == 8)
                    .sub(new_ra.x(), old_ra.x(), .{ .register = rhs_mat.ra.x() })
                else
                    .sub(new_ra.w(), old_ra.w(), .{ .register = rhs_mat.ra.w() })),
                .And => try isel.emit(if (size == 8)
                    .@"and"(new_ra.x(), old_ra.x(), .{ .register = rhs_mat.ra.x() })
                else
                    .@"and"(new_ra.w(), old_ra.w(), .{ .register = rhs_mat.ra.w() })),
                .Nand => {
                    try isel.emit(if (size == 8)
                        .orn(new_ra.x(), .xzr, .{ .register = new_ra.x() })
                    else
                        .orn(new_ra.w(), .wzr, .{ .register = new_ra.w() }));
                    try isel.emit(if (size == 8)
                        .@"and"(new_ra.x(), old_ra.x(), .{ .register = rhs_mat.ra.x() })
                    else
                        .@"and"(new_ra.w(), old_ra.w(), .{ .register = rhs_mat.ra.w() }));
                },
                .Or => try isel.emit(if (size == 8)
                    .orr(new_ra.x(), old_ra.x(), .{ .register = rhs_mat.ra.x() })
                else
                    .orr(new_ra.w(), old_ra.w(), .{ .register = rhs_mat.ra.w() })),
                .Xor => try isel.emit(if (size == 8)
                    .eor(new_ra.x(), old_ra.x(), .{ .register = rhs_mat.ra.x() })
                else
                    .eor(new_ra.w(), old_ra.w(), .{ .register = rhs_mat.ra.w() })),
                .Max, .Min => {
                    const signed = elem_ty.intInfo(zcu).signedness == .signed;
                    const cond: codegen.aarch64.encoding.ConditionCode = switch (op) {
                        .Max => if (signed) .gt else .hi,
                        .Min => if (signed) .lt else .lo,
                        else => unreachable,
                    };
                    if (size == 8) {
                        try isel.emit(.csel(new_ra.x(), old_ra.x(), rhs_mat.ra.x(), cond));
                        try isel.emit(.subs(.xzr, old_ra.x(), .{ .register = rhs_mat.ra.x() }));
                    } else {
                        try isel.emit(.csel(new_ra.w(), old_ra.w(), rhs_mat.ra.w(), cond));
                        try isel.emit(.subs(.wzr, old_ra.w(), .{ .register = rhs_mat.ra.w() }));
                        if (size < 4) {
                            const imms: u6 = @intCast(size * 8 - 1);
                            try isel.emit(if (signed)
                                .sbfm(old_ra.w(), old_ra.w(), .{ .N = .word, .immr = 0, .imms = imms })
                            else
                                .ubfm(old_ra.w(), old_ra.w(), .{ .N = .word, .immr = 0, .imms = imms }));
                        }
                    }
                },
            }
            try isel.emit(ldxr(size, old_ra, ptr_mat.ra, acquire));
            isel.instructions.items[loop_end_label] = .cbnz(
                status_ra.w(),
                -@as(i21, @intCast((isel.instructions.items.len - 1 - loop_end_label) << 2)),
            );

            try rhs_mat.finish(isel);
            try ptr_mat.finish(isel);
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .cmpxchg_weak, .cmpxchg_strong => |air_tag| {
            const ty_pl = air.data(air.inst_index).ty_pl;
            const extra = isel.air.extraData(Air.Cmpxchg, ty_pl.payload).data;
            const res_ty = ty_pl.ty;
            const elem_ty = res_ty.optionalChild(zcu);
            const size = elem_ty.abiSize(zcu);
            switch (size) {
                1, 2, 4, 8 => {},
                else => return isel.fail("bad {t} size {d} for {f}", .{ air_tag, size, isel.fmtType(elem_ty) }),
            }
            const success_order = extra.successOrder();
            const fail_order = extra.failureOrder();
            const acquire = switch (success_order) {
                .unordered, .monotonic, .release => false,
                .acquire, .acq_rel, .seq_cst => true,
            } or switch (fail_order) {
                .unordered, .monotonic, .release => false,
                .acquire, .acq_rel, .seq_cst => true,
            };
            const release = switch (success_order) {
                .unordered, .monotonic, .acquire => false,
                .release, .acq_rel, .seq_cst => true,
            };

            const opt_res_vi = isel.live_values.fetchRemove(air.inst_index);
            defer if (opt_res_vi) |res_vi| res_vi.value.deref(isel);
            var opt_payload_ra: ?Register.Alias = null;
            var opt_non_null_ra: ?Register.Alias = null;
            if (opt_res_vi) |res_vi| {
                if (res_ty.optionalReprIsPayload(zcu)) {
                    opt_payload_ra = try res_vi.value.defReg(isel);
                } else {
                    var non_null_it = res_vi.value.field(res_ty, size, 1);
                    const non_null_vi = try non_null_it.only(isel);
                    opt_non_null_ra = try non_null_vi.?.defReg(isel);
                    const early_non_null_lock: RegLock = if (opt_non_null_ra) |ra| isel.tryLockReg(ra) else .empty;
                    defer early_non_null_lock.unlock(isel);
                    var payload_it = res_vi.value.field(res_ty, 0, size);
                    const payload_vi = try payload_it.only(isel);
                    opt_payload_ra = try payload_vi.?.defReg(isel);
                }
            }
            const payload_lock: RegLock = if (opt_payload_ra) |ra| isel.tryLockReg(ra) else .empty;
            defer payload_lock.unlock(isel);
            const non_null_lock: RegLock = if (opt_non_null_ra) |ra| isel.tryLockReg(ra) else .empty;
            defer non_null_lock.unlock(isel);

            const ptr_vi = try isel.use(extra.ptr);
            const exp_vi = try isel.use(extra.expected_value);
            const new_vi = try isel.use(extra.new_value);
            const ptr_mat = try ptr_vi.matReg(isel);
            const exp_mat = try exp_vi.matReg(isel);
            const new_mat = try new_vi.matReg(isel);

            const old_ra = opt_payload_ra orelse try isel.allocIntReg();
            defer if (opt_payload_ra == null) isel.freeReg(old_ra);
            const status_ra = opt_non_null_ra orelse try isel.allocIntReg();
            defer if (opt_non_null_ra == null) isel.freeReg(status_ra);

            if (size < 4 and opt_payload_ra != null and elem_ty.isAbiInt(zcu) and elem_ty.intInfo(zcu).signedness == .signed) {
                try isel.emit(.sbfm(old_ra.w(), old_ra.w(), .{
                    .N = .word,
                    .immr = 0,
                    .imms = @intCast(size * 8 - 1),
                }));
            }
            const done_label = isel.instructions.items.len;

            if (opt_non_null_ra != null) {
                try isel.emit(.movz(status_ra.w(), 1, .{ .lsl = .@"0" }));
            }
            try isel.emit(.clrex(15));
            const fail_label = isel.instructions.items.len;

            try isel.emit(.b(@intCast((isel.instructions.items.len + 1 - done_label) << 2)));
            if (res_ty.optionalReprIsPayload(zcu) and opt_payload_ra != null) {
                try isel.emit(.orr(old_ra.x(), .xzr, .{ .register = .xzr }));
            }
            const cbnz_label = isel.instructions.items.len;
            try isel.emit(.cbnz(
                status_ra.w(),
                if (air_tag == .cmpxchg_weak)
                    @intCast((isel.instructions.items.len + 1 - done_label) << 2)
                else
                    0,
            ));
            try isel.emit(stxr(size, status_ra, new_mat.ra, ptr_mat.ra, release));
            try isel.emit(.@"b."(.ne, @intCast((isel.instructions.items.len + 1 - fail_label) << 2)));
            try isel.emit(switch (size) {
                1 => .subs(.wzr, old_ra.w(), .{ .extended_register = .{
                    .register = exp_mat.ra.w(),
                    .extend = .{ .uxtb = 0 },
                } }),
                2 => .subs(.wzr, old_ra.w(), .{ .extended_register = .{
                    .register = exp_mat.ra.w(),
                    .extend = .{ .uxth = 0 },
                } }),
                4 => .subs(.wzr, old_ra.w(), .{ .register = exp_mat.ra.w() }),
                8 => .subs(.xzr, old_ra.x(), .{ .register = exp_mat.ra.x() }),
                else => unreachable,
            });
            try isel.emit(ldxr(size, old_ra, ptr_mat.ra, acquire));
            if (air_tag == .cmpxchg_strong) {
                isel.instructions.items[cbnz_label] = .cbnz(
                    status_ra.w(),
                    -@as(i21, @intCast((isel.instructions.items.len - 1 - cbnz_label) << 2)),
                );
            }

            try new_mat.finish(isel);
            try exp_mat.finish(isel);
            try ptr_mat.finish(isel);
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .error_name => {
            if (isel.live_values.fetchRemove(air.inst_index)) |name_vi| unused: {
                defer name_vi.value.deref(isel);
                var ptr_part_it = name_vi.value.field(.slice_const_u8_sentinel_0, 0, 8);
                const ptr_part_vi = try ptr_part_it.only(isel);
                const ptr_part_ra = try ptr_part_vi.?.defReg(isel);
                var len_part_it = name_vi.value.field(.slice_const_u8_sentinel_0, 8, 8);
                const len_part_vi = try len_part_it.only(isel);
                const len_part_ra = len_part_ra: {
                    const ptr_lock: RegLock = if (ptr_part_ra) |name_ptr_ra| isel.tryLockReg(name_ptr_ra) else .empty;
                    defer ptr_lock.unlock(isel);
                    break :len_part_ra try len_part_vi.?.defReg(isel);
                };
                if (ptr_part_ra == null and len_part_ra == null) break :unused;

                const un_op = air.data(air.inst_index).un_op;
                const error_vi = try isel.use(un_op);
                const error_mat = try error_vi.matReg(isel);
                const ptr_ra = try isel.allocIntReg();
                defer isel.freeReg(ptr_ra);
                const start_ra, const end_ra = range_ras: {
                    const name_lock: RegLock = if (len_part_ra != null) if (ptr_part_ra) |name_ptr_ra|
                        isel.tryLockReg(name_ptr_ra)
                    else
                        .empty else .empty;
                    defer name_lock.unlock(isel);
                    break :range_ras .{ try isel.allocIntReg(), try isel.allocIntReg() };
                };
                defer {
                    isel.freeReg(start_ra);
                    isel.freeReg(end_ra);
                }
                if (len_part_ra) |name_len_ra| try isel.emit(.sub(
                    name_len_ra.w(),
                    end_ra.w(),
                    .{ .register = start_ra.w() },
                ));
                if (ptr_part_ra) |name_ptr_ra| try isel.emit(.add(
                    name_ptr_ra.x(),
                    ptr_ra.x(),
                    .{ .extended_register = .{
                        .register = start_ra.w(),
                        .extend = .{ .uxtw = 0 },
                    } },
                ));
                if (len_part_ra) |_| try isel.emit(.sub(end_ra.w(), end_ra.w(), .{ .immediate = 1 }));
                try isel.emit(.ldp(start_ra.w(), end_ra.w(), .{ .base = start_ra.x() }));
                try isel.emit(.add(start_ra.x(), ptr_ra.x(), .{ .extended_register = .{
                    .register = error_mat.ra.w(),
                    .extend = switch (zcu.errorSetBits()) {
                        else => unreachable,
                        1...8 => .{ .uxtb = 2 },
                        9...16 => .{ .uxth = 2 },
                        17...32 => .{ .uxtw = 2 },
                    },
                } }));
                try isel.lazy_relocs.append(gpa, .{
                    .symbol = .{ .kind = .const_data, .ty = .anyerror_type },
                    .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                });
                try isel.emit(.add(ptr_ra.x(), ptr_ra.x(), .{ .immediate = 0 }));
                try isel.lazy_relocs.append(gpa, .{
                    .symbol = .{ .kind = .const_data, .ty = .anyerror_type },
                    .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                });
                try isel.emit(.adrp(ptr_ra.x(), 0));
                try error_mat.finish(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .tag_name => {
            if (isel.live_values.fetchRemove(air.inst_index)) |name_vi| unused: {
                defer name_vi.value.deref(isel);
                var ptr_part_it = name_vi.value.field(.slice_const_u8_sentinel_0, 0, 8);
                const ptr_part_vi = try ptr_part_it.only(isel);
                const ptr_part_ra = try ptr_part_vi.?.defReg(isel);
                var len_part_it = name_vi.value.field(.slice_const_u8_sentinel_0, 8, 8);
                const len_part_vi = try len_part_it.only(isel);
                const len_part_ra = len_part_ra: {
                    const ptr_lock: RegLock = if (ptr_part_ra) |name_ptr_ra| isel.tryLockReg(name_ptr_ra) else .empty;
                    defer ptr_lock.unlock(isel);
                    break :len_part_ra try len_part_vi.?.defReg(isel);
                };
                if (ptr_part_ra == null and len_part_ra == null) break :unused;

                const un_op = air.data(air.inst_index).un_op;
                const enum_ty = isel.air.typeOf(un_op, ip);
                const int_info = enum_ty.intInfo(zcu);
                if (int_info.bits > 64) return isel.fail("too big tag_name {f}", .{isel.fmtType(enum_ty)});

                const tag_vi = try isel.use(un_op);
                const tag_mat = try tag_vi.matReg(isel);
                const ptr_ra = try isel.allocIntReg();
                defer isel.freeReg(ptr_ra);
                const start_ra, const end_ra = range_ras: {
                    const name_lock: RegLock = if (len_part_ra != null) if (ptr_part_ra) |name_ptr_ra|
                        isel.tryLockReg(name_ptr_ra)
                    else
                        .empty else .empty;
                    defer name_lock.unlock(isel);
                    break :range_ras .{ try isel.allocIntReg(), try isel.allocIntReg() };
                };
                defer {
                    isel.freeReg(start_ra);
                    isel.freeReg(end_ra);
                }
                if (len_part_ra) |name_len_ra| try isel.emit(.sub(
                    name_len_ra.w(),
                    end_ra.w(),
                    .{ .register = start_ra.w() },
                ));
                if (ptr_part_ra) |name_ptr_ra| try isel.emit(.add(
                    name_ptr_ra.x(),
                    ptr_ra.x(),
                    .{ .extended_register = .{
                        .register = start_ra.w(),
                        .extend = .{ .uxtw = 0 },
                    } },
                ));
                if (len_part_ra) |_| try isel.emit(.sub(end_ra.w(), end_ra.w(), .{ .immediate = 1 }));
                try isel.emit(.ldp(start_ra.w(), end_ra.w(), .{ .base = start_ra.x() }));
                const loaded_enum = ip.loadEnumType(enum_ty.toIntern());
                const tag_values = loaded_enum.field_values.get(ip);
                if (tag_values.len == 0) {
                    try isel.emit(switch (int_info.bits) {
                        else => unreachable,
                        1...32 => .add(start_ra.x(), ptr_ra.x(), .{ .extended_register = .{
                            .register = tag_mat.ra.w(),
                            .extend = switch (int_info.bits) {
                                else => unreachable,
                                1...8 => .{ .uxtb = 2 },
                                9...16 => .{ .uxth = 2 },
                                17...32 => .{ .uxtw = 2 },
                            },
                        } }),
                        33...64 => .add(start_ra.x(), ptr_ra.x(), .{ .shifted_register = .{
                            .register = tag_mat.ra.x(),
                            .shift = .{ .lsl = 2 },
                        } }),
                    });
                } else {
                    try isel.emit(.add(start_ra.x(), ptr_ra.x(), .{ .extended_register = .{
                        .register = start_ra.w(),
                        .extend = .{ .uxtw = 2 },
                    } }));
                    for (tag_values[1..], 1..) |tag_value, tag_index| {
                        const val: Constant = .fromInterned(tag_value);
                        var val_space: Constant.BigIntSpace = undefined;
                        const val_bigint = val.toBigInt(&val_space, zcu);
                        const val_u64: u64 = if (val_bigint.positive)
                            val_bigint.toInt(u64) catch unreachable
                        else
                            @bitCast(val_bigint.toInt(i64) catch unreachable);
                        try isel.emit(.csel(start_ra.w(), end_ra.w(), start_ra.w(), .eq));
                        try isel.movImmediate(end_ra.w(), @intCast(tag_index));
                        switch (int_info.bits) {
                            else => unreachable,
                            1...32 => {
                                try isel.emit(.subs(.wzr, tag_mat.ra.w(), .{ .register = end_ra.w() }));
                                try isel.movImmediate(end_ra.w(), @as(u32, @truncate(val_u64)));
                            },
                            33...64 => {
                                try isel.emit(.subs(.xzr, tag_mat.ra.x(), .{ .register = end_ra.x() }));
                                try isel.movImmediate(end_ra.x(), val_u64);
                            },
                        }
                    }
                    try isel.movImmediate(start_ra.w(), 0);
                }
                try isel.lazy_relocs.append(gpa, .{
                    .symbol = .{ .kind = .const_data, .ty = enum_ty.toIntern() },
                    .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                });
                try isel.emit(.add(ptr_ra.x(), ptr_ra.x(), .{ .immediate = 0 }));
                try isel.lazy_relocs.append(gpa, .{
                    .symbol = .{ .kind = .const_data, .ty = enum_ty.toIntern() },
                    .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                });
                try isel.emit(.adrp(ptr_ra.x(), 0));
                try tag_mat.finish(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .aggregate_init => {
            if (isel.live_values.fetchRemove(air.inst_index)) |agg_vi| {
                defer agg_vi.value.deref(isel);

                const ty_pl = air.data(air.inst_index).ty_pl;
                const agg_ty = ty_pl.ty;
                switch (ip.indexToKey(agg_ty.toIntern())) {
                    .vector_type => |vector_type| {
                        const elems: []const Air.Inst.Ref =
                            @ptrCast(isel.air.extra.items[ty_pl.payload..][0..@intCast(vector_type.len)]);
                        var elem_offset: u64 = 0;
                        const elem_ty: ZigType = .fromInterned(vector_type.child);
                        const elem_size = elem_ty.abiSize(zcu);
                        for (elems) |elem| {
                            var agg_part_it = agg_vi.value.field(agg_ty, elem_offset, elem_size);
                            try agg_part_it.move(isel, elem_ty, elem);
                            elem_offset += elem_size;
                        }
                    },
                    .array_type => |array_type| {
                        const elems: []const Air.Inst.Ref =
                            @ptrCast(isel.air.extra.items[ty_pl.payload..][0..@intCast(array_type.len)]);
                        var elem_offset: u64 = 0;
                        const elem_ty: ZigType = .fromInterned(array_type.child);
                        const elem_size = elem_ty.abiSize(zcu);
                        for (elems) |elem| {
                            var agg_part_it = agg_vi.value.field(agg_ty, elem_offset, elem_size);
                            try agg_part_it.move(isel, elem_ty, elem);
                            elem_offset += elem_size;
                        }
                        switch (array_type.sentinel) {
                            .none => {},
                            else => |sentinel| {
                                var agg_part_it = agg_vi.value.field(agg_ty, elem_offset, elem_size);
                                try agg_part_it.move(isel, elem_ty, .fromIntern(sentinel));
                            },
                        }
                    },
                    .struct_type => {
                        const loaded_struct = ip.loadStructType(agg_ty.toIntern());
                        const elems: []const Air.Inst.Ref =
                            @ptrCast(isel.air.extra.items[ty_pl.payload..][0..loaded_struct.field_types.len]);
                        var field_offset: u64 = 0;
                        var field_it = loaded_struct.iterateRuntimeOrder(ip);
                        while (field_it.next()) |field_index| {
                            const field_ty: ZigType = .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                            field_offset = loaded_struct.field_offsets.get(ip)[field_index];
                            const field_size = field_ty.abiSize(zcu);
                            if (field_size == 0) continue;
                            var agg_part_it = agg_vi.value.field(agg_ty, field_offset, field_size);
                            try agg_part_it.move(isel, field_ty, elems[field_index]);
                            field_offset += field_size;
                        }
                        assert(loaded_struct.alignment.forward(field_offset) == agg_vi.value.size(isel));
                    },
                    .tuple_type => |tuple_type| {
                        const elems: []const Air.Inst.Ref =
                            @ptrCast(isel.air.extra.items[ty_pl.payload..][0..tuple_type.types.len]);
                        var tuple_align: InternPool.Alignment = .@"1";
                        var field_offset: u64 = 0;
                        for (
                            tuple_type.types.get(ip),
                            tuple_type.values.get(ip),
                            elems,
                        ) |field_ty_index, field_val, elem| {
                            if (field_val != .none) continue;
                            const field_ty: ZigType = .fromInterned(field_ty_index);
                            const field_align = field_ty.abiAlignment(zcu);
                            tuple_align = tuple_align.maxStrict(field_align);
                            field_offset = field_align.forward(field_offset);
                            const field_size = field_ty.abiSize(zcu);
                            if (field_size == 0) continue;
                            var agg_part_it = agg_vi.value.field(agg_ty, field_offset, field_size);
                            try agg_part_it.move(isel, field_ty, elem);
                            field_offset += field_size;
                        }
                        assert(tuple_align.forward(field_offset) == agg_vi.value.size(isel));
                    },
                    else => return isel.fail("aggregate init {f}", .{isel.fmtType(agg_ty)}),
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .splat => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |vec_vi| unused: {
                defer vec_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const vec_ty = ty_op.ty;
                const vector_type = ip.indexToKey(vec_ty.toIntern()).vector_type;
                const elem_ty: ZigType = .fromInterned(vector_type.child);
                const elem_size = elem_ty.abiSize(zcu);
                if (vec_ty.bitSize(zcu) == vector_type.len * elem_size * 8) {
                    const elem_vi = try isel.use(ty_op.operand);
                    var elem_offset = vec_vi.value.size(isel);
                    while (elem_offset > 0) {
                        elem_offset -= elem_size;
                        var vec_part_it = vec_vi.value.field(vec_ty, elem_offset, elem_size);
                        try vec_part_it.copyFrom(isel, elem_ty, elem_vi);
                    }
                } else if (vec_ty.abiSize(zcu) <= 8 and elem_ty.isAbiInt(zcu)) {
                    const dst_ra = try vec_vi.value.defReg(isel) orelse break :unused;
                    const elem_vi = try isel.use(ty_op.operand);
                    if (vector_type.len == 0) break :unused;
                    var dst_lock = isel.lockReg(dst_ra);
                    defer dst_lock.unlock(isel);
                    const elem_mat = try elem_vi.matReg(isel);
                    const bits = elem_ty.intInfo(zcu).bits;
                    var elem_index: u64 = vector_type.len;
                    while (elem_index > 0) {
                        elem_index -= 1;
                        const bit_offset: u6 = @intCast(elem_index * bits);
                        if (bit_offset > 0) {
                            try isel.emit(.bfm(dst_ra.x(), elem_mat.ra.x(), .{
                                .N = .doubleword,
                                .immr = @as(u6, @truncate(64 - @as(u7, bit_offset))),
                                .imms = @intCast(bits - 1),
                            }));
                        } else {
                            try isel.emit(.ubfm(dst_ra.x(), elem_mat.ra.x(), .{
                                .N = .doubleword,
                                .immr = 0,
                                .imms = @intCast(bits - 1),
                            }));
                        }
                    }
                    try elem_mat.finish(isel);
                } else return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(vec_ty) });
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .union_init => |air_tag| {
            if (isel.live_values.fetchRemove(air.inst_index)) |union_vi| unused: {
                defer union_vi.value.deref(isel);

                const ty_pl = air.data(air.inst_index).ty_pl;
                const extra = isel.air.extraData(Air.UnionInit, ty_pl.payload).data;
                const union_ty = ty_pl.ty;
                const loaded_union = ip.loadUnionType(union_ty.toIntern());
                const union_layout = ZigType.getUnionLayout(loaded_union, zcu);

                if (union_layout.tag_size > 0) unused_tag: {
                    const loaded_tag = ip.loadEnumType(loaded_union.enum_tag_type);
                    var tag_it = union_vi.value.field(union_ty, union_layout.tagOffset(), union_layout.tag_size);
                    const tag_vi = try tag_it.only(isel);
                    const tag_ra = try tag_vi.?.defReg(isel) orelse break :unused_tag;
                    switch (union_layout.tag_size) {
                        0 => unreachable,
                        1...4 => try isel.movImmediate(tag_ra.w(), @as(u32, switch (loaded_tag.field_values.len) {
                            0 => extra.field_index,
                            else => switch (ip.indexToKey(loaded_tag.field_values.get(ip)[extra.field_index]).int.storage) {
                                .u64 => |imm| @intCast(imm),
                                .i64 => |imm| @bitCast(@as(i32, @intCast(imm))),
                                else => unreachable,
                            },
                        })),
                        5...8 => try isel.movImmediate(tag_ra.x(), switch (loaded_tag.field_values.len) {
                            0 => extra.field_index,
                            else => switch (ip.indexToKey(loaded_tag.field_values.get(ip)[extra.field_index]).int.storage) {
                                .u64 => |imm| imm,
                                .i64 => |imm| @bitCast(imm),
                                else => unreachable,
                            },
                        }),
                        else => return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(union_ty) }),
                    }
                }
                var payload_it = union_vi.value.field(union_ty, union_layout.payloadOffset(), union_layout.payload_size);
                var any_used = false;
                while (try payload_it.next(isel)) |payload_part| {
                    if (try payload_part.vi.defAddr(isel, union_ty, .{ .root_vi = union_vi.value })) |_| {
                        any_used = true;
                    }
                }
                if (!any_used) break :unused;

                try call.prepareReturn(isel);
                try call.finishReturn(isel);

                try call.prepareCallee(isel);
                try isel.global_relocs.append(gpa, .{
                    .name = "memcpy",
                    .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                });
                try isel.emit(.bl(0));
                try call.finishCallee(isel);

                try call.prepareParams(isel);
                const init_vi = try isel.use(extra.init);
                try isel.movImmediate(.x2, init_vi.size(isel));
                try call.paramAddress(isel, init_vi, .r1);
                try call.paramAddressOffset(isel, union_vi.value, union_layout.payloadOffset(), .r0);
                try call.finishParams(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .prefetch => {
            const prefetch = air.data(air.inst_index).prefetch;
            if (!(prefetch.rw == .write and prefetch.cache == .instruction)) {
                const maybe_slice_ty = isel.air.typeOf(prefetch.ptr, ip);
                const maybe_slice_vi = try isel.use(prefetch.ptr);
                const ptr_vi = if (maybe_slice_ty.isSlice(zcu)) ptr_vi: {
                    var ptr_part_it = maybe_slice_vi.field(maybe_slice_ty, 0, 8);
                    const ptr_part_vi = try ptr_part_it.only(isel);
                    break :ptr_vi ptr_part_vi.?;
                } else maybe_slice_vi;
                const ptr_mat = try ptr_vi.matReg(isel);
                try isel.emit(.prfm(.{
                    .policy = switch (prefetch.locality) {
                        1, 2, 3 => .keep,
                        0 => .strm,
                    },
                    .target = switch (prefetch.locality) {
                        0, 3 => .l1,
                        2 => .l2,
                        1 => .l3,
                    },
                    .type = switch (prefetch.rw) {
                        .read => switch (prefetch.cache) {
                            .data => .pld,
                            .instruction => .pli,
                        },
                        .write => switch (prefetch.cache) {
                            .data => .pst,
                            .instruction => unreachable,
                        },
                    },
                }, .{ .base = ptr_mat.ra.x() }));
                try ptr_mat.finish(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .mul_add => {
            if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const pl_op = air.data(air.inst_index).pl_op;
                const bin_op = isel.air.extraData(Air.Bin, pl_op.payload).data;
                const ty = isel.air.typeOf(pl_op.operand, ip);
                switch (ty.floatBits(isel.target)) {
                    else => unreachable,
                    16, 32, 64 => |bits| {
                        const res_ra = try res_vi.value.defReg(isel) orelse break :unused;
                        const need_fcvt = switch (bits) {
                            else => unreachable,
                            16 => !isel.target.cpu.has(.aarch64, .fullfp16),
                            32, 64 => false,
                        };
                        if (need_fcvt) try isel.emit(.fcvt(res_ra.h(), res_ra.s()));
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        const addend_vi = try isel.use(pl_op.operand);
                        const lhs_mat = try lhs_vi.matReg(isel);
                        const rhs_mat = try rhs_vi.matReg(isel);
                        const addend_mat = try addend_vi.matReg(isel);
                        const lhs_ra = if (need_fcvt) try isel.allocVecReg() else lhs_mat.ra;
                        defer if (need_fcvt) isel.freeReg(lhs_ra);
                        const rhs_ra = if (need_fcvt) try isel.allocVecReg() else rhs_mat.ra;
                        defer if (need_fcvt) isel.freeReg(rhs_ra);
                        const addend_ra = if (need_fcvt) try isel.allocVecReg() else addend_mat.ra;
                        defer if (need_fcvt) isel.freeReg(addend_ra);
                        try isel.emit(bits: switch (bits) {
                            else => unreachable,
                            16 => if (need_fcvt)
                                continue :bits 32
                            else
                                .fmadd(res_ra.h(), lhs_ra.h(), rhs_ra.h(), addend_ra.h()),
                            32 => .fmadd(res_ra.s(), lhs_ra.s(), rhs_ra.s(), addend_ra.s()),
                            64 => .fmadd(res_ra.d(), lhs_ra.d(), rhs_ra.d(), addend_ra.d()),
                        });
                        if (need_fcvt) {
                            try isel.emit(.fcvt(addend_ra.s(), addend_mat.ra.h()));
                            try isel.emit(.fcvt(rhs_ra.s(), rhs_mat.ra.h()));
                            try isel.emit(.fcvt(lhs_ra.s(), lhs_mat.ra.h()));
                        }
                        try addend_mat.finish(isel);
                        try rhs_mat.finish(isel);
                        try lhs_mat.finish(isel);
                    },
                    80, 128 => |bits| {
                        try call.prepareReturn(isel);
                        switch (bits) {
                            else => unreachable,
                            16, 32, 64, 128 => try call.returnLiveIn(isel, res_vi.value, .v0),
                            80 => {
                                var res_hi16_it = res_vi.value.field(ty, 8, 8);
                                const res_hi16_vi = try res_hi16_it.only(isel);
                                try call.returnLiveIn(isel, res_hi16_vi.?, .r1);
                                var res_lo64_it = res_vi.value.field(ty, 0, 8);
                                const res_lo64_vi = try res_lo64_it.only(isel);
                                try call.returnLiveIn(isel, res_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishReturn(isel);

                        try call.prepareCallee(isel);
                        try isel.global_relocs.append(gpa, .{
                            .name = switch (bits) {
                                else => unreachable,
                                16 => "__fmah",
                                32 => "fmaf",
                                64 => "fma",
                                80 => "__fmax",
                                128 => "fmaf128",
                            },
                            .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                        });
                        try isel.emit(.bl(0));
                        try call.finishCallee(isel);

                        try call.prepareParams(isel);
                        const lhs_vi = try isel.use(bin_op.lhs);
                        const rhs_vi = try isel.use(bin_op.rhs);
                        const addend_vi = try isel.use(pl_op.operand);
                        switch (bits) {
                            else => unreachable,
                            16, 32, 64, 128 => {
                                try call.paramLiveOut(isel, addend_vi, .v2);
                                try call.paramLiveOut(isel, rhs_vi, .v1);
                                try call.paramLiveOut(isel, lhs_vi, .v0);
                            },
                            80 => {
                                var addend_hi16_it = addend_vi.field(ty, 8, 8);
                                const addend_hi16_vi = try addend_hi16_it.only(isel);
                                try call.paramLiveOut(isel, addend_hi16_vi.?, .r5);
                                var addend_lo64_it = addend_vi.field(ty, 0, 8);
                                const addend_lo64_vi = try addend_lo64_it.only(isel);
                                try call.paramLiveOut(isel, addend_lo64_vi.?, .r4);
                                var rhs_hi16_it = rhs_vi.field(ty, 8, 8);
                                const rhs_hi16_vi = try rhs_hi16_it.only(isel);
                                try call.paramLiveOut(isel, rhs_hi16_vi.?, .r3);
                                var rhs_lo64_it = rhs_vi.field(ty, 0, 8);
                                const rhs_lo64_vi = try rhs_lo64_it.only(isel);
                                try call.paramLiveOut(isel, rhs_lo64_vi.?, .r2);
                                var lhs_hi16_it = lhs_vi.field(ty, 8, 8);
                                const lhs_hi16_vi = try lhs_hi16_it.only(isel);
                                try call.paramLiveOut(isel, lhs_hi16_vi.?, .r1);
                                var lhs_lo64_it = lhs_vi.field(ty, 0, 8);
                                const lhs_lo64_vi = try lhs_lo64_it.only(isel);
                                try call.paramLiveOut(isel, lhs_lo64_vi.?, .r0);
                            },
                        }
                        try call.finishParams(isel);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .field_parent_ptr => {
            if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);
                const ty_pl = air.data(air.inst_index).ty_pl;
                const extra = isel.air.extraData(Air.FieldParentPtr, ty_pl.payload).data;
                switch (codegen.fieldOffset(
                    ty_pl.ty,
                    isel.air.typeOf(extra.field_ptr, ip),
                    extra.field_index,
                    zcu,
                )) {
                    0 => try dst_vi.value.move(isel, extra.field_ptr),
                    else => |field_offset| {
                        const dst_ra = try dst_vi.value.defReg(isel) orelse break :unused;
                        const src_vi = try isel.use(extra.field_ptr);
                        const src_mat = try src_vi.matReg(isel);
                        const lo12: u12 = @truncate(field_offset >> 0);
                        const hi12: u12 = @intCast(field_offset >> 12);
                        if (hi12 > 0) try isel.emit(.sub(
                            dst_ra.x(),
                            if (lo12 > 0) dst_ra.x() else src_mat.ra.x(),
                            .{ .shifted_immediate = .{ .immediate = hi12, .lsl = .@"12" } },
                        ));
                        if (lo12 > 0) try isel.emit(.sub(dst_ra.x(), src_mat.ra.x(), .{ .immediate = lo12 }));
                        try src_mat.finish(isel);
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .wasm_memory_size, .wasm_memory_grow => unreachable,
        .cmp_lte_errors_len => {
            if (isel.live_values.fetchRemove(air.inst_index)) |is_vi| unused: {
                defer is_vi.value.deref(isel);
                const is_ra = try is_vi.value.defReg(isel) orelse break :unused;
                try isel.emit(.csinc(is_ra.w(), .wzr, .wzr, .invert(.ls)));

                const un_op = air.data(air.inst_index).un_op;
                const error_vi = try isel.use(un_op);
                const error_mat = try error_vi.matReg(isel);
                const ptr_ra = try isel.allocIntReg();
                defer isel.freeReg(ptr_ra);
                try isel.emit(.subs(.wzr, error_mat.ra.w(), .{ .register = ptr_ra.w() }));
                try isel.lazy_relocs.append(gpa, .{
                    .symbol = .{ .kind = .const_data, .ty = .anyerror_type },
                    .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                });
                try isel.emit(.ldr(ptr_ra.w(), .{ .base = ptr_ra.x() }));
                try isel.lazy_relocs.append(gpa, .{
                    .symbol = .{ .kind = .const_data, .ty = .anyerror_type },
                    .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                });
                try isel.emit(.adrp(ptr_ra.x(), 0));
                try error_mat.finish(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .runtime_nav_ptr => {
            if (isel.live_values.fetchRemove(air.inst_index)) |ptr_vi| unused: {
                defer ptr_vi.value.deref(isel);
                const ptr_ra = try ptr_vi.value.defReg(isel) orelse break :unused;

                const ty_nav = air.data(air.inst_index).ty_nav;
                if (ZigType.fromInterned(ip.getNav(ty_nav.nav).resolved.?.type).isRuntimeFnOrHasRuntimeBits(zcu)) switch (true) {
                    false => {
                        try isel.nav_relocs.append(gpa, .{
                            .nav = ty_nav.nav,
                            .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                        });
                        try isel.emit(.adr(ptr_ra.x(), 0));
                    },
                    true => {
                        try isel.nav_relocs.append(gpa, .{
                            .nav = ty_nav.nav,
                            .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                        });
                        if (ip.getNav(ty_nav.nav).getExtern(ip)) |_|
                            try isel.emit(.ldr(ptr_ra.x(), .{ .unsigned_offset = .{ .base = ptr_ra.x(), .offset = 0 } }))
                        else
                            try isel.emit(.add(ptr_ra.x(), ptr_ra.x(), .{ .immediate = 0 }));
                        try isel.nav_relocs.append(gpa, .{
                            .nav = ty_nav.nav,
                            .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                        });
                        try isel.emit(.adrp(ptr_ra.x(), 0));
                    },
                } else try isel.movImmediate(ptr_ra.x(), zcu.navAlignment(ty_nav.nav).forward(0xaaaaaaaaaaaaaaaa));
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .c_va_arg => {
            const maybe_arg_vi = isel.live_values.fetchRemove(air.inst_index);
            defer if (maybe_arg_vi) |arg_vi| arg_vi.value.deref(isel);
            const ty_op = air.data(air.inst_index).ty_op;
            const ty = ty_op.ty;
            var param_it: CallAbiIterator = .init;
            const param_vi = try param_it.param(isel, ty);
            defer param_vi.?.deref(isel);
            const passed_vi = switch (param_vi.?.parent(isel)) {
                .unallocated => param_vi.?,
                .stack_slot, .value, .constant => unreachable,
                .address => |address_vi| address_vi,
            };
            const passed_size: u5 = @intCast(passed_vi.alignment(isel).forward(passed_vi.size(isel)));
            const passed_is_vector = passed_vi.isVector(isel);

            const va_list_ptr_vi = try isel.use(ty_op.operand);
            const va_list_ptr_mat = try va_list_ptr_vi.matReg(isel);
            const offs_ra = try isel.allocIntReg();
            defer isel.freeReg(offs_ra);
            const stack_ra = try isel.allocIntReg();
            defer isel.freeReg(stack_ra);

            var part_vis: [2]Value.Index = undefined;
            var arg_part_ras: [2]?Register.Alias = @splat(null);
            const parts_len = parts_len: {
                var parts_len: u2 = 0;
                var part_it = passed_vi.parts(isel);
                while (part_it.next()) |part_vi| : (parts_len += 1) {
                    part_vis[parts_len] = part_vi;
                    const arg_vi = maybe_arg_vi orelse continue;
                    const part_offset, const part_size = part_vi.position(isel);
                    var arg_part_it = arg_vi.value.field(ty, part_offset, part_size);
                    const arg_part_vi = try arg_part_it.only(isel);
                    const first_lock: RegLock = if (parts_len == 1) if (arg_part_ras[0]) |ra0| isel.tryLockReg(ra0) else .empty else .empty;
                    defer first_lock.unlock(isel);
                    arg_part_ras[parts_len] = try arg_part_vi.?.defReg(isel);
                }
                break :parts_len parts_len;
            };

            const done_label = isel.instructions.items.len;
            try isel.emit(.str(stack_ra.x(), .{ .unsigned_offset = .{
                .base = va_list_ptr_mat.ra.x(),
                .offset = 0,
            } }));
            try isel.emit(switch (parts_len) {
                else => unreachable,
                1 => if (arg_part_ras[0]) |arg_part_ra| switch (part_vis[0].size(isel)) {
                    else => unreachable,
                    1 => if (arg_part_ra.isVector()) .ldr(arg_part_ra.b(), .{ .post_index = .{
                        .base = stack_ra.x(),
                        .index = passed_size,
                    } }) else switch (part_vis[0].signedness(isel)) {
                        .signed => .ldrsb(arg_part_ra.w(), .{ .post_index = .{
                            .base = stack_ra.x(),
                            .index = passed_size,
                        } }),
                        .unsigned => .ldrb(arg_part_ra.w(), .{ .post_index = .{
                            .base = stack_ra.x(),
                            .index = passed_size,
                        } }),
                    },
                    2 => if (arg_part_ra.isVector()) .ldr(arg_part_ra.h(), .{ .post_index = .{
                        .base = stack_ra.x(),
                        .index = passed_size,
                    } }) else switch (part_vis[0].signedness(isel)) {
                        .signed => .ldrsh(arg_part_ra.w(), .{ .post_index = .{
                            .base = stack_ra.x(),
                            .index = passed_size,
                        } }),
                        .unsigned => .ldrh(arg_part_ra.w(), .{ .post_index = .{
                            .base = stack_ra.x(),
                            .index = passed_size,
                        } }),
                    },
                    4 => .ldr(if (arg_part_ra.isVector()) arg_part_ra.s() else arg_part_ra.w(), .{ .post_index = .{
                        .base = stack_ra.x(),
                        .index = passed_size,
                    } }),
                    8 => .ldr(if (arg_part_ra.isVector()) arg_part_ra.d() else arg_part_ra.x(), .{ .post_index = .{
                        .base = stack_ra.x(),
                        .index = passed_size,
                    } }),
                    16 => .ldr(arg_part_ra.q(), .{ .post_index = .{
                        .base = stack_ra.x(),
                        .index = passed_size,
                    } }),
                } else .add(stack_ra.x(), stack_ra.x(), .{ .immediate = passed_size }),
                2 => if (arg_part_ras[0] != null or arg_part_ras[1] != null) .ldp(
                    @as(Register.Alias, arg_part_ras[0] orelse .zr).x(),
                    @as(Register.Alias, arg_part_ras[1] orelse .zr).x(),
                    .{ .post_index = .{
                        .base = stack_ra.x(),
                        .index = passed_size,
                    } },
                ) else .add(stack_ra.x(), stack_ra.x(), .{ .immediate = passed_size }),
            });
            try isel.emit(.ldr(stack_ra.x(), .{ .unsigned_offset = .{
                .base = va_list_ptr_mat.ra.x(),
                .offset = 0,
            } }));
            switch (isel.va_list) {
                .other => {},
                .sysv => {
                    const stack_label = isel.instructions.items.len;
                    try isel.emit(.b(
                        @intCast((isel.instructions.items.len + 1 - done_label) << 2),
                    ));
                    switch (parts_len) {
                        else => unreachable,
                        1 => if (arg_part_ras[0]) |arg_part_ra| try isel.emit(switch (part_vis[0].size(isel)) {
                            else => unreachable,
                            1 => if (arg_part_ra.isVector()) .ldr(arg_part_ra.b(), .{ .extended_register = .{
                                .base = stack_ra.x(),
                                .index = offs_ra.w(),
                                .extend = .{ .sxtw = 0 },
                            } }) else switch (part_vis[0].signedness(isel)) {
                                .signed => .ldrsb(arg_part_ra.w(), .{ .extended_register = .{
                                    .base = stack_ra.x(),
                                    .index = offs_ra.w(),
                                    .extend = .{ .sxtw = 0 },
                                } }),
                                .unsigned => .ldrb(arg_part_ra.w(), .{ .extended_register = .{
                                    .base = stack_ra.x(),
                                    .index = offs_ra.w(),
                                    .extend = .{ .sxtw = 0 },
                                } }),
                            },
                            2 => if (arg_part_ra.isVector()) .ldr(arg_part_ra.h(), .{ .extended_register = .{
                                .base = stack_ra.x(),
                                .index = offs_ra.w(),
                                .extend = .{ .sxtw = 0 },
                            } }) else switch (part_vis[0].signedness(isel)) {
                                .signed => .ldrsh(arg_part_ra.w(), .{ .extended_register = .{
                                    .base = stack_ra.x(),
                                    .index = offs_ra.w(),
                                    .extend = .{ .sxtw = 0 },
                                } }),
                                .unsigned => .ldrh(arg_part_ra.w(), .{ .extended_register = .{
                                    .base = stack_ra.x(),
                                    .index = offs_ra.w(),
                                    .extend = .{ .sxtw = 0 },
                                } }),
                            },
                            4 => .ldr(if (arg_part_ra.isVector()) arg_part_ra.s() else arg_part_ra.w(), .{ .extended_register = .{
                                .base = stack_ra.x(),
                                .index = offs_ra.w(),
                                .extend = .{ .sxtw = 0 },
                            } }),
                            8 => .ldr(if (arg_part_ra.isVector()) arg_part_ra.d() else arg_part_ra.x(), .{ .extended_register = .{
                                .base = stack_ra.x(),
                                .index = offs_ra.w(),
                                .extend = .{ .sxtw = 0 },
                            } }),
                            16 => .ldr(arg_part_ra.q(), .{ .extended_register = .{
                                .base = stack_ra.x(),
                                .index = offs_ra.w(),
                                .extend = .{ .sxtw = 0 },
                            } }),
                        }),
                        2 => if (arg_part_ras[0] != null or arg_part_ras[1] != null) {
                            try isel.emit(.ldp(
                                @as(Register.Alias, arg_part_ras[0] orelse .zr).x(),
                                @as(Register.Alias, arg_part_ras[1] orelse .zr).x(),
                                .{ .base = stack_ra.x() },
                            ));
                            try isel.emit(.add(stack_ra.x(), stack_ra.x(), .{ .extended_register = .{
                                .register = offs_ra.w(),
                                .extend = .{ .sxtw = 0 },
                            } }));
                        },
                    }
                    try isel.emit(.ldr(stack_ra.x(), .{ .unsigned_offset = .{
                        .base = va_list_ptr_mat.ra.x(),
                        .offset = if (passed_is_vector) 16 else 8,
                    } }));
                    try isel.emit(.@"b."(
                        .gt,
                        @intCast((isel.instructions.items.len + 1 - stack_label) << 2),
                    ));
                    try isel.emit(.str(stack_ra.w(), .{ .unsigned_offset = .{
                        .base = va_list_ptr_mat.ra.x(),
                        .offset = if (passed_is_vector) 28 else 24,
                    } }));
                    try isel.emit(.adds(stack_ra.w(), offs_ra.w(), .{ .immediate = passed_size }));
                    try isel.emit(.tbz(
                        offs_ra.w(),
                        31,
                        @intCast((isel.instructions.items.len + 1 - stack_label) << 2),
                    ));
                    try isel.emit(.ldr(offs_ra.w(), .{ .unsigned_offset = .{
                        .base = va_list_ptr_mat.ra.x(),
                        .offset = if (passed_is_vector) 28 else 24,
                    } }));
                },
            }
            try va_list_ptr_mat.finish(isel);
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .c_va_copy => {
            if (isel.live_values.fetchRemove(air.inst_index)) |va_list_vi| {
                defer va_list_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                const va_list_ptr_vi = try isel.use(ty_op.operand);
                const va_list_ptr_mat = try va_list_ptr_vi.matReg(isel);
                _ = try va_list_vi.value.load(isel, ty_op.ty, va_list_ptr_mat.ra, .{});
                try va_list_ptr_mat.finish(isel);
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .c_va_end => if (air.next()) |next_air_tag| continue :air_tag next_air_tag,
        .c_va_start => {
            if (isel.live_values.fetchRemove(air.inst_index)) |va_list_vi| {
                defer va_list_vi.value.deref(isel);
                const ty = air.data(air.inst_index).ty;
                switch (isel.va_list) {
                    .other => |va_list| if (try va_list_vi.value.defReg(isel)) |va_list_ra| try isel.emit(.add(
                        va_list_ra.x(),
                        va_list.base.x(),
                        .{ .immediate = @intCast(va_list.offset) },
                    )),
                    .sysv => |va_list| {
                        var vr_offs_it = va_list_vi.value.field(ty, 28, 4);
                        const vr_offs_vi = try vr_offs_it.only(isel);
                        if (try vr_offs_vi.?.defReg(isel)) |vr_offs_ra| try isel.movImmediate(
                            vr_offs_ra.w(),
                            @as(u32, @bitCast(va_list.__vr_offs)),
                        );
                        var gr_offs_it = va_list_vi.value.field(ty, 24, 4);
                        const gr_offs_vi = try gr_offs_it.only(isel);
                        if (try gr_offs_vi.?.defReg(isel)) |gr_offs_ra| try isel.movImmediate(
                            gr_offs_ra.w(),
                            @as(u32, @bitCast(va_list.__gr_offs)),
                        );
                        var vr_top_it = va_list_vi.value.field(ty, 16, 8);
                        const vr_top_vi = try vr_top_it.only(isel);
                        if (try vr_top_vi.?.defReg(isel)) |vr_top_ra| try isel.emit(.add(
                            vr_top_ra.x(),
                            va_list.__vr_top.base.x(),
                            .{ .immediate = @intCast(va_list.__vr_top.offset) },
                        ));
                        var gr_top_it = va_list_vi.value.field(ty, 8, 8);
                        const gr_top_vi = try gr_top_it.only(isel);
                        if (try gr_top_vi.?.defReg(isel)) |gr_top_ra| try isel.emit(.add(
                            gr_top_ra.x(),
                            va_list.__gr_top.base.x(),
                            .{ .immediate = @intCast(va_list.__gr_top.offset) },
                        ));
                        var stack_it = va_list_vi.value.field(ty, 0, 8);
                        const stack_vi = try stack_it.only(isel);
                        if (try stack_vi.?.defReg(isel)) |stack_ra| try isel.emit(.add(
                            stack_ra.x(),
                            va_list.__stack.base.x(),
                            .{ .immediate = @intCast(va_list.__stack.offset) },
                        ));
                    },
                }
            }
            if (air.next()) |next_air_tag| continue :air_tag next_air_tag;
        },
        .work_item_id, .work_group_size, .work_group_id, .spirv_runtime_array_len => unreachable,
    }
    return null;
}

pub fn body(isel: *Select, air_body: []const Air.Inst.Index) codegen.Error!void {
    {
        var live_reg_it = isel.live_registers.iterator();
        while (live_reg_it.next()) |live_reg_entry| switch (live_reg_entry.value.*) {
            _ => {
                const ra = &live_reg_entry.value.get(isel).location_payload.small.register;
                assert(ra.* == live_reg_entry.key);
                ra.* = .zr;
                live_reg_entry.value.* = .free;
            },
            .allocating => live_reg_entry.value.* = .free,
            .free => {},
        };
    }

    var air: AirIterator = .{
        .isel = isel,
        .tag_items = isel.air.instructions.items(.tag),
        .data_items = isel.air.instructions.items(.data),
        .body = air_body,
        .body_index = @intCast(air_body.len),
        .inst_index = undefined,
    };
    var opt_air_tag = air.next();
    while (opt_air_tag) |air_tag| switch (air_tag) {
        .block => {
            const unwrapped_block = isel.air.unwrapBlock(air.inst_index);
            try isel.block(
                air.inst_index,
                unwrapped_block.ty,
                unwrapped_block.body,
            );
            opt_air_tag = air.next();
        },
        .cond_br => {
            const cond_br = isel.air.unwrapCondBr(air.inst_index);

            try isel.body(cond_br.else_body);
            try isel.ensureFreeIntRegs(&.initFill(.free), 1);
            const else_label = isel.instructions.items.len;
            const else_live_registers = isel.live_registers;
            try isel.body(cond_br.then_body);
            try isel.merge(&else_live_registers, .{});
            try isel.ensureFreeIntRegs(&else_live_registers, 1);

            const cond_vi = try isel.use(cond_br.condition);
            const cond_mat = try cond_vi.matReg(isel);
            const disp = (isel.instructions.items.len + 1 - else_label) << 2;
            if (std.math.cast(i16, disp)) |disp16| {
                try isel.emit(.tbz(
                    cond_mat.ra.x(),
                    0,
                    disp16,
                ));
            } else {
                try isel.emit(.b(@intCast(disp)));
                try isel.emit(.tbnz(
                    cond_mat.ra.x(),
                    0,
                    2 << 2,
                ));
            }
            try cond_mat.finish(isel);

            opt_air_tag = air.next();
        },
        .dbg_inline_block => {
            const dbg_block = isel.air.unwrapDbgBlock(air.inst_index);
            try isel.block(air.inst_index, dbg_block.ty, dbg_block.body);
            opt_air_tag = air.next();
        },
        .loop,
        .switch_br,
        .loop_switch_br,
        .@"try",
        .try_cold,
        .try_ptr,
        .try_ptr_cold,
        => {
            try isel.controlFlowInst(air.inst_index, air_tag);
            opt_air_tag = air.next();
        },
        else => opt_air_tag = try isel.leafBody(&air, air_tag),
    };
    assert(air.body_index == 0);
}

fn controlFlowInst(isel: *Select, inst_index: Air.Inst.Index, air_tag: Air.Inst.Tag) codegen.Error!void {
    const zcu = isel.pt.zcu;
    const ip = &zcu.intern_pool;

    switch (air_tag) {
        else => unreachable,
        .loop => {
            const unwrapped_block = isel.air.unwrapBlock(inst_index);
            const loops = isel.loops.values();
            const loop_index = isel.loops.getIndex(inst_index).?;
            const loop = &loops[loop_index];

            tracking_log.debug("{f}", .{
                isel.fmtDom(inst_index, loop.dom, @intCast(isel.blocks.count())),
            });
            tracking_log.debug("{f}", .{isel.fmtLoopLive(inst_index)});
            assert(loop.depth == isel.blocks.count());

            if (false) {
                // loops are dumb...
                for (isel.loop_live.list.items[loop.live..loops[loop_index + 1].live]) |live_inst| {
                    const live_vi = try isel.use(live_inst.toRef());
                    try live_vi.mat(isel);
                }

                // IT'S DOM TIME!!!
                for (isel.blocks.values(), 0..) |*dom_block, dom_index| {
                    if (@as(u1, @truncate(isel.dom.items[
                        loop.dom + dom_index / @bitSizeOf(DomInt)
                    ] >> @truncate(dom_index))) == 0) continue;
                    var live_reg_it = dom_block.live_registers.iterator();
                    while (live_reg_it.next()) |live_reg_entry| switch (live_reg_entry.value.*) {
                        _ => |live_vi| try live_vi.mat(isel),
                        .allocating => unreachable,
                        .free => {},
                    };
                }
            }

            loop.live_registers = isel.live_registers;
            loop.repeat_list = Loop.empty_list;
            try isel.body(unwrapped_block.body);
            try isel.merge(&loop.live_registers, .{ .fill_extra = true });

            var repeat_label = loop.repeat_list;
            assert(repeat_label != Loop.empty_list);
            while (repeat_label != Loop.empty_list) {
                const instruction = &isel.instructions.items[repeat_label];
                const next_repeat_label = instruction.*;
                instruction.* = .b(-@as(i28, @intCast((isel.instructions.items.len - 1 - repeat_label) << 2)));
                repeat_label = @bitCast(next_repeat_label);
            }
        },
        .switch_br, .loop_switch_br => {
            const switch_br = isel.air.unwrapSwitch(inst_index);
            const cond_ty = isel.air.typeOf(switch_br.operand, ip);
            const cond_int_info: std.lang.Type.Int = if (cond_ty.toIntern() == .bool_type)
                .{ .signedness = .unsigned, .bits = 1 }
            else if (cond_ty.isAbiInt(zcu))
                cond_ty.intInfo(zcu)
            else
                return isel.fail("bad switch cond {f}", .{isel.fmtType(cond_ty)});

            const opt_loop = if (air_tag == .loop_switch_br) loop: {
                const loop = &isel.loops.values()[isel.loops.getIndex(inst_index).?];
                const cond_size = cond_ty.abiSize(zcu);
                const cond_align = cond_ty.abiAlignment(zcu);
                const slot_offset = cond_align.forward(isel.stack_size);
                isel.stack_size = @intCast(slot_offset + cond_size);
                loop.dispatch_slot_offset = @intCast(slot_offset);
                loop.live_registers = isel.live_registers;
                loop.repeat_list = Loop.empty_list;
                break :loop loop;
            } else null;

            var final_case = true;
            if (switch_br.else_body_len > 0) {
                var cases_it = switch_br.iterateCases();
                while (cases_it.next()) |_| {}
                try isel.body(cases_it.elseBody());
                assert(final_case);
                final_case = false;
            }
            const zero_reg: Register = switch (cond_int_info.bits) {
                else => unreachable,
                1...32 => .wzr,
                33...64 => .xzr,
            };
            var cond_mat: ?Value.Materialize = null;
            var cond_ra: ?Register.Alias = null;
            var cond_reg: Register = undefined;
            var cases_it = switch_br.iterateCases();
            while (cases_it.next()) |case| {
                if (!final_case) try isel.ensureFreeIntRegs(&.initFill(.free), 3);
                const next_label = isel.instructions.items.len;
                const next_live_registers = isel.live_registers;
                try isel.body(case.body);
                if (final_case) {
                    final_case = false;
                    continue;
                }
                try isel.merge(&next_live_registers, .{});
                try isel.ensureFreeIntRegs(&next_live_registers, 3);
                if (cond_ra == null) {
                    if (opt_loop != null) {
                        cond_ra = try isel.allocIntReg();
                    } else {
                        var cond_vi = try isel.use(switch_br.operand);
                        cond_mat = try cond_vi.matReg(isel);
                        cond_ra = cond_mat.?.ra;
                    }
                    cond_reg = switch (cond_int_info.bits) {
                        else => unreachable,
                        1...32 => cond_ra.?.w(),
                        33...64 => cond_ra.?.x(),
                    };
                }
                if (case.ranges.len == 0 and case.items.len == 1 and Constant.fromInterned(
                    case.items[0].toInterned().?,
                ).compareHetero(.eq, .zero_comptime_int, zcu)) {
                    try isel.emit(.cbnz(
                        cond_reg,
                        @intCast((isel.instructions.items.len + 1 - next_label) << 2),
                    ));
                    continue;
                }
                try isel.emit(.@"b."(
                    .invert(switch (case.ranges.len) {
                        0 => .eq,
                        else => .ls,
                    }),
                    @intCast((isel.instructions.items.len + 1 - next_label) << 2),
                ));
                var case_range_index = case.ranges.len;
                while (case_range_index > 0) {
                    case_range_index -= 1;

                    const low_val: Constant = .fromInterned(case.ranges[case_range_index][0].toInterned().?);
                    var low_bigint_space: Constant.BigIntSpace = undefined;
                    const low_bigint = low_val.toBigInt(&low_bigint_space, zcu);
                    const low_int: i64 = if (low_bigint.positive) @bitCast(
                        low_bigint.toInt(u64) catch
                            return isel.fail("too big case range start: {f}", .{isel.fmtConstant(low_val)}),
                    ) else low_bigint.toInt(i64) catch
                        return isel.fail("too big case range start: {f}", .{isel.fmtConstant(low_val)});

                    const high_val: Constant = .fromInterned(case.ranges[case_range_index][1].toInterned().?);
                    var high_bigint_space: Constant.BigIntSpace = undefined;
                    const high_bigint = high_val.toBigInt(&high_bigint_space, zcu);
                    const high_int: i64 = if (high_bigint.positive) @bitCast(
                        high_bigint.toInt(u64) catch
                            return isel.fail("too big case range end: {f}", .{isel.fmtConstant(high_val)}),
                    ) else high_bigint.toInt(i64) catch
                        return isel.fail("too big case range end: {f}", .{isel.fmtConstant(high_val)});

                    const adjusted_ra = switch (low_int) {
                        0 => cond_ra.?,
                        else => try isel.allocIntReg(),
                    };
                    defer if (adjusted_ra != cond_ra.?) isel.freeReg(adjusted_ra);
                    const adjusted_reg = switch (cond_int_info.bits) {
                        else => unreachable,
                        1...32 => adjusted_ra.w(),
                        33...64 => adjusted_ra.x(),
                    };
                    const delta_int = high_int -% low_int;
                    if (case_range_index | case.items.len > 0) {
                        if (std.math.cast(u5, delta_int)) |pos_imm| try isel.emit(.ccmp(
                            adjusted_reg,
                            .{ .immediate = pos_imm },
                            .{ .n = false, .z = true, .c = false, .v = false },
                            if (case_range_index > 0) .hi else .ne,
                        )) else if (std.math.cast(u5, -delta_int)) |neg_imm| try isel.emit(.ccmn(
                            adjusted_reg,
                            .{ .immediate = neg_imm },
                            .{ .n = false, .z = true, .c = false, .v = false },
                            if (case_range_index > 0) .hi else .ne,
                        )) else {
                            const imm_ra = try isel.allocIntReg();
                            defer isel.freeReg(imm_ra);
                            const imm_reg = switch (cond_int_info.bits) {
                                else => unreachable,
                                1...32 => imm_ra.w(),
                                33...64 => imm_ra.x(),
                            };
                            try isel.emit(.ccmp(
                                adjusted_reg,
                                .{ .register = imm_reg },
                                .{ .n = false, .z = true, .c = false, .v = false },
                                if (case_range_index > 0) .hi else .ne,
                            ));
                            try isel.movImmediate(imm_reg, switch (cond_int_info.bits) {
                                else => unreachable,
                                1...32 => @as(u32, @truncate(@as(u64, @bitCast(delta_int)))),
                                33...64 => @bitCast(delta_int),
                            });
                        }
                    } else {
                        if (std.math.cast(u12, delta_int)) |pos_imm| try isel.emit(.subs(
                            zero_reg,
                            adjusted_reg,
                            .{ .immediate = pos_imm },
                        )) else if (std.math.cast(u12, -delta_int)) |neg_imm| try isel.emit(.adds(
                            zero_reg,
                            adjusted_reg,
                            .{ .immediate = neg_imm },
                        )) else if (if (@as(i12, @truncate(delta_int)) == 0)
                            std.math.cast(u12, delta_int >> 12)
                        else
                            null) |pos_imm_lsr_12| try isel.emit(.subs(
                            zero_reg,
                            adjusted_reg,
                            .{ .shifted_immediate = .{ .immediate = pos_imm_lsr_12, .lsl = .@"12" } },
                        )) else if (if (@as(i12, @truncate(-delta_int)) == 0)
                            std.math.cast(u12, -delta_int >> 12)
                        else
                            null) |neg_imm_lsr_12| try isel.emit(.adds(
                            zero_reg,
                            adjusted_reg,
                            .{ .shifted_immediate = .{ .immediate = neg_imm_lsr_12, .lsl = .@"12" } },
                        )) else {
                            const imm_ra = try isel.allocIntReg();
                            defer isel.freeReg(imm_ra);
                            const imm_reg = switch (cond_int_info.bits) {
                                else => unreachable,
                                1...32 => imm_ra.w(),
                                33...64 => imm_ra.x(),
                            };
                            try isel.emit(.subs(zero_reg, adjusted_reg, .{ .register = imm_reg }));
                            try isel.movImmediate(imm_reg, switch (cond_int_info.bits) {
                                else => unreachable,
                                1...32 => @as(u32, @truncate(@as(u64, @bitCast(delta_int)))),
                                33...64 => @bitCast(delta_int),
                            });
                        }
                    }

                    switch (low_int) {
                        0 => {},
                        else => {
                            if (std.math.cast(u12, low_int)) |pos_imm| try isel.emit(.sub(
                                adjusted_reg,
                                cond_reg,
                                .{ .immediate = pos_imm },
                            )) else if (std.math.cast(u12, -low_int)) |neg_imm| try isel.emit(.add(
                                adjusted_reg,
                                cond_reg,
                                .{ .immediate = neg_imm },
                            )) else if (if (@as(i12, @truncate(low_int)) == 0)
                                std.math.cast(u12, low_int >> 12)
                            else
                                null) |pos_imm_lsr_12| try isel.emit(.sub(
                                adjusted_reg,
                                cond_reg,
                                .{ .shifted_immediate = .{ .immediate = pos_imm_lsr_12, .lsl = .@"12" } },
                            )) else if (if (@as(i12, @truncate(-low_int)) == 0)
                                std.math.cast(u12, -low_int >> 12)
                            else
                                null) |neg_imm_lsr_12| try isel.emit(.add(
                                adjusted_reg,
                                cond_reg,
                                .{ .shifted_immediate = .{ .immediate = neg_imm_lsr_12, .lsl = .@"12" } },
                            )) else {
                                const imm_ra = try isel.allocIntReg();
                                defer isel.freeReg(imm_ra);
                                const imm_reg = switch (cond_int_info.bits) {
                                    else => unreachable,
                                    1...32 => imm_ra.w(),
                                    33...64 => imm_ra.x(),
                                };
                                try isel.emit(.sub(adjusted_reg, cond_reg, .{ .register = imm_reg }));
                                try isel.movImmediate(imm_reg, switch (cond_int_info.bits) {
                                    else => unreachable,
                                    1...32 => @as(u32, @truncate(@as(u64, @bitCast(low_int)))),
                                    33...64 => @bitCast(low_int),
                                });
                            }
                        },
                    }
                }
                var case_item_index = case.items.len;
                while (case_item_index > 0) {
                    case_item_index -= 1;

                    const item_val: Constant = .fromInterned(case.items[case_item_index].toInterned().?);
                    var item_bigint_space: Constant.BigIntSpace = undefined;
                    const item_bigint = item_val.toBigInt(&item_bigint_space, zcu);
                    const item_int: i64 = if (item_bigint.positive) @bitCast(
                        item_bigint.toInt(u64) catch
                            return isel.fail("too big case item: {f}", .{isel.fmtConstant(item_val)}),
                    ) else item_bigint.toInt(i64) catch
                        return isel.fail("too big case item: {f}", .{isel.fmtConstant(item_val)});

                    if (case_item_index > 0) {
                        if (std.math.cast(u5, item_int)) |pos_imm| try isel.emit(.ccmp(
                            cond_reg,
                            .{ .immediate = pos_imm },
                            .{ .n = false, .z = true, .c = false, .v = false },
                            .ne,
                        )) else if (std.math.cast(u5, -item_int)) |neg_imm| try isel.emit(.ccmn(
                            cond_reg,
                            .{ .immediate = neg_imm },
                            .{ .n = false, .z = true, .c = false, .v = false },
                            .ne,
                        )) else {
                            const imm_ra = try isel.allocIntReg();
                            defer isel.freeReg(imm_ra);
                            const imm_reg = switch (cond_int_info.bits) {
                                else => unreachable,
                                1...32 => imm_ra.w(),
                                33...64 => imm_ra.x(),
                            };
                            try isel.emit(.ccmp(
                                cond_reg,
                                .{ .register = imm_reg },
                                .{ .n = false, .z = true, .c = false, .v = false },
                                .ne,
                            ));
                            try isel.movImmediate(imm_reg, switch (cond_int_info.bits) {
                                else => unreachable,
                                1...32 => @as(u32, @truncate(@as(u64, @bitCast(item_int)))),
                                33...64 => @bitCast(item_int),
                            });
                        }
                    } else {
                        if (std.math.cast(u12, item_int)) |pos_imm| try isel.emit(.subs(
                            zero_reg,
                            cond_reg,
                            .{ .immediate = pos_imm },
                        )) else if (std.math.cast(u12, -item_int)) |neg_imm| try isel.emit(.adds(
                            zero_reg,
                            cond_reg,
                            .{ .immediate = neg_imm },
                        )) else if (if (@as(i12, @truncate(item_int)) == 0)
                            std.math.cast(u12, item_int >> 12)
                        else
                            null) |pos_imm_lsr_12| try isel.emit(.subs(
                            zero_reg,
                            cond_reg,
                            .{ .shifted_immediate = .{ .immediate = pos_imm_lsr_12, .lsl = .@"12" } },
                        )) else if (if (@as(i12, @truncate(-item_int)) == 0)
                            std.math.cast(u12, -item_int >> 12)
                        else
                            null) |neg_imm_lsr_12| try isel.emit(.adds(
                            zero_reg,
                            cond_reg,
                            .{ .shifted_immediate = .{ .immediate = neg_imm_lsr_12, .lsl = .@"12" } },
                        )) else {
                            const imm_ra = try isel.allocIntReg();
                            defer isel.freeReg(imm_ra);
                            const imm_reg = switch (cond_int_info.bits) {
                                else => unreachable,
                                1...32 => imm_ra.w(),
                                33...64 => imm_ra.x(),
                            };
                            try isel.emit(.subs(zero_reg, cond_reg, .{ .register = imm_reg }));
                            try isel.movImmediate(imm_reg, switch (cond_int_info.bits) {
                                else => unreachable,
                                1...32 => @as(u32, @truncate(@as(u64, @bitCast(item_int)))),
                                33...64 => @bitCast(item_int),
                            });
                        }
                    }
                }
            }
            if (opt_loop) |loop| {
                const cond_size = cond_ty.abiSize(zcu);
                if (cond_ra) |ra| {
                    try isel.loadReg(
                        ra,
                        cond_size,
                        cond_int_info.signedness,
                        .sp,
                        loop.dispatch_slot_offset,
                    );
                    isel.freeReg(ra);
                }
                try isel.merge(&loop.live_registers, .{ .fill_extra = true });

                var repeat_label = loop.repeat_list;
                while (repeat_label != Loop.empty_list) {
                    const instruction = &isel.instructions.items[repeat_label];
                    const next_repeat_label = instruction.*;
                    instruction.* = .b(-@as(i28, @intCast((isel.instructions.items.len - 1 - repeat_label) << 2)));
                    repeat_label = @bitCast(next_repeat_label);
                }

                if (cond_size > 0) {
                    var cond_vi = try isel.use(switch_br.operand);
                    const init_mat = try cond_vi.matReg(isel);
                    try isel.storeReg(
                        init_mat.ra,
                        cond_size,
                        .sp,
                        loop.dispatch_slot_offset,
                    );
                    try init_mat.finish(isel);
                }
            } else {
                if (cond_mat) |mat| {
                    try mat.finish(isel);
                }
            }
        },
        .@"try", .try_cold => {
            const unwrapped_try = isel.air.unwrapTry(inst_index);
            const error_union_ty = isel.air.typeOf(unwrapped_try.error_union, &zcu.intern_pool);
            const error_union_info = ip.indexToKey(error_union_ty.toIntern()).error_union_type;
            const payload_ty: ZigType = .fromInterned(error_union_info.payload_type);

            const error_union_vi = try isel.use(unwrapped_try.error_union);
            if (isel.live_values.fetchRemove(inst_index)) |payload_vi| {
                defer payload_vi.value.deref(isel);

                var payload_part_it = error_union_vi.field(
                    error_union_ty,
                    codegen.errUnionPayloadOffset(payload_ty, zcu),
                    payload_vi.value.size(isel),
                );
                try payload_part_it.copyTo(isel, payload_ty, payload_vi.value);
            }

            try isel.ensureFreeIntRegs(&.initFill(.free), 1);
            const cont_label = isel.instructions.items.len;
            const cont_live_registers = isel.live_registers;
            try isel.body(unwrapped_try.else_body);
            try isel.merge(&cont_live_registers, .{});
            try isel.ensureFreeIntRegs(&cont_live_registers, 1);

            var error_set_part_it = error_union_vi.field(
                error_union_ty,
                codegen.errUnionErrorOffset(payload_ty, zcu),
                ZigType.fromInterned(error_union_info.error_set_type).abiSize(zcu),
            );
            const error_set_part_vi = try error_set_part_it.only(isel);
            const error_set_part_mat = try error_set_part_vi.?.matReg(isel);
            try isel.emit(.cbz(
                error_set_part_mat.ra.w(),
                @intCast((isel.instructions.items.len + 1 - cont_label) << 2),
            ));
            try error_set_part_mat.finish(isel);
        },
        .try_ptr, .try_ptr_cold => {
            const unwrapped_try = isel.air.unwrapTryPtr(inst_index);
            const error_union_ty = isel.air.typeOf(unwrapped_try.error_union_ptr, ip).childType(zcu);
            const error_union_info = ip.indexToKey(error_union_ty.toIntern()).error_union_type;
            const payload_ty: ZigType = .fromInterned(error_union_info.payload_type);

            const error_union_ptr_vi = try isel.use(unwrapped_try.error_union_ptr);
            const error_union_ptr_mat = try error_union_ptr_vi.matReg(isel);
            if (isel.live_values.fetchRemove(inst_index)) |payload_ptr_vi| unused: {
                defer payload_ptr_vi.value.deref(isel);
                switch (codegen.errUnionPayloadOffset(unwrapped_try.error_union_payload_ptr_ty.childType(zcu), zcu)) {
                    0 => try payload_ptr_vi.value.move(isel, unwrapped_try.error_union_ptr),
                    else => |payload_offset| {
                        const payload_ptr_ra = try payload_ptr_vi.value.defReg(isel) orelse break :unused;
                        const lo12: u12 = @truncate(payload_offset >> 0);
                        const hi12: u12 = @intCast(payload_offset >> 12);
                        if (hi12 > 0) try isel.emit(.add(
                            payload_ptr_ra.x(),
                            if (lo12 > 0) payload_ptr_ra.x() else error_union_ptr_mat.ra.x(),
                            .{ .shifted_immediate = .{ .immediate = hi12, .lsl = .@"12" } },
                        ));
                        if (lo12 > 0) try isel.emit(.add(payload_ptr_ra.x(), error_union_ptr_mat.ra.x(), .{ .immediate = lo12 }));
                    },
                }
            }

            try isel.ensureFreeIntRegs(&.initFill(.free), 1);
            const cont_label = isel.instructions.items.len;
            const cont_live_registers = isel.live_registers;
            try isel.body(unwrapped_try.else_body);
            try isel.merge(&cont_live_registers, .{});
            try isel.ensureFreeIntRegs(&cont_live_registers, 1);

            const error_set_ra = try isel.allocIntReg();
            try isel.emit(.cbz(
                error_set_ra.w(),
                @intCast((isel.instructions.items.len + 1 - cont_label) << 2),
            ));
            try isel.loadReg(
                error_set_ra,
                ZigType.fromInterned(error_union_info.error_set_type).abiSize(zcu),
                .unsigned,
                error_union_ptr_mat.ra,
                codegen.errUnionErrorOffset(payload_ty, zcu),
            );
            isel.freeReg(error_set_ra);
            try error_union_ptr_mat.finish(isel);
        },
    }
}

pub fn verify(isel: *Select, check_values: bool) void {
    if (!std.debug.runtime_safety) return;
    assert(isel.blocks.count() == 1 and isel.blocks.keys()[0] == Select.Block.main);
    assert(isel.active_loops.items.len == 0);
    assert(isel.dom_start == 0 and isel.dom_len == 0);
    var live_reg_it = isel.live_registers.iterator();
    while (live_reg_it.next()) |live_reg_entry| switch (live_reg_entry.value.*) {
        _ => {
            isel.dumpValues(.all);
            unreachable;
        },
        .allocating, .free => {},
    };
    if (check_values) for (isel.values.items) |value| if (value.refs != 0) {
        isel.dumpValues(.only_referenced);
        unreachable;
    };
}

///           Stack Frame Layout
/// +-+-----------------------------------+
/// |R| allocated stack                   |
/// +-+-----------------------------------+
/// |S| caller frame record               |   +---------------+
/// +-+-----------------------------------+ <-| entry/exit FP |
/// |R| caller frame                      |   +---------------+
/// +-+-----------------------------------+
/// |R| variable incoming stack arguments |   +---------------+
/// +-+-----------------------------------+ <-| __stack       |
/// |S| named incoming stack arguments    |   +---------------+
/// +-+-----------------------------------+ <-| entry/exit SP |
/// |S| incoming gr arguments             |   | __gr_top      |
/// +-+-----------------------------------+   +---------------+
/// |S| alignment gap                     |
/// +-+-----------------------------------+
/// |S| frame record                      |   +----------+
/// +-+-----------------------------------+ <-| FP       |
/// |S| incoming vr arguments             |   | __vr_top |
/// +-+-----------------------------------+   +----------+
/// |L| alignment gap                     |
/// +-+-----------------------------------+
/// |L| callee saved vr area              |
/// +-+-----------------------------------+
/// |L| callee saved gr area              |   +----------------------+
/// +-+-----------------------------------+ <-| prologue/epilogue SP |
/// |R| realignment gap                   |   +----------------------+
/// +-+-----------------------------------+
/// |L| locals                            |
/// +-+-----------------------------------+
/// |S| outgoing stack arguments          |   +----+
/// +-+-----------------------------------+ <-| SP |
/// |R| unallocated stack                 |   +----+
/// +-+-----------------------------------+
/// [S] Size computed by `analyze`, can be used by the body.
/// [L] Size computed by `layout`, can be used by the prologue/epilogue.
/// [R] Size unknown until runtime, can vary from one call to the next.
///
/// Constraints that led to this layout:
///  * FP to __stack/__gr_top/__vr_top must only pass through [S]
///  * SP to outgoing stack arguments/locals must only pass through [S]
///  * entry/exit SP to prologue/epilogue SP must only pass through [S/L]
///  * all save areas must be at a positive offset from prologue/epilogue SP
///  * the entry/exit SP to prologue/epilogue SP distance must
///   - be a multiple of 16 due to hardware restrictions on the value of SP
///   - conform to the limit from the first matching condition in the
///     following list due to instruction encoding limitations
///    1. callee saved gr count >= 2: multiple of 8 of at most 504 bytes
///    2. callee saved vr count >= 2: multiple of 8 of at most 504 bytes
///    3. callee saved gr count >= 1: at most 255 bytes
///    4. callee saved vr count >= 1: at most 255 bytes
///    5. variable incoming vr argument count >= 2: multiple of 16 of at most 1008 bytes
///    6. variable incoming vr argument count >= 1: at most 255 bytes
///    7. have frame record: multiple of 8 of at most 504 bytes
pub fn layout(
    isel: *Select,
    incoming: CallAbiIterator,
    is_sysv_var_args: bool,
    saved_gra_len: u7,
    saved_vra_len: u7,
    mod: *const Module,
) !usize {
    const zcu = isel.pt.zcu;
    const ip = &zcu.intern_pool;
    const nav = ip.getNav(isel.nav_index);
    wip_mir_log.debug("{f}<body>:\n", .{nav.fqn.fmt(ip)});

    const stack_size: u24 = @intCast(InternPool.Alignment.@"16".forward(isel.stack_size));

    var saves_buf: [10 + 8 + 8 + 2 + 8]struct {
        class: enum { integer, vector },
        needs_restore: bool,
        register: Register,
        offset: u10,
        size: u5,
    } = undefined;
    const saves, const saves_size, const frame_record_offset = saves: {
        var saves_len: usize = 0;
        var saves_size: u10 = 0;
        var save_ra: Register.Alias = undefined;

        // callee saved gr area
        save_ra = .r19;
        while (save_ra != .r29) : (save_ra = @fromBackingInt(@intCast(@backingInt(save_ra) + 1))) {
            if (!isel.saved_registers.contains(save_ra)) continue;
            saves_size = std.mem.alignForward(u10, saves_size, 8);
            saves_buf[saves_len] = .{
                .class = .integer,
                .needs_restore = true,
                .register = save_ra.x(),
                .offset = saves_size,
                .size = 8,
            };
            saves_len += 1;
            saves_size += 8;
        }
        var deferred_gr = if (saves_size == 8 or (saves_size % 16 != 0 and saved_gra_len % 2 != 0)) gr: {
            saves_len -= 1;
            saves_size -= 8;
            break :gr saves_buf[saves_len].register;
        } else null;
        defer assert(deferred_gr == null);

        // callee saved vr area
        save_ra = .v8;
        while (save_ra != .v16) : (save_ra = @fromBackingInt(@intCast(@backingInt(save_ra) + 1))) {
            if (!isel.saved_registers.contains(save_ra)) continue;
            saves_size = std.mem.alignForward(u10, saves_size, 8);
            saves_buf[saves_len] = .{
                .class = .vector,
                .needs_restore = true,
                .register = save_ra.d(),
                .offset = saves_size,
                .size = 8,
            };
            saves_len += 1;
            saves_size += 8;
        }
        if (deferred_gr != null and saved_gra_len % 2 == 0) {
            saves_size = std.mem.alignForward(u10, saves_size, 8);
            saves_buf[saves_len] = .{
                .class = .integer,
                .needs_restore = true,
                .register = deferred_gr.?,
                .offset = saves_size,
                .size = 8,
            };
            saves_len += 1;
            saves_size += 8;
            deferred_gr = null;
        }
        if (saves_size % 16 != 0 and saved_vra_len % 2 != 0) {
            const prev_save = &saves_buf[saves_len - 1];
            switch (prev_save.class) {
                .integer => {},
                .vector => {
                    prev_save.register = prev_save.register.alias.q();
                    prev_save.size = 16;
                    saves_size += 8;
                },
            }
        }

        // incoming vr arguments
        save_ra = if (mod.strip) incoming.nsrn else CallAbiIterator.nsrn_start;
        while (save_ra != if (is_sysv_var_args) CallAbiIterator.nsrn_end else incoming.nsrn) : (save_ra = @fromBackingInt(@intCast(@backingInt(save_ra) + 1))) {
            saves_size = std.mem.alignForward(u10, saves_size, 16);
            saves_buf[saves_len] = .{
                .class = .vector,
                .needs_restore = false,
                .register = save_ra.q(),
                .offset = saves_size,
                .size = 16,
            };
            saves_len += 1;
            saves_size += 16;
        }

        // frame record
        saves_size = std.mem.alignForward(u10, saves_size, 16);
        const frame_record_offset = saves_size;
        saves_buf[saves_len] = .{
            .class = .integer,
            .needs_restore = true,
            .register = .fp,
            .offset = saves_size,
            .size = 8,
        };
        saves_len += 1;
        saves_size += 8;

        saves_size = std.mem.alignForward(u10, saves_size, 8);
        saves_buf[saves_len] = .{
            .class = .integer,
            .needs_restore = true,
            .register = .lr,
            .offset = saves_size,
            .size = 8,
        };
        saves_len += 1;
        saves_size += 8;

        // incoming gr arguments
        if (deferred_gr) |gr| {
            saves_size = std.mem.alignForward(u10, saves_size, 8);
            saves_buf[saves_len] = .{
                .class = .integer,
                .needs_restore = true,
                .register = gr,
                .offset = saves_size,
                .size = 8,
            };
            saves_len += 1;
            saves_size += 8;
            deferred_gr = null;
        } else switch (@as(u1, @truncate(saved_gra_len))) {
            0 => {},
            1 => saves_size += 8,
        }
        save_ra = if (mod.strip) incoming.ngrn else CallAbiIterator.ngrn_start;
        while (save_ra != if (is_sysv_var_args) CallAbiIterator.ngrn_end else incoming.ngrn) : (save_ra = @fromBackingInt(@intCast(@backingInt(save_ra) + 1))) {
            saves_size = std.mem.alignForward(u10, saves_size, 8);
            saves_buf[saves_len] = .{
                .class = .integer,
                .needs_restore = false,
                .register = save_ra.x(),
                .offset = saves_size,
                .size = 8,
            };
            saves_len += 1;
            saves_size += 8;
        }

        assert(InternPool.Alignment.@"16".check(saves_size));
        break :saves .{ saves_buf[0..saves_len], saves_size, frame_record_offset };
    };

    {
        wip_mir_log.debug("{f}<prologue>:", .{nav.fqn.fmt(ip)});

        for (0..mod.patchable_function_entry) |_| {
            try isel.emit(.nop());
        }

        var save_index: usize = 0;
        while (save_index < saves.len) if (save_index + 2 <= saves.len and
            saves[save_index + 0].class == saves[save_index + 1].class and
            saves[save_index + 0].size == saves[save_index + 1].size and
            saves[save_index + 0].offset + saves[save_index + 0].size == saves[save_index + 1].offset)
        {
            try isel.emit(.stp(
                saves[save_index + 0].register,
                saves[save_index + 1].register,
                switch (saves[save_index + 0].offset) {
                    0 => .{ .pre_index = .{
                        .base = .sp,
                        .index = @intCast(-@as(i11, saves_size)),
                    } },
                    else => |offset| .{ .signed_offset = .{
                        .base = .sp,
                        .offset = @intCast(offset),
                    } },
                },
            ));
            save_index += 2;
        } else {
            try isel.emit(.str(
                saves[save_index].register,
                switch (saves[save_index].offset) {
                    0 => .{ .pre_index = .{
                        .base = .sp,
                        .index = @intCast(-@as(i11, saves_size)),
                    } },
                    else => |offset| .{ .unsigned_offset = .{
                        .base = .sp,
                        .offset = @intCast(offset),
                    } },
                },
            ));
            save_index += 1;
        };

        try isel.emit(.add(.fp, .sp, .{ .immediate = frame_record_offset }));
        const scratch_reg: Register = if (isel.stack_align == .@"16")
            .sp
        else if (stack_size == 0 and frame_record_offset == 0)
            .fp
        else
            .ip0;
        const stack_size_lo: u12 = @truncate(stack_size >> 0);
        const stack_size_hi: u12 = @truncate(stack_size >> 12);
        if (mod.stack_check) {
            if (stack_size_hi > 2) {
                try isel.movImmediate(.ip1, stack_size_hi);
                const loop_label = isel.instructions.items.len;
                try isel.emit(.sub(.sp, .sp, .{
                    .shifted_immediate = .{ .immediate = 1, .lsl = .@"12" },
                }));
                try isel.emit(.sub(.ip1, .ip1, .{ .immediate = 1 }));
                try isel.emit(.ldr(.xzr, .{ .base = .sp }));
                try isel.emit(.cbnz(.ip1, -@as(i21, @intCast(
                    (isel.instructions.items.len - loop_label) << 2,
                ))));
            } else for (0..stack_size_hi) |_| {
                try isel.emit(.sub(.sp, .sp, .{
                    .shifted_immediate = .{ .immediate = 1, .lsl = .@"12" },
                }));
                try isel.emit(.ldr(.xzr, .{ .base = .sp }));
            }
            if (stack_size_lo > 0) try isel.emit(.sub(
                scratch_reg,
                .sp,
                .{ .immediate = stack_size_lo },
            )) else if (scratch_reg.alias == Register.Alias.ip0)
                try isel.emit(.add(scratch_reg, .sp, .{ .immediate = 0 }));
        } else {
            if (stack_size_hi > 0) try isel.emit(.sub(scratch_reg, .sp, .{
                .shifted_immediate = .{ .immediate = stack_size_hi, .lsl = .@"12" },
            }));
            if (stack_size_lo > 0) try isel.emit(.sub(
                scratch_reg,
                if (stack_size_hi > 0) scratch_reg else .sp,
                .{ .immediate = stack_size_lo },
            )) else if (scratch_reg.alias == Register.Alias.ip0 and stack_size_hi == 0)
                try isel.emit(.add(scratch_reg, .sp, .{ .immediate = 0 }));
        }
        if (isel.stack_align != .@"16") try isel.emit(.@"and"(.sp, scratch_reg, .{ .immediate = .{
            .N = .doubleword,
            .immr = -%isel.stack_align.toLog2Units(),
            .imms = ~isel.stack_align.toLog2Units(),
        } }));
        wip_mir_log.debug("", .{});
    }

    const epilogue = isel.instructions.items.len;
    if (isel.returns) {
        try isel.emit(.ret(.lr));
        var save_index: usize = 0;
        var first_offset: ?u10 = null;
        while (save_index < saves.len) {
            if (save_index + 2 <= saves.len and saves[save_index + 1].needs_restore and
                saves[save_index + 0].class == saves[save_index + 1].class and
                saves[save_index + 0].size == saves[save_index + 1].size and
                saves[save_index + 0].offset + saves[save_index + 0].size == saves[save_index + 1].offset)
            {
                try isel.emit(.ldp(
                    saves[save_index + 0].register,
                    saves[save_index + 1].register,
                    if (first_offset) |offset| .{ .signed_offset = .{
                        .base = .sp,
                        .offset = @intCast(saves[save_index + 0].offset - offset),
                    } } else form: {
                        first_offset = @intCast(saves[save_index + 0].offset);
                        break :form .{ .post_index = .{
                            .base = .sp,
                            .index = @intCast(saves_size - first_offset.?),
                        } };
                    },
                ));
                save_index += 2;
            } else if (saves[save_index].needs_restore) {
                try isel.emit(.ldr(
                    saves[save_index].register,
                    if (first_offset) |offset| .{ .unsigned_offset = .{
                        .base = .sp,
                        .offset = saves[save_index + 0].offset - offset,
                    } } else form: {
                        const offset = saves[save_index + 0].offset;
                        first_offset = offset;
                        break :form .{ .post_index = .{
                            .base = .sp,
                            .index = @intCast(saves_size - offset),
                        } };
                    },
                ));
                save_index += 1;
            } else save_index += 1;
        }
        const offset = stack_size + first_offset.?;
        const offset_lo: u12 = @truncate(offset >> 0);
        const offset_hi: u12 = @truncate(offset >> 12);
        if (isel.stack_align != .@"16" or (offset_lo > 0 and offset_hi > 0)) {
            const fp_offset = @as(i11, first_offset.?) - frame_record_offset;
            try isel.emit(if (fp_offset >= 0)
                .add(.sp, .fp, .{ .immediate = @intCast(fp_offset) })
            else
                .sub(.sp, .fp, .{ .immediate = @intCast(-fp_offset) }));
        } else {
            if (offset_hi > 0) try isel.emit(.add(.sp, .sp, .{
                .shifted_immediate = .{ .immediate = offset_hi, .lsl = .@"12" },
            }));
            if (offset_lo > 0) try isel.emit(.add(.sp, .sp, .{
                .immediate = offset_lo,
            }));
        }
        wip_mir_log.debug("{f}<epilogue>:\n", .{nav.fqn.fmt(ip)});
    }
    return epilogue;
}

fn fmtDom(isel: *Select, inst: Air.Inst.Index, start: u32, len: u32) struct {
    isel: *Select,
    inst: Air.Inst.Index,
    start: u32,
    len: u32,
    pub fn format(data: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("%{d} -> {{", .{@backingInt(data.inst)});
        var first = true;
        for (data.isel.blocks.keys()[0..data.len], 0..) |block_inst_index, dom_index| {
            if (@as(u1, @truncate(data.isel.dom.items[
                data.start + dom_index / @bitSizeOf(DomInt)
            ] >> @truncate(dom_index))) == 0) continue;
            if (first) {
                first = false;
            } else {
                try writer.writeByte(',');
            }
            switch (block_inst_index) {
                Block.main => try writer.writeAll(" %main"),
                else => try writer.print(" %{d}", .{@backingInt(block_inst_index)}),
            }
        }
        if (!first) try writer.writeByte(' ');
        try writer.writeByte('}');
    }
} {
    return .{ .isel = isel, .inst = inst, .start = start, .len = len };
}

fn fmtLoopLive(isel: *Select, loop_inst: Air.Inst.Index) struct {
    isel: *Select,
    inst: Air.Inst.Index,
    pub fn format(data: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const loops = data.isel.loops.values();
        const loop_index = data.isel.loops.getIndex(data.inst).?;
        const live_insts =
            data.isel.loop_live.list.items[loops[loop_index].live..loops[loop_index + 1].live];

        try writer.print("%{d} <- {{", .{@backingInt(data.inst)});
        var first = true;
        for (live_insts) |live_inst| {
            if (first) {
                first = false;
            } else {
                try writer.writeByte(',');
            }
            try writer.print(" %{d}", .{@backingInt(live_inst)});
        }
        if (!first) try writer.writeByte(' ');
        try writer.writeByte('}');
    }
} {
    return .{ .isel = isel, .inst = loop_inst };
}

fn fmtType(isel: *Select, ty: ZigType) ZigType.Formatter {
    return ty.fmt(isel.pt.zcu);
}

fn fmtConstant(isel: *Select, constant: Constant) @typeInfo(@TypeOf(Constant.fmtValue)).@"fn".return_type.? {
    return constant.fmtValue(isel.pt.zcu);
}

fn block(
    isel: *Select,
    air_inst_index: Air.Inst.Index,
    res_ty: ZigType,
    air_body: []const Air.Inst.Index,
) !void {
    if (res_ty.toIntern() != .noreturn_type) {
        isel.blocks.putAssumeCapacityNoClobber(air_inst_index, .{
            .live_registers = isel.live_registers,
            .target_label = @intCast(isel.instructions.items.len),
        });
    }
    try isel.body(air_body);
    if (res_ty.toIntern() != .noreturn_type) {
        const block_entry = isel.blocks.pop().?;
        assert(block_entry.key == air_inst_index);
        if (isel.live_values.fetchRemove(air_inst_index)) |result_vi| result_vi.value.deref(isel);
    }
}

fn emit(isel: *Select, instruction: codegen.aarch64.encoding.Instruction) !void {
    wip_mir_log.debug("  | {f}", .{instruction});
    try isel.instructions.append(isel.pt.zcu.gpa, instruction);
}

fn emitPanic(isel: *Select, panic_id: Zcu.SimplePanicId) !void {
    const zcu = isel.pt.zcu;
    try isel.nav_relocs.append(zcu.gpa, .{
        .nav = switch (zcu.intern_pool.indexToKey(zcu.std_lang_decl_values.get(panic_id.toStdLangDecl()))) {
            else => unreachable,
            inline .@"extern", .func => |func| func.owner_nav,
        },
        .reloc = .{ .label = @intCast(isel.instructions.items.len) },
    });
    try isel.emit(.bl(0));
}

fn emitLiteral(isel: *Select, bytes: []const u8) !void {
    const words: []align(1) const u32 = @ptrCast(bytes);
    const literals = try isel.literals.addManyAsSlice(isel.pt.zcu.gpa, words.len);
    switch (isel.target.cpu.arch.endian()) {
        .little => @memcpy(literals, words),
        .big => for (words, 0..) |word, word_index| {
            literals[literals.len - 1 - word_index] = @byteSwap(word);
        },
    }
}

fn fail(isel: *Select, comptime format: []const u8, args: anytype) codegen.Error {
    @branchHint(.cold);
    return isel.pt.zcu.codegenFail(isel.nav_index, format, args);
}

/// dst = src
fn movImmediate(isel: *Select, dst_reg: Register, src_imm: u64) !void {
    const sf = dst_reg.format.general;
    if (src_imm == 0) {
        const zr: Register = switch (sf) {
            .word => .wzr,
            .doubleword => .xzr,
        };
        return isel.emit(.orr(dst_reg, zr, .{ .register = zr }));
    }

    const Part = u16;
    const min_part: Part = std.math.minInt(Part);
    const max_part: Part = std.math.maxInt(Part);

    const parts: [4]Part = @bitCast(switch (sf) {
        .word => @as(u32, @intCast(src_imm)),
        .doubleword => @as(u64, @intCast(src_imm)),
    });
    const width: u7 = switch (sf) {
        .word => 32,
        .doubleword => 64,
    };
    const parts_len: u3 = @intCast(@divExact(width, @bitSizeOf(Part)));
    var equal_min_count: u3 = 0;
    var equal_max_count: u3 = 0;
    for (parts[0..parts_len]) |part| {
        equal_min_count += @intFromBool(part == min_part);
        equal_max_count += @intFromBool(part == max_part);
    }

    const equal_fill_count, const fill_part: Part = if (equal_min_count >= equal_max_count)
        .{ equal_min_count, min_part }
    else
        .{ equal_max_count, max_part };
    var remaining_parts = @max(parts_len - equal_fill_count, 1);

    if (remaining_parts > 1) {
        var elem_width: u8 = 2;
        while (elem_width <= width) : (elem_width <<= 1) {
            const emask = @as(u64, std.math.maxInt(u64)) >> @intCast(64 - elem_width);
            const rmask = @divExact(@as(u64, switch (sf) {
                .word => std.math.maxInt(u32),
                .doubleword => std.math.maxInt(u64),
            }), emask);
            const elem = src_imm & emask;
            if (src_imm != elem * rmask) continue;
            const imask: u64 = @bitCast(@as(i64, @bitCast(elem << 63)) >> 63);
            const lsb0 = elem ^ (imask & emask);
            const lsb1 = (lsb0 - 1) | lsb0;
            if ((lsb1 +% 1) & lsb1 == 0) {
                const lo: u6 = @intCast(@ctz(lsb0));
                const hi: u6 = @intCast(@clz(lsb0) - (64 - elem_width));
                const mid: u6 = @intCast(elem_width - lo - hi);
                const smask: u6 = @truncate(imask);
                const mid_masked = mid & ~smask;
                return isel.emit(.orr(
                    dst_reg,
                    switch (sf) {
                        .word => .wzr,
                        .doubleword => .xzr,
                    },
                    .{ .immediate = .{
                        .N = @fromBackingInt(@intCast(elem_width >> 6)),
                        .immr = hi + mid_masked,
                        .imms = ((((lo + hi) & smask) | mid_masked) - 1) | -%@as(u6, @truncate(elem_width)) << 1,
                    } },
                ));
            }
        }
    }

    var part_index = parts_len;
    while (part_index > 0) {
        part_index -= 1;
        if (part_index >= remaining_parts and parts[part_index] == fill_part) continue;
        remaining_parts -= 1;
        try isel.emit(if (remaining_parts > 0) .movk(
            dst_reg,
            parts[part_index],
            .{ .lsl = @fromBackingInt(@intCast(part_index)) },
        ) else switch (fill_part) {
            else => unreachable,
            min_part => .movz(
                dst_reg,
                parts[part_index],
                .{ .lsl = @fromBackingInt(@intCast(part_index)) },
            ),
            max_part => .movn(
                dst_reg,
                ~parts[part_index],
                .{ .lsl = @fromBackingInt(@intCast(part_index)) },
            ),
        });
    }
    assert(remaining_parts == 0);
}

/// elem_ptr = base +- elem_size * index
/// elem_ptr, base, and index may alias
fn elemPtr(
    isel: *Select,
    elem_ptr_ra: Register.Alias,
    base_ra: Register.Alias,
    op: codegen.aarch64.encoding.Instruction.AddSubtractOp,
    elem_size: u64,
    index_vi: Value.Index,
) !void {
    const index_mat = try index_vi.matReg(isel);
    switch (@popCount(elem_size)) {
        0 => unreachable,
        1 => try isel.emit(switch (op) {
            .add => switch (base_ra) {
                else => .add(elem_ptr_ra.x(), base_ra.x(), .{ .shifted_register = .{
                    .register = index_mat.ra.x(),
                    .shift = .{ .lsl = @intCast(@ctz(elem_size)) },
                } }),
                .zr => switch (@ctz(elem_size)) {
                    0 => .orr(elem_ptr_ra.x(), .xzr, .{ .register = index_mat.ra.x() }),
                    else => |shift| .ubfm(elem_ptr_ra.x(), index_mat.ra.x(), .{
                        .N = .doubleword,
                        .immr = @intCast(64 - shift),
                        .imms = @intCast(63 - shift),
                    }),
                },
            },
            .sub => .sub(elem_ptr_ra.x(), base_ra.x(), .{ .shifted_register = .{
                .register = index_mat.ra.x(),
                .shift = .{ .lsl = @intCast(@ctz(elem_size)) },
            } }),
        }),
        2 => {
            const shift: u6 = @intCast(@ctz(elem_size));
            const temp_ra, const free_temp_ra = temp_ra: switch (op) {
                .add => switch (base_ra) {
                    else => {
                        const temp_ra = try isel.allocIntReg();
                        errdefer isel.freeReg(temp_ra);
                        try isel.emit(.add(elem_ptr_ra.x(), base_ra.x(), .{ .shifted_register = .{
                            .register = temp_ra.x(),
                            .shift = .{ .lsl = shift },
                        } }));
                        break :temp_ra .{ temp_ra, true };
                    },
                    .zr => {
                        if (shift > 0) try isel.emit(.ubfm(elem_ptr_ra.x(), elem_ptr_ra.x(), .{
                            .N = .doubleword,
                            .immr = -%shift,
                            .imms = ~shift,
                        }));
                        break :temp_ra .{ elem_ptr_ra, false };
                    },
                },
                .sub => {
                    const temp_ra = try isel.allocIntReg();
                    errdefer isel.freeReg(temp_ra);
                    try isel.emit(.sub(elem_ptr_ra.x(), base_ra.x(), .{ .shifted_register = .{
                        .register = temp_ra.x(),
                        .shift = .{ .lsl = shift },
                    } }));
                    break :temp_ra .{ temp_ra, true };
                },
            };
            defer if (free_temp_ra) isel.freeReg(temp_ra);
            try isel.emit(.add(temp_ra.x(), index_mat.ra.x(), .{ .shifted_register = .{
                .register = index_mat.ra.x(),
                .shift = .{ .lsl = @intCast(63 - @clz(elem_size) - shift) },
            } }));
        },
        else => {
            const elem_size_lsb1 = (elem_size - 1) | elem_size;
            if ((elem_size_lsb1 +% 1) & elem_size_lsb1 == 0) {
                const shift: u6 = @intCast(@ctz(elem_size));
                const temp_ra, const free_temp_ra = temp_ra: switch (op) {
                    .add => {
                        const temp_ra = try isel.allocIntReg();
                        errdefer isel.freeReg(temp_ra);
                        try isel.emit(.sub(elem_ptr_ra.x(), base_ra.x(), .{ .shifted_register = .{
                            .register = temp_ra.x(),
                            .shift = .{ .lsl = shift },
                        } }));
                        break :temp_ra .{ temp_ra, true };
                    },
                    .sub => switch (base_ra) {
                        else => {
                            const temp_ra = try isel.allocIntReg();
                            errdefer isel.freeReg(temp_ra);
                            try isel.emit(.add(elem_ptr_ra.x(), base_ra.x(), .{ .shifted_register = .{
                                .register = temp_ra.x(),
                                .shift = .{ .lsl = shift },
                            } }));
                            break :temp_ra .{ temp_ra, true };
                        },
                        .zr => {
                            if (shift > 0) try isel.emit(.ubfm(elem_ptr_ra.x(), elem_ptr_ra.x(), .{
                                .N = .doubleword,
                                .immr = -%shift,
                                .imms = ~shift,
                            }));
                            break :temp_ra .{ elem_ptr_ra, false };
                        },
                    },
                };
                defer if (free_temp_ra) isel.freeReg(temp_ra);
                try isel.emit(.sub(temp_ra.x(), index_mat.ra.x(), .{ .shifted_register = .{
                    .register = index_mat.ra.x(),
                    .shift = .{ .lsl = @intCast(64 - @clz(elem_size) - shift) },
                } }));
            } else {
                const temp_ra, const free_temp_ra = if (elem_ptr_ra == base_ra or elem_ptr_ra == index_mat.ra) .{
                    try isel.allocIntReg(), true,
                } else .{
                    elem_ptr_ra, false,
                };
                defer if (free_temp_ra) isel.freeReg(temp_ra);
                try isel.emit(switch (op) {
                    .add => .madd(elem_ptr_ra.x(), index_mat.ra.x(), temp_ra.x(), base_ra.x()),
                    .sub => .msub(elem_ptr_ra.x(), index_mat.ra.x(), temp_ra.x(), base_ra.x()),
                });
                try isel.movImmediate(temp_ra.x(), elem_size);
            }
        },
    }
    try index_mat.finish(isel);
}

fn clzLimb(
    isel: *Select,
    res_ra: Register.Alias,
    src_int_info: std.lang.Type.Int,
    src_ra: Register.Alias,
) !void {
    switch (src_int_info.bits) {
        else => unreachable,
        1...31 => |bits| {
            try isel.emit(.sub(res_ra.w(), res_ra.w(), .{
                .immediate = @intCast(32 - bits),
            }));
            switch (src_int_info.signedness) {
                .signed => {
                    try isel.emit(.clz(res_ra.w(), res_ra.w()));
                    try isel.emit(.ubfm(res_ra.w(), src_ra.w(), .{
                        .N = .word,
                        .immr = 0,
                        .imms = @intCast(bits - 1),
                    }));
                },
                .unsigned => try isel.emit(.clz(res_ra.w(), src_ra.w())),
            }
        },
        32 => try isel.emit(.clz(res_ra.w(), src_ra.w())),
        33...63 => |bits| {
            try isel.emit(.sub(res_ra.w(), res_ra.w(), .{
                .immediate = @intCast(64 - bits),
            }));
            switch (src_int_info.signedness) {
                .signed => {
                    try isel.emit(.clz(res_ra.x(), res_ra.x()));
                    try isel.emit(.ubfm(res_ra.x(), src_ra.x(), .{
                        .N = .doubleword,
                        .immr = 0,
                        .imms = @intCast(bits - 1),
                    }));
                },
                .unsigned => try isel.emit(.clz(res_ra.x(), src_ra.x())),
            }
        },
        64 => try isel.emit(.clz(res_ra.x(), src_ra.x())),
    }
}

fn ctzLimb(
    isel: *Select,
    res_ra: Register.Alias,
    src_int_info: std.lang.Type.Int,
    src_ra: Register.Alias,
) !void {
    switch (src_int_info.bits) {
        else => unreachable,
        1...31 => |bits| {
            try isel.emit(.clz(res_ra.w(), res_ra.w()));
            try isel.emit(.rbit(res_ra.w(), res_ra.w()));
            try isel.emit(.orr(res_ra.w(), src_ra.w(), .{ .immediate = .{
                .N = .word,
                .immr = @intCast(32 - bits),
                .imms = @intCast(32 - bits - 1),
            } }));
        },
        32 => {
            try isel.emit(.clz(res_ra.w(), res_ra.w()));
            try isel.emit(.rbit(res_ra.w(), src_ra.w()));
        },
        33...63 => |bits| {
            try isel.emit(.clz(res_ra.x(), res_ra.x()));
            try isel.emit(.rbit(res_ra.x(), res_ra.x()));
            try isel.emit(.orr(res_ra.x(), src_ra.x(), .{ .immediate = .{
                .N = .doubleword,
                .immr = @intCast(64 - bits),
                .imms = @intCast(64 - bits - 1),
            } }));
        },
        64 => {
            try isel.emit(.clz(res_ra.x(), res_ra.x()));
            try isel.emit(.rbit(res_ra.x(), src_ra.x()));
        },
    }
}

fn cmp(
    isel: *Select,
    res_ra: Register.Alias,
    ty: ZigType,
    orig_lhs_vi: Value.Index,
    op: std.math.CompareOperator,
    orig_rhs_vi: Value.Index,
) !struct { cset_label: usize } {
    var lhs_vi = orig_lhs_vi;
    var rhs_vi = orig_rhs_vi;
    if (!ty.isRuntimeFloat()) {
        const zcu = isel.pt.zcu;
        const cmp_ty = if (ty.zigTypeTag(zcu) == .optional and ty.optionalReprIsPayload(zcu))
            ty.optionalChild(zcu)
        else
            ty;
        const int_info: std.lang.Type.Int = if (cmp_ty.toIntern() == .bool_type)
            .{ .signedness = .unsigned, .bits = 1 }
        else if (cmp_ty.zigTypeTag(zcu) == .error_set)
            .{ .signedness = .unsigned, .bits = zcu.errorSetBits() }
        else if (cmp_ty.isAbiInt(zcu))
            cmp_ty.intInfo(zcu)
        else if (cmp_ty.isPtrAtRuntime(zcu))
            .{ .signedness = .unsigned, .bits = 64 }
        else
            return isel.fail("bad cmp_{t} {f}", .{ op, isel.fmtType(ty) });
        if (int_info.bits > 64 * Value.max_parts * Value.max_parts) return isel.fail("too big cmp_{t} {f}", .{ op, isel.fmtType(ty) });
        try isel.emit(.csinc(res_ra.w(), .wzr, .wzr, .invert(cond: switch (op) {
            .lt => switch (int_info.signedness) {
                .signed => .lt,
                .unsigned => .lo,
            },
            .lte => switch (int_info.bits) {
                else => unreachable,
                1...64 => switch (int_info.signedness) {
                    .signed => .le,
                    .unsigned => .ls,
                },
                65...64 * Value.max_parts * Value.max_parts => {
                    std.mem.swap(Value.Index, &lhs_vi, &rhs_vi);
                    continue :cond .gte;
                },
            },
            .eq => .eq,
            .gte => switch (int_info.signedness) {
                .signed => .ge,
                .unsigned => .hs,
            },
            .gt => switch (int_info.bits) {
                else => unreachable,
                1...64 => switch (int_info.signedness) {
                    .signed => .gt,
                    .unsigned => .hi,
                },
                65...64 * Value.max_parts * Value.max_parts => {
                    std.mem.swap(Value.Index, &lhs_vi, &rhs_vi);
                    continue :cond .lt;
                },
            },
            .neq => .ne,
        })));
        const cset_label = isel.instructions.items.len;

        var part_offset = lhs_vi.size(isel);
        while (part_offset > 0) {
            const part_size = @min(part_offset, 8);
            part_offset -= part_size;
            var lhs_part_it = lhs_vi.field(ty, part_offset, part_size);
            const lhs_part_vi = try lhs_part_it.only(isel);
            const lhs_part_mat = try lhs_part_vi.?.matReg(isel);
            var rhs_part_it = rhs_vi.field(ty, part_offset, part_size);
            const rhs_part_vi = try rhs_part_it.only(isel);
            const rhs_part_mat = try rhs_part_vi.?.matReg(isel);
            try isel.emit(switch (part_size) {
                else => unreachable,
                1...4 => switch (part_offset) {
                    0 => .subs(.wzr, lhs_part_mat.ra.w(), .{ .register = rhs_part_mat.ra.w() }),
                    else => switch (op) {
                        .lt, .lte, .gte, .gt => .sbcs(
                            .wzr,
                            lhs_part_mat.ra.w(),
                            rhs_part_mat.ra.w(),
                        ),
                        .eq, .neq => .ccmp(
                            lhs_part_mat.ra.w(),
                            .{ .register = rhs_part_mat.ra.w() },
                            .{ .n = false, .z = false, .c = false, .v = false },
                            .eq,
                        ),
                    },
                },
                5...8 => switch (part_offset) {
                    0 => .subs(.xzr, lhs_part_mat.ra.x(), .{ .register = rhs_part_mat.ra.x() }),
                    else => switch (op) {
                        .lt, .lte, .gte, .gt => .sbcs(
                            .xzr,
                            lhs_part_mat.ra.x(),
                            rhs_part_mat.ra.x(),
                        ),
                        .eq, .neq => .ccmp(
                            lhs_part_mat.ra.x(),
                            .{ .register = rhs_part_mat.ra.x() },
                            .{ .n = false, .z = false, .c = false, .v = false },
                            .eq,
                        ),
                    },
                },
            });
            try rhs_part_mat.finish(isel);
            try lhs_part_mat.finish(isel);
        }
        return .{ .cset_label = cset_label };
    }
    switch (ty.floatBits(isel.target)) {
        else => unreachable,
        16, 32, 64 => |bits| {
            const need_fcvt = switch (bits) {
                else => unreachable,
                16 => !isel.target.cpu.has(.aarch64, .fullfp16),
                32, 64 => false,
            };
            try isel.emit(.csinc(res_ra.w(), .wzr, .wzr, .invert(switch (op) {
                .lt => .lo,
                .lte => .ls,
                .eq => .eq,
                .gte => .ge,
                .gt => .gt,
                .neq => .ne,
            })));
            const cset_label = isel.instructions.items.len;

            const lhs_mat = try lhs_vi.matReg(isel);
            const rhs_mat = try rhs_vi.matReg(isel);
            const lhs_ra = if (need_fcvt) try isel.allocVecReg() else lhs_mat.ra;
            defer if (need_fcvt) isel.freeReg(lhs_ra);
            const rhs_ra = if (need_fcvt) try isel.allocVecReg() else rhs_mat.ra;
            defer if (need_fcvt) isel.freeReg(rhs_ra);
            try isel.emit(bits: switch (bits) {
                else => unreachable,
                16 => if (need_fcvt)
                    continue :bits 32
                else
                    .fcmp(lhs_ra.h(), .{ .register = rhs_ra.h() }),
                32 => .fcmp(lhs_ra.s(), .{ .register = rhs_ra.s() }),
                64 => .fcmp(lhs_ra.d(), .{ .register = rhs_ra.d() }),
            });
            if (need_fcvt) {
                try isel.emit(.fcvt(rhs_ra.s(), rhs_mat.ra.h()));
                try isel.emit(.fcvt(lhs_ra.s(), lhs_mat.ra.h()));
            }
            try rhs_mat.finish(isel);
            try lhs_mat.finish(isel);
            return .{ .cset_label = cset_label };
        },
        80, 128 => |bits| {
            try call.prepareReturn(isel);
            try call.returnFill(isel, .r0);
            try isel.emit(.csinc(res_ra.w(), .wzr, .wzr, .invert(cond: switch (op) {
                .lt => .lt,
                .lte => .le,
                .eq => .eq,
                .gte => {
                    std.mem.swap(Value.Index, &lhs_vi, &rhs_vi);
                    continue :cond .lte;
                },
                .gt => {
                    std.mem.swap(Value.Index, &lhs_vi, &rhs_vi);
                    continue :cond .lt;
                },
                .neq => .ne,
            })));
            const cset_label = isel.instructions.items.len;
            try isel.emit(.subs(.wzr, .w0, .{ .immediate = 0 }));
            try call.finishReturn(isel);

            try call.prepareCallee(isel);
            try isel.global_relocs.append(isel.pt.zcu.gpa, .{
                .name = switch (bits) {
                    else => unreachable,
                    16 => "__cmphf2",
                    32 => "__cmpsf2",
                    64 => "__cmpdf2",
                    80 => "__cmpxf2",
                    128 => "__cmptf2",
                },
                .reloc = .{ .label = @intCast(isel.instructions.items.len) },
            });
            try isel.emit(.bl(0));
            try call.finishCallee(isel);

            try call.prepareParams(isel);
            switch (bits) {
                else => unreachable,
                16, 32, 64, 128 => {
                    try call.paramLiveOut(isel, rhs_vi, .v1);
                    try call.paramLiveOut(isel, lhs_vi, .v0);
                },
                80 => {
                    var rhs_hi16_it = rhs_vi.field(ty, 8, 8);
                    const rhs_hi16_vi = try rhs_hi16_it.only(isel);
                    try call.paramLiveOut(isel, rhs_hi16_vi.?, .r3);
                    var rhs_lo64_it = rhs_vi.field(ty, 0, 8);
                    const rhs_lo64_vi = try rhs_lo64_it.only(isel);
                    try call.paramLiveOut(isel, rhs_lo64_vi.?, .r2);
                    var lhs_hi16_it = lhs_vi.field(ty, 8, 8);
                    const lhs_hi16_vi = try lhs_hi16_it.only(isel);
                    try call.paramLiveOut(isel, lhs_hi16_vi.?, .r1);
                    var lhs_lo64_it = lhs_vi.field(ty, 0, 8);
                    const lhs_lo64_vi = try lhs_lo64_it.only(isel);
                    try call.paramLiveOut(isel, lhs_lo64_vi.?, .r0);
                },
            }
            try call.finishParams(isel);
            return .{ .cset_label = cset_label };
        },
    }
}

fn loadReg(
    isel: *Select,
    ra: Register.Alias,
    size: u64,
    signedness: std.lang.Signedness,
    base_ra: Register.Alias,
    offset: i65,
) !void {
    switch (size) {
        0 => unreachable,
        1 => {
            if (std.math.cast(u12, offset)) |unsigned_offset| return isel.emit(if (ra.isVector()) .ldr(
                ra.b(),
                .{ .unsigned_offset = .{
                    .base = base_ra.x(),
                    .offset = unsigned_offset,
                } },
            ) else switch (signedness) {
                .signed => .ldrsb(ra.w(), .{ .unsigned_offset = .{
                    .base = base_ra.x(),
                    .offset = unsigned_offset,
                } }),
                .unsigned => .ldrb(ra.w(), .{ .unsigned_offset = .{
                    .base = base_ra.x(),
                    .offset = unsigned_offset,
                } }),
            });
            if (std.math.cast(i9, offset)) |signed_offset| return isel.emit(if (ra.isVector())
                .ldur(ra.b(), base_ra.x(), signed_offset)
            else switch (signedness) {
                .signed => .ldursb(ra.w(), base_ra.x(), signed_offset),
                .unsigned => .ldurb(ra.w(), base_ra.x(), signed_offset),
            });
        },
        2 => {
            if (std.math.cast(u13, offset)) |unsigned_offset| if (unsigned_offset % 2 == 0)
                return isel.emit(if (ra.isVector()) .ldr(
                    ra.h(),
                    .{ .unsigned_offset = .{
                        .base = base_ra.x(),
                        .offset = unsigned_offset,
                    } },
                ) else switch (signedness) {
                    .signed => .ldrsh(
                        ra.w(),
                        .{ .unsigned_offset = .{
                            .base = base_ra.x(),
                            .offset = unsigned_offset,
                        } },
                    ),
                    .unsigned => .ldrh(
                        ra.w(),
                        .{ .unsigned_offset = .{
                            .base = base_ra.x(),
                            .offset = unsigned_offset,
                        } },
                    ),
                });
            if (std.math.cast(i9, offset)) |signed_offset| return isel.emit(if (ra.isVector())
                .ldur(ra.h(), base_ra.x(), signed_offset)
            else switch (signedness) {
                .signed => .ldursh(ra.w(), base_ra.x(), signed_offset),
                .unsigned => .ldurh(ra.w(), base_ra.x(), signed_offset),
            });
        },
        3 => {
            const lo16_ra = try isel.allocIntReg();
            defer isel.freeReg(lo16_ra);
            try isel.emit(.orr(ra.w(), lo16_ra.w(), .{ .shifted_register = .{
                .register = ra.w(),
                .shift = .{ .lsl = 16 },
            } }));
            try isel.loadReg(ra, 1, signedness, base_ra, offset + 2);
            return isel.loadReg(lo16_ra, 2, .unsigned, base_ra, offset);
        },
        4 => {
            if (std.math.cast(u14, offset)) |unsigned_offset| if (unsigned_offset % 4 == 0) return isel.emit(.ldr(
                if (ra.isVector()) ra.s() else ra.w(),
                .{ .unsigned_offset = .{
                    .base = base_ra.x(),
                    .offset = unsigned_offset,
                } },
            ));
            if (std.math.cast(i9, offset)) |signed_offset| return isel.emit(.ldur(
                if (ra.isVector()) ra.s() else ra.w(),
                base_ra.x(),
                signed_offset,
            ));
        },
        5, 6 => {
            const lo32_ra = try isel.allocIntReg();
            defer isel.freeReg(lo32_ra);
            try isel.emit(.orr(ra.x(), lo32_ra.x(), .{ .shifted_register = .{
                .register = ra.x(),
                .shift = .{ .lsl = 32 },
            } }));
            try isel.loadReg(ra, size - 4, signedness, base_ra, offset + 4);
            return isel.loadReg(lo32_ra, 4, .unsigned, base_ra, offset);
        },
        7 => {
            const lo32_ra = try isel.allocIntReg();
            defer isel.freeReg(lo32_ra);
            const lo48_ra = try isel.allocIntReg();
            defer isel.freeReg(lo48_ra);
            try isel.emit(.orr(ra.x(), lo48_ra.x(), .{ .shifted_register = .{
                .register = ra.x(),
                .shift = .{ .lsl = 32 + 16 },
            } }));
            try isel.loadReg(ra, 1, signedness, base_ra, offset + 4 + 2);
            try isel.emit(.orr(lo48_ra.x(), lo32_ra.x(), .{ .shifted_register = .{
                .register = lo48_ra.x(),
                .shift = .{ .lsl = 32 },
            } }));
            try isel.loadReg(lo48_ra, 2, .unsigned, base_ra, offset + 4);
            return isel.loadReg(lo32_ra, 4, .unsigned, base_ra, offset);
        },
        8 => {
            if (std.math.cast(u15, offset)) |unsigned_offset| if (unsigned_offset % 8 == 0) return isel.emit(.ldr(
                if (ra.isVector()) ra.d() else ra.x(),
                .{ .unsigned_offset = .{
                    .base = base_ra.x(),
                    .offset = unsigned_offset,
                } },
            ));
            if (std.math.cast(i9, offset)) |signed_offset| return isel.emit(.ldur(
                if (ra.isVector()) ra.d() else ra.x(),
                base_ra.x(),
                signed_offset,
            ));
        },
        16 => {
            if (std.math.cast(u16, offset)) |unsigned_offset| if (unsigned_offset % 16 == 0) return isel.emit(.ldr(
                ra.q(),
                .{ .unsigned_offset = .{
                    .base = base_ra.x(),
                    .offset = unsigned_offset,
                } },
            ));
            if (std.math.cast(i9, offset)) |signed_offset| return isel.emit(.ldur(ra.q(), base_ra.x(), signed_offset));
        },
        else => return isel.fail("bad load size: {d}", .{size}),
    }
    const ptr_ra = try isel.allocIntReg();
    defer isel.freeReg(ptr_ra);
    try isel.loadReg(ra, size, signedness, ptr_ra, 0);
    if (std.math.cast(u24, offset)) |pos_offset| {
        const lo12: u12 = @truncate(pos_offset >> 0);
        const hi12: u12 = @intCast(pos_offset >> 12);
        if (hi12 > 0) try isel.emit(.add(
            ptr_ra.x(),
            if (lo12 > 0) ptr_ra.x() else base_ra.x(),
            .{ .shifted_immediate = .{ .immediate = hi12, .lsl = .@"12" } },
        ));
        if (lo12 > 0 or hi12 == 0) try isel.emit(.add(ptr_ra.x(), base_ra.x(), .{ .immediate = lo12 }));
    } else if (std.math.cast(u24, -offset)) |neg_offset| {
        const lo12: u12 = @truncate(neg_offset >> 0);
        const hi12: u12 = @intCast(neg_offset >> 12);
        if (hi12 > 0) try isel.emit(.sub(
            ptr_ra.x(),
            if (lo12 > 0) ptr_ra.x() else base_ra.x(),
            .{ .shifted_immediate = .{ .immediate = hi12, .lsl = .@"12" } },
        ));
        if (lo12 > 0 or hi12 == 0) try isel.emit(.sub(ptr_ra.x(), base_ra.x(), .{ .immediate = lo12 }));
    } else {
        try isel.emit(.add(ptr_ra.x(), base_ra.x(), .{ .register = ptr_ra.x() }));
        try isel.movImmediate(ptr_ra.x(), @truncate(@as(u65, @bitCast(offset))));
    }
}

fn storeReg(
    isel: *Select,
    ra: Register.Alias,
    size: u64,
    base_ra: Register.Alias,
    offset: i65,
) !void {
    switch (size) {
        0 => unreachable,
        1 => {
            if (std.math.cast(u12, offset)) |unsigned_offset| return isel.emit(if (ra.isVector()) .str(
                ra.b(),
                .{ .unsigned_offset = .{
                    .base = base_ra.x(),
                    .offset = unsigned_offset,
                } },
            ) else .strb(
                ra.w(),
                .{ .unsigned_offset = .{
                    .base = base_ra.x(),
                    .offset = unsigned_offset,
                } },
            ));
            if (std.math.cast(i9, offset)) |signed_offset| return isel.emit(if (ra.isVector())
                .stur(ra.b(), base_ra.x(), signed_offset)
            else
                .sturb(ra.w(), base_ra.x(), signed_offset));
        },
        2 => {
            if (std.math.cast(u13, offset)) |unsigned_offset| if (unsigned_offset % 2 == 0)
                return isel.emit(if (ra.isVector()) .str(
                    ra.h(),
                    .{ .unsigned_offset = .{
                        .base = base_ra.x(),
                        .offset = unsigned_offset,
                    } },
                ) else .strh(
                    ra.w(),
                    .{ .unsigned_offset = .{
                        .base = base_ra.x(),
                        .offset = unsigned_offset,
                    } },
                ));
            if (std.math.cast(i9, offset)) |signed_offset| return isel.emit(if (ra.isVector())
                .stur(ra.h(), base_ra.x(), signed_offset)
            else
                .sturh(ra.w(), base_ra.x(), signed_offset));
        },
        3 => {
            const hi8_ra = try isel.allocIntReg();
            defer isel.freeReg(hi8_ra);
            try isel.storeReg(hi8_ra, 1, base_ra, offset + 2);
            try isel.storeReg(ra, 2, base_ra, offset);
            return isel.emit(.ubfm(hi8_ra.w(), ra.w(), .{
                .N = .word,
                .immr = 16,
                .imms = 16 + 8 - 1,
            }));
        },
        4 => {
            if (std.math.cast(u14, offset)) |unsigned_offset| if (unsigned_offset % 4 == 0) return isel.emit(.str(
                if (ra.isVector()) ra.s() else ra.w(),
                .{ .unsigned_offset = .{
                    .base = base_ra.x(),
                    .offset = unsigned_offset,
                } },
            ));
            if (std.math.cast(i9, offset)) |signed_offset| return isel.emit(.stur(
                if (ra.isVector()) ra.s() else ra.w(),
                base_ra.x(),
                signed_offset,
            ));
        },
        5 => {
            const hi8_ra = try isel.allocIntReg();
            defer isel.freeReg(hi8_ra);
            try isel.storeReg(hi8_ra, 1, base_ra, offset + 4);
            try isel.storeReg(ra, 4, base_ra, offset);
            return isel.emit(.ubfm(hi8_ra.x(), ra.x(), .{
                .N = .doubleword,
                .immr = 32,
                .imms = 32 + 8 - 1,
            }));
        },
        6 => {
            const hi16_ra = try isel.allocIntReg();
            defer isel.freeReg(hi16_ra);
            try isel.storeReg(hi16_ra, 2, base_ra, offset + 4);
            try isel.storeReg(ra, 4, base_ra, offset);
            return isel.emit(.ubfm(hi16_ra.x(), ra.x(), .{
                .N = .doubleword,
                .immr = 32,
                .imms = 32 + 16 - 1,
            }));
        },
        7 => {
            const hi16_ra = try isel.allocIntReg();
            defer isel.freeReg(hi16_ra);
            const hi8_ra = try isel.allocIntReg();
            defer isel.freeReg(hi8_ra);
            try isel.storeReg(hi8_ra, 1, base_ra, offset + 6);
            try isel.storeReg(hi16_ra, 2, base_ra, offset + 4);
            try isel.storeReg(ra, 4, base_ra, offset);
            try isel.emit(.ubfm(hi8_ra.x(), ra.x(), .{
                .N = .doubleword,
                .immr = 32 + 16,
                .imms = 32 + 16 + 8 - 1,
            }));
            return isel.emit(.ubfm(hi16_ra.x(), ra.x(), .{
                .N = .doubleword,
                .immr = 32,
                .imms = 32 + 16 - 1,
            }));
        },
        8 => {
            if (std.math.cast(u15, offset)) |unsigned_offset| if (unsigned_offset % 8 == 0) return isel.emit(.str(
                if (ra.isVector()) ra.d() else ra.x(),
                .{ .unsigned_offset = .{
                    .base = base_ra.x(),
                    .offset = unsigned_offset,
                } },
            ));
            if (std.math.cast(i9, offset)) |signed_offset| return isel.emit(.stur(
                if (ra.isVector()) ra.d() else ra.x(),
                base_ra.x(),
                signed_offset,
            ));
        },
        16 => {
            if (std.math.cast(u16, offset)) |unsigned_offset| if (unsigned_offset % 16 == 0) return isel.emit(.str(
                ra.q(),
                .{ .unsigned_offset = .{
                    .base = base_ra.x(),
                    .offset = unsigned_offset,
                } },
            ));
            if (std.math.cast(i9, offset)) |signed_offset| return isel.emit(.stur(ra.q(), base_ra.x(), signed_offset));
        },
        else => return isel.fail("bad store size: {d}", .{size}),
    }
    const ptr_ra = try isel.allocIntReg();
    defer isel.freeReg(ptr_ra);
    try isel.storeReg(ra, size, ptr_ra, 0);
    if (std.math.cast(u24, offset)) |pos_offset| {
        const lo12: u12 = @truncate(pos_offset >> 0);
        const hi12: u12 = @intCast(pos_offset >> 12);
        if (hi12 > 0) try isel.emit(.add(
            ptr_ra.x(),
            if (lo12 > 0) ptr_ra.x() else base_ra.x(),
            .{ .shifted_immediate = .{ .immediate = hi12, .lsl = .@"12" } },
        ));
        if (lo12 > 0 or hi12 == 0) try isel.emit(.add(ptr_ra.x(), base_ra.x(), .{ .immediate = lo12 }));
    } else if (std.math.cast(u24, -offset)) |neg_offset| {
        const lo12: u12 = @truncate(neg_offset >> 0);
        const hi12: u12 = @intCast(neg_offset >> 12);
        if (hi12 > 0) try isel.emit(.sub(
            ptr_ra.x(),
            if (lo12 > 0) ptr_ra.x() else base_ra.x(),
            .{ .shifted_immediate = .{ .immediate = hi12, .lsl = .@"12" } },
        ));
        if (lo12 > 0 or hi12 == 0) try isel.emit(.sub(ptr_ra.x(), base_ra.x(), .{ .immediate = lo12 }));
    } else {
        try isel.emit(.add(ptr_ra.x(), base_ra.x(), .{ .register = ptr_ra.x() }));
        try isel.movImmediate(ptr_ra.x(), @truncate(@as(u65, @bitCast(offset))));
    }
}

const DomInt = u8;

pub const Value = struct {
    refs: u32,
    flags: Flags,
    offset_from_parent: u64,
    parent_payload: Parent.Payload,
    location_payload: Location.Payload,
    parts: Value.Index,

    /// Must be at least 16 to compute call abi.
    /// Must be at least 16, the largest hardware alignment.
    pub const max_parts = 16;
    pub const PartsLen = std.math.IntFittingRange(0, Value.max_parts);

    comptime {
        if (!std.debug.runtime_safety) assert(@sizeOf(Value) == 32);
    }

    pub const Flags = packed struct(u32) {
        alignment: InternPool.Alignment,
        parent_tag: Parent.Tag,
        location_tag: Location.Tag,
        parts_len_minus_one: std.math.IntFittingRange(0, Value.max_parts - 1),
        unused: u18 = 0,
    };

    pub const Parent = union(enum(u3)) {
        unallocated: void,
        stack_slot: Indirect,
        address: Value.Index,
        value: Value.Index,
        constant: Constant,

        pub const Tag = @typeInfo(Parent).@"union".tag_type.?;
        pub const Payload = Payload: {
            const info = @typeInfo(Parent).@"union";
            break :Payload @Union(.auto, null, info.field_names, info.field_types[0..], &@splat(.{}));
        };
    };

    pub const Location = union(enum(u1)) {
        large: struct {
            size: u64,
        },
        small: struct {
            size: u5,
            signedness: std.lang.Signedness,
            is_vector: bool,
            hint: Register.Alias,
            register: Register.Alias,
        },

        pub const Tag = @typeInfo(Location).@"union".tag_type.?;
        pub const Payload = Payload: {
            const info = @typeInfo(Location).@"union";
            break :Payload @Union(.auto, null, info.field_names, info.field_types[0..], &@splat(.{}));
        };
    };

    pub const Indirect = packed struct(u32) {
        base: Register.Alias,
        offset: i25,

        pub fn withOffset(ind: Indirect, offset: i25) Indirect {
            return .{
                .base = ind.base,
                .offset = ind.offset + offset,
            };
        }
    };

    pub const Index = enum(u32) {
        allocating = std.math.maxInt(u32) - 1,
        free = std.math.maxInt(u32) - 0,
        _,

        fn get(vi: Value.Index, isel: *Select) *Value {
            return &isel.values.items[@backingInt(vi)];
        }

        fn setAlignment(vi: Value.Index, isel: *Select, new_alignment: InternPool.Alignment) void {
            vi.get(isel).flags.alignment = new_alignment;
        }

        pub fn alignment(vi: Value.Index, isel: *Select) InternPool.Alignment {
            return vi.get(isel).flags.alignment;
        }

        pub fn setParent(vi: Value.Index, isel: *Select, new_parent: Parent) void {
            const value = vi.get(isel);
            assert(value.flags.parent_tag == .unallocated);
            value.flags.parent_tag = new_parent;
            value.parent_payload = switch (new_parent) {
                .unallocated => unreachable,
                inline else => |payload, tag| @unionInit(Parent.Payload, @tagName(tag), payload),
            };
            if (value.refs > 0) switch (new_parent) {
                .unallocated => unreachable,
                .stack_slot, .constant => {},
                .address, .value => |parent_vi| _ = parent_vi.ref(isel),
            };
        }

        pub fn changeStackSlot(vi: Value.Index, isel: *Select, new_stack_slot: Indirect) void {
            const value = vi.get(isel);
            assert(value.flags.parent_tag == .stack_slot);
            value.flags.parent_tag = .unallocated;
            vi.setParent(isel, .{ .stack_slot = new_stack_slot });
        }

        pub fn parent(vi: Value.Index, isel: *Select) Parent {
            const value = vi.get(isel);
            return switch (value.flags.parent_tag) {
                inline else => |tag| @unionInit(
                    Parent,
                    @tagName(tag),
                    @field(value.parent_payload, @tagName(tag)),
                ),
            };
        }

        pub fn valueParent(initial_vi: Value.Index, isel: *Select) struct { u64, Value.Index } {
            var offset: u64 = 0;
            var vi = initial_vi;
            parent: switch (vi.parent(isel)) {
                else => return .{ offset, vi },
                .value => |parent_vi| {
                    offset += vi.position(isel)[0];
                    vi = parent_vi;
                    continue :parent parent_vi.parent(isel);
                },
            }
        }

        pub fn location(vi: Value.Index, isel: *Select) Location {
            const value = vi.get(isel);
            return switch (value.flags.location_tag) {
                inline else => |tag| @unionInit(
                    Location,
                    @tagName(tag),
                    @field(value.location_payload, @tagName(tag)),
                ),
            };
        }

        pub fn position(vi: Value.Index, isel: *Select) struct { u64, u64 } {
            return .{ vi.get(isel).offset_from_parent, vi.size(isel) };
        }

        pub fn size(vi: Value.Index, isel: *Select) u64 {
            return switch (vi.location(isel)) {
                inline else => |loc| loc.size,
            };
        }

        fn setHint(vi: Value.Index, isel: *Select, new_hint: Register.Alias) void {
            vi.get(isel).location_payload.small.hint = new_hint;
        }

        pub fn hint(vi: Value.Index, isel: *Select) ?Register.Alias {
            return switch (vi.location(isel)) {
                .large => null,
                .small => |loc| switch (loc.hint) {
                    .zr => null,
                    else => |hint_reg| hint_reg,
                },
            };
        }

        fn setSignedness(vi: Value.Index, isel: *Select, new_signedness: std.lang.Signedness) void {
            const value = vi.get(isel);
            assert(value.location_payload.small.size <= 2);
            value.location_payload.small.signedness = new_signedness;
        }

        pub fn signedness(vi: Value.Index, isel: *Select) std.lang.Signedness {
            const value = vi.get(isel);
            return switch (value.flags.location_tag) {
                .large => .unsigned,
                .small => value.location_payload.small.signedness,
            };
        }

        fn setIsVector(vi: Value.Index, isel: *Select) void {
            const is_vector = &vi.get(isel).location_payload.small.is_vector;
            assert(!is_vector.*);
            is_vector.* = true;
        }

        pub fn isVector(vi: Value.Index, isel: *Select) bool {
            const value = vi.get(isel);
            return switch (value.flags.location_tag) {
                .large => false,
                .small => value.location_payload.small.is_vector,
            };
        }

        pub fn register(vi: Value.Index, isel: *Select) ?Register.Alias {
            return switch (vi.location(isel)) {
                .large => null,
                .small => |loc| switch (loc.register) {
                    .zr => null,
                    else => |reg| reg,
                },
            };
        }

        pub fn isUsed(vi: Value.Index, isel: *Select) bool {
            return vi.valueParent(isel)[1].parent(isel) != .unallocated or vi.hasRegisterRecursive(isel);
        }

        fn hasRegisterRecursive(vi: Value.Index, isel: *Select) bool {
            if (vi.register(isel)) |_| return true;
            var part_it = vi.parts(isel);
            if (part_it.only() == null) while (part_it.next()) |part_vi| if (part_vi.hasRegisterRecursive(isel)) return true;
            return false;
        }

        fn setParts(vi: Value.Index, isel: *Select, parts_len: Value.PartsLen) void {
            assert(parts_len > 1);
            const value = vi.get(isel);
            assert(value.flags.parts_len_minus_one == 0);
            value.parts = @fromBackingInt(@intCast(isel.values.items.len));
            value.flags.parts_len_minus_one = @intCast(parts_len - 1);
        }

        fn addPart(vi: Value.Index, isel: *Select, part_offset: u64, part_size: u64) Value.Index {
            const part_vi = isel.initValueAdvanced(vi.alignment(isel), part_offset, part_size);
            tracking_log.debug("${d} <- ${d}[{d}]", .{
                @backingInt(part_vi),
                @backingInt(vi),
                part_offset,
            });
            part_vi.setParent(isel, .{ .value = vi });
            return part_vi;
        }

        pub fn parts(vi: Value.Index, isel: *Select) Value.PartIterator {
            const value = vi.get(isel);
            return switch (value.flags.parts_len_minus_one) {
                0 => .initOne(vi),
                else => |parts_len_minus_one| .{
                    .vi = value.parts,
                    .remaining = @as(Value.PartsLen, parts_len_minus_one) + 1,
                },
            };
        }

        fn containingParts(vi: Value.Index, isel: *Select, part_offset: u64, part_size: u64) Value.PartIterator {
            const start_vi = vi.partAtOffset(isel, part_offset);
            const start_offset, const start_size = start_vi.position(isel);
            if (part_offset >= start_offset and part_size <= start_size) return .initOne(start_vi);
            const end_vi = vi.partAtOffset(isel, part_size - 1 + part_offset);
            return .{
                .vi = start_vi,
                .remaining = @intCast(@backingInt(end_vi) - @backingInt(start_vi) + 1),
            };
        }
        comptime {
            _ = containingParts;
        }

        fn partAtOffset(vi: Value.Index, isel: *Select, offset: u64) Value.Index {
            const SearchPartIndex = std.math.IntFittingRange(0, Value.max_parts * 2 - 1);
            const value = vi.get(isel);
            var last: SearchPartIndex = value.flags.parts_len_minus_one;
            if (last == 0) return vi;
            var first: SearchPartIndex = 0;
            last += 1;
            while (true) {
                const mid = (first + last) / 2;
                const mid_vi: Value.Index = @fromBackingInt(@intCast(@backingInt(value.parts) + mid));
                if (mid == first) return mid_vi;
                if (offset < mid_vi.get(isel).offset_from_parent) last = mid else first = mid;
            }
        }

        fn field(
            vi: Value.Index,
            ty: ZigType,
            field_offset: u64,
            field_size: u64,
        ) Value.FieldPartIterator {
            assert(field_size > 0);
            return .{
                .vi = vi,
                .ty = ty,
                .field_offset = field_offset,
                .field_size = field_size,
                .next_offset = 0,
            };
        }

        fn ref(initial_vi: Value.Index, isel: *Select) Value.Index {
            var vi = initial_vi;
            while (true) {
                const refs = &vi.get(isel).refs;
                refs.* += 1;
                if (refs.* > 1) return initial_vi;
                switch (vi.parent(isel)) {
                    .unallocated, .stack_slot, .constant => {},
                    .address, .value => |parent_vi| {
                        vi = parent_vi;
                        continue;
                    },
                }
                return initial_vi;
            }
        }

        pub fn deref(initial_vi: Value.Index, isel: *Select) void {
            var vi = initial_vi;
            while (true) {
                const refs = &vi.get(isel).refs;
                refs.* -= 1;
                if (refs.* > 0) return;
                switch (vi.parent(isel)) {
                    .unallocated, .constant => {},
                    .stack_slot => {
                        // reuse stack slot
                    },
                    .address, .value => |parent_vi| {
                        vi = parent_vi;
                        continue;
                    },
                }
                return;
            }
        }

        fn move(dst_vi: Value.Index, isel: *Select, src_ref: Air.Inst.Ref) !void {
            try dst_vi.copy(
                isel,
                isel.air.typeOf(src_ref, &isel.pt.zcu.intern_pool),
                try isel.use(src_ref),
            );
        }

        fn copy(dst_vi: Value.Index, isel: *Select, ty: ZigType, src_vi: Value.Index) !void {
            try dst_vi.copyAdvanced(isel, src_vi, .{
                .dst_ty = ty,
                .dst_vi = dst_vi,
                .dst_offset = 0,
                .src_ty = ty,
                .src_vi = src_vi,
                .src_offset = 0,
            });
        }

        fn copyAdvanced(dst_vi: Value.Index, isel: *Select, src_vi: Value.Index, root: struct {
            dst_ty: ZigType,
            dst_vi: Value.Index,
            dst_offset: u64,
            src_ty: ZigType,
            src_vi: Value.Index,
            src_offset: u64,
        }) !void {
            if (dst_vi == src_vi) return;
            var dst_part_it = dst_vi.parts(isel);
            if (dst_part_it.only()) |dst_part_vi| {
                var src_part_it = src_vi.parts(isel);
                if (src_part_it.only()) |src_part_vi| only: {
                    const src_part_size = src_part_vi.size(isel);
                    if (src_part_size > @as(@TypeOf(src_part_size), if (src_part_vi.isVector(isel)) 16 else 8)) {
                        var subpart_it = root.src_vi.field(root.src_ty, root.src_offset, src_part_size - 1);
                        _ = try subpart_it.next(isel);
                        src_part_it = src_vi.parts(isel);
                        assert(src_part_it.only() == null);
                        break :only;
                    }
                    return src_part_vi.liveOut(isel, try dst_part_vi.defReg(isel) orelse return);
                }
                while (src_part_it.next()) |src_part_vi| {
                    const src_part_offset, const src_part_size = src_part_vi.position(isel);
                    var dst_field_it = root.dst_vi.field(root.dst_ty, root.dst_offset + src_part_offset, src_part_size);
                    while (try dst_field_it.next(isel)) |dst_field| {
                        const field_offset = src_part_offset + dst_field.offset;
                        var src_sub_it = root.src_vi.field(root.src_ty, root.src_offset + field_offset, dst_field.vi.size(isel));
                        while (try src_sub_it.next(isel)) |src_sub| {
                            const sub_offset = field_offset + src_sub.offset;
                            const dst_leaf_vi = if (src_sub.offset == 0 and src_sub.vi.size(isel) == dst_field.vi.size(isel))
                                dst_field.vi
                            else dst_leaf_vi: {
                                var dst_leaf_it = root.dst_vi.field(root.dst_ty, root.dst_offset + sub_offset, src_sub.vi.size(isel));
                                break :dst_leaf_vi (try dst_leaf_it.only(isel)).?;
                            };
                            try dst_leaf_vi.copyAdvanced(isel, src_sub.vi, .{
                                .dst_ty = root.dst_ty,
                                .dst_vi = root.dst_vi,
                                .dst_offset = root.dst_offset + sub_offset,
                                .src_ty = root.src_ty,
                                .src_vi = root.src_vi,
                                .src_offset = root.src_offset + sub_offset,
                            });
                        }
                    }
                }
            } else while (dst_part_it.next()) |dst_part_vi| {
                const dst_part_offset, const dst_part_size = dst_part_vi.position(isel);
                var src_field_it = root.src_vi.field(root.src_ty, root.src_offset + dst_part_offset, dst_part_size);
                while (try src_field_it.next(isel)) |src_field| {
                    const field_offset = dst_part_offset + src_field.offset;
                    var dst_sub_it = root.dst_vi.field(root.dst_ty, root.dst_offset + field_offset, src_field.vi.size(isel));
                    while (try dst_sub_it.next(isel)) |dst_sub| {
                        const sub_offset = field_offset + dst_sub.offset;
                        const src_leaf_vi = if (dst_sub.offset == 0 and dst_sub.vi.size(isel) == src_field.vi.size(isel))
                            src_field.vi
                        else src_leaf_vi: {
                            var src_leaf_it = root.src_vi.field(root.src_ty, root.src_offset + sub_offset, dst_sub.vi.size(isel));
                            break :src_leaf_vi (try src_leaf_it.only(isel)).?;
                        };
                        try dst_sub.vi.copyAdvanced(isel, src_leaf_vi, .{
                            .dst_ty = root.dst_ty,
                            .dst_vi = root.dst_vi,
                            .dst_offset = root.dst_offset + sub_offset,
                            .src_ty = root.src_ty,
                            .src_vi = root.src_vi,
                            .src_offset = root.src_offset + sub_offset,
                        });
                    }
                }
            }
        }

        const AddOrSubtractOptions = struct {
            overflow: Overflow,

            const Overflow = union(enum) {
                @"unreachable",
                panic: Zcu.SimplePanicId,
                wrap,
                ra: Register.Alias,

                fn defCond(overflow: Overflow, isel: *Select, cond: codegen.aarch64.encoding.ConditionCode) !void {
                    switch (overflow) {
                        .@"unreachable" => unreachable,
                        .panic => |panic_id| {
                            const skip_label = isel.instructions.items.len;
                            try isel.emitPanic(panic_id);
                            try isel.emit(.@"b."(
                                cond.invert(),
                                @intCast((isel.instructions.items.len + 1 - skip_label) << 2),
                            ));
                        },
                        .wrap => {},
                        .ra => |overflow_ra| try isel.emit(.csinc(overflow_ra.w(), .wzr, .wzr, cond.invert())),
                    }
                }
            };
        };
        fn addOrSubtract(
            res_vi: Value.Index,
            isel: *Select,
            ty: ZigType,
            lhs_vi: Value.Index,
            op: codegen.aarch64.encoding.Instruction.AddSubtractOp,
            rhs_vi: Value.Index,
            opts: AddOrSubtractOptions,
        ) !void {
            const zcu = isel.pt.zcu;
            if (ty.isVector(zcu)) {
                const ip = &zcu.intern_pool;
                const vector_type = ip.indexToKey(ty.toIntern()).vector_type;
                const elem_ty: ZigType = .fromInterned(vector_type.child);
                const elem_size = elem_ty.abiSize(zcu);
                if (ty.bitSize(zcu) == vector_type.len * elem_size * 8) {
                    var elem_index: u64 = vector_type.len;
                    while (elem_index > 0) {
                        elem_index -= 1;
                        const elem_offset = elem_index * elem_size;
                        var res_elem_it = res_vi.field(ty, elem_offset, elem_size);
                        const res_elem_vi = try res_elem_it.only(isel);
                        var lhs_elem_it = lhs_vi.field(ty, elem_offset, elem_size);
                        const lhs_elem_vi = try lhs_elem_it.only(isel);
                        var rhs_elem_it = rhs_vi.field(ty, elem_offset, elem_size);
                        const rhs_elem_vi = try rhs_elem_it.only(isel);
                        try res_elem_vi.?.addOrSubtract(isel, elem_ty, lhs_elem_vi.?, op, rhs_elem_vi.?, opts);
                    }
                    return;
                }
                if (ty.abiSize(zcu) <= 8 and elem_ty.isAbiInt(zcu) and (opts.overflow == .wrap or opts.overflow == .@"unreachable")) {
                    const elem_int_info = elem_ty.intInfo(zcu);
                    const bits = elem_int_info.bits;
                    const res_ra = try res_vi.defReg(isel) orelse return;
                    var res_lock = isel.lockReg(res_ra);
                    defer res_lock.unlock(isel);
                    const lhs_mat = try lhs_vi.matReg(isel);
                    const rhs_mat = try rhs_vi.matReg(isel);
                    const tmp_lhs_ra = try isel.allocIntReg();
                    defer isel.freeReg(tmp_lhs_ra);
                    const tmp_rhs_ra = try isel.allocIntReg();
                    defer isel.freeReg(tmp_rhs_ra);
                    var elem_index: u64 = vector_type.len;
                    while (elem_index > 0) {
                        elem_index -= 1;
                        const lsb: u6 = @intCast(elem_index * bits);
                        if (elem_index == 0) {
                            try isel.emit(.ubfm(res_ra.x(), tmp_lhs_ra.x(), .{
                                .N = .doubleword,
                                .immr = 0,
                                .imms = @intCast(bits - 1),
                            }));
                        } else {
                            try isel.emit(.bfm(res_ra.x(), tmp_lhs_ra.x(), .{
                                .N = .doubleword,
                                .immr = @intCast((-%lsb) & 63),
                                .imms = @intCast(bits - 1),
                            }));
                        }
                        switch (op) {
                            .add => try isel.emit(.add(tmp_lhs_ra.x(), tmp_lhs_ra.x(), .{ .register = tmp_rhs_ra.x() })),
                            .sub => try isel.emit(.sub(tmp_lhs_ra.x(), tmp_lhs_ra.x(), .{ .register = tmp_rhs_ra.x() })),
                        }
                        try isel.emit(.ubfm(tmp_rhs_ra.x(), rhs_mat.ra.x(), .{
                            .N = .doubleword,
                            .immr = lsb,
                            .imms = @intCast(lsb + bits - 1),
                        }));
                        try isel.emit(.ubfm(tmp_lhs_ra.x(), lhs_mat.ra.x(), .{
                            .N = .doubleword,
                            .immr = lsb,
                            .imms = @intCast(lsb + bits - 1),
                        }));
                    }
                    try rhs_mat.finish(isel);
                    try lhs_mat.finish(isel);
                    return;
                }
            }
            if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ op, isel.fmtType(ty) });
            const int_info = ty.intInfo(zcu);
            if (int_info.bits > 128) return isel.fail("too big {t} {f}", .{ op, isel.fmtType(ty) });
            var part_offset = res_vi.size(isel);
            var need_wrap = switch (opts.overflow) {
                .@"unreachable" => false,
                .panic, .wrap, .ra => true,
            };
            var need_carry = switch (opts.overflow) {
                .@"unreachable", .wrap => false,
                .panic, .ra => true,
            };
            while (part_offset > 0) : (need_wrap = false) {
                const part_size = @min(part_offset, 8);
                part_offset -= part_size;
                var wrapped_res_part_it = res_vi.field(ty, part_offset, part_size);
                const wrapped_res_part_vi = try wrapped_res_part_it.only(isel);
                const wrapped_res_part_ra = wrapped_res_part_ra: {
                    const overflow_ra_lock: RegLock = switch (opts.overflow) {
                        .ra => |ra| isel.lockReg(ra),
                        else => .empty,
                    };
                    defer overflow_ra_lock.unlock(isel);
                    break :wrapped_res_part_ra try wrapped_res_part_vi.?.defReg(isel) orelse if (need_carry) .zr else continue;
                };
                const unwrapped_res_part_ra = unwrapped_res_part_ra: {
                    if (!need_wrap) break :unwrapped_res_part_ra wrapped_res_part_ra;
                    if (int_info.bits % 32 == 0) {
                        try opts.overflow.defCond(isel, switch (int_info.signedness) {
                            .signed => .vs,
                            .unsigned => switch (op) {
                                .add => .cs,
                                .sub => .cc,
                            },
                        });
                        break :unwrapped_res_part_ra wrapped_res_part_ra;
                    }
                    need_carry = false;
                    const wrapped_part_ra, const unwrapped_part_ra = part_ra: switch (opts.overflow) {
                        .@"unreachable" => unreachable,
                        .panic, .ra => switch (int_info.signedness) {
                            .signed => {
                                try opts.overflow.defCond(isel, .ne);
                                const wrapped_part_ra = switch (wrapped_res_part_ra) {
                                    else => |res_part_ra| res_part_ra,
                                    .zr => try isel.allocIntReg(),
                                };
                                errdefer if (wrapped_part_ra != wrapped_res_part_ra) isel.freeReg(wrapped_part_ra);
                                const unwrapped_part_ra = unwrapped_part_ra: {
                                    const wrapped_res_part_lock: RegLock = switch (wrapped_res_part_ra) {
                                        else => |res_part_ra| isel.lockReg(res_part_ra),
                                        .zr => .empty,
                                    };
                                    defer wrapped_res_part_lock.unlock(isel);
                                    break :unwrapped_part_ra try isel.allocIntReg();
                                };
                                errdefer isel.freeReg(unwrapped_part_ra);
                                switch (part_size) {
                                    else => unreachable,
                                    1...4 => try isel.emit(.subs(.wzr, wrapped_part_ra.w(), .{ .register = unwrapped_part_ra.w() })),
                                    5...8 => try isel.emit(.subs(.xzr, wrapped_part_ra.x(), .{ .register = unwrapped_part_ra.x() })),
                                }
                                break :part_ra .{ wrapped_part_ra, unwrapped_part_ra };
                            },
                            .unsigned => {
                                const unwrapped_part_ra = unwrapped_part_ra: {
                                    const wrapped_res_part_lock: RegLock = switch (wrapped_res_part_ra) {
                                        else => |res_part_ra| isel.lockReg(res_part_ra),
                                        .zr => .empty,
                                    };
                                    defer wrapped_res_part_lock.unlock(isel);
                                    break :unwrapped_part_ra try isel.allocIntReg();
                                };
                                errdefer isel.freeReg(unwrapped_part_ra);
                                const bit: u6 = @truncate(int_info.bits);
                                switch (opts.overflow) {
                                    .@"unreachable", .wrap => unreachable,
                                    .panic => |panic_id| {
                                        const skip_label = isel.instructions.items.len;
                                        try isel.emitPanic(panic_id);
                                        try isel.emit(.tbz(
                                            switch (bit) {
                                                0, 32 => unreachable,
                                                1...31 => unwrapped_part_ra.w(),
                                                33...63 => unwrapped_part_ra.x(),
                                            },
                                            bit,
                                            @intCast((isel.instructions.items.len + 1 - skip_label) << 2),
                                        ));
                                    },
                                    .ra => |overflow_ra| try isel.emit(switch (bit) {
                                        0, 32 => unreachable,
                                        1...31 => .ubfm(overflow_ra.w(), unwrapped_part_ra.w(), .{
                                            .N = .word,
                                            .immr = bit,
                                            .imms = bit,
                                        }),
                                        33...63 => .ubfm(overflow_ra.x(), unwrapped_part_ra.x(), .{
                                            .N = .doubleword,
                                            .immr = bit,
                                            .imms = bit,
                                        }),
                                    }),
                                }
                                break :part_ra .{ wrapped_res_part_ra, unwrapped_part_ra };
                            },
                        },
                        .wrap => .{ wrapped_res_part_ra, wrapped_res_part_ra },
                    };
                    defer if (wrapped_part_ra != wrapped_res_part_ra) isel.freeReg(wrapped_part_ra);
                    errdefer if (unwrapped_part_ra != wrapped_res_part_ra) isel.freeReg(unwrapped_part_ra);
                    if (wrapped_part_ra != .zr) try isel.emit(switch (part_size) {
                        else => unreachable,
                        1...4 => switch (int_info.signedness) {
                            .signed => .sbfm(wrapped_part_ra.w(), unwrapped_part_ra.w(), .{
                                .N = .word,
                                .immr = 0,
                                .imms = @truncate(int_info.bits - 1),
                            }),
                            .unsigned => .ubfm(wrapped_part_ra.w(), unwrapped_part_ra.w(), .{
                                .N = .word,
                                .immr = 0,
                                .imms = @truncate(int_info.bits - 1),
                            }),
                        },
                        5...8 => switch (int_info.signedness) {
                            .signed => .sbfm(wrapped_part_ra.x(), unwrapped_part_ra.x(), .{
                                .N = .doubleword,
                                .immr = 0,
                                .imms = @truncate(int_info.bits - 1),
                            }),
                            .unsigned => .ubfm(wrapped_part_ra.x(), unwrapped_part_ra.x(), .{
                                .N = .doubleword,
                                .immr = 0,
                                .imms = @truncate(int_info.bits - 1),
                            }),
                        },
                    });
                    break :unwrapped_res_part_ra unwrapped_part_ra;
                };
                defer if (unwrapped_res_part_ra != wrapped_res_part_ra) isel.freeReg(unwrapped_res_part_ra);
                var lhs_part_it = lhs_vi.field(ty, part_offset, part_size);
                const lhs_part_vi = try lhs_part_it.only(isel);
                const lhs_part_mat = try lhs_part_vi.?.matReg(isel);
                var rhs_part_it = rhs_vi.field(ty, part_offset, part_size);
                const rhs_part_vi = try rhs_part_it.only(isel);
                const rhs_part_mat = try rhs_part_vi.?.matReg(isel);
                try isel.emit(switch (part_size) {
                    else => unreachable,
                    1...4 => switch (op) {
                        .add => switch (part_offset) {
                            0 => switch (need_carry) {
                                false => .add(unwrapped_res_part_ra.w(), lhs_part_mat.ra.w(), .{ .register = rhs_part_mat.ra.w() }),
                                true => .adds(unwrapped_res_part_ra.w(), lhs_part_mat.ra.w(), .{ .register = rhs_part_mat.ra.w() }),
                            },
                            else => switch (need_carry) {
                                false => .adc(unwrapped_res_part_ra.w(), lhs_part_mat.ra.w(), rhs_part_mat.ra.w()),
                                true => .adcs(unwrapped_res_part_ra.w(), lhs_part_mat.ra.w(), rhs_part_mat.ra.w()),
                            },
                        },
                        .sub => switch (part_offset) {
                            0 => switch (need_carry) {
                                false => .sub(unwrapped_res_part_ra.w(), lhs_part_mat.ra.w(), .{ .register = rhs_part_mat.ra.w() }),
                                true => .subs(unwrapped_res_part_ra.w(), lhs_part_mat.ra.w(), .{ .register = rhs_part_mat.ra.w() }),
                            },
                            else => switch (need_carry) {
                                false => .sbc(unwrapped_res_part_ra.w(), lhs_part_mat.ra.w(), rhs_part_mat.ra.w()),
                                true => .sbcs(unwrapped_res_part_ra.w(), lhs_part_mat.ra.w(), rhs_part_mat.ra.w()),
                            },
                        },
                    },
                    5...8 => switch (op) {
                        .add => switch (part_offset) {
                            0 => switch (need_carry) {
                                false => .add(unwrapped_res_part_ra.x(), lhs_part_mat.ra.x(), .{ .register = rhs_part_mat.ra.x() }),
                                true => .adds(unwrapped_res_part_ra.x(), lhs_part_mat.ra.x(), .{ .register = rhs_part_mat.ra.x() }),
                            },
                            else => switch (need_carry) {
                                false => .adc(unwrapped_res_part_ra.x(), lhs_part_mat.ra.x(), rhs_part_mat.ra.x()),
                                true => .adcs(unwrapped_res_part_ra.x(), lhs_part_mat.ra.x(), rhs_part_mat.ra.x()),
                            },
                        },
                        .sub => switch (part_offset) {
                            0 => switch (need_carry) {
                                false => .sub(unwrapped_res_part_ra.x(), lhs_part_mat.ra.x(), .{ .register = rhs_part_mat.ra.x() }),
                                true => .subs(unwrapped_res_part_ra.x(), lhs_part_mat.ra.x(), .{ .register = rhs_part_mat.ra.x() }),
                            },
                            else => switch (need_carry) {
                                false => .sbc(unwrapped_res_part_ra.x(), lhs_part_mat.ra.x(), rhs_part_mat.ra.x()),
                                true => .sbcs(unwrapped_res_part_ra.x(), lhs_part_mat.ra.x(), rhs_part_mat.ra.x()),
                            },
                        },
                    },
                });
                try rhs_part_mat.finish(isel);
                try lhs_part_mat.finish(isel);
                need_carry = true;
            }
        }

        const MemoryAccessOptions = struct {
            root_vi: Value.Index = .free,
            offset: u64 = 0,
            field_offset: u64 = 0,
            @"volatile": bool = false,
            split: bool = true,
            in_place: bool = false,
            wrap: ?std.lang.Type.Int = null,
            expected_live_registers: *const LiveRegisters = &.initFill(.free),
        };

        fn load(
            vi: Value.Index,
            isel: *Select,
            root_ty: ZigType,
            base_ra: Register.Alias,
            opts: MemoryAccessOptions,
        ) !bool {
            const root_vi = switch (opts.root_vi) {
                _ => |root_vi| root_vi,
                .allocating => unreachable,
                .free => vi,
            };
            var part_it = vi.parts(isel);
            if (part_it.only()) |part_vi| only: {
                const part_size = part_vi.size(isel);
                const part_is_vector = part_vi.isVector(isel);
                if (part_size > @as(@TypeOf(part_size), if (part_is_vector) 16 else 8)) {
                    if (!opts.split) return false;
                    var subpart_it = root_vi.field(root_ty, opts.field_offset, part_size - 1);
                    _ = try subpart_it.next(isel);
                    part_it = vi.parts(isel);
                    assert(part_it.only() == null);
                    break :only;
                }
                const part_ra = if (try part_vi.defRegAdvanced(isel, .{ .in_place = opts.in_place })) |part_ra|
                    part_ra
                else if (opts.@"volatile")
                    .zr
                else
                    return false;
                const part_lock: RegLock = switch (part_ra) {
                    else => isel.lockReg(part_ra),
                    .zr => .empty,
                };
                defer switch (opts.expected_live_registers.get(part_ra)) {
                    _ => {},
                    .allocating => unreachable,
                    .free => part_lock.unlock(isel),
                };
                if (opts.wrap) |int_info| switch (int_info.bits) {
                    else => unreachable,
                    1...7, 9...15, 17...31 => |bits| try isel.emit(switch (int_info.signedness) {
                        .signed => .sbfm(part_ra.w(), part_ra.w(), .{
                            .N = .word,
                            .immr = 0,
                            .imms = @intCast(bits - 1),
                        }),
                        .unsigned => .ubfm(part_ra.w(), part_ra.w(), .{
                            .N = .word,
                            .immr = 0,
                            .imms = @intCast(bits - 1),
                        }),
                    }),
                    8, 16, 32 => |bits| if (part_size * 8 > bits) try isel.emit(switch (int_info.signedness) {
                        .signed => .sbfm(part_ra.x(), part_ra.x(), .{
                            .N = .doubleword,
                            .immr = 0,
                            .imms = @intCast(bits - 1),
                        }),
                        .unsigned => .ubfm(part_ra.x(), part_ra.x(), .{
                            .N = .doubleword,
                            .immr = 0,
                            .imms = @intCast(bits - 1),
                        }),
                    }),
                    33...63 => |bits| try isel.emit(switch (int_info.signedness) {
                        .signed => .sbfm(part_ra.x(), part_ra.x(), .{
                            .N = .doubleword,
                            .immr = 0,
                            .imms = @intCast(bits - 1),
                        }),
                        .unsigned => .ubfm(part_ra.x(), part_ra.x(), .{
                            .N = .doubleword,
                            .immr = 0,
                            .imms = @intCast(bits - 1),
                        }),
                    }),
                    64 => {},
                };
                try isel.loadReg(part_ra, part_size, part_vi.signedness(isel), base_ra, opts.offset);
                return true;
            }
            var used = false;
            while (part_it.next()) |part_vi| used |= try part_vi.load(isel, root_ty, base_ra, .{
                .root_vi = root_vi,
                .offset = opts.offset + part_vi.get(isel).offset_from_parent,
                .field_offset = opts.field_offset + part_vi.get(isel).offset_from_parent,
                .@"volatile" = opts.@"volatile",
                .split = opts.split,
                .in_place = opts.in_place,
                .wrap = switch (part_it.remaining) {
                    else => null,
                    0 => if (opts.wrap) |wrap| .{
                        .signedness = wrap.signedness,
                        .bits = @intCast(wrap.bits - 8 * part_vi.position(isel)[0]),
                    } else null,
                },
                .expected_live_registers = opts.expected_live_registers,
            });
            return used;
        }

        fn store(
            vi: Value.Index,
            isel: *Select,
            root_ty: ZigType,
            base_ra: Register.Alias,
            opts: MemoryAccessOptions,
        ) !void {
            const root_vi = switch (opts.root_vi) {
                _ => |root_vi| root_vi,
                .allocating => unreachable,
                .free => vi,
            };
            var part_it = vi.parts(isel);
            if (part_it.only()) |part_vi| only: {
                const part_size = part_vi.size(isel);
                const part_is_vector = part_vi.isVector(isel);
                if (part_size > @as(@TypeOf(part_size), if (part_is_vector) 16 else 8)) {
                    if (!opts.split) return;
                    var subpart_it = root_vi.field(root_ty, opts.field_offset, part_size - 1);
                    _ = try subpart_it.next(isel);
                    part_it = vi.parts(isel);
                    assert(part_it.only() == null);
                    break :only;
                }
                const part_mat = try part_vi.matReg(isel);
                try isel.storeReg(part_mat.ra, part_size, base_ra, opts.offset);
                return part_mat.finish(isel);
            }
            while (part_it.next()) |part_vi| try part_vi.store(isel, root_ty, base_ra, .{
                .root_vi = root_vi,
                .offset = opts.offset + part_vi.get(isel).offset_from_parent,
                .field_offset = opts.field_offset + part_vi.get(isel).offset_from_parent,
                .@"volatile" = opts.@"volatile",
                .split = opts.split,
                .wrap = switch (part_it.remaining) {
                    else => null,
                    0 => if (opts.wrap) |wrap| .{
                        .signedness = wrap.signedness,
                        .bits = @intCast(wrap.bits - 8 * part_vi.position(isel)[0]),
                    } else null,
                },
                .expected_live_registers = opts.expected_live_registers,
            });
        }

        fn mat(vi: Value.Index, isel: *Select) !void {
            if (false) {
                var part_it: Value.PartIterator = if (vi.size(isel) > 8) vi.parts(isel) else .initOne(vi);
                if (part_it.only()) |part_vi| only: {
                    const mat_ra = mat_ra: {
                        if (part_vi.register(isel)) |mat_ra| {
                            part_vi.get(isel).location_payload.small.register = .zr;
                            const live_vi = isel.live_registers.getPtr(mat_ra);
                            assert(live_vi.* == part_vi);
                            live_vi.* = .allocating;
                            break :mat_ra mat_ra;
                        }
                        if (part_vi.hint(isel)) |hint_ra| {
                            const live_vi = isel.live_registers.getPtr(hint_ra);
                            if (live_vi.* == .free) {
                                live_vi.* = .allocating;
                                isel.saved_registers.insert(hint_ra);
                                break :mat_ra hint_ra;
                            }
                        }
                        const part_size = part_vi.size(isel);
                        const part_is_vector = part_vi.isVector(isel);
                        if (part_size <= @as(@TypeOf(part_size), if (part_is_vector) 16 else 8))
                            switch (if (part_is_vector) isel.tryAllocVecReg() else isel.tryAllocIntReg()) {
                                .allocated => |ra| break :mat_ra ra,
                                .fill_candidate, .out_of_registers => {},
                            };
                        _, const parent_vi = vi.valueParent(isel);
                        switch (parent_vi.parent(isel)) {
                            .unallocated => parent_vi.setParent(isel, .{ .stack_slot = parent_vi.allocStackSlot(isel) }),
                            else => {},
                        }
                        break :only;
                    };
                    assert(isel.live_registers.get(mat_ra) == .allocating);
                    try Value.Materialize.finish(.{ .vi = part_vi, .ra = mat_ra }, isel);
                } else while (part_it.next()) |part_vi| try part_vi.mat(isel);
            } else {
                _, const parent_vi = vi.valueParent(isel);
                switch (parent_vi.parent(isel)) {
                    .unallocated => parent_vi.setParent(isel, .{ .stack_slot = parent_vi.allocStackSlot(isel) }),
                    else => {},
                }
            }
        }

        fn matReg(vi: Value.Index, isel: *Select) !Value.Materialize {
            const mat_ra = mat_ra: {
                if (vi.register(isel)) |mat_ra| {
                    vi.get(isel).location_payload.small.register = .zr;
                    const live_vi = isel.live_registers.getPtr(mat_ra);
                    assert(live_vi.* == vi);
                    live_vi.* = .allocating;
                    break :mat_ra mat_ra;
                }
                if (vi.hint(isel)) |hint_ra| {
                    const live_vi = isel.live_registers.getPtr(hint_ra);
                    if (live_vi.* == .free) {
                        live_vi.* = .allocating;
                        isel.saved_registers.insert(hint_ra);
                        break :mat_ra hint_ra;
                    }
                }
                break :mat_ra if (vi.isVector(isel)) try isel.allocVecReg() else try isel.allocIntReg();
            };
            assert(isel.live_registers.get(mat_ra) == .allocating);
            return .{ .vi = vi, .ra = mat_ra };
        }

        fn defAddr(
            def_vi: Value.Index,
            isel: *Select,
            root_ty: ZigType,
            opts: struct {
                root_vi: Value.Index = .free,
                wrap: ?std.lang.Type.Int = null,
                expected_live_registers: *const LiveRegisters = &.initFill(.free),
            },
        ) !?void {
            if (!def_vi.isUsed(isel)) return null;
            const offset_from_parent: i65, const parent_vi = def_vi.valueParent(isel);
            const stack_slot = switch (parent_vi.parent(isel)) {
                .unallocated => stack_slot: {
                    const stack_slot = parent_vi.allocStackSlot(isel);
                    parent_vi.setParent(isel, .{ .stack_slot = stack_slot });
                    break :stack_slot stack_slot;
                },
                .stack_slot => |stack_slot| stack_slot,
                else => unreachable,
            };
            _ = try def_vi.load(isel, root_ty, stack_slot.base, .{
                .root_vi = opts.root_vi,
                .offset = @intCast(stack_slot.offset + offset_from_parent),
                .field_offset = @intCast(offset_from_parent),
                .split = false,
                .in_place = true,
                .wrap = opts.wrap,
                .expected_live_registers = opts.expected_live_registers,
            });
        }

        fn defReg(def_vi: Value.Index, isel: *Select) !?Register.Alias {
            return def_vi.defRegAdvanced(isel, .{});
        }

        fn splitAncestorRegs(def_vi: Value.Index, isel: *Select) !void {
            var vi = def_vi;
            while (true) {
                switch (vi.parent(isel)) {
                    else => return,
                    .value => |parent_vi| vi = parent_vi,
                }
                if (vi.register(isel)) |ra| {
                    vi.get(isel).location_payload.small.register = .zr;
                    const live_vi = isel.live_registers.getPtr(ra);
                    assert(live_vi.* == vi);
                    live_vi.* = .allocating;
                    var part_it = vi.parts(isel);
                    assert(part_it.only() == null);

                    const vi_size = vi.size(isel);
                    if (ra.isVector()) {
                        var parts_buf: [Value.max_parts]Value.Index = undefined;
                        var parts_len: usize = 0;
                        while (part_it.next()) |part_vi| {
                            parts_buf[parts_len] = part_vi;
                            parts_len += 1;
                        }
                        var lane_end: usize = parts_len;
                        var lane_index: u1 = @intFromBool(vi_size > 8);
                        while (true) {
                            const lane_base_offset: u64 = @as(u64, lane_index) * 8;
                            var lane_start = lane_end;
                            while (lane_start > 0 and parts_buf[lane_start - 1].get(isel).offset_from_parent >= lane_base_offset) {
                                lane_start -= 1;
                            }
                            assert(lane_start < lane_end);
                            const first_part_vi = parts_buf[lane_start];
                            assert(first_part_vi.get(isel).offset_from_parent == lane_base_offset);
                            const first_part_mat = try first_part_vi.matReg(isel);
                            const lane_ra = if (first_part_mat.ra.isVector()) try isel.allocIntReg() else first_part_mat.ra;
                            defer if (lane_ra != first_part_mat.ra) isel.freeReg(lane_ra);
                            try isel.emit(switch (lane_index) {
                                0 => switch (vi_size) {
                                    else => unreachable,
                                    1...4 => .fmov(ra.s(), .{ .register = lane_ra.w() }),
                                    5...16 => .fmov(ra.d(), .{ .register = lane_ra.x() }),
                                },
                                1 => .fmov(ra.@"d[]"(1), .{ .register = lane_ra.x() }),
                            });
                            for (parts_buf[lane_start + 1 .. lane_end]) |part_vi| {
                                const part_offset, const part_size = part_vi.position(isel);
                                const lane_offset = part_offset - lane_base_offset;
                                const part_mat = try part_vi.matReg(isel);
                                const part_ra = if (part_mat.ra.isVector()) try isel.allocIntReg() else part_mat.ra;
                                defer if (part_ra != part_mat.ra) isel.freeReg(part_ra);
                                try isel.emit(switch (vi_size) {
                                    else => unreachable,
                                    1...4 => .bfm(lane_ra.w(), part_ra.w(), .{
                                        .N = .word,
                                        .immr = @as(u5, @truncate(32 - 8 * lane_offset)),
                                        .imms = @intCast(8 * part_size - 1),
                                    }),
                                    5...16 => .bfm(lane_ra.x(), part_ra.x(), .{
                                        .N = .doubleword,
                                        .immr = @as(u6, @truncate(64 - 8 * lane_offset)),
                                        .imms = @intCast(8 * part_size - 1),
                                    }),
                                });
                                if (part_ra != part_mat.ra) try isel.emit(switch (part_size) {
                                    else => unreachable,
                                    2 => if (isel.target.cpu.has(.aarch64, .fullfp16))
                                        .fmov(part_ra.w(), .{ .register = part_mat.ra.h() })
                                    else
                                        .umov(part_ra.w(), part_mat.ra.@"h[]"(0)),
                                    4 => .fmov(part_ra.w(), .{ .register = part_mat.ra.s() }),
                                    8 => .fmov(part_ra.x(), .{ .register = part_mat.ra.d() }),
                                });
                                try part_mat.finish(isel);
                            }
                            if (lane_ra != first_part_mat.ra) {
                                const first_part_size = first_part_vi.size(isel);
                                try isel.emit(switch (first_part_size) {
                                    else => unreachable,
                                    2 => if (isel.target.cpu.has(.aarch64, .fullfp16))
                                        .fmov(lane_ra.w(), .{ .register = first_part_mat.ra.h() })
                                    else
                                        .umov(lane_ra.w(), first_part_mat.ra.@"h[]"(0)),
                                    4 => .fmov(lane_ra.w(), .{ .register = first_part_mat.ra.s() }),
                                    8 => .fmov(lane_ra.x(), .{ .register = first_part_mat.ra.d() }),
                                });
                            }
                            try first_part_mat.finish(isel);
                            lane_end = lane_start;
                            if (lane_index == 0) break;
                            lane_index -= 1;
                        }
                        live_vi.* = .free;
                        vi = def_vi;
                        continue;
                    }

                    const first_part_vi = part_it.next().?;
                    const first_part_value = first_part_vi.get(isel);
                    assert(first_part_value.offset_from_parent == 0);

                    while (part_it.next()) |part_vi| {
                        const part_offset, const part_size = part_vi.position(isel);
                        const part_mat = try part_vi.matReg(isel);
                        const part_ra = if (part_mat.ra.isVector()) try isel.allocIntReg() else part_mat.ra;
                        defer if (part_ra != part_mat.ra) isel.freeReg(part_ra);
                        try isel.emit(switch (vi_size) {
                            else => unreachable,
                            1...4 => .bfm(ra.w(), part_ra.w(), .{
                                .N = .word,
                                .immr = @as(u5, @truncate(32 - 8 * part_offset)),
                                .imms = @intCast(8 * part_size - 1),
                            }),
                            5...8 => .bfm(ra.x(), part_ra.x(), .{
                                .N = .doubleword,
                                .immr = @as(u6, @truncate(64 - 8 * part_offset)),
                                .imms = @intCast(8 * part_size - 1),
                            }),
                        });
                        if (part_ra != part_mat.ra) try isel.emit(switch (part_size) {
                            else => unreachable,
                            2 => if (isel.target.cpu.has(.aarch64, .fullfp16))
                                .fmov(part_ra.w(), .{ .register = part_mat.ra.h() })
                            else
                                .umov(part_ra.w(), part_mat.ra.@"h[]"(0)),
                            4 => .fmov(part_ra.w(), .{ .register = part_mat.ra.s() }),
                            8 => .fmov(part_ra.x(), .{ .register = part_mat.ra.d() }),
                        });
                        try part_mat.finish(isel);
                    }
                    first_part_value.location_payload.small.register = ra;
                    live_vi.* = first_part_vi;
                    vi = def_vi;
                    continue;
                }
            }
        }

        fn defRegAdvanced(def_vi: Value.Index, isel: *Select, opts: struct {
            in_place: bool = false,
        }) !?Register.Alias {
            try def_vi.splitAncestorRegs(isel);
            var vi = def_vi;
            var offset: i65 = 0;
            var def_ra: ?Register.Alias = null;
            if (def_vi.register(isel) == null and def_vi.hasRegisterRecursive(isel)) {
                const ra = if (def_vi.isVector(isel)) try isel.allocVecReg() else try isel.allocIntReg();
                try def_vi.spillReg(isel, ra, 0, &.initFill(.free));
                isel.freeReg(ra);
                def_ra = ra;
            }
            while (true) {
                if (vi.register(isel)) |ra| {
                    assert(vi == def_vi);
                    vi.get(isel).location_payload.small.register = .zr;
                    const live_vi = isel.live_registers.getPtr(ra);
                    assert(live_vi.* == vi);
                    live_vi.* = .free;
                    def_ra = ra;
                }
                offset += vi.get(isel).offset_from_parent;
                switch (vi.parent(isel)) {
                    else => unreachable,
                    .unallocated => {
                        if (def_ra) |int_ra| if (def_vi.isVector(isel) and !int_ra.isVector()) {
                            const vec_ra = try isel.allocVecReg();
                            defer isel.freeReg(vec_ra);
                            try isel.emit(switch (def_vi.size(isel)) {
                                else => unreachable,
                                2 => if (isel.target.cpu.has(.aarch64, .fullfp16))
                                    .fmov(int_ra.w(), .{ .register = vec_ra.h() })
                                else
                                    .umov(int_ra.w(), vec_ra.@"h[]"(0)),
                                4 => .fmov(int_ra.w(), .{ .register = vec_ra.s() }),
                                8 => .fmov(int_ra.x(), .{ .register = vec_ra.d() }),
                            });
                            return vec_ra;
                        };
                        return def_ra;
                    },
                    .stack_slot => |stack_slot| {
                        if (opts.in_place) {
                            if (def_ra) |int_ra| if (def_vi.isVector(isel) and !int_ra.isVector()) {
                                const vec_ra = try isel.allocVecReg();
                                defer isel.freeReg(vec_ra);
                                try isel.emit(switch (def_vi.size(isel)) {
                                    else => unreachable,
                                    2 => if (isel.target.cpu.has(.aarch64, .fullfp16))
                                        .fmov(int_ra.w(), .{ .register = vec_ra.h() })
                                    else
                                        .umov(int_ra.w(), vec_ra.@"h[]"(0)),
                                    4 => .fmov(int_ra.w(), .{ .register = vec_ra.s() }),
                                    8 => .fmov(int_ra.x(), .{ .register = vec_ra.d() }),
                                });
                                return vec_ra;
                            };
                            return def_ra;
                        }
                        offset += stack_slot.offset;
                        const def_is_vector = def_vi.isVector(isel);
                        const ra = if (def_ra) |ra| ra: {
                            assert(isel.live_registers.get(ra) == .free);
                            isel.live_registers.getPtr(ra).* = .allocating;
                            break :ra ra;
                        } else if (def_is_vector) try isel.allocVecReg() else try isel.allocIntReg();
                        defer isel.freeReg(ra);
                        try isel.storeReg(ra, def_vi.size(isel), stack_slot.base, offset);
                        if (def_is_vector and !ra.isVector()) {
                            const vec_ra = try isel.allocVecReg();
                            defer isel.freeReg(vec_ra);
                            try isel.emit(switch (def_vi.size(isel)) {
                                else => unreachable,
                                2 => if (isel.target.cpu.has(.aarch64, .fullfp16))
                                    .fmov(ra.w(), .{ .register = vec_ra.h() })
                                else
                                    .umov(ra.w(), vec_ra.@"h[]"(0)),
                                4 => .fmov(ra.w(), .{ .register = vec_ra.s() }),
                                8 => .fmov(ra.x(), .{ .register = vec_ra.d() }),
                            });
                            return vec_ra;
                        }
                        return ra;
                    },
                    .value => |parent_vi| vi = parent_vi,
                }
            }
        }

        pub fn defUndef(def_vi: Value.Index, isel: *Select, root_ty: ZigType, opts: struct {
            root_vi: Value.Index = .free,
            offset: u64 = 0,
            split: bool = true,
        }) !void {
            const root_vi = switch (opts.root_vi) {
                _ => |root_vi| root_vi,
                .allocating => unreachable,
                .free => def_vi,
            };
            var part_it = def_vi.parts(isel);
            if (part_it.only()) |part_vi| only: {
                const part_size = part_vi.size(isel);
                const part_is_vector = part_vi.isVector(isel);
                if (part_size > @as(@TypeOf(part_size), if (part_is_vector) 16 else 8)) {
                    if (!opts.split) return;
                    var subpart_it = root_vi.field(root_ty, opts.offset, part_size - 1);
                    _ = try subpart_it.next(isel);
                    part_it = def_vi.parts(isel);
                    assert(part_it.only() == null);
                    break :only;
                }
                return if (try part_vi.defReg(isel)) |part_ra| try isel.emit(if (part_is_vector)
                    .movi(switch (part_size) {
                        else => unreachable,
                        1...8 => part_ra.@"8b"(),
                        9...16 => part_ra.@"16b"(),
                    }, 0xaa, .{ .lsl = 0 })
                else switch (part_size) {
                    else => unreachable,
                    1...4 => .orr(part_ra.w(), .wzr, .{ .immediate = .{
                        .N = .word,
                        .immr = 0b000001,
                        .imms = 0b111100,
                    } }),
                    5...8 => .orr(part_ra.x(), .xzr, .{ .immediate = .{
                        .N = .word,
                        .immr = 0b000001,
                        .imms = 0b111100,
                    } }),
                });
            }
            while (part_it.next()) |part_vi| try part_vi.defUndef(isel, root_ty, .{
                .root_vi = root_vi,
                .offset = opts.offset + part_vi.get(isel).offset_from_parent,
                .split = opts.split,
            });
        }

        pub fn liveIn(
            vi: Value.Index,
            isel: *Select,
            src_ra: Register.Alias,
            expected_live_registers: *const LiveRegisters,
        ) !void {
            try vi.splitAncestorRegs(isel);
            const src_live_vi = isel.live_registers.getPtr(src_ra);
            if (vi.register(isel)) |dst_ra| {
                const dst_live_vi = isel.live_registers.getPtr(dst_ra);
                assert(dst_live_vi.* == vi);
                if (dst_ra == src_ra) {
                    src_live_vi.* = .allocating;
                    return;
                }
                dst_live_vi.* = .allocating;
                if (try isel.fill(src_ra)) {
                    assert(src_live_vi.* == .free);
                    src_live_vi.* = .allocating;
                }
                assert(src_live_vi.* == .allocating);
                try isel.emit(switch (dst_ra.isVector()) {
                    false => switch (src_ra.isVector()) {
                        false => switch (vi.size(isel)) {
                            else => unreachable,
                            1...4 => .orr(dst_ra.w(), .wzr, .{ .register = src_ra.w() }),
                            5...8 => .orr(dst_ra.x(), .xzr, .{ .register = src_ra.x() }),
                        },
                        true => switch (vi.size(isel)) {
                            else => unreachable,
                            2 => if (isel.target.cpu.has(.aarch64, .fullfp16))
                                .fmov(dst_ra.w(), .{ .register = src_ra.h() })
                            else
                                .umov(dst_ra.w(), src_ra.@"h[]"(0)),
                            4 => .fmov(dst_ra.w(), .{ .register = src_ra.s() }),
                            8 => .fmov(dst_ra.x(), .{ .register = src_ra.d() }),
                        },
                    },
                    true => switch (src_ra.isVector()) {
                        false => size: switch (vi.size(isel)) {
                            else => unreachable,
                            2 => if (isel.target.cpu.has(.aarch64, .fullfp16))
                                .fmov(dst_ra.h(), .{ .register = src_ra.w() })
                            else
                                continue :size 4,
                            4 => .fmov(dst_ra.s(), .{ .register = src_ra.w() }),
                            8 => .fmov(dst_ra.d(), .{ .register = src_ra.x() }),
                        },
                        true => switch (vi.size(isel)) {
                            else => unreachable,
                            2 => if (isel.target.cpu.has(.aarch64, .fullfp16))
                                .fmov(dst_ra.h(), .{ .register = src_ra.h() })
                            else
                                .dup(dst_ra.h(), src_ra.@"h[]"(0)),
                            4 => .fmov(dst_ra.s(), .{ .register = src_ra.s() }),
                            8 => .fmov(dst_ra.d(), .{ .register = src_ra.d() }),
                            16 => .orr(dst_ra.@"16b"(), src_ra.@"16b"(), .{ .register = src_ra.@"16b"() }),
                        },
                    },
                });
                assert(dst_live_vi.* == .allocating);
                dst_live_vi.* = switch (expected_live_registers.get(dst_ra)) {
                    _ => .allocating,
                    .allocating => .allocating,
                    .free => .free,
                };
            } else {
                if (try isel.fill(src_ra)) {
                    assert(src_live_vi.* == .free);
                    src_live_vi.* = .allocating;
                }
                if (vi.hasRegisterRecursive(isel)) {
                    try vi.spillReg(isel, src_ra, 0, expected_live_registers);
                }
            }
            assert(src_live_vi.* == .allocating);
            vi.get(isel).location_payload.small.register = src_ra;
        }

        pub fn defLiveIn(
            vi: Value.Index,
            isel: *Select,
            src_ra: Register.Alias,
            expected_live_registers: *const LiveRegisters,
        ) !void {
            try vi.liveIn(isel, src_ra, expected_live_registers);
            const offset_from_parent, const parent_vi = vi.valueParent(isel);
            switch (parent_vi.parent(isel)) {
                .unallocated => {},
                .stack_slot => |stack_slot| if (stack_slot.base != Register.Alias.fp) try isel.storeReg(
                    src_ra,
                    vi.size(isel),
                    stack_slot.base,
                    @as(i65, stack_slot.offset) + offset_from_parent,
                ),
                else => unreachable,
            }
            try vi.spillReg(isel, src_ra, 0, expected_live_registers);
            vi.get(isel).location_payload.small.register = .zr;
        }

        fn spillReg(
            vi: Value.Index,
            isel: *Select,
            src_ra: Register.Alias,
            start_offset: u64,
            expected_live_registers: *const LiveRegisters,
        ) !void {
            assert(isel.live_registers.get(src_ra) == .allocating);
            var part_it = vi.parts(isel);
            if (part_it.only()) |part_vi| {
                const dst_ra = part_vi.register(isel) orelse return;
                if (dst_ra == src_ra) return;
                const part_size = part_vi.size(isel);
                const part_ra = if (part_vi.isVector(isel)) try isel.allocIntReg() else dst_ra;
                defer if (part_ra != dst_ra) isel.freeReg(part_ra);
                if (part_ra != dst_ra) try isel.emit(part_size: switch (part_size) {
                    else => unreachable,
                    2 => if (isel.target.cpu.has(.aarch64, .fullfp16))
                        .fmov(dst_ra.h(), .{ .register = part_ra.w() })
                    else
                        continue :part_size 4,
                    4 => .fmov(dst_ra.s(), .{ .register = part_ra.w() }),
                    8 => .fmov(dst_ra.d(), .{ .register = part_ra.x() }),
                });
                const lane_offset = if (src_ra.isVector()) start_offset % 8 else start_offset;
                const src_int_ra = if (src_ra.isVector()) part_ra else src_ra;
                try isel.emit(switch (lane_offset + part_size) {
                    else => unreachable,
                    1...4 => |end_offset| switch (part_vi.signedness(isel)) {
                        .signed => .sbfm(part_ra.w(), src_int_ra.w(), .{
                            .N = .word,
                            .immr = @intCast(8 * lane_offset),
                            .imms = @intCast(8 * end_offset - 1),
                        }),
                        .unsigned => .ubfm(part_ra.w(), src_int_ra.w(), .{
                            .N = .word,
                            .immr = @intCast(8 * lane_offset),
                            .imms = @intCast(8 * end_offset - 1),
                        }),
                    },
                    5...8 => |end_offset| switch (part_vi.signedness(isel)) {
                        .signed => .sbfm(part_ra.x(), src_int_ra.x(), .{
                            .N = .doubleword,
                            .immr = @intCast(8 * lane_offset),
                            .imms = @intCast(8 * end_offset - 1),
                        }),
                        .unsigned => .ubfm(part_ra.x(), src_int_ra.x(), .{
                            .N = .doubleword,
                            .immr = @intCast(8 * lane_offset),
                            .imms = @intCast(8 * end_offset - 1),
                        }),
                    },
                });
                if (src_ra.isVector()) try isel.emit(switch (start_offset + part_size) {
                    else => unreachable,
                    1...4 => .fmov(part_ra.w(), .{ .register = src_ra.s() }),
                    5...8 => .fmov(part_ra.x(), .{ .register = src_ra.d() }),
                    9...16 => .fmov(part_ra.x(), .{ .register = src_ra.@"d[]"(1) }),
                });
                const value_ra = &part_vi.get(isel).location_payload.small.register;
                assert(value_ra.* == dst_ra);
                value_ra.* = .zr;
                const dst_live_vi = isel.live_registers.getPtr(dst_ra);
                assert(dst_live_vi.* == part_vi);
                dst_live_vi.* = switch (expected_live_registers.get(dst_ra)) {
                    _ => .allocating,
                    .allocating => .allocating,
                    .free => .free,
                };
            } else while (part_it.next()) |part_vi| try part_vi.spillReg(
                isel,
                src_ra,
                start_offset + part_vi.get(isel).offset_from_parent,
                expected_live_registers,
            );
        }

        fn liveOut(vi: Value.Index, isel: *Select, ra: Register.Alias) !void {
            assert(try isel.fill(ra));
            const live_vi = isel.live_registers.getPtr(ra);
            assert(live_vi.* == .free);
            live_vi.* = .allocating;
            try Value.Materialize.finish(.{ .vi = vi, .ra = ra }, isel);
        }

        fn allocStackSlot(vi: Value.Index, isel: *Select) Value.Indirect {
            const slot_align = vi.alignment(isel);
            isel.stack_align = isel.stack_align.maxStrict(slot_align);
            const offset = slot_align.forward(isel.stack_size);
            isel.stack_size = @intCast(offset + vi.size(isel));
            tracking_log.debug("${d} -> [sp, #0x{x}]", .{ @backingInt(vi), @abs(offset) });
            return .{
                .base = .sp,
                .offset = @intCast(offset),
            };
        }

        fn address(initial_vi: Value.Index, isel: *Select, initial_offset: u64, ptr_ra: Register.Alias) !void {
            var vi = initial_vi;
            var offset: i65 = vi.get(isel).offset_from_parent + initial_offset;
            parent: switch (vi.parent(isel)) {
                .unallocated => {
                    const stack_slot = vi.allocStackSlot(isel);
                    vi.setParent(isel, .{ .stack_slot = stack_slot });
                    continue :parent .{ .stack_slot = stack_slot };
                },
                .stack_slot => |stack_slot| {
                    offset += stack_slot.offset;
                    const lo12: u12 = @truncate(@abs(offset) >> 0);
                    const hi12: u12 = @intCast(@abs(offset) >> 12);
                    if (hi12 > 0) try isel.emit(if (offset >= 0) .add(
                        ptr_ra.x(),
                        if (lo12 > 0) ptr_ra.x() else stack_slot.base.x(),
                        .{ .shifted_immediate = .{ .immediate = hi12, .lsl = .@"12" } },
                    ) else .sub(
                        ptr_ra.x(),
                        if (lo12 > 0) ptr_ra.x() else stack_slot.base.x(),
                        .{ .shifted_immediate = .{ .immediate = hi12, .lsl = .@"12" } },
                    ));
                    if (lo12 > 0 or hi12 == 0) try isel.emit(if (offset >= 0) .add(
                        ptr_ra.x(),
                        stack_slot.base.x(),
                        .{ .immediate = lo12 },
                    ) else .sub(
                        ptr_ra.x(),
                        stack_slot.base.x(),
                        .{ .immediate = lo12 },
                    ));
                },
                .address => |address_vi| {
                    if (offset != 0) {
                        const lo12: u12 = @truncate(@abs(offset) >> 0);
                        const hi12: u12 = @intCast(@abs(offset) >> 12);
                        if (hi12 > 0) try isel.emit(if (offset >= 0) .add(
                            ptr_ra.x(),
                            ptr_ra.x(),
                            .{ .shifted_immediate = .{ .immediate = hi12, .lsl = .@"12" } },
                        ) else .sub(
                            ptr_ra.x(),
                            ptr_ra.x(),
                            .{ .shifted_immediate = .{ .immediate = hi12, .lsl = .@"12" } },
                        ));
                        if (lo12 > 0) try isel.emit(if (offset >= 0) .add(
                            ptr_ra.x(),
                            ptr_ra.x(),
                            .{ .immediate = lo12 },
                        ) else .sub(
                            ptr_ra.x(),
                            ptr_ra.x(),
                            .{ .immediate = lo12 },
                        ));
                    }
                    try address_vi.liveOut(isel, ptr_ra);
                },
                .value => |parent_vi| {
                    vi = parent_vi;
                    offset += vi.get(isel).offset_from_parent;
                    continue :parent vi.parent(isel);
                },
                .constant => |constant| {
                    const pt = isel.pt;
                    const zcu = pt.zcu;
                    switch (true) {
                        false => {
                            try isel.uav_relocs.append(zcu.gpa, .{
                                .uav = .{
                                    .val = constant.toIntern(),
                                    .orig_ty = (try pt.singleConstPtrType(constant.typeOf(zcu))).toIntern(),
                                },
                                .reloc = .{
                                    .label = @intCast(isel.instructions.items.len),
                                    .addend = @intCast(offset),
                                },
                            });
                            try isel.emit(.adr(ptr_ra.x(), 0));
                        },
                        true => {
                            try isel.uav_relocs.append(zcu.gpa, .{
                                .uav = .{
                                    .val = constant.toIntern(),
                                    .orig_ty = (try pt.singleConstPtrType(constant.typeOf(zcu))).toIntern(),
                                },
                                .reloc = .{
                                    .label = @intCast(isel.instructions.items.len),
                                    .addend = @intCast(offset),
                                },
                            });
                            try isel.emit(.add(ptr_ra.x(), ptr_ra.x(), .{ .immediate = 0 }));
                            try isel.uav_relocs.append(zcu.gpa, .{
                                .uav = .{
                                    .val = constant.toIntern(),
                                    .orig_ty = (try pt.singleConstPtrType(constant.typeOf(zcu))).toIntern(),
                                },
                                .reloc = .{
                                    .label = @intCast(isel.instructions.items.len),
                                    .addend = @intCast(offset),
                                },
                            });
                            try isel.emit(.adrp(ptr_ra.x(), 0));
                        },
                    }
                },
            }
        }
    };

    pub const PartIterator = struct {
        vi: Value.Index,
        remaining: Value.PartsLen,

        fn initOne(vi: Value.Index) PartIterator {
            return .{ .vi = vi, .remaining = 1 };
        }

        pub fn next(it: *PartIterator) ?Value.Index {
            if (it.remaining == 0) return null;
            it.remaining -= 1;
            defer it.vi = @fromBackingInt(@intCast(@backingInt(it.vi) + 1));
            return it.vi;
        }

        pub fn peek(it: PartIterator) ?Value.Index {
            var it_mut = it;
            return it_mut.next();
        }

        pub fn only(it: PartIterator) ?Value.Index {
            return if (it.remaining == 1) it.vi else null;
        }
    };

    const FieldPartIterator = struct {
        vi: Value.Index,
        ty: ZigType,
        field_offset: u64,
        field_size: u64,
        next_offset: u64,

        fn next(it: *FieldPartIterator, isel: *Select) !?struct { offset: u64, vi: Value.Index } {
            const zcu = isel.pt.zcu;
            const ip = &zcu.intern_pool;
            next_part: while (true) {
                var next_offset = it.next_offset;
                var next_part_size = it.field_size - next_offset;
                if (next_part_size == 0) return null;
                var next_part_offset = it.field_offset + next_offset;

                var vi = it.vi;
                var ty = it.ty;
                var ty_size = vi.size(isel);
                assert(ty_size == ty.abiSize(zcu));
                var offset: u64 = 0;
                var size = ty_size;
                assert(next_part_offset + next_part_size <= size);
                while (next_part_offset > 0 or next_part_size < size) {
                    var part_vi = vi.partAtOffset(isel, next_part_offset);
                    if (part_vi != vi) {
                        var part_offset, size = part_vi.position(isel);
                        if (part_offset + size <= next_part_offset) {
                            const value = vi.get(isel);
                            const last_part_vi: Value.Index = @fromBackingInt(@intCast(@backingInt(value.parts) + value.flags.parts_len_minus_one));
                            if (part_vi == last_part_vi) {
                                it.next_offset = next_offset + next_part_size;
                                continue :next_part;
                            }
                            part_vi = @fromBackingInt(@intCast(@backingInt(part_vi) + 1));
                            part_offset, size = part_vi.position(isel);
                        }
                        if (part_offset > next_part_offset) {
                            const pad = part_offset - next_part_offset;
                            if (pad >= next_part_size) {
                                it.next_offset = next_offset + next_part_size;
                                continue :next_part;
                            }
                            next_offset += pad;
                            next_part_size -= pad;
                            next_part_offset = part_offset;
                        }
                        assert(part_offset <= next_part_offset and part_offset + size > next_part_offset);
                        vi = part_vi;
                        offset += part_offset;
                        next_part_offset -= part_offset;
                        next_part_size = @min(next_part_size, size - next_part_offset);
                        continue;
                    }
                    try isel.values.ensureUnusedCapacity(zcu.gpa, Value.max_parts);
                    type_key: switch (ip.indexToKey(ty.toIntern())) {
                        else => return isel.fail("Value.FieldPartIterator.next({f})", .{isel.fmtType(ty)}),
                        .int_type => |int_type| switch (int_type.bits) {
                            0 => unreachable,
                            1...8 => unreachable,
                            9...64 => if (size > 1) {
                                const half_size = @divExact(size, 2);
                                vi.setParts(isel, 2);
                                _ = vi.addPart(isel, 0, half_size);
                                _ = vi.addPart(isel, half_size, half_size);
                            } else unreachable,
                            65...64 * Value.max_parts => |bits| if (offset == 0 and size == ty_size) {
                                const parts_len: Value.PartsLen = @intCast(@divCeil(bits, 64));
                                vi.setParts(isel, parts_len);
                                for (0..parts_len) |part_index| _ = vi.addPart(isel, 8 * part_index, 8);
                            } else if (size > 1) {
                                const half_size = std.math.floorPowerOfTwo(u64, size - 1);
                                vi.setParts(isel, 2);
                                _ = vi.addPart(isel, 0, half_size);
                                _ = vi.addPart(isel, half_size, size - half_size);
                            } else unreachable,
                            64 * Value.max_parts + 1...64 * Value.max_parts * Value.max_parts => |bits| if (size > 8) {
                                const total_size = 8 * @divCeil(bits, 64);
                                const effective_size = @min(size, total_size -| offset);
                                const sub_part_size = @max(8, std.math.ceilPowerOfTwoAssert(u64, @divCeil(effective_size, Value.max_parts)));
                                const parts_len: Value.PartsLen = @intCast(@divCeil(effective_size, sub_part_size));
                                vi.setParts(isel, parts_len);
                                for (0..parts_len) |part_index| {
                                    const part_offset = sub_part_size * part_index;
                                    _ = vi.addPart(isel, part_offset, @min(sub_part_size, effective_size - part_offset));
                                }
                            } else unreachable,
                            else => return isel.fail("Value.FieldPartIterator.next({f})", .{isel.fmtType(ty)}),
                        },
                        .ptr_type => |ptr_type| switch (ptr_type.flags.size) {
                            .one, .many, .c => continue :type_key .{ .int_type = .{
                                .signedness = .unsigned,
                                .bits = 64,
                            } },
                            .slice => if (offset == 0 and size == ty_size) {
                                vi.setParts(isel, 2);
                                _ = vi.addPart(isel, 0, 8);
                                _ = vi.addPart(isel, 8, 8);
                            } else unreachable,
                        },
                        .opt_type => |child_type| if (ty.optionalReprIsPayload(zcu)) {
                            ty = .fromInterned(child_type);
                            continue :type_key ip.indexToKey(child_type);
                        } else {
                            const child_ty: ZigType = .fromInterned(child_type);
                            const child_size = child_ty.abiSize(zcu);
                            if (offset + size <= child_size) {
                                ty = child_ty;
                                ty_size = child_size;
                                continue :type_key ip.indexToKey(child_type);
                            }
                            if (offset > child_size) {
                                it.next_offset = next_offset + next_part_size;
                                continue :next_part;
                            }
                            if (offset == child_size) {
                                if (size > 1) {
                                    size = 1;
                                    switch (vi.get(isel).flags.location_tag) {
                                        .small => vi.get(isel).location_payload.small.size = 1,
                                        .large => vi.get(isel).location_payload.large.size = 1,
                                    }
                                    next_part_size = @min(next_part_size, size - next_part_offset);
                                    continue;
                                }
                                unreachable;
                            }
                            if (child_size >= 9 and child_size <= 15 and offset == 0 and size == ty_size) {
                                vi.setParts(isel, 2);
                                _ = vi.addPart(isel, 0, 8);
                                _ = vi.addPart(isel, 8, child_size - 7);
                            } else {
                                vi.setParts(isel, 2);
                                const child_part_vi = vi.addPart(isel, 0, child_size - offset);
                                if (offset == 0) {
                                    if (child_ty.isAbiInt(zcu)) {
                                        const child_int_info = child_ty.intInfo(zcu);
                                        if (child_int_info.bits <= 16) child_part_vi.setSignedness(isel, child_int_info.signedness);
                                    } else if (CallAbiIterator.homogeneousAggregateBaseType(zcu, child_ty.toIntern())) |fdt| {
                                        if (child_size == fdt.size()) child_part_vi.setIsVector(isel);
                                    }
                                }
                                _ = vi.addPart(isel, child_size - offset, 1);
                            }
                        },
                        .array_type, .vector_type => {
                            var min_part_log2_stride: u6 = if (size > 16)
                                @intCast(@max(4, std.math.log2_int_ceil(u64, @divCeil(size, Value.max_parts))))
                            else if (size > 8)
                                3
                            else
                                0;
                            const array_len, const elem_ty: ZigType = switch (ip.indexToKey(ty.toIntern())) {
                                .array_type => |array_type| .{ array_type.lenIncludingSentinel(), .fromInterned(array_type.child) },
                                .vector_type => |vector_type| .{ vector_type.len, .fromInterned(vector_type.child) },
                                else => unreachable,
                            };
                            const elem_size = elem_ty.abiSize(zcu);
                            if (ty.isVector(zcu) and ty.bitSize(zcu) != array_len * elem_size * 8) {
                                if (offset == 0 and size == ty_size and size > 8 and size <= 8 * Value.max_parts) {
                                    const parts_len: Value.PartsLen = @intCast(@divCeil(size, 8));
                                    vi.setParts(isel, parts_len);
                                    for (0..parts_len) |part_index| _ = vi.addPart(isel, 8 * part_index, @min(8, size - 8 * part_index));
                                } else return isel.fail("Value.FieldPartIterator.next({f})", .{isel.fmtType(ty)});
                            } else {
                                const Part = struct { offset: u64, size: u64 };
                                var parts: [Value.max_parts]Part = undefined;
                                var parts_len: Value.PartsLen = 0;
                                const elem_signedness = if (elem_ty.isAbiInt(zcu)) elem_signedness: {
                                    const elem_int_info = elem_ty.intInfo(zcu);
                                    break :elem_signedness if (elem_int_info.bits <= 16) elem_int_info.signedness else null;
                                } else null;
                                const elem_is_vector = if (CallAbiIterator.homogeneousAggregateBaseType(zcu, elem_ty.toIntern())) |fdt|
                                    elem_size == fdt.size()
                                else
                                    false;
                                retry: while (true) : (min_part_log2_stride += 1) {
                                    parts_len = 0;
                                    var elem_end: u64 = 0;
                                    for (0..@intCast(array_len)) |_| {
                                        const elem_begin = elem_end;
                                        if (elem_begin >= offset + size) break;
                                        elem_end = elem_begin + elem_size;
                                        if (elem_end <= offset) continue;
                                        if (offset >= elem_begin and offset + size <= elem_begin + elem_size) {
                                            ty = elem_ty;
                                            ty_size = elem_size;
                                            offset -= elem_begin;
                                            continue :type_key ip.indexToKey(elem_ty.toIntern());
                                        }
                                        const part_begin = @max(elem_begin, offset);
                                        const part_end = @min(elem_end, offset + size);
                                        const part_size = part_end - part_begin;
                                        if (parts_len > 0) combine: {
                                            const prev_part = &parts[parts_len - 1];
                                            const combined_size = part_end - prev_part.offset;
                                            if (min_part_log2_stride == 0 or
                                                (prev_part.offset >> min_part_log2_stride) != ((part_end - 1) >> min_part_log2_stride))
                                                break :combine;
                                            prev_part.size = combined_size;
                                            continue;
                                        }
                                        if (parts_len == Value.max_parts) continue :retry;
                                        parts[parts_len] = .{ .offset = part_begin, .size = part_size };
                                        parts_len += 1;
                                    }
                                    if (parts_len == 1 and min_part_log2_stride > 0) {
                                        min_part_log2_stride = 0;
                                        continue :retry;
                                    }
                                    break;
                                }
                                if (parts_len == 0) {
                                    it.next_offset = next_offset + next_part_size;
                                    continue :next_part;
                                }
                                if (parts_len == 1 and parts[0].offset == offset) {
                                    size = parts[0].size;
                                    switch (vi.get(isel).flags.location_tag) {
                                        .small => vi.get(isel).location_payload.small.size = @intCast(size),
                                        .large => vi.get(isel).location_payload.large.size = size,
                                    }
                                    if (size == elem_size) {
                                        if (elem_signedness) |signedness| vi.setSignedness(isel, signedness);
                                        if (elem_is_vector) vi.setIsVector(isel);
                                    }
                                    next_part_size = @min(next_part_size, size - next_part_offset);
                                    continue;
                                }
                                vi.setParts(isel, parts_len);
                                for (parts[0..parts_len]) |part| {
                                    const subpart_vi = vi.addPart(isel, part.offset - offset, part.size);
                                    if (part.size == elem_size) {
                                        if (elem_signedness) |signedness| subpart_vi.setSignedness(isel, signedness);
                                        if (elem_is_vector) subpart_vi.setIsVector(isel);
                                    }
                                }
                            }
                        },
                        .anyframe_type => unreachable,
                        .error_union_type => |error_union_type| {
                            var min_part_log2_stride: u6 = if (size > 16)
                                @intCast(@max(4, std.math.log2_int_ceil(u64, @divCeil(size, Value.max_parts))))
                            else if (size > 8)
                                3
                            else
                                0;
                            const payload_ty: ZigType = .fromInterned(error_union_type.payload_type);
                            const error_set_offset = codegen.errUnionErrorOffset(payload_ty, zcu);
                            const payload_offset = codegen.errUnionPayloadOffset(payload_ty, zcu);
                            const Part = struct { offset: u64, size: u64, signedness: ?std.lang.Signedness, is_vector: bool };
                            var parts: [Value.max_parts]Part = undefined;
                            var parts_len: Value.PartsLen = 0;
                            retry: while (true) : (min_part_log2_stride += 1) {
                                parts_len = 0;
                                var field_end: u64 = 0;
                                for (0..2) |field_index| {
                                    const field_ty: ZigType, const field_begin = switch (@as(enum { error_set, payload }, switch (field_index) {
                                        0 => if (error_set_offset < payload_offset) .error_set else .payload,
                                        1 => if (error_set_offset < payload_offset) .payload else .error_set,
                                        else => unreachable,
                                    })) {
                                        .error_set => .{ .fromInterned(error_union_type.error_set_type), error_set_offset },
                                        .payload => .{ payload_ty, payload_offset },
                                    };
                                    if (field_begin >= offset + size) break;
                                    const field_size = field_ty.abiSize(zcu);
                                    if (field_size == 0) continue;
                                    field_end = field_begin + field_size;
                                    if (field_end <= offset) continue;
                                    if (offset >= field_begin and offset + size <= field_begin + field_size) {
                                        ty = field_ty;
                                        ty_size = field_size;
                                        offset -= field_begin;
                                        continue :type_key ip.indexToKey(field_ty.toIntern());
                                    }
                                    const part_begin = @max(field_begin, offset);
                                    const part_end = @min(field_end, offset + size);
                                    const part_size = part_end - part_begin;
                                    const field_signedness = if (part_size == field_size and field_ty.isAbiInt(zcu)) field_signedness: {
                                        const field_int_info = field_ty.intInfo(zcu);
                                        break :field_signedness if (field_int_info.bits <= 16) field_int_info.signedness else null;
                                    } else null;
                                    const field_is_vector = if (part_size == field_size) if (CallAbiIterator.homogeneousAggregateBaseType(zcu, field_ty.toIntern())) |fdt|
                                        field_size == fdt.size()
                                    else
                                        false else false;
                                    var sub_begin = part_begin;
                                    while (sub_begin < part_end) {
                                        const sub_end = if (min_part_log2_stride == 3 and part_size > 8)
                                            @min(part_end, ((sub_begin >> 3) + 1) << 3)
                                        else
                                            part_end;
                                        const sub_size = sub_end - sub_begin;
                                        const sub_signedness = if (sub_size == field_size) field_signedness else null;
                                        const sub_is_vector = if (sub_size == field_size) field_is_vector else false;
                                        if (parts_len > 0) combine: {
                                            const prev_part = &parts[parts_len - 1];
                                            const combined_size = sub_end - prev_part.offset;
                                            if (min_part_log2_stride == 0 or
                                                (prev_part.offset == offset and sub_end == offset + size) or
                                                (prev_part.offset >> min_part_log2_stride) != ((sub_end - 1) >> min_part_log2_stride))
                                                break :combine;
                                            prev_part.size = combined_size;
                                            prev_part.signedness = null;
                                            prev_part.is_vector = false;
                                            sub_begin = sub_end;
                                            continue;
                                        }
                                        if (parts_len == Value.max_parts) continue :retry;
                                        parts[parts_len] = .{
                                            .offset = sub_begin,
                                            .size = sub_size,
                                            .signedness = sub_signedness,
                                            .is_vector = sub_is_vector,
                                        };
                                        parts_len += 1;
                                        sub_begin = sub_end;
                                    }
                                }
                                if (parts_len == 1 and min_part_log2_stride > 0) {
                                    min_part_log2_stride = 0;
                                    continue :retry;
                                }
                                break;
                            }
                            if (parts_len == 1 and parts[0].offset == offset) {
                                size = parts[0].size;
                                switch (vi.get(isel).flags.location_tag) {
                                    .small => vi.get(isel).location_payload.small.size = @intCast(size),
                                    .large => vi.get(isel).location_payload.large.size = size,
                                }
                                if (parts[0].signedness) |signedness| vi.setSignedness(isel, signedness);
                                if (parts[0].is_vector) vi.setIsVector(isel);
                                next_part_size = @min(next_part_size, size - next_part_offset);
                                continue;
                            }
                            if (parts_len == 1) {
                                const only_part = parts[0];
                                parts_len = 0;
                                if (only_part.offset > offset) {
                                    parts[parts_len] = .{ .offset = offset, .size = only_part.offset - offset, .signedness = null, .is_vector = false };
                                    parts_len += 1;
                                }
                                parts[parts_len] = only_part;
                                parts_len += 1;
                                const only_end = only_part.offset + only_part.size;
                                if (only_end < offset + size) {
                                    parts[parts_len] = .{ .offset = only_end, .size = offset + size - only_end, .signedness = null, .is_vector = false };
                                    parts_len += 1;
                                }
                            }
                            vi.setParts(isel, parts_len);
                            for (parts[0..parts_len]) |part| {
                                const subpart_vi = vi.addPart(isel, part.offset - offset, part.size);
                                if (part.signedness) |signedness| subpart_vi.setSignedness(isel, signedness);
                                if (part.is_vector) subpart_vi.setIsVector(isel);
                            }
                        },
                        .simple_type => |simple_type| switch (simple_type) {
                            .f16, .f32, .f64, .f128, .c_longdouble => return isel.fail("Value.FieldPartIterator.next({f})", .{isel.fmtType(ty)}),
                            .f80 => continue :type_key .{ .int_type = .{ .signedness = .unsigned, .bits = 80 } },
                            .usize,
                            .isize,
                            .c_char,
                            .c_short,
                            .c_ushort,
                            .c_int,
                            .c_uint,
                            .c_long,
                            .c_ulong,
                            .c_longlong,
                            .c_ulonglong,
                            => continue :type_key .{ .int_type = ty.intInfo(zcu) },
                            .anyopaque,
                            .void,
                            .type,
                            .comptime_int,
                            .comptime_float,
                            .noreturn,
                            .null,
                            .undefined,
                            .enum_literal,
                            .adhoc_inferred_error_set,
                            .generic_poison,
                            => unreachable,
                            .bool => continue :type_key .{ .int_type = .{ .signedness = .unsigned, .bits = 1 } },
                            .anyerror => continue :type_key .{ .int_type = .{
                                .signedness = .unsigned,
                                .bits = zcu.errorSetBits(),
                            } },
                        },
                        .struct_type => {
                            const loaded_struct = ip.loadStructType(ty.toIntern());
                            switch (loaded_struct.layout) {
                                .auto, .@"extern" => {},
                                .@"packed" => continue :type_key .{
                                    .int_type = ip.indexToKey(loaded_struct.packed_backing_int_type).int_type,
                                },
                            }
                            var min_part_log2_stride: u6 = if (size > 16)
                                @intCast(@max(4, std.math.log2_int_ceil(u64, @divCeil(size, Value.max_parts))))
                            else if (size > 8)
                                3
                            else
                                0;
                            const Part = struct { offset: u64, size: u64, signedness: ?std.lang.Signedness, is_vector: bool };
                            var parts: [Value.max_parts]Part = undefined;
                            var parts_len: Value.PartsLen = 0;
                            retry: while (true) : (min_part_log2_stride += 1) {
                                parts_len = 0;
                                var field_end: u64 = 0;
                                var field_it = loaded_struct.iterateRuntimeOrder(ip);
                                while (field_it.next()) |field_index| {
                                    if (loaded_struct.field_is_comptime_bits.get(ip, field_index)) continue;
                                    const field_ty: ZigType = .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                                    const field_begin = switch (loaded_struct.field_aligns.getOrNone(ip, field_index)) {
                                        .none => field_ty.abiAlignment(zcu),
                                        else => |field_align| field_align,
                                    }.forward(field_end);
                                    if (field_begin >= offset + size) break;
                                    const field_size = field_ty.abiSize(zcu);
                                    if (field_size == 0) continue;
                                    field_end = field_begin + field_size;
                                    if (field_end <= offset) continue;
                                    if (offset >= field_begin and offset + size <= field_begin + field_size) {
                                        ty = field_ty;
                                        ty_size = field_size;
                                        offset -= field_begin;
                                        continue :type_key ip.indexToKey(field_ty.toIntern());
                                    }
                                    const part_begin = @max(field_begin, offset);
                                    const part_end = @min(field_end, offset + size);
                                    const part_size = part_end - part_begin;
                                    const field_signedness = if (part_size == field_size and field_ty.isAbiInt(zcu)) field_signedness: {
                                        const field_int_info = field_ty.intInfo(zcu);
                                        break :field_signedness if (field_int_info.bits <= 16) field_int_info.signedness else null;
                                    } else null;
                                    const field_is_vector = if (part_size == field_size) if (CallAbiIterator.homogeneousAggregateBaseType(zcu, field_ty.toIntern())) |fdt|
                                        field_size == fdt.size()
                                    else
                                        false else false;
                                    var sub_begin = part_begin;
                                    while (sub_begin < part_end) {
                                        const sub_end = if (min_part_log2_stride == 3 and part_size > 8)
                                            @min(part_end, ((sub_begin >> 3) + 1) << 3)
                                        else
                                            part_end;
                                        const sub_size = sub_end - sub_begin;
                                        const sub_signedness = if (sub_size == field_size) field_signedness else null;
                                        const sub_is_vector = if (sub_size == field_size) field_is_vector else false;
                                        if (parts_len > 0) combine: {
                                            const prev_part = &parts[parts_len - 1];
                                            const combined_size = sub_end - prev_part.offset;
                                            if (min_part_log2_stride == 0 or
                                                (prev_part.offset == offset and sub_end == offset + size) or
                                                (prev_part.offset >> min_part_log2_stride) != ((sub_end - 1) >> min_part_log2_stride))
                                                break :combine;
                                            prev_part.size = combined_size;
                                            prev_part.signedness = null;
                                            prev_part.is_vector = false;
                                            sub_begin = sub_end;
                                            continue;
                                        }
                                        if (parts_len == Value.max_parts) continue :retry;
                                        parts[parts_len] = .{
                                            .offset = sub_begin,
                                            .size = sub_size,
                                            .signedness = sub_signedness,
                                            .is_vector = sub_is_vector,
                                        };
                                        parts_len += 1;
                                        sub_begin = sub_end;
                                    }
                                }
                                if (parts_len == 1 and min_part_log2_stride > 0) {
                                    min_part_log2_stride = 0;
                                    continue :retry;
                                }
                                break;
                            }
                            if (parts_len == 1 and parts[0].offset == offset) {
                                size = parts[0].size;
                                switch (vi.get(isel).flags.location_tag) {
                                    .small => vi.get(isel).location_payload.small.size = @intCast(size),
                                    .large => vi.get(isel).location_payload.large.size = size,
                                }
                                if (parts[0].signedness) |signedness| vi.setSignedness(isel, signedness);
                                if (parts[0].is_vector) vi.setIsVector(isel);
                                next_part_size = @min(next_part_size, size - next_part_offset);
                                continue;
                            }
                            if (parts_len == 1) {
                                const only_part = parts[0];
                                parts_len = 0;
                                if (only_part.offset > offset) {
                                    parts[parts_len] = .{ .offset = offset, .size = only_part.offset - offset, .signedness = null, .is_vector = false };
                                    parts_len += 1;
                                }
                                parts[parts_len] = only_part;
                                parts_len += 1;
                                const only_end = only_part.offset + only_part.size;
                                if (only_end < offset + size) {
                                    parts[parts_len] = .{ .offset = only_end, .size = offset + size - only_end, .signedness = null, .is_vector = false };
                                    parts_len += 1;
                                }
                            }
                            vi.setParts(isel, parts_len);
                            for (parts[0..parts_len]) |part| {
                                const subpart_vi = vi.addPart(isel, part.offset - offset, part.size);
                                if (part.signedness) |signedness| subpart_vi.setSignedness(isel, signedness);
                                if (part.is_vector) subpart_vi.setIsVector(isel);
                            }
                        },
                        .tuple_type => |tuple_type| {
                            var min_part_log2_stride: u6 = if (size > 16)
                                @intCast(@max(4, std.math.log2_int_ceil(u64, @divCeil(size, Value.max_parts))))
                            else if (size > 8)
                                3
                            else
                                0;
                            const Part = struct { offset: u64, size: u64, is_vector: bool };
                            var parts: [Value.max_parts]Part = undefined;
                            var parts_len: Value.PartsLen = 0;
                            retry: while (true) : (min_part_log2_stride += 1) {
                                parts_len = 0;
                                var field_end: u64 = 0;
                                for (tuple_type.types.get(ip), tuple_type.values.get(ip)) |field_type, field_value| {
                                    if (field_value != .none) continue;
                                    const field_ty: ZigType = .fromInterned(field_type);
                                    const field_begin = field_ty.abiAlignment(zcu).forward(field_end);
                                    if (field_begin >= offset + size) break;
                                    const field_size = field_ty.abiSize(zcu);
                                    if (field_size == 0) continue;
                                    field_end = field_begin + field_size;
                                    if (field_end <= offset) continue;
                                    if (offset >= field_begin and offset + size <= field_begin + field_size) {
                                        ty = field_ty;
                                        ty_size = field_size;
                                        offset -= field_begin;
                                        continue :type_key ip.indexToKey(field_ty.toIntern());
                                    }
                                    const part_begin = @max(field_begin, offset);
                                    const part_end = @min(field_end, offset + size);
                                    const part_size = part_end - part_begin;
                                    const field_is_vector = if (part_size == field_size) if (CallAbiIterator.homogeneousAggregateBaseType(zcu, field_ty.toIntern())) |fdt|
                                        field_size == fdt.size()
                                    else
                                        false else false;
                                    var sub_begin = part_begin;
                                    while (sub_begin < part_end) {
                                        const sub_end = if (min_part_log2_stride == 3 and part_size > 8)
                                            @min(part_end, ((sub_begin >> 3) + 1) << 3)
                                        else
                                            part_end;
                                        const sub_size = sub_end - sub_begin;
                                        const sub_is_vector = if (sub_size == field_size) field_is_vector else false;
                                        if (parts_len > 0) combine: {
                                            const prev_part = &parts[parts_len - 1];
                                            const combined_size = sub_end - prev_part.offset;
                                            if (min_part_log2_stride == 0 or
                                                (prev_part.offset == offset and sub_end == offset + size) or
                                                (prev_part.offset >> min_part_log2_stride) != ((sub_end - 1) >> min_part_log2_stride))
                                                break :combine;
                                            prev_part.size = combined_size;
                                            prev_part.is_vector = false;
                                            sub_begin = sub_end;
                                            continue;
                                        }
                                        if (parts_len == Value.max_parts) continue :retry;
                                        parts[parts_len] = .{ .offset = sub_begin, .size = sub_size, .is_vector = sub_is_vector };
                                        parts_len += 1;
                                        sub_begin = sub_end;
                                    }
                                }
                                if (parts_len == 1 and min_part_log2_stride > 0) {
                                    min_part_log2_stride = 0;
                                    continue :retry;
                                }
                                break;
                            }
                            if (parts_len == 1 and parts[0].offset == offset) {
                                size = parts[0].size;
                                switch (vi.get(isel).flags.location_tag) {
                                    .small => vi.get(isel).location_payload.small.size = @intCast(size),
                                    .large => vi.get(isel).location_payload.large.size = size,
                                }
                                if (parts[0].is_vector) vi.setIsVector(isel);
                                next_part_size = @min(next_part_size, size - next_part_offset);
                                continue;
                            }
                            if (parts_len == 1) {
                                const only_part = parts[0];
                                parts_len = 0;
                                if (only_part.offset > offset) {
                                    parts[parts_len] = .{ .offset = offset, .size = only_part.offset - offset, .is_vector = false };
                                    parts_len += 1;
                                }
                                parts[parts_len] = only_part;
                                parts_len += 1;
                                const only_end = only_part.offset + only_part.size;
                                if (only_end < offset + size) {
                                    parts[parts_len] = .{ .offset = only_end, .size = offset + size - only_end, .is_vector = false };
                                    parts_len += 1;
                                }
                            }
                            vi.setParts(isel, parts_len);
                            for (parts[0..parts_len]) |part| {
                                const subpart_vi = vi.addPart(isel, part.offset - offset, part.size);
                                if (part.is_vector) subpart_vi.setIsVector(isel);
                            }
                        },
                        .union_type => {
                            const loaded_union = ip.loadUnionType(ty.toIntern());
                            switch (loaded_union.layout) {
                                .auto, .@"extern" => {},
                                .@"packed" => continue :type_key .{ .int_type = .{
                                    .signedness = .unsigned,
                                    .bits = @intCast(ty.bitSize(zcu)),
                                } },
                            }
                            var min_part_log2_stride: u6 = if (size > 16)
                                @intCast(@max(4, std.math.log2_int_ceil(u64, @divCeil(size, Value.max_parts))))
                            else if (size > 8)
                                3
                            else
                                0;
                            const union_layout = ZigType.getUnionLayout(loaded_union, zcu);
                            const tag_offset = union_layout.tagOffset();
                            const payload_offset = union_layout.payloadOffset();
                            const Part = struct { offset: u64, size: u64, signedness: ?std.lang.Signedness };
                            var parts: [Value.max_parts]Part = undefined;
                            var parts_len: Value.PartsLen = 0;
                            retry: while (true) : (min_part_log2_stride += 1) {
                                parts_len = 0;
                                var field_end: u64 = 0;
                                for (0..2) |field_index| {
                                    const field: enum { tag, payload } = switch (field_index) {
                                        0 => if (tag_offset < payload_offset) .tag else .payload,
                                        1 => if (tag_offset < payload_offset) .payload else .tag,
                                        else => unreachable,
                                    };
                                    const field_size, const field_begin = switch (field) {
                                        .tag => .{ union_layout.tag_size, tag_offset },
                                        .payload => .{ union_layout.payload_size, payload_offset },
                                    };
                                    if (field_begin >= offset + size) break;
                                    if (field_size == 0) continue;
                                    field_end = field_begin + field_size;
                                    if (field_end <= offset) continue;
                                    const part_begin = @max(field_begin, offset);
                                    const part_end = @min(field_end, offset + size);
                                    const part_size = part_end - part_begin;
                                    const field_signedness = field_signedness: switch (field) {
                                        .tag => {
                                            if (offset >= field_begin and offset + size <= field_begin + field_size) {
                                                ty = .fromInterned(loaded_union.enum_tag_type);
                                                ty_size = field_size;
                                                offset -= field_begin;
                                                continue :type_key ip.indexToKey(loaded_union.enum_tag_type);
                                            }
                                            if (part_size < field_size) break :field_signedness null;
                                            const loaded_enum = ip.loadEnumType(loaded_union.enum_tag_type);
                                            const int_tag_type = ip.indexToKey(loaded_enum.int_tag_type).int_type;
                                            break :field_signedness if (int_tag_type.bits <= 16) int_tag_type.signedness else null;
                                        },
                                        .payload => {
                                            if (offset >= field_begin and offset + size <= field_begin + field_size) {
                                                const payload_log2_stride: u6 = if (size > 8 * Value.max_parts)
                                                    @intCast(std.math.log2_int_ceil(u64, @divCeil(size, Value.max_parts)))
                                                else if (size > 8)
                                                    3
                                                else
                                                    @intCast(std.math.log2_int(u64, size - 1));
                                                var part_offset: u64 = 0;
                                                var payload_parts_len: Value.PartsLen = 0;
                                                while (part_offset < size) {
                                                    const sub_size = @min(
                                                        std.math.floorPowerOfTwo(u64, size - part_offset),
                                                        @as(u64, 1) << @min(payload_log2_stride, @ctz(part_offset)),
                                                    );
                                                    part_offset += sub_size;
                                                    payload_parts_len += 1;
                                                }
                                                vi.setParts(isel, payload_parts_len);
                                                part_offset = 0;
                                                while (part_offset < size) {
                                                    const sub_size = @min(
                                                        std.math.floorPowerOfTwo(u64, size - part_offset),
                                                        @as(u64, 1) << @min(payload_log2_stride, @ctz(part_offset)),
                                                    );
                                                    _ = vi.addPart(isel, part_offset, sub_size);
                                                    part_offset += sub_size;
                                                }
                                                break :type_key;
                                            }
                                            break :field_signedness null;
                                        },
                                    };
                                    var sub_begin = part_begin;
                                    while (sub_begin < part_end) {
                                        const sub_end = if (min_part_log2_stride > 0)
                                            @min(part_end, ((sub_begin >> min_part_log2_stride) + 1) << min_part_log2_stride)
                                        else
                                            part_end;
                                        const sub_size = sub_end - sub_begin;
                                        const sub_signedness = if (sub_size == field_size) field_signedness else null;
                                        if (parts_len > 0) combine: {
                                            const prev_part = &parts[parts_len - 1];
                                            const combined_size = sub_end - prev_part.offset;
                                            if (min_part_log2_stride == 0 or
                                                (prev_part.offset == offset and sub_end == offset + size) or
                                                (prev_part.offset >> min_part_log2_stride) != ((sub_end - 1) >> min_part_log2_stride))
                                                break :combine;
                                            prev_part.size = combined_size;
                                            prev_part.signedness = null;
                                            sub_begin = sub_end;
                                            continue;
                                        }
                                        if (parts_len == Value.max_parts) continue :retry;
                                        parts[parts_len] = .{
                                            .offset = sub_begin,
                                            .size = sub_size,
                                            .signedness = sub_signedness,
                                        };
                                        parts_len += 1;
                                        sub_begin = sub_end;
                                    }
                                }
                                break;
                            }
                            if (parts_len == 1 and parts[0].offset == offset) {
                                size = parts[0].size;
                                switch (vi.get(isel).flags.location_tag) {
                                    .small => vi.get(isel).location_payload.small.size = @intCast(size),
                                    .large => vi.get(isel).location_payload.large.size = size,
                                }
                                if (parts[0].signedness) |signedness| vi.setSignedness(isel, signedness);
                                next_part_size = @min(next_part_size, size - next_part_offset);
                                continue;
                            }
                            if (parts_len == 1) {
                                const only_part = parts[0];
                                parts_len = 0;
                                if (only_part.offset > offset) {
                                    parts[parts_len] = .{ .offset = offset, .size = only_part.offset - offset, .signedness = null };
                                    parts_len += 1;
                                }
                                parts[parts_len] = only_part;
                                parts_len += 1;
                                const only_end = only_part.offset + only_part.size;
                                if (only_end < offset + size) {
                                    parts[parts_len] = .{ .offset = only_end, .size = offset + size - only_end, .signedness = null };
                                    parts_len += 1;
                                }
                            }
                            vi.setParts(isel, parts_len);
                            for (parts[0..parts_len]) |part| {
                                const subpart_vi = vi.addPart(isel, part.offset - offset, part.size);
                                if (part.signedness) |signedness| subpart_vi.setSignedness(isel, signedness);
                            }
                        },
                        .opaque_type, .func_type => continue :type_key .{ .simple_type = .anyopaque },
                        .enum_type => continue :type_key ip.indexToKey(ip.loadEnumType(ty.toIntern()).int_tag_type),
                        .error_set_type,
                        .inferred_error_set_type,
                        => continue :type_key .{ .simple_type = .anyerror },
                        .undef,
                        .simple_value,
                        .@"extern",
                        .func,
                        .int,
                        .err,
                        .error_union,
                        .enum_literal,
                        .enum_tag,
                        .float,
                        .ptr,
                        .slice,
                        .opt,
                        .aggregate,
                        .un,
                        .memoized_call,
                        => unreachable, // values, not types
                    }
                }
                it.next_offset = next_offset + size;
                return .{ .offset = next_offset - next_part_offset, .vi = vi };
            }
        }

        fn only(it: *FieldPartIterator, isel: *Select) !?Value.Index {
            const part = try it.next(isel);
            assert(part.?.offset == 0);
            return if (try it.next(isel)) |_| null else part.?.vi;
        }

        fn move(it: *FieldPartIterator, isel: *Select, src_ty: ZigType, src_ref: Air.Inst.Ref) !void {
            if (it.field_size == 0) return;
            const src_vi = try isel.use(src_ref);
            try it.copyFrom(isel, src_ty, src_vi);
        }

        fn copyFrom(it: *FieldPartIterator, isel: *Select, src_ty: ZigType, src_vi: Value.Index) !void {
            while (try it.next(isel)) |dst_part| {
                var src_part_it = src_vi.field(src_ty, dst_part.offset, dst_part.vi.size(isel));
                while (try src_part_it.next(isel)) |src_part| {
                    const sub_offset = dst_part.offset + src_part.offset;
                    var dst_sub_it = it.vi.field(it.ty, it.field_offset + sub_offset, src_part.vi.size(isel));
                    while (try dst_sub_it.next(isel)) |dst_sub| {
                        const leaf_offset = sub_offset + dst_sub.offset;
                        const src_leaf_vi = if (dst_sub.offset == 0 and dst_sub.vi.size(isel) == src_part.vi.size(isel))
                            src_part.vi
                        else src_leaf_vi: {
                            var src_leaf_it = src_vi.field(src_ty, leaf_offset, dst_sub.vi.size(isel));
                            break :src_leaf_vi (try src_leaf_it.only(isel)).?;
                        };
                        try dst_sub.vi.copyAdvanced(isel, src_leaf_vi, .{
                            .dst_ty = it.ty,
                            .dst_vi = it.vi,
                            .dst_offset = it.field_offset + leaf_offset,
                            .src_ty = src_ty,
                            .src_vi = src_vi,
                            .src_offset = leaf_offset,
                        });
                    }
                }
            }
        }

        fn copyTo(it: *FieldPartIterator, isel: *Select, dst_ty: ZigType, dst_vi: Value.Index) !void {
            while (try it.next(isel)) |src_part| {
                var dst_part_it = dst_vi.field(dst_ty, src_part.offset, src_part.vi.size(isel));
                while (try dst_part_it.next(isel)) |dst_part| {
                    const sub_offset = src_part.offset + dst_part.offset;
                    var src_sub_it = it.vi.field(it.ty, it.field_offset + sub_offset, dst_part.vi.size(isel));
                    while (try src_sub_it.next(isel)) |src_sub| {
                        const leaf_offset = sub_offset + src_sub.offset;
                        const dst_leaf_vi = if (src_sub.offset == 0 and src_sub.vi.size(isel) == dst_part.vi.size(isel))
                            dst_part.vi
                        else dst_leaf_vi: {
                            var dst_leaf_it = dst_vi.field(dst_ty, leaf_offset, src_sub.vi.size(isel));
                            break :dst_leaf_vi (try dst_leaf_it.only(isel)).?;
                        };
                        try dst_leaf_vi.copyAdvanced(isel, src_sub.vi, .{
                            .dst_ty = dst_ty,
                            .dst_vi = dst_vi,
                            .dst_offset = leaf_offset,
                            .src_ty = it.ty,
                            .src_vi = it.vi,
                            .src_offset = it.field_offset + leaf_offset,
                        });
                    }
                }
            }
        }
    };

    const Materialize = struct {
        vi: Value.Index,
        ra: Register.Alias,

        fn finish(mat: Value.Materialize, isel: *Select) codegen.Error!void {
            const live_vi = isel.live_registers.getPtr(mat.ra);
            assert(live_vi.* == .allocating);
            var vi = mat.vi;
            var offset: u64 = 0;
            const size = mat.vi.size(isel);
            free: while (true) {
                if (vi.register(isel)) |ra| {
                    if (ra != mat.ra) break :free if (vi == mat.vi) try isel.emit(if (mat.ra.isVector()) switch (ra.isVector()) {
                        false => size: switch (size) {
                            else => unreachable,
                            2 => if (isel.target.cpu.has(.aarch64, .fullfp16))
                                .fmov(mat.ra.h(), .{ .register = ra.w() })
                            else
                                continue :size 4,
                            4 => .fmov(mat.ra.s(), .{ .register = ra.w() }),
                            8 => .fmov(mat.ra.d(), .{ .register = ra.x() }),
                        },
                        true => switch (size) {
                            else => unreachable,
                            2 => if (isel.target.cpu.has(.aarch64, .fullfp16))
                                .fmov(mat.ra.h(), .{ .register = ra.h() })
                            else
                                .dup(mat.ra.h(), ra.@"h[]"(0)),
                            4 => .fmov(mat.ra.s(), .{ .register = ra.s() }),
                            8 => .fmov(mat.ra.d(), .{ .register = ra.d() }),
                            16 => .orr(mat.ra.@"16b"(), ra.@"16b"(), .{ .register = ra.@"16b"() }),
                        },
                    } else switch (ra.isVector()) {
                        false => switch (size) {
                            else => unreachable,
                            1...4 => .orr(mat.ra.w(), .wzr, .{ .register = ra.w() }),
                            5...8 => .orr(mat.ra.x(), .xzr, .{ .register = ra.x() }),
                        },
                        true => switch (size) {
                            else => unreachable,
                            2 => if (isel.target.cpu.has(.aarch64, .fullfp16))
                                .fmov(mat.ra.w(), .{ .register = ra.h() })
                            else
                                .umov(mat.ra.w(), ra.@"h[]"(0)),
                            4 => .fmov(mat.ra.w(), .{ .register = ra.s() }),
                            8 => .fmov(mat.ra.x(), .{ .register = ra.d() }),
                        },
                    }) else {
                        const part_ra = if (mat.ra.isVector()) try isel.allocIntReg() else mat.ra;
                        defer if (part_ra != mat.ra) isel.freeReg(part_ra);
                        if (part_ra != mat.ra) try isel.emit(size: switch (size) {
                            else => unreachable,
                            2 => if (isel.target.cpu.has(.aarch64, .fullfp16))
                                .fmov(mat.ra.h(), .{ .register = part_ra.w() })
                            else
                                continue :size 4,
                            4 => .fmov(mat.ra.s(), .{ .register = part_ra.w() }),
                            8 => .fmov(mat.ra.d(), .{ .register = part_ra.x() }),
                        });
                        const lane_offset = if (ra.isVector()) offset % 8 else offset;
                        const src_int_ra = if (ra.isVector()) part_ra else ra;
                        try isel.emit(switch (lane_offset + size) {
                            else => unreachable,
                            1...4 => |end_offset| switch (mat.vi.signedness(isel)) {
                                .signed => .sbfm(part_ra.w(), src_int_ra.w(), .{
                                    .N = .word,
                                    .immr = @intCast(8 * lane_offset),
                                    .imms = @intCast(8 * end_offset - 1),
                                }),
                                .unsigned => .ubfm(part_ra.w(), src_int_ra.w(), .{
                                    .N = .word,
                                    .immr = @intCast(8 * lane_offset),
                                    .imms = @intCast(8 * end_offset - 1),
                                }),
                            },
                            5...8 => |end_offset| switch (mat.vi.signedness(isel)) {
                                .signed => .sbfm(part_ra.x(), src_int_ra.x(), .{
                                    .N = .doubleword,
                                    .immr = @intCast(8 * lane_offset),
                                    .imms = @intCast(8 * end_offset - 1),
                                }),
                                .unsigned => .ubfm(part_ra.x(), src_int_ra.x(), .{
                                    .N = .doubleword,
                                    .immr = @intCast(8 * lane_offset),
                                    .imms = @intCast(8 * end_offset - 1),
                                }),
                            },
                        });
                        if (ra.isVector()) try isel.emit(switch (offset + size) {
                            else => unreachable,
                            1...4 => .fmov(part_ra.w(), .{ .register = ra.s() }),
                            5...8 => .fmov(part_ra.x(), .{ .register = ra.d() }),
                            9...16 => .fmov(part_ra.x(), .{ .register = ra.@"d[]"(1) }),
                        });
                    };
                    mat.vi.get(isel).location_payload.small.register = mat.ra;
                    live_vi.* = mat.vi;
                    return;
                }
                offset += vi.get(isel).offset_from_parent;
                switch (vi.parent(isel)) {
                    .unallocated => {
                        if (mat.vi.hasRegisterRecursive(isel)) {
                            try mat.vi.spillReg(isel, mat.ra, 0, &.initFill(.free));
                        }
                        mat.vi.get(isel).location_payload.small.register = mat.ra;
                        live_vi.* = mat.vi;
                        return;
                    },
                    .stack_slot => |stack_slot| break :free try isel.loadReg(
                        mat.ra,
                        size,
                        mat.vi.signedness(isel),
                        stack_slot.base,
                        @as(i65, stack_slot.offset) + offset,
                    ),
                    .address => |base_vi| {
                        const base_mat = try base_vi.matReg(isel);
                        try isel.loadReg(mat.ra, size, mat.vi.signedness(isel), base_mat.ra, offset);
                        break :free try base_mat.finish(isel);
                    },
                    .value => |parent_vi| vi = parent_vi,
                    .constant => |initial_constant| {
                        const zcu = isel.pt.zcu;
                        const ip = &zcu.intern_pool;
                        var constant = initial_constant.toIntern();
                        var constant_key = ip.indexToKey(constant);
                        while (true) {
                            constant_key: switch (constant_key) {
                                .int_type,
                                .ptr_type,
                                .array_type,
                                .vector_type,
                                .opt_type,
                                .anyframe_type,
                                .error_union_type,
                                .simple_type,
                                .struct_type,
                                .tuple_type,
                                .union_type,
                                .opaque_type,
                                .enum_type,
                                .func_type,
                                .error_set_type,
                                .inferred_error_set_type,

                                .enum_literal,
                                .memoized_call,
                                => unreachable, // not a runtime value
                                .undef => break :free try isel.emit(if (mat.ra.isVector()) .movi(switch (size) {
                                    else => unreachable,
                                    1...8 => mat.ra.@"8b"(),
                                    9...16 => mat.ra.@"16b"(),
                                }, 0xaa, .{ .lsl = 0 }) else switch (size) {
                                    else => unreachable,
                                    1...4 => .orr(mat.ra.w(), .wzr, .{ .immediate = .{
                                        .N = .word,
                                        .immr = 0b000001,
                                        .imms = 0b111100,
                                    } }),
                                    5...8 => .orr(mat.ra.x(), .xzr, .{ .immediate = .{
                                        .N = .word,
                                        .immr = 0b000001,
                                        .imms = 0b111100,
                                    } }),
                                }),
                                .simple_value => |simple_value| switch (simple_value) {
                                    .void, .null, .@"unreachable" => unreachable,
                                    .true => continue :constant_key .{ .int = .{
                                        .ty = .bool_type,
                                        .storage = .{ .u64 = 1 },
                                    } },
                                    .false => continue :constant_key .{ .int = .{
                                        .ty = .bool_type,
                                        .storage = .{ .u64 = 0 },
                                    } },
                                },
                                .int => |int| break :free switch (int.storage) {
                                    .u64 => |imm| switch (size) {
                                        else => unreachable,
                                        1...4 => try isel.movImmediate(mat.ra.w(), @as(u32, @truncate(std.math.shr(u64, imm, 8 * offset)))),
                                        5...8 => try isel.movImmediate(mat.ra.x(), std.math.shr(u64, imm, 8 * offset)),
                                    },
                                    .i64 => |imm| switch (size) {
                                        else => unreachable,
                                        1...4 => try isel.movImmediate(mat.ra.w(), @as(u32, @bitCast(@as(i32, @truncate(std.math.shr(i64, imm, 8 * offset)))))),
                                        5...8 => try isel.movImmediate(mat.ra.x(), @bitCast(std.math.shr(i64, imm, 8 * offset))),
                                    },
                                    .big_int => |big_int| {
                                        assert(size == 8);
                                        var imm: u64 = 0;
                                        const limb_bits = @bitSizeOf(std.math.big.Limb);
                                        const limbs = @divExact(64, limb_bits);
                                        var limb_index: usize = @intCast(@divExact(offset, @divExact(limb_bits, 8)) + limbs);
                                        for (0..limbs) |_| {
                                            limb_index -= 1;
                                            if (limb_index >= big_int.limbs.len) continue;
                                            if (limb_bits < 64) imm <<= limb_bits;
                                            imm |= big_int.limbs[limb_index];
                                        }
                                        if (!big_int.positive) {
                                            limb_index = @min(limb_index, big_int.limbs.len);
                                            imm = while (limb_index > 0) {
                                                limb_index -= 1;
                                                if (big_int.limbs[limb_index] != 0) break ~imm;
                                            } else -%imm;
                                        }
                                        try isel.movImmediate(mat.ra.x(), imm);
                                    },
                                },
                                .err => |err| continue :constant_key .{ .int = .{
                                    .ty = err.ty,
                                    .storage = .{ .u64 = ip.getErrorValueIfExists(err.name).? },
                                } },
                                .error_union => |error_union| {
                                    const error_union_type = ip.indexToKey(error_union.ty).error_union_type;
                                    const error_set_ty: ZigType = .fromInterned(error_union_type.error_set_type);
                                    const payload_ty: ZigType = .fromInterned(error_union_type.payload_type);
                                    const error_set_offset = codegen.errUnionErrorOffset(payload_ty, zcu);
                                    const error_set_size = error_set_ty.abiSize(zcu);
                                    if (offset >= error_set_offset and offset + size <= error_set_offset + error_set_size) {
                                        offset -= error_set_offset;
                                        continue :constant_key switch (error_union.val) {
                                            .err_name => |err_name| .{ .err = .{
                                                .ty = error_union_type.error_set_type,
                                                .name = err_name,
                                            } },
                                            .payload => .{ .int = .{
                                                .ty = error_union_type.error_set_type,
                                                .storage = .{ .u64 = 0 },
                                            } },
                                        };
                                    }
                                    const payload_offset = codegen.errUnionPayloadOffset(payload_ty, zcu);
                                    const payload_size = payload_ty.abiSize(zcu);
                                    if (offset >= payload_offset and offset + size <= payload_offset + payload_size) {
                                        offset -= payload_offset;
                                        switch (error_union.val) {
                                            .err_name => continue :constant_key .{ .undef = error_union_type.payload_type },
                                            .payload => |payload| {
                                                constant = payload;
                                                constant_key = ip.indexToKey(constant);
                                                continue :constant_key constant_key;
                                            },
                                        }
                                    }
                                },
                                .enum_tag => |enum_tag| continue :constant_key .{ .int = ip.indexToKey(enum_tag.int).int },
                                .float => |float| storage: switch (float.storage) {
                                    .f16 => |imm| {
                                        if (!mat.ra.isVector()) continue :constant_key .{ .int = .{
                                            .ty = .u16_type,
                                            .storage = .{ .u64 = @as(u16, @bitCast(imm)) },
                                        } };
                                        const feat_fp16 = isel.target.cpu.has(.aarch64, .fullfp16);
                                        if (feat_fp16) {
                                            const Repr = std.math.FloatRepr(f16);
                                            const repr: Repr = @bitCast(imm);
                                            if (repr.mantissa & std.math.maxInt(Repr.Mantissa) >> 5 == 0 and switch (repr.exponent) {
                                                .denormal, .infinite => false,
                                                else => std.math.cast(i3, repr.exponent.unbias() - 1) != null,
                                            }) break :free try isel.emit(.fmov(mat.ra.h(), .{ .immediate = imm }));
                                        }
                                        const bits: u16 = @bitCast(imm);
                                        if (bits == 0) break :free try isel.emit(.movi(mat.ra.d(), 0b00000000, .replicate));
                                        if (bits & std.math.maxInt(u8) == 0) break :free try isel.emit(.movi(
                                            mat.ra.@"4h"(),
                                            @intCast(@shrExact(bits, 8)),
                                            .{ .lsl = 8 },
                                        ));
                                        const temp_ra = try isel.allocIntReg();
                                        defer isel.freeReg(temp_ra);
                                        try isel.emit(.fmov(if (feat_fp16) mat.ra.h() else mat.ra.s(), .{ .register = temp_ra.w() }));
                                        break :free try isel.movImmediate(temp_ra.w(), bits);
                                    },
                                    .f32 => |imm| {
                                        if (!mat.ra.isVector()) continue :constant_key .{ .int = .{
                                            .ty = .u32_type,
                                            .storage = .{ .u64 = @as(u32, @bitCast(imm)) },
                                        } };
                                        const Repr = std.math.FloatRepr(f32);
                                        const repr: Repr = @bitCast(imm);
                                        if (repr.mantissa & std.math.maxInt(Repr.Mantissa) >> 5 == 0 and switch (repr.exponent) {
                                            .denormal, .infinite => false,
                                            else => std.math.cast(i3, repr.exponent.unbias() - 1) != null,
                                        }) break :free try isel.emit(.fmov(mat.ra.s(), .{ .immediate = @floatCast(imm) }));
                                        const bits: u32 = @bitCast(imm);
                                        if (bits == 0) break :free try isel.emit(.movi(mat.ra.d(), 0b00000000, .replicate));
                                        if (bits & std.math.maxInt(u24) == 0) break :free try isel.emit(.movi(
                                            mat.ra.@"2s"(),
                                            @intCast(@shrExact(bits, 24)),
                                            .{ .lsl = 24 },
                                        ));
                                        const temp_ra = try isel.allocIntReg();
                                        defer isel.freeReg(temp_ra);
                                        try isel.emit(.fmov(mat.ra.s(), .{ .register = temp_ra.w() }));
                                        break :free try isel.movImmediate(temp_ra.w(), bits);
                                    },
                                    .f64 => |imm| {
                                        if (!mat.ra.isVector()) continue :constant_key .{ .int = .{
                                            .ty = .u64_type,
                                            .storage = .{ .u64 = @as(u64, @bitCast(imm)) },
                                        } };
                                        const Repr = std.math.FloatRepr(f64);
                                        const repr: Repr = @bitCast(imm);
                                        if (repr.mantissa & std.math.maxInt(Repr.Mantissa) >> 5 == 0 and switch (repr.exponent) {
                                            .denormal, .infinite => false,
                                            else => std.math.cast(i3, repr.exponent.unbias() - 1) != null,
                                        }) break :free try isel.emit(.fmov(mat.ra.d(), .{ .immediate = @floatCast(imm) }));
                                        const bits: u64 = @bitCast(imm);
                                        if (bits == 0) break :free try isel.emit(.movi(mat.ra.d(), 0b00000000, .replicate));
                                        const temp_ra = try isel.allocIntReg();
                                        defer isel.freeReg(temp_ra);
                                        try isel.emit(.fmov(mat.ra.d(), .{ .register = temp_ra.x() }));
                                        break :free try isel.movImmediate(temp_ra.x(), bits);
                                    },
                                    .f80 => |imm| break :free try isel.movImmediate(
                                        mat.ra.x(),
                                        @truncate(std.math.shr(u80, @bitCast(imm), 8 * offset)),
                                    ),
                                    .f128 => |imm| switch (ZigType.fromInterned(float.ty).floatBits(isel.target)) {
                                        else => unreachable,
                                        16 => continue :storage .{ .f16 = @floatCast(imm) },
                                        32 => continue :storage .{ .f32 = @floatCast(imm) },
                                        64 => continue :storage .{ .f64 = @floatCast(imm) },
                                        128 => {
                                            const bits: u128 = @bitCast(imm);
                                            const hi64: u64 = @intCast(bits >> 64);
                                            const lo64: u64 = @truncate(bits >> 0);
                                            const temp_ra = try isel.allocIntReg();
                                            defer isel.freeReg(temp_ra);
                                            switch (hi64) {
                                                0 => {},
                                                else => {
                                                    try isel.emit(.fmov(mat.ra.@"d[]"(1), .{ .register = temp_ra.x() }));
                                                    try isel.movImmediate(temp_ra.x(), hi64);
                                                },
                                            }
                                            break :free switch (lo64) {
                                                0 => try isel.emit(.movi(switch (hi64) {
                                                    else => mat.ra.d(),
                                                    0 => mat.ra.@"2d"(),
                                                }, 0b00000000, .replicate)),
                                                else => {
                                                    try isel.emit(.fmov(mat.ra.d(), .{ .register = temp_ra.x() }));
                                                    try isel.movImmediate(temp_ra.x(), lo64);
                                                },
                                            };
                                        },
                                    },
                                },
                                .ptr => |ptr| {
                                    assert(offset == 0 and size == 8);
                                    break :free switch (ptr.base_addr) {
                                        .nav => |nav| if (ZigType.fromInterned(ip.getNav(nav).resolved.?.type).isRuntimeFnOrHasRuntimeBits(zcu)) switch (true) {
                                            false => {
                                                try isel.nav_relocs.append(zcu.gpa, .{
                                                    .nav = nav,
                                                    .reloc = .{
                                                        .label = @intCast(isel.instructions.items.len),
                                                        .addend = ptr.byte_offset,
                                                    },
                                                });
                                                try isel.emit(.adr(mat.ra.x(), 0));
                                            },
                                            true => {
                                                try isel.nav_relocs.append(zcu.gpa, .{
                                                    .nav = nav,
                                                    .reloc = .{
                                                        .label = @intCast(isel.instructions.items.len),
                                                        .addend = ptr.byte_offset,
                                                    },
                                                });
                                                if (ip.getNav(nav).getExtern(ip)) |_|
                                                    try isel.emit(.ldr(mat.ra.x(), .{ .unsigned_offset = .{ .base = mat.ra.x(), .offset = 0 } }))
                                                else
                                                    try isel.emit(.add(mat.ra.x(), mat.ra.x(), .{ .immediate = 0 }));
                                                try isel.nav_relocs.append(zcu.gpa, .{
                                                    .nav = nav,
                                                    .reloc = .{
                                                        .label = @intCast(isel.instructions.items.len),
                                                        .addend = ptr.byte_offset,
                                                    },
                                                });
                                                try isel.emit(.adrp(mat.ra.x(), 0));
                                            },
                                        } else continue :constant_key .{ .int = .{
                                            .ty = .usize_type,
                                            .storage = .{ .u64 = zcu.navAlignment(nav).forward(0xaaaaaaaaaaaaaaaa) },
                                        } },
                                        .uav => |uav| if (ZigType.fromInterned(ip.typeOf(uav.val)).isRuntimeFnOrHasRuntimeBits(zcu)) switch (true) {
                                            false => {
                                                try isel.uav_relocs.append(zcu.gpa, .{
                                                    .uav = uav,
                                                    .reloc = .{
                                                        .label = @intCast(isel.instructions.items.len),
                                                        .addend = ptr.byte_offset,
                                                    },
                                                });
                                                try isel.emit(.adr(mat.ra.x(), 0));
                                            },
                                            true => {
                                                try isel.uav_relocs.append(zcu.gpa, .{
                                                    .uav = uav,
                                                    .reloc = .{
                                                        .label = @intCast(isel.instructions.items.len),
                                                        .addend = ptr.byte_offset,
                                                    },
                                                });
                                                try isel.emit(.add(mat.ra.x(), mat.ra.x(), .{ .immediate = 0 }));
                                                try isel.uav_relocs.append(zcu.gpa, .{
                                                    .uav = uav,
                                                    .reloc = .{
                                                        .label = @intCast(isel.instructions.items.len),
                                                        .addend = ptr.byte_offset,
                                                    },
                                                });
                                                try isel.emit(.adrp(mat.ra.x(), 0));
                                            },
                                        } else continue :constant_key .{ .int = .{
                                            .ty = .usize_type,
                                            .storage = .{ .u64 = ZigType.fromInterned(uav.orig_ty).ptrAlignment(zcu).forward(0xaaaaaaaaaaaaaaaa) },
                                        } },
                                        .int => continue :constant_key .{ .int = .{
                                            .ty = .usize_type,
                                            .storage = .{ .u64 = ptr.byte_offset },
                                        } },
                                        .eu_payload => |base| {
                                            var base_ptr = ip.indexToKey(base).ptr;
                                            const eu_ty = ip.indexToKey(base_ptr.ty).ptr_type.child;
                                            const payload_ty = ip.indexToKey(eu_ty).error_union_type.payload_type;
                                            base_ptr.byte_offset += codegen.errUnionPayloadOffset(.fromInterned(payload_ty), zcu) + ptr.byte_offset;
                                            continue :constant_key .{ .ptr = base_ptr };
                                        },
                                        .opt_payload => |base| {
                                            var base_ptr = ip.indexToKey(base).ptr;
                                            base_ptr.byte_offset += ptr.byte_offset;
                                            continue :constant_key .{ .ptr = base_ptr };
                                        },
                                        .field => |field| {
                                            var base_ptr = ip.indexToKey(field.base).ptr;
                                            const agg_ty: ZigType = .fromInterned(ip.indexToKey(base_ptr.ty).ptr_type.child);
                                            const field_off: u64 = switch (agg_ty.zigTypeTag(zcu)) {
                                                .pointer => off: {
                                                    assert(agg_ty.isSlice(zcu));
                                                    break :off switch (field.index) {
                                                        Constant.slice_ptr_index => 0,
                                                        Constant.slice_len_index => @divExact(isel.target.ptrBitWidth(), 8),
                                                        else => unreachable,
                                                    };
                                                },
                                                .@"struct", .@"union" => agg_ty.structFieldOffset(@intCast(field.index), zcu),
                                                else => unreachable,
                                            };
                                            base_ptr.byte_offset += field_off + ptr.byte_offset;
                                            continue :constant_key .{ .ptr = base_ptr };
                                        },
                                        .comptime_alloc, .comptime_field, .arr_elem => unreachable,
                                    };
                                },
                                .slice => |slice| switch (offset) {
                                    0 => continue :constant_key switch (ip.indexToKey(slice.ptr)) {
                                        else => unreachable,
                                        .undef => |undef| .{ .undef = undef },
                                        .ptr => |ptr| .{ .ptr = ptr },
                                    },
                                    else => {
                                        assert(offset == @divExact(isel.target.ptrBitWidth(), 8));
                                        offset = 0;
                                        continue :constant_key .{ .int = ip.indexToKey(slice.len).int };
                                    },
                                },
                                .opt => |opt| {
                                    const child_ty = ip.indexToKey(opt.ty).opt_type;
                                    const child_size = ZigType.fromInterned(child_ty).abiSize(zcu);
                                    if (offset == child_size and size == 1) {
                                        offset = 0;
                                        continue :constant_key .{ .simple_value = switch (opt.val) {
                                            .none => .false,
                                            else => .true,
                                        } };
                                    }
                                    const opt_ty: ZigType = .fromInterned(opt.ty);
                                    if (offset + size <= child_size) continue :constant_key switch (opt.val) {
                                        .none => if (opt_ty.optionalReprIsPayload(zcu)) .{ .int = .{
                                            .ty = opt.ty,
                                            .storage = .{ .u64 = 0 },
                                        } } else .{ .undef = child_ty },
                                        else => |child| {
                                            constant = child;
                                            constant_key = ip.indexToKey(constant);
                                            continue :constant_key constant_key;
                                        },
                                    };
                                },
                                .aggregate => |aggregate| switch (ip.indexToKey(aggregate.ty)) {
                                    else => unreachable,
                                    .array_type, .vector_type => {
                                        const array_len, const elem_ty: ZigType = switch (ip.indexToKey(aggregate.ty)) {
                                            .array_type => |array_type| .{ array_type.lenIncludingSentinel(), .fromInterned(array_type.child) },
                                            .vector_type => |vector_type| .{ vector_type.len, .fromInterned(vector_type.child) },
                                            else => unreachable,
                                        };
                                        const elem_size = elem_ty.abiSize(zcu);
                                        const agg_ty: ZigType = .fromInterned(aggregate.ty);
                                        if (!agg_ty.isVector(zcu) or agg_ty.bitSize(zcu) == array_len * elem_size * 8) {
                                            if (offset >= array_len * elem_size) {
                                                offset = 0;
                                                continue :constant_key .{ .undef = .u8_type };
                                            }
                                            const elem_offset = @mod(offset, elem_size);
                                            if (size <= elem_size - elem_offset) {
                                                defer offset = elem_offset;
                                                continue :constant_key switch (aggregate.storage) {
                                                    .bytes => |bytes| .{ .int = .{ .ty = .u8_type, .storage = .{
                                                        .u64 = bytes.toSlice(array_len, ip)[@intCast(@divFloor(offset, elem_size))],
                                                    } } },
                                                    .elems => |elems| {
                                                        constant = elems[@intCast(@divFloor(offset, elem_size))];
                                                        constant_key = ip.indexToKey(constant);
                                                        continue :constant_key constant_key;
                                                    },
                                                    .repeated_elem => |repeated_elem| {
                                                        constant = repeated_elem;
                                                        constant_key = ip.indexToKey(constant);
                                                        continue :constant_key constant_key;
                                                    },
                                                };
                                            } else if (elem_size <= 16 and size <= 16) {
                                                var buffer: [32]u8 = @splat(0);
                                                const first_elem = @divFloor(offset, elem_size);
                                                const end_elem = @min(array_len, @divCeil(offset + size, elem_size));
                                                var ok = true;
                                                for (0..@intCast(end_elem - first_elem)) |i| {
                                                    const elem_idx = first_elem + i;
                                                    const dst_slice = buffer[@intCast(i * elem_size)..][0..@intCast(elem_size)];
                                                    switch (aggregate.storage) {
                                                        .bytes => |bytes| dst_slice[0] = bytes.toSlice(array_len, ip)[@intCast(elem_idx)],
                                                        .elems => |elems| if (!try isel.writeToMemory(.fromInterned(elems[@intCast(elem_idx)]), dst_slice)) {
                                                            ok = false;
                                                            break;
                                                        },
                                                        .repeated_elem => |repeated_elem| if (!try isel.writeToMemory(.fromInterned(repeated_elem), dst_slice)) {
                                                            ok = false;
                                                            break;
                                                        },
                                                    }
                                                }
                                                if (ok) {
                                                    constant_key = if (mat.ra.isVector()) .{ .float = switch (size) {
                                                        else => unreachable,
                                                        2 => .{ .ty = .f16_type, .storage = .{ .f16 = @bitCast(std.mem.readInt(
                                                            u16,
                                                            buffer[@intCast(elem_offset)..][0..2],
                                                            isel.target.cpu.arch.endian(),
                                                        )) } },
                                                        4 => .{ .ty = .f32_type, .storage = .{ .f32 = @bitCast(std.mem.readInt(
                                                            u32,
                                                            buffer[@intCast(elem_offset)..][0..4],
                                                            isel.target.cpu.arch.endian(),
                                                        )) } },
                                                        8 => .{ .ty = .f64_type, .storage = .{ .f64 = @bitCast(std.mem.readInt(
                                                            u64,
                                                            buffer[@intCast(elem_offset)..][0..8],
                                                            isel.target.cpu.arch.endian(),
                                                        )) } },
                                                        16 => .{ .ty = .f128_type, .storage = .{ .f128 = @bitCast(std.mem.readInt(
                                                            u128,
                                                            buffer[@intCast(elem_offset)..][0..16],
                                                            isel.target.cpu.arch.endian(),
                                                        )) } },
                                                    } } else .{ .int = .{
                                                        .ty = .u64_type,
                                                        .storage = .{ .u64 = switch (size) {
                                                            else => unreachable,
                                                            inline 1...8 => |ct_size| std.mem.readInt(
                                                                @Int(.unsigned, 8 * ct_size),
                                                                buffer[@intCast(elem_offset)..][0..ct_size],
                                                                isel.target.cpu.arch.endian(),
                                                            ),
                                                        } },
                                                    } };
                                                    offset = 0;
                                                    continue;
                                                }
                                            }
                                        }
                                    },
                                    .struct_type => {
                                        const loaded_struct = ip.loadStructType(aggregate.ty);
                                        switch (loaded_struct.layout) {
                                            .auto, .@"extern" => {
                                                var min_offset: u64 = offset;
                                                var max_end: u64 = offset + size;
                                                var has_overlap = false;
                                                var field_it = loaded_struct.iterateRuntimeOrder(ip);
                                                while (field_it.next()) |field_index| {
                                                    if (loaded_struct.field_is_comptime_bits.get(ip, field_index)) continue;
                                                    const field_ty: ZigType = .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                                                    const field_offset = loaded_struct.field_offsets.get(ip)[field_index];
                                                    const field_size = field_ty.abiSize(zcu);
                                                    if (offset >= field_offset and offset + size <= field_offset + field_size) {
                                                        offset -= field_offset;
                                                        constant = switch (aggregate.storage) {
                                                            .bytes => unreachable,
                                                            .elems => |elems| elems[field_index],
                                                            .repeated_elem => |repeated_elem| repeated_elem,
                                                        };
                                                        constant_key = ip.indexToKey(constant);
                                                        continue :constant_key constant_key;
                                                    }
                                                    if (field_size > 0 and field_offset < offset + size and field_offset + field_size > offset) {
                                                        has_overlap = true;
                                                        min_offset = @min(min_offset, field_offset);
                                                        max_end = @max(max_end, field_offset + field_size);
                                                    }
                                                }
                                                if (!has_overlap) {
                                                    offset = 0;
                                                    continue :constant_key .{ .undef = .u8_type };
                                                }
                                                const buffer = try zcu.gpa.alloc(u8, @intCast(max_end - min_offset));
                                                defer zcu.gpa.free(buffer);
                                                @memset(buffer, 0);
                                                var ok = true;
                                                field_it = loaded_struct.iterateRuntimeOrder(ip);
                                                while (field_it.next()) |field_index| {
                                                    if (loaded_struct.field_is_comptime_bits.get(ip, field_index)) continue;
                                                    const field_ty: ZigType = .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                                                    const field_offset = loaded_struct.field_offsets.get(ip)[field_index];
                                                    const field_size = field_ty.abiSize(zcu);
                                                    if (field_size > 0 and field_offset < offset + size and field_offset + field_size > offset) {
                                                        const field_val = switch (aggregate.storage) {
                                                            .bytes => unreachable,
                                                            .elems => |elems| elems[field_index],
                                                            .repeated_elem => |repeated_elem| repeated_elem,
                                                        };
                                                        if (!try isel.writeToMemory(
                                                            .fromInterned(field_val),
                                                            buffer[@intCast(field_offset - min_offset)..][0..@intCast(field_size)],
                                                        )) {
                                                            ok = false;
                                                            break;
                                                        }
                                                    }
                                                }
                                                if (ok) {
                                                    const rel_offset: usize = @intCast(offset - min_offset);
                                                    constant_key = if (mat.ra.isVector()) .{ .float = switch (size) {
                                                        else => unreachable,
                                                        2 => .{ .ty = .f16_type, .storage = .{ .f16 = @bitCast(std.mem.readInt(
                                                            u16,
                                                            buffer[rel_offset..][0..2],
                                                            isel.target.cpu.arch.endian(),
                                                        )) } },
                                                        4 => .{ .ty = .f32_type, .storage = .{ .f32 = @bitCast(std.mem.readInt(
                                                            u32,
                                                            buffer[rel_offset..][0..4],
                                                            isel.target.cpu.arch.endian(),
                                                        )) } },
                                                        8 => .{ .ty = .f64_type, .storage = .{ .f64 = @bitCast(std.mem.readInt(
                                                            u64,
                                                            buffer[rel_offset..][0..8],
                                                            isel.target.cpu.arch.endian(),
                                                        )) } },
                                                        16 => .{ .ty = .f128_type, .storage = .{ .f128 = @bitCast(std.mem.readInt(
                                                            u128,
                                                            buffer[rel_offset..][0..16],
                                                            isel.target.cpu.arch.endian(),
                                                        )) } },
                                                    } } else .{ .int = .{
                                                        .ty = .u64_type,
                                                        .storage = .{ .u64 = switch (size) {
                                                            else => unreachable,
                                                            inline 1...8 => |ct_size| std.mem.readInt(
                                                                @Int(.unsigned, 8 * ct_size),
                                                                buffer[rel_offset..][0..ct_size],
                                                                isel.target.cpu.arch.endian(),
                                                            ),
                                                        } },
                                                    } };
                                                    offset = 0;
                                                    continue;
                                                }
                                            },
                                            .@"packed" => {},
                                        }
                                    },
                                    .tuple_type => |tuple_type| {
                                        var field_offset: u64 = 0;
                                        for (tuple_type.types.get(ip), tuple_type.values.get(ip), 0..) |field_type, field_value, field_index| {
                                            if (field_value != .none) continue;
                                            const field_ty: ZigType = .fromInterned(field_type);
                                            field_offset = field_ty.abiAlignment(zcu).forward(field_offset);
                                            const field_size = field_ty.abiSize(zcu);
                                            if (offset >= field_offset and offset + size <= field_offset + field_size) {
                                                offset -= field_offset;
                                                constant = switch (aggregate.storage) {
                                                    .bytes => unreachable,
                                                    .elems => |elems| elems[field_index],
                                                    .repeated_elem => |repeated_elem| repeated_elem,
                                                };
                                                constant_key = ip.indexToKey(constant);
                                                continue :constant_key constant_key;
                                            }
                                            field_offset += field_size;
                                        }
                                    },
                                },
                                .un => |un| {
                                    const loaded_union = ip.loadUnionType(un.ty);
                                    const union_layout = ZigType.getUnionLayout(loaded_union, zcu);
                                    const payload_offset = union_layout.payloadOffset();
                                    if (loaded_union.has_runtime_tag) {
                                        const tag_offset = union_layout.tagOffset();
                                        if (offset >= tag_offset and offset + size <= tag_offset + union_layout.tag_size) {
                                            offset -= tag_offset;
                                            continue :constant_key switch (ip.indexToKey(un.tag)) {
                                                else => unreachable,
                                                .int => |int| .{ .int = int },
                                                .enum_tag => |enum_tag| .{ .enum_tag = enum_tag },
                                            };
                                        }
                                        if (offset >= tag_offset and offset < tag_offset + union_layout.tag_size and
                                            (offset >= payload_offset + union_layout.payload_size or offset + size <= payload_offset))
                                        {
                                            offset -= tag_offset;
                                            constant = un.tag;
                                            constant_key = ip.indexToKey(constant);
                                            continue :constant_key constant_key;
                                        }
                                    }
                                    if (offset >= payload_offset and
                                        (!loaded_union.has_runtime_tag or offset + size <= union_layout.tagOffset() or offset >= union_layout.tagOffset() + union_layout.tag_size))
                                    {
                                        const payload_rel_offset = offset - payload_offset;
                                        const val_size = if (un.val != .none)
                                            ZigType.fromInterned(ip.typeOf(un.val)).abiSize(zcu)
                                        else
                                            0;
                                        if (payload_rel_offset >= val_size) {
                                            offset = 0;
                                            continue :constant_key .{ .undef = .u8_type };
                                        }
                                        offset = payload_rel_offset;
                                        constant = un.val;
                                        constant_key = ip.indexToKey(constant);
                                        continue :constant_key constant_key;
                                    }
                                },
                                else => {},
                            }
                            const const_size: usize = @intCast(ZigType.fromInterned(constant_key.typeOf()).abiSize(zcu));
                            const buf_len: usize = @max(const_size, @as(usize, @intCast(offset + size)));
                            if (buf_len <= 4096) {
                                const buffer = try zcu.gpa.alloc(u8, buf_len);
                                defer zcu.gpa.free(buffer);
                                @memset(buffer, 0);
                                if (try isel.writeToMemory(.fromInterned(constant), buffer[0..const_size])) {
                                    constant_key = if (mat.ra.isVector()) .{ .float = switch (size) {
                                        else => unreachable,
                                        2 => .{ .ty = .f16_type, .storage = .{ .f16 = @bitCast(std.mem.readInt(
                                            u16,
                                            buffer[@intCast(offset)..][0..2],
                                            isel.target.cpu.arch.endian(),
                                        )) } },
                                        4 => .{ .ty = .f32_type, .storage = .{ .f32 = @bitCast(std.mem.readInt(
                                            u32,
                                            buffer[@intCast(offset)..][0..4],
                                            isel.target.cpu.arch.endian(),
                                        )) } },
                                        8 => .{ .ty = .f64_type, .storage = .{ .f64 = @bitCast(std.mem.readInt(
                                            u64,
                                            buffer[@intCast(offset)..][0..8],
                                            isel.target.cpu.arch.endian(),
                                        )) } },
                                        16 => .{ .ty = .f128_type, .storage = .{ .f128 = @bitCast(std.mem.readInt(
                                            u128,
                                            buffer[@intCast(offset)..][0..16],
                                            isel.target.cpu.arch.endian(),
                                        )) } },
                                    } } else .{ .int = .{
                                        .ty = .u64_type,
                                        .storage = .{ .u64 = switch (size) {
                                            else => unreachable,
                                            inline 1...8 => |ct_size| std.mem.readInt(
                                                @Int(.unsigned, 8 * ct_size),
                                                buffer[@intCast(offset)..][0..ct_size],
                                                isel.target.cpu.arch.endian(),
                                            ),
                                        } },
                                    } };
                                    offset = 0;
                                    continue;
                                }
                            }
                            return isel.fail("unsupported value <{f}, {f}>", .{
                                isel.fmtType(.fromInterned(constant_key.typeOf())),
                                isel.fmtConstant(.fromInterned(constant)),
                            });
                        }
                    },
                }
            }
            live_vi.* = .free;
        }
    };
};
fn initValue(isel: *Select, ty: ZigType) Value.Index {
    const zcu = isel.pt.zcu;
    return isel.initValueAdvanced(ty.abiAlignment(zcu), 0, ty.abiSize(zcu));
}
fn initValueAdvanced(
    isel: *Select,
    parent_alignment: InternPool.Alignment,
    offset_from_parent: u64,
    size: u64,
) Value.Index {
    defer isel.values.addOneAssumeCapacity().* = .{
        .refs = 0,
        .flags = .{
            .alignment = .fromLog2Units(@min(parent_alignment.toLog2Units(), @ctz(offset_from_parent))),
            .parent_tag = .unallocated,
            .location_tag = if (size > 16) .large else .small,
            .parts_len_minus_one = 0,
        },
        .offset_from_parent = offset_from_parent,
        .parent_payload = .{ .unallocated = {} },
        .location_payload = if (size > 16) .{ .large = .{
            .size = size,
        } } else .{ .small = .{
            .size = @intCast(size),
            .signedness = .unsigned,
            .is_vector = false,
            .hint = .zr,
            .register = .zr,
        } },
        .parts = undefined,
    };
    return @fromBackingInt(@intCast(isel.values.items.len));
}
const WhichValues = enum { only_referenced, all };
pub fn dumpValues(isel: *Select, which: WhichValues) void {
    dumpValuesInner(isel, which) catch |err| @panic(@errorName(err));
}
fn dumpValuesInner(isel: *Select, which: WhichValues) !void {
    const zcu = isel.pt.zcu;
    const gpa = zcu.gpa;
    const ip = &zcu.intern_pool;
    const nav = ip.getNav(isel.nav_index);

    const locked_stderr = std.debug.lockStderr(&.{});
    defer std.debug.unlockStderr();
    const stderr = &locked_stderr.file_writer.interface;

    var reverse_live_values: std.array_hash_map.Auto(Value.Index, std.ArrayList(Air.Inst.Index)) = .empty;
    defer {
        for (reverse_live_values.values()) |*list| list.deinit(gpa);
        reverse_live_values.deinit(gpa);
    }
    {
        try reverse_live_values.ensureTotalCapacity(gpa, isel.live_values.count());
        var live_val_it = isel.live_values.iterator();
        while (live_val_it.next()) |live_val_entry| switch (live_val_entry.value_ptr.*) {
            _ => {
                const gop = reverse_live_values.getOrPutAssumeCapacity(live_val_entry.value_ptr.*);
                if (!gop.found_existing) gop.value_ptr.* = .empty;
                try gop.value_ptr.append(gpa, live_val_entry.key_ptr.*);
            },
            .allocating, .free => unreachable,
        };
    }

    var reverse_live_registers: std.AutoHashMapUnmanaged(Value.Index, Register.Alias) = .empty;
    defer reverse_live_registers.deinit(gpa);
    {
        try reverse_live_registers.ensureTotalCapacity(gpa, @typeInfo(Register.Alias).@"enum".field_names.len);
        var live_reg_it = isel.live_registers.iterator();
        while (live_reg_it.next()) |live_reg_entry| switch (live_reg_entry.value.*) {
            _ => reverse_live_registers.putAssumeCapacityNoClobber(live_reg_entry.value.*, live_reg_entry.key),
            .allocating, .free => {},
        };
    }

    var roots: std.array_hash_map.Auto(Value.Index, u32) = .empty;
    defer roots.deinit(gpa);
    {
        try roots.ensureTotalCapacity(gpa, isel.values.items.len);
        var vi: Value.Index = @fromBackingInt(@intCast(isel.values.items.len));
        while (@backingInt(vi) > 0) {
            vi = @fromBackingInt(@intCast(@backingInt(vi) - 1));
            if (which == .only_referenced and vi.get(isel).refs == 0) continue;
            var root_vi = vi;
            while (true) switch (root_vi.parent(isel)) {
                .unallocated, .stack_slot, .constant => break,
                .value => |parent_vi| root_vi = parent_vi,
                .address => |address_vi| break roots.putAssumeCapacity(address_vi, 0),
            };
            roots.putAssumeCapacity(root_vi, 0);
        }
    }

    try stderr.print("# Begin {s} Value Dump: {f}:\n", .{ @typeName(Select), nav.fqn.fmt(ip) });
    while (roots.pop()) |root_entry| {
        const vi = root_entry.key;
        const value = vi.get(isel);
        try stderr.splatByteAll(' ', 2 * (@as(usize, 1) + root_entry.value));
        try stderr.print("${d}", .{@backingInt(vi)});
        {
            var first = true;
            if (reverse_live_values.get(vi)) |aiis| for (aiis.items) |aii| {
                if (aii == Block.main) {
                    try stderr.print("{s}%main", .{if (first) " <- " else ", "});
                } else {
                    try stderr.print("{s}%{d}", .{ if (first) " <- " else ", ", @backingInt(aii) });
                }
                first = false;
            };
            if (reverse_live_registers.get(vi)) |ra| {
                try stderr.print("{s}{t}", .{ if (first) " <- " else ", ", ra });
                first = false;
            }
        }
        try stderr.writeByte(':');
        switch (value.flags.parent_tag) {
            .unallocated => if (value.offset_from_parent != 0) try stderr.print(" +0x{x}", .{value.offset_from_parent}),
            .stack_slot => {
                try stderr.print(" [{t}, #{s}0x{x}", .{
                    value.parent_payload.stack_slot.base,
                    if (value.parent_payload.stack_slot.offset < 0) "-" else "",
                    @abs(value.parent_payload.stack_slot.offset),
                });
                if (value.offset_from_parent != 0) try stderr.print("+0x{x}", .{value.offset_from_parent});
                try stderr.writeByte(']');
            },
            .value => try stderr.print(" ${d}+0x{x}", .{ @backingInt(value.parent_payload.value), value.offset_from_parent }),
            .address => try stderr.print(" ${d}[0x{x}]", .{ @backingInt(value.parent_payload.address), value.offset_from_parent }),
            .constant => try stderr.print(" <{f}, {f}>", .{
                isel.fmtType(value.parent_payload.constant.typeOf(zcu)),
                isel.fmtConstant(value.parent_payload.constant),
            }),
        }
        try stderr.print(" align({t})", .{value.flags.alignment});
        switch (value.flags.location_tag) {
            .large => try stderr.print(" size=0x{x} large", .{value.location_payload.large.size}),
            .small => {
                const loc = value.location_payload.small;
                try stderr.print(" size=0x{x}", .{loc.size});
                switch (loc.signedness) {
                    .unsigned => {},
                    .signed => try stderr.writeAll(" signed"),
                }
                if (loc.hint != .zr) try stderr.print(" hint={t}", .{loc.hint});
                if (loc.register != .zr) try stderr.print(" loc={t}", .{loc.register});
            },
        }
        try stderr.print(" refs={d}\n", .{value.refs});

        var part_index = value.flags.parts_len_minus_one;
        if (part_index > 0) while (true) : (part_index -= 1) {
            roots.putAssumeCapacityNoClobber(
                @fromBackingInt(@intCast(@backingInt(value.parts) + part_index)),
                root_entry.value + 1,
            );
            if (part_index == 0) break;
        };
    }
    try stderr.print("# End {s} Value Dump: {f}\n\n", .{ @typeName(Select), nav.fqn.fmt(ip) });
}

fn hasRepeatedByteRepr(isel: *Select, constant: Constant) error{OutOfMemory}!?u8 {
    const zcu = isel.pt.zcu;
    const ty = constant.typeOf(zcu);
    const abi_size = std.math.cast(usize, ty.abiSize(zcu)) orelse return null;
    const byte_buffer = try zcu.gpa.alloc(u8, abi_size);
    defer zcu.gpa.free(byte_buffer);
    return if (try isel.writeToMemory(constant, byte_buffer) and
        std.mem.allEqual(u8, byte_buffer[1..], byte_buffer[0])) byte_buffer[0] else null;
}

fn writeToMemory(isel: *Select, constant: Constant, buffer: []u8) error{OutOfMemory}!bool {
    const zcu = isel.pt.zcu;
    const ip = &zcu.intern_pool;
    if (try isel.writeKeyToMemory(ip.indexToKey(constant.toIntern()), buffer)) return true;
    constant.writeToMemory(zcu, buffer) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        error.ReinterpretDeclRef, error.IllDefinedMemoryLayout => return false,
    };
    return true;
}
fn writeKeyToMemory(isel: *Select, constant_key: InternPool.Key, buffer: []u8) error{OutOfMemory}!bool {
    const zcu = isel.pt.zcu;
    const ip = &zcu.intern_pool;
    switch (constant_key) {
        .int_type,
        .ptr_type,
        .array_type,
        .vector_type,
        .opt_type,
        .anyframe_type,
        .error_union_type,
        .simple_type,
        .struct_type,
        .tuple_type,
        .union_type,
        .opaque_type,
        .enum_type,
        .func_type,
        .error_set_type,
        .inferred_error_set_type,

        .enum_literal,
        .memoized_call,
        => unreachable, // not a runtime value
        .err => |err| {
            const error_int = ip.getErrorValueIfExists(err.name).?;
            switch (buffer.len) {
                else => unreachable,
                inline 1, 2, 4, 8 => |size| std.mem.writeInt(
                    @Int(.unsigned, 8 * size),
                    buffer[0..size],
                    @intCast(error_int),
                    isel.target.cpu.arch.endian(),
                ),
            }
        },
        .error_union => |error_union| {
            const error_union_type = ip.indexToKey(error_union.ty).error_union_type;
            const error_set_ty: ZigType = .fromInterned(error_union_type.error_set_type);
            const payload_ty: ZigType = .fromInterned(error_union_type.payload_type);
            const error_set = buffer[@intCast(codegen.errUnionErrorOffset(payload_ty, zcu))..][0..@intCast(error_set_ty.abiSize(zcu))];
            switch (error_union.val) {
                .err_name => |err_name| if (!try isel.writeKeyToMemory(.{ .err = .{
                    .ty = error_set_ty.toIntern(),
                    .name = err_name,
                } }, error_set)) return false,
                .payload => |payload| {
                    if (!try isel.writeToMemory(
                        .fromInterned(payload),
                        buffer[@intCast(codegen.errUnionPayloadOffset(payload_ty, zcu))..][0..@intCast(payload_ty.abiSize(zcu))],
                    )) return false;
                    @memset(error_set, 0);
                },
            }
        },
        .opt => |opt| {
            const child_size: usize = @intCast(ZigType.fromInterned(ip.indexToKey(opt.ty).opt_type).abiSize(zcu));
            switch (opt.val) {
                .none => if (!ZigType.fromInterned(opt.ty).optionalReprIsPayload(zcu)) {
                    buffer[child_size] = @intFromBool(false);
                } else @memset(buffer[0..child_size], 0x00),
                else => |child_constant| {
                    if (!try isel.writeToMemory(.fromInterned(child_constant), buffer[0..child_size])) return false;
                    if (!ZigType.fromInterned(opt.ty).optionalReprIsPayload(zcu)) buffer[child_size] = @intFromBool(true);
                },
            }
        },
        .aggregate => |aggregate| switch (ip.indexToKey(aggregate.ty)) {
            else => unreachable,
            .array_type => |array_type| {
                var elem_offset: usize = 0;
                const elem_size: usize = @intCast(ZigType.fromInterned(array_type.child).abiSize(zcu));
                const len_including_sentinel: usize = @intCast(array_type.lenIncludingSentinel());
                switch (aggregate.storage) {
                    .bytes => |bytes| @memcpy(buffer[0..len_including_sentinel], bytes.toSlice(len_including_sentinel, ip)),
                    .elems => |elems| for (elems) |elem| {
                        if (!try isel.writeToMemory(.fromInterned(elem), buffer[elem_offset..][0..elem_size])) return false;
                        elem_offset += elem_size;
                    },
                    .repeated_elem => |repeated_elem| for (0..len_including_sentinel) |_| {
                        if (!try isel.writeToMemory(.fromInterned(repeated_elem), buffer[elem_offset..][0..elem_size])) return false;
                        elem_offset += elem_size;
                    },
                }
            },
            .vector_type => |vector_type| {
                const elem_ty: ZigType = .fromInterned(vector_type.child);
                const elem_size: usize = @intCast(elem_ty.abiSize(zcu));
                const vec_len: usize = @intCast(vector_type.len);
                if (ZigType.fromInterned(aggregate.ty).bitSize(zcu) == vec_len * elem_size * 8) {
                    @memset(buffer, 0);
                    var elem_offset: usize = 0;
                    switch (aggregate.storage) {
                        .bytes => |bytes| @memcpy(buffer[0..vec_len], bytes.toSlice(vec_len, ip)),
                        .elems => |elems| for (elems) |elem| {
                            if (!try isel.writeToMemory(.fromInterned(elem), buffer[elem_offset..][0..elem_size])) return false;
                            elem_offset += elem_size;
                        },
                        .repeated_elem => |repeated_elem| for (0..vec_len) |_| {
                            if (!try isel.writeToMemory(.fromInterned(repeated_elem), buffer[elem_offset..][0..elem_size])) return false;
                            elem_offset += elem_size;
                        },
                    }
                } else if (buffer.len <= 8 and (elem_ty.toIntern() == .bool_type or elem_ty.isAbiInt(zcu))) {
                    const elem_bits: u6 = @intCast(elem_ty.bitSize(zcu));
                    const mask: u64 = (@as(u64, 1) << elem_bits) - 1;
                    var packed_bits: u64 = 0;
                    var elem_buf: [8]u8 = @splat(0);
                    for (0..vec_len) |i| {
                        const elem_ip = switch (aggregate.storage) {
                            .bytes => |bytes| {
                                const b = bytes.toSlice(vec_len, ip)[i];
                                packed_bits |= (@as(u64, b) & mask) << @intCast(i * elem_bits);
                                continue;
                            },
                            .elems => |elems| elems[i],
                            .repeated_elem => |repeated_elem| repeated_elem,
                        };
                        @memset(elem_buf[0..elem_size], 0);
                        if (!try isel.writeToMemory(.fromInterned(elem_ip), elem_buf[0..elem_size])) return false;
                        const elem_val = std.mem.readInt(u64, &elem_buf, isel.target.cpu.arch.endian());
                        packed_bits |= (elem_val & mask) << @intCast(i * elem_bits);
                    }
                    var full_buf: [8]u8 = undefined;
                    std.mem.writeInt(u64, &full_buf, packed_bits, isel.target.cpu.arch.endian());
                    @memcpy(buffer, full_buf[0..buffer.len]);
                } else return false;
            },
            .struct_type => {
                const loaded_struct = ip.loadStructType(aggregate.ty);
                switch (loaded_struct.layout) {
                    .auto, .@"extern" => {
                        @memset(buffer, 0);
                        var field_offset: u64 = 0;
                        var field_it = loaded_struct.iterateRuntimeOrder(ip);
                        while (field_it.next()) |field_index| {
                            if (loaded_struct.field_is_comptime_bits.get(ip, field_index)) continue;
                            const field_ty: ZigType = .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                            field_offset = loaded_struct.field_offsets.get(ip)[field_index];
                            const field_size = field_ty.abiSize(zcu);
                            if (!try isel.writeToMemory(.fromInterned(switch (aggregate.storage) {
                                .bytes => unreachable,
                                .elems => |elems| elems[field_index],
                                .repeated_elem => |repeated_elem| repeated_elem,
                            }), buffer[@intCast(field_offset)..][0..@intCast(field_size)])) return false;
                            field_offset += field_size;
                        }
                    },
                    .@"packed" => return false,
                }
            },
            .tuple_type => |tuple_type| {
                @memset(buffer, 0);
                var field_offset: u64 = 0;
                for (tuple_type.types.get(ip), tuple_type.values.get(ip), 0..) |field_type, field_value, field_index| {
                    if (field_value != .none) continue;
                    const field_ty: ZigType = .fromInterned(field_type);
                    field_offset = field_ty.abiAlignment(zcu).forward(field_offset);
                    const field_size = field_ty.abiSize(zcu);
                    if (!try isel.writeToMemory(.fromInterned(switch (aggregate.storage) {
                        .bytes => unreachable,
                        .elems => |elems| elems[field_index],
                        .repeated_elem => |repeated_elem| repeated_elem,
                    }), buffer[@intCast(field_offset)..][0..@intCast(field_size)])) return false;
                    field_offset += field_size;
                }
            },
        },
        .undef => @memset(buffer, 0xaa),
        .ptr => |ptr| {
            if (buffer.len != 8) return false;
            const addr: u64 = switch (ptr.base_addr) {
                .nav => |nav| if (!ZigType.fromInterned(ip.getNav(nav).resolved.?.type).isRuntimeFnOrHasRuntimeBits(zcu))
                    zcu.navAlignment(nav).forward(0xaaaaaaaaaaaaaaaa)
                else
                    return false,
                .uav => |uav| if (!ZigType.fromInterned(ip.typeOf(uav.val)).isRuntimeFnOrHasRuntimeBits(zcu))
                    ZigType.fromInterned(uav.orig_ty).ptrAlignment(zcu).forward(0xaaaaaaaaaaaaaaaa)
                else
                    return false,
                .int => ptr.byte_offset,
                else => return false,
            };
            std.mem.writeInt(u64, buffer[0..8], addr, isel.target.cpu.arch.endian());
        },
        .slice => |slice| {
            if (buffer.len != 16) return false;
            if (!try isel.writeToMemory(.fromInterned(slice.ptr), buffer[0..8])) return false;
            if (!try isel.writeToMemory(.fromInterned(slice.len), buffer[8..16])) return false;
        },
        .un => |un| {
            const loaded_union = ip.loadUnionType(un.ty);
            switch (loaded_union.layout) {
                .auto, .@"extern" => {
                    const union_layout = ZigType.getUnionLayout(loaded_union, zcu);
                    if (union_layout.payload_size > 0 and un.val != .none) {
                        const field_size: usize = @intCast(ZigType.fromInterned(ip.typeOf(un.val)).abiSize(zcu));
                        const payload_offset: usize = @intCast(union_layout.payloadOffset());
                        if (field_size > 0) {
                            if (!try isel.writeToMemory(.fromInterned(un.val), buffer[payload_offset..][0..field_size])) return false;
                        }
                        if (field_size < union_layout.payload_size) {
                            @memset(buffer[payload_offset + field_size .. payload_offset + @as(usize, @intCast(union_layout.payload_size))], 0x00);
                        }
                    }
                    if (union_layout.tag_size > 0 and un.tag != .none) {
                        const tag_offset: usize = @intCast(union_layout.tagOffset());
                        const tag_size: usize = @intCast(union_layout.tag_size);
                        if (!try isel.writeToMemory(.fromInterned(un.tag), buffer[tag_offset..][0..tag_size])) return false;
                    }
                },
                .@"packed" => return false,
            }
        },
        else => return false,
    }
    return true;
}

const TryAllocRegResult = union(enum) {
    allocated: Register.Alias,
    fill_candidate: Register.Alias,
    out_of_registers,
};

fn tryAllocIntReg(isel: *Select) TryAllocRegResult {
    var failed_result: TryAllocRegResult = .out_of_registers;
    var ra: Register.Alias = .r0;
    while (true) : (ra = @fromBackingInt(@intCast(@backingInt(ra) + 1))) {
        if (ra == .r18) continue; // The Platform Register
        if (ra == Register.Alias.fp) continue;
        const live_vi = isel.live_registers.getPtr(ra);
        switch (live_vi.*) {
            _ => switch (failed_result) {
                .allocated => unreachable,
                .fill_candidate => {},
                .out_of_registers => failed_result = .{ .fill_candidate = ra },
            },
            .allocating => {},
            .free => {
                live_vi.* = .allocating;
                isel.saved_registers.insert(ra);
                return .{ .allocated = ra };
            },
        }
        if (ra == Register.Alias.lr) return failed_result;
    }
}

fn allocIntReg(isel: *Select) !Register.Alias {
    switch (isel.tryAllocIntReg()) {
        .allocated => |ra| return ra,
        .fill_candidate => |ra| {
            assert(try isel.fillMemory(ra));
            const live_vi = isel.live_registers.getPtr(ra);
            assert(live_vi.* == .free);
            live_vi.* = .allocating;
            return ra;
        },
        .out_of_registers => return isel.fail("ran out of registers", .{}),
    }
}

fn ensureFreeIntRegs(
    isel: *Select,
    expected_live_registers: *const LiveRegisters,
    count: usize,
) !void {
    var free_count: usize = 0;
    var ra: Register.Alias = .r0;
    while (true) : (ra = @fromBackingInt(@intCast(@backingInt(ra) + 1))) {
        if (ra != .r18 and ra != Register.Alias.fp) {
            if (isel.live_registers.get(ra) == .free) {
                free_count += 1;
                if (free_count >= count) return;
            }
        }
        if (ra == Register.Alias.lr) break;
    }
    ra = .r0;
    while (true) : (ra = @fromBackingInt(@intCast(@backingInt(ra) + 1))) {
        if (ra != .r18 and ra != Register.Alias.fp) {
            if (expected_live_registers.get(ra) == .free and
                switch (isel.live_registers.get(ra)) {
                    _ => true,
                    .allocating, .free => false,
                })
            {
                assert(try isel.fillMemory(ra));
                assert(isel.live_registers.get(ra) == .free);
                free_count += 1;
                if (free_count >= count) return;
            }
        }
        if (ra == Register.Alias.lr) break;
    }
}

fn tryAllocVecReg(isel: *Select) TryAllocRegResult {
    var failed_result: TryAllocRegResult = .out_of_registers;
    var ra: Register.Alias = .v0;
    while (true) : (ra = @fromBackingInt(@intCast(@backingInt(ra) + 1))) {
        const live_vi = isel.live_registers.getPtr(ra);
        switch (live_vi.*) {
            _ => switch (failed_result) {
                .allocated => unreachable,
                .fill_candidate => {},
                .out_of_registers => failed_result = .{ .fill_candidate = ra },
            },
            .allocating => {},
            .free => {
                live_vi.* = .allocating;
                isel.saved_registers.insert(ra);
                return .{ .allocated = ra };
            },
        }
        if (ra == Register.Alias.v31) return failed_result;
    }
}

fn allocVecReg(isel: *Select) !Register.Alias {
    switch (isel.tryAllocVecReg()) {
        .allocated => |ra| return ra,
        .fill_candidate => |ra| {
            assert(try isel.fillMemory(ra));
            return ra;
        },
        .out_of_registers => return isel.fail("ran out of registers", .{}),
    }
}

const RegLock = struct {
    ra: Register.Alias,
    const empty: RegLock = .{ .ra = .zr };
    fn unlock(lock: RegLock, isel: *Select) void {
        switch (lock.ra) {
            else => |ra| isel.freeReg(ra),
            .zr => {},
        }
    }
};
fn lockReg(isel: *Select, ra: Register.Alias) RegLock {
    assert(ra != .zr);
    const live_vi = isel.live_registers.getPtr(ra);
    assert(live_vi.* == .free);
    live_vi.* = .allocating;
    return .{ .ra = ra };
}
fn tryLockReg(isel: *Select, ra: Register.Alias) RegLock {
    assert(ra != .zr);
    const live_vi = isel.live_registers.getPtr(ra);
    switch (live_vi.*) {
        _, .allocating => return .{ .ra = .zr },
        .free => {
            live_vi.* = .allocating;
            return .{ .ra = ra };
        },
    }
}

fn freeReg(isel: *Select, ra: Register.Alias) void {
    assert(ra != .zr);
    const live_vi = isel.live_registers.getPtr(ra);
    assert(live_vi.* == .allocating);
    live_vi.* = .free;
}

fn use(isel: *Select, air_ref: Air.Inst.Ref) !Value.Index {
    const zcu = isel.pt.zcu;
    const ip = &zcu.intern_pool;
    try isel.values.ensureUnusedCapacity(zcu.gpa, 1);
    const vi, const ty = if (air_ref.toIndex()) |air_inst_index| vi_ty: {
        const live_gop = try isel.live_values.getOrPut(zcu.gpa, air_inst_index);
        if (live_gop.found_existing) return live_gop.value_ptr.*;
        const ty = isel.air.typeOf(air_ref, ip);
        const vi = isel.initValue(ty);
        tracking_log.debug("${d} <- %{d}", .{
            @backingInt(vi),
            @backingInt(air_inst_index),
        });
        live_gop.value_ptr.* = vi.ref(isel);
        break :vi_ty .{ vi, ty };
    } else vi_ty: {
        const constant: Constant = .fromInterned(air_ref.toInterned().?);
        const ty = constant.typeOf(zcu);
        const vi = isel.initValue(ty);
        tracking_log.debug("${d} <- <{f}, {f}>", .{
            @backingInt(vi),
            isel.fmtType(ty),
            isel.fmtConstant(constant),
        });
        vi.setParent(isel, .{ .constant = constant });
        break :vi_ty .{ vi, ty };
    };
    if (ty.isAbiInt(zcu)) {
        const int_info = ty.intInfo(zcu);
        if (int_info.bits <= 16) vi.setSignedness(isel, int_info.signedness);
    } else if (CallAbiIterator.homogeneousAggregateBaseType(zcu, ty.toIntern())) |fdt| {
        if (vi.size(isel) == fdt.size()) vi.setIsVector(isel);
    }
    return vi;
}

fn fill(isel: *Select, dst_ra: Register.Alias) codegen.Error!bool {
    switch (dst_ra) {
        else => {},
        Register.Alias.fp, .zr, .sp, .pc, .fpcr, .fpsr, .ffr => return false,
    }
    const dst_live_vi = isel.live_registers.getPtr(dst_ra);
    const dst_vi = switch (dst_live_vi.*) {
        _ => |dst_vi| dst_vi,
        .allocating => return false,
        .free => return true,
    };
    const src_ra = src_ra: {
        if (dst_vi.hint(isel)) |hint_ra| {
            assert(dst_live_vi.* == dst_vi);
            dst_live_vi.* = .allocating;
            defer dst_live_vi.* = dst_vi;
            if (try isel.fill(hint_ra)) {
                isel.saved_registers.insert(hint_ra);
                break :src_ra hint_ra;
            }
        }
        switch (if (dst_vi.isVector(isel)) isel.tryAllocVecReg() else isel.tryAllocIntReg()) {
            .allocated => |ra| break :src_ra ra,
            .fill_candidate, .out_of_registers => return isel.fillMemory(dst_ra),
        }
    };
    try dst_vi.liveIn(isel, src_ra, comptime &.initFill(.free));
    const src_live_vi = isel.live_registers.getPtr(src_ra);
    assert(src_live_vi.* == .allocating);
    src_live_vi.* = dst_vi;
    return true;
}

fn fillMemory(isel: *Select, dst_ra: Register.Alias) codegen.Error!bool {
    const dst_live_vi = isel.live_registers.getPtr(dst_ra);
    const dst_vi = switch (dst_live_vi.*) {
        _ => |dst_vi| dst_vi,
        .allocating => return false,
        .free => return true,
    };
    const dst_vi_ra = &dst_vi.get(isel).location_payload.small.register;
    assert(dst_vi_ra.* == dst_ra);
    dst_live_vi.* = .allocating;
    const base_ra = if (dst_ra.isVector()) try isel.allocIntReg() else dst_ra;
    try isel.loadReg(dst_ra, dst_vi.size(isel), dst_vi.signedness(isel), base_ra, 0);
    dst_vi_ra.* = .zr;
    dst_live_vi.* = .free;
    if (base_ra != dst_ra) isel.freeReg(base_ra);
    try dst_vi.address(isel, 0, base_ra);
    if (dst_live_vi.* != .free) assert(try isel.fill(dst_ra));
    return true;
}

/// Merges possibly differing value tracking into a consistent state.
///
/// At a conditional branch, if a value is expected in the same register on both
/// paths, or only expected in a register on only one path, tracking is updated:
///
///     $0 -> r0 // final state is now consistent with both paths
///      b.cond else
///     then:
///     $0 -> r0 // updated if not already consistent with else
///      ...
///      b end
///     else:
///     $0 -> r0
///      ...
///     end:
///
/// At a conditional branch, if a value is expected in different registers on
/// each path, mov instructions are emitted:
///
///     $0 -> r0 // final state is now consistent with both paths
///      b.cond else
///     then:
///     $0 -> r0 // updated to be consistent with else
///      mov x1, x0 // emitted to merge the inconsistent states
///     $0 -> r1
///      ...
///      b end
///     else:
///     $0 -> r0
///      ...
///     end:
///
/// At a loop, a value that is expected in a register at the repeats is updated:
///
///     $0 -> r0 // final state is now consistent with all paths
///     loop:
///     $0 -> r0 // updated to be consistent with the repeats
///      ...
///     $0 -> r0
///      b.cond loop
///      ...
///     $0 -> r0
///      b loop
///
/// At a loop, a value that is expected in a register at the top is filled:
///
///     $0 -> [sp, #A] // final state is now consistent with all paths
///     loop:
///     $0 -> [sp, #A] // updated to be consistent with the repeats
///      ldr x0, [sp, #A] // emitted to merge the inconsistent states
///     $0 -> r0
///      ...
///     $0 -> [sp, #A]
///      b.cond loop
///      ...
///     $0 -> [sp, #A]
///      b loop
///
/// At a loop, if a value that is expected in different registers on each path,
/// mov instructions are emitted:
///
///     $0 -> r0 // final state is now consistent with all paths
///     loop:
///     $0 -> r0 // updated to be consistent with the repeats
///      mov x1, x0 // emitted to merge the inconsistent states
///     $0 -> r1
///      ...
///     $0 -> r0
///      b.cond loop
///      ...
///     $0 -> r0
///      b loop
fn merge(
    isel: *Select,
    expected_live_registers: *const LiveRegisters,
    comptime opts: struct { fill_extra: bool = false },
) !void {
    var live_reg_it = isel.live_registers.iterator();
    while (live_reg_it.next()) |live_reg_entry| {
        const expected_vi = expected_live_registers.get(live_reg_entry.key);
        switch (expected_vi) {
            _ => try expected_vi.splitAncestorRegs(isel),
            .allocating, .free => {},
        }
    }
    live_reg_it = isel.live_registers.iterator();
    while (live_reg_it.next()) |live_reg_entry| {
        const ra = live_reg_entry.key;
        const actual_vi = live_reg_entry.value;
        const expected_vi = expected_live_registers.get(ra);
        switch (expected_vi) {
            else => switch (actual_vi.*) {
                _ => {},
                .allocating => unreachable,
                .free => actual_vi.* = .allocating,
            },
            .free => {},
        }
    }
    live_reg_it = isel.live_registers.iterator();
    while (live_reg_it.next()) |live_reg_entry| {
        const ra = live_reg_entry.key;
        const actual_vi = live_reg_entry.value;
        const expected_vi = expected_live_registers.get(ra);
        switch (expected_vi) {
            _ => {
                switch (actual_vi.*) {
                    _ => _ = if (opts.fill_extra) {
                        assert(try isel.fillMemory(ra));
                        assert(actual_vi.* == .free);
                    },
                    .allocating => actual_vi.* = .free,
                    .free => unreachable,
                }
                try expected_vi.liveIn(isel, ra, expected_live_registers);
            },
            .allocating => if (if (opts.fill_extra) try isel.fillMemory(ra) else try isel.fill(ra)) {
                assert(actual_vi.* == .free);
                actual_vi.* = .allocating;
            },
            .free => if (opts.fill_extra) assert(try isel.fillMemory(ra) and actual_vi.* == .free),
        }
    }
    live_reg_it = isel.live_registers.iterator();
    while (live_reg_it.next()) |live_reg_entry| {
        const ra = live_reg_entry.key;
        const actual_vi = live_reg_entry.value;
        const expected_vi = expected_live_registers.get(ra);
        switch (expected_vi) {
            _ => {
                assert(actual_vi.* == .allocating and expected_vi.register(isel) == ra);
                actual_vi.* = expected_vi;
            },
            .allocating => assert(actual_vi.* == .allocating),
            .free => if (opts.fill_extra) assert(actual_vi.* == .free),
        }
    }
}

const call = struct {
    const param_reg: Value.Index = @fromBackingInt(@intCast(@backingInt(Value.Index.allocating) - 2));
    const callee_clobbered_reg: Value.Index = @fromBackingInt(@intCast(@backingInt(Value.Index.allocating) - 1));
    const caller_saved_regs: LiveRegisters = .init(.{
        .r0 = param_reg,
        .r1 = param_reg,
        .r2 = param_reg,
        .r3 = param_reg,
        .r4 = param_reg,
        .r5 = param_reg,
        .r6 = param_reg,
        .r7 = param_reg,
        .r8 = param_reg,
        .r9 = callee_clobbered_reg,
        .r10 = callee_clobbered_reg,
        .r11 = callee_clobbered_reg,
        .r12 = callee_clobbered_reg,
        .r13 = callee_clobbered_reg,
        .r14 = callee_clobbered_reg,
        .r15 = callee_clobbered_reg,
        .r16 = callee_clobbered_reg,
        .r17 = callee_clobbered_reg,
        .r18 = callee_clobbered_reg,
        .r19 = .free,
        .r20 = .free,
        .r21 = .free,
        .r22 = .free,
        .r23 = .free,
        .r24 = .free,
        .r25 = .free,
        .r26 = .free,
        .r27 = .free,
        .r28 = .free,
        .r29 = .free,
        .r30 = callee_clobbered_reg,
        .zr = .free,
        .sp = .free,

        .pc = .free,

        .v0 = param_reg,
        .v1 = param_reg,
        .v2 = param_reg,
        .v3 = param_reg,
        .v4 = param_reg,
        .v5 = param_reg,
        .v6 = param_reg,
        .v7 = param_reg,
        .v8 = .free,
        .v9 = .free,
        .v10 = .free,
        .v11 = .free,
        .v12 = .free,
        .v13 = .free,
        .v14 = .free,
        .v15 = .free,
        .v16 = callee_clobbered_reg,
        .v17 = callee_clobbered_reg,
        .v18 = callee_clobbered_reg,
        .v19 = callee_clobbered_reg,
        .v20 = callee_clobbered_reg,
        .v21 = callee_clobbered_reg,
        .v22 = callee_clobbered_reg,
        .v23 = callee_clobbered_reg,
        .v24 = callee_clobbered_reg,
        .v25 = callee_clobbered_reg,
        .v26 = callee_clobbered_reg,
        .v27 = callee_clobbered_reg,
        .v28 = callee_clobbered_reg,
        .v29 = callee_clobbered_reg,
        .v30 = callee_clobbered_reg,
        .v31 = callee_clobbered_reg,

        .fpcr = .free,
        .fpsr = .free,

        .p0 = callee_clobbered_reg,
        .p1 = callee_clobbered_reg,
        .p2 = callee_clobbered_reg,
        .p3 = callee_clobbered_reg,
        .p4 = callee_clobbered_reg,
        .p5 = callee_clobbered_reg,
        .p6 = callee_clobbered_reg,
        .p7 = callee_clobbered_reg,
        .p8 = callee_clobbered_reg,
        .p9 = callee_clobbered_reg,
        .p10 = callee_clobbered_reg,
        .p11 = callee_clobbered_reg,
        .p12 = callee_clobbered_reg,
        .p13 = callee_clobbered_reg,
        .p14 = callee_clobbered_reg,
        .p15 = callee_clobbered_reg,

        .ffr = .free,
    });
    fn prepareReturn(isel: *Select) !void {
        var live_reg_it = isel.live_registers.iterator();
        while (live_reg_it.next()) |live_reg_entry| switch (caller_saved_regs.get(live_reg_entry.key)) {
            else => unreachable,
            param_reg, callee_clobbered_reg => switch (live_reg_entry.value.*) {
                _ => {},
                .allocating => unreachable,
                .free => live_reg_entry.value.* = .allocating,
            },
            .free => {},
        };
    }
    fn returnFill(isel: *Select, ra: Register.Alias) !void {
        const live_vi = isel.live_registers.getPtr(ra);
        if (try isel.fill(ra)) {
            assert(live_vi.* == .free);
            live_vi.* = .allocating;
        }
        assert(live_vi.* == .allocating);
    }
    fn returnLiveIn(isel: *Select, vi: Value.Index, ra: Register.Alias) !void {
        try vi.defLiveIn(isel, ra, &caller_saved_regs);
    }
    fn finishReturn(isel: *Select) !void {
        var live_reg_it = isel.live_registers.iterator();
        while (live_reg_it.next()) |live_reg_entry| {
            switch (live_reg_entry.value.*) {
                _ => |live_vi| switch (live_vi.size(isel)) {
                    else => unreachable,
                    1...8 => {},
                    16 => {
                        assert(try isel.fillMemory(live_reg_entry.key));
                        assert(live_reg_entry.value.* == .free);
                        switch (caller_saved_regs.get(live_reg_entry.key)) {
                            else => unreachable,
                            param_reg, callee_clobbered_reg => live_reg_entry.value.* = .allocating,
                            .free => {},
                        }
                        continue;
                    },
                },
                .allocating, .free => {},
            }
            switch (caller_saved_regs.get(live_reg_entry.key)) {
                else => unreachable,
                param_reg, callee_clobbered_reg => switch (live_reg_entry.value.*) {
                    _ => {
                        assert(try isel.fill(live_reg_entry.key));
                        assert(live_reg_entry.value.* == .free);
                        live_reg_entry.value.* = .allocating;
                    },
                    .allocating => {},
                    .free => live_reg_entry.value.* = .allocating,
                },
                .free => {},
            }
        }
    }
    fn prepareCallee(isel: *Select) !void {
        var live_reg_it = isel.live_registers.iterator();
        while (live_reg_it.next()) |live_reg_entry| switch (caller_saved_regs.get(live_reg_entry.key)) {
            else => unreachable,
            param_reg => assert(live_reg_entry.value.* == .allocating),
            callee_clobbered_reg => isel.freeReg(live_reg_entry.key),
            .free => {},
        };
    }
    fn finishCallee(_: *Select) !void {}
    fn prepareParams(_: *Select) !void {}
    fn paramLiveOut(isel: *Select, vi: Value.Index, ra: Register.Alias) !void {
        isel.freeReg(ra);
        try vi.liveOut(isel, ra);
        const live_vi = isel.live_registers.getPtr(ra);
        if (live_vi.* == .free) live_vi.* = .allocating;
    }
    fn paramAddress(isel: *Select, vi: Value.Index, ra: Register.Alias) !void {
        return paramAddressOffset(isel, vi, 0, ra);
    }
    fn paramAddressOffset(isel: *Select, vi: Value.Index, offset: u64, ra: Register.Alias) !void {
        isel.freeReg(ra);
        try vi.address(isel, offset, ra);
        const live_vi = isel.live_registers.getPtr(ra);
        if (live_vi.* == .free) live_vi.* = .allocating;
    }
    fn finishParams(isel: *Select) !void {
        var live_reg_it = isel.live_registers.iterator();
        while (live_reg_it.next()) |live_reg_entry| switch (caller_saved_regs.get(live_reg_entry.key)) {
            else => unreachable,
            param_reg => switch (live_reg_entry.value.*) {
                _ => {},
                .allocating => live_reg_entry.value.* = .free,
                .free => unreachable,
            },
            callee_clobbered_reg, .free => {},
        };
    }
};

pub const CallAbiIterator = struct {
    /// Next General-purpose Register Number
    ngrn: Register.Alias,
    /// Next SIMD and Floating-point Register Number
    nsrn: Register.Alias,
    /// next stacked argument address
    nsaa: u24,

    pub const ngrn_start: Register.Alias = .r0;
    pub const ngrn_end: Register.Alias = .r8;
    pub const nsrn_start: Register.Alias = .v0;
    pub const nsrn_end: Register.Alias = .v8;
    pub const nsaa_start: u42 = 0;

    pub const init: CallAbiIterator = .{
        // A.1
        .ngrn = ngrn_start,
        // A.2
        .nsrn = nsrn_start,
        // A.3
        .nsaa = nsaa_start,
    };

    pub fn param(it: *CallAbiIterator, isel: *Select, initial_ty: ZigType) !?Value.Index {
        const zcu = isel.pt.zcu;
        const ip = &zcu.intern_pool;

        var ty = initial_ty;
        if (!ty.hasRuntimeBits(zcu)) return null;
        try isel.values.ensureUnusedCapacity(zcu.gpa, Value.max_parts);
        const wip_vi = isel.initValue(ty);
        type_key: switch (ip.indexToKey(ty.toIntern())) {
            else => return isel.fail("CallAbiIterator.param({f})", .{isel.fmtType(ty)}),
            .int_type => |int_type| switch (int_type.bits) {
                0 => unreachable,
                1...16 => {
                    wip_vi.setSignedness(isel, int_type.signedness);
                    // C.7
                    it.integer(isel, wip_vi);
                },
                // C.7
                17...64 => it.integer(isel, wip_vi),
                // C.9
                65...128 => it.integers(isel, wip_vi, @splat(@divExact(wip_vi.size(isel), 2))),
                else => it.indirect(isel, wip_vi),
            },
            .array_type => switch (wip_vi.size(isel)) {
                0 => unreachable,
                1...8 => it.integer(isel, wip_vi),
                9...16 => |size| it.integers(isel, wip_vi, .{ 8, size - 8 }),
                else => it.indirect(isel, wip_vi),
            },
            .vector_type => switch (wip_vi.size(isel)) {
                0 => unreachable,
                1...7 => it.integer(isel, wip_vi),
                8, 16 => it.vector(isel, wip_vi),
                9...15 => |size| it.integers(isel, wip_vi, .{ 8, size - 8 }),
                else => it.indirect(isel, wip_vi),
            },
            .ptr_type => |ptr_type| switch (ptr_type.flags.size) {
                .one, .many, .c => continue :type_key .{ .int_type = .{
                    .signedness = .unsigned,
                    .bits = 64,
                } },
                .slice => it.integers(isel, wip_vi, @splat(8)),
            },
            .opt_type => |child_type| if (ty.optionalReprIsPayload(zcu)) {
                ty = .fromInterned(child_type);
                continue :type_key ip.indexToKey(child_type);
            } else switch (ZigType.fromInterned(child_type).abiSize(zcu)) {
                0 => continue :type_key .{ .simple_type = .bool },
                1...7 => it.integer(isel, wip_vi),
                8...15 => |child_size| it.integers(isel, wip_vi, .{ 8, child_size - 7 }),
                else => it.indirect(isel, wip_vi),
            },
            .anyframe_type => unreachable,
            .error_union_type => |error_union_type| switch (wip_vi.size(isel)) {
                0 => unreachable,
                1...8 => it.integer(isel, wip_vi),
                9...16 => {
                    var sizes: [2]u64 = @splat(0);
                    const payload_ty: ZigType = .fromInterned(error_union_type.payload_type);
                    {
                        const error_set_ty: ZigType = .fromInterned(error_union_type.error_set_type);
                        const offset = codegen.errUnionErrorOffset(payload_ty, zcu);
                        const end = offset % 8 + error_set_ty.abiSize(zcu);
                        const part_index: usize = @intCast(offset / 8);
                        sizes[part_index] = @max(sizes[part_index], @min(end, 8));
                        if (end > 8) sizes[part_index + 1] = @max(sizes[part_index + 1], end - 8);
                    }
                    {
                        const offset = codegen.errUnionPayloadOffset(payload_ty, zcu);
                        const end = offset % 8 + payload_ty.abiSize(zcu);
                        const part_index: usize = @intCast(offset / 8);
                        sizes[part_index] = @max(sizes[part_index], @min(end, 8));
                        if (end > 8) sizes[part_index + 1] = @max(sizes[part_index + 1], end - 8);
                    }
                    it.integers(isel, wip_vi, sizes);
                },
                else => it.indirect(isel, wip_vi),
            },
            .simple_type => |simple_type| switch (simple_type) {
                .f16, .f32, .f64, .f128, .c_longdouble => it.vector(isel, wip_vi),
                .f80 => continue :type_key .{ .int_type = .{ .signedness = .unsigned, .bits = 80 } },
                .usize,
                .isize,
                .c_char,
                .c_short,
                .c_ushort,
                .c_int,
                .c_uint,
                .c_long,
                .c_ulong,
                .c_longlong,
                .c_ulonglong,
                => continue :type_key .{ .int_type = ty.intInfo(zcu) },
                // B.1
                .anyopaque => it.indirect(isel, wip_vi),
                .bool => continue :type_key .{ .int_type = .{ .signedness = .unsigned, .bits = 1 } },
                .anyerror => continue :type_key .{ .int_type = .{
                    .signedness = .unsigned,
                    .bits = zcu.errorSetBits(),
                } },
                .void,
                .type,
                .comptime_int,
                .comptime_float,
                .noreturn,
                .null,
                .undefined,
                .enum_literal,
                .adhoc_inferred_error_set,
                .generic_poison,
                => unreachable,
            },
            .struct_type => {
                const loaded_struct = ip.loadStructType(ty.toIntern());
                switch (loaded_struct.layout) {
                    .auto, .@"extern" => {},
                    .@"packed" => continue :type_key ip.indexToKey(loaded_struct.packed_backing_int_type),
                }
                const size = wip_vi.size(isel);
                if (size <= 16 * 4) homogeneous_aggregate: {
                    const fdt = homogeneousStructBaseType(zcu, &loaded_struct) orelse break :homogeneous_aggregate;
                    const parts_len = @shrExact(size, fdt.log2Size());
                    if (parts_len > 4) break :homogeneous_aggregate;
                    it.vectors(isel, wip_vi, fdt, @intCast(parts_len));
                    break :type_key;
                }
                switch (size) {
                    0 => unreachable,
                    1...8 => it.integer(isel, wip_vi),
                    9...16 => {
                        var part_offset: u64 = 0;
                        var part_sizes: [2]u64 = undefined;
                        var parts_len: Value.PartsLen = 0;
                        var next_field_end: u64 = 0;
                        var field_it = loaded_struct.iterateRuntimeOrder(ip);
                        while (part_offset < size) {
                            const field_end = next_field_end;
                            const next_field_begin = while (field_it.next()) |field_index| {
                                if (loaded_struct.field_is_comptime_bits.get(ip, field_index)) continue;
                                const field_ty: ZigType = .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                                const field_size = field_ty.abiSize(zcu);
                                if (field_size == 0) continue;
                                const next_field_begin = switch (loaded_struct.field_aligns.getOrNone(ip, field_index)) {
                                    .none => field_ty.abiAlignment(zcu),
                                    else => |field_align| field_align,
                                }.forward(field_end);
                                if (next_field_begin == 0 and field_size == size) {
                                    ty = field_ty;
                                    continue :type_key ip.indexToKey(field_ty.toIntern());
                                }
                                next_field_end = next_field_begin + field_size;
                                break next_field_begin;
                            } else std.mem.alignForward(u64, size, 8);
                            while (next_field_begin - part_offset >= 8) {
                                const part_size = @min(field_end - part_offset, 8);
                                part_sizes[parts_len] = part_size;
                                assert(part_offset + part_size <= size);
                                parts_len += 1;
                                part_offset += part_size;
                                if (part_offset >= field_end) part_offset = next_field_begin;
                            }
                        }
                        assert(parts_len == part_sizes.len);
                        it.integers(isel, wip_vi, part_sizes);
                    },
                    else => it.indirect(isel, wip_vi),
                }
            },
            .tuple_type => |tuple_type| {
                const size = wip_vi.size(isel);
                if (size <= 16 * 4) homogeneous_aggregate: {
                    const fdt = homogeneousTupleBaseType(zcu, tuple_type) orelse break :homogeneous_aggregate;
                    const parts_len = @shrExact(size, fdt.log2Size());
                    if (parts_len > 4) break :homogeneous_aggregate;
                    it.vectors(isel, wip_vi, fdt, @intCast(parts_len));
                    break :type_key;
                }
                switch (size) {
                    0 => unreachable,
                    1...8 => it.integer(isel, wip_vi),
                    9...16 => {
                        var part_offset: u64 = 0;
                        var part_sizes: [2]u64 = undefined;
                        var parts_len: Value.PartsLen = 0;
                        var next_field_end: u64 = 0;
                        var field_index: usize = 0;
                        while (part_offset < size) {
                            const field_end = next_field_end;
                            const next_field_begin = while (field_index < tuple_type.types.len) {
                                defer field_index += 1;
                                if (tuple_type.values.get(ip)[field_index] != .none) continue;
                                const field_ty: ZigType = .fromInterned(tuple_type.types.get(ip)[field_index]);
                                const field_size = field_ty.abiSize(zcu);
                                if (field_size == 0) continue;
                                const next_field_begin = field_ty.abiAlignment(zcu).forward(field_end);
                                if (next_field_begin == 0 and field_size == size) {
                                    ty = field_ty;
                                    continue :type_key ip.indexToKey(field_ty.toIntern());
                                }
                                next_field_end = next_field_begin + field_size;
                                break next_field_begin;
                            } else std.mem.alignForward(u64, size, 8);
                            while (next_field_begin - part_offset >= 8) {
                                const part_size = @min(field_end - part_offset, 8);
                                part_sizes[parts_len] = part_size;
                                assert(part_offset + part_size <= size);
                                parts_len += 1;
                                part_offset += part_size;
                                if (part_offset >= field_end) part_offset = next_field_begin;
                            }
                        }
                        assert(parts_len == part_sizes.len);
                        it.integers(isel, wip_vi, part_sizes);
                    },
                    else => it.indirect(isel, wip_vi),
                }
            },
            .union_type => {
                const loaded_union = ip.loadUnionType(ty.toIntern());
                switch (loaded_union.layout) {
                    .auto, .@"extern" => {},
                    .@"packed" => continue :type_key .{ .int_type = .{
                        .signedness = .unsigned,
                        .bits = @intCast(ty.bitSize(zcu)),
                    } },
                }
                switch (wip_vi.size(isel)) {
                    0 => unreachable,
                    1...8 => it.integer(isel, wip_vi),
                    9...16 => {
                        const union_layout = ZigType.getUnionLayout(loaded_union, zcu);
                        var sizes: [2]u64 = @splat(0);
                        if (union_layout.tag_size > 0) {
                            const offset = union_layout.tagOffset();
                            const end = offset % 8 + union_layout.tag_size;
                            const part_index: usize = @intCast(offset / 8);
                            sizes[part_index] = @max(sizes[part_index], @min(end, 8));
                            if (end > 8) sizes[part_index + 1] = @max(sizes[part_index + 1], end - 8);
                        }
                        if (union_layout.payload_size > 0) {
                            const offset = union_layout.payloadOffset();
                            const end = offset % 8 + union_layout.payload_size;
                            const part_index: usize = @intCast(offset / 8);
                            sizes[part_index] = @max(sizes[part_index], @min(end, 8));
                            if (end > 8) sizes[part_index + 1] = @max(sizes[part_index + 1], end - 8);
                        }
                        it.integers(isel, wip_vi, sizes);
                    },
                    else => it.indirect(isel, wip_vi),
                }
            },
            .opaque_type, .func_type => continue :type_key .{ .simple_type = .anyopaque },
            .enum_type => continue :type_key ip.indexToKey(ip.loadEnumType(ty.toIntern()).int_tag_type),
            .error_set_type,
            .inferred_error_set_type,
            => continue :type_key .{ .simple_type = .anyerror },
            .undef,
            .simple_value,
            .@"extern",
            .func,
            .int,
            .err,
            .error_union,
            .enum_literal,
            .enum_tag,
            .float,
            .ptr,
            .slice,
            .opt,
            .aggregate,
            .un,
            .memoized_call,
            => unreachable, // values, not types
        }
        return wip_vi.ref(isel);
    }

    pub fn nonSysvVarArg(it: *CallAbiIterator, isel: *Select, ty: ZigType) !?Value.Index {
        const ngrn = it.ngrn;
        defer it.ngrn = ngrn;
        it.ngrn = ngrn_end;
        const nsrn = it.nsrn;
        defer it.nsrn = nsrn;
        it.nsrn = nsrn_end;
        return it.param(isel, ty);
    }

    pub fn ret(it: *CallAbiIterator, isel: *Select, ty: ZigType) !?Value.Index {
        const wip_vi = try it.param(isel, ty) orelse return null;
        switch (wip_vi.parent(isel)) {
            .unallocated, .stack_slot => {},
            .value, .constant => unreachable,
            .address => |address_vi| {
                assert(address_vi.hint(isel) == ngrn_start);
                address_vi.setHint(isel, ngrn_end);
            },
        }
        return wip_vi;
    }

    pub const FundamentalDataType = enum {
        half,
        single,
        double,
        quad,
        vector64,
        vector128,
        fn log2Size(fdt: FundamentalDataType) u3 {
            return switch (fdt) {
                .half => 1,
                .single => 2,
                .double, .vector64 => 3,
                .quad, .vector128 => 4,
            };
        }
        fn size(fdt: FundamentalDataType) u64 {
            return @as(u64, 1) << fdt.log2Size();
        }
    };
    fn homogeneousAggregateBaseType(zcu: *Zcu, initial_ty: InternPool.Index) ?FundamentalDataType {
        const ip = &zcu.intern_pool;
        var ty = initial_ty;
        return type_key: switch (ip.indexToKey(ty)) {
            else => null,
            .array_type => |array_type| {
                ty = array_type.child;
                continue :type_key ip.indexToKey(ty);
            },
            .vector_type => switch (ZigType.fromInterned(ty).abiSize(zcu)) {
                else => null,
                8 => .vector64,
                16 => .vector128,
            },
            .simple_type => |simple_type| switch (simple_type) {
                .f16 => .half,
                .f32 => .single,
                .f64 => .double,
                .f128 => .quad,
                .c_longdouble => switch (zcu.getTarget().cTypeBitSize(.longdouble).?) {
                    else => unreachable,
                    64 => .double,
                    80 => null,
                    128 => .quad,
                },
                else => null,
            },
            .struct_type => homogeneousStructBaseType(zcu, &ip.loadStructType(ty)),
            .tuple_type => |tuple_type| homogeneousTupleBaseType(zcu, tuple_type),
        };
    }
    fn homogeneousStructBaseType(zcu: *Zcu, loaded_struct: *const InternPool.LoadedStructType) ?FundamentalDataType {
        const ip = &zcu.intern_pool;
        var common_fdt: ?FundamentalDataType = null;
        for (0.., loaded_struct.field_types.get(ip)) |field_index, field_ty| {
            if (loaded_struct.field_is_comptime_bits.get(ip, field_index)) continue;
            if (loaded_struct.field_aligns.getOrNone(ip, field_index) != .none) return null;
            if (!ZigType.fromInterned(field_ty).hasRuntimeBits(zcu)) continue;
            const fdt = homogeneousAggregateBaseType(zcu, field_ty);
            if (common_fdt == null) common_fdt = fdt else if (fdt != common_fdt) return null;
        }
        return common_fdt;
    }
    fn homogeneousTupleBaseType(zcu: *Zcu, tuple_type: InternPool.Key.TupleType) ?FundamentalDataType {
        const ip = &zcu.intern_pool;
        var common_fdt: ?FundamentalDataType = null;
        for (tuple_type.values.get(ip), tuple_type.types.get(ip)) |field_val, field_ty| {
            if (field_val != .none) continue;
            const fdt = homogeneousAggregateBaseType(zcu, field_ty);
            if (common_fdt == null) common_fdt = fdt else if (fdt != common_fdt) return null;
        }
        return common_fdt;
    }

    const Spec = struct {
        offset: u64,
        size: u64,
    };

    fn stack(it: *CallAbiIterator, isel: *Select, wip_vi: Value.Index) void {
        // C.12
        it.nsaa = @intCast(wip_vi.alignment(isel).forward(it.nsaa));
        const parent_vi = switch (wip_vi.parent(isel)) {
            .unallocated, .stack_slot => wip_vi,
            .address, .constant => unreachable,
            .value => |parent_vi| parent_vi,
        };
        switch (parent_vi.parent(isel)) {
            .unallocated => parent_vi.setParent(isel, .{ .stack_slot = .{
                .base = .sp,
                .offset = it.nsaa,
            } }),
            .stack_slot => {},
            .address, .value, .constant => unreachable,
        }
        it.nsaa += @intCast(wip_vi.size(isel));
    }

    fn integer(it: *CallAbiIterator, isel: *Select, wip_vi: Value.Index) void {
        assert(wip_vi.size(isel) <= 8);
        const natural_alignment = wip_vi.alignment(isel);
        assert(natural_alignment.order(.@"16").compare(.lte));
        wip_vi.setAlignment(isel, natural_alignment.maxStrict(.@"8"));
        if (it.ngrn == ngrn_end) return it.stack(isel, wip_vi);
        wip_vi.setHint(isel, it.ngrn);
        it.ngrn = @fromBackingInt(@intCast(@backingInt(it.ngrn) + 1));
    }

    fn integers(it: *CallAbiIterator, isel: *Select, wip_vi: Value.Index, part_sizes: [2]u64) void {
        assert(wip_vi.size(isel) <= 16);
        const natural_alignment = wip_vi.alignment(isel);
        assert(natural_alignment.order(.@"16").compare(.lte));
        wip_vi.setAlignment(isel, natural_alignment.maxStrict(.@"8"));
        // C.8
        if (natural_alignment == .@"16") it.ngrn = @fromBackingInt(@intCast(std.mem.alignForward(
            @typeInfo(Register.Alias).@"enum".tag_type,
            @backingInt(it.ngrn),
            2,
        )));
        if (@backingInt(it.ngrn) > @backingInt(ngrn_end) - part_sizes.len) {
            it.ngrn = ngrn_end;
            return it.stack(isel, wip_vi);
        }
        wip_vi.setParts(isel, part_sizes.len);
        for (0.., part_sizes) |part_index, part_size|
            it.integer(isel, wip_vi.addPart(isel, 8 * part_index, part_size));
    }

    fn vector(it: *CallAbiIterator, isel: *Select, wip_vi: Value.Index) void {
        assert(wip_vi.size(isel) <= 16);
        const natural_alignment = wip_vi.alignment(isel);
        assert(natural_alignment.order(.@"16").compare(.lte));
        wip_vi.setAlignment(isel, natural_alignment.maxStrict(.@"8"));
        wip_vi.setIsVector(isel);
        if (it.nsrn == nsrn_end) return it.stack(isel, wip_vi);
        wip_vi.setHint(isel, it.nsrn);
        it.nsrn = @fromBackingInt(@intCast(@backingInt(it.nsrn) + 1));
    }

    fn vectors(
        it: *CallAbiIterator,
        isel: *Select,
        wip_vi: Value.Index,
        fdt: FundamentalDataType,
        parts_len: Value.PartsLen,
    ) void {
        const fdt_log2_size = fdt.log2Size();
        assert(wip_vi.size(isel) == @shlExact(@as(u9, parts_len), fdt_log2_size));
        const natural_alignment = wip_vi.alignment(isel);
        assert(natural_alignment.order(.@"16").compare(.lte));
        wip_vi.setAlignment(isel, natural_alignment.maxStrict(.@"8"));
        if (@backingInt(it.nsrn) > @backingInt(nsrn_end) - parts_len) {
            it.nsrn = nsrn_end;
            return it.stack(isel, wip_vi);
        }
        if (parts_len == 1) return it.vector(isel, wip_vi);
        wip_vi.setParts(isel, parts_len);
        const fdt_size = @as(u64, 1) << fdt_log2_size;
        for (0..parts_len) |part_index|
            it.vector(isel, wip_vi.addPart(isel, part_index << fdt_log2_size, fdt_size));
    }

    fn indirect(it: *CallAbiIterator, isel: *Select, wip_vi: Value.Index) void {
        const wip_address_vi = isel.initValue(.usize);
        wip_vi.setParent(isel, .{ .address = wip_address_vi });
        it.integer(isel, wip_address_vi);
    }
};

fn ldxr(size: u64, rt: Register.Alias, rn: Register.Alias, acquire: bool) codegen.aarch64.encoding.Instruction {
    const sz: u32 = switch (size) {
        1 => 0b00,
        2 => 0b01,
        4 => 0b10,
        8 => 0b11,
        else => unreachable,
    };
    const o0: u32 = @intFromBool(acquire);
    const rn_enc: u32 = @backingInt(rn.encode(.{ .sp = true }));
    const rt_enc: u32 = @backingInt(rt.encode(.{}));
    return @bitCast((sz << 30) | (0b001000010 << 21) | (0b11111 << 16) | (o0 << 15) | (0b11111 << 10) | (rn_enc << 5) | rt_enc);
}

fn stxr(size: u64, rs: Register.Alias, rt: Register.Alias, rn: Register.Alias, release: bool) codegen.aarch64.encoding.Instruction {
    const sz: u32 = switch (size) {
        1 => 0b00,
        2 => 0b01,
        4 => 0b10,
        8 => 0b11,
        else => unreachable,
    };
    const o0: u32 = @intFromBool(release);
    const rs_enc: u32 = @backingInt(rs.encode(.{}));
    const rn_enc: u32 = @backingInt(rn.encode(.{ .sp = true }));
    const rt_enc: u32 = @backingInt(rt.encode(.{}));
    return @bitCast((sz << 30) | (0b001000000 << 21) | (rs_enc << 16) | (o0 << 15) | (0b11111 << 10) | (rn_enc << 5) | rt_enc);
}

const Air = @import("../../Air.zig");
const assert = std.debug.assert;
const codegen = @import("../../codegen.zig");
const Constant = @import("../../Value.zig");
const InternPool = @import("../../InternPool.zig");
const Module = @import("../../Module.zig");
const Register = codegen.aarch64.encoding.Register;
const Select = @This();
const std = @import("std");
const tracking_log = std.log.scoped(.tracking);
const wip_mir_log = std.log.scoped(.@"wip-mir");
const Zcu = @import("../../Zcu.zig");
const ZigType = @import("../../Type.zig");
