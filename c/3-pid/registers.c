#include <math.h>

#include "registers.h"

modbus_mapping_t *registers_init() {
  modbus_mapping_t *self = modbus_mapping_new(
      // coils
      0, 0,
      // registers
      N_REG_HOLDING, N_REG_INPUT
  );
  if (self == NULL)
    return NULL;

  modbus_set_float_dcba(INFINITY, &self->tab_registers[INTEGRATION_TIME]);

  return self;
}

void registers_free(modbus_mapping_t *self) { modbus_mapping_free(self); }
