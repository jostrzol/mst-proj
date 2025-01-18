const std = @import("std");

/// Path to root of sysfs PWM driver
const PWM_ROOT_PATH = "/sys/class/pwm";
/// Maximum number of channels handled by the library
const MAX_CHANNELS = 8;
/// Maximum length of path in sysfs PWM driver structure handled by the library
const MAX_PWM_PATH_BYTES = 128;
/// Characters considered whitespace when reading from the sysfs PWM driver
const WHITESPACE = [_]u8{ ' ', '\t', '\n', '\r', '\x00' };

/// Buffer for path in sysfs PWM driver structure
const PathPwmBuffer = [MAX_PWM_PATH_BYTES]u8;

pub const Chip = struct {
    const Files = struct {
        export_: ?std.fs.File = null,
        unexport: ?std.fs.File = null,
        // npwn doesn't need to be kept open, as its value
        // is cached in npwm_cached
    };

    number: u8,
    channels: [MAX_CHANNELS]?Channel,

    npwm_cached: ?u8 = null,
    files: Files = .{},

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
        inline for (std.meta.fields(Files)) |f| {
            const maybe_file = @field(self.files, f.name);
            if (maybe_file) |file_| file_.close();
        }
    }

    pub fn npwm(self: *Chip) !u8 {
        if (self.npwm_cached) |value| return value;

        var buffer: PathPwmBuffer = undefined;
        const path_ = try self.path(&buffer, "/npwm", .{});
        const file_ = try std.fs.openFileAbsolute(path_, .{ .mode = .read_only });
        defer file_.close();

        const value = try readInt(u8, 8, file_, 10);
        self.npwm_cached = value;
        return value;
    }

    pub fn channel(self: *Chip, channel_nr: u8) !*Channel {
        if (channel_nr > try self.npwm()) return error.ChannelOutOfRange;

        if (self.channels[channel_nr]) |_| return &self.channels[channel_nr].?;

        self.channels[channel_nr] = try Channel.init(self, channel_nr);
        return &self.channels[channel_nr].?;
    }

    fn export_(self: *Chip, channel_nr: u8) !void {
        const file_ = try self.file(.export_, .{ .mode = .write_only });
        try file_.writer().print("{}", .{channel_nr});
    }

    fn unexport(self: *Chip, channel_nr: u8) !void {
        const file_ = try self.file(.unexport, .{ .mode = .write_only });
        try file_.writer().print("{}", .{channel_nr});
    }

    fn file(
        self: *Chip,
        comptime location: std.meta.FieldEnum(Files),
        flags: std.fs.File.OpenFlags,
    ) !std.fs.File {
        const name = @tagName(location);
        if (@field(self.files, name)) |file_| return file_;

        var buffer: PathPwmBuffer = undefined;
        const path_ = try self.path(&buffer, "/" ++ stripUnderscore(name), .{});
        const file_ = try std.fs.openFileAbsolute(path_, flags);
        @field(self.files, name) = file_;
        return file_;
    }

    fn path(
        self: *const Chip,
        buffer: []u8,
        comptime fmt: []const u8,
        args: anytype,
    ) std.fmt.BufPrintError![]u8 {
        const buf = try std.fmt.bufPrint(
            buffer,
            PWM_ROOT_PATH ++ "/pwmchip{}" ++ fmt,
            .{self.number} ++ args,
        );
        return buf;
    }
};

pub const Channel = struct {
    const Files = struct {
        period: ?std.fs.File = null,
        duty_cycle: ?std.fs.File = null,
        enable: ?std.fs.File = null,
    };

    chip: *Chip,
    number: u8,

    period_ns_cached: ?u64 = null,
    files: Files = .{},

    fn init(chip: *Chip, channel_nr: u8) !Channel {
        var channel = Channel{ .chip = chip, .number = channel_nr };
        try channel.export_();
        return channel;
    }

    fn export_(self: *Channel) !void {
        if (try self.isExported()) return;
        try self.chip.export_(self.number);
    }

    fn deinit(self: *Channel) void {
        self.unexport() catch std.log.err("couldn't unexport PWM channel\n", .{});
        inline for (std.meta.fields(Files)) |f| {
            const maybe_file = @field(self.files, f.name);
            if (maybe_file) |file_| file_.close();
        }
    }

    fn unexport(self: *Channel) !void {
        if (!try self.isExported()) return;
        try self.chip.unexport(self.number);
    }

    fn isExported(self: *const Channel) !bool {
        var buffer: PathPwmBuffer = undefined;
        const root_path = try self.path(&buffer, "", .{});
        return doesPathExist(root_path);
    }

    pub fn setParameters(self: *Channel, parameters: struct {
        frequency: u64,
        duty_cycle_ratio: f32,
    }) !void {
        const period_ns = std.time.ns_per_s / parameters.frequency;
        const duty_cycle_ns = @as(f32, @floatFromInt(period_ns)) * parameters.duty_cycle_ratio;
        try self.setPeriodNs(period_ns);
        try self.setDutyCycleNs(@intFromFloat(duty_cycle_ns));
    }

    pub fn setPeriodNs(self: *Channel, period_ns: u64) !void {
        if (period_ns == self.period_ns_cached) return;

        const file_ = try self.file(.period, .{ .mode = .read_write });
        try file_.writer().print("{}", .{period_ns});
        self.period_ns_cached = period_ns;
    }

    pub fn getPeriodNs(self: *Channel) !u64 {
        const file_ = try self.file(.period, .{ .mode = .read_write });
        try file_.seekTo(0);
        return try readInt(u64, 16, file_, 10);
    }

    pub fn setDutyCycleNs(self: *Channel, duty_cycle_ns: u64) !void {
        const file_ = try self.file(.duty_cycle, .{ .mode = .read_write });
        try file_.writer().print("{}", .{duty_cycle_ns});
    }

    pub fn getDutyCycleNs(self: *Channel) !u64 {
        const file_ = try self.file(.duty_cycle, .{ .mode = .read_write });
        try file_.seekTo(0);
        return try readInt(u64, 16, file_, 10);
    }

    pub fn enable(self: *Channel) !void {
        try self.setEnable(true);
    }

    pub fn disable(self: *Channel) !void {
        try self.setEnable(false);
    }

    fn setEnable(self: *Channel, value: bool) !void {
        const file_ = try self.file(.enable, .{ .mode = .read_write });
        _ = try file_.writer().print("{}", .{@intFromBool(value)});
    }

    pub fn isEnabled(self: *Channel) !bool {
        const file_ = try self.file(.enable, .{ .mode = .read_write });
        try file_.seekTo(0);
        return try readInt(u1, 8, file_, 10) == 1;
    }

    fn file(
        self: *Channel,
        comptime location: std.meta.FieldEnum(Files),
        flags: std.fs.File.OpenFlags,
    ) !std.fs.File {
        const name = @tagName(location);
        if (@field(self.files, name)) |file_| return file_;

        var buffer: PathPwmBuffer = undefined;
        const path_ = try self.path(&buffer, "/" ++ name, .{});
        std.debug.print("Channel.file: {s}; {}\n", .{ path_, flags });
        const file_ = try std.fs.openFileAbsolute(path_, flags);
        @field(self.files, name) = file_;
        return file_;
    }

    fn path(
        self: *const Channel,
        buffer: []u8,
        comptime fmt: []const u8,
        args: anytype,
    ) std.fmt.BufPrintError![]u8 {
        return try self.chip.path(
            buffer,
            "/pwm{}" ++ fmt,
            .{self.number} ++ args,
        );
    }
};

fn readInt(comptime T: type, comptime bufsize: u8, file: std.fs.File, base: u8) !T {
    var buffer: [bufsize:0]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);
    if (bytes_read == bufsize) return error.BufferTooSmall;

    var tokens = std.mem.tokenizeAny(u8, buffer[0..bytes_read], &WHITESPACE);
    const first_token = tokens.next() orelse return error.Empty;
    return try std.fmt.parseInt(T, first_token, base);
}

fn stripUnderscore(str: []const u8) []const u8 {
    if (!std.mem.endsWith(u8, str, "_")) return str;
    return str[0 .. str.len - 1];
}

fn doesPathExist(path: []const u8) bool {
    return if (std.fs.accessAbsolute(path, .{})) |_| true else |_| false;
}
