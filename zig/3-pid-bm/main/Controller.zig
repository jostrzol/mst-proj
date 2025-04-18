const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;

const Registers = @import("Registers.zig");
const RingBuffer = @import("ring_buffer.zig").RingBuffer;
const adc_t = @import("adc.zig");
const pwm_t = @import("pwm.zig");
const c = @import("c.zig");

const adc_bitwidth = c.ADC_BITWIDTH_9;
const adc_max = (1 << adc_bitwidth) - 1;

const pwm_bitwidth = c.LEDC_TIMER_13_BIT;
const pwm_max = (1 << pwm_bitwidth) - 1;

const timer_frequency: u32 = 1000000; // period = 1us

opts: InitOpts,
registers: *Registers,
adc: struct {
    unit: adc_t.Unit,
    channel: adc_t.Channel,
},
pwm: struct {
    timer: pwm_t.Timer,
    channel: pwm_t.Channel,
},
timer: struct {
    semaphore: sys.QueueHandle_t,
    handle: c.gptimer_handle_t,
},
// interval: struct {
//     rotate_once_s: f32,
//     rotate_all_s: f32,
// },
// state: struct {
//     revolutions: RingBuffer(u32),
//     is_close: bool,
//     feedback: Feedback,
// },

pub const InitOpts = struct {
    frequency: u64,
    revolution_treshold_close: f32,
    revolution_treshold_far: f32,
    revolution_bins: usize,
    reads_per_bin: usize,
};

const Feedback = struct {
    delta: f32,
    integration_component: f32,
};

const Self = @This();

pub fn init(registers: *Registers, opts: InitOpts) !Self {
    const adc_unit = try adc_t.Unit.init(c.ADC_UNIT_1);
    const adc_channel = try adc_unit.channel(c.ADC_CHANNEL_4, &.{
        .atten = c.ADC_ATTEN_DB_12,
        .bitwidth = adc_bitwidth,
    });

    const pwm_timer = try pwm_t.Timer.init(&.{
        .speed_mode = c.LEDC_LOW_SPEED_MODE,
        .duty_resolution = c.LEDC_TIMER_13_BIT,
        .timer_num = c.LEDC_TIMER_0,
        .freq_hz = 1000,
        .clk_cfg = c.LEDC_AUTO_CLK,
    });
    const pwm_channel = try pwm_timer.channel(c.LEDC_CHANNEL_0, c.GPIO_NUM_5);

    const timer_semaphore = idf.xSemaphoreCreateBinary() orelse return error.ErrorInvalidState;

    var timer: c.gptimer_handle_t = undefined;
    try c.espCheckError(gptimer_new_timer(
        &.{
            .clk_src = c.GPTIMER_CLK_SRC_DEFAULT,
            .direction = c.GPTIMER_COUNT_UP,
            .resolution_hz = timer_frequency,
        },
        &timer,
    ));
    try c.espCheckError(c.gptimer_register_event_callbacks(
        timer,
        &.{ .on_alarm = onTimerFired },
        timer_semaphore,
    ));

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
    };
}

pub fn deinit(self: *const Self) !void {
    _ = self;
}

pub fn run(args: ?*anyopaque) callconv(.c) void {
    const self: *Self = @alignCast(@ptrCast(args));

    while (true) {
        _ = idf.xSemaphoreTake(self.timer.semaphore, std.math.maxInt(u32));
    }
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
