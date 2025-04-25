const idf = @import("esp_idf");

const c = @import("c.zig");

pub const Unit = struct {
    handle: c.adc_oneshot_unit_handle_t,

    pub fn init(id: c.adc_unit_t) idf.esp_error!Unit {
        const config = c.adc_oneshot_unit_init_cfg_t{ .unit_id = id };
        var handle: c.adc_oneshot_unit_handle_t = undefined;
        try c.espCheckError(c.adc_oneshot_new_unit(&config, &handle));
        return .{ .handle = handle };
    }

    pub fn deinit(self: *const Unit) void {
        c.espLogError(c.adc_oneshot_del_unit(self.handle));
    }

    pub fn channel(
        self: Unit,
        id: c.adc_channel_t,
        config: *const c.adc_oneshot_chan_cfg_t,
    ) idf.esp_error!Channel {
        const err = c.adc_oneshot_config_channel(self.handle, id, config);
        try c.espCheckError(err);
        return .{ .unit = self, .id = id };
    }
};

pub const Channel = struct {
    unit: Unit,
    id: c.adc_channel_t,

    pub fn read(self: *const Channel) idf.esp_error!u16 {
        var value: c_int = undefined;
        try c.espCheckError(c.adc_oneshot_read(self.unit.handle, self.id, &value));
        return @as(u16, @intCast(value));
    }
};
