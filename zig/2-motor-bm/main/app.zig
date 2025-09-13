const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");
const sys = idf.sys;

const c = @import("c.zig");
usingnamespace @import("compiler-rt.zig");

const memory = @import("memory.zig");
const perf = @import("perf.zig");

const adc_unit = c.ADC_UNIT_1;
const adc_channel = c.ADC_CHANNEL_4;
const adc_bitwidth = c.ADC_BITWIDTH_9;
const adc_max = (1 << adc_bitwidth) - 1;
const adc_channel_config = c.adc_oneshot_chan_cfg_t{
    .atten = c.ADC_ATTEN_DB_12,
    .bitwidth = adc_bitwidth,
};

const pwm_timer = c.LEDC_TIMER_0;
const pwm_speed_mode = c.LEDC_LOW_SPEED_MODE;
const pwm_channel = c.LEDC_CHANNEL_0;
const pwm_bitwidth = c.LEDC_TIMER_13_BIT;
const pwm_max = (1 << pwm_bitwidth) - 1;
const pwm_timer_config = c.ledc_timer_config_t{
    .timer_num = pwm_timer,
    .speed_mode = pwm_speed_mode,
    .duty_resolution = pwm_bitwidth,
    .freq_hz = 1000,
    .clk_cfg = c.LEDC_AUTO_CLK,
};
const pwm_timer_deconfig = c.ledc_timer_config_t{
    .timer_num = pwm_timer,
    .deconfigure = true,
};
const pwm_channel_config = c.fixed.ledc_channel_config_t{
    .timer_sel = pwm_timer,
    .channel = pwm_channel,
    .speed_mode = pwm_speed_mode,
    .intr_type = c.LEDC_INTR_DISABLE,
    .gpio_num = c.GPIO_NUM_18,
    .duty = 0,
    .hpoint = 0,
};

const update_frequency = 10;
const sleep_time_ms = std.time.ms_per_s / update_frequency;

fn main() !void {
    log.info("Controlling motor from Zig", .{});

    const allocator = std.heap.raw_c_allocator;

    var adc: c.adc_oneshot_unit_handle_t = undefined;
    try c.espCheckError(c.adc_oneshot_new_unit(&.{ .unit_id = adc_unit }, &adc));
    defer c.espLogError(c.adc_oneshot_del_unit(adc), "adc_oneshot_del_unit");

    try c.espCheckError(c.adc_oneshot_config_channel(adc, adc_channel, &adc_channel_config));

    try c.espCheckError(c.ledc_timer_config(&pwm_timer_config));
    defer c.espLogError(c.ledc_timer_config(&pwm_timer_deconfig), "ledc_timer_config");

    try c.espCheckError(c.fixed.ledc_channel_config(&pwm_channel_config));
    defer c.espLogError(c.ledc_stop(pwm_speed_mode, pwm_channel, 0), "ledc_stop");

    var perf_main = try perf.Counter.init(allocator, "MAIN", update_frequency * 2);
    defer perf_main.deinit();

    var report_number: u64 = 0;
    while (true) {
        for (0..update_frequency) |_| {
            idf.vTaskDelay(sleep_time_ms / idf.portTICK_PERIOD_MS);

            const start = perf.Marker.now();

            var value: c_int = undefined;
            c.espCheckError(c.adc_oneshot_read(adc, adc_channel, &value)) catch |err| {
                log.err("adc_oneshot_read fail: {}", .{err});
                continue;
            };

            const value_normalized = @as(f32, @floatFromInt(value)) / @as(f32, @floatFromInt(adc_max));
            log.debug(
                "selected duty cycle: {d:.2} = {} / {}",
                .{ value_normalized, value, adc_max },
            );

            const duty_cycle: u32 = @intFromFloat(value_normalized * pwm_max);

            c.espCheckError(c.ledc_set_duty(pwm_speed_mode, pwm_channel, duty_cycle)) catch |err| {
                log.err("ledc_set_duty fail: {}", .{err});
                continue;
            };
            c.espCheckError(c.ledc_update_duty(pwm_speed_mode, pwm_channel)) catch |err| {
                log.err("ledc_update_duty fail: {}", .{err});
                continue;
            };

            perf_main.addSample(start);
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
