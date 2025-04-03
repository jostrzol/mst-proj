const errors = @import("error");

const c = @cImport({
    @cInclude("esp_adc/adc_oneshot.h");
});
//
pub const unit_t = enum(c_int) {
    ADC_UNIT_1 = c.ADC_UNIT_1,
    ADC_UNIT_2 = c.ADC_UNIT_2,
};

pub const oneshot_unit_init_cfg_t = c.adc_oneshot_unit_init_cfg_t;

pub const Unit = struct {
    handle: c.adc_oneshot_unit_handle_t,

    pub fn init(config: *const c.adc_oneshot_unit_init_cfg_t) Unit!void {
        var handle: c.adc_oneshot_unit_handle_t = undefined;
        try errors.espCheckError(c.adc_oneshot_new_unit(config, &handle));
        return .{ .handle = handle };
    }
};
