#include <stdbool.h>

#include "esp_adc/adc_continuous.h"
#include "esp_err.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h" // IWYU pragma: keep
#include "freertos/task.h"
#include "hal/adc_types.h"
#include "sdkconfig.h" // IWYU pragma: keep
#include "soc/soc_caps.h"

static const char TAG[] = "motor";

static const uint32_t ADC_READS_PER_FRAME = 1;
static const uint32_t ADC_FRAMES_PER_BUF = 8;
static const uint32_t ADC_FREQUENCY = SOC_ADC_SAMPLE_FREQ_THRES_LOW;
static const uint32_t ADC_BITWIDTH = ADC_BITWIDTH_9;

static const uint32_t ADC_FRAME_SIZE =
    ADC_READS_PER_FRAME * SOC_ADC_DIGI_DATA_BYTES_PER_CONV;
static const uint32_t ADC_BUF_SIZE = ADC_FRAMES_PER_BUF * ADC_FRAME_SIZE;
static const uint32_t ADC_READ_TIMEOUT = 1000 / ADC_FREQUENCY * 2;
static const uint32_t ADC_MAX_VALUE = (1 << ADC_BITWIDTH) - 1;

void app_main(void) {
  esp_err_t err;

  ESP_LOGI(TAG, "Controlling motor from C");

  const adc_continuous_handle_cfg_t handle_config = {
      .conv_frame_size = ADC_FRAME_SIZE,
      .max_store_buf_size = ADC_BUF_SIZE,
      .flags = {.flush_pool = true},
  };
  adc_continuous_handle_t adc;
  err = adc_continuous_new_handle(&handle_config, &adc);
  ESP_ERROR_CHECK(err);

  const adc_continuous_config_t adc_config = {
      .pattern_num = 1,
      .adc_pattern = (adc_digi_pattern_config_t[]){{
          .atten = ADC_ATTEN_DB_12,
          .channel = ADC_CHANNEL_4,
          .unit = ADC_UNIT_1,
          .bit_width = ADC_BITWIDTH,
      }},
      .sample_freq_hz = ADC_FREQUENCY,
  };
  err = adc_continuous_config(adc, &adc_config);
  ESP_ERROR_CHECK(err);

  err = adc_continuous_start(adc);
  ESP_ERROR_CHECK(err);

  while (true) {
    adc_digi_output_data_t buf[ADC_FRAMES_PER_BUF];
    uint32_t bytes_read;

    err = adc_continuous_read(
        adc, (uint8_t *)buf, ADC_BUF_SIZE, &bytes_read, ADC_READ_TIMEOUT
    );
    if (err != ESP_OK) {
      ESP_ERROR_CHECK_WITHOUT_ABORT(err);
      continue;
    }

    const uint32_t n_reads = bytes_read / SOC_ADC_DIGI_DATA_BYTES_PER_CONV;
    const uint16_t last_value = buf[n_reads - 1].type1.data;
    /* ESP_LOGI(TAG, "value: %d", last_value); */
    const float value_float = (float)last_value / ADC_MAX_VALUE;
    ESP_LOGI(TAG, "value: %f", value_float);

    vTaskDelay(1);
  }

  err = adc_continuous_stop(adc);
  ESP_ERROR_CHECK(err);
  err = adc_continuous_deinit(adc);
  ESP_ERROR_CHECK(err);
}
