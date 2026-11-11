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

test "wasm single-exit block elision, unreachable branch elision, undef memset, and inline activeTag" {
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;

    const S = struct {
        const Err = error{ OutOfMemory, Overflow };

        const Payload = struct {
            a: u64,
            b: u64,
            c: u64,
            d: u64,
        };

        const TaggedCmd = union(enum) {
            rect: Payload,
            circle: [4]f64,
            text: struct { x: f32, y: f32, len: u32 },
            clip: u32,
        };

        noinline fn makePayload(seed: u64, fail: bool) Err!Payload {
            if (fail) return error.OutOfMemory;
            return .{ .a = seed, .b = seed + 1, .c = seed + 2, .d = seed + 3 };
        }

        noinline fn evalCondUnreachBlock(x: u32, ok: bool) u32 {
            const doubled: u32 = blk: {
                const v = x * 2;
                if (!ok) unreachable else break :blk v + 7;
            };
            return doubled + 3;
        }

        noinline fn evalSingleCaseSwitch(tag: u8, val: u32) u32 {
            return blk: {
                switch (tag) {
                    1 => break :blk val * 5 + 1,
                    else => unreachable,
                }
            };
        }

        noinline fn evalMultiCaseSwitchUnreachElse(tag: u8, val: u32) u32 {
            return switch (tag) {
                0 => val + 10,
                1 => val + 20,
                2 => val + 30,
                else => unreachable,
            };
        }

        noinline fn evalCatchUnreach(seed: u64) u64 {
            const p = makePayload(seed, false) catch unreachable;
            return p.a + p.d;
        }

        noinline fn inspectActiveTag(cmd: *const TaggedCmd) u32 {
            return switch (std.meta.activeTag(cmd.*)) {
                .rect => @intCast(cmd.rect.a + cmd.rect.b),
                .circle => @intFromFloat(cmd.circle[0] + cmd.circle[3]),
                .text => cmd.text.len,
                .clip => cmd.clip,
            };
        }

        noinline fn exerciseUndefMemset(buf: []Payload, first: Payload) u64 {
            @memset(buf, undefined);
            buf[0] = first;
            return buf[0].b + buf[0].c;
        }

        inline fn sumConstPairs(pairs: []const [2]f32) f32 {
            var acc: f32 = 0;
            for (pairs) |pair| acc += pair[0] + pair[1];
            return acc;
        }

        noinline fn exerciseZeroSplatAndSliceCoercion(out_counts: *[16]u16, mut_pairs: [][2]f32) f32 {
            out_counts.* = @splat(0);
            var local_pos: [16]usize = @splat(0);
            for (mut_pairs, 0..) |*pair, i| {
                pair[0] += 1.0;
                out_counts[i & 15] += 1;
                local_pos[i & 15] += i + 1;
            }
            return sumConstPairs(mut_pairs) + @as(f32, @floatFromInt(local_pos[0] + local_pos[1]));
        }

        noinline fn bitcastU100ToI100IsNegative(val: u100) bool {
            var signed_val: i100 = @bitCast(val);
            _ = &signed_val;
            return signed_val < 0;
        }
    };

    try expect(S.evalCondUnreachBlock(10, true) == 30);
    try expect(S.evalSingleCaseSwitch(1, 8) == 41);
    try expect(S.evalMultiCaseSwitchUnreachElse(0, 5) == 15);
    try expect(S.evalMultiCaseSwitchUnreachElse(1, 5) == 25);
    try expect(S.evalMultiCaseSwitchUnreachElse(2, 5) == 35);
    try expect(S.evalCatchUnreach(100) == 203);
    try std.testing.expectError(error.OutOfMemory, S.makePayload(1, true));

    const cmd_rect: S.TaggedCmd = .{ .rect = .{ .a = 12, .b = 30, .c = 0, .d = 0 } };
    const cmd_text: S.TaggedCmd = .{ .text = .{ .x = 1.0, .y = 2.0, .len = 77 } };
    try expect(S.inspectActiveTag(&cmd_rect) == 42);
    try expect(S.inspectActiveTag(&cmd_text) == 77);

    var backing: [4]S.Payload = undefined;
    try expect(S.exerciseUndefMemset(&backing, .{ .a = 1, .b = 20, .c = 30, .d = 4 }) == 50);

    var counts: [16]u16 = @splat(99);
    var pairs = [2][2]f32{ .{ 1.5, 2.5 }, .{ 3.0, 4.0 } };
    const splat_sum = S.exerciseZeroSplatAndSliceCoercion(&counts, &pairs);
    try expect(counts[0] == 1 and counts[1] == 1 and counts[2] == 0 and counts[15] == 0);
    try expect(splat_sum == (2.5 + 2.5 + 4.0 + 4.0) + 3.0);

    try expect(S.bitcastU100ToI100IsNegative(@as(u100, 1) << 99));
    try expect(!S.bitcastU100ToI100IsNegative(@as(u100, 1) << 98));
}

test "3-scalar and 4-scalar multivalue auto returns and contiguous constant store coalescing" {
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;
    if (builtin.cpu.arch != .wasm32) return error.SkipZigTest;

    const S = struct {
        const Error = error{Invalid};

        const Mixed3 = struct {
            a: u32,
            b: u64,
            c: f32,
        };

        const QuadF32 = struct {
            x: f32,
            y: f32,
            z: f32,
            w: f32,
        };

        const Mixed4 = struct {
            a: u16,
            b: u16,
            c: f32,
            d: f64,
        };

        const SlugLike = extern struct {
            p0: [4]f32 = .{ 1.0, 2.0, 3.0, 4.0 },
            dyn: f32 = 0.0,
            tail_a: f32 = 5.0,
            clip_node: u32 = 99,
        };

        fn readSp() u32 {
            return asm (
                \\ .globaltype __stack_pointer, i32
                \\ global.get __stack_pointer
                \\ local.set %[ret]
                : [ret] "=r" (-> u32),
            );
        }

        noinline fn makeMixed3(x: u32, early: bool) Mixed3 {
            if (early) return .{ .a = x + 1, .b = @as(u64, x) * 10, .c = 1.5 };
            var m: Mixed3 = .{ .a = x * 2, .b = @as(u64, x) + 100, .c = @as(f32, @floatFromInt(x)) + 0.25 };
            m.a += 3;
            return m;
        }

        noinline fn lerpQuad(a: QuadF32, b: QuadF32, t: f32) QuadF32 {
            if (t <= 0.0) return a;
            if (t >= 1.0) return b;
            return .{
                .x = a.x + (b.x - a.x) * t,
                .y = a.y + (b.y - a.y) * t,
                .z = a.z + (b.z - a.z) * t,
                .w = a.w + (b.w - a.w) * t,
            };
        }

        noinline fn makeMixed4(seed: u16) Mixed4 {
            return .{
                .a = seed + 1,
                .b = seed * 3,
                .c = @as(f32, @floatFromInt(seed)) * 0.5,
                .d = @as(f64, @floatFromInt(seed)) * 2.25,
            };
        }

        noinline fn makeU16Triple(x: u16) [3]u16 {
            return .{ x, x + 10, x + 20 };
        }

        noinline fn makeErrorSlice(s: []const u8, fail: bool) Error![]const u8 {
            if (fail) return error.Invalid;
            return s[1..];
        }

        noinline fn makeOptPair(x: u32, present: bool) ?struct { u32, f32 } {
            if (!present) return null;
            return .{ x + 7, @as(f32, @floatFromInt(x)) * 1.5 };
        }

        noinline fn inspectEscapedQuad(q: *const QuadF32) f32 {
            return q.x + q.y * 2.0 + q.z * 3.0 + q.w * 4.0;
        }

        noinline fn writeSlugEntry(out: []SlugLike, idx: usize, dyn: f32, clip: u32) void {
            var inst: SlugLike = .{ .dyn = dyn };
            out[idx] = inst;
            out[idx].clip_node = clip;
            _ = &inst;
        }
    };

    const sp_before = S.readSp();

    const m3_early = S.makeMixed3(5, true);
    try expect(m3_early.a == 6 and m3_early.b == 50 and m3_early.c == 1.5);
    const m3_late = S.makeMixed3(5, false);
    try expect(m3_late.a == 13 and m3_late.b == 105 and m3_late.c == 5.25);

    const q = S.lerpQuad(
        .{ .x = 1.0, .y = 2.0, .z = 3.0, .w = 4.0 },
        .{ .x = 5.0, .y = 10.0, .z = 15.0, .w = 20.0 },
        0.5,
    );
    try expect(q.x == 3.0 and q.y == 6.0 and q.z == 9.0 and q.w == 12.0);

    // Function pointer call returning 4 scalars
    var fn_ptr: *const fn (S.QuadF32, S.QuadF32, f32) S.QuadF32 = &S.lerpQuad;
    _ = &fn_ptr;
    const q_indirect = fn_ptr(q, .{ .x = 0, .y = 0, .z = 0, .w = 0 }, 0.0);
    try expect(q_indirect.x == 3.0 and q_indirect.w == 12.0);

    // Escaped destination in memory for 4-scalar return
    const q_escaped = S.lerpQuad(
        .{ .x = 2.0, .y = 4.0, .z = 6.0, .w = 8.0 },
        .{ .x = 6.0, .y = 8.0, .z = 10.0, .w = 12.0 },
        0.5,
    );
    try expect(S.inspectEscapedQuad(&q_escaped) == 4.0 + 12.0 + 24.0 + 40.0);

    const m4 = S.makeMixed4(4);
    try expect(m4.a == 5 and m4.b == 12 and m4.c == 2.0 and m4.d == 9.0);

    const u16s = S.makeU16Triple(7);
    try expect(u16s[0] == 7 and u16s[1] == 17 and u16s[2] == 27);

    const ok_slice = try S.makeErrorSlice("hello", false);
    try std.testing.expectEqualStrings("ello", ok_slice);
    try std.testing.expectError(error.Invalid, S.makeErrorSlice("hello", true));

    const opt_some = S.makeOptPair(4, true) orelse return error.TestUnexpectedResult;
    try expect(opt_some[0] == 11 and opt_some[1] == 6.0);
    try expect(S.makeOptPair(4, false) == null);

    var slugs: [2]S.SlugLike = undefined;
    S.writeSlugEntry(&slugs, 0, 12.5, 42);
    S.writeSlugEntry(&slugs, 1, -3.25, 7);
    try expect(slugs[0].p0[0] == 1.0 and slugs[0].p0[3] == 4.0);
    try expect(slugs[0].dyn == 12.5 and slugs[0].tail_a == 5.0 and slugs[0].clip_node == 42);
    try expect(slugs[1].dyn == -3.25 and slugs[1].tail_a == 5.0 and slugs[1].clip_node == 7);

    const sp_after = S.readSp();
    try expect(sp_before == sp_after);
}

test "optional/union copy elision, rvalue method calls, and try read-only alloc aliasing" {
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;

    const S = struct {
        const Error = error{Fail};

        const Payload = struct {
            vals: [8]u32,

            noinline fn sumWith(self: Payload, bias: u32) u32 {
                var acc: u32 = bias;
                for (self.vals) |v| acc += v;
                return acc;
            }
        };

        const CmdPayload = union(enum) {
            range: struct { offset: u32, count: u32 },
            heavy: Payload,
            tag_only: u32,
        };

        const Cmd = struct {
            id: u32,
            payload: CmdPayload,
        };

        const Packet = struct {
            cmds: []const Cmd,
            bias: u32,
            extra: [6]u32,

            fn commands(self: *const Packet) []const Cmd {
                return self.cmds;
            }
        };

        noinline fn buildPacket(cmds: []const Cmd, bias: u32, fail: bool) Error!Packet {
            if (fail) return error.Fail;
            return .{
                .cmds = cmds,
                .bias = bias,
                .extra = .{ 1, 2, 3, 4, 5, 6 },
            };
        }

        noinline fn cascadeOptional(a: *const ?Payload, b: *const ?Payload) ?Payload {
            return if (a.*) |v| v else b.*;
        }

        noinline fn processPacket(cmds: []const Cmd, opt_a: *const ?Payload, opt_b: *const ?Payload, fail: bool) Error!u32 {
            const pkt = try buildPacket(cmds, 10, fail);
            var total: u32 = pkt.bias + pkt.extra[5];
            if (cascadeOptional(opt_a, opt_b)) |p| {
                total += p.sumWith(3);
            }
            for (pkt.commands()) |cmd| {
                switch (cmd.payload) {
                    .range => |r| total += r.offset + r.count,
                    .heavy => |h| total += h.sumWith(cmd.id),
                    .tag_only => |t| total += t,
                }
            }
            return total;
        }
    };

    const cmds = [_]S.Cmd{
        .{ .id = 2, .payload = .{ .range = .{ .offset = 10, .count = 5 } } },
        .{ .id = 4, .payload = .{ .heavy = .{ .vals = .{ 1, 2, 3, 4, 5, 6, 7, 8 } } } },
        .{ .id = 6, .payload = .{ .tag_only = 9 } },
    };
    var opt_none: ?S.Payload = null;
    var opt_some: ?S.Payload = .{ .vals = .{ 10, 20, 30, 40, 50, 60, 70, 80 } };
    _ = &opt_none;
    _ = &opt_some;

    const total = try S.processPacket(&cmds, &opt_none, &opt_some, false);
    // 10 + 6 + (360 + 3) + 15 + (36 + 4) + 9 = 443
    try expect(total == 443);
    try std.testing.expectError(error.Fail, S.processPacket(&cmds, &opt_none, &opt_some, true));

    const AliasSafety = struct {
        const Big = struct { a: u64, b: u64, c: u64, d: u64, e: u64, f: [3]u32 };
        const U = union(enum) { big: Big, small: u8 };
        var escaped_ptr: *Big = undefined;
        var dyn_idx: usize = 1;

        noinline fn escape(p: *Big) void {
            escaped_ptr = p;
        }

        noinline fn mutateEscapedAndReadByValue(v: Big) u64 {
            escaped_ptr.f[1] = 77;
            escaped_ptr.a = 7;
            const copy = v;
            return v.f[dyn_idx] + copy.a * 1000;
        }

        noinline fn passEscapedLocalByValue(x: u64) u64 {
            var a: Big = .{ .a = x, .b = x, .c = x, .d = x, .e = x, .f = .{ 1, 2, 3 } };
            escape(&a);
            const v = a;
            return mutateEscapedAndReadByValue(v);
        }

        noinline fn passPtrTargetByValue(p: *const Big) u64 {
            const v = p.*;
            return mutateEscapedAndReadByValue(v);
        }

        noinline fn consumeUnionAndMutateSource(u: U, p: *Big) u64 {
            p.a = 99;
            return u.big.a;
        }

        noinline fn wrapEscapedLocalInUnion(x: u64) u64 {
            var a: Big = .{ .a = x, .b = x, .c = x, .d = x, .e = x, .f = .{ 1, 2, 3 } };
            escape(&a);
            return consumeUnionAndMutateSource(.{ .big = a }, &a);
        }

        noinline fn mutatePtr(p: *Big) void {
            p.a = 99;
        }

        noinline fn copyAndMutateArg(v: Big) u64 {
            var x = v;
            mutatePtr(&x);
            return x.a;
        }

        noinline fn readArgA(v: Big) u64 {
            return v.a;
        }

        noinline fn copyViaSelectedFramePtr(cond: bool, idx: usize, o: *const Big) u64 {
            var b: Big = undefined;
            var a: Big = .{ .a = 1, .b = 2, .c = 3, .d = 4, .e = 5, .f = .{ 10, 11, 12 } };
            var c: Big = .{ .a = 6, .b = 7, .c = 8, .d = 9, .e = 10, .f = .{ 20, 21, 22 } };
            a.f[idx] +%= @intCast(idx);
            c.f[idx] +%= @intCast(idx);
            const p: *const Big = if (cond) &a else &c;
            b = p.*;
            a = o.*;
            c = o.*;
            return b.a * 1000 + b.f[idx] + a.f[idx] + c.f[idx];
        }
    };

    try expect(AliasSafety.passEscapedLocalByValue(42) == 42002);
    var b_esc: AliasSafety.Big = .{ .a = 5, .b = 5, .c = 5, .d = 5, .e = 5, .f = .{ 1, 2, 3 } };
    AliasSafety.escaped_ptr = &b_esc;
    try expect(AliasSafety.passPtrTargetByValue(&b_esc) == 5002);
    try expect(AliasSafety.wrapEscapedLocalInUnion(42) == 42);

    const const_big: AliasSafety.Big = .{ .a = 42, .b = 5, .c = 5, .d = 5, .e = 5, .f = .{ 1, 2, 3 } };
    try expect(AliasSafety.copyAndMutateArg(const_big) == 99);
    try expect(AliasSafety.readArgA(const_big) == 42);
    var local_big: AliasSafety.Big = const_big;
    local_big.b = 6;
    try expect(AliasSafety.copyAndMutateArg(local_big) == 99);
    try expect(AliasSafety.readArgA(local_big) == 42);

    const overwrite_big: AliasSafety.Big = .{ .a = 100, .b = 100, .c = 100, .d = 100, .e = 100, .f = .{ 500, 500, 500 } };
    try expect(AliasSafety.copyViaSelectedFramePtr(true, 1, &overwrite_big) == 2012);
    try expect(AliasSafety.copyViaSelectedFramePtr(false, 1, &overwrite_big) == 7022);
}

test "wasm_multivalue calling convention (#229)" {
    if (comptime !std.Target.wasm.featureSetHas(builtin.cpu.features, .multivalue)) return error.SkipZigTest;

    const S = struct {
        const Pair = extern struct {
            a: u32,
            b: u64,
        };

        const WrappedPair = extern struct {
            inner: Pair,
        };

        const SingleU32 = extern struct {
            a: u32,
        };

        const SingleF32 = extern struct {
            b: f32,
        };

        const PairOfSingleWrappers = extern struct {
            x: SingleU32,
            y: SingleF32,
        };

        const WidePair = extern struct {
            lo: u128,
            hi: f64,
        };

        const DoubleWidePair = extern struct {
            a: u128,
            b: u128,
        };

        const Triple = extern struct {
            x: u32,
            y: u32,
            z: u32,
        };

        const FiveFields = extern struct {
            a: u32,
            b: u64,
            c: f32,
            d: f64,
            e: u32,
        };

        // 2-scalar-field struct parameter expanded into (i32, i64); 3-field struct returned by multivalue
        noinline fn pairToTriple(p: Pair, extra: u32) callconv(.{ .wasm_multivalue = .{} }) Triple {
            return .{
                .x = p.a + extra,
                .y = @as(u32, @truncate(p.b)),
                .z = @as(u32, @truncate(p.b >> 32)) + extra,
            };
        }

        // Nested multi-field struct inside 1-field struct (Foo9 in Clang wasm-multivalue-abi.c) passed/returned indirectly
        noinline fn wrappedPairRoundtrip(w: WrappedPair) callconv(.{ .wasm_multivalue = .{} }) WrappedPair {
            return .{ .inner = .{ .a = w.inner.a + 3, .b = w.inner.b + 7 } };
        }

        // 2 fields that are each single-element structs (Foo7 in Clang wasm-multivalue-abi.c) expanded into (i32, f32)
        noinline fn pairOfSingleWrappersCombine(p: PairOfSingleWrappers) callconv(.{ .wasm_multivalue = .{} }) PairOfSingleWrappers {
            return .{
                .x = .{ .a = p.x.a * 2 },
                .y = .{ .b = p.y.b + 1.5 },
            };
        }

        // 2-field struct containing u128 (split into 2 i64s) and f64 -> 3 Wasm params
        noinline fn widePairCombine(wp: WidePair) callconv(.{ .wasm_multivalue = .{} }) u128 {
            return wp.lo + @as(u128, @intFromFloat(wp.hi));
        }

        // 2-field struct containing two u128s -> 4 Wasm i64 params and 4 Wasm i64 return values
        noinline fn doubleWidePairSwap(dwp: DoubleWidePair) callconv(.{ .wasm_multivalue = .{} }) DoubleWidePair {
            return .{ .a = dwp.b + 1, .b = dwp.a + 2 };
        }

        // 3-field struct parameter passed indirectly by pointer; 5-field struct returned by multivalue
        noinline fn tripleToFive(t: Triple) callconv(.{ .wasm_multivalue = .{} }) FiveFields {
            return .{
                .a = t.x + 1,
                .b = @as(u64, t.y) * 10,
                .c = @as(f32, @floatFromInt(t.z)) + 0.5,
                .d = @as(f64, @floatFromInt(t.x + t.y)) * 1.25,
                .e = t.x ^ t.z,
            };
        }
    };

    const t = S.pairToTriple(.{ .a = 10, .b = (20 << 32) | 30 }, 5);
    try expect(t.x == 15);
    try expect(t.y == 30);
    try expect(t.z == 25);

    const wp_rt = S.wrappedPairRoundtrip(.{ .inner = .{ .a = 7, .b = 93 } });
    try expect(wp_rt.inner.a == 10 and wp_rt.inner.b == 100);

    const foo7 = S.pairOfSingleWrappersCombine(.{ .x = .{ .a = 11 }, .y = .{ .b = 2.5 } });
    try expect(foo7.x.a == 22 and foo7.y.b == 4.0);

    const wp_res = S.widePairCombine(.{ .lo = (@as(u128, 3) << 64) | 100, .hi = 25.0 });
    try expect(wp_res == ((@as(u128, 3) << 64) | 125));

    const dwp = S.doubleWidePairSwap(.{
        .a = (@as(u128, 10) << 64) | 20,
        .b = (@as(u128, 30) << 64) | 40,
    });
    try expect(dwp.a == ((@as(u128, 30) << 64) | 41));
    try expect(dwp.b == ((@as(u128, 10) << 64) | 22));

    var fn_ptr: *const fn (S.Triple) callconv(.{ .wasm_multivalue = .{} }) S.FiveFields = &S.tripleToFive;
    _ = &fn_ptr;
    const five = fn_ptr(.{ .x = 4, .y = 6, .z = 9 });
    try expect(five.a == 5);
    try expect(five.b == 60);
    try expect(five.c == 9.5);
    try expect(five.d == 12.5);
    try expect(five.e == (4 ^ 9));
}

test "wasm tail calls: return_call and return_call_indirect (#230)" {
    if (comptime !std.Target.wasm.featureSetHas(builtin.cpu.features, .tail_call)) return error.SkipZigTest;

    const S = struct {
        const BigRet = extern struct {
            a: u64,
            b: u64,
            c: u64,
            d: u64,
            e: u64,
        };

        fn readSp() u32 {
            return asm (
                \\ .globaltype __stack_pointer, i32
                \\ global.get __stack_pointer
                \\ local.set %[ret]
                : [ret] "=r" (-> u32),
            );
        }

        noinline fn sumTailWithFrame(n: u32, acc: u64) u64 {
            var local_frame: [8]u32 = .{ n, n + 1, n + 2, n + 3, n + 4, n + 5, n + 6, n + 7 };
            _ = &local_frame;
            if (n == 0) return acc + local_frame[0];
            return @call(.always_tail, sumTailWithFrame, .{ n - 1, acc + local_frame[0] });
        }

        const StepFn = *const fn (u32, u32) u32;

        fn stepA(n: u32, acc: u32) u32 {
            if (n == 0) return acc;
            var next: StepFn = &stepB;
            _ = &next;
            return @call(.always_tail, next, .{ n - 1, acc + 2 });
        }

        fn stepB(n: u32, acc: u32) u32 {
            if (n == 0) return acc;
            var next: StepFn = &stepA;
            _ = &next;
            return @call(.always_tail, next, .{ n - 1, acc + 3 });
        }

        noinline fn sretTailCallee(v: BigRet, delta: u64) callconv(.c) BigRet {
            var callee_frame: [8]u64 = .{ delta, delta + 1, delta + 2, delta + 3, delta + 4, delta + 5, delta + 6, delta + 7 };
            _ = &callee_frame;
            return .{
                .a = v.a + callee_frame[0],
                .b = v.b + callee_frame[1],
                .c = v.c + callee_frame[2],
                .d = v.d + callee_frame[3],
                .e = v.e + callee_frame[4],
            };
        }

        noinline fn sretTailCaller(v: BigRet, delta: u64) callconv(.c) BigRet {
            const updated: BigRet = .{
                .a = v.a + 1,
                .b = v.b + 2,
                .c = v.c + 3,
                .d = v.d + 4,
                .e = v.e + 5,
            };
            return @call(.always_tail, sretTailCallee, .{ updated, delta });
        }

        noinline fn readEscapedLocal(ptr: *const [4]u64, extra: u64) u64 {
            var clobber: [8]u64 = .{ 0xdead, 0xbeef, 0xcafe, 0xbabe, 0x1111, 0x2222, 0x3333, 0x4444 };
            _ = &clobber;
            return ptr[0] + ptr[1] + ptr[2] + ptr[3] + extra + (clobber[0] - 0xdead);
        }

        noinline fn tailCallWithEscapedLocalPtr(unused_ptr: *const [4]u64, seed: u64) u64 {
            _ = unused_ptr;
            var local_arr: [4]u64 = .{ seed, seed + 10, seed + 20, seed + 30 };
            return @call(.always_tail, readEscapedLocal, .{ &local_arr, 0 });
        }

        noinline fn readEscapedLocalVoid(ptr: *const [4]u64, out: *u64) void {
            var clobber: [8]u64 = .{ 0xdead, 0xbeef, 0xcafe, 0xbabe, 0x1111, 0x2222, 0x3333, 0x4444 };
            _ = &clobber;
            out.* = ptr[0] + ptr[1] + ptr[2] + ptr[3] + (clobber[0] - 0xdead);
        }

        noinline fn tailCallWithEscapedLocalPtrVoid(unused_ptr: *const [4]u64, out: *u64) void {
            _ = unused_ptr;
            var local_arr: [4]u64 = .{ 10, 20, 30, 40 };
            return @call(.always_tail, readEscapedLocalVoid, .{ &local_arr, out });
        }
    };

    const sp_before = S.readSp();
    const sum = S.sumTailWithFrame(2000, 0);
    const sp_after = S.readSp();
    try expect(sp_before == sp_after);
    try expect(sum == @as(u64, 2000) * 2001 / 2);

    const indirect_res = S.stepA(100, 0);
    try expect(indirect_res == 50 * 2 + 50 * 3);
    try expect(S.readSp() == sp_before);

    const big_res = S.sretTailCaller(.{ .a = 10, .b = 20, .c = 30, .d = 40, .e = 50 }, 100);
    try expect(big_res.a == 111 and big_res.b == 123 and big_res.c == 135 and big_res.d == 147 and big_res.e == 159);
    try expect(S.readSp() == sp_before);

    const dummy_arr: [4]u64 = .{ 0, 0, 0, 0 };
    try expect(S.tailCallWithEscapedLocalPtr(&dummy_arr, 5) == 5 + 15 + 25 + 35);
    try expect(S.readSp() == sp_before);

    var void_out: u64 = 0;
    S.tailCallWithEscapedLocalPtrVoid(&dummy_arr, &void_out);
    try expect(void_out == 100);
    try expect(S.readSp() == sp_before);
}

test "wasm f16 soft-promotion to native f32 (#231)" {
    const S = struct {
        noinline fn f16Ops(a: f16, b: f16) struct {
            add: f16,
            sub: f16,
            mul: f16,
            fma: f16,
            reuse_expr: f16,
            div: f16,
            sqrt_a: f16,
            floor_a: f16,
            ceil_a: f16,
            trunc_a: f16,
            min_ab: f16,
            max_ab: f16,
            to_i32: i32,
            to_u64: u64,
            from_i16: f16,
            from_u32: f16,
        } {
            return .{
                .add = a + b,
                .sub = a - b,
                .mul = a * b,
                .fma = @mulAdd(f16, a, b, 0.5),
                .reuse_expr = (a * b) + (a - b) + (a + 1.25),
                .div = a / b,
                .sqrt_a = @sqrt(a),
                .floor_a = @floor(a),
                .ceil_a = @ceil(a),
                .trunc_a = @trunc(-a),
                .min_ab = @min(a, b),
                .max_ab = @max(a, b),
                .to_i32 = @intFromFloat(a),
                .to_u64 = @intFromFloat(b),
                .from_i16 = @floatFromInt(@as(i16, -42)),
                .from_u32 = @floatFromInt(@as(u32, 128)),
            };
        }

        noinline fn preserveBitCast(bits: u16) u16 {
            const f: f16 = @bitCast(bits);
            return @bitCast(f);
        }
    };

    const r = S.f16Ops(2.25, 1.5);
    try expect(r.add == 3.75);
    try expect(r.sub == 0.75);
    try expect(r.mul == 3.375);
    try expect(r.fma == 3.875);
    try expect(r.reuse_expr == 3.375 + 0.75 + 3.5);
    try expect(r.div == 1.5);
    try expect(r.sqrt_a == 1.5);
    try expect(r.floor_a == 2.0);
    try expect(r.ceil_a == 3.0);
    try expect(r.trunc_a == -2.0);
    try expect(r.min_ab == 1.5);
    try expect(r.max_ab == 2.25);
    try expect(r.to_i32 == 2);
    try expect(r.to_u64 == 1);
    try expect(r.from_i16 == -42.0);
    try expect(r.from_u32 == 128.0);

    // Signaling/custom NaN bit-patterns must survive @bitCast without lossy canonicalization
    try expect(S.preserveBitCast(0x7c01) == 0x7c01);
    try expect(S.preserveBitCast(0xfe55) == 0xfe55);
}

test "wasm 128-bit integer add, sub, mul, and 64-bit mulWithOverflow (#232)" {
    const S = struct {
        noinline fn add128(a: u128, b: u128) u128 {
            return a +% b;
        }

        noinline fn sub128(a: u128, b: u128) u128 {
            return a -% b;
        }

        noinline fn mul128Full(a: u128, b: u128) u128 {
            return a *% b;
        }

        noinline fn mulWideU64(a: u64, b: u64) u128 {
            return @as(u128, a) * @as(u128, b);
        }

        noinline fn mulOverflowU64(a: u64, b: u64) struct { u64, u1 } {
            return @mulWithOverflow(a, b);
        }

        noinline fn mulOverflowI64(a: i64, b: i64) struct { i64, u1 } {
            return @mulWithOverflow(a, b);
        }

        noinline fn mulOverflowU39(a: u39, b: u39) struct { u39, u1 } {
            return @mulWithOverflow(a, b);
        }

        noinline fn mulOverflowI39(a: i39, b: i39) struct { i39, u1 } {
            return @mulWithOverflow(a, b);
        }
    };

    const a: u128 = (@as(u128, 0x1234_5678_9abc_def0) << 64) | 0xfedc_ba98_7654_3210;
    const b: u128 = (@as(u128, 0x0111_2222_3333_4444) << 64) | 0x1111_1111_1111_1111;
    const sum = S.add128(a, b);
    try expect(S.sub128(sum, b) == a);

    const wide = S.mulWideU64(0x1_0000_0000, 0x2_0000_0003);
    try expect(wide == (@as(u128, 2) << 64) | 0x3_0000_0000);

    const full = S.mul128Full((@as(u128, 5) << 64) | 7, (@as(u128, 11) << 64) | 13);
    try expect(full == ((@as(u128, 5 * 13 + 7 * 11) << 64) | 91));

    const ov_u0 = S.mulOverflowU64(1_000_000, 2_000_000);
    try expect(ov_u0[0] == 2_000_000_000_000 and ov_u0[1] == 0);
    const ov_u1 = S.mulOverflowU64(0x8000_0000_0000_0000, 2);
    try expect(ov_u1[0] == 0 and ov_u1[1] == 1);

    const ov_s0 = S.mulOverflowI64(-1000, 2000);
    try expect(ov_s0[0] == -2_000_000 and ov_s0[1] == 0);
    const ov_s1 = S.mulOverflowI64(std.math.maxInt(i64), 2);
    try expect(ov_s1[1] == 1);

    const ov_u39_0 = S.mulOverflowU39(@as(u39, 1) << 32, 64);
    try expect(ov_u39_0[0] == (@as(u39, 1) << 38) and ov_u39_0[1] == 0);
    const ov_u39_1 = S.mulOverflowU39(@as(u39, 1) << 33, 64);
    try expect(ov_u39_1[0] == 0 and ov_u39_1[1] == 1);
    const ov_i39_0 = S.mulOverflowI39(-(@as(i39, 1) << 30), 64);
    try expect(ov_i39_0[0] == -(@as(i39, 1) << 36) and ov_i39_0[1] == 0);
    const ov_i39_1 = S.mulOverflowI39(std.math.maxInt(i39), 2);
    try expect(ov_i39_1[1] == 1);
}

test "wasm .optimized float mode, vector @mulAdd, vector @popCount, and v128.andnot (#233)" {
    const S = struct {
        noinline fn scalarOptimized(a: f32, b: f32, c: f32) f32 {
            @setFloatMode(.optimized);
            const x = (a + b) * c - (a / b);
            const neg = -x;
            return if (x > neg) x else neg;
        }

        noinline fn vectorOptimized(a: @Vector(4, f32), b: @Vector(4, f32), c: @Vector(4, f32)) f32 {
            @setFloatMode(.optimized);
            const prod = @mulAdd(@Vector(4, f32), a, b, c);
            const diff = prod - (a / b);
            const mask = diff > @as(@Vector(4, f32), @splat(0.0));
            const selected = @select(f32, mask, diff, -diff);
            return @reduce(.Add, selected) + @reduce(.Max, prod) + @reduce(.Min, prod);
        }

        noinline fn vectorMulAddF64(a: @Vector(2, f64), b: @Vector(2, f64), c: @Vector(2, f64)) @Vector(2, f64) {
            return @mulAdd(@Vector(2, f64), a, b, c);
        }

        noinline fn vectorMulAddF16(a: @Vector(8, f16), b: @Vector(8, f16), c: @Vector(8, f16)) @Vector(8, f16) {
            return @mulAdd(@Vector(8, f16), a, b, c);
        }

        noinline fn vectorPopCounts(
            v8: @Vector(16, u8),
            v16: @Vector(8, u16),
            v32: @Vector(4, u32),
            v64: @Vector(2, u64),
        ) u64 {
            const p8 = @popCount(v8);
            const p16 = @popCount(v16);
            const p32 = @popCount(v32);
            const p64 = @popCount(v64);
            return @as(u64, p8[0] + p8[15]) +
                @as(u64, p16[0] + p16[7]) +
                @as(u64, p32[0] + p32[3]) +
                @as(u64, p64[0] + p64[1]);
        }

        noinline fn vectorAndNot(a: @Vector(4, u32), b: @Vector(4, u32)) @Vector(4, u32) {
            return (a & ~b) ^ (~a & b);
        }
    };

    try expect(S.scalarOptimized(4.0, 2.0, 3.0) == 16.0);

    const va: @Vector(4, f32) = .{ 2.0, 4.0, 6.0, 8.0 };
    const vb: @Vector(4, f32) = .{ 1.0, 2.0, 3.0, 4.0 };
    const vc: @Vector(4, f32) = .{ 0.5, 1.0, 1.5, 2.0 };
    // prod = { 2.5, 9.0, 19.5, 34.0 }, a/b = { 2.0, 2.0, 2.0, 2.0 }
    // diff = { 0.5, 7.0, 17.5, 32.0 } -> sum = 57.0, max(prod) = 34.0, min(prod) = 2.5 -> 93.5
    try expect(S.vectorOptimized(va, vb, vc) == 93.5);

    const mf64 = S.vectorMulAddF64(.{ 1.5, 2.5 }, .{ 4.0, 2.0 }, .{ 0.5, -1.0 });
    try expect(mf64[0] == 6.5 and mf64[1] == 4.0);

    const mf16 = S.vectorMulAddF16(
        .{ 1.5, 2.0, 3.0, 4.0, 0.5, 1.0, 2.5, -1.0 },
        .{ 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 2.0, 3.0 },
        .{ 0.5, 1.0, -2.0, 0.0, 1.0, -3.0, 0.5, 5.0 },
    );
    try expect(mf16[0] == 3.5 and mf16[1] == 7.0 and mf16[2] == 10.0 and mf16[7] == 2.0);

    const pop_sum = S.vectorPopCounts(
        .{ 0x00, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 0xFF },
        .{ 0x0001, 2, 3, 4, 5, 6, 7, 0xFFFF },
        .{ 0x0000_0001, 2, 3, 0xFFFF_FFFF },
        .{ 0x0101_0101_0101_0101, 0xFFFF_FFFF_FFFF_FFFF },
    );
    // p8[0]=0, p8[15]=8; p16[0]=1, p16[7]=16; p32[0]=1, p32[3]=32; p64[0]=8, p64[1]=64 -> 130
    try expect(pop_sum == 130);

    const x: @Vector(4, u32) = .{ 0xF0F0_F0F0, 0x1234_5678, 0xAAAA_5555, 0xFFFF_0000 };
    const y: @Vector(4, u32) = .{ 0xFF00_FF00, 0x8765_4321, 0x5555_AAAA, 0x00FF_00FF };
    const an = S.vectorAndNot(x, y);
    try expect(@reduce(.And, an == (x ^ y)));
}

test "wasm shift mask elision and rotate synthesis (#234)" {
    const S = struct {
        noinline fn maskedShifts(x: u32, y: u64, k: u32) u64 {
            const s32 = (x << @intCast(k & 31)) ^ (x >> @intCast(k & 31));
            const s64 = (y << @intCast(k & 63)) ^ (y >> @intCast(k & 63));
            return @as(u64, s32) ^ s64;
        }

        noinline fn rotates(x: u32, y: u64, k: u32) u64 {
            const r32_const = (x << 7) | (x >> 25);
            const r32_var = std.math.rotl(u32, x, k);
            const r64_const = (y >> 19) | (y << 45);
            const r64_var = std.math.rotr(u64, y, k);
            return @as(u64, r32_const ^ r32_var) ^ r64_const ^ r64_var;
        }
    };

    try expect(S.maskedShifts(0x1234_5678, 0x1234_5678_9abc_def0, 37) ==
        (@as(u64, (@as(u32, 0x1234_5678) << 5) ^ (@as(u32, 0x1234_5678) >> 5)) ^
            ((@as(u64, 0x1234_5678_9abc_def0) << 37) ^ (@as(u64, 0x1234_5678_9abc_def0) >> 37))));

    const x: u32 = 0x89ab_cdef;
    const y: u64 = 0x0123_4567_89ab_cdef;
    try expect(S.rotates(x, y, 11) ==
        (@as(u64, std.math.rotl(u32, x, 7) ^ std.math.rotl(u32, x, 11)) ^
            std.math.rotr(u64, y, 19) ^ std.math.rotr(u64, y, 11)));
}

test "wasm inline byteSwap across signed/unsigned widths and SIMD vector select" {
    if (builtin.cpu.arch != .wasm32 and builtin.cpu.arch != .wasm64) return error.SkipZigTest;

    const S = struct {
        noinline fn swapU8(v: u8) u8 {
            return @byteSwap(v);
        }
        noinline fn swapI8(v: i8) i8 {
            return @byteSwap(v);
        }
        noinline fn swapU16(v: u16) u16 {
            return @byteSwap(v);
        }
        noinline fn swapI16(v: i16) i16 {
            return @byteSwap(v);
        }
        noinline fn swapU24(v: u24) u24 {
            return @byteSwap(v);
        }
        noinline fn swapI24(v: i24) i24 {
            return @byteSwap(v);
        }
        noinline fn swapU32(v: u32) u32 {
            return @byteSwap(v);
        }
        noinline fn swapI32(v: i32) i32 {
            return @byteSwap(v);
        }
        noinline fn swapU48(v: u48) u48 {
            return @byteSwap(v);
        }
        noinline fn swapI48(v: i48) i48 {
            return @byteSwap(v);
        }
        noinline fn swapU64(v: u64) u64 {
            return @byteSwap(v);
        }
        noinline fn swapI64(v: i64) i64 {
            return @byteSwap(v);
        }
        noinline fn swapU128(v: u128) u128 {
            return @byteSwap(v);
        }
        noinline fn clampVec4(v: @Vector(4, f32), lo: @Vector(4, f32), hi: @Vector(4, f32)) @Vector(4, f32) {
            const cond_lo = v < lo;
            const t = @select(f32, cond_lo, lo, v);
            const cond_hi = t > hi;
            return @select(f32, cond_hi, hi, t);
        }
    };

    try expect(S.swapU8(0xAB) == 0xAB);
    try expect(S.swapI8(-5) == -5);
    try expect(S.swapU16(0x1234) == 0x3412);
    try expect(S.swapI16(@bitCast(@as(u16, 0xFFFE))) == @as(i16, @bitCast(@as(u16, 0xFEFF))));
    try expect(S.swapU24(0x123456) == 0x563412);
    try expect(S.swapI24(@bitCast(@as(u24, 0x1234FE))) == @as(i24, @bitCast(@as(u24, 0xFE3412))));
    try expect(S.swapU32(0x1234_5678) == 0x7856_3412);
    try expect(S.swapI32(@bitCast(@as(u32, 0x89AB_CDEF))) == @as(i32, @bitCast(@as(u32, 0xEFCD_AB89))));
    try expect(S.swapU48(0x0123_4567_89AB) == 0xAB89_6745_2301);
    try expect(S.swapI48(@bitCast(@as(u48, 0x0123_4567_89FE))) == @as(i48, @bitCast(@as(u48, 0xFE89_6745_2301))));
    try expect(S.swapU64(0x0123_4567_89AB_CDEF) == 0xEFCD_AB89_6745_2301);
    try expect(S.swapI64(@bitCast(@as(u64, 0x0123_4567_89AB_CDFE))) == @as(i64, @bitCast(@as(u64, 0xFECD_AB89_6745_2301))));
    try expect(S.swapU128(0x0123456789ABCDEF_FEDCBA9876543210) == 0x1032547698BADCFE_EFCDAB8967452301);

    const clamped = S.clampVec4(
        .{ -3.0, 0.5, 4.0, 12.0 },
        .{ 0.0, 0.0, 0.0, 0.0 },
        .{ 10.0, 10.0, 10.0, 10.0 },
    );
    try expect(clamped[0] == 0.0 and clamped[1] == 0.5 and clamped[2] == 4.0 and clamped[3] == 10.0);
}
