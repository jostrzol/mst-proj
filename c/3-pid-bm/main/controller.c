#include "controller.h"
#include "driver/ledc.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_log.h"
#include "freertos/idf_additions.h"
#include "hal/ledc_types.h"

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

static const char TAG[] = "controller";

esp_err_t controller_init(controller_t *self) {
  esp_err_t err;

  adc_oneshot_unit_init_cfg_t init_config1 = {.unit_id = ADC_UNIT};
  err = adc_oneshot_new_unit(&init_config1, &self->adc);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "adc_oneshot_new_unit fail (0x%x)", err);
    return err;
  }

  adc_oneshot_chan_cfg_t config = {
      .atten = ADC_ATTENUATION,
      .bitwidth = ADC_BITWIDTH,
  };
  err = adc_oneshot_config_channel(self->adc, ADC_CHANNEL, &config);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "adc_oneshot_config_channel fail (0x%x)", err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(self->adc));
    return err;
  }

  const ledc_timer_config_t led_timer_config = {
      .speed_mode = PWM_SPEED,
      .duty_resolution = PWM_DUTY_RESOLUTION,
      .timer_num = LEDC_TIMER_0,
      .freq_hz = PWM_FREQUENCY,
      .clk_cfg = LEDC_AUTO_CLK,
  };
  err = ledc_timer_config(&led_timer_config);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "ledc_timer_config fail (0x%x)", err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(self->adc));
    return err;
  }

  ledc_channel_config_t ledc_channel = {
      .speed_mode = PWM_SPEED,
      .channel = PWM_CHANNEL,
      .timer_sel = led_timer_config.timer_num,
      .intr_type = LEDC_INTR_DISABLE,
      .gpio_num = PWM_GPIO,
      .duty = 0,
      .hpoint = 0
  };
  err = ledc_channel_config(&ledc_channel);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "ledc_channel_config fail (0x%x)", err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(self->adc));
    return err;
  }

  return ESP_OK;
}

void controller_deinit(controller_t *self) {
  ESP_ERROR_CHECK_WITHOUT_ABORT(ledc_stop(PWM_SPEED, PWM_CHANNEL, 0));
  ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(self->adc));
}

void controller_read_loop(void *params) {
  esp_err_t err;
  controller_t *self = params;

  ESP_LOGI(TAG, "Start controller_read_loop");

  while (true) {
    int value_raw;
    err = adc_oneshot_read(self->adc, ADC_CHANNEL, &value_raw);
    ESP_ERROR_CHECK_WITHOUT_ABORT(err);
    if (err != ESP_OK)
      continue;

    const float value_normalized = (float)value_raw / ADC_MAX_VALUE;
    ESP_LOGI(
        TAG, "selected duty cycle: %.2f = %d / %d", value_normalized, value_raw,
        ADC_MAX_VALUE
    );

    const uint32_t duty_cycle = value_normalized * PWM_DUTY_MAX;

    err = ledc_set_duty(PWM_SPEED, PWM_CHANNEL, duty_cycle);
    ESP_ERROR_CHECK_WITHOUT_ABORT(err);
    if (err != ESP_OK)
      continue;
    err = ledc_update_duty(PWM_SPEED, PWM_CHANNEL);
    ESP_ERROR_CHECK_WITHOUT_ABORT(err);
    if (err != ESP_OK)
      continue;

    vTaskDelay(1);
  }
}
