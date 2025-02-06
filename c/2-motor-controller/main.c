#include <bits/types/siginfo_t.h>
#include <fcntl.h>
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <i2c/smbus.h>
#include <linux/i2c-dev.h>
#include <pigpio.h>

#define I2C_ADAPTER_NUMBER "1"
const char I2C_ADAPTER_PATH[] = "/dev/i2c-" I2C_ADAPTER_NUMBER;
const uint32_t ADS7830_ADDRESS = 0x48;
const uint32_t MOTOR_LINE_NUMBER = 13;

const uint64_t PERIOD_MS = 5000;
const uint64_t PWM_CHANGES = 50;
const uint64_t PWM_MIN = 0.2 * PI_HW_PWM_RANGE;
const uint64_t PWM_MAX = 1.0 * PI_HW_PWM_RANGE;
const uint64_t PWM_FREQUENCY = 1000;
const uint64_t SLEEP_DURATION_NS = PERIOD_MS * 1000 / PWM_CHANGES;

bool do_continue = true;

void interrupt_handler(int) {
  printf("\nGracefully stopping\n");
  do_continue = false;
}

int32_t read_potentiometer_value(int i2c_file) {
  if (i2c_smbus_write_byte(i2c_file, 0x84) < 0) {
    perror("writing i2c ADC command failed\n");
    return -1;
  }

  int32_t value = i2c_smbus_read_byte(i2c_file);
  if (value < 0) {
    perror("reading i2c ADC value failed\n");
    return -1;
  }

  return value;
}

int main(int, char **) {
  if (gpioInitialise() < 0) {
    perror("pigpio initialization failed\n");
    goto end;
  }

  if (gpioSetSignalFunc(SIGINT, interrupt_handler)) {
    perror("Setting sigaction failed\n");
    goto end;
  }

  printf("%s", I2C_ADAPTER_PATH);
  int i2c_file = open(I2C_ADAPTER_PATH, O_RDWR);
  if (i2c_file < 0) {
    perror("opening i2c adapter failed\n");
    goto end;
  }

  if (ioctl(i2c_file, I2C_SLAVE, ADS7830_ADDRESS) < 0) {
    perror("assigning i2c adapter address failed\n");
    goto end;
  }

  printf("Controlling motor from C.\n");

  while (do_continue) {
    for (size_t i = 0; i < PWM_CHANGES; ++i) {
      int32_t value = read_potentiometer_value(i2c_file);
      if (value < 0)
        continue;

      printf("selected duty cycle: %.2f\n", (double)value / UINT8_MAX);

      // const double_t sin_value = sin((double_t)i / PWM_CHANGES * 2 * M_PI);
      // const double_t ratio = (sin_value + 1.) / 2.;
      const uint64_t duty_cycle =
          PWM_MIN + (PWM_MAX - PWM_MIN) * value / UINT8_MAX;
      if (gpioHardwarePWM(MOTOR_LINE_NUMBER, PWM_FREQUENCY, duty_cycle) < 0) {
        perror("Setting PWM failed\n");
        goto close_pigpio;
      }

      if (!do_continue)
        break;
      usleep(SLEEP_DURATION_NS);
    }
  }

  if (gpioHardwarePWM(MOTOR_LINE_NUMBER, 0, 0)) {
    perror("Disabling PWM failed\n");
  }

close_pigpio:
  gpioTerminate();
end:
  return EXIT_SUCCESS;
}
