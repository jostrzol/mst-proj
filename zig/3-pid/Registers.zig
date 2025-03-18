const std = @import("std");
const posix = std.posix;

const c = @cImport({
    @cInclude("modbus.h");
});

const Self = @This();

const RegInput = enum(u16) {
    frequency,
    control_signal,

    pub fn address(self: RegHolding) u16 {
        return @intFromEnum(self) * 2;
    }

    pub fn size() u16 {
        return std.meta.fields(RegInput).len * 2;
    }
};

const RegHolding = enum(u16) {
    target_frequency,
    proportional_factor,
    integration_time,
    differentiation_time,

    pub fn address(self: RegHolding) u16 {
        return @intFromEnum(self) * 2;
    }

    pub fn size() u16 {
        return std.meta.fields(RegHolding).len * 2;
    }
};

raw: *c.modbus_mapping_t,

pub fn init() !Self {
    const raw = c.modbus_mapping_new(
    // coils
    0, 0,
    // registers
    RegHolding.size(), RegInput.size());
    if (raw == null)
        return error.ModbusMappingInitFailed;

    var self: Self = .{ .raw = raw };

    self.set_holding(RegHolding.integration_time, std.math.inf(f32));

    return self;
}

pub fn deinit(self: *Self) void {
    c.modbus_mapping_free(self.raw);
}

pub fn set_holding(self: *Self, register: RegHolding, value: f32) void {
    c.modbus_set_float_badc(
        value,
        &self.raw.tab_registers[register.address()],
    );
}

pub fn set_input(self: *Self, register: RegInput, value: f32) void {
    c.modbus_set_float_badc(
        value,
        &self.raw.tab_input_registers[register.address()],
    );
}

pub fn get_holding(self: *const Self, register: RegHolding) f32 {
    return c.modbus_get_float_abcd(&self.raw.tab_registers[register.address()]);
}
