const std = @import("std");
const posix = std.posix;
const File = std.fs.File;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const Registers = @import("Registers.zig");

const c = @cImport({
    @cInclude("modbus.h");
    @cInclude("arpa/inet.h");
    @cInclude("memory.h");
    @cInclude("netinet/in.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
});

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
    handled: void,
    skipped: void,
};

pub const HandleError = error{ Accept, Receive } || Allocator.Error;

pub fn handle(self: *Self, fd: posix.fd_t) HandleError!HandleResult {
    if (fd == self.socket.handle) {
        // Create new connection
        var client_address: c.sockaddr_in = std.mem.zeroes(c.sockaddr_in);
        var addr_length: c.socklen_t = @sizeOf(@TypeOf(client_address));

        const connection_fd =
            c.accept(fd, @ptrCast(&client_address), &addr_length);
        if (connection_fd == -1)
            return HandleError.Accept;

        const connection = try self.connections.addOne();
        connection.* = File{ .handle = connection_fd };

        std.log.info("New connection from {s}:{} on socket {}\n", .{
            c.inet_ntoa(client_address.sin_addr), client_address.sin_port,
            connection_fd,
        });

        return .{ .accepted = connection.* };
    } else {
        // Handle modbus request
        if (c.modbus_set_socket(self.ctx, fd) != 0)
            return HandleError.Receive;

        var query = std.mem.zeroes([c.MODBUS_TCP_MAX_ADU_LENGTH]u8);
        const received = c.modbus_receive(self.ctx, &query);
        if (received == -1) {
            self.close_connection(fd);
            return HandleError.Receive;
        } else if (received == 0) {
            return .{ .handled = {} };
        }

        const res = c.modbus_reply(
            self.ctx,
            &query,
            received,
            @ptrCast(self.registers.raw),
        );
        if (res < 0) return HandleError.Receive;

        return .{ .handled = {} };
    }

    return .{ .skipped = {} };
}

pub fn close_connection(self: *Self, fd: posix.fd_t) void {
    for (self.connections.items) |*file| {
        if (file.handle != fd)
            continue;

        file.close();
        file.* = self.connections.pop();
        return;
    }
    std.debug.panic("File descriptor not found: {}", .{fd});
}
