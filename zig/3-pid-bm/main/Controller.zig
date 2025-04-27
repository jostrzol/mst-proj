const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;
const Allocator = std.mem.Allocator;

const Registers = @import("Registers.zig");
const RingBuffer = @import("ring_buffer.zig").RingBuffer;
const adc_m = @import("adc.zig");
const pwm_m = @import("pwm.zig");
const perf_m = @import("perf.zig");
const c = @import("c.zig");
const utils = @import("utils.zig");
const logErr = utils.logErr;
const panicErr = utils.panicErr;

const adc_bitwidth = c.ADC_BITWIDTH_9;
const adc_max = (1 << adc_bitwidth) - 1;

const pwm_bitwidth = c.LEDC_TIMER_13_BIT;
const pwm_duty_max = (1 << pwm_bitwidth) - 1;

const timer_frequency = 1000000; // period = 1us
const control_iters_per_perf_report = 10;

const pwm_min = 0.1;
const pwm_max = 1.0;
const limit_min_deadzone = 0.001;

opts: InitOpts,
registers: *Registers,
adc: struct {
    unit: adc_m.Unit,
    channel: adc_m.Channel,
},
pwm: struct {
    timer: pwm_m.Timer,
    channel: pwm_m.Channel,
},
timer: struct {
    semaphore: sys.QueueHandle_t,
    handle: c.gptimer_handle_t,
},
interval: struct {
    rotate_once_s: f32,
    rotate_all_s: f32,
},
state: struct {
    revolutions: RingBuffer(u32),
    is_close: bool,
    feedback: Feedback,
},

pub const InitOpts = struct {
    frequency: u64,
    revolution_treshold_close: f32,
    revolution_treshold_far: f32,
    revolution_bins: usize,
    reads_per_bin: usize,
};

const Feedback = struct {
    delta: f32 = 0,
    integration_component: f32 = 0,
};

const Self = @This();

pub fn init(allocator: Allocator, registers: *Registers, opts: InitOpts) !Self {
    const adc_unit = try adc_m.Unit.init(c.ADC_UNIT_1);
    errdefer adc_unit.deinit();
    const adc_channel = try adc_unit.channel(c.ADC_CHANNEL_4, &.{
        .atten = c.ADC_ATTEN_DB_12,
        .bitwidth = adc_bitwidth,
    });

    const pwm_timer = try pwm_m.Timer.init(&.{
        .speed_mode = c.LEDC_LOW_SPEED_MODE,
        .duty_resolution = c.LEDC_TIMER_13_BIT,
        .timer_num = c.LEDC_TIMER_0,
        .freq_hz = 1000,
        .clk_cfg = c.LEDC_AUTO_CLK,
    });
    errdefer pwm_timer.deinit();
    const pwm_channel = try pwm_timer.channel(c.LEDC_CHANNEL_0, c.GPIO_NUM_5);
    errdefer pwm_channel.deinit();

    const timer_semaphore = idf.xSemaphoreCreateBinary() orelse return error.ErrorInvalidState;
    errdefer idf.vSemaphoreDelete(timer_semaphore);

    var timer: c.gptimer_handle_t = undefined;
    try c.espCheckError(gptimer_new_timer(
        &.{
            .clk_src = c.GPTIMER_CLK_SRC_DEFAULT,
            .direction = c.GPTIMER_COUNT_UP,
            .resolution_hz = timer_frequency,
        },
        &timer,
    ));
    errdefer c.espLogError(c.gptimer_del_timer(timer));

    try c.espCheckError(c.gptimer_register_event_callbacks(
        timer,
        &.{ .on_alarm = onTimerFired },
        timer_semaphore,
    ));

    try c.espCheckError(c.gptimer_enable(timer));
    errdefer c.espLogError(c.gptimer_disable(timer));

    try c.espCheckError(gptimer_set_alarm_action(timer, &.{
        .alarm_count = timer_frequency / opts.frequency,
        .reload_count = 0,
        .flags = .{ .auto_reload_on_alarm = true },
    }));

    const interval_rotate_once_s: f32 =
        1.0 / @as(f32, @floatFromInt(opts.frequency)) * @as(f32, @floatFromInt(opts.reads_per_bin));
    const interval_rotate_all_s: f32 =
        interval_rotate_once_s * @as(f32, @floatFromInt(opts.revolution_bins));

    const revolutions = try RingBuffer(u32).init(allocator, opts.revolution_bins);
    errdefer revolutions.deinit(allocator);

    return .{
        .opts = opts,
        .registers = registers,
        .adc = .{
            .unit = adc_unit,
            .channel = adc_channel,
        },
        .pwm = .{
            .timer = pwm_timer,
            .channel = pwm_channel,
        },
        .timer = .{
            .semaphore = timer_semaphore,
            .handle = timer,
        },
        .interval = .{
            .rotate_once_s = interval_rotate_once_s,
            .rotate_all_s = interval_rotate_all_s,
        },
        .state = .{
            .revolutions = revolutions,
            .is_close = false,
            .feedback = .{},
        },
    };
}

pub fn deinit(self: *const Self, allocator: Allocator) void {
    self.state.revolutions.deinit(allocator);
    self.adc.unit.deinit();
    self.pwm.timer.deinit();
    self.pwm.channel.deinit();
    c.espLogError(c.gptimer_stop(self.timer.handle));
    c.espLogError(c.gptimer_disable(self.timer.handle));
    c.espLogError(c.gptimer_del_timer(self.timer.handle));
}

pub fn run(args: ?*anyopaque) callconv(.c) void {
    const self: *Self = @alignCast(@ptrCast(args));

    c.espCheckError(c.gptimer_start(self.timer.handle)) catch |err| panicErr(err);

    var perf_read = perf_m.Counter.init("READ") catch |err| panicErr(err);
    var perf_control = perf_m.Counter.init("CONTROL") catch |err| panicErr(err);

    while (true) {
        for (0..control_iters_per_perf_report) |_| {
            for (0..self.opts.reads_per_bin) |_| {
                _ = idf.xSemaphoreTake(self.timer.semaphore, std.math.maxInt(u32));

                const read_start = perf_m.StartMarker.now();
                logErr(self.read_iteration());
                perf_read.add_sample(read_start);
            }

            const control_start = perf_m.StartMarker.now();
            logErr(self.control_iteration());
            perf_control.add_sample(control_start);
        }

        perf_read.report();
        perf_control.report();
        perf_read.reset();
        perf_control.reset();
    }
}

fn read_iteration(self: *Self) !void {
    const value = try self.read_adc();

    if (!self.state.is_close and value < self.opts.revolution_treshold_close) {
        // gone close
        self.state.is_close = true;
        self.state.revolutions.back().* += 1;
    } else if (self.state.is_close and value > self.opts.revolution_treshold_far) {
        // gone far
        self.state.is_close = false;
    }
}

fn read_adc(self: *Self) !f32 {
    const value = try self.adc.channel.read();
    return @as(f32, @floatFromInt(value)) / adc_max;
}

fn control_iteration(self: *Self) !void {
    const frequency = self.calculate_frequency();
    try self.state.revolutions.push(0);
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
    const holding = self.registers.holding;
    return .{
        .target_frequency = holding.target_frequency.toF32(),
        .proportional_factor = holding.proportional_factor.toF32(),
        .integration_time = holding.integration_time.toF32(),
        .differentiation_time = holding.differentiation_time.toF32(),
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
    const duty_cycle: u32 = @intFromFloat(value * pwm_duty_max);
    try self.pwm.channel.set_duty_cycle(duty_cycle);
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
    var input = &self.registers.input;
    input.frequency = .fromF32(frequency);
    input.control_signal = .fromF32(control_signal);
}

export fn onTimerFired(
    _: c.gptimer_handle_t,
    _: [*c]const c.gptimer_alarm_event_data_t,
    user_data: ?*anyopaque,
) linksection(".iram1.0") callconv(.c) bool {
    const timer_semaphore: idf.QueueHandle_t = @ptrCast(user_data);

    var high_task_awoken: isize = 0;
    _ = idf.xSemaphoreGiveFromISR(timer_semaphore, &high_task_awoken);
    return high_task_awoken != 0;
}

pub const gptimer_config_t = extern struct {
    clk_src: c.gptimer_clock_source_t = @import("std").mem.zeroes(c.gptimer_clock_source_t),
    direction: c.gptimer_count_direction_t = @import("std").mem.zeroes(c.gptimer_count_direction_t),
    resolution_hz: u32 = @import("std").mem.zeroes(u32),
    intr_priority: c_int = @import("std").mem.zeroes(c_int),
    flags: packed struct(u32) {
        intr_shared: bool = false,
        allow_pd: bool = false,
        backup_before_sleep: bool = false,
        _padding: u29 = 0,
    } = .{},
};
pub extern fn gptimer_new_timer(config: ?*const gptimer_config_t, ret_timer: [*c]c.gptimer_handle_t) c.esp_err_t;

pub const gptimer_alarm_config_t = extern struct {
    alarm_count: u64 = @import("std").mem.zeroes(u64),
    reload_count: u64 = @import("std").mem.zeroes(u64),
    flags: packed struct(u32) {
        auto_reload_on_alarm: bool = false,
        _padding: u31 = 0,
    } = .{},
};
pub extern fn gptimer_set_alarm_action(timer: c.gptimer_handle_t, config: ?*const gptimer_alarm_config_t) c.esp_err_t;
