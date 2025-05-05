#include <bits/types/siginfo_t.h>
#include <fcntl.h>
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

const uint64_t PWM_FREQUENCY = 1000;
const uint64_t REFRESH_RATE = 60;
const uint64_t SLEEP_DURATION_US = 1e6 / REFRESH_RATE;

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
#define MAKE_READ_COMMAND(channel) (DEFAULT_READ_COMMAND & (channel << 4))

int32_t read_potentiometer_value(int i2c_file) {
  if (i2c_smbus_write_byte(i2c_file, MAKE_READ_COMMAND(0)) < 0) {
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
  printf("Controlling motor from C\n");

  if (gpioInitialise() < 0) {
    perror("pigpio initialization failed\n");
    return EXIT_FAILURE;
  }

  if (gpioSetSignalFunc(SIGINT, interrupt_handler)) {
    perror("Setting sigaction failed\n");
    gpioTerminate();
    return EXIT_FAILURE;
  }

  int i2c_file = open(I2C_ADAPTER_PATH, O_RDWR);
  if (i2c_file < 0) {
    perror("opening i2c adapter failed\n");
    gpioTerminate();
    return EXIT_FAILURE;
  }

  if (ioctl(i2c_file, I2C_SLAVE, ADS7830_ADDRESS) < 0) {
    perror("assigning i2c adapter address failed\n");
    gpioTerminate();
    return EXIT_FAILURE;
  }

  while (do_continue) {
    usleep(SLEEP_DURATION_US);

    int32_t value = read_potentiometer_value(i2c_file);
    if (value < 0)
      continue;

#ifdef DEBUG
    printf("selected duty cycle: %.2f\n", (double)value / UINT8_MAX);
#endif

    const uint64_t duty_cycle = PI_HW_PWM_RANGE * value / UINT8_MAX;
    if (gpioHardwarePWM(MOTOR_LINE_NUMBER, PWM_FREQUENCY, duty_cycle) < 0)
      perror("Setting PWM failed\n");
  }

  if (gpioHardwarePWM(MOTOR_LINE_NUMBER, 0, 0))
    perror("Disabling PWM failed\n");

  gpioTerminate();
  return EXIT_SUCCESS;
}
