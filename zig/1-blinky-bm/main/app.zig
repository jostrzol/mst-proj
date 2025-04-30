const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");
const sys = idf.sys;

const memory = @import("memory.zig");
const perf = @import("perf.zig");

usingnamespace @import("comptime-rt.zig");

const period_ms = 100;
const sleep_duration_ms = period_ms / 2;
const control_iters_per_perf_report: usize = 20;

fn main() !void {
    log.info("Blinking an LED from Zig", .{});

    var is_on = false;

    try idf.gpio.Direction.set(.GPIO_NUM_5, .GPIO_MODE_OUTPUT);

    const tasks = [_]sys.TaskHandle_t{sys.xTaskGetCurrentTaskHandle()};

    var perf_main = try perf.Counter.init("MAIN");

    while (true) {
        for (0..control_iters_per_perf_report) |_| {
            idf.vTaskDelay(sleep_duration_ms / idf.portTICK_PERIOD_MS);

            const start = perf.StartMarker.now();

            log.debug("Turning the LED {s}", .{if (is_on) "ON" else "OFF"});

            idf.gpio.Level.set(.GPIO_NUM_5, @intFromBool(is_on)) catch |err| {
                std.log.err("Error: {}", .{err});
                continue;
            };
            is_on = !is_on;

            perf_main.add_sample(start);
        }
        memory.report(&tasks);
        perf_main.report();
        perf_main.reset();
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
