const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const testing = std.testing;

extern fn cabi_realloc(
    old_ptr: ?[*]u8,
    old_len: usize,
    alignment: usize,
    new_len: usize,
) callconv(.c) ?[*]u8;

fn verifyTarget() !void {
    try testing.expectEqual(std.Target.Os.Tag.wasip3, builtin.os.tag);
    try testing.expectEqual(std.Target.Os.Tag.wasip3, builtin.target.os.tag);
    try testing.expect(builtin.os.tag.isWasi());
    try testing.expectEqual(std.Target.Cpu.Arch.wasm32, builtin.cpu.arch);
}

fn verifyCabiRealloc() !void {
    // Invalid alignment (0 or non-power-of-two) returns null.
    try testing.expectEqual(@as(?[*]u8, null), cabi_realloc(null, 0, 0, 16));
    try testing.expectEqual(@as(?[*]u8, null), cabi_realloc(null, 0, 3, 16));

    const alignments = [_]usize{ 1, 4, 8, 16 };
    for (alignments) |alignment| {
        // Zero-size allocation returns an aligned dangling pointer without trapping.
        const zero_ptr = cabi_realloc(null, 0, alignment, 0) orelse return error.UnexpectedNull;
        try testing.expectEqual(alignment, @intFromPtr(zero_ptr));

        // Fresh allocation.
        const initial_len: usize = 32;
        const ptr = cabi_realloc(null, 0, alignment, initial_len) orelse return error.OutOfMemory;
        try testing.expectEqual(@as(usize, 0), @intFromPtr(ptr) % alignment);
        for (0..initial_len) |i| {
            ptr[i] = @truncate(i *% 7 + alignment);
        }

        // Growing resize preserves existing bytes.
        const grown_len: usize = 128;
        const grown = cabi_realloc(ptr, initial_len, alignment, grown_len) orelse return error.OutOfMemory;
        try testing.expectEqual(@as(usize, 0), @intFromPtr(grown) % alignment);
        for (0..initial_len) |i| {
            try testing.expectEqual(@as(u8, @truncate(i *% 7 + alignment)), grown[i]);
        }
        for (initial_len..grown_len) |i| {
            grown[i] = @truncate(i *% 13 + 3);
        }

        // Shrinking resize preserves prefix bytes.
        const shrunk_len: usize = 16;
        const shrunk = cabi_realloc(grown, grown_len, alignment, shrunk_len) orelse return error.OutOfMemory;
        try testing.expectEqual(@as(usize, 0), @intFromPtr(shrunk) % alignment);
        for (0..shrunk_len) |i| {
            try testing.expectEqual(@as(u8, @truncate(i *% 7 + alignment)), shrunk[i]);
        }

        // Zero-size resize frees the allocation and returns an aligned dangling pointer.
        const freed_ptr = cabi_realloc(shrunk, shrunk_len, alignment, 0) orelse return error.UnexpectedNull;
        try testing.expectEqual(alignment, @intFromPtr(freed_ptr));
    }
}

fn verifyStdio(io: Io) !void {
    try Io.File.stdout().writeStreamingAll(io, "wasip3-stdout-ok\n");
    try Io.File.stderr().writeStreamingAll(io, "wasip3-stderr-ok\n");
    std.debug.print("wasip3-debug-print-ok\n", .{});
}

fn verifyClocks(io: Io) !void {
    const awake_start = Io.Clock.Timestamp.now(io, .awake);
    const real_now = Io.Clock.Timestamp.now(io, .real);
    try testing.expect(awake_start.raw.nanoseconds > 0);
    try testing.expect(real_now.raw.nanoseconds > 0);

    try io.sleep(.fromMilliseconds(5), .awake);

    const awake_end = Io.Clock.Timestamp.now(io, .awake);
    const elapsed = awake_start.durationTo(awake_end);
    try testing.expect(elapsed.raw.nanoseconds >= 1 * std.time.ns_per_ms);
}

fn verifyRandom(io: Io) !void {
    var buf1: [32]u8 = @splat(0);
    var buf2: [32]u8 = @splat(0);
    io.random(&buf1);
    io.random(&buf2);

    var non_zero = false;
    for (buf1) |b| {
        if (b != 0) {
            non_zero = true;
            break;
        }
    }
    try testing.expect(non_zero);
    try testing.expect(!std.mem.eql(u8, &buf1, &buf2));
}

fn verifyFilesystem(io: Io) !void {
    const cwd = Io.Dir.cwd();
    const base_dir = "wasip3_e2e_fs_test_dir";
    const sub_dir = "wasip3_e2e_fs_test_dir/nested";
    const file_path = "wasip3_e2e_fs_test_dir/nested/hello.txt";
    const renamed_path = "wasip3_e2e_fs_test_dir/nested/renamed.txt";

    // Clean up any leftover artifacts from a prior interrupted run.
    cwd.deleteFile(io, file_path) catch {};
    cwd.deleteFile(io, renamed_path) catch {};
    cwd.deleteDir(io, sub_dir) catch {};
    cwd.deleteDir(io, base_dir) catch {};

    try cwd.createDirPath(io, sub_dir);

    {
        var file = try cwd.createFile(io, file_path, .{ .read = true, .truncate = true });
        defer file.close(io);

        try file.writeStreamingAll(io, "Hello, WASI Preview 3!");
        try file.writePositionalAll(io, "WORLD", 7);

        const fstat = try file.stat(io);
        try testing.expectEqual(Io.File.Kind.file, fstat.kind);
        try testing.expectEqual(@as(u64, 22), fstat.size);

        var pos_buf: [5]u8 = undefined;
        const pos_n = try file.readPositionalAll(io, &pos_buf, 7);
        try testing.expectEqual(@as(usize, 5), pos_n);
        try testing.expectEqualStrings("WORLD", pos_buf[0..pos_n]);
    }

    const dstat = try cwd.statFile(io, file_path, .{});
    try testing.expectEqual(Io.File.Kind.file, dstat.kind);
    try testing.expectEqual(@as(u64, 22), dstat.size);

    var read_buf: [64]u8 = undefined;
    const content = try cwd.readFile(io, file_path, &read_buf);
    try testing.expectEqualStrings("Hello, WORLDPreview 3!", content);

    {
        var dir = try cwd.openDir(io, sub_dir, .{ .iterate = true });
        defer dir.close(io);

        var found_hello = false;
        var entry_count: usize = 0;
        var it = dir.iterate();
        while (try it.next(io)) |entry| {
            entry_count += 1;
            if (std.mem.eql(u8, entry.name, "hello.txt")) {
                try testing.expectEqual(Io.File.Kind.file, entry.kind);
                found_hello = true;
            }
        }
        try testing.expect(found_hello);
        try testing.expectEqual(@as(usize, 1), entry_count);

        // Verify directory mutation (createFile / deleteFile) on an opened subdirectory
        // exercises descriptor-flags.mutate-directory (0x20) in path_open.
        {
            var nested_file = try dir.createFile(io, "nested_via_opendir.txt", .{ .read = true });
            defer nested_file.close(io);
            var nested_writer = nested_file.writer(io, &.{});
            try nested_writer.interface.writeAll("Opened dir mutation!");
        }
        const nested_content = try dir.readFile(io, "nested_via_opendir.txt", &read_buf);
        try testing.expectEqualStrings("Opened dir mutation!", nested_content);
        try dir.deleteFile(io, "nested_via_opendir.txt");
        try testing.expectError(error.FileNotFound, dir.statFile(io, "nested_via_opendir.txt", .{}));
    }

    try cwd.rename(file_path, cwd, renamed_path, io);
    try testing.expectError(error.FileNotFound, cwd.statFile(io, file_path, .{}));

    const renamed_content = try cwd.readFile(io, renamed_path, &read_buf);
    try testing.expectEqualStrings("Hello, WORLDPreview 3!", renamed_content);

    try cwd.deleteFile(io, renamed_path);
    try testing.expectError(error.FileNotFound, cwd.statFile(io, renamed_path, .{}));

    try cwd.deleteDir(io, sub_dir);
    try cwd.deleteDir(io, base_dir);
    try testing.expectError(error.FileNotFound, cwd.statFile(io, base_dir, .{}));
}

fn verifyWasmAllocator() !void {
    const gpa = std.heap.wasm_allocator;

    var list: std.ArrayList(u64) = .empty;
    defer list.deinit(gpa);

    for (0..512) |i| {
        try list.append(gpa, @as(u64, @intCast(i)) *% 0x0102_0304_0506_0708);
    }
    for (list.items, 0..) |val, i| {
        try testing.expectEqual(@as(u64, @intCast(i)) *% 0x0102_0304_0506_0708, val);
    }

    // Multi-page allocation (128 KiB) to exercise memory.grow.
    const big = try gpa.alignedAlloc(u8, .@"16", 128 * 1024);
    defer gpa.free(big);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(big.ptr) % 16);
    @memset(big, 0xA5);
    try testing.expectEqual(@as(u8, 0xA5), big[0]);
    try testing.expectEqual(@as(u8, 0xA5), big[big.len - 1]);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    try verifyTarget();
    try verifyCabiRealloc();
    try verifyStdio(io);

    // Verify CLI arguments passed via `wasmtime run ... wasip3_e2e.wasm arg_one arg_two`.
    var args_list: std.ArrayList([]u8) = .empty;
    defer {
        for (args_list.items) |arg| gpa.free(arg);
        args_list.deinit(gpa);
    }
    var arg_it = try init.minimal.args.iterateAllocator(gpa);
    defer arg_it.deinit();
    while (arg_it.next()) |arg| {
        try args_list.append(gpa, try gpa.dupe(u8, arg));
    }
    try testing.expect(args_list.items.len >= 3);
    try testing.expectEqualStrings("arg_one", args_list.items[1]);
    try testing.expectEqualStrings("arg_two", args_list.items[2]);

    // Verify environment variables passed via `wasmtime run --env TEST_ENV_KEY=wasip3_val`.
    const env_val = init.environ_map.get("TEST_ENV_KEY") orelse return error.MissingExpectedEnvVar;
    try testing.expectEqualStrings("wasip3_val", env_val);

    var minimal_env_map = try init.minimal.environ.createMap(gpa);
    defer minimal_env_map.deinit();
    try testing.expectEqualStrings("wasip3_val", minimal_env_map.get("TEST_ENV_KEY").?);

    try verifyClocks(io);
    try verifyRandom(io);
    try verifyFilesystem(io);
    try verifyWasmAllocator();
}

test "wasip3 target tags" {
    try verifyTarget();
}

test "wasip3 cabi_realloc" {
    try verifyCabiRealloc();
}

test "wasip3 stdio writes" {
    try verifyStdio(testing.io);
}

test "wasip3 args and environ" {
    const args: std.process.Args = .{ .vector = {} };
    var arg_it = try args.iterateAllocator(testing.allocator);
    defer arg_it.deinit();
    const arg0 = arg_it.next() orelse return error.MissingArgv0;
    try testing.expect(arg0.len > 0);

    var env_map = try testing.environ.createMap(testing.allocator);
    defer env_map.deinit();
    if (env_map.get("TEST_ENV_KEY")) |val| {
        try testing.expectEqualStrings("wasip3_val", val);
    }
}

test "wasip3 clocks and sleep" {
    try verifyClocks(testing.io);
}

test "wasip3 cryptographic random" {
    try verifyRandom(testing.io);
}

test "wasip3 filesystem operations" {
    try verifyFilesystem(testing.io);
}

test "wasip3 dynamic memory allocation" {
    try verifyWasmAllocator();
}
