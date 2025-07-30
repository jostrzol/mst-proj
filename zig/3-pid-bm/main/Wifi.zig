const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;

const c = @import("c.zig");
const logErr = @import("utils.zig").logErr;

const ssid = c.CONFIG_ESP_WIFI_SSID;
const password = c.CONFIG_ESP_WIFI_PASSWORD;
const maximum_retries = 5;

const Self = @This();

pub const EventFlags = packed struct(sys.EventBits_t) {
    failed: bool = false,
    connected: bool = false,
    _padding: u30 = 0,

    fn all() EventFlags {
        return .{ .failed = true, .connected = true };
    }
};

var event_group: sys.EventGroupHandle_t = null;
var retry_count: u32 = 0;

netif: *sys.esp_netif_t,

pub fn init() !Self {
    if (event_group) |_| return error.ErrorWifiAlreadySetUp;

    const event_group_local = sys.xEventGroupCreate() orelse return error.ErrorSetupWifi;
    event_group = event_group_local;

    try idf.espCheckError(sys.esp_netif_init());
    errdefer idf.espLogError(sys.esp_netif_deinit(), "esp_netif_deinit");

    const netif = sys.esp_netif_create_default_wifi_sta() orelse return error.ErrorSetupWifi;
    errdefer sys.esp_netif_destroy_default_wifi(netif);

    try idf.wifi.init(&c.fixed.wifiInitConfigDefault());
    errdefer logErr(idf.wifi.deinit(), "Wifi.deinit");

    var handler_wifi: sys.esp_event_handler_instance_t = undefined;
    try idf.espCheckError(sys.esp_event_handler_instance_register(
        sys.WIFI_EVENT,
        c.ESP_EVENT_ANY_ID,
        &eventHandler,
        null,
        &handler_wifi,
    ));

    var handler_ip: sys.esp_event_handler_instance_t = undefined;
    try idf.espCheckError(sys.esp_event_handler_instance_register(
        sys.IP_EVENT,
        @intFromEnum(sys.ip_event_t.IP_EVENT_STA_GOT_IP),
        &eventHandler,
        null,
        &handler_ip,
    ));

    try idf.wifi.setMode(.WIFI_MODE_STA);

    var wifi_config = sys.wifi_config_t{
        .sta = .{
            .ssid = nullExtend(@FieldType(sys.wifi_sta_config_t, "ssid"), ssid),
            .password = nullExtend(@FieldType(sys.wifi_sta_config_t, "password"), password),
            .threshold = .{ .authmode = sys.wifi_auth_mode_t.WIFI_AUTH_WPA2_PSK },
        },
    };
    try idf.wifi.setConfig(.WIFI_IF_STA, &wifi_config);

    try idf.wifi.start();
    errdefer logErr(idf.wifi.stop(), "Wifi.stop");

    const bits = sys.xEventGroupWaitBits(
        event_group_local,
        @bitCast(EventFlags.all()),
        @intFromBool(false),
        @intFromBool(false),
        std.math.maxInt(sys.TickType_t),
    );
    const flags: EventFlags = @bitCast(bits);
    if (flags.connected) {
        std.log.info("Connected to AP SSID:{s}", .{ssid});
    } else if (flags.failed) {
        return error.ErrorWifiConnectionFailed;
    }

    try idf.wifi.PowerSave.set(.WIFI_PS_NONE);

    return .{ .netif = netif };
}

pub fn deinit(self: *const Self) void {
    event_group = null;
    logErr(idf.wifi.stop(), "Wifi.stop");
    logErr(idf.wifi.deinit(), "Wifi.deinit");
    sys.esp_netif_destroy_default_wifi(self.netif);
    idf.espLogError(sys.esp_netif_deinit(), "esp_netif_deinit");
}

fn eventHandler(
    args: ?*anyopaque,
    event_base: sys.esp_event_base_t,
    event_id: i32,
    event_data: ?*anyopaque,
) callconv(.c) void {
    eventHandlerImpl(args, event_base, event_id, event_data) catch |err| {
        std.log.err("Wifi.eventHandler fail: {}", .{err});
    };
}

fn eventHandlerImpl(
    _: ?*anyopaque,
    event_base: sys.esp_event_base_t,
    event_id: i32,
    event_data: ?*anyopaque,
) !void {
    const event_group_local = event_group orelse {
        return error.WifiNotInitialized;
    };
    const event = EventType{ .base = event_base, .id = @bitCast(event_id) };

    if (event.is(&EventType.wifi(.WIFI_EVENT_STA_START))) {
        try idf.wifi.connect();
    } else if (event.is(&EventType.wifi(.WIFI_EVENT_STA_DISCONNECTED))) {
        if (retry_count < maximum_retries) {
            try idf.wifi.connect();
            retry_count += 1;
            std.log.info(
                "Retrying to connect to the AP ({}/{})",
                .{ retry_count, maximum_retries },
            );
        } else {
            std.log.err("Connecting to the AP failed", .{});
            _ = sys.xEventGroupSetBits(
                event_group_local,
                @bitCast(EventFlags{ .failed = true }),
            );
        }
    } else if (event.is(&EventType.ip(.IP_EVENT_STA_GOT_IP))) {
        const data: *sys.ip_event_got_ip_t = @alignCast(@ptrCast(event_data));
        const addr: [4]u8 = @bitCast(data.ip_info.ip.addr);
        std.log.info("Got ip: {}.{}.{}.{}", .{ addr[0], addr[1], addr[2], addr[3] });
        retry_count = 0;
        _ = sys.xEventGroupSetBits(
            event_group_local,
            @bitCast(EventFlags{ .connected = true }),
        );
    }
}

const EventType = struct {
    base: sys.esp_event_base_t,
    id: c_uint,

    pub fn wifi(id: sys.wifi_event_t) EventType {
        return .{ .base = sys.WIFI_EVENT, .id = @intFromEnum(id) };
    }
    pub fn ip(id: sys.ip_event_t) EventType {
        return .{ .base = sys.IP_EVENT, .id = @intFromEnum(id) };
    }

    pub fn is(self: *const EventType, other: *const EventType) bool {
        return std.mem.eql(
            u8,
            @ptrCast(self[0..1]),
            @ptrCast(other[0..1]),
        );
    }
};

fn nullExtend(comptime T: type, comptime str: [:0]const u8) [@sizeOf(T)]u8 {
    return (str ++ (.{'\x00'} ** (@sizeOf(T) - str.len))).*;
}
