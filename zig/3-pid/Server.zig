const std = @import("std");
const posix = std.posix;
const File = std.fs.File;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const Registers = @import("Registers.zig");
const c = @import("c.zig");

const Self = @This();

ctx: *c.modbus_t,
registers: *Registers,
socket: File,
connections: ArrayList(File),

const InitError = error{
    ModbusSocketOpen,
    ModbusSocketListen,
} || Allocator.Error;

pub fn init(
    allocator: Allocator,
    registers: *Registers,
    args: struct {
        address: [*:0]const u8 = "0.0.0.0",
        port: u31 = 5502,
        n_connections_max: u32,
    },
) InitError!Self {
    const ctx = c.modbus_new_tcp(args.address, args.port) orelse {
        return InitError.ModbusSocketOpen;
    };
    errdefer c.modbus_free(ctx);

    const socket_fd = c.modbus_tcp_listen(ctx, 5);
    if (socket_fd == -1)
        return InitError.ModbusSocketListen;
    const socket = File{ .handle = socket_fd };
    errdefer socket.close();

    const connections = try ArrayList(File)
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

pub const HandleResult = union(enum) {
    accepted: File,
    received: void,
    closed: void,
    skipped: void,
};

pub const HandleError = error{Receive} || Allocator.Error || posix.AcceptError;

pub fn handle(self: *Self, fd: posix.fd_t) HandleError!HandleResult {
    if (fd == self.socket.handle) {
        // Create new connection
        var client_address = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 0);
        var addr_length = client_address.getOsSockLen();

        const connection_fd = try posix.accept(fd, &client_address.any, &addr_length, 0);
        const file = File{ .handle = connection_fd };
        errdefer file.close();

        const connection = try self.connections.addOne();
        connection.* = file;

        std.log.info("New connection from {} on socket {}", .{ client_address, connection_fd });

        return .{ .accepted = file };
    } else {
        // Handle modbus request
        errdefer self.closeConnection(fd);

        if (c.modbus_set_socket(self.ctx, fd) != 0)
            return HandleError.Receive;

        var query = std.mem.zeroes([c.MODBUS_TCP_MAX_ADU_LENGTH]u8);
        const received = c.modbus_receive(self.ctx, &query);
        if (received == -1) {
            return switch (std.posix.errno(received)) {
                .CONNRESET => return .{ .closed = {} },
                else => HandleError.Receive,
            };
        }
        if (received == 0)
            return .{ .received = {} };

        const res = c.modbus_reply(
            self.ctx,
            &query,
            received,
            @ptrCast(self.registers.raw),
        );
        if (res < 0) return HandleError.Receive;

        return .{ .received = {} };
    }

    return .{ .skipped = {} };
}

pub fn closeConnection(self: *Self, fd: posix.fd_t) void {
    for (self.connections.items) |*file| {
        if (file.handle != fd)
            continue;

        file.close();
        file.* = self.connections.pop();
        return;
    }
    std.debug.panic("File descriptor not found: {}", .{fd});
}
