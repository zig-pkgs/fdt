const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const fdt_dep = b.dependency("fdt", .{});

    const translate_c = b.addTranslateC(.{
        .root_source_file = fdt_dep.path("libfdt/libfdt.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(fdt_dep.path("libfdt"));

    const lib_mod = b.addModule("fdt", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.addImport("c", translate_c.createModule());
    lib_mod.addIncludePath(fdt_dep.path("libfdt"));

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "fdt",
        .root_module = lib_mod,
    });
    lib.addCSourceFiles(.{
        .root = fdt_dep.path("libfdt"),
        .files = &fdt_src,
        .flags = &.{},
    });
    lib.installHeadersDirectory(
        fdt_dep.path("libfdt"),
        "",
        .{
            .include_extensions = &.{".h"},
            .exclude_extensions = &.{"internal.h"},
        },
    );
    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

const fdt_src = [_][]const u8{
    "fdt.c",
    "fdt_ro.c",
    "fdt_wip.c",
    "fdt_sw.c",
    "fdt_rw.c",
    "fdt_strerror.c",
    "fdt_empty_tree.c",
    "fdt_addresses.c",
    "fdt_overlay.c",
    "fdt_check.c",
};
