const std = @import("std");

pub fn logErr(result: anyerror!void) void {
    result catch |err| std.log.err("Error: {}", .{err});
}
