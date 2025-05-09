#include <bits/time.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>

#include "perf.h"

uint64_t ns_from_timespec(const struct timespec *timespec) {
  return timespec->tv_nsec + timespec->tv_sec * 1000000000;
}

int perf_counter_init(perf_counter_t *self, const char *name) {
  int res;

  struct timespec resolution;
  res = clock_getres(CLOCK_THREAD_CPUTIME_ID, &resolution);
  if (res != 0) {
    return res;
  }

  printf(
      "Performance counter %s, cpu resolution: %ld s %ld ns\n", name,
      resolution.tv_sec, resolution.tv_nsec
  );

  *self = (perf_counter_t){
      .name = name,
      .total_time_ns = 0,
      .sample_count = 0,
  };

  return 0;
}

perf_mark_t perf_mark() {
  struct timespec mark;
  int res = clock_gettime(CLOCK_THREAD_CPUTIME_ID, &mark);
  if (res != 0)
    return 0;
  else
    return ns_from_timespec(&mark);
}
void perf_counter_add_sample(perf_counter_t *self, perf_mark_t start) {
  const perf_mark_t end = perf_mark();
  const uint64_t diff = end - start;

  self->total_time_ns += diff;
  self->sample_count += 1;
}

void perf_counter_report(perf_counter_t *const self) {
  const double time_us = (double)self->total_time_ns / 1e3 / self->sample_count;
  printf(
      "Performance counter %s: %.3f us (%d sampl.)\n", self->name, time_us,
      self->sample_count
  );
}
void perf_counter_reset(perf_counter_t *self) {
  self->total_time_ns = 0;
  self->sample_count = 0;
}
