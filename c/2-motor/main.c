#include <bits/types/siginfo_t.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <i2c/smbus.h>
#include <linux/i2c-dev.h>
#include <pigpio.h>

#include "memory.h"
#include "perf.h"

#define I2C_ADAPTER_NUMBER "1"
const char I2C_ADAPTER_PATH[] = "/dev/i2c-" I2C_ADAPTER_NUMBER;
const uint32_t ADS7830_ADDRESS = 0x48;

const uint32_t MOTOR_LINE_NUMBER = 13;
const uint64_t PWM_FREQUENCY = 1000;

const uint64_t CONTROL_FREQUENCY = 10;
const uint64_t SLEEP_DURATION_US = 1e6 / CONTROL_FREQUENCY;

bool do_continue = true;

void interrupt_handler(int) {
  printf("\nGracefully stopping\n");
  do_continue = false;
}

// bit    7: single-ended inputs mode
// bits 6-4: channel selection
// bit    3: is internal reference enabled
// bit    2: is converter enabled
// bits 1-0: unused
const uint8_t DEFAULT_READ_COMMAND = 0b10001100;
#define MAKE_READ_COMMAND(channel) (DEFAULT_READ_COMMAND & ((channel) << 4))

int read_adc(int i2c_file, uint8_t *value) {
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

  res = ioctl(i2c_file, I2C_RDWR, &data);
  if (res < 0) {
    fprintf(stderr, "ioctl(RDWR) fail (%d): %s\n", res, strerror(errno));
    return -1;
  }

  *value = read_value;

  return 0;
}

int main(int, char **) {
  int res;

  printf("Controlling motor from C\n");

  res = gpioInitialise();
  if (res < 0) {
    fprintf(stderr, "gpioInitialise fail (%d)\n", res);
    return EXIT_FAILURE;
  }

  res = gpioSetSignalFunc(SIGINT, interrupt_handler);
  if (res != 0) {
    fprintf(stderr, "gpioSetSignalFunc fail (%d)\n", res);
    gpioTerminate();
    return EXIT_FAILURE;
  }

  res = gpioHardwarePWM(MOTOR_LINE_NUMBER, PWM_FREQUENCY, 0);
  if (res != 0) {
    fprintf(stderr, "gpioHardwarePWM fail (%d)\n", res);
    gpioTerminate();
    return EXIT_FAILURE;
  }

  int i2c_file = open(I2C_ADAPTER_PATH, O_RDWR);
  if (i2c_file < 0) {
    fprintf(stderr, "open(i2c) fail (%d): %s\n", i2c_file, strerror(errno));
    gpioTerminate();
    return EXIT_FAILURE;
  }

  res = ioctl(i2c_file, I2C_SLAVE, ADS7830_ADDRESS);
  if (res != 0) {
    fprintf(stderr, "ioctl(SLAVE) fail (%d): %s\n", i2c_file, strerror(errno));
    close(i2c_file);
    gpioTerminate();
    return EXIT_FAILURE;
  }

  perf_counter_t *perf;
  res = perf_counter_init(&perf, "MAIN", CONTROL_FREQUENCY * 2);
  if (res != 0) {
    fprintf(stderr, "perf_counter_init fail (%d)\n", res);
    close(i2c_file);
    gpioTerminate();
    return EXIT_FAILURE;
  }

  int64_t report_number = 0;

  while (do_continue) {
    for (size_t i = 0; i < CONTROL_FREQUENCY; ++i) {
      usleep(SLEEP_DURATION_US);

      perf_mark_t start = perf_mark();

      uint8_t value;
      res = read_adc(i2c_file, &value);
      if (res != 0) {
        fprintf(stderr, "read_adc fail (%d)\n", res);
        continue;
      }

#ifdef DEBUG
      printf("selected duty cycle: %.2f\n", (double)value / UINT8_MAX);
#endif

      const uint64_t duty_cycle = PI_HW_PWM_RANGE * value / UINT8_MAX;
      res = gpioHardwarePWM(MOTOR_LINE_NUMBER, PWM_FREQUENCY, duty_cycle);
      if (res != 0) {
        fprintf(stderr, "gpioHardwarePWM fail (%d)\n", res);
        continue;
      }

      perf_counter_add_sample(perf, start);
    }

    printf("# REPORT %lld\n", report_number);
    memory_report();
    perf_counter_report(perf);
    perf_counter_reset(perf);
    report_number += 1;
  }

  perf_counter_deinit(perf);
  close(i2c_file);
  res = gpioHardwarePWM(MOTOR_LINE_NUMBER, 0, 0);
  if (res)
    fprintf(stderr, "gpioHardwarePWM fail (%d)\n", res);
  gpioTerminate();

  return EXIT_SUCCESS;
}
