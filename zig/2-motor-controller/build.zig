const std = @import("std");

const rpiTargetQuery = std.Target.Query{
    .cpu_arch = .arm,
    .cpu_model = .{ .explicit = &std.Target.arm.cpu.arm1176jzf_s },
    .os_tag = .linux,
    .abi = .gnueabihf,
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const zig_pwm = b.dependency("zig-pwm", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "2-motor-controller-zig",
        .root_source_file = b.path("./main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("pwm", zig_pwm.module("pwm"));
    exe.linkLibC();

    b.installArtifact(exe);

    const check_step = b.step("check", "Check the application");
    check_step.dependOn(&exe.step);
}
