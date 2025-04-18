const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;

const Wifi = @import("Wifi.zig");
const c = @import("c.zig");

const Self = @This();

const server_port_number = 5502;
const server_modbus_address = 0;

handle: *const anyopaque,

const ServerInitOpts = struct {
    netif: *sys.esp_netif_obj,
};

pub fn init(opts: *const ServerInitOpts) !Self {
    var handle: *const anyopaque = undefined;
    try c.espCheckError(c.mbc_slave_init_tcp(@ptrCast(&handle)));
    errdefer c.espLogError(c.mbc_slave_destroy());

    var comm_info = c.mb_communication_info_t{ .unnamed_1 = .{
        .ip_addr_type = c.MB_IPV4,
        .ip_mode = c.MB_MODE_TCP,
        .ip_port = server_port_number,
        .ip_addr = null,
        .ip_netif_ptr = opts.netif,
        .slave_uid = server_modbus_address,
    } };
    try c.espCheckError(c.mbc_slave_setup(&comm_info));

    try c.espCheckError(c.mbc_slave_start());

    return .{ .handle = handle };
}

pub fn deinit(_: *const Self) void {
    c.espLogError(c.mbc_slave_destroy());
}
