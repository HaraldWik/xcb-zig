const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "xcb_zig_generator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    const run = b.addRunArtifact(exe);

    run.addFileArg(b.path("protocol/core.zon"));

    run.addArg("-o");
    const output = run.addOutputFileArg("xcb.zig");

    b.getInstallStep().dependOn(&run.step);

    _ = b.addModule("xcb", .{
        .root_source_file = output,
        .target = target,
        .optimize = optimize,
    });

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
