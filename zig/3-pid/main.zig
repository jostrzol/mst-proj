const std = @import("std");
const posix = std.posix;
const POLL = std.os.linux.POLL;

const pwm = @import("pwm");

const Server = @import("Server.zig");
const Registers = @import("Registers.zig");
const Controller = @import("Controller.zig");

const c = @cImport({
    @cInclude("signal.h");
    @cInclude("string.h");
});

const n_connections_max = 5;

const i2c_adapter_number = 1;
const i2c_adapter_path = std.fmt.comptimePrint("/dev/i2c-{}", .{i2c_adapter_number});
const ads7830_address: c_int = 0x48;
const motor_pwm_channel: u8 = 1; // gpio 13

const pwm_frequency: f32 = 1000;
const read_rate: u64 = 60;
const read_interval_us: u64 = std.time.us_per_s / read_rate;

const controller_options: Controller.Options = .{
    .i2c_adapter_path = i2c_adapter_path,
    .i2c_address = ads7830_address,
    .read_interval_us = read_interval_us,
    .revolution_treshold_close = 105,
    .revolution_treshold_far = 118,
    .revolution_bins = 10,
    .revolution_bin_rotate_interval_us = 100 * std.time.us_per_ms,
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
    const allocator = gpa.allocator();

    var registers = try Registers.init();
    defer registers.deinit();

    var controller = try Controller.init(&registers, controller_options);
    defer controller.deinit();

    var server = try Server.init(
        allocator,
        &registers,
        .{ .n_connections_max = 5 },
    );
    defer server.deinit();

    var poll_fds = try std.BoundedArray(posix.pollfd, n_connections_max).init(0);
    const initial_fds = try poll_fds.addManyAsArray(1);
    initial_fds.* = .{
        pollfd_init(server.socket.handle),
    };

    while (do_continue) {
        const n_polled = posix.poll(poll_fds.slice(), 1000) catch |err| {
            std.log.err("Polling: {}\n", .{err});
            continue;
        };
        if (n_polled == 0)
            continue;

        for (poll_fds.slice()) |*poll_fd| {
            const fd = poll_fd.fd;

            if (poll_fd.revents & (POLL.ERR | POLL.HUP) != 0) {
                poll_fd.fd = -fd; // mark for removal
                server.close_connection(fd);
            }
            if (poll_fd.revents & POLL.ERR != 0)
                std.log.err("File (socket?) closed unexpectedly\n", .{});
            if (poll_fd.revents & POLL.NVAL != 0)
                std.log.err("File (socket?) not open\n", .{});
            if (poll_fd.revents & POLL.IN != 0) {
                // res = controller_handle(&controller, fd);
                // if (res < 0)
                // perror("Failed to handle controller timer activation");
                // if (res != 0)
                // continue; // Handled -- either error or success
                //
                const res = server.handle(fd) catch |err| {
                    std.log.err("Failed to handle connection: {}\n", .{err});
                    if (err == error.Receive)
                        poll_fd.fd = -fd; // mark for removal
                    continue;
                };

                switch (res) {
                    .accepted => |file| {
                        const new_pollfd = poll_fds.addOneAssumeCapacity();
                        new_pollfd.* = pollfd_init(file.handle);
                    },
                    else => {},
                }
            }
        }

        // Remove marked connections
        var i: u32 = 0;
        while (i < poll_fds.len) {
            if (poll_fds.get(i).fd < 0)
                poll_fds.set(i, poll_fds.pop())
            else
                i += 1;
        }

        // std.time.sleep(sleep_time_ns);
        //
        // const value = read_potentiometer_value(i2c_file) orelse continue;
        // const duty_cycle = @as(f32, @floatFromInt(value)) / std.math.maxInt(u8);
        // std.debug.print("selected duty cycle: {d:.2}\n", .{duty_cycle});
        //
        // channel.setParameters(.{
        //     .frequency = null,
        //     .duty_cycle_ratio = duty_cycle,
        // }) catch |err| {
        //     std.debug.print("error updating duty cycle: {}\n", .{err});
        // };
    }
}

fn pollfd_init(fd: posix.fd_t) posix.pollfd {
    return .{ .fd = fd, .events = POLL.IN, .revents = 0 };
}
