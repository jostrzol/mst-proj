#include "server.h"
#include "esp_modbus_common.h"
#include "esp_modbus_slave.h"

#define SERVER_PORT_NUMBER (5502)
#define SERVER_MODBUS_ADDRESS (0)

#define SERVER_PAR_INFO_GET_TOUT (10) // Timeout for get parameter info

#define MB_READ_MASK                                                           \
  (MB_EVENT_INPUT_REG_RD | MB_EVENT_HOLDING_REG_RD | MB_EVENT_DISCRETE_RD |    \
   MB_EVENT_COILS_RD)
#define MB_WRITE_MASK (MB_EVENT_HOLDING_REG_WR | MB_EVENT_COILS_WR)
#define MB_READ_WRITE_MASK (MB_READ_MASK | MB_WRITE_MASK)

#define MB_HOLDING_MASK (MB_EVENT_HOLDING_REG_WR | MB_EVENT_HOLDING_REG_RD)
#define MB_INPUT_MASK (MB_EVENT_INPUT_REG_RD)

static const char TAG[] = "server";

esp_err_t server_init(server_t *self, server_options_t *options) {
  esp_err_t err;

  // Init
  err = mbc_slave_init_tcp(&self->handle);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "mbc_slave_init_tcp fail (0x%x)", (int)err);
    return err;
  }

  mb_communication_info_t comm_info = {
      .ip_addr_type = MB_IPV4,
      .ip_mode = MB_MODE_TCP,
      .ip_port = SERVER_PORT_NUMBER,
      .ip_addr = NULL, // Bind to any address
      .ip_netif_ptr = options->netif,
      .slave_uid = SERVER_MODBUS_ADDRESS,
  };
  err = mbc_slave_setup(&comm_info);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "mbc_slave_setup fail (0x%x)", (int)err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(mbc_slave_destroy());
    return err;
  }

  // Set registers
  err = mbc_slave_set_descriptor((mb_register_area_descriptor_t){
      .type = MB_PARAM_INPUT,
      .start_offset = 0,
      .address = &options->registers->input,
      .size = sizeof(options->registers->input),
  });
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "mbc_slave_set_descriptor (input) fail (0x%x)", (int)err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(mbc_slave_destroy());
    return err;
  }

  err = mbc_slave_set_descriptor((mb_register_area_descriptor_t){
      .type = MB_PARAM_HOLDING,
      .start_offset = 0,
      .address = &options->registers->holding,
      .size = sizeof(options->registers->holding),
  });
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "mbc_slave_set_descriptor (holding) fail (0x%x)", (int)err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(mbc_slave_destroy());
    return err;
  }

  // Start
  err = mbc_slave_start();
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "mbc_slave_start fail (0x%x)", (int)err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(mbc_slave_destroy());
    return err;
  }

  // TODO: is this needed?
  vTaskDelay(5);

  return ESP_OK;
}

void server_deinit(server_t *self) {
  ESP_ERROR_CHECK_WITHOUT_ABORT(mbc_slave_destroy());
}

esp_err_t server_iteration() {
  mb_param_info_t reg_info;

  mbc_slave_check_event(MB_READ_WRITE_MASK);

  esp_err_t err = mbc_slave_get_param_info(&reg_info, SERVER_PAR_INFO_GET_TOUT);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "mbc_slave_get_param_info fail (0x%x)", (int)err);
    return err;
  }

  if (reg_info.type & MB_READ_MASK)
    return ESP_OK; // Don't log reads

  const char *rw_str = (reg_info.type & MB_READ_MASK) ? "READ" : "WRITE";

  const char *type_str;
  if (reg_info.type & MB_HOLDING_MASK) {
    type_str = "HOLDING";
  } else if (reg_info.type & MB_INPUT_MASK) {
    type_str = "INPUT";
  } else {
    type_str = "UNKNOWN";
  }

  ESP_LOGI(
      TAG,
      "%s %s (%" PRIu32 " us), ADDR:%u, TYPE:%u, INST_ADDR:0x%" PRIxPTR
      ", SIZE:%u",
      type_str, rw_str, reg_info.time_stamp, (unsigned)reg_info.mb_offset,
      (unsigned)reg_info.type, (uintptr_t)reg_info.address,
      (unsigned)reg_info.size
  );

  return ESP_OK;
}

void server_loop(void *params) {
  ESP_LOGI(TAG, "Listening for modbus requests...");

  while (true)
    ESP_ERROR_CHECK_WITHOUT_ABORT(server_iteration());
}
