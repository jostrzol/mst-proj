#pragma once

#include "esp_netif_types.h"

typedef struct {
  esp_netif_t *netif;
} my_wifi_t;

esp_err_t my_wifi_init(my_wifi_t *self);
void my_wifi_deinit(my_wifi_t *self);
