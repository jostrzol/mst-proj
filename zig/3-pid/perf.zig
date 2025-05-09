const std = @import("std");

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
    total_time_ns: u64,
    sample_count: u32,

    pub fn init(name: []const u8) !Self {
        var resolution: c.struct_timespec = undefined;
        const res = c.clock_getres(c.CLOCK_THREAD_CPUTIME_ID, &resolution);
        if (res != 0)
            return std.posix.unexpectedErrno(std.posix.errno(res));

        std.log.info(
            "Performance counter {s}, cpu resolution: {} ns",
            .{ name, ns_from_timespec(&resolution) },
        );

        return .{
            .name = name,
            .total_time_ns = 0,
            .sample_count = 0,
        };
    }

    pub fn add_sample(self: *Self, start: Marker) void {
        const end = Marker.now();
        const cycles = end.time_ns - start.time_ns;

        self.total_time_ns += cycles;
        self.sample_count += 1;
    }

    pub fn report(self: *const Self) void {
        const total_time_ns: f64 = @floatFromInt(self.total_time_ns);
        const sample_count: f64 = @floatFromInt(self.sample_count);
        const time_us = total_time_ns / 1000.0 / sample_count;
        std.log.info(
            "Performance counter {s}: {d:.3} us ({} sampl.)",
            .{ self.name, time_us, self.sample_count },
        );
    }

    pub fn reset(self: *Self) void {
        self.total_time_ns = 0;
        self.sample_count = 0;
    }
};

fn ns_from_timespec(timespec: *const c.struct_timespec) u64 {
    return @intCast(timespec.tv_nsec + timespec.tv_sec * std.time.ns_per_s);
}
