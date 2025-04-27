const std = @import("std");
const idf = @import("esp_idf");

const c = @cImport({
    @cInclude("esp_clk_tree.h");
    @cInclude("soc/clk_tree_defs.h");
});

pub usingnamespace c;

pub fn espCheckError(err: c.esp_err_t) idf.esp_error!void {
    try idf.espCheckError(@enumFromInt(err));
}
