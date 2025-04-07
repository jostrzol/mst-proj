#include <stdlib.h>

#include "FreeRTOSConfig.h"
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

  StaticTask_t read_task_buf;
  TaskHandle_t read_task = xTaskCreateStaticPinnedToCore(
      controller_read_loop, "READ_LOOP", STACK_SIZE, &controller,
      configMAX_PRIORITIES - 1, read_stack, &read_task_buf, 1
  );

  /* char *task_list_buffer = malloc(1024); // Make sure this is big enough */
  /**/
  /* if (task_list_buffer) { */
  /*   vTaskList(task_list_buffer); // Fills the buffer with task info */
  /*   ESP_LOGI( */
  /*       "TASKS", "\nTask Name\tStatus\tPrio\tStack\tNum\n%s",
   * task_list_buffer */
  /*   ); */
  /*   free(task_list_buffer); */
  /* } else { */
  /*   ESP_LOGE("TASKS", "Failed to allocate memory for task list"); */
  /* } */

  server_loop(&server);
  /* while (true) */
  /*   vTaskDelay(10 * 1000 / portTICK_PERIOD_MS); */

  vTaskDelete(read_task);

  controller_deinit(&controller);
  server_deinit(&server);
  services_deinit(&services);
}
