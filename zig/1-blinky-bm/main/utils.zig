const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;

pub fn rtosCheckError(result: sys.BaseType_t) !void {
    if (result != 1) return error.ErrorRtos;
}
