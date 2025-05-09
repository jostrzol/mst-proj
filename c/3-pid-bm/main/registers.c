#include <math.h>

#include "registers.h"

void registers_init(registers_t *registers) {
  mb_set_float_cdab(&registers->input.frequency, 0);
  mb_set_float_cdab(&registers->input.control_signal, 0);

  mb_set_float_cdab(&registers->holding.target_frequency, 0);
  mb_set_float_cdab(&registers->holding.proportional_factor, 0);
  mb_set_float_cdab(&registers->holding.integration_time, INFINITY);
  mb_set_float_cdab(&registers->holding.differentiation_time, 0);
}
