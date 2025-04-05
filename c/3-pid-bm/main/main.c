#include <stdio.h>

#include "esp_err.h"
#include "esp_log.h"
#include "esp_modbus_slave.h"
#include "freertos/FreeRTOS.h" // IWYU pragma: keep
#include "sdkconfig.h"         // IWYU pragma: keep

#include "registers.h"
#include "services.h"
#include "wifi.h"

#define MB_TCP_PORT_NUMBER (5502)

#define MB_PAR_INFO_GET_TOUT (10) // Timeout for get parameter info

#define MB_READ_MASK                                                           \
  (MB_EVENT_INPUT_REG_RD | MB_EVENT_HOLDING_REG_RD | MB_EVENT_DISCRETE_RD |    \
   MB_EVENT_COILS_RD)
#define MB_WRITE_MASK (MB_EVENT_HOLDING_REG_WR | MB_EVENT_COILS_WR)
#define MB_READ_WRITE_MASK (MB_READ_MASK | MB_WRITE_MASK)

#define MB_SLAVE_ADDR (0)

static const char *TAG = "pid";

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
      "mbc_slave_setup fail (0x%x).", (int)err
  );

  err = regs_init(regs);
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG, "regs_init fail (0x%x).",
      (int)err
  );

  err = mbc_slave_start();
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "mbc_slave_start fail (0x%x).", (int)err
  );
  vTaskDelay(5);
  return err;
}

static esp_err_t slave_destroy(void) {
  esp_err_t err = mbc_slave_destroy();
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "mbc_slave_destroy fail (0x%x).", (int)err
  );
  return err;
}

void app_main(void) {
  esp_log_level_set(TAG, ESP_LOG_INFO);

  services_t services;
  ESP_ERROR_CHECK(services_init(&services));

  regs_t regs;
  mb_communication_info_t comm_info = {
      .ip_addr_type = MB_IPV4,
      .ip_mode = MB_MODE_TCP,
      .ip_port = MB_TCP_PORT_NUMBER,
      .ip_addr = NULL, // Bind to any address
      .ip_netif_ptr = (void *)services.wifi.netif,
      .slave_uid = MB_SLAVE_ADDR,
  };
  ESP_ERROR_CHECK(slave_init(&comm_info, &regs));

  modbus_loop();

  ESP_ERROR_CHECK(slave_destroy());
  services_deinit(&services);
}
