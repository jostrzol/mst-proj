#pragma once

#include <modbus.h>

enum reg_input {
  // clang-format off
  FREQUENCY      = 2 * 0,
  CONTROL_SIGNAL = 2 * 1,
  // clang-format on
};
#define N_REG_INPUT 2

enum reg_holding {
  // clang-format off
  TARGET_FREQUENCY     = 2 * 0,
  PROPORTIONAL_FACTOR  = 2 * 1,
  INTEGRATION_TIME     = 2 * 2,
  DIFFERENTIATION_TIME = 2 * 3,
  // clang-format on
};
#define N_REG_HOLDING 4

modbus_mapping_t *registers_init();

void registers_free(modbus_mapping_t *self);
