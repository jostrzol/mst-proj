const std = @import("std");
const idf = @import("esp_idf");

const c = @cImport({
    @cInclude("esp_adc/adc_oneshot.h");
    @cInclude("driver/ledc.h");
    @cInclude("mdns.h");
});

pub usingnamespace c;

pub fn espCheckError(err: c.esp_err_t) idf.esp_error!void {
    try idf.espCheckError(@enumFromInt(err));
}

pub fn espLogError(errc: c.esp_err_t) void {
    espCheckError(errc) catch |err| {
        std.log.err("Error: {}", .{err});
    };
}
