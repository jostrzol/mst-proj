const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;

const Wifi = @import("Wifi.zig");
const c = @import("c.zig");

const Self = @This();

const mdns_port = 502;
const mdns_hostname = "esp32";

mdns: MDns,
wifi: Wifi,

pub fn init() !Self {
    idf.espCheckError(sys.nvs_flash_init()) catch |err| {
        switch (err) {
            idf.esp_error.ErrorNvsNoFreePages,
            idf.esp_error.ErrorNvsNewVersionFound,
            => {
                try idf.espCheckError(sys.nvs_flash_erase());
                try idf.espCheckError(sys.nvs_flash_init());
            },
            else => return err,
        }
    };
    errdefer idf.espLogError(sys.nvs_flash_deinit());

    try idf.espCheckError(sys.esp_event_loop_create_default());
    errdefer idf.espLogError(sys.esp_event_loop_delete_default());

    const mdns = try MDns.init();
    errdefer mdns.deinit();

    const wifi = try Wifi.init();
    errdefer wifi.deinit();

    return .{
        .mdns = mdns,
        .wifi = wifi,
    };
}

pub fn deinit(self: *const Self) void {
    self.wifi.deinit();
    self.mdns.deinit();
    idf.espLogError(sys.esp_event_loop_delete_default());
    idf.espLogError(sys.nvs_flash_deinit());
}

const MDns = struct {
    fn init() !MDns {
        try c.espCheckError(c.mdns_init());
        errdefer c.mdns_free();

        try c.espCheckError(c.mdns_hostname_set(mdns_hostname));

        var txt_items = [_]c.mdns_txt_item_t{
            .{ .key = "board", .value = "esp32" },
        };
        const res = c.mdns_service_add(mdns_hostname, "_modbus", "_tcp", mdns_port, &txt_items, txt_items.len);
        try c.espCheckError(res);

        return .{};
    }

    fn deinit(_: MDns) void {
        c.mdns_free();
    }
};
