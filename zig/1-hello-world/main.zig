const std = @import("std");
const gpio = @import("gpio");
const signal = @cImport(@cInclude("signal.h"));

const sleep_time_ns = std.time.ns_per_s / 2;

var do_continue = true;
pub fn interrupt_handler(_: c_int) callconv(.C) void {
    std.debug.print("\nGracefully stopping\n", .{});
    do_continue = false;
}
const interrupt_sigaction = signal.struct_sigaction{
    .__sigaction_handler = .{ .sa_handler = &interrupt_handler },
};

pub fn main() !void {
    if (signal.sigaction(signal.SIGINT, &interrupt_sigaction, null) != 0) {
        return error.SigactionNotSet;
    }

    var chip = try gpio.getChip("/dev/gpiochip0");
    defer chip.close();
    std.debug.print("Blinking an LED from Zig.\n", .{});

    var line = try chip.requestLine(14, .{ .output = true });
    defer line.close();

    while (do_continue) {
        try line.setHigh();
        std.time.sleep(sleep_time_ns);
        try line.setLow();
        std.time.sleep(sleep_time_ns);
    }

    try line.setLow();
}
