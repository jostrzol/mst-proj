const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const log_level = b.option(std.log.Level, "log-level", "Log level");

    const gpio = b.dependency("gpio", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "1-blinky-zig",
        .root_source_file = b.path("./main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("gpio", gpio.module("gpio"));
    exe.linkLibC();

    const config = b.addOptions();
    const log_level_coerced = if (log_level) |lvl| lvl else switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe, .ReleaseFast, .ReleaseSmall => .info,
    };
    const log_level_name = std.enums.tagName(std.log.Level, log_level_coerced) orelse unreachable;
    config.addOption([]const u8, "log_level", log_level_name);
    exe.root_module.addOptions("config", config);

    b.installArtifact(exe);

    const check_step = b.step("check", "Check the application");
    check_step.dependOn(&exe.step);
}
