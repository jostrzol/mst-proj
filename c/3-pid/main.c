#include <errno.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>

#include <pigpio.h>

#include "controller.h"
#include "registers.h"
#include "server.h"
#include "units.h"

#define N_FDS_SYSTEM 3
#define N_CONNECTIONS 5
#define N_FDS_MAX (N_FDS_SYSTEM + N_CONNECTIONS)

static const server_options_t SERVER_OPTIONS = {.n_connections = N_CONNECTIONS};

static const uint64_t READ_RATE = 1000;
static const uint64_t READ_INTERVAL_US = MICRO_PER_1 / READ_RATE;

static const controller_options_t CONTROLLER_OPTIONS = {
    .read_interval_us = READ_INTERVAL_US,
    .revolution_treshold_close = 105,
    .revolution_treshold_far = 118,
    .revolution_bins = 10,
    .control_interval_us = 100 * 1e3,
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

  res = gpioInitialise();
  if (res < 0) {
    perror("Failed to initialize gpio\n");
    goto end;
  }

  res = gpioSetSignalFunc(SIGINT, &interrupt_handler);
  if (res < 0) {
    perror("Failed to set signal function\n");
    goto pigpio_close;
  }

  modbus_mapping_t *registers = registers_init();
  if (registers == NULL) {
    fprintf(
        stderr, "Failed to allocate the mapping: %s\n", modbus_strerror(errno)
    );
    goto pigpio_close;
  }

  static server_t server;
  res = server_init(&server, registers, SERVER_OPTIONS);
  if (res < 0) {
    perror("Initializing modbus server failed\n");
    goto registers_close;
  }

  static controller_t controller;
  res = controller_init(&controller, registers, CONTROLLER_OPTIONS);
  if (res < 0) {
    perror("Initializing controller failed\n");
    goto server_close;
  }

  struct pollfd poll_fds[N_FDS_MAX] = {
      {.fd = controller.read_timer_fd, .events = POLL_IN},
      {.fd = controller.io_timer_fd, .events = POLL_IN},
      {.fd = server.socket_fd, .events = POLL_IN},
  };
  size_t n_poll_fds = N_FDS_SYSTEM;

  while (do_continue) {
    res = poll(poll_fds, n_poll_fds, 1000);
    if (res == -1 && errno != EINTR)
      perror("Failed to poll");
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
        if (res < 0)
          perror("Failed to handle controller timer activation");
        if (res != 0)
          continue; // Handled -- either error or success

        server_result_t result;
        res = server_handle(&server, fd, &result);
        if (res != 0) {
          fprintf(
              stderr, "Failed to handle connection: %s\n",
              modbus_strerror(errno)
          );
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

  controller_close(&controller);
server_close:
  server_close(&server);
registers_close:
  registers_free(registers);
pigpio_close:
  gpioTerminate();
end:
  return EXIT_SUCCESS;
}
