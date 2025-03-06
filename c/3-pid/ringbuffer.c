#include "ringbuffer.h"
#include <stdlib.h>
#include <string.h>

ringbuffer_t *ringbuffer_alloc(size_t length)
{
    const size_t array_size = sizeof(uint32_t) * length;
    ringbuffer_t *self = malloc(sizeof(ringbuffer_t) + array_size);

    self->length = length;
    self->tail = 0;
    memset(self->array, 0, array_size);
    return self;
}

uint32_t *ringbuffer_back(ringbuffer_t *self)
{
    return &self->array[self->tail];
}

void ringbuffer_push(ringbuffer_t *self, uint32_t value)
{
    self->array[++self->tail] = value;
}
