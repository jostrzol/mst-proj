const idf = @import("esp_idf");

const c = @import("c.zig").c;

pub const Unit = struct {
    handle: c.adc_oneshot_unit_handle_t,

    pub fn init(id: c.adc_unit_t) idf.esp_error!Unit {
        const config = c.adc_oneshot_unit_init_cfg_t{ .unit_id = id };
        var handle: c.adc_oneshot_unit_handle_t = undefined;
        try cEspCheckError(c.adc_oneshot_new_unit(&config, &handle));
        return .{ .handle = handle };
    }

    pub fn channel(
        self: Unit,
        _channel: c.adc_channel_t,
        config: *const c.adc_oneshot_chan_cfg_t,
    ) idf.esp_error!Channel {
        const err = c.adc_oneshot_config_channel(self.handle, _channel, config);
        try cEspCheckError(err);
        return .{ .unit = self, .handle = _channel };
    }
};

pub const Channel = struct {
    unit: Unit,
    handle: c.adc_channel_t,

    pub fn read(self: *const Channel) idf.esp_error!u16 {
        var value: c_int = undefined;
        try cEspCheckError(c.adc_oneshot_read(self.unit.handle, self.handle, &value));
        return @as(u16, @intCast(value));
    }
};

fn cEspCheckError(err: c.esp_err_t) idf.esp_error!void {
    try idf.espCheckError(@enumFromInt(err));
}
