#pragma once

#include "driver/gptimer_types.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_err.h"
#include "freertos/idf_additions.h"

#include "perf.h"
#include "registers.h"
#include "ringbuffer.h"

typedef struct {
  uint64_t frequency;
  float revolution_treshold_close;
  float revolution_treshold_far;
  size_t revolution_bins;
  size_t reads_per_bin;
} controller_opts_t;

typedef struct {
  float delta;
  float integration_component;
} feedback_t;

typedef struct {
  controller_opts_t opts;
  regs_t *regs;
  adc_oneshot_unit_handle_t adc;
  struct {
    SemaphoreHandle_t semaphore;
    gptimer_handle_t handle;
  } timer;
  struct {
    float rotate_once_s;
    float rotate_all_s;
  } interval;
  struct {
    ringbuffer_t *revolutions;
    bool is_close;
    feedback_t feedback;
  } state;
} controller_t;

esp_err_t
controller_init(controller_t *self, regs_t *regs, controller_opts_t opts);
void controller_deinit(controller_t *self);

void controller_loop(void *params);
