#include <stdbool.h>

#include "driver/ledc.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_err.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h" // IWYU pragma: keep
#include "hal/adc_types.h"
#include "hal/ledc_types.h"
#include "sdkconfig.h" // IWYU pragma: keep

static const char TAG[] = "pid";

// Configuration
static const adc_unit_t ADC_UNIT = ADC_UNIT_1;
static const adc_channel_t ADC_CHANNEL = ADC_CHANNEL_4;
static const adc_atten_t ADC_ATTENUATION = ADC_ATTEN_DB_12;
static const adc_bitwidth_t ADC_BITWIDTH = ADC_BITWIDTH_9;

static const uint32_t PWM_SPEED = LEDC_LOW_SPEED_MODE;
static const uint32_t PWM_CHANNEL = LEDC_CHANNEL_0;
static const uint32_t PWM_GPIO = 5;
static const uint32_t PWM_FREQUENCY = 1000;
static const uint32_t PWM_DUTY_RESOLUTION = LEDC_TIMER_13_BIT;

// Derived constants
static const uint32_t ADC_MAX_VALUE = (1 << ADC_BITWIDTH) - 1;

static const uint32_t PWM_DUTY_MAX = (1 << PWM_DUTY_RESOLUTION) - 1;

void app_main(void) {
  esp_err_t err;

  ESP_LOGI(TAG, "Controlling motor from C");

  adc_oneshot_unit_handle_t adc;
  adc_oneshot_unit_init_cfg_t init_config1 = {.unit_id = ADC_UNIT};
  err = adc_oneshot_new_unit(&init_config1, &adc);
  ESP_ERROR_CHECK(err);

  adc_oneshot_chan_cfg_t config = {
      .atten = ADC_ATTENUATION,
      .bitwidth = ADC_BITWIDTH,
  };
  err = adc_oneshot_config_channel(adc, ADC_CHANNEL, &config);
  ESP_ERROR_CHECK(err);

  const ledc_timer_config_t led_timer_config = {
      .speed_mode = PWM_SPEED,
      .duty_resolution = PWM_DUTY_RESOLUTION,
      .timer_num = LEDC_TIMER_0,
      .freq_hz = PWM_FREQUENCY,
      .clk_cfg = LEDC_AUTO_CLK,
  };
  err = ledc_timer_config(&led_timer_config);
  ESP_ERROR_CHECK(err);

  ledc_channel_config_t ledc_channel = {
      .speed_mode = PWM_SPEED,
      .channel = PWM_CHANNEL,
      .timer_sel = led_timer_config.timer_num,
      .intr_type = LEDC_INTR_DISABLE,
      .gpio_num = PWM_GPIO,
      .duty = 0,
      .hpoint = 0
  };
  ESP_ERROR_CHECK(ledc_channel_config(&ledc_channel));

  while (true) {
    int value_raw;
    err = adc_oneshot_read(adc, ADC_CHANNEL, &value_raw);
    if (err != ESP_OK) {
      ESP_ERROR_CHECK_WITHOUT_ABORT(err);
      continue;
    }

    const float value_normalized = (float)value_raw / ADC_MAX_VALUE;
    ESP_LOGI(
        TAG, "selected duty cycle: %.2f = %d / %d", value_normalized, value_raw,
        ADC_MAX_VALUE
    );

    const uint32_t duty_cycle = value_normalized * PWM_DUTY_MAX;

    ESP_ERROR_CHECK(ledc_set_duty(PWM_SPEED, PWM_CHANNEL, duty_cycle));
    ESP_ERROR_CHECK(ledc_update_duty(PWM_SPEED, PWM_CHANNEL));

    vTaskDelay(1);
  }

  ESP_ERROR_CHECK(ledc_stop(PWM_SPEED, PWM_CHANNEL, 0));
}
