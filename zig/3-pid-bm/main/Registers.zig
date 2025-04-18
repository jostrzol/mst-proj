const std = @import("std");

const Self = @This();

input: Input = .{},
holding: Holding = .{},

pub const Input = packed struct {
    frequency: FloatCDAB = FloatCDAB.zero,
    control_signal: FloatCDAB = FloatCDAB.zero,
};

pub const Holding = packed struct {
    target_frequency: FloatCDAB = FloatCDAB.zero,
    proportional_factor: FloatCDAB = FloatCDAB.zero,
    integration_time: FloatCDAB = FloatCDAB.inf,
    differentiation_time: FloatCDAB = FloatCDAB.zero,
};

pub const FloatCDAB = packed struct {
    const zero = FloatCDAB.fromF32(0.0);
    const inf = FloatCDAB.fromF32(std.math.inf(f32));

    raw: packed struct { c: u8, d: u8, a: u8, b: u8 },

    pub fn fromF32(value: f32) FloatCDAB {
        const bytes: [4]u8 = @bitCast(value);
        return .{ .raw = .{
            .c = bytes[2],
            .d = bytes[3],
            .a = bytes[0],
            .b = bytes[1],
        } };
    }

    pub fn toF32(self: FloatCDAB) f32 {
        const bytes = [4]u8{ self.raw.a, self.raw.b, self.raw.c, self.raw.d };
        return @bitCast(bytes);
    }
};
