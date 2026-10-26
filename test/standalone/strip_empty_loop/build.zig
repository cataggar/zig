const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Test the program");
    b.default_step = test_step;

    const optimize = std.builtin.Optimize.debug;
    const target = b.graph.host;

    const main = b.addExecutable(.{
        .name = "main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .optimize = optimize,
            .target = target,
            .strip = true,
        }),
    });

    // TODO: actually check the output
    _ = main.getEmittedBin();

    test_step.dependOn(&main.step);

    const wf = b.addWriteFiles();
    const mod_a_src = wf.add("mod_a.zig",
        \\const b = @import("b");
        \\pub export fn entry(x: u16) u16 {
        \\    return b.helper(x);
        \\}
    );
    const mod_b_src = wf.add("mod_b.zig",
        \\pub inline fn helper(x: u16) u16 {
        \\    const y: u16 = x;
        \\    return y;
        \\}
    );

    for ([_]bool{ true, false }) |root_strip| {
        const obj = b.addObject(.{
            .name = if (root_strip) "stripped_caller" else "unstripped_caller",
            .root_module = b.createModule(.{
                .root_source_file = mod_a_src,
                .optimize = optimize,
                .target = target,
                .strip = root_strip,
                .imports = &.{
                    .{
                        .name = "b",
                        .module = b.createModule(.{
                            .root_source_file = mod_b_src,
                            .optimize = optimize,
                            .target = target,
                            .strip = !root_strip,
                        }),
                    },
                },
            }),
        });
        _ = obj.getEmittedBin();
        test_step.dependOn(&obj.step);
    }
}
