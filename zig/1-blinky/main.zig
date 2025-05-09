const std = @import("std");
const gpio = @import("gpio");

const c = @import("c.zig");
const memory = @import("memory.zig");
const perf = @import("perf.zig");

const period_ms = 100;
const sleep_time_ns = period_ms * std.time.ns_per_ms / 2;
const line_number = 13;

const control_iters_per_perf_report: usize = 20;

var do_continue = true;
pub fn interrupt_handler(_: c_int) callconv(.C) void {
    std.debug.print("\nGracefully stopping\n", .{});
    do_continue = false;
}
const interrupt_sigaction = c.struct_sigaction{
    .__sigaction_handler = .{ .sa_handler = &interrupt_handler },
};

pub fn main() !void {
    std.log.info("Controlling an LED from Zig\n", .{});

    if (c.sigaction(c.SIGINT, &interrupt_sigaction, null) != 0) {
        return error.SigactionNotSet;
    }

    var chip = try gpio.getChip("/dev/gpiochip0");
    defer chip.close();

    var line = try chip.requestLine(line_number, .{ .output = true });
    defer line.close();

    var is_on = false;

    var perf_main = try perf.Counter.init("MAIN");
    while (do_continue) {
        for (0..control_iters_per_perf_report) |_| {
            std.time.sleep(sleep_time_ns);

            const start = perf.Marker.now();

            std.log.debug("Turning the LED {s}", .{if (is_on) "ON" else "OFF"});
            line.setValue(is_on) catch |err| std.log.err("Error: {}", .{err});
            is_on = !is_on;

            perf_main.add_sample(start);
        }

        memory.report();
        perf_main.report();
        perf_main.reset();
    }

    try line.setLow();
}

pub const std_options: std.Options = .{
    .log_level = switch (@import("builtin").mode) {
        .Debug => .debug,
        .ReleaseSafe, .ReleaseFast, .ReleaseSmall => .info,
    },
};
