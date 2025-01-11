#include <bits/types/siginfo_t.h>
#include <math.h>
#include <pigpio.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

const uint64_t DUTY_CYCLE_MAX = 1000000;

const uint32_t LINE_NUMBER = 13;

const uint64_t PERIOD_MS = 5000;
const uint64_t PWM_CHANGES = 50;
const uint64_t PWM_MIN = 0.2 * DUTY_CYCLE_MAX;
const uint64_t PWM_MAX = 0.7 * DUTY_CYCLE_MAX;
const uint64_t PWM_FREQUENCY = 1000;
const uint64_t SLEEP_DURATION_NS = PERIOD_MS * 1000 / PWM_CHANGES;

bool do_continue = true;

void interrupt_handler(int) {
  printf("\nGracefully stopping\n");
  do_continue = false;
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

  printf("Controlling motor from C.\n");

  while (do_continue) {
    for (size_t i = 0; i < PWM_CHANGES; ++i) {
      const double_t sin_value = sin((double_t)i / PWM_CHANGES * 2 * M_PI);
      const double_t ratio = (sin_value + 1.) / 2.;
      const uint64_t duty_cycle = PWM_MIN + ratio * (PWM_MAX - PWM_MIN);
      if (gpioHardwarePWM(LINE_NUMBER, PWM_FREQUENCY, duty_cycle) < 0) {
        perror("Setting PWM failed\n");
        goto close_pigpio;
      }

      if (!do_continue)
        break;
      usleep(SLEEP_DURATION_NS);
    }
  }

  if (gpioHardwarePWM(LINE_NUMBER, 0, 0)) {
    perror("Disabling PWM failed\n");
  }

close_pigpio:
  gpioTerminate();
end:
  return EXIT_SUCCESS;
}
