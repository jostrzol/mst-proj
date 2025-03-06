#pragma once

#include <stddef.h>
#include <stdint.h>

enum reg_input {
  // clang-format off
  FREQUENCY      = 2 * 0,
  CONTROL_SIGNAL = 2 * 1,
  // clang-format on
};
const size_t N_REG_INPUT = 2;

enum reg_holding {
  // clang-format off
  TARGET_FREQUENCY     = 2 * 0,
  PROPORTIONAL_FACTOR  = 2 * 1,
  INTEGRATION_TIME     = 2 * 2,
  DIFFERENTIATION_TIME = 2 * 3,
  // clang-format on
};
const size_t N_REG_HOLDING = 4;
