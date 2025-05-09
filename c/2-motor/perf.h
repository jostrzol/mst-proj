#pragma once

#include <stddef.h>
#include <stdint.h>
#include <time.h>

typedef struct {
  const char *name;
  struct timespec total_time;
  size_t sample_count;
} perf_counter_t;

typedef struct timespec perf_mark_t;

int perf_counter_init(perf_counter_t *self, const char *name);

perf_mark_t perf_mark();
void perf_counter_add_sample(perf_counter_t *self, perf_mark_t start);

void perf_counter_report(perf_counter_t *const self);
void perf_counter_reset(perf_counter_t *self);
