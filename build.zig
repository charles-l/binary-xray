const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const target = b.standardTargetOptions(.{});
    const build_mode = .Debug;

    const lib = b.addSharedLibrary(.{ .name = "cov", .root_source_file = .{ .path = "src/covtool.zig" }, .target = target, .optimize = build_mode });
    lib.addCSourceFile("hacks.c", &.{""});
    lib.addIncludePath("/usr/include");
    lib.addIncludePath("/home/nc/src/dynamorio/build/include");
    lib.addIncludePath("/home/nc/src/dynamorio/build/ext/include/");
    lib.addLibraryPath("/home/nc/src/dynamorio/build/ext/lib64/release/");
    lib.linkSystemLibrary("drmgr");
    lib.linkSystemLibrary("bfd");
    lib.linkLibC();
    lib.force_pic = true;
    lib.defineCMacro("LINUX", "1");
    lib.defineCMacro("X86_64", "1");
    lib.defineCMacro("_REENTRANT", "1");
    lib.install();

    const frontend = b.addExecutable(.{
        .name = "guicov",
        .root_source_file = .{ .path = "src/frontend.zig" },
        .target = target,
        .optimize = build_mode,
    });
    frontend.linkLibC();
    frontend.defineCMacro("PLATFORM_DESKTOP", "1");
    frontend.addCSourceFile("raylib/src/rglfw.c", &.{"-fno-sanitize=undefined"});
    frontend.addCSourceFile("raylib/src/rcore.c", &.{"-fno-sanitize=undefined"});
    frontend.addCSourceFile("raylib/src/rshapes.c", &.{"-fno-sanitize=undefined"});
    frontend.addCSourceFile("raylib/src/rtextures.c", &.{"-fno-sanitize=undefined"});
    frontend.addCSourceFile("raylib/src/rtext.c", &.{"-fno-sanitize=undefined"});
    frontend.addCSourceFile("raylib/src/rmodels.c", &.{"-fno-sanitize=undefined"});
    frontend.addCSourceFile("raylib/src/utils.c", &.{"-fno-sanitize=undefined"});
    frontend.addCSourceFile("raylib/src/raudio.c", &.{"-fno-sanitize=undefined"});
    // zig does *not* like files named anything other than .c for addCSourceFile, copy the header file before adding it as a dep.
    std.fs.copyFileAbsolute(b.pathFromRoot("raygui/src/raygui.h"), b.pathFromRoot("raygui/src/raygui.c"), .{}) catch unreachable;
    frontend.addCSourceFile("raygui/src/raygui.c", &.{ "-fno-sanitize=undefined", "-DRAYGUI_IMPLEMENTATION" });
    frontend.addIncludePath("raylib/src");
    frontend.addIncludePath("raylib/src/external/glfw/include");
    frontend.addIncludePath("raygui/src");
    frontend.linkSystemLibrary("pthread");
    frontend.install();

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/covtool.zig" },
        .target = target,
        .optimize = build_mode,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
