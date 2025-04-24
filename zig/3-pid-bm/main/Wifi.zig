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
    errdefer idf.espLogError(sys.esp_netif_deinit());

    const netif = sys.esp_netif_create_default_wifi_sta() orelse return error.ErrorSetupWifi;
    errdefer sys.esp_netif_destroy_default_wifi(netif);

    try idf.wifi.init(&wifiInitConfigDefault());
    errdefer logErr(idf.wifi.deinit());

    var handler_wifi: sys.esp_event_handler_instance_t = undefined;
    try idf.espCheckError(sys.esp_event_handler_instance_register(
        sys.WIFI_EVENT,
        c.ESP_EVENT_ANY_ID,
        &event_handler,
        null,
        &handler_wifi,
    ));

    var handler_ip: sys.esp_event_handler_instance_t = undefined;
    try idf.espCheckError(sys.esp_event_handler_instance_register(
        sys.IP_EVENT,
        @intFromEnum(sys.ip_event_t.IP_EVENT_STA_GOT_IP),
        &event_handler,
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
    errdefer logErr(idf.wifi.stop());

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
    } else {
        std.log.err("Unexpected event", .{});
    }

    try idf.wifi.PowerSave.set(.WIFI_PS_NONE);

    return .{ .netif = netif };
}

pub fn deinit(self: *const Self) void {
    event_group = null;
    logErr(idf.wifi.stop());
    logErr(idf.wifi.deinit());
    sys.esp_netif_destroy_default_wifi(self.netif);
    idf.espLogError(sys.esp_netif_deinit());
}

fn event_handler(
    args: ?*anyopaque,
    event_base: sys.esp_event_base_t,
    event_id: i32,
    event_data: ?*anyopaque,
) callconv(.c) void {
    event_handler_impl(args, event_base, event_id, event_data) catch |err| {
        std.log.err("Failed to handle wifi event: {}", .{err});
    };
}

fn event_handler_impl(
    _: ?*anyopaque,
    event_base: sys.esp_event_base_t,
    event_id: i32,
    event_data: ?*anyopaque,
) !void {
    const event_group_local = event_group orelse {
        std.log.err("Wifi event handler called after wifi deinitialization", .{});
        return;
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

fn wifiInitConfigDefault() sys.wifi_init_config_t {
    return .{
        .osi_funcs = &sys.g_wifi_osi_funcs,
        .wpa_crypto_funcs = sys.g_wifi_default_wpa_crypto_funcs,
        .static_rx_buf_num = c.CONFIG_ESP_WIFI_STATIC_RX_BUFFER_NUM,
        .dynamic_rx_buf_num = c.CONFIG_ESP_WIFI_DYNAMIC_RX_BUFFER_NUM,
        .tx_buf_type = c.CONFIG_ESP_WIFI_TX_BUFFER_TYPE,
        .static_tx_buf_num = config(c_int, "CONFIG_ESP_WIFI_STATIC_TX_BUFFER_NUM") orelse 0,
        .dynamic_tx_buf_num = config(c_int, "CONFIG_ESP_WIFI_DYNAMIC_TX_BUFFER_NUM") orelse 0,
        .rx_mgmt_buf_type = c.CONFIG_ESP_WIFI_DYNAMIC_RX_MGMT_BUF,
        .rx_mgmt_buf_num = config(c_int, "CONFIG_ESP_WIFI_RX_MGMT_BUF_NUM_DEF") orelse 0,
        .cache_tx_buf_num = config(c_int, "CONFIG_ESP_WIFI_CACHE_TX_BUFFER_NUM") orelse 0,
        .csi_enable = @intFromBool(config_csi_enable),
        .ampdu_rx_enable = @intFromBool(config(bool, "CONFIG_ESP_WIFI_AMPDU_RX_ENABLED")),
        .ampdu_tx_enable = @intFromBool(config(bool, "CONFIG_ESP_WIFI_AMPDU_TX_ENABLED")),
        .amsdu_tx_enable = @intFromBool(config(bool, "CONFIG_ESP_WIFI_AMSDU_TX_ENABLED")),
        .nvs_enable = @intFromBool(config(bool, "CONFIG_ESP_WIFI_NVS_ENABLED")),
        .nano_enable = @intFromBool(config(bool, "CONFIG_NEWLIB_NANO_FORMAT")),
        .rx_ba_win = if (config(bool, "CONFIG_ESP_WIFI_AMPDU_RX_ENABLED")) c.CONFIG_ESP_WIFI_RX_BA_WIN else 0,
        .wifi_task_core_id = if (config(bool, "CONFIG_ESP_WIFI_TASK_PINNED_TO_CORE_1")) 1 else 0,
        .beacon_max_len = config(c_int, "CONFIG_ESP_WIFI_SOFTAP_BEACON_MAX_LEN") orelse 754,
        .mgmt_sbuf_num = config(c_int, "CONFIG_ESP_WIFI_MGMT_SBUF_NUM") orelse 32,
        .feature_caps = @bitCast(Capabilities.fromConfig()),
        .sta_disconnected_pm = config(bool, "CONFIG_ESP_WIFI_STA_DISCONNECTED_PM_ENABLE"),
        .espnow_max_encrypt_num = c.CONFIG_ESP_WIFI_ESPNOW_MAX_ENCRYPT_NUM,
        .tx_hetb_queue_num = config(c_int, "CONFIG_ESP_WIFI_TX_HETB_QUEUE_NUM") orelse 1,
        .dump_hesigb_enable = config(bool, "CONFIG_ESP_WIFI_ENABLE_DUMP_HESIGB") and !config_csi_enable,
        .magic = 0x1F2F3F4F,
    };
}

const config_csi_enable = config(bool, "CONFIG_ESP_WIFI_CSI_ENABLED");

const Capabilities = packed struct(u64) {
    enable_wpa3_sae: bool = false,
    enable_cache_tx_buffer: bool = false,
    ftm_initiator: bool = false,
    ftm_responder: bool = false,
    enable_gcmp: bool = false,
    enable_gmac: bool = false,
    enable_11r: bool = false,
    enable_enterprise: bool = false,
    _padding: u56 = 0,

    fn fromConfig() Capabilities {
        return .{
            .enable_wpa3_sae = config(bool, "CONFIG_ESP_WIFI_ENABLE_WPA3_SAE"),
            .enable_cache_tx_buffer = config(bool, "WIFI_CACHE_TX_BUFFER_NUM"),
            .ftm_initiator = config(bool, "CONFIG_ESP_WIFI_FTM_INITIATOR_SUPPORT"),
            .ftm_responder = config(bool, "CONFIG_ESP_WIFI_FTM_RESPONDER_SUPPORT"),
            .enable_gcmp = config(bool, "CONFIG_ESP_WIFI_GCMP_SUPPORT"),
            .enable_gmac = config(bool, "CONFIG_ESP_WIFI_GMAC_SUPPORT"),
            .enable_11r = config(bool, "CONFIG_ESP_WIFI_11R_SUPPORT"),
            .enable_enterprise = config(bool, "CONFIG_ESP_WIFI_ENTERPRISE_SUPPORT"),
        };
    }
};

fn config(comptime T: type, comptime key: []const u8) if (T == bool) bool else ?T {
    const is_defined = @hasDecl(c, key);
    if (T == bool) {
        return is_defined;
    } else {
        return if (@hasDecl(c, key)) @field(c, key) else null;
    }
}

fn nullExtend(comptime T: type, comptime str: [:0]const u8) [@sizeOf(T)]u8 {
    return (str ++ (.{'\x00'} ** (@sizeOf(T) - str.len))).*;
}
