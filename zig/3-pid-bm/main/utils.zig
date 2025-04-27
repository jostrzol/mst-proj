const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;

pub fn logErr(result: anyerror!void) void {
    result catch |err| std.log.err("Error: {}", .{err});
}

pub fn panicErr(err: anyerror) noreturn {
    std.debug.panic("Fatal error: {}", .{err});
}

pub fn rtosCheckError(result: sys.BaseType_t) !void {
    if (result != 1) return error.ErrorRtos;
}
