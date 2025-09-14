const std = @import("std");
const config = @import("config");
const posix = std.posix;
const POLL = std.os.linux.POLL;

const pwm = @import("pwm");

const Server = @import("Server.zig");
const Registers = @import("Registers.zig");
const Controller = @import("Controller.zig");
const memory = @import("memory.zig");
const c = @import("c.zig");

const n_fds_system = 2;
const n_connections_max = 5;
const n_fds = n_fds_system + n_connections_max;

const i2c_adapter_number = 1;
const i2c_adapter_path = std.fmt.comptimePrint("/dev/i2c-{}", .{i2c_adapter_number});
const ads7830_address = 0x48;

const motor_pwm_channel = 1; // gpio 13
const pwm_frequency: f32 = 1000;

const read_frequency: u32 = 1000;
const control_frequency: u32 = 10;
const reads_per_bin: u32 = read_frequency / control_frequency;

const controller_options: Controller.Options = .{
    .control_frequency = control_frequency,
    .time_window_bins = 10,
    .reads_per_bin = reads_per_bin,
    .revolution_threshold_close = 0.20,
    .revolution_threshold_far = 0.36,
    .i2c_adapter_path = i2c_adapter_path,
    .i2c_address = ads7830_address,
    .pwm_channel = motor_pwm_channel,
    .pwm_frequency = 1000,
};

var do_continue = true;
pub fn interruptHandler(_: c_int) callconv(.C) void {
    std.debug.print("\nGracefully stopping\n", .{});
    do_continue = false;
}

pub fn main() !void {
    std.log.info("Controlling motor using PID from Zig", .{});

    const signal = @intFromPtr(c.signal(c.SIGINT, &interruptHandler));
    if (signal < 0)
        return std.posix.unexpectedErrno(std.posix.errno(signal));

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var counting = memory.CountingAllocator.init(gpa.allocator());
    const alloc = counting.allocator();

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

    var poll_fds = try std.BoundedArray(posix.pollfd, n_fds).init(0);
    const initial_fds = try poll_fds.addManyAsArray(n_fds_system);
    initial_fds.* = .{
        pollfdInit(server.socket.handle),
        pollfdInit(controller.timer.handle),
    };

    while (do_continue) {
        const n_polled = posix.poll(poll_fds.slice(), 1000) catch |err| {
            std.log.err("poll fail: {}", .{err});
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
                server.closeConnection(fd);
            } else if (poll_fd.revents & POLL.IN != 0) {
                const controller_res = controller.handle(fd) catch |err| {
                    std.log.err("Controller.handle fail: {}", .{err});
                    continue;
                };
                if (controller_res == .handled)
                    continue;

                const server_res = server.handle(fd) catch |err| {
                    std.log.err("Server.handle fail: {}", .{err});
                    continue;
                };

                switch (server_res) {
                    .accepted => |file| {
                        const new_pollfd = poll_fds.addOneAssumeCapacity();
                        new_pollfd.* = pollfdInit(file.handle);
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

fn pollfdInit(fd: posix.fd_t) posix.pollfd {
    return .{ .fd = fd, .events = POLL.IN, .revents = 0 };
}

pub const std_options: std.Options = .{
    .log_level = std.enums.nameCast(std.log.Level, config.log_level),
};
