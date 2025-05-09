#pragma once

#include "driver/gptimer_types.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_err.h"

#include "freertos/idf_additions.h"
#include "registers.h"
#include "ringbuffer.h"

typedef struct {
  uint64_t frequency;
  float revolution_treshold_close;
  float revolution_treshold_far;
  size_t revolution_bins;
  size_t reads_per_bin;
} controller_options_t;

typedef struct {
  float delta;
  float integration_component;
} feedback_t;

typedef struct {
  controller_options_t options;
  registers_t *registers;
  adc_oneshot_unit_handle_t adc;
  gptimer_handle_t timer;
  struct {
    float rotate_once_s;
    float rotate_all_s;
  } interval;
  struct {
    ringbuffer_t *revolutions;
    bool is_close;
    feedback_t feedback;
  } state;
  TaskHandle_t task;
} controller_t;

esp_err_t controller_init(
    controller_t *self, registers_t *registers, controller_options_t options
);
void controller_deinit(controller_t *self);

void controller_loop(void *params);
