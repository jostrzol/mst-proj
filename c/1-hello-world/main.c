#include <bits/types/siginfo_t.h>
#include <gpiod.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

const char consumer[] = "Consumer";
const char chipname[] = "gpiochip0";
const int32_t line_number = 14;

const int64_t period_ms = 1000;
const int64_t sleep_time_ns = period_ms * 1000 / 2;

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

  struct gpiod_chip *chip = gpiod_chip_open_by_name(chipname);
  if (!chip) {
    perror("Open chip failed\n");
    goto end;
  }

  struct gpiod_line *line = gpiod_chip_get_line(chip, line_number);
  if (!line) {
    perror("Get line failed\n");
    goto close_chip;
  }

  ret = gpiod_line_request_output(line, consumer, 0);
  if (ret < 0) {
    perror("Request line as output failed\n");
    goto release_line;
  }

  printf("Blinking LED from C\n");

  uint8_t line_value = 0;
  while (do_continue) {
    ret = gpiod_line_set_value(line, line_value);
    if (ret < 0) {
      perror("Set line output failed\n");
      goto release_line;
    }
    usleep(sleep_time_ns);
    line_value = !line_value;
  }

  ret = gpiod_line_set_value(line, 0);
  if (ret < 0) {
    perror("Set line output failed\n");
  }

release_line:
  gpiod_line_release(line);
close_chip:
  gpiod_chip_close(chip);
end:
  return EXIT_SUCCESS;
}
