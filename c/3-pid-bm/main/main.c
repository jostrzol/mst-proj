#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include "FreeRTOSConfig.h"
#include "esp_err.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h" // IWYU pragma: keep
#include "freertos/idf_additions.h"
#include "freertos/projdefs.h"
#include "freertos/task.h"
#include "portmacro.h"

#include "controller.h"
#include "registers.h"
#include "sdkconfig.h"
#include "server.h"
#include "services.h"

#define STACK_SIZE (4096)

static const char *TAG = "pid";

void app_main(void) {
  esp_err_t err;
  esp_log_level_set(TAG, ESP_LOG_INFO);

  ESP_LOGI(TAG, "Controlling motor using PID from C");

  services_t services;
  err = services_init(&services);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "services_init fail (0x%x)", err);
    abort();
  }

  registers_t registers;
  registers_init(&registers);

  server_t server;
  server_options_t server_options = {
      .registers = &registers, .netif = services.wifi.netif
  };
  err = server_init(&server, &server_options);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "server_init fail (0x%x)", err);
    services_deinit(&services);
    abort();
  }

  errno = 0;
  const float revolution_threshold_close =
      strtof(CONFIG_REVOLUTION_THRESHOLD_CLOSE, NULL);
  if (errno != 0) {
    ESP_LOGE(
        TAG, "parsing REVOLUTION_THRESHOLD_CLOSE (0x%x): %s", errno,
        strerror(errno)
    );
  }
  const float revolution_threshold_far =
      strtof(CONFIG_REVOLUTION_THRESHOLD_CLOSE, NULL);
  if (errno != 0) {
    ESP_LOGE(
        TAG, "parsing REVOLUTION_THRESHOLD_FAR (0x%x): %s", errno,
        strerror(errno)
    );
  }
  const controller_options_t controller_options = {
      .control_frequency = 10,
      .time_window_bins = 10,
      .reads_per_bin = 100,
      .revolution_threshold_close = revolution_threshold_close,
      .revolution_threshold_far = revolution_threshold_far,
  };

  controller_t controller;
  err = controller_init(&controller, &registers, controller_options);
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

  while (true) {
    vTaskDelay(10 * 1000 / portTICK_PERIOD_MS);
  }

  vTaskDelete(server_task);
  vTaskDelete(controller_task);

  controller_deinit(&controller);
  server_deinit(&server);
  services_deinit(&services);
}
