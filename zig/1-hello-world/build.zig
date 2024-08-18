const std = @import("std");

const rpiTargetQuery = std.Target.Query{
    .cpu_arch = .arm,
    .cpu_model = .{ .explicit = &std.Target.arm.cpu.arm1176jzf_s },
    .os_tag = .linux,
    .abi = .gnueabihf,
};

pub fn build(b: *std.Build) void {
    const isRpi = b.option(bool, "rpi", "Target Raspberry Pi Zero") orelse false;

    const target = if (isRpi) b.resolveTargetQuery(rpiTargetQuery) else b.host;

    const exe = b.addExecutable(.{
        .name = "1-hello-world-zig",
        .root_source_file = b.path("./main.zig"),
        .target = target,
    });

    b.installArtifact(exe);
}
