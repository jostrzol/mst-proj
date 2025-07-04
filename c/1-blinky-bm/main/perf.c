#include <inttypes.h>
#include <string.h>

#include "esp_clk_tree.h"
#include "esp_log.h"
#include "soc/clk_tree_defs.h"

#include "perf.h"

static const char *TAG = "perf";

esp_err_t perf_counter_init(
    perf_counter_t **const self, const char *name, size_t length
) {
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

  const size_t array_size = sizeof(uint32_t) * length;
  perf_counter_t *me = malloc(sizeof(perf_counter_t) + array_size);
  if (me == NULL) {
    ESP_LOGE(TAG, "malloc fail");
    return ESP_ERR_NO_MEM;
  }

  *me = (perf_counter_t){
      .name = name,
      .cpu_frequency = cpu_frequency,
      .capacity = length,
      .length = 0,
  };

  *self = me;

  return ESP_OK;
}
void perf_counter_deinit(perf_counter_t *self) { free(self); }

perf_mark_t perf_mark() { return esp_cpu_get_cycle_count(); }

void perf_counter_add_sample(perf_counter_t *self, perf_mark_t start) {
  const esp_cpu_cycle_count_t end = esp_cpu_get_cycle_count();
  const esp_cpu_cycle_count_t diff = end - start;

  if (self->length >= self->capacity) {
    fprintf(stderr, "perf_counter_add_sample: buffer is full\n");
    return;
  }

  self->samples[self->length] = diff;
  self->length += 1;
}

void perf_counter_report(perf_counter_t *const self) {
  printf("Performance counter %s: [", self->name);
  for (size_t i = 0; i < self->length; ++i) {
    const float time_us = (float)self->samples[i] * 1e6 / self->cpu_frequency;
    printf("%.2f", time_us);
    if (i < self->length - 1)
      printf(",");
  }
  printf("] us\n");
}
void perf_counter_reset(perf_counter_t *self) { self->length = 0; }
