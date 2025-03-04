#include <arpa/inet.h>
#include <bits/types/siginfo_t.h>
#include <errno.h>
#include <fcntl.h>
#include <i2c/smbus.h>
#include <linux/i2c-dev.h>
#include <modbus.h>
#include <netinet/in.h>
#include <pigpio.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <unistd.h>

/* #include "pid.h" */
#include "registers.h"
#include "server.h"

#define N_CONNECTIONS 5
#define N_FDS_MAX (1 + N_CONNECTIONS)

/* static const uint64_t READ_RATE = 1000; */
/* static const uint64_t READ_INTERVAL_US = 1e6 / READ_RATE; */
/**/
/* static const pid_settings_t PID_SETTINGS = { */
/*     .read_interval_us = READ_INTERVAL_US, */
/*     .revolution_treshold_close = 105, */
/*     .revolution_treshold_far = 118, */
/*     .revolution_bins = 10, */
/*     .revolution_bin_rotate_interval_us = 100 * 1e3, */
/*     .pwm_channel = 13, */
/*     .pwm_frequency = 1000., */
/* }; */
/**/
static bool do_continue = true;

static server_t server = {.socket_fd = -1};
static modbus_mapping_t *registers;

void interrupt_handler(int)
{
    printf("\nGracefully stopping\n");
    do_continue = false;
    if (server.socket_fd != -1)
        server_close(&server);
    modbus_mapping_free(registers);
    exit(EXIT_FAILURE);
}
const struct sigaction interrupt_sigaction = {
    .sa_handler = &interrupt_handler,
};

int main(int, char **)
{
    int res;

    res = sigaction(SIGINT, &interrupt_sigaction, NULL);
    if (res < 0) {
        perror("Setting sigaction failed\n");
        goto end;
    }

    registers = modbus_mapping_new(0, 0, N_REG_HOLDING, N_REG_INPUT);
    if (registers == NULL) {
        fprintf(
            stderr, "Failed to allocate the mapping: %s\n",
            modbus_strerror(errno)
        );
        goto end;
    }

    res = server_init(
        &server,
        (server_options_t){
            .n_connections = 5,
            .registers = registers,
        }
    );
    if (res < 0) {
        perror("Initializing modbus server failed\n");
        goto registers_close;
    }

    struct pollfd poll_fds[N_FDS_MAX] = {
        {.fd = server.socket_fd, .events = POLL_IN},
    };
    size_t n_poll_fds = 1;

    for (;;) {
        res = poll(poll_fds, n_poll_fds, -1);
        if (res == -1) {
            perror("Failed to poll");
            continue;
        }

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
                    poll_fds[n_poll_fds++] = (struct pollfd
                    ){.fd = result.new_connection_fd, .events = POLLIN};
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

    server_close(&server);
registers_close:
    modbus_mapping_free(registers);
end:
    return EXIT_SUCCESS;
}
