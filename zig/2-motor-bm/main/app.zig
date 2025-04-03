const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");

const c = @cImport({
    @cInclude("esp_adc/adc_oneshot.h");
});

pub const unit_t = enum(c_int) {
    ADC_UNIT_1 = c.ADC_UNIT_1,
    ADC_UNIT_2 = c.ADC_UNIT_2,
};

pub const oneshot_unit_init_cfg_t = c.adc_oneshot_unit_init_cfg_t;

pub const Unit = struct {
    handle: c.adc_oneshot_unit_handle_t,

    pub fn init(config: *const c.adc_oneshot_unit_init_cfg_t) !Unit {
        var handle: c.adc_oneshot_unit_handle_t = undefined;
        const err = c.adc_oneshot_new_unit(config, &handle);
        try idf.espCheckError(@enumFromInt(err));
        return .{ .handle = handle };
    }
};

const tag = "motor";
const period_ms = 1000;
const sleep_duration_ms = period_ms / 2;

fn main() !void {
    log.info("Controlling motor from Zig", .{});

    var is_on = false;

    try idf.gpio.Direction.set(.GPIO_NUM_5, .GPIO_MODE_OUTPUT);

    // const adc_unit = try idf.adc.Unit.init(&.{ .unit_id = @intFromEnum(unit_t.ADC_UNIT_1) });
    // _ = adc_unit;
    const adc_unit = try Unit.init(&.{ .unit_id = @intFromEnum(unit_t.ADC_UNIT_1) });
    _ = adc_unit;

    while (true) {
        log.info("Turning the LED {s}", .{if (is_on) "ON" else "OFF"});

        try idf.gpio.Level.set(.GPIO_NUM_5, @intFromBool(is_on));
        is_on = !is_on;
        idf.vTaskDelay(sleep_duration_ms / idf.portTICK_PERIOD_MS);
    }
}

export fn app_main() callconv(.C) void {
    main() catch |err| std.debug.panic("Error calling main: {}", .{err});
}

// override the std panic function with idf.panic
pub const panic = idf.panic;
const log = std.log.scoped(.@"esp-idf");
pub const std_options: std.Options = .{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },
    // Define logFn to override the std implementation
    .logFn = idf.espLogFn,
};
