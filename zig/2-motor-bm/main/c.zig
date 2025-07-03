const std = @import("std");
const idf = @import("esp_idf");

const c = @cImport({
    @cInclude("esp_adc/adc_oneshot.h");
    @cInclude("driver/ledc.h");

    @cInclude("esp_clk_tree.h");
    @cInclude("soc/clk_tree_defs.h");
});

pub usingnamespace c;

pub fn espCheckError(err: c.esp_err_t) idf.esp_error!void {
    try idf.espCheckError(@enumFromInt(err));
}

pub fn espLogError(errc: c.esp_err_t, operation: []const u8) void {
    espCheckError(errc) catch |err| {
        std.log.err("{s} fail: {}", .{ operation, err });
    };
}
