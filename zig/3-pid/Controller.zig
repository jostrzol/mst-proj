const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const File = std.fs.File;
const Allocator = std.mem.Allocator;

const Registers = @import("Registers.zig");
const RingBuffer = @import("ring_buffer.zig").RingBuffer;
const pwm = @import("pwm");
const memory = @import("memory.zig");
const c = @import("c.zig");

const Self = @This();

const pwm_min = 0.2;
const pwm_max = 1.0;
const limit_min_deadzone = 0.001;

const control_iters_per_perf_report: usize = 10;

allocator: Allocator,
options: Options,
revolutions: RingBuffer(u32),
registers: *Registers,
i2c_file: File,
pwm_chip: *pwm.Chip,
pwm_channel: *pwm.Channel,
read_timer: File,
control_timer: File,
is_close: bool = false,
feedback: Feedback = .{ .delta = 0, .integration_component = 0 },
iteration: usize = 0,

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
    /// [control_interval_us] is the interval at which all the following happens:
    /// * calculating the frequency for the current time window,
    /// * updating duty cycle,
    /// * updating duty cycle.
    ///
    /// [control_interval_us] also is the interval that each of the bins in the
    /// time window correspond to.
    ///
    /// If `control_interval_us = 100 * std.time.us_per_ms`, then:
    /// * the last bin corresponds to range `0..-100 ms` from now,
    /// * the second-to-last bin corresponds to range `-100..-200 ms` from now,
    /// * and so on.
    ///
    /// In total, frequency is counted from revolutions in all bins, across the
    /// total interval of [revolution_bins] * [control_interval_us].
    control_interval_us: u64,
    /// Linux PWM channel to use.
    pwm_channel: u8,
    /// Frequency of the PWM signal.
    pwm_frequency: u64,
};

const Feedback = struct { delta: f32, integration_component: f32 };

pub fn init(
    allocator: Allocator,
    registers: *Registers,
    options: Options,
) !Self {
    var revolutions = try RingBuffer(u32).init(allocator, options.revolution_bins);
    errdefer revolutions.deinit(allocator);

    const i2c_file = try std.fs.openFileAbsolute(
        options.i2c_adapter_path,
        std.fs.File.OpenFlags{ .mode = .read_write },
    );
    errdefer i2c_file.close();

    if (linux.ioctl(i2c_file.handle, c.I2C_SLAVE, options.i2c_address) < 0)
        return error.SettingI2cSlave;

    var chip = try allocator.create(pwm.Chip);
    errdefer allocator.destroy(chip);

    chip.* = try pwm.Chip.init(0);
    errdefer chip.deinit();

    var channel = try chip.channel(options.pwm_channel);
    errdefer channel.deinit();

    const read_timer_fd = try posix.timerfd_create(linux.CLOCK.REALTIME, .{});
    const read_timer = File{ .handle = read_timer_fd };
    errdefer read_timer.close();

    const read_timerspec = timerspec_from_us(options.read_interval_us);
    try posix.timerfd_settime(read_timer_fd, .{}, &read_timerspec, null);

    const control_timer_fd = try posix.timerfd_create(linux.CLOCK.REALTIME, .{});
    const control_timer = File{ .handle = control_timer_fd };
    errdefer control_timer.close();

    const control_timerspec = timerspec_from_us(options.control_interval_us);
    try posix.timerfd_settime(control_timer_fd, .{}, &control_timerspec, null);

    try channel.setParameters(.{
        .frequency = options.pwm_frequency,
        .duty_cycle_ratio = 0.3,
    });
    try channel.enable();

    return .{
        .allocator = allocator,
        .revolutions = revolutions,
        .options = options,
        .registers = registers,
        .i2c_file = i2c_file,
        .pwm_chip = chip,
        .pwm_channel = channel,
        .read_timer = read_timer,
        .control_timer = control_timer,
    };
}

pub fn deinit(self: *Self) void {
    self.revolutions.deinit(self.allocator);
    self.control_timer.close();
    self.read_timer.close();
    self.pwm_channel.deinit();
    self.pwm_chip.deinit();
    self.allocator.destroy(self.pwm_chip);
    self.i2c_file.close();
}

fn timerspec_from_us(interval_us: u64) linux.itimerspec {
    const s = interval_us / std.time.us_per_s;
    const ns = (interval_us * std.time.ns_per_us) % std.time.ns_per_s;
    const timespec = linux.timespec{
        .tv_sec = @truncate(@as(i64, @bitCast(s))),
        .tv_nsec = @truncate(@as(i64, @bitCast(ns))),
    };
    return .{
        .it_interval = timespec,
        .it_value = timespec,
    };
}

pub const HandleResult = enum { handled, skipped };

pub fn handle(self: *Self, fd: posix.fd_t) !HandleResult {
    if (fd == self.read_timer.handle) {
        var expirations: u64 = undefined;
        _ = try self.read_timer.readAll(std.mem.asBytes(&expirations));

        const value = read_potentiometer_value(self) orelse return error.I2cRead;

        switch (self.get_hystheresis(value)) {
            .below => if (!self.is_close) {
                // gone close
                self.is_close = true;
                self.revolutions.back().* += 1;
            },
            .between => {},
            .above => if (self.is_close) {
                // gone far
                self.is_close = false;
            },
        }

        return .handled;
    } else if (fd == self.control_timer.handle) {
        var expirations: u64 = undefined;
        _ = try self.control_timer.readAll(std.mem.asBytes(&expirations));

        const frequency = self.calculate_frequency();
        try self.revolutions.push(0);
        std.log.debug("frequency: {d:.2} Hz", .{frequency});

        const control_params = self.read_control_params();
        // inline for (std.meta.fields(ControlParams)) |field| {
        //     const value = @field(control_params, field.name);
        //     std.log.debug("{s}: {d:.2}", .{ field.name, value });
        // }

        const control = self.calculate_control(&control_params, frequency);

        const control_signal_limited = limit(control.signal, pwm_min, pwm_max);

        try self.pwm_channel.setParameters(.{
            .frequency = null,
            .duty_cycle_ratio = control_signal_limited,
        });

        self.write_status(frequency, control_signal_limited);

        self.feedback = control.feedback;

        if (self.iteration % control_iters_per_perf_report == 0) {
            memory.report();
        }
        self.iteration += 1;

        return .handled;
    }

    return .skipped;
}

fn read_potentiometer_value(self: *Self) ?u8 {
    var write_value = make_read_command(0);
    var read_value: u8 = undefined;

    const addr = self.options.i2c_address;
    var msgs = [_]c.i2c_msg{
        // write command
        .{ .addr = addr, .flags = 0, .len = 1, .buf = &write_value },
        // read data
        .{ .addr = addr, .flags = c.I2C_M_RD, .len = 1, .buf = &read_value },
    };
    var data = c.i2c_rdwr_ioctl_data{ .msgs = &msgs, .nmsgs = 2 };

    if (linux.ioctl(self.i2c_file.handle, c.I2C_RDWR, @intFromPtr(&data)) < 0)
        return null;

    return read_value;
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

const Hysteresis = enum { below, between, above };

fn get_hystheresis(self: *Self, value: u8) Hysteresis {
    if (value < self.options.revolution_treshold_close) return .below;
    if (value > self.options.revolution_treshold_far) return .above;
    return .between;
}

fn calculate_frequency(self: *Self) f32 {
    var sum: u32 = 0;
    for (self.revolutions.items) |value|
        sum += value;

    const interval_s =
        @as(f32, @floatFromInt(self.options.control_interval_us)) / std.time.us_per_s;
    const all_bins_interval_s: f32 =
        interval_s * @as(f32, @floatFromInt(self.options.revolution_bins));

    return @as(f32, @floatFromInt(sum)) / all_bins_interval_s;
}

pub const ControlParams = struct {
    target_frequency: f32,
    proportional_factor: f32,
    integration_time: f32,
    differentiation_time: f32,
};

fn read_control_params(self: *Self) ControlParams {
    const H = Registers.Holding;
    return .{
        .target_frequency = self.registers.get_holding(H.target_frequency),
        .proportional_factor = self.registers.get_holding(H.proportional_factor),
        .integration_time = self.registers.get_holding(H.integration_time),
        .differentiation_time = self.registers.get_holding(H.differentiation_time),
    };
}

fn calculate_control(
    self: *const Self,
    params: *const ControlParams,
    frequency: f32,
) struct { signal: f32, feedback: Feedback } {
    const interval_s =
        @as(f32, @floatFromInt(self.options.control_interval_us)) / std.time.us_per_s;

    const integration_factor: f32 =
        params.proportional_factor / params.integration_time * interval_s;
    const differentiation_factor: f32 =
        params.proportional_factor * params.differentiation_time / interval_s;

    const delta: f32 = params.target_frequency - frequency;
    std.log.debug("delta: {d:.2}", .{delta});

    const proportional_component: f32 = params.proportional_factor * delta;
    const integration_component: f32 =
        self.feedback.integration_component +
        integration_factor * self.feedback.delta;
    const differentiation_component: f32 =
        differentiation_factor * (delta - self.feedback.delta);

    const control_signal: f32 = proportional_component +
        integration_component +
        differentiation_component;

    std.log.debug("control_signal: {d:.2} = {d:.2} + {d:.2} + {d:.2}", .{
        control_signal,
        proportional_component,
        integration_component,
        differentiation_component,
    });

    return .{
        .signal = control_signal,
        .feedback = .{
            .delta = delta,
            .integration_component = integration_component,
        },
    };
}

fn finite_or_zero(value: f32) f32 {
    return if (std.math.isFinite(value)) 0 else value;
}

fn limit(value: f32, min: f32, max: f32) f32 {
    if (value < limit_min_deadzone)
        return 0;

    const result = value + min;
    return if (result < min) min else if (result > max) max else result;
}

fn write_status(self: *Self, frequency: f32, control_signal: f32) void {
    self.registers.set_input(Registers.Input.frequency, frequency);
    self.registers.set_input(Registers.Input.control_signal, control_signal);
}
