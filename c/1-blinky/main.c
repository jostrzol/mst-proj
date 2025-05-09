#include <bits/types/siginfo_t.h>
#include <errno.h>
#include <gpiod.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <unistd.h>

#include "memory.h"
#include "perf.h"

const char CONSUMER[] = "Consumer";
const char CHIPNAME[] = "gpiochip0";
const int32_t LINE_NUMBER = 13;

const int64_t BLINK_FREQUENCY = 10;
const int64_t UPDATE_FREQUENCY = BLINK_FREQUENCY * 2;
const int64_t SLEEP_DURATION_US = 1000000 / UPDATE_FREQUENCY;

bool do_continue = true;

void interrupt_handler(int) {
  printf("\nGracefully stopping\n");
  do_continue = false;
}
const struct sigaction interrupt_sigaction = {
    .sa_handler = &interrupt_handler,
};

int main(int, char **) {
  int res;

  printf("Controlling an LED from C\n");

  res = sigaction(SIGINT, &interrupt_sigaction, NULL);
  if (res != 0) {
    fprintf(stderr, "sigaction fail (%d): %s\n", res, strerror(errno));
    return EXIT_FAILURE;
  }

  struct gpiod_chip *chip = gpiod_chip_open_by_name(CHIPNAME);
  if (!chip) {
    fprintf(stderr, "gpiod_chip_open_by_name fail: %s\n", strerror(errno));
    return EXIT_FAILURE;
  }

  struct gpiod_line *line = gpiod_chip_get_line(chip, LINE_NUMBER);
  if (!line) {
    fprintf(stderr, "gpiod_chip_get_line fail: %s\n", strerror(errno));
    gpiod_chip_close(chip);
    return EXIT_FAILURE;
  }

  res = gpiod_line_request_output(line, CONSUMER, 0);
  if (res != 0) {
    fprintf(
        stderr, "gpiod_line_request_output fail (%d): %s\n", res,
        strerror(errno)
    );
    gpiod_line_release(line);
    gpiod_chip_close(chip);
    return EXIT_FAILURE;
  }

  bool is_on = false;

  perf_counter_t *perf;
  res = perf_counter_init(&perf, "MAIN", UPDATE_FREQUENCY * 2);
  if (res != 0) {
    fprintf(stderr, "perf_counter_init fail (%d): %s\n", res, strerror(errno));
    return EXIT_FAILURE;
  }

  while (do_continue) {
    for (size_t i = 0; i < UPDATE_FREQUENCY; ++i) {
      usleep(SLEEP_DURATION_US);

      const perf_mark_t start = perf_mark();

#ifdef DEBUG
      printf("Turning the LED %s", led_state ? "ON" : "OFF");
#endif

      res = gpiod_line_set_value(line, is_on);
      if (res != 0) {
        fprintf(
            stderr, "gpiod_line_set_value fail (%d): %s\n", res, strerror(errno)
        );
        continue;
      }

      is_on = !is_on;

      perf_counter_add_sample(perf, start);
    }

    memory_report();
    perf_counter_report(perf);
    perf_counter_reset(perf);
  }

  perf_counter_deinit(perf);
  res = gpiod_line_set_value(line, 0);
  if (res != 0) {
    fprintf(
        stderr, "gpiod_line_set_value fail (%d): %s\n", res, strerror(errno)
    );
  }
  gpiod_line_release(line);
  gpiod_chip_close(chip);

  return EXIT_SUCCESS;
}
