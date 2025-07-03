const std = @import("std");
const idf = @import("esp_idf");
const Allocator = std.mem.Allocator;
const sys = idf.sys;

const c = @import("c.zig");
const utils = @import("utils.zig");

pub const Marker = struct {
    cycle: sys.esp_cpu_cycle_count_t,

    pub fn now() Marker {
        return .{ .cycle = sys.esp_cpu_get_cycle_count() };
    }
};

pub const Counter = struct {
    const Self = @This();

    name: []const u8,
    cpu_frequency: u32,
    samples: std.ArrayList(sys.esp_cpu_cycle_count_t),

    pub fn init(allocator: Allocator, name: []const u8, length: usize) !Self {
        var cpu_frequency: u32 = undefined;
        try c.espCheckError(c.esp_clk_tree_src_get_freq_hz(
            c.SOC_MOD_CLK_CPU,
            0,
            &cpu_frequency,
        ));

        const samples = try std.ArrayList(sys.esp_cpu_cycle_count_t).initCapacity(allocator, length);

        return .{
            .name = name,
            .cpu_frequency = cpu_frequency,
            .samples = samples,
        };
    }

    pub fn deinit(self: *const Self) void {
        self.samples.deinit();
    }

    pub fn add_sample(self: *Self, start: Marker) void {
        const end = Marker.now();
        const diff = end.cycle - start.cycle;

        if (self.samples.items.len >= self.samples.capacity) {
            std.log.err("Counter.add_sample fail: buffer is full", .{});
            return;
        }

        const sample = self.samples.addOneAssumeCapacity();
        sample.* = diff;
    }

    pub fn report(self: *const Self) void {
        std.log.info(
            "Performance counter {s}: {}",
            .{ self.name, SampleFormatter{ .data = self } },
        );
    }

    const SampleFormatter = std.fmt.Formatter(formatSamples);

    fn formatSamples(
        data: *const Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const scale = 1e6 / @as(f32, @floatFromInt(data.cpu_frequency));
        const samples = data.samples.items;

        try writer.writeAll("[");
        for (samples, 0..) |sample, i| {
            const value = @as(f32, @floatFromInt(sample)) * scale;
            try std.fmt.format(writer, "{d:.2}", .{value});
            if (i < samples.len - 1)
                try writer.writeAll(",");
        }
        try writer.writeAll("] us");
    }

    pub fn reset(self: *Self) void {
        self.samples.clearRetainingCapacity();
    }
};
