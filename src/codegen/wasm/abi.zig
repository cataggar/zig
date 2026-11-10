//! Classifies Zig types to follow the C-ABI for Wasm.
//! The convention for Wasm's C-ABI can be found at the tool-conventions repo:
//! https://github.com/WebAssembly/tool-conventions/blob/main/BasicCABI.md
//! When not targeting the C-ABI, Zig is allowed to do derail from this convention.
//! Note: Above mentioned document is not an official specification, therefore called a convention.

const std = @import("std");
const Target = std.Target;
const assert = std.debug.assert;

const Type = @import("../../Type.zig");
const Zcu = @import("../../Zcu.zig");

/// Describes how the Wasm backend represents a C ABI value.
pub const Class = union(enum) {
    direct: Type,
    double_i64,
    indirect,
    unrolled: struct {
        elem_type: Type,
        len: u32,
    },
};

pub const LlvmClass = union(enum) {
    direct: Type,
    indirect,
};

pub const max_multivalue_param_fields = 2;
pub const max_multivalue_param_wasm_vals = 32;
pub const max_multivalue_return_fields = 100;
pub const max_multivalue_return_wasm_vals = max_multivalue_return_fields * 2;

pub const MultiValueField = struct {
    offset: u32,
    ty: Type,
};

pub const MultiValueParamClass = union(enum) {
    direct: Type,
    double_i64,
    fields: struct {
        len: u8,
        items: [max_multivalue_param_wasm_vals]MultiValueField,
    },
    indirect,
    unrolled: struct {
        elem_type: Type,
        len: u32,
    },
};

pub const MultiValueReturnClass = union(enum) {
    direct: Type,
    fields: struct {
        len: u8,
        items: [max_multivalue_return_wasm_vals]MultiValueField,
    },
    indirect,
    unrolled: struct {
        elem_type: Type,
        len: u32,
    },
};

fn collectMultiValueStructFields(
    ty: Type,
    zcu: *const Zcu,
    target: *const Target,
    max_scalar_fields: usize,
    items: []MultiValueField,
    wasm_count: *usize,
    scalar_field_count: *usize,
) bool {
    const ip = &zcu.intern_pool;
    const struct_type = zcu.typeToStruct(ty).?;
    if (struct_type.layout != .@"extern") return false;
    for (struct_type.field_types.get(ip), 0..) |field_ty_index, field_index| {
        const field_ty: Type = .fromInterned(field_ty_index);
        if (!field_ty.hasRuntimeBits(zcu)) continue;

        const field_align = struct_type.field_aligns.getOrNone(ip, field_index);
        if (field_align != .none and field_align.compareStrict(.gt, field_ty.abiAlignment(zcu))) {
            return false;
        }
        if (field_ty.zigTypeTag(zcu) == .@"union" and zcu.typeToUnion(field_ty).?.layout != .@"packed") {
            return false;
        }
        const field_off: u32 = @intCast(ty.structFieldOffset(field_index, zcu));
        switch (classifyType(field_ty, zcu, target)) {
            .direct => |scalar_ty| {
                scalar_field_count.* += 1;
                if (scalar_field_count.* > max_scalar_fields) return false;
                if (wasm_count.* >= items.len) return false;
                items[wasm_count.*] = .{ .offset = field_off, .ty = scalar_ty };
                wasm_count.* += 1;
            },
            .double_i64 => {
                scalar_field_count.* += 1;
                if (scalar_field_count.* > max_scalar_fields) return false;
                if (wasm_count.* + 2 > items.len) return false;
                items[wasm_count.*] = .{ .offset = field_off, .ty = .u64 };
                items[wasm_count.* + 1] = .{ .offset = field_off + 8, .ty = .u64 };
                wasm_count.* += 2;
            },
            .unrolled => |vec| {
                scalar_field_count.* += 1;
                if (scalar_field_count.* > max_scalar_fields) return false;
                if (wasm_count.* + vec.len > items.len) return false;
                const elem_size: u32 = @intCast(vec.elem_type.abiSize(zcu));
                for (0..vec.len) |idx| {
                    items[wasm_count.*] = .{
                        .offset = field_off + @as(u32, @intCast(idx)) * elem_size,
                        .ty = vec.elem_type,
                    };
                    wasm_count.* += 1;
                }
            },
            .indirect => return false,
        }
    }
    return true;
}

pub fn classifyParamMultiValue(ty: Type, zcu: *const Zcu, target: *const Target) MultiValueParamClass {
    switch (classifyType(ty, zcu, target)) {
        .direct => |scalar_ty| return .{ .direct = scalar_ty },
        .double_i64 => return .double_i64,
        .unrolled => |vec| return .{ .unrolled = .{ .elem_type = vec.elem_type, .len = vec.len } },
        .indirect => {},
    }

    if (ty.zigTypeTag(zcu) == .@"struct" and zcu.typeToStruct(ty).?.layout == .@"extern") {
        var items: [max_multivalue_param_wasm_vals]MultiValueField = undefined;
        var wasm_count: usize = 0;
        var scalar_field_count: usize = 0;
        if (collectMultiValueStructFields(
            ty,
            zcu,
            target,
            max_multivalue_param_fields,
            &items,
            &wasm_count,
            &scalar_field_count,
        ) and scalar_field_count == max_multivalue_param_fields) {
            if (wasm_count == 2 and items[0].offset == 0 and items[1].offset == 8 and
                items[0].ty.toIntern() == .u64_type and items[1].ty.toIntern() == .u64_type)
            {
                return .double_i64;
            }
            return .{ .fields = .{
                .len = @intCast(wasm_count),
                .items = items,
            } };
        }
    }

    return .indirect;
}

pub fn classifyReturnMultiValue(ty: Type, zcu: *const Zcu, target: *const Target) MultiValueReturnClass {
    switch (classifyType(ty, zcu, target)) {
        .direct => |scalar_ty| return .{ .direct = scalar_ty },
        .double_i64 => {
            var items: [max_multivalue_return_wasm_vals]MultiValueField = undefined;
            items[0] = .{ .offset = 0, .ty = .u64 };
            items[1] = .{ .offset = 8, .ty = .u64 };
            return .{ .fields = .{
                .len = 2,
                .items = items,
            } };
        },
        .unrolled => |vec| return .{ .unrolled = .{ .elem_type = vec.elem_type, .len = vec.len } },
        .indirect => {},
    }

    if (ty.zigTypeTag(zcu) == .@"struct" and zcu.typeToStruct(ty).?.layout == .@"extern") {
        var items: [max_multivalue_return_wasm_vals]MultiValueField = undefined;
        var wasm_count: usize = 0;
        var scalar_field_count: usize = 0;
        if (collectMultiValueStructFields(
            ty,
            zcu,
            target,
            max_multivalue_return_fields,
            &items,
            &wasm_count,
            &scalar_field_count,
        ) and scalar_field_count >= 1 and scalar_field_count <= max_multivalue_return_fields and wasm_count > 0) {
            if (wasm_count == 1 and items[0].offset == 0) {
                return .{ .direct = items[0].ty };
            }
            return .{ .fields = .{
                .len = @intCast(wasm_count),
                .items = items,
            } };
        }
    }

    return .indirect;
}

pub fn classifyType(ty: Type, zcu: *const Zcu, target: *const Target) Class {
    if (ty.zigTypeTag(zcu) == .vector) {
        const elem_type = ty.childType(zcu);
        const is_v128 = (target.cpu.has(.wasm, .simd128) or target.cpu.has(.wasm, .relaxed_simd)) and
            ty.bitSize(zcu) == 128 and ty.abiSize(zcu) == 16 and
            switch (elem_type.bitSize(zcu)) {
                8, 16, 32, 64 => true,
                else => false,
            };
        if (!is_v128) {
            return .{ .unrolled = .{
                .elem_type = elem_type,
                .len = ty.vectorLen(zcu),
            } };
        }
        return .{ .direct = ty };
    }

    return switch (classifyTypeForLlvm(ty, zcu)) {
        .direct => |scalar_ty| if (scalar_ty.zigTypeTag(zcu) == .vector)
            classifyType(scalar_ty, zcu, target)
        else if (scalar_ty.bitSize(zcu) > 64)
            .double_i64
        else
            .{ .direct = scalar_ty },
        .indirect => .indirect,
    };
}

pub fn classifyTypeForLlvm(ty: Type, zcu: *const Zcu) LlvmClass {
    const ip = &zcu.intern_pool;
    assert(ty.hasRuntimeBits(zcu));
    switch (ty.zigTypeTag(zcu)) {
        .int, .@"enum", .error_set => return .{ .direct = ty },
        .float => return switch (ty.floatBits(zcu.getTarget())) {
            else => unreachable,
            16, 32, 64, 128 => .{ .direct = ty },
            80 => .indirect,
        },
        .bool => return .{ .direct = ty },
        .vector => return .{ .direct = ty },
        .array => return .indirect,
        .optional => {
            assert(ty.isPtrLikeOptional(zcu));
            return .{ .direct = ty };
        },
        .pointer => {
            assert(!ty.isSlice(zcu));
            return .{ .direct = ty };
        },
        .@"struct" => {
            const struct_type = zcu.typeToStruct(ty).?;
            switch (struct_type.layout) {
                .auto => unreachable,
                .@"packed" => return .{ .direct = ty },
                .@"extern" => {},
            }
            var opt_single_field_ty: ?Type = null;
            for (struct_type.field_types.get(ip), 0..) |field_ty_index, field_index| {
                const field_ty: Type = .fromInterned(field_ty_index);
                if (!field_ty.hasRuntimeBits(zcu)) continue;

                if (opt_single_field_ty != null) {
                    return .indirect;
                }

                const field_align = struct_type.field_aligns.getOrNone(ip, field_index);
                if (field_align != .none and field_align.compareStrict(.gt, field_ty.abiAlignment(zcu))) {
                    return .indirect;
                }
                opt_single_field_ty = field_ty;
            }
            const single_field_ty = opt_single_field_ty.?;
            if (single_field_ty.zigTypeTag(zcu) == .array) {
                switch (single_field_ty.arrayLenIncludingSentinel(zcu)) {
                    0 => unreachable,
                    1 => return classifyTypeForLlvm(single_field_ty.childType(zcu), zcu),
                    else => {},
                }
            }
            return classifyTypeForLlvm(single_field_ty, zcu);
        },
        .@"union" => {
            const union_obj = zcu.typeToUnion(ty).?;
            if (union_obj.layout == .@"packed") {
                return .{ .direct = ty };
            }
            const layout = ty.unionGetLayout(zcu);
            assert(layout.tag_size == 0);
            if (union_obj.field_types.len > 1) return .indirect;
            const first_field_ty = Type.fromInterned(union_obj.field_types.get(ip)[0]);
            if (first_field_ty.zigTypeTag(zcu) == .array) {
                switch (first_field_ty.arrayLenIncludingSentinel(zcu)) {
                    0 => unreachable,
                    1 => return classifyTypeForLlvm(first_field_ty.childType(zcu), zcu),
                    else => {},
                }
            }
            return classifyTypeForLlvm(first_field_ty, zcu);
        },
        .error_union,
        .frame,
        .@"anyframe",
        .noreturn,
        .void,
        .type,
        .comptime_float,
        .comptime_int,
        .undefined,
        .null,
        .@"fn",
        .@"opaque",
        .spirv,
        .enum_literal,
        => unreachable,
    }
}
