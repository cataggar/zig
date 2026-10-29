const builtin = @import("builtin");
const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "if statements" {
    shouldBeEqual(1, 1);
    firstEqlThird(2, 1, 2);
}
fn shouldBeEqual(a: i32, b: i32) void {
    if (a != b) {
        unreachable;
    } else {
        return;
    }
}
fn firstEqlThird(a: i32, b: i32, c: i32) void {
    if (a == b) {
        unreachable;
    } else if (b == c) {
        unreachable;
    } else if (a == c) {
        return;
    } else {
        unreachable;
    }
}

test "else if expression" {
    try expect(elseIfExpressionF(1) == 1);
}
fn elseIfExpressionF(c: u8) u8 {
    if (c == 0) {
        return 0;
    } else if (c == 1) {
        return 1;
    } else {
        return @as(u8, 2);
    }
}

// #2297
var global_with_val: anyerror!u32 = 0;
var global_with_err: anyerror!u32 = error.SomeError;

test "unwrap mutable global var" {
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO

    if (global_with_val) |v| {
        try expect(v == 0);
    } else |_| {
        unreachable;
    }
    if (global_with_err) |_| {
        unreachable;
    } else |e| {
        try expect(e == error.SomeError);
    }
}

test "labeled break inside comptime if inside runtime if" {
    var answer: i32 = 0;
    var c = true;
    _ = &c;
    if (c) {
        answer = if (true) blk: {
            break :blk @as(i32, 42);
        };
    }
    try expect(answer == 42);
}

test "const result loc, runtime if cond, else unreachable" {
    const Num = enum { One, Two };

    var t = true;
    _ = &t;
    const x = if (t) Num.Two else unreachable;
    try expect(x == .Two);
}

test "if copies its payload" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO

    const S = struct {
        fn doTheTest() !void {
            var tmp: ?i32 = 10;
            if (tmp) |value| {
                // Modify the original variable
                tmp = null;
                try expect(value == 10);
            } else unreachable;
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "if prongs cast to expected type instead of peer type resolution" {
    const S = struct {
        fn doTheTest(f: bool) !void {
            var x: i32 = 0;
            x = if (f) 1 else 2;
            try expect(x == 2);

            var b = true;
            _ = &b;
            const y: i32 = if (b) 1 else 2;
            try expect(y == 1);
        }
    };
    try S.doTheTest(false);
    try comptime S.doTheTest(false);
}

test "if peer expressions inferred optional type" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    var self: []const u8 = "abcdef";
    var index: usize = 0;
    _ = .{ &self, &index };
    const left_index = (index << 1) + 1;
    const right_index = left_index + 1;
    const left = if (left_index < self.len) self[left_index] else null;
    const right = if (right_index < self.len) self[right_index] else null;
    try expect(left_index < self.len);
    try expect(right_index < self.len);
    try expect(left.? == 98);
    try expect(right.? == 99);
}

test "if-else expression with runtime condition result location is inferred optional" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO

    const A = struct { b: u64, c: u64 };
    var d: bool = true;
    _ = &d;
    const e = if (d) A{ .b = 15, .c = 30 } else null;
    try expect(e != null);
}

test "result location with inferred type ends up being pointer to comptime_int" {
    var a: ?u32 = 1234;
    var b: u32 = 2000;
    _ = .{ &a, &b };
    const c = if (a) |d| blk: {
        if (d < b) break :blk @as(u32, 1);
        break :blk 0;
    } else @as(u32, 0);
    try expect(c == 1);
}

test "if-@as-if chain" {
    var fast = true;
    var very_fast = false;
    _ = .{ &fast, &very_fast };

    const num_frames = if (fast)
        @as(u32, if (very_fast) 16 else 4)
    else
        1;

    try expect(num_frames == 4);
}

fn returnTrue() bool {
    return true;
}

test "if value shouldn't be load-elided if used later (structs)" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;

    const Foo = struct { x: i32 };

    var a = Foo{ .x = 1 };
    var b = Foo{ .x = 1 };

    const c = if (@call(.never_inline, returnTrue, .{})) a else b;
    // The second variable is superfluous with the current
    // state of codegen optimizations, but in future
    // "if (smthg) a else a" may be optimized simply into "a".

    a.x = 2;
    b.x = 3;

    try std.testing.expectEqual(c.x, 1);
}

test "if value shouldn't be load-elided if used later (optionals)" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;

    var a: ?i32 = 1;
    var b: ?i32 = 1;

    const c = if (@call(.never_inline, returnTrue, .{})) a else b;

    a = 2;
    b = 3;

    try std.testing.expectEqual(c, 1);
}

test "variable type inferred from if expression" {
    var a = if (true) {
        return;
    } else true;
    _ = &a;
    return error.TestFailed;
}

test "branch returning slice in tuple literal under high register pressure" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const S = struct {
        const Info = struct {
            intent: [8]u8 = "abcdefgh".*,
            extra: [32]u8 = @splat(0),
        };

        var vals: [14]u64 = .{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 };
        var opt_info: ?Info = Info{};

        fn check(b: bool) !void {
            const x0 = vals[0];
            const x1 = vals[1];
            const x2 = vals[2];
            const x3 = vals[3];
            const x4 = vals[4];
            const x5 = vals[5];
            const x6 = vals[6];
            const x7 = vals[7];
            const x8 = vals[8];
            const x9 = vals[9];
            const x10 = vals[10];
            const x11 = vals[11];
            const x12 = vals[12];
            const x13 = vals[13];

            const t = .{
                x0,
                x1,
                x2,
                x3,
                x4,
                x5,
                x6,
                x7,
                x8,
                x9,
                x10,
                x11,
                x12,
                x13,
                if (b) if (opt_info) |v| v.intent[0..] else "-" else "-",
                switch (b) {
                    true => if (opt_info) |v| v.intent[0..] else "-",
                    false => "-",
                },
            };
            try expect(t[0] + t[1] + t[2] + t[3] + t[4] + t[5] + t[6] + t[7] + t[8] + t[9] + t[10] + t[11] + t[12] + t[13] == 105);
            if (b) {
                try expect(std.mem.eql(u8, t[14], "abcdefgh"));
                try expect(std.mem.eql(u8, t[15], "abcdefgh"));
            } else {
                try expect(std.mem.eql(u8, t[14], "-"));
                try expect(std.mem.eql(u8, t[15], "-"));
            }
        }
    };

    try S.check(false);
    try S.check(true);
}
