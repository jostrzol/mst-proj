const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

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
    const i2c_tools = b.dependency("i2c-tools", .{ .target = target, .optimize = optimize });

    const i2c_build_dir = makeCachedTempDir(b, "i2c-tools", "build") catch unreachable;
    const copy_sources = b.addSystemCommand(&[_][]const u8{
        "cp", "-r", i2c_tools.path("").getPath(b), i2c_build_dir.path(b, "").getPath(b),
    });

    const target_str = formatTarget(b.allocator, &target) catch unreachable;
    defer b.allocator.free(target_str);
    const cc = std.fmt.allocPrint(b.allocator, "zig cc --target={s}", .{target_str}) catch unreachable;
    defer b.allocator.free(cc);

    const i2c_tools_build = b.addSystemCommand(
        &[_][]const u8{ "make", "-C", i2c_build_dir.path(b, "").getPath(b) },
    );
    i2c_tools_build.setEnvironmentVariable("CC", cc);
    i2c_tools_build.step.dependOn(&copy_sources.step);

    const exe = b.addExecutable(.{
        .name = "2-motor-controller-zig",
        .root_source_file = b.path("./main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("pwm", zig_pwm.module("pwm"));
    exe.linkLibC();
    // exe.addIncludePath(i2c_tools.path("./include/"));
    // exe.addIncludePath(b.path("./i2c-tools/include/"));
    // exe.addLibraryPath(b.path("./i2c-tools/lib/"));
    // exe.linkSystemLibrary("i2c");

    // exe.linkLibrary(i2c_tools_lib);
    exe.addIncludePath(i2c_build_dir.path(b, "include"));
    exe.addLibraryPath(i2c_build_dir.path(b, "lib"));
    exe.linkSystemLibrary("i2c");
    exe.step.dependOn(&i2c_tools_build.step);

    b.installArtifact(exe);

    const check_step = b.step("check", "Check the application");
    check_step.dependOn(&exe.step);
}

fn makeCachedTempDir(b: *std.Build, dependency: []const u8, dir_key: []const u8) !std.Build.LazyPath {
    const pkg_hash = findPkgHashOrFatal(b, dependency);

    const full_key = try std.mem.concat(b.allocator, u8, &[_][]const u8{ pkg_hash, dir_key });
    defer b.allocator.free(full_key);

    var full_hash: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(full_key, &full_hash, .{});

    const full_hash_hex = std.Build.hex64(@bitCast(full_hash[0..8].*));

    const result = try b.cache_root.join(b.allocator, &[_][]const u8{ "tmp", &full_hash_hex });
    return std.Build.LazyPath{ .cwd_relative = result };
}

// Copied from Build.zig
fn findPkgHashOrFatal(b: *std.Build, name: []const u8) []const u8 {
    for (b.available_deps) |dep| {
        if (std.mem.eql(u8, dep[0], name)) return dep[1];
    }

    const full_path = b.pathFromRoot("build.zig.zon");
    std.debug.panic("no dependency named '{s}' in '{s}'. All packages used in build.zig must be declared in this file", .{ name, full_path });
}

fn formatTarget(
    allocator: std.mem.Allocator,
    target: *const std.Build.ResolvedTarget,
) std.fmt.AllocPrintError![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}-{s}-{s}", .{
        target.result.osArchName(),
        @tagName(target.result.os.tag),
        @tagName(target.result.abi),
    });
}
