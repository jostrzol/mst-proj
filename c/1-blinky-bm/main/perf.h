#pragma once

#include "esp_cpu.h"
#include "esp_err.h"

#define CPU_FREQUENC

typedef struct {
  const char *name;
  uint32_t cpu_frequency;
  size_t capacity;
  size_t length;
  esp_cpu_cycle_count_t samples[];
} perf_counter_t;

typedef esp_cpu_cycle_count_t perf_mark_t;

esp_err_t
perf_counter_init(perf_counter_t **const self, const char *name, size_t length);
void perf_counter_deinit(perf_counter_t *self);

perf_mark_t perf_mark();
void perf_counter_add_sample(perf_counter_t *self, perf_mark_t start);

void perf_counter_report(perf_counter_t *const self);
void perf_counter_reset(perf_counter_t *self);
