const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;

const c = @cImport({
    @cInclude("esp_adc/adc_oneshot.h");
    @cInclude("driver/ledc.h");

    @cInclude("esp_clk_tree.h");
    @cInclude("soc/clk_tree_defs.h");
});

pub usingnamespace c;

pub fn espCheckError(err: c.esp_err_t) idf.esp_error!void {
    return idf.espCheckError(@enumFromInt(err));
}

pub fn espLogError(errc: c.esp_err_t, operation: []const u8) void {
    espCheckError(errc) catch |err| {
        std.log.err("{s} fail: {}", .{ operation, err });
    };
}

pub fn rtosCheckError(result: sys.BaseType_t) !void {
    if (result != 1) return error.ErrorRtos;
}

// Needed, because c-translate cannot properly translate flags
pub const fixed = struct {
    pub const ledc_channel_config_t = extern struct {
        gpio_num: c_int = @import("std").mem.zeroes(c_int),
        speed_mode: c.ledc_mode_t = @import("std").mem.zeroes(c.ledc_mode_t),
        channel: c.ledc_channel_t = @import("std").mem.zeroes(c.ledc_channel_t),
        intr_type: c.ledc_intr_type_t = @import("std").mem.zeroes(c.ledc_intr_type_t),
        timer_sel: c.ledc_timer_t = @import("std").mem.zeroes(c.ledc_timer_t),
        duty: u32 = @import("std").mem.zeroes(u32),
        hpoint: c_int = @import("std").mem.zeroes(c_int),
        sleep_mode: c.ledc_sleep_mode_t = @import("std").mem.zeroes(c.ledc_sleep_mode_t),
        flags: packed struct(u32) {
            output_invert: bool = false,
            _: u31 = 0,
        } = .{},
    };

    pub extern fn ledc_channel_config(ledc_conf: ?*const ledc_channel_config_t) c.esp_err_t;
};
