#include <stdio.h>

#include "esp_err.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h" // IWYU pragma: keep
#include "mdns.h"
#include "nvs_flash.h"
#include "sdkconfig.h" // IWYU pragma: keep

#include "mbcontroller.h"  // for mbcontroller defines and api
#include "modbus_params.h" // for modbus parameters structures

#include "wifi.h"

#define MB_TCP_PORT_NUMBER (5502)
#define MB_MDNS_PORT (502)

// Defines below are used to define register start address for each type of
// Modbus registers
#define HOLD_OFFSET(field)                                                     \
  ((uint16_t)(offsetof(holding_reg_params_t, field) >> 1))
#define INPUT_OFFSET(field)                                                    \
  ((uint16_t)(offsetof(input_reg_params_t, field) >> 1))
#define MB_REG_DISCRETE_INPUT_START (0x0000)
#define MB_REG_COILS_START (0x0000)
#define MB_REG_INPUT_START_AREA0                                               \
  (INPUT_OFFSET(input_data0)) // register offset input area 0
#define MB_REG_INPUT_START_AREA1                                               \
  (INPUT_OFFSET(input_data4)) // register offset input area 1
#define MB_REG_HOLDING_START_AREA0 (HOLD_OFFSET(holding_data0))
#define MB_REG_HOLDING_START_AREA1 (HOLD_OFFSET(holding_data4))

#define MB_PAR_INFO_GET_TOUT (10) // Timeout for get parameter info
#define MB_CHAN_DATA_MAX_VAL (10)
#define MB_CHAN_DATA_OFFSET (1.1f)

#define MB_READ_MASK                                                           \
  (MB_EVENT_INPUT_REG_RD | MB_EVENT_HOLDING_REG_RD | MB_EVENT_DISCRETE_RD |    \
   MB_EVENT_COILS_RD)
#define MB_WRITE_MASK (MB_EVENT_HOLDING_REG_WR | MB_EVENT_COILS_WR)
#define MB_READ_WRITE_MASK (MB_READ_MASK | MB_WRITE_MASK)

#define MB_SLAVE_ADDR (0)

static const char *TAG = "pid";

static portMUX_TYPE param_lock = portMUX_INITIALIZER_UNLOCKED;

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

// Set register values into known state
static void setup_reg_data(void) {
  // Define initial state of parameters
  discrete_reg_params.discrete_input0 = 1;
  discrete_reg_params.discrete_input1 = 0;
  discrete_reg_params.discrete_input2 = 1;
  discrete_reg_params.discrete_input3 = 0;
  discrete_reg_params.discrete_input4 = 1;
  discrete_reg_params.discrete_input5 = 0;
  discrete_reg_params.discrete_input6 = 1;
  discrete_reg_params.discrete_input7 = 0;

  holding_reg_params.holding_data0 = 1.34;
  holding_reg_params.holding_data1 = 2.56;
  holding_reg_params.holding_data2 = 3.78;
  holding_reg_params.holding_data3 = 4.90;

  holding_reg_params.holding_data4 = 5.67;
  holding_reg_params.holding_data5 = 6.78;
  holding_reg_params.holding_data6 = 7.79;
  holding_reg_params.holding_data7 = 8.80;
  coil_reg_params.coils_port0 = 0x55;
  coil_reg_params.coils_port1 = 0xAA;

  input_reg_params.input_data0 = 1.12;
  input_reg_params.input_data1 = 2.34;
  input_reg_params.input_data2 = 3.56;
  input_reg_params.input_data3 = 4.78;
  input_reg_params.input_data4 = 1.12;
  input_reg_params.input_data5 = 2.34;
  input_reg_params.input_data6 = 3.56;
  input_reg_params.input_data7 = 4.78;
}

static void slave_operation_func(void *arg) {
  mb_param_info_t reg_info; // keeps the Modbus registers access information

  ESP_LOGI(TAG, "Modbus slave stack initialized.");
  ESP_LOGI(TAG, "Start modbus test...");
  // The cycle below will be terminated when parameter holding_data0
  // incremented each access cycle reaches the CHAN_DATA_MAX_VAL value.
  for (; holding_reg_params.holding_data0 < MB_CHAN_DATA_MAX_VAL;) {
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
      if (reg_info.address == (uint8_t *)&holding_reg_params.holding_data0) {
        portENTER_CRITICAL(&param_lock);
        holding_reg_params.holding_data0 += MB_CHAN_DATA_OFFSET;
        if (holding_reg_params.holding_data0 >=
            (MB_CHAN_DATA_MAX_VAL - MB_CHAN_DATA_OFFSET)) {
          coil_reg_params.coils_port1 = 0xFF;
        }
        portEXIT_CRITICAL(&param_lock);
      }
    } else if (reg_info.type & MB_EVENT_INPUT_REG_RD) {
      ESP_LOGI(
          TAG,
          "INPUT READ (%" PRIu32 " us), ADDR:%u, TYPE:%u, INST_ADDR:0x%" PRIx32
          ", SIZE:%u",
          reg_info.time_stamp, (unsigned)reg_info.mb_offset,
          (unsigned)reg_info.type, (uint32_t)reg_info.address,
          (unsigned)reg_info.size
      );
    } else if (reg_info.type & MB_EVENT_DISCRETE_RD) {
      ESP_LOGI(
          TAG,
          "DISCRETE READ (%" PRIu32
          " us), ADDR:%u, TYPE:%u, INST_ADDR:0x%" PRIx32 ", SIZE:%u",
          reg_info.time_stamp, (unsigned)reg_info.mb_offset,
          (unsigned)reg_info.type, (uint32_t)reg_info.address,
          (unsigned)reg_info.size
      );
    } else if (reg_info.type & (MB_EVENT_COILS_RD | MB_EVENT_COILS_WR)) {
      ESP_LOGI(
          TAG,
          "COILS %s (%" PRIu32 " us), ADDR:%u, TYPE:%u, INST_ADDR:0x%" PRIx32
          ", SIZE:%u",
          rw_str, reg_info.time_stamp, (unsigned)reg_info.mb_offset,
          (unsigned)reg_info.type, (uint32_t)reg_info.address,
          (unsigned)reg_info.size
      );
      if (coil_reg_params.coils_port1 == 0xFF)
        break;
    }
  }
  // Destroy of Modbus controller on alarm
  ESP_LOGI(TAG, "Modbus controller destroyed.");
  vTaskDelay(100);
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

  my_wifi_init(wifi);
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
static esp_err_t slave_init(mb_communication_info_t *comm_info) {
  mb_register_area_descriptor_t
      reg_area; // Modbus register area descriptor structure

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

  // The code below initializes Modbus register area descriptors
  // for Modbus Holding Registers, Input Registers, Coils and Discrete Inputs
  // Initialization should be done for each supported Modbus register area
  // according to register map. When external master trying to access the
  // register in the area that is not initialized by mbc_slave_set_descriptor()
  // API call then Modbus stack will send exception response for this register
  // area.
  reg_area.type = MB_PARAM_HOLDING; // Set type of register area
  reg_area.start_offset =
      MB_REG_HOLDING_START_AREA0; // Offset of register area in Modbus protocol
  reg_area.address = (void *)&holding_reg_params
                         .holding_data0; // Set pointer to storage instance
  reg_area.size = (MB_REG_HOLDING_START_AREA1 - MB_REG_HOLDING_START_AREA0)
                  << 1; // Set the size of register storage instance
  err = mbc_slave_set_descriptor(reg_area);
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "mbc_slave_set_descriptor fail, returns(0x%x).", (int)err
  );

  reg_area.type = MB_PARAM_HOLDING; // Set type of register area
  reg_area.start_offset =
      MB_REG_HOLDING_START_AREA1; // Offset of register area in Modbus protocol
  reg_area.address = (void *)&holding_reg_params
                         .holding_data4; // Set pointer to storage instance
  reg_area.size = sizeof(float)
                  << 2; // Set the size of register storage instance
  err = mbc_slave_set_descriptor(reg_area);
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "mbc_slave_set_descriptor fail, returns(0x%x).", (int)err
  );

  // Initialization of Input Registers area
  reg_area.type = MB_PARAM_INPUT;
  reg_area.start_offset = MB_REG_INPUT_START_AREA0;
  reg_area.address = (void *)&input_reg_params.input_data0;
  reg_area.size = sizeof(float) << 2;
  err = mbc_slave_set_descriptor(reg_area);
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "mbc_slave_set_descriptor fail, returns(0x%x).", (int)err
  );
  reg_area.type = MB_PARAM_INPUT;
  reg_area.start_offset = MB_REG_INPUT_START_AREA1;
  reg_area.address = (void *)&input_reg_params.input_data4;
  reg_area.size = sizeof(float) << 2;
  err = mbc_slave_set_descriptor(reg_area);
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "mbc_slave_set_descriptor fail, returns(0x%x).", (int)err
  );

  // Initialization of Coils register area
  reg_area.type = MB_PARAM_COIL;
  reg_area.start_offset = MB_REG_COILS_START;
  reg_area.address = (void *)&coil_reg_params;
  reg_area.size = sizeof(coil_reg_params);
  err = mbc_slave_set_descriptor(reg_area);
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "mbc_slave_set_descriptor fail, returns(0x%x).", (int)err
  );

  // Initialization of Discrete Inputs register area
  reg_area.type = MB_PARAM_DISCRETE;
  reg_area.start_offset = MB_REG_DISCRETE_INPUT_START;
  reg_area.address = (void *)&discrete_reg_params;
  reg_area.size = sizeof(discrete_reg_params);
  err = mbc_slave_set_descriptor(reg_area);
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "mbc_slave_set_descriptor fail, returns(0x%x).", (int)err
  );

  // Set values into known state
  setup_reg_data();

  // Starts of modbus controller and stack
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

// An example application of Modbus slave. It is based on freemodbus stack.
// See deviceparams.h file for more information about assigned Modbus
// parameters. These parameters can be accessed from main application and also
// can be changed by external Modbus master host.
void app_main(void) {
  my_wifi_t wifi;
  ESP_ERROR_CHECK(init_services(&wifi));

  // Set UART log level
  esp_log_level_set(TAG, ESP_LOG_INFO);

  mb_communication_info_t comm_info = {
      .ip_addr_type = MB_IPV4,
      .ip_mode = MB_MODE_TCP,
      .ip_port = MB_TCP_PORT_NUMBER,
      .ip_addr = NULL, // Bind to any address
      .ip_netif_ptr = (void *)wifi.netif,
      .slave_uid = MB_SLAVE_ADDR,
  };
  ESP_ERROR_CHECK(slave_init(&comm_info));

  // The Modbus slave logic is located in this function (user handling of
  // Modbus)
  slave_operation_func(NULL);

  ESP_ERROR_CHECK(slave_destroy());
  ESP_ERROR_CHECK(destroy_services(&wifi));
}
