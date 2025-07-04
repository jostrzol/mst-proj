#include <errno.h>
#include <math.h>
#include <stdio.h>

#include "registers.h"

modbus_mapping_t *registers_init() {
  modbus_mapping_t *self = modbus_mapping_new(
      // coils
      0, 0,
      // registers
      REG_HOLDING_SIZE_PER_U16, REG_INPUT_SIZE_PER_U16
  );
  if (self == NULL) {
    fprintf(stderr, "modbus_mapping_new fail: %s", modbus_strerror(errno));
    return NULL;
  }

  modbus_set_float_badc(INFINITY, &self->tab_registers[REG_INTEGRATION_TIME]);

  return self;
}

void registers_free(modbus_mapping_t *self) { modbus_mapping_free(self); }
