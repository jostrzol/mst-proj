const std = @import("std");
const gpio = @import("gpio");
const signal = @cImport({
    @cInclude("signal.h");
    @cInclude("malloc.h");
});

const memory = @import("memory.zig");

const period_ms = 100;
const sleep_time_ns = period_ms * std.time.ns_per_ms / 2;
const line_number = 13;

const control_iters_per_perf_report: usize = 20;

var do_continue = true;
pub fn interrupt_handler(_: c_int) callconv(.C) void {
    std.debug.print("\nGracefully stopping\n", .{});
    do_continue = false;
}
const interrupt_sigaction = signal.struct_sigaction{
    .__sigaction_handler = .{ .sa_handler = &interrupt_handler },
};

pub fn main() !void {
    std.log.info("Controlling an LED from Zig\n", .{});

    if (signal.sigaction(signal.SIGINT, &interrupt_sigaction, null) != 0) {
        return error.SigactionNotSet;
    }

    var chip = try gpio.getChip("/dev/gpiochip0");
    defer chip.close();

    var line = try chip.requestLine(line_number, .{ .output = true });
    defer line.close();

    var is_on = false;
    while (do_continue) {
        for (0..control_iters_per_perf_report) |_| {
            std.time.sleep(sleep_time_ns);

            std.log.debug("Turning the LED {s}", .{if (is_on) "ON" else "OFF"});
            line.setValue(is_on) catch |err| std.log.err("Error: {}", .{err});
            is_on = !is_on;
        }

        memory.report();
    }

    try line.setLow();
}

pub const std_options: std.Options = .{
    .log_level = switch (@import("builtin").mode) {
        .Debug => .debug,
        .ReleaseSafe, .ReleaseFast, .ReleaseSmall => .info,
    },
};
