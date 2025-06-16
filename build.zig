const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create internal modules (not exposed to library users)
    const rc4_mod = b.createModule(.{ .root_source_file = b.path("src/rc4.zig"), .target = target, .optimize = optimize });
    const objects_mod = b.createModule(.{
        .root_source_file = b.path("src/objects/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    const crypt_mod = b.createModule(.{ .root_source_file = b.path("src/crypt.zig"), .target = target, .optimize = optimize, .imports = &.{
        .{ .name = "rc4", .module = rc4_mod },
        .{ .name = "object", .module = objects_mod },
    } });

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

    const test_crypt_mod = b.createModule(.{ .root_source_file = b.path("src/tests/test_crypt.zig"), .target = target, .optimize = optimize, .imports = &.{
        .{ .name = "crypt", .module = crypt_mod },
        .{ .name = "rc4", .module = rc4_mod },
        .{ .name = "object", .module = objects_mod },
    } });

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

    const crypt_tests = b.addTest(.{
        .name = "crypt",
        .root_module = test_crypt_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const run_main_tests = b.addRunArtifact(object_tests);
    const run_crypt_tests = b.addRunArtifact(crypt_tests);

    const lib_step = b.step("test:root", "Run root tests");
    lib_step.dependOn(&run_lib_unit_tests.step);
    const object_step = b.step("test:objects", "Run objects tests");
    object_step.dependOn(&run_main_tests.step);
    const crypt_step = b.step("test:crypt", "Run crypt test");
    crypt_step.dependOn(&run_crypt_tests.step);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(lib_step);
    test_step.dependOn(object_step);
    test_step.dependOn(crypt_step);
}
