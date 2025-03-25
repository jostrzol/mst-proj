#include "driver/gpio.h"
#include "esp_log.h"

#include "freertos/FreeRTOS.h" // IWYU pragma: keep
#include "freertos/task.h"
#include "sdkconfig.h" // IWYU pragma: keep

static const char TAG[] = "blinky";

static const uint32_t BLINK_GPIO = 5;
static const uint32_t BLINK_PERIOD = 500;

void app_main(void) {
  ESP_LOGI(TAG, "Example configured to blink GPIO LED!");

  uint8_t led_state = 0;

  gpio_reset_pin(BLINK_GPIO);
  gpio_set_direction(BLINK_GPIO, GPIO_MODE_OUTPUT);

  while (true) {
    ESP_LOGI(TAG, "Turning the LED %s!", led_state == true ? "ON" : "OFF");

    gpio_set_level(BLINK_GPIO, led_state);
    led_state = !led_state;
    vTaskDelay(BLINK_PERIOD / portTICK_PERIOD_MS);
  }
}
