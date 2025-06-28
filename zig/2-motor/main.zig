const std = @import("std");
const config = @import("config");
const linux = std.os.linux;

const pwm = @import("pwm");

const c = @import("c.zig");
const memory = @import("memory.zig");
const perf = @import("perf.zig");

const i2c_adapter_number = 1;
const i2c_adapter_path = std.fmt.comptimePrint("/dev/i2c-{}", .{i2c_adapter_number});
const ads7830_address = 0x48;

const motor_pwm_channel = 1; // gpio 13
const pwm_frequency = 1000;

const update_frequency = 10;
const sleep_time_ns = std.time.ns_per_s / update_frequency;

var do_continue = true;
pub fn interrupt_handler(_: c_int) callconv(.C) void {
    std.debug.print("\nGracefully stopping\n", .{});
    do_continue = false;
}

pub fn main() !void {
    std.log.info("Controlling motor from Zig\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var counting = memory.CountingAllocator.init(gpa.allocator());
    const allocator = counting.allocator();

    const signal = @intFromPtr(c.signal(c.SIGINT, &interrupt_handler));
    if (signal < 0)
        return std.posix.unexpectedErrno(std.posix.errno(signal));

    var chip = try pwm.Chip.init(0);
    defer chip.deinit();

    const i2c_file = try std.fs.openFileAbsolute(
        i2c_adapter_path,
        std.fs.File.OpenFlags{ .mode = .read_write },
    );
    defer i2c_file.close();

    if (linux.ioctl(i2c_file.handle, c.I2C_SLAVE, ads7830_address) < 0)
        return error.SettingI2cSlave;

    var channel = try chip.channel(motor_pwm_channel);
    defer channel.deinit();

    try channel.setParameters(.{
        .frequency = pwm_frequency,
        .duty_cycle_ratio = 0,
    });
    try channel.enable();

    var perf_main = try perf.Counter.init(allocator, "MAIN", update_frequency * 2);
    defer perf_main.deinit();

    var report_number: u64 = 0;

    while (do_continue) {
        for (0..update_frequency) |_| {
            std.time.sleep(sleep_time_ns);

            const start = perf.Marker.now();

            const value = read_adc(i2c_file) orelse continue;
            const duty_cycle = @as(f32, @floatFromInt(value)) / std.math.maxInt(u8);
            std.log.debug("selected duty cycle: {d:.2}", .{duty_cycle});

            channel.setParameters(.{
                .frequency = null,
                .duty_cycle_ratio = duty_cycle,
            }) catch |err| {
                std.log.err("Error: {}\n", .{err});
            };

            perf_main.add_sample(start);
        }

        std.log.info("# REPORT {}", .{report_number});
        memory.report();
        perf_main.report();
        perf_main.reset();
        report_number += 1;
    }
}

fn read_adc(i2c_file: std.fs.File) ?u8 {
    var write_value = make_read_command(0);
    var read_value: u8 = undefined;

    var msgs = [_]c.i2c_msg{
        // write command
        .{ .addr = ads7830_address, .flags = 0, .len = 1, .buf = &write_value },
        // read data
        .{ .addr = ads7830_address, .flags = c.I2C_M_RD, .len = 1, .buf = &read_value },
    };
    var data = c.i2c_rdwr_ioctl_data{ .msgs = &msgs, .nmsgs = 2 };

    if (linux.ioctl(i2c_file.handle, c.I2C_RDWR, @intFromPtr(&data)) < 0)
        return null;

    return read_value;
}

fn make_read_command(channel: u3) u8 {
    // bit    7: single-ended inputs mode
    // bits 6-4: channel selection
    // bit    3: is internal reference enabled
    // bit    2: is converter enabled
    // bits 1-0: unused
    const default_read_command = 0b10001100;

    const channel_u8: u8 = @intCast(channel);
    return default_read_command & (channel_u8 << 4);
}

pub const std_options: std.Options = .{
    .log_level = std.enums.nameCast(std.log.Level, config.log_level),
};
