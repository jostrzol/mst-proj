#include "ringbuffer.h"
#include "esp_err.h"
#include "esp_log.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const char *TAG = "ringbuffer";

esp_err_t ringbuffer_init(ringbuffer_t **const self, size_t length) {
  const size_t array_size = sizeof(uint32_t) * length;
  ringbuffer_t *me = malloc(sizeof(ringbuffer_t) + array_size);
  if (me == NULL) {
    ESP_LOGE(TAG, "malloc fail");
    return ESP_ERR_INVALID_STATE;
  }

  me->length = length;
  me->tail = 0;
  memset(me->array, 0, array_size);

  *self = me;
  return ESP_OK;
}
void ringbuffer_deinit(ringbuffer_t *self) { free(self); }

uint32_t *ringbuffer_back(ringbuffer_t *self) {
  return &self->array[self->tail];
}

void ringbuffer_push(ringbuffer_t *self, uint32_t value) {
  self->tail = (self->tail + 1) % self->length;
  self->array[self->tail] = value;
}
