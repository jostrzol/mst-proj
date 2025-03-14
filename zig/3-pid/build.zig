const std = @import("std");

pub fn build(b: *std.Build) !void {
    var arena = std.heap.ArenaAllocator.init(b.allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const zig_pwm = b.dependency("zig-pwm", .{ .target = target, .optimize = optimize });
    const i2c_tools = b.dependency("i2c-tools", .{ .target = target, .optimize = optimize });
    const modbus = b.dependency("modbus", .{ .target = target, .optimize = optimize })
        .path("libmodbus-3.1.11");

    const i2c_tools_lib = b.addSharedLibrary(.{
        .name = "i2c",
        .version = .{ .major = 0, .minor = 1, .patch = 1 },
        .pic = true,
        .target = target,
        .optimize = optimize,
    });
    i2c_tools_lib.bundle_compiler_rt = false;
    i2c_tools_lib.addIncludePath(i2c_tools.path("include"));
    i2c_tools_lib.installHeadersDirectory(i2c_tools.path("include"), "", .{});
    i2c_tools_lib.addCSourceFile(.{ .file = i2c_tools.path("lib/smbus.c") });
    i2c_tools_lib.linkLibC();

    const write = b.addWriteFiles();
    _ = write.addCopyDirectory(modbus, "", .{});

    const configure = b.addSystemCommand(&[_][]const u8{"./configure"});
    configure.stdio = .{ .check = .{} };
    configure.addFileInput(write.getDirectory().path(b, "src/modbus-version.h"));
    const triple = try target.query.zigTriple(alloc);
    const hostArg = try std.fmt.allocPrint(alloc, "--host={s}", .{triple});
    configure.addArg(hostArg);
    configure.addPrefixedDirectoryArg("--prefix=", write.getDirectory().path(b, "build"));
    configure.setCwd(write.getDirectory());
    configure.step.dependOn(&write.step);

    const make = b.addSystemCommand(&[_][]const u8{ "make", "install" });
    make.setCwd(write.getDirectory());
    make.step.dependOn(&configure.step);

    const exe = b.addExecutable(.{
        .name = "3-pid-zig",
        .root_source_file = b.path("./main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.linkLibrary(i2c_tools_lib);
    exe.step.dependOn(&make.step);
    exe.addIncludePath(write.getDirectory().path(b, "build/include"));
    exe.addLibraryPath(write.getDirectory().path(b, "build/lib/libmodbus.so"));
    exe.root_module.addImport("pwm", zig_pwm.module("pwm"));

    b.installArtifact(exe);

    const check_step = b.step("check", "Check the application");
    check_step.dependOn(&exe.step);
}
