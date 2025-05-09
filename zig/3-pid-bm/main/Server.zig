const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;

const Registers = @import("Registers.zig");
const c = @import("c.zig");
const logErr = @import("utils.zig").logErr;

const Self = @This();

const port_number = 5502;
const modbus_address = 0;

const par_info_get_tout_ms = 10; // timeout for get parameter info

handle: *const anyopaque,

const ServerInitOptions = struct {
    netif: *sys.esp_netif_obj,
    registers: *Registers,
};

pub fn init(options: *const ServerInitOptions) !Self {
    var handle: *const anyopaque = undefined;
    try c.espCheckError(c.mbc_slave_init_tcp(@ptrCast(&handle)));
    errdefer c.espLogError(c.mbc_slave_destroy());

    var comm_info = c.mb_communication_info_t{ .unnamed_1 = .{
        .ip_addr_type = c.MB_IPV4,
        .ip_mode = c.MB_MODE_TCP,
        .ip_port = port_number,
        .ip_addr = null,
        .ip_netif_ptr = options.netif,
        .slave_uid = modbus_address,
    } };
    try c.espCheckError(c.mbc_slave_setup(&comm_info));

    try c.espCheckError(mbc_slave_set_descriptor(.{
        .start_offset = 0,
        .type = c.MB_PARAM_INPUT,
        .address = &options.registers.input,
        .size = @sizeOf(Registers.Input),
    }));

    try c.espCheckError(mbc_slave_set_descriptor(.{
        .start_offset = 0,
        .type = c.MB_PARAM_HOLDING,
        .address = &options.registers.holding,
        .size = @sizeOf(Registers.Holding),
    }));

    try c.espCheckError(c.mbc_slave_start());

    return .{ .handle = handle };
}

pub fn deinit(_: *const Self) void {
    c.espLogError(c.mbc_slave_destroy());
}

pub fn run(args: ?*anyopaque) callconv(.c) void {
    const self: *Self = @alignCast(@ptrCast(args));

    std.log.info("Listening for modbus requests...", .{});

    while (true)
        logErr(self.iteration());
}

fn iteration(_: *Self) !void {
    _ = c.mbc_slave_check_event(@as(u32, @bitCast(EventGroup.read_write)));

    var reg_info: c.mb_param_info_t = undefined;
    try c.espCheckError(c.mbc_slave_get_param_info(
        &reg_info,
        par_info_get_tout_ms,
    ));

    const event_type: EventGroup = @bitCast(reg_info.type);

    if (event_type.isRead())
        return; // Don't log reads

    const rw_str = if (event_type.isRead()) "READ" else "WRITE";
    const type_str =
        if (event_type.isHolding()) "HOLDING" else if (event_type.isInput()) "INPUT" else "UNKNOWN";

    std.log.info("{s} {s} ({} us), ADDR:{}, TYPE:{}, INST_ADDR:{*}, SIZE:{}", .{
        type_str,
        rw_str,
        reg_info.time_stamp,
        reg_info.mb_offset,
        reg_info.type,
        reg_info.address,
        reg_info.size,
    });
}

const EventGroup = packed struct(c.mb_event_group_t) {
    const read_write = EventGroup{
        .holding_write = true,
        .holding_read = true,
        .input_read = true,
        .coils_write = true,
        .coils_read = true,
        .discrete_read = true,
    };

    holding_write: bool = false,
    holding_read: bool = false,
    _padding0: u1 = 0,
    input_read: bool = false,
    coils_write: bool = false,
    coils_read: bool = false,
    discrete_read: bool = false,
    stack_started: bool = false,
    _padding1: u24 = 0,

    pub fn isRead(self: EventGroup) bool {
        return self.holding_read or self.input_read or self.coils_read or self.discrete_read;
    }

    pub fn isWrite(self: EventGroup) bool {
        return self.holding_write or self.coils_write;
    }

    pub fn isHolding(self: EventGroup) bool {
        return self.holding_read or self.holding_write;
    }

    pub fn isInput(self: EventGroup) bool {
        return self.input_read;
    }
};

pub const mb_register_area_descriptor_t = extern struct {
    // For some reason doesn't work without `start_offset` being u32.
    // Otherwise, C code receives some mangled version of the struct, probably
    // some error in following the calling convention, maybe caused by
    // zig-espressif-bootrstrap.
    start_offset: u32 = @import("std").mem.zeroes(u32),
    type: c_uint = @import("std").mem.zeroes(c_uint),
    address: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    size: usize = @import("std").mem.zeroes(usize),
};
pub extern fn mbc_slave_set_descriptor(descr_data: mb_register_area_descriptor_t) callconv(.c) c.esp_err_t;
