#pragma once

#include <modbus.h>

#define FLOAT_PER_U16 (sizeof(float) / sizeof(uint16_t))

enum reg_input {
  // clang-format off
  REG_FREQUENCY      = 2 * 0,
  REG_CONTROL_SIGNAL = 2 * 1,
  // clang-format on
};
#define N_REG_INPUT 2
#define REG_INPUT_SIZE_PER_U16 (N_REG_INPUT * FLOAT_PER_U16)

enum reg_holding {
  // clang-format off
  REG_TARGET_FREQUENCY     = 2 * 0,
  REG_PROPORTIONAL_FACTOR  = 2 * 1,
  REG_INTEGRATION_TIME     = 2 * 2,
  REG_DIFFERENTIATION_TIME = 2 * 3,
  // clang-format on
};
#define N_REG_HOLDING 4
#define REG_HOLDING_SIZE_PER_U16 (N_REG_HOLDING * FLOAT_PER_U16)

modbus_mapping_t *registers_init();

void registers_free(modbus_mapping_t *self);
