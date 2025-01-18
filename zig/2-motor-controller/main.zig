const std = @import("std");
const gpio = @import("gpio");
const signal = @cImport(@cInclude("signal.h"));

const pwm = @import("pwm.zig");

const period_ms = 1000;
const sleep_time_ns = period_ms * std.time.ns_per_ms / 2;

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

    var chip = try pwm.Chip.init(0);
    defer chip.deinit();

    std.debug.print("Controlling motor from Zig.\n", .{});

    var channel = try chip.channel(1);

    try channel.setParameters(.{ .frequency = 1000, .duty_cycle_ratio = 0.0 });
    try channel.enable();

    while (do_continue) {
        channel.setParameters(
            .{ .frequency = 1000, .duty_cycle_ratio = 1.0 },
        ) catch std.debug.print("cannot set duty cycle", .{});
        std.time.sleep(sleep_time_ns);

        std.log.debug(
            "on?: {}, period [ns]: {}, duty_cycle [ns]: {}",
            .{ try channel.isEnabled(), try channel.getPeriodNs(), try channel.getDutyCycleNs() },
        );

        channel.setParameters(
            .{ .frequency = 1000, .duty_cycle_ratio = 0.3 },
        ) catch std.debug.print("cannot set duty cycle", .{});
        std.time.sleep(sleep_time_ns);

        std.log.debug(
            "on?: {}, period [ns]: {}, duty_cycle [ns]: {}",
            .{ try channel.isEnabled(), try channel.getPeriodNs(), try channel.getDutyCycleNs() },
        );
    }
}
