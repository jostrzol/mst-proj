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
// timer: struct {
//     semaphore_buf: sys.StaticSemaphore_t,
//     semaphore: sys.SemaphoreHandle_t,
//     handle: c.gptimer_handle_t,
// },
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
    };
}

pub fn deinit(self: *const Self) !void {
    _ = self;
}
