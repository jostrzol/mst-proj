const std = @import("std");
const posix = std.posix;

const c = @import("c.zig");

const Self = @This();

pub const Input = enum(u16) {
    frequency,
    control_signal,

    pub fn address(self: Input) u16 {
        return @intFromEnum(self) * 2;
    }

    pub fn size() u16 {
        return std.meta.fields(Input).len * 2;
    }
};

pub const Holding = enum(u16) {
    target_frequency,
    proportional_factor,
    integration_time,
    differentiation_time,

    pub fn address(self: Holding) u16 {
        return @intFromEnum(self) * 2;
    }

    pub fn size() u16 {
        return std.meta.fields(Holding).len * 2;
    }
};

raw: *c.modbus_mapping_t,

pub fn init() !Self {
    const raw = c.modbus_mapping_new(
    // coils
    0, 0,
    // registers
    Holding.size(), Input.size());
    if (raw == null)
        return error.ModbusMappingInitFailed;

    var self: Self = .{ .raw = raw };

    self.setHolding(Holding.integration_time, std.math.inf(f32));

    return self;
}

pub fn deinit(self: *Self) void {
    c.modbus_mapping_free(self.raw);
}

pub fn setHolding(self: *Self, register: Holding, value: f32) void {
    c.modbus_set_float_badc(
        value,
        &self.raw.tab_registers[register.address()],
    );
}

pub fn setInput(self: *Self, register: Input, value: f32) void {
    c.modbus_set_float_badc(
        value,
        &self.raw.tab_input_registers[register.address()],
    );
}

pub fn getHolding(self: *const Self, register: Holding) f32 {
    return c.modbus_get_float_abcd(&self.raw.tab_registers[register.address()]);
}
