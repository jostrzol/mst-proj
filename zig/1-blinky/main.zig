const std = @import("std");
const config = @import("config");
const gpio = @import("gpio");

const c = @import("c.zig");
const memory = @import("memory.zig");
const perf = @import("perf.zig");

const line_number = 13;

const blink_frequency = 10;
const update_frequency = 2 * blink_frequency;
const sleep_time_ns = std.time.ns_per_s / update_frequency;

var do_continue = true;
pub fn interrupt_handler(_: c_int) callconv(.C) void {
    std.debug.print("\nGracefully stopping\n", .{});
    do_continue = false;
}

pub fn main() !void {
    std.log.info("Controlling an LED from Zig\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var counting = memory.CountingAllocator.init(gpa.allocator());
    const allocator = counting.allocator();

    const signal = @intFromPtr(c.signal(c.SIGINT, &interrupt_handler));
    if (signal < 0)
        return std.posix.unexpectedErrno(std.posix.errno(signal));

    var chip = try gpio.getChip("/dev/gpiochip0");
    defer chip.close();

    var line = try chip.requestLine(line_number, .{ .output = true });
    defer line.close();

    var perf_main = try perf.Counter.init(allocator, "MAIN", update_frequency * 2);
    defer perf_main.deinit();

    var report_number: u64 = 0;

    var is_on = false;
    while (do_continue) {
        for (0..update_frequency) |_| {
            std.time.sleep(sleep_time_ns);

            const start = perf.Marker.now();

            std.log.debug("Turning the LED {s}", .{if (is_on) "ON" else "OFF"});
            line.setValue(is_on) catch |err| std.log.err("Line.setValue fail: {}", .{err});
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

pub const std_options: std.Options = .{
    .log_level = std.enums.nameCast(std.log.Level, config.log_level),
};
