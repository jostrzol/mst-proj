const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");
const sys = idf.sys;

const memory = @import("memory.zig");
const perf = @import("perf.zig");

usingnamespace @import("comptime-rt.zig");

const blink_frequency = 10;
const update_frequency = 2 * blink_frequency;
const sleep_time_ms = std.time.ms_per_s / update_frequency;

fn main() !void {
    log.info("Blinking an LED from Zig", .{});

    const allocator = std.heap.raw_c_allocator;

    try idf.gpio.Direction.set(.GPIO_NUM_5, .GPIO_MODE_OUTPUT);

    var perf_main = try perf.Counter.init(allocator, "MAIN", update_frequency * 2);
    defer perf_main.deinit();

    var report_number: u64 = 0;

    var is_on = false;
    while (true) {
        for (0..update_frequency) |_| {
            idf.vTaskDelay(sleep_time_ms / idf.portTICK_PERIOD_MS);

            const start = perf.Marker.now();

            log.debug("Turning the LED {s}", .{if (is_on) "ON" else "OFF"});

            idf.gpio.Level.set(.GPIO_NUM_5, @intFromBool(is_on)) catch |err| {
                std.log.err("Error: {}", .{err});
                continue;
            };
            is_on = !is_on;

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
