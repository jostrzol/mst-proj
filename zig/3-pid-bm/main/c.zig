const idf = @import("esp_idf");

const c = @cImport({
    @cInclude("esp_adc/adc_oneshot.h");
    @cInclude("driver/ledc.h");
});

pub usingnamespace c;

pub fn espCheckError(err: c.esp_err_t) idf.esp_error!void {
    try idf.espCheckError(@enumFromInt(err));
}
