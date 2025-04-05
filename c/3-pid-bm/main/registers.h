#pragma once

#include "esp_err.h"

typedef struct {
  float frequency;
  float control_signal;
} __attribute__((aligned(1))) regs_input_t;

typedef struct {
  float target_frequency;
  float proportional_factor;
  float integration_time;
  float differentiation_time;
} __attribute__((aligned(1))) regs_holding_t;

typedef struct {
  regs_input_t input;
  regs_holding_t holding;
} regs_t;

esp_err_t regs_init(regs_t *self);
