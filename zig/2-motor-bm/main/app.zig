const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");
const sys = idf.sys;

const c = @import("c.zig");
usingnamespace @import("comptime-rt.zig");

const adc = @import("adc.zig");
const pwm = @import("pwm.zig");
const memory = @import("memory.zig");
const perf = @import("perf.zig");

const adc_bitwidth = c.ADC_BITWIDTH_9;
const adc_max = (1 << adc_bitwidth) - 1;

const pwm_bitwidth = c.LEDC_TIMER_13_BIT;
const pwm_max = (1 << pwm_bitwidth) - 1;

const update_frequency = 10;
const sleep_time_ms = std.time.ms_per_s / update_frequency;

fn main() !void {
    log.info("Controlling motor from Zig", .{});

    const allocator = std.heap.raw_c_allocator;

    const adc_unit = try adc.Unit.init(c.ADC_UNIT_1);
    defer adc_unit.deinit();
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
    defer pwm_timer.deinit();
    const pwm_channel = try pwm_timer.channel(c.LEDC_CHANNEL_0, c.GPIO_NUM_5);
    defer pwm_channel.deinit();

    var perf_main = try perf.Counter.init(allocator, "MAIN", update_frequency * 2);
    defer perf_main.deinit();

    var report_number: u64 = 0;
    while (true) {
        for (0..update_frequency) |_| {
            idf.vTaskDelay(sleep_time_ms / idf.portTICK_PERIOD_MS);

            const start = perf.Marker.now();

            const value = try adc_channel.read();

            const value_normalized = @as(f32, @floatFromInt(value)) / @as(f32, @floatFromInt(adc_max));
            log.debug(
                "selected duty cycle: {d:.2} = {} / {}",
                .{ value_normalized, value, adc_max },
            );

            const duty_cycle: u32 = @intFromFloat(value_normalized * pwm_max);
            try pwm_channel.set_duty_cycle(duty_cycle);

            perf_main.add_sample(start);
        }

        std.log.info("# REPORT {}", .{report_number});
        memory.report();
        perf_main.report();
        perf_main.reset();
        report_number += 1;
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
