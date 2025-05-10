#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <modbus.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/timerfd.h>
#include <unistd.h>

#include <i2c/smbus.h>
#include <linux/i2c-dev.h>
#include <pigpio.h>

#include "controller.h"
#include "memory.h"
#include "registers.h"
#include "units.h"

#define PWM_MIN 0.2
#define PWM_MAX 1.0
#define LIMIT_MIN_DEADZONE 0.001

#define I2C_ADAPTER_NUMBER "1"
const char I2C_ADAPTER_PATH[] = "/dev/i2c-" I2C_ADAPTER_NUMBER;
const uint32_t ADS7830_ADDRESS = 0x48;

// bit    7: single-ended inputs mode
// bits 6-4: channel selection
// bit    3: is internal reference enabled
// bit    2: is converter enabled
// bits 1-0: unused
const uint8_t DEFAULT_READ_COMMAND = 0b10001100;
#define MAKE_READ_COMMAND(channel) (DEFAULT_READ_COMMAND & (channel << 4))

int read_adc(controller_t *self, uint8_t *value) {
  int res;

  uint8_t write_value = MAKE_READ_COMMAND(0);
  uint8_t read_value;

  struct i2c_msg msgs[2] = {
      // write command
      {.addr = ADS7830_ADDRESS, .flags = 0, .len = 1, .buf = &write_value},
      // read data
      {.addr = ADS7830_ADDRESS, .flags = I2C_M_RD, .len = 1, .buf = &read_value}
  };
  const struct i2c_rdwr_ioctl_data data = {.msgs = msgs, .nmsgs = 2};

  res = ioctl(self->i2c_fd, I2C_RDWR, &data);
  if (res < 0) {
    fprintf(stderr, "ioctl fail (%d)\n", res);
    return -1;
  }

  *value = read_value;

  return 0;
}

int set_duty_cycle(controller_t *self, float value) {
  int res;
  res = gpioHardwarePWM(
      self->options.pwm_channel, self->options.pwm_frequency,
      PI_HW_PWM_RANGE * value
  );
  if (res != 0) {
    fprintf(stderr, "gpioHardwarePWM fail (%d)\n", res);
    return -1;
  }

  return 0;
}

struct itimerspec interval_from_us(uint64_t us) {
  const struct timespec timespec = {
      .tv_sec = us / MICRO_PER_1,
      .tv_nsec = (us * NANO_PER_MIRCO) % NANO_PER_1,
  };
  return (struct itimerspec){
      .it_interval = timespec,
      .it_value = timespec,
  };
}

float finite_or_zero(float value) { return isfinite(value) ? value : 0; }

float limit(float value, float min, float max) {
  if (value < LIMIT_MIN_DEADZONE)
    return 0;

  const float result = value + min;
  return result < min ? min : (result > max ? max : result);
}

float calculate_frequency(controller_t *self) {
  uint32_t sum = 0;
  for (size_t i = 0; i < self->state.revolutions->length; ++i)
    sum += self->state.revolutions->array[i];

  return (float)sum / self->interval.rotate_all_s;
}

typedef struct {
  float target_frequency;
  float proportional_factor;
  float integration_time;
  float differentiation_time;
} control_params_t;

control_params_t read_control_params(controller_t *self) {
  uint16_t *registers = self->registers->tab_registers;
  return (control_params_t){
      .target_frequency =
          modbus_get_float_abcd(&registers[REG_TARGET_FREQUENCY]),
      .proportional_factor =
          modbus_get_float_abcd(&registers[REG_PROPORTIONAL_FACTOR]),
      .integration_time =
          modbus_get_float_abcd(&registers[REG_INTEGRATION_TIME]),
      .differentiation_time =
          modbus_get_float_abcd(&registers[REG_DIFFERENTIATION_TIME]),
  };
}

typedef struct {
  float signal;
  feedback_t feedback;
} control_t;

control_t calculate_control(
    controller_t *self, control_params_t const *params, float frequency
) {
  const float interval_s = self->interval.rotate_once_s;

  const float integration_factor =
      params->proportional_factor / params->integration_time * interval_s;
  const float differentiation_factor =
      params->proportional_factor * params->differentiation_time / interval_s;

  const float delta = params->target_frequency - frequency;
#ifdef DEBUG
  printf("delta: %.2f\n", delta);
#endif

  const float proportional_component = params->proportional_factor * delta;
  const float integration_component =
      self->state.feedback.integration_component +
      integration_factor * self->state.feedback.delta;
  const float differentiation_component =
      differentiation_factor * (delta - self->state.feedback.delta);

  const float control_signal = proportional_component + integration_component +
                               differentiation_component;
#ifdef DEBUG
  printf(
      "control_signal: %.2f = %.2f + %.2f + %.2f\n", control_signal,
      proportional_component, integration_component, differentiation_component
  );
#endif

  return (control_t
  ){.signal = control_signal,
    .feedback = {
        .delta = finite_or_zero(delta),
        .integration_component = finite_or_zero(integration_component),
    }};
}

void write_state(controller_t *self, float frequency, float control_signal) {
  uint16_t *registers = self->registers->tab_input_registers;
  modbus_set_float_badc(frequency, &registers[REG_FREQUENCY]);
  modbus_set_float_badc(control_signal, &registers[REG_CONTROL_SIGNAL]);
}

int controller_init(
    controller_t *self, modbus_mapping_t *registers,
    controller_options_t options
) {
  int res = 0;

  ringbuffer_t *revolutions;
  res = ringbuffer_init(&revolutions, options.time_window_bins);
  if (res != 0) {
    fprintf(stderr, "ringbuffer_init fail (%d)\n", res);
    return -1;
  }

  const int i2c_fd = open(I2C_ADAPTER_PATH, O_RDWR);
  if (i2c_fd < 0) {
    fprintf(stderr, "i2c_fd fail (%d)\n", i2c_fd);
    ringbuffer_deinit(revolutions);
    return -1;
  }

  res = ioctl(i2c_fd, I2C_SLAVE, ADS7830_ADDRESS);
  if (res != 0) {
    fprintf(stderr, "ioctl fail (%d)\n", res);
    close(i2c_fd);
    ringbuffer_deinit(revolutions);
    return -1;
  }

  const int timer_fd = timerfd_create(CLOCK_REALTIME, 0);
  if (timer_fd < 0) {
    fprintf(stderr, "timerfd_create fail (%d)\n", timer_fd);
    close(i2c_fd);
    ringbuffer_deinit(revolutions);
    return -1;
  }

  const uint64_t read_frequency =
      options.control_frequency * options.reads_per_bin;
  const uint64_t read_interval_us = MICRO_PER_1 / read_frequency;

  const struct itimerspec timerspec = interval_from_us(read_interval_us);
  res = timerfd_settime(timer_fd, 0, &timerspec, NULL) != 0;
  if (res != 0) {
    fprintf(stderr, "timerfd_settime fail (%d)\n", res);
    close(timer_fd);
    close(i2c_fd);
    ringbuffer_deinit(revolutions);
    return -1;
  }

  perf_counter_t *perf_read;
  res = perf_counter_init(&perf_read, "READ", read_frequency * 2);
  if (res != 0) {
    fprintf(stderr, "perf_counter_init fail (%d)\n", res);
    close(timer_fd);
    close(i2c_fd);
    ringbuffer_deinit(revolutions);
    return -1;
  }

  perf_counter_t *perf_control;
  res = perf_counter_init(
      &perf_control, "CONTROL", options.control_frequency * 2
  );
  if (res != 0) {
    fprintf(stderr, "perf_counter_init fail (%d)\n", res);
    perf_counter_deinit(perf_read);
    close(timer_fd);
    close(i2c_fd);
    ringbuffer_deinit(revolutions);
    return -1;
  }

  const float interval_rotate_once_s = (float)1 / options.control_frequency;
  const float interval_rotate_all_s =
      interval_rotate_once_s * options.time_window_bins;

  *self = (controller_t){
      .registers = registers,
      .options = options,
      .i2c_fd = i2c_fd,
      .timer_fd = timer_fd,
      .interval =
          {
              .rotate_once_s = interval_rotate_once_s,
              .rotate_all_s = interval_rotate_all_s,
          },
      .state =
          {
              .revolutions = revolutions,
              .is_close = false,
              .feedback = {.delta = 0, .integration_component = 0},
              .iteration = 1,
          },
      .perf =
          {
              .read = perf_read,
              .control = perf_control,
          },
  };

  return 0;
}

void controller_deinit(controller_t *self) {
  int res;

  perf_counter_deinit(self->perf.control);
  perf_counter_deinit(self->perf.read);

  res = close(self->timer_fd);
  if (res != 0)
    fprintf(stderr, "close(timer_fd) fail (%d): %s\n", res, strerror(errno));

  res = close(self->i2c_fd);
  if (res != 0)
    fprintf(stderr, "close(i2c_fd) fail (%d): %s\n", res, strerror(errno));

  res = gpioHardwarePWM(self->options.pwm_channel, 0, 0);
  if (res != 0)
    fprintf(stderr, "gpioHardwarePWM fail (%d): %s\n", res, strerror(errno));

  ringbuffer_deinit(self->state.revolutions);
}

int read_phase(controller_t *self) {
  int res;

  uint8_t value;
  res = read_adc(self, &value);
  if (res != 0) {
    fprintf(stderr, "read_adc fail (%d)\n", res);
    return -1;
  }

  if (value < self->options.revolution_treshold_close &&
      !self->state.is_close) {
    // gone close
    self->state.is_close = true;
    *ringbuffer_back(self->state.revolutions) += 1;
  } else if (value > self->options.revolution_treshold_far &&
             self->state.is_close) {
    // gone far
    self->state.is_close = false;
  }

  return 0;
}

int control_phase(controller_t *self) {
  int res;

  const float frequency = calculate_frequency(self);
  ringbuffer_push(self->state.revolutions, 0);

  const control_params_t params = read_control_params(self);

  const control_t control = calculate_control(self, &params, frequency);

  const float control_signal_limited = limit(control.signal, PWM_MIN, PWM_MAX);
#ifdef DEBUG
  printf("control_signal_limited: %.2f", control_signal_limited);
#endif

  write_state(self, frequency, control_signal_limited);
  res = set_duty_cycle(self, control_signal_limited);
  if (res != 0) {
    fprintf(stderr, "set_duty_cycle fail (%d)\n", res);
    return -1;
  }

  self->state.feedback = control.feedback;

#ifdef DEBUG
  printf("frequency: %.2f", frequency);
#endif

  return 0;
}

int controller_handle(controller_t *self, int fd) {
  int res;

  if (fd != self->timer_fd)
    return 0;

  uint64_t expirations;
  res = read(fd, &expirations, sizeof(typeof(expirations)));
  if (res < 0) {
    fprintf(stderr, "read fail (%d)\n", res);
    return -1;
  }

  perf_mark_t read_start = perf_mark();
  read_phase(self);
  perf_counter_add_sample(self->perf.read, read_start);

  if (self->state.iteration % self->options.reads_per_bin == 0) {
    perf_mark_t control_start = perf_mark();
    control_phase(self);
    perf_counter_add_sample(self->perf.control, control_start);
  }

  const size_t reads_per_report =
      self->options.reads_per_bin * self->options.control_frequency;
  if (self->state.iteration % reads_per_report == 0) {
    const uint64_t report_number = self->state.iteration / reads_per_report - 1;
    printf("# REPORT %lld\n", report_number);
    memory_report();
    perf_counter_report(self->perf.read);
    perf_counter_report(self->perf.control);
    perf_counter_reset(self->perf.read);
    perf_counter_reset(self->perf.control);
  }

  self->state.iteration += 1;

  return 1;
}
