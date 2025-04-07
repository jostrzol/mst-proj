#include <math.h>

#include "registers.h"

void regs_init(regs_t *regs) {
  mb_set_float_cdab(&regs->input.frequency, 0);
  mb_set_float_cdab(&regs->input.control_signal, 0);

  mb_set_float_cdab(&regs->holding.target_frequency, 0);
  mb_set_float_cdab(&regs->holding.proportional_factor, 0);
  mb_set_float_cdab(&regs->holding.integration_time, INFINITY);
  mb_set_float_cdab(&regs->holding.differentiation_time, 0);
}
