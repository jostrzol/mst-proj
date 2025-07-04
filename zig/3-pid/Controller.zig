const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const File = std.fs.File;
const Allocator = std.mem.Allocator;

const Registers = @import("Registers.zig");
const RingBuffer = @import("ring_buffer.zig").RingBuffer;
const pwm = @import("pwm");
const memory = @import("memory.zig");
const perf = @import("perf.zig");
const c = @import("c.zig");

const Self = @This();

const pwm_min = 0.2;
const pwm_max = 1.0;
const limit_min_deadzone = 0.001;

allocator: Allocator,
options: Options,
registers: *Registers,
i2c_file: File,
pwm_chip: *pwm.Chip,
pwm_channel: *pwm.Channel,
timer: File,
interval: struct {
    rotate_once_s: f32,
    rotate_all_s: f32,
},
state: struct {
    revolutions: RingBuffer(u32),
    is_close: bool = false,
    feedback: Feedback = .{ .delta = 0, .integration_component = 0 },
    iteration: u64 = 1,
},
perf: struct {
    read: perf.Counter,
    control: perf.Counter,
},

pub const Options = struct {
    /// Frequency of control phase, during which the following happens:
    /// * calculating the frequency for the current time window,
    /// * moving the time window forward,
    /// * updating duty cycle,
    /// * updating modbus registers.
    control_frequency: u32,
    /// Frequency is estimated for the current time window. That window is broken
    /// into [time_window_bins] bins and is moved every time the control phase
    /// takes place.
    time_window_bins: u32,
    /// Each bin in the time window gets [reads_per_bin] reads, before the next
    /// control phase fires. That means, that the read phase occurs with frequency
    /// equal to:
    ///     `control_frequency * reads_per_bin`
    /// , because every time the window moves (control phase), there must be
    /// [reads_per_bin] reads in the last bin already (read phase).
    reads_per_bin: u32,
    /// When ADC reads below this signal, the state is set to `close` to the
    /// motor magnet. If the state has changed, a new revolution is counted.
    revolution_treshold_close: u8,
    /// When ADC reads above this signal, the state is set to `far` from the
    /// motor magnet.
    revolution_treshold_far: u8,
    /// Path to I2C adapter that the ADC device is connected to.
    i2c_adapter_path: []const u8,
    /// Address on the I2C bus of the ADC device.
    i2c_address: u8,
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
    var revolutions = try RingBuffer(u32).init(allocator, options.time_window_bins);
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

    const timer_fd = try posix.timerfd_create(linux.CLOCK.REALTIME, .{});
    const timer = File{ .handle = timer_fd };
    errdefer timer.close();

    const read_frequency = options.control_frequency * options.reads_per_bin;
    const read_interval_us = std.time.us_per_s / read_frequency;

    const timerspec = timerspec_from_us(read_interval_us);
    try posix.timerfd_settime(timer_fd, .{}, &timerspec, null);

    try channel.setParameters(.{
        .frequency = options.pwm_frequency,
        .duty_cycle_ratio = 0.0,
    });
    try channel.enable();

    const interval_rotate_once_s: f32 =
        1.0 / @as(f32, @floatFromInt(options.control_frequency));
    const interval_rotate_all_s: f32 =
        interval_rotate_once_s * @as(f32, @floatFromInt(options.time_window_bins));

    const perf_read = try perf.Counter.init(allocator, "READ", read_frequency * 2);
    errdefer perf_read.deinit();
    const perf_control = try perf.Counter.init(allocator, "CONTROL", options.control_frequency * 2);
    errdefer perf_control.deinit();

    return .{
        .allocator = allocator,
        .options = options,
        .registers = registers,
        .i2c_file = i2c_file,
        .pwm_chip = chip,
        .pwm_channel = channel,
        .timer = timer,
        .interval = .{
            .rotate_once_s = interval_rotate_once_s,
            .rotate_all_s = interval_rotate_all_s,
        },
        .state = .{ .revolutions = revolutions },
        .perf = .{
            .read = perf_read,
            .control = perf_control,
        },
    };
}

pub fn deinit(self: *Self) void {
    self.state.revolutions.deinit(self.allocator);
    self.timer.close();
    self.pwm_channel.deinit();
    self.pwm_chip.deinit();
    self.allocator.destroy(self.pwm_chip);
    self.i2c_file.close();
}

pub const HandleResult = enum { handled, skipped };

pub fn handle(self: *Self, fd: posix.fd_t) !HandleResult {
    if (fd != self.timer.handle) return .skipped;

    var expirations: u64 = undefined;
    _ = try self.timer.readAll(std.mem.asBytes(&expirations));

    const read_start = perf.Marker.now();
    self.read_phase() catch |err| std.log.err("read_phase fail: {}", .{err});
    self.perf.read.add_sample(read_start);

    if (self.state.iteration % self.options.reads_per_bin == 0) {
        const control_start = perf.Marker.now();
        self.control_phase() catch |err| std.log.err("control_phase fail: {}", .{err});
        self.perf.control.add_sample(control_start);
    }

    const reads_per_report = self.options.reads_per_bin * self.options.control_frequency;
    if (self.state.iteration % reads_per_report == 0) {
        const report_number = self.state.iteration / reads_per_report - 1;
        std.log.info("# REPORT {}", .{report_number});
        memory.report();
        self.perf.control.report();
        self.perf.read.report();
        self.perf.control.reset();
        self.perf.read.reset();
    }

    self.state.iteration += 1;

    return .handled;
}

fn read_phase(self: *Self) !void {
    const value = try self.read_adc();

    if (!self.state.is_close and value < self.options.revolution_treshold_close) {
        // gone close
        self.state.is_close = true;
        self.state.revolutions.back().* += 1;
    } else if (self.state.is_close and value > self.options.revolution_treshold_far) {
        // gone far
        self.state.is_close = false;
    }
}

fn read_adc(self: *Self) !u8 {
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

    const res = linux.ioctl(self.i2c_file.handle, c.I2C_RDWR, @intFromPtr(&data));
    if (res < 0)
        return posix.unexpectedErrno(posix.errno(res));

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

fn control_phase(self: *Self) !void {
    const frequency = self.calculate_frequency();
    self.state.revolutions.push(0);
    std.log.debug("frequency: {d:.2} Hz", .{frequency});

    const control_params = self.read_control_params();

    const control = self.calculate_control(&control_params, frequency);

    const control_signal_limited = limit(control.signal, pwm_min, pwm_max);
    std.log.debug("control signal limited: {d:.2}", .{control_signal_limited});

    try self.set_duty_cycle(control_signal_limited);

    self.write_registers(frequency, control_signal_limited);

    self.state.feedback = control.feedback;
}

fn calculate_frequency(self: *Self) f32 {
    var sum: u32 = 0;
    for (self.state.revolutions.items) |value|
        sum += value;

    return @as(f32, @floatFromInt(sum)) / self.interval.rotate_all_s;
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
    const interval_s = self.interval.rotate_once_s;

    const integration_factor: f32 =
        params.proportional_factor / params.integration_time * interval_s;
    const differentiation_factor: f32 =
        params.proportional_factor * params.differentiation_time / interval_s;

    const delta: f32 = params.target_frequency - frequency;
    std.log.debug("delta: {d:.2}", .{delta});

    const proportional_component: f32 = params.proportional_factor * delta;
    const integration_component: f32 =
        self.state.feedback.integration_component +
        integration_factor * self.state.feedback.delta;
    const differentiation_component: f32 =
        differentiation_factor * (delta - self.state.feedback.delta);

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

fn set_duty_cycle(self: *Self, value: f32) !void {
    try self.pwm_channel.setParameters(.{
        .frequency = null,
        .duty_cycle_ratio = value,
    });
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

fn write_registers(self: *Self, frequency: f32, control_signal: f32) void {
    self.registers.set_input(Registers.Input.frequency, frequency);
    self.registers.set_input(Registers.Input.control_signal, control_signal);
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
