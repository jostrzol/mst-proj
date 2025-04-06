#pragma once

#include "driver/gptimer_types.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_err.h"
#include "freertos/FreeRTOS.h"

#include "ringbuffer.h"

typedef struct {
  uint64_t frequency;
  float revolution_treshold_close;
  float revolution_treshold_far;
  size_t revolution_bins;
  size_t reads_per_bin;
} controller_opts_t;

typedef struct {
  controller_opts_t opts;
  adc_oneshot_unit_handle_t adc;
  StaticSemaphore_t timer_semaphore_buf;
  SemaphoreHandle_t timer_semaphore;
  gptimer_handle_t timer;
  ringbuffer_t *revolutions;
  bool is_close;
} controller_t;

esp_err_t controller_init(controller_t *self, controller_opts_t opts);
void controller_deinit(controller_t *self);

void controller_read_loop(void *params);
