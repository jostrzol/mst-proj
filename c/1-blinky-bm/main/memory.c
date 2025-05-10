#include "esp_log.h"
#include "esp_private/freertos_debug.h"
#include "freertos/idf_additions.h"

#include "memory.h"

static const char *TAG = "memory";

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

void memory_report() {
  const TaskHandle_t task = xTaskGetCurrentTaskHandle();

  char *name = pcTaskGetName(task);

  int32_t task_stack_usage = stack_usage(task);
  if (task_stack_usage == -1) {
    ESP_LOGE(TAG, "stack_usage fail");
    return;
  }

  ESP_LOGI(TAG, "%s stack usage: %" PRIi32 " B", name, task_stack_usage);

  size_t total_heap_size = heap_caps_get_total_size(0);
  size_t free_heap_size = heap_caps_get_free_size(0);
  size_t heap_usage = total_heap_size - free_heap_size;
  ESP_LOGI(TAG, "Heap usage: %d B", heap_usage);
}
