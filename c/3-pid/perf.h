#pragma once

#include <stddef.h>
#include <stdint.h>
#include <time.h>

typedef struct {
  const char *name;
  uint64_t total_time_ns;
  size_t sample_count;
} perf_counter_t;

typedef uint64_t perf_mark_t;

int perf_counter_init(perf_counter_t *self, const char *name);

perf_mark_t perf_mark();
void perf_counter_add_sample(perf_counter_t *self, perf_mark_t start);

void perf_counter_report(perf_counter_t *const self);
void perf_counter_reset(perf_counter_t *self);
