#pragma once

#include "mb_endianness_utils.h"

typedef struct {
  val_32_arr frequency;
  val_32_arr control_signal;
} __attribute__((aligned(1))) registers_input_t;

typedef struct {
  val_32_arr target_frequency;
  val_32_arr proportional_factor;
  val_32_arr integration_time;
  val_32_arr differentiation_time;
} __attribute__((aligned(1))) registers_holding_t;

typedef struct {
  registers_input_t input;
  registers_holding_t holding;
} registers_t;

void registers_init(registers_t *registers);
