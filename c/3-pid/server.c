#include <arpa/inet.h>
#include <errno.h>
#include <memory.h>
#include <netinet/in.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "server.h"

int server_init(
    server_t *self, modbus_mapping_t *registers, server_options_t options
) {
  modbus_t *ctx = modbus_new_tcp("0.0.0.0", 5502);
  if (ctx == NULL) {
    fprintf(stderr, "modbus_new_tcp fail\n");
    return -1;
  }

  int socket_fd = modbus_tcp_listen(ctx, options.n_connections);
  if (socket_fd < 0) {
    fprintf(stderr, "modbus_tcp_listen fail (%d)\n", socket_fd);
    modbus_free(ctx);
    return -1;
  }

  int *connection_fds = malloc(options.n_connections * sizeof(int));

  *self = (server_t){
      .ctx = ctx,
      .registers = registers,
      .socket_fd = socket_fd,
      .n_connections_active = 0,
      .n_connections_max = options.n_connections,
      .connection_fds = connection_fds,
  };

  return 0;
}

void server_deinit(server_t *self) {
  int res;

  for (size_t i = 0; i < self->n_connections_active; ++i) {
    int fd = self->connection_fds[i];
    res = close(fd);
    if (res != 0)
      fprintf(stderr, "close(%d) fail (%d): %s\n", fd, res, strerror(errno));
  }

  res = close(self->socket_fd);
  if (res != 0)
    fprintf(stderr, "close(socket_fd) fail (%d): %s\n", res, strerror(errno));

  modbus_free(self->ctx);
}

const server_result_t SERVER_RESULT_ZERO = {
    .is_closed = false, .new_connection_fd = -1
};

int server_handle(server_t *self, int fd, server_result_t *result) {
  *result = SERVER_RESULT_ZERO;

  if (fd == self->socket_fd) {
    // Create new connection
    struct sockaddr_in client_address;
    socklen_t addr_length = sizeof(client_address);
    memset(&client_address, 0, sizeof(client_address));
    int connection_fd =
        accept(fd, (struct sockaddr *)&client_address, &addr_length);
    if (connection_fd < 0) {
      fprintf(stderr, "accept fail (%d)\n", connection_fd);
      return -1;
    }

    if (self->n_connections_active >= self->n_connections_max) {
      fprintf(stderr, "reached maximum connection count");
      return -1;
    }
    size_t i = self->n_connections_active++;
    self->connection_fds[i] = connection_fd;

    result->new_connection_fd = connection_fd;

    printf(
        "New connection from %s:%d on socket %d\n",
        inet_ntoa(client_address.sin_addr), client_address.sin_port,
        connection_fd
    );
  } else {
    // Handle modbus request
    int res = modbus_set_socket(self->ctx, fd);
    if (res != 0) {
      fprintf(stderr, "modbus_set_socket fail (%d)\n", res);
      return -1;
    }

    uint8_t query[MODBUS_TCP_MAX_ADU_LENGTH];
    int received = modbus_receive(self->ctx, query);
    if (received == -1) {
      result->is_closed = true;
      if (errno == ECONNRESET) {
        return 0;
      } else {
        fprintf(stderr, "modbus_receive fail (%d)\n", received);
        server_close_fd(self, fd);
        return -1;
      }
    }
    if (received == 0)
      return 0;

    res = modbus_reply(self->ctx, query, received, self->registers);
    if (res < 0) {
      fprintf(stderr, "modbus_reply fail (%d)\n", res);
      server_close_fd(self, fd);
      return -1;
    }
  }

  return 0;
}

bool server_close_fd(server_t *self, int fd) {
  for (size_t i = 0; i < self->n_connections_active; ++i) {
    if (self->connection_fds[i] != fd)
      continue;

    close(fd);
    int last_connection_fd =
        self->connection_fds[self->n_connections_active - 1];
    self->connection_fds[i] = last_connection_fd;
    self->n_connections_active -= 1;
    return true;
  }
  return false;
}
