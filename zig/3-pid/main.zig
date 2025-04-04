const std = @import("std");
const posix = std.posix;
const POLL = std.os.linux.POLL;

const pwm = @import("pwm");

const Server = @import("Server.zig");
const Registers = @import("Registers.zig");
const Controller = @import("Controller.zig");

const c = @cImport({
    @cInclude("signal.h");
});

const n_fds_system = 3;
const n_connections_max = 5;
const n_fds = n_fds_system + n_connections_max;

const i2c_adapter_number = 1;
const i2c_adapter_path = std.fmt.comptimePrint("/dev/i2c-{}", .{i2c_adapter_number});
const ads7830_address: c_int = 0x48;
const motor_pwm_channel: u8 = 1; // gpio 13

const pwm_frequency: f32 = 1000;
const read_rate: u64 = 1000;
const read_interval_us: u64 = std.time.us_per_s / read_rate;

const controller_options: Controller.Options = .{
    .i2c_adapter_path = i2c_adapter_path,
    .i2c_address = ads7830_address,
    .read_interval_us = read_interval_us,
    .revolution_treshold_close = 105,
    .revolution_treshold_far = 118,
    .revolution_bins = 10,
    .control_interval_us = 100 * std.time.us_per_ms,
    .pwm_channel = motor_pwm_channel,
    .pwm_frequency = 1000,
};

var do_continue = true;
pub fn interrupt_handler(_: c_int) callconv(.C) void {
    std.debug.print("\nGracefully stopping\n", .{});
    do_continue = false;
}
const interrupt_sigaction = c.struct_sigaction{
    .__sigaction_handler = .{ .sa_handler = &interrupt_handler },
};

pub fn main() !void {
    std.debug.print("Controlling motor from Zig.\n", .{});

    if (c.sigaction(c.SIGINT, &interrupt_sigaction, null) != 0) {
        return error.SigactionNotSet;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var registers = try Registers.init();
    defer registers.deinit();

    var controller = try Controller.init(alloc, &registers, controller_options);
    defer controller.deinit();

    var server = try Server.init(
        alloc,
        &registers,
        .{ .n_connections_max = 5 },
    );
    defer server.deinit();

    var poll_fds = try std.BoundedArray(posix.pollfd, n_connections_max).init(0);
    const initial_fds = try poll_fds.addManyAsArray(n_fds_system);
    initial_fds.* = .{
        pollfd_init(server.socket.handle),
        pollfd_init(controller.read_timer.handle),
        pollfd_init(controller.control_timer.handle),
    };

    while (do_continue) {
        const n_polled = posix.poll(poll_fds.slice(), 1000) catch |err| {
            std.log.err("Polling: {}", .{err});
            continue;
        };
        if (n_polled == 0)
            continue;

        for (poll_fds.slice()) |*poll_fd| {
            const fd = poll_fd.fd;

            if (poll_fd.revents & POLL.ERR != 0)
                std.log.err("File (socket?) closed unexpectedly", .{});
            if (poll_fd.revents & POLL.NVAL != 0)
                std.log.err("File (socket?) not open", .{});

            if (poll_fd.revents & (POLL.ERR | POLL.HUP) != 0) {
                poll_fd.fd = -fd; // mark for removal
                server.close_connection(fd);
            } else if (poll_fd.revents & POLL.IN != 0) {
                const controller_res = controller.handle(fd) catch |err| {
                    std.log.err("Failed to handle controller timer activation: {}", .{err});
                    continue;
                };
                if (controller_res == .handled)
                    continue;

                const server_res = server.handle(fd) catch |err| {
                    std.log.err("Failed to handle connection: {}", .{err});
                    continue;
                };

                switch (server_res) {
                    .accepted => |file| {
                        const new_pollfd = poll_fds.addOneAssumeCapacity();
                        new_pollfd.* = pollfd_init(file.handle);
                    },
                    .closed => poll_fd.fd = -fd, // mark for removal
                    else => {},
                }
            }
        }

        // Remove marked connections
        var i: u32 = 0;
        while (i < poll_fds.len) {
            const poll_fd = &poll_fds.slice()[i];
            if (poll_fd.fd < 0) {
                std.log.info("Closing connection on socket {}", .{-poll_fd.fd});
                poll_fd.* = poll_fds.pop();
            } else i += 1;
        }
    }
}

fn pollfd_init(fd: posix.fd_t) posix.pollfd {
    return .{ .fd = fd, .events = POLL.IN, .revents = 0 };
}
