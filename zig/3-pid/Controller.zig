const std = @import("std");
const posix = std.posix;
const File = std.fs.File;

const Registers = @import("Registers.zig");
const pwm = @import("pwm");

const c = @cImport({
    @cInclude("memory.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("sys/ioctl.h");
    @cInclude("i2c/smbus.h");
    @cInclude("linux/i2c-dev.h");
    @cInclude("unistd.h");
});

const Self = @This();

options: Options,
registers: *Registers,
i2c_file: File,
pwm_chip: pwm.Chip,
pwm_channel: *pwm.Channel,

pub const Options = struct {
    /// Path to I2C adapter that the ADC device is connected to.
    i2c_adapter_path: []const u8,
    /// Address on the I2C bus of the ADC device.
    i2c_address: u8,
    /// Interval between ADC reads.
    read_interval_us: u64,
    /// When ADC reads below this signal, the state is set to `close` to the
    /// motor magnet. If the state has changed, a new revolution is counted.
    revolution_treshold_close: u8,
    /// When ADC reads above this signal, the state is set to `far` from the
    /// motor magnet.
    revolution_treshold_far: u8,
    /// Revolutions are binned in a ring buffer based on when they happened.
    /// More recent revolutions are in the tail of the buffer, while old ones
    /// are in the head of the buffer (soon to be replaced).
    ///
    /// [revolution_bins] is the number of bins in the ring buffer.
    revolution_bins: u32,
    /// Revolutions are binned in a ring buffer based on when they happened.
    /// More recent revolutions are in the tail of the buffer, while old ones
    /// are in the head of the buffer (soon to be replaced).
    ///
    /// [revolution_bin_rotate_interval] is the interval that each of the bins
    /// correspond to.
    ///
    /// If `revolution_bin_rotate_interval = Duration::from_millis(100)`, then:
    /// * the last bin corresponds to range `0..-100 ms` from now,
    /// * the second-to-last bin corresponds to range `-100..-200 ms` from now,
    /// * and so on.
    ///
    /// In total, frequency will be counted from revolutions in all bins, across
    /// the total interval of [revolution_bins] *
    /// [revolution_bin_rotate_interval].
    ///
    /// [revolution_bin_rotate_interval] is also the interval at which the
    /// measured frequency updates, so all the IO happens at this interval too.
    revolution_bin_rotate_interval_us: u64,
    /// Linux PWM channel to use.
    pwm_channel: u8,
    /// Frequency of the PWM signal.
    pwm_frequency: u64,
};

pub fn init(registers: *Registers, options: Options) !Self {
    const i2c_file = try std.fs.openFileAbsolute(
        options.i2c_adapter_path,
        std.fs.File.OpenFlags{ .mode = .read_write },
    );
    errdefer i2c_file.close();

    if (c.ioctl(i2c_file.handle, c.I2C_SLAVE, options.i2c_address) < 0) {
        return error.SettingI2cSlave;
    }

    var chip = try pwm.Chip.init(0);
    errdefer chip.deinit();

    var channel = try chip.channel(options.pwm_channel);
    errdefer channel.deinit();

    try channel.setParameters(.{
        .frequency = options.pwm_frequency,
        .duty_cycle_ratio = 0,
    });
    try channel.enable();

    return .{
        .options = options,
        .registers = registers,
        .i2c_file = i2c_file,
        .pwm_chip = chip,
        .pwm_channel = channel,
    };
}

pub fn deinit(self: *Self) void {
    self.i2c_file.close();
    self.pwm_channel.deinit();
    self.pwm_chip.deinit();
}
