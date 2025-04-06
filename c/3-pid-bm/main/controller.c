#include "driver/gptimer.h"
#include "driver/ledc.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_log.h"
#include "freertos/idf_additions.h"
#include "hal/ledc_types.h"
#include "portmacro.h"

#include "controller.h"
#include "ringbuffer.h"

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

static const uint32_t TIMER_FREQUENCY = 1000000; // period = 1us

// Derived constants
static const uint32_t ADC_MAX_VALUE = (1 << ADC_BITWIDTH) - 1;
static const uint32_t PWM_DUTY_MAX = (1 << PWM_DUTY_RESOLUTION) - 1;

static const char TAG[] = "controller";

esp_err_t read_adc(controller_t *self, float *value) {
  int value_raw;

  esp_err_t err = adc_oneshot_read(self->adc, ADC_CHANNEL, &value_raw);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "adc_oneshot_read fail (0x%x)", err);
    return err;
  }

  *value = (float)value_raw / ADC_MAX_VALUE;
  return ESP_OK;
}

esp_err_t set_duty(float value) {
  esp_err_t err;

  const uint32_t duty_cycle = value * PWM_DUTY_MAX;

  err = ledc_set_duty(PWM_SPEED, PWM_CHANNEL, duty_cycle);
  ESP_ERROR_CHECK_WITHOUT_ABORT(err);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "ledc_set_duty fail (0x%x)", err);
    return err;
  }

  err = ledc_update_duty(PWM_SPEED, PWM_CHANNEL);
  ESP_ERROR_CHECK_WITHOUT_ABORT(err);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "ledc_update_duty fail (0x%x)", err);
    return err;
  }

  return ESP_OK;
}

bool IRAM_ATTR on_timer_fired(
    gptimer_handle_t timer, const gptimer_alarm_event_data_t *edata,
    void *user_data
) {
  SemaphoreHandle_t timer_semaphore = user_data;

  BaseType_t high_task_awoken = pdFALSE;
  xSemaphoreGiveFromISR(timer_semaphore, &high_task_awoken);
  return high_task_awoken == pdTRUE;
}

esp_err_t controller_init(controller_t *self, controller_opts_t opts) {
  esp_err_t err;

  SemaphoreHandle_t timer_semaphore =
      xSemaphoreCreateBinaryStatic(&self->timer_semaphore_buf);
  if (timer_semaphore == NULL) {
    ESP_LOGE(TAG, "xSemaphoreCreateBinaryStatic fail");
    return ESP_ERR_INVALID_STATE;
  }

  adc_oneshot_unit_handle_t adc;
  adc_oneshot_unit_init_cfg_t init_config1 = {.unit_id = ADC_UNIT};
  err = adc_oneshot_new_unit(&init_config1, &adc);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "adc_oneshot_new_unit fail (0x%x)", err);
    return err;
  }

  adc_oneshot_chan_cfg_t config = {
      .atten = ADC_ATTENUATION,
      .bitwidth = ADC_BITWIDTH,
  };
  err = adc_oneshot_config_channel(adc, ADC_CHANNEL, &config);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "adc_oneshot_config_channel fail (0x%x)", err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(adc));
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
    ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(adc));
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
    ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(adc));
    return err;
  }

  ringbuffer_t *revolutions = ringbuffer_alloc(opts.revolution_bins);

  gptimer_handle_t timer;
  err = gptimer_new_timer(
      &(gptimer_config_t){
          .clk_src = GPTIMER_CLK_SRC_DEFAULT,
          .direction = GPTIMER_COUNT_UP,
          .resolution_hz = TIMER_FREQUENCY,
      },
      &timer
  );
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "timer_init fail (0x%x)", err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(adc));
    return err;
  }

  err = gptimer_register_event_callbacks(
      timer,
      &(gptimer_event_callbacks_t){
          .on_alarm = on_timer_fired,
      },
      timer_semaphore
  );
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "gptimer_register_event_callbacks fail (0x%x)", err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(gptimer_del_timer(self->timer));
    ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(adc));
    return err;
  }
  err = gptimer_enable(timer);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "gptimer_enable fail (0x%x)", err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(gptimer_del_timer(self->timer));
    ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(adc));
    return err;
  }
  err = gptimer_set_alarm_action(
      timer,
      &(gptimer_alarm_config_t){
          .alarm_count = TIMER_FREQUENCY / opts.frequency,
          .reload_count = 0,
          .flags.auto_reload_on_alarm = true,
      }
  );
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "gptimer_set_alarm_action fail (0x%x)", err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(gptimer_del_timer(self->timer));
    ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(adc));
    return err;
  }

  // TODO: remove
  set_duty(0.15);

  *self = (controller_t){
      .opts = opts,
      .adc = adc,
      .timer_semaphore_buf = self->timer_semaphore_buf,
      .timer_semaphore = timer_semaphore,
      .timer = timer,
      .revolutions = revolutions,
      .is_close = false,
  };

  return ESP_OK;
}

void controller_deinit(controller_t *self) {
  free(self->revolutions);
  ESP_ERROR_CHECK_WITHOUT_ABORT(gptimer_stop(self->timer));
  ESP_ERROR_CHECK_WITHOUT_ABORT(gptimer_disable(self->timer));
  ESP_ERROR_CHECK_WITHOUT_ABORT(gptimer_del_timer(self->timer));
  ESP_ERROR_CHECK_WITHOUT_ABORT(ledc_stop(PWM_SPEED, PWM_CHANNEL, 0));
  ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(self->adc));
}

float calculate_frequency(controller_t *self) {
  uint32_t sum = 0;
  for (size_t i = 0; i < self->revolutions->length; ++i)
    sum += self->revolutions->array[i];

  const float interval_s =
      (float)1 / self->opts.frequency * self->opts.reads_per_bin;
  const float all_bins_interval_s = interval_s * self->opts.revolution_bins;

  return (float)sum / all_bins_interval_s;
}

void controller_read_loop(void *params) {
  esp_err_t err;
  controller_t *self = params;

  ESP_LOGI(TAG, "Start controller_read_loop");

  ESP_ERROR_CHECK(gptimer_start(self->timer));
  while (true) {
    for (size_t i = 0; i < self->opts.reads_per_bin; ++i) {
      xSemaphoreTake(self->timer_semaphore, portMAX_DELAY);

      float value;
      err = read_adc(self, &value);
      ESP_ERROR_CHECK_WITHOUT_ABORT(err);
      if (err != ESP_OK)
        continue;

      if (value < self->opts.revolution_treshold_close && !self->is_close) {
        // gone close
        self->is_close = true;
        *ringbuffer_back(self->revolutions) += 1;
      } else if (value > self->opts.revolution_treshold_far && self->is_close) {
        // gone far
        self->is_close = false;
      }
    }

    const float frequency = calculate_frequency(self);
    ringbuffer_push(self->revolutions, 0);

    ESP_LOGI(TAG, "frequency: %.2f", frequency);
  }
}
