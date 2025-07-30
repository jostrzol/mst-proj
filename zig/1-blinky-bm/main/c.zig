const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;

const c = @cImport({
    @cInclude("esp_clk_tree.h");
    @cInclude("soc/clk_tree_defs.h");
});

pub usingnamespace c;

pub fn espCheckError(err: c.esp_err_t) idf.esp_error!void {
    try idf.espCheckError(@enumFromInt(err));
}

pub fn rtosCheckError(result: sys.BaseType_t) !void {
    if (result != 1) return error.ErrorRtos;
}
