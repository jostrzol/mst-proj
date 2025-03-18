const std = @import("std");
const posix = std.posix;

const Registers = @import("Registers.zig");

const c = @cImport({
    @cInclude("modbus.h");
});

const Self = @This();

ctx: *c.modbus_t,
registers: *Registers,
socket: std.fs.File,
connections: std.ArrayList(std.fs.File),

const InitError = error{
    ModbusSocketFailedToOpen,
    ModbusSocketFailedToListen,
} || std.mem.Allocator.Error;

pub fn init(
    allocator: std.mem.Allocator,
    registers: *Registers,
    args: struct {
        address: [*:0]const u8 = "0.0.0.0",
        port: u31 = 5502,
        n_connections_max: u32,
    },
) InitError!Self {
    const ctx = c.modbus_new_tcp(args.address, args.port) orelse {
        return InitError.ModbusSocketFailedToOpen;
    };

    errdefer c.modbus_free(ctx);

    const socket_fd = c.modbus_tcp_listen(ctx, 5);
    if (socket_fd == -1)
        return InitError.ModbusSocketFailedToListen;
    const socket = std.fs.File{ .handle = socket_fd };
    errdefer socket.close();

    const connections = try std.ArrayList(std.fs.File)
        .initCapacity(allocator, args.n_connections_max);
    errdefer connections.deinit(allocator);

    return .{
        .ctx = ctx,
        .registers = registers,
        .socket = socket,
        .connections = connections,
    };
}

pub fn deinit(self: *Self) void {
    for (self.connections.items) |connection| {
        connection.close();
    }
    self.connections.deinit();
    self.socket.close();
    c.modbus_free(self.ctx);
}
