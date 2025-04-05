#include <stdio.h>

#include "esp_err.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_modbus_slave.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h" // IWYU pragma: keep
#include "mdns.h"
#include "nvs_flash.h"
#include "registers.h"
#include "sdkconfig.h" // IWYU pragma: keep

#include "wifi.h"

#define MB_TCP_PORT_NUMBER (5502)
#define MB_MDNS_PORT (502)

#define MB_PAR_INFO_GET_TOUT (10) // Timeout for get parameter info

#define MB_READ_MASK                                                           \
  (MB_EVENT_INPUT_REG_RD | MB_EVENT_HOLDING_REG_RD | MB_EVENT_DISCRETE_RD |    \
   MB_EVENT_COILS_RD)
#define MB_WRITE_MASK (MB_EVENT_HOLDING_REG_WR | MB_EVENT_COILS_WR)
#define MB_READ_WRITE_MASK (MB_READ_MASK | MB_WRITE_MASK)

#define MB_SLAVE_ADDR (0)

static const char *TAG = "pid";

#define MB_MDNS_HOSTNAME "esp32"

static void start_mdns_service(void) {
  // initialize mDNS
  ESP_ERROR_CHECK(mdns_init());
  // set mDNS hostname (required if you want to advertise services)
  ESP_ERROR_CHECK(mdns_hostname_set(MB_MDNS_HOSTNAME));
  ESP_LOGI(TAG, "mdns hostname set to: [%s]", MB_MDNS_HOSTNAME);

  // structure with TXT records
  mdns_txt_item_t serviceTxtData[] = {{"board", "esp32"}};

  // initialize service
  ESP_ERROR_CHECK(mdns_service_add(
      MB_MDNS_HOSTNAME, "_modbus", "_tcp", MB_MDNS_PORT, serviceTxtData, 1
  ));
}

static void stop_mdns_service(void) { mdns_free(); }

static void modbus_loop() {
  mb_param_info_t reg_info; // keeps the Modbus registers access information

  ESP_LOGI(TAG, "Modbus slave stack initialized.");
  ESP_LOGI(TAG, "Start modbus test...");

  while (true) {
    // Check for read/write events of Modbus master for certain events
    (void)mbc_slave_check_event(MB_READ_WRITE_MASK);
    ESP_ERROR_CHECK_WITHOUT_ABORT(
        mbc_slave_get_param_info(&reg_info, MB_PAR_INFO_GET_TOUT)
    );
    const char *rw_str = (reg_info.type & MB_READ_MASK) ? "READ" : "WRITE";
    // Filter events and process them accordingly
    if (reg_info.type & (MB_EVENT_HOLDING_REG_WR | MB_EVENT_HOLDING_REG_RD)) {
      // Get parameter information from parameter queue
      ESP_LOGI(
          TAG,
          "HOLDING %s (%" PRIu32 " us), ADDR:%u, TYPE:%u, INST_ADDR:0x%" PRIx32
          ", SIZE:%u",
          rw_str, reg_info.time_stamp, (unsigned)reg_info.mb_offset,
          (unsigned)reg_info.type, (uint32_t)reg_info.address,
          (unsigned)reg_info.size
      );
    } else if (reg_info.type & MB_EVENT_INPUT_REG_RD) {
      ESP_LOGI(
          TAG,
          "INPUT READ (%" PRIu32 " us), ADDR:%u, TYPE:%u, INST_ADDR:0x%" PRIx32
          ", SIZE:%u",
          reg_info.time_stamp, (unsigned)reg_info.mb_offset,
          (unsigned)reg_info.type, (uint32_t)reg_info.address,
          (unsigned)reg_info.size
      );
    }
  }
}

static esp_err_t init_services(my_wifi_t *wifi) {
  esp_err_t result = nvs_flash_init();
  if (result == ESP_ERR_NVS_NO_FREE_PAGES ||
      result == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_ERROR_CHECK(nvs_flash_erase());
    result = nvs_flash_init();
  }
  MB_RETURN_ON_FALSE(
      (result == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "nvs_flash_init fail, returns(0x%x).", (int)result
  );
  result = esp_event_loop_create_default();
  MB_RETURN_ON_FALSE(
      (result == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "esp_event_loop_create_default fail, returns(0x%x).", (int)result
  );

  // Start mdns service and register device
  start_mdns_service();

  result = my_wifi_init(wifi);
  MB_RETURN_ON_FALSE(
      (result == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "esp_wifi_set_ps fail, returns(0x%x).", (int)result
  );

  result = esp_wifi_set_ps(WIFI_PS_NONE);
  MB_RETURN_ON_FALSE(
      (result == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "esp_wifi_set_ps fail, returns(0x%x).", (int)result
  );
  return ESP_OK;
}

static esp_err_t destroy_services(my_wifi_t *wifi) {
  esp_err_t err = ESP_OK;

  my_wifi_deinit(wifi);
  err = esp_event_loop_delete_default();
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "esp_event_loop_delete_default fail, returns(0x%x).", (int)err
  );
  err = esp_netif_deinit();
  MB_RETURN_ON_FALSE(
      (err == ESP_OK || err == ESP_ERR_NOT_SUPPORTED), ESP_ERR_INVALID_STATE,
      TAG, "esp_netif_deinit fail, returns(0x%x).", (int)err
  );
  err = nvs_flash_deinit();
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "nvs_flash_deinit fail, returns(0x%x).", (int)err
  );
  stop_mdns_service();
  return err;
}

// Modbus slave initialization
static esp_err_t slave_init(mb_communication_info_t *comm_info, regs_t *regs) {
  void *slave_handler = NULL;

  // Initialization of Modbus controller
  esp_err_t err = mbc_slave_init_tcp(&slave_handler);
  MB_RETURN_ON_FALSE(
      (err == ESP_OK && slave_handler != NULL), ESP_ERR_INVALID_STATE, TAG,
      "mb controller initialization fail."
  );

  // Setup communication parameters and start stack
  err = mbc_slave_setup((void *)comm_info);
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "mbc_slave_setup fail, returns(0x%x).", (int)err
  );

  err = regs_init(regs);
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "regs_init fail, returns(0x%x).", (int)err
  );

  err = mbc_slave_start();
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "mbc_slave_start fail, returns(0x%x).", (int)err
  );
  vTaskDelay(5);
  return err;
}

static esp_err_t slave_destroy(void) {
  esp_err_t err = mbc_slave_destroy();
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "mbc_slave_destroy fail, returns(0x%x).", (int)err
  );
  return err;
}

void app_main(void) {
  my_wifi_t wifi;
  ESP_ERROR_CHECK(init_services(&wifi));

  // Set UART log level
  esp_log_level_set(TAG, ESP_LOG_INFO);

  regs_t regs;
  mb_communication_info_t comm_info = {
      .ip_addr_type = MB_IPV4,
      .ip_mode = MB_MODE_TCP,
      .ip_port = MB_TCP_PORT_NUMBER,
      .ip_addr = NULL, // Bind to any address
      .ip_netif_ptr = (void *)wifi.netif,
      .slave_uid = MB_SLAVE_ADDR,
  };
  ESP_ERROR_CHECK(slave_init(&comm_info, &regs));

  modbus_loop();

  ESP_ERROR_CHECK(slave_destroy());
  ESP_ERROR_CHECK(destroy_services(&wifi));
}
