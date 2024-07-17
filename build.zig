const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // add your library, which gets built as a shared library
    const lib = b.addSharedLibrary(.{
        .name = "zigpy",
        .root_source_file = b.path("src/example_lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // run bind_gen.zig to generate the python bindings
    const bind_gen = b.addExecutable(.{
        .name = "bind_gen",
        .root_source_file = b.path("src/bind_gen.zig"),
        .target = b.host,
    });
    const bind_gen_step = b.addRunArtifact(bind_gen);
    b.getInstallStep().dependOn(&bind_gen_step.step);
}
