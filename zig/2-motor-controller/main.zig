const std = @import("std");
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

const period_ms: u64 = 5000;
const pwm_updates_per_period: u64 = 50;
const pwm_min: f32 = 0.2;
const pwm_max: f32 = 1.0;
const pwm_frequency: f32 = 1000;
const sleep_time_ns: u64 = period_ms * std.time.ns_per_ms / pwm_updates_per_period;

var do_continue = true;
pub fn interrupt_handler(_: c_int) callconv(.C) void {
    std.debug.print("\nGracefully stopping\n", .{});
    do_continue = false;
}
const interrupt_sigaction = c.struct_sigaction{
    .__sigaction_handler = .{ .sa_handler = &interrupt_handler },
};

pub fn main() !void {
    if (c.sigaction(c.SIGINT, &interrupt_sigaction, null) != 0) {
        return error.SigactionNotSet;
    }

    var chip = try pwm.Chip.init(0);
    defer chip.deinit();

    const i2c_file = try std.fs.openFileAbsolute(
        i2c_adapter_path,
        std.fs.File.OpenFlags{ .mode = .read_write },
    );
    defer i2c_file.close();

    if (c.ioctl(i2c_file.handle, c.I2C_SLAVE, ads7830_address) < 0) {
        return error.SettingI2cSlave;
    }

    std.debug.print("Controlling motor from Zig.\n", .{});

    var channel = try chip.channel(motor_pwm_channel);
    defer channel.deinit();

    try channel.setParameters(.{
        .frequency = pwm_frequency,
        .duty_cycle_ratio = 0,
    });
    try channel.enable();

    main_loop: while (true) {
        for (0..pwm_updates_per_period) |i| {
            _ = c.i2c_smbus_write_byte(i2c_file.handle, 0x84);
            const value = c.i2c_smbus_read_byte(i2c_file.handle);
            std.debug.print("selected duty cycle: {}", .{value});

            updateDutyCycle(channel, i) catch |err| {
                std.debug.print("error updating duty cycle: {}", .{err});
            };

            if (!do_continue) break :main_loop;
            std.time.sleep(sleep_time_ns);
        }
    }
}
fn updateDutyCycle(channel: *pwm.Channel, step: u64) !void {
    const sin_arg_ratio = @as(f32, @floatFromInt(step)) / pwm_updates_per_period;
    const sin = std.math.sin(sin_arg_ratio * 2 * std.math.pi);
    const ratio = (sin + 1) / 2;
    const duty_cycle = pwm_min + ratio * (pwm_max - pwm_min);
    try channel.setParameters(.{
        .frequency = null,
        .duty_cycle_ratio = duty_cycle,
    });
}
