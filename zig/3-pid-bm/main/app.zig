const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");
const sys = idf.sys;

const c = @import("c.zig");
usingnamespace @import("comptime-rt.zig");

const Services = @import("Services.zig");
const Server = @import("Server.zig");
const Registers = @import("Registers.zig");
const Controller = @import("Controller.zig");
const adc = @import("adc.zig");
const pwm = @import("pwm.zig");

const stack_size = 4096;

fn main() !void {
    const heap = std.heap.raw_c_allocator;
    var arena = std.heap.ArenaAllocator.init(heap);
    defer arena.deinit();
    const allocator = arena.allocator();

    const services = try Services.init();
    defer services.deinit();

    var registers = Registers{};

    var server = try Server.init(&.{
        .netif = services.wifi.netif,
        .registers = &registers,
    });
    defer server.deinit();

    var controller = try Controller.init(
        allocator,
        &registers,
        .{
            .frequency = 1000,
            .revolution_treshold_close = 0.36,
            .revolution_treshold_far = 0.40,
            .revolution_bins = 10,
            .reads_per_bin = 100,
        },
    );
    defer controller.deinit();

    const server_task = idf.xTaskCreatePinnedToCore(
        Server.run,
        "SERVER_LOOP",
        stack_size,
        &server,
        2,
        null,
        0,
    );
    defer sys.vTaskDelete(server_task);

    const controller_task = idf.xTaskCreatePinnedToCore(
        Controller.run,
        "CONTROLLER_LOOP",
        stack_size,
        &controller,
        c.configMAX_PRIORITIES - 1,
        null,
        1,
    );
    defer sys.vTaskDelete(controller_task);

    log.info("Controlling motor from Zig", .{});

    while (true)
        idf.vTaskDelay(10 * 1000 / c.portTICK_PERIOD_MS);
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
