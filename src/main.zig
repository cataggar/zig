const std = @import("std");
const p3 = std.os.wasi.p3;

pub fn main() u8 {
    const msg = "Life is not a malfunction.\n";
    const pair = p3.stream_u8.new();
    const rx: i32 = @bitCast(@as(u32, @truncate(pair)));
    const tx: i32 = @bitCast(@as(u32, @truncate(pair >> 32)));

    const fut = p3.stdout_mod.@"write-via-stream"(rx);
    if (@as(u32, @truncate(p3.stream_u8.write(tx, msg.ptr, msg.len))) == p3.BLOCKED) {
        waitReady(tx);
    }
    p3.stream_u8.@"drop-writable"(tx);

    var fut_ret: [2]u8 align(4) = @splat(0);
    if (p3.future_stdout.read(fut, &fut_ret) == p3.BLOCKED) {
        waitReady(fut);
    }
    p3.future_stdout.@"drop-readable"(fut);
    return 0;
}

fn waitReady(handle: i32) void {
    const ws = p3.waitable_set.new();
    defer p3.waitable_set.drop(ws);
    p3.waitable.join(handle, ws);
    var payload: [2]i32 = .{ 0, 0 };
    _ = p3.waitable_set.wait(ws, &payload);
    p3.waitable.join(handle, 0);
}
