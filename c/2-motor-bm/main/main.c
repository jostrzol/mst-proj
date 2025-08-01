#include <stdbool.h>
#include <stdlib.h>

#include "driver/ledc.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_err.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h" // IWYU pragma: keep
#include "freertos/idf_additions.h"
#include "hal/adc_types.h"
#include "hal/ledc_types.h"
#include "lwip/err.h"
#include "sdkconfig.h" // IWYU pragma: keep

#include "memory.h"
#include "perf.h"

static const char TAG[] = "motor";

const uint64_t CONTROL_FREQUENCY = 10;
const uint64_t SLEEP_DURATION_MS = 1000 / CONTROL_FREQUENCY;

static const adc_unit_t ADC_UNIT = ADC_UNIT_1;
static const adc_channel_t ADC_CHANNEL = ADC_CHANNEL_4;
static const adc_atten_t ADC_ATTENUATION = ADC_ATTEN_DB_12;
static const adc_bitwidth_t ADC_BITWIDTH = ADC_BITWIDTH_9;
static const uint32_t ADC_MAX_VALUE = (1 << ADC_BITWIDTH) - 1;
static const adc_oneshot_chan_cfg_t ADC_CHANNEL_CONFIG = {
    .atten = ADC_ATTENUATION,
    .bitwidth = ADC_BITWIDTH,
};

static const uint32_t PWM_TIMER_NUM = LEDC_TIMER_0;
static const uint32_t PWM_SPEED = LEDC_LOW_SPEED_MODE;
static const uint32_t PWM_CHANNEL = LEDC_CHANNEL_0;
static const uint32_t PWM_BITWIDTH = LEDC_TIMER_13_BIT;
static const uint32_t PWM_DUTY_MAX = (1 << PWM_BITWIDTH) - 1;
static const ledc_timer_config_t PWM_TIMER_CONFIG = {
    .timer_num = PWM_TIMER_NUM,
    .speed_mode = PWM_SPEED,
    .duty_resolution = PWM_BITWIDTH,
    .freq_hz = 1000,
    .clk_cfg = LEDC_AUTO_CLK,
};
static const ledc_timer_config_t PWM_TIMER_DECONFIG = {
    .timer_num = PWM_TIMER_NUM,
    .deconfigure = true,
};
static const ledc_channel_config_t PWM_CHANNEL_CONFIG = {
    .timer_sel = PWM_TIMER_NUM,
    .channel = PWM_CHANNEL,
    .speed_mode = PWM_SPEED,
    .intr_type = LEDC_INTR_DISABLE,
    .gpio_num = GPIO_NUM_5,
    .duty = 0,
    .hpoint = 0,
};

void app_main(void) {
  esp_err_t err;

  ESP_LOGI(TAG, "Controlling motor from C");

  adc_oneshot_unit_handle_t adc;
  adc_oneshot_unit_init_cfg_t init_config1 = {.unit_id = ADC_UNIT};
  err = adc_oneshot_new_unit(&init_config1, &adc);
  if (err != ERR_OK) {
    ESP_LOGE(TAG, "adc_oneshot_new_unit fail (0x%x)", (int)err);
    abort();
  }

  err = adc_oneshot_config_channel(adc, ADC_CHANNEL, &ADC_CHANNEL_CONFIG);
  if (err != ERR_OK) {
    ESP_LOGE(TAG, "adc_oneshot_config_channel fail (0x%x)", (int)err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(adc));
    abort();
  }

  err = ledc_timer_config(&PWM_TIMER_CONFIG);
  if (err != ERR_OK) {
    ESP_LOGE(TAG, "ledc_timer_config fail (0x%x)", (int)err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(adc));
    abort();
  }

  err = ledc_channel_config(&PWM_CHANNEL_CONFIG);
  if (err != ERR_OK) {
    ESP_LOGE(TAG, "ledc_channel_config fail (0x%x)", (int)err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(ledc_timer_config(&PWM_TIMER_DECONFIG));
    ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(adc));
    abort();
  }

  perf_counter_t *perf;
  err = perf_counter_init(&perf, "MAIN", CONTROL_FREQUENCY * 2);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "perf_counter_init fail (0x%x)", (int)err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(ledc_stop(PWM_SPEED, PWM_CHANNEL, 0));
    ESP_ERROR_CHECK_WITHOUT_ABORT(ledc_timer_config(&PWM_TIMER_DECONFIG));
    ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(adc));
    abort();
  }

  uint64_t report_number = 0;
  while (true) {
    for (size_t i = 0; i < CONTROL_FREQUENCY; ++i) {
      vTaskDelay(SLEEP_DURATION_MS / portTICK_PERIOD_MS);

      const perf_mark_t start = perf_mark();

      int value_raw;
      err = adc_oneshot_read(adc, ADC_CHANNEL, &value_raw);
      if (err != ESP_OK) {
        ESP_ERROR_CHECK_WITHOUT_ABORT(err);
        continue;
      }

      const float value_normalized = (float)value_raw / ADC_MAX_VALUE;
      ESP_LOGD(
          TAG, "selected duty cycle: %.2f = %d / %" PRIu32, value_normalized,
          value_raw, ADC_MAX_VALUE
      );

      const uint32_t duty_cycle = value_normalized * PWM_DUTY_MAX;

      err = ledc_set_duty(PWM_SPEED, PWM_CHANNEL, duty_cycle);
      if (err != ESP_OK) {
        ESP_ERROR_CHECK_WITHOUT_ABORT(err);
        continue;
      }
      err = ledc_update_duty(PWM_SPEED, PWM_CHANNEL);
      if (err != ESP_OK) {
        ESP_ERROR_CHECK_WITHOUT_ABORT(err);
        continue;
      }

      perf_counter_add_sample(perf, start);
    }

    ESP_LOGI(TAG, "# REPORT %llu", report_number);
    memory_report();
    perf_counter_report(perf);
    perf_counter_reset(perf);
    report_number += 1;
  }

  perf_counter_deinit(perf);
  ESP_ERROR_CHECK_WITHOUT_ABORT(ledc_stop(PWM_SPEED, PWM_CHANNEL, 0));
  ESP_ERROR_CHECK_WITHOUT_ABORT(ledc_timer_config(&PWM_TIMER_DECONFIG));
  ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(adc));
}
