#include <bits/types/siginfo_t.h>
#include <fcntl.h>
#include <i2c/smbus.h>
#include <linux/i2c-dev.h>
#include <pigpio.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "pid.h"

const uint64_t READ_RATE = 1000;
const uint64_t READ_INTERVAL_US = 1e6 / READ_RATE;

const struct pid_settings_t pid_settings = {
    .read_interval_us = READ_INTERVAL_US,
    .revolution_treshold_close = 105,
    .revolution_treshold_far = 118,
    .revolution_bins = 10,
    .revolution_bin_rotate_interval_us = 100 * 1e3,
    .pwm_channel = 13,
    .pwm_frequency = 1000.,
};

bool do_continue = true;

void interrupt_handler(int) {
  printf("\nGracefully stopping\n");
  do_continue = false;
}
const struct sigaction interrupt_sigaction = {
    .sa_handler = &interrupt_handler,
};

int main(int, char **) {
  int ret;

  ret = sigaction(SIGINT, &interrupt_sigaction, NULL);
  if (ret < 0) {
    perror("Setting sigaction failed\n");
    goto end;
  }

  while (do_continue) {
  }

end:
  return EXIT_SUCCESS;
}
