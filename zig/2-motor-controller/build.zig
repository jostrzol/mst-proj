const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const zig_pwm = b.dependency("zig-pwm", .{ .target = target, .optimize = optimize });
    const i2c_tools = b.dependency("i2c-tools", .{ .target = target, .optimize = optimize });

    const i2c_tools_lib = b.addSharedLibrary(.{
        .name = "i2c",
        .version = .{ .major = 0, .minor = 1, .patch = 1 },
        .pic = true,
        .target = target,
        .optimize = optimize,
    });
    i2c_tools_lib.bundle_compiler_rt = false;
    i2c_tools_lib.addIncludePath(i2c_tools.path("include"));
    i2c_tools_lib.addCSourceFile(.{ .file = i2c_tools.path("lib/smbus.c") });
    i2c_tools_lib.linkLibC();
    b.installArtifact(i2c_tools_lib);

    const exe = b.addExecutable(.{
        .name = "2-motor-controller-zig",
        .root_source_file = b.path("./main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("pwm", zig_pwm.module("pwm"));
    exe.linkLibC();
    exe.addIncludePath(i2c_tools.path("include"));
    exe.linkLibrary(i2c_tools_lib);

    b.installArtifact(exe);

    const check_step = b.step("check", "Check the application");
    check_step.dependOn(&exe.step);
}
