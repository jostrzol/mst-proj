const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");

const c = @import("c.zig");
usingnamespace @import("comptime-rt.zig");

const Services = @import("Services.zig");
const Server = @import("Server.zig");
const Registers = @import("Registers.zig");
const Controller = @import("Controller.zig");
const adc = @import("adc.zig");
const pwm = @import("pwm.zig");

fn main() !void {
    const services = try Services.init();
    defer services.deinit();

    var registers = Registers{};

    const server = try Server.init(&.{
        .netif = services.wifi.netif,
        .registers = &registers,
    });
    defer server.deinit();

    const controller = try Controller.init(&registers, .{
        .frequency = 1000,
        .revolution_treshold_close = 0.36,
        .revolution_treshold_far = 0.40,
        .revolution_bins = 10,
        .reads_per_bin = 100,
    });
    defer controller.deinit();

    log.info("Controlling motor from Zig", .{});

    while (true) {
        // const value = try adc_channel.read();
        //
        // const value_normalized = @as(f32, @floatFromInt(value)) / @as(f32, @floatFromInt(adc_max));
        // log.info(
        //     "selected duty cycle: {d:.2} = {} / {}",
        //     .{ value_normalized, value, adc_max },
        // );
        //
        // const duty_cycle: u32 = @intFromFloat(value_normalized * pwm_max);
        // try pwm_channel.set_duty_cycle(duty_cycle);

        idf.vTaskDelay(100);
    }
}

export fn app_main() callconv(.C) void {
    main() catch |err| std.debug.panic("Failed to call main: {}", .{err});
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
