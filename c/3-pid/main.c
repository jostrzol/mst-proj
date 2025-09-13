#include <errno.h>
#include <poll.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#include <pigpio.h>
#include <string.h>

#include "controller.h"
#include "registers.h"
#include "server.h"

#define N_FDS_SYSTEM 2
#define N_CONNECTIONS 5
#define N_FDS_MAX (N_FDS_SYSTEM + N_CONNECTIONS)

static const server_options_t SERVER_OPTIONS = {.n_connections = N_CONNECTIONS};

static const uint64_t READ_FREQUENCY = 1000;
static const uint64_t CONTROL_FREQUENCY = 10;
static const uint64_t READS_PER_BIN = (READ_FREQUENCY / CONTROL_FREQUENCY);

static const controller_options_t CONTROLLER_OPTIONS = {
    .control_frequency = CONTROL_FREQUENCY,
    .time_window_bins = 10,
    .reads_per_bin = READS_PER_BIN,
    .revolution_treshold_close = 0.20,
    .revolution_treshold_far = 0.36,
    .pwm_channel = 13,
    .pwm_frequency = 1000.,
};

static bool do_continue = true;

void interrupt_handler(int) {
  printf("\nGracefully stopping\n");
  do_continue = false;
}

int main(int, char **) {
  int res;

  printf("Controlling motor using PID from C\n");

  res = gpioInitialise();
  if (res < 0) {
    fprintf(stderr, "gpioInitialise fail (%d)\n", res);
    return EXIT_FAILURE;
  }

  res = gpioSetSignalFunc(SIGINT, &interrupt_handler);
  if (res < 0) {
    fprintf(stderr, "gpioSetSignalFunc fail (%d)\n", res);
    gpioTerminate();
    return EXIT_FAILURE;
  }

  modbus_mapping_t *registers = registers_init();
  if (registers == NULL) {
    fprintf(stderr, "registers_init fail\n");
    gpioTerminate();
    return EXIT_FAILURE;
  }

  static server_t server;
  res = server_init(&server, registers, SERVER_OPTIONS);
  if (res < 0) {
    fprintf(stderr, "server_init fail (%d)\n", res);
    registers_free(registers);
    gpioTerminate();
    return EXIT_FAILURE;
  }

  static controller_t controller;
  res = controller_init(&controller, registers, CONTROLLER_OPTIONS);
  if (res < 0) {
    fprintf(stderr, "controller_init fail (%d)\n", res);
    server_deinit(&server);
    registers_free(registers);
    gpioTerminate();
    return EXIT_FAILURE;
  }

  struct pollfd poll_fds[N_FDS_MAX] = {
      {.fd = controller.timer_fd, .events = POLL_IN},
      {.fd = server.socket_fd, .events = POLL_IN},
  };
  size_t n_poll_fds = N_FDS_SYSTEM;

  while (do_continue) {
    res = poll(poll_fds, n_poll_fds, 1000);
    if (res == -1 && errno != EINTR)
      fprintf(stderr, "poll fail (%d): %s\n", res, strerror(errno));
    if (res <= 0)
      continue;

    for (size_t i = 0; i < n_poll_fds; ++i) {
      struct pollfd *poll_fd = &poll_fds[i];
      int fd = poll_fd->fd;

      if (poll_fd->revents & (POLLERR | POLLHUP)) {
        poll_fd->fd = -fd; // mark for removal
        server_close_fd(&server, fd);
      }
      if (poll_fd->revents & POLLERR)
        fprintf(stderr, "File (socket?) closed unexpectedly\n");
      if (poll_fd->revents & POLLNVAL)
        fprintf(stderr, "File (socket?) not open\n");
      if (poll_fd->revents & POLLIN) {
        res = controller_handle(&controller, fd);
        if (res < 0) {
          fprintf(stderr, "controller_handle fail (%d)\n", res);
        }
        if (res != 0)
          continue; // Handled -- either error or success

        server_result_t result;
        res = server_handle(&server, fd, &result);
        if (res != 0) {
          fprintf(stderr, "server_handle fail (%d)\n", res);
        }

        // Reflect connection modifications in poll_fds
        if (result.is_closed)
          poll_fd->fd = -fd; // mark for removal
        if (result.new_connection_fd != -1) {
          poll_fds[n_poll_fds++] =
              (struct pollfd){.fd = result.new_connection_fd, .events = POLLIN};
        }
      }
    }

    // Remove marked connections
    size_t i = 0;
    while (i < n_poll_fds) {
      if (poll_fds[i].fd < 0)
        poll_fds[i] = poll_fds[--n_poll_fds];
      else
        i += 1;
    }
  }

  controller_deinit(&controller);
  server_deinit(&server);
  registers_free(registers);
  gpioTerminate();
  return EXIT_SUCCESS;
}
