#include <fcntl.h>
#include <math.h>
#include <modbus.h>
#include <stdio.h>
#include <stdlib.h>
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

static const size_t CONTROL_ITERS_PER_PERF_REPORT = 10;

int32_t read_potentiometer_value(int i2c_file) {
  uint8_t write_value = MAKE_READ_COMMAND(0);
  uint8_t read_value;

  struct i2c_msg msgs[2] = {
      // write command
      {.addr = ADS7830_ADDRESS, .flags = 0, .len = 1, .buf = &write_value},
      // read data
      {.addr = ADS7830_ADDRESS, .flags = I2C_M_RD, .len = 1, .buf = &read_value}
  };
  const struct i2c_rdwr_ioctl_data data = {.msgs = msgs, .nmsgs = 2};

  if (ioctl(i2c_file, I2C_RDWR, &data) < 0) {
    perror("i2c read/write ADC command failed\n");
    return -1;
  }

  return read_value;
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

int controller_set_duty_cycle(controller_t *self, float value) {
  return gpioHardwarePWM(
      self->options.pwm_channel, self->options.pwm_frequency,
      PI_HW_PWM_RANGE * value
  );
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
  for (size_t i = 0; i < self->revolutions->length; ++i)
    sum += self->revolutions->array[i];

  const float interval_s =
      (float)self->options.control_interval_us / MICRO_PER_1;
  const float all_bins_interval_s = interval_s * self->options.revolution_bins;

  return (float)sum / all_bins_interval_s;
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
  const float interval_s =
      (float)self->options.control_interval_us / MICRO_PER_1;

  const float integration_factor =
      params->proportional_factor / params->integration_time * interval_s;
  const float differentiation_factor =
      params->proportional_factor * params->differentiation_time / interval_s;

  const float delta = params->target_frequency - frequency;
#ifdef DEBUG
  printf("delta: %.2f\n", delta);
#endif

  const float proportional_component = params->proportional_factor * delta;
  const float integration_component = self->feedback.integration_component +
                                      integration_factor * self->feedback.delta;
  const float differentiation_component =
      differentiation_factor * (delta - self->feedback.delta);

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
  ringbuffer_t *revolutions = ringbuffer_alloc(options.revolution_bins);

  const int i2c_fd = open(I2C_ADAPTER_PATH, O_RDWR);
  if (i2c_fd < 0) {
    return EXIT_FAILURE;
  }

  res = ioctl(i2c_fd, I2C_SLAVE, ADS7830_ADDRESS);
  if (res != 0) {
    close(i2c_fd);
    return EXIT_FAILURE;
  }

  const int read_timer_fd = timerfd_create(CLOCK_REALTIME, 0);
  if (read_timer_fd < 0) {
    close(i2c_fd);
    return EXIT_FAILURE;
  }

  const struct itimerspec read_timerspec =
      interval_from_us(options.read_interval_us);
  res = timerfd_settime(read_timer_fd, 0, &read_timerspec, NULL) != 0;
  if (res) {
    close(read_timer_fd);
    close(i2c_fd);
    return EXIT_FAILURE;
  }

  const int io_timer_fd = timerfd_create(CLOCK_REALTIME, 0);
  if (io_timer_fd < 0) {
    close(read_timer_fd);
    close(i2c_fd);
    return EXIT_FAILURE;
  }

  const struct itimerspec io_timerspec =
      interval_from_us(options.control_interval_us);
  res = timerfd_settime(io_timer_fd, 0, &io_timerspec, NULL);
  if (res != 0) {
    close(io_timer_fd);
    close(read_timer_fd);
    close(i2c_fd);
    return EXIT_FAILURE;
  }

  perf_counter_t perf_read;
  res = perf_counter_init(&perf_read, "READ");
  if (res != 0) {
    close(io_timer_fd);
    close(read_timer_fd);
    close(i2c_fd);
    return EXIT_FAILURE;
  }

  perf_counter_t perf_control;
  res = perf_counter_init(&perf_control, "CONTROL");
  if (res != 0) {
    close(io_timer_fd);
    close(read_timer_fd);
    close(i2c_fd);
    return EXIT_FAILURE;
  }

  *self = (controller_t){
      .registers = registers,
      .options = options,
      .revolutions = revolutions,
      .i2c_fd = i2c_fd,
      .read_timer_fd = read_timer_fd,
      .io_timer_fd = io_timer_fd,
      .feedback = {.delta = 0, .integration_component = 0},
      .iteration = 0,
      .perf_read = perf_read,
      .perf_control = perf_control,
  };

  return EXIT_SUCCESS;
}

void controller_close(controller_t *self) {
  if (close(self->io_timer_fd) != 0)
    perror("Failed to close IO timer");
  if (close(self->read_timer_fd) != 0)
    perror("Failed to close read timer");
  if (close(self->i2c_fd) != 0)
    perror("Failed to close i2c controller");
  if (gpioHardwarePWM(self->options.pwm_channel, 0, 0) != 0)
    perror("Failed to disable PWM");
}

int controller_handle(controller_t *self, int fd) {
  uint64_t expirations;

  if (fd == self->read_timer_fd) {
    if (read(fd, &expirations, sizeof(typeof(expirations))) < 0)
      return EXIT_FAILURE;

    perf_mark_t read_start = perf_mark();

    const int32_t value = read_potentiometer_value(self->i2c_fd);
    if (value < 0)
      return EXIT_FAILURE;

    if (value < self->options.revolution_treshold_close && !self->is_close) {
      // gone close
      self->is_close = true;
      *ringbuffer_back(self->revolutions) += 1;
    } else if (value > self->options.revolution_treshold_far &&
               self->is_close) {
      // gone far
      self->is_close = false;
    }

    perf_counter_add_sample(&self->perf_read, read_start);

    return 1;
  } else if (fd == self->io_timer_fd) {
    if (read(fd, &expirations, sizeof(typeof(expirations))) < 0)
      return EXIT_FAILURE;

    perf_mark_t control_start = perf_mark();

    const float frequency = calculate_frequency(self);
    ringbuffer_push(self->revolutions, 0);
#ifdef DEBUG
    printf("frequency: %.2f\n", frequency);
#endif

    const control_params_t control_params = read_control_params(self);

    const control_t control =
        calculate_control(self, &control_params, frequency);

    const float control_signal_limited =
        limit(control.signal, PWM_MIN, PWM_MAX);
#ifdef DEBUG
    printf("control_signal_limited: %.2f\n", control_signal_limited);
#endif

    write_state(self, frequency, control_signal_limited);
    controller_set_duty_cycle(self, control_signal_limited);

    self->feedback = control.feedback;

    perf_counter_add_sample(&self->perf_control, control_start);

    if (self->iteration % CONTROL_ITERS_PER_PERF_REPORT == 0) {
      memory_report();
      perf_counter_report(&self->perf_read);
      perf_counter_report(&self->perf_control);
      perf_counter_reset(&self->perf_read);
      perf_counter_reset(&self->perf_control);
    }
    self->iteration += 1;

    return 1;
  }

  return 0;
}
