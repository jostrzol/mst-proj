const std = @import("std");

const PWM_ROOT_PATH = "/sys/class/pwm";
const MAX_CHANNELS = 8;
const WHITESPACE = " \t\n\r\x00";

const PathZ = [std.fs.MAX_PATH_BYTES:0]u8;

fn pathMakeZ(comptime fmt: []const u8, args: anytype) std.fmt.BufPrintError!PathZ {
    var buf: PathZ = undefined;
    _ = try std.fmt.bufPrintZ(&buf, fmt, args);
    return buf;
}

pub const Chip = struct {
    number: u8,
    channels: [MAX_CHANNELS]?Channel,
    npwm_cached: ?u8 = null,

    pub fn init(chip_nr: u8) !Chip {
        return .{
            .number = chip_nr,
            .channels = .{null} ** MAX_CHANNELS,
        };
    }

    pub fn deinit(self: *Chip) void {
        for (self.channels) |maybe_chan| {
            var chan = maybe_chan orelse continue;
            chan.deinit();
        }
    }

    pub fn npwm(self: *Chip) !u8 {
        if (self.npwm_cached) |value| return value;
        const npwm_path = try self.path("/npwm", .{});
        const value = try readUnsigned(u8, &npwm_path, 8, 10);
        self.npwm_cached = value;
        return value;
    }

    pub fn channel(self: *Chip, channel_nr: u8) !*Channel {
        if (channel_nr > try self.npwm()) return error.ChannelOutOfRange;

        if (self.channels[channel_nr]) |_| return &self.channels[channel_nr].?;

        self.channels[channel_nr] = try Channel.init(self, channel_nr);
        return &self.channels[channel_nr].?;
    }

    fn path(
        self: *const Chip,
        comptime fmt: []const u8,
        args: anytype,
    ) std.fmt.BufPrintError!PathZ {
        return pathMakeZ(PWM_ROOT_PATH ++ "/pwmchip{}" ++ fmt, .{self.number} ++ args);
    }
};

pub const Channel = struct {
    chip: *Chip,
    number: u8,
    period_ns_cached: ?u64 = null,

    fn init(chip: *Chip, channel_nr: u8) !Channel {
        var channel = Channel{ .chip = chip, .number = channel_nr };
        try channel.export_();
        return channel;
    }

    fn isExported(self: *const Channel) !bool {
        const root_path = try self.path("", .{});
        return doesPathExist(&root_path);
    }

    fn export_(self: *Channel) !void {
        if (try self.isExported()) return;
        const export_path = try self.chip.path("/export", .{});
        try writeValue(&export_path, self.number);
    }

    fn deinit(self: *Channel) void {
        self.chip.channels[self.number] = null;
        self.unexport() catch std.log.err("couldn't unexport PWM channel\n", .{});
    }

    fn unexport(self: *Channel) !void {
        if (!try self.isExported()) return;
        const unexport_path = try self.chip.path("/unexport", .{});
        try writeValue(&unexport_path, self.number);
    }

    pub fn setFrequency(self: *Channel, frequency: u64) !void {
        const period_ns = std.time.ns_per_s / frequency;
        try self.setPeriodNs(period_ns);
    }

    pub fn setPeriodNs(self: *Channel, period_ns: u64) !void {
        const period_path = try self.path("/period", .{});
        std.log.debug("period: {}\n", .{period_ns});
        try writeValue(&period_path, period_ns);
        self.period_ns_cached = period_ns;
    }

    pub fn setDutyCycleRatio(self: *Channel, duty_cycle_ratio: f32) !void {
        const period = self.period_ns_cached orelse return error.PeriodNotSet;
        const duty_cycle_ns = @as(f32, @floatFromInt(period)) * duty_cycle_ratio;
        try self.setDutyCycle(@intFromFloat(duty_cycle_ns));
    }

    pub fn setDutyCycle(self: *Channel, duty_cycle_ns: u64) !void {
        const duty_cycle_path = try self.path("/duty_cycle", .{});
        std.log.debug("duty cycle: {}\n", .{duty_cycle_ns});
        try writeValue(&duty_cycle_path, duty_cycle_ns);
    }

    pub fn setEnable(self: *Channel, enable: bool) !void {
        const enable_path = try self.path("/enable", .{});
        try writeValue(&enable_path, @intFromBool(enable));
    }

    fn path(
        self: *const Channel,
        comptime fmt: []const u8,
        args: anytype,
    ) std.fmt.BufPrintError!PathZ {
        return self.chip.path("/pwm{}" ++ fmt, .{self.number} ++ args);
    }
};

fn readUnsigned(comptime T: type, file_path: [*:0]const u8, comptime bufsize: u8, base: u8) !T {
    const line = try readAll(file_path, bufsize);
    var tokens = std.mem.tokenizeAny(u8, &line, WHITESPACE);
    const first_token = tokens.next() orelse return error.Empty;
    return try std.fmt.parseUnsigned(T, first_token, base);
}

fn readAll(file_path: [*:0]const u8, comptime bufsize: u8) ![bufsize:0]u8 {
    const file = try std.fs.openFileAbsoluteZ(file_path, .{});
    defer file.close();

    var buffer: [bufsize:0]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);
    if (bytes_read == bufsize) return error.BufferTooSmall;

    return buffer;
}

fn writeValue(file_path: [*:0]const u8, value: anytype) !void {
    try print(file_path, "{}", .{value});
}

fn print(file_path: [*:0]const u8, comptime format: []const u8, args: anytype) !void {
    const file = try std.fs.openFileAbsoluteZ(file_path, .{ .mode = .write_only });
    defer file.close();

    const writer = std.fs.File.writer(file);
    try writer.print(format, args);
}

fn doesPathExist(path: [*:0]const u8) bool {
    return if (std.fs.accessAbsoluteZ(path, .{})) |_| true else |_| false;
}
