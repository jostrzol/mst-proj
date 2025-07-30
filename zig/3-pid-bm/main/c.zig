const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;

const c = @cImport({
    @cDefine("__XTENSA__", "1");
    @cUndef("__riscv");

    @cInclude("esp_adc/adc_oneshot.h");
    @cInclude("driver/ledc.h");
    @cInclude("driver/gptimer.h");
    @cInclude("esp_clk_tree.h");
    @cInclude("soc/clk_tree_defs.h");

    @cInclude("freertos/FreeRTOS.h");
    @cInclude("portmacro.h");

    @cInclude("mdns.h");
    @cInclude("esp_modbus_common.h");
    @cInclude("esp_modbus_slave.h");

    @cInclude("sdkconfig.h");
});

pub usingnamespace c;

pub fn espCheckError(err: c.esp_err_t) idf.esp_error!void {
    try idf.espCheckError(@enumFromInt(err));
}

pub fn espLogError(errc: c.esp_err_t, operation: []const u8) void {
    espCheckError(errc) catch |err| {
        std.log.err("{s} fail: {}", .{ operation, err });
    };
}

pub fn rtosCheckError(result: sys.BaseType_t) !void {
    if (result != 1) return error.ErrorRtos;
}

// Needed, because c-translate cannot properly translate flags and some macros
pub const fixed = struct {
    pub const ledc_channel_config_t = extern struct {
        gpio_num: c_int = @import("std").mem.zeroes(c_int),
        speed_mode: c.ledc_mode_t = @import("std").mem.zeroes(c.ledc_mode_t),
        channel: c.ledc_channel_t = @import("std").mem.zeroes(c.ledc_channel_t),
        intr_type: c.ledc_intr_type_t = @import("std").mem.zeroes(c.ledc_intr_type_t),
        timer_sel: c.ledc_timer_t = @import("std").mem.zeroes(c.ledc_timer_t),
        duty: u32 = @import("std").mem.zeroes(u32),
        hpoint: c_int = @import("std").mem.zeroes(c_int),
        sleep_mode: c.ledc_sleep_mode_t = @import("std").mem.zeroes(c.ledc_sleep_mode_t),
        flags: packed struct(u32) {
            output_invert: bool = false,
            _: u31 = 0,
        } = .{},
    };

    pub extern fn ledc_channel_config(ledc_conf: ?*const ledc_channel_config_t) c.esp_err_t;

    pub fn wifiInitConfigDefault() sys.wifi_init_config_t {
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

    pub const Capabilities = packed struct(u64) {
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
};
