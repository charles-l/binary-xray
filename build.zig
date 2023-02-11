const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addSharedLibrary("cov", "src/main.zig", .unversioned);
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
    lib.setBuildMode(mode);
    lib.install();

    const main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
