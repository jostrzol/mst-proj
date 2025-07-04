#include <bits/time.h>
#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "perf.h"

uint64_t ns_from_timespec(const struct timespec *timespec) {
  return timespec->tv_nsec + timespec->tv_sec * 1000000000;
}

int perf_counter_init(
    perf_counter_t **const self, const char *name, size_t length
) {
  int res;

  struct timespec resolution;
  res = clock_getres(CLOCK_THREAD_CPUTIME_ID, &resolution);
  if (res != 0) {
    fprintf(stderr, "clock_getres fail (%d): %s\n", res, strerror(errno));
    return -1;
  }

  printf(
      "Performance counter %s, cpu resolution: %llu ns\n", name,
      ns_from_timespec(&resolution)
  );

  const size_t array_size = sizeof(uint32_t) * length;
  perf_counter_t *me = malloc(sizeof(perf_counter_t) + array_size);
  if (me == NULL) {
    fprintf(stderr, "malloc fail (%d): %s\n", errno, strerror(errno));
    return -1;
  }

  *me = (perf_counter_t){
      .name = name,
      .capacity = length,
      .length = 0,
  };

  *self = me;

  return 0;
}
void perf_counter_deinit(perf_counter_t *self) { free(self); }

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

  if (self->length >= self->capacity) {
    fprintf(stderr, "perf_counter_add_sample: buffer is full");
    return;
  }

  self->samples_ns[self->length] = diff;
  self->length += 1;
}

void perf_counter_report(perf_counter_t *const self) {
  printf("Performance counter %s: [", self->name);
  for (size_t i = 0; i < self->length; ++i) {
    printf("%u", self->samples_ns[i] / 1000);
    if (i < self->length - 1)
      printf(",");
  }
  printf("] us\n");
}
void perf_counter_reset(perf_counter_t *self) { self->length = 0; }
