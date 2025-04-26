#include "driver/gpio.h"
#include "esp_log.h"

#include "freertos/FreeRTOS.h" // IWYU pragma: keep
#include "freertos/idf_additions.h"
#include "sdkconfig.h" // IWYU pragma: keep

#include "memory.h"

static const char TAG[] = "blinky";

static const uint32_t BLINK_GPIO = 5;
static const uint32_t PERIOD_MS = 1000;
static const uint32_t SLEEP_DURATION_MS = PERIOD_MS / 2;

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

  while (true) {
    ESP_LOGI(TAG, "Turning the LED %s", led_state == true ? "ON" : "OFF");

    err = gpio_set_level(BLINK_GPIO, led_state);
    if (err != ESP_OK) {
      ESP_LOGE(TAG, "gpio_set_level fail (0x%x)", (int)err);
      continue;
    }
    led_state = !led_state;

    memory_report(1, task);

    vTaskDelay(SLEEP_DURATION_MS / portTICK_PERIOD_MS);
  }
}
