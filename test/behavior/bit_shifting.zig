const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const builtin = @import("builtin");

fn ShardedTable(comptime Key: type, comptime mask_bit_count: comptime_int, comptime V: type) type {
    const key_bits = @typeInfo(Key).int.bits;
    std.debug.assert(Key == @Int(.unsigned, key_bits));
    std.debug.assert(key_bits >= mask_bit_count);
    const shard_key_bits = mask_bit_count;
    const ShardKey = @Int(.unsigned, mask_bit_count);
    const shift_amount = key_bits - shard_key_bits;
    return struct {
        const Self = @This();
        shards: [1 << shard_key_bits]?*Node,

        pub fn create() Self {
            return .{ .shards = @splat(null) };
        }

        fn getShardKey(key: Key) ShardKey {
            // https://github.com/ziglang/zig/issues/1544
            // this special case is needed because you can't u32 >> 32.
            if (ShardKey == u0) return 0;

            // this can be u1 >> u0
            const shard_key = key >> shift_amount;

            // TODO: https://github.com/ziglang/zig/issues/1544
            // This cast could be implicit if we teach the compiler that
            // u32 >> 30 -> u2
            return @as(ShardKey, @intCast(shard_key));
        }

        pub fn put(self: *Self, node: *Node) void {
            const shard_key = Self.getShardKey(node.key);
            node.next = self.shards[shard_key];
            self.shards[shard_key] = node;
        }

        pub fn get(self: *Self, key: Key) ?*Node {
            const shard_key = Self.getShardKey(key);
            var maybe_node = self.shards[shard_key];
            while (maybe_node) |node| : (maybe_node = node.next) {
                if (node.key == key) return node;
            }
            return null;
        }

        pub const Node = struct {
            key: Key,
            value: V,
            next: ?*Node,

            pub fn init(self: *Node, key: Key, value: V) void {
                self.key = key;
                self.value = value;
                self.next = null;
            }
        };
    };
}

test "sharded table" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    // realistic 16-way sharding
    try testShardedTable(u32, 4, 8);

    try testShardedTable(u5, 0, 32); // ShardKey == u0
    try testShardedTable(u5, 2, 32);
    try testShardedTable(u5, 5, 32);

    try testShardedTable(u1, 0, 2);
    try testShardedTable(u1, 1, 2); // this does u1 >> u0

    try testShardedTable(u0, 0, 1);
}

fn testShardedTable(comptime Key: type, comptime mask_bit_count: comptime_int, comptime node_count: comptime_int) !void {
    const Table = ShardedTable(Key, mask_bit_count, void);

    var table = Table.create();
    var node_buffer: [node_count]Table.Node = undefined;
    for (&node_buffer, 0..) |*node, i| {
        const key = @as(Key, @intCast(i));
        try expect(table.get(key) == null);
        node.init(key, {});
        table.put(node);
    }

    for (&node_buffer, 0..) |*node, i| {
        try expect(table.get(@as(Key, @intCast(i))) == node);
    }
}

// #2225
test "comptime shr of BigInt" {
    comptime {
        const n0 = 0xdeadbeef0000000000000000;
        try expect(n0 >> 64 == 0xdeadbeef);
        const n1 = 17908056155735594659;
        try expect(n1 >> 64 == 0);
    }
}

test "comptime shift safety check" {
    _ = @as(usize, 42) << @sizeOf(usize);
}

test "Saturating Shift Left where lhs is of a computed type" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    const S = struct {
        pub fn FixedPoint(comptime ValueType: type) type {
            return struct {
                value: ValueType,
                exponent: ShiftType,

                const ShiftType = @Int(.signed, @typeInfo(std.math.Log2Int(ValueType)).int.bits);

                pub fn shiftExponent(self: @This(), shift: ShiftType) @This() {
                    const shiftAbs = @abs(shift);
                    return .{ .value = if (shift >= 0) self.value >> shiftAbs else self.value <<| shiftAbs, .exponent = self.exponent + shift };
                }
            };
        }
    };

    const FP = S.FixedPoint(i32);

    const value = (FP{
        .value = 1,
        .exponent = 1,
    }).shiftExponent(-1);

    try expect(value.value == 2);
    try expect(value.exponent == 0);
}

test "Saturating Shift Left" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    const S = struct {
        fn shlSat(x: anytype, y: std.math.Log2Int(@TypeOf(x))) @TypeOf(x) {
            return x <<| y;
        }

        fn testType(comptime T: type) !void {
            comptime var rhs: std.math.Log2Int(T) = 0;
            inline while (true) : (rhs += 1) {
                comptime var lhs: T = std.math.minInt(T);
                inline while (true) : (lhs += 1) {
                    try expectEqual(lhs <<| rhs, shlSat(lhs, rhs));
                    if (lhs == std.math.maxInt(T)) break;
                }
                if (rhs == @bitSizeOf(T) - 1) break;
            }
        }
    };

    try S.testType(u2);
    try S.testType(i2);
    try S.testType(u3);
    try S.testType(i3);
    try S.testType(u4);
    try S.testType(i4);

    try expectEqual(0xfffffffffffffff0fffffffffffffff0, S.shlSat(@as(u128, 0x0fffffffffffffff0fffffffffffffff), 4));
    try expectEqual(0xffffffffffffffffffffffffffffffff, S.shlSat(@as(u128, 0x0fffffffffffffff0fffffffffffffff), 5));
    try expectEqual(-0x80000000000000000000000000000000, S.shlSat(@as(i128, -0x0fffffffffffffff0fffffffffffffff), 5));

    try expectEqual(51146728248377216718956089012931236753385031969422887335676427626502090568823039920051095192592252455482604439493126109519019633529459266458258243583, S.shlSat(@as(i495, 0x2fe6bc5448c55ce18252e2c9d44777505dfe63ff249a8027a6626c7d8dd9893fd5731e51474727be556f757facb586a4e04bbc0148c6c7ad692302f46fbd), 0x31));
    try expectEqual(-57896044618658097711785492504343953926634992332820282019728792003956564819968, S.shlSat(@as(i256, -0x53d4148cee74ea43477a65b3daa7b8fdadcbf4508e793f4af113b8d8da5a7eb6), 0x91));
    try expectEqual(170141183460469231731687303715884105727, S.shlSat(@as(i128, 0x2fe6bc5448c55ce18252e2c9d4477750), 0x31));
    try expectEqual(0, S.shlSat(@as(i128, 0), 127));
}

test "128-bit and 72-bit shifts with constant and runtime shift amounts" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    const S = struct {
        fn checkShifts(comptime T: type, comptime val: T, comptime shifts: anytype) !void {
            var rt_val: T = val;
            _ = &rt_val;
            inline for (shifts) |s| {
                const expected_shl: T = comptime (val << s);
                const expected_shr: T = comptime (val >> s);

                // Constant shift amount with runtime lhs
                try expectEqual(expected_shl, rt_val << s);
                try expectEqual(expected_shr, rt_val >> s);

                // Runtime shift amount with runtime lhs
                var rt_s: std.math.Log2Int(T) = s;
                _ = &rt_s;
                try expectEqual(expected_shl, rt_val << rt_s);
                try expectEqual(expected_shr, rt_val >> rt_s);
            }
        }

        fn doTheTest() !void {
            @setEvalBranchQuota(10000);
            const shifts_128 = .{ 0, 1, 31, 32, 63, 64, 65, 96, 127 };
            const shifts_72 = .{ 0, 1, 31, 32, 63, 64, 65, 71 };

            const u128_vals = .{
                @as(u128, 0),
                @as(u128, 1),
                @as(u128, 0x01234567_89abcdef_fedcba98_76543211),
                @as(u128, 0xfedcba98_76543210_01234567_89abcdef),
                std.math.maxInt(u128),
            };
            inline for (u128_vals) |v| {
                try checkShifts(u128, v, shifts_128);
            }

            const i128_vals = .{
                @as(i128, 0),
                @as(i128, 1),
                @as(i128, -1),
                @as(i128, 0x01234567_89abcdef_fedcba98_76543211),
                @as(i128, -0x01234567_89abcdef_fedcba98_76543211),
                std.math.minInt(i128),
                std.math.maxInt(i128),
            };
            inline for (i128_vals) |v| {
                try checkShifts(i128, v, shifts_128);
            }

            const u72_vals = .{
                @as(u72, 0),
                @as(u72, 1),
                @as(u72, 0xa5_fedcba98_76543211),
                std.math.maxInt(u72),
            };
            inline for (u72_vals) |v| {
                try checkShifts(u72, v, shifts_72);
            }

            const i72_vals = .{
                @as(i72, 0),
                @as(i72, 1),
                @as(i72, -1),
                @as(i72, 0x25_fedcba98_76543211),
                @as(i72, -0x25_fedcba98_76543211),
                std.math.minInt(i72),
                std.math.maxInt(i72),
            };
            inline for (i72_vals) |v| {
                try checkShifts(i72, v, shifts_72);
            }

            // Explicit cross-limb carry and sign-extension checks
            var u: u128 = 0x01234567_89abcdef_fedcba98_76543210;
            var neg: i128 = -0x01234567_89abcdef_fedcba98_76543210;
            var s0: u7 = 0;
            var s1: u7 = 1;
            var s64: u7 = 64;
            var s65: u7 = 65;
            var s127: u7 = 127;
            _ = .{ &u, &neg, &s0, &s1, &s64, &s65, &s127 };

            try expectEqual(@as(u128, 0x01234567_89abcdef_fedcba98_76543210), u << s0);
            try expectEqual(@as(u128, 0x02468acf_13579bdf_fdb97530_eca86420), u << s1);
            try expectEqual(@as(u128, 0xfedcba98_76543210_00000000_00000000), u << s64);
            try expectEqual(@as(u128, 0xfdb97530_eca86420_00000000_00000000), u << s65);
            try expectEqual(@as(u128, 0x0091a2b3_c4d5e6f7_ff6e5d4c_3b2a1908), u >> s1);
            try expectEqual(@as(u128, 0x00000000_00000000_01234567_89abcdef), u >> s64);
            try expectEqual(@as(u128, 0x00000000_00000000_0091a2b3_c4d5e6f7), u >> s65);
            try expectEqual(@as(i128, -1), neg >> s127);
            try expectEqual(@as(i128, -1), neg >> 127);
        }
    };

    try S.doTheTest();
    try comptime S.doTheTest();
}
