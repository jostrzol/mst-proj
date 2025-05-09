#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <modbus.h>

#include "perf.h"
#include "ringbuffer.h"

typedef struct {
  /// Interval between ADC reads.
  uint64_t read_interval_us;
  /// When ADC reads below this signal, the state is set to `close` to the
  /// motor magnet. If the state has changed, a new revolution is counted.
  uint8_t revolution_treshold_close;
  /// When ADC reads above this signal, the state is set to `far` from the
  /// motor magnet.
  uint8_t revolution_treshold_far;
  /// Revolutions are binned in a ring buffer based on when they happened.
  /// More recent revolutions are in the tail of the buffer, while old ones
  /// are in the head of the buffer (soon to be replaced).
  ///
  /// [revolution_bins] is the number of bins in the ring buffer.
  size_t revolution_bins;
  /// [control_interval_us] is the interval at which all the following happens:
  /// * calculating the frequency for the current time window,
  /// * updating duty cycle,
  /// * updating duty cycle.
  ///
  /// [control_interval_us] also is the interval that each of the bins in the
  /// time window correspond to.
  ///
  /// If `control_interval_us = 100_000_000`, then:
  /// * the last bin corresponds to range `0..-100 ms` from now,
  /// * the second-to-last bin corresponds to range `-100..-200 ms` from now,
  /// * and so on.
  ///
  /// In total, frequency is counted from revolutions in all bins, across the
  /// total interval of [revolution_bins] * [control_interval_us].
  uint64_t control_interval_us;
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
  ringbuffer_t *revolutions;
  controller_options_t options;
  modbus_mapping_t *registers;
  int i2c_fd;
  int read_timer_fd;
  int io_timer_fd;
  bool is_close;
  feedback_t feedback;
  size_t iteration;
  perf_counter_t perf_read;
  perf_counter_t perf_control;
} controller_t;

int controller_init(
    controller_t *self, modbus_mapping_t *registers,
    controller_options_t options
);

void controller_close(controller_t *self);

int controller_handle(controller_t *self, int fd);
