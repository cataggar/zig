const std = @import("std");
const expect = std.testing.expect;
const builtin = @import("builtin");

test "memory size and grow" {
    var prev = @wasmMemorySize(0);
    _ = &prev;
    try expect(prev == @wasmMemoryGrow(0, 1));
    try expect(prev + 1 == @wasmMemorySize(0));
}

test "asm .i32.add" {
    const a: u32 = std.math.maxInt(u32);
    const b: u32 = 3;
    const result = asm (
        \\ local.get %[a]
        \\ local.get %[b]
        \\ i32.add
        \\ local.set %[ret]
        : [ret] "=r" (-> u32),
        : [a] "r" (a),
          [b] "r" (b),
    );

    try expect(result == 2);
}

test "asm .i64.clz" {
    const a: u64 = 1;
    const result = asm (
        \\ local.get %[a]
        \\ i64.clz
        \\ local.set %[ret]
        : [ret] "=r" (-> u64),
        : [a] "r" (a),
    );

    try expect(result == 63);
}

test "asm .i32.const" {
    const result = asm (
        \\ i32.const 12
        \\ local.set %[ret]
        : [ret] "=r" (-> u32),
    );

    try expect(result == 12);
}

test "asm .i64.const" {
    const result = asm (
        \\ i64.const 42
        \\ local.set %[ret]
        : [ret] "=r" (-> u64),
    );

    try expect(result == 42);
}

test "asm .f32.const" {
    const result = asm (
        \\ f32.const 1.5
        \\ local.set %[ret]
        : [ret] "=r" (-> f32),
    );

    try expect(result == 1.5);
}

test "asm .f64.const" {
    const result = asm (
        \\ f64.const 2.25
        \\ local.set %[ret]
        : [ret] "=r" (-> f64),
    );

    try expect(result == 2.25);
}

test "asm .local.get" {
    const a: u32 = 77;
    const result = asm (
        \\ local.get %[a]
        \\ local.set %[ret]
        : [ret] "=r" (-> u32),
        : [a] "r" (a),
    );

    try expect(result == 77);
}

test "asm .local.set" {
    const result = asm (
        \\ i32.const 55
        \\ local.set %[ret]
        : [ret] "=r" (-> u32),
    );

    try expect(result == 55);
}

test "asm .local.tee" {
    const a: u32 = 3;
    const result = asm (
        \\ local.get %[a]
        \\ local.tee %[ret]
        \\ drop
        : [ret] "=r" (-> u32),
        : [a] "r" (a),
    );

    try expect(result == 3);
}

test "asm .memory.copy" {
    var src: [8]u8 = .{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var dst: [8]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };

    asm volatile (
        \\ local.get %[dst]
        \\ local.get %[src]
        \\ i32.const 8
        \\ memory.copy 0, 0
        :
        : [dst] "r" (@intFromPtr(&dst)),
          [src] "r" (@intFromPtr(&src)),
    );

    try std.testing.expectEqualSlices(u8, &src, &dst);
}

test "asm .memory.fill" {
    var buf: [8]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };

    asm volatile (
        \\ local.get %[dst]
        \\ i32.const 2
        \\ i32.const 8
        \\ memory.fill 0
        :
        : [dst] "r" (@intFromPtr(&buf)),
    );

    try std.testing.expectEqualSlices(u8, &.{ 2, 2, 2, 2, 2, 2, 2, 2 }, &buf);
}

test "asm .i64.load and .i64.store" {
    var slot: u64 = 0;
    const value: u64 = 0x4444;

    const result = asm (
        \\ local.get %[ptr]
        \\ local.get %[value]
        \\ i64.store 0:p2align=0
        \\ local.get %[ptr]
        \\ i64.load 0
        \\ local.set %[ret]
        : [ret] "=r" (-> u64),
        : [ptr] "r" (@intFromPtr(&slot)),
          [value] "r" (value),
    );

    try expect(result == value);
    try expect(slot == value);
}

test "asm .globaltype, global.get, global.set, and trailing comments" {
    const sp = asm (
        \\ # full-line hash comment
        \\ // full-line slash comment
        \\ .globaltype __stack_pointer, i32
        \\ global.get __stack_pointer # trailing hash comment
        \\ global.set __stack_pointer // trailing slash comment
        \\ global.get __stack_pointer
        \\ local.set %[ret]
        : [ret] "=r" (-> u32),
    );
    try expect(sp != 0);
}

test "asm callconv(.naked), immediate offset, and call operand" {
    const S = struct {
        const Context = struct {
            pad: u32 = 0,
            bias: u32,
            out: u32 = 0,
        };

        fn addBias(x: u32, ctx: *Context) callconv(.c) void {
            ctx.out = x + ctx.bias;
        }

        noinline fn nakedTrampoline(_: u32, _: *Context) callconv(.naked) void {
            asm volatile (
                \\ local.get 0
                \\ local.get 1
                \\ i32.load %[bias_offset]
                \\ i32.add
                \\ local.get 1
                \\ call %[func]
                \\ return
                :
                : [bias_offset] "X" (@offsetOf(Context, "bias")),
                  [func] "X" (&addBias),
            );
        }
    };
    comptime {
        @export(&S.nakedTrampoline, .{ .name = "zig_test_wasm_naked_trampoline" });
    }

    var ctx: S.Context = .{ .bias = 10 };
    const trampoline = @extern(*const fn (u32, *S.Context) callconv(.c) void, .{
        .name = "zig_test_wasm_naked_trampoline",
    });
    trampoline(5, &ctx);
    try expect(ctx.out == 25);
}

test "leaf function with stack frame and early returns preserves caller stack and __stack_pointer" {
    const S = struct {
        const Pair = struct {
            a: u32,
            b: u32,
        };

        noinline fn leafWithStack(x: u32, early: bool) u32 {
            var arr: [8]u32 = .{ x, x + 1, x + 2, x + 3, x + 4, x + 5, x + 6, x + 7 };
            var pair: Pair = .{ .a = x * 2, .b = x * 3 };
            _ = &arr;
            _ = &pair;

            if (early) {
                return arr[x & 7] + pair.a;
            }

            arr[(x + 1) & 7] += pair.b;
            pair.a += arr[(x + 2) & 7];
            return arr[(x + 1) & 7] + pair.a;
        }

        fn readSp() u32 {
            return asm (
                \\ .globaltype __stack_pointer, i32
                \\ global.get __stack_pointer
                \\ local.set %[ret]
                : [ret] "=r" (-> u32),
            );
        }
    };

    var caller_canary: [4]u32 = .{ 0x1111_2222, 0x3333_4444, 0x5555_6666, 0x7777_8888 };
    _ = &caller_canary;

    const sp_before = S.readSp();
    const r1 = S.leafWithStack(3, true);
    const sp_mid = S.readSp();
    const r2 = S.leafWithStack(3, false);
    const sp_after = S.readSp();

    try expect(r1 == (3 + 3) + 6);
    try expect(r2 == (7 + 9) + (6 + 8));
    try expect(sp_before == sp_mid);
    try expect(sp_before == sp_after);
    try expect(caller_canary[0] == 0x1111_2222);
    try expect(caller_canary[1] == 0x3333_4444);
    try expect(caller_canary[2] == 0x5555_6666);
    try expect(caller_canary[3] == 0x7777_8888);
}

test "leaf function with over-aligned stack frame and @frameAddress" {
    const S = struct {
        const Info = struct {
            frame_addr: usize,
            buf_addr: usize,
            sum: u32,
        };

        noinline fn overAlignedLeaf(seed: u32) Info {
            var aligned_buf: [4]u32 align(64) = .{ seed, seed + 10, seed + 20, seed + 30 };
            _ = &aligned_buf;
            return .{
                .frame_addr = @frameAddress(),
                .buf_addr = @intFromPtr(&aligned_buf),
                .sum = aligned_buf[0] + aligned_buf[1] + aligned_buf[2] + aligned_buf[3],
            };
        }

        noinline fn frameOnlyLeaf() usize {
            return @frameAddress();
        }
    };

    const info = S.overAlignedLeaf(5);
    try expect(info.frame_addr != 0);
    try expect(info.frame_addr % 64 == 0);
    try expect(info.buf_addr % 64 == 0);
    try expect(info.sum == 80);

    const frame_only = S.frameOnlyLeaf();
    try expect(frame_only != 0);
    try expect(frame_only % 16 == 0);
}

test "live UAVs, over-aligned UAVs, and offset UAVs alongside dead branches pruned by Mir.Optimize" {
    const S = struct {
        const Pair = extern struct {
            a: u32,
            b: u32,
        };

        noinline fn computeWithPrunedDeadUavs(x: u32) struct {
            sum: u32,
            aligned_addr: usize,
            off_only_base_addr: usize,
            sub_slice: []const u8,
        } {
            const five = asm (
                \\ i32.const 5
                \\ local.set %[ret]
                : [ret] "=r" (-> u32),
            );
            if (five != 5) {
                const dead_str: []const u8 = "dead_branch_uav_string_constant_110";
                const dead_sub: []const u8 = ("dead_branch_offset_uav_constant_110")[12..18];
                const dead_pair: *const Pair = &.{ .a = 900, .b = 901 };
                const dead_field: *const u32 = &(@as(Pair, .{ .a = 700, .b = 701 }).b);
                const dead_aligned_arr: [4]u32 align(64) = .{ 111, 222, 333, 444 };
                const dead_aligned: *align(64) const [4]u32 = &dead_aligned_arr;
                return .{
                    .sum = @as(u32, @truncate(@intFromPtr(dead_str.ptr))) +
                        @as(u32, dead_sub[0]) +
                        dead_pair.a +
                        dead_field.* +
                        dead_aligned[0],
                    .aligned_addr = @intFromPtr(dead_aligned),
                    .off_only_base_addr = @intFromPtr(dead_field),
                    .sub_slice = dead_sub,
                };
            }

            const sink: u32 = x + 5;

            const live_pair: *const Pair = &.{ .a = 10, .b = 20 };
            const live_field_b: *const u32 = &(@as(Pair, .{ .a = 30, .b = 40 }).b);
            const live_aligned_arr: [4]u32 align(64) = .{ 1, 2, 3, 4 };
            const live_aligned: *align(64) const [4]u32 = &live_aligned_arr;
            const live_only_off_arr: [4]u32 align(64) = .{ 5, 6, 7, 8 };
            const live_only_off_aligned: *align(8) const u32 = &live_only_off_arr[2];
            const live_sub_slice: []const u8 = ("prefix_wasm_uav_suffix")[7..15];

            return .{
                .sum = sink + live_pair.a + live_pair.b + live_field_b.* + live_aligned[0] + live_only_off_aligned.*,
                .aligned_addr = @intFromPtr(live_aligned),
                .off_only_base_addr = @intFromPtr(live_only_off_aligned) - 8,
                .sub_slice = live_sub_slice,
            };
        }
    };

    const res = S.computeWithPrunedDeadUavs(7);
    try expect(res.sum == 12 + 10 + 20 + 40 + 1 + 7);
    try expect(res.aligned_addr % 64 == 0);
    try expect(res.off_only_base_addr % 64 == 0);
    try std.testing.expectEqualStrings("wasm_uav", res.sub_slice);
}

test "interleaved mixed local types and eliminated interior locals preserve values after compaction" {
    const S = struct {
        const Result = struct {
            i32_out: u32,
            i64_out: u64,
            f32_out: f32,
            f64_out: f64,
            vec_out: i32,
        };

        noinline fn computeMixedLocals(p32: u32, p64: u64, pf32: f32, pf64: f64) Result {
            // Single-use temporaries interleaved with multi-use locals of every Valtype
            // so Mir.Optimize eliminates interior locals before compactLocals regroups runs.
            const tmp32_a: u32 = (p32 +% 3) *% 5;
            const live32_a: u32 = tmp32_a ^ (p32 +% 11);

            const tmp64_a: u64 = (p64 +% 7) *% 9;
            const live64_a: u64 = tmp64_a +% (p64 ^ 0x1234_5678_9abc_def0);

            const tmpf32_a: f32 = (pf32 + 1.5) * 2.0;
            const livef32_a: f32 = tmpf32_a + (pf32 * 0.5);

            const tmpf64_a: f64 = (pf64 - 0.25) * 4.0;
            const livef64_a: f64 = tmpf64_a + (pf64 * 1.25);

            const vec_a: @Vector(4, i32) = @splat(@as(i32, @intCast(live32_a & 0x7fff)));

            const tmp32_b: u32 = live32_a +% @as(u32, @intCast(vec_a[0]));
            const live32_b: u32 = (tmp32_b *% 3) ^ p32;

            const tmp64_b: u64 = live64_a ^ @as(u64, live32_b);
            const live64_b: u64 = tmp64_b +% (live64_a >> 4);

            const tmpf32_b: f32 = livef32_a * 1.5;
            const livef32_b: f32 = tmpf32_b - pf32 + livef32_a;

            const tmpf64_b: f64 = livef64_a * 0.5;
            const livef64_b: f64 = tmpf64_b + pf64 + livef64_a;

            const vec_b: @Vector(4, i32) = @splat(@as(i32, @intCast(live32_b & 0x7fff)));

            return .{
                .i32_out = live32_a +% live32_b +% p32,
                .i64_out = live64_a +% live64_b +% p64,
                .f32_out = livef32_a + livef32_b + pf32,
                .f64_out = livef64_a + livef64_b + pf64,
                .vec_out = vec_a[1] + vec_a[3] + vec_b[0] + vec_b[2],
            };
        }
    };

    const got = S.computeMixedLocals(10, 100, 2.5, 8.25);

    const live32_a: u32 = ((10 + 3) * 5) ^ (10 + 11);
    const live64_a: u64 = ((100 + 7) * 9) + (100 ^ 0x1234_5678_9abc_def0);
    const livef32_a: f32 = ((2.5 + 1.5) * 2.0) + (2.5 * 0.5);
    const livef64_a: f64 = ((8.25 - 0.25) * 4.0) + (8.25 * 1.25);
    const vec_a_lane: i32 = @intCast(live32_a & 0x7fff);
    const live32_b: u32 = ((live32_a + @as(u32, @intCast(vec_a_lane))) * 3) ^ 10;
    const live64_b: u64 = (live64_a ^ @as(u64, live32_b)) + (live64_a >> 4);
    const livef32_b: f32 = (livef32_a * 1.5) - 2.5 + livef32_a;
    const livef64_b: f64 = (livef64_a * 0.5) + 8.25 + livef64_a;
    const vec_b_lane: i32 = @intCast(live32_b & 0x7fff);

    try expect(got.i32_out == live32_a + live32_b + 10);
    try expect(got.i64_out == live64_a + live64_b + 100);
    try expect(got.f32_out == livef32_a + livef32_b + 2.5);
    try expect(got.f64_out == livef64_a + livef64_b + 8.25);
    try expect(got.vec_out == vec_a_lane * 2 + vec_b_lane * 2);
}

test "leaf and non-leaf functions with stack frames and mixed-type locals preserve prologue locals and __stack_pointer" {
    const S = struct {
        const FrameData = struct {
            w32: u32,
            w64: u64,
            wf32: f32,
            wf64: f64,
        };

        fn readSp() u32 {
            return asm (
                \\ .globaltype __stack_pointer, i32
                \\ global.get __stack_pointer
                \\ local.set %[ret]
                : [ret] "=r" (-> u32),
            );
        }

        noinline fn leafMixedWithStack(p32: u32, p64: u64, pf32: f32, pf64: f64) FrameData {
            var slot: FrameData = .{
                .w32 = p32 + 1,
                .w64 = p64 + 2,
                .wf32 = pf32 + 0.5,
                .wf64 = pf64 + 1.5,
            };
            _ = &slot;

            const l32: u32 = (p32 ^ 0x55) +% slot.w32;
            const l64: u64 = (p64 ^ 0xaa55) +% slot.w64;
            const lf32: f32 = (pf32 * 2.0) + slot.wf32;
            const lf64: f64 = (pf64 * 3.0) + slot.wf64;

            slot.w32 = l32 +% p32;
            slot.w64 = l64 +% p64;
            slot.wf32 = lf32 + pf32;
            slot.wf64 = lf64 + pf64;

            return .{
                .w32 = slot.w32 +% l32,
                .w64 = slot.w64 +% l64,
                .wf32 = slot.wf32 + lf32,
                .wf64 = slot.wf64 + lf64,
            };
        }

        noinline fn mutateFrameHelper(frame: *FrameData, delta: u32) u32 {
            var helper_scratch: [4]u64 = .{ delta, delta + 10, delta + 20, delta + 30 };
            _ = &helper_scratch;
            frame.w32 +%= @as(u32, @truncate(helper_scratch[1]));
            frame.w64 +%= helper_scratch[2];
            frame.wf32 += 1.0;
            frame.wf64 += 2.0;
            return @as(u32, @truncate(helper_scratch[0] + helper_scratch[3]));
        }

        noinline fn nonLeafMixedWithStack(p32: u32, p64: u64, pf32: f32, pf64: f64) FrameData {
            var slot: FrameData = .{
                .w32 = p32 + 10,
                .w64 = p64 + 20,
                .wf32 = pf32 + 1.25,
                .wf64 = pf64 + 2.5,
            };

            // Live across the helper call so they must coexist with sp_local and bottom_stack_local.
            const pre32: u32 = (p32 *% 3) +% 7;
            const pre64: u64 = (p64 *% 5) +% 9;
            const pref32: f32 = pf32 * 1.5;
            const pref64: f64 = pf64 * 2.5;

            const helper_ret = mutateFrameHelper(&slot, pre32);

            return .{
                .w32 = slot.w32 +% pre32 +% helper_ret +% p32,
                .w64 = slot.w64 +% pre64 +% p64,
                .wf32 = slot.wf32 + pref32 + pf32,
                .wf64 = slot.wf64 + pref64 + pf64,
            };
        }
    };

    const sp_initial = S.readSp();
    const leaf_res = S.leafMixedWithStack(6, 40, 1.5, 3.5);
    const sp_after_leaf = S.readSp();
    const non_leaf_res = S.nonLeafMixedWithStack(6, 40, 1.5, 3.5);
    const sp_final = S.readSp();

    try expect(sp_initial == sp_after_leaf);
    try expect(sp_initial == sp_final);

    const l32: u32 = (6 ^ 0x55) + 7;
    const l64: u64 = (40 ^ 0xaa55) + 42;
    const lf32: f32 = (1.5 * 2.0) + 2.0;
    const lf64: f64 = (3.5 * 3.0) + 5.0;
    try expect(leaf_res.w32 == (l32 + 6) + l32);
    try expect(leaf_res.w64 == (l64 + 40) + l64);
    try expect(leaf_res.wf32 == (lf32 + 1.5) + lf32);
    try expect(leaf_res.wf64 == (lf64 + 3.5) + lf64);

    const pre32: u32 = 6 * 3 + 7; // 25
    const pre64: u64 = 40 * 5 + 9; // 209
    const pref32: f32 = 1.5 * 1.5; // 2.25
    const pref64: f64 = 3.5 * 2.5; // 8.75
    const helper_ret: u32 = pre32 + (pre32 + 30); // 80
    try expect(non_leaf_res.w32 == (16 + (pre32 + 10)) + pre32 + helper_ret + 6);
    try expect(non_leaf_res.w64 == (60 + (pre32 + 20)) + pre64 + 40);
    try expect(non_leaf_res.wf32 == (2.75 + 1.0) + pref32 + 1.5);
    try expect(non_leaf_res.wf64 == (6.0 + 2.0) + pref64 + 3.5);
}

test "sroa aggregate promotion and escape fallback" {
    const S = struct {
        const Vec2 = struct {
            x: f32,
            y: f32,
        };

        const Rect = struct {
            x: i32,
            y: i32,
            w: i32,
            h: i32,
        };

        const Transform = struct {
            offset: Vec2,
            scale: f32,
        };

        const BatchEntry = struct {
            rect: Rect,
            transform: Transform,
            color: u32,
            active: bool,
        };

        const Holder = struct {
            ptr: *Rect,
            tag: u32,
        };

        const Error = error{
            OutOfBounds,
            EmptySlice,
            InvalidState,
        };

        const default_batch: BatchEntry = .{
            .rect = .{ .x = 10, .y = 20, .w = 30, .h = 40 },
            .transform = .{ .offset = .{ .x = 1.5, .y = -2.5 }, .scale = 2.0 },
            .color = 0xdead_beef,
            .active = true,
        };

        const default_opt_rect: ?Rect = .{ .x = 7, .y = 8, .w = 9, .h = 10 };
        const default_arr_vec: [2]Vec2 = .{
            .{ .x = 3.0, .y = 4.0 },
            .{ .x = 5.0, .y = 6.0 },
        };

        noinline fn makeRectNoInline(x: i32, fail: bool) Error!Rect {
            if (fail) return error.OutOfBounds;
            return .{ .x = x, .y = x + 1, .w = x * 2, .h = x * 3 };
        }

        inline fn checkVoidInline(ok: bool) Error!void {
            if (!ok) return error.InvalidState;
        }

        noinline fn subSliceNoInline(input: []const u8, skip: usize) Error![]const u8 {
            if (skip > input.len) return error.EmptySlice;
            return input[skip..];
        }

        noinline fn mutateEscapedRect(r: *Rect, dx: i32, dy: i32) i32 {
            r.x += dx;
            r.y += dy;
            return r.x + r.y + r.w + r.h;
        }

        noinline fn exerciseNestedAndCopies(seed: i32) !void {
            var r: Rect = .{ .x = 1, .y = 2, .w = 3, .h = 4 };
            var r2 = r;
            r.x = 99;
            try expect(r2.x == 1);
            try expect(r2.y == 2);
            try expect(r2.w == 3);
            try expect(r2.h == 4);
            r2.h = 40;
            try expect(r.h == 4);
            r2.h = 4;

            if (seed > 0) {
                r.y += seed;
                r.w *= 2;
            } else {
                r.y -= seed;
                r.h *= 3;
            }

            var i: i32 = 0;
            while (i < 3) : (i += 1) {
                r.x += i;
                r.h += 1;
            }

            const deltas = [_]i32{ 2, 4, 6 };
            for (deltas) |d| {
                r.w += d;
            }

            try expect(r.x == 99 + 3);
            try expect(r.y == 2 + seed);
            try expect(r.w == 6 + 12);
            try expect(r.h == 4 + 3);

            var outer: BatchEntry = .{
                .rect = r2,
                .transform = .{ .offset = .{ .x = 0.5, .y = 1.5 }, .scale = 4.0 },
                .color = 0x1122_3344,
                .active = false,
            };
            var outer_copy = outer;
            outer.rect.x += 10;
            outer.transform.offset.y += 2.5;
            outer.active = true;

            try expect(outer_copy.rect.x == 1);
            try expect(outer_copy.transform.offset.y == 1.5);
            try expect(!outer_copy.active);
            outer_copy.color += 1;
            try expect(outer.color == 0x1122_3344);
            try expect(outer.rect.x == 11);
            try expect(outer.transform.offset.y == 4.0);
            try expect(outer.active);

            var tup: struct { u32, u64, Rect } = .{ 10, 100, r2 };
            const tup_snapshot = tup;
            tup[0] += 5;
            tup[1] += 50;
            tup[2].w = 77;
            try expect(tup_snapshot[0] == 10);
            try expect(tup_snapshot[1] == 100);
            try expect(tup_snapshot[2].w == 3);
            try expect(tup[0] == 15);
            try expect(tup[1] == 150);
            try expect(tup[2].w == 77);
        }

        noinline fn exerciseSlices(text: []const u8) !void {
            var s: []const u8 = text;
            var acc: u32 = 0;
            while (s.len > 0) {
                acc = acc *% 31 +% s.ptr[0] +% @as(u32, @truncate(s.len));
                s = s[1..];
            }
            try expect(s.len == 0);
            try expect(acc != 0);

            var backing: [4]u32 = .{ 10, 20, 30, 40 };
            var nums: []u32 = backing[0..];
            var idx: usize = 0;
            while (idx < nums.len) : (idx += 1) {
                nums[idx] += @as(u32, @truncate(idx + 1));
            }
            nums = nums[1..3];
            try expect(nums.len == 2);
            try expect(nums.ptr[0] == 22);
            try expect(nums[1] == 33);

            var opt_slice: ?[]const u8 = null;
            try expect(opt_slice == null);
            opt_slice = text[1..4];
            if (opt_slice) |*ps| {
                ps.* = ps.*[1..];
            }
            const unwrapped = opt_slice orelse "";
            try expect(unwrapped.len == 2);
            try expect(unwrapped[0] == text[2]);
            try expect(unwrapped[1] == text[3]);
        }

        noinline fn exerciseOptionals(seed: u32) !void {
            var opt_rect: ?Rect = null;
            try expect(opt_rect == null);

            const fallback = opt_rect orelse Rect{ .x = -1, .y = -2, .w = -3, .h = -4 };
            try expect(fallback.x == -1);

            opt_rect = .{
                .x = @intCast(seed),
                .y = @intCast(seed + 1),
                .w = 10,
                .h = 20,
            };
            if (opt_rect) |*payload| {
                payload.x += 10;
                payload.h += 5;
            }
            if (opt_rect) |payload| {
                try expect(payload.x == @as(i32, @intCast(seed)) + 10);
                try expect(payload.y == @as(i32, @intCast(seed + 1)));
                try expect(payload.w == 10);
                try expect(payload.h == 25);
            } else {
                return error.TestUnexpectedResult;
            }

            var opt_u64: ?u64 = null;
            try expect((opt_u64 orelse 99) == 99);
            opt_u64 = @as(u64, seed) * 1000;
            if (opt_u64) |*v| {
                v.* += 7;
            }
            try expect((opt_u64 orelse 0) == @as(u64, seed) * 1000 + 7);

            var nested_opt: ??u32 = null;
            try expect(nested_opt == null);
            nested_opt = @as(?u32, null);
            if (nested_opt) |inner| {
                try expect(inner == null);
            } else {
                return error.TestUnexpectedResult;
            }
            nested_opt = @as(?u32, seed + 42);
            if (nested_opt) |inner| {
                try expect((inner orelse 0) == seed + 42);
            } else {
                return error.TestUnexpectedResult;
            }
        }

        noinline fn exerciseErrorUnions(seed: i32) !void {
            try checkVoidInline(true);
            try std.testing.expectError(error.InvalidState, checkVoidInline(false));

            var eu_rect: Error!Rect = makeRectNoInline(seed, false);
            if (eu_rect) |*r_ptr| {
                r_ptr.x += 100;
                r_ptr.h += 50;
            } else |_| {
                return error.TestUnexpectedResult;
            }
            const r_ok = try eu_rect;
            try expect(r_ok.x == seed + 100);
            try expect(r_ok.y == seed + 1);
            try expect(r_ok.w == seed * 2);
            try expect(r_ok.h == seed * 3 + 50);

            eu_rect = makeRectNoInline(seed, true);
            const r_caught = eu_rect catch Rect{ .x = 0, .y = 0, .w = 1, .h = 1 };
            try expect(r_caught.x == 0);
            try expect(r_caught.w == 1);

            var eu_slice: Error![]const u8 = subSliceNoInline("wasm_sroa", 5);
            if (eu_slice) |*s_ptr| {
                s_ptr.* = s_ptr.*[1..];
            } else |_| {
                return error.TestUnexpectedResult;
            }
            try std.testing.expectEqualStrings("roa", try eu_slice);

            eu_slice = subSliceNoInline("wasm", 10);
            const fallback_slice = eu_slice catch "fallback";
            try std.testing.expectEqualStrings("fallback", fallback_slice);
        }

        noinline fn exerciseFixedArraysAndOverflow(runtime_i: usize, base: u32) !void {
            var arr_f32: [4]f32 = .{ 1.0, 2.0, 3.0, 4.0 };
            const arr_snapshot = arr_f32;
            arr_f32[0] = arr_f32[3] + 0.5;
            arr_f32[3] = arr_f32[1] * 3.0;
            try expect(arr_snapshot[0] == 1.0);
            try expect(arr_snapshot[3] == 4.0);
            try expect(arr_f32[0] == 4.5);
            try expect(arr_f32[1] == 2.0);
            try expect(arr_f32[2] == 3.0);
            try expect(arr_f32[3] == 6.0);

            var vecs: [2]Vec2 = .{
                .{ .x = 1.0, .y = 2.0 },
                .{ .x = 10.0, .y = 20.0 },
            };
            vecs[0].x += vecs[1].y;
            vecs[1].x -= vecs[0].y;
            try expect(vecs[0].x == 21.0);
            try expect(vecs[1].x == 8.0);

            var arr_dyn: [4]u32 = .{ base, base + 10, base + 20, base + 30 };
            arr_dyn[runtime_i] += 100;
            try expect(arr_dyn[2] == base + 120);
            try expect(arr_dyn[0] == base);

            var sum: u8 = 200;
            var overflow_count: u32 = 0;
            const increments = [_]u8{ 30, 40, 10 };
            for (increments) |inc| {
                const add_ov = @addWithOverflow(sum, inc);
                sum = add_ov[0];
                if (add_ov[1] != 0) {
                    overflow_count += 1;
                }
            }
            try expect(overflow_count == 1);
            try expect(sum == (@as(u8, 200) +% 30 +% 40 +% 10));

            const mul_ok = @mulWithOverflow(@as(u16, @intCast(base)), @as(u16, 10));
            try expect(mul_ok[0] == base * 10);
            try expect(mul_ok[1] == 0);

            const mul_ov = @mulWithOverflow(@as(u16, 1000), @as(u16, 100));
            try expect(mul_ov[0] == @as(u16, @truncate(@as(u32, 100_000))));
            try expect(mul_ov[1] == 1);
        }

        noinline fn exerciseUavConstantsAndEscapes(seed: i32) !void {
            // Comptime aggregate constants (.uav_ref decomposition) into mutable locals
            var batch = default_batch;
            batch.rect.w = 999;
            batch.transform.scale = 8.0;
            try expect(batch.rect.x == 10);
            try expect(batch.rect.y == 20);
            try expect(batch.rect.w == 999);
            try expect(batch.rect.h == 40);
            try expect(batch.transform.offset.x == 1.5);
            try expect(batch.transform.offset.y == -2.5);
            try expect(batch.transform.scale == 8.0);
            try expect(batch.color == 0xdead_beef);
            try expect(batch.active);

            var opt_from_uav = default_opt_rect;
            if (opt_from_uav) |*r| {
                r.y = 88;
            }
            try expect((opt_from_uav orelse unreachable).x == 7);
            try expect((opt_from_uav orelse unreachable).y == 88);
            try expect((opt_from_uav orelse unreachable).w == 9);
            try expect((opt_from_uav orelse unreachable).h == 10);

            var arr_from_uav = default_arr_vec;
            arr_from_uav[1].x = 55.0;
            try expect(arr_from_uav[0].x == 3.0);
            try expect(arr_from_uav[0].y == 4.0);
            try expect(arr_from_uav[1].x == 55.0);
            try expect(arr_from_uav[1].y == 6.0);

            var slice_from_uav: []const u8 = "constant_slice_payload";
            slice_from_uav = slice_from_uav[9..14];
            try std.testing.expectEqualStrings("slice", slice_from_uav);

            // Escaped aggregates alongside promoted aggregates in the same function
            var promoted: Rect = .{ .x = seed, .y = seed * 2, .w = 5, .h = 6 };
            var escaped_call: Rect = .{ .x = 10, .y = 20, .w = 30, .h = 40 };
            var escaped_int: Rect = .{ .x = 1, .y = 2, .w = 3, .h = 4 };
            var escaped_field: Rect = .{ .x = 7, .y = 8, .w = 9, .h = 10 };

            const call_sum = mutateEscapedRect(&escaped_call, promoted.x, promoted.y);
            try expect(escaped_call.x == 10 + seed);
            try expect(escaped_call.y == 20 + seed * 2);
            try expect(call_sum == (10 + seed) + (20 + seed * 2) + 30 + 40);

            const addr = @intFromPtr(&escaped_int);
            try expect(addr != 0);
            escaped_int.w += promoted.w;
            try expect(escaped_int.w == 8);

            var holder: Holder = .{
                .ptr = &escaped_field,
                .tag = 42,
            };
            holder.ptr.h += promoted.h;
            promoted.x += holder.ptr.x;
            try expect(escaped_field.h == 16);
            try expect(promoted.x == seed + 7);
            try expect(holder.tag == 42);
        }
    };

    try S.exerciseNestedAndCopies(5);
    try S.exerciseSlices("zig_wasm");
    try S.exerciseOptionals(12);
    try S.exerciseErrorUnions(4);
    try S.exerciseFixedArraysAndOverflow(2, 5);
    try S.exerciseUavConstantsAndEscapes(3);
}

test "small 1-scalar and 2-scalar aggregate returns avoid sret" {
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;

    const S = struct {
        const Vec2 = struct {
            x: f32,
            y: f32,
        };

        const SingleWrap = struct {
            x: f32,
        };

        const MixedPair = struct {
            a: u32,
            b: u64,
        };

        const NestedPair = struct {
            first: SingleWrap,
            second: struct {
                tag: void = {},
                y: i32,
            },
        };

        noinline fn curveExtent(p0: f32, p1: f32, p2: f32) [2]f32 {
            return .{ @min(p0, p1, p2), @max(p0, p1, p2) };
        }

        noinline fn makeConstPair() [2]f32 {
            return .{ 3.5, -7.25 };
        }

        noinline fn makeVec2(x: f32, y: f32) Vec2 {
            var v: Vec2 = .{ .x = x, .y = y };
            v.x += 1.5;
            v.y -= 0.5;
            return v;
        }

        noinline fn makePairMixed(a: u32, b: u64) MixedPair {
            return .{ .a = a + 10, .b = b * 3 };
        }

        noinline fn makeSingleWrap(x: f32) SingleWrap {
            var w: SingleWrap = .{ .x = x * 2.0 };
            w.x += 0.25;
            return w;
        }

        noinline fn makeNestedPair(x: f32, y: i32) NestedPair {
            return .{
                .first = .{ .x = x },
                .second = .{ .y = y },
            };
        }

        noinline fn inspectEscapedVec2(ptr: *const Vec2) f32 {
            return ptr.x + ptr.y;
        }

        fn readSp() u32 {
            return asm (
                \\ .globaltype __stack_pointer, i32
                \\ global.get __stack_pointer
                \\ local.set %[ret]
                : [ret] "=r" (-> u32),
            );
        }
    };

    const sp_before = S.readSp();

    const ext = S.curveExtent(3.5, -2.0, 9.25);
    try expect(ext[0] == -2.0);
    try expect(ext[1] == 9.25);

    const const_pair = S.makeConstPair();
    try expect(const_pair[0] == 3.5);
    try expect(const_pair[1] == -7.25);

    const v = S.makeVec2(4.0, 10.0);
    try expect(v.x == 5.5);
    try expect(v.y == 9.5);

    const mixed = S.makePairMixed(7, 100);
    try expect(mixed.a == 17);
    try expect(mixed.b == 300);

    const single = S.makeSingleWrap(3.0);
    try expect(single.x == 6.25);

    const nested = S.makeNestedPair(1.25, -42);
    try expect(nested.first.x == 1.25);
    try expect(nested.second.y == -42);

    // Unused return value (exercises drop path)
    _ = S.makeVec2(1.0, 2.0);
    _ = S.makeSingleWrap(1.0);

    // Escaped caller result (exercises non-promoted caller destination path)
    const escaped_v = S.makeVec2(2.0, 6.0);
    try expect(S.inspectEscapedVec2(&escaped_v) == 9.0);

    const sp_after = S.readSp();
    try expect(sp_before == sp_after);
}

test "sroa unread fields, bitcast byte-array loads, and readonly by-ref arg alias" {
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;
    if (builtin.cpu.arch != .wasm32) return error.SkipZigTest;

    const S = struct {
        const Padding = struct {
            value: [4]f32,

            noinline fn top(self: Padding) f32 {
                return self.value[0];
            }

            noinline fn left(self: Padding) f32 {
                return self.value[3];
            }
        };

        const Element = struct {
            id: u32,
            weight: f32,
        };

        const ElementPool = struct {
            items: []const Element,
            capacity: usize,

            noinline fn getPtr(self: *const ElementPool, idx: u16) *const Element {
                return &self.items.ptr[idx];
            }
        };

        const Curve = struct {
            p0: [2]f32,
            p1: [2]f32,
            p2: [2]f32,
        };

        noinline fn curveExtent(curve: Curve, axis: u1) [2]f32 {
            const a = curve.p0[axis];
            const b = curve.p1[axis];
            const c = curve.p2[axis];
            return .{
                @min(a, @min(b, c)),
                @max(a, @max(b, c)),
            };
        }

        noinline fn curveExtentFromPtr(curve_ptr: *const Curve, axis: u1) [2]f32 {
            const curve = curve_ptr.*;
            const a = curve.p0[axis];
            const b = curve.p1[axis];
            const c = curve.p2[axis];
            return .{
                @min(a, @min(b, c)),
                @max(a, @max(b, c)),
            };
        }

        noinline fn curveExtentVarFromPtr(curve_ptr: *const Curve, axis: u1) [2]f32 {
            var curve = curve_ptr.*;
            _ = &curve;
            const a = curve.p0[axis];
            const b = curve.p1[axis];
            const c = curve.p2[axis];
            return .{
                @min(a, @min(b, c)),
                @max(a, @max(b, c)),
            };
        }

        noinline fn bitcastAfterBreakingCondBrWrite(p: *[4]u8, c: bool, d: bool) u32 {
            const v = p.*;
            blk: {
                if (c) {
                    p[0] = 0xFF;
                    if (d) break :blk;
                    unreachable;
                }
            }
            return @bitCast(v);
        }

        noinline fn readU16Le(bytes: *const [2]u8) u16 {
            return std.mem.readInt(u16, bytes, .little);
        }

        noinline fn readU32Le(bytes: *const [4]u8) u32 {
            return std.mem.readInt(u32, bytes, .little);
        }

        noinline fn readU64Le(bytes: *const [8]u8) u64 {
            return std.mem.readInt(u64, bytes, .little);
        }

        noinline fn bitcastF64FromBytes(bytes: *const [8]u8) f64 {
            return @bitCast(bytes.*);
        }

        fn readSp() u32 {
            return asm (
                \\ .globaltype __stack_pointer, i32
                \\ global.get __stack_pointer
                \\ local.set %[ret]
                : [ret] "=r" (-> u32),
            );
        }
        inline fn fillRedZone(sp: u32) void {
            const rz: [*]volatile u8 = @ptrFromInt(sp - 64);
            for (0..64) |i| rz[i] = 0xA5;
        }

        inline fn checkRedZone(sp: u32) bool {
            const rz: [*]volatile u8 = @ptrFromInt(sp - 64);
            for (0..64) |i| {
                if (rz[i] != 0xA5) return false;
            }
            return true;
        }
    };

    const sp_before = S.readSp();

    const pad: S.Padding = .{ .value = .{ 1.25, 2.5, 3.75, 8.5 } };
    S.fillRedZone(sp_before);
    const pad_top = pad.top();
    const pad_left = pad.left();
    const rz_pad = S.checkRedZone(sp_before);
    try expect(pad_top == 1.25);
    try expect(pad_left == 8.5);
    if (!rz_pad) return error.PadTouchedRedZone;

    const elems = [_]S.Element{
        .{ .id = 10, .weight = 1.5 },
        .{ .id = 20, .weight = 3.5 },
        .{ .id = 30, .weight = 5.5 },
    };
    const pool: S.ElementPool = .{ .items = &elems, .capacity = 8 };
    S.fillRedZone(sp_before);
    const elem_ptr = pool.getPtr(2);
    const rz_pool = S.checkRedZone(sp_before);
    try expect(elem_ptr.id == 30);
    try expect(elem_ptr.weight == 5.5);
    if (!rz_pool) return error.PoolTouchedRedZone;

    const curve: S.Curve = .{
        .p0 = .{ 4.0, -3.0 },
        .p1 = .{ -1.5, 7.25 },
        .p2 = .{ 2.0, 1.0 },
    };
    S.fillRedZone(sp_before);
    const ext_x = S.curveExtent(curve, 0);
    const ext_y = S.curveExtent(curve, 1);
    if (!S.checkRedZone(sp_before)) return error.CurveExtentTouchedRedZone;
    const ext_ptr_y = S.curveExtentFromPtr(&curve, 1);
    const ext_var_ptr_y = S.curveExtentVarFromPtr(&curve, 1);
    const rz_curve = S.checkRedZone(sp_before);
    try expect(ext_x[0] == -1.5);
    try expect(ext_x[1] == 4.0);
    try expect(ext_y[0] == -3.0);
    try expect(ext_y[1] == 7.25);
    try expect(ext_ptr_y[0] == -3.0);
    try expect(ext_ptr_y[1] == 7.25);
    try expect(ext_var_ptr_y[0] == -3.0);
    try expect(ext_var_ptr_y[1] == 7.25);
    if (!rz_curve) return error.CurvePtrTouchedRedZone;

    var mut_bytes = [4]u8{ 1, 2, 3, 4 };
    var rt_true_c = true;
    var rt_true_d = true;
    _ = &rt_true_c;
    _ = &rt_true_d;
    try expect(S.bitcastAfterBreakingCondBrWrite(&mut_bytes, rt_true_c, rt_true_d) == 0x04030201);
    try expect(mut_bytes[0] == 0xFF);

    const raw_bytes align(8) = [_]u8{
        0xef, 0xcd, 0xab, 0x90, 0x78, 0x56, 0x34, 0x12,
        0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
    };
    const f64_bytes: [8]u8 = @bitCast(@as(f64, 42.125));
    // Test both aligned and unaligned offsets
    S.fillRedZone(sp_before);
    const u16_val = S.readU16Le(raw_bytes[1..3]);
    const u32_val = S.readU32Le(raw_bytes[1..5]);
    const u64_val0 = S.readU64Le(raw_bytes[0..8]);
    const u64_val1 = S.readU64Le(raw_bytes[3..11]);
    const f64_val = S.bitcastF64FromBytes(&f64_bytes);
    const rz_read = S.checkRedZone(sp_before);
    try expect(u16_val == 0xabcd);
    try expect(u32_val == 0x7890abcd);
    try expect(u64_val0 == 0x1234567890abcdef);
    try expect(u64_val1 == 0x3322111234567890);
    try expect(f64_val == 42.125);
    if (!rz_read) return error.ReadTouchedRedZone;

    const sp_after = S.readSp();
    try expect(sp_before == sp_after);
}

test "auto calling convention error union, optional, and slice returns" {
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;
    if (builtin.cpu.arch != .wasm32) return error.SkipZigTest;

    const S = struct {
        const Err = error{ Fail, BadValue };

        noinline fn retErrVoid(fail: bool) Err!void {
            if (fail) return error.Fail;
        }

        noinline fn retErrU32(x: u32, fail: bool) Err!u32 {
            if (fail) return error.BadValue;
            return x * 3 + 1;
        }

        noinline fn retErrU32ConstOk() Err!u32 {
            return 12345;
        }

        noinline fn retErrU32ConstErr() Err!u32 {
            return error.Fail;
        }

        noinline fn retErrPtr(ptr: *const u32, fail: bool) Err!*const u32 {
            if (fail) return error.Fail;
            return ptr;
        }

        noinline fn retOptU32(x: u32, present: bool) ?u32 {
            if (!present) return null;
            return x + 7;
        }

        noinline fn retOptU32ConstSome() ?u32 {
            return 99;
        }

        noinline fn retOptU32ConstNull() ?u32 {
            return null;
        }

        noinline fn retOptF64(x: f64, present: bool) ?f64 {
            if (!present) return null;
            return x * 2.5;
        }

        noinline fn retOptVoid(present: bool) ?void {
            if (!present) return null;
            return {};
        }

        noinline fn retSlice(bytes: []const u8, start: usize, end: usize) []const u8 {
            return bytes[start..end];
        }

        noinline fn retOptSlice(bytes: []const u8, present: bool) ?[]const u8 {
            if (!present) return null;
            return bytes[1..4];
        }

        noinline fn exerciseReturns(target_val: *const u32, bytes: []const u8) !void {
            try retErrVoid(false);
            if (retErrVoid(true)) |_| return error.TestUnexpectedResult else |err| {
                try expect(err == error.Fail);
            }

            const v1 = try retErrU32(10, false);
            try expect(v1 == 31);
            if (retErrU32(10, true)) |_| return error.TestUnexpectedResult else |err| {
                try expect(err == error.BadValue);
            }
            try expect((try retErrU32ConstOk()) == 12345);
            if (retErrU32ConstErr()) |_| return error.TestUnexpectedResult else |err| {
                try expect(err == error.Fail);
            }

            const p1 = try retErrPtr(target_val, false);
            try expect(p1.* == 777);
            if (retErrPtr(target_val, true)) |_| return error.TestUnexpectedResult else |err| {
                try expect(err == error.Fail);
            }

            try expect(retOptU32(35, true).? == 42);
            try expect(retOptU32(35, false) == null);
            try expect(retOptU32ConstSome().? == 99);
            try expect(retOptU32ConstNull() == null);
            _ = retOptU32(1, true);

            try expect(retOptF64(4.0, true).? == 10.0);
            try expect(retOptF64(4.0, false) == null);

            try expect(retOptVoid(true) != null);
            try expect(retOptVoid(false) == null);

            const sub = retSlice(bytes, 1, 4);
            try expect(sub.len == 3);
            try expect(sub[0] == 'b' and sub[2] == 'd');

            const opt_sub = retOptSlice(bytes, true).?;
            try expect(opt_sub.len == 3 and opt_sub[0] == 'b');
            try expect(retOptSlice(bytes, false) == null);
        }

        fn readSp() u32 {
            return asm (
                \\ .globaltype __stack_pointer, i32
                \\ global.get __stack_pointer
                \\ local.set %[ret]
                : [ret] "=r" (-> u32),
            );
        }

        inline fn fillRedZone(sp: u32) void {
            const rz: [*]volatile u8 = @ptrFromInt(sp - 64);
            for (0..64) |i| rz[i] = 0xA5;
        }

        inline fn checkRedZone(sp: u32) bool {
            const rz: [*]volatile u8 = @ptrFromInt(sp - 64);
            for (0..64) |i| {
                if (rz[i] != 0xA5) return false;
            }
            return true;
        }
    };

    const target_val: u32 = 777;
    const sp_before = S.readSp();
    S.fillRedZone(sp_before);
    try S.exerciseReturns(&target_val, "abcdef");
    if (!S.checkRedZone(sp_before)) return error.ReturnTestTouchedRedZone;
    const sp_after = S.readSp();
    try expect(sp_before == sp_after);
}

test "auto calling convention small aggregate parameters by value" {
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;
    if (builtin.cpu.arch != .wasm32) return error.SkipZigTest;

    const S = struct {
        const Err = error{BadParam};

        const Single = struct {
            x: u32,
        };

        const Vec2 = struct {
            x: f32,
            y: f32,
        };

        const Vec3 = struct {
            x: f32,
            y: f32,
            z: f32,
        };

        const Rect = struct {
            x: f32,
            y: f32,
            w: f32,
            h: f32,
        };

        const QuadCurve = struct {
            pts: [4]f32,
        };

        noinline fn takeSingle(s: Single) u32 {
            return s.x + 9;
        }

        noinline fn takeVec2(v: Vec2) f32 {
            return v.x * 2.0 + v.y;
        }

        noinline fn takeVec3(v: Vec3) f32 {
            return v.x + v.y + v.z;
        }

        noinline fn takeRect(r: Rect) f32 {
            return (r.x + r.y) * (r.w + r.h);
        }

        noinline fn takeSlice(s: []const u8) u32 {
            return @as(u32, @intCast(s.len)) * 100 + s[0] + s[s.len - 1];
        }

        noinline fn takeArr3(a: [3]u32) u32 {
            return a[0] + a[1] * 10 + a[2] * 100;
        }

        noinline fn takeOptU32(opt: ?u32) u32 {
            return opt orelse 999;
        }

        noinline fn takeOptVec2(opt: ?Vec2) f32 {
            const v = opt orelse return -1.0;
            return v.x - v.y;
        }

        noinline fn takeErrU32(eu: Err!u32) u32 {
            return eu catch 555;
        }

        noinline fn takeErrVec2(eu: Err!Vec2) f32 {
            const v = eu catch return -2.0;
            return v.x + v.y;
        }

        noinline fn quadAtRuntimeIndex(q: QuadCurve, idx: usize) f32 {
            return q.pts[idx];
        }

        noinline fn exerciseByValueParams(bytes: []const u8) !void {
            const s: Single = .{ .x = 33 };
            try expect(takeSingle(s) == 42);

            const v2: Vec2 = .{ .x = 3.5, .y = 1.25 };
            try expect(takeVec2(v2) == 8.25);

            const v3: Vec3 = .{ .x = 1.0, .y = 2.5, .z = 4.5 };
            try expect(takeVec3(v3) == 8.0);

            const rect: Rect = .{ .x = 1.5, .y = 2.5, .w = 3.0, .h = 5.0 };
            try expect(takeRect(rect) == 32.0);

            const sub = bytes[1..5];
            try expect(takeSlice(sub) == 400 + 'b' + 'e');

            const arr3 = [3]u32{ 4, 5, 6 };
            try expect(takeArr3(arr3) == 654);

            try expect(takeOptU32(77) == 77);
            try expect(takeOptU32(null) == 999);

            try expect(takeOptVec2(.{ .x = 9.0, .y = 2.5 }) == 6.5);
            try expect(takeOptVec2(null) == -1.0);

            try expect(takeErrU32(88) == 88);
            try expect(takeErrU32(error.BadParam) == 555);

            try expect(takeErrVec2(.{ .x = 1.25, .y = 2.75 }) == 4.0);
            try expect(takeErrVec2(error.BadParam) == -2.0);
        }

        fn readSp() u32 {
            return asm (
                \\ .globaltype __stack_pointer, i32
                \\ global.get __stack_pointer
                \\ local.set %[ret]
                : [ret] "=r" (-> u32),
            );
        }

        inline fn fillRedZone(sp: u32) void {
            const rz: [*]volatile u8 = @ptrFromInt(sp - 64);
            for (0..64) |i| rz[i] = 0xA5;
        }

        inline fn checkRedZone(sp: u32) bool {
            const rz: [*]volatile u8 = @ptrFromInt(sp - 64);
            for (0..64) |i| {
                if (rz[i] != 0xA5) return false;
            }
            return true;
        }
    };

    const sp_before = S.readSp();
    S.fillRedZone(sp_before);
    try S.exerciseByValueParams("abcdef");
    if (!S.checkRedZone(sp_before)) return error.ByValueParamTouchedRedZone;

    const q: S.QuadCurve = .{ .pts = .{ 10.5, 20.25, -5.0, 42.0 } };
    try expect(S.quadAtRuntimeIndex(q, 0) == 10.5);
    try expect(S.quadAtRuntimeIndex(q, 1) == 20.25);
    try expect(S.quadAtRuntimeIndex(q, 2) == -5.0);
    try expect(S.quadAtRuntimeIndex(q, 3) == 42.0);

    const sp_after = S.readSp();
    try expect(sp_before == sp_after);
}

test "vector_index lane accesses in SROA and readonly alloc alias" {
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;
    if (builtin.cpu.arch != .wasm32) return error.SkipZigTest;

    const S = struct {
        const Rect = struct {
            v: @Vector(4, f32),

            noinline fn x(self: Rect) f32 {
                return self.v[0];
            }

            noinline fn y(self: Rect) f32 {
                return self.v[1];
            }

            noinline fn w(self: Rect) f32 {
                return self.v[2];
            }

            noinline fn h(self: Rect) f32 {
                return self.v[3];
            }

            noinline fn withUpdatedW(self: Rect, new_w: f32) f32 {
                var copy = self;
                copy.v[2] = new_w;
                return copy.v[0] + copy.v[1] + copy.v[2] + copy.v[3];
            }
        };

        noinline fn readLaneFromPtr(ptr: *const Rect) f32 {
            const r = ptr.*;
            return r.v[2];
        }

        noinline fn mutateLaneFromPtr(ptr: *const Rect, delta: f32) f32 {
            var r = ptr.*;
            r.v[2] += delta;
            return r.v[0] + r.v[2];
        }

        noinline fn exerciseVectorLanes(seed: i32) !void {
            var vf32: @Vector(4, f32) = .{ 1.0, 2.0, 3.0, 4.0 };
            vf32[2] = vf32[0] + 10.5;
            try expect(vf32[0] == 1.0);
            try expect(vf32[1] == 2.0);
            try expect(vf32[2] == 11.5);
            try expect(vf32[3] == 4.0);

            var vi32: @Vector(4, i32) = .{ seed, seed + 1, seed + 2, seed + 3 };
            vi32[1] = vi32[3] * 2;
            vi32[3] = -42;
            try expect(vi32[0] == seed);
            try expect(vi32[1] == (seed + 3) * 2);
            try expect(vi32[2] == seed + 2);
            try expect(vi32[3] == -42);

            var vf64: @Vector(2, f64) = .{ 1.25, -3.5 };
            vf64[0] = vf64[1] * 2.0;
            vf64[1] = 8.75;
            try expect(vf64[0] == -7.0);
            try expect(vf64[1] == 8.75);

            var vu16: @Vector(8, u16) = .{ 10, 20, 30, 40, 50, 60, 70, 80 };
            vu16[5] = vu16[2] + 500;
            try expect(vu16[0] == 10);
            try expect(vu16[5] == 530);
            try expect(vu16[7] == 80);

            var vi8: @Vector(16, i8) = .{ -1, -2, -3, -4, 5, 6, 7, 8, -9, -10, 11, 12, -13, 14, -15, 16 };
            vi8[9] = vi8[1] - 20;
            try expect(vi8[0] == -1);
            try expect(vi8[9] == -22);
            try expect(vi8[15] == 16);
        }

        fn readSp() u32 {
            return asm (
                \\ .globaltype __stack_pointer, i32
                \\ global.get __stack_pointer
                \\ local.set %[ret]
                : [ret] "=r" (-> u32),
            );
        }

        inline fn fillRedZone(sp: u32) void {
            const rz: [*]volatile u8 = @ptrFromInt(sp - 64);
            for (0..64) |i| rz[i] = 0xA5;
        }

        inline fn checkRedZone(sp: u32) bool {
            const rz: [*]volatile u8 = @ptrFromInt(sp - 64);
            for (0..64) |i| {
                if (rz[i] != 0xA5) return false;
            }
            return true;
        }
    };

    const rect: S.Rect = .{ .v = .{ 1.5, 2.5, 3.5, 4.5 } };
    const sp_before = S.readSp();
    S.fillRedZone(sp_before);

    const rx = rect.x();
    const ry = rect.y();
    const rw = rect.w();
    const rh = rect.h();
    const updated_sum = rect.withUpdatedW(10.0);
    try S.exerciseVectorLanes(7);
    const rz_lanes = S.checkRedZone(sp_before);

    try expect(rx == 1.5);
    try expect(ry == 2.5);
    try expect(rw == 3.5);
    try expect(rh == 4.5);
    try expect(updated_sum == 1.5 + 2.5 + 10.0 + 4.5);
    if (!rz_lanes) return error.VectorLaneAccessTouchedRedZone;

    var mem_rect: S.Rect = .{ .v = .{ 5.0, 6.0, 7.25, 8.0 } };
    _ = &mem_rect;
    S.fillRedZone(sp_before);
    const ptr_w = S.readLaneFromPtr(&mem_rect);
    const ptr_mut = S.mutateLaneFromPtr(&mem_rect, 2.75);
    const rz_ptr = S.checkRedZone(sp_before);

    try expect(ptr_w == 7.25);
    try expect(ptr_mut == 5.0 + 10.0);
    if (!rz_ptr) return error.VectorPtrLaneLoadTouchedRedZone;

    const sp_after = S.readSp();
    try expect(sp_before == sp_after);
}

test "wasm SROA avoids over-promoting large copy-modify-pass aggregates" {
    if (builtin.zig_backend != .stage2_wasm) return error.SkipZigTest;
    if (builtin.cpu.arch != .wasm32) return error.SkipZigTest;

    const S = struct {
        const SlugInstance = extern struct {
            f0: f32 = 0,
            f1: f32 = 1,
            f2: f32 = 2,
            f3: f32 = 3,
            f4: f32 = 4,
            f5: f32 = 5,
            f6: f32 = 6,
            f7: f32 = 7,
            f8: f32 = 8,
            f9: f32 = 9,
            f10: f32 = 10,
            f11: f32 = 11,
            f12: f32 = 12,
            f13: f32 = 13,
            f14: f32 = 14,
            f15: f32 = 15,
            f16: f32 = 16,
            f17: f32 = 17,
            clip_node: f32 = -1,
        };

        const SlugList = struct {
            items: []SlugInstance,
            len: usize = 0,

            noinline fn appendAssumeCapacity(self: *SlugList, item: SlugInstance) void {
                self.items[self.len] = item;
                self.len += 1;
            }
        };

        const Instance = extern struct {
            f0: f32 = 0,
            f1: f32 = 1,
            f2: f32 = 2,
            f3: f32 = 3,
            f4: f32 = 4,
            f5: f32 = 5,
            f6: f32 = 6,
            f7: f32 = 7,
            f8: f32 = 8,
            f9: f32 = 9,
            f10: f32 = 10,
            f11: f32 = 11,
            f12: f32 = 12,
            f13: f32 = 13,
            f14: f32 = 14,
            f15: f32 = 15,
            f16: f32 = 16,
            f17: f32 = 17,
            f18: f32 = 18,
            f19: f32 = 19,
            f20: f32 = 20,
            f21: f32 = 21,
            f22: f32 = 22,
            f23: f32 = 23,
            f24: f32 = 24,
            f25: f32 = 25,
        };

        noinline fn pushTextInstance(list: *SlugList, instance: SlugInstance, clip_node: f32) void {
            var out = instance;
            out.clip_node = clip_node;
            list.appendAssumeCapacity(out);
        }

        noinline fn pushInstances(out_slice: []Instance, insts: []const Instance, clip: f32) void {
            for (insts, 0..) |inst, i| {
                var out = inst;
                out.f0 += 1.0;
                out.f25 = clip;
                out_slice[i] = out;
            }
        }

        noinline fn destroyAndReplace(box_b: *[16]u32, a: [16]u32, box_a: *[16]u32) void {
            box_a.* = undefined;
            box_b.* = a;
        }
    };

    var slug_buf: [2]S.SlugInstance = undefined;
    var slug_list: S.SlugList = .{ .items = &slug_buf };
    var base_slug: S.SlugInstance = .{};
    base_slug.f0 = 100.5;
    base_slug.f17 = 200.25;
    S.pushTextInstance(&slug_list, base_slug, 42.0);
    S.pushTextInstance(&slug_list, base_slug, 99.0);
    try expect(slug_list.len == 2);
    try expect(slug_buf[0].f0 == 100.5);
    try expect(slug_buf[0].f9 == 9.0);
    try expect(slug_buf[0].f17 == 200.25);
    try expect(slug_buf[0].clip_node == 42.0);
    try expect(slug_buf[1].clip_node == 99.0);

    const src_insts = [2]S.Instance{
        .{ .f0 = 10.0, .f12 = 123.0, .f25 = 0.0 },
        .{ .f0 = 20.0, .f12 = 456.0, .f25 = 0.0 },
    };
    var dst_insts: [2]S.Instance = undefined;
    S.pushInstances(&dst_insts, &src_insts, 77.5);
    try expect(dst_insts[0].f0 == 11.0);
    try expect(dst_insts[0].f12 == 123.0);
    try expect(dst_insts[0].f24 == 24.0);
    try expect(dst_insts[0].f25 == 77.5);
    try expect(dst_insts[1].f0 == 21.0);
    try expect(dst_insts[1].f12 == 456.0);
    try expect(dst_insts[1].f24 == 24.0);
    try expect(dst_insts[1].f25 == 77.5);

    var buf_a: [16]u32 = @splat(0);
    buf_a[0] = 1234;
    var buf_b: [16]u32 = undefined;
    var box_a: *[16]u32 = &buf_a;
    _ = &box_a;
    S.destroyAndReplace(&buf_b, buf_a, box_a);
    try expect(buf_b[0] == 1234);
}
