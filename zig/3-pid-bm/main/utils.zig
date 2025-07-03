const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;

pub fn logErr(result: anyerror!void, operation: []const u8) void {
    result catch |err| std.log.err("{s} fail: {}", .{operation, err});
}

pub fn panicErr(err: anyerror) noreturn {
    std.debug.panic("Fatal error: {}", .{err});
}

pub fn rtosCheckError(result: sys.BaseType_t) !void {
    if (result != 1) return error.ErrorRtos;
}
