#pragma once

#include <stddef.h>
#include <stdint.h>
#include <time.h>

typedef struct {
  const char *name;
  size_t capacity;
  size_t length;
  uint32_t samples_ns[];
} perf_counter_t;

typedef uint64_t perf_mark_t;

int perf_counter_init(
    perf_counter_t **const self, const char *name, size_t length
);
void perf_counter_deinit(perf_counter_t *self);

perf_mark_t perf_mark();
void perf_counter_add_sample(perf_counter_t *self, perf_mark_t start);

void perf_counter_report(perf_counter_t *const self);
void perf_counter_reset(perf_counter_t *self);
