#include "driver/gpio.h"
#include "esp_log.h"

#include "freertos/FreeRTOS.h" // IWYU pragma: keep
#include "freertos/idf_additions.h"
#include "sdkconfig.h" // IWYU pragma: keep

#include "memory.h"
#include "perf.h"

static const uint32_t BLINK_GPIO = 5;
static const uint32_t PERIOD_MS = 1000;
static const uint32_t SLEEP_DURATION_MS = PERIOD_MS / 2;

static const size_t CONTROL_ITERS_PER_PERF_REPORT = 2;

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

  uint8_t led_state = 0;

  TaskHandle_t task = xTaskGetCurrentTaskHandle();

  perf_counter_t perf;
  err = perf_counter_init(&perf, "MAIN");
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "perf_counter_init fail (0x%x)", (int)err);
    abort();
  }

  while (true) {
    for (size_t i = 0; i < CONTROL_ITERS_PER_PERF_REPORT; ++i) {
      vTaskDelay(SLEEP_DURATION_MS / portTICK_PERIOD_MS);

      const perf_start_mark_t start = perf_counter_mark_start();

      ESP_LOGD(TAG, "Turning the LED %s", led_state == true ? "ON" : "OFF");

      err = gpio_set_level(BLINK_GPIO, led_state);
      if (err != ESP_OK) {
        ESP_LOGE(TAG, "gpio_set_level fail (0x%x)", (int)err);
        continue;
      }
      led_state = !led_state;

      perf_counter_add_sample(&perf, start);
    }

    memory_report(1, task);
    perf_counter_report(&perf);
    perf_counter_reset(&perf);
  }
}
