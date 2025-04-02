const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");

const tag = "motor";
const period_ms = 1000;
const sleep_duration_ms = period_ms / 2;

fn main() !void {
    log.info("Blinking an LED from Zig", .{});

    var is_on = false;

    try idf.gpio.Direction.set(.GPIO_NUM_5, .GPIO_MODE_OUTPUT);
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
