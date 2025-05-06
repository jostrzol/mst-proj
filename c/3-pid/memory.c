#include <malloc.h>
#include <stdio.h>

#include "memory.h"

size_t heap_usage = 0;

void memory_report() { printf("Heap usage: %d B\n", heap_usage); }

extern void *__libc_malloc(size_t size);
extern void *__libc_calloc(size_t count, size_t size);
extern void *__libc_realloc(void *ptr, size_t size);
extern void __libc_free(void *ptr);

int malloc_hook_active = 0;

void *malloc(size_t size) {
  void *const ptr = __libc_malloc(size);
  heap_usage += malloc_usable_size(ptr);
  return ptr;
}

void *calloc(size_t count, size_t size) {
  void *const ptr = __libc_calloc(count, size);
  heap_usage += malloc_usable_size(ptr);
  return ptr;
}

void *realloc(void *ptr, size_t size) {
  const size_t old_size = malloc_usable_size(ptr);
  void *const new_ptr = __libc_realloc(ptr, size);
  heap_usage += malloc_usable_size(new_ptr) - old_size;
  return new_ptr;
}

void free(void *ptr) {
  heap_usage -= malloc_usable_size(ptr);
  __libc_free(ptr);
}
