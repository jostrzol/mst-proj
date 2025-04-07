#include <math.h>

#include "driver/gptimer.h"
#include "driver/ledc.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_log.h"
#include "freertos/idf_additions.h"
#include "hal/ledc_types.h"
#include "mb_endianness_utils.h"
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
static const float PWM_MIN = 0.10;
static const float PWM_MAX = 1.00;
static const float PWM_LIMIT_MIN_DEADZONE = 0.001;

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

esp_err_t set_duty_cycle(float value) {
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

esp_err_t
controller_init(controller_t *self, regs_t *regs, controller_opts_t opts) {
  esp_err_t err;

  SemaphoreHandle_t timer_semaphore =
      xSemaphoreCreateBinaryStatic(&self->timer.semaphore_buf);
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
    ESP_ERROR_CHECK_WITHOUT_ABORT(gptimer_del_timer(timer));
    ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(adc));
    return err;
  }
  err = gptimer_enable(timer);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "gptimer_enable fail (0x%x)", err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(gptimer_del_timer(timer));
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
    ESP_ERROR_CHECK_WITHOUT_ABORT(gptimer_del_timer(timer));
    ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(adc));
    return err;
  }

  const float interval_rotate_once_s =
      (float)1 / opts.frequency * opts.reads_per_bin;
  const float interval_rotate_all_s =
      interval_rotate_once_s * opts.revolution_bins;

  *self = (controller_t){
      .opts = opts,
      .regs = regs,
      .adc = adc,
      .timer =
          {
              .semaphore_buf = self->timer.semaphore_buf,
              .semaphore = timer_semaphore,
              .handle = timer,
          },
      .interval =
          {
              .rotate_once_s = interval_rotate_once_s,
              .rotate_all_s = interval_rotate_all_s,
          },
      .state =
          {
              .revolutions = revolutions,
              .is_close = false,
              .feedback = {.delta = 0, .integration_component = 0},
          },
  };

  return ESP_OK;
}

void controller_deinit(controller_t *self) {
  free(self->state.revolutions);
  ESP_ERROR_CHECK_WITHOUT_ABORT(gptimer_stop(self->timer.handle));
  ESP_ERROR_CHECK_WITHOUT_ABORT(gptimer_disable(self->timer.handle));
  ESP_ERROR_CHECK_WITHOUT_ABORT(gptimer_del_timer(self->timer.handle));
  ESP_ERROR_CHECK_WITHOUT_ABORT(ledc_stop(PWM_SPEED, PWM_CHANNEL, 0));
  ESP_ERROR_CHECK_WITHOUT_ABORT(adc_oneshot_del_unit(self->adc));
}

float finite_or_zero(float value) { return isfinite(value) ? value : 0; }

float limit(float value, float min, float max) {
  if (value < PWM_LIMIT_MIN_DEADZONE)
    return 0;

  const float result = value + min;
  return result < min ? min : (result > max ? max : result);
}

float calculate_frequency(controller_t *self) {
  uint32_t sum = 0;
  for (size_t i = 0; i < self->state.revolutions->length; ++i)
    sum += self->state.revolutions->array[i];

  return (float)sum / self->interval.rotate_all_s;
}

typedef struct {
  float target_frequency;
  float proportional_factor;
  float integration_time;
  float differentiation_time;
} control_params_t;

control_params_t read_control_params(controller_t *self) {
  regs_holding_t *holding = &self->regs->holding;
  return (control_params_t){
      .target_frequency = mb_get_float_cdab(&holding->target_frequency),
      .proportional_factor = mb_get_float_cdab(&holding->proportional_factor),
      .integration_time = mb_get_float_cdab(&holding->integration_time),
      .differentiation_time = mb_get_float_cdab(&holding->differentiation_time),
  };
}

typedef struct {
  float signal;
  feedback_t feedback;
} control_t;

control_t calculate_control(
    controller_t *self, const control_params_t *params, float frequency
) {
  const float interval_s = self->interval.rotate_all_s;

  const float integration_factor =
      params->proportional_factor / params->integration_time * interval_s;
  const float differentiation_factor =
      params->proportional_factor * params->differentiation_time / interval_s;

  const float delta = params->target_frequency - frequency;
  ESP_LOGI(TAG, "delta: %.2f", delta);

  const float proportional_component = params->proportional_factor * delta;
  const float integration_component =
      self->state.feedback.integration_component +
      integration_factor * self->state.feedback.delta;
  const float differentiation_component =
      differentiation_factor * (delta - self->state.feedback.delta);

  const float control_signal = proportional_component + integration_component +
                               differentiation_component;
  ESP_LOGI(
      TAG, "control_signal: %.2f = %.2f + %.2f + %.2f", control_signal,
      proportional_component, integration_component, differentiation_component
  );

  return (control_t
  ){.signal = control_signal,
    .feedback = {
        .delta = finite_or_zero(delta),
        .integration_component = finite_or_zero(integration_component),
    }};
}

void write_state(controller_t *self, float frequency, float control_signal) {
  regs_input_t *input = &self->regs->input;
  mb_set_float_cdab(&input->frequency, frequency);
  mb_set_float_cdab(&input->control_signal, control_signal);
}

void controller_loop(void *params) {
  esp_err_t err;
  controller_t *self = params;

  ESP_LOGI(TAG, "Start controller_read_loop");

  ESP_ERROR_CHECK(gptimer_start(self->timer.handle));
  while (true) {
    for (size_t i = 0; i < self->opts.reads_per_bin; ++i) {
      xSemaphoreTake(self->timer.semaphore, portMAX_DELAY);

      float value;
      err = read_adc(self, &value);
      ESP_ERROR_CHECK_WITHOUT_ABORT(err);
      if (err != ESP_OK)
        continue;

      if (value < self->opts.revolution_treshold_close &&
          !self->state.is_close) {
        // gone close
        self->state.is_close = true;
        *ringbuffer_back(self->state.revolutions) += 1;
      } else if (value > self->opts.revolution_treshold_far &&
                 self->state.is_close) {
        // gone far
        self->state.is_close = false;
      }
    }

    const float frequency = calculate_frequency(self);
    ringbuffer_push(self->state.revolutions, 0);

    const control_params_t params = read_control_params(self);

    const control_t control = calculate_control(self, &params, frequency);

    const float control_signal_limited =
        limit(control.signal, PWM_MIN, PWM_MAX);
    ESP_LOGI(TAG, "control_signal_limited: %.2f", control_signal_limited);

    write_state(self, frequency, control_signal_limited);
    set_duty_cycle(control_signal_limited);

    self->state.feedback = control.feedback;

    ESP_LOGI(TAG, "frequency: %.2f", frequency);
  }
}
