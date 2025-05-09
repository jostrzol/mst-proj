#pragma once

#include <stddef.h>
#include <stdint.h>

typedef struct {
  size_t length;
  size_t tail;
  uint32_t array[];
} ringbuffer_t;

int ringbuffer_init(ringbuffer_t **const self, size_t length);
void ringbuffer_deinit(ringbuffer_t *self);

uint32_t *ringbuffer_back(ringbuffer_t *self);

void ringbuffer_push(ringbuffer_t *self, uint32_t value);
