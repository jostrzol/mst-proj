#pragma once

#include "ringbuffer.h"
#include <modbus.h>
#include <stddef.h>
#include <stdint.h>

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
  /// Revolutions are binned in a ring buffer based on when they happened.
  /// More recent revolutions are in the tail of the buffer, while old ones
  /// are in the head of the buffer (soon to be replaced).
  ///
  /// [revolution_bin_rotate_interval] is the interval that each of the bins
  /// correspond to.
  ///
  /// If `revolution_bin_rotate_interval = Duration::from_millis(100)`, then:
  /// * the last bin corresponds to range `0..-100 ms` from now,
  /// * the second-to-last bin corresponds to range `-100..-200 ms` from now,
  /// * and so on.
  ///
  /// In total, frequency will be counted from revolutions in all bins, across
  /// the total interval of [revolution_bins] *
  /// [revolution_bin_rotate_interval].
  ///
  /// [revolution_bin_rotate_interval] is also the interval at which the
  /// measured frequency updates, so all the IO happens at this interval too.
  uint64_t revolution_bin_rotate_interval_us;
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
} controller_t;

int controller_init(
    controller_t *self, modbus_mapping_t *registers,
    controller_options_t options
);

void controller_close(controller_t *self);

int controller_handle(controller_t *self, int fd);
