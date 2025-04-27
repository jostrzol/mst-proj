const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;

const c = @import("c.zig");
const utils = @import("utils.zig");

pub const StartMarker = struct {
    cycle: sys.esp_cpu_cycle_count_t,

    pub fn now() StartMarker {
        return .{ .cycle = sys.esp_cpu_get_cycle_count() };
    }
};

pub const Counter = struct {
    const Self = @This();

    name: []const u8,
    cpu_frequency: u32,
    total_cycles: sys.esp_cpu_cycle_count_t,
    sample_count: u32,

    pub fn init(name: []const u8) !Self {
        var cpu_frequency: u32 = undefined;
        try c.espCheckError(c.esp_clk_tree_src_get_freq_hz(
            c.SOC_MOD_CLK_CPU,
            0,
            &cpu_frequency,
        ));

        return .{
            .name = name,
            .cpu_frequency = cpu_frequency,
            .total_cycles = 0,
            .sample_count = 0,
        };
    }

    pub fn add_sample(self: *Self, start: StartMarker) void {
        const end = sys.esp_cpu_get_cycle_count();
        const cycles = end - start.cycle;

        self.total_cycles += cycles;
        self.sample_count += 1;
    }

    pub fn report(self: *const Self) void {
        const cycles_avg = @as(f64, @floatFromInt(self.total_cycles)) / @as(f64, @floatFromInt(self.sample_count));
        const time_ms = cycles_avg / @as(f64, @floatFromInt(self.cpu_frequency)) * 1e6;
        std.log.info(
            "Performance counter {s}: {d:.3} us = {d:.0} cycles ({} sampl.)",
            .{ self.name, time_ms, cycles_avg, self.sample_count },
        );
    }

    pub fn reset(self: *Self) void {
        self.total_cycles = 0;
        self.sample_count = 0;
    }
};
