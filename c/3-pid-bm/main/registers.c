#include <math.h>

#include "esp_modbus_common.h"
#include "esp_modbus_slave.h"
#include "registers.h"

static const char *TAG = "registers";

esp_err_t regs_init(regs_t *self) {
  esp_err_t err;

  *self = (regs_t){
      .input =
          {
              .frequency = 0,
              .control_signal = 0,
          },
      .holding =
          {
              .target_frequency = 0,
              .proportional_factor = 0,
              .integration_time = INFINITY,
              .differentiation_time = 0,
          },
  };

  err = mbc_slave_set_descriptor((mb_register_area_descriptor_t){
      .type = MB_PARAM_INPUT,
      .start_offset = 0,
      .address = &self->input,
      .size = sizeof(self->input),
  });
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "mbc_slave_set_descriptor fail, returns(0x%x).", (int)err
  );

  err = mbc_slave_set_descriptor((mb_register_area_descriptor_t){
      .type = MB_PARAM_HOLDING,
      .start_offset = 0,
      .address = &self->holding,
      .size = sizeof(self->holding),
  });
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "mbc_slave_set_descriptor fail, returns(0x%x).", (int)err
  );

  return ESP_OK;
}
