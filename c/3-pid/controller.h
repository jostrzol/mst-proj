#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <modbus.h>

#include "perf.h"
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
  uint8_t revolution_treshold_close;
  /// When ADC reads above this signal, the state is set to `far` from the
  /// motor magnet.
  uint8_t revolution_treshold_far;
  /// Linux PWM channel to use.
  uint8_t pwm_channel;
  /// Frequency of the PWM signal.
  uint64_t pwm_frequency;
} controller_options_t;

typedef struct {
  float delta;
  float integration_component;
} feedback_t;

typedef struct {
  controller_options_t options;
  modbus_mapping_t *registers;
  int i2c_fd;
  int timer_fd;
  struct {
    float rotate_once_s;
    float rotate_all_s;
  } interval;
  struct {
    ringbuffer_t *revolutions;
    bool is_close;
    feedback_t feedback;
    uint64_t iteration;
  } state;
  struct {
    perf_counter_t *read;
    perf_counter_t *control;
  } perf;
} controller_t;

int controller_init(
    controller_t *self, modbus_mapping_t *registers,
    controller_options_t options
);

void controller_deinit(controller_t *self);

int controller_handle(controller_t *self, int fd);
