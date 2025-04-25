const idf = @import("esp_idf");

const c = @import("c.zig");

pub const Timer = struct {
    id: c.ledc_timer_t,
    speed_mode: c.ledc_mode_t,

    pub fn init(config: *const c.ledc_timer_config_t) !Timer {
        try c.espCheckError(c.ledc_timer_config(config));
        return .{
            .id = config.timer_num,
            .speed_mode = config.speed_mode,
        };
    }

    pub fn deinit(self: *const Timer) void {
        c.espLogError(c.ledc_timer_config(&.{
            .timer_num = self.id,
            .deconfigure = true,
        }));
    }

    pub fn channel(self: *const Timer, id: c.ledc_channel_t, gpio: c_int) !Channel {
        const config = ledc_channel_config_t{
            .timer_sel = self.id,
            .speed_mode = self.speed_mode,
            .intr_type = c.LEDC_INTR_DISABLE,
            .channel = id,
            .gpio_num = gpio,
            .duty = 0,
            .hpoint = 0,
        };
        try c.espCheckError(ledc_channel_config(@ptrCast(&config)));
        return .{ .timer = self, .id = id };
    }
};

pub const Channel = struct {
    timer: *const Timer,
    id: c.ledc_channel_t,

    pub fn set_duty_cycle(self: *const Channel, duty_cycle: u32) !void {
        try c.espCheckError(c.ledc_set_duty(self.timer.speed_mode, self.id, duty_cycle));
        try c.espCheckError(c.ledc_update_duty(self.timer.speed_mode, self.id));
    }

    pub fn deinit(self: *const Channel) void {
        c.espLogError(c.ledc_stop(self.timer.speed_mode, self.id, 0));
    }
};

// Needed, because c-translate cannot properly translate flags
pub const ledc_channel_config_t = extern struct {
    const flags_t = packed struct {
        output_invert: bool,
        _: u31,
    };

    gpio_num: c_int = @import("std").mem.zeroes(c_int),
    speed_mode: c.ledc_mode_t = @import("std").mem.zeroes(c.ledc_mode_t),
    channel: c.ledc_channel_t = @import("std").mem.zeroes(c.ledc_channel_t),
    intr_type: c.ledc_intr_type_t = @import("std").mem.zeroes(c.ledc_intr_type_t),
    timer_sel: c.ledc_timer_t = @import("std").mem.zeroes(c.ledc_timer_t),
    duty: u32 = @import("std").mem.zeroes(u32),
    hpoint: c_int = @import("std").mem.zeroes(c_int),
    sleep_mode: c.ledc_sleep_mode_t = @import("std").mem.zeroes(c.ledc_sleep_mode_t),
    flags: flags_t = @import("std").mem.zeroes(flags_t),
};

extern fn ledc_channel_config(ledc_conf: ?*const ledc_channel_config_t) c.esp_err_t;
