#include "driver/gpio.h"
#include "esp_log.h"

#include "freertos/FreeRTOS.h" // IWYU pragma: keep
#include "freertos/idf_additions.h"
#include "sdkconfig.h" // IWYU pragma: keep

#include "memory.h"
#include "perf.h"

static const uint32_t BLINK_GPIO = 5;

const int64_t BLINK_FREQUENCY = 10;
const int64_t UPDATE_FREQUENCY = BLINK_FREQUENCY * 2;
const int64_t SLEEP_DURATION_MS = 1000 / UPDATE_FREQUENCY;

static const char TAG[] = "blinky";

void app_main(void) {
  esp_err_t err;

  ESP_LOGI(TAG, "Blinking an LED from C");

  err = gpio_reset_pin(BLINK_GPIO);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "gpio_reset_pin fail (0x%x)", (int)err);
    abort();
  }
  err = gpio_set_direction(BLINK_GPIO, GPIO_MODE_OUTPUT);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "gpio_set_direction fail (0x%x)", (int)err);
    abort();
  }

  perf_counter_t *perf;
  err = perf_counter_init(&perf, "MAIN", UPDATE_FREQUENCY * 2);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "perf_counter_init fail (0x%x)", (int)err);
    abort();
  }

  uint8_t is_on = 0;

  uint64_t report_number = 0;
  while (true) {
    for (size_t i = 0; i < UPDATE_FREQUENCY; ++i) {
      vTaskDelay(SLEEP_DURATION_MS / portTICK_PERIOD_MS);

      const perf_mark_t start = perf_mark();

      ESP_LOGD(TAG, "Turning the LED %s", is_on == true ? "ON" : "OFF");

      err = gpio_set_level(BLINK_GPIO, is_on);
      if (err != ESP_OK) {
        ESP_LOGE(TAG, "gpio_set_level fail (0x%x)", (int)err);
        continue;
      }
      is_on = !is_on;

      perf_counter_add_sample(perf, start);
    }

    ESP_LOGI(TAG, "# REPORT %llu", report_number);
    memory_report();
    perf_counter_report(perf);
    perf_counter_reset(perf);
    report_number += 1;
  }

  perf_counter_deinit(perf);
}
