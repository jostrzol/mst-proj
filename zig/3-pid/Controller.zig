const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const File = std.fs.File;
const Allocator = std.mem.Allocator;

const Registers = @import("Registers.zig");
const pwm = @import("pwm");

const c = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("linux/i2c-dev.h");
});

const Self = @This();

allocator: Allocator,
options: Options,
registers: *Registers,
i2c_file: File,
pwm_chip: *pwm.Chip,
pwm_channel: *pwm.Channel,
read_timer: File,

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

pub fn init(
    allocator: Allocator,
    registers: *Registers,
    options: Options,
) !Self {
    const i2c_file = try std.fs.openFileAbsolute(
        options.i2c_adapter_path,
        std.fs.File.OpenFlags{ .mode = .read_write },
    );
    errdefer i2c_file.close();

    if (c.ioctl(i2c_file.handle, c.I2C_SLAVE, options.i2c_address) < 0) {
        return error.SettingI2cSlave;
    }

    var chip = try allocator.create(pwm.Chip);
    errdefer allocator.destroy(chip);

    chip.* = try pwm.Chip.init(0);
    errdefer chip.deinit();

    var channel = try chip.channel(options.pwm_channel);
    errdefer channel.deinit();

    try channel.setParameters(.{
        .frequency = options.pwm_frequency,
        .duty_cycle_ratio = 0,
    });
    try channel.enable();

    const read_timer_fd = try posix.timerfd_create(linux.CLOCK.REALTIME, .{});
    const read_timer = File{ .handle = read_timer_fd };
    errdefer read_timer.close();

    const read_timerspec = timerspec_from_us(options.read_interval_us);
    try posix.timerfd_settime(read_timer_fd, .{}, &read_timerspec, null);

    return .{
        .allocator = allocator,
        .options = options,
        .registers = registers,
        .i2c_file = i2c_file,
        .pwm_chip = chip,
        .pwm_channel = channel,
        .read_timer = read_timer,
    };
}

pub fn deinit(self: *Self) void {
    self.read_timer.close();
    self.pwm_channel.deinit();
    self.pwm_chip.deinit();
    self.allocator.destroy(self.pwm_chip);
    self.i2c_file.close();
}

fn timerspec_from_us(interval_us: u64) linux.itimerspec {
    const timespec = linux.timespec{
        .tv_sec = @truncate(@as(i64, @bitCast(interval_us / std.time.us_per_s))),
        .tv_nsec = @truncate(@as(i64, @bitCast(interval_us % std.time.us_per_s))),
    };
    return .{
        .it_interval = timespec,
        .it_value = timespec,
    };
}

pub const HandleResult = enum { handled, skipped };

pub fn handle(self: *Self, fd: posix.fd_t) !HandleResult {
    if (fd == self.read_timer.handle) {
        return .handled;
    }

    return .skipped;
}

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
    if (c.i2c_smbus_write_byte(i2c_file.handle, make_read_command(0)) < 0) {
        std.log.err("writing i2c ADC command failed", .{});
        return null;
    }

    const value = c.i2c_smbus_read_byte(i2c_file.handle);
    if (value < 0) {
        std.log.err("reading i2c ADC value failed", .{});
        return null;
    }

    return @intCast(value);
}
