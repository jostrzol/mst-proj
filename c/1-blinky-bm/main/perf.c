#include <inttypes.h>
#include <math.h>

#include "esp_clk_tree.h"
#include "esp_log.h"
#include "soc/clk_tree_defs.h"

#include "perf.h"

static const char *TAG = "perf";

esp_err_t perf_counter_init(perf_counter_t *self, const char *name) {
  esp_err_t err;

  uint32_t cpu_frequency;
  err = esp_clk_tree_src_get_freq_hz(SOC_MOD_CLK_CPU, 0, &cpu_frequency);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "esp_clk_tree_src_get_freq_hz fail (0x%x)", err);
    return err;
  }

  ESP_LOGI(
      TAG, "Performance counter %s, cpu frequency: %" PRIu32, name,
      cpu_frequency
  );

  *self = (perf_counter_t){
      .name = name,
      .cpu_frequency = cpu_frequency,
      .total_cycles = 0,
      .sample_count = 0,
  };

  return ESP_OK;
}

perf_start_mark_t perf_counter_mark_start() {
  return esp_cpu_get_cycle_count();
}
void perf_counter_add_sample(perf_counter_t *self, perf_start_mark_t start) {
  const esp_cpu_cycle_count_t end = esp_cpu_get_cycle_count();
  const esp_cpu_cycle_count_t cycles = end - start;

  self->total_cycles += cycles;
  self->sample_count += 1;
}

void perf_counter_report(perf_counter_t *const self) {
  const double cycles_avg = (double)self->total_cycles / self->sample_count;
  const double time_ms = cycles_avg / self->cpu_frequency * 1e6;
  ESP_LOGI(
      TAG, "Performance counter %s: %.3f us = %.0f cycles (%d sampl.)",
      self->name, time_ms, cycles_avg, self->sample_count
  );
}
void perf_counter_reset(perf_counter_t *self) {
  self->total_cycles = 0;
  self->sample_count = 0;
}
