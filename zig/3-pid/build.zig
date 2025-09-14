const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const log_level = b.option(std.log.Level, "log-level", "Log level");

    const revolution_threshold_close = try getEnvF32(b, "REVOLUTION_THRESHOLD_CLOSE", 0.2);
    const revolution_threshold_far = try getEnvF32(b, "REVOLUTION_THRESHOLD_FAR", 0.36);

    const zig_pwm = b.dependency("zig-pwm", .{ .target = target, .optimize = optimize });

    const i2c_tools = try makeI2cTools(b, .{ .target = target, .optimize = optimize });
    const modbus = try makeModbus(b, .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "3-pid-zig",
        .root_source_file = b.path("./main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.linkLibrary(i2c_tools);
    exe.step.dependOn(modbus.step);
    exe.addIncludePath(modbus.includedir);
    exe.addLibraryPath(modbus.libdir);
    exe.linkSystemLibrary(modbus.libname);
    exe.root_module.addImport("pwm", zig_pwm.module("pwm"));

    const config = b.addOptions();
    const log_level_coerced = if (log_level) |lvl| lvl else switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe, .ReleaseFast, .ReleaseSmall => .info,
    };
    const log_level_name = std.enums.tagName(std.log.Level, log_level_coerced) orelse unreachable;
    config.addOption([]const u8, "log_level", log_level_name);
    config.addOption(f32, "revolution_threshold_close", revolution_threshold_close);
    config.addOption(f32, "revolution_threshold_far", revolution_threshold_far);
    exe.root_module.addOptions("config", config);

    b.installArtifact(exe);

    const check_step = b.step("check", "Check the application");
    check_step.dependOn(&exe.step);
}

fn getEnvF32(b: *std.Build, name: []const u8, default: f32) !f32 {
    const str = std.process.getEnvVarOwned(
        b.allocator,
        name,
    ) catch return default;
    return std.fmt.parseFloat(f32, str) catch {
        std.log.err("{s} must be float, got '{s}'", .{ name, str });
        b.invalid_user_input = true;
        return error.EnvVarNotFloat;
    };
}

const MakeOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode = .Debug,
};

fn makeI2cTools(b: *std.Build, options: MakeOptions) !*std.Build.Step.Compile {
    const src = b.dependency("i2c-tools", .{});

    const lib = b.addSharedLibrary(.{
        .name = "i2c",
        .version = .{ .major = 0, .minor = 1, .patch = 1 },
        .pic = true,
        .target = options.target,
        .optimize = options.optimize,
    });
    lib.bundle_compiler_rt = false;
    lib.addIncludePath(src.path("include"));
    lib.installHeadersDirectory(src.path("include"), "", .{});
    lib.addCSourceFile(.{ .file = src.path("lib/smbus.c") });
    lib.linkLibC();

    return lib;
}

fn makeModbus(b: *std.Build, options: MakeOptions) !struct {
    step: *std.Build.Step,
    includedir: std.Build.LazyPath,
    libname: []const u8,
    libdir: std.Build.LazyPath,
} {
    const src = b.dependency("modbus", .{}).path("");

    const write = b.addWriteFiles();
    _ = write.addCopyDirectory(src, "", .{});
    const writeDir = write.getDirectory();

    const autoreconf = b.addSystemCommand(&[_][]const u8{"./autogen.sh"});
    autoreconf.stdio = .{ .check = .{} };
    autoreconf.addFileInput(writeDir.path(b, "configure.ac"));
    autoreconf.addFileInput(writeDir.path(b, "autogen.sh"));
    autoreconf.setCwd(writeDir);
    autoreconf.step.dependOn(&write.step);

    const configure = b.addSystemCommand(&[_][]const u8{"./configure"});
    configure.stdio = .{ .check = .{} };
    configure.addFileInput(writeDir.path(b, "configure"));
    const triple = try options.target.query.zigTriple(b.allocator);
    defer b.allocator.free(triple);
    const hostArg = try std.fmt.allocPrint(b.allocator, "--host={s}", .{triple});
    defer b.allocator.free(hostArg);
    configure.addArg(hostArg);
    configure.addPrefixedDirectoryArg("--prefix=", writeDir.path(b, "build"));
    const cc = try std.fmt.allocPrint(b.allocator, "zig cc -target {s}", .{triple});
    configure.setEnvironmentVariable("CC", cc);
    const cpp = try std.fmt.allocPrint(b.allocator, "zig c++ -target {s}", .{triple});
    configure.setEnvironmentVariable("CXX", cpp);
    configure.setCwd(writeDir);
    configure.step.dependOn(&autoreconf.step);

    const make = b.addSystemCommand(&[_][]const u8{ "make", "install" });
    make.setCwd(writeDir);
    make.step.dependOn(&configure.step);

    return .{
        .step = &make.step,
        .includedir = writeDir.path(b, "build/include/modbus"),
        .libname = "modbus",
        .libdir = writeDir.path(b, "build/lib"),
    };
}
