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
