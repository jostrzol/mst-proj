#pragma once

#include "esp_adc/adc_oneshot.h"
#include "esp_err.h"

typedef struct {
  adc_oneshot_unit_handle_t adc;
} controller_t;

esp_err_t controller_init(controller_t *self);
void controller_deinit(controller_t *self);

void controller_read_loop(void *params);
