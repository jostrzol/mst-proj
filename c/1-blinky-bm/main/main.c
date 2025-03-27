#include "driver/gpio.h"
#include "esp_log.h"

#include "freertos/FreeRTOS.h" // IWYU pragma: keep
#include "freertos/task.h"
#include "sdkconfig.h" // IWYU pragma: keep

static const char TAG[] = "blinky";

static const uint32_t BLINK_GPIO = 5;
static const uint32_t PERIOD_MS = 1000;
static const uint32_t SLEEP_DURATION_MS = PERIOD_MS / 2;

void app_main(void) {
  ESP_LOGI(TAG, "Blinking an LED from C");

  uint8_t led_state = 0;

  gpio_reset_pin(BLINK_GPIO);
  gpio_set_direction(BLINK_GPIO, GPIO_MODE_OUTPUT);

  while (true) {
    ESP_LOGI(TAG, "Turning the LED %s", led_state == true ? "ON" : "OFF");

    gpio_set_level(BLINK_GPIO, led_state);
    led_state = !led_state;
    vTaskDelay(SLEEP_DURATION_MS / portTICK_PERIOD_MS);
  }
}
