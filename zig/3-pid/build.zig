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

    const configure = b.addSystemCommand(&[_][]const u8{"./configure"});
    const triple = try target.query.zigTriple(alloc);
    const hostArg = try std.fmt.allocPrint(alloc, "--host={s}", .{triple});
    configure.addArg(hostArg);
    const prefix = modbus.path(b, "build/").getPath(b);
    const prefixArg = try std.fmt.allocPrint(alloc, "--prefix={s}", .{prefix});
    configure.addArg(prefixArg);
    configure.setCwd(modbus.path(b, ""));

    const make = b.addSystemCommand(&[_][]const u8{ "make", "install" });
    make.setCwd(modbus.path(b, ""));
    make.step.dependOn(&configure.step);

    // const modbus_lib = b.addSharedLibrary(.{
    //     .name = "modbus",
    //     .version = .{ .major = 3, .minor = 1, .patch = 11 },
    //     .pic = true,
    //     .target = target,
    //     .optimize = optimize,
    // });
    // modbus_lib.bundle_compiler_rt = false;
    // modbus_lib.addIncludePath(modbus.path(b, "src"));
    // modbus_lib.addSystemIncludePath(modbus.path(b, ""));
    // modbus_lib.installHeadersDirectory(modbus.path(b, "src"), "", .{});
    // modbus_lib.addCSourceFiles(.{
    //     .root = modbus.path(b, "src"),
    //     .files = &[_][]const u8{
    //         "modbus.c",
    //         "modbus-tcp.c",
    //         "modbus-rtu.c",
    //         "modbus-data.c",
    //     },
    // });
    // modbus_lib.linkLibC();
    // modbus_lib.defineCMacro("_GNU_SOURCE", "1");
    // modbus_lib.step.dependOn(&configure.step);

    const exe = b.addExecutable(.{
        .name = "3-pid-zig",
        .root_source_file = b.path("./main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.linkLibrary(i2c_tools_lib);
    // exe.linkLibrary(modbus_lib);
    exe.step.dependOn(&make.step);
    exe.addIncludePath(modbus.path(b, "build/include"));
    exe.addLibraryPath(modbus.path(b, "build/lib/libmodbus.so.5.1.0"));
    exe.root_module.addImport("pwm", zig_pwm.module("pwm"));

    b.installArtifact(exe);

    const check_step = b.step("check", "Check the application");
    check_step.dependOn(&exe.step);
}
