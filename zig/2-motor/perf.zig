const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @import("c.zig");

pub const Marker = struct {
    time_ns: u64,

    pub fn now() Marker {
        var time: c.struct_timespec = undefined;
        const res = c.clock_gettime(c.CLOCK_THREAD_CPUTIME_ID, &time);
        const time_ns = if (res != 0) 0 else ns_from_timespec(&time);
        return Marker{ .time_ns = time_ns };
    }
};

pub const Counter = struct {
    const Self = @This();

    name: []const u8,
    samples_ns: std.ArrayList(u32),

    // Panics instead of errors, not to influence CCN metric
    pub fn init(allocator: Allocator, name: []const u8, length: usize) Self {
        var resolution: c.struct_timespec = undefined;
        const res = c.clock_getres(c.CLOCK_THREAD_CPUTIME_ID, &resolution);
        if (res != 0) {
            const err = std.posix.unexpectedErrno(std.posix.errno(res));
            std.debug.panic("Counter clock resolution: {}", .{err});
        }

        std.log.info(
            "Performance counter {s}, cpu resolution: {} ns",
            .{ name, ns_from_timespec(&resolution) },
        );

        const samples_ns = std.ArrayList(u32).initCapacity(allocator, length) catch |err| {
            std.debug.panic("Counter buffer init: {}", .{err});
        };

        return .{
            .name = name,
            .samples_ns = samples_ns,
        };
    }

    pub fn deinit(self: *const Counter) void {
        self.samples_ns.deinit();
    }

    pub fn add_sample(self: *Self, start: Marker) void {
        const end = Marker.now();
        const diff = end.time_ns - start.time_ns;

        if (self.samples_ns.items.len >= self.samples_ns.capacity) {
            std.log.err("perf.Counter.add_sample: buffer is full", .{});
            return;
        }

        const sample = self.samples_ns.addOneAssumeCapacity();
        sample.* = @truncate(diff);
    }

    pub fn report(self: *const Self) void {
        std.log.info(
            "Performance counter {s}: {}",
            .{ self.name, SampleFormatter{ .data = self.samples_ns.items } },
        );
    }

    const SampleFormatter = std.fmt.Formatter(formatSamples);

    fn formatSamples(
        data: []const u32,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.writeAll("[");
        for (data, 0..) |sample, i| {
            try std.fmt.format(writer, "{d}", .{sample / 1000});
            if (i < data.len - 1)
                try writer.writeAll(",");
        }
        try writer.writeAll("] us");
    }

    pub fn reset(self: *Self) void {
        self.samples_ns.clearRetainingCapacity();
    }
};

fn ns_from_timespec(timespec: *const c.struct_timespec) u64 {
    const tv_sec: u64 = @intCast(timespec.tv_sec);
    const tv_nsec: u64 = @intCast(timespec.tv_nsec);
    return tv_nsec + tv_sec * std.time.ns_per_s;
}
