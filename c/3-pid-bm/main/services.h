#pragma once

#include "wifi.h"

typedef struct {
  my_wifi_t wifi;
} services_t;

esp_err_t services_init(services_t *self);
void services_deinit(services_t *self);
