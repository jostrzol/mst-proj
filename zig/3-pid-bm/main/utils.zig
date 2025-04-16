const std = @import("std");

pub fn logErr(err: anyerror) void {
    std.log.err("Error: {}", .{err});
}
