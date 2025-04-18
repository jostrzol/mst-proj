const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");

const c = @import("c.zig");
usingnamespace @import("comptime-rt.zig");

const Services = @import("Services.zig");
const Server = @import("Server.zig");
const adc = @import("adc.zig");
const pwm = @import("pwm.zig");

const adc_bitwidth = c.ADC_BITWIDTH_9;
const adc_max = (1 << adc_bitwidth) - 1;

const pwm_bitwidth = c.LEDC_TIMER_13_BIT;
const pwm_max = (1 << pwm_bitwidth) - 1;

fn main() !void {
    const services = try Services.init();
    defer services.deinit();

    const server = try Server.init(&.{ .netif = services.wifi.netif });
    defer server.deinit();

    log.info("Controlling motor from Zig", .{});

    const adc_unit = try adc.Unit.init(c.ADC_UNIT_1);
    const adc_channel = try adc_unit.channel(c.ADC_CHANNEL_4, &.{
        .atten = c.ADC_ATTEN_DB_12,
        .bitwidth = adc_bitwidth,
    });

    const pwm_timer = try pwm.Timer.init(&.{
        .speed_mode = c.LEDC_LOW_SPEED_MODE,
        .duty_resolution = c.LEDC_TIMER_13_BIT,
        .timer_num = c.LEDC_TIMER_0,
        .freq_hz = 1000,
        .clk_cfg = c.LEDC_AUTO_CLK,
    });
    const pwm_channel = try pwm_timer.channel(c.LEDC_CHANNEL_0, c.GPIO_NUM_5);

    while (true) {
        const value = try adc_channel.read();

        const value_normalized = @as(f32, @floatFromInt(value)) / @as(f32, @floatFromInt(adc_max));
        log.info(
            "selected duty cycle: {d:.2} = {} / {}",
            .{ value_normalized, value, adc_max },
        );

        const duty_cycle: u32 = @intFromFloat(value_normalized * pwm_max);
        try pwm_channel.set_duty_cycle(duty_cycle);

        idf.vTaskDelay(100);
    }
}

export fn app_main() callconv(.C) void {
    main() catch |err| std.debug.panic("Failed to call main: {}", .{err});
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
