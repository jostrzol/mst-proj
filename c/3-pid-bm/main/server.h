#pragma once

#include "esp_err.h"
#include "registers.h"

typedef struct {
  void *handle;
} server_t;

typedef struct {
  void *netif;
  registers_t *registers;
} server_options_t;

esp_err_t server_init(server_t *self, server_options_t *options);
void server_deinit(server_t *self);

void server_loop(void *params);
