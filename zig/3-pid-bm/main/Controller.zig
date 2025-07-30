const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;
const Allocator = std.mem.Allocator;

const Registers = @import("Registers.zig");
const RingBuffer = @import("ring_buffer.zig").RingBuffer;
const perf_m = @import("perf.zig");
const memory = @import("memory.zig");
const c = @import("c.zig");
const utils = @import("utils.zig");
const logErr = utils.logErr;
const panicErr = utils.panicErr;

const adc_unit = c.ADC_UNIT_1;
const adc_channel = c.ADC_CHANNEL_4;
const adc_bitwidth = c.ADC_BITWIDTH_9;
const adc_max = (1 << adc_bitwidth) - 1;
const adc_channel_config = c.adc_oneshot_chan_cfg_t{
    .atten = c.ADC_ATTEN_DB_12,
    .bitwidth = adc_bitwidth,
};

const pwm_timer = c.LEDC_TIMER_0;
const pwm_speed_mode = c.LEDC_LOW_SPEED_MODE;
const pwm_channel = c.LEDC_CHANNEL_0;
const pwm_bitwidth = c.LEDC_TIMER_13_BIT;
const pwm_duty_max = (1 << pwm_bitwidth) - 1;
const pwm_timer_config = c.ledc_timer_config_t{
    .timer_num = pwm_timer,
    .speed_mode = pwm_speed_mode,
    .duty_resolution = pwm_bitwidth,
    .freq_hz = 1000,
    .clk_cfg = c.LEDC_AUTO_CLK,
};
const pwm_timer_deconfig = c.ledc_timer_config_t{
    .timer_num = pwm_timer,
    .deconfigure = true,
};
const pwm_channel_config = c.fixed.ledc_channel_config_t{
    .timer_sel = pwm_timer,
    .channel = pwm_channel,
    .speed_mode = pwm_speed_mode,
    .intr_type = c.LEDC_INTR_DISABLE,
    .gpio_num = c.GPIO_NUM_5,
    .duty = 0,
    .hpoint = 0,
};

const pwm_min = 0.1;
const pwm_max = 1.0;
const limit_min_deadzone = 0.001;

const timer_frequency = 1000000; // period = 1us
const control_iters_per_perf_report = 10;

var controller_task: sys.TaskHandle_t = null;

allocator: Allocator,
options: InitOptions,
registers: *Registers,
adc: c.adc_oneshot_unit_handle_t,
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
    const revolutions = try RingBuffer(u32).init(allocator, options.time_window_bins);
    errdefer revolutions.deinit(allocator);

    var adc: c.adc_oneshot_unit_handle_t = undefined;
    try c.espCheckError(c.adc_oneshot_new_unit(&.{ .unit_id = adc_unit }, &adc));
    errdefer c.espLogError(c.adc_oneshot_del_unit(adc), "adc_oneshot_del_unit");

    try c.espCheckError(c.adc_oneshot_config_channel(adc, adc_channel, &adc_channel_config));

    try c.espCheckError(c.ledc_timer_config(&pwm_timer_config));
    errdefer c.espLogError(c.ledc_timer_config(&pwm_timer_deconfig), "ledc_timer_config");

    try c.espCheckError(c.fixed.ledc_channel_config(&pwm_channel_config));
    errdefer c.espLogError(c.ledc_stop(pwm_speed_mode, pwm_channel, 0), "ledc_stop");

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

    return .{
        .allocator = allocator,
        .options = options,
        .registers = registers,
        .adc = adc,
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
    c.espLogError(c.gptimer_stop(self.timer), "gptimer_stop");
    c.espLogError(c.gptimer_disable(self.timer), "gptimer_disable");
    c.espLogError(c.gptimer_del_timer(self.timer), "gptimer_del_timer");
    c.espLogError(c.ledc_stop(pwm_speed_mode, pwm_channel, 0), "ledc_stop");
    c.espLogError(c.ledc_timer_config(&pwm_timer_deconfig), "ledc_timer_config");
    c.espLogError(c.adc_oneshot_del_unit(self.adc), "adc_oneshot_del_unit");
    self.state.revolutions.deinit(self.allocator);
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
                logErr(self.readPhase(), "Controller.readPhase");
                perf_read.addSample(read_start);
            }

            const control_start = perf_m.Marker.now();
            logErr(self.controlPhase(), "Controller.controlPhase");
            perf_control.addSample(control_start);
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

fn readPhase(self: *Self) !void {
    const value = try self.readAdc();

    if (!self.state.is_close and value < self.options.revolution_treshold_close) {
        // gone close
        self.state.is_close = true;
        self.state.revolutions.back().* += 1;
    } else if (self.state.is_close and value > self.options.revolution_treshold_far) {
        // gone far
        self.state.is_close = false;
    }
}

fn readAdc(self: *Self) !f32 {
    var value: c_int = undefined;
    try c.espCheckError(c.adc_oneshot_read(self.adc, adc_channel, &value));
    return @as(f32, @floatFromInt(value)) / adc_max;
}

fn controlPhase(self: *Self) !void {
    const frequency = self.calculateFrequency();
    try self.state.revolutions.push(0);
    std.log.debug("frequency: {d:.2} Hz", .{frequency});

    const control_params = self.readControlParams();

    const control = self.calculateControl(&control_params, frequency);

    const control_signal_limited = limit(control.signal, pwm_min, pwm_max);
    std.log.debug("control signal limited: {d:.2}", .{control_signal_limited});

    try setDutyCycle(control_signal_limited);

    self.writeRegisters(frequency, control_signal_limited);

    self.state.feedback = control.feedback;
}

fn calculateFrequency(self: *Self) f32 {
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

fn readControlParams(self: *Self) ControlParams {
    const holding = self.registers.holding;
    return .{
        .target_frequency = holding.target_frequency.toF32(),
        .proportional_factor = holding.proportional_factor.toF32(),
        .integration_time = holding.integration_time.toF32(),
        .differentiation_time = holding.differentiation_time.toF32(),
    };
}

fn calculateControl(
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

fn setDutyCycle(value: f32) !void {
    const duty_cycle: u32 = @intFromFloat(value * pwm_duty_max);
    try c.espCheckError(c.ledc_set_duty(pwm_speed_mode, pwm_channel, duty_cycle));
    try c.espCheckError(c.ledc_update_duty(pwm_speed_mode, pwm_channel));
}

fn finiteOrZero(value: f32) f32 {
    return if (std.math.isFinite(value)) 0 else value;
}

fn limit(value: f32, min: f32, max: f32) f32 {
    if (value < limit_min_deadzone)
        return 0;

    const result = value + min;
    return if (result < min) min else if (result > max) max else result;
}

fn writeRegisters(self: *Self, frequency: f32, control_signal: f32) void {
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
