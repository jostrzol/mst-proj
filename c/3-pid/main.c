#include <arpa/inet.h>
#include <bits/types/siginfo_t.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <unistd.h>

#include <i2c/smbus.h>
#include <linux/i2c-dev.h>
#include <modbus.h>
#include <pigpio.h>

#include "pid.h"

const uint64_t READ_RATE = 1000;
const uint64_t READ_INTERVAL_US = 1e6 / READ_RATE;

const struct pid_settings_t PID_SETTINGS = {
    .read_interval_us = READ_INTERVAL_US,
    .revolution_treshold_close = 105,
    .revolution_treshold_far = 118,
    .revolution_bins = 10,
    .revolution_bin_rotate_interval_us = 100 * 1e3,
    .pwm_channel = 13,
    .pwm_frequency = 1000.,
};

const uint8_t NB_CONNECTION = 5;

static bool do_continue = true;
static modbus_t *ctx = NULL;
static modbus_mapping_t *mb_mapping;

static int server_socket = -1;

void interrupt_handler(int) {
  printf("\nGracefully stopping\n");
  do_continue = false;
  if (server_socket != -1) {
    close(server_socket);
  }
  modbus_free(ctx);
  modbus_mapping_free(mb_mapping);
}
const struct sigaction interrupt_sigaction = {
    .sa_handler = &interrupt_handler,
};

int main(int, char **) {
  int ret;

  ret = sigaction(SIGINT, &interrupt_sigaction, NULL);
  if (ret < 0) {
    perror("Setting sigaction failed\n");
    goto fail;
  }

  ctx = modbus_new_tcp("0.0.0.0", 5502);

  mb_mapping =
      modbus_mapping_new(MODBUS_MAX_READ_BITS, 0, MODBUS_MAX_READ_REGISTERS, 0);
  if (mb_mapping == NULL) {
    fprintf(stderr, "Failed to allocate the mapping: %s\n",
            modbus_strerror(errno));
    goto modbus_close;
  }

  server_socket = modbus_tcp_listen(ctx, NB_CONNECTION);
  if (server_socket == -1) {
    fprintf(stderr, "Unable to listen TCP connection\n");
    goto modbus_mapping_close;
  }

  fd_set refset;
  fd_set rdset;

  /* Clear the reference set of socket */
  FD_ZERO(&refset);
  /* Add the server socket */
  FD_SET(server_socket, &refset);

  /* Keep track of the max file descriptor */
  int fdmax = server_socket;

  for (;;) {
    rdset = refset;
    if (select(fdmax + 1, &rdset, NULL, NULL, NULL) == -1) {
      perror("Server select() failure.");
      goto modbus_server_close;
    }

    /* Run through the existing connections looking for data to be
     * read */
    for (int master_socket = 0; master_socket <= fdmax; master_socket++) {

      if (!FD_ISSET(master_socket, &rdset)) {
        continue;
      }

      if (master_socket == server_socket) {
        /* A client is asking a new connection */
        struct sockaddr_in clientaddr;
        socklen_t addrlen = sizeof(clientaddr);
        memset(&clientaddr, 0, sizeof(clientaddr));
        int newfd =
            accept(server_socket, (struct sockaddr *)&clientaddr, &addrlen);
        if (newfd == -1) {
          perror("Server accept() error");
        } else {
          FD_SET(newfd, &refset);

          if (newfd > fdmax) {
            /* Keep track of the maximum */
            fdmax = newfd;
          }
          printf("New connection from %s:%d on socket %d\n",
                 inet_ntoa(clientaddr.sin_addr), clientaddr.sin_port, newfd);
        }
      } else {
        modbus_set_socket(ctx, master_socket);

        uint8_t query[MODBUS_TCP_MAX_ADU_LENGTH];
        int rc = modbus_receive(ctx, query);
        if (rc > 0) {
          modbus_reply(ctx, query, rc, mb_mapping);
        } else if (rc == -1) {
          /* This example server in ended on connection closing or
           * any errors. */
          printf("Connection closed on socket %d\n", master_socket);
          close(master_socket);

          /* Remove from reference set */
          FD_CLR(master_socket, &refset);

          if (master_socket == fdmax) {
            fdmax--;
          }
        }
      }
    }
  }

  return EXIT_SUCCESS;

modbus_server_close:
  close(server_socket);
modbus_mapping_close:
  modbus_mapping_free(mb_mapping);
modbus_close:
  modbus_free(ctx);
fail:
  return EXIT_FAILURE;
}
