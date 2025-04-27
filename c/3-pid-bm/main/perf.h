#pragma once

#include "esp_cpu.h"
#include "esp_err.h"

#define CPU_FREQUENC

typedef struct {
  const char *name;
  uint32_t cpu_frequency;
  esp_cpu_cycle_count_t total_cycles;
  size_t sample_count;
} perf_counter_t;

typedef esp_cpu_cycle_count_t perf_start_mark_t;

esp_err_t perf_counter_init(perf_counter_t *self, const char *name);

perf_start_mark_t perf_counter_mark_start();
void perf_counter_add_sample(perf_counter_t *self, perf_start_mark_t start);

void perf_counter_report(perf_counter_t *const self);
void perf_counter_reset(perf_counter_t *self);
