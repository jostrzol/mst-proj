const std = @import("std");
const linux = std.os.linux;

const pwm = @import("pwm");

const c = @cImport({
    @cInclude("signal.h");
    @cInclude("linux/i2c-dev.h");
    @cInclude("i2c/smbus.h");
    @cInclude("sys/ioctl.h");
});

const i2c_adapter_number = 1;
const i2c_adapter_path = std.fmt.comptimePrint("/dev/i2c-{}", .{i2c_adapter_number});
const ads7830_address: c_int = 0x48;
const motor_pwm_channel: u8 = 1; // gpio 13

const pwm_frequency: f32 = 1000;
const refresh_rate: u64 = 60;
const sleep_time_ns: u64 = std.time.ns_per_ms / refresh_rate;

var do_continue = true;
pub fn interrupt_handler(_: c_int) callconv(.C) void {
    std.debug.print("\nGracefully stopping\n", .{});
    do_continue = false;
}
const interrupt_sigaction = c.struct_sigaction{
    .__sigaction_handler = .{ .sa_handler = &interrupt_handler },
};

fn make_read_command(comptime channel: u8) u8 {
    comptime std.debug.assert(channel < 7);

    // bit    7: single-ended inputs mode
    // bits 6-4: channel selection
    // bit    3: is internal reference enabled
    // bit    2: is converter enabled
    // bits 1-0: unused
    const default_read_command = 0b10001100;

    return default_read_command & (channel << 4);
}

fn read_potentiometer_value(i2c_file: std.fs.File) ?u8 {
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

pub fn main() !void {
    if (c.sigaction(c.SIGINT, &interrupt_sigaction, null) != 0)
        return error.SigactionNotSet;

    var chip = try pwm.Chip.init(0);
    defer chip.deinit();

    const i2c_file = try std.fs.openFileAbsolute(
        i2c_adapter_path,
        std.fs.File.OpenFlags{ .mode = .read_write },
    );
    defer i2c_file.close();

    if (linux.ioctl(i2c_file.handle, c.I2C_SLAVE, ads7830_address) < 0)
        return error.SettingI2cSlave;

    std.debug.print("Controlling motor from Zig.\n", .{});

    var channel = try chip.channel(motor_pwm_channel);
    defer channel.deinit();

    try channel.setParameters(.{
        .frequency = pwm_frequency,
        .duty_cycle_ratio = 0,
    });
    try channel.enable();

    while (do_continue) {
        std.time.sleep(sleep_time_ns);

        const value = read_potentiometer_value(i2c_file) orelse continue;
        const duty_cycle = @as(f32, @floatFromInt(value)) / std.math.maxInt(u8);
        std.debug.print("selected duty cycle: {d:.2}\n", .{duty_cycle});

        channel.setParameters(.{
            .frequency = null,
            .duty_cycle_ratio = duty_cycle,
        }) catch |err| {
            std.debug.print("error updating duty cycle: {}\n", .{err});
        };
    }
}
