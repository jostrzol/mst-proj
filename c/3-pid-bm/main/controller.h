#pragma once

#include "driver/gptimer_types.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_err.h"

#include "freertos/idf_additions.h"
#include "registers.h"
#include "ringbuffer.h"

typedef struct {
  /// Frequency of control phase, during which the following happens:
  /// * calculating the frequency for the current time window,
  /// * moving the time window forward,
  /// * updating duty cycle,
  /// * updating modbus registers.
  uint32_t control_frequency;
  /// Frequency is estimated for the current time window. That window is broken
  /// into [time_window_bins] bins and is moved every time the control phase
  /// takes place.
  size_t time_window_bins;
  /// Each bin in the time window gets [reads_per_bin] reads, before the next
  /// control phase fires. That means, that the read phase occurs with frequency
  /// equal to:
  ///     `control_frequency * reads_per_bin`
  /// , because every time the window moves (control phase), there must be
  /// [reads_per_bin] reads in the last bin already (read phase).
  uint32_t reads_per_bin;
  /// When ADC reads below this signal, the state is set to `close` to the
  /// motor magnet. If the state has changed, a new revolution is counted.
  float revolution_threshold_close;
  /// When ADC reads above this signal, the state is set to `far` from the
  /// motor magnet.
  float revolution_threshold_far;
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
