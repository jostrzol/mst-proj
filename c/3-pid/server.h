#pragma once

#include <modbus.h>
#include <stddef.h>

typedef struct {
  int n_connections;
} server_options_t;

typedef struct {
  modbus_t *ctx;
  modbus_mapping_t *registers;
  int socket_fd;
  size_t n_connections_active;
  size_t n_connections_max;
  int *connection_fds;
} server_t;

typedef struct {
  bool is_closed;
  int new_connection_fd;
} server_result_t;

int server_init(
    server_t *server, modbus_mapping_t *registers, server_options_t options
);

void server_close(server_t *server);

int server_handle(server_t *server, int fd, server_result_t *result);

bool server_close_fd(server_t *self, int fd);
