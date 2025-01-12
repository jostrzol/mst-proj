const std = @import("std");

const rpiTargetQuery = std.Target.Query{
    .cpu_arch = .arm,
    .cpu_model = .{ .explicit = &std.Target.arm.cpu.arm1176jzf_s },
    .os_tag = .linux,
    .abi = .gnueabihf,
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const isRpi = b.option(bool, "rpi", "Target Raspberry Pi Zero") orelse false;
    const target = if (isRpi) b.resolveTargetQuery(rpiTargetQuery) else b.host;

    const gpio = b.dependency("gpio", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "2-motor-controller-zig",
        .root_source_file = b.path("./main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("gpio", gpio.module("gpio"));
    exe.linkLibC();

    b.installArtifact(exe);
}
