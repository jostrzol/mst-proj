#include <inttypes.h>
#include <stdlib.h>

#include "FreeRTOSConfig.h"
#include "esp_err.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_private/freertos_debug.h"
#include "freertos/FreeRTOS.h" // IWYU pragma: keep
#include "freertos/idf_additions.h"
#include "freertos/projdefs.h"
#include "freertos/task.h"
#include "portmacro.h"

#include "controller.h"
#include "registers.h"
#include "server.h"
#include "services.h"

#define STACK_SIZE (4096)
#define MEM_REPORT_INTERVAL_MS 1000

static const char *TAG = "pid";

int32_t stack_usage(TaskHandle_t task) {
  BaseType_t err;

  TaskSnapshot_t snapshot;
  err = vTaskGetSnapshot(task, &snapshot);
  if (err != pdTRUE) {
    ESP_LOGE(TAG, "vTaskGetSnapshot fail (0x%x)", err);
    return -1;
  }

  return snapshot.pxEndOfStack - snapshot.pxTopOfStack;
}

void app_main(void) {
  esp_err_t err;
  esp_log_level_set(TAG, ESP_LOG_INFO);

  services_t services;
  err = services_init(&services);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "services_init fail (0x%x)", err);
    abort();
  }

  regs_t regs;
  regs_init(&regs);

  server_t server;
  server_opts_t server_opts = {.regs = &regs, .netif = services.wifi.netif};
  err = server_init(&server, &server_opts);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "server_init fail (0x%x)", err);
    services_deinit(&services);
    abort();
  }

  controller_t controller;
  err = controller_init(
      &controller, &regs,
      (controller_opts_t){
          .frequency = 1000,
          .revolution_treshold_close = 0.36,
          .revolution_treshold_far = 0.40,
          .revolution_bins = 10,
          .reads_per_bin = 100,
      }
  );
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "controller_init fail (0x%x)", err);
    server_deinit(&server);
    services_deinit(&services);
    abort();
  }

  BaseType_t task_err;
  TaskHandle_t controller_task;
  task_err = xTaskCreatePinnedToCore(
      controller_loop, "CONTROLLER_LOOP", STACK_SIZE, &controller,
      configMAX_PRIORITIES - 1, &controller_task, 1
  );
  if (task_err != pdPASS) {
    ESP_LOGE(TAG, "starting controller task fail (0x%x)", task_err);
    controller_deinit(&controller);
    server_deinit(&server);
    services_deinit(&services);
    abort();
  }

  TaskHandle_t server_task;
  task_err = xTaskCreatePinnedToCore(
      server_loop, "SERVER_LOOP", STACK_SIZE, &server, 2, &server_task, 0
  );
  if (task_err != pdPASS) {
    ESP_LOGE(TAG, "starting controller task fail (0x%x)", task_err);
    vTaskDelete(controller_task);
    controller_deinit(&controller);
    server_deinit(&server);
    services_deinit(&services);
    abort();
  }

  size_t total_heap_size = heap_caps_get_total_size(0);
  while (true) {
    vTaskDelay(MEM_REPORT_INTERVAL_MS / portTICK_PERIOD_MS);

    int32_t controller_stack_usage = stack_usage(controller_task);
    if (controller_stack_usage != -1) {
      ESP_LOGI(
          TAG, "Controller stack usage: %" PRIi32 "/%d", controller_stack_usage,
          STACK_SIZE
      );
    }

    int32_t server_stack_usage = stack_usage(server_task);
    if (server_stack_usage != -1) {
      ESP_LOGI(
          TAG, "Server stack usage: %" PRIi32 "/%d", server_stack_usage,
          STACK_SIZE
      );
    }

    size_t free_heap_size = heap_caps_get_free_size(0);
    size_t heap_usage = total_heap_size - free_heap_size;
    ESP_LOGI(TAG, "Heap usage: %d", heap_usage);
  }

  vTaskDelete(server_task);
  vTaskDelete(controller_task);

  controller_deinit(&controller);
  server_deinit(&server);
  services_deinit(&services);
}
