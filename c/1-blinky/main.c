#include <bits/types/siginfo_t.h>
#include <gpiod.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

const char CONSUMER[] = "Consumer";
const char CHIPNAME[] = "gpiochip0";
const int32_t LINE_NUMBER = 14;

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
  int ret;

  ret = sigaction(SIGINT, &interrupt_sigaction, NULL);
  if (ret < 0) {
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

  ret = gpiod_line_request_output(line, CONSUMER, 0);
  if (ret < 0) {
    perror("Request line as output failed\n");
    gpiod_line_release(line);
    gpiod_chip_close(chip);
    return EXIT_FAILURE;
  }

  printf("Blinking an LED from C\n");

  uint8_t line_value = 0;
  while (do_continue) {
    usleep(SLEEP_DURATION_US);

    ret = gpiod_line_set_value(line, line_value);
    if (ret < 0) {
      perror("Set line output failed\n");
      continue;
    }

    line_value = !line_value;
  }

  ret = gpiod_line_set_value(line, 0);
  if (ret < 0) {
    perror("Set line output failed\n");
  }

  gpiod_line_release(line);
  gpiod_chip_close(chip);
  return EXIT_SUCCESS;
}
