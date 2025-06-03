const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("pdfrw_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_objects_mod = b.createModule(.{
        .root_source_file = b.path("src/objects/test_mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_objects_mod.addImport("pdfrw_zig", lib_mod);
    const lib = b.addStaticLibrary(.{
        .name = "pdfrw_zig",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .name = "root",
        .root_module = lib_mod,
    });
    const object_tests = b.addTest(.{
        .name = "objects",
        .root_module = test_objects_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const run_main_tests = b.addRunArtifact(object_tests);

    const lib_step = b.step("test:root", "Run root tests");
    lib_step.dependOn(&run_lib_unit_tests.step);
    const object_step = b.step("test:objects", "Run objects tests");
    object_step.dependOn(&run_main_tests.step);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(lib_step);
    test_step.dependOn(object_step);
}
