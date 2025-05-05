#include <malloc.h>
#include <stdio.h>

#include "memory.h"

size_t heap_usage = 0;

void memory_report() { printf("Heap usage: %d\n", heap_usage); }

extern void *__libc_malloc(size_t size);
extern void *__libc_calloc(size_t count, size_t size);
extern void *__libc_realloc(void *ptr, size_t size);
extern void *__libc_free(void *ptr);

int malloc_hook_active = 0;

void *malloc(size_t size) {
  heap_usage += size;
  return __libc_malloc(size);
}

void *calloc(size_t count, size_t size) {
  heap_usage += count * size;
  return __libc_calloc(count, size);
}

void *realloc(void *ptr, size_t size) {
  heap_usage += size - sizeof(ptr);
  return __libc_realloc(ptr, size);
}

void free(void *ptr) {
  heap_usage -= sizeof(ptr);
  __libc_free(ptr);
}
