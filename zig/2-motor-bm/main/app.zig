const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");

const c = @import("c.zig").c;
const adc = @import("adc.zig");
usingnamespace @import("comptime-rt.zig");

fn main() !void {
    log.info("Controlling motor from Zig", .{});

    try idf.gpio.Direction.set(.GPIO_NUM_5, .GPIO_MODE_OUTPUT);

    const adc_unit = try adc.Unit.init(c.ADC_UNIT_1);
    const adc_channel = try adc_unit.channel(c.ADC_CHANNEL_4, &.{
        .atten = c.ADC_ATTEN_DB_12,
        .bitwidth = c.ADC_BITWIDTH_9,
    });

    while (true) {
        const value = try adc_channel.read();

        const value_normalized = @as(f32, @floatFromInt(value)) / @as(f32, @floatFromInt((1 << 9) - 1));
        log.info("selected duty cycle: {d:.2} = {} / {}", .{
            value_normalized,
            value,
            ((1 << 9) - 1),
        });

        idf.vTaskDelay(1);
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
