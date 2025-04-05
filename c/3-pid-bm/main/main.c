#include <stdlib.h>

#include "esp_err.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h" // IWYU pragma: keep
#include "freertos/idf_additions.h"

#include "controller.h"
#include "portmacro.h"
#include "registers.h"
#include "server.h"
#include "services.h"

#define STACK_SIZE (4096)
StackType_t read_stack[STACK_SIZE];

static const char *TAG = "pid";

void app_main(void) {
  esp_err_t err;
  esp_log_level_set(TAG, ESP_LOG_INFO);

  services_t services;
  err = services_init(&services);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "services_init fail (0x%x)", err);
    abort();
  }

  regs_t regs = regs_create();

  server_t server;
  server_opts_t server_opts = {.regs = &regs, .netif = services.wifi.netif};
  err = server_init(&server, &server_opts);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "server_init fail (0x%x)", err);
    services_deinit(&services);
    abort();
  }

  controller_t controller;
  err = controller_init(&controller);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "server_init fail (0x%x)", err);
    server_deinit(&server);
    services_deinit(&services);
    abort();
  }

  StaticTask_t read_task_buf;
  TaskHandle_t read_task = xTaskCreateStatic(
      controller_read_loop, "READ_LOOP", STACK_SIZE, &controller,
      tskIDLE_PRIORITY, read_stack, &read_task_buf
  );
  server_loop(&server);

  vTaskDelete(read_task);

  controller_deinit(&controller);
  server_deinit(&server);
  services_deinit(&services);
}
