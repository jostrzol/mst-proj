const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;
const Allocator = std.mem.Allocator;

const Registers = @import("Registers.zig");
const RingBuffer = @import("ring_buffer.zig").RingBuffer;
const adc_m = @import("adc.zig");
const pwm_m = @import("pwm.zig");
const perf_m = @import("perf.zig");
const memory = @import("memory.zig");
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

var controller_task: sys.TaskHandle_t = null;

allocator: Allocator,
options: InitOptions,
registers: *Registers,
adc: struct {
    unit: adc_m.Unit,
    channel: adc_m.Channel,
},
pwm: struct {
    timer: pwm_m.Timer,
    channel: pwm_m.Channel,
},
timer: c.gptimer_handle_t,
interval: struct {
    rotate_once_s: f32,
    rotate_all_s: f32,
},
state: struct {
    revolutions: RingBuffer(u32),
    is_close: bool,
    feedback: Feedback,
},

pub const InitOptions = struct {
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
    revolution_treshold_close: f32,
    /// When ADC reads above this signal, the state is set to `far` from the
    /// motor magnet.
    revolution_treshold_far: f32,
};

const Feedback = struct {
    delta: f32 = 0,
    integration_component: f32 = 0,
};

const Self = @This();

pub fn init(allocator: Allocator, registers: *Registers, options: InitOptions) !Self {
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

    var timer: c.gptimer_handle_t = undefined;
    try c.espCheckError(gptimer_new_timer(
        &.{
            .clk_src = c.GPTIMER_CLK_SRC_DEFAULT,
            .direction = c.GPTIMER_COUNT_UP,
            .resolution_hz = timer_frequency,
        },
        &timer,
    ));
    errdefer c.espLogError(c.gptimer_del_timer(timer), "gptimer_del_timer");

    try c.espCheckError(c.gptimer_register_event_callbacks(
        timer,
        &.{ .on_alarm = onTimerFired },
        null,
    ));

    try c.espCheckError(c.gptimer_enable(timer));
    errdefer c.espLogError(c.gptimer_disable(timer), "gptimer_disable");

    const read_frequency = options.control_frequency * options.reads_per_bin;
    try c.espCheckError(gptimer_set_alarm_action(timer, &.{
        .alarm_count = timer_frequency / read_frequency,
        .reload_count = 0,
        .flags = .{ .auto_reload_on_alarm = true },
    }));

    const interval_rotate_once_s: f32 =
        1.0 / @as(f32, @floatFromInt(options.control_frequency));
    const interval_rotate_all_s: f32 =
        interval_rotate_once_s * @as(f32, @floatFromInt(options.time_window_bins));

    const revolutions = try RingBuffer(u32).init(allocator, options.time_window_bins);
    errdefer revolutions.deinit(allocator);

    return .{
        .allocator = allocator,
        .options = options,
        .registers = registers,
        .adc = .{
            .unit = adc_unit,
            .channel = adc_channel,
        },
        .pwm = .{
            .timer = pwm_timer,
            .channel = pwm_channel,
        },
        .timer = timer,
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

pub fn deinit(self: *const Self) void {
    self.state.revolutions.deinit(self.allocator);
    self.adc.unit.deinit();
    self.pwm.timer.deinit();
    self.pwm.channel.deinit();
    c.espLogError(c.gptimer_stop(self.timer), "gptimer_stop");
    c.espLogError(c.gptimer_disable(self.timer), "gptimer_disable");
    c.espLogError(c.gptimer_del_timer(self.timer), "gptimer_del_timer");
}

pub fn run(args: ?*anyopaque) callconv(.c) void {
    const self: *Self = @alignCast(@ptrCast(args));

    std.log.info("Starting controller", .{});

    if (controller_task != null)
        std.debug.panic("Controller task already running", .{});
    controller_task = idf.xTaskGetCurrentTaskHandle();
    defer controller_task = null;

    c.espCheckError(c.gptimer_start(self.timer)) catch |err| panicErr(err);

    const control_frequency = self.options.control_frequency;
    const read_frequency = control_frequency * self.options.reads_per_bin;

    var perf_read = perf_m.Counter.init(
        self.allocator,
        "READ",
        read_frequency,
    ) catch |err| panicErr(err);
    defer perf_read.deinit();

    var perf_control = perf_m.Counter.init(
        self.allocator,
        "CONTROL",
        control_frequency,
    ) catch |err| panicErr(err);
    defer perf_control.deinit();

    var report_number: u64 = 0;
    while (true) {
        for (0..self.options.control_frequency) |_| {
            for (0..self.options.reads_per_bin) |_| {
                while (idf.ulTaskGenericNotifyTake(
                    c.tskDEFAULT_INDEX_TO_NOTIFY,
                    c.pdTRUE,
                    c.portMAX_DELAY,
                ) == 0) {}

                const read_start = perf_m.Marker.now();
                logErr(self.read_phase(), "Controller.read_phase");
                perf_read.add_sample(read_start);
            }

            const control_start = perf_m.Marker.now();
            logErr(self.control_phase(), "Controller.control_phase");
            perf_control.add_sample(control_start);
        }

        std.log.info("# REPORT {}", .{report_number});
        memory.report();
        perf_read.report();
        perf_control.report();
        perf_read.reset();
        perf_control.reset();
        report_number += 1;
    }
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

fn read_adc(self: *Self) !f32 {
    const value = try self.adc.channel.read();
    return @as(f32, @floatFromInt(value)) / adc_max;
}

fn control_phase(self: *Self) !void {
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
    _: ?*anyopaque,
) linksection(".iram1.0") callconv(.c) bool {
    var high_task_awoken: isize = 0;
    _ = idf.vTaskGenericNotifyGiveFromISR(
        controller_task,
        c.tskDEFAULT_INDEX_TO_NOTIFY,
        &high_task_awoken,
    );
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
