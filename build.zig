const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const target = b.standardTargetOptions(.{});
    const build_mode = .Debug;

    if (b.args) |args| {
        std.debug.print("{s}\n", .{args});
    }

    const dynamorio_buildpath = lbl: {
        const o = b.option([]const u8, "dynamorio-build", "the path to your dynamorio build directory");
        if (o == null) {
            @panic("Need -Ddynamorio-build=/path/to/dynamorio/build. You can clone it from here: https://github.com/DynamoRIO/dynamorio");
        }
        break :lbl o.?;
    };

    const lib = b.addSharedLibrary(.{ .name = "bx", .root_source_file = .{ .path = "src/libbx.zig" }, .target = target, .optimize = build_mode });
    lib.addIncludePath("/usr/include");

    lib.addIncludePath(try std.fs.path.join(b.allocator, &.{ dynamorio_buildpath, "include" }));
    lib.addIncludePath(try std.fs.path.join(b.allocator, &.{ dynamorio_buildpath, "ext/include" }));
    lib.addLibraryPath(try std.fs.path.join(b.allocator, &.{ dynamorio_buildpath, "ext/lib64/release" }));

    lib.addCSourceFile("hacks.c", &.{""});

    lib.linkSystemLibrary("drmgr");
    lib.linkSystemLibrary("bfd");
    lib.linkLibC();
    lib.force_pic = true;
    lib.defineCMacro("LINUX", "1");
    lib.defineCMacro("X86_64", "1");
    lib.defineCMacro("_REENTRANT", "1");
    lib.install();

    const gui = b.addExecutable(.{
        .name = "bxgui",
        .root_source_file = .{ .path = "src/gui.zig" },
        .target = target,
        .optimize = build_mode,
    });
    gui.linkLibC();
    gui.defineCMacro("PLATFORM_DESKTOP", "1");
    gui.addCSourceFile("raylib/src/rglfw.c", &.{"-fno-sanitize=undefined"});
    gui.addCSourceFile("raylib/src/rcore.c", &.{"-fno-sanitize=undefined"});
    gui.addCSourceFile("raylib/src/rshapes.c", &.{"-fno-sanitize=undefined"});
    gui.addCSourceFile("raylib/src/rtextures.c", &.{"-fno-sanitize=undefined"});
    gui.addCSourceFile("raylib/src/rtext.c", &.{"-fno-sanitize=undefined"});
    gui.addCSourceFile("raylib/src/rmodels.c", &.{"-fno-sanitize=undefined"});
    gui.addCSourceFile("raylib/src/utils.c", &.{"-fno-sanitize=undefined"});
    gui.addCSourceFile("raylib/src/raudio.c", &.{"-fno-sanitize=undefined"});
    // zig does *not* like files named anything other than .c for addCSourceFile, copy the header file before adding it as a dep.
    std.fs.copyFileAbsolute(b.pathFromRoot("raygui/src/raygui.h"), b.pathFromRoot("raygui/src/raygui.c"), .{}) catch unreachable;
    gui.addCSourceFile("raygui/src/raygui.c", &.{ "-fno-sanitize=undefined", "-DRAYGUI_IMPLEMENTATION" });
    gui.addIncludePath("raylib/src");
    gui.addIncludePath("raylib/src/external/glfw/include");
    gui.addIncludePath("raygui/src");
    gui.linkSystemLibrary("pthread");
    gui.install();

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/covtool.zig" },
        .target = target,
        .optimize = build_mode,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
