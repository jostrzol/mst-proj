#include <bits/types/siginfo_t.h>
#include <gpiod.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

const char CONSUMER[] = "Consumer";
const char CHIPNAME[] = "gpiochip0";
const int32_t LINE_NUMBER = 13;

const int64_t PERIOD_MS = 100;
const int64_t SLEEP_DURATION_US = PERIOD_MS * 1000 / 2;

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
  if (res < 0) {
    perror("Setting sigaction failed\n");
    return EXIT_FAILURE;
  }

  struct gpiod_chip *chip = gpiod_chip_open_by_name(CHIPNAME);
  if (!chip) {
    perror("Open chip failed\n");
    return EXIT_FAILURE;
  }

  struct gpiod_line *line = gpiod_chip_get_line(chip, LINE_NUMBER);
  if (!line) {
    perror("Get line failed\n");
    gpiod_chip_close(chip);
    return EXIT_FAILURE;
  }

  res = gpiod_line_request_output(line, CONSUMER, 0);
  if (res < 0) {
    perror("Request line as output failed\n");
    gpiod_line_release(line);
    gpiod_chip_close(chip);
    return EXIT_FAILURE;
  }

  uint8_t is_on = 0;
  while (do_continue) {
    usleep(SLEEP_DURATION_US);

#ifdef DEBUG
    printf("Turning the LED %s", led_state ? "ON" : "OFF");
#endif

    res = gpiod_line_set_value(line, is_on);
    if (res < 0) {
      perror("Set line output failed\n");
      continue;
    }

    is_on = !is_on;
  }

  res = gpiod_line_set_value(line, 0);
  if (res < 0) {
    perror("Set line output failed\n");
  }

  gpiod_line_release(line);
  gpiod_chip_close(chip);
  return EXIT_SUCCESS;
}
