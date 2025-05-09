#include <bits/time.h>
#include <inttypes.h>
#include <stdio.h>
#include <time.h>

#include "perf.h"

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
      .total_time = {.tv_sec = 0, .tv_nsec = 0},
      .sample_count = 0,
  };

  return 0;
}

perf_mark_t perf_mark() {
  struct timespec mark;
  int res = clock_gettime(CLOCK_THREAD_CPUTIME_ID, &mark);
  if (res != 0)
    return (struct timespec){.tv_sec = 0, .tv_nsec = 0};
  else
    return mark;
}
void perf_counter_add_sample(perf_counter_t *self, perf_mark_t start) {
  const perf_mark_t end = perf_mark();
  const struct timespec diff = {
      .tv_sec = end.tv_sec - start.tv_sec,
      .tv_nsec = end.tv_nsec - start.tv_nsec,
  };

  self->total_time = (struct timespec){
      .tv_sec = self->total_time.tv_sec + diff.tv_sec,
      .tv_nsec = self->total_time.tv_nsec + diff.tv_nsec,
  };
  self->sample_count += 1;
}

void perf_counter_report(perf_counter_t *const self) {
  const double time_us =
      ((double)self->total_time.tv_nsec / 1e3 + self->total_time.tv_sec * 1e6) /
      self->sample_count;
  printf(
      "Performance counter %s: %.3f us (%d sampl.)\n", self->name, time_us,
      self->sample_count
  );
}
void perf_counter_reset(perf_counter_t *self) {
  self->total_time = (struct timespec){.tv_sec = 0, .tv_nsec = 0};
  self->sample_count = 0;
}
